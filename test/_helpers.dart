import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dictionarylib/entry_types.dart';
import 'package:dictionarylib/globals.dart';
import 'package:dictionarylib/sharing/auth/auth_api.dart';
import 'package:dictionarylib/sharing/auth/auth_service.dart';
import 'package:dictionarylib/sharing/auth/auth_store.dart';
import 'package:dictionarylib/sharing/sharing.dart';
import 'package:dictionarylib/sharing/sharing_config.dart';
import 'package:dictionarylib/sharing/sync_api.dart';
import 'package:dictionarylib/sharing/synced_entry_list.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Minimal stand-in for [Entry] suitable for tests that only round-trip
/// keys (lists, sync engine, etc).
class FakeEntry extends Entry {
  final String _key;
  FakeEntry(this._key);
  @override
  String getKey() => _key;
  @override
  String? getPhrase(Locale locale) => _key;
  @override
  List<String> getCategories() => const [];
  @override
  EntryType getEntryType() => EntryType.WORD;
  @override
  List<SubEntry> getSubEntries() => const [];
  @override
  int compareTo(Entry other) => _key.compareTo(other.getKey());
}

/// Install a no-op handler for the flutter_secure_storage MethodChannel
/// so [AuthStore.clear] / [save] / [load] don't throw
/// MissingPluginException in tests. Returns null for every call —
/// `AuthStore` doesn't need the storage to roundtrip for the
/// tests we care about, just to not throw.
void installFakeSecureStorage() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
    (MethodCall call) async => null,
  );
}

/// Populate `keyedByEnglishEntriesGlobal` with [FakeEntry] instances so
/// that `EntryList.loadEntryList` / `SyncedEntryList.replaceEntriesFromServer`
/// can resolve stored keys back to objects.
void seedDictionary(Iterable<String> keys) {
  keyedByEnglishEntriesGlobal.clear();
  for (final k in keys) {
    keyedByEnglishEntriesGlobal[k] = FakeEntry(k);
  }
}

/// Default config used by every sharing-related test.
const kTestSharingConfig = SharingConfig(
  appId: 'auslan',
  appName: 'Test App',
  apiBaseUrl: 'https://api.example.test',
  shareLinkBaseUrl: 'https://share.example.test/l',
  shareLinkHost: 'share.example.test',
  urlScheme: 'auslan',
  auth: SharingAuthConfig(
    appleBundleId: 'com.example.test',
    googleServerClientId: 'test.google.client.id',
    facebookAppId: 'test-fb-app-id',
  ),
);

/// Default in-memory session for tests that need an authenticated push.
const kTestSession = AuthSession(
  sessionToken: 'fake-session-jwt',
  provider: AuthProvider.apple,
  displayName: 'Test User',
  signedInAtMillis: 1700000000000,
);

/// Configure the global [sharing] singleton with a stub HTTP client and a
/// fresh manager. The returned [Sharing] starts out with a signed-in
/// session at [kTestSession] so writes-that-require-auth don't need a
/// separate setup step.
List<http.Request> installFakeSharing(
    Future<http.Response> Function(http.Request) handle) {
  final out = <http.Request>[];
  final client = MockClient((req) async {
    out.add(req);
    return handle(req);
  });
  final api = SyncApi(kTestSharingConfig, client: client);
  final authApi = AuthApi(kTestSharingConfig, client: client);
  final authStore = AuthStore.withSession(kTestSession);
  final auth =
      AuthService(config: kTestSharingConfig, api: authApi, store: authStore);
  final lists = SyncedEntryListManager.fromStartup();
  sharing = Sharing.forTesting(
      config: kTestSharingConfig, api: api, lists: lists, auth: auth);
  return out;
}

/// Canned 201 response for `POST /v1/lists` that echoes back the
/// supplied listId. Use as the POST branch of an [installFakeSharing]
/// handler. Mirrors the worker's create response shape: `listId`,
/// `lastSeq`, `createdAt`, `updatedAt`.
Future<http.Response> stubCreateResponse(
  http.Request req, {
  int lastSeq = 1,
  int createdAt = 1700000000,
  int updatedAt = 1700000000,
}) async {
  final body = jsonDecode(req.body) as Map<String, dynamic>;
  return http.Response(
    jsonEncode({
      'listId': body['listId'],
      'lastSeq': lastSeq,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    }),
    201,
    headers: {'content-type': 'application/json'},
  );
}

/// Canned 200 response for `POST /v1/lists/:id/sync` that reports every
/// op in the request as applied. Sequence numbers start at
/// `firstAppliedSeq` and increment by 1.
Future<http.Response> stubSyncApplyAll(
  http.Request req, {
  int firstAppliedSeq = 2,
  List<Map<String, dynamic>>? missedOps,
  Map<String, dynamic>? snapshot,
  Map<String, dynamic>? members,
}) async {
  final body = jsonDecode(req.body) as Map<String, dynamic>;
  final ops = (body['ops'] as List<dynamic>).cast<Map<String, dynamic>>();
  final applied = <Map<String, dynamic>>[];
  for (var i = 0; i < ops.length; i++) {
    applied.add({
      'opId': ops[i]['opId'],
      'status': 'applied',
      'seq': firstAppliedSeq + i,
    });
  }
  final appliedSeq =
      ops.isEmpty ? firstAppliedSeq - 1 : firstAppliedSeq + ops.length - 1;
  return http.Response(
    jsonEncode({
      'appliedSeq': appliedSeq,
      'applied': applied,
      'missedOps': missedOps,
      'snapshot': snapshot,
      'members': members ??
          {
            'owner': {'userId': 'apple:test-user', 'displayName': 'Test User'},
            'editors': <Map<String, dynamic>>[],
          },
    }),
    200,
    headers: {'content-type': 'application/json'},
  );
}

/// Canned 200 response shape for `GET /v1/lists/:id/state` (full
/// authenticated snapshot including the members block).
Map<String, dynamic> snapshotJson({
  required String listId,
  required String displayName,
  required List<String> entries,
  int lastSeq = 1,
  int createdAt = 1700000000,
  int updatedAt = 1700000000,
  Map<String, dynamic>? members,
}) {
  return {
    'schemaVersion': 2,
    'listId': listId,
    'displayName': displayName,
    'appId': 'auslan',
    'entries': entries,
    'lastSeq': lastSeq,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    'members': members ??
        {
          'owner': {'userId': 'apple:test-user', 'displayName': 'Test User'},
          'editors': <Map<String, dynamic>>[],
        },
  };
}
