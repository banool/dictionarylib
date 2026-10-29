import 'dart:async';

import 'package:flutter/widgets.dart';

import '../common.dart';
import 'account_sync.dart';
import 'auth/auth_api.dart';
import 'auth/auth_service.dart';
import 'auth/auth_store.dart';
import 'deep_link_handler.dart';
import 'sharing_config.dart';
import 'sync_api.dart';
import 'sync_engine.dart';
import 'synced_entry_list.dart';

/// Container for the runtime sharing state — the config the app was set up
/// with, the API client, the synced-list manager, the sync engine, the
/// auth subsystem, and the deep-link handler. Either all of these exist
/// or none of them do; that's the [Sharing] facade's reason for existing
/// instead of independently nullable globals.
///
/// Constructed once via [Sharing.setup] from `main()`. Apps that don't
/// want sharing leave `setupSharing` uncalled — the global is
/// pre-populated with [Sharing.disabled] so consumers can always reach
/// `sharing.engine` / `sharing.lists` / `sharing.auth` without
/// null-checks. The dummy collaborators operate on empty state, so
/// every read returns nothing and every network-bound mutation is a
/// no-op. UI gates that should hide sharing UI entirely (the "Shared
/// with me" tab, share buttons) check [isEnabled] instead.
///
/// The instance is stored at [globals.sharing].
class Sharing with ChangeNotifier {
  final SharingConfig config;
  final SyncApi api;
  final SyncedEntryListManager lists;
  final SyncEngine engine;
  final AuthService auth;
  final DeepLinkHandler deepLinks;

  /// Account sync: all of a signed-in person's lists, follows and progress
  /// on every device. Inert in [Sharing.disabled].
  final AccountSyncController accountSync;

  /// True when the app actually wired sharing in (called
  /// [setupSharing]). False for the [Sharing.disabled] sentinel so
  /// UI gates can hide sharing surfaces without inspecting individual
  /// collaborator state.
  final bool isEnabled;

  /// Installed in [setup] (skipped under [Sharing.forTesting]) — fires
  /// [SyncEngine.pushAllDirty] on `AppLifecycleState.paused` so any
  /// queued edits land before the OS suspends. Lives here rather than
  /// in a per-page widget so it runs regardless of which screen is
  /// visible when backgrounding happens.
  _SharingLifecycleObserver? _lifecycle;

  Sharing._({
    required this.config,
    required this.api,
    required this.lists,
    required this.engine,
    required this.auth,
    required this.deepLinks,
    this.isEnabled = true,
    bool accountSyncEnabled = true,
  }) : accountSync = AccountSyncController(
         api: api,
         auth: auth,
         engine: engine,
         lists: lists,
         enabled: isEnabled && accountSyncEnabled,
       ) {
    // Surface auth changes through the same [bumpState] channel as
    // sync changes — UI components only need to listen to [Sharing]
    // itself, not to AuthStore separately.
    auth.store.addListener(bumpState);
    _lastSessionToken = auth.store.current?.sessionToken;
    auth.store.addListener(_onAuthChanged);
  }

  String? _lastSessionToken;

  /// Signing in is syncing (decision 1): a new session, whichever screen
  /// signed in, starts a cycle at once (the merge, the first time).
  void _onAuthChanged() {
    final token = auth.store.current?.sessionToken;
    if (token != null && token != _lastSessionToken) {
      unawaited(accountSync.kick(SyncReason.signedIn));
    }
    _lastSessionToken = token;
  }

  /// Inert sentinel used as the initial value of `globals.sharing` so
  /// callers can always reach into `sharing.engine` / `sharing.lists`
  /// without null-checks. Every collection is empty and any
  /// network-bound action is a no-op (no session is loaded; nothing
  /// calls `deepLinks.start()`; the lifecycle observer is not
  /// installed). UI bits that want to hide sharing affordances when
  /// the app didn't configure sharing should branch on
  /// [Sharing.isEnabled].
  factory Sharing.disabled() {
    const dummyConfig = SharingConfig(
      appId: '',
      apiBaseUrl: '',
      shareLinkBaseUrl: '',
      shareLinkHost: '',
      urlScheme: '',
      appName: '',
      auth: SharingAuthConfig(appleBundleId: '', googleServerClientId: ''),
    );
    final api = SyncApi(dummyConfig);
    final authApi = AuthApi(dummyConfig);
    final authStore = AuthStore.withSession(null);
    final auth = AuthService(
      config: dummyConfig,
      api: authApi,
      store: authStore,
    );
    final lists = SyncedEntryListManager({});
    final engine = SyncEngine(api: api, manager: lists, auth: auth);
    final deepLinks = DeepLinkHandler(config: dummyConfig);
    return Sharing._(
      config: dummyConfig,
      api: api,
      lists: lists,
      engine: engine,
      auth: auth,
      deepLinks: deepLinks,
      isEnabled: false,
    );
  }

  /// Fire the change notifier. The engine, [ListsService], and the
  /// auth store all funnel through here so UI bits like the "pending
  /// sync" badge or the "signed in as `<Provider>`" indicator rebuild
  /// without manual setState.
  void bumpState() => notifyListeners();

  /// Stream of one-shot UI notifications from the engine (session
  /// expired, editor demoted, etc.). Convenience pass-through so UI
  /// consumers don't have to reach into `sharing.engine.notifications`.
  Stream<SyncNotification> get engineNotifications => engine.notifications;

  /// Sign the current user out. First makes a best-effort, time-boxed
  /// attempt to push any queued edits — the session is still valid at
  /// this point, so flushing here is safe and means a routine sign-out
  /// doesn't silently discard offline work. Whatever fails to land
  /// (offline, server down) is then dropped: the queue must not survive
  /// into a different account's session, because a follow-up sign-in by
  /// someone else would push the previous user's edits under the new
  /// identity. Finally the account-bound list mirrors (owned + editor)
  /// are dropped so the next account doesn't inherit them. Anonymous
  /// subscriptions, and the underlying local lists that owner mirrors
  /// wrap, are kept.
  ///
  /// Call this instead of `auth.signOut()` directly. The latter is
  /// reserved for the engine's own 401-handling path
  /// ([SyncEngine._handleSyncError]) which already protects the queue
  /// (it preserves pending ops across an expiry so the next sign-in
  /// by the same user resumes the flush).
  ///
  /// With account sync this also flushes the account's queued ops, then
  /// drops the account state and the unsent-answers queue (section 5.9 of
  /// the plan). Every local list keeps its signs and the revision history
  /// stays; nothing on the server changes.
  Future<void> signOut() async {
    try {
      await engine.pushAllDirty().timeout(const Duration(seconds: 10));
    } catch (e) {
      printAndLog('Sharing.signOut: best-effort flush failed: $e');
    }
    // Flushes the account queue (10 s at most), then clears pending ops,
    // the owner and editor wrappers and the account state.
    await accountSync.signOutLocally();
    await engine.clearAllPendingOps();
    await auth.signOut();
    // Drop account-bound list mirrors (owned + editor) so the next account to
    // sign in doesn't inherit the previous user's lists. Subscriptions are
    // anonymous public reads, so they stay.
    await lists.clearEditableLists();
    bumpState();
  }

  /// Permanently delete the signed-in user's account: every list they own
  /// and their editor access to others' lists are removed on the server
  /// (along with the display name we store), then all local sharing state
  /// on this device is cleared — pending ops, the session, and every
  /// synced list mirror (subscriptions included; re-subscribe is one tap).
  ///
  /// Throws if the server call fails, leaving the local session intact so
  /// the user can retry. On success there's nothing left to manage.
  Future<void> deleteAccount() async {
    await engine.clearAllPendingOps();
    await auth.deleteAccount();
    // The owned + editor lists are gone on the server; drop their local
    // mirrors and the account state (no flush: there's nothing to flush to).
    // The local lists keep their signs. Subscriptions to other people's
    // lists are anonymous and stay.
    await accountSync.signOutLocally(flush: false);
    await lists.clearEditableLists();
    bumpState();
  }

  /// Construct the subsystem, load the persisted auth session, start
  /// the deep-link listener, and install the lifecycle observer.
  /// Idempotent at the call-site via the `!sharing.isEnabled` assert in
  /// `setupSharing` — calling this method itself twice would install
  /// two lifecycle observers.
  static Future<Sharing> setup(SharingConfig config) async {
    final api = SyncApi(config);
    final authApi = AuthApi(config);
    final authStore = AuthStore();
    final auth = AuthService(config: config, api: authApi, store: authStore);
    final deepLinks = DeepLinkHandler(config: config);
    await Future.wait([authStore.load(), deepLinks.start()]);
    // All the waiting is done before the user's lists are looked at, and
    // nothing may wait between here and the return. The synced-list manager
    // takes hold of the list objects it finds, and those are only safe from
    // being rebuilt underneath it (see EntryLoader.setEntriesGlobal) once the
    // caller has published this instance as `sharing`. A wait in between is
    // a window for a background dictionary refresh to land in, leaving every
    // share made from this device wrapping lists that nothing else reads.
    final lists = SyncedEntryListManager.fromStartup();
    final engine = SyncEngine(api: api, manager: lists, auth: auth);
    final instance = Sharing._(
      config: config,
      api: api,
      lists: lists,
      engine: engine,
      auth: auth,
      deepLinks: deepLinks,
    );
    instance._installLifecycleObserver();
    return instance;
  }

  void _installLifecycleObserver() {
    final observer = _SharingLifecycleObserver(engine, accountSync);
    _lifecycle = observer;
    WidgetsBinding.instance.addObserver(observer);
  }

  /// Test-only constructor. Lets tests wire up a [Sharing] with
  /// already-built collaborators (typically backed by `MockClient`s and
  /// a pre-populated [SyncedEntryListManager]), without spinning up the
  /// deep-link listener or hitting secure storage. Skips the lifecycle
  /// observer install too — tests drive `engine.pushAllDirty()` directly.
  @visibleForTesting
  factory Sharing.forTesting({
    required SharingConfig config,
    required SyncApi api,
    required SyncedEntryListManager lists,
    required AuthService auth,
    SyncEngine? engine,
    DeepLinkHandler? deepLinks,
    bool accountSyncEnabled = true,
  }) {
    return Sharing._(
      config: config,
      api: api,
      lists: lists,
      engine: engine ?? SyncEngine(api: api, manager: lists, auth: auth),
      auth: auth,
      deepLinks: deepLinks ?? DeepLinkHandler(config: config),
      accountSyncEnabled: accountSyncEnabled,
    );
  }

  @override
  void dispose() {
    final observer = _lifecycle;
    if (observer != null) {
      WidgetsBinding.instance.removeObserver(observer);
      _lifecycle = null;
    }
    auth.store.removeListener(bumpState);
    auth.store.removeListener(_onAuthChanged);
    accountSync.dispose();
    auth.dispose();
    engine.dispose();
    deepLinks.dispose();
    super.dispose();
  }
}

class _SharingLifecycleObserver with WidgetsBindingObserver {
  final SyncEngine _engine;
  final AccountSyncController _accountSync;
  _SharingLifecycleObserver(this._engine, this._accountSync);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // Fire-and-forget: the OS only gives us best-effort time on
      // pause. The engine awaits per-list locks internally so the
      // serialisation is correct even if we don't await here.
      unawaited(_engine.pushAllDirty());
      unawaited(_accountSync.kick(SyncReason.paused));
    } else if (state == AppLifecycleState.resumed) {
      unawaited(_accountSync.kick(SyncReason.resumed));
    }
  }
}
