// Multi-device e2e, one device: an install from before account sync takes
// the update, then its owner signs in for the first time. Its lists, its
// revision history and its progress figures must come through both steps
// whole, and end up on the account once.
//
// What the old version left behind is, by default, written before the app
// starts, in the layout a released build wrote (as
// upgrade_shared_favourites_suite.dart does). With
// `--dart-define=MD_UPGRADE_FROM_INSTALL=true` nothing is written: the suite
// takes what an old build installed on the device left there, for the
// old-build-then-new-build check (the old build seeds the same lists,
// answers and settings as [seedAsReleasedBuild] does, with its own code; see
// docs/account-sync-progress.md in dictionarylib).

import 'package:dictionarylib/dictionarylib.dart';
import 'package:dictionarylib/saved_video.dart';
import 'package:dolphinsr/dolphinsr.dart' show Combination, Review;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import '../helpers.dart';
import 'account_sync_suites.dart' show MdOtherDevice;
import 'md_common.dart';

const bool _fromInstall = bool.fromEnvironment('MD_UPGRADE_FROM_INSTALL');

/// The second list the old install has.
const String upgradeListName = 'Upgrade Animals';

/// Answers in the old install's history, random-mode cards counted and the
/// card limit it had set.
const int upgradeAnswers = 5;
const int upgradeRandomCount = 4;
const int upgradeCardLimit = 25;

/// The answers: sign-to-word cards of the first two of [videos], "Got it",
/// [upgradeAnswers] of them across the last few days.
List<Review> upgradeHistory(List<SavedVideo> videos) {
  final now = DateTime.now();
  return [
    for (var i = 0; i < upgradeAnswers; i++)
      Review(
        master: savedVideoMasterId(videos[i % 2]),
        combination: const Combination(front: [1], back: [0]),
        rating: Rating.Good,
        ts: now.subtract(Duration(days: upgradeAnswers - i)),
      ),
  ];
}

/// The old install, in the storage layout a released build wrote: the
/// default list under its old key holding the first of [storedVideos], a
/// list called [upgradeListName] holding the other two, the history, the
/// random-mode count and some revision settings.
Future<void> seedAsReleasedBuild(List<String> storedVideos) async {
  final videos = [for (final s in storedVideos) SavedVideo.tryParse(s)!];
  final prefs = await SharedPreferences.getInstance();
  await prefs.clear();
  const oldDefault = 'favourites_words';
  final animals = EntryList.getKeyFromName(upgradeListName);
  await prefs.setStringList('word_list_keys', [oldDefault, animals]);
  await prefs.setStringList(oldDefault, [storedVideos[0]]);
  await prefs.setInt('${oldDefault}_schemaVersion', 3);
  await prefs.setStringList(animals, storedVideos.sublist(1, 3));
  await prefs.setInt('${animals}_schemaVersion', 3);
  await prefs.setStringList(KEY_STORED_REVIEWS, [
    for (final r in upgradeHistory(videos)) encodeReview(r),
  ]);
  await prefs.setInt(KEY_REVIEWS_SCHEMA_VERSION, reviewsSchemaVersion);
  await prefs.setInt(KEY_RANDOM_REVIEWS_COUNTER, upgradeRandomCount);
  await prefs.setInt(
    KEY_FIRST_RANDOM_REVIEW,
    DateTime.now().millisecondsSinceEpoch ~/ 1000 - 86400,
  );
  await prefs.setInt(KEY_REVISION_CARD_LIMIT, upgradeCardLimit);
  await prefs.setInt(
    KEY_REVISION_STRATEGY,
    RevisionStrategy.SpacedRepetition.index,
  );
  await prefs.setBool(KEY_WORD_TO_SIGN, false);
  await prefs.setBool(KEY_SIGN_TO_WORD, true);
}

/// [storedVideos]: three saved videos from three entries, as a list stores
/// them (the app's test config has them; see DictAppTestConfig.storedVideos).
void runUpgradeSyncFromOldInstall(
  MdSuiteConfig cfg, {
  required List<String> storedVideos,
}) {
  mdConfig = cfg;
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('an install from before account sync takes the update and '
      'signs in: lists, history and progress come through, once', (
    WidgetTester tester,
  ) async {
    await mdRequireServer();
    expect(storedVideos.length, greaterThanOrEqualTo(3));
    final videos = [for (final s in storedVideos) SavedVideo.tryParse(s)!];
    if (!_fromInstall) await seedAsReleasedBuild(storedVideos);
    // Signed out. (On iOS the keychain outlives the app, so an earlier run
    // on this simulator may have left a session.)
    final store = AuthStore();
    await store.clear();
    store.dispose();

    // --- The update's first launch. ---
    await mdSetup();
    expect(sharing.auth.store.current, isNull, reason: 'signed out before');
    final defaultKey = userEntryListManager.defaultListKey;
    final animalsKey = EntryList.getKeyFromName(upgradeListName);
    Set<String> keysOf(String key) => {
      for (final v in userEntryListManager.getEntryLists()[key]!.savedVideos)
        v.entryKey,
    };
    void expectDeviceAsBefore(String when) {
      expect(keysOf(defaultKey), {videos[0].entryKey}, reason: when);
      expect(keysOf(animalsKey), {
        videos[1].entryKey,
        videos[2].entryKey,
      }, reason: when);
      expect(reviewHistory.read(), hasLength(upgradeAnswers), reason: when);
      expect(
        sharedPreferences.getInt(KEY_RANDOM_REVIEWS_COUNTER),
        upgradeRandomCount,
        reason: when,
      );
      expect(
        sharedPreferences.getInt(KEY_REVISION_CARD_LIMIT),
        upgradeCardLimit,
        reason: when,
      );
    }

    expectDeviceAsBefore('after the update');
    await sharedPreferences.setStringList(KEY_LISTS_TO_REVIEW, [
      defaultKey,
      animalsKey,
    ]);

    await mdPumpApp(tester);
    final dueBefore = await _dueOnRevisionPage(tester);
    await _expectProgress(tester, upgradeAnswers);

    // --- The first sign-in: the merge. ---
    final userId = 'test:md-$mdRunId-upgrade-sync';
    await mdSignInAs(userId, 'Md Upgrader');
    await mdWaitForAccountSync();
    mdClearSnackBars();
    await settle(tester);
    expectDeviceAsBefore('after signing in');
    expect(reviewHistory.unsentCount, 0);
    expect(sharing.lists.ownerForSourceKey(defaultKey), isNotNull);
    expect(sharing.lists.ownerForSourceKey(animalsKey), isNotNull);

    // The account has it all, once.
    expect(
      (await mdServerEntryKeys(
        sharing.lists.ownerForSourceKey(defaultKey)!.listId,
      )).toSet(),
      {videos[0].entryKey},
    );
    expect(
      (await mdServerEntryKeys(
        sharing.lists.ownerForSourceKey(animalsKey)!.listId,
      )).toSet(),
      {videos[1].entryKey, videos[2].entryKey},
    );
    final other = await MdOtherDevice.signIn(userId);
    expect(await other.answers(), hasLength(upgradeAnswers));
    expect(sharing.accountSync.randomTotalWithPending, upgradeRandomCount);

    // The progress figures and due cards are what they were.
    expect(await _dueOnRevisionPage(tester), dueBefore);
    await _expectProgress(tester, upgradeAnswers);
    await sharedPreferences.setInt(
      KEY_REVISION_STRATEGY,
      RevisionStrategy.Random.index,
    );
    await _expectProgress(tester, upgradeRandomCount);
  });
}

/// Cards due on the Revision page.
Future<int> _dueOnRevisionPage(WidgetTester tester) async {
  mdClearSnackBars();
  await mdTapWhenVisible(
    tester,
    mdNavIcon(Icons.style),
    reason: 'Revision tab icon in the bottom navigation',
  );
  final page = tester.state<FlashcardsLandingPageState>(
    find.byType(FlashcardsLandingPage),
  );
  page.updateRevisionSettings();
  await settle(tester);
  return getNumDueCards(
    page.dolphinInformation.dolphin,
    RevisionStrategy.SpacedRepetition,
  );
}

/// The progress page (from the Revision page) shows [total] (answers, or
/// random-mode cards).
Future<void> _expectProgress(WidgetTester tester, int total) async {
  await tester.tap(find.byIcon(Icons.timeline));
  await settle(tester);
  await mdWaitForUi(
    tester,
    () => find
        .byWidgetPredicate(
          (w) =>
              w is HearthStatTile &&
              w.label == mdL10n.flashcardsTotalReviews &&
              w.value == '$total',
        )
        .evaluate()
        .isNotEmpty,
    reason: 'the progress page should show $total',
  );
  await tester.pageBack();
  await settle(tester);
}
