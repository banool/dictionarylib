import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math' show max;

import 'package:dolphinsr/dolphinsr.dart' show Review;
import 'package:flutter/foundation.dart';

import '../analytics.dart';
import '../common.dart';
import '../entry_list.dart';
import '../flashcards_logic.dart'
    show KEY_FIRST_RANDOM_REVIEW, KEY_RANDOM_REVIEWS_COUNTER;
import '../revision_history.dart';
import '../globals.dart';
import '../l10n/app_localizations.dart';
import '../list_storage.dart';
import '../lists_service.dart';
import '../saved_video.dart';
import '../tv_focus.dart';
import 'account_sync_api.dart';
import 'account_sync_state.dart';
import 'auth/auth_service.dart';
import 'auth/auth_store.dart';
import 'list_id.dart';
import 'sync_api.dart';
import 'sync_engine.dart';
import 'synced_entry_list.dart';
import 'synced_settings.dart';
import 'sync_clock.dart';

/// Why a cycle was asked for (section 5.2 of the plan).
enum SyncReason {
  /// A few seconds after the first frame.
  startup,

  /// The app came back to the foreground.
  resumed,

  /// Something changed on the device (debounced 2 s).
  localChange,

  /// The person pulled to refresh: immediate, ignores backoff and pauses.
  pullToRefresh,

  /// A sign-in just completed: immediate.
  signedIn,

  /// The app is going to the background: flush what's queued, best-effort.
  paused,
}

/// One-shot events for the UI (snackbars), from [AccountSyncController.notices].
sealed class AccountSyncNotice {
  const AccountSyncNotice();
}

/// The sign-in merge finished: "Your lists and progress are now syncing."
class MergeCompletedNotice extends AccountSyncNotice {
  const MergeCompletedNotice();
}

/// What the Settings status line shows.
enum AccountSyncStatus {
  signedOut,
  syncing,
  synced,
  waitingForConnection,
  paused,
}

/// The canonical user id (`provider:sub`) of [session]: the stored one, or
/// for sessions saved before the field existed, the JWT's `sub`.
String sessionUserId(AuthSession session) {
  if (session.userId.isNotEmpty) return session.userId;
  try {
    final parts = session.sessionToken.split('.');
    if (parts.length != 3) return '';
    final payload = utf8.decode(
      base64Url.decode(base64Url.normalize(parts[1])),
    );
    final sub = (jsonDecode(payload) as Map<String, dynamic>)['sub'];
    return sub is String ? sub : '';
  } catch (_) {
    return '';
  }
}

/// Lowercased, trimmed, runs of whitespace collapsed: how two list names
/// are compared for the sign-in merge. Mirrors the worker's `normalizeName`.
String normalizeListName(String name) =>
    name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

/// The name a local list goes by when it is matched or created on the
/// account: its key with underscores as spaces.
String localListName(String localKey) => EntryList.getNameFromKey(localKey);

/// Prefs key the `enable_account_sync` knob is cached under by [readKnob].
const String KEY_ACCOUNT_SYNC_KNOB = 'knob_enable_account_sync';

/// Most `addEntries` bytes in one op, so a few of them still fit a request.
const int _maxAddEntriesOpBytes = 40 * 1024;

/// Most account ops in one request (the server's cap).
const int _maxAccountOpsPerRequest = 50;

/// Pages of answers fetched per cycle before giving the lists a turn.
const int _maxPagesPerCycle = 50;

/// `sinceSeq` for a request that wants no answers back (the merge's and the
/// links' calls): beyond any account's seq, so the page is empty.
const int _noAnswers = 9007199254740991;

/// Account sync (section 5 of the plan): keeps every list a signed-in person
/// owns, the lists they follow and edit, and (Phase 3) their flashcard
/// progress the same on every device they sign in on.
///
/// One instance, owned by [Sharing]. Everything that changes which lists the
/// device has runs under one lock: the sign-in merge, the reconciliation
/// after each account round trip, and the list operations in
/// [ListsService] (create, delete, rename of a list being linked, share).
/// Cycles are strictly sequential; a [kick] while one runs asks for another.
///
/// The device's state for the account is one prefs blob
/// ([AccountSyncState]), held in memory here and written whole after every
/// step, so a killed app resumes exactly where it was. Lists themselves keep
/// syncing through the [SyncEngine] as before: a linked list is an
/// owner-mode [SyncedEntryList], private or shared.
class AccountSyncController {
  final SyncApi _api;
  final AuthService _auth;
  final SyncEngine _engine;
  final SyncedEntryListManager _lists;

  /// Non-null only for a real app run: [kick] does nothing for the disabled
  /// sentinel.
  final bool _enabled;

  final AsyncLock _lock = AsyncLock();
  Future<void>? _inflight;
  bool _again = false;
  bool _againIsPullToRefresh = false;
  Timer? _debounce;
  Timer? _retryTimer;
  int _backoffSeconds = 0;
  int _waiters = 0;
  bool _syncing = false;

  /// Set when a link installs a wrapper with ops to send.
  bool _linkedThisCycle = false;

  AccountSyncState? _st;
  bool _stLoaded = false;

  final StreamController<AccountSyncNotice> _notices =
      StreamController<AccountSyncNotice>.broadcast(sync: true);

  /// Snackbar-worthy events. See [AccountSyncNotice].
  Stream<AccountSyncNotice> get notices => _notices.stream;

  AccountSyncController({
    required this._api,
    required this._auth,
    required this._engine,
    required this._lists,
    this._enabled = true,
  }) {
    if (_enabled) {
      _engine.onOwnedListGone = _onOwnedListGone;
      _engine.onFollowed = _onFollowed;
      _engine.onUnfollowed = _onUnfollowed;
    }
  }

  void dispose() {
    _debounce?.cancel();
    _retryTimer?.cancel();
    _notices.close();
  }

  // -------- State --------

  AccountSyncState? get _state {
    if (!_stLoaded) {
      _st = AccountSyncState.load();
      _stLoaded = true;
    }
    return _st;
  }

  Future<void> _save() async {
    final st = _st;
    if (st == null) return;
    await st.save();
  }

  /// Read-only view of the stored state, for the UI and tests.
  AccountSyncState? get state => _state;

  int _now() => syncNowSecs();

  /// Account sync can run on this device at all: the app wired sharing, it
  /// isn't the web or a TV, and the knob is on.
  bool get supported =>
      _enabled &&
      sharing.isEnabled &&
      !kIsWeb &&
      !isAndroidTv &&
      (sharedPreferences.getBool(KEY_ACCOUNT_SYNC_KNOB) ?? true);

  /// Account sync is on for the signed-in account and its merge is done:
  /// lists are linked and steady-state rules apply (a list deleted elsewhere
  /// is deleted here, deletes go everywhere).
  bool get isActive {
    if (!supported) return false;
    final session = _auth.store.current;
    final st = _state;
    return session != null &&
        st != null &&
        st.userId == sessionUserId(session) &&
        st.mergeDone;
  }

  /// This device holds account-sync state for the signed-in account (the
  /// merge has at least started), so its owner wrappers are account links:
  /// deleting one deletes the list everywhere. False before account sync
  /// has ever run here, when an owner wrapper is a share made the old way.
  bool get ownsLinks {
    final session = _auth.store.current;
    final st = _state;
    return session != null && st != null && st.userId == sessionUserId(session);
  }

  /// Account ops can be queued for the account this device's state belongs
  /// to: there is a state, it isn't being cleared, and no other account is
  /// signed in. Also true while the session has expired (the ops wait for
  /// the same account to sign in again; another account's sign-in clears
  /// them) and while the knob has account sync switched off, so nothing
  /// done meanwhile is lost to the account.
  bool get queuesForAccount {
    final st = _state;
    if (st == null || st.clearing) return false;
    final session = _auth.store.current;
    return session == null || st.userId == sessionUserId(session);
  }

  /// A signed-in device where account sync may run: list creation records
  /// a link to make, and so on, even before the merge has finished.
  bool get isSignedInAndSupported => supported && _auth.store.current != null;

  bool get isSyncing => _syncing;

  AccountSyncStatus get status {
    if (!supported || _auth.store.current == null) {
      return AccountSyncStatus.signedOut;
    }
    if (_syncing) return AccountSyncStatus.syncing;
    final st = _state;
    final paused = st?.pausedUntil;
    if (paused != null && paused > _now()) return AccountSyncStatus.paused;
    final err = st?.lastErrorKind;
    if (err == SyncErrorKind.network.name || err == SyncErrorKind.server.name) {
      return AccountSyncStatus.waitingForConnection;
    }
    return AccountSyncStatus.synced;
  }

  /// Unix seconds of the last complete cycle, if any.
  int? get lastSyncAt => _state?.lastSyncAt;

  /// The random-mode total from the account (Phase 3 adds pending ones).
  int get accountRandomTotal => _state?.randomTotal ?? 0;

  /// Why [localKey] doesn't sync, if it doesn't.
  String? unsyncableReason(String localKey) => _state?.unsyncable[localKey];

  /// True while [localKey] is being linked to the account.
  bool isLinking(String localKey) =>
      _state?.linking.containsKey(localKey) ?? false;

  // -------- Kicks and cycles --------

  /// Ask for a cycle. Returns when it (or the cycle it was folded into) has
  /// finished; callers that don't care needn't await it.
  Future<void> kick(SyncReason reason) {
    if (!supported) return Future.value();
    if (reason == SyncReason.localChange) {
      _debounce?.cancel();
      final completer = Completer<void>();
      _debounce = Timer(const Duration(seconds: 2), () {
        _request(SyncReason.localChange).whenComplete(completer.complete);
      });
      return completer.future;
    }
    return _request(reason);
  }

  Future<void> _request(SyncReason reason) {
    final inflight = _inflight;
    if (inflight != null) {
      _again = true;
      if (reason == SyncReason.pullToRefresh) _againIsPullToRefresh = true;
      return inflight;
    }
    final f = _loop(reason);
    _inflight = f;
    f.whenComplete(() => _inflight = null);
    return f;
  }

  Future<void> _loop(SyncReason first) async {
    var reason = first;
    while (true) {
      _again = false;
      _againIsPullToRefresh = false;
      await _lock.synchronized(() => _cycle(reason));
      if (!_again) return;
      reason = _againIsPullToRefresh
          ? SyncReason.pullToRefresh
          : SyncReason.localChange;
    }
  }

  /// Run [body] under the controller's lock, after any cycle in progress
  /// has reached a point where it can stop (cycles check between steps).
  /// For the list operations that change which lists the device has.
  Future<T> exclusive<T>(Future<T> Function() body) async {
    _waiters++;
    try {
      return await _lock.synchronized(body);
    } finally {
      _waiters--;
    }
  }

  /// A list operation is waiting: stop the cycle at the next step and run
  /// again afterwards.
  bool get _shouldYield => _waiters > 0;

  Future<void> _cycle(SyncReason reason) async {
    if (!supported) return;
    final session = _auth.store.current;
    if (session == null) return;
    final uid = sessionUserId(session);
    if (uid.isEmpty) return;

    if (reason == SyncReason.paused) {
      // Best-effort flush only; the OS gives us little time.
      await _flushAccountOps(session);
      return;
    }
    final paused = _state?.pausedUntil;
    if (reason != SyncReason.pullToRefresh &&
        paused != null &&
        paused > _now()) {
      return;
    }

    _syncing = true;
    sharing.bumpState();
    try {
      var st = _state;
      if (st != null && (st.userId != uid || st.clearing)) {
        // Another account, or a sign-out killed part way (finished here;
        // the session it would have removed is still here, so the merge
        // runs again and links the lists back by name).
        await _clearLinksLocally();
        st = null;
      }
      if (st == null) {
        // M0.
        st = AccountSyncState(userId: uid);
        _st = st;
        _stLoaded = true;
        await _save();
      }
      if (!st.mergeDone) {
        final finished = await _runMerge(session);
        if (!finished) {
          _again = true;
          return;
        }
      }
      if (_shouldYield) {
        _again = true;
        return;
      }
      // Lists first, through the engine (its own per-list locks).
      await _engine.syncAll();
      if (_shouldYield) {
        _again = true;
        return;
      }
      await _accountRoundTrip(session);
      if (_shouldYield) {
        _again = true;
        return;
      }
      _linkedThisCycle = false;
      await _linkLocalLists(session, merging: false);
      if (_linkedThisCycle) await _engine.syncAll();
      await _afterCycle();
      final cur = _st;
      if (cur != null) {
        cur.lastSyncAt = _now();
        cur.lastErrorKind = null;
        cur.pausedUntil = null;
        await _save();
      }
      _backoffSeconds = 0;
    } on SyncException catch (e) {
      await _handleFailure(e);
    } catch (e, stack) {
      // A bug, not the network: log it and try again much later, rather
      // than let it escape as an unhandled error or spin.
      printAndLog('AccountSync: cycle failed: $e\n$stack');
      Analytics.track('sync_failed', props: {'kind': 'client'});
      _scheduleRetry(3600);
    } finally {
      _syncing = false;
      sharing.bumpState();
    }
  }

  /// Most answer batches uploaded per cycle (each its own request); the
  /// rest go on the next.
  static const int _maxReviewBatchesPerCycle = 40;

  /// Step 6 of a cycle: send the unsent answers.
  Future<void> _afterCycle() async {
    final session = _auth.store.current;
    if (session == null) return;
    if (await _uploadAnswers(session, yieldable: true)) _again = true;
  }

  /// Acknowledged batches taken off the queue at once (each removal
  /// rewrites the queue, and on Android the whole prefs file). A kill
  /// before that sends those batches again, which the account finds to be
  /// duplicates.
  static const int _batchesPerQueueWrite = 10;

  /// Send unsent answers in batches of up to 500 (and ~40 KB), each an
  /// `addReviews` op whose id comes from its lines; a batch leaves the
  /// queue only once the account has it (applied or duplicate). At most
  /// [_maxReviewBatchesPerCycle] requests; returns true if answers are left
  /// to send (or it stopped for a list operation, when [yieldable]).
  Future<bool> _uploadAnswers(
    AuthSession session, {
    required bool yieldable,
  }) async {
    final done = <String>[];
    var sent = 0;
    Future<void> commit() async {
      if (done.isEmpty) return;
      await reviewHistory.removeUploaded(List.of(done));
      done.clear();
      sent = 0;
    }

    try {
      for (var i = 0; i < _maxReviewBatchesPerCycle; i++) {
        if (yieldable && _shouldYield) return true;
        final batch = reviewHistory.nextUploadBatch(skip: done.length);
        if (batch == null) return false;
        if (batch.wire.isNotEmpty) {
          final op = AccountOp(
            opId: batch.opId,
            type: 'addReviews',
            args: {'reviews': batch.wire},
          );
          final resp = await _send(session, [op], sinceSeq: _noAnswers);
          final out = resp.outcomeFor(op.opId);
          if (out == null || out.shouldRetry) return false;
          if (!out.isDone) {
            printAndLog(
              'AccountSync: answers refused (${out.reasonCode}); '
              'dropping the batch',
            );
          }
        }
        // (A batch none of which could be read can never be accepted: it
        // leaves the queue unsent.)
        done.addAll(batch.lines);
        if (++sent >= _batchesPerQueueWrite) await commit();
      }
      return reviewHistory.nextUploadBatch(skip: done.length) != null;
    } finally {
      await commit();
    }
  }

  /// Answers waiting to go up (for the UI).
  int get unsentAnswerCount => reviewHistory.unsentCount;

  /// Store a revision session's [answers] on this device and, when account
  /// sync runs for the signed-in account, queue them for it and start a
  /// cycle to send them.
  Future<void> recordAnswers(List<Review> answers) async {
    final queue = queuesForAccount;
    await reviewHistory.appendLocal(answers, queueForUpload: queue);
    if (queue && answers.isNotEmpty) {
      unawaited(kick(SyncReason.localChange));
    }
  }

  /// Whether a random-mode session ending now goes to the account as an op
  /// of its own ([recordRandomSession]): once the merge is done. Before
  /// that it is only in the device's counter, which the merge sends as one
  /// session. Read and act on it without an await in between (see
  /// `bumpRandomReviewCounter`).
  bool get takesRandomSessions =>
      queuesForAccount && (_state?.mergeDone ?? false);

  /// Record [count] random-mode cards as one session: an op with a fresh
  /// id, so the account adds it once. Only when [takesRandomSessions].
  Future<void> recordRandomSession(int count) async {
    if (count <= 0 || !takesRandomSessions) return;
    await enqueue(
      AccountOp(
        opId: generateOpId(),
        type: 'randomSession',
        args: {
          'count': count.clamp(1, _maxRandomSessionCount),
          'tsUs': DateTime.now().microsecondsSinceEpoch,
        },
      ),
    );
    unawaited(kick(SyncReason.localChange));
  }

  /// Random-mode cards counted on the account, plus those still on their
  /// way there (the progress page, signed in).
  int get randomTotalWithPending {
    final st = _state;
    if (st == null) return 0;
    var total = st.randomTotal;
    for (final op in st.pendingOps) {
      if (op.type == 'randomSession') total += (op.args['count'] as int?) ?? 0;
    }
    return total;
  }

  /// Revision progress is being deleted on this device at [tsUs]: tell the
  /// account, which drops every answer and random session from before it,
  /// everywhere. The device's own reset is the caller's; the account's
  /// answer resets this device again ([_applyRevisionPage]), which drops
  /// nothing more and covers a kill before the caller got to it.
  Future<void> recordReset(int tsUs) async {
    final st = _state;
    if (st == null || !queuesForAccount) return;
    st.pendingOps.removeWhere((o) => o.type == 'randomSession');
    st.pendingOps.add(
      AccountOp(
        opId: generateOpId(),
        type: 'resetProgress',
        args: {'tsUs': tsUs},
      ),
    );
    await _save();
    unawaited(kick(SyncReason.localChange));
  }

  Future<void> _handleFailure(SyncException e) async {
    printAndLog('AccountSync: cycle ended: $e');
    Analytics.track('sync_failed', props: {'kind': e.kind.name});
    final st = _st;
    st?.lastErrorKind = e.kind.name;
    switch (e.kind) {
      case SyncErrorKind.unauthorized:
        // As the engine does: drop the session, keep every bit of state,
        // so signing in again as the same account carries on.
        await _auth.dropSessionLocally();
        _engine.emit(SyncNotification.sessionExpired);
      case SyncErrorKind.rateLimited:
      case SyncErrorKind.unavailable:
        final wait =
            e.retryAfterSeconds ??
            (e.kind == SyncErrorKind.unavailable ? 3600 : 60);
        st?.pausedUntil = _now() + wait;
        _scheduleRetry(wait);
      case SyncErrorKind.network:
      case SyncErrorKind.server:
        _backoffSeconds = _backoffSeconds == 0
            ? 2
            : (_backoffSeconds * 2).clamp(2, 3600);
        _scheduleRetry(_backoffSeconds);
      default:
        // Anything else is a client bug; try again much later rather than
        // spin.
        _scheduleRetry(3600);
    }
    await _save();
  }

  void _scheduleRetry(int seconds) {
    _retryTimer?.cancel();
    _retryTimer = Timer(Duration(seconds: seconds), () {
      unawaited(kick(SyncReason.resumed));
    });
  }

  // -------- The sign-in merge (section 5.4) --------

  /// Run the merge from its saved phase. Returns false if it stopped early
  /// (a list operation is waiting, or a create must be retried later).
  Future<bool> _runMerge(AuthSession session) async {
    final st = _st!;
    // M1: the directory. Re-fetched on resume, which is harmless.
    final dir = await _send(session, const [], sinceSeq: _noAnswers);
    st.follows = dir.follows;
    _mergeSettings = dir.settings;
    _mergeResetTsUs = dir.resetTsUs;
    if (st.mergePhase == MergePhase.directory) {
      st.mergePhase = MergePhase.lists;
      await _save();
    }
    if (_incarnationChanged(dir)) {
      // A merge in progress against an account that has since been deleted:
      // start again against the new one.
      await _clearLinksLocally();
      _st = AccountSyncState(userId: st.userId, incarnation: dir.incarnation);
      await _save();
      return false;
    }
    final cur = _st!;
    if (cur.mergePhase == MergePhase.lists) {
      // M2 and M3: the device's lists, the default first.
      if (!await _linkLocalLists(session, merging: true)) return false;
      if (_shouldYield) return false;
      // M4: the account's other lists.
      await _installAccountLists(session);
      if (_shouldYield) return false;
      await _sendMergeReorder(session);
      cur.mergePhase = MergePhase.follows;
      await _save();
    }
    if (cur.mergePhase == MergePhase.follows) {
      await _mergeFollows(session);
      await _installEditorLists(session);
      cur.mergePhase = MergePhase.history;
      await _save();
    }
    if (cur.mergePhase == MergePhase.history) {
      await _mergeHistory(session);
      cur.mergePhase = MergePhase.done;
      await _save();
      _notices.add(const MergeCompletedNotice());
      Analytics.track(
        'sync_merge_completed',
        props: {
          'lists_bucket': Analytics.bucket(_lists.ownedLists.length),
          'answers_bucket': Analytics.bucket(_storedAnswerCount()),
        },
      );
    }
    return true;
  }

  /// M6: the device's flashcard history goes up (all of it; answers already
  /// on the account are duplicates there), its random-mode count goes up as
  /// one session keyed by this install (so signing out and in again here
  /// never counts it twice), and the synced revision settings meet: the
  /// account's values win, and the device's go up where the account has
  /// none (the next round trip's change detection sends them).
  Future<void> _mergeHistory(AuthSession session) async {
    final st = _st!;
    await reviewHistory.queueEverythingForUpload();
    // From here to the save nothing awaits, so a random-mode session can't
    // end in between: until the merge is done one goes into the counter
    // read here, afterwards it is an op of its own ([recordRandomSession]).
    final counter = sharedPreferences.getInt(KEY_RANDOM_REVIEWS_COUNTER) ?? 0;
    final first = sharedPreferences.getInt(KEY_FIRST_RANDOM_REVIEW);
    // In pieces of at most the account's per-session cap, each with an id
    // of its own that is the same every time this install merges.
    var left = counter;
    for (var part = 0; left > 0; part++) {
      final count = left < _maxRandomSessionCount
          ? left
          : _maxRandomSessionCount;
      left -= count;
      _enqueue(
        AccountOp(
          opId:
              'random-initial-${getOrCreateClientId()}'
              '${part == 0 ? '' : '-$part'}',
          type: 'randomSession',
          args: {
            'count': count,
            'tsUs': first != null
                ? first * 1000000
                : DateTime.now().microsecondsSinceEpoch,
          },
        ),
      );
    }
    applyIncomingSettings(st, _mergeSettings, const {}, accountWins: true);
    // A reset made on the account before this device joined it isn't
    // applied here: it was never about this device's answers, and the
    // account already refuses the ones from before it (they stay on this
    // device only). Later resets apply as usual.
    if (_mergeResetTsUs > st.lastResetTsUs) st.lastResetTsUs = _mergeResetTsUs;
    st.mergePhase = MergePhase.done;
    await _save();
  }

  int _storedAnswerCount() => reviewHistory.storedCount;

  /// Most cards one `randomSession` op may count (`MAX_RANDOM_SESSION_COUNT`
  /// in the worker).
  static const int _maxRandomSessionCount = 10000;

  /// The account's settings and reset time as M1 read them (re-read on
  /// resume).
  List<SettingValue> _mergeSettings = const [];
  int _mergeResetTsUs = 0;

  bool _incarnationChanged(AccountSyncResponse resp) {
    final st = _st;
    if (st == null || resp.incarnation.isEmpty) return false;
    if (st.incarnation.isEmpty) {
      st.incarnation = resp.incarnation;
      return false;
    }
    return st.incarnation != resp.incarnation;
  }

  /// One account request with [ops]; keeps the cached directory, follows
  /// and editor lists current. Answers and paging are the caller's.
  Future<AccountSyncResponse> _send(
    AuthSession session,
    List<AccountOp> ops, {
    int? sinceSeq,
  }) async {
    final st = _st!;
    final resp = await _api.accountSync(
      clientId: getOrCreateClientId(),
      sinceSeq: sinceSeq ?? st.sinceSeq,
      ops: ops,
      sessionToken: session.sessionToken,
    );
    st.directory = resp.directory;
    st.editorListIds = resp.editorListIds;
    st.randomTotal = resp.randomTotal;
    return resp;
  }

  // -------- Linking local lists (M2, M3, and every cycle after) --------

  /// Local keys of lists linked on this device, by server list id.
  Map<String, String> _linkedKeysById() => {
    for (final w in _lists.ownedLists)
      if (w.meta.sourceLocalKey != null) w.listId: w.meta.sourceLocalKey!,
  };

  /// Link every local list that isn't linked, linking or unsyncable: the
  /// default list first, then the rest in display order. With [merging]
  /// (the sign-in merge) a list is matched by name against the account's
  /// lists; afterwards too, so a list whose link was lost (its metadata
  /// unreadable at start-up) finds its way back rather than duplicating.
  /// Returns false if it stopped early.
  Future<bool> _linkLocalLists(
    AuthSession session, {
    required bool merging,
  }) async {
    final st = _st!;
    // Drop records whose list has gone (deleted while linking, the app
    // killed before the record went: the account's copy is deleted too, as
    // the delete would have done) or that a finished link left behind
    // (killed before the record was removed).
    for (final key in st.linking.keys.toList()) {
      final rec = st.linking[key]!;
      final exists = userEntryListManager.getEntryLists().containsKey(key);
      if (rec.step != LinkStep.install && !exists) {
        st.linking.remove(key);
        _queueDeleteFor(rec);
      } else if (_lists.ownerForSourceKey(key) != null) {
        st.linking.remove(key);
      }
    }
    // Lists kept on this device for a reason that may have passed: too
    // many signs (some removed since), or the account full (lists deleted
    // since). They are tried again.
    final liveOnAccount = st.directory.where((d) => d.isLive).length;
    for (final key in st.unsyncable.keys.toList()) {
      final list = userEntryListManager.getEntryLists()[key];
      final reason = st.unsyncable[key];
      if (list == null ||
          (reason == UnsyncableReason.tooLarge &&
              list.savedVideos.length <= maxEntriesPerPrivateList) ||
          (reason == UnsyncableReason.listLimit &&
              liveOnAccount < maxListsPerAccount)) {
        st.unsyncable.remove(key);
      }
    }
    await _save();

    final defaultKey = readDefaultListKey();
    final keys = userEntryListManager.getEntryLists().keys.toList();
    if (defaultKey != null && keys.remove(defaultKey)) {
      keys.insert(0, defaultKey);
    }
    // Finish installs first: their local lists exist only for this.
    for (final key in st.linking.keys.toList()) {
      final rec = st.linking[key];
      if (rec != null && rec.step == LinkStep.install) {
        await _finishInstall(session, key, rec);
        if (_shouldYield) return false;
      }
    }
    for (final key in keys) {
      if (_shouldYield) return false;
      if (_lists.ownerForSourceKey(key) != null) continue;
      if (st.unsyncable.containsKey(key)) continue;
      final list = userEntryListManager.getEntryLists()[key];
      if (list == null) continue;
      var rec = st.linking[key];
      if (rec == null) {
        if (list.savedVideos.length > maxEntriesPerPrivateList) {
          st.unsyncable[key] = UnsyncableReason.tooLarge;
          await _save();
          Analytics.track(
            'sync_list_unsyncable',
            props: {'reason': UnsyncableReason.tooLarge},
          );
          continue;
        }
        rec = _matchByName(key) ?? _newCreateRecord(key == defaultKey);
        st.linking[key] = rec;
        await _save();
      }
      final ok = await _link(session, key, rec);
      if (!ok) return false;
    }
    // An account with no default list adopts this device's when that list
    // is already linked (a list shared from it before account sync, which
    // the merge doesn't create again).
    final hasDefault = st.directory.any((d) => d.isLive && d.isDefault);
    final defaultWrapper = defaultKey == null
        ? null
        : _lists.ownerForSourceKey(defaultKey);
    if (!hasDefault &&
        defaultWrapper != null &&
        !st.pendingOps.any((o) => o.type == 'setDefault')) {
      _enqueue(
        AccountOp(
          opId: generateOpId(),
          type: 'setDefault',
          args: {'listId': defaultWrapper.listId},
        ),
      );
      await _save();
    }
    return true;
  }

  LinkingRecord _newCreateRecord(bool isDefault) {
    final st = _st!;
    // The device's default list becomes the account's default when the
    // account has none (M2).
    final accountHasDefault = st.directory.any((d) => d.isLive && d.isDefault);
    return LinkingRecord(
      listId: generateListId(),
      requestId: generateOpId(),
      step: LinkStep.create,
      makeDefault: isDefault && !accountHasDefault,
    );
  }

  /// A record linking [localKey] to an account list it should merge into:
  /// for the device's default list, the account's default (M2); for any
  /// other list, the first live list in directory order with the same name
  /// that isn't already linked (or being linked) on this device (M3).
  LinkingRecord? _matchByName(String localKey) {
    final st = _st!;
    final taken = {
      ..._linkedKeysById().keys,
      for (final r in st.linking.values) r.listId,
    };
    if (localKey == readDefaultListKey()) {
      for (final d in st.directory) {
        if (d.isLive && d.isDefault && !taken.contains(d.listId)) {
          return LinkingRecord(listId: d.listId, step: LinkStep.seed);
        }
      }
    }
    final wanted = normalizeListName(localListName(localKey));
    final rows = [...st.directory]
      ..sort((a, b) => a.position.compareTo(b.position));
    for (final d in rows) {
      if (!d.isLive || taken.contains(d.listId)) continue;
      // The account's default is only matched by the device's default.
      if (d.isDefault && localKey != readDefaultListKey()) {
        final defaultKey = readDefaultListKey();
        final defaultLinked =
            defaultKey != null && _lists.ownerForSourceKey(defaultKey) != null;
        if (!defaultLinked) continue;
      }
      if (normalizeListName(d.name) == wanted) {
        return LinkingRecord(listId: d.listId, step: LinkStep.seed);
      }
    }
    return null;
  }

  /// Carry one link from its saved step to the end. Returns false when it
  /// can't finish now (a create to retry later).
  Future<bool> _link(
    AuthSession session,
    String localKey,
    LinkingRecord rec,
  ) async {
    final st = _st!;
    var attempts = 0;
    while (rec.step == LinkStep.create) {
      attempts++;
      if (attempts > 5) {
        throw SyncException(SyncErrorKind.server, 'create kept colliding');
      }
      final requestId = rec.requestId!;
      final createOp = AccountOp(
        opId: 'create-$requestId',
        type: 'createList',
        args: {
          'requestId': requestId,
          'listId': rec.listId,
          'name': _serverName(localKey),
          'visibility': listVisibilityPrivate,
          if (rec.noNameMatch) 'nameMatch': false,
        },
      );
      final resp = await _send(session, [createOp], sinceSeq: _noAnswers);
      final out = resp.outcomeFor(createOp.opId);
      if (out == null) {
        throw SyncException(SyncErrorKind.server, 'create not answered');
      }
      if (out.isDone && out.result?.listId != null) {
        final listId = out.result!.listId!;
        final linkedHere =
            _linkedKeysById().containsKey(listId) ||
            st.linking.entries.any(
              (e) => e.key != localKey && e.value.listId == listId,
            );
        if (linkedHere) {
          // Matched by name to a list this device already has linked to
          // another of its lists ("Pets" twice): make a list of its own.
          rec
            ..listId = generateListId()
            ..requestId = generateOpId()
            ..noNameMatch = true;
          await _save();
          continue;
        }
        rec
          ..listId = listId
          ..step = LinkStep.seed;
        await _save();
        break;
      }
      switch (out.reasonCode) {
        case accountReasonIdCollision:
          rec
            ..listId = generateListId()
            ..requestId = generateOpId();
          await _save();
          continue;
        case accountReasonListLimit:
          st.linking.remove(localKey);
          st.unsyncable[localKey] = UnsyncableReason.listLimit;
          await _save();
          Analytics.track(
            'sync_list_unsyncable',
            props: {'reason': UnsyncableReason.listLimit},
          );
          return true;
        case accountReasonRetry:
          // The server couldn't make the list yet: back off and resend the
          // same op (it finds the half-made row).
          throw SyncException(SyncErrorKind.server, 'create to be retried');
        default:
          // A create the server will never take (a name it refuses, say):
          // leave the list on this device until it's renamed rather than
          // retry forever.
          printAndLog(
            'AccountSync: create refused for $localKey: ${out.reason}',
          );
          st.linking.remove(localKey);
          st.unsyncable[localKey] = UnsyncableReason.refused;
          await _save();
          return true;
      }
    }
    if (rec.makeDefault) {
      final op = AccountOp(
        opId: 'default-${rec.requestId ?? rec.listId}',
        type: 'setDefault',
        args: {'listId': rec.listId},
      );
      await _send(session, [op], sinceSeq: _noAnswers);
      rec.makeDefault = false;
      await _save();
    }
    return _linkAndMerge(session, localKey, rec);
  }

  /// A name the server takes: the local name, cut to its length limit.
  String _serverName(String localKey) {
    final name = localListName(localKey).trim();
    return name.length <= maxDisplayNameLen
        ? name
        : name.substring(0, maxDisplayNameLen);
  }

  /// Merge the local list [localKey] with the account list in [rec] and
  /// install the owner wrapper (section 5.4, "merging one list"): the
  /// account's signs in its order, then the local extras, which go up as
  /// `addEntries` (private) or `addEntry` (shared) ops through the
  /// wrapper's own queue. Writes entries, then the wrapper's meta, then the
  /// index, then forgets the record; a kill anywhere in between redoes the
  /// merge (nothing was sent yet), which only ever adds.
  Future<bool> _linkAndMerge(
    AuthSession session,
    String localKey,
    LinkingRecord rec,
  ) async {
    final st = _st!;
    final local = userEntryListManager.getEntryLists()[localKey];
    if (local == null) {
      st.linking.remove(localKey);
      await _save();
      return true;
    }
    final ListSnapshot snapshot;
    try {
      snapshot = await _api.getState(
        listId: rec.listId,
        sessionToken: session.sessionToken,
      );
    } on SyncException catch (e) {
      if (e.kind == SyncErrorKind.notFound ||
          e.kind == SyncErrorKind.gone ||
          e.kind == SyncErrorKind.forbidden) {
        // The list it was to merge into is gone: start over with a create
        // of its own on the next pass, and have the account check the row
        // (`unlink` marks it deleted if the list really is gone), or the
        // next pass would match the same row again.
        st.linking.remove(localKey);
        if (!st.pendingOps.any(
          (o) => o.type == 'unlink' && o.args['listId'] == rec.listId,
        )) {
          _enqueue(
            AccountOp(
              opId: generateOpId(),
              type: 'unlink',
              args: {'listId': rec.listId},
            ),
          );
        }
        await _save();
        return true;
      }
      rethrow;
    }
    final remote = LinkedHashSet<SavedVideo>.from(snapshot.entries);
    final localOnly = [
      for (final v in local.savedVideos)
        if (!remote.contains(v)) v,
    ];
    final merged = <SavedVideo>{...remote, ...localOnly};
    local.savedVideos
      ..clear()
      ..addAll(merged);
    // Renamed here while it was being linked: the local name wins (it's the
    // later intent), queued in the wrapper's first meta write with its seed
    // ops, and in the same account save that forgets the record.
    final localName = _serverName(localKey);
    final renameOnLanding =
        rec.renamed &&
        normalizeListName(localName) != normalizeListName(snapshot.displayName);
    final now = _now();
    final wrapper = SyncedEntryList.owner(
      meta: SyncedListMeta(
        listId: snapshot.listId,
        displayName: renameOnLanding ? localName : snapshot.displayName,
        role: ListRole.owner,
        lastKnownSeq: snapshot.lastSeq,
        etag: null,
        lastSyncedAt: _now(),
        serverUpdatedAt: snapshot.updatedAt,
        orphaned: false,
        sourceLocalKey: localKey,
        pendingOps: [
          if (renameOnLanding)
            PendingOp(
              opId: generateOpId(),
              type: 'rename',
              args: {'displayName': localName},
              clientTs: now,
            ),
          ...seedOps(localOnly, snapshot.visibility),
        ],
        cachedMembers: snapshot.members,
        visibility: snapshot.visibility,
      ),
      source: local,
    );
    await local.write();
    await _lists.insert(wrapper);
    // Anything the person changed on the plain list while this ran went
    // straight into the set without an op: catch it up.
    for (final v in local.savedVideos.toList()) {
      if (!merged.contains(v)) await _engine.enqueueAddVideo(wrapper.listId, v);
    }
    for (final v in merged) {
      if (!local.savedVideos.contains(v)) {
        await _engine.enqueueRemoveVideo(wrapper.listId, v);
      }
    }
    st.linking.remove(localKey);
    if (renameOnLanding) {
      _enqueue(
        AccountOp(
          opId: generateOpId(),
          type: 'rename',
          args: {'listId': snapshot.listId, 'name': localName},
        ),
      );
    }
    await _save();
    // Its seed ops go with the engine's next pass over the lists, which the
    // cycle runs (see [_cycle]).
    _linkedThisCycle = true;
    sharing.bumpState();
    return true;
  }

  /// The ops that put [videos] on a list: `addEntries` of at most 200 and
  /// ~40 KB each for a private list, one `addEntry` each for a shared one.
  static List<PendingOp> seedOps(List<SavedVideo> videos, String visibility) {
    final now = syncNowSecs();
    if (visibility != listVisibilityPrivate) {
      return [
        for (final v in videos)
          PendingOp(
            opId: generateOpId(),
            type: 'addEntry',
            args: v.toJson(),
            clientTs: now,
          ),
      ];
    }
    final out = <PendingOp>[];
    var chunk = <Map<String, dynamic>>[];
    var bytes = 0;
    void flush() {
      if (chunk.isEmpty) return;
      out.add(
        PendingOp(
          opId: generateOpId(),
          type: 'addEntries',
          args: {'entries': chunk},
          clientTs: now,
        ),
      );
      chunk = [];
      bytes = 0;
    }

    for (final v in videos) {
      final json = v.toJson();
      final size = encodedJsonBytes(json) + 1;
      if (chunk.length >= maxAddEntriesPerOp ||
          (chunk.isNotEmpty && bytes + size > _maxAddEntriesOpBytes)) {
        flush();
      }
      chunk.add(json);
      bytes += size;
    }
    flush();
    return out;
  }

  // -------- The account's lists not on this device (M4, every cycle) --------

  Future<void> _installAccountLists(AuthSession session) async {
    final st = _st!;
    final linked = _linkedKeysById();
    final linkingTargets = {for (final r in st.linking.values) r.listId};
    final suppressed = _suppressedIds();
    final rows = [...st.directory]
      ..sort((a, b) => a.position.compareTo(b.position));
    for (final row in rows) {
      if (_shouldYield) return;
      if (!row.isLive) continue;
      if (linked.containsKey(row.listId)) continue;
      if (linkingTargets.contains(row.listId)) continue;
      if (suppressed.contains(row.listId)) continue;
      final key = _allocateInstallKey(row.name);
      final rec = LinkingRecord(listId: row.listId, step: LinkStep.install);
      st.linking[key] = rec;
      await _save();
      await _finishInstall(session, key, rec);
    }
  }

  /// Ids this device has asked the account to delete or unlink: not to be
  /// installed again while the op is on its way.
  /// An `unlink` or `restore` for [listId] is queued: the account's answer
  /// will settle what happens to it here.
  bool _verdictPending(String listId) => _st!.pendingOps.any(
    (o) =>
        (o.type == 'unlink' || o.type == 'restore') &&
        o.args['listId'] == listId,
  );

  Set<String> _suppressedIds() => {
    for (final op in _st!.pendingOps)
      if ((op.type == 'delete' || op.type == 'unlink') &&
          op.args['listId'] is String)
        op.args['listId'] as String,
  };

  String _allocateInstallKey(String name) {
    String fallback;
    try {
      fallback = lookupDictLibLocalizations(startingLocale)
          .importedListFallbackName;
    } catch (_) {
      fallback = 'Imported list';
    }
    // A key an install record has claimed but not created yet is taken
    // too.
    final claimed = _st!.linking.keys.toSet();
    var candidate = name;
    for (var n = 2; ; n++) {
      final key = listsService.allocateLocalKey(
        preferredName: candidate,
        fallbackBase: fallback,
      );
      if (!claimed.contains(key)) return key;
      candidate = '$name $n';
    }
  }

  /// Create the local list for an install record (if a killed run didn't
  /// get that far), fill it from the account and link it.
  Future<void> _finishInstall(
    AuthSession session,
    String key,
    LinkingRecord rec,
  ) async {
    final st = _st!;
    if (_linkedKeysById().containsKey(rec.listId)) {
      st.linking.remove(key);
      await _save();
      return;
    }
    if (!userEntryListManager.getEntryLists().containsKey(key)) {
      try {
        await userEntryListManager.createEntryList(key);
      } on EntryListNameException catch (e) {
        printAndLog('AccountSync: could not make $key for ${rec.listId}: $e');
        st.linking.remove(key);
        await _save();
        return;
      }
    }
    rec.step = LinkStep.seed;
    await _save();
    await _linkAndMerge(session, key, rec);
    // An install whose list turned out to be gone leaves an empty list
    // behind: take it away again.
    final local = userEntryListManager.getEntryLists()[key];
    if (local != null &&
        _lists.ownerForSourceKey(key) == null &&
        !st.linking.containsKey(key) &&
        local.savedVideos.isEmpty &&
        key != readDefaultListKey()) {
      await userEntryListManager.deleteEntryList(key);
    }
  }

  /// After the merge: the account's order, then the lists this device
  /// created, in its order; the local index set the same way, with lists
  /// that don't sync at the end.
  Future<void> _sendMergeReorder(AuthSession session) async {
    final st = _st!;
    final linked = _linkedKeysById();
    final directoryOrder =
        ([...st.directory]..sort((a, b) => a.position.compareTo(b.position)))
            .where((d) => d.isLive)
            .map((d) => d.listId)
            .toList();
    final ids = <String>[
      for (final id in directoryOrder)
        if (linked.containsKey(id)) id,
    ];
    for (final key in userEntryListManager.getEntryLists().keys) {
      final w = _lists.ownerForSourceKey(key);
      if (w != null && !ids.contains(w.listId)) ids.add(w.listId);
    }
    if (ids.isEmpty) return;
    _enqueue(
      AccountOp(opId: generateOpId(), type: 'reorder', args: {'listIds': ids}),
    );
    await _save();
    await _applyLocalOrder(ids);
  }

  /// Put the local lists in [ids] order (by the lists linked to them), the
  /// ones not linked after, lists that don't sync last.
  Future<void> _applyLocalOrder(List<String> ids) async {
    final st = _st!;
    final current = userEntryListManager.getEntryLists().keys.toList();
    final keyById = _linkedKeysById();
    final ordered = <String>[
      for (final id in ids)
        if (keyById[id] != null && current.contains(keyById[id])) keyById[id]!,
    ];
    final rest = [
      for (final k in current)
        if (!ordered.contains(k) && !st.unsyncable.containsKey(k)) k,
    ];
    final last = [
      for (final k in current)
        if (!ordered.contains(k) && st.unsyncable.containsKey(k)) k,
    ];
    final next = [...ordered, ...rest, ...last];
    if (listEquals(next, current)) return;
    userEntryListManager.setOrder(next);
    await userEntryListManager.writeEntryListKeys();
  }

  // -------- Follows and editor lists (M5, every cycle) --------

  Future<void> _mergeFollows(AuthSession session) async {
    final st = _st!;
    final account = st.follows.toSet();
    // The device's follows go up (union, decision 5).
    for (final l in _lists.subscribedLists) {
      if (!account.contains(l.listId)) {
        _enqueue(
          AccountOp(
            opId: generateOpId(),
            type: 'follow',
            args: {'listId': l.listId},
          ),
        );
      }
    }
    await _save();
    await _installAccountFollows();
  }

  /// Follow here what the account follows and this device doesn't. Lists
  /// found gone are tried again at most once a day.
  Future<void> _installAccountFollows() async {
    final st = _st!;
    final owned = {for (final d in st.directory) d.listId};
    for (final id in st.follows) {
      if (_shouldYield) return;
      if (_lists.hasList(id) || owned.contains(id)) continue;
      final gone = st.followsGone[id];
      if (gone != null && _now() - gone < 24 * 3600) continue;
      try {
        await _engine.subscribe(id, fromAccount: true);
        st.followsGone.remove(id);
      } on SyncException catch (e) {
        if (e.kind == SyncErrorKind.notFound || e.kind == SyncErrorKind.gone) {
          st.followsGone[id] = _now();
        } else {
          rethrow;
        }
      }
      await _save();
    }
  }

  /// Install editor mirrors for the lists the person edits (decision 13,
  /// section 5.7), without asking.
  Future<void> _installEditorLists(AuthSession session) async {
    final st = _st!;
    for (final id in st.editorListIds) {
      if (_shouldYield) return;
      final existing = _lists.get(id);
      if (existing != null &&
          (existing.meta.role == ListRole.editor ||
              existing.meta.role == ListRole.owner)) {
        continue;
      }
      final ListSnapshot snapshot;
      try {
        snapshot = await _api.getState(
          listId: id,
          sessionToken: session.sessionToken,
        );
      } on SyncException catch (e) {
        if (e.kind == SyncErrorKind.notFound ||
            e.kind == SyncErrorKind.gone ||
            e.kind == SyncErrorKind.forbidden) {
          continue;
        }
        rethrow;
      }
      if (existing != null) await _lists.removeLocal(id);
      await _lists.insert(
        SyncedEntryList.editor(
          meta: SyncedListMeta(
            listId: snapshot.listId,
            displayName: snapshot.displayName,
            role: ListRole.editor,
            lastKnownSeq: snapshot.lastSeq,
            etag: null,
            lastSyncedAt: _now(),
            serverUpdatedAt: snapshot.updatedAt,
            orphaned: false,
            cachedMembers: snapshot.members,
          ),
          savedVideos: LinkedHashSet<SavedVideo>.of(snapshot.entries),
        ),
      );
      sharing.bumpState();
    }
  }

  // -------- The steady-state round trip (section 5.2 step 5) --------

  void _enqueue(AccountOp op) {
    _st!.pendingOps.add(op);
  }

  /// Queue an account op from outside a cycle (the list operations in
  /// [ListsService]) and save. No-op when account sync isn't running for a
  /// signed-in account.
  Future<void> enqueue(AccountOp op) async {
    final st = _state;
    if (st == null) return;
    st.pendingOps.add(op);
    await _save();
  }

  /// The head of the queue that fits one request.
  List<AccountOp> _takeBatch() {
    final out = <AccountOp>[];
    var bytes = 128;
    for (final op in _st!.pendingOps) {
      if (out.length >= _maxAccountOpsPerRequest) break;
      final size = encodedJsonBytes(op.toJson()) + 1;
      if (out.isNotEmpty && bytes + size > maxBatchBodyBytes) break;
      out.add(op);
      bytes += size;
    }
    return out;
  }

  /// Answers arrived during this round trip and the pages haven't been told
  /// (once, at its end).
  bool _historyGrew = false;

  Future<void> _accountRoundTrip(AuthSession session) async {
    try {
      await _accountRoundTripPages(session);
    } finally {
      if (_historyGrew) {
        _historyGrew = false;
        reviewHistory.notifyChanged();
      }
    }
  }

  Future<void> _accountRoundTripPages(AuthSession session) async {
    // A setting changed here goes up in this request, so it is pending
    // before the account's values are applied (an incoming value never
    // overwrites a change this device hasn't sent).
    for (final op in detectSettingChanges(_st!)) {
      _enqueue(op);
    }
    await _save();
    var staleCursorReset = false;
    for (var page = 0; page < _maxPagesPerCycle; page++) {
      final st = _st!;
      final batch = _takeBatch();
      final resp = await _send(session, batch);
      if (_incarnationChanged(resp)) {
        await _restartAgainstNewIncarnation(resp);
        _again = true;
        return;
      }
      if (resp.seq < st.sinceSeq && !staleCursorReset) {
        // The server lost state relative to this device (restored to an
        // earlier point): read everything again from the start (answers
        // already held dedupe), and send every answer again, since the
        // ones this device sent after that point are gone there. This
        // response answered the old cursor, so its page isn't used.
        st.sinceSeq = 0;
        staleCursorReset = true;
        await _save();
        await _applyResults(batch, resp);
        await _save();
        await reviewHistory.queueEverythingForUpload();
        continue;
      }
      await _applyResults(batch, resp);
      await _applyAccountState(session, resp);
      await _applyRevisionPage(resp);
      st.sinceSeq = resp.nextSinceSeq;
      await _save();
      final left = _takeBatch();
      if (!resp.hasMore && left.isEmpty) {
        _retryOpsBackoff = 0;
        return;
      }
      if (!resp.hasMore &&
          batch.isNotEmpty &&
          listEquals(
            [for (final o in left) o.opId],
            [for (final o in batch) o.opId],
          )) {
        // Nothing in the batch went through (each answered `retry`, the
        // list it needs being unreachable for now, say): try again later
        // rather than straight away, backing off.
        _retryOpsBackoff = _retryOpsBackoff == 0
            ? 30
            : (_retryOpsBackoff * 2).clamp(30, 3600);
        _scheduleRetry(_retryOpsBackoff);
        return;
      }
      if (_shouldYield) {
        _again = true;
        return;
      }
    }
    _again = true;
  }

  /// Seconds before ops the server keeps answering `retry` are sent again
  /// (doubling, reset once the queue moves).
  int _retryOpsBackoff = 0;

  /// Flush queued account ops without the rest of a cycle (app paused).
  Future<void> _flushAccountOps(AuthSession session) async {
    final st = _state;
    if (st == null || !st.mergeDone) return;
    if (st.userId != sessionUserId(session)) return;
    for (final op in detectSettingChanges(st)) {
      _enqueue(op);
    }
    if (st.pendingOps.isEmpty) return;
    await _save();
    try {
      final batch = _takeBatch();
      final resp = await _send(session, batch, sinceSeq: _noAnswers);
      if (_incarnationChanged(resp)) return;
      await _applyResults(batch, resp);
      await _save();
    } catch (e) {
      printAndLog('AccountSync: paused flush failed: $e');
    }
  }

  /// One page of revision data: a reset made elsewhere first (so late
  /// answers from before it are dropped), then the answers, then settings.
  /// The caller saves `sinceSeq` only after this returns: a kill in between
  /// re-reads the same page, which is harmless.
  Future<void> _applyRevisionPage(AccountSyncResponse resp) async {
    final st = _st!;
    if (resp.resetTsUs > st.lastResetTsUs) {
      await reviewHistory.reset(resp.resetTsUs);
      await sharedPreferences.setInt(KEY_RANDOM_REVIEWS_COUNTER, 0);
      await sharedPreferences.remove(KEY_FIRST_RANDOM_REVIEW);
      st.lastResetTsUs = resp.resetTsUs;
      await _save();
    }
    final incoming = [for (final r in resp.reviews) ?reviewFromWire(r)];
    if (incoming.isNotEmpty &&
        await reviewHistory.mergeRemote(incoming, notify: false) > 0) {
      _historyGrew = true;
    }
    final pendingKeys = {
      for (final op in st.pendingOps)
        if (op.type == 'setSetting') op.args['key'] as String?,
    };
    applyIncomingSettings(st, resp.settings, pendingKeys);
  }

  /// Take answered ops off the queue and act on refusals.
  Future<void> _applyResults(
    List<AccountOp> batch,
    AccountSyncResponse resp,
  ) async {
    final st = _st!;
    for (final op in batch) {
      final out = resp.outcomeFor(op.opId);
      if (out == null || out.shouldRetry) continue;
      st.pendingOps.removeWhere((o) => o.opId == op.opId);
      if (op.type == 'unlink') {
        final listId = op.args['listId'] as String?;
        if (listId == null) continue;
        final wrapper = _lists.get(listId);
        if (out.isDone) {
          // Verified gone: what happens to the local copy.
          if (wrapper != null && wrapper.meta.role == ListRole.owner) {
            await _handleDeletedElsewhere(wrapper);
          }
        } else if (out.reasonCode == accountReasonStillLive &&
            wrapper != null &&
            wrapper.meta.orphaned) {
          // A false alarm (the 404s were something else): sync again.
          wrapper.meta.orphaned = false;
          await wrapper.writeMeta();
          _linkedThisCycle = true;
        }
      } else if (op.type == 'restore') {
        // Restored because this device's unsent edits were newer than the
        // delete (see [_handleDeletedElsewhere]).
        final listId = op.args['listId'] as String?;
        final wrapper = listId == null ? null : _lists.get(listId);
        if (wrapper == null || wrapper.meta.role != ListRole.owner) continue;
        if (out.isDone) {
          // Back on every device, private; the edits go up now.
          wrapper.meta.orphaned = false;
          wrapper.meta.visibility = listVisibilityPrivate;
          await wrapper.writeMeta();
          _linkedThisCycle = true;
        } else {
          // It can't come back (purged since): kept here as a list of its
          // own, which the next pass links again by name.
          printAndLog(
            'AccountSync: restore refused (${out.reasonCode}); keeping '
            '${wrapper.listId} here',
          );
          await _engine.dropOwned(wrapper.listId);
          sharing.bumpState();
        }
      } else if (!out.isDone) {
        printAndLog(
          'AccountSync: ${op.type} refused (${out.reasonCode}): ${out.reason}',
        );
      }
    }
  }

  /// Bring the device in line with the account after a response: lists
  /// deleted elsewhere, lists made elsewhere, the order and default, and
  /// follows and editor lists.
  Future<void> _applyAccountState(
    AuthSession session,
    AccountSyncResponse resp,
  ) async {
    final st = _st!;
    final pendingDeletes = _suppressedIds();
    // Lists this device has linked.
    for (final w in _lists.ownedLists.toList()) {
      final row = st.rowFor(w.listId);
      if (w.meta.orphaned) {
        // Waiting for the account's verdict (an unlink or a restore on its
        // way). Without one (the app died between orphaning it and queueing
        // that), settle it from the directory now.
        if (_verdictPending(w.listId)) continue;
        if (row != null && row.isLive) {
          w.meta.orphaned = false;
          await w.writeMeta();
          _linkedThisCycle = true;
          continue;
        }
        if (row != null && row.isDeleted) {
          await _handleDeletedElsewhere(w);
          continue;
        }
      }
      if (row == null) {
        // Missing, not deleted: verify with the list itself before
        // anything happens to the local copy (a directory restored to an
        // earlier point, say). `unlink` answers still_live and puts the row
        // back if the list is fine.
        if (!pendingDeletes.contains(w.listId)) {
          _enqueue(
            AccountOp(
              opId: generateOpId(),
              type: 'unlink',
              args: {'listId': w.listId},
            ),
          );
          await _save();
        }
        continue;
      }
      if (row.isDeleted) await _handleDeletedElsewhere(w);
    }
    // Lists the account has and this device doesn't.
    await _installAccountLists(session);
    // The default list follows the account's.
    for (final d in st.directory) {
      if (d.isLive && d.isDefault) {
        final key = _linkedKeysById()[d.listId];
        if (key != null && readDefaultListKey() != key) {
          await sharedPreferences.setString(KEY_DEFAULT_LIST_KEY, key);
        }
      }
    }
    // The order, unless this device has a reorder on its way.
    if (!st.pendingOps.any((o) => o.type == 'reorder')) {
      final ids =
          ([...st.directory]..sort((a, b) => a.position.compareTo(b.position)))
              .where((d) => d.isLive)
              .map((d) => d.listId)
              .toList();
      await _applyLocalOrder(ids);
    }
    // Follows: unfollowed elsewhere (it was followed, now it isn't, and no
    // follow is on its way from here) goes here too; followed elsewhere is
    // followed here.
    final previous = st.follows.toSet();
    final now = resp.follows.toSet();
    final pendingFollows = {
      for (final op in st.pendingOps)
        if (op.type == 'follow') op.args['listId'],
    };
    for (final id in previous.difference(now)) {
      if (pendingFollows.contains(id)) continue;
      final l = _lists.get(id);
      if (l != null && l.meta.role == ListRole.subscriber) {
        await _engine.unsubscribe(id, fromAccount: true);
      }
    }
    st.follows = resp.follows;
    await _save();
    await _installAccountFollows();
    await _installEditorLists(session);
  }

  /// A linked list deleted on another device (or verified gone), resolved
  /// by timestamps without a word to the person (section 5.5):
  /// - the directory row is `deleted` and this device has unsent edits newer
  ///   than the delete (or the delete's time is unknown): the edits are the
  ///   later intent, so the list is restored, everywhere, and they go up
  ///   once the account has it back;
  /// - deleted, and nothing unsent or only older edits: the delete is the
  ///   later intent, so the list goes here too, edits and all;
  /// - the row gone altogether (purged, or the account restored to an
  ///   earlier point): with unsent edits the list stays here as a list of
  ///   its own, which the next pass links again by name; without, it goes.
  /// The default list is never deleted this way (the server refuses to
  /// delete it): it just stops being linked, and links again.
  Future<void> _handleDeletedElsewhere(SyncedEntryList wrapper) async {
    final key = wrapper.meta.sourceLocalKey;
    if (key == null) {
      await _lists.removeLocal(wrapper.listId);
      return;
    }
    if (key == readDefaultListKey()) {
      await _engine.dropOwned(wrapper.listId);
      return;
    }
    final pending = wrapper.meta.pendingOps;
    final row = _st!.rowFor(wrapper.listId);
    if (row != null && row.isLive) {
      // The account has it live after all: nothing to settle.
      if (wrapper.meta.orphaned) {
        wrapper.meta.orphaned = false;
        await wrapper.writeMeta();
        _linkedThisCycle = true;
      }
      return;
    }
    if (pending.isNotEmpty) {
      if (row == null || !row.isDeleted) {
        await _engine.dropOwned(wrapper.listId);
        sharing.bumpState();
        return;
      }
      final newest = pending.map((o) => o.clientTs).reduce(max);
      final deletedAt = row.deletedClientTs;
      if (deletedAt == null || newest >= deletedAt) {
        await _restoreWithEdits(wrapper);
        return;
      }
    }
    // The list first: a kill before the wrapper goes leaves a wrapper whose
    // source is missing, which start-up drops; the other way round would
    // leave an unlinked list that links again and undoes the delete.
    await userEntryListManager.deleteEntryList(key);
    await _engine.dropOwned(wrapper.listId);
    sharing.bumpState();
  }

  /// Queue the account's `restore` of [wrapper]'s list, then hold the list
  /// back from syncing (orphaned, still editable) until the answer: its
  /// edits can only go up once it is live again. In that order, so a kill
  /// in between leaves the restore queued (the list's next sync is a 410,
  /// which orphans it with an `unlink` that the restore then answers).
  Future<void> _restoreWithEdits(SyncedEntryList wrapper) async {
    final st = _st!;
    if (!st.pendingOps.any(
      (o) => o.type == 'restore' && o.args['listId'] == wrapper.listId,
    )) {
      _enqueue(
        AccountOp(
          opId: generateOpId(),
          type: 'restore',
          args: {'listId': wrapper.listId},
        ),
      );
      await _save();
    }
    if (!wrapper.meta.orphaned) {
      wrapper.meta.orphaned = true;
      await wrapper.writeMeta();
    }
  }

  // -------- Engine hooks --------

  /// The engine found an owner list gone (410, or three 404s). Never takes
  /// the controller lock (the engine holds the list's lock, and a cycle
  /// holding ours may be waiting for it): it stops the list syncing,
  /// queues a verifying `unlink`, and the next cycle acts on the verdict.
  Future<bool> _onOwnedListGone(
    SyncedEntryList list, {
    required bool gone,
  }) async {
    // Without account state (signed out, or account sync never ran) the
    // engine does what it did before account sync.
    if (!queuesForAccount) return false;
    final st = _st!;
    list.meta.orphaned = true;
    await list.writeMeta();
    if (!st.pendingOps.any(
      (o) => o.type == 'unlink' && o.args['listId'] == list.listId,
    )) {
      st.pendingOps.add(
        AccountOp(
          opId: generateOpId(),
          type: 'unlink',
          args: {'listId': list.listId},
        ),
      );
      await _save();
    }
    unawaited(kick(SyncReason.localChange));
    return true;
  }

  void _onFollowed(String listId) {
    if (!queuesForAccount || !(_state?.mergeDone ?? false)) return;
    unawaited(
      enqueue(
        AccountOp(
          opId: generateOpId(),
          type: 'follow',
          args: {'listId': listId},
        ),
      ).then((_) => kick(SyncReason.localChange)),
    );
  }

  void _onUnfollowed(String listId) {
    if (!queuesForAccount || !(_state?.mergeDone ?? false)) return;
    unawaited(
      enqueue(
        AccountOp(
          opId: generateOpId(),
          type: 'unfollow',
          args: {'listId': listId},
        ),
      ).then((_) => kick(SyncReason.localChange)),
    );
  }

  // -------- Linking new lists, share (used by ListsService) --------

  /// Record that [localKey], just created on a signed-in device, is to be
  /// linked. Call under [exclusive].
  Future<void> noteCreatedLocally(String localKey) async {
    final st = _state;
    if (st == null || !isSignedInAndSupported) return;
    st.linking[localKey] = LinkingRecord(
      listId: generateListId(),
      requestId: generateOpId(),
      step: LinkStep.create,
    );
    await _save();
  }

  /// A local list changed key (renamed before it was linked): keep its
  /// records with it. Call under [exclusive].
  Future<void> noteKeyMoved(String oldKey, String newKey) async {
    final st = _state;
    if (st == null) return;
    final rec = st.linking.remove(oldKey);
    if (rec != null) st.linking[newKey] = rec..renamed = true;
    final reason = st.unsyncable.remove(oldKey);
    // A name the account refused is tried again under the new one.
    if (reason != null && reason != UnsyncableReason.refused) {
      st.unsyncable[newKey] = reason;
    }
    await _save();
  }

  /// A local list was deleted: forget its records. With [deleteOnAccount],
  /// the account list its link was heading for (if it was being linked) is
  /// deleted too, queued in the same save. Call under [exclusive].
  Future<void> noteDeletedLocally(
    String localKey, {
    bool deleteOnAccount = false,
  }) async {
    final st = _state;
    if (st == null) return;
    final rec = st.linking.remove(localKey);
    st.unsyncable.remove(localKey);
    if (deleteOnAccount && rec != null) _queueDeleteFor(rec);
    await _save();
  }

  /// Queue the account's `delete` of the list [rec] was linking to (the
  /// person deleted the local list while it was being linked). If the
  /// create never landed there is nothing to delete, and the account says
  /// so.
  void _queueDeleteFor(LinkingRecord rec) {
    if (_st!.pendingOps.any(
      (o) => o.type == 'delete' && o.args['listId'] == rec.listId,
    )) {
      return;
    }
    _enqueue(
      AccountOp(
        opId: generateOpId(),
        type: 'delete',
        args: {'listId': rec.listId},
      ),
    );
  }

  /// Run a cycle now and answer the owner wrapper of [localKey] if the list
  /// is linked afterwards. For the share dialog. Not under [exclusive].
  Future<SyncedEntryList?> ensureLinked(String localKey) async {
    var wrapper = _lists.ownerForSourceKey(localKey);
    if (wrapper != null) return wrapper;
    await kick(SyncReason.pullToRefresh);
    wrapper = _lists.ownerForSourceKey(localKey);
    return wrapper;
  }

  // -------- Sign-out, switch, deletion (section 5.9) --------

  /// The local half of signing out, also used when another account signs
  /// in: every owner and editor wrapper goes (the local lists keep their
  /// signs; subscriptions stay), and so do the account state and pending
  /// ops. Nothing on the server changes.
  Future<void> _clearLinksLocally() async {
    final st = _state;
    if (st != null && !st.clearing) {
      st.clearing = true;
      await _save();
    }
    await _engine.clearAllPendingOps();
    await _lists.clearEditableLists();
    await clearRevisionUploadQueue();
    await AccountSyncState.clear();
    _st = null;
    _stLoaded = true;
  }

  /// The unsent-answers queue goes with the account state (the history
  /// itself stays on the device).
  Future<void> clearRevisionUploadQueue() => reviewHistory.clearUnsent();

  /// The incarnation changed under a merged device: the account it was
  /// linked to was deleted and this is a new one. Start over (dropping
  /// links, keeping lists) and merge into it.
  Future<void> _restartAgainstNewIncarnation(AccountSyncResponse resp) async {
    final uid = _st!.userId;
    await _clearLinksLocally();
    _st = AccountSyncState(userId: uid, incarnation: resp.incarnation);
    _stLoaded = true;
    await _save();
  }

  /// Sign out (section 5.9): a best-effort flush of the account queue for
  /// up to 10 s (the caller flushes list queues), then the local clear.
  Future<void> signOutLocally({bool flush = true}) async {
    await exclusive(() async {
      final session = _auth.store.current;
      if (flush && session != null) {
        try {
          await () async {
            await _flushAccountOps(session);
            final st = _state;
            if (st != null &&
                st.mergeDone &&
                st.userId == sessionUserId(session)) {
              await _uploadAnswers(session, yieldable: false);
            }
          }().timeout(const Duration(seconds: 10));
        } catch (e) {
          printAndLog('AccountSync: sign-out flush failed: $e');
        }
      }
      await _clearLinksLocally();
    });
  }

  /// Test helper: forget the in-memory state so the next access reloads it
  /// from prefs (as a new process would).
  @visibleForTesting
  void reloadStateForTesting() {
    _st = null;
    _stLoaded = false;
  }
}
