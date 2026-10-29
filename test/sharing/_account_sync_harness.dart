import 'package:dictionarylib/entry_list.dart';
import 'package:dictionarylib/globals.dart';
import 'package:dictionarylib/saved_video.dart';
import 'package:dictionarylib/sharing/account_sync.dart';
import 'package:dictionarylib/sharing/auth/auth_api.dart';
import 'package:dictionarylib/sharing/auth/auth_service.dart';
import 'package:dictionarylib/sharing/auth/auth_store.dart';
import 'package:dictionarylib/sharing/sharing.dart';
import 'package:dictionarylib/sharing/sharing_config.dart';
import 'package:dictionarylib/sharing/sync_api.dart';
import 'package:dictionarylib/sharing/sync_engine.dart';
import 'package:dictionarylib/sharing/synced_entry_list.dart';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../_helpers.dart';
import '../_recording_prefs.dart';
import '_fake_account_server.dart';

/// A [RecordingPrefsStore] that calls [onWrite] as each write is issued,
/// before it lands: the crash-point tests take a server snapshot there.
class CallbackPrefsStore extends RecordingPrefsStore {
  final void Function() onWrite;
  CallbackPrefsStore(super.values, this.onWrite);

  @override
  Future<bool> setValue(String valueType, String key, Object value) {
    onWrite();
    return super.setValue(valueType, key, value);
  }

  @override
  Future<bool> remove(String key) {
    onWrite();
    return super.remove(key);
  }
}

/// One phone or tablet in an account-sync test. Everything a device has
/// lives in its SharedPreferences (and its session), so a device is a prefs
/// map: [activate] installs it and builds the app's globals from it, as a
/// launch would; [deactivate] puts it away. One device is active at a time.
class TestDevice {
  final FakeAccountServer server;
  final String name;
  Map<String, Object> prefs;
  String? token;
  String? userId;
  RecordingPrefsStore? store;
  final List<AccountSyncNotice> notices = [];

  /// The engine's notifications (snackbars in the app) while active.
  final List<SyncNotification> engineNotices = [];

  /// The server this device talks to: the in-memory one by default.
  final SharingConfig config;
  final http.Client Function() makeClient;
  final Future<String> Function(String userId) mintToken;

  TestDevice(
    this.server,
    this.name, {
    Map<String, Object>? prefs,
    SharingConfig? config,
    http.Client Function()? makeClient,
    Future<String> Function(String userId)? mintToken,
  }) : prefs = prefs ?? {},
       config = config ?? kTestSharingConfig,
       makeClient = makeClient ?? server.client,
       mintToken = mintToken ?? ((u) async => server.signIn(u));

  static TestDevice? _active;

  /// Launch this device (putting away whichever one was running). With
  /// [onWrite], every prefs write is reported as it's issued.
  Future<void> activate({void Function()? onWrite}) async {
    final previous = _active;
    if (previous != null && previous != this) previous.deactivate();
    if (_active == this) return;
    if (onWrite == null) {
      store = await installPrefs(prefs);
    } else {
      final s = CallbackPrefsStore(prefs, onWrite);
      SharedPreferencesStorePlatform.instance = s;
      SharedPreferences.resetStatic();
      sharedPreferences = await SharedPreferences.getInstance();
      store = s;
    }
    resetClientIdCacheForTesting();
    userEntryListManager = UserEntryListManager.fromStartup();
    final client = makeClient();
    final api = SyncApi(config, client: client);
    final authApi = AuthApi(config, client: client);
    final session = token == null
        ? null
        : AuthSession(
            sessionToken: token!,
            provider: AuthProvider.test,
            userId: userId!,
            signedInAtMillis: 1700000000000,
          );
    final auth = AuthService(
      config: config,
      api: authApi,
      store: AuthStore.withSession(session),
    );
    sharing = Sharing.forTesting(
      config: config,
      api: api,
      lists: SyncedEntryListManager.fromStartup(),
      auth: auth,
    );
    sharing.accountSync.notices.listen(notices.add);
    sharing.engineNotifications.listen(engineNotices.add);
    _active = this;
  }

  /// Stop this device, keeping what it stored.
  void deactivate() {
    if (_active != this) return;
    prefs = prefsSnapshot();
    sharing.dispose();
    _active = null;
  }

  /// Sign in as [user] (the sign-in kicks a cycle, as in the app).
  Future<void> signIn(String user) async {
    await activate();
    userId = user;
    token = await mintToken(user);
    await sharing.auth.store.save(
      AuthSession(
        sessionToken: token!,
        provider: AuthProvider.test,
        userId: user,
        signedInAtMillis: 1700000000000,
      ),
    );
  }

  /// Run cycles and flush list queues until nothing is left to do.
  Future<void> settle({int rounds = 4}) async {
    await activate();
    for (var i = 0; i < rounds; i++) {
      await sharing.accountSync.kick(SyncReason.pullToRefresh);
      await sharing.engine.pushAllDirty();
    }
    await sharing.accountSync.kick(SyncReason.pullToRefresh);
  }

  /// Make a local list called [listName] holding [keys] (as a person would,
  /// through ListsService when signed in).
  Future<EntryList> addLocalList(String listName, List<String> keys) async {
    await activate();
    final key = EntryList.getKeyFromName(listName);
    await userEntryListManager.createEntryList(key);
    final list = userEntryListManager.getEntryLists()[key]!;
    for (final k in keys) {
      await list.addVideo(video(k));
    }
    return list;
  }

  /// The local lists as `name → entry keys`, in display order.
  Map<String, List<String>> localLists() => {
    for (final l in userEntryListManager.getEntryLists().values)
      l.getName(): [for (final v in l.savedVideos) v.entryKey],
  };
}

SavedVideo video(String key) =>
    SavedVideo(entryKey: key, mediaPath: videoFor(key));

/// An HTTP client that fails requests [failWhen] picks with a network
/// error, for the real-server tests (the in-memory server has its own
/// fault injection).
class FlakyClient extends http.BaseClient {
  final http.Client inner;
  bool Function(http.BaseRequest req)? failWhen;
  FlakyClient(this.inner);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (failWhen?.call(request) ?? false) {
      throw http.ClientException('flaky: refused', request.url);
    }
    return inner.send(request);
  }
}
