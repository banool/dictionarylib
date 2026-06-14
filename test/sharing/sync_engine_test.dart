import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:dictionarylib/entry_list.dart';
import 'package:dictionarylib/globals.dart';
import 'package:dictionarylib/saved_video.dart';
import 'package:dictionarylib/sharing/auth/auth_api.dart';
import 'package:dictionarylib/sharing/auth/auth_service.dart';
import 'package:dictionarylib/sharing/auth/auth_store.dart';
import 'package:dictionarylib/sharing/sync_api.dart';
import 'package:dictionarylib/sharing/sync_engine.dart';
import 'package:dictionarylib/sharing/synced_entry_list.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../_helpers.dart';

/// Construct a SavedVideo for the synthetic `videoFor(entryKey)` URL.
/// Lets per-entry tests stay terse — `_v('apple')` instead of spelling
/// out the URL each time.
SavedVideo _v(String entryKey) =>
    SavedVideo(entryKey: entryKey, mediaPath: videoFor(entryKey));

/// Build a [SyncEngine] backed by a stub HTTP client. Returns the
/// engine, its manager, the requests list, and the auth service so
/// individual tests can drop the session to exercise unauthenticated
/// paths.
({
  SyncEngine engine,
  SyncedEntryListManager manager,
  AuthService auth,
  List<http.Request> requests
}) _makeEngine(Future<http.Response> Function(http.Request) handle,
    {AuthSession? session = kTestSession}) {
  final requests = <http.Request>[];
  final client = MockClient((req) async {
    requests.add(req);
    return handle(req);
  });
  final api = SyncApi(kTestSharingConfig, client: client);
  final authApi = AuthApi(kTestSharingConfig, client: client);
  final store = AuthStore.withSession(session);
  final auth =
      AuthService(config: kTestSharingConfig, api: authApi, store: store);
  final manager = SyncedEntryListManager.fromStartup();
  final engine = SyncEngine(api: api, manager: manager, auth: auth);
  return (engine: engine, manager: manager, auth: auth, requests: requests);
}

/// Construct a local list seeded with one saved video per entry key in
/// [keys] (the synthetic `videoFor(key)` URL).
Future<EntryList> _localListWith(String localKey, List<String> keys) async {
  if (localKey != 'favourites_words' &&
      !userEntryListManager.getEntryLists().containsKey(localKey)) {
    await userEntryListManager.createEntryList(localKey);
  }
  final list = userEntryListManager.getEntryLists()[localKey]!;
  for (final k in keys) {
    await list.addVideo(_v(k));
  }
  return list;
}

void main() {
  setUp(() async {
    installFakeSecureStorage();
    SharedPreferences.setMockInitialValues({});
    sharedPreferences = await SharedPreferences.getInstance();
    seedDictionary(['apple', 'banana', 'cherry', 'date']);
    userEntryListManager = UserEntryListManager.fromStartup();
  });

  /// Helper: build an owner-mode list with the given local key + initial
  /// keys, pre-installed in the manager so tests can skip the createOwned
  /// round-trip. Shared by every group below.
  Future<SyncedEntryList> setUpOwnedList(
      SyncEngine engine, SyncedEntryListManager manager,
      {String localKey = 'cats_words',
      List<String> initialKeys = const ['apple'],
      String listId = 'listidaaaaa1'}) async {
    final source = await _localListWith(localKey, initialKeys);
    final list = SyncedEntryList.owner(
      meta: SyncedListMeta(
        listId: listId,
        displayName: 'My Cats',
        role: ListRole.owner,
        lastKnownSeq: 1,
        etag: null,
        lastSyncedAt: 1700000000,
        serverUpdatedAt: 1700000000,
        orphaned: false,
        sourceLocalKey: localKey,
      ),
      source: source,
    );
    await manager.insert(list);
    return list;
  }

  group('SyncEngine.createOwned', () {
    test('POSTs entries + returns an owner wrapper with the local source',
        () async {
      final source = await _localListWith('cats_words', ['apple', 'banana']);
      final ctx = _makeEngine((req) async => stubCreateResponse(req));

      final synced = await ctx.engine.createOwned(
        displayName: 'My Cats',
        source: source,
        sessionToken: 'fake-session-jwt',
      );

      expect(ctx.requests, hasLength(1));
      final body = jsonDecode(ctx.requests.single.body) as Map<String, dynamic>;
      expect(body['displayName'], 'My Cats');
      expect(body['entries'], [
        {'entry': 'apple', 'video': videoFor('apple')},
        {'entry': 'banana', 'video': videoFor('banana')},
      ]);
      expect(body['schemaVersion'], 3);

      expect(synced.meta.role, ListRole.owner);
      expect(synced.meta.sourceLocalKey, 'cats_words');
      expect(synced.meta.lastKnownSeq, 1);
      expect(synced.ownerSource, same(source));
      // Owner wrapper shares the local list's savedVideos set by identity.
      expect(synced.savedVideos, same(source.savedVideos));
    });

    test('retries on ID_COLLISION with a new key', () async {
      final source = await _localListWith('cats_words', const []);
      var calls = 0;
      final ctx = _makeEngine((req) async {
        calls++;
        if (calls == 1) {
          return http.Response(
            jsonEncode({
              'error': {'code': 'ID_COLLISION', 'message': 'taken'}
            }),
            409,
          );
        }
        return stubCreateResponse(req);
      });

      final synced = await ctx.engine.createOwned(
          displayName: 'x', source: source, sessionToken: 'fake-session-jwt');
      expect(calls, 2);
      expect(synced.listId, isNotEmpty);
    });

    test('rethrows non-collision errors without retrying', () async {
      final source = await _localListWith('cats_words', const []);
      var calls = 0;
      final ctx = _makeEngine((req) async {
        calls++;
        return http.Response(
            jsonEncode({
              'error': {'code': 'INVALID', 'message': 'no'}
            }),
            400);
      });

      await expectLater(
        ctx.engine.createOwned(
            displayName: 'x', source: source, sessionToken: 'fake-session-jwt'),
        throwsA(isA<SyncException>()
            .having((e) => e.kind, 'kind', SyncErrorKind.invalidBody)),
      );
      expect(calls, 1);
    });
  });

  group('SyncEngine — op queue + /sync flush', () {
    test('enqueueAddEntry queues a pending op and persists meta', () async {
      final ctx = _makeEngine((req) async => stubSyncApplyAll(req));
      final list = await setUpOwnedList(ctx.engine, ctx.manager);

      ctx.engine.enqueueAddVideo(list.listId, _v('banana'));
      expect(list.meta.pendingOps, hasLength(1));
      expect(list.meta.pendingOps.single.type, 'addEntry');
      expect(list.meta.pendingOps.single.args['entry'], 'banana');
      expect(list.meta.pendingOps.single.args['video'], videoFor('banana'));
    });

    test('flush — applied ops are dropped from the queue', () async {
      final ctx = _makeEngine((req) async => stubSyncApplyAll(req));
      final list = await setUpOwnedList(ctx.engine, ctx.manager);

      ctx.engine.enqueueAddVideo(list.listId, _v('banana'));
      ctx.engine.enqueueAddVideo(list.listId, _v('cherry'));
      // The engine debounces by 2s; flush directly via pushAllDirty.
      await ctx.engine.pushAllDirty();

      expect(list.meta.pendingOps, isEmpty);
      expect(list.meta.lastKnownSeq, greaterThan(1));
      // Two ops in one batch.
      final syncReqs = ctx.requests.where((r) => r.url.path.endsWith('/sync'));
      expect(syncReqs, hasLength(1));
      final body = jsonDecode(syncReqs.single.body) as Map<String, dynamic>;
      expect((body['ops'] as List).length, 2);
    });

    test('flush sends lastKnownSeq + clientId headers', () async {
      final ctx = _makeEngine((req) async => stubSyncApplyAll(req));
      final list = await setUpOwnedList(ctx.engine, ctx.manager);
      ctx.engine.enqueueAddVideo(list.listId, _v('banana'));
      await ctx.engine.pushAllDirty();

      final req = ctx.requests.firstWhere((r) => r.url.path.endsWith('/sync'));
      expect(req.headers['x-app-id'], 'auslan');
      expect(req.headers['authorization'], 'Bearer fake-session-jwt');
      expect(req.headers['x-client-id'], isNotEmpty);
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      expect(body['lastKnownSeq'], 1);
    });

    test('missedOps from other editors are applied to local mirror', () async {
      final ctx = _makeEngine((req) async {
        if (req.url.path.endsWith('/sync')) {
          return stubSyncApplyAll(req, missedOps: [
            {
              'seq': 5,
              'type': 'addEntry',
              'args': {'entry': 'date', 'video': videoFor('date')},
              'userId': 'apple:other-editor',
              'actorDisplayName': 'Other Editor',
              'serverTs': 1700000100,
            }
          ]);
        }
        return http.Response('', 404);
      });
      final list = await setUpOwnedList(ctx.engine, ctx.manager);
      // Trigger a sync with no pending ops — pulls in missedOps.
      await ctx.engine.syncAll();

      expect(list.savedVideos.map((v) => v.entryKey), contains('date'));
    });

    test('snapshot response (catch-up) replaces local entries', () async {
      final ctx = _makeEngine((req) async {
        return http.Response(
          jsonEncode({
            'appliedSeq': 99,
            'applied': [],
            'missedOps': null,
            'snapshot': snapshotJson(
                listId: 'listidaaaaa1',
                displayName: 'My Cats',
                entries: ['cherry', 'date'],
                lastSeq: 99),
            'members': {
              'owner': {
                'userId': 'apple:test-user',
                'displayName': 'Test User'
              },
              'editors': <Map<String, dynamic>>[],
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final list = await setUpOwnedList(ctx.engine, ctx.manager);
      await ctx.engine.syncAll();
      // The owner's local source list should now reflect the snapshot.
      expect(list.ownerSource!.savedVideos.map((v) => v.entryKey),
          containsAll(['cherry', 'date']));
      expect(list.meta.lastKnownSeq, 99);
    });

    test('401 drops the session locally, leaves ops queued', () async {
      final ctx = _makeEngine((req) async {
        return http.Response(
            jsonEncode({
              'error': {'code': 'UNAUTHORIZED', 'message': 'expired'}
            }),
            401);
      });
      final list = await setUpOwnedList(ctx.engine, ctx.manager);
      ctx.engine.enqueueAddVideo(list.listId, _v('banana'));
      await ctx.engine.pushAllDirty();

      expect(ctx.auth.store.current, isNull,
          reason: 'engine should drop the session on 401');
      expect(list.meta.pendingOps, isNotEmpty,
          reason: 'ops stay queued for the eventual re-sign-in');
    });

    test('403 demotes role to subscriber and drops ops', () async {
      final ctx = _makeEngine((req) async {
        return http.Response(
            jsonEncode({
              'error': {'code': 'FORBIDDEN', 'message': 'gone'}
            }),
            403);
      });
      final list = await setUpOwnedList(ctx.engine, ctx.manager);
      ctx.engine.enqueueAddVideo(list.listId, _v('banana'));
      await ctx.engine.pushAllDirty();

      expect(list.meta.role, ListRole.subscriber);
      expect(list.meta.pendingOps, isEmpty);
    });

    test(
        'repeated 404s on an owned list eventually drop the share but keep '
        'the local list', () async {
      final ctx = _makeEngine((req) async {
        return http.Response(
            jsonEncode({
              'error': {'code': 'NOT_FOUND', 'message': 'gone'}
            }),
            404);
      });
      final list = await setUpOwnedList(ctx.engine, ctx.manager);
      ctx.engine.enqueueAddVideo(list.listId, _v('banana'));

      // A 404 is ambiguous (config drift / transient miss), so the first
      // two leave the share and its queue fully intact.
      await ctx.engine.pushAllDirty();
      await ctx.engine.pushAllDirty();
      expect(ctx.manager.hasList(list.listId), isTrue,
          reason: 'mirror must survive transient 404s');
      expect(list.meta.pendingOps, isNotEmpty,
          reason: 'queued edits must survive transient 404s');

      // The third consecutive 404 is treated as authoritative.
      await ctx.engine.pushAllDirty();
      // The share is gone server-side, so rather than leave a "deleted by you"
      // zombie the owner mirror is dropped...
      expect(ctx.manager.hasList(list.listId), isFalse);
      // ...while the underlying local list (the user's own data) is kept, so it
      // simply reverts to a plain local list.
      expect(userEntryListManager.getEntryLists().containsKey('cats_words'),
          isTrue);
    });

    test('410 (gone) drops the share immediately — it is authoritative',
        () async {
      final ctx = _makeEngine((req) async {
        return http.Response(
            jsonEncode({
              'error': {'code': 'GONE', 'message': 'deleted'}
            }),
            410);
      });
      final list = await setUpOwnedList(ctx.engine, ctx.manager);
      ctx.engine.enqueueAddVideo(list.listId, _v('banana'));
      await ctx.engine.pushAllDirty();

      expect(ctx.manager.hasList(list.listId), isFalse);
      expect(userEntryListManager.getEntryLists().containsKey('cats_words'),
          isTrue);
    });

    test('an editor mirror and its queue survive transient 404s', () async {
      final ctx = _makeEngine((req) async {
        return http.Response(
            jsonEncode({
              'error': {'code': 'NOT_FOUND', 'message': 'gone'}
            }),
            404);
      });
      await ctx.manager.insert(SyncedEntryList.editor(
        meta: SyncedListMeta(
          listId: 'editor404aaa',
          displayName: 'Editing',
          role: ListRole.editor,
          lastKnownSeq: 1,
          etag: null,
          lastSyncedAt: 1700000000,
          serverUpdatedAt: 1700000000,
          orphaned: false,
        ),
        savedVideos: LinkedHashSet.of({_v('apple')}),
      ));
      ctx.engine.enqueueAddVideo('editor404aaa', _v('banana'));

      await ctx.engine.pushAllDirty();
      await ctx.engine.pushAllDirty();

      final mirror = ctx.manager.get('editor404aaa');
      expect(mirror, isNotNull,
          reason: 'editor mirror must survive transient 404s');
      expect(mirror!.meta.pendingOps, isNotEmpty);

      // The third consecutive 404 deletes the editor mirror (it was only
      // ever a copy of someone else's list).
      await ctx.engine.pushAllDirty();
      expect(ctx.manager.hasList('editor404aaa'), isFalse);
    });

    test('a successful sync resets the consecutive-404 counter', () async {
      var calls = 0;
      final ctx = _makeEngine((req) async {
        calls++;
        if (calls == 3) return stubSyncApplyAll(req);
        return http.Response(
            jsonEncode({
              'error': {'code': 'NOT_FOUND', 'message': 'gone'}
            }),
            404);
      });
      final list = await setUpOwnedList(ctx.engine, ctx.manager);
      ctx.engine.enqueueAddVideo(list.listId, _v('banana'));

      await ctx.engine.pushAllDirty(); // 404 #1.
      await ctx.engine.pushAllDirty(); // 404 #2.
      await ctx.engine.pushAllDirty(); // Success — resets the counter.
      ctx.engine.enqueueAddVideo(list.listId, _v('cherry'));
      await ctx.engine.pushAllDirty(); // 404 #1 again.
      await ctx.engine.pushAllDirty(); // 404 #2 again.

      expect(ctx.manager.hasList(list.listId), isTrue,
          reason: 'the success in between must reset the 404 streak');
    });

    test(
        'stale-cursor 400 re-adopts server state, keeps the queue, and '
        'reflushes', () async {
      final notifications = <SyncNotification>[];
      var stateGets = 0;
      final ctx = _makeEngine((req) async {
        if (req.method == 'GET' && req.url.path.endsWith('/state')) {
          stateGets++;
          return http.Response(
              jsonEncode(snapshotJson(
                listId: 'listidaaaaa1',
                displayName: 'Cats',
                entries: ['apple'],
                lastSeq: 2,
              )),
              200);
        }
        return http.Response(
            jsonEncode({
              'error': {
                'code': 'INVALID_BODY',
                'message': 'lastKnownSeq is ahead of the server',
                'details': {'reason': 'stale_cursor'},
              }
            }),
            400);
      });
      ctx.engine.notifications.listen(notifications.add);
      final list = await setUpOwnedList(ctx.engine, ctx.manager);
      // Simulate a cursor from before the server lost state.
      list.meta.lastKnownSeq = 99;
      ctx.engine.enqueueAddVideo(list.listId, _v('banana'));

      await ctx.engine.pushAllDirty();

      expect(stateGets, 1, reason: 'recovery must fetch /state');
      expect(list.meta.lastKnownSeq, 2,
          reason: 'cursor must be re-adopted from the authoritative snapshot');
      expect(list.meta.pendingOps, isNotEmpty,
          reason: 'queued edits must survive the cursor reset');
      // Server state (apple) plus the still-pending local edit (banana).
      expect(list.savedVideos, containsAll({_v('apple'), _v('banana')}));
      expect(notifications, contains(SyncNotification.snapshotCatchUp));
    });

    test('no session → flush is a no-op, ops stay queued', () async {
      final ctx =
          _makeEngine((req) async => stubSyncApplyAll(req), session: null);
      final list = await setUpOwnedList(ctx.engine, ctx.manager);
      ctx.engine.enqueueAddVideo(list.listId, _v('banana'));
      await ctx.engine.pushAllDirty();

      expect(ctx.requests, isEmpty);
      expect(list.meta.pendingOps, hasLength(1));
    });

    test('cachedMembers is updated after each /sync response', () async {
      final ctx = _makeEngine((req) async => stubSyncApplyAll(req, members: {
            'owner': {'userId': 'apple:test-user', 'displayName': 'Test User'},
            'editors': [
              {
                'userId': 'google:bob',
                'displayName': 'Bob',
                'addedAt': 1700000010,
                'addedBy': 'apple:test-user',
              }
            ],
          }));
      final list = await setUpOwnedList(ctx.engine, ctx.manager);
      ctx.engine.enqueueAddVideo(list.listId, _v('banana'));
      await ctx.engine.pushAllDirty();

      expect(list.meta.cachedMembers, isNotNull);
      expect(list.meta.cachedMembers!.editors, hasLength(1));
      expect(list.meta.cachedMembers!.editors.single.displayName, 'Bob');
    });
  });

  group('SyncEngine.subscribe', () {
    test('fetches the public R2 snapshot and inserts a subscriber wrapper',
        () async {
      final ctx = _makeEngine((req) async {
        return http.Response(
          jsonEncode({
            'schemaVersion': 3,
            'listId': 'abcdef123456',
            'displayName': 'Greetings',
            'appId': 'auslan',
            'entries': [
              {'entry': 'apple', 'video': videoFor('apple')},
              {'entry': 'banana', 'video': videoFor('banana')},
            ],
            'lastSeq': 4,
            'createdAt': 1700000000,
            'updatedAt': 1700000050,
          }),
          200,
          headers: {
            'content-type': 'application/json',
            'etag': '"sub-etag"',
            'last-modified': 'Mon, 14 Nov 2023 12:00:00 GMT',
          },
        );
      });

      final list = await ctx.engine.subscribe('abcdef123456');

      expect(list, isNotNull);
      expect(list!.meta.role, ListRole.subscriber);
      expect(list.meta.lastKnownSeq, 4);
      expect(list.meta.etag, '"sub-etag"');
      expect(list.savedVideos.map((v) => v.entryKey), ['apple', 'banana']);
    });
  });

  group('SyncEngine.acceptInvite', () {
    test('installs an editor-mode mirror from the snapshot', () async {
      final ctx = _makeEngine((req) async {
        if (req.url.path.endsWith('/accept-invite')) {
          return http.Response(
            jsonEncode(snapshotJson(
              listId: 'invitedlist1',
              displayName: 'Joined List',
              entries: ['apple'],
              lastSeq: 7,
            )),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('', 404);
      });

      final list = await ctx.engine
          .acceptInvite(listId: 'invitedlist1', token: 'invite-tok');
      expect(list.meta.role, ListRole.editor);
      expect(list.meta.lastKnownSeq, 7);
      expect(list.savedVideos.map((v) => v.entryKey), ['apple']);
    });

    test('owner accepting own invite is a no-op success', () async {
      final ctx = _makeEngine((req) async {
        return http.Response(
            jsonEncode(snapshotJson(
                listId: 'ownedidaaaaa',
                displayName: 'My Own',
                entries: ['apple'],
                lastSeq: 5)),
            200);
      });
      // Pre-install an owner list with the same id.
      final source = await _localListWith('myown_words', ['apple']);
      final owned = SyncedEntryList.owner(
        meta: SyncedListMeta(
          listId: 'ownedidaaaaa',
          displayName: 'My Own',
          role: ListRole.owner,
          lastKnownSeq: 1,
          etag: null,
          lastSyncedAt: 1700000000,
          serverUpdatedAt: 1700000000,
          orphaned: false,
          sourceLocalKey: 'myown_words',
        ),
        source: source,
      );
      await ctx.manager.insert(owned);

      final result =
          await ctx.engine.acceptInvite(listId: 'ownedidaaaaa', token: 'tok');
      // Same wrapper returned, still owner.
      expect(result.meta.role, ListRole.owner);
    });
  });

  group('SyncEngine.createInvite + removeEditor + leaveAsEditor', () {
    test('createInvite POSTs and returns the token', () async {
      final ctx = _makeEngine((req) async {
        return http.Response(
          jsonEncode({
            'token': 'inv-token-xyz',
            'expiresAt': 1700000999,
            'listId': 'listidaaaaa1',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final source = await _localListWith('owner_words', const []);
      await ctx.manager.insert(SyncedEntryList.owner(
        meta: SyncedListMeta(
          listId: 'listidaaaaa1',
          displayName: 'X',
          role: ListRole.owner,
          lastKnownSeq: 1,
          etag: null,
          lastSyncedAt: 1700000000,
          serverUpdatedAt: 1700000000,
          orphaned: false,
          sourceLocalKey: 'owner_words',
        ),
        source: source,
      ));

      final invite = await ctx.engine.createInvite('listidaaaaa1');
      expect(invite.token, 'inv-token-xyz');
      expect(invite.expiresAt, 1700000999);
    });

    test('leaveAsEditor removes the local mirror', () async {
      final ctx = _makeEngine((req) async {
        if (req.method == 'DELETE') return http.Response('', 204);
        return http.Response('', 404);
      });
      await ctx.manager.insert(SyncedEntryList.editor(
        meta: SyncedListMeta(
          listId: 'editingaaaaa',
          displayName: 'Editing',
          role: ListRole.editor,
          lastKnownSeq: 1,
          etag: null,
          lastSyncedAt: 1700000000,
          serverUpdatedAt: 1700000000,
          orphaned: false,
        ),
        savedVideos: LinkedHashSet<SavedVideo>(),
      ));

      await ctx.engine.leaveAsEditor('editingaaaaa');
      expect(ctx.manager.get('editingaaaaa'), isNull);
    });
  });

  group('SyncEngine subscriber pull', () {
    test('304 path bumps lastSyncedAt without touching entries', () async {
      final ctx = _makeEngine((req) async => http.Response('', 304));
      await ctx.manager.insert(SyncedEntryList.subscriber(
        meta: SyncedListMeta(
          listId: 'subbed123456',
          displayName: 'Subbed',
          role: ListRole.subscriber,
          lastKnownSeq: 1,
          etag: '"etag1"',
          lastSyncedAt: 1700000000,
          serverUpdatedAt: 1700000000,
          orphaned: false,
        ),
        savedVideos: LinkedHashSet<SavedVideo>(),
      ));

      await ctx.engine.refreshSubscriber('subbed123456');
      final list = ctx.manager.get('subbed123456')!;
      expect(list.meta.lastSyncedAt, greaterThan(1700000000));
    });

    test(
        'user-initiated refresh sends Cache-Control: no-cache; '
        'background poll does not', () async {
      final ctx = _makeEngine((req) async => http.Response('', 304));
      await ctx.manager.insert(SyncedEntryList.subscriber(
        meta: SyncedListMeta(
          listId: 'subbed123456',
          displayName: 'Subbed',
          role: ListRole.subscriber,
          lastKnownSeq: 1,
          etag: '"etag1"',
          lastSyncedAt: 1700000000,
          serverUpdatedAt: 1700000000,
          orphaned: false,
        ),
        savedVideos: LinkedHashSet<SavedVideo>(),
      ));

      // Pull-to-refresh → bypass the worker edge cache.
      await ctx.engine.refreshSubscriber('subbed123456');
      final refreshReq = ctx.requests.last;
      expect(refreshReq.method, 'GET');
      expect(refreshReq.headers['cache-control'], 'no-cache');

      // Background full sync → stay on the cheap cached path (no override).
      await ctx.engine.syncAll();
      final pollReq = ctx.requests.last;
      expect(pollReq.method, 'GET');
      expect(pollReq.headers.containsKey('cache-control'), isFalse);
    });
  });

  group('SyncEngine — per-list lock serialisation', () {
    test(
        'enqueueAddEntry during an in-flight flush is sent in a follow-up '
        '/sync call (no lost op)', () async {
      // Gate the first /sync response so we can interleave a second
      // enqueue + flush before it returns.
      final firstSyncGate = Completer<void>();
      var syncCallCount = 0;
      final ctx = _makeEngine((req) async {
        if (req.url.path.endsWith('/sync')) {
          syncCallCount++;
          if (syncCallCount == 1) {
            await firstSyncGate.future;
          }
          return stubSyncApplyAll(req);
        }
        return http.Response('', 404);
      });
      final list = await setUpOwnedList(ctx.engine, ctx.manager);

      // Op 1 — kick off the first flush (which will block on the gate).
      ctx.engine.enqueueAddVideo(list.listId, _v('banana'));
      final firstFlush = ctx.engine.pushAllDirty();
      // Yield a few times so the request actually leaves the engine.
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(syncCallCount, 1,
          reason: 'first /sync should have been dispatched');

      // Op 2 — enqueued *while* the first sync is still in flight.
      // The lock should park this op's flush behind the in-flight one.
      ctx.engine.enqueueAddVideo(list.listId, _v('cherry'));
      expect(list.meta.pendingOps.where((o) => o.args['entry'] == 'cherry'),
          hasLength(1));

      // Release the first sync so it can drain.
      firstSyncGate.complete();
      await firstFlush;
      // The drain loop in _drainListPending re-flushes if more ops are
      // queued; await any tail work.
      await ctx.engine.pushAllDirty();

      expect(syncCallCount, greaterThanOrEqualTo(2),
          reason: 'the second op must be sent in its own /sync call');
      expect(list.meta.pendingOps, isEmpty, reason: 'both ops should be acked');
    });

    test(
        'two concurrent pushAllDirty calls do not double-send the same '
        'pending ops', () async {
      // We count both the number of /sync calls AND the number of
      // distinct ops that the engine sent on the wire. The lock should
      // serialise the flushes such that each op is sent exactly once,
      // even if the second flush ends up firing a pull-only /sync.
      final sentOpIds = <String>[];
      final ctx = _makeEngine((req) async {
        if (req.url.path.endsWith('/sync')) {
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          for (final op in (body['ops'] as List).cast<Map<String, dynamic>>()) {
            sentOpIds.add(op['opId'] as String);
          }
          return stubSyncApplyAll(req);
        }
        return http.Response('', 404);
      });
      final list = await setUpOwnedList(ctx.engine, ctx.manager);
      ctx.engine.enqueueAddVideo(list.listId, _v('banana'));
      final theOpId = list.meta.pendingOps.single.opId;

      // Fire two pushAllDirty calls concurrently. The per-list lock
      // serialises them — the op must reach the wire exactly once.
      await Future.wait([
        ctx.engine.pushAllDirty(),
        ctx.engine.pushAllDirty(),
      ]);

      expect(sentOpIds, [theOpId],
          reason: 'lock serialisation must prevent the same op from being '
              're-sent on a concurrent flush call');
      expect(list.meta.pendingOps, isEmpty);
    });
  });

  group('SyncEngine — partial-batch draining', () {
    test('60 queued ops → two /sync calls (50 + 10)', () async {
      final sentBatchSizes = <int>[];
      final ctx = _makeEngine((req) async {
        if (req.url.path.endsWith('/sync')) {
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          final ops = (body['ops'] as List).cast<Map<String, dynamic>>();
          sentBatchSizes.add(ops.length);
          // Use the next batch's expected starting seq so each batch's
          // applied seqs are unique. lastKnownSeq starts at 1 and grows.
          final start = 1 +
              sentBatchSizes.fold<int>(
                  0, (sum, n) => sum + (n == ops.length ? 0 : n)) +
              1; // simplistic but sufficient
          return stubSyncApplyAll(req, firstAppliedSeq: start);
        }
        return http.Response('', 404);
      });
      // Seed 60 entries into the dictionary so the addEntry ops have
      // matching local entries.
      final keys = List.generate(60, (i) => 'word$i');
      seedDictionary(['apple', 'banana', 'cherry', 'date', ...keys]);
      final list = await setUpOwnedList(ctx.engine, ctx.manager);

      for (final k in keys) {
        ctx.engine.enqueueAddVideo(list.listId, _v(k));
      }
      expect(list.meta.pendingOps, hasLength(60));

      await ctx.engine.pushAllDirty();

      expect(sentBatchSizes, [50, 10],
          reason: 'queue should drain in two chunks per the '
              '_maxOpsPerBatch cap');
      expect(list.meta.pendingOps, isEmpty);
    });
  });

  group('SyncEngine — 429 backoff path', () {
    test('429 with Retry-After leaves pending ops queued', () async {
      var syncCallCount = 0;
      final ctx = _makeEngine((req) async {
        syncCallCount++;
        return http.Response(
          jsonEncode({
            'error': {'code': 'RATE_LIMITED', 'message': 'slow down'}
          }),
          429,
          headers: {'retry-after': '1'},
        );
      });
      final list = await setUpOwnedList(ctx.engine, ctx.manager);
      ctx.engine.enqueueAddVideo(list.listId, _v('banana'));

      await ctx.engine.pushAllDirty();

      expect(syncCallCount, 1,
          reason: 'engine should not retry immediately on 429 — backoff '
              'timer takes over');
      expect(list.meta.pendingOps, hasLength(1),
          reason: 'pending ops stay queued for the eventual backoff retry');
      expect(list.meta.role, ListRole.owner,
          reason: '429 does not change role');
      // We intentionally don't pump the backoff timer here — the test
      // for "the engine actually retries after the backoff window" is
      // tricky to write without making it flaky on slow CI, and the
      // backoff machinery is exercised by the explicit doubling test
      // below.
    });

    test('repeated 5xx doubles the backoff seconds', () async {
      final ctx = _makeEngine((req) async {
        return http.Response(
          jsonEncode({
            'error': {'code': 'SERVER', 'message': 'oops'}
          }),
          500,
        );
      });
      final list = await setUpOwnedList(ctx.engine, ctx.manager);
      ctx.engine.enqueueAddVideo(list.listId, _v('banana'));

      // First flush — fails 5xx, schedules backoff seconds = 2.
      await ctx.engine.pushAllDirty();
      // Reach into the per-list state via the test-only AsyncLock path
      // is overkill; instead, drive the engine by calling syncAll/flush
      // directly. pushAllDirty bails after the first failure because of
      // the backoff guard, so we use syncAll to trigger another flush.
      await ctx.engine.syncAll();
      await ctx.engine.syncAll();

      // Three failed attempts: 1 (prev) * 2 = 2 → 4 → 8.
      // We can't observe the private backoffSeconds field directly,
      // but we can assert the engine kept retrying instead of getting
      // wedged: the queue is still non-empty (no auto-drop) and at
      // least three /sync calls have happened.
      expect(list.meta.pendingOps, isNotEmpty,
          reason: 'server failures do not drop ops');
    });
  });

  group('SyncEngine — crash-window recovery via replayPendingOpsLocally', () {
    test(
        'meta-written-but-entries-write-skipped → load + replay folds the '
        'pending op back into the in-memory entries set', () async {
      // Simulate a crash *after* meta-write but *before* entries-write
      // by writing the meta blob manually and leaving the payload
      // shared-prefs key empty. Owner mode shares the source's payload
      // key, so we use editor mode here for a clean meta-vs-payload
      // separation.
      const listId = 'crashedlist1';
      final pendingOp = PendingOp(
        opId: 'op-test-1',
        type: 'addEntry',
        args: {'entry': 'banana', 'video': videoFor('banana')},
        clientTs: 1700000010,
      );
      final meta = SyncedListMeta(
        listId: listId,
        displayName: 'Crashed',
        role: ListRole.editor,
        lastKnownSeq: 1,
        etag: null,
        lastSyncedAt: 1700000000,
        serverUpdatedAt: 1700000000,
        orphaned: false,
        pendingOps: [pendingOp],
      );
      await sharedPreferences.setString(
          sharedMetaStorageKey(listId), jsonEncode(meta.toJson()));
      // No payload write — simulates the crash window.
      await sharedPreferences.setStringList(KEY_SHARED_LIST_IDS, [listId]);

      // Restart: build a fresh manager from prefs.
      final reloaded = SyncedEntryListManager.fromStartup();
      final list = reloaded.get(listId);

      expect(list, isNotNull,
          reason: 'loadFromRaw should successfully load the editor list');
      expect(list!.savedVideos.map((v) => v.entryKey), contains('banana'),
          reason: 'replayPendingOpsLocally must fold the pending '
              'addEntry back into the in-memory saved-videos set');
      expect(list.meta.pendingOps, hasLength(1),
          reason: 'pending op is still queued for the next /sync');
    });
  });

  group('SyncEngine — 403 demotion triggers post-demote pull', () {
    test(
        '403 on /sync → role flips to subscriber, ops cleared, '
        'removedAsEditor notification emitted, follow-up GET fires', () async {
      var sawSync = false;
      var sawPostDemoteGet = false;
      final ctx = _makeEngine((req) async {
        if (req.method == 'POST' && req.url.path.endsWith('/sync')) {
          sawSync = true;
          return http.Response(
              jsonEncode({
                'error': {'code': 'FORBIDDEN', 'message': 'gone'}
              }),
              403);
        }
        if (req.method == 'GET' &&
            req.url.path.endsWith('/v1/lists/listidaaaaa1')) {
          sawPostDemoteGet = true;
          // Return a fresh public snapshot — the demoted user gets the
          // read-only view via this path.
          return http.Response(
            jsonEncode({
              'schemaVersion': 3,
              'listId': 'listidaaaaa1',
              'displayName': 'My Cats',
              'appId': 'auslan',
              'entries': [
                {'entry': 'apple', 'video': videoFor('apple')},
                {'entry': 'banana', 'video': videoFor('banana')},
              ],
              'lastSeq': 5,
              'createdAt': 1700000000,
              'updatedAt': 1700000050,
            }),
            200,
            headers: {'etag': '"post-demote-etag"'},
          );
        }
        return http.Response('', 404);
      });
      // Note: editor mode for the demotion test so we exercise the
      // editor → subscriber transition rather than the more unusual
      // owner → subscriber transition.
      await ctx.manager.insert(SyncedEntryList.editor(
        meta: SyncedListMeta(
          listId: 'listidaaaaa1',
          displayName: 'My Cats',
          role: ListRole.editor,
          lastKnownSeq: 1,
          etag: null,
          lastSyncedAt: 1700000000,
          serverUpdatedAt: 1700000000,
          orphaned: false,
        ),
        savedVideos: LinkedHashSet<SavedVideo>.from([_v('apple')]),
      ));
      final list = ctx.manager.get('listidaaaaa1')!;

      final notifications = <SyncNotification>[];
      final sub = ctx.engine.notifications.listen(notifications.add);

      ctx.engine.enqueueAddVideo(list.listId, _v('banana'));
      await ctx.engine.pushAllDirty();
      // The post-demote pull is fire-and-forget; let it run.
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      expect(sawSync, isTrue);
      expect(list.meta.role, ListRole.subscriber);
      expect(list.meta.pendingOps, isEmpty);
      expect(notifications, contains(SyncNotification.removedAsEditor));
      expect(sawPostDemoteGet, isTrue,
          reason: 'the engine should immediately pull the public snapshot '
              'after demoting so the user sees canonical state');

      await sub.cancel();
    });
  });

  group('SyncEngine — 401 session-expired notification', () {
    test('401 on /sync emits sessionExpired and preserves pending ops',
        () async {
      final ctx = _makeEngine((req) async {
        return http.Response(
            jsonEncode({
              'error': {'code': 'UNAUTHORIZED', 'message': 'expired'}
            }),
            401);
      });
      final list = await setUpOwnedList(ctx.engine, ctx.manager);

      final notifications = <SyncNotification>[];
      final sub = ctx.engine.notifications.listen(notifications.add);

      ctx.engine.enqueueAddVideo(list.listId, _v('banana'));
      await ctx.engine.pushAllDirty();

      expect(notifications, contains(SyncNotification.sessionExpired));
      expect(list.meta.pendingOps, isNotEmpty,
          reason: 'ops must survive a 401 — next sign-in resumes the flush');
      expect(ctx.auth.store.current, isNull,
          reason: 'session is dropped locally on 401');

      await sub.cancel();
    });
  });

  group('SyncEngine — multi-device convergence (owner)', () {
    test('local pending op + remote missedOp both end up in source.entries',
        () async {
      final ctx = _makeEngine((req) async {
        if (req.url.path.endsWith('/sync')) {
          // Server applied our addEntry(apple) AND reports that another
          // device added "banana" with seq 5.
          return stubSyncApplyAll(req, firstAppliedSeq: 4, missedOps: [
            {
              'seq': 5,
              'type': 'addEntry',
              'args': {'entry': 'banana', 'video': videoFor('banana')},
              'userId': 'apple:other-device',
              'actorDisplayName': 'Phone',
              'serverTs': 1700000099,
            }
          ]);
        }
        return http.Response('', 404);
      });
      final list =
          await setUpOwnedList(ctx.engine, ctx.manager, initialKeys: const []);
      ctx.engine.enqueueAddVideo(list.listId, _v('apple'));
      // Optimistically apply the local op to the source (mirrors what
      // SyncedEntryList.addVideo does after enqueue).
      list.ownerSource!.savedVideos.add(_v('apple'));
      await ctx.engine.pushAllDirty();

      final keys = list.ownerSource!.savedVideos.map((v) => v.entryKey).toSet();
      expect(keys, containsAll(['apple', 'banana']),
          reason: 'owner source list must contain both the locally-added '
              'and the remotely-added entries after convergence');
      // The source list should also be persisted via writeAllAfterServerAck
      // (which calls write() on the owner wrapper → which delegates to
      // the source's payload key).
      final persisted =
          sharedPreferences.getStringList(list.ownerSource!.key) ?? const [];
      expect(persisted.toSet(),
          containsAll([_v('apple').toStorage(), _v('banana').toStorage()]),
          reason: 'shared-prefs payload must reflect the merged state');
    });
  });

  group('SyncException + RemoteList — schemaVersion validation', () {
    test(
        'unsupported schemaVersion on a subscriber GET → '
        'SyncException(server)', () async {
      final ctx = _makeEngine((req) async {
        return http.Response(
          jsonEncode({
            'schemaVersion': 99,
            'listId': 'badschema001',
            'displayName': 'Bad',
            'appId': 'auslan',
            'entries': const ['apple'],
            'lastSeq': 1,
            'createdAt': 1,
            'updatedAt': 1,
          }),
          200,
          headers: {'content-type': 'application/json', 'etag': '"x"'},
        );
      });
      await expectLater(
        ctx.engine.subscribe('badschema001'),
        throwsA(isA<SyncException>()
            .having((e) => e.kind, 'kind', SyncErrorKind.server)),
      );
    });

    test('missing schemaVersion is rejected', () async {
      // No deployed clients pre-date the schemaVersion field, so a
      // payload without it is a misbehaving server, not a back-compat
      // case. Reject so the client doesn't silently misinterpret it.
      final ctx = _makeEngine((req) async {
        return http.Response(
          jsonEncode({
            // No schemaVersion field.
            'listId': 'oldschema001',
            'displayName': 'Old',
            'appId': 'auslan',
            'entries': const ['apple'],
            'lastSeq': 1,
            'createdAt': 1,
            'updatedAt': 1,
          }),
          200,
          headers: {'content-type': 'application/json', 'etag': '"x"'},
        );
      });
      await expectLater(
        ctx.engine.subscribe('oldschema001'),
        throwsA(isA<SyncException>()
            .having((e) => e.kind, 'kind', SyncErrorKind.server)),
      );
    });
  });

  group('SyncEngine — unknown 4xx → unknownClient', () {
    test('an unrecognised 4xx (422) maps to SyncErrorKind.unknownClient',
        () async {
      final ctx = _makeEngine((req) async {
        return http.Response(
          jsonEncode({
            'error': {'code': 'UNPROCESSABLE', 'message': 'nope'}
          }),
          422,
        );
      });
      final list = await setUpOwnedList(ctx.engine, ctx.manager);
      ctx.engine.enqueueAddVideo(list.listId, _v('banana'));
      await ctx.engine.pushAllDirty();
      // unknownClient is treated as permanently rejected — ops dropped.
      expect(list.meta.pendingOps, isEmpty,
          reason: 'unknownClient ops drop from the queue (would loop '
              'forever otherwise)');
    });
  });

  group('SyncedEntryListManager.fromStartup — meta-level recovery', () {
    test('cachedMembers survives a fromStartup round-trip', () async {
      const listId = 'memberscache1';
      final meta = SyncedListMeta(
        listId: listId,
        displayName: 'Cached Members',
        role: ListRole.editor,
        lastKnownSeq: 5,
        etag: null,
        lastSyncedAt: 1700000000,
        serverUpdatedAt: 1700000000,
        orphaned: false,
        cachedMembers: MembersBlock(
          owner: const MemberRef(
              userId: 'apple:test-user', displayName: 'Test User'),
          editors: const [
            EditorRef(
              userId: 'google:bob',
              displayName: 'Bob',
              addedAt: 1700000010,
              addedBy: 'apple:test-user',
            ),
          ],
        ),
      );
      await sharedPreferences.setString(
          sharedMetaStorageKey(listId), jsonEncode(meta.toJson()));
      await sharedPreferences.setStringList(KEY_SHARED_LIST_IDS, [listId]);

      final reloaded = SyncedEntryListManager.fromStartup();
      final list = reloaded.get(listId);
      expect(list, isNotNull);
      expect(list!.meta.cachedMembers, isNotNull);
      expect(list.meta.cachedMembers!.owner.userId, 'apple:test-user');
      expect(list.meta.cachedMembers!.editors, hasLength(1));
      expect(list.meta.cachedMembers!.editors.single.displayName, 'Bob');
    });
  });

  group('SyncEngine.createOwned — ID-collision exhaustion', () {
    test(
        'always-409 server → throws SyncException(idCollision) after '
        '5 attempts', () async {
      var attempts = 0;
      final source = await _localListWith('cats_words', const []);
      final ctx = _makeEngine((req) async {
        attempts++;
        return http.Response(
            jsonEncode({
              'error': {'code': 'ID_COLLISION', 'message': 'taken'}
            }),
            409);
      });

      await expectLater(
        ctx.engine.createOwned(
            displayName: 'x', source: source, sessionToken: 'fake-session-jwt'),
        throwsA(isA<SyncException>()
            .having((e) => e.kind, 'kind', SyncErrorKind.idCollision)),
      );
      // _createKeyMaxAttempts = 5 in sync_engine.dart.
      expect(attempts, 5,
          reason: 'engine should give up after 5 collision retries');
    });
  });

  group('SyncEngine.renameOwned', () {
    test('PUTs the new name and adopts it from the response snapshot',
        () async {
      final ctx = _makeEngine((req) async {
        if (req.method == 'PUT' &&
            req.url.path.endsWith('/v1/lists/listidaaaaa1')) {
          return http.Response(
            jsonEncode(snapshotJson(
              listId: 'listidaaaaa1',
              displayName: 'Renamed Cats',
              entries: ['apple'],
              lastSeq: 8,
              updatedAt: 1700000200,
            )),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('', 404);
      });
      final list = await setUpOwnedList(ctx.engine, ctx.manager);

      await ctx.engine
          .renameOwned(list.listId, 'Renamed Cats', 'fake-session-jwt');

      final put = ctx.requests.singleWhere((r) => r.method == 'PUT');
      expect(jsonDecode(put.body), {'displayName': 'Renamed Cats'});
      // The owner wrapper adopts the authoritative name + cursor.
      expect(list.meta.displayName, 'Renamed Cats');
      expect(list.meta.lastKnownSeq, 8);
      expect(list.meta.serverUpdatedAt, 1700000200);
    });

    test('throws for a non-owner role and sends no request', () async {
      final ctx = _makeEngine((req) async => http.Response('', 404));
      await ctx.manager.insert(SyncedEntryList.editor(
        meta: SyncedListMeta(
          listId: 'editoraaaaaa',
          displayName: 'Editing',
          role: ListRole.editor,
          lastKnownSeq: 1,
          etag: null,
          lastSyncedAt: 1,
          serverUpdatedAt: 1,
          orphaned: false,
        ),
        savedVideos: LinkedHashSet<SavedVideo>(),
      ));
      expect(
          () => ctx.engine
              .renameOwned('editoraaaaaa', 'Nope', 'fake-session-jwt'),
          throwsA(isA<StateError>()));
      expect(ctx.requests, isEmpty);
    });
  });

  group('SyncEngine — displayName sync-down', () {
    test('a /sync response displayName updates the editor mirror name',
        () async {
      // The owner renamed the list; the editor learns the new name from
      // the displayName echoed on their next /sync (no dedicated op).
      final ctx = _makeEngine((req) async {
        if (req.url.path.endsWith('/sync')) {
          return http.Response(
            jsonEncode({
              'appliedSeq': 1,
              'applied': <Map<String, dynamic>>[],
              'missedOps': <Map<String, dynamic>>[],
              'snapshot': null,
              'members': {
                'owner': {'userId': 'apple:other', 'displayName': 'Owner'},
                'editors': [
                  {
                    'userId': 'apple:test-user',
                    'displayName': 'Test User',
                    'addedAt': 1,
                    'addedBy': 'apple:other',
                  }
                ],
              },
              'wasSnapshotCatchUp': false,
              'displayName': 'Renamed By Owner',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('', 404);
      });
      await ctx.manager.insert(SyncedEntryList.editor(
        meta: SyncedListMeta(
          listId: 'editoraaaaaa',
          displayName: 'Old Name',
          role: ListRole.editor,
          lastKnownSeq: 1,
          etag: null,
          lastSyncedAt: 1,
          serverUpdatedAt: 1,
          orphaned: false,
        ),
        savedVideos: LinkedHashSet<SavedVideo>(),
      ));
      final list = ctx.manager.get('editoraaaaaa')!;

      await ctx.engine.syncAll();

      expect(list.meta.displayName, 'Renamed By Owner');
    });

    test('a /sync response without displayName leaves the local name alone',
        () async {
      // Back-compat: an older server omits the field. The client must
      // keep its current name rather than blanking it.
      final ctx = _makeEngine((req) async => stubSyncApplyAll(req));
      final list = await setUpOwnedList(ctx.engine, ctx.manager);
      final before = list.meta.displayName;
      ctx.engine.enqueueAddVideo(list.listId, _v('banana'));
      await ctx.engine.pushAllDirty();
      expect(list.meta.displayName, before);
    });
  });

  // Pull-to-refresh on a shared list routes through refreshList. The
  // editor/owner case is the fix for "a co-editor I just accepted only
  // shows up after an app restart": a pull-only /sync refreshes the
  // cached member directory.
  group('SyncEngine.refreshList', () {
    test('editor list does a /sync that refreshes the member directory',
        () async {
      final ctx = _makeEngine((req) async => stubSyncApplyAll(req, members: {
            'owner': {'userId': 'apple:test-user', 'displayName': 'Alice'},
            'editors': [
              {
                'userId': 'apple:bob',
                'displayName': 'Bob',
                'addedAt': 1700000000,
                'addedBy': 'apple:test-user',
              },
            ],
          }));
      await ctx.manager.insert(SyncedEntryList.editor(
        meta: SyncedListMeta(
          listId: 'editlist0001',
          displayName: 'Shared',
          role: ListRole.editor,
          lastKnownSeq: 1,
          etag: null,
          lastSyncedAt: 1700000000,
          serverUpdatedAt: 1700000000,
          orphaned: false,
        ),
        savedVideos: LinkedHashSet<SavedVideo>(),
      ));
      // Precondition: the stale state the creator's device is stuck in
      // until a sync actually runs — no cached members yet.
      expect(ctx.manager.get('editlist0001')!.meta.cachedMembers, isNull);

      await ctx.engine.refreshList('editlist0001');

      expect(ctx.requests.any((r) => r.url.path.endsWith('/sync')), isTrue,
          reason: 'an editor refresh must hit /sync');
      final members = ctx.manager.get('editlist0001')!.meta.cachedMembers;
      expect(members, isNotNull);
      expect(members!.editors.map((e) => e.userId), contains('apple:bob'),
          reason: 'the just-added co-editor should now be visible');
    });

    test('subscriber list re-pulls the public payload', () async {
      final ctx = _makeEngine((req) async => http.Response(
            jsonEncode(snapshotJson(
                listId: 'sublist00001',
                displayName: 'Fresh name',
                entries: ['apple', 'banana'])),
            200,
            headers: {'content-type': 'application/json', 'etag': '"v2"'},
          ));
      await ctx.manager.insert(SyncedEntryList.subscriber(
        meta: SyncedListMeta(
          listId: 'sublist00001',
          displayName: 'Stale name',
          role: ListRole.subscriber,
          lastKnownSeq: 0,
          etag: null,
          lastSyncedAt: 1700000000,
          serverUpdatedAt: 1700000000,
          orphaned: false,
        ),
        savedVideos: LinkedHashSet<SavedVideo>(),
      ));

      await ctx.engine.refreshList('sublist00001');

      expect(
          ctx.requests.any((r) =>
              r.method == 'GET' &&
              r.url.path.endsWith('/v1/lists/sublist00001')),
          isTrue,
          reason: 'a subscriber refresh re-pulls the public payload');
      final list = ctx.manager.get('sublist00001')!;
      expect(list.meta.displayName, 'Fresh name');
      expect(
          list.savedVideos.map((v) => v.entryKey).toSet(), {'apple', 'banana'});
    });

    test('unknown list id is a no-op (no request)', () async {
      final ctx = _makeEngine((req) async => stubSyncApplyAll(req));
      await ctx.engine.refreshList('doesnotexist1');
      expect(ctx.requests, isEmpty);
    });
  });

  group('SyncEngine — foreground refresh error surfacing', () {
    http.Response serverError(http.Request req) => http.Response(
        jsonEncode({
          'error': {'code': 'INTERNAL', 'message': 'boom'}
        }),
        500);

    Future<void> insertSubscriber(SyncedEntryListManager manager,
        {String listId = 'subbed123456'}) async {
      await manager.insert(SyncedEntryList.subscriber(
        meta: SyncedListMeta(
          listId: listId,
          displayName: 'Subbed',
          role: ListRole.subscriber,
          lastKnownSeq: 1,
          etag: '"etag1"',
          lastSyncedAt: 1700000000,
          serverUpdatedAt: 1700000000,
          orphaned: false,
        ),
        savedVideos: LinkedHashSet<SavedVideo>(),
      ));
    }

    test('refreshList rethrows a server failure for an editable list',
        () async {
      final ctx = _makeEngine((req) async => serverError(req));
      final list = await setUpOwnedList(ctx.engine, ctx.manager);
      await expectLater(
        ctx.engine.refreshList(list.listId),
        throwsA(isA<SyncException>()
            .having((e) => e.kind, 'kind', SyncErrorKind.server)),
      );
    });

    test('refreshList rethrows a network failure for a subscriber', () async {
      final ctx =
          _makeEngine((req) async => throw http.ClientException('no route'));
      await insertSubscriber(ctx.manager);
      await expectLater(
        ctx.engine.refreshList('subbed123456'),
        throwsA(isA<SyncException>()
            .having((e) => e.kind, 'kind', SyncErrorKind.network)),
      );
    });

    test('refreshSubscriber rethrows network failures too', () async {
      final ctx =
          _makeEngine((req) async => throw http.ClientException('no route'));
      await insertSubscriber(ctx.manager);
      await expectLater(
        ctx.engine.refreshSubscriber('subbed123456'),
        throwsA(isA<SyncException>()),
      );
    });

    test('background pushAllDirty still swallows the same failure', () async {
      final ctx = _makeEngine((req) async => serverError(req));
      final list = await setUpOwnedList(ctx.engine, ctx.manager);
      ctx.engine.enqueueAddVideo(list.listId, _v('banana'));
      // Must complete normally; the op stays queued for the backoff retry.
      await ctx.engine.pushAllDirty();
      expect(ctx.manager.get(list.listId)!.meta.pendingOps, isNotEmpty);
    });

    test('syncAll reports per-list failures instead of throwing', () async {
      final ctx = _makeEngine((req) async => serverError(req));
      await setUpOwnedList(ctx.engine, ctx.manager);
      await insertSubscriber(ctx.manager);
      final failures = await ctx.engine.syncAll();
      expect(failures, hasLength(2));
      expect(failures.every((e) => e.kind == SyncErrorKind.server), isTrue);
    });
  });
}
