/// Account sync against the REAL Worker (`wrangler dev`), with two devices'
/// full client stacks in one process (the harness swaps their prefs and
/// globals). Where `account_sync_test.dart` runs the same client against
/// an in-memory server, this checks the two agree with the real backend.
///
/// Auto-skips when no server answers, like `multi_device_sync_test.dart`:
///   (cd ../dictionary_backend/workers && bunx wrangler dev --env dev --port 8790)
///   flutter test test/sharing/account_sync_multi_device_test.dart \
///     --dart-define=INTEGRATION_BASE_URL=http://localhost:8790
///
/// Run it on its own rather than in one `flutter test` with
/// `multi_device_sync_test.dart`: files run in parallel, and that one's
/// `tearDownAll` wipes every test user on the worker, lists included, which
/// can land in the middle of a test here.
library;

import 'dart:convert';
import 'dart:io';

import 'package:dictionarylib/common.dart';
import 'package:dictionarylib/flashcards_logic.dart';
import 'package:dictionarylib/globals.dart';
import 'package:dictionarylib/lists_service.dart';
import 'package:dictionarylib/revision_history.dart';
import 'package:dictionarylib/saved_video.dart';
import 'package:dictionarylib/sharing/account_sync.dart';
import 'package:dictionarylib/sharing/sync_api.dart';
import 'package:dictionarylib/sharing/sync_clock.dart';
import 'package:dolphinsr/dolphinsr.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../_helpers.dart';
import '_account_sync_harness.dart';
import '_fake_account_server.dart';
import 'multi_device_helpers.dart';

Future<void> main() async {
  installFakeSecureStorage();
  HttpOverrides.global = null;

  if (!await integrationServerReachable()) {
    final msg = 'no server reachable at $kIntegrationBaseUrl';
    if (Platform.environment.containsKey('REQUIRE_SERVER')) {
      fail('[account-sync] $msg; REQUIRE_SERVER is set');
    }
    // ignore: avoid_print
    print('[account-sync] skipping: $msg');
    return;
  }

  // Unused by the real server; the harness wants one.
  final unused = FakeAccountServer();

  Future<String> mint(String userId) async => (await signInTestUser(
    userId: userId,
    displayName: 'Account Sync',
  )).sessionToken;

  /// A device talking to the real Worker. [fail] picks requests to refuse.
  TestDevice device(String name, {bool Function(http.BaseRequest)? fail}) {
    late TestDevice d;
    d = TestDevice(
      unused,
      name,
      config: kIntegrationSharingConfig,
      makeClient: () => FlakyClient(http.Client())..failWhen = fail,
      mintToken: mint,
    );
    return d;
  }

  Future<Map<String, dynamic>> accountState(String token) async {
    final r = await http.post(
      Uri.parse('$kIntegrationBaseUrl/v1/account/sync'),
      headers: {
        'x-app-id': kIntegrationAppId,
        'authorization': 'Bearer $token',
        'content-type': 'application/json',
      },
      body: jsonEncode({'clientId': 'checker', 'sinceSeq': 0, 'ops': []}),
    );
    expect(r.statusCode, 200);
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<List<String>> serverKeys(String token, String listId) async {
    final r = await http.get(
      Uri.parse('$kIntegrationBaseUrl/v1/lists/$listId/state'),
      headers: {
        'x-app-id': kIntegrationAppId,
        'authorization': 'Bearer $token',
      },
    );
    expect(r.statusCode, 200, reason: r.body);
    final json = jsonDecode(r.body) as Map<String, dynamic>;
    return [for (final e in (json['entries'] as List)) e['entry'] as String];
  }

  setUp(() {
    seedDictionary(const []);
  });

  tearDown(() {
    TestDevice(unused, 'none').deactivate();
    debugSyncClockOffsetSeconds = 0;
  });

  test('two devices with "Animals" signing in close together end with one, '
      'holding both', () async {
    final user = randomTestUserId('test:acc-e');
    // The phone gets as far as reading the directory, then loses the
    // network: its merge resumes after the tablet's has created "Animals".
    var phoneOffline = false;
    final phone = device(
      'phone',
      fail: (req) => phoneOffline && req.url.path != '/v1/auth/sign-in',
    );
    await phone.activate();
    await phone.addLocalList('Animals', ['cat', 'dog']);
    await phone.signIn(user);
    phoneOffline = true;
    await sharing.accountSync.kick(SyncReason.pullToRefresh);
    phone.deactivate();

    final tablet = device('tablet');
    await tablet.activate();
    await tablet.addLocalList('Animals', ['dog', 'eel']);
    await tablet.signIn(user);
    await tablet.settle();

    phoneOffline = false;
    await phone.settle();
    await tablet.settle();

    final dir = await accountState(phone.token!);
    final animals = [
      for (final r in (dir['directory'] as List))
        if (r['name'] == 'Animals' && r['state'] == 'live') r['listId'],
    ];
    expect(animals, hasLength(1));
    final keys = await serverKeys(phone.token!, animals.single as String);
    expect(keys.toSet(), {'cat', 'dog', 'eel'});
    expect(phone.localLists()['Animals']!.toSet(), {'cat', 'dog', 'eel'});
    await tablet.activate();
    expect(tablet.localLists()['Animals']!.toSet(), {'cat', 'dog', 'eel'});
  });

  test(
    'both edit the same list offline, then come back: the union, once',
    () async {
      final user = randomTestUserId('test:acc-f');
      var offline = false;
      final phone = device('phone', fail: (_) => offline);
      final tablet = device('tablet', fail: (_) => offline);
      await phone.activate();
      await phone.addLocalList('Birds', ['owl']);
      await phone.signIn(user);
      await phone.settle();
      await tablet.signIn(user);
      await tablet.settle();

      offline = true;
      await phone.activate();
      var w = sharing.lists.ownerForSourceKey('Birds_words')!;
      await w.addVideo(video('crow'));
      await w.addVideo(video('wren'));
      await tablet.activate();
      w = sharing.lists.ownerForSourceKey('Birds_words')!;
      await w.addVideo(video('crow'));
      await w.addVideo(video('kite'));
      offline = false;
      await tablet.settle();
      await phone.settle();
      await tablet.settle();

      expect(phone.localLists()['Birds'], isNotNull);
      await phone.activate();
      final id = sharing.lists.ownerForSourceKey('Birds_words')!.listId;
      final keys = await serverKeys(phone.token!, id);
      expect(keys.toSet(), {'owl', 'crow', 'wren', 'kite'});
      expect(keys.length, 4, reason: 'no duplicates');
      expect(phone.localLists()['Birds']!.toSet(), keys.toSet());
      await tablet.activate();
      expect(tablet.localLists()['Birds']!.toSet(), keys.toSet());
    },
  );

  test('a list deleted on one device: edits elsewhere older than the delete '
      'go with it, newer ones bring it back everywhere', () async {
    final user = randomTestUserId('test:acc-g');
    var tabletOffline = false;
    final phone = device('phone');
    final tablet = device('tablet', fail: (_) => tabletOffline);
    await phone.activate();
    await phone.addLocalList('Older', ['a']);
    await phone.addLocalList('Newer', ['b']);
    await phone.signIn(user);
    await phone.settle();
    await tablet.signIn(user);
    await tablet.settle();

    // The tablet edits both offline: by its clock, one a minute before the
    // delete and one a minute after.
    tabletOffline = true;
    await tablet.activate();
    debugSyncClockOffsetSeconds = -60;
    await sharing.lists.ownerForSourceKey('Older_words')!.addVideo(video('c'));
    debugSyncClockOffsetSeconds = 60;
    await sharing.lists.ownerForSourceKey('Newer_words')!.addVideo(video('d'));
    debugSyncClockOffsetSeconds = 0;
    tablet.deactivate();

    await phone.activate();
    final newerId = sharing.lists.ownerForSourceKey('Newer_words')!.listId;
    for (final key in ['Older_words', 'Newer_words']) {
      await listsService.deleteList(userEntryListManager.getEntryLists()[key]!);
    }
    await phone.settle();

    tabletOffline = false;
    await tablet.settle();
    final lists = tablet.localLists();
    expect(lists.containsKey('Older'), isFalse);
    expect(lists['Newer']!.toSet(), {'b', 'd'});
    expect(sharing.lists.ownerForSourceKey('Newer_words')!.listId, newerId);
    expect((await serverKeys(tablet.token!, newerId)).toSet(), {'b', 'd'});
    await phone.settle();
    expect(phone.localLists()['Newer']!.toSet(), {'b', 'd'});
    expect(phone.localLists().containsKey('Older'), isFalse);
  });

  test('two devices renaming offline end with the later rename', () async {
    final user = randomTestUserId('test:acc-rn');
    var offline = false;
    final phone = device('phone', fail: (_) => offline);
    final tablet = device('tablet', fail: (_) => offline);
    await phone.activate();
    await phone.addLocalList('Zoo', ['a']);
    await phone.signIn(user);
    await phone.settle();
    await tablet.signIn(user);
    await tablet.settle();
    offline = true;
    debugSyncClockOffsetSeconds = 30;
    await listsService.renameList(
      userEntryListManager.getEntryLists()['Zoo_words']!,
      'Later',
    );
    tablet.deactivate();
    await phone.activate();
    debugSyncClockOffsetSeconds = 0;
    await listsService.renameList(
      userEntryListManager.getEntryLists()['Zoo_words']!,
      'Earlier',
    );
    offline = false;
    await tablet.settle();
    await phone.settle();
    final id = sharing.lists.ownerForSourceKey('Zoo_words')!.listId;
    final r = await http.get(
      Uri.parse('$kIntegrationBaseUrl/v1/lists/$id/state'),
      headers: {
        'x-app-id': kIntegrationAppId,
        'authorization': 'Bearer ${phone.token}',
      },
    );
    expect((jsonDecode(r.body) as Map)['displayName'], 'Later');
    expect(sharing.lists.ownerForSourceKey('Zoo_words')!.getName(), 'Later');
    final dir = await accountState(phone.token!);
    expect(
      (dir['directory'] as List).firstWhere((d) => d['listId'] == id)['name'],
      'Later',
    );
  });

  test('a list shared from an old build and "unshared" with a DELETE stays '
      'on the account, private', () async {
    final user = randomTestUserId('test:acc-old');
    final phone = device('phone');
    await phone.activate();
    await phone.signIn(user);
    await phone.settle();
    // An old build on another device: shares a list the old way, then its
    // "stop sharing" is a DELETE without the capability header.
    final listId = 'old${DateTime.now().microsecondsSinceEpoch}';
    final create = await http.post(
      Uri.parse('$kIntegrationBaseUrl/v1/lists'),
      headers: {
        'x-app-id': kIntegrationAppId,
        'authorization': 'Bearer ${phone.token}',
        'content-type': 'application/json',
      },
      body: jsonEncode({
        'listId': listId,
        'displayName': 'Old Share',
        'entries': [
          {'entry': 'x', 'video': integrationVideoFor('x')},
        ],
        'schemaVersion': 3,
      }),
    );
    expect(create.statusCode, 201);
    final del = await http.delete(
      Uri.parse('$kIntegrationBaseUrl/v1/lists/$listId'),
      headers: {
        'x-app-id': kIntegrationAppId,
        'authorization': 'Bearer ${phone.token}',
      },
    );
    expect(del.statusCode, 204);

    await phone.settle();
    final dir = await accountState(phone.token!);
    final row = (dir['directory'] as List).firstWhere(
      (r) => r['listId'] == listId,
    );
    expect(row['state'], 'live');
    expect(row['visibility'], listVisibilityPrivate);
    expect(phone.localLists()['Old Share'], ['x']);
  });

  test('share and stop sharing against the real Worker', () async {
    final user = randomTestUserId('test:acc-share');
    final phone = device('phone');
    await phone.activate();
    await phone.addLocalList('Zoo', ['lion']);
    await phone.signIn(user);
    await phone.settle();
    final w = await listsService.shareList(
      sourceList: userEntryListManager.getEntryLists()['Zoo_words']!,
      displayName: 'Zoo Signs',
      sessionToken: phone.token!,
    );
    expect(w.meta.isShared, isTrue);
    final pub = await http.get(
      Uri.parse('$kIntegrationBaseUrl/v1/lists/${w.listId}'),
    );
    expect(pub.statusCode, 200);
    await listsService.stopSharing(w);
    final gone = await http.get(
      Uri.parse('$kIntegrationBaseUrl/v1/lists/${w.listId}'),
      headers: {'cache-control': 'no-cache'},
    );
    expect(gone.statusCode, 404);
    expect(phone.localLists()['Zoo Signs'], ['lion']);
  });

  test('revision both ways against the real Worker: answers, random '
      'sessions, a setting and a reset', () async {
    final user = randomTestUserId('test:acc-rev');
    final now = DateTime.now().microsecondsSinceEpoch;
    Review answer(String key, int tsUs) => Review(
      master: savedVideoMasterId(
        SavedVideo(entryKey: key, mediaPath: videoFor(key)),
      ),
      combination: const Combination(front: [0], back: [1]),
      rating: Rating.Good,
      ts: DateTime.fromMicrosecondsSinceEpoch(tsUs),
    );

    final phone = device('phone');
    await phone.activate();
    // History from before signing in: 700 answers, so it goes up in two
    // batches.
    await reviewHistory.appendLocal([
      for (var i = 0; i < 700; i++) answer('w$i', now - 3600000000 + i),
    ], queueForUpload: false);
    await sharedPreferences.setInt(KEY_RANDOM_REVIEWS_COUNTER, 4);
    await sharedPreferences.setInt(KEY_REVISION_CARD_LIMIT, 25);
    await phone.signIn(user);
    await phone.settle();
    expect(reviewHistory.unsentCount, 0);

    final tablet = device('tablet');
    await tablet.activate();
    await tablet.signIn(user);
    await tablet.settle();
    expect(reviewHistory.read(), hasLength(700));
    expect(sharedPreferences.getInt(KEY_REVISION_CARD_LIMIT), 25);
    expect(sharing.accountSync.randomTotalWithPending, 4);
    await sharing.accountSync.recordAnswers([answer('t1', now - 1000)]);
    await bumpRandomReviewCounter(2);
    await tablet.settle();

    await phone.settle();
    expect(reviewHistory.read(), hasLength(701));
    expect(sharing.accountSync.randomTotalWithPending, 6);

    // The phone deletes all revision progress; the tablet follows.
    final resetAt = DateTime.now().microsecondsSinceEpoch;
    await sharing.accountSync.recordReset(resetAt);
    await reviewHistory.reset(resetAt);
    await phone.settle();
    final acc = await accountState(phone.token!);
    expect(acc['reviews'], isEmpty);
    expect(acc['randomTotal'], 0);
    await tablet.settle();
    expect(reviewHistory.read(), isEmpty);
    expect(sharing.accountSync.randomTotalWithPending, 0);
  });
}
