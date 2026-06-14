import 'dart:collection';
import 'dart:convert';

import 'package:dictionarylib/entry_list.dart';
import 'package:dictionarylib/globals.dart';
import 'package:dictionarylib/saved_video.dart';
import 'package:dictionarylib/sharing/synced_entry_list.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../_helpers.dart';

SavedVideo _v(String key) =>
    SavedVideo(entryKey: key, mediaPath: videoFor(key));

/// Install an owner wrapper around a fresh local list plus a subscriber
/// mirror, returning the owner wrapper. Mirrors the direct-insert
/// pattern used by sync_engine_test.dart.
Future<SyncedEntryList> _installLists() async {
  await userEntryListManager.createEntryList('cats_words');
  final source = userEntryListManager.getEntryLists()['cats_words']!;
  await source.addVideo(_v('apple'));
  final owned = SyncedEntryList.owner(
    meta: SyncedListMeta(
      listId: 'ownedsignout',
      displayName: 'Cats',
      role: ListRole.owner,
      lastKnownSeq: 1,
      etag: null,
      lastSyncedAt: 1700000000,
      serverUpdatedAt: 1700000000,
      orphaned: false,
      sourceLocalKey: 'cats_words',
    ),
    source: source,
  );
  await sharing.lists.insert(owned);
  await sharing.lists.insert(SyncedEntryList.subscriber(
    meta: SyncedListMeta(
      listId: 'subbedsignout',
      displayName: 'Followed',
      role: ListRole.subscriber,
      lastKnownSeq: 1,
      etag: null,
      lastSyncedAt: 1700000000,
      serverUpdatedAt: 1700000000,
      orphaned: false,
    ),
    savedVideos: LinkedHashSet.of({_v('banana')}),
  ));
  return owned;
}

void main() {
  setUp(() async {
    installFakeSecureStorage();
    SharedPreferences.setMockInitialValues({});
    sharedPreferences = await SharedPreferences.getInstance();
    seedDictionary(['apple', 'banana', 'cherry']);
    userEntryListManager = UserEntryListManager.fromStartup();
  });

  group('Sharing.signOut', () {
    test('best-effort pushes queued edits under the still-valid session',
        () async {
      final requests = installFakeSharing((req) async {
        if (req.method == 'POST' && req.url.path.endsWith('/sync')) {
          return stubSyncApplyAll(req);
        }
        return http.Response('', 404);
      });
      final owned = await _installLists();
      await sharing.engine.enqueueAddVideo(owned.listId, _v('cherry'));

      await sharing.signOut();

      final syncPosts =
          requests.where((r) => r.url.path.endsWith('/sync')).toList();
      expect(syncPosts, isNotEmpty,
          reason: 'sign-out must attempt to land queued edits first');
      final body = jsonDecode(syncPosts.first.body) as Map<String, dynamic>;
      expect((body['ops'] as List).length, 1);

      // Session gone, owner/editor mirrors gone, local data + subs kept.
      expect(sharing.auth.store.current, isNull);
      expect(sharing.lists.hasList('ownedsignout'), isFalse);
      expect(userEntryListManager.getEntryLists().containsKey('cats_words'),
          isTrue);
      expect(sharing.lists.hasList('subbedsignout'), isTrue);
    });

    test('still signs out cleanly when the flush cannot reach the server',
        () async {
      installFakeSharing((req) async => throw http.ClientException('offline'));
      final owned = await _installLists();
      await sharing.engine.enqueueAddVideo(owned.listId, _v('cherry'));

      await sharing.signOut();

      expect(sharing.auth.store.current, isNull);
      expect(sharing.lists.hasList('ownedsignout'), isFalse);
      expect(sharing.lists.hasList('subbedsignout'), isTrue);
      expect(userEntryListManager.getEntryLists().containsKey('cats_words'),
          isTrue);
    });
  });
}
