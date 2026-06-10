import 'dart:collection';

import 'package:dictionarylib/common.dart';
import 'package:dictionarylib/entry_list.dart';
import 'package:dictionarylib/globals.dart';
import 'package:dictionarylib/saved_video.dart';
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
    test('addVideo persists the saved video to sharedPreferences', () async {
      final list = EntryList('cats_words', LinkedHashSet<SavedVideo>(), true);
      final v = SavedVideo(entryKey: 'apple', videoUrl: videoFor('apple'));
      await list.addVideo(v);
      expect(sharedPreferences.getStringList('cats_words'),
          ['apple|${videoFor('apple')}']);
    });

    test('removeVideo persists the removal', () async {
      final v = SavedVideo(entryKey: 'apple', videoUrl: videoFor('apple'));
      final saved = LinkedHashSet<SavedVideo>()..add(v);
      final list = EntryList('cats_words', saved, true);
      await list.write();
      expect(sharedPreferences.getStringList('cats_words'),
          ['apple|${videoFor('apple')}']);
      await list.removeVideo(v);
      expect(sharedPreferences.getStringList('cats_words'), isEmpty);
    });

    test('addAllVideosOfEntry adds every video of the entry', () async {
      seedDictionary(['apple'], videosByKey: {
        'apple': ['https://example.test/apple-1.mp4', 'https://example.test/apple-2.mp4']
      });
      final list = EntryList('cats_words', LinkedHashSet<SavedVideo>(), true);
      await list.addAllVideosOfEntry(keyedByEnglishEntriesGlobal['apple']!);
      expect(list.savedVideos.length, 2);
      expect(list.containsEntry(keyedByEnglishEntriesGlobal['apple']!), isTrue);
    });

    test('fromRaw loads previously-written saved videos', () async {
      await sharedPreferences.setStringList('cats_words', [
        'apple|${videoFor('apple')}',
        'banana|${videoFor('banana')}',
      ]);
      // Mark as already migrated so we don't trigger the legacy expand.
      await sharedPreferences.setInt('cats_words_schemaVersion', 2);
      final list = EntryList.fromRaw('cats_words');
      expect(list.savedVideos.map((v) => v.entryKey), ['apple', 'banana']);
    });
  });

  group('EntryList.containsAllVideosOf', () {
    test('true only once every video of the entry is saved', () async {
      seedDictionary(['apple'], videosByKey: {
        'apple': ['https://example.test/a1.mp4', 'https://example.test/a2.mp4'],
      });
      final entry = keyedByEnglishEntriesGlobal['apple']!;
      final list = EntryList('cats_words', LinkedHashSet<SavedVideo>(), true);

      // Nothing saved → not fully contained.
      expect(list.containsAllVideosOf(entry), isFalse);

      // One of two saved → partially saved; still keep showing it in "add".
      await list.addVideo(SavedVideo(
          entryKey: 'apple', videoUrl: 'https://example.test/a1.mp4'));
      expect(list.containsEntry(entry), isTrue);
      expect(list.containsAllVideosOf(entry), isFalse);

      // Both saved → fully contained; nothing left to add.
      await list.addVideo(SavedVideo(
          entryKey: 'apple', videoUrl: 'https://example.test/a2.mp4'));
      expect(list.containsAllVideosOf(entry), isTrue);
    });

    test('an entry with no videos is never fully contained', () {
      keyedByEnglishEntriesGlobal['voiceless'] = FakeEntry('voiceless');
      final list = EntryList('cats_words', LinkedHashSet<SavedVideo>(), true);
      expect(
          list.containsAllVideosOf(keyedByEnglishEntriesGlobal['voiceless']!),
          isFalse);
    });
  });

  group('EntryList v1→v2 migration', () {
    test('legacy entry keys expand to every video of the entry', () async {
      seedDictionary(['apple', 'banana'], videosByKey: {
        'apple': [
          'https://example.test/apple-1.mp4',
          'https://example.test/apple-2.mp4'
        ],
        'banana': ['https://example.test/banana.mp4'],
      });
      await sharedPreferences.setStringList('cats_words', ['apple', 'banana']);
      final list = EntryList.fromRaw('cats_words');
      expect(list.savedVideos.length, 3);
      expect(sharedPreferences.getInt('cats_words_schemaVersion'), 2);
      // Migration is written back so the next load skips the expand.
      expect(sharedPreferences.getStringList('cats_words'), [
        'apple|https://example.test/apple-1.mp4',
        'apple|https://example.test/apple-2.mp4',
        'banana|https://example.test/banana.mp4',
      ]);
    });

    test('legacy entries no longer in the dictionary are dropped', () async {
      await sharedPreferences
          .setStringList('cats_words', ['apple', 'no_longer_in_dict']);
      final list = EntryList.fromRaw('cats_words');
      expect(list.savedVideos.map((v) => v.entryKey), ['apple']);
    });

    test('a list with schemaVersion=2 is not re-migrated', () async {
      await sharedPreferences.setStringList(
          'cats_words', ['apple|${videoFor('apple')}']);
      await sharedPreferences.setInt('cats_words_schemaVersion', 2);
      final list = EntryList.fromRaw('cats_words');
      expect(list.savedVideos.length, 1);
      expect(list.savedVideos.first.videoUrl, videoFor('apple'));
    });

    test('order is preserved: sub-entries first, then within-sub-entry videos',
        () async {
      // Two-sub-entry entry. expand should walk sub-entries 0, 1, … in
      // order, and within each, the media list in order.
      final entry = FakeEntry('multi', subEntries: const [
        FakeSubEntryFixture(videos: ['s1-v1.mp4', 's1-v2.mp4']),
        FakeSubEntryFixture(videos: ['s2-v1.mp4']),
      ]);
      keyedByEnglishEntriesGlobal['multi'] = entry;
      await sharedPreferences.setStringList('cats_words', ['multi']);
      final list = EntryList.fromRaw('cats_words');
      expect(list.savedVideos.map((v) => v.videoUrl).toList(),
          ['s1-v1.mp4', 's1-v2.mp4', 's2-v1.mp4']);
    });

    test('legacy entry with zero videos is dropped, not added as empty',
        () async {
      // FakeEntry with no `videos` arg has no sub-entries; allVideosOf
      // returns []. Migration drops such items rather than adding a
      // SavedVideo with no URL.
      keyedByEnglishEntriesGlobal['voiceless'] = FakeEntry('voiceless');
      await sharedPreferences
          .setStringList('cats_words', ['voiceless', 'apple']);
      final list = EntryList.fromRaw('cats_words');
      expect(list.savedVideos.map((v) => v.entryKey), ['apple']);
    });

    test('duplicate legacy entries collapse to one set of saved videos',
        () async {
      // Set semantics mean re-saving the same entry doesn't bloat the
      // post-migration list. Important so a buggy v1 client that wrote
      // duplicates doesn't trigger duplicate UI rows.
      await sharedPreferences
          .setStringList('cats_words', ['apple', 'apple', 'apple']);
      final list = EntryList.fromRaw('cats_words');
      expect(list.savedVideos.length, 1);
      expect(list.savedVideos.single.entryKey, 'apple');
    });

    test('empty legacy list still gets the schemaVersion flag set', () async {
      // Fresh-install favourites is the canonical empty-list case. The
      // flag must be set so the next launch doesn't re-scan.
      await sharedPreferences.setStringList('cats_words', const []);
      EntryList.fromRaw('cats_words');
      expect(sharedPreferences.getInt('cats_words_schemaVersion'), 2);
    });

    test('list with no shared-prefs entry at all gets the flag set', () async {
      // First-ever load of a list — sharedPreferences has nothing at
      // the key. Must still set the flag so we don't re-run migration
      // logic on the next launch.
      EntryList.fromRaw('cats_words');
      expect(sharedPreferences.getInt('cats_words_schemaVersion'), 2);
    });

    test('mixed legacy + v2 items in the same list are both honoured',
        () async {
      // A list could be in this state if a v1 client wrote it before
      // upgrade, and a partially-rolled-out v2 client mutated it once
      // (writing one item in the new format) before crashing. The
      // loader must accept both side-by-side.
      seedDictionary(['apple', 'banana']);
      await sharedPreferences.setStringList('cats_words', [
        'apple', // legacy bare key
        'banana|${videoFor('banana')}', // v2 item
      ]);
      final list = EntryList.fromRaw('cats_words');
      expect(list.savedVideos.map((v) => v.entryKey).toSet(),
          {'apple', 'banana'});
      expect(list.containsVideo(
          SavedVideo(entryKey: 'banana', videoUrl: videoFor('banana'))),
          isTrue);
    });

    test('migration is idempotent across two loads', () async {
      seedDictionary(['apple'], videosByKey: {
        'apple': ['https://example.test/a1.mp4', 'https://example.test/a2.mp4'],
      });
      await sharedPreferences.setStringList('cats_words', ['apple']);

      final first = EntryList.fromRaw('cats_words');
      final firstSerialised = sharedPreferences.getStringList('cats_words');
      final flagAfterFirst =
          sharedPreferences.getInt('cats_words_schemaVersion');

      // Second load should be a pure read of the written-back state.
      final second = EntryList.fromRaw('cats_words');
      final secondSerialised = sharedPreferences.getStringList('cats_words');
      final flagAfterSecond =
          sharedPreferences.getInt('cats_words_schemaVersion');

      expect(secondSerialised, firstSerialised);
      expect(flagAfterSecond, flagAfterFirst);
      expect(second.savedVideos.toList(), first.savedVideos.toList());
    });

    test('a list where every legacy entry got dropped still sets the flag',
        () async {
      // Edge case: every entry in the legacy list is missing from the
      // current dictionary. The list ends up empty but we still want
      // the flag set so the next launch skips the (now-pointless)
      // re-scan.
      await sharedPreferences.setStringList(
          'cats_words', ['no_such_entry_1', 'no_such_entry_2']);
      final list = EntryList.fromRaw('cats_words');
      expect(list.savedVideos, isEmpty);
      expect(sharedPreferences.getInt('cats_words_schemaVersion'), 2);
      expect(sharedPreferences.getStringList('cats_words'), isEmpty);
    });

    test('migrated list answers the new read API correctly', () async {
      seedDictionary(['apple'], videosByKey: {
        'apple': ['https://example.test/a1.mp4', 'https://example.test/a2.mp4'],
      });
      await sharedPreferences.setStringList('cats_words', ['apple']);
      final list = EntryList.fromRaw('cats_words');

      expect(list.containsEntry(keyedByEnglishEntriesGlobal['apple']!), isTrue);
      expect(list.videosForEntry(keyedByEnglishEntriesGlobal['apple']!),
          hasLength(2));
      expect(list.uniqueEntries.map((e) => e.getKey()), ['apple']);
      expect(list.groupedByEntry.keys.single.getKey(), 'apple');
      expect(list.groupedByEntry.values.single, hasLength(2));
    });

    test(
        'a v2-only list with no schemaVersion flag is not re-expanded, '
        'just flag-stamped', () async {
      // The flag could be missing (e.g. lost in a crash between the
      // write-back and the flag write — currently they're separate
      // calls). The next load sees v2-format items, doesn't re-expand
      // anything (nothing to expand), and stamps the flag.
      await sharedPreferences.setStringList(
          'cats_words', ['apple|${videoFor('apple')}']);
      // No setInt for the flag.
      final list = EntryList.fromRaw('cats_words');
      expect(list.savedVideos, hasLength(1));
      expect(list.savedVideos.single.videoUrl, videoFor('apple'));
      // Storage shape is unchanged — we didn't accidentally re-write
      // anything garbled.
      expect(sharedPreferences.getStringList('cats_words'),
          ['apple|${videoFor('apple')}']);
      expect(sharedPreferences.getInt('cats_words_schemaVersion'), 2);
    });

    test('SavedVideo.tryParse splits on the FIRST pipe — video URL with '
        'a literal pipe round-trips', () async {
      // Defence in depth: someone constructed a video URL that contains
      // `|`. Storage uses the leftmost `|` as the separator, so the
      // whole URL (including its internal pipes) becomes the videoUrl
      // half. The migration loader handles this correctly because the
      // parse runs before any legacy-expansion fallback.
      seedDictionary(['apple']);
      const oddUrl = 'https://example.test/path?x=a|b|c';
      await sharedPreferences.setStringList('cats_words', ['apple|$oddUrl']);
      final list = EntryList.fromRaw('cats_words');
      expect(list.savedVideos, hasLength(1));
      expect(list.savedVideos.single.entryKey, 'apple');
      expect(list.savedVideos.single.videoUrl, oddUrl);
    });

    test(
        'unwritable fire-and-forget shouldn\'t leave in-memory state '
        'inconsistent', () async {
      // The migration writes are unawaited, so the in-memory result is
      // the source of truth. A second load after the write completed
      // sees the migrated state — checked here by completing the
      // microtask queue between loads.
      seedDictionary(['apple']);
      await sharedPreferences.setStringList('cats_words', ['apple']);
      final first = EntryList.fromRaw('cats_words');
      expect(first.savedVideos, hasLength(1));
      await Future<void>.delayed(Duration.zero);
      final reloaded = EntryList.fromRaw('cats_words');
      expect(reloaded.savedVideos.map((v) => v.toStorage()),
          first.savedVideos.map((v) => v.toStorage()));
    });

    test(
        'UserEntryListManager.fromStartup triggers migration on every '
        'managed list', () async {
      // The manager loads each list via EntryList.fromRaw, so the
      // migration should fire for the manager's known lists exactly
      // once and the flag should be set per-list.
      seedDictionary(['apple', 'banana']);
      await sharedPreferences.setStringList(
          KEY_ENTRY_LIST_KEYS, ['favourites_words', 'cats_words']);
      await sharedPreferences.setStringList('favourites_words', ['apple']);
      await sharedPreferences.setStringList('cats_words', ['banana']);

      userEntryListManager = UserEntryListManager.fromStartup();

      expect(sharedPreferences.getInt('favourites_words_schemaVersion'), 2);
      expect(sharedPreferences.getInt('cats_words_schemaVersion'), 2);
      expect(
          userEntryListManager
              .getEntryLists()['favourites_words']!
              .savedVideos
              .single
              .entryKey,
          'apple');
      expect(
          userEntryListManager
              .getEntryLists()['cats_words']!
              .savedVideos
              .single
              .entryKey,
          'banana');
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
      final v = SavedVideo(entryKey: 'apple', videoUrl: videoFor('apple'));
      await userEntryListManager
          .getEntryLists()['cats_words']!
          .addVideo(v);
      expect(sharedPreferences.getStringList('cats_words'), [v.toStorage()]);

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

    test('renameEntryList moves the list + its videos, keeping position',
        () async {
      userEntryListManager = UserEntryListManager.fromStartup();
      await userEntryListManager.createEntryList('a_words');
      await userEntryListManager.createEntryList('b_words');
      final v = SavedVideo(entryKey: 'apple', videoUrl: videoFor('apple'));
      await userEntryListManager.getEntryLists()['a_words']!.addVideo(v);

      await userEntryListManager.renameEntryList('a_words', 'cats_words');

      final lists = userEntryListManager.getEntryLists();
      // Renamed in place: new key sits where the old one was, old key gone.
      expect(lists.keys.toList(),
          [KEY_FAVOURITES_ENTRIES, 'cats_words', 'b_words']);
      expect(lists.containsKey('a_words'), isFalse);
      // The saved video came along, and the object's own key was updated.
      expect(lists['cats_words']!.containsVideo(v), isTrue);
      expect(lists['cats_words']!.key, 'cats_words');
      // Storage moved to the new key; the old key + its schema flag are gone.
      expect(sharedPreferences.getStringList('cats_words'), [v.toStorage()]);
      expect(sharedPreferences.getStringList('a_words'), isNull);
      expect(sharedPreferences.getInt('a_words_schemaVersion'), isNull);
      // The persisted index reflects the rename.
      expect(sharedPreferences.getStringList(KEY_ENTRY_LIST_KEYS),
          [KEY_FAVOURITES_ENTRIES, 'cats_words', 'b_words']);
    });

    test('renameEntryList survives a reload from prefs', () async {
      userEntryListManager = UserEntryListManager.fromStartup();
      await userEntryListManager.createEntryList('a_words');
      final v = SavedVideo(entryKey: 'apple', videoUrl: videoFor('apple'));
      await userEntryListManager.getEntryLists()['a_words']!.addVideo(v);
      await userEntryListManager.renameEntryList('a_words', 'cats_words');

      userEntryListManager = UserEntryListManager.fromStartup();
      final lists = userEntryListManager.getEntryLists();
      expect(lists.keys.toList(), [KEY_FAVOURITES_ENTRIES, 'cats_words']);
      expect(lists['cats_words']!.containsVideo(v), isTrue);
    });

    test('renameEntryList rejects a name that already exists', () async {
      userEntryListManager = UserEntryListManager.fromStartup();
      await userEntryListManager.createEntryList('a_words');
      await userEntryListManager.createEntryList('b_words');
      expect(() => userEntryListManager.renameEntryList('a_words', 'b_words'),
          throwsA(isA<EntryListNameException>()));
      // The source list is left untouched.
      expect(userEntryListManager.getEntryLists().containsKey('a_words'), isTrue);
    });

    test('renameEntryList refuses to rename favourites', () async {
      userEntryListManager = UserEntryListManager.fromStartup();
      await userEntryListManager.createEntryList('cats_words');
      expect(
          () => userEntryListManager.renameEntryList(
              KEY_FAVOURITES_ENTRIES, 'renamed_words'),
          throwsA(isA<EntryListNameException>()));
      // Favourites stays put under its fixed key, in its place.
      expect(userEntryListManager.getEntryLists().keys.first,
          KEY_FAVOURITES_ENTRIES);
      expect(sharedPreferences.getStringList(KEY_ENTRY_LIST_KEYS)?.first,
          KEY_FAVOURITES_ENTRIES);
    });

    test('renameEntryList is a no-op when the name is unchanged', () async {
      userEntryListManager = UserEntryListManager.fromStartup();
      await userEntryListManager.createEntryList('cats_words');
      final v = SavedVideo(entryKey: 'apple', videoUrl: videoFor('apple'));
      await userEntryListManager.getEntryLists()['cats_words']!.addVideo(v);
      await userEntryListManager.renameEntryList('cats_words', 'cats_words');
      expect(userEntryListManager.getEntryLists()['cats_words']!.containsVideo(v),
          isTrue);
      expect(sharedPreferences.getStringList('cats_words'), [v.toStorage()]);
    });
  });
}
