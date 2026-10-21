import 'dart:convert';
import 'dart:math';

import 'package:dictionarylib/entry_list.dart';
import 'package:dictionarylib/entry_types.dart';
import 'package:dictionarylib/flashcards_logic.dart';
import 'package:dictionarylib/globals.dart';
import 'package:dictionarylib/list_storage.dart';
import 'package:dictionarylib/sharing/synced_entry_list.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '_helpers.dart';
import '_recording_prefs.dart';

/// The built-in favourites list used to be recognised by a fixed storage
/// key. It is now an ordinary list, stored under a key derived from its
/// name, with one pointer saying which list can't be deleted. Every
/// existing install has to be carried from the old layout to the new one
/// the first time it launches on this code, without losing a saved sign,
/// a revision selection or a share — whatever state it was in, and
/// however many times that launch is cut short.
///
/// These tests start from what old versions actually left in shared prefs
/// and compare what the user would have seen then with what they see now.

const String _legacy = legacyFavouritesListKey;

const List<String> _dictionary = ['apple', 'banana', 'cherry', 'dog', 'eel'];

/// A saved video as stored today: `entry|path`.
String _v3(String entry) => '$entry|${videoFor(entry)}';

/// A saved video as stored before paths: `entry|full url`.
String _v2(String entry) => '$entry|${urlFor(entry)}';

String _keyFor(String name) => '${name}_words'.replaceAll(' ', '_');

/// Bring the lists up the way a launch does: the user's lists, then sharing
/// (which resolves each share made from this device against them).
void _boot() {
  userEntryListManager = UserEntryListManager.fromStartup();
  installFakeSharing((_) async => http.Response('', 500));
}

/// The user's lists as loaded: `[key, [saved videos]]` for each, in order.
List<Object> _lists() => [
  for (final list in userEntryListManager.getEntryLists().values)
    [
      list.key,
      [for (final v in list.savedVideos) v.toStorage()],
    ],
];

/// What the old layout showed for [prefs]: the lists in index order (the
/// built-in list alone if no index was ever written), each with what the
/// loader makes of its stored videos. The loader hasn't changed, so this is
/// what the user was looking at before the update.
Future<List<Object>> _legacyLists(Map<String, Object> prefs) async {
  await installPrefs(prefs);
  final keys =
      sharedPreferences.getStringList(KEY_ENTRY_LIST_KEYS) ?? [_legacy];
  return [
    for (final key in keys)
      [
        key,
        [for (final v in EntryList.loadSavedVideos(key)) v.toStorage()],
      ],
  ];
}

/// A share's stored metadata, as [SyncedEntryList.writeMeta] leaves it,
/// plus a field this build knows nothing about.
String _meta(
  String id,
  ListRole role, {
  String? source,
  String name = 'A share',
  List<PendingOp> pending = const [],
}) {
  final json = SyncedListMeta(
    listId: id,
    displayName: name,
    role: role,
    lastKnownSeq: 4,
    etag: role == ListRole.subscriber ? '"etag"' : null,
    lastSyncedAt: 1700000000,
    serverUpdatedAt: 1700000001,
    orphaned: false,
    sourceLocalKey: source,
    pendingOps: [...pending],
  ).toJson();
  json['fieldFromALaterBuild'] = {'kept': true};
  return jsonEncode(json);
}

PendingOp _pendingAdd(String entry) => PendingOp(
  opId: 'op-$entry',
  type: 'addEntry',
  args: {'entry': entry, 'video': videoFor(entry)},
  clientTs: 1700000002,
);

/// Launch on [initial] in [locale] and check the install came through
/// whole: same lists in the same order with the same saved videos, the
/// built-in list now an ordinary one named for the locale, and everything
/// that referred to it still referring to it.
Future<void> _expectCarriedOver(
  Map<String, Object> initial, {
  Locale? locale,
}) async {
  final before = await _legacyLists(initial);
  final oldIndex = [for (final l in before) (l as List)[0] as String];

  startingLocale = locale ?? LOCALE_ENGLISH;
  final store = await installPrefs(initial);
  userEntryListManager = UserEntryListManager.fromStartup();
  // Read before sharing loads: a share replays its unsent edits onto its
  // list in memory, which is not part of what was stored.
  final lists = _lists();
  installFakeSharing((_) async => http.Response('', 500));
  final prefs = sharedPreferences;

  // The pointer names a list, and that list sits where the built-in one did.
  final defaultKey = prefs.getString(KEY_DEFAULT_LIST_KEY);
  expect(defaultKey, isNotNull);
  expect(prefs.getStringList(KEY_ENTRY_LIST_KEYS), [
    for (final key in oldIndex) key == _legacy ? defaultKey : key,
  ]);
  expect(userEntryListManager.defaultListKey, defaultKey);

  // It took a key of its own, derived from the name the user has been
  // seeing, and no other list's.
  final expectedName = startingDefaultListName();
  final others = oldIndex.where((key) => key != _legacy).toList();
  expect(others, isNot(contains(defaultKey)));
  var expectedKey = _keyFor(expectedName);
  for (var n = 2; others.contains(expectedKey); n++) {
    expectedKey = _keyFor('$expectedName $n');
  }
  expect(defaultKey, expectedKey);
  expect(defaultKey, isNot(_legacy));

  // Every list holds exactly what it held, in the same order.
  expect(lists, [
    for (final list in before)
      [(list as List)[0] == _legacy ? defaultKey : list[0], list[1]],
  ]);

  // Nothing is left where the built-in list used to be, or mid-move.
  expect(prefs.containsKey(_legacy), isFalse);
  expect(prefs.containsKey(listSchemaVersionKey(_legacy)), isFalse);
  expect(prefs.containsKey(KEY_LIST_KEY_MOVE), isFalse);

  // Only the default list is undeletable.
  for (final list in userEntryListManager.getEntryLists().values) {
    expect(list.canBeDeleted(), list.key != defaultKey, reason: list.key);
  }

  // The revision selection still means the same lists.
  final chosenBefore = initial[KEY_LISTS_TO_REVIEW] as List<String>?;
  expect(
    prefs.getStringList(KEY_LISTS_TO_REVIEW),
    chosenBefore == null
        ? isNull
        : [for (final key in chosenBefore) key == _legacy ? defaultKey : key],
  );
  if (chosenBefore == null) {
    expect(loadListsToReview(), [defaultKey]);
  }

  // Shares: one made from the built-in list now points at where it went;
  // every other one is as it was; and each still loads if it did before.
  for (final id
      in (initial[KEY_SHARED_LIST_IDS] as List<String>?) ?? const <String>[]) {
    final rawBefore = initial[sharedMetaStorageKey(id)] as String?;
    if (rawBefore == null) continue;
    final metaBefore = jsonDecode(rawBefore) as Map<String, dynamic>;
    final source = metaBefore['sourceLocalKey'] as String?;
    final isOwner = metaBefore['role'] == ListRole.owner.name;
    final loadedBefore = !isOwner || oldIndex.contains(source);
    final loaded = sharing.lists.get(id);
    expect(loaded != null, loadedBefore, reason: 'share $id');
    if (loaded == null) continue;

    final expectedSource = source == _legacy ? defaultKey : source;
    expect(jsonDecode(prefs.getString(sharedMetaStorageKey(id))!), {
      ...metaBefore,
      'sourceLocalKey': expectedSource,
    }, reason: 'share $id');
    expect(loaded.meta.role.name, metaBefore['role']);
    expect(loaded.meta.displayName, metaBefore['displayName']);
    expect(
      loaded.meta.pendingOps.length,
      (metaBefore['pendingOps'] as List).length,
    );
    if (isOwner) {
      final local = userEntryListManager.getEntryLists()[expectedSource]!;
      expect(loaded.key, expectedSource);
      expect(identical(loaded.savedVideos, local.savedVideos), isTrue);
      expect(sharing.lists.ownerForSourceKey(expectedSource!), same(loaded));
      expect(local.getName(), metaBefore['displayName']);
    }
  }

  // Nothing unrelated was touched.
  bool listOrShareKey(String key) =>
      key.startsWith('shared_') ||
      key.endsWith('_words') ||
      key.endsWith('_schemaVersion') ||
      const {
        KEY_ENTRY_LIST_KEYS,
        KEY_DEFAULT_LIST_KEY,
        KEY_LIST_KEY_MOVE,
        KEY_LISTS_TO_REVIEW,
      }.contains(key);
  final after = prefsSnapshot();
  expect(
    {
      for (final e in after.entries)
        if (!listOrShareKey(e.key)) e.key: e.value,
    },
    {
      for (final e in initial.entries)
        if (!listOrShareKey(e.key)) e.key: e.value,
    },
  );

  // And it's done: the next launch reads all of this back and writes
  // nothing.
  expect(store.writes, isNotEmpty);
  final again = await installPrefs(after);
  _boot();
  expect(again.writes, isEmpty, reason: 'second launch wrote ${again.writes}');
  expect(prefsSnapshot(), after);
}

/// Launch on [initial], then relaunch from every state a crash part-way
/// through that first launch could have left on disk. Each one has to end
/// up exactly where the uninterrupted launch did.
Future<void> _expectEveryCrashPointRecovers(
  Map<String, Object> initial, {
  Locale? locale,
}) async {
  startingLocale = locale ?? LOCALE_ENGLISH;
  final store = await installPrefs(initial);
  _boot();
  final finished = prefsSnapshot();
  final finishedLists = _lists();
  final writes = List.of(store.writes);

  for (var n = 0; n <= writes.length; n++) {
    await installPrefs(replayWrites(initial, writes, n));
    _boot();
    final why = 'after dying $n writes into ${writes.length}: $writes';
    expect(_lists(), finishedLists, reason: why);
    expect(prefsSnapshot(), finished, reason: why);
  }
}

void main() {
  setUp(() {
    installFakeSecureStorage();
    seedDictionary(_dictionary);
    startingLocale = LOCALE_ENGLISH;
  });

  tearDown(() {
    startingLocale = LOCALE_ENGLISH;
  });

  group('a new install', () {
    for (final (locale, name) in [
      (LOCALE_ENGLISH, 'Favourites'),
      (LOCALE_SINHALA, 'ප්‍රියතම'),
      (LOCALE_TAMIL, 'பிடித்தவை'),
    ]) {
      test('starts with one empty list called "$name"', () async {
        startingLocale = locale;
        await installPrefs({});
        _boot();

        final key = _keyFor(name);
        expect(_lists(), [
          [key, <String>[]],
        ]);
        expect(userEntryListManager.getEntryLists()[key]!.getName(), name);
        expect(sharedPreferences.getStringList(KEY_ENTRY_LIST_KEYS), [key]);
        expect(sharedPreferences.getString(KEY_DEFAULT_LIST_KEY), key);
        expect(sharedPreferences.getInt(listSchemaVersionKey(key)), 3);
        // Nothing is ever written under the old fixed key.
        expect(sharedPreferences.containsKey(_legacy), isFalse);
        expect(sharedPreferences.containsKey(KEY_LIST_KEY_MOVE), isFalse);
      });
    }

    test('falls back to English for a language it has no name in', () async {
      startingLocale = const Locale('fr');
      await installPrefs({});
      _boot();
      expect(userEntryListManager.defaultListKey, 'Favourites_words');
    });

    test('is not redone on the next launch', () async {
      await installPrefs({});
      _boot();
      final after = prefsSnapshot();

      final store = await installPrefs(after);
      _boot();
      expect(store.writes, isEmpty);
    });

    test('keeps its name when the app language changes later', () async {
      await installPrefs({});
      _boot();
      final after = prefsSnapshot();

      startingLocale = LOCALE_SINHALA;
      await installPrefs(after);
      _boot();
      expect(userEntryListManager.getEntryLists().keys, ['Favourites_words']);
    });

    test('survives a crash at any point', () async {
      await _expectEveryCrashPointRecovers({});
    });
  });

  group('an install from before the default list was an ordinary list', () {
    test('that only ever used favourites, so never wrote an index', () async {
      await _expectCarriedOver({
        _legacy: [_v3('apple'), _v3('banana')],
        listSchemaVersionKey(_legacy): 3,
      });
      expect(_lists(), [
        [
          'Favourites_words',
          [_v3('apple'), _v3('banana')],
        ],
      ]);
    });

    test('that never saved anything but has been launched', () async {
      await _expectCarriedOver({
        _legacy: <String>[],
        listSchemaVersionKey(_legacy): 3,
      });
    });

    test('with several lists keeps their order and contents', () async {
      await _expectCarriedOver({
        KEY_ENTRY_LIST_KEYS: [_legacy, 'Animals_words', 'Zoo_🦁_words'],
        _legacy: [_v3('apple')],
        listSchemaVersionKey(_legacy): 3,
        'Animals_words': [_v3('dog'), _v3('eel')],
        listSchemaVersionKey('Animals_words'): 3,
        'Zoo_🦁_words': <String>[],
        listSchemaVersionKey('Zoo_🦁_words'): 3,
      });
      expect(
        userEntryListManager.getEntryLists().values.map((l) => l.getName()),
        ['Favourites', 'Animals', 'Zoo 🦁'],
      );
    });

    test('whose favourites are still in the oldest format (whole entries, '
        'no version recorded)', () async {
      await _expectCarriedOver({
        _legacy: ['apple', 'cherry'],
      });
      expect(_lists(), [
        [
          'Favourites_words',
          [_v3('apple'), _v3('cherry')],
        ],
      ]);
    });

    test('whose favourites are still stored as full URLs', () async {
      await _expectCarriedOver({
        _legacy: [_v2('banana'), _v2('dog')],
        listSchemaVersionKey(_legacy): 2,
      });
      expect(_lists(), [
        [
          'Favourites_words',
          [_v3('banana'), _v3('dog')],
        ],
      ]);
    });

    test('with other lists but nothing ever stored for favourites', () async {
      await _expectCarriedOver({
        KEY_ENTRY_LIST_KEYS: [_legacy, 'Animals_words'],
        'Animals_words': [_v3('dog')],
        listSchemaVersionKey('Animals_words'): 3,
      });
    });

    test('keeps favourites chosen for revision, in place', () async {
      await _expectCarriedOver({
        KEY_ENTRY_LIST_KEYS: [_legacy, 'Animals_words'],
        _legacy: [_v3('apple')],
        'Animals_words': [_v3('dog')],
        KEY_LISTS_TO_REVIEW: ['Animals_words', _legacy, 'Colours_categ'],
      });
      expect(loadListsToReview(), [
        'Animals_words',
        'Favourites_words',
        'Colours_categ',
      ]);
    });

    test('leaves a revision selection without favourites alone', () async {
      await _expectCarriedOver({
        KEY_ENTRY_LIST_KEYS: [_legacy, 'Animals_words'],
        _legacy: [_v3('apple')],
        'Animals_words': [_v3('dog')],
        KEY_LISTS_TO_REVIEW: ['Animals_words'],
      });
    });

    test('still revises from the default list when no selection was ever '
        'made', () async {
      await _expectCarriedOver({
        _legacy: [_v3('apple')],
      });
      expect(sharedPreferences.containsKey(KEY_LISTS_TO_REVIEW), isFalse);
      expect(loadListsToReview(), ['Favourites_words']);
    });

    test('keeps an empty revision selection empty', () async {
      await _expectCarriedOver({
        _legacy: [_v3('apple')],
        KEY_LISTS_TO_REVIEW: <String>[],
      });
      expect(loadListsToReview(), isEmpty);
    });

    for (final (locale, name) in [
      (LOCALE_SINHALA, 'ප්‍රියතම'),
      (LOCALE_TAMIL, 'பிடித்தவை'),
    ]) {
      test('is named "$name" when that is what the user has been '
          'seeing', () async {
        await _expectCarriedOver({
          KEY_ENTRY_LIST_KEYS: [_legacy, 'Animals_words'],
          _legacy: [_v3('apple')],
          'Animals_words': [_v3('dog')],
          KEY_LISTS_TO_REVIEW: [_legacy],
        }, locale: locale);
        expect(userEntryListManager.defaultListKey, _keyFor(name));
        expect(
          userEntryListManager.getEntryLists().values.first.getName(),
          name,
        );
      });

      test('takes "$name 2" if the user already made a list called '
          '"$name"', () async {
        // Only the English word was ever reserved, so this could happen.
        await _expectCarriedOver({
          KEY_ENTRY_LIST_KEYS: [_legacy, _keyFor(name)],
          _legacy: [_v3('apple')],
          _keyFor(name): [_v3('dog')],
          listSchemaVersionKey(_keyFor(name)): 3,
        }, locale: locale);
        expect(_lists(), [
          [
            _keyFor('$name 2'),
            [_v3('apple')],
          ],
          [
            _keyFor(name),
            [_v3('dog')],
          ],
        ]);
      });
    }

    test('skips past every taken numbered name too', () async {
      await _expectCarriedOver({
        KEY_ENTRY_LIST_KEYS: [_legacy, 'ප්‍රියතම_words', 'ප්‍රියතම_2_words'],
        _legacy: [_v3('apple')],
        'ප්‍රියතම_words': [_v3('dog')],
        'ප්‍රියතම_2_words': [_v3('eel')],
      }, locale: LOCALE_SINHALA);
      expect(userEntryListManager.defaultListKey, 'ප්‍රියතම_3_words');
    });

    test('does not pick up stray data left under the key it moves '
        'to', () async {
      // Not a list (it isn't in the index), so not the user's favourites.
      await _expectCarriedOver({
        _legacy: [_v3('apple')],
        listSchemaVersionKey(_legacy): 3,
        'Favourites_words': [_v3('dog'), _v3('eel')],
        listSchemaVersionKey('Favourites_words'): 2,
      });
      expect(_lists(), [
        [
          'Favourites_words',
          [_v3('apple')],
        ],
      ]);
    });

    test('leaves unrelated settings exactly as they were', () async {
      await _expectCarriedOver({
        _legacy: [_v3('apple')],
        'theme_variant': 'hearth',
        'stored_reviews': ['a', 'b'],
        'locale_override': 'en',
        'revision_card_limit': 25,
        'hide_community_lists': true,
        'Animals_categ': ['not a user list'],
      });
    });
  });

  group('an install that had shared its favourites', () {
    // The state the person who reported the revision bug is in: Favourites
    // shared under another name ("Favourites" itself is refused for a
    // share). Sharing drops any share whose source list it can't find, so
    // the share has to be pointed at the list's new key before it loads.
    Map<String, Object> sharedFavourites() => {
      KEY_ENTRY_LIST_KEYS: [_legacy, 'Animals_words'],
      _legacy: [_v3('apple'), _v3('banana')],
      listSchemaVersionKey(_legacy): 3,
      'Animals_words': [_v3('dog')],
      listSchemaVersionKey('Animals_words'): 3,
      KEY_LISTS_TO_REVIEW: [_legacy],
      KEY_SHARED_LIST_IDS: ['own000000001'],
      sharedMetaStorageKey('own000000001'): _meta(
        'own000000001',
        ListRole.owner,
        source: _legacy,
        name: 'Tiny Tunks',
      ),
    };

    test('is still sharing it, under the same name', () async {
      await _expectCarriedOver(sharedFavourites());

      final share = sharing.lists.get('own000000001')!;
      expect(share.meta.role, ListRole.owner);
      expect(share.getName(), 'Tiny Tunks');
      expect(share.key, 'Favourites_words');
      expect(share.savedVideos.map((v) => v.toStorage()), [
        _v3('apple'),
        _v3('banana'),
      ]);
      // The list goes by the share's name while it's shared.
      expect(
        userEntryListManager.getEntryLists().values.map((l) => l.getName()),
        ['Tiny Tunks', 'Animals'],
      );
      expect(sharedPreferences.getStringList(KEY_SHARED_LIST_IDS), [
        'own000000001',
      ]);
    });

    test('keeps edits that had not reached the server yet', () async {
      final initial = sharedFavourites();
      initial[sharedMetaStorageKey('own000000001')] = _meta(
        'own000000001',
        ListRole.owner,
        source: _legacy,
        name: 'Tiny Tunks',
        pending: [_pendingAdd('cherry')],
      );
      await _expectCarriedOver(initial);

      final share = sharing.lists.get('own000000001')!;
      expect(share.meta.pendingOps.single.opId, 'op-cherry');
      // Replayed onto the list on load, as before.
      expect(share.savedVideos.map((v) => v.entryKey), [
        'apple',
        'banana',
        'cherry',
      ]);
    });

    test('leaves its other shares, and ones it follows, untouched', () async {
      final initial = sharedFavourites();
      initial[KEY_SHARED_LIST_IDS] = [
        'own000000001',
        'own000000002',
        'edit00000001',
        'sub000000001',
      ];
      initial[sharedMetaStorageKey('own000000002')] = _meta(
        'own000000002',
        ListRole.owner,
        source: 'Animals_words',
        name: 'Zoo Signs',
      );
      initial[sharedMetaStorageKey('edit00000001')] = _meta(
        'edit00000001',
        ListRole.editor,
        name: 'Class list',
      );
      initial[sharedPayloadStorageKey('edit00000001')] = [_v3('eel')];
      initial[sharedMetaStorageKey('sub000000001')] = _meta(
        'sub000000001',
        ListRole.subscriber,
        name: 'Teacher list',
      );
      initial[sharedPayloadStorageKey('sub000000001')] = [_v3('cherry')];
      final untouched = {
        for (final id in ['own000000002', 'edit00000001', 'sub000000001'])
          sharedMetaStorageKey(id): initial[sharedMetaStorageKey(id)],
      };

      await _expectCarriedOver(initial);

      for (final e in untouched.entries) {
        expect(sharedPreferences.getString(e.key), e.value, reason: e.key);
      }
      expect(sharing.lists.listIds, [
        'own000000001',
        'own000000002',
        'edit00000001',
        'sub000000001',
      ]);
      expect(
        sharing.lists.get('edit00000001')!.savedVideos.single.entryKey,
        'eel',
      );
      expect(
        sharing.lists.get('sub000000001')!.savedVideos.single.entryKey,
        'cherry',
      );
    });

    test('survives a crash at any point', () async {
      await _expectEveryCrashPointRecovers(sharedFavourites());
      expect(sharing.lists.get('own000000001'), isNotNull);
    });

    test('in Sinhala, with a list already called ප්‍රියතම', () async {
      final initial = sharedFavourites();
      initial[KEY_ENTRY_LIST_KEYS] = [
        _legacy,
        'Animals_words',
        'ප්‍රියතම_words',
      ];
      initial['ප්‍රියතම_words'] = [_v3('eel')];
      await _expectCarriedOver(initial, locale: LOCALE_SINHALA);
      expect(sharing.lists.get('own000000001')!.key, 'ප්‍රියතම_2_words');
    });
  });

  group('a launch that is cut short', () {
    final installs = <String, Map<String, Object>>{
      'favourites only, no index': {
        _legacy: [_v3('apple'), _v3('banana')],
        listSchemaVersionKey(_legacy): 3,
      },
      'favourites in the oldest format': {
        _legacy: ['apple', 'dog'],
      },
      'favourites stored as URLs, with other lists and a selection': {
        KEY_ENTRY_LIST_KEYS: [_legacy, 'Animals_words', 'Other_words'],
        _legacy: [_v2('apple')],
        listSchemaVersionKey(_legacy): 2,
        'Animals_words': ['dog', 'eel'],
        'Other_words': [_v3('cherry')],
        listSchemaVersionKey('Other_words'): 3,
        KEY_LISTS_TO_REVIEW: [_legacy, 'Other_words'],
      },
      'other lists, favourites never stored': {
        KEY_ENTRY_LIST_KEYS: [_legacy, 'Animals_words'],
        'Animals_words': [_v3('dog')],
      },
      'stray data under the target key': {
        _legacy: [_v3('apple')],
        'Favourites_words': [_v3('dog')],
        listSchemaVersionKey('Favourites_words'): 3,
      },
    };

    for (final e in installs.entries) {
      test('ends up in the same place: ${e.key}', () async {
        await _expectEveryCrashPointRecovers(e.value);
        await _expectCarriedOver(e.value);
      });
    }

    test('ends up in the same place in Sinhala with a name clash', () async {
      final initial = <String, Object>{
        KEY_ENTRY_LIST_KEYS: [_legacy, 'ප්‍රියතම_words'],
        _legacy: [_v3('apple')],
        'ප්‍රියතම_words': [_v3('dog')],
        KEY_LISTS_TO_REVIEW: [_legacy, 'ප්‍රියතම_words'],
      };
      await _expectEveryCrashPointRecovers(initial, locale: LOCALE_SINHALA);
    });

    test('keeps signs saved after the move even if the old copy is still '
        'around', () async {
      // The move got as far as copying the list and switching the index,
      // the user then saved another sign (under the new key), and the old
      // copy was never cleaned up. The newer copy has to win.
      await installPrefs({
        KEY_LIST_KEY_MOVE: jsonEncode([_legacy, 'Favourites_words']),
        KEY_ENTRY_LIST_KEYS: ['Favourites_words'],
        KEY_DEFAULT_LIST_KEY: 'Favourites_words',
        'Favourites_words': [_v3('apple'), _v3('banana')],
        listSchemaVersionKey('Favourites_words'): 3,
        _legacy: [_v3('apple')],
        listSchemaVersionKey(_legacy): 3,
      });
      _boot();

      expect(_lists(), [
        [
          'Favourites_words',
          [_v3('apple'), _v3('banana')],
        ],
      ]);
      expect(sharedPreferences.containsKey(_legacy), isFalse);
      expect(sharedPreferences.containsKey(KEY_LIST_KEY_MOVE), isFalse);
    });

    test('never overwrites a copy already made under the new key', () async {
      // Journal written, list copied, and the app died before the index
      // was switched. Whatever is under the new key is the list now.
      await installPrefs({
        KEY_LIST_KEY_MOVE: jsonEncode([_legacy, 'Favourites_words']),
        'Favourites_words': [_v3('apple'), _v3('cherry')],
        listSchemaVersionKey('Favourites_words'): 3,
        _legacy: [_v3('apple')],
        listSchemaVersionKey(_legacy): 3,
      });
      _boot();

      expect(_lists(), [
        [
          'Favourites_words',
          [_v3('apple'), _v3('cherry')],
        ],
      ]);
      expect(userEntryListManager.defaultListKey, 'Favourites_words');
    });
  });

  group('a move journal that is not a move in progress', () {
    Map<String, Object> settled() => {
      KEY_ENTRY_LIST_KEYS: ['Favourites_words', 'Animals_words', 'Zoo_words'],
      KEY_DEFAULT_LIST_KEY: 'Favourites_words',
      'Favourites_words': [_v3('apple')],
      listSchemaVersionKey('Favourites_words'): 3,
      'Animals_words': [_v3('dog')],
      listSchemaVersionKey('Animals_words'): 3,
      'Zoo_words': [_v3('eel')],
      listSchemaVersionKey('Zoo_words'): 3,
    };

    Future<void> expectDroppedUntouched(String journal) async {
      final initial = settled()..[KEY_LIST_KEY_MOVE] = journal;
      await installPrefs(initial);
      _boot();
      expect(prefsSnapshot(), settled());
    }

    test('is dropped when both keys are lists', () async {
      await expectDroppedUntouched(jsonEncode(['Animals_words', 'Zoo_words']));
    });

    test('is dropped when neither key is a list', () async {
      await expectDroppedUntouched(jsonEncode(['Gone_words', 'Never_words']));
    });

    test('is dropped when it cannot be read', () async {
      await expectDroppedUntouched('not json');
      await expectDroppedUntouched(jsonEncode({'old': 'a'}));
      await expectDroppedUntouched(jsonEncode(['only one']));
      await expectDroppedUntouched(jsonEncode([1, 2]));
    });
  });

  group('once migrated', () {
    Map<String, Object> migrated() => {
      KEY_ENTRY_LIST_KEYS: ['Favourites_words', 'Animals_words'],
      KEY_DEFAULT_LIST_KEY: 'Favourites_words',
      'Favourites_words': [_v3('apple')],
      listSchemaVersionKey('Favourites_words'): 3,
      'Animals_words': [_v3('dog')],
      listSchemaVersionKey('Animals_words'): 3,
    };

    test('a list the user calls "favourites" is just a list', () async {
      // Its key is the one the built-in list used to have. It must not be
      // taken for an old install and moved, or cleaned up as a leftover.
      final initial = migrated()
        ..[KEY_ENTRY_LIST_KEYS] = ['Favourites_words', 'Animals_words', _legacy]
        ..[_legacy] = [_v3('eel')]
        ..[listSchemaVersionKey(_legacy)] = 3;
      final store = await installPrefs(initial);
      _boot();

      expect(store.writes, isEmpty);
      expect(_lists(), [
        [
          'Favourites_words',
          [_v3('apple')],
        ],
        [
          'Animals_words',
          [_v3('dog')],
        ],
        [
          _legacy,
          [_v3('eel')],
        ],
      ]);
      expect(
        userEntryListManager.getEntryLists()[_legacy]!.getName(),
        'favourites',
      );
      expect(
        userEntryListManager.getEntryLists()[_legacy]!.canBeDeleted(),
        isTrue,
      );
    });

    test('a missing pointer falls to the first list, touching nothing '
        'else', () async {
      final initial = migrated()..remove(KEY_DEFAULT_LIST_KEY);
      await installPrefs(initial);
      _boot();
      expect(prefsSnapshot(), migrated());
    });

    test('a pointer to a list that is gone falls to the first list', () async {
      final initial = migrated()..[KEY_DEFAULT_LIST_KEY] = 'Deleted_words';
      await installPrefs(initial);
      _boot();
      expect(prefsSnapshot(), migrated());
    });

    test('an empty index gets a default list back', () async {
      await installPrefs({
        KEY_ENTRY_LIST_KEYS: <String>[],
        KEY_DEFAULT_LIST_KEY: 'Deleted_words',
      });
      _boot();
      expect(_lists(), [
        ['Favourites_words', <String>[]],
      ]);
      expect(userEntryListManager.defaultListKey, 'Favourites_words');
    });

    test('loading the lists again mid-session changes nothing', () async {
      // The entry loader rebuilds the manager whenever the dictionary data
      // is refreshed.
      await installPrefs({
        _legacy: [_v3('apple')],
      });
      _boot();
      final after = prefsSnapshot();
      final lists = _lists();

      userEntryListManager = UserEntryListManager.fromStartup();
      expect(prefsSnapshot(), after);
      expect(_lists(), lists);
    });
  });

  group('an install captured from a released build', () {
    // Not hand-built: these are the list-related prefs the released apps
    // left on a device, read off it before this code was installed on top.
    test('Auslan 2.x on iOS: favourites shared as "Tiny Tunks", a second '
        'list, both chosen for revision', () async {
      const meta =
          '{"schemaVersion":2,"listId":"ib2g46esf7sb","displayName":"Tiny '
          'Tunks","role":"owner","lastKnownSeq":0,"etag":null,'
          '"lastSyncedAt":1792593951,"serverUpdatedAt":1792593925,'
          '"orphaned":false,"sourceLocalKey":"favourites_words",'
          '"pendingOps":[],"cachedMembers":{"owner":{"userId":'
          '"test:auslan-dev","displayName":"Auslan Tester"},"editors":[]}}';
      final install = <String, Object>{
        'word_list_keys': ['favourites_words', 'Zoo_words'],
        'favourites_words': [
          'apple|/mp4video/29/29380_1.mp4',
          'dog|/mp4video/39/39340_1.mp4',
        ],
        'favourites_words_schemaVersion': 3,
        'Zoo_words': ['cat|/mp4video/50/50980_1.mp4'],
        'Zoo_words_schemaVersion': 3,
        'lists_chosen_to_review': ['favourites_words', 'Zoo_words'],
        'shared_list_ids': ['ib2g46esf7sb'],
        'shared_ib2g46esf7sb_meta': meta,
        'advisory_version': 3,
        'current_data_version': 1234,
        'recent_searches': ['apple', 'dog', 'cat'],
        'reviews_schema_version': 2,
        'shared_client_id': '0123456789abcdef0123456789abcdef',
      };
      await _expectCarriedOver(install);
      await _expectEveryCrashPointRecovers(install);

      expect(_lists(), [
        [
          'Favourites_words',
          ['apple|/mp4video/29/29380_1.mp4', 'dog|/mp4video/39/39340_1.mp4'],
        ],
        [
          'Zoo_words',
          ['cat|/mp4video/50/50980_1.mp4'],
        ],
      ]);
      expect(loadListsToReview(), ['Favourites_words', 'Zoo_words']);
      expect(sharing.lists.get('ib2g46esf7sb')!.getName(), 'Tiny Tunks');
      expect(sharing.lists.get('ib2g46esf7sb')!.key, 'Favourites_words');
    });

    test('SLSL 2.x on Android, in Sinhala: one sign in favourites, nothing '
        'else ever written', () async {
      final install = <String, Object>{
        'favourites_words': ['apple|/media/SLCFDFruits_Apple.mp4'],
        'favourites_words_schemaVersion': 3,
        'locale_override': 'si',
      };
      await _expectCarriedOver(install, locale: LOCALE_SINHALA);
      await _expectEveryCrashPointRecovers(install, locale: LOCALE_SINHALA);

      expect(_lists(), [
        [
          'ප්‍රියතම_words',
          ['apple|/media/SLCFDFruits_Apple.mp4'],
        ],
      ]);
      expect(
        userEntryListManager.getEntryLists().values.single.getName(),
        'ප්‍රියතම',
      );
      expect(loadListsToReview(), ['ප්‍රියතම_words']);
    });
  });

  group('any install an old version could have left', () {
    // Not just the tidy cases above: every combination of list formats,
    // names, selections and shares that the old code could produce, in
    // each language, checked the same way.
    const names = [
      'Animals',
      'Dogs and Cats',
      'Zoo 🦁',
      'x',
      'Favourites 2',
      'ප්‍රියතම',
      'ප්‍රියතම 2',
      'பிடித்தவை',
      'My List',
    ];

    Object? stored(Random r) {
      final picked = (_dictionary.toList()..shuffle(r)).take(r.nextInt(5));
      switch (r.nextInt(6)) {
        case 0:
          return null; // nothing ever written under the key
        case 1:
          return [<String>[], 3];
        case 2:
          return [
            [for (final e in picked) _v3(e)],
            3,
          ];
        case 3:
          return [
            [for (final e in picked) e],
            null,
          ]; // whole entries, before versions were recorded
        case 4:
          return [
            [for (final e in picked) _v2(e)],
            2,
          ];
        default:
          return [
            [for (final e in picked) _v3(e)],
            null,
          ]; // current data whose version flag never landed
      }
    }

    Map<String, Object> randomInstall(Random r) {
      final prefs = <String, Object>{};
      void put(String key, Object? content) {
        if (content == null) return;
        final [videos, version] = content as List;
        prefs[key] = videos as List<String>;
        if (version != null) prefs[listSchemaVersionKey(key)] = version as int;
      }

      put(_legacy, stored(r));
      final others = (names.toList()..shuffle(r))
          .take(r.nextInt(5))
          .map(_keyFor)
          .toList();
      for (final key in others) {
        put(key, stored(r));
      }
      // The index was only written once there was more than favourites
      // (or a list had been made and deleted again).
      if (others.isNotEmpty || r.nextBool()) {
        prefs[KEY_ENTRY_LIST_KEYS] = [_legacy, ...others];
      }

      if (r.nextInt(3) > 0) {
        final candidates = [_legacy, ...others, 'Colours_categ', 'Gone_words']
          ..shuffle(r);
        prefs[KEY_LISTS_TO_REVIEW] = candidates
            .take(r.nextInt(candidates.length + 1))
            .toList();
      }

      final shares = <String>[];
      void share(String id, String meta, {List<String>? payload}) {
        shares.add(id);
        prefs[sharedMetaStorageKey(id)] = meta;
        if (payload != null) prefs[sharedPayloadStorageKey(id)] = payload;
      }

      if (r.nextBool()) {
        share(
          'ownfav000001',
          _meta(
            'ownfav000001',
            ListRole.owner,
            source: _legacy,
            name: 'Tiny Tunks',
            pending: [if (r.nextBool()) _pendingAdd('eel')],
          ),
        );
      }
      if (others.isNotEmpty && r.nextBool()) {
        share(
          'ownoth000001',
          _meta('ownoth000001', ListRole.owner, source: others.first),
        );
      }
      if (r.nextInt(4) == 0) {
        // Its source list is gone; sharing drops it, as it always has.
        share(
          'ownlost00001',
          _meta('ownlost00001', ListRole.owner, source: 'Deleted_words'),
        );
      }
      if (r.nextBool()) {
        share(
          'editor000001',
          _meta('editor000001', ListRole.editor),
          payload: [_v3('dog')],
        );
      }
      if (r.nextBool()) {
        share(
          'subscr000001',
          _meta('subscr000001', ListRole.subscriber),
          payload: [_v3('cherry')],
        );
      }
      if (shares.isNotEmpty) prefs[KEY_SHARED_LIST_IDS] = shares..shuffle(r);

      if (r.nextBool()) prefs['theme_variant'] = 'classic';
      if (r.nextBool()) prefs['stored_reviews'] = ['r1', 'r2'];
      if (r.nextInt(5) == 0) {
        // Debris under a key the move might want.
        prefs['Favourites_words'] = [_v3('dog')];
      }
      return prefs;
    }

    final locales = [LOCALE_ENGLISH, LOCALE_SINHALA, LOCALE_TAMIL];

    test('is carried over whole (3000 generated installs)', () async {
      for (var seed = 0; seed < 3000; seed++) {
        final r = Random(seed);
        final install = randomInstall(r);
        final locale = locales[r.nextInt(locales.length)];
        try {
          await _expectCarriedOver(install, locale: locale);
        } catch (_) {
          // ignore: avoid_print
          print('seed $seed, $locale: $install');
          rethrow;
        }
      }
    });

    test(
      'recovers from a crash at any point (600 generated installs)',
      () async {
        for (var seed = 10000; seed < 10600; seed++) {
          final r = Random(seed);
          final install = randomInstall(r);
          final locale = locales[r.nextInt(locales.length)];
          try {
            await _expectEveryCrashPointRecovers(install, locale: locale);
          } catch (_) {
            // ignore: avoid_print
            print('seed $seed, $locale: $install');
            rethrow;
          }
        }
      },
    );
  });
}
