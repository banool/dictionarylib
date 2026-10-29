import 'dart:async';

import 'package:dictionarylib/common.dart';
import 'package:dictionarylib/entry_list.dart';
import 'package:dictionarylib/flashcards_logic.dart';
import 'package:dictionarylib/globals.dart';
import 'package:dictionarylib/lists_service.dart';
import 'package:dictionarylib/revision_history.dart';
import 'package:dictionarylib/saved_video.dart';
import 'package:dictionarylib/sharing/account_sync.dart';
import 'package:dictionarylib/sharing/sync_clock.dart';
import 'package:dictionarylib/sharing/sync_engine.dart';
import 'package:dolphinsr/dolphinsr.dart';
import 'package:flutter_test/flutter_test.dart';

import '../_helpers.dart';
import '_account_sync_harness.dart';
import '_fake_account_server.dart';
import '_fake_time.dart';

/// Account sync with the backend coming and going (Daniel, 2026-10-29):
/// while it is away every local operation behaves as if it weren't there
/// (at once, quietly, the status line saying "waiting for a connection"),
/// and when it is back the device, the account and a second device agree,
/// nothing doubled. Runs in fake time, with the in-memory server's
/// [NetworkSwitch] playing the network.
void main() {
  setUpAll(installFakeSecureStorage);

  late FakeAccountServer server;

  setUp(() {
    seedDictionary(const []);
    server = FakeAccountServer();
    communityEntryListManager = DummyEntryListManager();
  });

  tearDown(() {
    TestDevice(server, 'none').deactivate();
  });

  EntryList list(String key) => userEntryListManager.getEntryLists()[key]!;

  /// Nothing shown: account notices other than the merge's one-time
  /// "now syncing", engine notices other than an expired session.
  void expectQuiet(TestDevice d, String when) {
    expect(
      d.notices.where((n) => n is! MergeCompletedNotice),
      isEmpty,
      reason: '$when: account notices',
    );
    expect(
      d.engineNotices.where((n) => n != SyncNotification.sessionExpired),
      isEmpty,
      reason: '$when: engine notices',
    );
  }

  void expectWaiting(String when) {
    expect(
      sharing.accountSync.status,
      AccountSyncStatus.waitingForConnection,
      reason: when,
    );
  }

  /// Back online the way the app does it (a resume), then let it finish.
  Future<void> backOnline(TestDevice d) async {
    server.net.up();
    await d.activate();
    await sharing.accountSync.kick(SyncReason.resumed);
    await d.settle(rounds: 6);
  }

  Map<String, Set<String>> serverLists() => {
    for (final r in server.liveRows('alice'))
      r['name'] as String: server.entryKeys(r['listId'] as String).toSet(),
  };

  Map<String, Set<String>> deviceLists(TestDevice d) => {
    for (final e in d.localLists().entries) e.key: e.value.toSet(),
  };

  /// [d] and a fresh device signing in agree with the account, and the
  /// account has each list once.
  Future<void> expectAgreed(TestDevice d, {required String when}) async {
    await d.activate();
    final rows = server.liveRows('alice');
    expect(
      rows.map((r) => r['name']).toSet(),
      hasLength(rows.length),
      reason: '$when: a list twice on the account',
    );
    expect(deviceLists(d), serverLists(), reason: '$when: device vs account');
    for (final key in userEntryListManager.getEntryLists().keys) {
      expect(
        sharing.lists.ownerForSourceKey(key),
        isNotNull,
        reason: '$when: $key not linked',
      );
    }
    final other = TestDevice(server, 'fresh-${d.name}');
    await other.activate();
    await other.signIn('alice');
    await other.settle(rounds: 6);
    expect(deviceLists(other), serverLists(), reason: '$when: fresh device');
    other.deactivate();
    await d.activate();
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

  int serverAnswerCount() =>
      (server.account('alice')['reviews'] as List).length;

  /// Let microtasks run (a cycle get as far as its next request) without
  /// the clock moving.
  Future<void> spin() async {
    for (var i = 0; i < 50; i++) {
      await Future<void>.value();
    }
  }

  fakeTimeTest('a: signing in with the backend down; the merge completes when '
      'it is back', (t) async {
    final phone = TestDevice(server, 'phone');
    await phone.activate();
    await phone.addLocalList('Animals', ['cat', 'dog']);
    await reviewHistory.appendLocal([
      answer('cat', 600),
    ], queueForUpload: false);
    server.net.down();
    await phone.signIn('alice');
    await phone.settle();
    expectWaiting('signed in, backend down');
    expect(sharing.accountSync.state!.mergeDone, isFalse);

    // Everything on the device carries on, at once.
    await t.instant(listsService.createList('Birds'), 'create');
    await t.instant(list('Birds_words').addVideo(video('owl')), 'save');
    await t.instant(
      listsService.renameList(list('Animals_words'), 'Beasts'),
      'rename',
    );
    expect(phone.localLists().keys, containsAll(['Beasts', 'Birds']));
    expectQuiet(phone, 'outage');

    await backOnline(phone);
    expect(sharing.accountSync.state!.mergeDone, isTrue);
    expect(serverLists(), {
      'Favourites': <String>{},
      'Beasts': {'cat', 'dog'},
      'Birds': {'owl'},
    });
    expect(serverAnswerCount(), 1);
    await expectAgreed(phone, when: 'after');
  });

  fakeTimeTest('f: with the network a black hole, every operation completes '
      'at once', (t) async {
    final phone = TestDevice(server, 'phone');
    await phone.activate();
    await phone.addLocalList('Animals', ['cat']);
    await phone.addLocalList('Gone', ['x']);
    await phone.signIn('alice');
    await phone.settle();

    server.net.blackhole();
    unawaited(sharing.accountSync.kick(SyncReason.pullToRefresh));
    await spin();
    expect(server.net.held, greaterThan(0), reason: 'a cycle is stuck');

    await t.instant(listsService.createList('Birds'), 'create');
    await spin();
    await t.instant(list('Birds_words').addVideo(video('owl')), 'save');
    await t.instant(
      list('Animals_words').addVideo(video('dog')),
      'save to a linked list',
    );
    await spin();
    await t.instant(
      listsService.renameList(list('Animals_words'), 'Beasts'),
      'rename a linked list',
    );
    await spin();
    await t.instant(
      listsService.renameList(list('Birds_words'), 'Sea birds'),
      'rename a list being linked',
    );
    await spin();
    await t.instant(listsService.reorderLists(2, 0), 'reorder');
    await spin();
    await t.instant(listsService.deleteList(list('Gone_words')), 'delete');
    await spin();
    await t.instant(
      sharing.accountSync.recordAnswers([answer('cat', 5)]),
      'finish a revision session',
    );
    await t.instant(bumpRandomReviewCounter(2), 'finish a random session');
    await t.instant(
      sharedPreferences.setInt(KEY_REVISION_CARD_LIMIT, 25),
      'change a setting',
    );
    expectQuiet(phone, 'black hole');

    await backOnline(phone);
    expect(serverLists(), {
      'Favourites': <String>{},
      'Beasts': {'cat', 'dog'},
      'Sea birds': {'owl'},
    });
    expect(serverAnswerCount(), 1);
    await expectAgreed(phone, when: 'after');
    expectQuiet(phone, 'after');
  });

  fakeTimeTest('f: signing out with the network a black hole is instant, and '
      'what was queued goes up once it is back', (t) async {
    final phone = TestDevice(server, 'phone');
    await phone.activate();
    await phone.addLocalList('Animals', ['cat']);
    await phone.signIn('alice');
    await phone.settle();
    server.net.blackhole();
    await list('Animals_words').addVideo(video('dog'));
    unawaited(sharing.accountSync.kick(SyncReason.pullToRefresh));
    await spin();
    await t.instant(sharing.signOut(), 'sign out');
    expect(sharing.auth.store.current, isNull);
    expect(phone.localLists()['Animals'], ['cat', 'dog']);
    server.net.up();
    // The parting flush was in the black hole: it failed when the network
    // changed. The edit is on the device, and the next sign-in's merge
    // takes it up.
    await t.wait(const Duration(minutes: 1));
    phone.token = null;
    await phone.signIn('alice');
    await phone.settle();
    expect(serverLists()['Animals'], {'cat', 'dog'});
  });

  int accountRequests() =>
      server.log.where((l) => l == 'POST /v1/account/sync').length;

  int serverRandomTotal() {
    var total = 0;
    for (final r in server.account('alice')['randomSessions'] as List) {
      total += r['count'] as int;
    }
    return total;
  }

  String? serverSetting(String key) =>
      (server.account('alice')['settings'] as Map)[key]?['value'] as String?;

  fakeTimeTest('b: the backend going down after each merge step and coming '
      'back ends merged, nothing lost or doubled', (t) async {
    // The account already has an Animals, so the merge also merges by name.
    server.createAccountList(
      'alice',
      'Animals',
      entries: [
        ['eel', videoFor('eel')],
      ],
    );
    final setup = TestDevice(server, 'setup');
    await setup.activate();
    await list(kDefaultListKey).addVideo(video('a'));
    await setup.addLocalList('Animals', ['cat']);
    await setup.addLocalList('Birds', ['owl']);
    await reviewHistory.appendLocal([
      answer('cat', 900),
      answer('owl', 800),
    ], queueForUpload: false);
    await sharedPreferences.setInt(KEY_RANDOM_REVIEWS_COUNTER, 2);
    await sharedPreferences.setInt(KEY_REVISION_CARD_LIMIT, 25);
    setup.deactivate();
    final initial = setup.prefs;
    final token = server.signIn('alice');
    final server0 = server.clone();
    final expected = {
      'Favourites': {'a'},
      'Animals': {'cat', 'eel'},
      'Birds': {'owl'},
    };

    // How many requests a merge with no outage makes.
    final probe = TestDevice(server, 'probe', prefs: Map.of(initial))
      ..token = token
      ..userId = 'alice';
    final before = server.requestCount;
    await probe.settle(rounds: 6);
    final total = server.requestCount - before;
    probe.deactivate();
    expect(serverLists(), expected);

    for (var n = 0; n <= total; n++) {
      server = server0.clone();
      final label = 'down after $n of $total requests';
      var sent = 0;
      server.failBefore = (_) => ++sent > n;
      final d = TestDevice(server, label, prefs: Map.of(initial))
        ..token = token
        ..userId = 'alice';
      await d.activate();
      await d.settle();
      // Meanwhile on the device: every list still there with its signs.
      final local = deviceLists(d);
      for (final e in {
        'Favourites': {'a'},
        'Animals': {'cat'},
        'Birds': {'owl'},
      }.entries) {
        expect(local[e.key], containsAll(e.value), reason: label);
      }
      expectQuiet(d, label);
      server.failBefore = null;
      await backOnline(d);
      expect(serverLists(), expected, reason: '$label: account');
      expect(deviceLists(d), expected, reason: '$label: device');
      expect(serverAnswerCount(), 2, reason: '$label: answers');
      expect(serverRandomTotal(), 2, reason: '$label: random');
      expect(serverSetting(KEY_REVISION_CARD_LIMIT), '25', reason: label);
      expect(sharing.accountSync.state!.mergeDone, isTrue, reason: label);
      d.deactivate();
    }
  });

  fakeTimeTest('c: a long offline session in steady state, then back online', (
    t,
  ) async {
    final zoo = server.createAccountList(
      'bob',
      'Zoo',
      visibility: 'shared',
      entries: [
        ['z', videoFor('z')],
      ],
    );
    final phone = TestDevice(server, 'phone');
    await phone.activate();
    await phone.addLocalList('Animals', ['cat']);
    await phone.addLocalList('Birds', ['owl']);
    await phone.addLocalList('Fish', ['eel']);
    await sharing.engine.subscribe(zoo);
    await phone.signIn('alice');
    await phone.settle();
    expect(server.account('alice')['follows'], [zoo]);

    server.net.down();
    await t.wait(const Duration(seconds: 10));
    final keys = ['Animals_words', 'Birds_words', 'Fish_words'];
    for (var i = 0; i < 30; i++) {
      await t.instant(list(keys[i % 3]).addVideo(video('s$i')), 'save sign $i');
    }
    await t.instant(
      listsService.renameList(list('Animals_words'), 'Beasts'),
      'rename',
    );
    await t.instant(
      listsService.renameList(list('Birds_words'), 'Sky'),
      'rename',
    );
    await t.wait(const Duration(seconds: 5));
    await t.instant(
      listsService.renameList(list('Birds_words'), 'Sky birds'),
      'rename again',
    );
    await t.instant(listsService.reorderLists(2, 0), 'reorder');
    await t.instant(listsService.deleteList(list('Fish_words')), 'delete');
    await t.instant(sharing.engine.unsubscribe(zoo), 'unfollow');
    await t.instant(
      sharing.accountSync.recordAnswers([
        for (var i = 0; i < 5; i++) answer('s$i', 60 - i),
      ]),
      'a revision session',
    );
    await t.instant(bumpRandomReviewCounter(3), 'a random session');
    await t.instant(
      sharedPreferences.setInt(KEY_REVISION_CARD_LIMIT, 50),
      'a setting',
    );
    await t.wait(const Duration(minutes: 20));
    expectWaiting('an outage');
    expectQuiet(phone, 'an outage');
    final order = phone.localLists().keys.toList();

    await backOnline(phone);
    expect(serverLists(), {
      'Favourites': <String>{},
      'Beasts': {'cat', for (var i = 0; i < 30; i += 3) 's$i'},
      'Sky birds': {'owl', for (var i = 1; i < 30; i += 3) 's$i'},
    });
    expect(server.account('alice')['follows'], isEmpty);
    expect(serverAnswerCount(), 5);
    expect(serverRandomTotal(), 3);
    expect(serverSetting(KEY_REVISION_CARD_LIMIT), '50');
    expect(phone.localLists().keys.toList(), order);
    await expectAgreed(phone, when: 'after');
    // The fresh device has the same order.
    final tablet = TestDevice(server, 'tablet');
    await tablet.activate();
    await tablet.signIn('alice');
    await tablet.settle();
    expect(tablet.localLists().keys.toList(), order);
    expect(sharedPreferences.getInt(KEY_REVISION_CARD_LIMIT), 50);
    expect(reviewHistory.read(), hasLength(5));
    expectQuiet(phone, 'after');
  });

  fakeTimeTest('d: with every answer lost, nothing is doubled', (t) async {
    final zoo = server.createAccountList(
      'bob',
      'Zoo',
      visibility: 'shared',
      entries: [
        ['z', videoFor('z')],
      ],
    );
    final phone = TestDevice(server, 'phone');
    await phone.activate();
    await phone.addLocalList('Animals', ['cat']);
    await phone.addLocalList('Gone', ['x']);
    await phone.signIn('alice');
    await phone.settle();

    Future<void> lossy(Future<void> Function() op) async {
      server.net.lossy();
      await op();
      await sharing.accountSync.kick(SyncReason.pullToRefresh);
      await sharing.engine.pushAllDirty();
      server.net.up();
      await phone.settle();
    }

    await lossy(() => listsService.createList('Birds'));
    await lossy(() => list('Birds_words').addVideo(video('owl')));
    await lossy(() async {
      for (final k in ['a', 'b', 'c']) {
        await list('Animals_words').addVideo(video(k));
      }
    });
    await lossy(() => listsService.renameList(list('Animals_words'), 'Beasts'));
    await lossy(() => listsService.reorderLists(2, 0));
    await lossy(() => listsService.deleteList(list('Gone_words')));
    await lossy(() async {
      server.net.up();
      await sharing.engine.subscribe(zoo);
      server.net.lossy();
    });
    await lossy(
      () => sharing.accountSync.recordAnswers([
        answer('cat', 30),
        answer('owl', 20),
      ]),
    );
    await lossy(() => bumpRandomReviewCounter(4));
    await lossy(() => sharedPreferences.setInt(KEY_REVISION_CARD_LIMIT, 10));
    await lossy(() => sharing.engine.unsubscribe(zoo));
    // Following needs the list itself, so that part goes through; the
    // account's `follow` is what's lost.
    await lossy(() async {
      server.net.up();
      await sharing.engine.subscribe(zoo);
      server.net.lossy();
    });

    expect(serverLists(), {
      'Favourites': <String>{},
      'Beasts': {'cat', 'a', 'b', 'c'},
      'Birds': {'owl'},
    });
    for (final r in server.liveRows('alice')) {
      final keys = server.entryKeys(r['listId'] as String);
      expect(keys, hasLength(keys.toSet().length), reason: 'a sign twice');
    }
    expect(serverAnswerCount(), 2);
    expect(serverRandomTotal(), 4);
    expect(server.account('alice')['follows'], [zoo]);
    expect(serverSetting(KEY_REVISION_CARD_LIMIT), '10');
    await expectAgreed(phone, when: 'after');
    expectQuiet(phone, 'lossy');
  });

  fakeTimeTest('e: a flaky network converges, and a dead one is not '
      'hammered', (t) async {
    final phone = TestDevice(server, 'phone');
    await phone.activate();
    await phone.addLocalList('Animals', ['cat']);
    await phone.addLocalList('Birds', ['owl']);
    await phone.addLocalList('Fish', ['eel']);
    await reviewHistory.appendLocal([
      for (var i = 0; i < 20; i++) answer('w$i', 100 + i),
    ], queueForUpload: false);
    server.net.flaky(0.5, seed: 7);
    final start = server.requestCount;
    await phone.signIn('alice');
    bool converged() =>
        (sharing.accountSync.state?.mergeDone ?? false) &&
        sharing.accountSync.state!.pendingOps.isEmpty &&
        reviewHistory.unsentCount == 0 &&
        sharing.lists.ownedLists.every((w) => w.meta.pendingOps.isEmpty) &&
        server.liveRows('alice').length == 4 &&
        serverAnswerCount() == 20;
    while (!converged() && server.requestCount - start < 200) {
      await sharing.accountSync.kick(SyncReason.resumed);
      await sharing.engine.pushAllDirty();
    }
    expect(converged(), isTrue, reason: 'converged within 200 requests');
    expect(deviceLists(phone), serverLists());
    expectQuiet(phone, 'flaky');

    // Dead for an hour, nobody touching the app: the retries back off.
    await list('Animals_words').addVideo(video('dog'));
    await sharing.accountSync.recordAnswers([answer('dog', 5)]);
    server.net.down();
    final dead = server.requestCount;
    await t.wait(const Duration(hours: 1));
    final sent = server.requestCount - dead;
    expect(sent, greaterThan(5), reason: 'it keeps trying');
    expect(sent, lessThan(150), reason: 'but backs off ($sent requests)');
    expectWaiting('dead network');
    server.net.up();
    // Back within five minutes, by the retry timer alone.
    await t.wait(const Duration(minutes: 5, seconds: 5));
    expect(serverLists()['Animals'], {'cat', 'dog'});
    expect(serverAnswerCount(), 21);
  });

  fakeTimeTest('g: coming back online by each path', (t) async {
    final phone = TestDevice(server, 'phone');
    await phone.activate();
    await phone.addLocalList('Animals', ['cat']);
    await phone.signIn('alice');
    await phone.settle();
    final w = sharing.lists.ownerForSourceKey('Animals_words')!;

    // A resume.
    server.net.down();
    await sharing.accountSync.recordAnswers([answer('cat', 50)]);
    await t.wait(const Duration(minutes: 3));
    server.net.up();
    await sharing.accountSync.kick(SyncReason.resumed);
    expect(serverAnswerCount(), 1, reason: 'resume');

    // The retry timer: within five minutes, nothing touched.
    server.net.down();
    await sharing.accountSync.recordAnswers([answer('cat', 40)]);
    await t.wait(const Duration(minutes: 30));
    server.net.up();
    await t.wait(const Duration(minutes: 5, seconds: 5));
    expect(serverAnswerCount(), 2, reason: 'retry timer');

    // Pull to refresh.
    server.net.down();
    await sharing.accountSync.recordAnswers([answer('cat', 30)]);
    await t.wait(const Duration(minutes: 30));
    server.net.up();
    await sharing.accountSync.kick(SyncReason.pullToRefresh);
    expect(serverAnswerCount(), 3, reason: 'pull to refresh');

    // A local change while the server is failing waits for the retry.
    server.net.down();
    await sharing.accountSync.kick(SyncReason.resumed);
    await t.wait(const Duration(minutes: 15)); // the backoff at its cap
    // Just after a retry, so the next is minutes away.
    final r0 = accountRequests();
    while (accountRequests() == r0) {
      await t.wait(const Duration(seconds: 1));
    }
    final before = accountRequests();
    await listsService.reorderLists(1, 0);
    await sharing.accountSync.recordAnswers([answer('cat', 20)]);
    await t.wait(const Duration(seconds: 30));
    expect(
      accountRequests(),
      before,
      reason: 'a local change during a retry wait sends nothing early',
    );
    server.net.up();
    await t.wait(const Duration(minutes: 5, seconds: 5));
    expect(serverAnswerCount(), 4, reason: 'it rode the retry');
    expect(w.meta.pendingOps, isEmpty);
    expectQuiet(phone, 'g');
  });

  for (final tabletFirst in [false, true]) {
    fakeTimeTest('h: two devices edit and rename one list offline; '
        '${tabletFirst ? 'the later' : 'the earlier'} comes back first', (
      t,
    ) async {
      final phone = TestDevice(server, 'phone');
      await phone.activate();
      await phone.addLocalList('Animals', ['cat']);
      await phone.signIn('alice');
      await phone.settle();
      final tablet = TestDevice(server, 'tablet');
      await tablet.activate();
      await tablet.signIn('alice');
      await tablet.settle();

      server.net.down();
      await phone.activate();
      await list('Animals_words').addVideo(video('dog'));
      await listsService.renameList(list('Animals_words'), 'Earlier');
      await tablet.activate();
      await t.wait(const Duration(seconds: 30));
      await list('Animals_words').addVideo(video('eel'));
      await list('Animals_words').addVideo(video('dog'));
      await listsService.renameList(list('Animals_words'), 'Later');
      server.net.up();
      final order = tabletFirst ? [tablet, phone] : [phone, tablet];
      for (final d in [...order, ...order]) {
        await d.activate();
        await sharing.accountSync.kick(SyncReason.resumed);
        await d.settle();
      }
      final want = {
        'Favourites': <String>{},
        'Later': {'cat', 'dog', 'eel'},
      };
      expect(serverLists(), want);
      for (final d in [phone, tablet]) {
        expect(deviceLists(d), want, reason: d.name);
        expectQuiet(d, d.name);
      }
      final id =
          server
                  .liveRows('alice')
                  .firstWhere((r) => r['name'] == 'Later')['listId']
              as String;
      expect(server.entryKeys(id), hasLength(3));
    });
  }

  for (final deleterFirst in [true, false]) {
    for (final deleteLater in [true, false]) {
      fakeTimeTest('i: deleted offline on one device, edited offline on the '
          'other; the ${deleteLater ? 'delete' : 'edit'} is later, the '
          '${deleterFirst ? 'deleter' : 'editor'} comes back first', (t) async {
        final phone = TestDevice(server, 'phone');
        await phone.activate();
        await phone.addLocalList('Animals', ['cat']);
        await phone.signIn('alice');
        await phone.settle();
        final tablet = TestDevice(server, 'tablet');
        await tablet.activate();
        await tablet.signIn('alice');
        await tablet.settle();

        server.net.down();
        Future<void> delete() async {
          await phone.activate();
          await listsService.deleteList(list('Animals_words'));
        }

        Future<void> edit() async {
          await tablet.activate();
          await list('Animals_words').addVideo(video('dog'));
        }

        if (deleteLater) {
          await edit();
          await t.wait(const Duration(seconds: 30));
          await delete();
        } else {
          await delete();
          await t.wait(const Duration(seconds: 30));
          await edit();
        }
        server.net.up();
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
        expect(serverLists(), want);
        for (final d in [phone, tablet]) {
          expect(deviceLists(d), want, reason: d.name);
          expectQuiet(d, d.name);
        }
      });
    }
  }

  fakeTimeTest('j: a session found expired only when back online keeps the '
      'queued work, which goes up after signing in again', (t) async {
    final phone = TestDevice(server, 'phone');
    await phone.activate();
    await phone.addLocalList('Animals', ['cat']);
    await phone.signIn('alice');
    await phone.settle();
    server.net.down();
    await list('Animals_words').addVideo(video('dog'));
    await listsService.renameList(list('Animals_words'), 'Beasts');
    await sharing.accountSync.recordAnswers([answer('cat', 10)]);
    await listsService.createList('Birds');
    // The session expires on the server meanwhile.
    server.tokens.remove(phone.token);
    server.net.up();
    await sharing.accountSync.kick(SyncReason.resumed);
    await sharing.engine.pushAllDirty();
    expect(sharing.auth.store.current, isNull);
    expect(phone.localLists().keys, containsAll(['Beasts', 'Birds']));
    expect(phone.localLists()['Beasts'], ['cat', 'dog']);
    phone.token = null;
    await phone.signIn('alice');
    await phone.settle();
    expect(serverLists(), {
      'Favourites': <String>{},
      'Beasts': {'cat', 'dog'},
      'Birds': <String>{},
    });
    expect(serverAnswerCount(), 1);
    // The only thing shown: the expired session.
    expect(
      phone.engineNotices.where((n) => n != SyncNotification.sessionExpired),
      isEmpty,
    );
    expect(phone.notices.where((n) => n is! MergeCompletedNotice), isEmpty);
  });

  fakeTimeTest('k: the kill switch on and off mid-session', (t) async {
    final phone = TestDevice(server, 'phone');
    await phone.activate();
    await phone.addLocalList('Animals', ['cat']);
    await phone.addLocalList('Birds', ['owl']);
    await phone.signIn('alice');
    await phone.settle();

    server.accountSyncDisabled = true;
    await listsService.reorderLists(2, 0);
    await sharing.accountSync.kick(SyncReason.resumed);
    expect(sharing.accountSync.status, AccountSyncStatus.paused);
    // Lists still sync through their own /sync.
    await list('Animals_words').addVideo(video('dog'));
    await sharing.engine.pushAllDirty();
    expect(serverLists()['Animals'], {'cat', 'dog'});
    // Paused for its Retry-After, with nobody told.
    final before = accountRequests();
    await t.wait(const Duration(minutes: 30));
    expect(accountRequests(), before, reason: 'paused');
    expectQuiet(phone, 'kill switch');
    server.accountSyncDisabled = false;
    await t.wait(const Duration(minutes: 31));
    final order = phone.localLists().keys.toList();
    final rows = [...server.liveRows('alice')]
      ..sort((a, b) => (a['position'] as int).compareTo(b['position'] as int));
    expect(rows.map((r) => r['name']).toList(), order, reason: 'resumed');

    // Off again, then a pull to refresh goes through at once.
    server.accountSyncDisabled = true;
    await sharing.accountSync.kick(SyncReason.resumed);
    expect(sharing.accountSync.status, AccountSyncStatus.paused);
    server.accountSyncDisabled = false;
    await sharing.accountSync.recordAnswers([answer('cat', 5)]);
    await sharing.accountSync.kick(SyncReason.pullToRefresh);
    expect(serverAnswerCount(), 1);
    expect(sharing.accountSync.status, isNot(AccountSyncStatus.paused));
  });

  fakeTimeTest('l: lists made, renamed and deleted during a merge the black '
      'hole holds, then the network back: converged', (t) async {
    final phone = TestDevice(server, 'phone');
    await phone.activate();
    await phone.addLocalList('Animals', ['cat']);
    await phone.addLocalList('Gone', ['x']);
    server.net.blackhole();
    await phone.signIn('alice');
    await spin();
    expect(server.net.held, greaterThan(0));
    await t.instant(listsService.createList('Birds'), 'create');
    await spin();
    await t.instant(
      listsService.renameList(list('Animals_words'), 'Beasts'),
      'rename',
    );
    await spin();
    await t.instant(listsService.deleteList(list('Gone_words')), 'delete');
    await spin();
    await t.instant(list('Birds_words').addVideo(video('owl')), 'save');
    await backOnline(phone);
    expect(serverLists(), {
      'Favourites': <String>{},
      'Beasts': {'cat'},
      'Birds': {'owl'},
    });
    await expectAgreed(phone, when: 'after');
    expectQuiet(phone, 'l');
  });
}
