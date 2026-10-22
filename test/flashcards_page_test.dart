import 'package:dictionarylib/common.dart';
import 'package:dictionarylib/entry_types.dart';
import 'package:dictionarylib/flashcards_logic.dart';
import 'package:dictionarylib/globals.dart';
import 'package:dictionarylib/l10n/app_localizations.dart';
import 'package:dictionarylib/page_flashcards.dart';
import 'package:dictionarylib/revision.dart';
import 'package:dictionarylib/saved_video.dart';
import 'package:dolphinsr/dolphinsr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '_helpers.dart';

/// A revision session, driven through the real page: which cards it shows,
/// when it ends, and what it stores.
///
/// Each sign's "video" here is a still image. The page shows those without a
/// video player, which is the part of it a widget test can't run. (The
/// on-device suites in dictionarylib_test_support cover the same ground with
/// real videos.)

/// The page asks the app's cache for each still image. Nothing can be
/// fetched in a test, and the real cache would go looking for the device's
/// storage, so this one fails every request on the spot and the page shows
/// its "couldn't load" notice where the image would be.
class _NoImages implements MyCacheManager {
  @override
  Stream<FileResponse> getImageFile(
    String url, {
    String? key,
    Map<String, String>? headers,
    bool withProgress = false,
    int? maxHeight,
    int? maxWidth,
  }) => Stream.error(StateError('No images in tests'));

  @override
  Stream<FileResponse> getFileStream(
    String url, {
    String? key,
    Map<String, String>? headers,
    bool withProgress = false,
  }) => Stream.error(StateError('No images in tests'));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _wordToSign = Combination(front: [0], back: [1]);

ResolvedSavedVideo _sign(String word) {
  final path = '/$word.jpg';
  final entry = FakeEntry(word, videos: [path]);
  return ResolvedSavedVideo(
    video: SavedVideo(entryKey: word, mediaPath: path),
    entry: entry,
    subEntry: entry.getSubEntries().single,
    videoUrl: '$kTestMediaBase$path',
  );
}

final DateTime _start = DateTime.now();

/// A stored answer for [word], [daysAgo] days before the tests started.
Review _stored(String word, Rating rating, int daysAgo, {int minutes = 0}) =>
    Review(
      master: savedVideoMasterId(_sign(word).video),
      combination: _wordToSign,
      rating: rating,
      ts: _start.subtract(Duration(days: daysAgo, minutes: -minutes)),
    );

/// Two correct answers, eleven days ago and the day before: learned, and
/// long since due again.
List<Review> _learnedAndDue(String word, {int minutes = 0}) => [
  _stored(word, Rating.Good, 12, minutes: minutes),
  _stored(word, Rating.Good, 11, minutes: minutes),
];

/// Two correct answers yesterday and the day before: learned, and not due
/// for days.
List<Review> _learnedAndResting(String word) => [
  _stored(word, Rating.Good, 2),
  _stored(word, Rating.Good, 1),
];

final FlashcardsConfig _config = FlashcardsConfig(
  videoAspectRatio: 16 / 9,
  navigateToEntryPage: (
    context,
    entry,
    showSaveButtons, {
    focusVideo,
    saveToList,
  }) async {},
  buildRegionInfo: (context, resolved, horizontal, revealed) =>
      const SizedBox.shrink(),
  regionRowHeight: 48,
);

DolphinInformation _dolphin(List<String> words, List<Review> stored) {
  final signs = [for (final word in words) _sign(word)];
  // Word → sign cards only: the word is on the card from the start, so a
  // test can tell which card it is looking at.
  final masters = getMastersFromVideos(LOCALE_ENGLISH, signs, true, false);
  return getDolphinInformationFromVideos(signs, masters, reviews: stored);
}

/// Open the session page as the landing page would, on a phone-sized screen.
Future<void> _startSession(
  WidgetTester tester,
  List<String> words, {
  List<Review> stored = const [],
  RevisionStrategy strategy = RevisionStrategy.SpacedRepetition,
  DolphinInformation? di,
}) async {
  tester.view.physicalSize = const Size(1206, 2622);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await sharedPreferences.setStringList(KEY_STORED_REVIEWS, [
    for (final review in stored) encodeReview(review),
  ]);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: DictLibLocalizations.localizationsDelegates,
      supportedLocales: DictLibLocalizations.supportedLocales,
      home: FlashcardsPage(
        di: di ?? _dolphin(words, stored),
        revisionStrategy: strategy,
        existingReviews: stored,
        config: _config,
      ),
    ),
  );
  await tester.pump();
}

final _reveal = find.byKey(const ValueKey('revealButton'));
final _gotIt = find.byKey(const ValueKey('ratingButton.gotIt'));
final _forgot = find.byKey(const ValueKey('ratingButton.forgot'));
final _next = find.byKey(const ValueKey('ratingButton.next'));
final _back = find.byIcon(Icons.chevron_left);
final _forward = find.byIcon(Icons.chevron_right);
final _summary = find.text('Revision summary');

/// Which of [words] is on the card showing.
String _showing(Iterable<String> words) =>
    words.singleWhere((word) => find.text(word).evaluate().isNotEmpty);

/// Reveal the card showing and answer it. "Forgot" holds the card for a
/// moment before moving on; this waits that out.
Future<void> _answer(WidgetTester tester, {bool forgot = false}) async {
  expect(_reveal, findsOneWidget, reason: 'the card came up already answered');
  await tester.tap(_reveal);
  await tester.pump();
  await tester.tap(forgot ? _forgot : _gotIt);
  await tester.pump();
  if (forgot) await tester.pump(const Duration(seconds: 1));
  await tester.pump();
}

/// What the stored history holds for [word], oldest first.
List<Rating> _ratingsFor(String word) => [
  for (final review in readReviews())
    if (review.master == savedVideoMasterId(_sign(word).video)) review.rating!,
];

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    sharedPreferences = await SharedPreferences.getInstance();
    mediaBaseUrls = const [kTestMediaBase];
    myCacheManager = _NoImages();
  });

  // The session used to take each card from DolphinSR as it went. A new card
  // is still the first thing DolphinSR has after one correct answer, so with
  // new cards and due ones together it showed the new ones over and over,
  // the counter ran past the total, and the session never ended.
  testWidgets('new cards and cards due for review are each shown once, the '
      'due ones first, and then the session ends', (tester) async {
    const words = ['due1', 'due2', 'due3', 'new1', 'new2'];
    final stored = [
      for (final (i, word) in ['due1', 'due2', 'due3'].indexed)
        ..._learnedAndDue(word, minutes: i),
    ];
    await _startSession(tester, words, stored: stored);

    final shown = <String>[];
    for (var k = 1; k <= 5; k++) {
      expect(find.text('$k / 5'), findsOneWidget);
      shown.add(_showing(words));
      await _answer(tester);
    }
    expect(_summary, findsOneWidget);
    expect(shown.sublist(0, 3), ['due1', 'due2', 'due3']);
    expect(shown.sublist(3), unorderedEquals(['new1', 'new2']));

    // One more answer stored for each.
    expect(readReviews(), hasLength(stored.length + 5));
    for (final word in words) {
      expect(_ratingsFor(word).last, Rating.Good, reason: word);
    }
  });

  testWidgets('"Forgot" is stored as Again, "Got it" as Good, and the card '
      'left on its default answer as Good', (tester) async {
    const words = ['apple', 'banana', 'cherry'];
    await _startSession(
      tester,
      words,
      stored: [
        ..._learnedAndDue('apple'),
        ..._learnedAndDue('banana', minutes: 1),
        ..._learnedAndDue('cherry', minutes: 2),
      ],
    );

    await _answer(tester, forgot: true); // apple
    await _answer(tester); // banana
    // cherry: revealed, then a tap on the card to move on.
    await tester.tap(_reveal);
    await tester.pump();
    await tester.tap(find.text('cherry'));
    await tester.pump();
    await tester.pump();

    expect(_summary, findsOneWidget);
    expect(_ratingsFor('apple'), [Rating.Good, Rating.Good, Rating.Again]);
    expect(_ratingsFor('banana'), [Rating.Good, Rating.Good, Rating.Good]);
    expect(_ratingsFor('cherry'), [Rating.Good, Rating.Good, Rating.Good]);

    // The forgotten card is due again straight away; the others are not.
    final next = getSessionCards(
      _dolphin(words, readReviews()).dolphin,
      RevisionStrategy.SpacedRepetition,
    );
    expect(next.map((card) => card.front!.single), ['apple']);
  });

  testWidgets('changing an answer after stepping back stores the new one '
      'only', (tester) async {
    const words = ['apple', 'banana'];
    await _startSession(
      tester,
      words,
      stored: [
        ..._learnedAndDue('apple'),
        ..._learnedAndDue('banana', minutes: 1),
      ],
    );

    await _answer(tester); // apple: Got it
    expect(find.text('2 / 2'), findsOneWidget);
    await tester.tap(_back);
    await tester.pump();
    expect(find.text('1 / 2'), findsOneWidget);
    expect(_showing(words), 'apple');
    // It comes back as it was answered, and this time it's "Forgot".
    expect(_reveal, findsNothing);
    await tester.tap(_forgot);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('2 / 2'), findsOneWidget);
    await _answer(tester); // banana

    expect(_summary, findsOneWidget);
    expect(_ratingsFor('apple'), [Rating.Good, Rating.Good, Rating.Again]);
    expect(readReviews(), hasLength(4 + 2));
  });

  // "Forgot" holds the card on screen for a moment before moving on. The
  // forward arrow, used in that moment, moves on by itself; the pending move
  // then fired as well, onto a card the user hadn't answered or, from the
  // last card, out of the session.
  testWidgets('the forward arrow during the pause after "Forgot" moves on '
      'once, not twice', (tester) async {
    const words = ['apple', 'banana', 'cherry'];
    await _startSession(
      tester,
      words,
      stored: [
        ..._learnedAndDue('apple'),
        ..._learnedAndDue('banana', minutes: 1),
        ..._learnedAndDue('cherry', minutes: 2),
      ],
    );

    await _answer(tester); // apple
    await _answer(tester); // banana
    expect(find.text('3 / 3'), findsOneWidget);
    await tester.tap(_back);
    await tester.pump();
    expect(_showing(words), 'banana');
    await tester.tap(_forgot);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(_forward);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('3 / 3'), findsOneWidget);

    // Well past the pause: still on the third card, which still wants an
    // answer.
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('3 / 3'), findsOneWidget);
    expect(_showing(words), 'cherry');
    await _answer(tester);

    expect(_summary, findsOneWidget);
    expect(_ratingsFor('banana').last, Rating.Again);
    expect(_ratingsFor('cherry'), hasLength(3));
  });

  // The session's cards are taken from the front of the list, and DolphinSR's
  // own order has cards never shown at the front. With more of those than
  // the cap, nothing else was shown until every one had been seen once.
  testWidgets('a capped session takes the forgotten, the half learned and '
      'the due before any card never shown', (tester) async {
    const words = ['forgotten', 'half', 'due', 'new1', 'new2', 'new3', 'new4'];
    final stored = [
      ..._learnedAndDue('forgotten'),
      _stored('forgotten', Rating.Again, 1),
      _stored('half', Rating.Good, 2),
      ..._learnedAndDue('due', minutes: 1),
    ];
    await sharedPreferences.setInt(KEY_REVISION_CARD_LIMIT, 4);
    await _startSession(tester, words, stored: stored);

    final shown = <String>[];
    for (var k = 1; k <= 4; k++) {
      expect(find.text('$k / 4'), findsOneWidget);
      shown.add(_showing(words));
      await _answer(tester);
    }
    expect(_summary, findsOneWidget);
    expect(shown.sublist(0, 3), ['half', 'forgotten', 'due']);
    expect(shown[3], startsWith('new'));
    expect(readReviews(), hasLength(stored.length + 4));
  });

  // Random revision took its cards from DolphinSR too, which only hands out
  // cards that are due.
  testWidgets('random revision goes through every card though none is due, '
      'and stores no answers', (tester) async {
    const words = ['apple', 'banana', 'cherry'];
    final stored = [for (final word in words) ..._learnedAndResting(word)];
    await _startSession(
      tester,
      words,
      stored: stored,
      strategy: RevisionStrategy.Random,
    );

    final shown = <String>[];
    for (var k = 1; k <= 3; k++) {
      expect(find.text('$k / 3'), findsOneWidget);
      shown.add(_showing(words));
      await tester.tap(_reveal);
      await tester.pump();
      await tester.tap(_next);
      await tester.pump();
      await tester.pump();
    }
    expect(_summary, findsOneWidget);
    expect(shown, unorderedEquals(words));
    expect(readReviews(), hasLength(stored.length));
    expect(sharedPreferences.getInt(KEY_RANDOM_REVIEWS_COUNTER), 3);
  });

  // The landing page underneath rebuilds its lookup whenever it refreshes.
  testWidgets('a session keeps the videos it started with when the page is '
      'rebuilt with others', (tester) async {
    const words = ['apple', 'banana'];
    final stored = [
      ..._learnedAndDue('apple'),
      ..._learnedAndDue('banana', minutes: 1),
    ];
    await _startSession(tester, words, stored: stored);
    expect(_showing(words), 'apple');

    // The same page, handed a lookup that apple has gone from.
    await _startSession(
      tester,
      words,
      stored: stored,
      di: _dolphin(['banana'], stored),
    );
    expect(find.text('1 / 2'), findsOneWidget);
    expect(_showing(words), 'apple');
    await _answer(tester);
    await _answer(tester);
    expect(_summary, findsOneWidget);
    expect(readReviews(), hasLength(stored.length + 2));
  });

  // A card whose video can't be found is passed over. Drawing from DolphinSR,
  // the page was handed the same card straight back, for ever.
  testWidgets('a card whose video has gone is passed over, and the session '
      'carries on to its end', (tester) async {
    const words = ['apple', 'banana', 'cherry'];
    final stored = [
      ..._learnedAndDue('apple'),
      ..._learnedAndDue('banana', minutes: 1),
      ..._learnedAndDue('cherry', minutes: 2),
    ];
    final di = _dolphin(words, stored);
    di.masterToVideoMap.remove(savedVideoMasterId(_sign('banana').video));
    await _startSession(tester, words, stored: stored, di: di);

    expect(_showing(words), 'apple');
    await _answer(tester);
    // banana is passed over on the next frame.
    await tester.pump();
    expect(find.text('3 / 3'), findsOneWidget);
    expect(_showing(words), 'cherry');
    await _answer(tester);

    expect(_summary, findsOneWidget);
    expect(_ratingsFor('banana'), hasLength(2));
    expect(readReviews(), hasLength(stored.length + 2));
    // Let the "card unavailable" message run its course.
    await tester.pump(const Duration(seconds: 10));
  });
}
