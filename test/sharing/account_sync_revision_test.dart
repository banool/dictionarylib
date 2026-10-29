import 'dart:collection';
import 'dart:convert';

import 'package:dictionarylib/common.dart';
import 'package:dictionarylib/entry_list.dart';
import 'package:dictionarylib/entry_types.dart';
import 'package:dictionarylib/flashcards_logic.dart';
import 'package:dictionarylib/globals.dart';
import 'package:dictionarylib/revision_history.dart';
import 'package:dictionarylib/saved_video.dart';
import 'package:dictionarylib/sharing/account_sync.dart';
import 'package:dictionarylib/sharing/synced_entry_list.dart';
import 'package:dictionarylib/sharing/synced_settings.dart';
import 'package:dolphinsr/dolphinsr.dart';
import 'package:flutter_test/flutter_test.dart';

import '../_helpers.dart';
import '../_recording_prefs.dart';
import '_account_sync_harness.dart';
import '_fake_account_server.dart';

/// Revision progress and settings on every device (section 5.8 of the
/// plan): the one writer of the history, the upload queue, resets, random
/// mode and the synced settings, against the in-memory server.
void main() {
  late FakeAccountServer server;

  setUpAll(installFakeSecureStorage);

  setUp(() {
    seedDictionary(const []);
    server = FakeAccountServer();
    communityEntryListManager = DummyEntryListManager();
  });

  tearDown(() {
    TestDevice(server, 'none').deactivate();
  });

  Future<TestDevice> freshDevice(String name) async {
    final d = TestDevice(server, name);
    await d.activate();
    return d;
  }

  /// A device that has signed in as alice and finished its merge.
  Future<TestDevice> signedIn(String name) async {
    final d = await freshDevice(name);
    await d.signIn('alice');
    await d.settle();
    expect(sharing.accountSync.isActive, isTrue);
    return d;
  }

  List<Map<String, dynamic>> serverAnswers([String user = 'alice']) =>
      (server.account(user)['reviews'] as List).cast<Map<String, dynamic>>();

  Set<String> serverAnswerIds([String user = 'alice']) => {
    for (final r in serverAnswers(user)) '${r['m']}|${r['c']}|${r['t']}',
  };

  Set<String> localAnswerIds() => {
    for (final r in reviewHistory.read())
      '${r.master}|${reviewToWire(r)['c']}|${r.ts!.microsecondsSinceEpoch}',
  };

  int serverRandomTotal([String user = 'alice']) {
    var total = 0;
    for (final s in server.account(user)['randomSessions'] as List) {
      total += s['count'] as int;
    }
    return total;
  }

  /// What Settings' "Delete all revision progress" does.
  Future<void> resetAsSettingsDoes(int nowUs) async {
    await sharing.accountSync.recordReset(nowUs);
    await reviewHistory.reset(nowUs);
    await sharedPreferences.setInt(KEY_RANDOM_REVIEWS_COUNTER, 0);
    await sharedPreferences.remove(KEY_FIRST_RANDOM_REVIEW);
  }

  /// Every `addReviews` op sent, as (op id, answer count), in order.
  List<(String, int)> watchAnswerUploads() {
    final sent = <(String, int)>[];
    server.failBefore = (req) {
      if (req.url.path == '/v1/account/sync') {
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        for (final op in (body['ops'] as List).cast<Map<String, dynamic>>()) {
          if (op['type'] == 'addReviews') {
            final args = op['args'] as Map<String, dynamic>;
            sent.add((op['opId'] as String, (args['reviews'] as List).length));
          }
        }
      }
      return false;
    };
    return sent;
  }

  group('the history has one writer', () {
    test('answers arriving during a session are kept when it ends', () async {
      await installPrefs({});
      await reviewHistory.appendLocal([
        _answer('a', 1),
        _answer('b', 2),
      ], queueForUpload: false);
      // A session starts with what is stored then...
      final atStart = reviewHistory.read();
      // ...answers from another device arrive while it is open...
      expect(await reviewHistory.mergeRemote([_answer('c', 3)]), 1);
      // ...and it ends. Before account sync the page wrote back
      // `atStart + its answers`, which would drop c.
      final session = [_answer('d', 4), _answer('e', 5)];
      expect(
        [...atStart, ...session].map(encodeReview),
        isNot(contains(encodeReview(_answer('c', 3)))),
      );
      await reviewHistory.appendLocal(session, queueForUpload: false);
      expect(reviewHistory.read().map((r) => r.master).toSet(), {
        for (final k in ['a', 'b', 'c', 'd', 'e']) _master(k),
      });
    });

    test('a session ending while answers arrive loses neither', () async {
      await installPrefs({});
      final version = reviewHistory.version.value;
      await Future.wait([
        reviewHistory.appendLocal([
          _answer('a', 1),
          _answer('b', 2),
        ], queueForUpload: true),
        reviewHistory.mergeRemote([_answer('c', 3), _answer('d', 4)]),
        reviewHistory.appendLocal([_answer('e', 5)], queueForUpload: true),
      ]);
      expect(reviewHistory.read(), hasLength(5));
      // Only this device's own answers wait to go up.
      expect(reviewHistory.unsentCount, 3);
      expect(reviewHistory.version.value, greaterThan(version));
    });

    test('an answer already stored is not stored again', () async {
      await installPrefs({});
      await reviewHistory.appendLocal([_answer('a', 1)], queueForUpload: false);
      expect(
        await reviewHistory.mergeRemote([
          _answer('a', 1),
          // Same card and time with another rating is the same answer.
          _answer('a', 1, rating: Rating.Again),
          _answer('a', 2),
        ]),
        1,
      );
      expect(reviewHistory.read(), hasLength(2));
    });

    test('an older answer arriving after a newer one counts in its place', () {
      // Stored in arrival order: a newer answer from this device, then an
      // older one from another device that synced late.
      final now = DateTime.now();
      Review at(int daysAgo, Rating rating) => Review(
        master: _master('dog'),
        combination: _wordToSign,
        rating: rating,
        ts: now.subtract(Duration(days: daysAgo)),
      );
      final arrival = [at(1, Rating.Good), at(3, Rating.Again)];
      final inOrder = [at(3, Rating.Again), at(1, Rating.Good)];
      final a = _dolphin(['dog'], arrival).dolphin;
      final b = _dolphin(['dog'], inOrder).dolphin;
      final sa = a.summary();
      final sb = b.summary();
      expect(
        [sa.due, sa.later, sa.learning, sa.overdue],
        [sb.due, sb.later, sb.learning, sb.overdue],
      );
      // Neither answer was thrown away as out of order.
      expect(a.skippedOutOfOrderReviews, 0);
    });
  });

  group('answers go up', () {
    test('a session signed in reaches the account and other devices', () async {
      final phone = await signedIn('phone');
      await sharing.accountSync.recordAnswers([
        _answer('a', 1000),
        _answer('b', 2000),
      ]);
      expect(reviewHistory.unsentCount, 2);
      await phone.settle();
      expect(reviewHistory.unsentCount, 0);
      expect(serverAnswers(), hasLength(2));

      final tablet = await signedIn('tablet');
      expect(localAnswerIds(), serverAnswerIds());
      await sharing.accountSync.recordAnswers([_answer('c', 3000)]);
      await tablet.settle();
      expect(serverAnswers(), hasLength(3));
    });

    test(
      'the queue drains in batches of 500 with ids from their contents',
      () async {
        final phone = await signedIn('phone');
        final uploads = watchAnswerUploads();
        await sharing.accountSync.recordAnswers([
          for (var i = 0; i < 1200; i++) _answer('w$i', 1000 + i),
        ]);
        await phone.settle();
        expect(reviewHistory.unsentCount, 0);
        expect(serverAnswers(), hasLength(1200));
        expect(uploads.map((u) => u.$2), [500, 500, 200]);
        expect(uploads.map((u) => u.$1).toSet(), hasLength(3));
        expect(uploads.every((u) => u.$1.startsWith('reviews-')), isTrue);
      },
    );

    test('a kill before the account answered sends the same batch again, '
        'which is stored once', () async {
      final phone = await signedIn('phone');
      final uploads = watchAnswerUploads();
      var lost = 0;
      server.loseResponse = (req) =>
          req.url.path == '/v1/account/sync' &&
          req.body.contains('"addReviews"') &&
          lost++ == 0;
      await sharing.accountSync.recordAnswers([
        for (var i = 0; i < 10; i++) _answer('w$i', 1000 + i),
      ]);
      await sharing.accountSync.kick(SyncReason.pullToRefresh);
      // The server stored them; the device never heard.
      expect(serverAnswers(), hasLength(10));
      expect(reviewHistory.unsentCount, 10);
      // The app dies here and starts again.
      phone.deactivate();
      await phone.settle();
      expect(reviewHistory.unsentCount, 0);
      expect(serverAnswers(), hasLength(10));
      expect(uploads, hasLength(2));
      expect(uploads[0].$1, uploads[1].$1);
      expect(localAnswerIds(), serverAnswerIds());
    });

    test('signing in sends the whole history; the next device gets it, '
        'its own goes up and nothing is doubled', () async {
      final phone = await freshDevice('phone');
      await reviewHistory.appendLocal([
        _answer('a', 1000),
        _answer('b', 2000),
        _answer('c', 3000),
      ], queueForUpload: false);
      await phone.signIn('alice');
      await phone.settle();
      expect(serverAnswers(), hasLength(3));

      final tablet = await freshDevice('tablet');
      await reviewHistory.appendLocal([
        _answer('c', 3000),
        _answer('d', 4000),
      ], queueForUpload: false);
      await tablet.signIn('alice');
      await tablet.settle();
      expect(serverAnswers(), hasLength(4));
      expect(reviewHistory.read(), hasLength(4));

      await phone.settle();
      expect(reviewHistory.read(), hasLength(4));
      expect(localAnswerIds(), serverAnswerIds());

      // Signing out and in again on the phone sends it all again: the
      // account finds only duplicates.
      await sharing.signOut();
      expect(reviewHistory.read(), hasLength(4), reason: 'history stays');
      expect(sharedPreferences.getStringList(KEY_REVIEWS_UNSENT), isNull);
      await phone.signIn('alice');
      await phone.settle();
      expect(serverAnswers(), hasLength(4));
      expect(reviewHistory.read(), hasLength(4));
    });
  });

  group('resets', () {
    test('a reset elsewhere drops older answers here, keeps later ones, '
        'and late answers from before it are refused', () async {
      final now = DateTime.now().microsecondsSinceEpoch;
      final phone = await signedIn('phone');
      await sharing.accountSync.recordAnswers([_answer('a', now - 7200000000)]);
      await phone.settle();
      final tablet = await signedIn('tablet');
      expect(reviewHistory.read(), hasLength(1));

      // The tablet goes offline and answers a card an hour ago.
      server.failBefore = (_) => true;
      await sharing.accountSync.recordAnswers([_answer('b', now - 3600000000)]);
      await tablet.settle();
      server.failBefore = null;

      // The phone deletes all revision progress now.
      await phone.activate();
      await resetAsSettingsDoes(now);
      await phone.settle();
      expect(reviewHistory.read(), isEmpty);
      expect(serverAnswers(), isEmpty);

      // The tablet, still offline, answers another card after the reset.
      await tablet.activate();
      server.failBefore = (_) => true;
      await sharing.accountSync.recordAnswers([_answer('c', now + 60000000)]);
      await tablet.settle();
      server.failBefore = null;
      await tablet.settle();
      // The reset reached it: a and b are gone, c stays and went up.
      expect(reviewHistory.read().map((r) => r.master), [_master('c')]);
      expect(reviewHistory.unsentCount, 0);
      expect(serverAnswers().map((r) => r['m']), [_master('c')]);

      await phone.settle();
      expect(reviewHistory.read().map((r) => r.master), [_master('c')]);
    });

    test('a reset made before a device joined the account leaves its older '
        'answers on it', () async {
      final now = DateTime.now().microsecondsSinceEpoch;
      server.account('alice')['resetTsUs'] = now;
      final phone = await freshDevice('phone');
      await reviewHistory.appendLocal([
        _answer('a', now - 1000),
        _answer('b', now + 1000),
      ], queueForUpload: false);
      await phone.signIn('alice');
      await phone.settle();
      expect(reviewHistory.read(), hasLength(2));
      expect(reviewHistory.unsentCount, 0);
      expect(serverAnswers().map((r) => r['m']), [_master('b')]);
      await phone.settle();
      expect(reviewHistory.read(), hasLength(2));
    });

    test('a reset killed half way still resets this device', () async {
      final now = DateTime.now().microsecondsSinceEpoch;
      final phone = await signedIn('phone');
      await sharing.accountSync.recordAnswers([_answer('a', now - 1000)]);
      await phone.settle();
      // The account's op is queued, then the app dies before the device's
      // own reset.
      await sharing.accountSync.recordReset(now);
      phone.deactivate();
      await phone.settle();
      expect(reviewHistory.read(), isEmpty);
      expect(serverAnswers(), isEmpty);
    });
  });

  group('random mode', () {
    test('the progress page shows the account total, pending sessions '
        'included, and signing in again never counts a device twice', () async {
      final phone = await freshDevice('phone');
      await sharedPreferences.setInt(KEY_RANDOM_REVIEWS_COUNTER, 7);
      await sharedPreferences.setInt(KEY_FIRST_RANDOM_REVIEW, 1700000000);
      await phone.signIn('alice');
      await phone.settle();
      expect(serverRandomTotal(), 7);
      expect(sharing.accountSync.randomTotalWithPending, 7);

      server.failBefore = (_) => true;
      await bumpRandomReviewCounter(3);
      expect(sharing.accountSync.randomTotalWithPending, 10);
      await phone.settle();
      server.failBefore = null;
      expect(sharing.accountSync.randomTotalWithPending, 10);
      await phone.settle();
      expect(serverRandomTotal(), 10);
      expect(sharing.accountSync.randomTotalWithPending, 10);
      expect(sharedPreferences.getInt(KEY_RANDOM_REVIEWS_COUNTER), 10);

      await sharing.signOut();
      await phone.signIn('alice');
      await phone.settle();
      expect(serverRandomTotal(), 10);

      final tablet = await freshDevice('tablet');
      await sharedPreferences.setInt(KEY_RANDOM_REVIEWS_COUNTER, 2);
      await tablet.signIn('alice');
      await tablet.settle();
      expect(serverRandomTotal(), 12);
      expect(sharing.accountSync.randomTotalWithPending, 12);
    });

    test('a restored copy of a device counts nothing twice', () async {
      final phone = await signedIn('phone');
      server.failBefore = (_) => true;
      await bumpRandomReviewCounter(3);
      await sharing.accountSync.recordAnswers([
        _answer('a', 1000),
        _answer('b', 2000),
      ]);
      await phone.settle();
      server.failBefore = null;
      phone.deactivate();

      // A new phone restored from a backup of this one: the same queues,
      // a client id of its own.
      final restored =
          TestDevice(server, 'restored', prefs: Map.of(phone.prefs))
            ..token = phone.token
            ..userId = phone.userId;
      await restored.activate();
      await regenerateClientId();
      await restored.settle();
      await phone.settle();
      await restored.settle();
      expect(serverRandomTotal(), 3);
      expect(serverAnswers(), hasLength(2));
    });
  });

  group('settings', () {
    test('a value this build can\'t use is left alone, not stored or '
        'overwritten', () async {
      final phone = await signedIn('phone');
      await sharedPreferences.setInt(KEY_REVISION_CARD_LIMIT, 25);
      await sharedPreferences.setInt(KEY_REVISION_STRATEGY, 0);
      await phone.settle();
      // A newer build elsewhere stores values this one doesn't know.
      final settings = server.account('alice')['settings'] as Map;
      settings[KEY_REVISION_CARD_LIMIT] = {
        'key': KEY_REVISION_CARD_LIMIT,
        'value': '200',
        'seq': 1000,
      };
      settings[KEY_REVISION_STRATEGY] = {
        'key': KEY_REVISION_STRATEGY,
        'value': '"spaced"',
        'seq': 1001,
      };
      await phone.settle();
      expect(sharedPreferences.getInt(KEY_REVISION_CARD_LIMIT), 25);
      expect(sharedPreferences.getInt(KEY_REVISION_STRATEGY), 0);
      expect(settings[KEY_REVISION_CARD_LIMIT]['value'], '200');
      expect(settings[KEY_REVISION_STRATEGY]['value'], '"spaced"');
      // A device joining the account keeps its own too, without sending it
      // over the account's.
      final tablet = await freshDevice('tablet');
      await sharedPreferences.setInt(KEY_REVISION_CARD_LIMIT, 50);
      await tablet.signIn('alice');
      await tablet.settle();
      await tablet.settle();
      expect(sharedPreferences.getInt(KEY_REVISION_CARD_LIMIT), 50);
      expect(settings[KEY_REVISION_CARD_LIMIT]['value'], '200');
    });

    test('the last change, in the account\'s order, wins everywhere', () async {
      final phone = await signedIn('phone');
      await sharedPreferences.setInt(KEY_REVISION_CARD_LIMIT, 10);
      await phone.settle();
      final tablet = await signedIn('tablet');
      expect(sharedPreferences.getInt(KEY_REVISION_CARD_LIMIT), 10);

      // Both change it offline; the tablet comes back first.
      await sharedPreferences.setInt(KEY_REVISION_CARD_LIMIT, 25);
      await phone.activate();
      await sharedPreferences.setInt(KEY_REVISION_CARD_LIMIT, 50);
      await tablet.settle();
      await phone.settle();
      expect(sharedPreferences.getInt(KEY_REVISION_CARD_LIMIT), 50);
      await tablet.settle();
      expect(sharedPreferences.getInt(KEY_REVISION_CARD_LIMIT), 50);
      final setting =
          (server.account('alice')['settings'] as Map)[KEY_REVISION_CARD_LIMIT];
      expect(setting['value'], '50');
    });

    test('at sign-in the account\'s settings win, and the device\'s go up '
        'where the account has none', () async {
      final phone = await signedIn('phone');
      await sharedPreferences.setBool(KEY_SIGN_TO_WORD, false);
      await phone.settle();

      final tablet = await freshDevice('tablet');
      await sharedPreferences.setBool(KEY_SIGN_TO_WORD, true);
      await sharedPreferences.setString(KEY_REVISION_LANGUAGE_CODE, 'ta');
      await tablet.signIn('alice');
      await tablet.settle();
      expect(sharedPreferences.getBool(KEY_SIGN_TO_WORD), isFalse);
      expect(sharedPreferences.getString(KEY_REVISION_LANGUAGE_CODE), 'ta');
      await phone.settle();
      expect(sharedPreferences.getBool(KEY_SIGN_TO_WORD), isFalse);
      expect(sharedPreferences.getString(KEY_REVISION_LANGUAGE_CODE), 'ta');
    });

    test('lists to revise travel by account id; ones a device lacks are '
        'left out there and kept on the account', () async {
      final animals = server.createAccountList(
        'alice',
        'Animals',
        entries: [
          ['dog', videoFor('dog')],
        ],
      );
      communityEntryListManager = _Community(['community_birds']);
      final phone = await signedIn('phone');
      final phoneKey = sharing.lists.get(animals)!.key;
      await sharedPreferences.setStringList(KEY_LISTS_TO_REVIEW, [
        phoneKey,
        'community_birds',
        'Gone_words',
      ]);
      expect(encodeListsToReview([phoneKey, 'community_birds', 'Gone_words']), [
        'list:$animals',
        'community:community_birds',
        'local:Gone_words',
      ]);
      await phone.settle();
      final onAccount =
          (server.account('alice')['settings']
              as Map)[KEY_LISTS_TO_REVIEW]['value'];

      // The tablet has no community lists.
      communityEntryListManager = DummyEntryListManager();
      final tablet = await signedIn('tablet');
      final tabletKey = sharing.lists.get(animals)!.key;
      expect(sharedPreferences.getStringList(KEY_LISTS_TO_REVIEW), [tabletKey]);
      await tablet.settle();
      // The tablet's shorter selection didn't go back up.
      expect(
        (server.account('alice')['settings']
            as Map)[KEY_LISTS_TO_REVIEW]['value'],
        onAccount,
      );
      communityEntryListManager = _Community(['community_birds']);
      await phone.settle();
      expect(sharedPreferences.getStringList(KEY_LISTS_TO_REVIEW), [
        phoneKey,
        'community_birds',
        'Gone_words',
      ]);
    });
  });

  group('the session expired, the server rewound, the queue cleared', () {
    test('answers, random sessions and a reset made while the session has '
        'expired reach the account when the same person signs in', () async {
      final now = DateTime.now().microsecondsSinceEpoch;
      final phone = await signedIn('phone');
      server.tokens.remove(phone.token);
      await sharing.accountSync.kick(SyncReason.pullToRefresh);
      expect(sharing.auth.store.current, isNull);
      await sharing.accountSync.recordAnswers([_answer('a', now - 1000)]);
      await bumpRandomReviewCounter(3);
      await phone.signIn('alice');
      await phone.settle();
      expect(serverAnswers().map((r) => r['m']), [_master('a')]);
      expect(serverRandomTotal(), 3);

      server.tokens.remove(phone.token);
      await sharing.accountSync.kick(SyncReason.pullToRefresh);
      await resetAsSettingsDoes(DateTime.now().microsecondsSinceEpoch);
      await phone.signIn('alice');
      await phone.settle();
      expect(serverAnswers(), isEmpty);
      expect(serverRandomTotal(), 0);
    });

    test(
      'a server restored to an earlier point gets every answer again',
      () async {
        final phone = await signedIn('phone');
        final earlier = server.clone();
        await sharing.accountSync.recordAnswers([
          _answer('a', 1000),
          _answer('b', 2000),
        ]);
        await phone.settle();
        expect(serverAnswers(), hasLength(2));
        // Point-in-time recovery to before the answers.
        server.accounts = earlier.accounts;
        expect(serverAnswers(), isEmpty);
        await phone.settle();
        expect(serverAnswers(), hasLength(2));
        expect(reviewHistory.read(), hasLength(2));
        // A device signing in now gets them.
        await signedIn('tablet');
        expect(reviewHistory.read(), hasLength(2));
      },
    );

    test('clearing the queue keeps answers the history lacks', () async {
      await installPrefs({
        KEY_STORED_REVIEWS: [encodeReview(_answer('a', 1))],
        KEY_REVIEWS_UNSENT: [
          encodeReview(_answer('a', 1)),
          encodeReview(_answer('b', 2)),
        ],
      });
      await reviewHistory.clearUnsent();
      expect(reviewHistory.read().map((r) => r.master), [
        _master('a'),
        _master('b'),
      ]);
      expect(reviewHistory.unsentCount, 0);
    });

    test('signing out sends the answers still queued', () async {
      final phone = await signedIn('phone');
      server.failBefore = (_) => true;
      await sharing.accountSync.recordAnswers([_answer('a', 1000)]);
      await phone.settle();
      server.failBefore = null;
      expect(reviewHistory.unsentCount, 1);
      await sharing.signOut();
      // The parting flush goes in the background, after signing out.
      for (var i = 0; i < 200 && serverAnswers().isEmpty; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(serverAnswers(), hasLength(1));
      expect(reviewHistory.read(), hasLength(1));
    });

    test(
      'more random-mode cards than one session holds go up whole, once',
      () async {
        final phone = await freshDevice('phone');
        await sharedPreferences.setInt(KEY_RANDOM_REVIEWS_COUNTER, 25000);
        await phone.signIn('alice');
        await phone.settle();
        expect(serverRandomTotal(), 25000);
        await sharing.signOut();
        await phone.signIn('alice');
        await phone.settle();
        expect(serverRandomTotal(), 25000);
      },
    );
  });

  group('a kill at any point of the merge and upload', () {
    test('the account ends with every answer, the random count and the '
        'settings, once', () async {
      final setup = await freshDevice('setup');
      await reviewHistory.appendLocal([
        for (var i = 0; i < 600; i++) _answer('w$i', 1000 + i),
      ], queueForUpload: false);
      await sharedPreferences.setInt(KEY_RANDOM_REVIEWS_COUNTER, 5);
      await sharedPreferences.setInt(KEY_REVISION_CARD_LIMIT, 25);
      setup.deactivate();
      final initial = setup.prefs;
      final token = server.signIn('alice');

      final server0 = server.clone();
      final snapshots = <FakeAccountServer>[];
      final original = TestDevice(server, 'original', prefs: initial)
        ..token = token
        ..userId = 'alice';
      await original.activate(onWrite: () => snapshots.add(server.clone()));
      await original.settle();
      final writes = List.of(original.store!.writes);
      final finalServer = server.clone();
      original.deactivate();
      expect(writes.length, snapshots.length);

      for (var k = 0; k <= writes.length; k++) {
        for (final serverAfter in [false, true]) {
          final base = serverAfter
              ? (k == writes.length ? finalServer : snapshots[k])
              : (k == 0 ? server0 : snapshots[k - 1]);
          final s = base.clone();
          final label =
              'killed after $k of ${writes.length} writes, '
              'server ${serverAfter ? 'after' : 'before'}';
          final d =
              TestDevice(s, label, prefs: replayWrites(initial, writes, k))
                ..token = token
                ..userId = 'alice';
          await d.settle(rounds: 6);
          final acc = s.account('alice');
          final answers = (acc['reviews'] as List).cast<Map<String, dynamic>>();
          expect(answers, hasLength(600), reason: '$label: answers');
          expect(
            answers.map((r) => '${r['m']}${r['t']}').toSet(),
            hasLength(600),
            reason: '$label: answers once',
          );
          expect(reviewHistory.read(), hasLength(600), reason: label);
          expect(reviewHistory.unsentCount, 0, reason: '$label: queue');
          var random = 0;
          for (final r in acc['randomSessions'] as List) {
            random += r['count'] as int;
          }
          expect(random, 5, reason: '$label: random count');
          expect(
            (acc['settings'] as Map)[KEY_REVISION_CARD_LIMIT]?['value'],
            '25',
            reason: '$label: setting',
          );
          d.deactivate();
        }
      }
    });
  });
}

const _wordToSign = Combination(front: [0], back: [1]);

String _master(String key) =>
    savedVideoMasterId(SavedVideo(entryKey: key, mediaPath: videoFor(key)));

/// An answer to [key]'s word-to-sign card at [tsUs].
Review _answer(String key, int tsUs, {Rating rating = Rating.Good}) => Review(
  master: _master(key),
  combination: _wordToSign,
  rating: rating,
  ts: DateTime.fromMicrosecondsSinceEpoch(tsUs),
);

DolphinInformation _dolphin(List<String> words, List<Review> stored) {
  final signs = [
    for (final word in words)
      () {
        final entry = FakeEntry(word, videos: [videoFor(word)]);
        return ResolvedSavedVideo(
          video: SavedVideo(entryKey: word, mediaPath: videoFor(word)),
          entry: entry,
          subEntry: entry.getSubEntries().single,
          videoUrl: urlFor(word),
        );
      }(),
  ];
  final masters = getMastersFromVideos(LOCALE_ENGLISH, signs, true, false);
  return getDolphinInformationFromVideos(signs, masters, reviews: stored);
}

class _Community implements EntryListManager {
  final List<String> keys;
  _Community(this.keys);

  @override
  LinkedHashMap<String, EntryList> getEntryLists() => LinkedHashMap.of({
    for (final k in keys) k: EntryList(k, LinkedHashSet<SavedVideo>(), false),
  });
}
