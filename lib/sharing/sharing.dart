import 'dart:async';

import 'package:flutter/widgets.dart';

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
  }) {
    // Surface auth changes through the same [bumpState] channel as
    // sync changes — UI components only need to listen to [Sharing]
    // itself, not to AuthStore separately.
    auth.store.addListener(bumpState);
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
      auth: SharingAuthConfig(
        appleBundleId: '',
        googleServerClientId: '',
        facebookAppId: '',
      ),
    );
    final api = SyncApi(dummyConfig);
    final authApi = AuthApi(dummyConfig);
    final authStore = AuthStore.withSession(null);
    final auth = AuthService(config: dummyConfig, api: authApi, store: authStore);
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

  /// Sign the current user out: drop every list's pending-op queue (so a
  /// follow-up sign-in by a different account can't push the previous user's
  /// queued edits under the new identity), then drop the account-bound list
  /// mirrors (owned + editor) so the new account doesn't inherit the previous
  /// user's lists. Anonymous subscriptions, and the underlying local lists
  /// that owner mirrors wrap, are kept.
  ///
  /// Call this instead of `auth.signOut()` directly. The latter is
  /// reserved for the engine's own 401-handling path
  /// ([SyncEngine._handleSyncError]) which already protects the queue
  /// (it preserves pending ops across an expiry so the next sign-in
  /// by the same user resumes the flush).
  Future<void> signOut() async {
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
    // mirrors. Subscriptions to other people's lists are anonymous and stay.
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
    final lists = SyncedEntryListManager.fromStartup();
    final engine = SyncEngine(api: api, manager: lists, auth: auth);
    final deepLinks = DeepLinkHandler(config: config);
    await Future.wait([
      authStore.load(),
      deepLinks.start(),
    ]);
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
    final observer = _SharingLifecycleObserver(engine);
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
  }) {
    return Sharing._(
      config: config,
      api: api,
      lists: lists,
      engine: engine ?? SyncEngine(api: api, manager: lists, auth: auth),
      auth: auth,
      deepLinks: deepLinks ?? DeepLinkHandler(config: config),
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
    auth.dispose();
    engine.dispose();
    deepLinks.dispose();
    super.dispose();
  }
}

class _SharingLifecycleObserver with WidgetsBindingObserver {
  final SyncEngine _engine;
  _SharingLifecycleObserver(this._engine);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // Fire-and-forget: the OS only gives us best-effort time on
      // pause. The engine awaits per-list locks internally so the
      // serialisation is correct even if we don't await here.
      unawaited(_engine.pushAllDirty());
    }
  }
}
