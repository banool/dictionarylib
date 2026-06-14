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

    test('rejects names containing characters outside the allowed set', () {
      // Regression for the old `[,.-_!]` class, where the unescaped dash
      // formed the range U+002E–U+005F and silently admitted these. They
      // must all be rejected as invalidChars now that the dash is literal.
      for (final name in const [
        'a/b',
        'a:b',
        'a@b',
        'a<b',
        'a[b',
        'a^b',
        'a;b',
        'a=b',
        r'a\b',
      ]) {
        expect(
          () => EntryList.getKeyFromName(name),
          throwsA(isA<EntryListNameException>()
              .having((e) => e.kind, 'kind', EntryListNameError.invalidChars)),
          reason: '$name contains a disallowed character',
        );
      }
    });

    test('accepts the literal punctuation in the allowed set', () {
      for (final name in const [
        'a-b',
        'a_b',
        'a.b',
        'a,b!',
        'Café déjà', // Unicode letters with diacritics.
        'Числа 123', // Cyrillic letters and digits.
        'list 42',
      ]) {
        expect(
          () => EntryList.getKeyFromName(name),
          returnsNormally,
          reason: '$name only uses allowed characters',
        );
      }
    });

    test('a literal underscore in a typed name displays as a space (lossy)',
        () {
      final key = EntryList.getKeyFromName('a_b');
      expect(key, 'a_b_words');
      expect(EntryList.getNameFromKey(key), 'a b');
    });
  });

  group('EntryList persistence', () {
    test('addVideo persists the saved video (by path) to sharedPreferences',
        () async {
      final list = EntryList('cats_words', LinkedHashSet<SavedVideo>(), true);
      final v = SavedVideo(entryKey: 'apple', mediaPath: videoFor('apple'));
      await list.addVideo(v);
      expect(sharedPreferences.getStringList('cats_words'),
          ['apple|${videoFor('apple')}']);
    });

    test('removeVideo persists the removal', () async {
      final v = SavedVideo(entryKey: 'apple', mediaPath: videoFor('apple'));
      final saved = LinkedHashSet<SavedVideo>()..add(v);
      final list = EntryList('cats_words', saved, true);
      await list.write();
      expect(sharedPreferences.getStringList('cats_words'),
          ['apple|${videoFor('apple')}']);
      await list.removeVideo(v);
      expect(sharedPreferences.getStringList('cats_words'), isEmpty);
    });

    test('addAllVideosOfEntry adds every video of the entry', () async {
      seedDictionary([
        'apple'
      ], videosByKey: {
        'apple': ['/apple-1.mp4', '/apple-2.mp4']
      });
      final list = EntryList('cats_words', LinkedHashSet<SavedVideo>(), true);
      await list.addAllVideosOfEntry(keyedByEnglishEntriesGlobal['apple']!);
      expect(list.savedVideos.length, 2);
      expect(list.containsEntry(keyedByEnglishEntriesGlobal['apple']!), isTrue);
    });

    test('fromRaw loads previously-written (v3) saved videos', () async {
      await sharedPreferences.setStringList('cats_words', [
        'apple|${videoFor('apple')}',
        'banana|${videoFor('banana')}',
      ]);
      // Stamp the current version so no migration runs.
      await sharedPreferences.setInt(
          'cats_words_schemaVersion', listSchemaVersion);
      final list = EntryList.fromRaw('cats_words');
      expect(list.savedVideos.map((v) => v.entryKey), ['apple', 'banana']);
      expect(list.savedVideos.map((v) => v.mediaPath),
          [videoFor('apple'), videoFor('banana')]);
    });
  });

  group('EntryList.containsAllVideosOf', () {
    test('true only once every video of the entry is saved', () async {
      seedDictionary([
        'apple'
      ], videosByKey: {
        'apple': ['/a1.mp4', '/a2.mp4'],
      });
      final entry = keyedByEnglishEntriesGlobal['apple']!;
      final list = EntryList('cats_words', LinkedHashSet<SavedVideo>(), true);

      expect(list.containsAllVideosOf(entry), isFalse);

      await list.addVideo(SavedVideo(entryKey: 'apple', mediaPath: '/a1.mp4'));
      expect(list.containsEntry(entry), isTrue);
      expect(list.containsAllVideosOf(entry), isFalse);

      await list.addVideo(SavedVideo(entryKey: 'apple', mediaPath: '/a2.mp4'));
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

  // The list storage format has stepped v1 (entry keys) → v2 (per-video, full
  // URL) → v3 (per-video, media path). loadSavedVideos applies the steps in
  // order, so a list at any version converges to v3. These exercise each entry
  // point.
  group('EntryList migration → v3', () {
    test('v1 (legacy entry keys) expands to every video, as paths', () async {
      seedDictionary([
        'apple',
        'banana'
      ], videosByKey: {
        'apple': ['/apple-1.mp4', '/apple-2.mp4'],
        'banana': ['/banana.mp4'],
      });
      // v1 shape: bare entry keys, no version flag.
      await sharedPreferences.setStringList('cats_words', ['apple', 'banana']);
      final list = EntryList.fromRaw('cats_words');
      expect(list.savedVideos.length, 3);
      expect(sharedPreferences.getInt('cats_words_schemaVersion'),
          listSchemaVersion);
      // Written back as paths so the next load is a plain read.
      expect(sharedPreferences.getStringList('cats_words'), [
        'apple|/apple-1.mp4',
        'apple|/apple-2.mp4',
        'banana|/banana.mp4',
      ]);
    });

    test('v2 (per-video full URL) is rewritten to the media path', () async {
      // v2 shape: "<entryKey>|<fullUrl>", flagged as schemaVersion 2.
      await sharedPreferences
          .setStringList('cats_words', ['apple|${urlFor('apple')}']);
      await sharedPreferences.setInt('cats_words_schemaVersion', 2);
      final list = EntryList.fromRaw('cats_words');
      expect(list.savedVideos.single.entryKey, 'apple');
      expect(list.savedVideos.single.mediaPath, videoFor('apple'));
      expect(sharedPreferences.getStringList('cats_words'),
          ['apple|${videoFor('apple')}']);
      expect(sharedPreferences.getInt('cats_words_schemaVersion'),
          listSchemaVersion);
    });

    test('v1 steps all the way to v3 via v2 (full chain)', () async {
      // A bare entry key with NO version flag must traverse v1→v2→v3: it is
      // expanded to the entry's videos as full URLs, then those URLs are
      // stripped to paths. End state: media paths, flagged v3.
      seedDictionary([
        'apple'
      ], videosByKey: {
        'apple': ['/apple-1.mp4', '/apple-2.mp4'],
      });
      await sharedPreferences.setStringList('cats_words', ['apple']);
      final list = EntryList.fromRaw('cats_words');
      expect(list.savedVideos.map((v) => v.mediaPath).toList(),
          ['/apple-1.mp4', '/apple-2.mp4']);
      expect(sharedPreferences.getStringList('cats_words'),
          ['apple|/apple-1.mp4', 'apple|/apple-2.mp4']);
      expect(sharedPreferences.getInt('cats_words_schemaVersion'),
          listSchemaVersion);
    });

    test('a v2 list with no version flag is treated as v1 and stripped',
        () async {
      // No flag ⇒ start at v1. The pipe item passes through v1→v2 untouched,
      // then v2→v3 strips its base to a path — it is NOT re-expanded.
      await sharedPreferences
          .setStringList('cats_words', ['apple|${urlFor('apple')}']);
      final list = EntryList.fromRaw('cats_words');
      expect(list.savedVideos, hasLength(1));
      expect(list.savedVideos.single.mediaPath, videoFor('apple'));
      expect(sharedPreferences.getStringList('cats_words'),
          ['apple|${videoFor('apple')}']);
      expect(sharedPreferences.getInt('cats_words_schemaVersion'),
          listSchemaVersion);
    });

    test('a v3 list (flagged) is loaded as-is, no migration', () async {
      await sharedPreferences
          .setStringList('cats_words', ['apple|${videoFor('apple')}']);
      await sharedPreferences.setInt(
          'cats_words_schemaVersion', listSchemaVersion);
      final list = EntryList.fromRaw('cats_words');
      expect(list.savedVideos.single.mediaPath, videoFor('apple'));
      // Untouched on disk.
      expect(sharedPreferences.getStringList('cats_words'),
          ['apple|${videoFor('apple')}']);
    });

    test('legacy entries no longer in the dictionary are dropped', () async {
      await sharedPreferences
          .setStringList('cats_words', ['apple', 'no_longer_in_dict']);
      final list = EntryList.fromRaw('cats_words');
      expect(list.savedVideos.map((v) => v.entryKey), ['apple']);
    });

    test('order is preserved: sub-entries first, then within-sub-entry videos',
        () async {
      final entry = FakeEntry('multi', subEntries: const [
        FakeSubEntryFixture(videos: ['/s1-v1.mp4', '/s1-v2.mp4']),
        FakeSubEntryFixture(videos: ['/s2-v1.mp4']),
      ]);
      keyedByEnglishEntriesGlobal['multi'] = entry;
      await sharedPreferences.setStringList('cats_words', ['multi']);
      final list = EntryList.fromRaw('cats_words');
      expect(list.savedVideos.map((v) => v.mediaPath).toList(),
          ['/s1-v1.mp4', '/s1-v2.mp4', '/s2-v1.mp4']);
    });

    test('legacy entry with zero videos is dropped, not added as empty',
        () async {
      keyedByEnglishEntriesGlobal['voiceless'] = FakeEntry('voiceless');
      await sharedPreferences
          .setStringList('cats_words', ['voiceless', 'apple']);
      final list = EntryList.fromRaw('cats_words');
      expect(list.savedVideos.map((v) => v.entryKey), ['apple']);
    });

    test('duplicate legacy entries collapse to one set of saved videos',
        () async {
      await sharedPreferences
          .setStringList('cats_words', ['apple', 'apple', 'apple']);
      final list = EntryList.fromRaw('cats_words');
      expect(list.savedVideos.length, 1);
      expect(list.savedVideos.single.entryKey, 'apple');
    });

    test('empty legacy list still gets the version flag set', () async {
      await sharedPreferences.setStringList('cats_words', const []);
      EntryList.fromRaw('cats_words');
      expect(sharedPreferences.getInt('cats_words_schemaVersion'),
          listSchemaVersion);
    });

    test('list with no shared-prefs entry at all gets the flag set', () async {
      EntryList.fromRaw('cats_words');
      expect(sharedPreferences.getInt('cats_words_schemaVersion'),
          listSchemaVersion);
    });

    test('mixed legacy + v2 items in the same list both reach v3', () async {
      seedDictionary(['apple', 'banana']);
      await sharedPreferences.setStringList('cats_words', [
        'apple', // legacy bare key
        'banana|${urlFor('banana')}', // v2 full-URL item
      ]);
      final list = EntryList.fromRaw('cats_words');
      expect(
          list.savedVideos.map((v) => v.entryKey).toSet(), {'apple', 'banana'});
      // Both ended up keyed by path.
      expect(
          list.containsVideo(
              SavedVideo(entryKey: 'banana', mediaPath: videoFor('banana'))),
          isTrue);
      expect(
          list.containsVideo(
              SavedVideo(entryKey: 'apple', mediaPath: videoFor('apple'))),
          isTrue);
    });

    test('migration is idempotent across two loads', () async {
      seedDictionary([
        'apple'
      ], videosByKey: {
        'apple': ['/a1.mp4', '/a2.mp4'],
      });
      await sharedPreferences.setStringList('cats_words', ['apple']);

      final first = EntryList.fromRaw('cats_words');
      final firstSerialised = sharedPreferences.getStringList('cats_words');
      final flagAfterFirst =
          sharedPreferences.getInt('cats_words_schemaVersion');

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
      await sharedPreferences
          .setStringList('cats_words', ['no_such_entry_1', 'no_such_entry_2']);
      final list = EntryList.fromRaw('cats_words');
      expect(list.savedVideos, isEmpty);
      expect(sharedPreferences.getInt('cats_words_schemaVersion'),
          listSchemaVersion);
      expect(sharedPreferences.getStringList('cats_words'), isEmpty);
    });

    test('migrated list answers the new read API correctly', () async {
      seedDictionary([
        'apple'
      ], videosByKey: {
        'apple': ['/a1.mp4', '/a2.mp4'],
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

    test('a media URL not under any known base is kept as-is, not dropped',
        () async {
      // Defensive: a stored v2 URL from an unexpected host can't be stripped
      // to a path. We keep it verbatim rather than silently deleting the save
      // (it just won't resolve for display until the data matches again).
      const oddUrl = 'https://elsewhere.example/weird/clip.mp4';
      await sharedPreferences.setStringList('cats_words', ['apple|$oddUrl']);
      await sharedPreferences.setInt('cats_words_schemaVersion', 2);
      final list = EntryList.fromRaw('cats_words');
      expect(list.savedVideos.single.entryKey, 'apple');
      expect(list.savedVideos.single.mediaPath, oddUrl);
    });

    test(
        'SavedVideo.tryParse splits on the FIRST pipe — a value with a literal '
        'pipe round-trips through migration', () async {
      // Storage uses the leftmost `|` as the separator, so the whole value
      // (including its internal pipes) is the media half. Here it's a URL
      // under the base, so v2→v3 strips it to a path that keeps the pipes.
      seedDictionary(['apple']);
      final oddUrl = '$kTestMediaBase/path?x=a|b|c';
      await sharedPreferences.setStringList('cats_words', ['apple|$oddUrl']);
      await sharedPreferences.setInt('cats_words_schemaVersion', 2);
      final list = EntryList.fromRaw('cats_words');
      expect(list.savedVideos, hasLength(1));
      expect(list.savedVideos.single.entryKey, 'apple');
      expect(list.savedVideos.single.mediaPath, '/path?x=a|b|c');
    });

    test('in-memory state is correct regardless of the fire-and-forget write',
        () async {
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
      seedDictionary(['apple', 'banana']);
      await sharedPreferences.setStringList(
          KEY_ENTRY_LIST_KEYS, ['favourites_words', 'cats_words']);
      await sharedPreferences.setStringList('favourites_words', ['apple']);
      await sharedPreferences.setStringList('cats_words', ['banana']);

      userEntryListManager = UserEntryListManager.fromStartup();

      expect(sharedPreferences.getInt('favourites_words_schemaVersion'),
          listSchemaVersion);
      expect(sharedPreferences.getInt('cats_words_schemaVersion'),
          listSchemaVersion);
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
      final v = SavedVideo(entryKey: 'apple', mediaPath: videoFor('apple'));
      await userEntryListManager.getEntryLists()['cats_words']!.addVideo(v);
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
      userEntryListManager.reorder(2, 1);
      expect(userEntryListManager.getEntryLists().keys.toList(),
          [KEY_FAVOURITES_ENTRIES, 'b_words', 'a_words']);
    });

    test('renameEntryList moves the list + its videos, keeping position',
        () async {
      userEntryListManager = UserEntryListManager.fromStartup();
      await userEntryListManager.createEntryList('a_words');
      await userEntryListManager.createEntryList('b_words');
      final v = SavedVideo(entryKey: 'apple', mediaPath: videoFor('apple'));
      await userEntryListManager.getEntryLists()['a_words']!.addVideo(v);

      await userEntryListManager.renameEntryList('a_words', 'cats_words');

      final lists = userEntryListManager.getEntryLists();
      expect(lists.keys.toList(),
          [KEY_FAVOURITES_ENTRIES, 'cats_words', 'b_words']);
      expect(lists.containsKey('a_words'), isFalse);
      expect(lists['cats_words']!.containsVideo(v), isTrue);
      expect(lists['cats_words']!.key, 'cats_words');
      expect(sharedPreferences.getStringList('cats_words'), [v.toStorage()]);
      expect(sharedPreferences.getStringList('a_words'), isNull);
      expect(sharedPreferences.getInt('a_words_schemaVersion'), isNull);
      expect(sharedPreferences.getStringList(KEY_ENTRY_LIST_KEYS),
          [KEY_FAVOURITES_ENTRIES, 'cats_words', 'b_words']);
    });

    test('renameEntryList survives a reload from prefs', () async {
      userEntryListManager = UserEntryListManager.fromStartup();
      await userEntryListManager.createEntryList('a_words');
      final v = SavedVideo(entryKey: 'apple', mediaPath: videoFor('apple'));
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
      expect(
          userEntryListManager.getEntryLists().containsKey('a_words'), isTrue);
    });

    test('renameEntryList refuses to rename favourites', () async {
      userEntryListManager = UserEntryListManager.fromStartup();
      await userEntryListManager.createEntryList('cats_words');
      expect(
          () => userEntryListManager.renameEntryList(
              KEY_FAVOURITES_ENTRIES, 'renamed_words'),
          throwsA(isA<EntryListNameException>()));
      expect(userEntryListManager.getEntryLists().keys.first,
          KEY_FAVOURITES_ENTRIES);
      expect(sharedPreferences.getStringList(KEY_ENTRY_LIST_KEYS)?.first,
          KEY_FAVOURITES_ENTRIES);
    });

    test('renameEntryList is a no-op when the name is unchanged', () async {
      userEntryListManager = UserEntryListManager.fromStartup();
      await userEntryListManager.createEntryList('cats_words');
      final v = SavedVideo(entryKey: 'apple', mediaPath: videoFor('apple'));
      await userEntryListManager.getEntryLists()['cats_words']!.addVideo(v);
      await userEntryListManager.renameEntryList('cats_words', 'cats_words');
      expect(
          userEntryListManager.getEntryLists()['cats_words']!.containsVideo(v),
          isTrue);
      expect(sharedPreferences.getStringList('cats_words'), [v.toStorage()]);
    });
  });
}
