import 'dart:collection';

import 'package:dictionarylib/common.dart';
import 'package:dictionarylib/entry_list.dart';
import 'package:dictionarylib/entry_types.dart';
import 'package:dictionarylib/globals.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '_helpers.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    sharedPreferences = await SharedPreferences.getInstance();
    seedDictionary(['apple', 'banana', 'cherry', 'date']);
  });

  group('EntryList.getKeyFromName / getNameFromKey', () {
    test('round-trips simple names', () {
      final key = EntryList.getKeyFromName('Animals');
      expect(key, 'Animals_words');
      expect(EntryList.getNameFromKey(key), 'Animals');
    });

    test('replaces spaces in names with underscores', () {
      final key = EntryList.getKeyFromName('My cool list');
      expect(key, 'My_cool_list_words');
      expect(EntryList.getNameFromKey(key), 'My cool list');
    });

    test('returns "Favourites" for the favourites key', () {
      expect(EntryList.getNameFromKey(KEY_FAVOURITES_ENTRIES), 'Favourites');
    });

    test('rejects empty names', () {
      expect(() => EntryList.getKeyFromName(''), throwsA(anything));
    });

    test('rejects "Favourites" / "favourites" (any case, with whitespace)', () {
      for (final name in const [
        'Favourites',
        'favourites',
        'FAVOURITES',
        '  Favourites  ',
      ]) {
        expect(() => EntryList.getKeyFromName(name), throwsA(anything),
            reason: '$name should be rejected as reserved');
      }
    });
  });

  group('EntryList persistence', () {
    test('addEntry persists the entry key to sharedPreferences', () async {
      final list = EntryList('cats_words', LinkedHashSet<Entry>(), true);
      await list.addEntry(FakeEntry('apple'));
      expect(sharedPreferences.getStringList('cats_words'), ['apple']);
    });

    test('removeEntry persists the removal', () async {
      final entry = FakeEntry('apple');
      final entries = LinkedHashSet<Entry>()..add(entry);
      final list = EntryList('cats_words', entries, true);
      await list.write();
      expect(sharedPreferences.getStringList('cats_words'), ['apple']);
      await list.removeEntry(entry);
      expect(sharedPreferences.getStringList('cats_words'), isEmpty);
    });

    test('fromRaw loads previously-written entries', () async {
      await sharedPreferences.setStringList('cats_words', ['apple', 'banana']);
      final list = EntryList.fromRaw('cats_words');
      expect(list.entries.map((e) => e.getKey()), ['apple', 'banana']);
    });

    test('fromRaw drops entries no longer in the dictionary', () async {
      await sharedPreferences
          .setStringList('cats_words', ['apple', 'no_longer_in_dict']);
      final list = EntryList.fromRaw('cats_words');
      expect(list.entries.map((e) => e.getKey()), ['apple']);
    });
  });

  group('EntryList favourites rules', () {
    test('favourites cannot be deleted; user lists can', () {
      final fav = EntryList(KEY_FAVOURITES_ENTRIES, LinkedHashSet(), true);
      final user = EntryList('cats_words', LinkedHashSet(), true);
      expect(fav.canBeDeleted(), isFalse);
      expect(user.canBeDeleted(), isTrue);
    });

    test('canBeEdited reflects the constructor flag', () {
      final readOnly = EntryList('community_words', LinkedHashSet(), false);
      final editable = EntryList('cats_words', LinkedHashSet(), true);
      expect(readOnly.canBeEdited(), isFalse);
      expect(editable.canBeEdited(), isTrue);
    });
  });

  group('UserEntryListManager', () {
    test('fromStartup defaults to a single favourites list', () async {
      userEntryListManager = UserEntryListManager.fromStartup();
      expect(
          userEntryListManager.getEntryLists().keys, [KEY_FAVOURITES_ENTRIES]);
    });

    test('createEntryList adds to the index and is persisted', () async {
      userEntryListManager = UserEntryListManager.fromStartup();
      await userEntryListManager.createEntryList('cats_words');
      expect(userEntryListManager.getEntryLists().keys,
          [KEY_FAVOURITES_ENTRIES, 'cats_words']);
      expect(sharedPreferences.getStringList(KEY_ENTRY_LIST_KEYS),
          [KEY_FAVOURITES_ENTRIES, 'cats_words']);

      // Reload from prefs and verify the new list survives.
      userEntryListManager = UserEntryListManager.fromStartup();
      expect(userEntryListManager.getEntryLists().keys,
          [KEY_FAVOURITES_ENTRIES, 'cats_words']);
    });

    test('createEntryList rejects duplicate keys', () async {
      userEntryListManager = UserEntryListManager.fromStartup();
      await userEntryListManager.createEntryList('cats_words');
      expect(() => userEntryListManager.createEntryList('cats_words'),
          throwsA(anything));
    });

    test('deleteEntryList removes the index entry + its payload', () async {
      userEntryListManager = UserEntryListManager.fromStartup();
      await userEntryListManager.createEntryList('cats_words');
      await userEntryListManager
          .getEntryLists()['cats_words']!
          .addEntry(FakeEntry('apple'));
      expect(sharedPreferences.getStringList('cats_words'), ['apple']);

      await userEntryListManager.deleteEntryList('cats_words');
      expect(
          userEntryListManager.getEntryLists().keys, [KEY_FAVOURITES_ENTRIES]);
      expect(sharedPreferences.getStringList(KEY_ENTRY_LIST_KEYS),
          [KEY_FAVOURITES_ENTRIES]);
      expect(sharedPreferences.getStringList('cats_words'), isNull);
    });

    test('reorder refuses to move favourites away from index 0', () async {
      userEntryListManager = UserEntryListManager.fromStartup();
      await userEntryListManager.createEntryList('a_words');
      await userEntryListManager.createEntryList('b_words');
      userEntryListManager.reorder(0, 2);
      expect(userEntryListManager.getEntryLists().keys.first,
          KEY_FAVOURITES_ENTRIES);
    });

    test('reorder swaps non-favourites lists', () async {
      userEntryListManager = UserEntryListManager.fromStartup();
      await userEntryListManager.createEntryList('a_words');
      await userEntryListManager.createEntryList('b_words');
      // Move b_words (index 2) before a_words (index 1).
      userEntryListManager.reorder(2, 1);
      expect(userEntryListManager.getEntryLists().keys.toList(),
          [KEY_FAVOURITES_ENTRIES, 'b_words', 'a_words']);
    });
  });
}
