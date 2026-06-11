import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../common.dart';
import '../entry_list.dart';
import '../globals.dart';
import '../saved_video.dart';
import 'auth/auth_service.dart';
import 'list_id.dart';
import 'sync_api.dart';
import 'synced_entry_list.dart';

/// Lightweight async mutex. Each `synchronized` call appends its body
/// to a serial chain, guaranteeing at most one body runs at a time for
/// a given lock. Used by [SyncEngine] to serialise per-list flush /
/// pull / mutation work — eliminating the inflight-bool + debounce-
/// timer race that the prior state machine had.
@visibleForTesting
class AsyncLock {
  Future<void> _last = Future.value();

  Future<T> synchronized<T>(Future<T> Function() body) {
    final prev = _last;
    final completer = Completer<void>();
    _last = completer.future;
    return () async {
      try {
        await prev;
      } catch (_) {/* prior body errored; don't propagate to next */}
      try {
        return await body();
      } finally {
        completer.complete();
      }
    }();
  }
}

/// Per-list mutable engine state: the serialisation lock, the
/// debounced-flush timer, and 429/5xx backoff state. One instance per
/// listId, kept in [SyncEngine._state].
class _PerListState {
  final AsyncLock lock = AsyncLock();
  Timer? debounceTimer;
  int? backoffSeconds;

  /// Consecutive 404 (notFound) responses for this list. A 404 is
  /// ambiguous — server-side config drift or a transient miss can
  /// produce one for a list that still exists — so the engine only
  /// orphans/destroys local state after several in a row (see
  /// [SyncEngine._notFoundOrphanThreshold]). Reset on any successful
  /// round-trip.
  int consecutiveNotFound = 0;

  void cancelTimer() {
    debounceTimer?.cancel();
    debounceTimer = null;
  }
}

/// What kind of session-state notification the engine emits to the UI
/// via [SyncEngine.notifications]. UI consumers translate these into
/// localised banners / snackbars.
enum SyncNotification {
  /// Server returned 401 on a sync attempt and the local session has
  /// been dropped. UI should prompt re-sign-in. The pending op queue
  /// is preserved — the next successful sign-in resumes the flush.
  sessionExpired,

  /// Server returned 403 — caller has been removed as editor and
  /// demoted to subscriber. Pending ops were unrecoverable and have
  /// been dropped.
  removedAsEditor,

  /// Server returned a catch-up snapshot because the client's
  /// `lastKnownSeq` had fallen out of the retained op-log window. The
  /// in-memory state has been refreshed but intermediate ops by other
  /// editors are no longer available, so a still-pending local op may
  /// have silently overwritten (or been overwritten by) work the user
  /// can no longer see. UI surfaces an advisory banner so the user
  /// can reconcile manually.
  snapshotCatchUp,
}

/// Push / pull engine for [SyncedEntryList]s.
///
/// ## Concurrency model
///
/// Each list has its own [AsyncLock]. Every operation that touches a
/// list's state (push, pull, accept-invite, create, etc.) takes the
/// lock before mutating in-memory state or hitting the server. This
/// gives us:
///
///   - **No inflight-vs-newly-scheduled-flush race.** Newly enqueued
///     ops that arrive during a /sync just queue behind the
///     lock; once it releases they get their turn.
///   - **`pushAllDirty` actually drains.** It awaits the lock per list
///     until the queue is empty, so the OS-suspend window genuinely
///     ends only after the network round-trips complete.
///   - **No "scheduled timer fires while inflight" bail-out path.**
///     The timer-driven flush also takes the lock — if a flush is
///     already running, the timer's flush just waits its turn.
///
/// ## Persistence ordering
///
/// User mutations write meta first then entries (so the pending op is
/// durable even if entries write doesn't complete — load-time replay
/// fixes the state in memory). Server acks write entries first then
/// meta (so the new local state is durable even if we crash before
/// clearing the pending op — the retry returns "duplicate" which is
/// idempotent). See [SyncedEntryList] docs for the full invariant.
///
/// ## Wire contract
///
/// Editor / owner lists: local mutations enqueue [PendingOp]s; the
/// engine batches them and POSTs to `/v1/lists/:id/sync` after a 2s
/// debounce. The response carries per-op outcomes (applied / duplicate
/// / rejected) plus `missedOps` from other editors — or a full
/// `snapshot` if the client is too far behind for an op diff.
///
/// Subscriber lists: pull from `/v1/lists/:id` (R2 snapshot) with
/// `If-None-Match` — no DO request needed.
///
/// **Invariant:** local mirror state = server state at `lastKnownSeq`
/// + pending ops applied in order. Re-derived after every sync.
class SyncEngine {
  final SyncApi _api;
  final SyncedEntryListManager _manager;
  final AuthService _auth;

  final Map<String, _PerListState> _state = {};

  /// `sync: true` so a notification fired from inside an in-progress
  /// [_handleSyncError] (e.g. the 401 path during a /sync) reaches its
  /// listeners synchronously rather than being deferred to a later
  /// microtask. Without sync delivery, the await-chain wrapping the
  /// /sync request can complete and the engine method return before
  /// the listener microtask fires — leaving test code that asserts on
  /// the notification immediately after `await pushAllDirty()` racing
  /// against the stream scheduler. Safe here because listener
  /// callbacks are short (snackbar / dialog plumbing) and never
  /// re-enter the engine.
  final StreamController<SyncNotification> _notifications =
      StreamController<SyncNotification>.broadcast(sync: true);

  /// UI listens here for one-shot events (session expired, demoted)
  /// that aren't easily expressed as state on the lists themselves.
  Stream<SyncNotification> get notifications => _notifications.stream;

  _PerListState _stateOf(String listId) =>
      _state.putIfAbsent(listId, _PerListState.new);

  static const Duration _pushDebounce = Duration(seconds: 2);
  static const Duration _maxBackoff = Duration(minutes: 5);

  /// Server-side cap on ops per /sync request (must match
  /// `MAX_OPS_PER_BATCH` in `lists/workers/src/validation.ts`). The
  /// engine chunks any pending queue larger than this into multiple
  /// sequential /sync calls so a long offline session can still
  /// drain.
  static const int _maxOpsPerBatch = 50;

  /// How many random list IDs we'll try before giving up on a create.
  /// With 60 bits per key, collisions should be unobservable; failures
  /// here mean something else is wrong.
  static const int _createKeyMaxAttempts = 5;

  /// How many consecutive 404s a list must accumulate before the engine
  /// treats it as genuinely gone. A 410 (gone) is authoritative — the
  /// owner tombstoned the list — and skips the threshold entirely. A
  /// 404 is not: an APP_ID config drift on a deploy resolves every list
  /// to a fresh empty DO and would otherwise mass-delete editor mirrors
  /// (and their queued edits) over a server-side mistake, the same
  /// failure class the wrong-app 403 guard exists for.
  static const int _notFoundOrphanThreshold = 3;

  SyncEngine({
    required SyncApi api,
    required SyncedEntryListManager manager,
    required AuthService auth,
  })  : _api = api,
        _manager = manager,
        _auth = auth;

  void dispose() {
    for (final s in _state.values) {
      s.cancelTimer();
    }
    _state.clear();
    _notifications.close();
    _api.close();
  }

  void _clearListState(String listId) {
    _state.remove(listId)?.cancelTimer();
  }

  // -------- Public mutation entry points --------

  /// Enqueue an `addEntry` op for [listId] adding [video]. The caller
  /// is responsible for having already applied the optimistic
  /// mutation to the local mirror (or, for owner lists, to the source
  /// EntryList).
  ///
  /// Persistence ordering: the pending op + meta are written before
  /// the entries write that follows in [SyncedEntryList.addVideo].
  /// See the class-level doc.
  Future<void> enqueueAddVideo(String listId, SavedVideo video) {
    return _enqueueOp(listId, 'addEntry', video.toJson());
  }

  Future<void> enqueueRemoveVideo(String listId, SavedVideo video) {
    return _enqueueOp(listId, 'removeEntry', video.toJson());
  }

  Future<void> _enqueueOp(
      String listId, String type, Map<String, dynamic> args) async {
    final list = _manager.get(listId);
    if (list == null) return;
    if (!_isEditableRole(list.meta.role) || list.meta.orphaned) return;
    final op = PendingOp(
      opId: generateOpId(),
      type: type,
      args: args,
      clientTs: _nowSecs(),
    );
    list.meta.pendingOps.add(op);
    try {
      await list.writeMeta();
    } catch (e) {
      // writeMeta failed — roll back the in-memory enqueue and
      // propagate. Without this rollback, the caller would persist
      // its entries-set mutation in a follow-up `write()` while the
      // pending op never reached disk, so the server would never
      // learn about the edit: the optimistic in-memory state and the
      // durable state would diverge silently. Re-thrown so the
      // mutator (SyncedEntryList.addEntry/removeEntry) can revert its
      // own optimistic change and the UI can surface the failure.
      list.meta.pendingOps.remove(op);
      printAndLog('SyncEngine: writeMeta $listId failed: $e');
      rethrow;
    }
    sharing.bumpState();
    _scheduleFlush(listId);
  }

  bool _isEditableRole(ListRole role) =>
      role == ListRole.owner || role == ListRole.editor;

  /// Arm the debounce timer. Idempotent — if a timer was already armed
  /// it's reset to the new deadline. If a flush is in progress under
  /// the lock when the timer fires, the new flush just queues behind
  /// it and runs as soon as the lock releases.
  ///
  /// **Backoff respected:** when a transient failure has installed a
  /// longer retry timer (network down / 5xx / 429), a new user op
  /// must NOT collapse the wait back to the 2s debounce. The pending
  /// op will ride along on the next retry. Without this guard, a
  /// chronically failing endpoint plus active user editing would
  /// hammer the server every 2s instead of backing off.
  void _scheduleFlush(String listId) {
    final state = _stateOf(listId);
    if (state.backoffSeconds != null &&
        (state.debounceTimer?.isActive ?? false)) {
      return;
    }
    state.cancelTimer();
    state.debounceTimer = Timer(_pushDebounce, () => _flushOps(listId));
  }

  /// Flush every dirty editable list now and wait for the round-trips
  /// to actually complete. Used on `AppLifecycleState.paused` so
  /// unsaved edits land before the OS suspends us.
  ///
  /// Per list, we loop until the queue is empty or [_flushOps] installs
  /// a backoff timer. Each iteration takes the per-list lock, so a
  /// concurrent timer-driven flush serialises naturally. The
  /// backoff-installed signal is what bounds the loop — there's no
  /// fixed iteration cap, so a long offline edit batch fully drains
  /// rather than getting stuck behind an arbitrary limit. A chronically
  /// failing endpoint can't spin: the first failure installs a backoff
  /// timer and the loop exits, leaving the timer to retry later.
  Future<void> pushAllDirty() async {
    final dirty = _manager.editableLists
        .where((l) => l.meta.pendingOps.isNotEmpty)
        .toList();
    await Future.wait(dirty.map((l) => _drainListPending(l.listId).catchError(
        (e) => printAndLog('SyncEngine: drain ${l.listId} failed: $e'))));
  }

  /// Loop [_flushOps] for one list until its queue is empty or a
  /// backoff timer has been installed. Used by both [pushAllDirty]
  /// (background-suspend drain) and [syncAll] (foreground full sync)
  /// — both want "land everything queued, then return". A bare
  /// `_flushOps` call only ships one batch of up to [_maxOpsPerBatch],
  /// so a long offline edit batch needs the loop to fully drain.
  ///
  /// Bail conditions beyond "queue empty / list orphaned / wrong
  /// role":
  ///   - **No session.** [_flushOps] short-circuits when signed out,
  ///     leaving the queue untouched. Looping would spin.
  ///   - **Backoff installed.** A transient failure inside
  ///     [_flushOps] arms a retry timer; defer to it.
  ///   - **No forward progress.** Defensive: if a flush returned
  ///     without consuming any ops AND without installing a backoff
  ///     (shouldn't happen in normal flow), exit so a future change
  ///     to [_flushOps] can't spin this loop.
  Future<void> _drainListPending(String listId) async {
    while (true) {
      final list = _manager.get(listId);
      if (list == null || list.meta.pendingOps.isEmpty) return;
      if (list.meta.orphaned) return;
      if (!_isEditableRole(list.meta.role)) return;
      if (_auth.store.current == null) return;
      final before = list.meta.pendingOps.length;
      await _flushOps(listId);
      if (_stateOf(listId).backoffSeconds != null) return;
      final after = _manager.get(listId)?.meta.pendingOps.length ?? 0;
      if (after >= before) return;
    }
  }

  /// Full bidirectional sync of every list. Called on app open /
  /// resume. Editable lists go through /sync (carrying any pending
  /// ops); subscribers pull from R2.
  ///
  /// Editable lists always run at least one [_flushOps] — even when
  /// the queue is empty, the call pulls missedOps from other editors
  /// (a pull-only sync). After that, [_drainListPending] keeps
  /// flushing while there's still queued work, so a long offline
  /// queue (>50 ops) fully lands before returning.
  Future<void> syncAll() async {
    final futures = <Future<void>>[];
    for (final l in _manager.editableLists) {
      futures.add(_flushAndDrain(l.listId).catchError((e) =>
          printAndLog('SyncEngine: sync editable ${l.listId} failed: $e')));
    }
    for (final l in _manager.subscribedLists) {
      futures.add(_pullSubscribed(l.listId).catchError(
          (e) => printAndLog('SyncEngine: pull sub ${l.listId} failed: $e')));
    }
    await Future.wait(futures);
  }

  Future<void> _flushAndDrain(String listId) async {
    await _flushOps(listId);
    await _drainListPending(listId);
  }

  // -------- Editor / owner: /sync flow --------

  /// POST /sync with pending ops + lastKnownSeq, then reconcile the
  /// response into local state. All under the per-list lock — no
  /// inflight bool needed.
  Future<void> _flushOps(String listId) {
    return _stateOf(listId).lock.synchronized(() async {
      final list = _manager.get(listId);
      if (list == null) return;
      if (!_isEditableRole(list.meta.role)) return;
      if (list.meta.orphaned) return;

      final session = _auth.store.current;
      if (session == null) {
        printAndLog('SyncEngine: no session; cannot /sync $listId');
        return;
      }

      // Snapshot the queue. New ops added during the request go to the
      // tail and will be picked up by the next flush iteration.
      final fullQueueLen = list.meta.pendingOps.length;
      final batchLen =
          fullQueueLen > _maxOpsPerBatch ? _maxOpsPerBatch : fullQueueLen;
      final batch = list.meta.pendingOps.sublist(0, batchLen);
      final opsForWire = batch.map((o) => o.toJson()).toList();

      try {
        final response = await _api.syncOps(
          listId: listId,
          lastKnownSeq: list.meta.lastKnownSeq,
          ops: opsForWire,
          sessionToken: session.sessionToken,
          clientId: getOrCreateClientId(),
        );
        await _applySyncResponse(list, batch, response);
        _stateOf(listId).backoffSeconds = null;
        _stateOf(listId).consecutiveNotFound = 0;
        // If new ops landed during the request OR we sent a partial
        // batch, schedule another flush so we keep draining.
        if (list.meta.pendingOps.isNotEmpty && !list.meta.orphaned) {
          _scheduleFlush(listId);
        }
      } on SyncException catch (e) {
        await _handleSyncError(list, e, batch);
      }
    });
  }

  /// Apply a /sync response: drop acked ops from the queue, fold in
  /// missedOps (or adopt snapshot), refresh members + cursor, persist
  /// in ack-order (entries first, then meta).
  Future<void> _applySyncResponse(
    SyncedEntryList list,
    List<PendingOp> batch,
    SyncResponse response,
  ) async {
    // 1. Drop applied + duplicate ops from the queue. For rejected,
    // log + drop — there's no inverse to revert.
    final ackedIds = <String>{};
    for (final outcome in response.applied) {
      ackedIds.add(outcome.opId);
      if (outcome.status == OpStatus.rejected) {
        printAndLog('SyncEngine: ${list.listId} op ${outcome.opId} rejected: '
            '${outcome.reason}');
      }
    }
    list.meta.pendingOps.removeWhere((o) => ackedIds.contains(o.opId));

    // 2. Fold in remote work.
    final snapshot = response.snapshot;
    final missedOps = response.missedOps;
    if (snapshot != null) {
      _adoptSnapshot(list, snapshot);
      if (response.wasSnapshotCatchUp) {
        _notifications.add(SyncNotification.snapshotCatchUp);
      }
    } else if (missedOps != null && missedOps.isNotEmpty) {
      for (final op in missedOps) {
        list.applyOpToSavedVideos(op.type, op.args);
      }
    }
    // 3. Re-apply this client's still-pending ops on top so the
    // visible state matches (server view at lastKnownSeq) +
    // (queued ops in order). Idempotent under set semantics.
    for (final op in list.meta.pendingOps) {
      list.applyOpToSavedVideos(op.type, op.args);
    }

    // 4. Update cursor + member cache + sync timestamp. The response
    // echoes the list's current display name on every /sync, so an
    // owner's rename reaches editors here without a dedicated op. Guard
    // on non-null so an older server (no field) leaves the name alone.
    list.meta.lastKnownSeq = response.appliedSeq;
    list.meta.lastSyncedAt = _nowSecs();
    list.meta.cachedMembers = response.members;
    if (response.displayName != null) {
      list.meta.displayName = response.displayName!;
    }

    // 5. Persist in ack-order: entries first, then meta. Awaited so
    // we don't return until the new state is durable.
    try {
      await list.writeAllAfterServerAck();
    } catch (e) {
      printAndLog('SyncEngine: writeAll ${list.listId} failed: $e');
    }
    sharing.bumpState();
  }

  /// Replace local state with a server snapshot (catch-up case).
  /// Mutates entries in place; the caller is responsible for the
  /// persistence write after pending-op reapply. Routes through
  /// [SyncedEntryList.replaceEntriesFromServer] for all three roles —
  /// owner-mode wrappers share their entries set with the source list
  /// by reference, so a single replace path serves everyone.
  void _adoptSnapshot(SyncedEntryList list, ListSnapshot snapshot) {
    list.meta.displayName = snapshot.displayName;
    list.meta.serverUpdatedAt = snapshot.updatedAt;
    list.meta.cachedMembers = snapshot.members;
    list.meta.lastKnownSeq = snapshot.lastSeq;
    list.replaceEntriesFromServer(snapshot.entries);
  }

  Future<void> _handleSyncError(
      SyncedEntryList list, SyncException e, List<PendingOp> batch) async {
    final listId = list.listId;
    // The stale-cursor 400 is recoverable (server lost state relative
    // to our cursor); handle it before the generic invalidBody branch
    // would destroy the queue.
    if (e.isStaleCursor) {
      await _recoverFromStaleCursor(list);
      return;
    }
    switch (e.kind) {
      case SyncErrorKind.unauthorized:
        printAndLog('SyncEngine: $listId 401 on sync — dropping session');
        await _auth.dropSessionLocally();
        _notifications.add(SyncNotification.sessionExpired);
        sharing.bumpState();
      case SyncErrorKind.forbidden:
        // Distinguish "removed as editor" (DO membership check) from a
        // worker-level config 403 (`x-app-id` mismatch). The latter is
        // a transient server-config bug; destructively demoting +
        // dropping pending ops would destroy the user's offline edits
        // over a deploy mismatch, so just back off and retry.
        if (e.isWrongAppForbid) {
          printAndLog(
              'SyncEngine: $listId 403 (wrong_app) — backing off, NOT demoting');
          _scheduleBackoffRetry(list, null);
          break;
        }
        printAndLog('SyncEngine: $listId 403 on sync — demoting to subscriber');
        list.meta.pendingOps.clear();
        list.meta.role = ListRole.subscriber;
        _clearListState(listId);
        try {
          await list.writeMeta();
        } catch (err) {
          printAndLog('SyncEngine: writeMeta $listId failed: $err');
        }
        _notifications.add(SyncNotification.removedAsEditor);
        sharing.bumpState();
        // Immediately refresh entries from the R2 snapshot so the
        // user sees the canonical (read-only) state instead of their
        // last-known editor view. Best-effort; if the pull fails the
        // next syncAll catches it.
        unawaited(_pullSubscribed(listId).catchError((err) =>
            printAndLog('SyncEngine: post-demote pull $listId failed: $err')));
      case SyncErrorKind.notFound:
      case SyncErrorKind.gone:
        await _handleNotFoundOrGone(list, e.kind, 'sync');
      case SyncErrorKind.rateLimited:
        _scheduleBackoffRetry(list, _parseRetryAfter(e.details?['retryAfter']));
      case SyncErrorKind.network:
      case SyncErrorKind.server:
        _scheduleBackoffRetry(list, null);
      case SyncErrorKind.invalidBody:
      case SyncErrorKind.missingHeader:
      case SyncErrorKind.payloadTooLarge:
      case SyncErrorKind.idCollision:
      case SyncErrorKind.unknownClient:
        // Permanently rejected. Re-sending these ops will keep failing,
        // so drop them — pending queue must self-heal. Should be
        // unreachable in normal use; indicates a client bug.
        printAndLog(
            'SyncEngine: sync $listId failed unrecoverably (${e.kind}), '
            'dropping ${batch.length} op(s) from the queue: $e');
        final dropIds = batch.map((o) => o.opId).toSet();
        list.meta.pendingOps.removeWhere((o) => dropIds.contains(o.opId));
        try {
          await list.writeMeta();
        } catch (err) {
          printAndLog('SyncEngine: writeMeta $listId failed: $err');
        }
        sharing.bumpState();
    }
  }

  /// Self-heal from a stale-cursor rejection: the server's `last_seq`
  /// is behind our persisted `lastKnownSeq` (server-side data loss,
  /// restore-from-backup, listId reuse). Re-adopt the authoritative
  /// state via /state, re-apply the still-pending queue on top, and
  /// schedule a flush so the queued edits land against the fresh
  /// cursor. Without this the generic invalidBody handling would drop
  /// every future edit forever — the poison is the cursor, not the ops.
  Future<void> _recoverFromStaleCursor(SyncedEntryList list) async {
    final listId = list.listId;
    final session = _auth.store.current;
    if (session == null) return;
    printAndLog('SyncEngine: $listId cursor ahead of server '
        '(lastKnownSeq=${list.meta.lastKnownSeq}) — re-adopting server state');
    try {
      final snapshot = await _api.getState(
          listId: listId, sessionToken: session.sessionToken);
      _adoptSnapshot(list, snapshot);
      // Re-apply the queued local edits so they survive the reset and
      // get re-sent against the fresh cursor.
      for (final op in list.meta.pendingOps) {
        list.applyOpToSavedVideos(op.type, op.args);
      }
      try {
        await list.writeAllAfterServerAck();
      } catch (e) {
        printAndLog('SyncEngine: writeAll $listId failed: $e');
      }
      // Reuse the catch-up notification: the user's view was replaced
      // wholesale by server state with local edits re-applied on top.
      _notifications.add(SyncNotification.snapshotCatchUp);
      sharing.bumpState();
      if (list.meta.pendingOps.isNotEmpty) _scheduleFlush(listId);
    } on SyncException catch (err) {
      if (err.kind == SyncErrorKind.notFound ||
          err.kind == SyncErrorKind.gone) {
        // The list truly has no state on the (fresh) server.
        await _handleNotFoundOrGone(list, err.kind, 'stale-cursor recovery');
        return;
      }
      printAndLog(
          'SyncEngine: stale-cursor recovery for $listId failed: $err');
      _scheduleBackoffRetry(list, null);
    }
  }

  /// Decide what to do about a notFound/gone response for [list].
  ///
  /// 410 GONE is authoritative — the server only returns it for a
  /// tombstoned list (explicit owner delete or account deletion) — so
  /// it orphans immediately. 404 NOT_FOUND is ambiguous (config drift,
  /// transient R2 miss on the subscriber path) and destroying an editor
  /// mirror plus its queued edits over one is unrecoverable, so 404
  /// only orphans after [_notFoundOrphanThreshold] consecutive
  /// occurrences; until then the engine backs off and retries with all
  /// local state preserved.
  Future<void> _handleNotFoundOrGone(
      SyncedEntryList list, SyncErrorKind kind, String context) async {
    if (kind == SyncErrorKind.gone) {
      await _markOrphaned(list, 'gone on $context');
      return;
    }
    final state = _stateOf(list.listId);
    state.consecutiveNotFound++;
    if (state.consecutiveNotFound < _notFoundOrphanThreshold) {
      printAndLog('SyncEngine: ${list.listId} 404 on $context '
          '(${state.consecutiveNotFound}/$_notFoundOrphanThreshold) — '
          'backing off before treating the list as gone');
      _scheduleBackoffRetry(list, null);
      return;
    }
    await _markOrphaned(
        list, '$_notFoundOrphanThreshold consecutive 404s on $context');
  }

  int? _parseRetryAfter(dynamic raw) {
    if (raw == null) return null;
    return int.tryParse(raw.toString());
  }

  void _scheduleBackoffRetry(SyncedEntryList list, int? hintSeconds) {
    final state = _stateOf(list.listId);
    final prev = state.backoffSeconds ?? 1;
    var next = hintSeconds ?? (prev * 2);
    if (next > _maxBackoff.inSeconds) next = _maxBackoff.inSeconds;
    state.backoffSeconds = next;
    state.cancelTimer();
    // Dispatch by role at fire time: editable lists retry the /sync
    // flush, subscribers retry the R2 pull. Without the role check a
    // subscriber's retry would hit _flushOps's role guard and silently
    // do nothing, leaving the list stale until the next full syncAll.
    state.debounceTimer = Timer(Duration(seconds: next), () {
      final current = _manager.get(list.listId);
      if (current == null) return;
      if (_isEditableRole(current.meta.role)) {
        _flushOps(list.listId);
      } else {
        _pullSubscribed(list.listId);
      }
    });
  }

  Future<void> _markOrphaned(SyncedEntryList list, String reason) async {
    // Pending ops are unrecoverable either way — the server has removed the
    // list, so there's no destination for them.
    list.meta.pendingOps.clear();
    _clearListState(list.listId);

    if (_isEditableRole(list.meta.role)) {
      // A list the user owns or edits whose share has gone from the server is
      // a dead end — there's nothing left to sync, and leaving a "deleted by
      // you" mirror around is just a zombie the user can't easily remove. So
      // drop the share instead of orphaning it. `removeLocal` does the right
      // thing per role: for an owner it keeps the underlying local source list
      // (the user's own data, which predates the share) so it reverts to a
      // plain local list; for an editor it deletes the local mirror entirely
      // (it was only ever a copy of someone else's list).
      printAndLog('SyncEngine: ${list.listId} $reason — '
          'share gone, dropping ${list.meta.role.name} mirror');
      try {
        await _manager.removeLocal(list.listId);
      } catch (e) {
        printAndLog('SyncEngine: removeLocal ${list.listId} failed: $e');
      }
      sharing.bumpState();
      return;
    }

    // Subscriber: keep a read-only snapshot flagged "deleted by its owner" so
    // the user doesn't lose the signs they were following; they can unsubscribe
    // to remove it.
    printAndLog('SyncEngine: ${list.listId} $reason — marking orphaned');
    list.meta.orphaned = true;
    try {
      await list.writeMeta();
    } catch (e) {
      printAndLog('SyncEngine: writeMeta ${list.listId} failed: $e');
    }
    sharing.bumpState();
  }

  // -------- Subscriber: R2 poll --------

  Future<void> _pullSubscribed(String listId) {
    return _stateOf(listId).lock.synchronized(() async {
      final local = _manager.get(listId);
      if (local == null) return;
      if (local.meta.orphaned) return;
      // For demoted-editor refresh, role is now subscriber even though
      // the local payload key is still the editor mirror's. That's
      // fine — `replaceEntriesFromServer` operates on the wrapper's
      // entries set, which is the right thing in either case.
      try {
        final result =
            await _api.getList(local.listId, ifNoneMatch: local.meta.etag);
        final state = _stateOf(listId);
        state.backoffSeconds = null;
        state.consecutiveNotFound = 0;
        if (result is FetchNotModified) {
          local.meta.lastSyncedAt = _nowSecs();
          await local.writeMeta();
          sharing.bumpState();
          return;
        }
        final ok = result as FetchOk;
        local.replaceEntriesFromServer(ok.list.entries);
        local.meta.displayName = ok.list.displayName;
        local.meta.etag = ok.etag;
        local.meta.lastKnownSeq = ok.list.lastSeq;
        local.meta.lastSyncedAt = _nowSecs();
        local.meta.serverUpdatedAt = ok.serverUpdatedAt;
        try {
          await local.writeAllAfterServerAck();
        } catch (e) {
          printAndLog('SyncEngine: writeAll ${local.listId} failed: $e');
        }
        sharing.bumpState();
      } on SyncException catch (e) {
        if (e.kind == SyncErrorKind.notFound || e.kind == SyncErrorKind.gone) {
          // A fresh subscriber pull can transiently 404 (R2 propagation
          // right after publish), so 404s go through the same
          // threshold-and-backoff treatment as the sync path.
          await _handleNotFoundOrGone(local, e.kind, 'pull');
          return;
        }
        printAndLog('SyncEngine: pull ${local.listId} error: $e');
      }
    });
  }

  // -------- Public lifecycle API --------

  /// Create a new owned list and publish it.
  Future<SyncedEntryList> createOwned({
    required String displayName,
    required EntryList source,
    required String sessionToken,
  }) async {
    final entries = source.savedVideos.toList();
    CreateResult result;
    String listId;
    var attempt = 0;
    while (true) {
      listId = generateListId();
      attempt++;
      try {
        result = await _api.createList(
          listId: listId,
          displayName: displayName,
          entries: entries,
          sessionToken: sessionToken,
        );
        break;
      } on SyncException catch (e) {
        if (e.kind == SyncErrorKind.idCollision &&
            attempt < _createKeyMaxAttempts) {
          printAndLog(
              'SyncEngine: key collision on $listId, retrying with a new key');
          continue;
        }
        rethrow;
      }
    }
    final list = SyncedEntryList.owner(
      meta: SyncedListMeta(
        listId: result.listId,
        displayName: displayName,
        role: ListRole.owner,
        lastKnownSeq: result.lastSeq,
        etag: null,
        lastSyncedAt: _nowSecs(),
        serverUpdatedAt: result.updatedAt,
        orphaned: false,
        sourceLocalKey: source.key,
      ),
      source: source,
    );
    await _manager.insert(list);
    return list;
  }

  /// Subscribe to a shared list by key.
  ///
  /// If a list with this id is already on the device:
  ///   - As an owner or editor → run a sync to catch any cross-device updates.
  ///   - As a subscriber → pull to refresh.
  Future<SyncedEntryList?> subscribe(String listId) async {
    // Fast path: already on the device. Defer to per-list sync — those
    // helpers take the per-list lock themselves, so re-entering through
    // `lock.synchronized` here would deadlock.
    final existing = _manager.get(listId);
    if (existing != null) {
      if (_isEditableRole(existing.meta.role)) {
        await _flushOps(listId);
      } else {
        await _pullSubscribed(listId);
      }
      // The list may have been orphaned mid-call; return whatever's
      // current rather than asserting it's still there.
      return _manager.get(listId);
    }
    // Fresh fetch: hold the per-list lock across the network call AND
    // the manager.insert so two near-simultaneous subscribes (e.g. the
    // user tapping a share link twice in quick succession) don't both
    // GET + insert, with second-write-wins on the manager map.
    return _stateOf(listId).lock.synchronized(() async {
      // Re-check after acquiring: another caller may have inserted
      // while we were queued behind their lock body.
      final reChecked = _manager.get(listId);
      if (reChecked != null) return reChecked;
      final result = await _api.getList(listId);
      if (result is! FetchOk) {
        throw SyncException(
            SyncErrorKind.server, 'unexpected 304 on fresh fetch');
      }
      final remote = result.list;
      final list = SyncedEntryList.subscriber(
        meta: SyncedListMeta(
          listId: remote.listId,
          displayName: remote.displayName,
          role: ListRole.subscriber,
          lastKnownSeq: remote.lastSeq,
          etag: result.etag,
          lastSyncedAt: _nowSecs(),
          serverUpdatedAt: result.serverUpdatedAt,
          orphaned: false,
        ),
        savedVideos: _hydrateSavedVideos(remote.entries),
      );
      await _manager.insert(list);
      return list;
    });
  }

  /// Accept an invite — adds the caller to the list's editors and
  /// installs an editor-mode mirror locally.
  ///
  /// Held under the per-list lock so the network round-trip and the
  /// follow-up manager mutation can't interleave with a concurrent
  /// flush / subscribe for the same listId. The server enforces
  /// single-use on the invite token itself; the lock here is purely
  /// about local-state coherence.
  Future<SyncedEntryList> acceptInvite({
    required String listId,
    required String token,
  }) async {
    final session = _auth.store.current;
    if (session == null) {
      throw StateError('acceptInvite: no current session');
    }
    return _stateOf(listId).lock.synchronized(() async {
      final snapshot = await _api.acceptInvite(
          listId: listId, token: token, sessionToken: session.sessionToken);

      final existing = _manager.get(listId);
      if (existing != null && _isEditableRole(existing.meta.role)) {
        // Already an owner or editor — refresh meta and keep any queued
        // local ops + existing mirror. Clear the orphaned flag too: a
        // re-accept of an invite to a list that was orphaned locally
        // (e.g. server transiently 404'd and we got back-online with
        // a fresh invite) should restore sync, not leave the engine's
        // `if (orphaned) return` guard tripped forever.
        existing.meta.cachedMembers = snapshot.members;
        existing.meta.lastKnownSeq = snapshot.lastSeq;
        existing.meta.displayName = snapshot.displayName;
        existing.meta.orphaned = false;
        await existing.writeMeta();
        sharing.bumpState();
        return existing;
      }
      // Was a subscriber — replace the read-only mirror with an
      // editor-mode one. No pending ops can exist on a subscriber.
      if (existing != null) {
        await _manager.removeLocal(listId);
      }
      final editorList = SyncedEntryList.editor(
        meta: SyncedListMeta(
          listId: snapshot.listId,
          displayName: snapshot.displayName,
          role: ListRole.editor,
          lastKnownSeq: snapshot.lastSeq,
          etag: null,
          lastSyncedAt: _nowSecs(),
          serverUpdatedAt: snapshot.updatedAt,
          orphaned: false,
          cachedMembers: snapshot.members,
        ),
        savedVideos: _hydrateSavedVideos(snapshot.entries),
      );
      await _manager.insert(editorList);
      return editorList;
    });
  }

  /// Owner-only: mint an invite token to share with a prospective
  /// editor.
  Future<InviteTokenResult> createInvite(String listId) async {
    final list = _manager.get(listId);
    if (list == null || list.meta.role != ListRole.owner) {
      throw StateError('createInvite: $listId is not owner-role');
    }
    final session = _auth.store.current;
    if (session == null) {
      throw StateError('createInvite: no current session');
    }
    return _api.createInvite(
        listId: listId, sessionToken: session.sessionToken);
  }

  /// Owner-only: remove an editor by user id.
  Future<void> removeEditor(String listId, String userId) async {
    final session = _auth.store.current;
    if (session == null) {
      throw StateError('removeEditor: no current session');
    }
    await _api.removeEditor(
        listId: listId, userIdOrMe: userId, sessionToken: session.sessionToken);
    await _flushOps(listId);
  }

  /// Editor self-leave. Removes from the list's editors server-side
  /// and drops the local mirror.
  Future<void> leaveAsEditor(String listId) async {
    final list = _manager.get(listId);
    if (list == null || list.meta.role != ListRole.editor) return;
    final session = _auth.store.current;
    if (session != null) {
      try {
        await _api.removeEditor(
            listId: listId,
            userIdOrMe: 'me',
            sessionToken: session.sessionToken);
      } on SyncException catch (e) {
        const ignorable = {
          SyncErrorKind.notFound,
          SyncErrorKind.gone,
          SyncErrorKind.forbidden,
        };
        if (!ignorable.contains(e.kind)) rethrow;
      }
    }
    _clearListState(listId);
    await _manager.removeLocal(listId);
    // Notify listeners (e.g. the lists overview / "Shared with me" tab) so
    // the list we just left disappears immediately instead of lingering
    // until the next rebuild.
    sharing.bumpState();
  }

  /// Owner-only: rename a shared list. PUTs the new display name to the
  /// server, then adopts the authoritative name + cursor from the
  /// returned snapshot. Editors pick the new name up on their next
  /// /sync (it's echoed in the response); subscribers on their next R2
  /// poll. Held under the per-list lock so it can't interleave with a
  /// concurrent flush for the same list.
  Future<void> renameOwned(
      String listId, String displayName, String sessionToken) async {
    final list = _manager.get(listId);
    if (list == null || list.meta.role != ListRole.owner) {
      throw StateError('renameOwned: $listId is not owner-role');
    }
    await _stateOf(listId).lock.synchronized(() async {
      final snapshot = await _api.renameList(
          listId: listId, displayName: displayName, sessionToken: sessionToken);
      final current = _manager.get(listId);
      if (current == null) return;
      current.meta.displayName = snapshot.displayName;
      current.meta.serverUpdatedAt = snapshot.updatedAt;
      current.meta.lastKnownSeq = snapshot.lastSeq;
      current.meta.cachedMembers = snapshot.members;
      await current.writeMeta();
      sharing.bumpState();
    });
  }

  /// Stop sharing as owner — delete on the server, remove locally.
  Future<void> unshare(String listId) async {
    final list = _manager.get(listId);
    if (list == null || list.meta.role != ListRole.owner) return;
    final session = _auth.store.current;
    if (session != null) {
      try {
        await _api.deleteList(
            listId: listId, sessionToken: session.sessionToken);
      } on SyncException catch (e) {
        const ignorable = {
          SyncErrorKind.notFound,
          SyncErrorKind.gone,
          SyncErrorKind.forbidden,
        };
        if (!ignorable.contains(e.kind)) rethrow;
      }
    }
    _clearListState(listId);
    await _manager.removeLocal(listId);
  }

  /// Single-list subscriber refresh.
  Future<void> refreshSubscriber(String listId) async {
    final list = _manager.get(listId);
    if (list == null || list.meta.role != ListRole.subscriber) return;
    await _pullSubscribed(listId);
  }

  /// Force a full sync of a single shared list, whatever the viewer's
  /// role — drives the pull-to-refresh on the shared-list and members
  /// pages.
  ///
  /// Owner/editor lists go through /sync. Even with an empty op queue
  /// this is a pull: it folds in other editors' missedOps and refreshes
  /// the member directory (`meta.cachedMembers`), so a co-editor who was
  /// just added via an invite shows up immediately instead of only after
  /// an app restart. Subscribers re-pull the public payload from R2.
  Future<void> refreshList(String listId) async {
    final list = _manager.get(listId);
    if (list == null) return;
    if (_isEditableRole(list.meta.role)) {
      await _flushAndDrain(listId);
    } else {
      await _pullSubscribed(listId);
    }
  }

  /// Subscriber stops following. Server-side state untouched.
  Future<void> unsubscribe(String listId) async {
    final list = _manager.get(listId);
    if (list == null || list.meta.role != ListRole.subscriber) return;
    _clearListState(listId);
    await _manager.removeLocal(listId);
  }

  /// Drop every list's pending-op queue and cancel pending flushes.
  /// Called from [Sharing.signOut] so a follow-up sign-in by a
  /// different account can't push the previous user's queued edits
  /// under the new identity. The local entries-set on each list is
  /// untouched — only the queue and the engine's per-list timers are.
  Future<void> clearAllPendingOps() async {
    final writes = <Future<void>>[];
    for (final list in _manager.editableLists) {
      if (list.meta.pendingOps.isEmpty) continue;
      list.meta.pendingOps.clear();
      _clearListState(list.listId);
      writes.add(list.writeMeta().catchError((e) => printAndLog(
          'SyncEngine: clearAllPendingOps writeMeta ${list.listId} failed: $e')));
    }
    await Future.wait(writes);
    sharing.bumpState();
  }

  int _nowSecs() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

  LinkedHashSet<SavedVideo> _hydrateSavedVideos(List<SavedVideo> entries) {
    // LinkedHashSet preserves first-occurrence insertion order; the
    // server payload is already insertion-ordered (per
    // entries.position), so this just carries that ordering forward
    // into the local mirror.
    return LinkedHashSet<SavedVideo>.from(entries);
  }
}
