/// Multi-device sync integration tests.
///
/// Runs the REAL client stack ("device A": SyncApi + AuthService +
/// SyncedEntryListManager + SyncEngine) against a REAL local worker
/// (`wrangler dev`), with a second independent identity ("device B") driving
/// the server over raw HTTP. This covers the client-side reconciliation
/// behaviour that neither the bun HTTP suite (no Dart client) nor the
/// MockClient unit suite (no real server, single stack) can see:
/// optimistic apply + pending-op replay + missedOps folding + snapshot
/// catch-up + role transitions, all against genuine server seq ordering.
///
/// Auto-skips (like the backend repo's workers/test/integration) when no
/// server is reachable. Start one from a checkout of the private backend
/// repo (a sibling of this one):
///   bash -c 'cd ../dictionary_backend/workers && bunx wrangler dev --env dev'
/// then run:
///   flutter test test/sharing/multi_device_sync_test.dart
library;

import 'dart:async';
import 'dart:io';

import 'package:dictionarylib/entry_list.dart';
import 'package:dictionarylib/globals.dart';
import 'package:dictionarylib/saved_video.dart';
import 'package:dictionarylib/sharing/auth/auth_store.dart';
import 'package:dictionarylib/sharing/sync_engine.dart';
import 'package:dictionarylib/sharing/synced_entry_list.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../_helpers.dart';
import 'multi_device_helpers.dart';

SavedVideo _v(String key) =>
    SavedVideo(entryKey: key, videoUrl: integrationVideoFor(key));

Future<void> main() async {
  // The secure-storage fake calls TestWidgetsFlutterBinding.ensureInitialized,
  // which installs an HttpOverrides that blocks real network access. Null it
  // out so the suite can reach the local worker.
  installFakeSecureStorage();
  HttpOverrides.global = null;

  if (!await integrationServerReachable()) {
    final msg = 'no server reachable at $kIntegrationBaseUrl.\nStart one in '
        'another terminal from the private backend repo:\n'
        '  cd ../dictionary_backend/workers && bunx wrangler dev --env dev';
    // CI sets REQUIRE_SERVER so a skip can't masquerade as a pass — fail
    // loudly. A plain local `flutter test` leaves it unset and skips.
    if (Platform.environment.containsKey('REQUIRE_SERVER')) {
      fail(
          '[multi-device] $msg\nREQUIRE_SERVER is set — failing not skipping.');
    }
    // ignore: avoid_print
    print('[multi-device] skipping — $msg');
    return;
  }

  late RealDeviceStack deviceA;
  late List<SyncNotification> notifications;
  late StreamSubscription<SyncNotification> notificationSub;

  /// Build a fresh device-A stack signed in as a fresh test user.
  Future<void> freshDeviceA() async {
    final session = await signInTestUser(userId: randomTestUserId());
    deviceA = RealDeviceStack.install(session);
    notifications = [];
    notificationSub = deviceA.engine.notifications.listen(notifications.add);
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    sharedPreferences = await SharedPreferences.getInstance();
    resetClientIdCacheForTesting();
    seedDictionary(const []);
    userEntryListManager = UserEntryListManager.fromStartup();
    await freshDeviceA();
  });

  tearDown(() async {
    await notificationSub.cancel();
    deviceA.dispose();
    // Let any fire-and-forget engine work (post-demote pull, orphan cleanup)
    // settle before the framework tears the test down.
    await Future<void>.delayed(const Duration(milliseconds: 300));
  });

  tearDownAll(wipeTestData);

  /// Owner-side helper: device A shares a local list and returns the wrapper.
  Future<SyncedEntryList> shareOwnedList(
      String localKey, List<String> keys, String displayName) async {
    await userEntryListManager.createEntryList(localKey);
    final source = userEntryListManager.getEntryLists()[localKey]!;
    for (final k in keys) {
      await source.addVideo(_v(k));
    }
    return deviceA.engine.createOwned(
      displayName: displayName,
      source: source,
      sessionToken: deviceA.auth.store.current!.sessionToken,
    );
  }

  /// Editor-side helper: device B owns a list, device A joins as editor.
  Future<(HttpDevice owner, String listId, SyncedEntryList mirror)>
      joinAsEditor({List<String> initialKeys = const []}) async {
    final owner = await HttpDevice.signIn();
    final listId = await owner.createList(
      displayName: 'B owned list',
      entries: [
        for (final k in initialKeys)
          {'entry': k, 'video': integrationVideoFor(k)}
      ],
    );
    final invite = await owner.createInvite(listId);
    final mirror =
        await deviceA.engine.acceptInvite(listId: listId, token: invite);
    return (owner, listId, mirror);
  }

  group('multi-device convergence', () {
    test('another editor’s edits reach device A on refresh', () async {
      final owned = await shareOwnedList('conv_words', ['apple'], 'Converge');
      final listId = owned.listId;

      // Device B joins as an editor and pushes an add.
      final b = await HttpDevice.signIn();
      final invite = await deviceA.engine.createInvite(listId);
      await b.acceptInvite(listId, invite.token);
      await b.sync(listId, ['add:banana']);

      await deviceA.engine.refreshList(listId);

      expect(owned.savedVideos, contains(_v('banana')));
      expect(owned.meta.pendingOps, isEmpty);
      // Both sides agree with the server.
      expect(await b.entryKeys(listId), unorderedEquals(['apple', 'banana']));
    });

    test(
        'concurrent offline edit + foreign op converge through server '
        'seq order', () async {
      final (owner, listId, mirror) = await joinAsEditor(initialKeys: ['base']);

      // Device A removes `base` offline (pending op, no flush yet) while the
      // owner concurrently adds `extra` server-side.
      await mirror.removeVideo(_v('base'));
      expect(mirror.meta.pendingOps, hasLength(1));
      await owner.sync(listId, ['add:extra']);

      // A's flush carries its op at a stale cursor; the server applies it
      // after the owner's add and returns that add as a missedOp.
      await deviceA.engine.pushAllDirty();

      expect(mirror.meta.pendingOps, isEmpty);
      expect(mirror.savedVideos, equals({_v('extra')}));
      expect(await owner.entryKeys(listId), equals(['extra']));
    });

    test('owner rename lands on the editor on its next flush', () async {
      final (owner, listId, mirror) = await joinAsEditor();

      // A queues an edit, then the owner renames before A flushes.
      await mirror.addVideo(_v('renamed-during-edit'));
      await owner.rename(listId, 'Renamed by owner');

      await deviceA.engine.pushAllDirty();

      expect(mirror.meta.displayName, 'Renamed by owner');
      expect(mirror.meta.pendingOps, isEmpty);
      expect(await owner.entryKeys(listId), contains('renamed-during-edit'));
    });

    test(
        'falling out of the op-log window yields a snapshot catch-up '
        'notification and a converged mirror', () async {
      final (owner, listId, mirror) = await joinAsEditor(initialKeys: ['keep']);

      // The owner churns >500 ops so A's cursor falls out of the retained
      // window (OP_LOG_RETAIN=500, max 50 ops per batch).
      for (var batch = 0; batch < 11; batch++) {
        final specs = <String>[];
        for (var i = 0; i < 25; i++) {
          final key = 'churn-$batch-$i';
          specs
            ..add('add:$key')
            ..add('remove:$key');
        }
        await owner.sync(listId, specs);
      }

      await mirror.addVideo(_v('mine'));
      await deviceA.engine.pushAllDirty();

      expect(notifications, contains(SyncNotification.snapshotCatchUp));
      expect(mirror.meta.pendingOps, isEmpty);
      final serverKeys = await owner.entryKeys(listId);
      expect(serverKeys, unorderedEquals(['keep', 'mine']));
      expect(mirror.savedVideos.map((v) => v.entryKey),
          unorderedEquals(serverKeys));
    }, timeout: const Timeout(Duration(minutes: 2)));
  });

  group('role transitions seen from device A', () {
    test(
        'removal as editor mid-edit demotes to subscriber and drops the '
        'queue (documenting current behaviour)', () async {
      final (owner, listId, mirror) = await joinAsEditor(initialKeys: ['x']);

      await mirror.addVideo(_v('doomed-edit'));
      expect(mirror.meta.pendingOps, hasLength(1));

      // Resolve device A's user id from the server's members block (the
      // client never stores its own user id locally).
      final editorUserId = (await owner.state(listId)).editorUserIds.single;
      await owner.removeEditor(listId, editorUserId);

      await deviceA.engine.pushAllDirty();

      expect(notifications, contains(SyncNotification.removedAsEditor));
      final demoted = deviceA.manager.get(listId);
      expect(demoted, isNotNull);
      expect(demoted!.meta.role, ListRole.subscriber);
      // Current engine behaviour: the queued edit is discarded on demotion.
      expect(demoted.meta.pendingOps, isEmpty);
      expect(await owner.entryKeys(listId), equals(['x']));
    });

    test(
        'owner account deletion tombstones the list; the editor mirror is '
        'dropped on next sync (documenting current behaviour)', () async {
      final (owner, listId, mirror) = await joinAsEditor(initialKeys: ['y']);
      expect(mirror.meta.role, ListRole.editor);

      await owner.deleteAccount();
      await deviceA.engine.refreshList(listId);

      // 410 GONE → _markOrphaned → editor mirrors are deleted locally.
      expect(deviceA.manager.get(listId), isNull);
    });

    test('session expiry preserves the queue; re-sign-in drains it', () async {
      final (owner, listId, mirror) = await joinAsEditor();
      final goodSession = deviceA.auth.store.current!;

      // Corrupt the session, then edit: flush must 401, keep the op, and
      // surface the sessionExpired notification.
      await deviceA.auth.store.save(AuthSession(
        sessionToken: 'garbage-token',
        provider: goodSession.provider,
        displayName: goodSession.displayName,
        signedInAtMillis: goodSession.signedInAtMillis,
      ));
      await mirror.addVideo(_v('queued-while-expired'));
      await deviceA.engine.pushAllDirty();

      expect(notifications, contains(SyncNotification.sessionExpired));
      expect(deviceA.auth.store.current, isNull);
      expect(mirror.meta.pendingOps, hasLength(1));

      // Re-sign-in (same identity) and sync: the queued edit lands.
      await deviceA.auth.store.save(goodSession);
      await deviceA.engine.syncAll();

      expect(mirror.meta.pendingOps, isEmpty);
      expect(await owner.entryKeys(listId), contains('queued-while-expired'));
    });
  });
}
