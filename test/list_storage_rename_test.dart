import 'package:dictionarylib/entry_list.dart';
import 'package:dictionarylib/entry_types.dart';
import 'package:dictionarylib/flashcards_logic.dart';
import 'package:dictionarylib/globals.dart';
import 'package:dictionarylib/list_storage.dart';
import 'package:dictionarylib/lists_service.dart';
import 'package:dictionarylib/saved_video.dart';
import 'package:dictionarylib/sharing/sharing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '_helpers.dart';
import '_recording_prefs.dart';

/// Renaming a list gives it a new storage key, and several things are
/// stored against the old one: its saved videos, its place in the order,
/// whether it's chosen for revision, and — for the default list — the
/// pointer that says it can't be deleted. All of them have to move
/// together, and a rename that's cut short must not leave the list in two
/// places or in none.

SavedVideo _video(String entry) =>
    SavedVideo(entryKey: entry, mediaPath: videoFor(entry));

String _v3(String entry) => _video(entry).toStorage();

/// A settled install: the default list, two more, one chosen for revision
/// alongside the default.
Map<String, Object> _install() => {
  KEY_ENTRY_LIST_KEYS: [kDefaultListKey, 'cats_words', 'dogs_words'],
  KEY_DEFAULT_LIST_KEY: kDefaultListKey,
  kDefaultListKey: [_v3('apple'), _v3('banana')],
  listSchemaVersionKey(kDefaultListKey): 3,
  'cats_words': [_v3('cherry')],
  listSchemaVersionKey('cats_words'): 3,
  'dogs_words': [_v3('dog')],
  listSchemaVersionKey('dogs_words'): 3,
  KEY_LISTS_TO_REVIEW: [kDefaultListKey, 'cats_words'],
  'theme_variant': 'hearth',
};

void _boot() {
  userEntryListManager = UserEntryListManager.fromStartup();
}

/// `[key, [saved videos]]` for each list, in order.
List<Object> _lists() => [
  for (final list in userEntryListManager.getEntryLists().values)
    [
      list.key,
      [for (final v in list.savedVideos) v.toStorage()],
    ],
];

void main() {
  setUp(() {
    installFakeSecureStorage();
    seedDictionary(['apple', 'banana', 'cherry', 'dog', 'eel']);
    startingLocale = LOCALE_ENGLISH;
    sharing = Sharing.disabled();
  });

  group('renaming the default list', () {
    test('takes its videos, its place, the pointer and the revision '
        'selection with it', () async {
      await installPrefs(_install());
      _boot();

      await userEntryListManager.renameEntryList(
        kDefaultListKey,
        'Everyday_Signs_words',
      );

      expect(prefsSnapshot(), {
        KEY_ENTRY_LIST_KEYS: [
          'Everyday_Signs_words',
          'cats_words',
          'dogs_words',
        ],
        KEY_DEFAULT_LIST_KEY: 'Everyday_Signs_words',
        'Everyday_Signs_words': [_v3('apple'), _v3('banana')],
        listSchemaVersionKey('Everyday_Signs_words'): 3,
        'cats_words': [_v3('cherry')],
        listSchemaVersionKey('cats_words'): 3,
        'dogs_words': [_v3('dog')],
        listSchemaVersionKey('dogs_words'): 3,
        KEY_LISTS_TO_REVIEW: ['Everyday_Signs_words', 'cats_words'],
        'theme_variant': 'hearth',
      });
      expect(userEntryListManager.defaultListKey, 'Everyday_Signs_words');
      final renamed = userEntryListManager
          .getEntryLists()['Everyday_Signs_words']!;
      expect(renamed.getName(), 'Everyday Signs');
      expect(renamed.canBeDeleted(), isFalse);
      expect(loadListsToReview(), ['Everyday_Signs_words', 'cats_words']);
    });

    test('is still in place, and still undeletable, after a restart', () async {
      await installPrefs(_install());
      _boot();
      await userEntryListManager.renameEntryList(
        kDefaultListKey,
        'Everyday_Signs_words',
      );
      final after = prefsSnapshot();

      final store = await installPrefs(after);
      _boot();

      expect(store.writes, isEmpty);
      expect(_lists(), [
        [
          'Everyday_Signs_words',
          [_v3('apple'), _v3('banana')],
        ],
        [
          'cats_words',
          [_v3('cherry')],
        ],
        [
          'dogs_words',
          [_v3('dog')],
        ],
      ]);
      expect(
        userEntryListManager
            .getEntryLists()['Everyday_Signs_words']!
            .canBeDeleted(),
        isFalse,
      );
      expect(
        () => userEntryListManager.deleteEntryList('Everyday_Signs_words'),
        throwsStateError,
      );
    });

    test('keeps working for a sign saved straight afterwards', () async {
      await installPrefs(_install());
      _boot();
      await userEntryListManager.renameEntryList(
        kDefaultListKey,
        'Everyday_Signs_words',
      );
      final list = userEntryListManager
          .getEntryLists()['Everyday_Signs_words']!;
      await list.addVideo(_video('eel'));

      await installPrefs(prefsSnapshot());
      _boot();
      expect(
        userEntryListManager
            .getEntryLists()['Everyday_Signs_words']!
            .savedVideos
            .map((v) => v.entryKey),
        ['apple', 'banana', 'eel'],
      );
    });

    test('frees the name Favourites for another list', () async {
      await installPrefs(_install());
      _boot();
      expect(
        () => userEntryListManager.createEntryList('Favourites_words'),
        throwsA(isA<EntryListNameException>()),
      );

      await userEntryListManager.renameEntryList(
        kDefaultListKey,
        'Everyday_Signs_words',
      );
      await userEntryListManager.createEntryList('Favourites_words');

      final second = userEntryListManager.getEntryLists()['Favourites_words']!;
      expect(second.savedVideos, isEmpty);
      expect(second.canBeDeleted(), isTrue);
      await userEntryListManager.deleteEntryList('Favourites_words');
      expect(userEntryListManager.defaultListKey, 'Everyday_Signs_words');
    });

    test('back to its old name works', () async {
      await installPrefs(_install());
      _boot();
      await userEntryListManager.renameEntryList(kDefaultListKey, 'A_words');
      await userEntryListManager.renameEntryList('A_words', kDefaultListKey);
      expect(prefsSnapshot(), _install());
    });
  });

  group('renaming any other list', () {
    test('leaves the pointer alone and keeps the list chosen for '
        'revision', () async {
      await installPrefs(_install());
      _boot();

      await userEntryListManager.renameEntryList(
        'cats_words',
        'Big_Cats_words',
      );

      expect(prefsSnapshot(), {
        KEY_ENTRY_LIST_KEYS: [kDefaultListKey, 'Big_Cats_words', 'dogs_words'],
        KEY_DEFAULT_LIST_KEY: kDefaultListKey,
        kDefaultListKey: [_v3('apple'), _v3('banana')],
        listSchemaVersionKey(kDefaultListKey): 3,
        'Big_Cats_words': [_v3('cherry')],
        listSchemaVersionKey('Big_Cats_words'): 3,
        'dogs_words': [_v3('dog')],
        listSchemaVersionKey('dogs_words'): 3,
        // It used to drop out of the selection, since that's stored by key.
        KEY_LISTS_TO_REVIEW: [kDefaultListKey, 'Big_Cats_words'],
        'theme_variant': 'hearth',
      });
    });

    test(
      'that is not chosen for revision leaves the selection alone',
      () async {
        await installPrefs(_install());
        _boot();
        await userEntryListManager.renameEntryList(
          'dogs_words',
          'Hounds_words',
        );
        expect(sharedPreferences.getStringList(KEY_LISTS_TO_REVIEW), [
          kDefaultListKey,
          'cats_words',
        ]);
      },
    );

    test('to a name that is taken changes nothing', () async {
      await installPrefs(_install());
      _boot();
      await expectLater(
        userEntryListManager.renameEntryList('cats_words', 'dogs_words'),
        throwsA(isA<EntryListNameException>()),
      );
      await expectLater(
        userEntryListManager.renameEntryList('cats_words', kDefaultListKey),
        throwsA(isA<EntryListNameException>()),
      );
      expect(prefsSnapshot(), _install());
    });

    test('clears stray data left under the new key rather than adopting '
        'it', () async {
      final install = _install()
        ..['Big_Cats_words'] = [_v3('eel')]
        ..[listSchemaVersionKey('Big_Cats_words')] = 2;
      await installPrefs(install);
      _boot();
      await userEntryListManager.renameEntryList(
        'cats_words',
        'Big_Cats_words',
      );
      expect(sharedPreferences.getStringList('Big_Cats_words'), [
        _v3('cherry'),
      ]);
      expect(
        sharedPreferences.getInt(listSchemaVersionKey('Big_Cats_words')),
        3,
      );
    });
  });

  test('a list that is shared from this device is renamed through its '
      'share, not here', () async {
    await installPrefs(_install());
    _boot();
    installFakeSharing((req) async {
      if (req.method == 'POST') return stubCreateResponse(req);
      return http.Response('', 404);
    });
    await listsService.shareList(
      sourceList: userEntryListManager.getEntryLists()['cats_words']!,
      displayName: 'Cat Signs',
      sessionToken: kTestSession.sessionToken,
    );
    final before = prefsSnapshot();

    await expectLater(
      userEntryListManager.renameEntryList('cats_words', 'Big_Cats_words'),
      throwsStateError,
    );
    expect(prefsSnapshot(), before);
    expect(userEntryListManager.getEntryLists().keys, [
      kDefaultListKey,
      'cats_words',
      'dogs_words',
    ]);
  });

  group('a rename that is cut short', () {
    // Relaunch from every state a crash during the rename could have left
    // on disk. The list must come back whole under one name or the other,
    // with everything else that refers to it agreeing.
    Future<void> expectAllOrNothing(String oldKey, String newKey) async {
      await installPrefs(_install());
      _boot();
      final before = prefsSnapshot();
      final store = await installPrefs(_install());
      _boot();
      await userEntryListManager.renameEntryList(oldKey, newKey);
      final after = prefsSnapshot();
      final writes = List.of(store.writes);
      expect(writes, isNotEmpty);

      var sawBefore = false;
      var sawAfter = false;
      for (var n = 0; n <= writes.length; n++) {
        await installPrefs(replayWrites(_install(), writes, n));
        _boot();
        final recovered = prefsSnapshot();
        final why = 'after dying $n writes into ${writes.length}: $writes';
        expect(recovered, anyOf(before, after), reason: why);
        if (_equal(recovered, before)) {
          // Once the rename has taken effect it never goes back.
          expect(sawAfter, isFalse, reason: why);
          sawBefore = true;
        } else {
          sawAfter = true;
        }
        // Whichever it is, nothing was lost.
        final videos = [
          for (final l in userEntryListManager.getEntryLists().values)
            ...l.savedVideos.map((v) => v.toStorage()),
        ];
        expect(videos, [
          _v3('apple'),
          _v3('banana'),
          _v3('cherry'),
          _v3('dog'),
        ], reason: why);
        expect(
          userEntryListManager.getEntryLists().keys,
          contains(userEntryListManager.defaultListKey),
          reason: why,
        );
      }
      expect(sawBefore, isTrue);
      expect(sawAfter, isTrue);
    }

    test('of the default list comes back whole', () async {
      await expectAllOrNothing(kDefaultListKey, 'Everyday_Signs_words');
    });

    test('of another list comes back whole', () async {
      await expectAllOrNothing('cats_words', 'Big_Cats_words');
    });

    test(
      'of a list that is not chosen for revision comes back whole',
      () async {
        await expectAllOrNothing('dogs_words', 'Hounds_words');
      },
    );
  });

  group('deleting and reordering', () {
    test('the default list cannot be deleted, wherever it sits', () async {
      await installPrefs(_install());
      _boot();
      userEntryListManager.reorder(0, 3);
      await userEntryListManager.writeEntryListKeys();
      expect(userEntryListManager.getEntryLists().keys, [
        'cats_words',
        'dogs_words',
        kDefaultListKey,
      ]);

      expect(
        () => userEntryListManager.deleteEntryList(kDefaultListKey),
        throwsStateError,
      );
      final lists = userEntryListManager.getEntryLists();
      expect(lists[kDefaultListKey]!.canBeDeleted(), isFalse);
      expect(lists['cats_words']!.canBeDeleted(), isTrue);
      expect(sharedPreferences.getStringList(kDefaultListKey), [
        _v3('apple'),
        _v3('banana'),
      ]);
    });

    test('other lists can be deleted, including the first one', () async {
      await installPrefs(_install());
      _boot();
      userEntryListManager.reorder(1, 0);
      await userEntryListManager.writeEntryListKeys();
      expect(userEntryListManager.getEntryLists().keys.first, 'cats_words');

      await userEntryListManager.deleteEntryList('cats_words');

      expect(userEntryListManager.getEntryLists().keys, [
        kDefaultListKey,
        'dogs_words',
      ]);
      expect(sharedPreferences.containsKey('cats_words'), isFalse);
      expect(userEntryListManager.defaultListKey, kDefaultListKey);
    });

    test('every reorder of three lists lands where the drag put it', () async {
      // (from, to) as the reorderable list reports them: `to` counts
      // positions before the dragged row is taken out.
      const keys = [kDefaultListKey, 'cats_words', 'dogs_words'];
      for (var from = 0; from < 3; from++) {
        for (var to = 0; to <= 3; to++) {
          if (to == from || to == from + 1) continue; // dropped in place
          await installPrefs(_install());
          _boot();
          userEntryListManager.reorder(from, to);

          final expected = keys.toList()..removeAt(from);
          expected.insert(to > from ? to - 1 : to, keys[from]);
          expect(
            userEntryListManager.getEntryLists().keys,
            expected,
            reason: 'moving $from to $to',
          );
          expect(userEntryListManager.defaultListKey, kDefaultListKey);
        }
      }
    });
  });
}

bool _equal(Map<String, Object> a, Map<String, Object> b) =>
    equals(a).matches(b, <dynamic, dynamic>{});
