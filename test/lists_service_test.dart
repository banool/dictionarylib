import 'dart:collection';
import 'dart:convert';

import 'package:dictionarylib/entry_list.dart';
import 'package:dictionarylib/globals.dart';
import 'package:dictionarylib/lists_service.dart';
import 'package:dictionarylib/saved_video.dart';
import 'package:dictionarylib/sharing/sharing.dart';
import 'package:dictionarylib/sharing/synced_entry_list.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '_helpers.dart';

void main() {
  setUp(() async {
    installFakeSecureStorage();
    SharedPreferences.setMockInitialValues({});
    sharedPreferences = await SharedPreferences.getInstance();
    seedDictionary(['apple', 'banana', 'cherry']);
    userEntryListManager = UserEntryListManager.fromStartup();
    sharing = Sharing.disabled();
  });

  group('myLists', () {
    test('returns local user lists only (synced wrappers in their own tabs)',
        () async {
      installFakeSharing((req) async {
        if (req.method == 'GET' && req.url.path.endsWith('/sub010000000')) {
          return http.Response(
            jsonEncode({
              'schemaVersion': 3,
              'listId': 'sub010000000',
              'displayName': 'Sub',
              'appId': 'auslan',
              'entries': const <Map<String, String>>[],
              'lastSeq': 1,
              'createdAt': 1,
              'updatedAt': 1,
            }),
            200,
            headers: {'etag': '"e"'},
          );
        }
        return http.Response('', 404);
      });

      await userEntryListManager.createEntryList('cats_words');
      await sharing.engine.subscribe('sub010000000');

      final names = listsService.myLists.map((l) => l.getName()).toList();
      expect(names, ['Favourites', 'cats']);
    });
  });

  group('writableLists', () {
    SyncedListMeta meta(String id, String name, ListRole role,
            {bool orphaned = false}) =>
        SyncedListMeta(
          listId: id,
          displayName: name,
          role: role,
          lastKnownSeq: 1,
          etag: null,
          lastSyncedAt: 1,
          serverUpdatedAt: 1,
          orphaned: orphaned,
        );

    test('matches the local user lists when sharing is disabled', () async {
      // sharing defaults to disabled in setUp.
      await userEntryListManager.createEntryList('cats_words');
      expect(listsService.writableLists.map((l) => l.key).toList(),
          listsService.myLists.map((l) => l.key).toList());
    });

    test(
        'is the local user lists plus editor lists, excluding subscriber + '
        'orphaned lists', () async {
      // This is the divergence behind the "saved to N lists" bug: an editor
      // list is a save target (the sheet shows it) but the old myLists-only
      // count missed it. writableLists is the single source both now use.
      installFakeSharing((_) async => http.Response('', 404));
      await userEntryListManager.createEntryList('cats_words');

      await sharing.lists.insert(SyncedEntryList.editor(
        meta: meta('editor010000', 'Editing', ListRole.editor),
        savedVideos: LinkedHashSet<SavedVideo>(),
      ));
      // A read-only subscription and an orphaned editor list must NOT be
      // offered as save targets.
      await sharing.lists.insert(SyncedEntryList.subscriber(
        meta: meta('sub010000000', 'Following', ListRole.subscriber),
        savedVideos: LinkedHashSet<SavedVideo>(),
      ));
      await sharing.lists.insert(SyncedEntryList.editor(
        meta: meta('editor020000', 'Gone', ListRole.editor, orphaned: true),
        savedVideos: LinkedHashSet<SavedVideo>(),
      ));

      final names = listsService.writableLists.map((l) => l.getName()).toList();
      expect(names, ['Favourites', 'cats', 'Editing'],
          reason: 'writable = local user lists + non-orphaned editor lists');
    });

    test('routes an owner-shared local list through its wrapper', () async {
      installFakeSharing((req) async {
        if (req.method == 'POST' && req.url.path == '/v1/lists') {
          return stubCreateResponse(req);
        }
        return http.Response('', 404);
      });
      await userEntryListManager.createEntryList('cats_words');
      final source = userEntryListManager.getEntryLists()['cats_words']!;
      await listsService.shareList(
        sourceList: source,
        displayName: 'Cats',
        sessionToken: 'fake-session-jwt',
      );
      // The 'cats' row is the owner wrapper (so a toggle enqueues a sync op),
      // not the bare local list.
      final cats =
          listsService.writableLists.firstWhere((l) => l.key == 'cats_words');
      expect(cats, isA<SyncedEntryList>());
      expect((cats as SyncedEntryList).meta.role, ListRole.owner);
    });
  });

  group('shareList', () {
    test('creates an owner wrapper; edits through the wrapper enqueue ops',
        () async {
      final requests = installFakeSharing((req) async {
        if (req.method == 'POST' && req.url.path == '/v1/lists') {
          return stubCreateResponse(req);
        }
        if (req.method == 'POST' && req.url.path.endsWith('/sync')) {
          return stubSyncApplyAll(req);
        }
        return http.Response('', 404);
      });

      await userEntryListManager.createEntryList('cats_words');
      final source = userEntryListManager.getEntryLists()['cats_words']!;
      final synced = await listsService.shareList(
        sourceList: source,
        displayName: 'Cats',
        sessionToken: 'fake-session-jwt',
      );
      expect(synced.meta.role, ListRole.owner);
      // The "favourites star" / "My Lists tap" path both end up holding
      // the wrapper (via [ListsService.favouritesList] or the overview's
      // wrapper-routing). Edits through the wrapper enqueue a sync op.
      final v = SavedVideo(entryKey: 'apple', videoUrl: videoFor('apple'));
      await synced.addVideo(v);
      expect(synced.meta.pendingOps, hasLength(1));
      expect(synced.meta.pendingOps.single.type, 'addEntry');
      expect(synced.meta.pendingOps.single.args['entry'], 'apple');
      expect(synced.meta.pendingOps.single.args['video'], videoFor('apple'));
      // The wrapper and the source share their savedVideos set by
      // reference, so the local view sees the add too.
      expect(source.savedVideos.map((sv) => sv.entryKey), contains('apple'));
      // Just one create request so far — the enqueue debounces.
      expect(requests.where((r) => r.method == 'POST').length, 1);
    });

    test('mutating the source directly trips the owner-mode tripwire',
        () async {
      // The wrapper's [addEntry] override is the only enqueue path;
      // direct mutation on the underlying source list bypasses it and
      // would let the entries set drift out of sync with the server.
      // [EntryList._assertNotOwnerShared] is a debug-mode tripwire
      // designed to catch any new code path that re-introduces that
      // bypass — a regression here would silently corrupt the synced
      // mirror in production, so we want it to fail loudly during
      // development.
      installFakeSharing((req) async {
        if (req.method == 'POST' && req.url.path == '/v1/lists') {
          return stubCreateResponse(req);
        }
        return http.Response('', 404);
      });
      await userEntryListManager.createEntryList('cats_words');
      final source = userEntryListManager.getEntryLists()['cats_words']!;
      final synced = await listsService.shareList(
        sourceList: source,
        displayName: 'Cats',
        sessionToken: 'fake-session-jwt',
      );
      final v = SavedVideo(entryKey: 'apple', videoUrl: videoFor('apple'));
      expect(() async => await source.addVideo(v),
          throwsA(isA<AssertionError>()));
      // No op enqueued either way — the assertion fires before the
      // source's `entries.add`.
      expect(synced.meta.pendingOps, isEmpty);
    });
  });

  group('favouritesList', () {
    test('returns the local list when favourites is not shared', () async {
      installFakeSharing((_) async => http.Response('', 404));
      final fav = listsService.favouritesList;
      expect(fav, isNot(isA<SyncedEntryList>()));
      expect(fav.key, 'favourites_words');
    });

    test('returns the wrapper when favourites is owner-shared', () async {
      installFakeSharing((req) async {
        if (req.method == 'POST' && req.url.path == '/v1/lists') {
          return stubCreateResponse(req);
        }
        return http.Response('', 404);
      });
      final source = userEntryListManager.getEntryLists()['favourites_words']!;
      await listsService.shareList(
        sourceList: source,
        displayName: 'My Favourites',
        sessionToken: 'fake-session-jwt',
      );
      final fav = listsService.favouritesList;
      expect(fav, isA<SyncedEntryList>());
      expect((fav as SyncedEntryList).meta.role, ListRole.owner);
    });
  });

  group('unshareList', () {
    test('deletes server-side and removes the local owner wrapper', () async {
      final requests = installFakeSharing((req) async {
        if (req.method == 'POST' && req.url.path == '/v1/lists') {
          return stubCreateResponse(req);
        }
        if (req.method == 'DELETE') return http.Response('', 204);
        return http.Response('', 404);
      });

      await userEntryListManager.createEntryList('cats_words');
      final source = userEntryListManager.getEntryLists()['cats_words']!;
      final synced = await listsService.shareList(
        sourceList: source,
        displayName: 'Cats',
        sessionToken: 'fake-session-jwt',
      );
      await listsService.unshareList(synced);
      expect(sharing.lists.get(synced.listId), isNull);
      expect(requests.last.method, 'DELETE');
      // The local source list is untouched (still in userEntryListManager).
      expect(userEntryListManager.getEntryLists().containsKey('cats_words'),
          isTrue);
    });
  });

  group('importOwnedLists', () {
    test('imports owned + editor lists with the correct roles', () async {
      installFakeSharing((req) async {
        if (req.url.path == '/v1/my-lists') {
          return http.Response(
              jsonEncode({
                'ownedListIds': ['ownedlist001'],
                'editorListIds': ['editorlist01'],
              }),
              200);
        }
        if (req.url.path.endsWith('/state')) {
          if (req.url.path.contains('ownedlist001')) {
            return http.Response(
                jsonEncode(snapshotJson(
                    listId: 'ownedlist001',
                    displayName: 'Mine',
                    entries: ['apple'],
                    lastSeq: 3)),
                200);
          }
          return http.Response(
              jsonEncode(snapshotJson(
                  listId: 'editorlist01',
                  displayName: 'Editing',
                  entries: ['banana'],
                  lastSeq: 4,
                  members: {
                    'owner': {'userId': 'apple:other', 'displayName': 'Other'},
                    'editors': [
                      {
                        'userId': 'apple:test-user',
                        'displayName': 'Test User',
                        'addedAt': 1,
                        'addedBy': 'apple:other',
                      }
                    ],
                  })),
              200);
        }
        return http.Response('', 404);
      });

      final result = await listsService.importOwnedLists();
      expect(result.imported, 2);
      expect(result.skipped, 0);
      expect(result.total, 2);

      final owned = sharing.lists.get('ownedlist001');
      expect(owned, isNotNull);
      expect(owned!.meta.role, ListRole.owner);
      expect(owned.savedVideos.map((sv) => sv.entryKey), ['apple']);

      final edited = sharing.lists.get('editorlist01');
      expect(edited, isNotNull);
      expect(edited!.meta.role, ListRole.editor);
      expect(edited.savedVideos.map((sv) => sv.entryKey), ['banana']);
    });

    test('skips lists already on the device', () async {
      installFakeSharing((req) async {
        if (req.url.path == '/v1/my-lists') {
          return http.Response(
              jsonEncode({
                'ownedListIds': ['ownedlist001'],
                'editorListIds': <String>[],
              }),
              200);
        }
        return http.Response('', 404);
      });

      // Pre-install the list. importOwnedLists should skip it.
      await userEntryListManager.createEntryList('mine_words');
      final source = userEntryListManager.getEntryLists()['mine_words']!;
      await sharing.lists.insert(SyncedEntryList.owner(
        meta: SyncedListMeta(
          listId: 'ownedlist001',
          displayName: 'Mine',
          role: ListRole.owner,
          lastKnownSeq: 1,
          etag: null,
          lastSyncedAt: 1,
          serverUpdatedAt: 1,
          orphaned: false,
          sourceLocalKey: 'mine_words',
        ),
        source: source,
      ));

      final result = await listsService.importOwnedLists();
      expect(result.imported, 0);
      expect(result.skipped, 1);
    });
  });

  group('importOwnedLists — local-name collision', () {
    /// Multi-device convergence variant: a fresh device imports an
    /// owned list whose displayName matches a local list the user
    /// already had. The local user list must NOT be overwritten —
    /// allocateLocalKey should suffix the imported list to "MyList 2"
    /// (key "MyList_2_words") so both coexist.
    test('imported owned list with a name-collision gets a suffixed local key',
        () async {
      installFakeSharing((req) async {
        if (req.url.path == '/v1/my-lists') {
          return http.Response(
              jsonEncode({
                'ownedListIds': ['ownedlist001'],
                'editorListIds': <String>[],
              }),
              200);
        }
        if (req.url.path.endsWith('/state') &&
            req.url.path.contains('ownedlist001')) {
          return http.Response(
              jsonEncode(snapshotJson(
                  listId: 'ownedlist001',
                  displayName: 'MyList',
                  entries: ['apple'],
                  lastSeq: 3)),
              200);
        }
        return http.Response('', 404);
      });

      // Pre-existing local list with the same display name. Use the
      // EntryList key shape the import path would produce (`MyList`
      // → `MyList_words`) so the collision actually triggers.
      await userEntryListManager.createEntryList('MyList_words');
      final preExisting =
          userEntryListManager.getEntryLists()['MyList_words']!;
      final cherryVideo =
          SavedVideo(entryKey: 'cherry', videoUrl: videoFor('cherry'));
      await preExisting.addVideo(cherryVideo);
      final preExistingVideos = preExisting.savedVideos.toSet();

      final result = await listsService.importOwnedLists();
      expect(result.imported, 1);

      // The pre-existing local list is untouched.
      expect(preExisting.savedVideos.toSet(), preExistingVideos,
          reason: 'import must not overwrite an existing local list');

      // The imported owner list got a new local key — "MyList 2" →
      // "MyList_2_words" — that hosts the server's entries.
      final suffixed = userEntryListManager.getEntryLists()['MyList_2_words'];
      expect(suffixed, isNotNull,
          reason: 'allocateLocalKey should suffix on name collision');
      expect(suffixed!.savedVideos.map((sv) => sv.entryKey), contains('apple'));

      // Both local lists still exist in the manager.
      expect(userEntryListManager.getEntryLists().keys,
          containsAll(['MyList_words', 'MyList_2_words']));
    });
  });

  group('SyncedEntryListManager.fromStartup — owner with missing source', () {
    /// Regression: if a user deletes the local list backing an owner-mode
    /// share (now blocked at the UI but the manager still has to be
    /// resilient to legacy data and to the user manipulating prefs out-
    /// of-band), the manager's startup load must drop the dangling
    /// index entry AND clean up the orphaned meta/payload keys instead
    /// of leaving them in shared prefs forever.
    test('drops the dangling entry and cleans up shared-prefs', () async {
      installFakeSharing((_) async => http.Response('', 404));

      // Build an owner wrapper whose source is a real local list, then
      // persist it so the index + meta land in shared prefs.
      await userEntryListManager.createEntryList('cats_words');
      final source = userEntryListManager.getEntryLists()['cats_words']!;
      await sharing.lists.insert(SyncedEntryList.owner(
        meta: SyncedListMeta(
          listId: 'ownedlist001',
          displayName: 'Cats',
          role: ListRole.owner,
          lastKnownSeq: 1,
          etag: null,
          lastSyncedAt: 1,
          serverUpdatedAt: 1,
          orphaned: false,
          sourceLocalKey: 'cats_words',
        ),
        source: source,
      ));
      expect(sharedPreferences.getString('shared_ownedlist001_meta'),
          isNotNull);
      expect(sharedPreferences.getStringList(KEY_SHARED_LIST_IDS),
          contains('ownedlist001'));

      // Simulate the user deleting the local source list out from under
      // the wrapper, then a fresh app launch.
      await userEntryListManager.deleteEntryList('cats_words');
      final reloaded = SyncedEntryListManager.fromStartup();

      // Manager doesn't hold the orphaned wrapper any more.
      expect(reloaded.hasList('ownedlist001'), isFalse);
      // The index has been re-written without the dangling id, and the
      // orphaned meta + payload keys have been removed (no more leak).
      expect(sharedPreferences.getStringList(KEY_SHARED_LIST_IDS),
          isNot(contains('ownedlist001')));
      expect(sharedPreferences.getString('shared_ownedlist001_meta'), isNull);
      expect(sharedPreferences.getStringList('shared_ownedlist001_words'),
          isNull);
    });
  });

}
