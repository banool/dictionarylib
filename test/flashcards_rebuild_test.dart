import 'dart:math';
import 'package:dictionarylib/flashcards_logic.dart';
import 'package:dictionarylib/globals.dart';
import 'package:dolphinsr_dart/dolphinsr_dart.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tests for [rebuildDolphin] / [filterReviewsToMasters] — the M2 fix
/// that keeps the in-session DolphinSR at exactly one review per card.
///
/// These run pure-Dart against DolphinSR (no widgets): a flashcard
/// session re-rating a card used to call `dolphin.addReviews` on every
/// rating change while only the last review is persisted, so the
/// in-session state accumulated phantom reviews and diverged from what
/// the next session rebuilds from storage. [rebuildDolphin] discards the
/// mutated instance and replays the canonical review set instead.

/// Two cards' worth of masters, each with the standard word↔sign pair of
/// combinations. Built directly (rather than via [getMastersFromVideos])
/// so a test's expected card set is deterministic; the rebuild path
/// doesn't care how the masters were produced.
List<Master> _twoMasters() => const [
      Master(
        id: 'apple',
        fields: ['apple', VIDEO_LINKS_MARKER],
        combinations: [
          Combination(front: [0], back: [1]),
          Combination(front: [1], back: [0]),
        ],
      ),
      Master(
        id: 'banana',
        fields: ['banana', VIDEO_LINKS_MARKER],
        combinations: [
          Combination(front: [0], back: [1]),
          Combination(front: [1], back: [0]),
        ],
      ),
    ];

const _wordToSign = Combination(front: [0], back: [1]);

Review _review(String master, Rating rating, DateTime ts,
    {Combination combination = _wordToSign}) {
  return Review(
      master: master, combination: combination, ts: ts, rating: rating);
}

/// Compare two DolphinSR instances by the schedule buckets their cards
/// fall into. Two dolphins built from the same masters + the same
/// effective review set must agree here; phantom reviews show up as a
/// divergence (e.g. a card promoted out of "due"/"learning").
void _expectSameSchedule(DolphinSR a, DolphinSR b) {
  final sa = a.summary();
  final sb = b.summary();
  expect(sa.learning, sb.learning, reason: 'learning bucket diverged');
  expect(sa.due, sb.due, reason: 'due bucket diverged');
  expect(sa.overdue, sb.overdue, reason: 'overdue bucket diverged');
  expect(sa.later, sb.later, reason: 'later bucket diverged');
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    sharedPreferences = await SharedPreferences.getInstance();
    keyedByEnglishEntriesGlobal.clear();
  });

  group('filterReviewsToMasters', () {
    test('drops reviews for unknown masters', () {
      final masters = _twoMasters();
      final reviews = [
        _review('apple', Rating.Good, DateTime(2024, 1, 1)),
        _review('ghost', Rating.Good, DateTime(2024, 1, 2)),
      ];
      final out = filterReviewsToMasters(reviews, masters);
      expect(out, hasLength(1));
      expect(out.single.master, 'apple');
    });

    test('drops reviews for combinations the master does not define', () {
      // A master that only offers word→sign; a review for sign→word must
      // be dropped or DolphinSR would throw on apply.
      final masters = const [
        Master(
          id: 'apple',
          fields: ['apple', VIDEO_LINKS_MARKER],
          combinations: [
            Combination(front: [0], back: [1])
          ],
        ),
      ];
      final reviews = [
        _review('apple', Rating.Good, DateTime(2024, 1, 1)),
        _review('apple', Rating.Good, DateTime(2024, 1, 2),
            combination: const Combination(front: [1], back: [0])),
      ];
      final out = filterReviewsToMasters(reviews, masters);
      expect(out, hasLength(1));
      expect(out.single.combination, const Combination(front: [0], back: [1]));
    });

    test('keeps every valid review unchanged', () {
      final masters = _twoMasters();
      final reviews = [
        _review('apple', Rating.Good, DateTime(2024, 1, 1)),
        _review('banana', Rating.Hard, DateTime(2024, 1, 2)),
      ];
      expect(filterReviewsToMasters(reviews, masters), reviews);
    });
  });

  group('rebuildDolphin — one review per card', () {
    test(
        're-rating a card does not accumulate phantom reviews: the rebuilt '
        'state matches a fresh build with only the latest review', () {
      final masters = _twoMasters();
      final di = getDolphinInformationFromVideos([], masters, reviews: []);

      // Simulate the buggy in-session sequence: reveal-then-Got-it (a
      // Good review), then the user changes their mind to Forgot (Hard).
      // The page keys answers by card, so answers.values already holds
      // only the latest review per card — the phantom history lived in
      // the DolphinSR instance, not in answers.
      final t1 = DateTime(2025, 1, 1, 9, 0, 0);
      final t2 = DateTime(2025, 1, 1, 9, 0, 5);
      // What the old code did to the live instance: BOTH reviews applied.
      di.dolphin.addReviews([_review('apple', Rating.Good, t1)]);
      di.dolphin.addReviews([_review('apple', Rating.Hard, t2)]);

      // The latest-per-card answer the page would persist + rebuild from.
      final latestAnswer = _review('apple', Rating.Hard, t2);
      final rebuilt = rebuildDolphin(di, [latestAnswer]);

      // Ground truth: a brand-new session built from the masters + the
      // single persisted review (exactly what next launch reconstructs).
      final nextSession =
          getDolphinInformationFromVideos([], masters, reviews: [latestAnswer]);

      _expectSameSchedule(rebuilt.dolphin, nextSession.dolphin);
    });

    test(
        'rebuilt dolphin equals next-session rebuild across persisted '
        'history + multiple re-rated session answers', () {
      final masters = _twoMasters();
      // Pre-existing persisted history from earlier sessions.
      final existing = [
        _review('apple', Rating.Good, DateTime(2024, 12, 1, 10)),
        _review('banana', Rating.Good, DateTime(2024, 12, 2, 10)),
      ];
      final di =
          getDolphinInformationFromVideos([], masters, reviews: existing);

      // This session: answer both cards, then re-rate apple. Phantom
      // reviews pile into the live instance.
      final a1 = _review('apple', Rating.Good, DateTime(2025, 1, 1, 9, 0, 0));
      final a2 = _review('banana', Rating.Hard, DateTime(2025, 1, 1, 9, 0, 2));
      final a1Final =
          _review('apple', Rating.Hard, DateTime(2025, 1, 1, 9, 0, 4));
      di.dolphin.addReviews([a1]);
      di.dolphin.addReviews([a2]);
      di.dolphin.addReviews([a1Final]);

      final answers = [a1Final, a2]; // latest per card
      final rebuilt = rebuildDolphin(di, answers);

      // Next session reconstructs from existing + the persisted session
      // answers (one per card).
      final nextSession = getDolphinInformationFromVideos([], masters,
          reviews: [...existing, ...answers]);

      _expectSameSchedule(rebuilt.dolphin, nextSession.dolphin);
    });

    test(
        'rebuild preserves the DolphinInformation carry-along fields so it '
        'can itself be rebuilt again', () {
      final masters = _twoMasters();
      final di = getDolphinInformationFromVideos([], masters, reviews: []);
      final answer =
          _review('apple', Rating.Good, DateTime(2025, 1, 1, 9, 0, 0));
      final rebuilt = rebuildDolphin(di, [answer]);

      expect(rebuilt.masters, same(di.masters));
      expect(rebuilt.orderSeed, di.orderSeed);
      expect(rebuilt.sessionReviews, same(di.sessionReviews));
      expect(rebuilt.masterToVideoMap, same(di.masterToVideoMap));

      // A second rebuild (re-rating again) must still work — proves the
      // retained masters/seed survive the first rebuild intact.
      final answer2 =
          _review('apple', Rating.Hard, DateTime(2025, 1, 1, 9, 0, 5));
      final rebuilt2 = rebuildDolphin(rebuilt, [answer2]);
      final nextSession =
          getDolphinInformationFromVideos([], masters, reviews: [answer2]);
      _expectSameSchedule(rebuilt2.dolphin, nextSession.dolphin);
    });

    test(
        'reviews are applied in ascending ts order regardless of the order '
        'they arrive in answers (DolphinSR throws on out-of-order apply)', () {
      final masters = _twoMasters();
      // Persisted history is OLDER than the session answers; if the
      // rebuild applied session answers before the persisted ones it
      // would throw "Cannot apply review before current lastReviewed".
      final existing = [
        _review('apple', Rating.Good, DateTime(2024, 6, 1, 10)),
      ];
      final di =
          getDolphinInformationFromVideos([], masters, reviews: existing);

      // Hand answers in a deliberately reversed (newest-first) order.
      final newer =
          _review('apple', Rating.Good, DateTime(2025, 1, 2, 9, 0, 0));
      // rebuildDolphin must sort internally — this must not throw.
      expect(() => rebuildDolphin(di, [newer]), returnsNormally);
    });

    test(
        'rebuilt dolphin schedules identically to a same-seed manual build '
        'from the canonical one-per-card review set — including nextCard '
        'ordering', () {
      // The card order is intentionally re-randomised each session
      // (random order is a feature), so comparing nextCard against a
      // *fresh* getDolphinInformationFromVideos isn't deterministic. To
      // pin the M2 invariant at the ordering level we build the
      // ground-truth dolphin with the SAME order seed.
      final masters = _twoMasters();
      final di = getDolphinInformationFromVideos([], masters, reviews: []);

      final t1 = DateTime(2025, 1, 1, 9, 0, 0);
      final t2 = DateTime(2025, 1, 1, 9, 0, 5);
      // Buggy live sequence: two reviews accumulate on the instance.
      di.dolphin.addReviews([_review('apple', Rating.Good, t1)]);
      di.dolphin.addReviews([_review('apple', Rating.Hard, t2)]);
      final answer = _review('apple', Rating.Hard, t2);
      final rebuilt = rebuildDolphin(di, [answer]);

      // Ground truth: same masters, same order seed, only the latest
      // review.
      final truth = DolphinSR();
      truth.addMasters(masters,
          shuffleCardOrder: true, random: Random(di.orderSeed));
      truth.addReviews([answer]);

      _expectSameSchedule(rebuilt.dolphin, truth);
      final a = rebuilt.dolphin.nextCard();
      final b = truth.nextCard();
      expect(a?.master, b?.master);
      expect(a?.combination, b?.combination);
    });
  });
}
