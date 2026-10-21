import 'package:dictionarylib/entry_types.dart';
import 'package:dictionarylib/globals.dart';
import 'package:dictionarylib/page_entry_list_overview.dart'
    show KEY_LISTS_OVERVIEW_TAB_INDEX;
import 'package:dictionarylib/saved_video.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../config.dart';
import '../helpers.dart';

// End-to-end coverage for tap-to-rename in the lists overview's edit mode,
// including that the default list (the one that starts out as "Favourites")
// offers it like any other.
//
// The list is seeded directly (not created via the dialog) so the test
// targets a known name, then driven through the real edit-mode tap → rename
// dialog → confirm flow. It asserts both the visible result and that the
// list's saved videos survive the underlying key change.

void runListsRenameSuite(DictAppTestConfig cfg) {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'edit mode: tapping a list renames it (videos preserved); the default '
    'list can be renamed too',
    (WidgetTester tester) async {
      await cfg.setup();

      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      advisoryShownOnce = true;
      // Pin the overview to the My Lists tab so the edit pencil + our seeded
      // list are on the visible tab regardless of what a previous run left.
      await sharedPreferences.setInt(KEY_LISTS_OVERVIEW_TAB_INDEX, 0);

      // Seed a renamable list with one real saved video so we can prove the
      // rename carries the contents across the key change.
      const startKey = 'RenameMe_words';
      const endKey = 'Renamed_words';
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

      Future<void> cleanup() async {
        for (final k in [startKey, endKey]) {
          if (userEntryListManager.getEntryLists().containsKey(k)) {
            await userEntryListManager.deleteEntryList(k);
          }
        }
      }

      await cleanup();
      await userEntryListManager.createEntryList(startKey);
      await userEntryListManager.getEntryLists()[startKey]!.addVideo(video);
      addTearDown(cleanup);

      await tester.pumpWidget(cfg.buildApp(LOCALE_ENGLISH));
      await settle(tester);

      // Lists tab -> My Lists.
      await tester.tap(find.byIcon(Icons.view_list));
      await settle(tester);
      expect(
        find.text('RenameMe'),
        findsOneWidget,
        reason: 'the seeded list should be on the My Lists tab',
      );

      // Enter edit mode (the pencil flips from outline to filled).
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await settle(tester);

      // --- Rename the seeded list by tapping it. ---
      await tester.tap(find.text('RenameMe'));
      await settle(tester);
      expect(
        find.text('Rename List'),
        findsOneWidget,
        reason: 'tapping a list in edit mode should open the rename dialog',
      );
      // The dialog is pre-filled with the current name.
      expect(find.widgetWithText(TextField, 'RenameMe'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Renamed');
      await tester.tap(find.text('Confirm'));
      await settle(tester);

      // The list now lives under the new key, kept its saved video, and the
      // old key is gone.
      final lists = userEntryListManager.getEntryLists();
      expect(
        lists.containsKey(endKey),
        isTrue,
        reason: 'rename should move the list to the new key',
      );
      expect(
        lists.containsKey(startKey),
        isFalse,
        reason: 'the old key should be gone after rename',
      );
      expect(
        lists[endKey]!.containsVideo(video),
        isTrue,
        reason: 'the saved video should survive the rename',
      );
      expect(
        find.text('Renamed'),
        findsOneWidget,
        reason: 'the renamed list should show its new name',
      );
      expect(find.text('RenameMe'), findsNothing);

      // --- The default list offers a rename as well. ---
      // Still in edit mode. Opened and cancelled rather than gone through
      // with, so a run on a real install leaves the user's list as it was.
      final defaultKey = userEntryListManager.defaultListKey;
      final defaultName = userEntryListManager
          .getEntryLists()[defaultKey]!
          .getName();
      await tester.tap(find.text(defaultName));
      await settle(tester);
      expect(
        find.text('Rename List'),
        findsOneWidget,
        reason: 'the default list should be renamable like any other',
      );
      expect(find.widgetWithText(TextField, defaultName), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      expect(userEntryListManager.defaultListKey, defaultKey);
      expect(find.text(defaultName), findsOneWidget);
    },
  );
}
