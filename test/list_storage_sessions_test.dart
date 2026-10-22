import 'dart:convert';
import 'dart:math';

import 'package:dictionarylib/common.dart';
import 'package:dictionarylib/entry_list.dart';
import 'package:dictionarylib/entry_loader.dart';
import 'package:dictionarylib/entry_types.dart';
import 'package:dictionarylib/flashcards_logic.dart';
import 'package:dictionarylib/globals.dart';
import 'package:dictionarylib/list_storage.dart';
import 'package:dictionarylib/lists_service.dart';
import 'package:dictionarylib/page_search.dart' show getEntryTypes;
import 'package:dictionarylib/saved_video.dart';
import 'package:dictionarylib/sharing/sharing.dart';
import 'package:dictionarylib/sharing/synced_entry_list.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '_helpers.dart';
import '_recording_prefs.dart';

/// What a user's lists go through over a session, beyond the first launch
/// after the update: lists made, renamed, deleted and reordered, signs
/// saved, the revision selection changed, the dictionary data refreshed
/// underneath — and the app dying at any point along the way. These came
/// out of an adversarial review of the default-list migration; the cases
/// in the first groups were bugs it found.

SavedVideo _video(String entry) =>
    SavedVideo(entryKey: entry, mediaPath: videoFor(entry));

String _v3(String entry) => _video(entry).toStorage();

String _keyFor(String name) => '${name}_words'.replaceAll(' ', '_');

void _boot() {
  userEntryListManager = UserEntryListManager.fromStartup();
}

List<Object> _lists() => [
  for (final list in userEntryListManager.getEntryLists().values)
    [
      list.key,
      [for (final v in list.savedVideos) v.toStorage()],
    ],
];

String _ownerMeta(String id, String source) => jsonEncode(
  SyncedListMeta(
    listId: id,
    displayName: 'Tiny Tunks',
    role: ListRole.owner,
    lastKnownSeq: 4,
    etag: null,
    lastSyncedAt: 1700000000,
    serverUpdatedAt: 1700000001,
    orphaned: false,
    sourceLocalKey: source,
  ).toJson(),
);

class _Loader extends EntryLoader {
  @override
  Set<Entry> loadEntriesInner(String data) => {};

  @override
  Future<NewData?> downloadNewData(
    int currentVersion,
    bool forceDownload, {
    Duration requestTimeout = kDataFetchTimeout,
  }) async => null;
}

/// What a dictionary data refresh does once the new data is in hand.
void _refreshDictionary() {
  _Loader().setEntriesGlobal({...entriesGlobal});
}

Map<String, Object> _settled() => {
  KEY_ENTRY_LIST_KEYS: ['Favourites_words', 'Zoo_words'],
  KEY_DEFAULT_LIST_KEY: 'Favourites_words',
  'Favourites_words': [_v3('apple')],
  listSchemaVersionKey('Favourites_words'): 3,
  'Zoo_words': [_v3('dog')],
  listSchemaVersionKey('Zoo_words'): 3,
};

void main() {
  setUp(() {
    installFakeSecureStorage();
    seedDictionary([
      'apple',
      'banana',
      'cherry',
      'dog',
      'eel',
      for (var i = 0; i < 200; i++) 'w$i',
    ]);
    startingLocale = LOCALE_ENGLISH;
    sharing = Sharing.disabled();
  });

  tearDown(() {
    startingLocale = LOCALE_ENGLISH;
    sharing = Sharing.disabled();
  });

  group('a stale key in the revision selection', () {
    test('renaming a list onto the name of a deleted, once-chosen list does '
        'not add it to the revision selection', () async {
      // "Animals" was chosen for revision, then deleted. Deleting never
      // cleaned the selection, so its key is still in there.
      await installPrefs({
        KEY_ENTRY_LIST_KEYS: ['Favourites_words', 'Zoo_words'],
        KEY_DEFAULT_LIST_KEY: 'Favourites_words',
        'Favourites_words': [_v3('apple')],
        listSchemaVersionKey('Favourites_words'): 3,
        'Zoo_words': [_v3('dog')],
        listSchemaVersionKey('Zoo_words'): 3,
        KEY_LISTS_TO_REVIEW: ['Favourites_words', 'Animals_words'],
      });
      _boot();
      // The user sees only Favourites chosen. Zoo is not.
      expect(getEntryListsToReviseKeys(), [
        'Favourites_words',
      ], reason: 'before the rename');

      await userEntryListManager.renameEntryList('Zoo_words', 'Animals_words');

      expect(getEntryListsToReviseKeys(), [
        'Favourites_words',
      ], reason: 'the renamed list was never chosen for revision');
    });

    test('the migration does not add the built-in list to a selection the '
        'user left it out of', () async {
      // A Sinhala user once had their own list called ප්‍රියතම (only the
      // English word was reserved), chose it for revision and deleted it.
      // Favourites itself is NOT chosen.
      final name = 'ප්‍රියතම';
      startingLocale = LOCALE_SINHALA;
      await installPrefs({
        KEY_ENTRY_LIST_KEYS: [legacyFavouritesListKey, 'Animals_words'],
        legacyFavouritesListKey: [_v3('apple')],
        listSchemaVersionKey(legacyFavouritesListKey): 3,
        'Animals_words': [_v3('dog')],
        listSchemaVersionKey('Animals_words'): 3,
        KEY_LISTS_TO_REVIEW: ['Animals_words', _keyFor(name)],
      });
      _boot();
      expect(userEntryListManager.defaultListKey, _keyFor(name));
      expect(getEntryListsToReviseKeys(), ['Animals_words']);
    });

    test('deleting a list takes it out of the selection', () async {
      await installPrefs(
        _settled()..[KEY_LISTS_TO_REVIEW] = ['Zoo_words', 'Favourites_words'],
      );
      _boot();
      await userEntryListManager.deleteEntryList('Zoo_words');
      expect(sharedPreferences.getStringList(KEY_LISTS_TO_REVIEW), [
        'Favourites_words',
      ]);
    });

    test('deleting a list that was not chosen leaves the selection alone, '
        'including when none was ever made', () async {
      await installPrefs(_settled());
      _boot();
      await userEntryListManager.deleteEntryList('Zoo_words');
      expect(sharedPreferences.containsKey(KEY_LISTS_TO_REVIEW), isFalse);
    });

    test('a new list starts out not chosen, even with the name of a list '
        'that was chosen and then deleted on an older version', () async {
      await installPrefs(
        _settled()
          ..[KEY_LISTS_TO_REVIEW] = ['Favourites_words', 'Animals_words'],
      );
      _boot();
      await userEntryListManager.createEntryList('Animals_words');
      expect(getEntryListsToReviseKeys(), ['Favourites_words']);
      expect(sharedPreferences.getStringList(KEY_LISTS_TO_REVIEW), [
        'Favourites_words',
      ]);
    });
  });

  group('a list name whose key one of the app\'s settings already uses', () {
    // "search for" becomes the key `search_for_words`, which is where the
    // search-direction switch is kept.
    Map<String, Object> install() => _settled()..[KEY_SEARCH_FOR_WORDS] = true;

    test(
      'is refused when creating a list, and the setting is untouched',
      () async {
        await installPrefs(install());
        _boot();
        await expectLater(
          userEntryListManager.createEntryList(
            EntryList.getKeyFromName('search for'),
          ),
          throwsA(
            isA<EntryListNameException>().having(
              (e) => e.kind,
              'kind',
              EntryListNameError.reserved,
            ),
          ),
        );
        expect(prefsSnapshot(), install());
        expect(userEntryListManager.getEntryLists().keys, [
          'Favourites_words',
          'Zoo_words',
        ]);
      },
    );

    test('is refused when renaming a list, and nothing changes', () async {
      await installPrefs(install());
      _boot();
      await expectLater(
        userEntryListManager.renameEntryList(
          'Zoo_words',
          EntryList.getKeyFromName('search for'),
        ),
        throwsA(isA<EntryListNameException>()),
      );
      expect(prefsSnapshot(), install());
      expect(userEntryListManager.getEntryLists().keys, [
        'Favourites_words',
        'Zoo_words',
      ]);
      expect(
        userEntryListManager.getEntryLists()['Zoo_words']!.key,
        'Zoo_words',
      );
    });

    // The switch is only written when someone changes the search filter:
    // never in Auslan, which has no filter button, and in SLSL only for
    // those who have used it. For everyone else nothing is stored under the
    // key yet, and the name has to be refused all the same, or the list is
    // stored where the switch is read from and every search throws reading
    // a list as a bool.
    test('is refused when creating a list even if the setting has never '
        'been written, and search still works', () async {
      await installPrefs(_settled());
      _boot();
      await expectLater(
        userEntryListManager.createEntryList(
          EntryList.getKeyFromName('search for', rejectUnderscores: true),
        ),
        throwsA(
          isA<EntryListNameException>().having(
            (e) => e.kind,
            'kind',
            EntryListNameError.reserved,
          ),
        ),
      );
      expect(prefsSnapshot(), _settled());
      // What every keystroke in the search box calls.
      expect(getEntryTypes, returnsNormally);
    });

    test('is refused when renaming a list even if the setting has never '
        'been written, and search still works', () async {
      await installPrefs(_settled());
      _boot();
      await expectLater(
        userEntryListManager.renameEntryList(
          'Zoo_words',
          EntryList.getKeyFromName('search for', rejectUnderscores: true),
        ),
        throwsA(
          isA<EntryListNameException>().having(
            (e) => e.kind,
            'kind',
            EntryListNameError.reserved,
          ),
        ),
      );
      expect(prefsSnapshot(), _settled());
      expect(getEntryTypes, returnsNormally);
    });
  });

  group('a dictionary data refresh mid-session', () {
    // The loader used to rebuild the user's lists every time new data
    // arrived. A share made from the device kept hold of the list object it
    // had found at startup, so from then on there were two copies of the
    // list: one the share edited, one everything else read.
    Future<void> launchWithSharedDefaultList() async {
      await installPrefs({
        legacyFavouritesListKey: [_v3('apple')],
        listSchemaVersionKey(legacyFavouritesListKey): 3,
        KEY_SHARED_LIST_IDS: ['own000000001'],
        sharedMetaStorageKey('own000000001'): _ownerMeta(
          'own000000001',
          legacyFavouritesListKey,
        ),
      });
      _refreshDictionary(); // the first load: builds the lists
      installFakeSharing((req) async {
        if (req.method == 'DELETE') return http.Response('', 204);
        return http.Response('', 500);
      });
    }

    const key = 'Favourites_words';

    test('leaves the lists that shares are holding in place', () async {
      await launchWithSharedDefaultList();
      final manager = userEntryListManager;
      final list = manager.getEntryLists()[key]!;

      _refreshDictionary();

      expect(userEntryListManager, same(manager));
      expect(userEntryListManager.getEntryLists()[key], same(list));
      expect(
        identical(
          sharing.lists.ownerForSourceKey(key)!.savedVideos,
          list.savedVideos,
        ),
        isTrue,
      );
    });

    test(
      'a sign saved to a shared list afterwards shows in the list',
      () async {
        await launchWithSharedDefaultList();
        _refreshDictionary();

        await sharing.lists.ownerForSourceKey(key)!.addVideo(_video('cherry'));

        expect(
          userEntryListManager.getEntryLists()[key]!.savedVideos.map(
            (v) => v.entryKey,
          ),
          ['apple', 'cherry'],
          reason: 'the list the Lists page and revision read from',
        );
      },
    );

    test('and is still there after unsharing, saving again and '
        'restarting', () async {
      await launchWithSharedDefaultList();
      _refreshDictionary();

      final share = sharing.lists.ownerForSourceKey(key)!;
      await share.addVideo(_video('cherry'));
      await listsService.unshareList(share);
      await userEntryListManager.getEntryLists()[key]!.addVideo(_video('dog'));

      await installPrefs(prefsSnapshot());
      sharing = Sharing.disabled();
      _boot();
      expect(
        userEntryListManager.getEntryLists()[key]!.savedVideos.map(
          (v) => v.entryKey,
        ),
        ['apple', 'cherry', 'dog'],
      );
    });

    test('still loads the lists when it is the first load of a cold '
        'start', () async {
      // No cached dictionary: the first data to arrive is a download, and
      // sharing has not started yet.
      await installPrefs({
        legacyFavouritesListKey: [_v3('apple')],
      });
      _refreshDictionary();
      expect(userEntryListManager.getEntryLists().keys, [key]);
    });
  });

  test('a migration cut short, then relaunched in another language, keeps '
      'every video, the share and the selection', () async {
    final initial = <String, Object>{
      KEY_ENTRY_LIST_KEYS: [legacyFavouritesListKey, 'Animals_words'],
      legacyFavouritesListKey: ['apple', 'banana'], // oldest format
      'Animals_words': [_v3('dog')],
      listSchemaVersionKey('Animals_words'): 3,
      KEY_LISTS_TO_REVIEW: [legacyFavouritesListKey],
      KEY_SHARED_LIST_IDS: ['own000000001'],
      sharedMetaStorageKey('own000000001'): _ownerMeta(
        'own000000001',
        legacyFavouritesListKey,
      ),
    };
    startingLocale = LOCALE_SINHALA;
    final store = await installPrefs(initial);
    _boot();
    installFakeSharing((_) async => http.Response('', 500));
    final writes = List.of(store.writes);

    for (var n = 0; n <= writes.length; n++) {
      startingLocale = LOCALE_TAMIL;
      await installPrefs(replayWrites(initial, writes, n));
      _boot();
      installFakeSharing((_) async => http.Response('', 500));
      final why = 'died $n writes into $writes';
      final key = userEntryListManager.defaultListKey;
      expect(
        key,
        anyOf(_keyFor('ප්‍රියතම'), _keyFor('பிடித்தவை')),
        reason: why,
      );
      expect(_lists(), [
        [
          key,
          [_v3('apple'), _v3('banana')],
        ],
        [
          'Animals_words',
          [_v3('dog')],
        ],
      ], reason: why);
      expect(loadListsToReview(), [key], reason: why);
      expect(sharing.lists.get('own000000001')?.key, key, reason: why);
      expect(
        sharedPreferences.containsKey(legacyFavouritesListKey),
        isFalse,
        reason: why,
      );
    }
  });

  group('in-session edits, cut short anywhere', () {
    // Every list carries one "token" video that is never removed, so a list
    // can be followed through renames. Names are never reused.
    test('never lose a list, a video, the order, the default or the '
        'selection (300 generated sessions)', () async {
      for (var seed = 0; seed < 300; seed++) {
        final r = Random(seed);
        var nextWord = 0;
        var nextName = 0;
        String word() => 'w${nextWord++}';
        String name() => 'L${nextName++}';

        // Start from a legacy install so the session includes the migration.
        final initial = <String, Object>{};
        final others = <String>[];
        final tokens = <String, String>{}; // key -> token
        final legacyToken = word();
        initial[legacyFavouritesListKey] = [_v3(legacyToken)];
        initial[listSchemaVersionKey(legacyFavouritesListKey)] = 3;
        for (var i = r.nextInt(3); i > 0; i--) {
          final k = _keyFor(name());
          others.add(k);
          tokens[k] = word();
          initial[k] = [_v3(tokens[k]!)];
          initial[listSchemaVersionKey(k)] = 3;
        }
        if (others.isNotEmpty || r.nextBool()) {
          initial[KEY_ENTRY_LIST_KEYS] = [legacyFavouritesListKey, ...others];
        }
        if (r.nextBool()) {
          initial[KEY_LISTS_TO_REVIEW] = [
            if (r.nextBool()) legacyFavouritesListKey,
            for (final k in others)
              if (r.nextBool()) k,
          ];
        }

        // What the user sees, in terms that survive a key change.
        ({
          List<String> order,
          Map<String, Set<String>> videos,
          String defaultToken,
          Set<String> chosen,
        })
        view(Map<String, String> tokenByKey) {
          final lists = userEntryListManager.getEntryLists();
          return (
            order: [for (final k in lists.keys) tokenByKey[k] ?? '?$k'],
            videos: {
              for (final e in lists.entries)
                tokenByKey[e.key] ?? '?${e.key}': {
                  for (final v in e.value.savedVideos) v.entryKey,
                },
            },
            defaultToken:
                tokenByKey[userEntryListManager.defaultListKey] ?? '?default',
            chosen: {
              for (final k in loadListsToReview())
                if (lists.containsKey(k)) tokenByKey[k] ?? '?$k',
            },
          );
        }

        final store = await installPrefs(initial);
        _boot();
        tokens[userEntryListManager.defaultListKey] = legacyToken;

        // boundaries[i] = number of writes after op i-1; views[i] likewise.
        final boundaries = <int>[0, store.writes.length];
        final tokenMaps = <Map<String, String>>[
          {...tokens}
            ..remove(userEntryListManager.defaultListKey)
            ..[legacyFavouritesListKey] = legacyToken,
          {...tokens},
        ];
        final views = [null, view(tokens)];
        final ops = <String>['migrate'];

        for (var step = 0; step < 6; step++) {
          final lists = userEntryListManager.getEntryLists();
          final keys = lists.keys.toList();
          final pick = keys[r.nextInt(keys.length)];
          switch (r.nextInt(6)) {
            case 0:
              final k = _keyFor(name());
              await userEntryListManager.createEntryList(k);
              tokens[k] = word();
              await lists[k]!.addVideo(_video(tokens[k]!));
              ops.add('create $k');
            case 1:
              if (pick == userEntryListManager.defaultListKey) {
                ops.add('noop');
                break;
              }
              await userEntryListManager.deleteEntryList(pick);
              tokens.remove(pick);
              ops.add('delete $pick');
            case 2:
              final k = _keyFor(name());
              await userEntryListManager.renameEntryList(pick, k);
              tokens[k] = tokens.remove(pick)!;
              ops.add('rename $pick -> $k');
            case 3:
              final a = r.nextInt(keys.length);
              final b = r.nextInt(keys.length);
              userEntryListManager.reorder(a, b);
              await userEntryListManager.writeEntryListKeys();
              ops.add('reorder $a $b');
            case 4:
              await lists[pick]!.addVideo(_video(word()));
              ops.add('add to $pick');
            default:
              final s = loadListsToReview().toSet();
              if (!s.add(pick)) s.remove(pick);
              await sharedPreferences.setStringList(
                KEY_LISTS_TO_REVIEW,
                s.toList(),
              );
              ops.add('toggle $pick');
          }
          boundaries.add(store.writes.length);
          tokenMaps.add({...tokens});
          views.add(view(tokens));
        }
        final writes = List.of(store.writes);

        for (var n = boundaries[1]; n <= writes.length; n++) {
          // Which op was n in the middle of (or just after)?
          var op = 1;
          while (boundaries[op] < n) {
            op++;
          }
          final before = views[n == boundaries[op] ? op : op - 1]!;
          final after = views[op]!;
          final why =
              'seed $seed, died $n writes in (during "${ops[op - 1]}" of '
              '$ops)\nwrites: ${writes.sublist(boundaries[op - 1], n)}'
              '\nstate: ${replayWrites(initial, writes, n)}';

          await installPrefs(replayWrites(initial, writes, n));
          _boot();
          // A token may be under its old or its new key.
          final tokenByKey = {...tokenMaps[op - 1], ...tokenMaps[op]};
          final got = view(tokenByKey);

          // Lists that exist both before and after the op are all there,
          // in an order the user had, holding at least what they held
          // before and after.
          final stable = before.order.toSet().intersection(after.order.toSet());
          final gotStable = got.order.where(stable.contains).toList();
          expect(
            gotStable,
            anyOf(
              equals(before.order.where(stable.contains).toList()),
              equals(after.order.where(stable.contains).toList()),
            ),
            reason: why,
          );
          for (final t in stable) {
            expect(
              got.videos[t],
              anyOf(equals(before.videos[t]), equals(after.videos[t])),
              reason: '$why\nlist $t',
            );
          }
          expect(got.defaultToken, before.defaultToken, reason: why);
          expect(
            got.chosen.intersection(stable),
            anyOf(
              equals(before.chosen.intersection(stable)),
              equals(after.chosen.intersection(stable)),
            ),
            reason: why,
          );
          // The pointer names a stored list.
          expect(
            sharedPreferences.getStringList(KEY_ENTRY_LIST_KEYS),
            contains(sharedPreferences.getString(KEY_DEFAULT_LIST_KEY)),
            reason: why,
          );
        }
      }
    });
  });
}

/// The keys of the lists revision would draw from right now: the stored
/// selection, limited to lists that exist.
List<String> getEntryListsToReviseKeys() {
  final lists = userEntryListManager.getEntryLists();
  return [
    for (final k in loadListsToReview())
      if (lists.containsKey(k)) k,
  ];
}
