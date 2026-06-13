/// Helpers for the multi-device sync integration suite
/// (`multi_device_sync_test.dart`).
///
/// The model: "device A" is a REAL client stack (SyncApi + AuthService +
/// SyncedEntryListManager + SyncEngine — the exact production classes) talking
/// to a real `wrangler dev` worker over HTTP, while "device B" is a thin raw
/// HTTP client (a Dart port of the bun suite's `Client` in the backend
/// repo's `workers/test/integration/helpers.ts`) acting as a second,
/// independent identity. This sidesteps the process-wide singletons
/// (`sharedPreferences`, `sharing`, the cached client id) that prevent two
/// full Flutter stacks from coexisting in one test process, while still
/// exercising the real client-side reconciliation logic end to end.
///
/// Suite-level config is read from dart-defines, mirroring the bun suite:
///   INTEGRATION_BASE_URL  default http://localhost:8787
///   TEST_AUTH_TOKEN       default the dev-env shared token in wrangler.toml
///
/// Start the server with: bash -c 'cd ../dictionary_backend/workers && bunx wrangler dev --env dev'
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dictionarylib/globals.dart';
import 'package:dictionarylib/sharing/auth/auth_api.dart';
import 'package:dictionarylib/sharing/auth/auth_service.dart';
import 'package:dictionarylib/sharing/auth/auth_store.dart';
import 'package:dictionarylib/sharing/sharing.dart';
import 'package:dictionarylib/sharing/sharing_config.dart';
import 'package:dictionarylib/sharing/sync_api.dart';
import 'package:dictionarylib/sharing/sync_engine.dart';
import 'package:dictionarylib/sharing/synced_entry_list.dart';
import 'package:http/http.dart' as http;

const String kIntegrationBaseUrl = String.fromEnvironment(
    'INTEGRATION_BASE_URL',
    defaultValue: 'http://localhost:8787');

const String kIntegrationTestAuthToken = String.fromEnvironment(
    'TEST_AUTH_TOKEN',
    defaultValue: 'dev-integration-test-token-please-override');

/// Must match the dev env's APP_ID in the backend repo's workers/wrangler.toml.
const String kIntegrationAppId = 'auslan';

/// Sharing config pointing the real client stack at the local worker.
const SharingConfig kIntegrationSharingConfig = SharingConfig(
  appId: kIntegrationAppId,
  appName: 'Integration Test App',
  apiBaseUrl: kIntegrationBaseUrl,
  shareLinkBaseUrl: 'https://share.example.test/l',
  shareLinkHost: 'share.example.test',
  urlScheme: 'auslan',
  auth: SharingAuthConfig(
    appleBundleId: 'com.example.test',
    googleServerClientId: 'test.google.client.id',
    facebookAppId: 'test-fb-app-id',
  ),
);

/// True when a worker is listening at [kIntegrationBaseUrl]. Mirrors the
/// auto-skip behaviour of the bun integration suite so `flutter test` stays
/// green when no server is running.
Future<bool> integrationServerReachable() async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
  try {
    final req =
        await client.getUrl(Uri.parse('$kIntegrationBaseUrl/v1/health'));
    final resp = await req.close().timeout(const Duration(seconds: 3));
    await resp.drain<void>();
    return resp.statusCode == 200;
  } catch (_) {
    return false;
  } finally {
    client.close(force: true);
  }
}

final Random _rand = Random.secure();

String _randomHex(int byteCount) {
  const hex = '0123456789abcdef';
  final buf = StringBuffer();
  for (var i = 0; i < byteCount * 2; i++) {
    buf.write(hex[_rand.nextInt(16)]);
  }
  return buf.toString();
}

/// Random `test:<slug>` user id — the test provider only accepts ids in this
/// namespace, and randomness keeps parallel test runs from colliding.
String randomTestUserId([String prefix = 'test:int-dart']) =>
    '$prefix-${_randomHex(4)}';

/// Deterministic video URL for an entry key, matching the convention used by
/// the bun suite and `test/_helpers.dart`.
String integrationVideoFor(String key) => 'https://example.test/$key.mp4';

/// Sign in via the worker's test provider and return the minted session.
Future<AuthSession> signInTestUser(
    {String? userId, String displayName = 'Dart Integration User'}) async {
  final resp = await http.post(
    Uri.parse('$kIntegrationBaseUrl/v1/auth/sign-in'),
    headers: {
      'x-app-id': kIntegrationAppId,
      'content-type': 'application/json',
    },
    body: jsonEncode({
      'provider': 'test',
      'testAuthToken': kIntegrationTestAuthToken,
      'userId': userId ?? randomTestUserId(),
      'displayName': displayName,
    }),
  );
  if (resp.statusCode != 200) {
    throw StateError(
        'test sign-in failed: HTTP ${resp.statusCode} ${resp.body}');
  }
  final json = jsonDecode(resp.body) as Map<String, dynamic>;
  return AuthSession(
    sessionToken: json['sessionToken'] as String,
    // The provider enum value is irrelevant to the engine; apple stands in.
    provider: AuthProvider.apple,
    displayName: json['displayName'] as String? ?? displayName,
    signedInAtMillis: DateTime.now().millisecondsSinceEpoch,
  );
}

/// Best-effort wipe of all test-user data on the dev worker. Call from
/// tearDownAll; failures are swallowed (the worker self-heals via random ids).
Future<void> wipeTestData() async {
  try {
    await http.post(
      Uri.parse('$kIntegrationBaseUrl/v1/test/wipe'),
      headers: {
        'x-app-id': kIntegrationAppId,
        'x-test-auth-token': kIntegrationTestAuthToken,
      },
    ).timeout(const Duration(seconds: 10));
  } catch (_) {/* best effort */}
}

/// The full real-client stack for "device A". All collaborators are the
/// production classes; only the secure-storage channel and SharedPreferences
/// are test fakes (installed by the caller's setUp).
class RealDeviceStack {
  final SyncEngine engine;
  final SyncedEntryListManager manager;
  final AuthService auth;
  final Sharing sharingInstance;

  RealDeviceStack._(this.engine, this.manager, this.auth, this.sharingInstance);

  /// Build the stack and install it as the global `sharing` so wrapper
  /// mutations (SyncedEntryList.addVideo → sharing.engine) route here.
  factory RealDeviceStack.install(AuthSession session) {
    final api = SyncApi(kIntegrationSharingConfig);
    final authApi = AuthApi(kIntegrationSharingConfig);
    final store = AuthStore.withSession(session);
    final auth = AuthService(
        config: kIntegrationSharingConfig, api: authApi, store: store);
    final manager = SyncedEntryListManager.fromStartup();
    final engine = SyncEngine(api: api, manager: manager, auth: auth);
    final sharingInstance = Sharing.forTesting(
      config: kIntegrationSharingConfig,
      api: api,
      lists: manager,
      auth: auth,
      engine: engine,
    );
    sharing = sharingInstance;
    return RealDeviceStack._(engine, manager, auth, sharingInstance);
  }

  void dispose() {
    // Cancels per-list debounce/backoff timers so nothing fires after the
    // test completes. Disposing Sharing would also close the API client.
    engine.dispose();
  }
}

/// Typed view of the worker's GET /v1/lists/:id/state response — just the
/// fields the suite asserts on. Decoding happens once, in
/// [HttpDevice.state], so tests stay free of raw-JSON casts.
class ServerListState {
  final String displayName;

  /// Entry keys in server position order.
  final List<String> entryKeys;

  /// Canonical user id (`provider:sub`) of the owner.
  final String ownerUserId;

  /// Canonical user ids of the editors.
  final List<String> editorUserIds;

  final int lastSeq;

  const ServerListState({
    required this.displayName,
    required this.entryKeys,
    required this.ownerUserId,
    required this.editorUserIds,
    required this.lastSeq,
  });

  factory ServerListState.fromJson(Map<String, dynamic> json) {
    final members = json['members'] as Map<String, dynamic>;
    return ServerListState(
      displayName: json['displayName'] as String,
      entryKeys: [
        for (final e in json['entries'] as List<dynamic>)
          (e as Map<String, dynamic>)['entry'] as String,
      ],
      ownerUserId:
          (members['owner'] as Map<String, dynamic>)['userId'] as String,
      editorUserIds: [
        for (final e in members['editors'] as List<dynamic>)
          (e as Map<String, dynamic>)['userId'] as String,
      ],
      lastSeq: json['lastSeq'] as int,
    );
  }
}

/// "Device B": a second identity speaking raw HTTP to the worker, with its
/// own session token, client id, and per-list cursor. Mirrors the bun
/// integration suite's `Client` helper.
class HttpDevice {
  final AuthSession session;
  final String clientId = _randomHex(8);
  final Map<String, int> _cursor = {};

  HttpDevice(this.session);

  static Future<HttpDevice> signIn(
      {String? userId, String? displayName}) async {
    return HttpDevice(await signInTestUser(
        userId: userId, displayName: displayName ?? 'Device B'));
  }

  Map<String, String> _headers({bool json = false}) => {
        'x-app-id': kIntegrationAppId,
        'authorization': 'Bearer ${session.sessionToken}',
        if (json) 'content-type': 'application/json',
      };

  Uri _u(String path) => Uri.parse('$kIntegrationBaseUrl$path');

  /// POST /v1/lists — create a list owned by this device.
  Future<String> createList({
    required String displayName,
    List<Map<String, String>> entries = const [],
  }) async {
    final listId = _randomBase32(12);
    final resp = await http.post(
      _u('/v1/lists'),
      headers: _headers(json: true),
      body: jsonEncode({
        'listId': listId,
        'displayName': displayName,
        'entries': entries,
        'schemaVersion': 3,
      }),
    );
    _expect(resp, 201, 'createList');
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    _cursor[listId] = body['lastSeq'] as int;
    return listId;
  }

  /// POST /v1/lists/:id/invites — owner-only invite mint.
  Future<String> createInvite(String listId) async {
    final resp =
        await http.post(_u('/v1/lists/$listId/invites'), headers: _headers());
    _expect(resp, 200, 'createInvite');
    return (jsonDecode(resp.body) as Map<String, dynamic>)['token'] as String;
  }

  /// POST /v1/lists/:id/accept-invite.
  Future<void> acceptInvite(String listId, String token) async {
    final resp = await http.post(
      _u('/v1/lists/$listId/accept-invite'),
      headers: _headers(json: true),
      body: jsonEncode({'token': token}),
    );
    _expect(resp, 200, 'acceptInvite');
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    _cursor[listId] = body['lastSeq'] as int;
  }

  /// POST /v1/lists/:id/sync with add/remove ops built from short specs of
  /// the form 'add:key' / 'remove:key'. Tracks this device's cursor and
  /// returns the applied sequence number.
  Future<int> sync(String listId, List<String> specs) async {
    final ops = [
      for (final spec in specs)
        () {
          final parts = spec.split(':');
          final key = parts[1];
          return {
            'opId': _randomHex(8),
            'type': parts[0] == 'add' ? 'addEntry' : 'removeEntry',
            'args': {'entry': key, 'video': integrationVideoFor(key)},
            'clientTs': DateTime.now().millisecondsSinceEpoch ~/ 1000,
          };
        }(),
    ];
    final resp = await http.post(
      _u('/v1/lists/$listId/sync'),
      headers: {..._headers(json: true), 'x-client-id': clientId},
      body: jsonEncode({'lastKnownSeq': _cursor[listId] ?? 0, 'ops': ops}),
    );
    _expect(resp, 200, 'sync');
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    final appliedSeq = body['appliedSeq'] as int;
    _cursor[listId] = appliedSeq;
    return appliedSeq;
  }

  /// GET /v1/lists/:id/state — authenticated snapshot (members included).
  Future<ServerListState> state(String listId) async {
    final resp =
        await http.get(_u('/v1/lists/$listId/state'), headers: _headers());
    _expect(resp, 200, 'state');
    return ServerListState.fromJson(
        jsonDecode(resp.body) as Map<String, dynamic>);
  }

  /// Entry keys currently in the list per the server, in position order.
  Future<List<String>> entryKeys(String listId) async =>
      (await state(listId)).entryKeys;

  /// PUT /v1/lists/:id — owner-only rename.
  Future<void> rename(String listId, String displayName) async {
    final resp = await http.put(
      _u('/v1/lists/$listId'),
      headers: _headers(json: true),
      body: jsonEncode({'displayName': displayName}),
    );
    _expect(resp, 200, 'rename');
  }

  /// DELETE /v1/lists/:id/editors/:userId — owner removes an editor.
  Future<void> removeEditor(String listId, String userId) async {
    final resp = await http.delete(
      _u('/v1/lists/$listId/editors/${Uri.encodeComponent(userId)}'),
      headers: _headers(),
    );
    _expect(resp, 204, 'removeEditor');
  }

  /// DELETE /v1/account — delete this device's account and owned lists.
  Future<void> deleteAccount() async {
    final resp = await http.delete(_u('/v1/account'), headers: _headers());
    _expect(resp, 200, 'deleteAccount');
  }

  void _expect(http.Response resp, int status, String what) {
    if (resp.statusCode != status) {
      throw StateError(
          '$what: expected HTTP $status, got ${resp.statusCode}: ${resp.body}');
    }
  }

  static String _randomBase32(int len) {
    const alphabet = 'abcdefghijklmnopqrstuvwxyz234567';
    return List.generate(len, (_) => alphabet[_rand.nextInt(32)]).join();
  }
}
