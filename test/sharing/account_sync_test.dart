import 'package:dictionarylib/globals.dart';
import 'package:dictionarylib/lists_service.dart';
import 'package:dictionarylib/sharing/account_sync.dart';
import 'package:dictionarylib/sharing/account_sync_state.dart';
import 'package:dictionarylib/sharing/sync_api.dart';
import 'package:dictionarylib/sharing/sync_clock.dart';
import 'package:dictionarylib/sharing/synced_entry_list.dart';
import 'package:flutter_test/flutter_test.dart';

import '../_helpers.dart';
import '../_recording_prefs.dart';
import '_account_sync_harness.dart';
import '_fake_account_server.dart';

/// The sign-in merge (section 5.4 of the plan) and the controller around it,
/// against the in-memory server in `_fake_account_server.dart`.
void main() {
  late FakeAccountServer server;

  setUpAll(installFakeSecureStorage);

  setUp(() {
    seedDictionary(const []);
    server = FakeAccountServer();
  });

  tearDown(() {
    // Put the active device away so its timers die with it.
    TestDevice(server, 'none').deactivate();
    debugSyncClockOffsetSeconds = 0;
  });

  Future<TestDevice> freshDevice(String name) async {
    final d = TestDevice(server, name);
    await d.activate();
    return d;
  }

  group('merge', () {
    test('the default list merges into the account default', () async {
      final defaultId = server.createAccountList(
        'alice',
        'Favourites',
        entries: [
          ['a', videoFor('a')],
          ['b', videoFor('b')],
        ],
        isDefault: true,
      );
      final phone = await freshDevice('phone');
      final fav = userEntryListManager.getEntryLists()[kDefaultListKey]!;
      await fav.addVideo(video('b'));
      await fav.addVideo(video('c'));

      await phone.signIn('alice');
      await phone.settle();

      final w = sharing.lists.ownerForSourceKey(kDefaultListKey)!;
      expect(w.listId, defaultId);
      expect(w.meta.visibility, listVisibilityPrivate);
      expect(fav.savedVideos.map((v) => v.entryKey), ['a', 'b', 'c']);
      expect(server.entryKeys(defaultId), ['a', 'b', 'c']);
      expect(server.liveRows('alice').length, 1);
      expect(sharing.accountSync.state!.mergePhase, MergePhase.done);
      expect(phone.notices.whereType<MergeCompletedNotice>(), isNotEmpty);
    });

    test(
      'a device default becomes the account default when it has none',
      () async {
        final phone = await freshDevice('phone');
        await userEntryListManager.getEntryLists()[kDefaultListKey]!.addVideo(
          video('a'),
        );
        await phone.signIn('alice');
        await phone.settle();
        final rows = server.liveRows('alice');
        expect(rows.length, 1);
        expect(rows.single['isDefault'], isTrue);
        expect(rows.single['name'], 'Favourites');
        expect(server.entryKeys(rows.single['listId'] as String), ['a']);
      },
    );

    test(
      'same-name lists merge: case, whitespace and underscores aside',
      () async {
        final petsId = server.createAccountList(
          'alice',
          '  Pet   Animals ',
          entries: [
            ['dog', videoFor('dog')],
          ],
        );
        final phone = await freshDevice('phone');
        await phone.addLocalList('pet animals', ['cat']);
        await phone.signIn('alice');
        await phone.settle();
        final w = sharing.lists.ownerForSourceKey('pet_animals_words')!;
        expect(w.listId, petsId);
        expect(server.entryKeys(petsId), ['dog', 'cat']);
        expect(
          server.liveRows('alice').where((r) => r['listId'] == petsId).length,
          1,
        );
      },
    );

    test('two lists called Pets stay two lists', () async {
      // The account's default list is called Pets; the device has a
      // Favourites default and a list of its own called Pets.
      final accountPets = server.createAccountList(
        'alice',
        'Pets',
        entries: [
          ['dog', videoFor('dog')],
        ],
        isDefault: true,
      );
      final phone = await freshDevice('phone');
      await phone.addLocalList('Pets', ['cat']);
      await phone.signIn('alice');
      await phone.settle();

      // The device default merged into the account default (Pets); the
      // device's own Pets became a list of its own.
      expect(
        sharing.lists.ownerForSourceKey(kDefaultListKey)!.listId,
        accountPets,
      );
      final own = sharing.lists.ownerForSourceKey('Pets_words')!;
      expect(own.listId, isNot(accountPets));
      final pets = server.liveRows('alice').where((r) => r['name'] == 'Pets');
      expect(pets.length, 2);
      expect(server.entryKeys(own.listId), ['cat']);
      expect(server.entryKeys(accountPets), ['dog']);
    });

    test('a list over 5000 signs stays on the device', () async {
      final phone = await freshDevice('phone');
      final big = await phone.addLocalList('Huge', []);
      for (var i = 0; i <= maxEntriesPerPrivateList; i++) {
        big.savedVideos.add(video('w$i'));
      }
      await big.write();
      await phone.signIn('alice');
      await phone.settle();
      expect(sharing.lists.ownerForSourceKey('Huge_words'), isNull);
      expect(
        sharing.accountSync.unsyncableReason('Huge_words'),
        UnsyncableReason.tooLarge,
      );
      expect(server.liveRows('alice').map((r) => r['name']), ['Favourites']);
      // No snackbar: My lists says so on the list's row instead.
      expect(phone.notices, everyElement(isA<MergeCompletedNotice>()));
      // It's shown last.
      expect(userEntryListManager.getEntryLists().keys.last, 'Huge_words');
    });

    test('the account order first, then the lists this device made', () async {
      final x = server.createAccountList('alice', 'X', isDefault: true);
      final y = server.createAccountList('alice', 'Y');
      final phone = await freshDevice('phone');
      await phone.addLocalList('B', ['b']);
      await phone.addLocalList('A', ['a']);
      await phone.signIn('alice');
      await phone.settle();
      final rows = server.liveRows('alice');
      expect(rows.map((r) => r['name']), ['X', 'Y', 'B', 'A']);
      expect(rows.first['listId'], x);
      expect(rows[1]['listId'], y);
      // The device's lists in the same order (its default merged into X).
      expect(phone.localLists().keys, ['X', 'Y', 'B', 'A']);
    });

    test('an account with only lists shared before account sync keeps the '
        "device's order", () async {
      // An upgrade: the old build shared Birds (and another device shared
      // Fish) under this account, which has no default list yet, so its
      // order is only the order things were shared in.
      final phone = await freshDevice('phone');
      await sharedPreferences.setBool(KEY_ACCOUNT_SYNC_KNOB, false);
      await phone.addLocalList('Animals', ['cat']);
      await phone.addLocalList('Birds', ['owl']);
      await phone.signIn('alice');
      server.createAccountList('alice', 'Fish', visibility: 'shared');
      await listsService.shareList(
        sourceList: userEntryListManager.getEntryLists()['Birds_words']!,
        displayName: 'Birds',
        sessionToken: phone.token!,
      );
      expect(phone.localLists().keys, ['Favourites', 'Animals', 'Birds']);

      await sharedPreferences.setBool(KEY_ACCOUNT_SYNC_KNOB, true);
      await phone.settle();
      expect(phone.localLists().keys, [
        'Favourites',
        'Animals',
        'Birds',
        'Fish',
      ]);
      expect(server.liveRows('alice').map((r) => r['name']), [
        'Favourites',
        'Animals',
        'Birds',
        'Fish',
      ]);
      expect(server.liveRows('alice').first['isDefault'], isTrue);
    });

    test('account lists arriving with names already taken', () async {
      // Two lists called MyList on the account, and one called "search for",
      // whose key is a setting's.
      final first = server.createAccountList(
        'alice',
        'MyList',
        entries: [
          ['apple', videoFor('apple')],
        ],
      );
      final second = server.createAccountList(
        'alice',
        'MyList',
        entries: [
          ['pear', videoFor('pear')],
        ],
      );
      server.createAccountList(
        'alice',
        'search for',
        entries: [
          ['fig', videoFor('fig')],
        ],
      );
      final phone = await freshDevice('phone');
      await phone.addLocalList('MyList', ['cherry']);
      await phone.signIn('alice');
      await phone.settle();
      expect(sharing.lists.ownerForSourceKey('MyList_words')!.listId, first);
      final lists = userEntryListManager.getEntryLists();
      expect(sharing.lists.ownerForSourceKey('MyList_2_words')!.listId, second);
      expect(lists['MyList_words']!.savedVideos.map((v) => v.entryKey), [
        'apple',
        'cherry',
      ]);
      expect(lists['MyList_2_words']!.savedVideos.map((v) => v.entryKey), [
        'pear',
      ]);
      expect(sharedPreferences.get('search_for_words'), isNull);
      expect(lists['search_for_2_words']!.getName(), 'search for');
    });

    test('a second device gets every list with its signs', () async {
      final phone = await freshDevice('phone');
      await phone.addLocalList('Animals', ['cat', 'dog']);
      await userEntryListManager.getEntryLists()[kDefaultListKey]!.addVideo(
        video('hello'),
      );
      await phone.signIn('alice');
      await phone.settle();

      final tablet = await freshDevice('tablet');
      await tablet.signIn('alice');
      await tablet.settle();
      expect(tablet.localLists(), {
        'Favourites': ['hello'],
        'Animals': ['cat', 'dog'],
      });
    });
  });

  group('controller', () {
    test('kicks while a cycle runs fold into one more', () async {
      final phone = await freshDevice('phone');
      await phone.signIn('alice');
      await phone.settle();
      server.log.clear();
      await Future.wait([
        sharing.accountSync.kick(SyncReason.pullToRefresh),
        sharing.accountSync.kick(SyncReason.pullToRefresh),
        sharing.accountSync.kick(SyncReason.pullToRefresh),
      ]);
      final rounds = server.log
          .where((l) => l == 'POST /v1/account/sync')
          .length;
      expect(rounds, lessThanOrEqualTo(2));
    });

    test(
      'the kill switch pauses for an hour; pull to refresh still tries',
      () async {
        final phone = await freshDevice('phone');
        await phone.signIn('alice');
        await phone.settle();
        server.accountSyncDisabled = true;
        await sharing.accountSync.kick(SyncReason.pullToRefresh);
        final st = sharing.accountSync.state!;
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        expect(st.pausedUntil, closeTo(now + 3600, 5));
        expect(sharing.accountSync.status, AccountSyncStatus.paused);
        server.log.clear();
        await sharing.accountSync.kick(SyncReason.resumed);
        expect(server.log, isEmpty);
        server.accountSyncDisabled = false;
        await sharing.accountSync.kick(SyncReason.pullToRefresh);
        expect(sharing.accountSync.status, AccountSyncStatus.synced);
      },
    );

    test('a network failure is reported as waiting for a connection', () async {
      final phone = await freshDevice('phone');
      await phone.signIn('alice');
      await phone.settle();
      server.failBefore = (_) => true;
      await sharing.accountSync.kick(SyncReason.pullToRefresh);
      expect(
        sharing.accountSync.status,
        AccountSyncStatus.waitingForConnection,
      );
      server.failBefore = null;
      await sharing.accountSync.kick(SyncReason.pullToRefresh);
      expect(sharing.accountSync.status, AccountSyncStatus.synced);
    });

    test('signing out keeps every list and drops the account state', () async {
      final phone = await freshDevice('phone');
      await phone.addLocalList('Animals', ['cat']);
      await phone.signIn('alice');
      await phone.settle();
      expect(sharing.lists.ownedLists, isNotEmpty);
      await sharing.signOut();
      expect(sharing.lists.ownedLists, isEmpty);
      expect(sharedPreferences.getString(KEY_ACCOUNT_SYNC_STATE), isNull);
      expect(phone.localLists()['Animals'], ['cat']);
      // Signing in again links them again, without duplicating anything.
      phone.token = null;
      await phone.signIn('alice');
      await phone.settle();
      expect(server.liveRows('alice').map((r) => r['name']), [
        'Favourites',
        'Animals',
      ]);
    });

    test('signing out while the first merge waits on the network leaves '
        'nothing of the account behind', () async {
      // A list on the account that the merge would install here.
      server.createAccountList(
        'alice',
        'Shared elsewhere',
        entries: [
          ['dog', videoFor('dog')],
        ],
        visibility: 'shared',
      );
      final phone = await freshDevice('phone');
      await phone.addLocalList('Animals', ['cat']);
      server.net.blackhole();
      await phone.signIn('alice');
      while (server.net.held == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      await sharing.signOut();
      // The held requests go through now, the signed-out session's with
      // them.
      server.net.up();
      await sharing.accountSync.kick(SyncReason.pullToRefresh);
      await sharing.engine.pushAllDirty();
      expect(sharing.auth.store.current, isNull);
      expect(sharing.accountSync.state, isNull);
      expect(sharedPreferences.getString(KEY_ACCOUNT_SYNC_STATE), isNull);
      expect(sharing.lists.editableLists, isEmpty);
      expect(phone.localLists().keys, ['Favourites', 'Animals']);
    });

    test('signing straight back in syncs, even with an identical token (the '
        'Worker can mint one: same person, same second)', () async {
      final phone = TestDevice(
        server,
        'phone',
        mintToken: (u) async {
          server.tokens['same-token'] = u;
          return 'same-token';
        },
      );
      await phone.activate();
      await phone.addLocalList('Animals', ['cat']);
      await phone.signIn('alice');
      await phone.settle();
      await sharing.signOut();
      expect(sharing.lists.ownedLists, isEmpty);
      await phone.signIn('alice');
      await phone.settle();
      expect(sharing.accountSync.state?.mergeDone, isTrue);
      expect(sharing.lists.ownerForSourceKey('Animals_words'), isNotNull);
    });

    test(
      'another account signing in starts again and merges into it',
      () async {
        final phone = await freshDevice('phone');
        await phone.addLocalList('Animals', ['cat']);
        await phone.signIn('alice');
        await phone.settle();
        // Bob signs in on the same device without Alice signing out (her
        // session expired, say).
        await phone.signIn('bob');
        await phone.settle();
        expect(sharing.accountSync.state!.userId, 'bob');
        expect(server.liveRows('bob').map((r) => r['name']), [
          'Favourites',
          'Animals',
        ]);
        // Alice's account is untouched.
        expect(server.liveRows('alice').length, 2);
        final bobsAnimals = sharing.lists.ownerForSourceKey('Animals_words')!;
        expect(server.lists[bobsAnimals.listId]!['owner'], 'bob');
      },
    );

    test(
      'a new account incarnation (deleted elsewhere) starts again',
      () async {
        final phone = await freshDevice('phone');
        await phone.addLocalList('Animals', ['cat']);
        await phone.signIn('alice');
        await phone.settle();
        // The account was deleted on another device and a new one made.
        server.accounts.remove('alice');
        server.lists.clear();
        await phone.settle();
        expect(server.liveRows('alice').map((r) => r['name']), [
          'Favourites',
          'Animals',
        ]);
        expect(phone.localLists()['Animals'], ['cat']);
      },
    );
  });

  group('lists', () {
    late TestDevice phone;
    late TestDevice tablet;

    Future<void> twoDevices() async {
      phone = await freshDevice('phone');
      await phone.addLocalList('Animals', ['cat', 'dog']);
      await phone.signIn('alice');
      await phone.settle();
      tablet = await freshDevice('tablet');
      await tablet.signIn('alice');
      await tablet.settle();
    }

    test('delete removes it here and everywhere', () async {
      await twoDevices();
      await phone.activate();
      final animals = userEntryListManager.getEntryLists()['Animals_words']!;
      final id = sharing.lists.ownerForSourceKey('Animals_words')!.listId;
      expect(listsService.canDelete(animals), isTrue);
      await listsService.deleteList(animals);
      expect(userEntryListManager.getEntryLists()['Animals_words'], isNull);
      await phone.settle();
      expect(server.lists[id]!['tombstoned'], isTrue);
      await tablet.settle();
      expect(tablet.localLists().containsKey('Animals'), isFalse);
    });

    test('a list deleted elsewhere goes here too when the edits here are '
        'older than the delete', () async {
      await twoDevices();
      // The tablet edits offline, a minute before the delete by its clock...
      await tablet.activate();
      server.failBefore = (_) => true;
      debugSyncClockOffsetSeconds = -60;
      await sharing.lists
          .ownerForSourceKey('Animals_words')!
          .addVideo(video('owl'));
      debugSyncClockOffsetSeconds = 0;
      await sharing.engine.pushAllDirty();
      server.failBefore = null;
      tablet.deactivate();
      // ...and the phone deletes it.
      await phone.activate();
      await listsService.deleteList(
        userEntryListManager.getEntryLists()['Animals_words']!,
      );
      await phone.settle();
      await tablet.settle();
      expect(tablet.localLists().containsKey('Animals'), isFalse);
      expect(sharing.lists.ownerForSourceKey('Animals_words'), isNull);
      expect(server.liveRows('alice').map((r) => r['name']), ['Favourites']);
      expect(tablet.notices, everyElement(isA<MergeCompletedNotice>()));
    });

    test('a list deleted elsewhere comes back everywhere when the edits here '
        'are newer than the delete', () async {
      await twoDevices();
      final id = sharing.lists.ownerForSourceKey('Animals_words')!.listId;
      await tablet.activate();
      server.failBefore = (_) => true;
      debugSyncClockOffsetSeconds = 60;
      await sharing.lists
          .ownerForSourceKey('Animals_words')!
          .addVideo(video('owl'));
      debugSyncClockOffsetSeconds = 0;
      await sharing.engine.pushAllDirty();
      server.failBefore = null;
      tablet.deactivate();
      await phone.activate();
      await listsService.deleteList(
        userEntryListManager.getEntryLists()['Animals_words']!,
      );
      await phone.settle();
      expect(phone.localLists().containsKey('Animals'), isFalse);
      await tablet.settle();
      // Restored, with the edit, under the same id.
      expect(tablet.localLists()['Animals'], ['cat', 'dog', 'owl']);
      final w = sharing.lists.ownerForSourceKey('Animals_words')!;
      expect(w.listId, id);
      expect(w.meta.orphaned, isFalse);
      expect(w.meta.pendingOps, isEmpty);
      expect(server.entryKeys(id), ['cat', 'dog', 'owl']);
      expect(server.lists[id]!['tombstoned'], isFalse);
      expect(
        server.liveRows('alice').where((r) => r['name'] == 'Animals'),
        hasLength(1),
      );
      // And back on the phone.
      await phone.settle();
      expect(phone.localLists()['Animals'], ['cat', 'dog', 'owl']);
      expect(tablet.notices, everyElement(isA<MergeCompletedNotice>()));
    });

    test(
      'a list gone from the account altogether (purged) stays here as a '
      'list of its own when it has unsent edits, and goes when not',
      () async {
        await twoDevices();
        await tablet.activate();
        await tablet.addLocalList('Birds', ['owl']);
        await tablet.settle();
        final animals = sharing.lists
            .ownerForSourceKey('Animals_words')!
            .listId;
        final birds = sharing.lists.ownerForSourceKey('Birds_words')!.listId;
        server.failBefore = (_) => true;
        await sharing.lists
            .ownerForSourceKey('Animals_words')!
            .addVideo(video('eel'));
        server.failBefore = null;
        tablet.deactivate();
        // Both deleted and purged, rows and all (a server rewound, say).
        for (final id in [animals, birds]) {
          server.purgeList(id);
          (server.account('alice')['directory'] as List).removeWhere(
            (r) => r['listId'] == id,
          );
        }
        await tablet.settle(rounds: 6);
        expect(tablet.localLists().containsKey('Birds'), isFalse);
        expect(tablet.localLists()['Animals'], ['cat', 'dog', 'eel']);
        // Linked again by name, as a new list.
        final again = sharing.lists.ownerForSourceKey('Animals_words')!;
        expect(again.listId, isNot(animals));
        expect(server.entryKeys(again.listId), ['cat', 'dog', 'eel']);
      },
    );

    test('410 on a list: verified with unlink, then gone here too', () async {
      await twoDevices();
      await phone.activate();
      final id = sharing.lists.ownerForSourceKey('Animals_words')!.listId;
      // Deleted on the server in a way the directory hasn't caught up with.
      server.lists[id]!['tombstoned'] = true;
      await phone.settle();
      expect(phone.localLists().containsKey('Animals'), isFalse);
      final row = server.liveRows('alice').where((r) => r['listId'] == id);
      expect(row, isEmpty);
    });

    test('three 404s: kept when the list turns out to be live', () async {
      await twoDevices();
      await phone.activate();
      final id = sharing.lists.ownerForSourceKey('Animals_words')!.listId;
      // The list answers 404 to /sync for a while (a server hiccup), but
      // /state (the unlink check) finds it.
      var fail = true;
      server.failBefore = null;
      final real = server.lists[id]!;
      server.lists.remove(id);
      for (var i = 0; i < 3; i++) {
        await sharing.engine.refreshList(id).catchError((_) {});
      }
      server.lists[id] = real;
      fail = false;
      expect(fail, isFalse);
      await phone.settle();
      final w = sharing.lists.ownerForSourceKey('Animals_words');
      expect(w, isNotNull);
      expect(w!.meta.orphaned, isFalse);
      expect(phone.localLists()['Animals'], ['cat', 'dog']);
    });

    test('share and stop sharing flip the visibility', () async {
      await twoDevices();
      await phone.activate();
      final animals = userEntryListManager.getEntryLists()['Animals_words']!;
      final w = await listsService.shareList(
        sourceList: animals,
        displayName: 'Zoo',
        sessionToken: phone.token!,
      );
      expect(w.meta.isShared, isTrue);
      expect(w.getName(), 'Zoo');
      expect(server.lists[w.listId]!['visibility'], 'shared');
      await listsService.stopSharing(w);
      expect(w.meta.isShared, isFalse);
      expect(server.lists[w.listId]!['visibility'], 'private');
      // Still linked, still on every device.
      expect(sharing.lists.ownerForSourceKey('Animals_words'), same(w));
      await tablet.settle();
      expect(tablet.localLists()['Zoo'], ['cat', 'dog']);
    });

    test('the default list cannot be deleted', () async {
      await twoDevices();
      await phone.activate();
      final fav = userEntryListManager.getEntryLists()[kDefaultListKey]!;
      expect(listsService.canDelete(fav), isFalse);
      await expectLater(listsService.deleteList(fav), throwsStateError);
    });

    test(
      'a list made while signed in links, with what was added meanwhile',
      () async {
        await twoDevices();
        await phone.activate();
        server.failBefore = (_) => true;
        final key = await listsService.createList('Birds');
        final birds = userEntryListManager.getEntryLists()[key]!;
        await listsService.writableFor(birds).addVideo(video('owl'));
        expect(sharing.accountSync.isLinking(key), isTrue);
        server.failBefore = null;
        await phone.settle();
        final w = sharing.lists.ownerForSourceKey(key)!;
        expect(server.entryKeys(w.listId), ['owl']);
        await tablet.settle();
        expect(tablet.localLists()['Birds'], ['owl']);
      },
    );

    test(
      'deleting a list still being linked deletes its server copy',
      () async {
        await twoDevices();
        await phone.activate();
        // The create lands but its answer is lost.
        server.loseResponse = (req) => req.url.path == '/v1/account/sync';
        final key = await listsService.createList('Birds');
        await sharing.accountSync.kick(SyncReason.pullToRefresh);
        server.loseResponse = null;
        expect(sharing.accountSync.isLinking(key), isTrue);
        await listsService.deleteList(
          userEntryListManager.getEntryLists()[key]!,
        );
        await phone.settle();
        expect(
          server.liveRows('alice').where((r) => r['name'] == 'Birds'),
          isEmpty,
        );
        await tablet.settle();
        expect(tablet.localLists().containsKey('Birds'), isFalse);
      },
    );

    test('a rename on one device reaches the other', () async {
      await twoDevices();
      await phone.activate();
      await listsService.renameList(
        userEntryListManager.getEntryLists()['Animals_words']!,
        'Beasts',
      );
      // Queued, so it goes with the phone's next sync.
      await phone.settle();
      await tablet.settle();
      expect(tablet.localLists().containsKey('Beasts'), isTrue);
    });

    test('a reorder on one device reaches the other', () async {
      await twoDevices();
      await phone.activate();
      await listsService.reorderLists(1, 0);
      expect(phone.localLists().keys, ['Animals', 'Favourites']);
      await phone.settle();
      await tablet.settle();
      expect(tablet.localLists().keys, ['Animals', 'Favourites']);
    });
  });

  group('follows', () {
    test('follows go both ways; a gone one waits a day', () async {
      final shared = server.createAccountList(
        'carol',
        'Carols',
        visibility: 'shared',
        entries: [
          ['x', videoFor('x')],
        ],
      );
      final other = server.createAccountList(
        'carol',
        'Other',
        visibility: 'shared',
      );
      final phone = await freshDevice('phone');
      await sharing.engine.subscribe(shared);
      await phone.signIn('alice');
      await phone.settle();
      expect(server.account('alice')['follows'], [shared]);

      // Followed on another device: followed here.
      (server.account('alice')['follows'] as List).add(other);
      (server.account('alice')['follows'] as List).add('gonelist0001');
      await phone.settle();
      expect(sharing.lists.get(other)?.meta.role, ListRole.subscriber);
      expect(sharing.accountSync.state!.followsGone.keys, ['gonelist0001']);
      server.log.clear();
      await phone.settle();
      expect(server.log.where((l) => l.contains('gonelist0001')), isEmpty);

      // Unfollowed on another device: unfollowed here.
      (server.account('alice')['follows'] as List).remove(other);
      await phone.settle();
      expect(sharing.lists.get(other), isNull);

      // Unfollowed here: unfollowed on the account.
      await listsService.unsubscribeList(sharing.lists.get(shared)!);
      await phone.settle();
      expect(server.account('alice')['follows'], ['gonelist0001']);
    });

    test('lists the person edits arrive as editor mirrors', () async {
      final edited = server.createAccountList(
        'carol',
        'Team',
        visibility: 'shared',
      );
      (server.lists[edited]!['editors'] as List).add('alice');
      final phone = await freshDevice('phone');
      await phone.signIn('alice');
      await phone.settle();
      expect(sharing.lists.get(edited)?.meta.role, ListRole.editor);
    });
  });

  group('interrupted, offline and switched-off work', () {
    int accountRequests() =>
        server.log.where((l) => l == 'POST /v1/account/sync').length;

    test('an op the account keeps answering retry waits, '
        'rather than being sent again and again', () async {
      final phone = await freshDevice('phone');
      await phone.addLocalList('Animals', ['cat']);
      await phone.addLocalList('Birds', ['owl']);
      await phone.signIn('alice');
      await phone.settle();
      server.answerRetry = (op) => op['type'] == 'reorder';
      await listsService.reorderLists(1, 3);
      final before = accountRequests();
      await sharing.accountSync.kick(SyncReason.pullToRefresh);
      expect(accountRequests() - before, lessThan(4));
      expect(
        sharing.accountSync.state!.pendingOps.map((o) => o.type),
        contains('reorder'),
      );
      server.answerRetry = null;
      await phone.settle();
      expect(sharing.accountSync.state!.pendingOps, isEmpty);
    });

    test('work done while the session has expired reaches the account '
        'when the same person signs in again', () async {
      final phone = await freshDevice('phone');
      await phone.addLocalList('Animals', ['cat']);
      await phone.addLocalList('Birds', ['owl']);
      await phone.signIn('alice');
      await phone.settle();
      final birds = sharing.lists.ownerForSourceKey('Birds_words')!.listId;
      // The session expires (the account answers 401).
      server.tokens.remove(phone.token);
      await sharing.accountSync.kick(SyncReason.pullToRefresh);
      expect(sharing.auth.store.current, isNull);
      // Meanwhile: a reorder and a delete.
      await listsService.reorderLists(1, 0);
      expect(
        listsService.canDelete(
          userEntryListManager.getEntryLists()['Birds_words']!,
        ),
        isTrue,
      );
      await listsService.deleteList(
        userEntryListManager.getEntryLists()['Birds_words']!,
      );
      final order = userEntryListManager.getEntryLists().keys.toList();
      await phone.signIn('alice');
      await phone.settle();
      expect(server.lists[birds]!['tombstoned'], isTrue);
      expect(userEntryListManager.getEntryLists().keys.toList(), order);
      final tablet = await freshDevice('tablet');
      await tablet.signIn('alice');
      await tablet.settle();
      expect(tablet.localLists().keys, ['Animals', 'Favourites']);
    });

    test('a delete killed at any point never brings the list back', () async {
      final setup = await freshDevice('setup');
      await setup.addLocalList('Birds', ['owl']);
      await setup.signIn('alice');
      await setup.settle();
      final birdsId = sharing.lists.ownerForSourceKey('Birds_words')!.listId;
      setup.deactivate();
      final initial = setup.prefs;
      final token = setup.token!;

      final snapshots = <FakeAccountServer>[];
      final server0 = server.clone();
      final original = TestDevice(server, 'original', prefs: initial)
        ..token = token
        ..userId = 'alice';
      await original.activate(onWrite: () => snapshots.add(server.clone()));
      await listsService.deleteList(
        userEntryListManager.getEntryLists()['Birds_words']!,
      );
      await original.settle();
      final writes = List.of(original.store!.writes);
      final finalServer = server.clone();
      original.deactivate();

      for (var k = 0; k <= writes.length; k++) {
        for (final serverAfter in [false, true]) {
          final base = serverAfter
              ? (k == writes.length ? finalServer : snapshots[k])
              : (k == 0 ? server0 : snapshots[k - 1]);
          final s = base.clone();
          final label =
              'killed after $k of ${writes.length} writes, '
              'server ${serverAfter ? 'after' : 'before'}';
          final d =
              TestDevice(s, label, prefs: replayWrites(initial, writes, k))
                ..token = token
                ..userId = 'alice';
          await d.settle(rounds: 6);
          final live = s
              .liveRows('alice')
              .where((r) => r['name'] == 'Birds')
              .toList();
          final here = d.localLists().containsKey('Birds');
          if (here) {
            // The delete never started: the list is as it was.
            expect(live, hasLength(1), reason: label);
            expect(live.single['listId'], birdsId, reason: label);
            expect(
              sharing.lists.ownerForSourceKey('Birds_words')?.listId,
              birdsId,
              reason: label,
            );
          } else {
            expect(live, isEmpty, reason: '$label: back on the account');
          }
          d.deactivate();
        }
      }
    });

    test('a list deleted while being linked goes from the account too, '
        'even if the app dies before the link is forgotten', () async {
      final phone = await freshDevice('phone');
      await phone.signIn('alice');
      await phone.settle();
      // A new list whose create reaches the account, the answer lost.
      server.loseResponse = (req) =>
          req.url.path == '/v1/account/sync' &&
          req.body.contains('"createList"');
      await listsService.createList('Fish');
      await sharing.accountSync.kick(SyncReason.pullToRefresh);
      server.loseResponse = null;
      expect(
        server.liveRows('alice').where((r) => r['name'] == 'Fish'),
        hasLength(1),
      );
      expect(sharing.lists.ownerForSourceKey('Fish_words'), isNull);
      // The person deletes it and the app dies straight after the local
      // delete.
      await userEntryListManager.deleteEntryList('Fish_words');
      phone.deactivate();
      await phone.settle();
      expect(
        server.liveRows('alice').where((r) => r['name'] == 'Fish'),
        isEmpty,
      );
      expect(phone.localLists().containsKey('Fish'), isFalse);
    });

    test('a sign-out killed at any point leaves every list once', () async {
      final setup = await freshDevice('setup');
      await setup.addLocalList('Animals', ['cat']);
      await setup.addLocalList('Birds', ['owl']);
      await setup.signIn('alice');
      await setup.settle();
      setup.deactivate();
      final initial = setup.prefs;
      final token = setup.token!;

      final original = TestDevice(server, 'original', prefs: initial)
        ..token = token
        ..userId = 'alice';
      await original.activate(onWrite: () {});
      await sharing.signOut();
      final writes = List.of(original.store!.writes);
      original.deactivate();
      expect(writes, isNotEmpty);

      for (var k = 0; k <= writes.length; k++) {
        final s = server.clone();
        final label = 'killed after $k of ${writes.length} writes';
        // Still signed in (the session goes last).
        final d = TestDevice(s, label, prefs: replayWrites(initial, writes, k))
          ..token = token
          ..userId = 'alice';
        await d.settle(rounds: 6);
        expect(d.localLists().keys.toList()..sort(), [
          'Animals',
          'Birds',
          'Favourites',
        ], reason: label);
        expect(s.liveRows('alice').map((r) => r['name']).toList()..sort(), [
          'Animals',
          'Birds',
          'Favourites',
        ], reason: '$label: account');
        d.deactivate();
      }
    });

    test(
      'a row whose list has gone is checked, and the list linked anew',
      () async {
        final fishId = server.createAccountList(
          'alice',
          'Fish',
          entries: [
            ['eel', videoFor('eel')],
          ],
        );
        server.purgeList(fishId);
        final phone = await freshDevice('phone');
        await phone.addLocalList('Fish', ['cod']);
        await phone.signIn('alice');
        await phone.settle(rounds: 6);
        final live = server.liveRows('alice').where((r) => r['name'] == 'Fish');
        expect(live, hasLength(1));
        expect(live.single['listId'], isNot(fishId));
        expect(phone.localLists()['Fish'], ['cod']);
        expect(
          sharing.lists.ownerForSourceKey('Fish_words')?.listId,
          live.single['listId'],
        );
      },
    );

    test(
      'a list kept here for its size syncs once it is small enough',
      () async {
        final phone = await freshDevice('phone');
        final big = await phone.addLocalList('Huge', []);
        for (var i = 0; i <= maxEntriesPerPrivateList; i++) {
          big.savedVideos.add(video('w$i'));
        }
        await big.write();
        await phone.signIn('alice');
        await phone.settle();
        expect(
          sharing.accountSync.unsyncableReason('Huge_words'),
          UnsyncableReason.tooLarge,
        );
        await big.removeVideo(video('w0'));
        await phone.settle();
        expect(sharing.accountSync.unsyncableReason('Huge_words'), isNull);
        expect(sharing.lists.ownerForSourceKey('Huge_words'), isNotNull);
      },
    );

    test(
      'edits to a list waiting for the account\'s verdict are kept',
      () async {
        final phone = await freshDevice('phone');
        await phone.addLocalList('Animals', ['cat']);
        await phone.signIn('alice');
        await phone.settle();
        final id = sharing.lists.ownerForSourceKey('Animals_words')!.listId;
        // Deleted on the server; the device finds out from the list (410)
        // while the account can't be reached.
        server.lists[id]!['tombstoned'] = true;
        server.failBefore = (req) => req.url.path == '/v1/account/sync';
        await sharing.engine.refreshList(id).catchError((_) {});
        final w = sharing.lists.ownerForSourceKey('Animals_words')!;
        expect(w.meta.orphaned, isTrue);
        await userEntryListManager.getEntryLists()['Animals_words']!.addVideo(
          video('dog'),
        );
        server.failBefore = null;
        await phone.settle();
        // Gone from the account, kept here with the new sign.
        expect(phone.localLists()['Animals'], ['cat', 'dog']);
      },
    );

    test('with account sync switched off, a list shared the old way and '
        'deleted on the server goes back to a plain list', () async {
      final phone = await freshDevice('phone');
      await sharedPreferences.setBool(KEY_ACCOUNT_SYNC_KNOB, false);
      await phone.addLocalList('Animals', ['cat']);
      await phone.signIn('alice');
      final w = await listsService.shareList(
        sourceList: userEntryListManager.getEntryLists()['Animals_words']!,
        displayName: 'Zoo',
        sessionToken: phone.token!,
      );
      expect(sharing.accountSync.state, isNull);
      server.lists[w.listId]!['tombstoned'] = true;
      await sharing.engine.refreshList(w.listId).catchError((_) {});
      expect(sharing.lists.ownerForSourceKey('Animals_words'), isNull);
      expect(phone.localLists()['Animals'], ['cat']);
    });

    test('with account sync switched off, sharing a list already on the '
        'account shares it rather than a copy', () async {
      final phone = await freshDevice('phone');
      await phone.addLocalList('Animals', ['cat']);
      await phone.signIn('alice');
      await phone.settle();
      final w = sharing.lists.ownerForSourceKey('Animals_words')!;
      final listsBefore = server.lists.length;
      await sharedPreferences.setBool(KEY_ACCOUNT_SYNC_KNOB, false);
      final shared = await listsService.shareList(
        sourceList: userEntryListManager.getEntryLists()['Animals_words']!,
        displayName: 'Zoo',
        sessionToken: phone.token!,
      );
      expect(shared.listId, w.listId);
      expect(server.lists.length, listsBefore);
      expect(server.lists[w.listId]!['visibility'], 'shared');
    });
  });

  group('last intent wins, offline first', () {
    int requests() => server.log.length;

    Future<TestDevice> phoneWithAnimals() async {
      final phone = await freshDevice('phone');
      await phone.addLocalList('Animals', ['cat']);
      await phone.signIn('alice');
      await phone.settle();
      return phone;
    }

    test('a rename takes effect at once, offline, without a request', () async {
      final phone = await phoneWithAnimals();
      final w = sharing.lists.ownerForSourceKey('Animals_words')!;
      server.failBefore = (_) => true;
      final before = requests();
      await listsService.renameList(
        userEntryListManager.getEntryLists()['Animals_words']!,
        'Beasts',
      );
      expect(requests(), before, reason: 'no request on rename');
      expect(w.getName(), 'Beasts');
      expect(
        userEntryListManager.getEntryLists()['Animals_words']!.getName(),
        'Beasts',
      );
      expect(w.meta.pendingOps.map((o) => o.type), ['rename']);
      expect(
        sharing.accountSync.state!.pendingOps.map((o) => o.type),
        contains('rename'),
      );
      // Still Beasts after a failed sync and a restart.
      await sharing.accountSync.kick(SyncReason.pullToRefresh);
      phone.deactivate();
      await phone.activate();
      expect(
        sharing.lists.ownerForSourceKey('Animals_words')!.getName(),
        'Beasts',
      );
      server.failBefore = null;
      await phone.settle();
      expect(server.lists[w.listId]!['displayName'], 'Beasts');
      expect(
        server.liveRows('alice').where((r) => r['name'] == 'Beasts'),
        hasLength(1),
      );
    });

    test(
      'a queued rename is not undone by the old name echoed meanwhile',
      () async {
        final phone = await phoneWithAnimals();
        final w = sharing.lists.ownerForSourceKey('Animals_words')!;
        server.failBefore = (_) => true;
        for (var i = 0; i < 60; i++) {
          await w.addVideo(video('w$i'));
        }
        await listsService.renameSharedList(w, 'Beasts');
        // The first batch (50 ops, not the rename) goes through and echoes the
        // old name; the rest fail.
        var lists = 0;
        server.failBefore = (req) =>
            req.url.path.endsWith('/sync') &&
            !req.url.path.contains('account') &&
            ++lists > 1;
        await sharing.engine.pushAllDirty();
        expect(server.lists[w.listId]!['displayName'], 'Animals');
        expect(w.meta.pendingOps.map((o) => o.type), contains('rename'));
        expect(w.getName(), 'Beasts');
        server.failBefore = null;
        await phone.settle();
        expect(w.getName(), 'Beasts');
        expect(server.lists[w.listId]!['displayName'], 'Beasts');
      },
    );

    test('two devices renaming offline end with the later rename', () async {
      final phone = await phoneWithAnimals();
      final tablet = await freshDevice('tablet');
      await tablet.signIn('alice');
      await tablet.settle();
      final id = sharing.lists.ownerForSourceKey('Animals_words')!.listId;
      server.failBefore = (_) => true;
      // The tablet renames first in the test, but later by the clocks.
      debugSyncClockOffsetSeconds = 30;
      await listsService.renameList(
        userEntryListManager.getEntryLists()['Animals_words']!,
        'Later',
      );
      tablet.deactivate();
      await phone.activate();
      debugSyncClockOffsetSeconds = 0;
      await listsService.renameList(
        userEntryListManager.getEntryLists()['Animals_words']!,
        'Earlier',
      );
      server.failBefore = null;
      // The tablet's rename lands first, the phone's (older) second.
      await tablet.settle();
      await phone.settle();
      expect(server.lists[id]!['displayName'], 'Later');
      expect(
        sharing.lists.ownerForSourceKey('Animals_words')!.getName(),
        'Later',
      );
      expect(
        server.liveRows('alice').firstWhere((r) => r['listId'] == id)['name'],
        'Later',
      );
      await tablet.settle();
      expect(
        sharing.lists.ownerForSourceKey('Animals_words')!.getName(),
        'Later',
      );
      expect(phone.notices, everyElement(isA<MergeCompletedNotice>()));
    });

    test(
      'a rename the server refuses puts the old name back, quietly',
      () async {
        final phone = await phoneWithAnimals();
        final w = sharing.lists.ownerForSourceKey('Animals_words')!;
        server.failBefore = (_) => true;
        // Allowed while private...
        await listsService.renameSharedList(w, 'Favourites');
        expect(w.getName(), 'Favourites');
        // ...but shared from another device before it landed.
        server.lists[w.listId]!['visibility'] = 'shared';
        server.failBefore = null;
        await phone.settle();
        expect(w.getName(), 'Animals');
        expect(w.meta.pendingOps, isEmpty);
        expect(server.lists[w.listId]!['displayName'], 'Animals');
        expect(phone.notices, everyElement(isA<MergeCompletedNotice>()));
      },
    );

    test(
      'a rename made while the list was being linked reaches the account',
      () async {
        final phone = await freshDevice('phone');
        await phone.signIn('alice');
        await phone.settle();
        // A new list whose create lands on the account but whose answer is
        // lost, then renamed before the link finishes.
        server.loseResponse = (req) =>
            req.url.path == '/v1/account/sync' &&
            req.body.contains('"createList"');
        await listsService.createList('Fish');
        await sharing.accountSync.kick(SyncReason.pullToRefresh);
        server.loseResponse = null;
        expect(sharing.lists.ownerForSourceKey('Fish_words'), isNull);
        await listsService.renameList(
          userEntryListManager.getEntryLists()['Fish_words']!,
          'Sea life',
        );
        await phone.settle();
        final w = sharing.lists.ownerForSourceKey('Sea_life_words')!;
        expect(w.getName(), 'Sea life');
        expect(server.lists[w.listId]!['displayName'], 'Sea life');
        expect(
          server.liveRows('alice').map((r) => r['name']),
          containsAll(['Sea life']),
        );
        expect(
          server.liveRows('alice').where((r) => r['name'] == 'Fish'),
          isEmpty,
        );
      },
    );

    test('two devices reordering offline end with the later order', () async {
      final phone = await freshDevice('phone');
      await phone.addLocalList('Animals', ['cat']);
      await phone.addLocalList('Birds', ['owl']);
      await phone.signIn('alice');
      await phone.settle();
      final tablet = await freshDevice('tablet');
      await tablet.signIn('alice');
      await tablet.settle();
      server.failBefore = (_) => true;
      debugSyncClockOffsetSeconds = 30;
      await listsService.reorderLists(2, 0); // Birds first (later)
      final tabletOrder = tablet.localLists().keys.toList();
      tablet.deactivate();
      await phone.activate();
      debugSyncClockOffsetSeconds = 0;
      await listsService.reorderLists(1, 0); // Animals first (earlier)
      server.failBefore = null;
      await tablet.settle();
      await phone.settle();
      expect(phone.localLists().keys.toList(), tabletOrder);
      await tablet.settle();
      expect(tablet.localLists().keys.toList(), tabletOrder);
    });

    test('a rename killed at any point ends with one name, the same here and '
        'on the account', () async {
      final setup = await phoneWithAnimals();
      final id = sharing.lists.ownerForSourceKey('Animals_words')!.listId;
      setup.deactivate();
      final initial = setup.prefs;
      final token = setup.token!;
      final server0 = server.clone();
      final snapshots = <FakeAccountServer>[];
      final original = TestDevice(server, 'original', prefs: initial)
        ..token = token
        ..userId = 'alice';
      await original.activate(onWrite: () => snapshots.add(server.clone()));
      await listsService.renameList(
        userEntryListManager.getEntryLists()['Animals_words']!,
        'Beasts',
      );
      await original.settle();
      final writes = List.of(original.store!.writes);
      final finalServer = server.clone();
      original.deactivate();
      expect(finalServer.lists[id]!['displayName'], 'Beasts');
      for (var k = 0; k <= writes.length; k++) {
        for (final serverAfter in [false, true]) {
          final base = serverAfter
              ? (k == writes.length ? finalServer : snapshots[k])
              : (k == 0 ? server0 : snapshots[k - 1]);
          final s = base.clone();
          final label =
              'killed after $k of ${writes.length} writes, '
              'server ${serverAfter ? 'after' : 'before'}';
          final d =
              TestDevice(s, label, prefs: replayWrites(initial, writes, k))
                ..token = token
                ..userId = 'alice';
          await d.settle(rounds: 6);
          final w = sharing.lists.ownerForSourceKey('Animals_words');
          expect(w, isNotNull, reason: label);
          expect(w!.listId, id, reason: label);
          final name = s.lists[id]!['displayName'];
          expect(['Animals', 'Beasts'], contains(name), reason: label);
          expect(w.getName(), name, reason: '$label: same name here');
          expect(w.meta.pendingOps, isEmpty, reason: '$label: queue');
          if (k > 0) expect(name, 'Beasts', reason: label);
          d.deactivate();
        }
      }
    });

    test('restoring a list for newer edits, killed at any point, ends with '
        'the list back once, edits and all', () async {
      final phone = await phoneWithAnimals();
      final id = sharing.lists.ownerForSourceKey('Animals_words')!.listId;
      final tablet = await freshDevice('tablet');
      await tablet.signIn('alice');
      await tablet.settle();
      server.failBefore = (_) => true;
      debugSyncClockOffsetSeconds = 60;
      await sharing.lists
          .ownerForSourceKey('Animals_words')!
          .addVideo(video('owl'));
      debugSyncClockOffsetSeconds = 0;
      server.failBefore = null;
      tablet.deactivate();
      await phone.activate();
      await listsService.deleteList(
        userEntryListManager.getEntryLists()['Animals_words']!,
      );
      await phone.settle();
      phone.deactivate();
      final initial = tablet.prefs;
      final token = tablet.token!;
      final server0 = server.clone();
      final snapshots = <FakeAccountServer>[];
      final original = TestDevice(server, 'original', prefs: initial)
        ..token = token
        ..userId = 'alice';
      await original.activate(onWrite: () => snapshots.add(server.clone()));
      await original.settle();
      final writes = List.of(original.store!.writes);
      final finalServer = server.clone();
      original.deactivate();
      expect(finalServer.entryKeys(id), ['cat', 'owl']);
      for (var k = 0; k <= writes.length; k++) {
        for (final serverAfter in [false, true]) {
          final base = serverAfter
              ? (k == writes.length ? finalServer : snapshots[k])
              : (k == 0 ? server0 : snapshots[k - 1]);
          final s = base.clone();
          final label =
              'killed after $k of ${writes.length} writes, '
              'server ${serverAfter ? 'after' : 'before'}';
          final d =
              TestDevice(s, label, prefs: replayWrites(initial, writes, k))
                ..token = token
                ..userId = 'alice';
          await d.settle(rounds: 6);
          expect(d.localLists()['Animals'], ['cat', 'owl'], reason: label);
          final live = s
              .liveRows('alice')
              .where((r) => r['name'] == 'Animals')
              .toList();
          expect(live, hasLength(1), reason: '$label: once on the account');
          final w = sharing.lists.ownerForSourceKey('Animals_words');
          expect(w?.listId, live.single['listId'], reason: label);
          expect(w!.meta.orphaned, isFalse, reason: label);
          expect(w.meta.pendingOps, isEmpty, reason: label);
          expect(s.entryKeys(live.single['listId'] as String).toSet(), {
            'cat',
            'owl',
          }, reason: '$label: on the account');
          d.deactivate();
        }
      }
    });
  });

  group('a kill at any point of the merge', () {
    test('resumes to the same lists, with nothing lost or doubled', () async {
      server.createAccountList(
        'alice',
        'Favourites',
        entries: [
          ['b', videoFor('b')],
        ],
        isDefault: true,
      );
      server.createAccountList(
        'alice',
        'Animals',
        entries: [
          ['eagle', videoFor('eagle')],
        ],
      );
      final setup = await freshDevice('setup');
      await userEntryListManager.getEntryLists()[kDefaultListKey]!.addVideo(
        video('a'),
      );
      await setup.addLocalList('Animals', ['cat', 'dog']);
      await setup.addLocalList('Birds', ['owl']);
      setup.deactivate();
      final initial = setup.prefs;
      final token = server.signIn('alice');

      // The run that gets killed: every prefs write recorded, and the
      // server as it stood when each was issued.
      final server0 = server.clone();
      final snapshots = <FakeAccountServer>[];
      final original = TestDevice(server, 'original', prefs: initial)
        ..token = token
        ..userId = 'alice';
      await original.activate(onWrite: () => snapshots.add(server.clone()));
      await original.settle();
      final writes = List.of(original.store!.writes);
      final finalServer = server.clone();
      original.deactivate();
      expect(writes.length, snapshots.length);
      expect(writes.length, greaterThan(20));

      const expected = {
        'Favourites': {'a', 'b'},
        'Animals': {'cat', 'dog', 'eagle'},
        'Birds': {'owl'},
      };

      void check(TestDevice d, FakeAccountServer s, String label) {
        final local = {
          for (final e in d.localLists().entries) e.key: e.value.toSet(),
        };
        expect(local, expected, reason: '$label: device lists');
        final rows = s.liveRows('alice');
        expect(
          rows.map((r) => r['name']).toList()..sort(),
          expected.keys.toList()..sort(),
          reason: '$label: one server list per name',
        );
        for (final r in rows) {
          final id = r['listId'] as String;
          expect(
            s.entryKeys(id).toSet(),
            expected[r['name']],
            reason: '$label: server ${r['name']}',
          );
        }
        for (final key in userEntryListManager.getEntryLists().keys) {
          final w = sharing.lists.ownerForSourceKey(key);
          expect(w, isNotNull, reason: '$label: $key linked');
          expect(w!.meta.pendingOps, isEmpty, reason: '$label: $key queue');
          final row = rows.firstWhere((r) => r['listId'] == w.listId);
          expect(row['name'], w.getName(), reason: '$label: $key target');
        }
        final st = sharing.accountSync.state!;
        expect(st.mergePhase, MergePhase.done, reason: label);
        expect(st.linking, isEmpty, reason: '$label: links left');
        expect(st.pendingOps, isEmpty, reason: '$label: account queue');
      }

      for (var k = 0; k <= writes.length; k++) {
        for (final serverAfter in [false, true]) {
          final base = serverAfter
              ? (k == writes.length ? finalServer : snapshots[k])
              : (k == 0 ? server0 : snapshots[k - 1]);
          final s = base.clone();
          final label =
              'killed after $k of ${writes.length} writes, '
              'server ${serverAfter ? 'after' : 'before'}';
          final d =
              TestDevice(s, label, prefs: replayWrites(initial, writes, k))
                ..token = token
                ..userId = 'alice';
          await d.settle(rounds: 6);
          check(d, s, label);
          d.deactivate();
        }
      }
    });
  });
}
