import 'dart:convert';
import 'dart:io';

import 'package:dictionarylib/globals.dart';
import 'package:dictionarylib/sharing/account_sync_api.dart';
import 'package:dictionarylib/sharing/account_sync_state.dart';
import 'package:dictionarylib/sharing/install_marker.dart';
import 'package:dictionarylib/sharing/sync_api.dart';
import 'package:dictionarylib/sharing/synced_entry_list.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../_recording_prefs.dart';

/// The account-sync wire shapes and the restore detection (sections 5.10 and
/// 5.13 "Wire" of the plan).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('wire', () {
    test('an account sync response parses, unknown fields ignored', () {
      final r = AccountSyncResponse.fromJson({
        'incarnation': 'abc',
        'seq': 7,
        'nextSinceSeq': 5,
        'results': [
          {
            'opId': 'o1',
            'status': 'applied',
            'seq': 6,
            'result': {'listId': 'l1', 'created': true},
            'somethingNew': 1,
          },
          {'opId': 'o2', 'status': 'duplicate', 'seq': 4},
          {
            'opId': 'o3',
            'status': 'rejected',
            'reason': 'busy',
            'reasonCode': 'retry',
          },
        ],
        'directory': [
          {
            'listId': 'l1',
            'position': 1,
            'isDefault': true,
            'visibility': 'private',
            'name': 'Favourites',
            'state': 'live',
            'deletedAt': null,
            'colour': 'blue',
          },
        ],
        'follows': ['f1'],
        'settings': [
          {'key': 'revision_strategy', 'value': '1', 'seq': 3},
        ],
        'resetTsUs': 9,
        'randomTotal': 12,
        'reviews': [
          {'m': 'm', 'c': '0@@@1', 'r': 2, 't': 100, 'seq': 2},
        ],
        'randomSessions': [
          {'opId': 'rs', 'count': 3, 'tsUs': 50, 'seq': 1},
        ],
        'hasMore': true,
        'editorListIds': ['e1'],
        'futureField': {'x': 1},
      });
      expect(r.incarnation, 'abc');
      expect(r.nextSinceSeq, 5);
      expect(r.outcomeFor('o1')!.result!.listId, 'l1');
      expect(r.outcomeFor('o1')!.isDone, isTrue);
      expect(r.outcomeFor('o2')!.isDone, isTrue);
      expect(r.outcomeFor('o3')!.shouldRetry, isTrue);
      expect(r.directory.single.isDefault, isTrue);
      expect(r.directory.single.visibility, listVisibilityPrivate);
      expect(r.follows, ['f1']);
      expect(r.settings.single.key, 'revision_strategy');
      expect(r.reviews.single.t, 100);
      expect(r.randomSessions.single.count, 3);
      expect(r.hasMore, isTrue);
      expect(r.editorListIds, ['e1']);
    });

    test('a minimal response takes defaults', () {
      final r = AccountSyncResponse.fromJson({'seq': 4});
      expect(r.nextSinceSeq, 4);
      expect(r.directory, isEmpty);
      expect(r.hasMore, isFalse);
      expect(r.incarnation, '');
    });

    test('503 UNAVAILABLE maps to unavailable with its Retry-After', () {
      final e = SyncException.fromResponse(
        http.Response(
          jsonEncode({
            'error': {
              'code': 'UNAVAILABLE',
              'message': 'off',
              'details': {'reason': 'account_sync_disabled'},
            },
          }),
          503,
          headers: {'retry-after': '3600'},
        ),
      );
      expect(e.kind, SyncErrorKind.unavailable);
      expect(e.retryAfterSeconds, 3600);
      expect(e.details!['reason'], unavailableReasonAccountSyncDisabled);
      expect(e.isTransient, isTrue);
      // Any other 5xx is still a server error.
      expect(
        SyncException.fromResponse(http.Response('', 503)).kind,
        SyncErrorKind.server,
      );
    });

    test('visibility on snapshots and /sync, shared when absent', () {
      final base = {
        'schemaVersion': 3,
        'listId': 'l',
        'displayName': 'n',
        'appId': 'auslan',
        'entries': <Object>[],
        'lastSeq': 0,
        'createdAt': 0,
        'updatedAt': 0,
        'members': {
          'owner': {'userId': 'u', 'displayName': 'U'},
          'editors': <Object>[],
        },
      };
      expect(ListSnapshot.fromJson(base).visibility, listVisibilityShared);
      expect(
        ListSnapshot.fromJson({...base, 'visibility': 'private'}).visibility,
        listVisibilityPrivate,
      );
      final sync = SyncResponse.fromJson({
        'appliedSeq': 1,
        'applied': <Object>[],
        'missedOps': <Object>[],
        'snapshot': null,
        'members': base['members'],
        'displayName': 'n',
      });
      expect(sync.visibility, isNull);
    });

    test('an addEntries applied in part counts as the list being full', () {
      final o = OpOutcome.fromJson({
        'opId': 'x',
        'status': 'applied',
        'seq': 3,
        'reasonCode': 'list_full',
      });
      expect(o.hitListFull, isTrue);
      expect(o.isListFullRejection, isFalse);
    });

    test('list meta keeps visibility, and an old blob reads as shared', () {
      final meta = SyncedListMeta(
        listId: 'l',
        displayName: 'n',
        role: ListRole.owner,
        lastKnownSeq: 1,
        etag: null,
        lastSyncedAt: null,
        serverUpdatedAt: null,
        orphaned: false,
        visibility: listVisibilityPrivate,
      );
      final round = SyncedListMeta.fromJson(meta.toJson())!;
      expect(round.visibility, listVisibilityPrivate);
      final old = meta.toJson()..remove('visibility');
      expect(SyncedListMeta.fromJson(old)!.visibility, listVisibilityShared);
    });

    test(
      'the account state blob round-trips, and a foreign one is dropped',
      () {
        final st = AccountSyncState(
          userId: 'u',
          incarnation: 'i',
          sinceSeq: 4,
          mergePhase: MergePhase.lists,
          linking: {
            'A_words': LinkingRecord(
              listId: 'l',
              requestId: 'r',
              step: LinkStep.create,
              makeDefault: true,
            ),
          },
          unsyncable: {'B_words': UnsyncableReason.tooLarge},
          pendingOps: [
            const AccountOp(opId: 'o', type: 'follow', args: {'listId': 'f'}),
          ],
        );
        final back = AccountSyncState.fromJson(
          jsonDecode(jsonEncode(st.toJson())) as Map<String, dynamic>,
        )!;
        expect(back.linking['A_words']!.makeDefault, isTrue);
        expect(back.unsyncable, {'B_words': UnsyncableReason.tooLarge});
        expect(back.pendingOps.single.opId, 'o');
        expect(back.mergePhase, MergePhase.lists);
        expect(
          AccountSyncState.fromJson({...st.toJson(), 'schema': 99}),
          isNull,
        );
      },
    );
  });

  group('restore detection', () {
    late Map<String, String> keychain;
    late Directory support;

    setUp(() async {
      keychain = {};
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
            (call) async {
              final args = Map<String, dynamic>.from(call.arguments as Map);
              final key = args['key'] as String?;
              switch (call.method) {
                case 'read':
                  return keychain[key];
                case 'write':
                  keychain[key!] = args['value'] as String;
                  return null;
                case 'delete':
                  keychain.remove(key);
                  return null;
              }
              return null;
            },
          );
      support = await Directory.systemTemp.createTemp('install-marker');
      resetClientIdCacheForTesting();
    });

    tearDown(() => support.delete(recursive: true));

    Future<InstallKind> check() => checkInstallMarker(
      secureStorage: const FlutterSecureStorage(),
      supportDirectory: () async => support,
    );

    test('a fresh install writes the marker', () async {
      await installPrefs({});
      expect(await check(), InstallKind.fresh);
      expect(await check(), InstallKind.normal);
    });

    test(
      'an install updating to this build is not taken for a restore',
      () async {
        // Used sharing before: a client id, but no marker or flag yet.
        await installPrefs({KEY_SHARED_CLIENT_ID: 'old-client'});
        expect(await check(), InstallKind.fresh);
        expect(sharedPreferences.getString(KEY_SHARED_CLIENT_ID), 'old-client');
      },
    );

    test('a restored backup gets a client id of its own', () async {
      await installPrefs({});
      expect(await check(), InstallKind.fresh);
      getOrCreateClientId();
      final original = sharedPreferences.getString(KEY_SHARED_CLIENT_ID)!;
      final backup = prefsSnapshot();
      // A new phone: the prefs come back, the marker doesn't.
      keychain.clear();
      await support.delete(recursive: true);
      support = await Directory.systemTemp.createTemp('install-marker');
      await installPrefs(backup);
      resetClientIdCacheForTesting();
      expect(await check(), InstallKind.restored);
      final now = sharedPreferences.getString(KEY_SHARED_CLIENT_ID)!;
      expect(now, isNot(original));
      expect(getOrCreateClientId(), now);
      // Account state and queues are left alone: every queued op is
      // idempotent by its op id.
      expect(await check(), InstallKind.normal);
    });
  });
}
