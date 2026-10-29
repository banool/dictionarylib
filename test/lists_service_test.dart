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
    // installFakeSharing leaves account sync off, so these tests cover
    // sharing as it works then (a list is shared as a new list, `POST
    // /v1/lists`). With account sync on, sharing flips a linked list's
    // visibility instead; that's in sharing/account_sync_test.dart.
    seedDictionary(['apple', 'banana', 'cherry']);
    userEntryListManager = UserEntryListManager.fromStartup();
    sharing = Sharing.disabled();
  });

  group('myLists', () {
    test(
      'returns local user lists only (synced wrappers in their own tabs)',
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
      },
    );
  });

  group('writableLists', () {
    SyncedListMeta meta(
      String id,
      String name,
      ListRole role, {
      bool orphaned = false,
    }) => SyncedListMeta(
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
      expect(
        listsService.writableLists.map((l) => l.key).toList(),
        listsService.myLists.map((l) => l.key).toList(),
      );
    });

    test('is the local user lists plus editor lists, excluding subscriber + '
        'orphaned lists', () async {
      // This is the divergence behind the "saved to N lists" bug: an editor
      // list is a save target (the sheet shows it) but the old myLists-only
      // count missed it. writableLists is the single source both now use.
      installFakeSharing((_) async => http.Response('', 404));
      await userEntryListManager.createEntryList('cats_words');

      await sharing.lists.insert(
        SyncedEntryList.editor(
          meta: meta('editor010000', 'Editing', ListRole.editor),
          savedVideos: LinkedHashSet<SavedVideo>(),
        ),
      );
      // A read-only subscription and an orphaned editor list must NOT be
      // offered as save targets.
      await sharing.lists.insert(
        SyncedEntryList.subscriber(
          meta: meta('sub010000000', 'Following', ListRole.subscriber),
          savedVideos: LinkedHashSet<SavedVideo>(),
        ),
      );
      await sharing.lists.insert(
        SyncedEntryList.editor(
          meta: meta('editor020000', 'Gone', ListRole.editor, orphaned: true),
          savedVideos: LinkedHashSet<SavedVideo>(),
        ),
      );

      final names = listsService.writableLists.map((l) => l.getName()).toList();
      expect(names, [
        'Favourites',
        'cats',
        'Editing',
      ], reason: 'writable = local user lists + non-orphaned editor lists');
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
      final cats = listsService.writableLists.firstWhere(
        (l) => l.key == 'cats_words',
      );
      expect(cats, isA<SyncedEntryList>());
      expect((cats as SyncedEntryList).meta.role, ListRole.owner);
    });
  });

  group('shareList', () {
    test(
      'creates an owner wrapper; edits through the wrapper enqueue ops',
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
        final v = SavedVideo(entryKey: 'apple', mediaPath: videoFor('apple'));
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
      },
    );

    test(
      'mutating the source directly goes through its owner wrapper',
      () async {
        // The wrapper's [addEntry] override is the only enqueue path;
        // direct mutation on the underlying source list would bypass it
        // and let the entries set drift out of sync with the server. Every
        // UI path holds the wrapper, but account sync links lists in the
        // background, so a caller can be holding the plain list from
        // before: the plain list hands the mutation to the wrapper.
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
        final v = SavedVideo(entryKey: 'apple', mediaPath: videoFor('apple'));
        await source.addVideo(v);
        expect(synced.meta.pendingOps.single.type, 'addEntry');
        expect(source.savedVideos, contains(v));
      },
    );
  });

  group('renameSharedList', () {
    /// Share a fresh local list owned by the test user and return its
    /// owner wrapper. The fake server echoes the create + serves the
    /// rename PUT back as an updated snapshot.
    Future<SyncedEntryList> shareCats() async {
      await userEntryListManager.createEntryList('cats_words');
      final source = userEntryListManager.getEntryLists()['cats_words']!;
      return listsService.shareList(
        sourceList: source,
        displayName: 'Cats',
        sessionToken: 'fake-session-jwt',
      );
    }

    test(
      'owner rename takes effect at once and is queued, with no request',
      () async {
        final requests = installFakeSharing((req) async {
          if (req.method == 'POST' && req.url.path == '/v1/lists') {
            return stubCreateResponse(req);
          }
          if (req.method == 'PUT') {
            final body = jsonDecode(req.body) as Map<String, dynamic>;
            return http.Response(
              jsonEncode(
                snapshotJson(
                  listId: 'ownedlist001',
                  displayName: body['displayName'] as String,
                  entries: const <String>[],
                  lastSeq: 3,
                ),
              ),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response('', 404);
        });
        final owned = await shareCats();

        final before = requests.length;
        await listsService.renameSharedList(owned, 'Kittens');

        // Nothing waits for the network: no PUT, no request at all yet.
        expect(requests.length, before);
        expect(requests.where((r) => r.method == 'PUT'), isEmpty);
        expect(owned.meta.displayName, 'Kittens');
        expect(owned.getName(), 'Kittens');
        final op = owned.meta.pendingOps.last;
        expect(op.type, 'rename');
        expect(op.args, {'displayName': 'Kittens'});
      },
    );

    test('a non-owner (editor) rename throws and sends no PUT', () async {
      final requests = installFakeSharing((_) async => http.Response('', 404));
      await sharing.lists.insert(
        SyncedEntryList.editor(
          meta: SyncedListMeta(
            listId: 'editor010000',
            displayName: 'Editing',
            role: ListRole.editor,
            lastKnownSeq: 1,
            etag: null,
            lastSyncedAt: 1,
            serverUpdatedAt: 1,
            orphaned: false,
          ),
          savedVideos: LinkedHashSet<SavedVideo>(),
        ),
      );
      final editor = sharing.lists.get('editor010000')!;
      await expectLater(
        listsService.renameSharedList(editor, 'Nope'),
        throwsA(isA<StateError>()),
      );
      expect(requests.where((r) => r.method == 'PUT'), isEmpty);
    });

    test('a reserved name is rejected client-side before any PUT', () async {
      final requests = installFakeSharing((req) async {
        if (req.method == 'POST' && req.url.path == '/v1/lists') {
          return stubCreateResponse(req);
        }
        return http.Response('', 404);
      });
      final owned = await shareCats();
      await expectLater(
        listsService.renameSharedList(owned, 'Favourites'),
        throwsA(isA<EntryListNameException>()),
      );
      expect(requests.where((r) => r.method == 'PUT'), isEmpty);
      // The wrapper keeps its original name.
      expect(owned.meta.displayName, 'Cats');
    });
  });

  group('stopSharing', () {
    test('makes the list private and keeps it linked', () async {
      final requests = installFakeSharing((req) async {
        if (req.method == 'POST' && req.url.path == '/v1/lists') {
          return stubCreateResponse(req);
        }
        if (req.method == 'PUT' && req.url.path.endsWith('/visibility')) {
          return http.Response(
            jsonEncode({
              ...snapshotJson(listId: 'x', displayName: 'Cats'),
              'listId': req.url.pathSegments[2],
              'visibility': 'private',
            }),
            200,
          );
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
      await listsService.stopSharing(synced);
      expect(requests.last.method, 'PUT');
      expect(jsonDecode(requests.last.body), {'visibility': 'private'});
      // Never a DELETE: the list stays, on the account and here.
      expect(requests.where((r) => r.method == 'DELETE'), isEmpty);
      expect(sharing.lists.get(synced.listId), same(synced));
      expect(synced.meta.isShared, isFalse);
      expect(
        userEntryListManager.getEntryLists().containsKey('cats_words'),
        isTrue,
      );
    });
  });

  // A list has one name as far as the user is concerned: the one the Lists
  // page shows. For a list shared from this device that's the share's
  // display name, and it has to come back from the plain local list too,
  // since not every screen goes and fetches the owner wrapper first.
  group('the name of a list shared from this device', () {
    setUp(() {
      installFakeSharing((req) async {
        if (req.method == 'POST' && req.url.path == '/v1/lists') {
          return stubCreateResponse(req);
        }
        if (req.method == 'PUT' && req.url.path.endsWith('/visibility')) {
          return http.Response(
            jsonEncode({
              ...snapshotJson(listId: 'x', displayName: 'Tiny Tunks'),
              'listId': req.url.pathSegments[2],
              'visibility': 'private',
            }),
            200,
          );
        }
        return http.Response('', 404);
      });
    });

    test('is the share name, from the local list as well as the wrapper, '
        'when Favourites is shared under another name', () async {
      await userEntryListManager.createEntryList('cats_words');
      final favourites = userEntryListManager.getEntryLists()[kDefaultListKey]!;
      final owned = await listsService.shareList(
        sourceList: favourites,
        displayName: 'Tiny Tunks',
        sessionToken: 'fake-session-jwt',
      );

      expect(owned.getName(), 'Tiny Tunks');
      expect(favourites.getName(), 'Tiny Tunks');
      // The unshared list next to it keeps its own name.
      expect(listsService.myLists.map((l) => l.getName()).toList(), [
        'Tiny Tunks',
        'cats',
      ]);
    });

    test('follows a rename of the share', () async {
      await userEntryListManager.createEntryList('cats_words');
      final cats = userEntryListManager.getEntryLists()['cats_words']!;
      final owned = await listsService.shareList(
        sourceList: cats,
        displayName: 'cats',
        sessionToken: 'fake-session-jwt',
      );
      expect(cats.getName(), 'cats');

      // What a rename leaves behind once the server has confirmed it.
      owned.meta.displayName = 'Big Cats';
      expect(cats.getName(), 'Big Cats');
    });

    test('keeps the name it was shared under once it is no longer shared '
        '(it stays a list on the account, which goes by that name)', () async {
      final favourites = userEntryListManager.getEntryLists()[kDefaultListKey]!;
      final owned = await listsService.shareList(
        sourceList: favourites,
        displayName: 'Tiny Tunks',
        sessionToken: 'fake-session-jwt',
      );
      await listsService.stopSharing(owned);

      expect(favourites.getName(), 'Tiny Tunks');
    });
  });

  // Bringing the account's lists onto a device (and their name clashes) is
  // the sign-in merge's job now: sharing/account_sync_test.dart.
  group('allocateLocalKey', () {
    test('a copy of a list called "search for" gets a suffixed key too', () {
      expect(
        listsService.allocateLocalKey(
          preferredName: 'search for',
          fallbackBase: 'Duplicated list',
        ),
        'search_for_2_words',
      );
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
      await sharing.lists.insert(
        SyncedEntryList.owner(
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
        ),
      );
      expect(
        sharedPreferences.getString('shared_ownedlist001_meta'),
        isNotNull,
      );
      expect(
        sharedPreferences.getStringList(KEY_SHARED_LIST_IDS),
        contains('ownedlist001'),
      );

      // Simulate the user deleting the local source list out from under
      // the wrapper, then a fresh app launch.
      await userEntryListManager.deleteEntryList('cats_words');
      final reloaded = SyncedEntryListManager.fromStartup();

      // Manager doesn't hold the orphaned wrapper any more.
      expect(reloaded.hasList('ownedlist001'), isFalse);
      // The index has been re-written without the dangling id, and the
      // orphaned meta + payload keys have been removed (no more leak).
      expect(
        sharedPreferences.getStringList(KEY_SHARED_LIST_IDS),
        isNot(contains('ownedlist001')),
      );
      expect(sharedPreferences.getString('shared_ownedlist001_meta'), isNull);
      expect(
        sharedPreferences.getStringList('shared_ownedlist001_words'),
        isNull,
      );
    });
  });
}
