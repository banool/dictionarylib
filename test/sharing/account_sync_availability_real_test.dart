/// Account sync against the REAL Worker with the network between the
/// devices and it coming and going: an in-test proxy (`NetProxy`, from
/// dictionarylib_test_support) sits in front of `wrangler dev` and is taken
/// down, made lossy (the Worker does the work, the answer is dropped), and
/// brought back. Scenarios a, c, d and i of `account_sync_availability_test`
/// (which runs them all against the in-memory server, in fake time).
///
/// Run on its own (not in one `flutter test` with the other real-Worker
/// files, whose wipes would land mid-test):
///   flutter test test/sharing/account_sync_availability_real_test.dart \
///     --dart-define=INTEGRATION_BASE_URL=http://localhost:8790
library;

import 'dart:convert';
import 'dart:io';

import 'package:dictionarylib/common.dart';
import 'package:dictionarylib/entry_list.dart';
import 'package:dictionarylib/flashcards_logic.dart';
import 'package:dictionarylib/globals.dart';
import 'package:dictionarylib/lists_service.dart';
import 'package:dictionarylib/saved_video.dart';
import 'package:dictionarylib/sharing/account_sync.dart';
import 'package:dictionarylib/sharing/sharing_config.dart';
import 'package:dictionarylib/sharing/sync_clock.dart';
import 'package:dolphinsr/dolphinsr.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

// The proxy the on-device suites use too; it lives in the test support
// package (which depends on this one, so it can't be a dependency here) and
// imports only dart:io.
// ignore: avoid_relative_lib_imports
import '../../dictionarylib_test_support/lib/net_proxy.dart';
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
      fail('[availability] $msg; REQUIRE_SERVER is set');
    }
    // ignore: avoid_print
    print('[availability] skipping: $msg');
    return;
  }

  final unused = FakeAccountServer();
  late NetProxy proxy;

  setUp(() async {
    seedDictionary(const []);
    communityEntryListManager = DummyEntryListManager();
    proxy = await NetProxy.start(Uri.parse(kIntegrationBaseUrl));
  });

  tearDown(() async {
    TestDevice(unused, 'none').deactivate();
    debugSyncClockOffsetSeconds = 0;
    await proxy.close();
  });

  Future<String> mint(String userId) async => (await signInTestUser(
    userId: userId,
    displayName: 'Availability',
  )).sessionToken;

  /// A device whose requests go through the proxy.
  TestDevice viaProxy(String name) => TestDevice(
    unused,
    name,
    config: SharingConfig(
      appId: kIntegrationAppId,
      appName: 'Integration Test App',
      apiBaseUrl: proxy.baseUrl,
      shareLinkBaseUrl: 'https://share.example.test/l',
      shareLinkHost: 'share.example.test',
      urlScheme: 'auslan',
      auth: const SharingAuthConfig(
        appleBundleId: 'com.example.test',
        googleServerClientId: 'test.google.client.id',
      ),
    ),
    makeClient: http.Client.new,
    mintToken: mint,
  );

  /// A device talking to the Worker directly (a second phone elsewhere).
  TestDevice direct(String name) => TestDevice(
    unused,
    name,
    config: kIntegrationSharingConfig,
    makeClient: http.Client.new,
    mintToken: mint,
  );

  Future<Map<String, dynamic>> account(String token) async {
    final r = await http.post(
      Uri.parse('$kIntegrationBaseUrl/v1/account/sync'),
      headers: {
        'x-app-id': kIntegrationAppId,
        'authorization': 'Bearer $token',
        'content-type': 'application/json',
      },
      body: jsonEncode({'clientId': 'checker', 'sinceSeq': 0, 'ops': []}),
    );
    expect(r.statusCode, 200, reason: r.body);
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<List<String>> keysOf(String token, String listId) async {
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

  /// The account's live lists, name → entry keys; each name once.
  Future<Map<String, Set<String>>> accountLists(String token) async {
    final dir = (await account(token))['directory'] as List;
    final live = [
      for (final r in dir)
        if (r['state'] == 'live') r,
    ];
    final names = live.map((r) => r['name'] as String).toList();
    expect(names.toSet(), hasLength(names.length), reason: 'a list twice');
    return {
      for (final r in live)
        r['name'] as String: (await keysOf(
          token,
          r['listId'] as String,
        )).toSet(),
    };
  }

  Map<String, Set<String>> deviceLists(TestDevice d) => {
    for (final e in d.localLists().entries) e.key: e.value.toSet(),
  };

  EntryList list(String key) => userEntryListManager.getEntryLists()[key]!;

  Future<T> instant<T>(Future<T> f, String what) async {
    final sw = Stopwatch()..start();
    final v = await f;
    expect(
      sw.elapsedMilliseconds,
      lessThan(1000),
      reason: '$what should not wait on the network',
    );
    return v;
  }

  Review answer(String key, int secondsAgo) => Review(
    master: savedVideoMasterId(
      SavedVideo(entryKey: key, mediaPath: videoFor(key)),
    ),
    combination: const Combination(front: [1], back: [0]),
    rating: Rating.Good,
    ts: DateTime.fromMillisecondsSinceEpoch(
      (syncNowSecs() - secondsAgo) * 1000,
    ),
  );

  void expectQuiet(TestDevice d) {
    expect(d.notices.where((n) => n is! MergeCompletedNotice), isEmpty);
    expect(d.engineNotices, isEmpty);
  }

  Future<void> backOnline(TestDevice d) async {
    await proxy.up();
    await d.activate();
    await sharing.accountSync.kick(SyncReason.resumed);
    await d.settle(rounds: 6);
  }

  test('a: signing in with the Worker unreachable; the merge completes when '
      'it is back', () async {
    final user = randomTestUserId('test:av-a');
    final phone = viaProxy('phone');
    await phone.activate();
    await phone.addLocalList('Animals', ['cat', 'dog']);
    await proxy.down();
    await phone.signIn(user);
    await phone.settle();
    expect(sharing.accountSync.status, AccountSyncStatus.waitingForConnection);
    await instant(listsService.createList('Birds'), 'create');
    await instant(list('Birds_words').addVideo(video('owl')), 'save');
    await instant(
      listsService.renameList(list('Animals_words'), 'Beasts'),
      'rename',
    );
    expectQuiet(phone);
    await backOnline(phone);
    expect(sharing.accountSync.state!.mergeDone, isTrue);
    final want = {
      'Favourites': <String>{},
      'Beasts': {'cat', 'dog'},
      'Birds': {'owl'},
    };
    expect(await accountLists(phone.token!), want);
    expect(deviceLists(phone), want);
    final tablet = direct('tablet');
    await tablet.activate();
    await tablet.signIn(user);
    await tablet.settle();
    expect(deviceLists(tablet), want);
  });

  test('c: a long offline session, then back online', () async {
    final user = randomTestUserId('test:av-c');
    final phone = viaProxy('phone');
    await phone.activate();
    await phone.addLocalList('Animals', ['cat']);
    await phone.addLocalList('Birds', ['owl']);
    await phone.addLocalList('Fish', ['eel']);
    await phone.signIn(user);
    await phone.settle();
    await proxy.down();
    final keys = ['Animals_words', 'Birds_words', 'Fish_words'];
    for (var i = 0; i < 9; i++) {
      await instant(list(keys[i % 3]).addVideo(video('s$i')), 'save $i');
    }
    await instant(
      listsService.renameList(list('Animals_words'), 'Beasts'),
      'rename',
    );
    await instant(
      listsService.renameList(list('Birds_words'), 'Sky'),
      'rename',
    );
    await instant(
      listsService.renameList(list('Birds_words'), 'Sky birds'),
      'rename again',
    );
    await instant(listsService.reorderLists(2, 0), 'reorder');
    await instant(listsService.deleteList(list('Fish_words')), 'delete');
    await instant(
      sharing.accountSync.recordAnswers([
        for (var i = 0; i < 3; i++) answer('s$i', 30 - i),
      ]),
      'a revision session',
    );
    await instant(bumpRandomReviewCounter(2), 'a random session');
    await instant(
      sharedPreferences.setInt(KEY_REVISION_CARD_LIMIT, 50),
      'a setting',
    );
    await sharing.accountSync.kick(SyncReason.resumed);
    expect(sharing.accountSync.status, AccountSyncStatus.waitingForConnection);
    expectQuiet(phone);
    final order = phone.localLists().keys.toList();
    await backOnline(phone);
    final want = {
      'Favourites': <String>{},
      'Beasts': {'cat', 's0', 's3', 's6'},
      'Sky birds': {'owl', 's1', 's4', 's7'},
    };
    expect(await accountLists(phone.token!), want);
    final acc = await account(phone.token!);
    expect(acc['reviews'], hasLength(3));
    expect(acc['randomTotal'], 2);
    expect(
      (acc['settings'] as List).firstWhere(
        (s) => s['key'] == KEY_REVISION_CARD_LIMIT,
      )['value'],
      '50',
    );
    final tablet = direct('tablet');
    await tablet.activate();
    await tablet.signIn(user);
    await tablet.settle();
    expect(deviceLists(tablet), want);
    expect(tablet.localLists().keys.toList(), order);
    expect(sharedPreferences.getInt(KEY_REVISION_CARD_LIMIT), 50);
  });

  test('d: with every answer lost, nothing is doubled', () async {
    final user = randomTestUserId('test:av-d');
    final phone = viaProxy('phone');
    await phone.activate();
    await phone.addLocalList('Animals', ['cat']);
    await phone.addLocalList('Gone', ['x']);
    await phone.signIn(user);
    await phone.settle();

    Future<void> lossy(Future<void> Function() op) async {
      await proxy.lossy();
      await op();
      await sharing.accountSync.kick(SyncReason.pullToRefresh);
      await sharing.engine.pushAllDirty();
      await proxy.up();
      await phone.settle();
    }

    await lossy(() => listsService.createList('Birds'));
    await lossy(() => list('Birds_words').addVideo(video('owl')));
    await lossy(() async {
      for (final k in ['a', 'b']) {
        await list('Animals_words').addVideo(video(k));
      }
    });
    await lossy(() => listsService.renameList(list('Animals_words'), 'Beasts'));
    await lossy(() => listsService.reorderLists(2, 0));
    await lossy(() => listsService.deleteList(list('Gone_words')));
    await lossy(
      () => sharing.accountSync.recordAnswers([
        answer('cat', 30),
        answer('owl', 20),
      ]),
    );
    await lossy(() => bumpRandomReviewCounter(3));
    await lossy(() => sharedPreferences.setInt(KEY_REVISION_CARD_LIMIT, 10));

    final want = {
      'Favourites': <String>{},
      'Beasts': {'cat', 'a', 'b'},
      'Birds': {'owl'},
    };
    expect(await accountLists(phone.token!), want);
    final dir = (await account(phone.token!))['directory'] as List;
    for (final r in dir) {
      if (r['state'] != 'live') continue;
      final keys = await keysOf(phone.token!, r['listId'] as String);
      expect(keys, hasLength(keys.toSet().length), reason: 'a sign twice');
    }
    final acc = await account(phone.token!);
    expect(acc['reviews'], hasLength(2));
    expect(acc['randomTotal'], 3);
    expect(deviceLists(phone), want);
    expectQuiet(phone);
  });

  for (final deleterFirst in [true, false]) {
    for (final deleteLater in [true, false]) {
      test('i: deleted offline on one device, edited offline on the other; '
          'the ${deleteLater ? 'delete' : 'edit'} is later, the '
          '${deleterFirst ? 'deleter' : 'editor'} comes back first', () async {
        final user = randomTestUserId('test:av-i');
        final phone = viaProxy('phone');
        await phone.activate();
        await phone.addLocalList('Animals', ['cat']);
        await phone.signIn(user);
        await phone.settle();
        final tablet = viaProxy('tablet');
        await tablet.activate();
        await tablet.signIn(user);
        await tablet.settle();

        await proxy.down();
        Future<void> delete(int offset) async {
          await phone.activate();
          debugSyncClockOffsetSeconds = offset;
          await listsService.deleteList(list('Animals_words'));
          debugSyncClockOffsetSeconds = 0;
        }

        Future<void> edit(int offset) async {
          await tablet.activate();
          debugSyncClockOffsetSeconds = offset;
          await list('Animals_words').addVideo(video('dog'));
          debugSyncClockOffsetSeconds = 0;
        }

        await delete(deleteLater ? 60 : 0);
        await edit(deleteLater ? 0 : 60);
        await proxy.up();
        final order = deleterFirst ? [phone, tablet] : [tablet, phone];
        for (final d in [...order, ...order]) {
          await d.activate();
          await sharing.accountSync.kick(SyncReason.resumed);
          await d.settle();
        }
        final want = deleteLater
            ? {'Favourites': <String>{}}
            : {
                'Favourites': <String>{},
                'Animals': {'cat', 'dog'},
              };
        expect(await accountLists(phone.token!), want);
        for (final d in [phone, tablet]) {
          await d.activate();
          expect(deviceLists(d), want, reason: d.name);
          expectQuiet(d);
        }
      });
    }
  }
}
