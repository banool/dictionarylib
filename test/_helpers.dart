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
///
/// Construction modes:
///   - Default (no args after key): zero sub-entries — for legacy-style
///     tests that only care about the entry key.
///   - `videos: [...]` — one sub-entry holding those video URLs.
///   - `subEntries: [FakeSubEntryFixture(videos: [...]), ...]` — full
///     control over the sub-entry shape, used by the v1→v2 list
///     migration tests where ordering across sub-entries matters.
///
/// Passing both `videos` and `subEntries` is rejected as a programmer
/// error — pick one or the other.
class FakeEntry extends Entry {
  final String _key;
  final List<SubEntry> _subEntries;
  final List<String> _categories;
  FakeEntry(
    this._key, {
    List<String>? videos,
    List<FakeSubEntryFixture>? subEntries,
    List<String> categories = const [],
  })  : assert(
            videos == null || subEntries == null,
            'pass `videos:` (single-sub-entry shorthand) OR `subEntries:` '
            '(explicit list), not both'),
        _categories = categories,
        _subEntries = subEntries != null
            ? subEntries.map((f) => f._build()).toList()
            : (videos == null || videos.isEmpty)
                ? const []
                : [_FakeSubEntry(videos)];
  @override
  String getKey() => _key;
  @override
  String? getPhrase(Locale locale) => _key;
  @override
  List<String> getCategories() => _categories;
  @override
  EntryType getEntryType() => EntryType.WORD;
  @override
  List<SubEntry> getSubEntries() => _subEntries;
  @override
  int compareTo(Entry other) => _key.compareTo(other.getKey());
}

/// Description of one sub-entry to attach to a [FakeEntry]. Wraps the
/// private [_FakeSubEntry] so tests can compose multi-sub-entry
/// entries without touching the implementation type.
class FakeSubEntryFixture {
  final List<String> videos;
  const FakeSubEntryFixture({required this.videos});
  _FakeSubEntry _build() => _FakeSubEntry(videos);
}

class _FakeSubEntry extends SubEntry<String, String> {
  final List<String> _media;
  _FakeSubEntry(this._media);
  @override
  String getKey(Entry parentEntry) =>
      '${parentEntry.getKey()}::${_media.isEmpty ? "" : _media.first}';
  @override
  List<String> getMedia() => _media;
  @override
  List<String> getRelatedWords() => const [];
  @override
  List<String> getDefinitions(Locale locale) => const [];
  @override
  List<String> getRegions() => const [];
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

/// Base URL the tests treat media as served from. A media path resolves
/// to `kTestMediaBase + path` (see [mediaUrlForPath]); the v2→v3 list /
/// review migrations strip it back off (see [mediaPathForUrl]).
const String kTestMediaBase = 'https://example.test';

/// Populate `keyedByEnglishEntriesGlobal` with [FakeEntry] instances.
/// By default each entry gets one synthetic media **path** (`/<key>.mp4`,
/// what [SubEntry.getMedia] now returns) so per-video tests can refer to
/// it via [videoFor] without spelling it out. Pass [videosByKey] to
/// supply specific paths per entry (migration / multi-video scenarios).
/// Also configures [mediaBaseUrls], which the migrations rely on.
void seedDictionary(
  Iterable<String> keys, {
  Map<String, List<String>> videosByKey = const {},
}) {
  mediaBaseUrls = const [kTestMediaBase];
  keyedByEnglishEntriesGlobal.clear();
  for (final k in keys) {
    final videos = videosByKey[k] ?? [videoFor(k)];
    keyedByEnglishEntriesGlobal[k] = FakeEntry(k, videos: videos);
  }
}

/// The media **path** (the v3 saved-video identity) for [entryKey].
String videoFor(String entryKey) => '/$entryKey.mp4';

/// The full v2-era media URL for [entryKey] — `kTestMediaBase` + its
/// path. Used by migration tests that seed the old full-URL shape.
String urlFor(String entryKey) => '$kTestMediaBase${videoFor(entryKey)}';

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
///
/// Accepts entry keys for backward compatibility — each is mapped to
/// `{entry: key, video: videoFor(key)}` so existing tests don't have
/// to spell out the wire shape. For tests that exercise multi-video
/// scenarios, pass [videoEntries] directly as the canonical shape.
Map<String, dynamic> snapshotJson({
  required String listId,
  required String displayName,
  List<String>? entries,
  List<Map<String, String>>? videoEntries,
  int lastSeq = 1,
  int createdAt = 1700000000,
  int updatedAt = 1700000000,
  Map<String, dynamic>? members,
}) {
  final wireEntries = videoEntries ??
      (entries ?? const <String>[])
          .map((k) => {'entry': k, 'video': videoFor(k)})
          .toList();
  return {
    'schemaVersion': 3,
    'listId': listId,
    'displayName': displayName,
    'appId': 'auslan',
    'entries': wireEntries,
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
