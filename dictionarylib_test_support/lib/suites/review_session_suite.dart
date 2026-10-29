import 'package:dictionarylib/common.dart';
import 'package:dictionarylib/entry_list.dart';
import 'package:dictionarylib/entry_types.dart';
import 'package:dictionarylib/flashcards_logic.dart';
import 'package:dictionarylib/globals.dart';
import 'package:dictionarylib/l10n/app_localizations.dart';
import 'package:dictionarylib/revision.dart';
import 'package:dictionarylib/saved_video.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../config.dart';
import '../helpers.dart';

// End-to-end coverage for the flashcard review feature: a full 10-card spaced-
// repetition session driven through the real UI. It exercises:
//   - the per-card reveal + rate flow (Got it / Forgot),
//   - the back/forward card navigation (stepping back revisits an earlier card
//     revealed with its prior rating, and the position counter stays correct),
//     and
//   - review persistence on exit (reviewHistory.appendLocal → KEY_STORED_REVIEWS).
//
// A second test runs sessions back to back over a list holding new cards,
// cards due for review and one that gets forgotten: each session shows each
// of its cards once, a capped one takes what is due for review before what
// has never been seen, the right cards are still due after each, and random
// revision goes through them all whatever is due.

const int kSessionCards = 10;

void runReviewSessionSuite(DictAppTestConfig cfg) {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a 10-card review session reveals, rates, steps back and forward, and '
      'persists every review on exit', (WidgetTester tester) async {
    await cfg.setup();

    // Portrait phone viewport so the flashcard uses its vertical layout (reveal
    // / rating buttons and nav arrows on screen, not in a side panel).
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    advisoryShownOnce = true;

    // Seed a dedicated list with plenty of real, dictionary-backed videos so the
    // session has well over kSessionCards due cards to draw from. A separate
    // list (deleted in teardown) keeps the user's real favourites untouched.
    final saved = <SavedVideo>[];
    for (final e in entriesGlobal) {
      for (final sub in e.getSubEntries()) {
        for (final media in sub.getMedia()) {
          saved.add(SavedVideo(entryKey: e.getKey(), mediaPath: media));
        }
      }
      if (saved.length >= 30) break;
    }
    expect(
      saved.length,
      greaterThanOrEqualTo(kSessionCards),
      reason: 'need enough seed videos to fill the session',
    );

    final listKey = EntryList.getKeyFromName('ReviewTest');
    if (!userEntryListManager.getEntryLists().containsKey(listKey)) {
      await userEntryListManager.createEntryList(listKey);
    }
    final testList = userEntryListManager.getEntryLists()[listKey]!;
    for (final v in saved) {
      await testList.addVideo(v);
    }
    addTearDown(() => userEntryListManager.deleteEntryList(listKey));

    // Configure the session: review the seeded list, spaced-repetition, capped
    // at exactly kSessionCards, both card directions on, and (where the app
    // filters the flashcard pool, e.g. by region) allow everything so no
    // seeded video is filtered out. Start review history from empty so the
    // post-session count is exact.
    await sharedPreferences.setStringList(KEY_LISTS_TO_REVIEW, [listKey]);
    await sharedPreferences.setInt(
      KEY_REVISION_STRATEGY,
      RevisionStrategy.SpacedRepetition.index,
    );
    await sharedPreferences.setInt(KEY_REVISION_CARD_LIMIT, kSessionCards);
    await sharedPreferences.setBool(KEY_WORD_TO_SIGN, true);
    await sharedPreferences.setBool(KEY_SIGN_TO_WORD, true);
    await cfg.seedFlashcardSettings?.call();
    await sharedPreferences.remove(KEY_STORED_REVIEWS);
    addTearDown(() async {
      await sharedPreferences.remove(KEY_STORED_REVIEWS);
      await sharedPreferences.remove(KEY_REVISION_CARD_LIMIT);
      await cfg.clearFlashcardSettings?.call();
      await sharedPreferences.setStringList(KEY_LISTS_TO_REVIEW, [
        userEntryListManager.defaultListKey,
      ]);
    });

    await tester.pumpWidget(cfg.buildApp(LOCALE_ENGLISH));
    await settle(tester);

    // Revision tab -> Start the session.
    await tester.tap(find.byIcon(Icons.style));
    await settle(tester);
    final startButton = find.byKey(const ValueKey("startButton"));
    expect(
      startButton,
      findsOneWidget,
      reason: 'the revision landing page should offer a Start button',
    );
    await tester.tap(startButton);
    await settle(tester);

    final revealButton = find.byKey(const ValueKey("revealButton"));
    final gotIt = find.byKey(const ValueKey("ratingButton.gotIt"));
    final forgot = find.byKey(const ValueKey("ratingButton.forgot"));

    // Reveal the current card and rate it, advancing to the next card. Revealing
    // records a default "Got it"; tapping Forgot overwrites it to Again and waits
    // out the brief feedback timer before the card auto-advances.
    Future<void> revealAndRate({required bool forgotIt}) async {
      expect(revealButton, findsOneWidget);
      await tester.tap(revealButton);
      await settle(tester);
      if (forgotIt) {
        await tester.tap(forgot);
        await tester.pump(
          const Duration(seconds: 1),
        ); // feedback timer (~750ms)
        await settle(tester);
      } else {
        await tester.tap(gotIt);
        await settle(tester);
      }
    }

    // --- Cards 1-3: rate "Got it", landing on card 4. ---
    for (var k = 1; k <= 3; k++) {
      expect(find.text('$k / $kSessionCards'), findsOneWidget);
      await revealAndRate(forgotIt: false);
    }

    // On card 4, not yet revealed.
    expect(find.text('4 / $kSessionCards'), findsOneWidget);
    expect(revealButton, findsOneWidget);

    // --- Back/forward navigation. ---
    final back = find.byIcon(Icons.chevron_left);
    final forward = find.byIcon(Icons.chevron_right);

    // Step back to card 3: it reappears revealed with its earlier rating (so the
    // rating buttons, not the reveal button, are shown) and the counter tracks
    // the position rather than the answered-count.
    await tester.tap(back);
    await settle(tester);
    expect(find.text('3 / $kSessionCards'), findsOneWidget);
    expect(gotIt, findsOneWidget);
    expect(revealButton, findsNothing);

    // Keep stepping back to the first card; a further back tap is a no-op (we
    // never go below the first card).
    await tester.tap(back);
    await settle(tester);
    expect(find.text('2 / $kSessionCards'), findsOneWidget);
    await tester.tap(back);
    await settle(tester);
    expect(find.text('1 / $kSessionCards'), findsOneWidget);
    await tester.tap(back);
    await settle(tester);
    expect(find.text('1 / $kSessionCards'), findsOneWidget);

    // Walk forward through the already-shown cards back to card 4. Forward
    // navigation reuses the shown cards (no new draws), so we land exactly where
    // we left off — on the still-unrevealed card 4.
    for (var k = 2; k <= 4; k++) {
      await tester.tap(forward);
      await settle(tester);
      expect(find.text('$k / $kSessionCards'), findsOneWidget);
    }
    expect(revealButton, findsOneWidget);

    // --- Card 4: "Got it". Card 5: "Forgot". ---
    await revealAndRate(forgotIt: false);
    expect(find.text('5 / $kSessionCards'), findsOneWidget);
    await revealAndRate(forgotIt: true);

    // --- Cards 6-10: "Got it". The 10th advance ends the session. ---
    for (var k = 6; k <= kSessionCards; k++) {
      expect(find.text('$k / $kSessionCards'), findsOneWidget);
      await revealAndRate(forgotIt: false);
    }

    // Session complete: the summary replaces the card, so neither the reveal nor
    // the rating buttons remain.
    expect(revealButton, findsNothing);
    expect(gotIt, findsNothing);

    // Reviews are written when the session ends; the close button writes again
    // (idempotently) and pops back to the landing page.
    await tester.tap(find.byIcon(Icons.close));
    await settle(tester);

    // --- Persistence: exactly one review per card, with the single Forgot
    // recorded as Again and the rest as Good. ---
    final reviews = readReviews();
    expect(
      reviews.length,
      kSessionCards,
      reason: 'one persisted review per reviewed card',
    );
    expect(
      reviews.where((r) => r.rating == Rating.Again).length,
      1,
      reason: 'the one Forgot rating should persist as Again',
    );
    expect(
      reviews.where((r) => r.rating == Rating.Good).length,
      kSessionCards - 1,
      reason: 'the remaining ratings should persist as Good',
    );
  });

  // A session used to take each card from the scheduler as it went. A card
  // that is answered but still being learned (a new one, which needs two
  // correct answers, or one that was forgotten) is still the first thing the
  // scheduler has, so with other cards waiting behind it the session showed
  // it over and over and never reached them, or its own end. That was also
  // why "Forgot" had been stored as Hard, which doesn't send a card back to
  // be relearned: it makes it wait longer than before. (test/
  // flashcards_page_test.dart in dictionarylib runs the same page without a
  // device; this is the check with real videos and the real landing page.)
  testWidgets('sessions over new cards, due cards and a forgotten one show '
      'each card once, the ones that matter most first, and leave the right '
      'ones due', (WidgetTester tester) async {
    await cfg.setup();

    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    advisoryShownOnce = true;

    // Twelve videos from twelve entries.
    final saved = <SavedVideo>[];
    for (final e in entriesGlobal) {
      final subEntries = e.getSubEntries();
      if (subEntries.isEmpty || subEntries.first.getMedia().isEmpty) continue;
      saved.add(
        SavedVideo(
          entryKey: e.getKey(),
          mediaPath: subEntries.first.getMedia().first,
        ),
      );
      if (saved.length == 12) break;
    }
    expect(saved, hasLength(12));

    final listKey = EntryList.getKeyFromName('MixedReviewTest');
    if (!userEntryListManager.getEntryLists().containsKey(listKey)) {
      await userEntryListManager.createEntryList(listKey);
    }
    final testList = userEntryListManager.getEntryLists()[listKey]!;
    for (final v in saved) {
      await testList.addVideo(v);
    }
    addTearDown(() => userEntryListManager.deleteEntryList(listKey));

    // One card per video (sign to word), and sessions capped at ten cards
    // (the smallest cap there is) to begin with.
    await sharedPreferences.setStringList(KEY_LISTS_TO_REVIEW, [listKey]);
    await sharedPreferences.setInt(
      KEY_REVISION_STRATEGY,
      RevisionStrategy.SpacedRepetition.index,
    );
    await sharedPreferences.setInt(KEY_REVISION_CARD_LIMIT, 10);
    await sharedPreferences.setBool(KEY_WORD_TO_SIGN, false);
    await sharedPreferences.setBool(KEY_SIGN_TO_WORD, true);
    await cfg.seedFlashcardSettings?.call();

    // The last three were learned eleven days ago (two correct answers, a
    // day apart), which makes them due. The other nine have never been seen.
    final now = DateTime.now();
    String storedReview(SavedVideo video, DateTime ts) => [
      savedVideoMasterId(video),
      '1${COMBINATION_DELIMETER}0',
      Rating.Good.index,
      ts.microsecondsSinceEpoch,
    ].join(REVIEW_DELIMITER);
    await sharedPreferences.setStringList(KEY_STORED_REVIEWS, [
      for (final (i, video) in saved.sublist(9).indexed) ...[
        storedReview(video, now.subtract(Duration(days: 12, minutes: i))),
        storedReview(video, now.subtract(Duration(days: 11, minutes: i))),
      ],
    ]);
    final randomReviewsBefore = sharedPreferences.getInt(
      KEY_RANDOM_REVIEWS_COUNTER,
    );
    final firstRandomReviewBefore = sharedPreferences.getInt(
      KEY_FIRST_RANDOM_REVIEW,
    );
    addTearDown(() async {
      await sharedPreferences.remove(KEY_STORED_REVIEWS);
      await sharedPreferences.remove(KEY_REVISION_CARD_LIMIT);
      await sharedPreferences.remove(KEY_WORD_TO_SIGN);
      await sharedPreferences.remove(KEY_SIGN_TO_WORD);
      await sharedPreferences.setInt(
        KEY_REVISION_STRATEGY,
        RevisionStrategy.SpacedRepetition.index,
      );
      for (final (key, before) in [
        (KEY_RANDOM_REVIEWS_COUNTER, randomReviewsBefore),
        (KEY_FIRST_RANDOM_REVIEW, firstRandomReviewBefore),
      ]) {
        if (before == null) {
          await sharedPreferences.remove(key);
        } else {
          await sharedPreferences.setInt(key, before);
        }
      }
      await cfg.clearFlashcardSettings?.call();
      await sharedPreferences.setStringList(KEY_LISTS_TO_REVIEW, [
        userEntryListManager.defaultListKey,
      ]);
    });

    await tester.pumpWidget(cfg.buildApp(LOCALE_ENGLISH));
    await settle(tester);
    await tester.tap(find.byIcon(Icons.style));
    await settle(tester);

    final startButton = find.byKey(const ValueKey("startButton"));
    final revealButton = find.byKey(const ValueKey("revealButton"));
    final gotIt = find.byKey(const ValueKey("ratingButton.gotIt"));
    final forgot = find.byKey(const ValueKey("ratingButton.forgot"));
    final l = lookupDictLibLocalizations(LOCALE_ENGLISH);

    // The word each card turns out to be, once it is revealed.
    final words = {
      for (final video in saved)
        video.entryKey: keyedByEnglishEntriesGlobal[video.entryKey]!.getPhrase(
          LOCALE_ENGLISH,
        )!,
    };
    final dueOnes = [for (final video in saved.sublist(9)) video.entryKey];
    final newOnes = [for (final video in saved.sublist(0, 9)) video.entryKey];

    // Start a session of [cards] cards and go through it, answering "Forgot"
    // on card [forget] (counting from 1) and "Got it" on the rest, then leave
    // the summary for the landing page. Returns the entries the cards were
    // for, in the order they came up.
    Future<List<String>> runSession({required int cards, int? forget}) async {
      final shown = <String>[];
      await tester.tap(startButton);
      await settle(tester);
      for (var k = 1; k <= cards; k++) {
        expect(find.text('$k / $cards'), findsOneWidget);
        // A card the session hasn't shown before: face down, not already
        // answered.
        expect(
          revealButton,
          findsOneWidget,
          reason: 'card $k of $cards came up already answered',
        );
        await tester.tap(revealButton);
        await settle(tester);
        shown.add(
          words.keys.singleWhere(
            (key) => find.text(words[key]!).evaluate().isNotEmpty,
          ),
        );
        if (k == forget) {
          await tester.tap(forgot);
          await tester.pump(const Duration(seconds: 1)); // feedback timer
          await settle(tester);
          if (k < cards) {
            // Stepping back shows it as it was answered, "Forgot" filled in,
            // and stepping forward returns to the card after it.
            expect(find.text('${k + 1} / $cards'), findsOneWidget);
            await tester.tap(find.byIcon(Icons.chevron_left));
            await settle(tester);
            expect(find.text('$k / $cards'), findsOneWidget);
            expect(
              find.descendant(of: forgot, matching: find.byType(FilledButton)),
              findsOneWidget,
            );
            expect(
              find.descendant(of: gotIt, matching: find.byType(OutlinedButton)),
              findsOneWidget,
            );
            await tester.tap(find.byIcon(Icons.chevron_right));
            await settle(tester);
          }
        } else {
          await tester.tap(gotIt);
          await settle(tester);
        }
      }
      // The summary, not one card more, with its tally of how it went.
      expect(revealButton, findsNothing);
      expect(gotIt, findsNothing);
      expect(find.text(l.sessionCompleteHeadline(cards)), findsOneWidget);
      expect(find.text(l.summarySuccess), findsOneWidget);
      expect(find.text(l.summaryGotIt), findsOneWidget);
      expect(find.text(l.summaryForgot), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close));
      await settle(tester);
      expect(shown.toSet(), hasLength(cards), reason: 'a card came up twice');
      return shown;
    }

    // --- A capped session. All twelve are due, three for review and nine
    // never seen, and the ten it has room for start with the three for
    // review: with the new ones first, as they used to be, a long enough
    // list of unseen signs kept everything else out of capped sessions
    // altogether. The first card gets forgotten. ---
    expect(find.text('10 flashcards'), findsOneWidget);
    final first = await runSession(cards: 10, forget: 1);
    expect(first.sublist(0, 3), unorderedEquals(dueOnes));
    expect(newOnes, containsAll(first.sublist(3)));
    final forgotten = first.first;
    final seenOnce = first.sublist(3);
    final unseen = [
      for (final key in newOnes)
        if (!seenOnce.contains(key)) key,
    ];
    expect(unseen, hasLength(2));

    var reviews = readReviews();
    expect(reviews, hasLength(6 + 10), reason: 'one review per card shown');
    expect(reviews.where((r) => r.rating == Rating.Again), hasLength(1));

    // --- Due now: the one that was forgotten, the seven new cards that
    // have had one correct answer and want a second, and the two never
    // seen. In that order, each group longest-waiting first. ---
    expect(find.text('10 flashcards'), findsOneWidget);
    final second = await runSession(cards: 10);
    expect(second.sublist(0, 8), [forgotten, ...seenOnce]);
    expect(second.sublist(8), unorderedEquals(unseen));
    expect(readReviews(), hasLength(6 + 10 + 10));

    // No cap from here on. (The landing page reads it when it is opened.)
    await sharedPreferences.remove(KEY_REVISION_CARD_LIMIT);
    await tester.tap(find.byIcon(Icons.view_list));
    await settle(tester);
    await tester.tap(find.byIcon(Icons.style));
    await settle(tester);

    // --- The seven are learned now. Left: the forgotten one, got right
    // once since and wanting a second time, and the last two new ones,
    // likewise. ---
    expect(find.text('3 flashcards'), findsOneWidget);
    final third = await runSession(cards: 3);
    expect(third, [forgotten, ...second.sublist(8)]);
    expect(readReviews(), hasLength(6 + 10 + 10 + 3));

    // Nothing left to revise.
    expect(find.text('0 flashcards'), findsOneWidget);
    expect(tester.widget<FilledButton>(startButton).onPressed, isNull);

    // Random revision isn't about what is due: it goes through all twelve.
    // (It used to be handed out by the scheduler too, which would have had
    // nothing to give it here.)
    final random = find.text(RevisionStrategy.Random.pretty);
    await tester.ensureVisible(random);
    await tester.tap(random);
    await settle(tester);
    expect(find.text('12 flashcards'), findsOneWidget);
    await tester.tap(startButton);
    await settle(tester);
    final next = find.byKey(const ValueKey("ratingButton.next"));
    for (var k = 1; k <= 12; k++) {
      expect(find.text('$k / 12'), findsOneWidget);
      expect(revealButton, findsOneWidget);
      await tester.tap(revealButton);
      await settle(tester);
      await tester.tap(next);
      await settle(tester);
    }
    expect(revealButton, findsNothing);
    expect(next, findsNothing);
    // Its summary says how many signs were gone through and nothing about
    // how it went: random revision never asks. (It used to work out a
    // success rate anyway, which came to 0% for anyone using "Next".)
    expect(find.text(l.sessionCompleteHeadline(12)), findsOneWidget);
    expect(find.text(l.summarySuccess), findsNothing);
    expect(find.text(l.summaryGotIt), findsNothing);
    expect(find.text(l.summaryForgot), findsNothing);
    expect(find.textContaining('%'), findsNothing);
    await tester.tap(find.byIcon(Icons.close));
    await settle(tester);
    // Random sessions don't add to the spaced-repetition history.
    expect(readReviews(), hasLength(6 + 10 + 10 + 3));
  });
}
