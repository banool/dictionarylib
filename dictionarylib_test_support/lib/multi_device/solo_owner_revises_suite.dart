// Multi-device e2e, but one device and one person: the report this suite
// case exists for.
//
// Someone shared their Favourites list under another name. Everyone they
// shared it with could revise from it; they couldn't, because the Revision
// page went on offering it under the name it has on the device while the
// Lists page showed the name it was shared under. A list goes by one name
// everywhere now, and for a shared list that is the share's.
//
// So: sign in, share the default list through the real dialog (which won't
// take "Favourites" as the share's name), and without restarting find it on
// the Lists page, on the Revision page and in the sources picker under the
// name it was shared as, and run a session from it. The worker is asked what
// it holds at the end, and whether it refuses the reserved names itself (an
// older app version doesn't check them all before sending).

import 'package:dictionarylib/dictionarylib.dart';
import 'package:dictionarylib/list_storage.dart';
import 'package:dictionarylib/saved_video.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../config.dart';
import '../helpers.dart';
import 'md_common.dart';

const String _shareName = 'Tiny Tunks';

void runSoloOwnerRevises(MdSuiteConfig cfg) {
  mdConfig = cfg;
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('someone who shares their list can revise from it straight '
      'away, under the name they shared it as', (WidgetTester tester) async {
    await mdRequireServer();
    await mdSetup();

    final userId = 'test:md-$mdRunId-solo';
    await mdSignInAs(userId, 'Md Solo');

    final favourites = mdL10n.favouritesListName;
    final defaultKey = userEntryListManager.defaultListKey;
    final defaultList = userEntryListManager.getEntryLists()[defaultKey]!;
    expect(
      defaultList.getName(),
      favourites,
      reason: 'expected an install whose default list is still "$favourites"',
    );
    // Signed in, every list is on the account (linked, private) once
    // account sync has run; what matters is that it isn't shared.
    expect(
      listsService.ownedShareFor(defaultList)?.meta.isShared ?? false,
      isFalse,
      reason: 'expected an install whose default list is not shared yet',
    );

    // Two signs in the default list, which is what revision draws from
    // until the user chooses otherwise.
    final first = mdEntryWithVideo();
    final second = mdEntryWithVideo(exclude: {first.getKey()});
    for (final entry in [first, second]) {
      await defaultList.addVideo(
        SavedVideo(
          entryKey: entry.getKey(),
          mediaPath: entry
              .getSubEntries()
              .firstWhere((s) => s.getMedia().isNotEmpty)
              .getMedia()
              .first,
        ),
      );
    }
    await sharedPreferences.remove(KEY_LISTS_TO_REVIEW);
    await sharedPreferences.remove(KEY_STORED_REVIEWS);
    await sharedPreferences.remove(KEY_REVISION_CARD_LIMIT);
    await sharedPreferences.setInt(
      KEY_REVISION_STRATEGY,
      RevisionStrategy.SpacedRepetition.index,
    );
    await sharedPreferences.setBool(KEY_WORD_TO_SIGN, false);
    await sharedPreferences.setBool(KEY_SIGN_TO_WORD, true);

    await mdPumpApp(tester);

    // --- Share it. ---
    await mdOpenListsTab(tester);
    await mdOpenOverviewTab(tester, mdL10n.listMyLists);
    final row = find.byKey(ValueKey(defaultKey));
    expect(find.descendant(of: row, matching: find.text(favourites)), findsOne);
    await tester.tap(row);
    await settle(tester);
    await tester.tap(find.byIcon(Icons.share));
    await settle(tester);

    // The dialog offers the list's own name, which a share can't have: most
    // people never rename their Favourites, and a shared list called that
    // would sit beside it looking like it.
    final nameField = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    expect(find.widgetWithText(TextField, favourites), findsOneWidget);
    await tester.tap(find.text(mdL10n.shareDialogShareButton));
    await settle(tester);
    expect(
      find.text(mdL10n.shareValidationReservedName(favourites)),
      findsOneWidget,
    );
    expect(
      sharing.lists.ownerForSourceKey(defaultKey)?.meta.isShared ?? false,
      isFalse,
    );

    await tester.enterText(nameField, _shareName);
    await tester.tap(find.text(mdL10n.shareDialogShareButton));
    await mdWaitForUi(
      tester,
      () => find.text(mdL10n.shareLinkDoneButton).evaluate().isNotEmpty,
      reason: 'share-link dialog after sharing',
    );
    await tester.tap(find.text(mdL10n.shareLinkDoneButton));
    await settle(tester);

    final share = sharing.lists.ownerForSourceKey(defaultKey);
    expect(share, isNotNull, reason: 'sharing should leave an owned share');
    expect(share!.meta.isShared, isTrue);
    // The list on the device is the one it was: same key, same signs, still
    // the default list.
    expect(userEntryListManager.defaultListKey, defaultKey);
    expect(sharedPreferences.getString(KEY_DEFAULT_LIST_KEY), defaultKey);

    // --- The Lists page calls it by the name it was shared as. ---
    await tester.pageBack();
    await settle(tester);
    expect(find.descendant(of: row, matching: find.text(_shareName)), findsOne);
    expect(find.text(favourites), findsNothing);

    // --- So does the Revision page, with no restart in between, and it is
    // still what revision draws from. ---
    await mdTapWhenVisible(
      tester,
      mdNavIcon(Icons.style),
      reason: 'Revision tab icon in the bottom navigation',
    );
    expect(find.text(_shareName), findsOneWidget);
    expect(find.text(favourites), findsNothing);

    // The picker offers it under that name.
    await tester.tap(find.text(_shareName));
    await settle(tester);
    expect(find.text(mdL10n.flashcardsSelectLists), findsOneWidget);
    expect(find.text(_shareName), findsWidgets);
    expect(find.text(favourites), findsNothing);
    await tester.tapAt(const Offset(20, 20));
    await settle(tester);
    expect(find.text(mdL10n.flashcardsSelectLists), findsNothing);

    // --- A session from it. ---
    expect(find.text(mdL10n.revisionFlashcardCount(2)), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('startButton')));
    await settle(tester);
    for (var k = 1; k <= 2; k++) {
      expect(find.text('$k / 2'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('revealButton')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('ratingButton.gotIt')));
      await settle(tester);
    }
    expect(find.byKey(const ValueKey('revealButton')), findsNothing);
    await tester.tap(find.widgetWithIcon(IconButton, Icons.close));
    await settle(tester);
    expect(readReviews(), hasLength(2));

    // --- Server truth. ---
    final state = await mdServerState(share.listId);
    expect(state.displayName, _shareName);
    expect(state.ownerUserId, userId);
    expect(state.entryKeys, unorderedEquals([first.getKey(), second.getKey()]));

    // The worker refuses the reserved names itself, in each of the apps'
    // languages and whatever the capitals.
    final token = sharing.auth.store.current!.sessionToken;
    for (final name in [
      favourites,
      favourites.toLowerCase(),
      lookupDictLibLocalizations(LOCALE_SINHALA).favouritesListName,
      lookupDictLibLocalizations(LOCALE_TAMIL).favouritesListName,
    ]) {
      await expectLater(
        sharing.api.renameList(
          listId: share.listId,
          displayName: name,
          sessionToken: token,
        ),
        throwsA(
          isA<SyncException>().having(
            (e) => e.kind,
            'kind',
            SyncErrorKind.invalidBody,
          ),
        ),
        reason: 'the worker should refuse "$name" as a shared list\'s name',
      );
    }
    expect((await mdServerState(share.listId)).displayName, _shareName);
  });
}
