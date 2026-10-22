import 'dart:convert';

import 'package:dictionarylib/common.dart';
import 'package:dictionarylib/entry_list.dart';
import 'package:dictionarylib/entry_types.dart';
import 'package:dictionarylib/flashcards_logic.dart';
import 'package:dictionarylib/globals.dart';
import 'package:dictionarylib/l10n/app_localizations.dart';
import 'package:dictionarylib/list_storage.dart';
import 'package:dictionarylib/page_entry_list_overview.dart'
    show KEY_LISTS_OVERVIEW_TAB_INDEX;
import 'package:dictionarylib/revision.dart';
import 'package:dictionarylib/sharing/auth/auth_store.dart';
import 'package:dictionarylib/sharing/synced_entry_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import '../helpers.dart';

// End-to-end coverage for the first launch after the update that made
// Favourites an ordinary list. Until then it lived under a fixed storage key
// and its name wasn't stored at all; now it is stored like any other list,
// under a key made from its name, with one setting saying which list can't be
// deleted.
//
// Each test puts an old install's storage in place, written as the released
// apps wrote it, and only then starts the app, on the device's real storage.
// The move happens once, as the lists are first loaded, so each kind of
// install is its own test file (its own launch of the app).

/// The installs the update lands on.
enum LegacyInstall {
  /// Signs saved to favourites and to one other list, both chosen for
  /// revision.
  plain,

  /// The same, with favourites shared from this device as "Tiny Tunks". The
  /// share is stored against the list's key, and sharing drops a share whose
  /// list it can't find, so this is the install with the most to lose.
  favouritesShared,

  /// One sign saved to favourites and nothing else ever written, with the
  /// app set to a language other than English.
  inAnotherLanguage,
}

const String _oldKey = 'favourites_words';
const String _otherKey = 'Zoo_words';
const String _shareId = 'e2emigrate22';
const String _shareName = 'Tiny Tunks';

/// A share's stored details as a released build wrote them (read off a
/// device), with the list's id changed.
const String _oldShare =
    '{"schemaVersion":2,"listId":"$_shareId","displayName":"$_shareName",'
    '"role":"owner","lastKnownSeq":0,"etag":null,"lastSyncedAt":1792593951,'
    '"serverUpdatedAt":1792593925,"orphaned":false,'
    '"sourceLocalKey":"$_oldKey","pendingOps":[],"cachedMembers":{"owner":'
    '{"userId":"test:e2e","displayName":"E2E Tester"},"editors":[]}}';

void runDefaultListMigrationSuite(
  DictAppTestConfig cfg,
  LegacyInstall install, {
  Locale? language,
}) {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  language ??= LOCALE_ENGLISH;

  final inAnotherLanguage = install == LegacyInstall.inAnotherLanguage;
  final shared = install == LegacyInstall.favouritesShared;

  testWidgets('an install from before Favourites was an ordinary list '
      '(${install.name}) opens with everything where it was', (
    WidgetTester tester,
  ) async {
    expect(
      cfg.storedVideos.length,
      greaterThanOrEqualTo(3),
      reason: 'this suite needs storedVideos in the app\'s test config',
    );
    final inFavourites = inAnotherLanguage
        ? cfg.storedVideos.sublist(0, 1)
        : cfg.storedVideos.sublist(0, 2);
    final inOther = cfg.storedVideos.sublist(2, 3);

    // --- The old install. Nothing of the app has run yet. ---
    final prefs = await SharedPreferences.getInstance();
    // Put back whatever was here before, for a run on an install someone
    // uses (the test runner's own installs start empty).
    final before = {for (final key in prefs.getKeys()) key: prefs.get(key)!};
    addTearDown(() async {
      await prefs.clear();
      for (final MapEntry(:key, :value) in before.entries) {
        switch (value) {
          case final bool v:
            await prefs.setBool(key, v);
          case final int v:
            await prefs.setInt(key, v);
          case final double v:
            await prefs.setDouble(key, v);
          case final String v:
            await prefs.setString(key, v);
          case final List<Object?> v:
            await prefs.setStringList(key, v.cast<String>());
        }
      }
    });
    await prefs.clear();
    // Nobody is signed in. (On iOS the Keychain outlives the app, so a
    // session from an earlier run can still be there, and with one the app
    // would take the made-up share below to the real server.) The upgrade of
    // someone who is signed in, with a share the server knows, is in the
    // multi-device suite, which has a server of its own.
    await AuthStore().clear();

    await prefs.setStringList(_oldKey, inFavourites);
    await prefs.setInt('${_oldKey}_schemaVersion', 3);
    if (inAnotherLanguage) {
      await prefs.setString('locale_override', language!.languageCode);
    } else {
      await prefs.setStringList('word_list_keys', [_oldKey, _otherKey]);
      await prefs.setStringList(_otherKey, inOther);
      await prefs.setInt('${_otherKey}_schemaVersion', 3);
      await prefs.setStringList('lists_chosen_to_review', [_oldKey, _otherKey]);
    }
    if (shared) {
      await prefs.setStringList('shared_list_ids', [_shareId]);
      await prefs.setString('shared_${_shareId}_meta', _oldShare);
    }

    // --- The update's first launch. ---
    await cfg.setup();

    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    advisoryShownOnce = true;

    // The videos have to be ones the dictionary still has, or the lists
    // would rightly come up short.
    for (final stored in cfg.storedVideos) {
      final [entryKey, mediaPath] = stored.split('|');
      final entry = keyedByEnglishEntriesGlobal[entryKey];
      final found =
          entry != null &&
          entry.getSubEntries().any((s) => s.getMedia().contains(mediaPath));
      expect(
        found,
        isTrue,
        reason:
            '"$stored" is no longer in the dictionary: update storedVideos '
            'in the app\'s integration_test/test_config.dart',
      );
    }

    // --- Storage: the list has moved, and all that pointed at it has
    // followed. ---
    final name = lookupDictLibLocalizations(language!).favouritesListName;
    final newKey = EntryList.getKeyFromName(name);
    expect(sharedPreferences.getString(KEY_DEFAULT_LIST_KEY), newKey);
    expect(userEntryListManager.defaultListKey, newKey);
    expect(sharedPreferences.getStringList(newKey), inFavourites);
    expect(sharedPreferences.get(_oldKey), isNull);
    expect(sharedPreferences.get('${_oldKey}_schemaVersion'), isNull);
    expect(sharedPreferences.get(KEY_LIST_KEY_MOVE), isNull);
    expect(sharedPreferences.getStringList(KEY_ENTRY_LIST_KEYS), [
      newKey,
      if (!inAnotherLanguage) _otherKey,
    ]);
    expect(loadListsToReview(), [newKey, if (!inAnotherLanguage) _otherKey]);
    if (!inAnotherLanguage) {
      expect(sharedPreferences.getStringList(_otherKey), inOther);
    }

    final lists = userEntryListManager.getEntryLists();
    expect(lists.keys, [newKey, if (!inAnotherLanguage) _otherKey]);
    expect(lists[newKey]!.savedVideos.map((v) => v.toStorage()), inFavourites);

    if (shared) {
      // The share is still there, and still this list's.
      final share = sharing.lists.ownerForSourceKey(newKey);
      expect(share, isNotNull, reason: 'the share was dropped');
      expect(share!.listId, _shareId);
      expect(share.getName(), _shareName);
      final storedShare = jsonDecode(
        sharedPreferences.getString(sharedMetaStorageKey(_shareId))!,
      ) as Map<String, dynamic>;
      expect(storedShare['sourceLocalKey'], newKey);
      expect(sharedPreferences.getStringList(KEY_SHARED_LIST_IDS), [_shareId]);
    } else {
      expect(sharing.lists.ownerForSourceKey(newKey), isNull);
    }

    // --- The app: the same lists, by the names the user knows them by. ---
    // A shared list goes by its share's name everywhere.
    final shownAs = shared ? _shareName : name;
    final l = lookupDictLibLocalizations(LOCALE_ENGLISH);
    await sharedPreferences.setInt(KEY_LISTS_OVERVIEW_TAB_INDEX, 0);
    await sharedPreferences.setInt(
      KEY_REVISION_STRATEGY,
      RevisionStrategy.SpacedRepetition.index,
    );
    await sharedPreferences.setBool(KEY_WORD_TO_SIGN, true);
    await sharedPreferences.setBool(KEY_SIGN_TO_WORD, true);
    await cfg.seedFlashcardSettings?.call();

    await tester.pumpWidget(cfg.buildApp(LOCALE_ENGLISH));
    await settle(tester);
    await tester.tap(find.byIcon(Icons.view_list));
    await settle(tester);

    final row = find.byKey(ValueKey(newKey));
    expect(row, findsOneWidget);
    expect(find.descendant(of: row, matching: find.text(shownAs)), findsOne);
    if (shared) {
      expect(find.text(name), findsNothing);
    } else {
      expect(
        find.descendant(
          of: row,
          matching: find.text(l.listWordCount(inFavourites.length)),
        ),
        findsOne,
      );
    }
    // A list called Favourites, in any of the apps' languages, has the star.
    // A shared one never does.
    expect(
      find.descendant(of: row, matching: find.byIcon(Icons.star)),
      shared ? findsNothing : findsOne,
    );
    if (!inAnotherLanguage) {
      final other = find.byKey(const ValueKey(_otherKey));
      expect(find.descendant(of: other, matching: find.text('Zoo')), findsOne);
      expect(
        find.descendant(of: other, matching: find.text(l.listWordCount(1))),
        findsOne,
      );
    }

    // Editing the lists: it is the one that can't be deleted.
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await settle(tester);
    expect(
      find.descendant(
        of: find.byKey(ValueKey(newKey)),
        matching: find.byIcon(Icons.remove_circle),
      ),
      findsNothing,
    );
    if (!inAnotherLanguage) {
      expect(
        find.descendant(
          of: find.byKey(const ValueKey(_otherKey)),
          matching: find.byIcon(Icons.remove_circle),
        ),
        findsOne,
      );
    }
    await tester.tap(find.byIcon(Icons.edit));
    await settle(tester);

    // Revision: still the chosen lists, with all their cards, and a session
    // starts from them.
    await tester.tap(find.byIcon(Icons.style));
    await settle(tester);
    expect(find.text(shownAs), findsOneWidget);
    if (!inAnotherLanguage) expect(find.text('Zoo'), findsOneWidget);
    final cards = 2 * (inFavourites.length + (inAnotherLanguage ? 0 : 1));
    expect(find.text(l.revisionFlashcardCount(cards)), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('startButton')));
    await settle(tester);
    expect(find.text('1 / $cards'), findsOneWidget);
    expect(find.byKey(const ValueKey('revealButton')), findsOneWidget);
    await tester.tap(find.widgetWithIcon(IconButton, Icons.close));
    await settle(tester);
    expect(find.byKey(const ValueKey('startButton')), findsOneWidget);
  });
}
