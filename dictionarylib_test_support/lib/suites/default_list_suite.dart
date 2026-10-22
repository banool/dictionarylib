import 'package:dictionarylib/entry_list.dart';
import 'package:dictionarylib/entry_types.dart';
import 'package:dictionarylib/flashcards_logic.dart';
import 'package:dictionarylib/globals.dart';
import 'package:dictionarylib/l10n/app_localizations.dart';
import 'package:dictionarylib/list_storage.dart';
import 'package:dictionarylib/lists_service.dart';
import 'package:dictionarylib/page_entry_list_overview.dart'
    show KEY_LISTS_OVERVIEW_TAB_INDEX;
import 'package:dictionarylib/saved_video.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../config.dart';
import '../helpers.dart';

// End-to-end coverage for the default list (the one every install starts
// with, called "Favourites") being an ordinary list: it is renamed and
// reordered like the others, its name is free for other lists once it has
// another, and the star goes with the name, not with the list. What is left
// that is its own: it can't be deleted.
//
// Also here, because they are about what a list may be called: the one name
// a list can't have ("search for", whose storage key the app keeps a setting
// under), and the names a list can't be shared under.

const String _renamedDefault = 'E2E Default';
const String _other = 'E2E Other';

void runDefaultListSuite(DictAppTestConfig cfg) {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the default list is renamed, reordered and named like any '
      'other list, and is the one that can\'t be deleted', (
    WidgetTester tester,
  ) async {
    await cfg.setup();

    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    advisoryShownOnce = true;
    await sharedPreferences.setInt(KEY_LISTS_OVERVIEW_TAB_INDEX, 0);

    final l = lookupDictLibLocalizations(LOCALE_ENGLISH);
    final favourites = l.favouritesListName;
    final favouritesKey = EntryList.getKeyFromName(favourites);
    final renamedKey = EntryList.getKeyFromName(_renamedDefault);
    final otherKey = EntryList.getKeyFromName(_other);

    final startKey = userEntryListManager.defaultListKey;
    final startName = EntryList.getNameFromKey(startKey);
    expect(
      listsService.ownedShareFor(
        userEntryListManager.getEntryLists()[startKey]!,
      ),
      isNull,
      reason: 'this suite renames the default list, so it must not be shared',
    );
    // A list of this name that was here before the test is the user's.
    final hadFavourites =
        startKey != favouritesKey &&
        userEntryListManager.getEntryLists().containsKey(favouritesKey);
    expect(
      hadFavourites,
      isFalse,
      reason: 'this suite makes a list called "$favourites" of its own',
    );

    // Leave things as they were found: the default list under its old name,
    // none of the lists made here, the revision choice as it was.
    final choiceBefore = sharedPreferences.getStringList(KEY_LISTS_TO_REVIEW);
    Future<void> restore() async {
      final lists = userEntryListManager.getEntryLists();
      final defaultKey = userEntryListManager.defaultListKey;
      for (final key in [favouritesKey, otherKey, 'search_for_words']) {
        if (key != defaultKey && lists.containsKey(key)) {
          await userEntryListManager.deleteEntryList(key);
        }
      }
      if (defaultKey != startKey) {
        await userEntryListManager.renameEntryList(defaultKey, startKey);
      }
      if (choiceBefore == null) {
        await sharedPreferences.remove(KEY_LISTS_TO_REVIEW);
      } else {
        await sharedPreferences.setStringList(
          KEY_LISTS_TO_REVIEW,
          choiceBefore,
        );
      }
    }

    addTearDown(restore);

    // A second list with a sign in it, and the default list chosen for
    // revision.
    final entry = entriesGlobal.firstWhere(
      (e) => e.getSubEntries().any((s) => s.getMedia().isNotEmpty),
    );
    final video = SavedVideo(
      entryKey: entry.getKey(),
      mediaPath: entry
          .getSubEntries()
          .firstWhere((s) => s.getMedia().isNotEmpty)
          .getMedia()
          .first,
    );
    if (!userEntryListManager.getEntryLists().containsKey(otherKey)) {
      await userEntryListManager.createEntryList(otherKey);
    }
    await userEntryListManager.getEntryLists()[otherKey]!.addVideo(video);
    final defaultList = userEntryListManager.getEntryLists()[startKey]!;
    if (!defaultList.containsVideo(video)) {
      await defaultList.addVideo(video);
      addTearDown(() async {
        await userEntryListManager
            .getEntryLists()[userEntryListManager.defaultListKey]
            ?.removeVideo(video);
      });
    }
    await sharedPreferences.setStringList(KEY_LISTS_TO_REVIEW, [startKey]);

    await tester.pumpWidget(cfg.buildApp(LOCALE_ENGLISH));
    await settle(tester);
    await tester.tap(find.byIcon(Icons.view_list));
    await settle(tester);

    Finder row(String key) => find.byKey(ValueKey(key));
    Finder inRow(String key, Finder what) =>
        find.descendant(of: row(key), matching: what);
    final deleteButton = find.byIcon(Icons.remove_circle);
    // The text field of whichever dialog is open.
    final dialogField = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );

    Future<void> enterEditMode() async {
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await settle(tester);
    }

    Future<void> leaveEditMode() async {
      await tester.tap(find.byIcon(Icons.edit));
      await settle(tester);
    }

    /// The new-list dialog, from edit mode's add button. A list that gets
    /// made takes the page out of edit mode; a name that is refused leaves it
    /// there.
    Future<void> makeList(String name) async {
      await tester.tap(find.byIcon(Icons.add));
      await settle(tester);
      expect(find.text(l.listNewList), findsOneWidget);
      await tester.enterText(dialogField, name);
      await tester.tap(find.text(l.alertConfirm));
      await settle(tester);
    }

    // --- It can't be deleted; the other list can. ---
    await enterEditMode();
    expect(inRow(startKey, deleteButton), findsNothing);
    expect(inRow(otherKey, deleteButton), findsOne);

    // --- It is renamed like any other list, and what pointed at it
    // follows. ---
    await tester.tap(inRow(startKey, find.text(startName)));
    await settle(tester);
    expect(find.text(l.listRenameList), findsOneWidget);
    await tester.enterText(dialogField, _renamedDefault);
    await tester.tap(find.text(l.alertConfirm));
    await settle(tester);

    expect(userEntryListManager.defaultListKey, renamedKey);
    expect(sharedPreferences.getString(KEY_DEFAULT_LIST_KEY), renamedKey);
    expect(sharedPreferences.get(startKey), isNull);
    expect(
      userEntryListManager.getEntryLists()[renamedKey]!.containsVideo(video),
      isTrue,
      reason: 'its saved sign should come with it',
    );
    expect(loadListsToReview(), [renamedKey]);
    expect(inRow(renamedKey, find.text(_renamedDefault)), findsOne);
    // Renamed, it is still the one that can't be deleted.
    expect(inRow(renamedKey, deleteButton), findsNothing);

    // --- "Favourites" is a name like any other now: another list can take
    // it. (Making a list takes the page out of edit mode.) ---
    await makeList(favourites);
    expect(
      userEntryListManager.getEntryLists().containsKey(favouritesKey),
      isTrue,
      reason: 'a list should be able to be called "$favourites"',
    );

    // --- The star goes with the name. ---
    expect(inRow(favouritesKey, find.byIcon(Icons.star)), findsOne);
    expect(inRow(renamedKey, find.byIcon(Icons.star)), findsNothing);
    expect(inRow(otherKey, find.byIcon(Icons.star)), findsNothing);

    // --- That list can be deleted; the default list still can't. ---
    await enterEditMode();
    expect(inRow(favouritesKey, deleteButton), findsOne);
    expect(inRow(renamedKey, deleteButton), findsNothing);

    // --- It is reordered like any other list: dragged from first place to
    // below the next one. ---
    expect(userEntryListManager.getEntryLists().keys.first, renamedKey);
    final second = userEntryListManager.getEntryLists().keys.elementAt(1);
    final distance =
        tester.getCenter(row(second)).dy - tester.getCenter(row(renamedKey)).dy;
    await tester.timedDrag(
      row(renamedKey),
      Offset(0, distance + 20),
      const Duration(milliseconds: 800),
    );
    await settle(tester);
    final order = userEntryListManager.getEntryLists().keys.toList();
    expect(order.indexOf(renamedKey), 1, reason: 'order is now $order');
    expect(order.first, second);
    expect(sharedPreferences.getStringList(KEY_ENTRY_LIST_KEYS), order);
    // Wherever it is in the order, it is still the default list.
    expect(userEntryListManager.defaultListKey, renamedKey);
    expect(inRow(renamedKey, deleteButton), findsNothing);

    // --- Deleting the list that took the name. ---
    await tester.tap(inRow(favouritesKey, deleteButton));
    await settle(tester);
    await tester.tap(find.text(l.alertConfirm));
    await settle(tester);
    expect(
      userEntryListManager.getEntryLists().containsKey(favouritesKey),
      isFalse,
    );
    expect(row(favouritesKey), findsNothing);

    // --- The one name a list can't have. Its key is where the search page
    // keeps one of its settings, and a list stored there broke every
    // search. ---
    await makeList('search for');
    expect(
      find.textContaining(l.listNameErrorReserved('search for')),
      findsOne,
    );
    expect(
      userEntryListManager.getEntryLists().containsKey('search_for_words'),
      isFalse,
    );
    expect(sharedPreferences.get('search_for_words'), isNot(isA<List>()));
    await leaveEditMode();

    // --- A list can't be shared as "Favourites", in any of the apps'
    // languages: most people never rename theirs, and a shared list of that
    // name would sit beside it looking like it. The check comes before
    // anything is sent, or anyone is asked to sign in. ---
    await tester.tap(row(renamedKey));
    await settle(tester);
    await tester.tap(find.byIcon(Icons.share));
    await settle(tester);
    expect(find.text(l.shareDialogTitle), findsOneWidget);
    expect(find.widgetWithText(TextField, _renamedDefault), findsOneWidget);
    for (final name in [
      favourites,
      ' ${favourites.toUpperCase()} ',
      lookupDictLibLocalizations(LOCALE_SINHALA).favouritesListName,
      lookupDictLibLocalizations(LOCALE_TAMIL).favouritesListName,
    ]) {
      await tester.enterText(dialogField, name);
      await tester.tap(find.text(l.shareDialogShareButton));
      await settle(tester);
      expect(
        find.text(l.shareValidationReservedName(name.trim())),
        findsOneWidget,
        reason: 'sharing as "$name" should be refused',
      );
      expect(find.text(l.shareDialogTitle), findsOneWidget);
    }
    await tester.tap(find.text(l.alertCancel));
    await settle(tester);
    await tester.pageBack();
    await settle(tester);

    // --- Elsewhere it goes by its new name, and is still what revision
    // draws from. ---
    await tester.tap(find.byIcon(Icons.style));
    await settle(tester);
    expect(find.text(_renamedDefault), findsOneWidget);
    expect(find.text(startName), findsNothing);

    // --- And search works. ---
    await tester.tap(
      find.descendant(
        of: find.byType(BottomNavigationBar),
        matching: find.byIcon(Icons.search),
      ),
    );
    await settle(tester);
    final searchField = find.byKey(const ValueKey('searchPage.searchForm'));
    await tester.tap(searchField);
    await settle(tester);
    await tester.enterText(searchField, entry.getKey());
    await settle(tester);
    expect(find.text(entry.getKey()), findsWidgets);
    FocusManager.instance.primaryFocus?.unfocus();
    await settle(tester);
  });
}
