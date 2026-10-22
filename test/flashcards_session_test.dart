import 'dart:math';

import 'package:dictionarylib/flashcards_logic.dart';
import 'package:dictionarylib/revision.dart';
import 'package:dolphinsr/dolphinsr.dart';
import 'package:flutter_test/flutter_test.dart';

/// Which cards a revision session goes through ([getSessionCards]), and what
/// each answer does to when a card comes round again.
///
/// These run pure-Dart against DolphinSR (no widgets), with the clock handed
/// in so nothing depends on the day or hour the tests run at.

const _wordToSign = Combination(front: [0], back: [1]);
const _signToWord = Combination(front: [1], back: [0]);

Master _master(String id, {bool bothWays = false}) => Master(
  id: id,
  fields: [id, VIDEO_LINKS_MARKER],
  combinations: [_wordToSign, if (bothWays) _signToWord],
);

Review _review(
  String master,
  Rating rating,
  DateTime ts, {
  Combination combination = _wordToSign,
}) {
  return Review(
    master: master,
    combination: combination,
    ts: ts,
    rating: rating,
  );
}

/// A Tuesday afternoon, well away from any clock change.
final DateTime _now = DateTime(2026, 3, 10, 14, 30);

/// [days] calendar days before or after [_now], at the same time of day.
DateTime _day(int days, {int minutes = 0}) => DateTime(
  _now.year,
  _now.month,
  _now.day + days,
  _now.hour,
  _now.minute + minutes,
);

/// What the app builds before a session: the cards, then the stored history
/// replayed in order.
DolphinSR _dolphin(
  List<Master> masters,
  List<Review> stored, {
  required DateTime now,
  int seed = 1,
}) {
  final dolphin = DolphinSR(
    now: () => now,
    outOfOrderReviewPolicy: OutOfOrderReviewPolicy.skip,
  );
  dolphin.addMasters(masters, shuffleCardOrder: true, random: Random(seed));
  dolphin.addReviews([...stored]..sort((a, b) => a.ts!.compareTo(b.ts!)));
  return dolphin;
}

String _id(DRCard card) =>
    '${card.master} ${card.combination!.front}>${card.combination!.back}';

/// The masters of the cards a spaced-repetition session started at [now]
/// would go through, in order.
List<String> _session(
  List<Master> masters,
  List<Review> stored, {
  required DateTime now,
  int seed = 1,
}) => [
  for (final card in getSessionCards(
    _dolphin(masters, stored, now: now, seed: seed),
    RevisionStrategy.SpacedRepetition,
    now: now,
  ))
    card.master!,
];

/// The cards DolphinSR itself hands out, in its order, found by asking it
/// for the next card over and over and answering each "Easy", which is the
/// one answer that takes any card out of the running for the rest of the
/// day.
List<String> _servedByDolphin(DolphinSR dolphin, DateTime now) {
  final served = <String>[];
  while (true) {
    final card = dolphin.nextCard();
    if (card == null) break;
    served.add(_id(card));
    expect(
      served.length,
      lessThanOrEqualTo(dolphin.cardsLength()),
      reason: 'DolphinSR served a card twice: ${served.last}',
    );
    final last = card.lastReviewed;
    dolphin.addReviews([
      Review(
        master: card.master,
        combination: card.combination,
        rating: Rating.Easy,
        ts: last != null && last.isAfter(now) ? last : now,
      ),
    ]);
  }
  return served;
}

/// Days the clocks go forward or back in Europe, North America and
/// Australia (UTC dates, used only for their year, month and day). Which of
/// them matter depends on where the tests are run.
final List<DateTime> _clockChanges = [
  DateTime.utc(2025, 3, 30),
  DateTime.utc(2025, 10, 26),
  DateTime.utc(2026, 3, 29),
  DateTime.utc(2026, 10, 25),
  DateTime.utc(2026, 3, 8),
  DateTime.utc(2026, 11, 1),
  DateTime.utc(2026, 4, 5),
  DateTime.utc(2026, 10, 4),
];

/// A deck with every kind of history in it: cards never seen, cards part
/// way through being learned, cards resting, due, long overdue and
/// forgotten, some reviewed at the same instant as each other, and always
/// one each that fell due yesterday, falls due today and falls due tomorrow.
(List<Master>, List<Review>) _generatedDeck(Random random, DateTime now) {
  const ratings = [
    Rating.Good,
    Rating.Good,
    Rating.Good,
    Rating.Good,
    Rating.Again,
    Rating.Again,
    Rating.Hard,
    Rating.Easy,
  ];
  final masters = <Master>[];
  final reviews = <Review>[];
  final count = 1 + random.nextInt(25);
  for (var i = 0; i < count; i++) {
    final master = _master('sign$i', bothWays: random.nextBool());
    masters.add(master);
    for (final combination in master.combinations!) {
      // Minutes before now, walking forwards from up to ten months back.
      var minutesAgo = random.nextInt(300 * 24 * 60);
      for (var n = random.nextInt(7); n > 0 && minutesAgo > 0; n--) {
        reviews.add(
          _review(
            master.id!,
            ratings[random.nextInt(ratings.length)],
            now.subtract(Duration(minutes: minutesAgo)),
            combination: combination,
          ),
        );
        // The next one any time from the same minute to a month later.
        minutesAgo -= random.nextInt(30 * 24 * 60);
      }
    }
  }
  // Two correct answers a day apart earn four days, counted by the calendar
  // from the second: answered five, four and three days ago, these are due
  // a day ago, today and in a day.
  for (final (i, lastAnswered) in [5, 4, 3].indexed) {
    final master = _master('boundary$i');
    masters.add(master);
    for (final daysAgo in [lastAnswered + 1, lastAnswered]) {
      reviews.add(
        _review(
          master.id!,
          Rating.Good,
          DateTime(
            now.year,
            now.month,
            now.day - daysAgo,
            random.nextInt(24),
            random.nextInt(60),
          ),
        ),
      );
    }
  }
  return (masters, reviews);
}

void main() {
  group('filterReviewsToMasters', () {
    test('drops reviews for unknown masters', () {
      final masters = [_master('apple', bothWays: true), _master('banana')];
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
      final masters = [_master('apple')];
      final reviews = [
        _review('apple', Rating.Good, DateTime(2024, 1, 1)),
        _review(
          'apple',
          Rating.Good,
          DateTime(2024, 1, 2),
          combination: _signToWord,
        ),
      ];
      final out = filterReviewsToMasters(reviews, masters);
      expect(out, hasLength(1));
      expect(out.single.combination, _wordToSign);
    });

    test('keeps every valid review unchanged', () {
      final masters = [_master('apple'), _master('banana')];
      final reviews = [
        _review('apple', Rating.Good, DateTime(2024, 1, 1)),
        _review('banana', Rating.Again, DateTime(2024, 1, 2)),
      ];
      expect(filterReviewsToMasters(reviews, masters), reviews);
    });
  });

  group('getSessionCards, spaced repetition', () {
    test('is the cards DolphinSR counts as due, in the order it serves them '
        'but with the ones never shown moved to the end, for any deck on any '
        'day at any time', () {
      for (var seed = 0; seed < 400; seed++) {
        final random = Random(seed);
        // Any minute of any day over three years, and for a third of the
        // decks a day the clocks change somewhere, or the day after. Cards
        // fall due by calendar day, so those days, and the minutes either
        // side of midnight, are the ones to get wrong.
        final day = seed % 3 == 0
            ? _clockChanges[random.nextInt(_clockChanges.length)].add(
                Duration(days: random.nextInt(2)),
              )
            : DateTime.utc(2025, 1, 1 + random.nextInt(3 * 365));
        final now = DateTime(
          day.year,
          day.month,
          day.day,
          random.nextInt(24),
          random.nextInt(60),
        );
        final (masters, reviews) = _generatedDeck(random, now);

        final dolphin = _dolphin(masters, reviews, now: now, seed: seed);
        final neverShown = {
          for (final card in dolphin.getAllCardState())
            if (card.lastReviewed == null) _id(card),
        };
        final cards = getSessionCards(
          dolphin,
          RevisionStrategy.SpacedRepetition,
          now: now,
        );

        final summary = dolphin.summary();
        expect(
          cards.length,
          summary.learning! + summary.overdue! + summary.due!,
          reason: 'deck $seed: not the number of cards DolphinSR has due',
        );
        final served = _servedByDolphin(
          _dolphin(masters, reviews, now: now, seed: seed),
          now,
        );
        expect(cards.map(_id).toList(), [
          ...served.where((id) => !neverShown.contains(id)),
          ...served.where(neverShown.contains),
        ], reason: 'deck $seed: not the cards, or the order, expected');
      }
    });

    test('has each card once', () {
      for (var seed = 0; seed < 50; seed++) {
        final (masters, reviews) = _generatedDeck(Random(seed), _now);
        final cards = getSessionCards(
          _dolphin(masters, reviews, now: _now, seed: seed),
          RevisionStrategy.SpacedRepetition,
          now: _now,
        );
        expect(cards.toSet(), hasLength(cards.length));
      }
    });

    test('puts cards part way through being learned first, then the overdue, '
        'then those due today, then the ones never shown, and leaves out '
        'the rest', () {
      final masters = [
        for (final id in ['resting', 'today', 'overdue', 'new', 'half'])
          _master(id),
      ];
      final stored = [
        // Answered correctly twice: given four days. This one a day ago...
        _review('resting', Rating.Good, _day(-2)),
        _review('resting', Rating.Good, _day(-1)),
        // ...this one four days ago, so due today...
        _review('today', Rating.Good, _day(-5)),
        _review('today', Rating.Good, _day(-4)),
        // ...and this one long enough ago to be overdue.
        _review('overdue', Rating.Good, _day(-10)),
        _review('overdue', Rating.Good, _day(-9)),
        // Answered correctly once: still being learned.
        _review('half', Rating.Good, _day(-1)),
      ];
      expect(_session(masters, stored, now: _now), [
        'half',
        'overdue',
        'today',
        'new',
      ]);
    });

    test('puts the cards never shown last, in the shuffled order they were '
        'set up in', () {
      final masters = [
        for (final id in ['a', 'b', 'c', 'd', 'e', 'f']) _master(id),
      ];
      final stored = [
        _review('b', Rating.Good, _day(-1)),
        _review('e', Rating.Good, _day(-2)),
      ];
      final dolphin = _dolphin(masters, stored, now: _now, seed: 5);
      final setUpOrder = [
        for (final card in dolphin.getAllCardState())
          if (card.master != 'b' && card.master != 'e') card.master!,
      ];
      expect(
        setUpOrder,
        isNot(['a', 'c', 'd', 'f']),
        reason: 'the seed should shuffle them',
      );
      expect(
        [
          for (final card in getSessionCards(
            dolphin,
            RevisionStrategy.SpacedRepetition,
            now: _now,
          ))
            card.master!,
        ],
        ['e', 'b', ...setUpOrder],
      );
    });

    // DolphinSR's own order has the cards never shown first. A session that
    // is capped takes its cards from the front, so a long list of new signs
    // kept everything else out until all of them had been seen once.
    test('has every card that was forgotten, is half learned or is due for '
        'review ahead of any number of cards never shown', () {
      final masters = [
        for (var i = 0; i < 300; i++) _master('new$i'),
        _master('forgotten'),
        _master('half'),
        _master('overdue'),
      ];
      final stored = [
        _review('forgotten', Rating.Good, _day(-12)),
        _review('forgotten', Rating.Good, _day(-11)),
        _review('forgotten', Rating.Again, _day(-1)),
        _review('half', Rating.Good, _day(-2)),
        _review('overdue', Rating.Good, _day(-10)),
        _review('overdue', Rating.Good, _day(-9)),
      ];
      final session = _session(masters, stored, now: _now);
      expect(session, hasLength(303));
      // What a session capped at ten would be given.
      expect(session.sublist(0, 3), ['half', 'forgotten', 'overdue']);
      expect(session.sublist(3, 10), everyElement(startsWith('new')));
    });
  });

  // A session used to ask DolphinSR for its next card each time, and a card
  // that is answered but still being learned is still the first thing it
  // has. Two new cards, which it put in front of three due ones, were shown
  // over and over, the three were never reached, and the session never
  // ended.
  group('a session with new cards and cards due for review', () {
    final masters = [
      for (final id in ['new1', 'new2', 'due1', 'due2', 'due3']) _master(id),
    ];
    final stored = [
      for (final (i, id) in ['due1', 'due2', 'due3'].indexed) ...[
        _review(id, Rating.Good, _day(-12, minutes: i)),
        _review(id, Rating.Good, _day(-11, minutes: i)),
      ],
    ];

    test('goes through each of them once, the new ones last', () {
      final session = _session(masters, stored, now: _now);
      expect(session, hasLength(5));
      expect(session.sublist(0, 3), ['due1', 'due2', 'due3']);
      expect(session.sublist(3), unorderedEquals(['new1', 'new2']));
    });

    test('leaves the new cards due afterwards, for a second look', () {
      // The session's answers, as it stores them: one per card.
      final afterSession = [
        ...stored,
        for (final (i, id) in ['new1', 'new2', 'due1', 'due2', 'due3'].indexed)
          _review(id, Rating.Good, _day(0, minutes: 1 + i)),
      ];
      expect(
        _session(masters, afterSession, now: _day(0, minutes: 10)),
        unorderedEquals(['new1', 'new2']),
      );

      // Answered correctly a second time, they rest like the others.
      final afterSecondLook = [
        ...afterSession,
        _review('new1', Rating.Good, _day(0, minutes: 11)),
        _review('new2', Rating.Good, _day(0, minutes: 12)),
      ];
      expect(
        _session(masters, afterSecondLook, now: _day(0, minutes: 20)),
        isEmpty,
      );
    });
  });

  // "Forgot" is stored as Rating.Again. It used to be stored as Rating.Hard,
  // which DolphinSR takes to mean "remembered, with difficulty" and answers
  // by making the card wait longer than it did before.
  group('a card that was due and is answered "Forgot"', () {
    final masters = [_master('apple'), _master('banana')];
    // Both learned eleven days ago, so both due.
    final learned = [
      for (final (i, id) in ['apple', 'banana'].indexed) ...[
        _review(id, Rating.Good, _day(-12, minutes: i)),
        _review(id, Rating.Good, _day(-11, minutes: i)),
      ],
    ];
    final forgotApple = [
      ...learned,
      _review('apple', Rating.Again, _now),
      _review('banana', Rating.Good, _day(0, minutes: 1)),
    ];

    test('is due again straight away', () {
      expect(_session(masters, forgotApple, now: _day(0, minutes: 5)), [
        'apple',
      ]);
    });

    test('stays due however long it is left', () {
      expect(_session(masters, forgotApple, now: _day(30)), contains('apple'));
    });

    test('is still due after one correct answer, and rests for four days '
        'after a second', () {
      final once = [
        ...forgotApple,
        _review('apple', Rating.Good, _day(0, minutes: 6)),
      ];
      expect(_session(masters, once, now: _day(0, minutes: 10)), ['apple']);
      expect(_session(masters, once, now: _day(1)), ['apple']);

      final twice = [...once, _review('apple', Rating.Good, _day(1))];
      expect(_session(masters, twice, now: _day(1, minutes: 5)), isEmpty);
      expect(_session(masters, twice, now: _day(4)), isEmpty);
      expect(_session(masters, twice, now: _day(5)), ['apple']);
    });

    test('goes back to being due if it is forgotten again part way', () {
      final history = [
        ...forgotApple,
        _review('apple', Rating.Good, _day(0, minutes: 6)),
        _review('apple', Rating.Again, _day(1)),
        _review('apple', Rating.Good, _day(1, minutes: 5)),
      ];
      // One correct answer since the second lapse: not enough yet.
      expect(_session(masters, history, now: _day(1, minutes: 10)), ['apple']);
    });

    test('would have been put off for longer by the Hard that "Forgot" used '
        'to send', () {
      final hard = [
        ...learned,
        _review('apple', Rating.Hard, _now),
        _review('banana', Rating.Good, _day(0, minutes: 1)),
      ];
      // Not just "not due today": further away than the four days it had.
      for (var days = 0; days <= 5; days++) {
        expect(
          _session(masters, hard, now: _day(days, minutes: 5)),
          isNot(contains('apple')),
          reason: 'day $days',
        );
      }
    });
  });

  group('a new card that is answered "Forgot"', () {
    final masters = [_master('apple')];

    test('stays due, and needs two correct answers after that', () {
      final forgot = [_review('apple', Rating.Again, _now)];
      expect(_session(masters, forgot, now: _day(0, minutes: 5)), ['apple']);

      final once = [
        ...forgot,
        _review('apple', Rating.Good, _day(0, minutes: 6)),
      ];
      expect(_session(masters, once, now: _day(0, minutes: 10)), ['apple']);

      final twice = [
        ...once,
        _review('apple', Rating.Good, _day(0, minutes: 11)),
      ];
      expect(_session(masters, twice, now: _day(0, minutes: 15)), isEmpty);
    });

    test('loses the correct answer it had', () {
      final history = [
        _review('apple', Rating.Good, _day(-1)),
        _review('apple', Rating.Again, _now),
        _review('apple', Rating.Good, _day(0, minutes: 5)),
      ];
      expect(_session(masters, history, now: _day(0, minutes: 10)), ['apple']);
    });
  });

  // Random revision used to draw from DolphinSR as well, which only ever
  // hands out cards that are due. Anyone who also used spaced repetition was
  // shown just those, and with nothing due the session ended as it began.
  group('getSessionCards, random revision', () {
    final masters = [
      for (final id in ['a', 'b', 'c', 'd', 'e']) _master(id, bothWays: true),
    ];
    // Every card learned in the last two days: nothing due for days.
    final stored = [
      for (final master in masters)
        for (final (i, combination) in master.combinations!.indexed) ...[
          _review(
            master.id!,
            Rating.Good,
            _day(-2, minutes: i),
            combination: combination,
          ),
          _review(
            master.id!,
            Rating.Good,
            _day(-1, minutes: i),
            combination: combination,
          ),
        ],
    ];

    test('is every card, whatever spaced repetition has scheduled', () {
      final dolphin = _dolphin(masters, stored, now: _now);
      expect(
        getSessionCards(dolphin, RevisionStrategy.SpacedRepetition, now: _now),
        isEmpty,
        reason: 'nothing is due',
      );
      final cards = getSessionCards(
        dolphin,
        RevisionStrategy.Random,
        now: _now,
      );
      expect(cards, hasLength(10));
      expect(cards.toSet(), hasLength(10));
      expect(cards.length, getNumDueCards(dolphin, RevisionStrategy.Random));
    });

    test('is in the shuffled order the cards were set up in, a different '
        'one for a different shuffle', () {
      List<String> order(int seed) => [
        for (final card in getSessionCards(
          _dolphin(masters, stored, now: _now, seed: seed),
          RevisionStrategy.Random,
          now: _now,
        ))
          _id(card),
      ];
      expect(order(3), order(3));
      expect(order(3), isNot(order(4)));
      expect(order(3), unorderedEquals(order(4)));
    });
  });
}
