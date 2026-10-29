// Multi-device e2e for account sync (section 5.13 of dictionarylib's
// docs/account-sync-plan.md): the real app on two devices against a local
// worker.
//
// `flutter test integration_test` installs the app afresh for every run and
// removes it afterwards, so a run can't pick up where an earlier one left a
// device. Each phase is therefore one run on one device, and what a phase
// needs from "another device" in the middle of it (an edit made elsewhere
// while this one was offline, a list deleted elsewhere) is done by
// [MdOtherDevice], which talks to the worker as the same person over plain
// HTTP, the way another phone's app would. The phases that need both real
// apps (E) carry their state through the account itself.

import 'dart:convert';

import 'package:dictionarylib/dictionarylib.dart';
import 'package:dictionarylib/saved_video.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';

import '../config.dart';
import 'md_common.dart';

/// The person each scenario signs in as (one per scenario and run).
String mdSyncUser(String scenario) => 'test:md-$mdRunId-sync-$scenario';

/// [n] saved videos, one from each of [n] different entries that have a
/// video, skipping the first [skip].
List<SavedVideo> mdVideos(int n, {int skip = 0}) {
  final out = <SavedVideo>[];
  var seen = 0;
  for (final e in entriesGlobal) {
    final sub = e.getSubEntries().where((s) => s.getMedia().isNotEmpty);
    if (sub.isEmpty) continue;
    if (seen++ < skip) continue;
    out.add(
      SavedVideo(entryKey: e.getKey(), mediaPath: sub.first.getMedia().first),
    );
    if (out.length == n) break;
  }
  expect(
    out,
    hasLength(n),
    reason: 'the dictionary should have $n entries with videos',
  );
  return out;
}

/// Make a list on the device (signed out, as before account sync) holding
/// [videos].
Future<void> mdLocalList(String name, List<SavedVideo> videos) async {
  final key = EntryList.getKeyFromName(name);
  if (!userEntryListManager.getEntryLists().containsKey(key)) {
    await userEntryListManager.createEntryList(key);
  }
  final list = userEntryListManager.getEntryLists()[key]!;
  for (final v in videos) {
    await list.addVideo(v);
  }
}

/// Entry keys of the device's list called [name], or null.
Set<String>? mdLocalKeys(String name) {
  for (final l in userEntryListManager.getEntryLists().values) {
    if (l.getName() == name) return {for (final v in l.savedVideos) v.entryKey};
  }
  return null;
}

/// Another device of the same person, as raw HTTP. Its own session and
/// client id; its edits arrive at the worker like another phone's.
class MdOtherDevice {
  final String userId;
  final String token;
  final String clientId = 'md-other-${DateTime.now().microsecondsSinceEpoch}';
  int _ops = 0;

  MdOtherDevice._(this.userId, this.token);

  static Future<MdOtherDevice> signIn(String userId) async {
    final r = await http.post(
      Uri.parse('$mdApiBaseUrl/v1/auth/sign-in'),
      headers: {'x-app-id': mdConfig.appId, 'content-type': 'application/json'},
      body: jsonEncode({
        'provider': 'test',
        'testAuthToken': mdTestAuthToken,
        'userId': userId,
        'displayName': 'Md Other Device',
      }),
    );
    expect(r.statusCode, 200, reason: 'other device sign-in: ${r.body}');
    return MdOtherDevice._(
      userId,
      (jsonDecode(r.body) as Map<String, dynamic>)['sessionToken'] as String,
    );
  }

  Map<String, String> _headers({bool capability = true}) => {
    'x-app-id': mdConfig.appId,
    'authorization': 'Bearer $token',
    'content-type': 'application/json',
    if (capability) 'x-sync-capabilities': 'account-sync',
  };

  String _opId() => '$clientId-${_ops++}';

  /// `POST /v1/account/sync` with [ops] (each `{type, args}`); the response.
  Future<Map<String, dynamic>> account([
    List<Map<String, dynamic>> ops = const [],
  ]) async {
    final r = await http.post(
      Uri.parse('$mdApiBaseUrl/v1/account/sync'),
      headers: _headers(),
      body: jsonEncode({
        'clientId': clientId,
        'sinceSeq': 9007199254740991,
        'ops': [
          for (final op in ops) {'opId': _opId(), ...op},
        ],
      }),
    );
    expect(r.statusCode, 200, reason: 'account sync: ${r.body}');
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  /// Live lists on the account, name → id.
  Future<Map<String, String>> liveLists() async {
    final dir = (await account())['directory'] as List;
    return {
      for (final r in dir)
        if (r['state'] == 'live') r['name'] as String: r['listId'] as String,
    };
  }

  /// Every live list called [name] (there should be one).
  Future<List<String>> listsNamed(String name) async {
    final dir = (await account())['directory'] as List;
    return [
      for (final r in dir)
        if (r['state'] == 'live' && r['name'] == name) r['listId'] as String,
    ];
  }

  Future<Map<String, dynamic>> state(String listId) async {
    final r = await http.get(
      Uri.parse('$mdApiBaseUrl/v1/lists/$listId/state'),
      headers: _headers(),
    );
    expect(r.statusCode, 200, reason: 'state of $listId: ${r.body}');
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<List<String>> entryKeys(String listId) async => [
    for (final e in ((await state(listId))['entries'] as List))
      e['entry'] as String,
  ];

  /// Add [videos] to [listId] through `/sync`.
  Future<void> addToList(String listId, List<SavedVideo> videos) async {
    final st = await state(listId);
    final r = await http.post(
      Uri.parse('$mdApiBaseUrl/v1/lists/$listId/sync'),
      headers: _headers(),
      body: jsonEncode({
        'lastKnownSeq': st['lastSeq'],
        'ops': [
          for (final v in videos)
            {
              'opId': _opId(),
              'type': 'addEntry',
              'args': v.toJson(),
              'clientTs': DateTime.now().millisecondsSinceEpoch ~/ 1000,
            },
        ],
      }),
    );
    expect(r.statusCode, 200, reason: 'list sync: ${r.body}');
  }

  /// Delete a list the way a device with account sync does.
  Future<void> deleteList(String listId) async {
    final out = await account([
      {
        'type': 'delete',
        'args': {'listId': listId},
      },
    ]);
    final result = (out['results'] as List).single;
    expect(result['status'], 'applied', reason: 'delete: $result');
  }

  /// Share a list the way a build from before account sync does
  /// (`POST /v1/lists`); returns its id.
  Future<String> oldBuildShare(String name, List<SavedVideo> videos) async {
    final id = generateListId();
    final r = await http.post(
      Uri.parse('$mdApiBaseUrl/v1/lists'),
      headers: _headers(capability: false),
      body: jsonEncode({
        'listId': id,
        'displayName': name,
        'entries': [for (final v in videos) v.toJson()],
        'schemaVersion': 3,
      }),
    );
    expect(r.statusCode, 201, reason: 'old-build share: ${r.body}');
    return id;
  }

  /// An old build's "stop sharing": a DELETE without the capability header.
  Future<void> oldBuildUnshare(String listId) async {
    final r = await http.delete(
      Uri.parse('$mdApiBaseUrl/v1/lists/$listId'),
      headers: _headers(capability: false),
    );
    expect(r.statusCode, 204, reason: 'old-build unshare: ${r.body}');
  }
}

/// Open My Lists and wait for a row called [name] (or for it to be gone).
Future<void> mdExpectListOnScreen(
  WidgetTester tester,
  String name, {
  bool present = true,
}) async {
  await mdOpenListsTab(tester);
  await mdOpenOverviewTab(tester, mdL10n.listMyLists);
  await mdWaitForUi(
    tester,
    () => find.text(name).evaluate().isNotEmpty == present,
    reason: present ? '"$name" on My Lists' : '"$name" gone from My Lists',
  );
}

// -------- Phase E: two devices with "Animals" sign in --------

/// E1, device A: a list called Animals on the device, then sign in.
void runPhaseEFirstDevice(MdSuiteConfig cfg) {
  mdConfig = cfg;
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('device A: its Animals goes up when it signs in', (tester) async {
    await mdRequireServer();
    await mdSetup();
    final v = mdVideos(4);
    await mdLocalList('Animals', [v[0], v[1]]);
    await mdSignInAs(mdSyncUser('e'), 'Md Sync E');
    await mdWaitForAccountSync();
    final other = await MdOtherDevice.signIn(mdSyncUser('e'));
    final ids = await other.listsNamed('Animals');
    expect(ids, hasLength(1));
    expect((await other.entryKeys(ids.single)).toSet(), {
      v[0].entryKey,
      v[1].entryKey,
    });
    await mdPumpApp(tester);
    await mdExpectListOnScreen(tester, 'Animals');
  });
}

/// E2, device B: its own Animals, with other signs; after signing in there is
/// one Animals holding both, here and on the account.
void runPhaseESecondDevice(MdSuiteConfig cfg) {
  mdConfig = cfg;
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('device B: its Animals merges into the same list', (
    tester,
  ) async {
    await mdRequireServer();
    await mdSetup();
    final v = mdVideos(4);
    await mdLocalList('Animals', [v[1], v[2]]);
    await mdSignInAs(mdSyncUser('e'), 'Md Sync E');
    await mdWaitForAccountSync();
    final want = {v[0].entryKey, v[1].entryKey, v[2].entryKey};
    expect(mdLocalKeys('Animals'), want);
    final other = await MdOtherDevice.signIn(mdSyncUser('e'));
    final ids = await other.listsNamed('Animals');
    expect(ids, hasLength(1), reason: 'one Animals on the account');
    final keys = await other.entryKeys(ids.single);
    expect(keys.toSet(), want);
    expect(keys, hasLength(want.length), reason: 'no sign twice');
    await mdPumpApp(tester);
    await mdExpectListOnScreen(tester, 'Animals');
  });
}

/// E3, device A again (a new install, its own Animals once more): it ends
/// with the one list holding everything.
void runPhaseEFirstDeviceAgain(MdSuiteConfig cfg) {
  mdConfig = cfg;
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('device A again: one Animals with every sign', (tester) async {
    await mdRequireServer();
    await mdSetup();
    final v = mdVideos(4);
    await mdLocalList('Animals', [v[3]]);
    await mdSignInAs(mdSyncUser('e'), 'Md Sync E');
    await mdWaitForAccountSync();
    final want = {for (final x in v) x.entryKey};
    expect(mdLocalKeys('Animals'), want);
    final other = await MdOtherDevice.signIn(mdSyncUser('e'));
    final ids = await other.listsNamed('Animals');
    expect(ids, hasLength(1));
    expect((await other.entryKeys(ids.single)).toSet(), want);
  });
}

// -------- Phase F: both edit the same list offline --------

/// One device, with the other as raw HTTP: this device's edits wait in its
/// queue (its session dropped, as when it expires offline) while the other
/// device edits the same list; back online, the list holds the union, each
/// sign once.
void runPhaseFOfflineEdits(MdSuiteConfig cfg) {
  mdConfig = cfg;
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('both edit the same list offline: the union, once', (
    tester,
  ) async {
    await mdRequireServer();
    await mdSetup();
    final v = mdVideos(5);
    await mdLocalList('Birds', [v[0]]);
    await mdSignInAs(mdSyncUser('f'), 'Md Sync F');
    await mdWaitForAccountSync();
    final birds = sharing.lists.ownerForSourceKey('Birds_words')!;

    // This device goes "offline" and edits.
    await sharing.auth.dropSessionLocally();
    await birds.addVideo(v[1]);
    await birds.addVideo(v[2]);
    expect(birds.meta.pendingOps, hasLength(2));

    // The other device edits the same list meanwhile, one sign in common.
    final other = await MdOtherDevice.signIn(mdSyncUser('f'));
    await other.addToList(birds.listId, [v[2], v[3]]);

    // Back online.
    await sharing.auth.signInWithTestToken(
      testAuthToken: mdTestAuthToken,
      userId: mdSyncUser('f'),
      displayName: 'Md Sync F',
    );
    await mdWaitForAccountSync();
    final want = {v[0].entryKey, v[1].entryKey, v[2].entryKey, v[3].entryKey};
    final keys = await other.entryKeys(birds.listId);
    expect(keys.toSet(), want);
    expect(keys, hasLength(want.length), reason: 'no sign twice');
    expect(mdLocalKeys('Birds'), want);
    expect(birds.meta.pendingOps, isEmpty);
  });
}

// -------- Phase G: a list deleted on another device --------

/// One device, with the other as raw HTTP: a list deleted elsewhere goes
/// from this device; one this device had unsent changes to stays, as a list
/// of its own, and the person is told; and a list deleted here (through the
/// Lists page) goes from the account.
void runPhaseGDeleteElsewhere(MdSuiteConfig cfg) {
  mdConfig = cfg;
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('deleted elsewhere: gone here, or kept with unsent changes', (
    tester,
  ) async {
    await mdRequireServer();
    await mdSetup();
    final v = mdVideos(4);
    await mdLocalList('Gone', [v[0]]);
    await mdLocalList('Kept', [v[1]]);
    await mdLocalList('Mine', [v[2]]);
    await mdSignInAs(mdSyncUser('g'), 'Md Sync G');
    await mdWaitForAccountSync();
    final other = await MdOtherDevice.signIn(mdSyncUser('g'));
    final ids = await other.liveLists();

    // Deleted elsewhere, nothing unsent here: it goes.
    await other.deleteList(ids['Gone']!);
    await mdWaitForAccountSync();
    expect(mdLocalKeys('Gone'), isNull);

    // Unsent changes here (offline), deleted elsewhere: kept, unlinked.
    final kept = sharing.lists.ownerForSourceKey('Kept_words')!;
    await sharing.auth.dropSessionLocally();
    await kept.addVideo(v[3]);
    await other.deleteList(ids['Kept']!);
    await sharing.auth.signInWithTestToken(
      testAuthToken: mdTestAuthToken,
      userId: mdSyncUser('g'),
      displayName: 'Md Sync G',
    );
    await mdWaitForAccountSync();
    expect(mdLocalKeys('Kept'), {v[1].entryKey, v[3].entryKey});
    expect(sharing.lists.ownerForSourceKey('Kept_words'), isNull);
    expect(
      sharing.accountSync.unsyncableReason('Kept_words'),
      UnsyncableReason.keptUnsent,
    );

    // Deleted here, through the Lists page: gone from the account too.
    await mdPumpApp(tester);
    await mdOpenListsTab(tester);
    await mdOpenOverviewTab(tester, mdL10n.listMyLists);
    await mdTapWhenVisible(
      tester,
      find.byIcon(Icons.edit_outlined),
      reason: 'edit lists',
    );
    final row = find.ancestor(
      of: find.text('Mine'),
      matching: find.byType(ReorderableDragStartListener),
    );
    await mdTapWhenVisible(
      tester,
      find.descendant(of: row, matching: find.byIcon(Icons.remove_circle)),
      reason: 'delete button on Mine',
    );
    await mdWaitForUi(
      tester,
      () => find
          .text(mdL10n.listDeleteEverywhereConfirm('Mine'))
          .evaluate()
          .isNotEmpty,
      reason: 'the confirmation says it goes from every device',
    );
    await mdTapWhenVisible(
      tester,
      find.text(mdL10n.alertConfirm),
      reason: 'confirm',
    );
    await mdWaitForAccountSync();
    expect((await other.liveLists()).containsKey('Mine'), isFalse);
  });
}

// -------- Solo: an old build's "stop sharing" --------

/// A list shared from a build that predates account sync, and then
/// "unshared" by it (a DELETE without the capability header), is still on
/// the account, private, and arrives on this device.
void runSoloOldBuildStopSharing(MdSuiteConfig cfg) {
  mdConfig = cfg;
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets("an old build's stop sharing keeps the list on the account", (
    tester,
  ) async {
    await mdRequireServer();
    await mdSetup();
    await mdSignInAs(mdSyncUser('old'), 'Md Sync Old');
    await mdWaitForAccountSync();
    final old = await MdOtherDevice.signIn(mdSyncUser('old'));
    final v = mdVideos(2);
    final id = await old.oldBuildShare('Old Share', v);
    await old.oldBuildUnshare(id);
    await mdWaitForAccountSync();
    final dir = (await old.account())['directory'] as List;
    final row = dir.firstWhere((r) => r['listId'] == id);
    expect(row['state'], 'live');
    expect(row['visibility'], 'private');
    expect(mdLocalKeys('Old Share'), {for (final x in v) x.entryKey});
    final w = sharing.lists.get(id)!;
    expect(w.meta.isShared, isFalse);
    await mdPumpApp(tester);
    await mdExpectListOnScreen(tester, 'Old Share');
  });
}
