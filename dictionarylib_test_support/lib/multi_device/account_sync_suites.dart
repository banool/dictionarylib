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

import 'dart:async';
import 'dart:convert';

import 'package:dictionarylib/dictionarylib.dart';
import 'package:dictionarylib/saved_video.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:dolphinsr/dolphinsr.dart' show Combination, Rating, Review;
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';

import '../config.dart';
import '../helpers.dart';
import '../net_proxy.dart';
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

  /// Every answer on the account (paged from the start).
  Future<List<Map<String, dynamic>>> answers() async {
    final out = <Map<String, dynamic>>[];
    var since = 0;
    while (true) {
      final r = await http.post(
        Uri.parse('$mdApiBaseUrl/v1/account/sync'),
        headers: _headers(),
        body: jsonEncode({'clientId': clientId, 'sinceSeq': since, 'ops': []}),
      );
      expect(r.statusCode, 200, reason: 'account sync: ${r.body}');
      final json = jsonDecode(r.body) as Map<String, dynamic>;
      out.addAll((json['reviews'] as List).cast<Map<String, dynamic>>());
      since = json['nextSinceSeq'] as int;
      if (json['hasMore'] != true) return out;
    }
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

  /// Remove [videos] from [listId] through `/sync`.
  Future<void> removeFromList(String listId, List<SavedVideo> videos) async {
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
              'type': 'removeEntry',
              'args': v.toJson(),
              'clientTs': DateTime.now().millisecondsSinceEpoch ~/ 1000,
            },
        ],
      }),
    );
    expect(r.statusCode, 200, reason: 'list sync: ${r.body}');
  }

  /// Delete a list the way a device with account sync does, at [clientTs]
  /// by this device's clock (now by default).
  Future<void> deleteList(String listId, {int? clientTs}) async {
    final out = await account([
      {
        'type': 'delete',
        'args': {'listId': listId},
        'clientTs': clientTs ?? _nowSecs(),
      },
    ]);
    final result = (out['results'] as List).single;
    expect(result['status'], 'applied', reason: 'delete: $result');
  }

  /// Rename a list the way a device with account sync does (a `rename` op
  /// through `/sync`), at [clientTs] by this device's clock; the answer.
  Future<Map<String, dynamic>> renameList(
    String listId,
    String name, {
    required int clientTs,
  }) async {
    final st = await state(listId);
    final r = await http.post(
      Uri.parse('$mdApiBaseUrl/v1/lists/$listId/sync'),
      headers: _headers(),
      body: jsonEncode({
        'lastKnownSeq': st['lastSeq'],
        'ops': [
          {
            'opId': _opId(),
            'type': 'rename',
            'args': {'displayName': name},
            'clientTs': clientTs,
          },
        ],
      }),
    );
    expect(r.statusCode, 200, reason: 'list sync: ${r.body}');
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  static int _nowSecs() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

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

    // This device goes "offline" and edits, and renames the list: the new
    // name shows at once.
    await sharing.auth.dropSessionLocally();
    await birds.addVideo(v[1]);
    await birds.addVideo(v[2]);
    await listsService.renameList(birds, 'Garden birds');
    expect(birds.getName(), 'Garden birds');
    expect(birds.meta.pendingOps, hasLength(3));

    // The other device edits the same list meanwhile, one sign in common,
    // and renamed it too, but earlier (by its clock).
    final other = await MdOtherDevice.signIn(mdSyncUser('f'));
    await other.addToList(birds.listId, [v[2], v[3]]);
    await other.renameList(
      birds.listId,
      'Birds two',
      clientTs: DateTime.now().millisecondsSinceEpoch ~/ 1000 - 120,
    );

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
    expect(mdLocalKeys('Garden birds'), want);
    expect(birds.meta.pendingOps, isEmpty);
    // The later rename (this device's) is the name everywhere.
    expect((await other.state(birds.listId))['displayName'], 'Garden birds');
    expect(birds.getName(), 'Garden birds');

    // Set semantics: offline again, this device removes a sign and saves it
    // again while the other device removes it. The sign stays, once, on
    // both.
    await sharing.auth.dropSessionLocally();
    await birds.removeVideo(v[0]);
    await birds.addVideo(v[0]);
    expect(birds.meta.pendingOps, hasLength(2));
    await other.removeFromList(birds.listId, [v[0]]);
    expect(await other.entryKeys(birds.listId), isNot(contains(v[0].entryKey)));
    await sharing.auth.signInWithTestToken(
      testAuthToken: mdTestAuthToken,
      userId: mdSyncUser('f'),
      displayName: 'Md Sync F',
    );
    await mdWaitForAccountSync();
    final after = await other.entryKeys(birds.listId);
    expect(after.where((k) => k == v[0].entryKey), hasLength(1));
    expect(after.toSet(), want);
    expect(mdLocalKeys('Garden birds'), want);

    // And on screen: the list, with the sign in it.
    await mdPumpApp(tester);
    await mdExpectListOnScreen(tester, 'Garden birds');
    await mdTapWhenVisible(
      tester,
      find.text('Garden birds'),
      reason: 'open Garden birds',
    );
    await mdWaitForUi(
      tester,
      () => find.byKey(ValueKey(v[0].entryKey)).evaluate().isNotEmpty,
      reason: 'the sign saved again shows in the list',
    );
  });
}

// -------- Phase G: a list deleted on another device --------

/// One device, with the other as raw HTTP: a list deleted elsewhere goes
/// from this device; against unsent changes here the later intent wins,
/// silently: changes older than the delete go with the list, changes newer
/// than it bring the list back on the account with them; and a list deleted
/// here (through the Lists page) goes from the account.
void runPhaseGDeleteElsewhere(MdSuiteConfig cfg) {
  mdConfig = cfg;
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('deleted elsewhere: the later of the delete and the edits here '
      'wins', (tester) async {
    await mdRequireServer();
    await mdSetup();
    final v = mdVideos(5);
    await mdLocalList('Gone', [v[0]]);
    await mdLocalList('Older', [v[1]]);
    await mdLocalList('Newer', [v[4]]);
    await mdLocalList('Mine', [v[2]]);
    await mdSignInAs(mdSyncUser('g'), 'Md Sync G');
    await mdWaitForAccountSync();
    final other = await MdOtherDevice.signIn(mdSyncUser('g'));
    final ids = await other.liveLists();

    // Deleted elsewhere, nothing unsent here: it goes.
    await other.deleteList(ids['Gone']!);
    await mdWaitForAccountSync();
    expect(mdLocalKeys('Gone'), isNull);

    // Unsent changes here (offline) to two lists, both deleted elsewhere:
    // one a minute after the changes (by the other device's clock), one a
    // minute before.
    final older = sharing.lists.ownerForSourceKey('Older_words')!;
    final newer = sharing.lists.ownerForSourceKey('Newer_words')!;
    await sharing.auth.dropSessionLocally();
    await older.addVideo(v[3]);
    await newer.addVideo(v[3]);
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await other.deleteList(ids['Older']!, clientTs: now + 60);
    await other.deleteList(ids['Newer']!, clientTs: now - 60);
    await sharing.auth.signInWithTestToken(
      testAuthToken: mdTestAuthToken,
      userId: mdSyncUser('g'),
      displayName: 'Md Sync G',
    );
    await mdWaitForAccountSync();
    // The delete was later: the list and the change are gone, here and
    // there.
    expect(mdLocalKeys('Older'), isNull);
    expect((await other.liveLists()).containsKey('Older'), isFalse);
    // The change was later: the list is back on the account, change and
    // all, under the same id.
    final want = {v[4].entryKey, v[3].entryKey};
    expect(mdLocalKeys('Newer'), want);
    expect(
      sharing.lists.ownerForSourceKey('Newer_words')?.listId,
      ids['Newer'],
    );
    expect((await other.liveLists())['Newer'], ids['Newer']);
    expect((await other.entryKeys(ids['Newer']!)).toSet(), want);

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

// -------- Phase H: revision both ways --------

/// The revision settings every phase H run starts from: spaced repetition,
/// sign-to-word cards only (one card per sign), the default list, no cap.
Future<void> _mdRevisionSettings() async {
  await sharedPreferences.setInt(
    KEY_REVISION_STRATEGY,
    RevisionStrategy.SpacedRepetition.index,
  );
  await sharedPreferences.setBool(KEY_WORD_TO_SIGN, false);
  await sharedPreferences.setBool(KEY_SIGN_TO_WORD, true);
  await sharedPreferences.remove(KEY_LISTS_TO_REVIEW);
  await sharedPreferences.remove(KEY_REVISION_CARD_LIMIT);
}

/// The default list holding [videos].
Future<void> _mdDefaultListHolds(List<SavedVideo> videos) async {
  final list = userEntryListManager
      .getEntryLists()[userEntryListManager.defaultListKey]!;
  for (final v in videos) {
    if (!list.savedVideos.contains(v)) await list.addVideo(v);
  }
}

/// Open the Revision tab and return its page's state once it is up.
Future<FlashcardsLandingPageState> _mdOpenRevision(WidgetTester tester) async {
  mdClearSnackBars();
  await mdTapWhenVisible(
    tester,
    mdNavIcon(Icons.style),
    reason: 'Revision tab icon in the bottom navigation',
  );
  await mdWaitForUi(
    tester,
    () => find.byKey(const ValueKey('startButton')).evaluate().isNotEmpty,
    reason: 'the Revision page',
  );
  return tester.state<FlashcardsLandingPageState>(
    find.byType(FlashcardsLandingPage),
  );
}

/// Cards due on the Revision page now.
int _mdDue(FlashcardsLandingPageState page) => getNumDueCards(
  page.dolphinInformation.dolphin,
  RevisionStrategy.SpacedRepetition,
);

/// Cards that would be due with no history at all (every card new).
int _mdDueWithoutHistory(FlashcardsLandingPageState page) => getNumDueCards(
  page.widget.controller
      .getDolphin(
        page.filteredVideos,
        const [],
        revisionStrategy: RevisionStrategy.SpacedRepetition,
      )
      .dolphin,
  RevisionStrategy.SpacedRepetition,
);

/// Answer every due card "Got it" through the session page, then close it.
Future<void> _mdRunSession(WidgetTester tester, int cards) async {
  expect(find.text(mdL10n.revisionFlashcardCount(cards)), findsOneWidget);
  await tester.tap(find.byKey(const ValueKey('startButton')));
  await settle(tester);
  for (var k = 1; k <= cards; k++) {
    expect(find.text('$k / $cards'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('revealButton')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('ratingButton.gotIt')));
    await settle(tester);
  }
  expect(find.byKey(const ValueKey('revealButton')), findsNothing);
  await tester.tap(find.widgetWithIcon(IconButton, Icons.close));
  await settle(tester);
}

/// The progress page (from the Revision page) shows [total] answers.
Future<void> _mdExpectProgressTotal(WidgetTester tester, int total) async {
  await tester.tap(find.byIcon(Icons.timeline));
  await settle(tester);
  await mdWaitForUi(
    tester,
    () => find
        .byWidgetPredicate(
          (w) =>
              w is HearthStatTile &&
              w.label == mdL10n.flashcardsTotalReviews &&
              w.value == '$total',
        )
        .evaluate()
        .isNotEmpty,
    reason: 'the progress page should count $total answers',
  );
  await tester.pageBack();
  await settle(tester);
}

/// A random-mode session through the Revision page: switch to Random, start,
/// reveal and "Next" every card, close, and switch back to spaced
/// repetition (the strategy is a synced setting the other phases expect).
/// Returns how many cards it showed (what it adds to the random total).
Future<int> _mdRunRandomSession(WidgetTester tester) async {
  Future<void> pick(RevisionStrategy strategy) async {
    final option = find.text(strategy.pretty);
    await mdWaitForUi(
      tester,
      () => option.evaluate().isNotEmpty,
      reason: 'the ${strategy.pretty} option',
    );
    await tester.ensureVisible(option.first);
    await settle(tester);
    await tester.tap(option.first);
    await settle(tester);
  }

  await pick(RevisionStrategy.Random);
  final start = find.byKey(const ValueKey('startButton'));
  await tester.ensureVisible(start);
  await settle(tester);
  await tester.tap(start);
  await settle(tester);
  final first = tester
      .widgetList<Text>(find.byType(Text))
      .map((t) => t.data ?? '')
      .firstWhere(
        (s) => RegExp(r'^1 / \d+$').hasMatch(s),
        orElse: () => fail('no "1 / n" on the random session page'),
      );
  final cards = int.parse(first.split(' / ')[1]);
  for (var k = 1; k <= cards; k++) {
    expect(find.text('$k / $cards'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('revealButton')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('ratingButton.next')));
    await settle(tester);
  }
  expect(find.byKey(const ValueKey('revealButton')), findsNothing);
  await tester.tap(find.widgetWithIcon(IconButton, Icons.close));
  await settle(tester);
  await pick(RevisionStrategy.SpacedRepetition);
  return cards;
}

/// The progress page (from the Revision page), on its Random tab, shows
/// [total] cards.
Future<void> _mdExpectRandomTotal(WidgetTester tester, int total) async {
  await tester.tap(find.byIcon(Icons.timeline));
  await settle(tester);
  await mdTapWhenVisible(
    tester,
    find.text(RevisionStrategy.Random.pretty),
    reason: 'the Random tab of the progress page',
  );
  await mdWaitForUi(
    tester,
    () => find
        .byWidgetPredicate(
          (w) =>
              w is HearthStatTile &&
              w.label == mdL10n.flashcardsTotalReviews &&
              w.value == '$total',
        )
        .evaluate()
        .isNotEmpty,
    reason: 'the progress page should count $total random-mode cards',
  );
  await tester.pageBack();
  await settle(tester);
}

/// The account's random-mode total.
Future<int> _mdAccountRandomTotal(MdOtherDevice other) async =>
    ((await other.account())['randomTotal'] as num?)?.toInt() ?? 0;

/// Two answers ("Got it", two days and one day ago) to [video]'s card:
/// learned, and not due again for a while.
List<Review> _mdLearnedAndResting(SavedVideo video) {
  final now = DateTime.now();
  return [
    for (final daysAgo in [2, 1])
      Review(
        master: savedVideoMasterId(video),
        combination: const Combination(front: [1], back: [0]),
        rating: Rating.Good,
        ts: now.subtract(Duration(days: daysAgo)),
      ),
  ];
}

/// H1, device A: two cards learned in earlier sessions, a session now on the
/// rest; every answer reaches the account.
void runPhaseHFirstDevice(MdSuiteConfig cfg) {
  mdConfig = cfg;
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('device A: its answers go up', (tester) async {
    await mdRequireServer();
    await mdSetup();
    await reviewHistory.reset(DateTime.now().microsecondsSinceEpoch);
    await _mdRevisionSettings();
    await _mdDefaultListHolds(mdVideos(4));
    await mdSignInAs(mdSyncUser('h'), 'Md Sync H');
    await mdWaitForAccountSync();
    await mdPumpApp(tester);
    var page = await _mdOpenRevision(tester);
    final cards = page.filteredVideos;
    expect(cards.length, greaterThanOrEqualTo(3), reason: 'cards to revise');
    expect(_mdDue(page), cards.length, reason: 'every card new and due');

    // Earlier sessions (on this device) learned the first two.
    await sharing.accountSync.recordAnswers([
      ..._mdLearnedAndResting(cards[0].video),
      ..._mdLearnedAndResting(cards[1].video),
    ]);
    await settle(tester);
    page = tester.state(find.byType(FlashcardsLandingPage));
    expect(_mdDue(page), cards.length - 2, reason: 'the page re-read them');

    await _mdRunSession(tester, cards.length - 2);
    final total = 4 + cards.length - 2;
    expect(reviewHistory.read(), hasLength(total));
    await mdWaitForAccountSync();
    expect(reviewHistory.unsentCount, 0);
    final other = await MdOtherDevice.signIn(mdSyncUser('h'));
    expect(await other.answers(), hasLength(total));
    await _mdExpectProgressTotal(tester, total);

    // Random mode: a session here, counted on the account.
    final random = await _mdRunRandomSession(tester);
    expect(random, greaterThan(0));
    await mdWaitForAccountSync();
    expect(await _mdAccountRandomTotal(other), random);
    await _mdExpectRandomTotal(tester, random);
    mdEmit('MD_RANDOM_A', '$random');
  });
}

/// H2, device B: A's answers arrive and count in its due cards and progress
/// page; its own session goes up.
void runPhaseHSecondDevice(MdSuiteConfig cfg) {
  mdConfig = cfg;
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets("device B: A's answers count here, its own go up", (
    tester,
  ) async {
    await mdRequireServer();
    await mdSetup();
    await reviewHistory.reset(DateTime.now().microsecondsSinceEpoch);
    final other = await MdOtherDevice.signIn(mdSyncUser('h'));
    final fromA = (await other.answers()).length;
    expect(fromA, greaterThan(4), reason: 'phase H1 ran first');
    final randomFromA = await _mdAccountRandomTotal(other);
    expect(randomFromA, greaterThan(0), reason: "H1's random session");
    // A sign of its own that A hasn't seen, so B has a card due whatever
    // A's answers did.
    await _mdDefaultListHolds([mdVideos(5)[4]]);
    await mdSignInAs(mdSyncUser('h'), 'Md Sync H');
    await mdWaitForAccountSync();
    expect(reviewHistory.read(), hasLength(fromA));
    // A's revision settings came with the account.
    expect(sharedPreferences.getBool(KEY_WORD_TO_SIGN), isFalse);
    await mdPumpApp(tester);
    final page = await _mdOpenRevision(tester);
    expect(page.existingReviews, hasLength(fromA));
    final due = _mdDue(page);
    expect(
      due,
      lessThanOrEqualTo(_mdDueWithoutHistory(page) - 2),
      reason: "the two cards A learned aren't due here",
    );
    expect(due, greaterThan(0));

    await _mdRunSession(tester, due);
    await mdWaitForAccountSync();
    expect(reviewHistory.unsentCount, 0);
    expect(await other.answers(), hasLength(fromA + due));
    await _mdExpectProgressTotal(tester, fromA + due);

    // Random mode: A's count is here; a session here adds to it, on the
    // account and on this progress page.
    await _mdExpectRandomTotal(tester, randomFromA);
    final random = await _mdRunRandomSession(tester);
    await mdWaitForAccountSync();
    expect(await _mdAccountRandomTotal(other), randomFromA + random);
    await _mdExpectRandomTotal(tester, randomFromA + random);
    mdEmit('MD_RANDOM_TOTAL', '${randomFromA + random}');
  });
}

/// H3, device A again (a new install): every answer from both, in its due
/// cards and progress page.
void runPhaseHFirstDeviceAgain(MdSuiteConfig cfg) {
  mdConfig = cfg;
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('device A again: answers from both devices', (tester) async {
    await mdRequireServer();
    await mdSetup();
    await reviewHistory.reset(DateTime.now().microsecondsSinceEpoch);
    final other = await MdOtherDevice.signIn(mdSyncUser('h'));
    final all = (await other.answers()).length;
    await mdSignInAs(mdSyncUser('h'), 'Md Sync H');
    await mdWaitForAccountSync();
    expect(reviewHistory.read(), hasLength(all));
    await mdPumpApp(tester);
    final page = await _mdOpenRevision(tester);
    expect(page.existingReviews, hasLength(all));
    expect(_mdDue(page), lessThan(_mdDueWithoutHistory(page)));
    await _mdExpectProgressTotal(tester, all);
    // Both devices' random-mode sessions, summed.
    final random = await _mdAccountRandomTotal(other);
    expect(random, greaterThan(0));
    await _mdExpectRandomTotal(tester, random);
  });
}

// -------- Solo: offline, then online --------

/// The person behind [mdSyncUser] for the offline/online pair.
String get _mdOfflineUser => mdSyncUser('offline');

const String _mdOfflineName = 'Offline list';
const String _mdOfflineRenamed = 'Offline renamed';
const String _mdBlackholeName = 'Blackhole list';
const String _mdBlackholeRenamed = 'Blackhole renamed';

/// Pump until [done] holds, at most [within]; fail with [what] if it
/// doesn't. Each step offline must show its result within a second.
Future<void> _mdWithin(
  WidgetTester tester,
  bool Function() done,
  String what, {
  Duration within = const Duration(seconds: 1),
}) async {
  final sw = Stopwatch()..start();
  while (!done()) {
    if (sw.elapsed > within) {
      fail('$what took longer than $within with the network down');
    }
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void _mdNoSnackBar(String when) {
  expect(find.byType(SnackBar), findsNothing, reason: '$when: a snackbar');
}

/// One device, the app's network taken away mid-session by a proxy inside
/// the app between it and the worker: the person makes a list, saves signs
/// into it, renames it, does a revision session and changes a revision
/// setting through the real UI, each showing at once with nothing said
/// about the network, Settings reading "Waiting for a connection"; then the
/// network comes back and it all reaches the account. The second run
/// ([runSoloOfflineOnlineAfter], another device) checks it from scratch.
void runSoloOfflineOnline(
  MdSuiteConfig cfg, {
  required NavigateToEntryPageFn navigateToEntryPage,
}) {
  mdConfig = cfg;
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('offline (refused, then a black hole): everything shows at '
      'once; online: it all goes up', (tester) async {
    await mdRequireServer();
    final proxy = await NetProxy.start(Uri.parse(mdApiBaseUrl));
    addTearDown(proxy.close);
    await mdSetup(apiBaseUrl: proxy.baseUrl);
    await sharedPreferences.setInt(KEY_LISTS_OVERVIEW_TAB_INDEX, 0);
    await _mdRevisionSettings();
    await mdSignInAs(_mdOfflineUser, 'Md Offline');
    await mdWaitForAccountSync();
    await mdPumpApp(tester);
    mdClearSnackBars();

    // Connections refused (no network at all).
    await proxy.down();
    final first = await _mdOfflineRound(
      tester,
      navigateToEntryPage: navigateToEntryPage,
      name: _mdOfflineName,
      renamed: _mdOfflineRenamed,
      cardLimit: 10,
      skipEntries: 0,
    );

    // A black hole: connections accepted and never answered (a captive
    // portal, dead Wi-Fi). Nothing may wait for it either.
    await proxy.blackhole();
    final second = await _mdOfflineRound(
      tester,
      navigateToEntryPage: navigateToEntryPage,
      name: _mdBlackholeName,
      renamed: _mdBlackholeRenamed,
      cardLimit: 25,
      skipEntries: 2,
    );
    expect(proxy.requests, greaterThan(0), reason: 'the app tried meanwhile');

    // The sync status sheet says what is waiting and why.
    await _mdOpenSyncStatus(tester);
    expect(
      _mdSheetValue(tester, SyncStatusKeys.problem),
      mdL10n.syncStatusProblemNetwork,
    );
    expect(
      _mdSheetValue(tester, SyncStatusKeys.pending),
      isNot(mdL10n.syncStatusNothing),
    );
    await _mdCloseSheet(tester);

    // Back online (the app comes back to the foreground).
    await proxy.up();
    await sharing.accountSync.kick(SyncReason.resumed);
    await mdWaitForAccountSync();

    // Sync now on the sheet: nothing waiting, no problem.
    await _mdOpenSyncStatus(tester);
    await tester.tap(find.byKey(SyncStatusKeys.syncNow));
    await mdWaitForUi(
      tester,
      () =>
          _mdSheetValue(tester, SyncStatusKeys.pending) ==
              mdL10n.syncStatusNothing &&
          _mdSheetValue(tester, SyncStatusKeys.problem) == null,
      reason: 'the sheet says nothing is waiting after Sync now',
    );
    _mdNoSnackBar('synced now');
    await _mdCloseSheet(tester);
    final other = await MdOtherDevice.signIn(_mdOfflineUser);
    final lists = await other.liveLists();
    for (final (renamed, round) in [
      (_mdOfflineRenamed, first),
      (_mdBlackholeRenamed, second),
    ]) {
      expect(lists.keys, contains(renamed));
      expect((await other.entryKeys(lists[renamed]!)).toSet(), {
        for (final v in round.saved) v.entryKey,
      });
      expect(
        sharing.lists.ownerForSourceKey(EntryList.getKeyFromName(renamed)),
        isNotNull,
      );
    }
    expect(await other.answers(), hasLength(first.due + second.due));
    final settings = (await other.account())['settings'] as List;
    expect(
      settings.firstWhere((x) => x['key'] == KEY_REVISION_CARD_LIMIT)['value'],
      '25',
    );
    mdEmit('MD_OFFLINE_ANSWERS', '${first.due + second.due}');
  });
}

/// Open the sync status sheet from Settings.
Future<void> _mdOpenSyncStatus(WidgetTester tester) async {
  mdClearSnackBars();
  await mdTapWhenVisible(
    tester,
    mdNavIcon(Icons.settings),
    reason: 'Settings tab',
  );
  final row = find.byKey(const ValueKey('settings.syncStatusRow'));
  await mdWaitForUi(
    tester,
    () => row.evaluate().isNotEmpty,
    reason: 'the "Signed in with" row',
  );
  await tester.ensureVisible(row);
  await settle(tester);
  await tester.tap(row);
  await mdWaitForUi(
    tester,
    () => find.text(mdL10n.syncStatusTitle).evaluate().isNotEmpty,
    reason: 'the sync status sheet',
  );
}

/// A sync status sheet row's value, or null when the row isn't shown.
String? _mdSheetValue(WidgetTester tester, Key key) {
  final row = find.byKey(key);
  if (row.evaluate().isEmpty) return null;
  return tester
      .widgetList<Text>(find.descendant(of: row, matching: find.byType(Text)))
      .skip(1)
      .map((t) => t.data ?? '')
      .join('\n');
}

Future<void> _mdCloseSheet(WidgetTester tester) async {
  await tester.tapAt(const Offset(20, 20));
  await settle(tester);
}

/// One round of the offline suite, the proxy already down or a black hole:
/// make a list called [name], save two signs into it from their word pages,
/// rename it [renamed], revise it, and set the card limit to [cardLimit],
/// each through the real UI, each showing within a second with no snackbar;
/// then Settings reads "Waiting for a connection".
Future<({List<SavedVideo> saved, int due})> _mdOfflineRound(
  WidgetTester tester, {
  required NavigateToEntryPageFn navigateToEntryPage,
  required String name,
  required String renamed,
  required int cardLimit,
  required int skipEntries,
}) async {
  // Make a list.
  await mdOpenListsTab(tester);
  await mdOpenOverviewTab(tester, mdL10n.listMyLists);
  await mdTapWhenVisible(
    tester,
    find.byIcon(Icons.edit_outlined),
    reason: 'edit lists',
  );
  await mdTapWhenVisible(tester, find.byIcon(Icons.add), reason: 'new list');
  await tester.enterText(find.byType(TextField).last, name);
  await tester.tap(find.text(mdL10n.alertConfirm));
  final key = EntryList.getKeyFromName(name);
  await _mdWithin(
    tester,
    () =>
        userEntryListManager.getEntryLists().containsKey(key) &&
        find.text(name).evaluate().isNotEmpty,
    'making a list',
  );
  _mdNoSnackBar('made a list');
  await settle(tester);

  // Save two signs into it, from their word pages.
  final withVideo = entriesGlobal
      .where((e) => e.getSubEntries().any((s) => s.getMedia().isNotEmpty))
      .skip(skipEntries)
      .take(2)
      .toList();
  final saved = <SavedVideo>[];
  for (final entry in withVideo) {
    unawaited(
      navigateToEntryPage(rootNavigatorKey.currentContext!, entry, true),
    );
    await settle(tester);
    await mdTapWhenVisible(
      tester,
      find.byKey(const ValueKey('wordPage.saveButton')).first,
      reason: 'the save button on ${entry.getKey()}',
    );
    await tester.tap(find.byKey(ValueKey('saveVideoSheet.row.$key')));
    await _mdWithin(
      tester,
      () => userEntryListManager.getEntryLists()[key]!.savedVideos.any(
        (v) => v.entryKey == entry.getKey(),
      ),
      'saving ${entry.getKey()}',
    );
    saved.add(
      userEntryListManager.getEntryLists()[key]!.savedVideos.firstWhere(
        (v) => v.entryKey == entry.getKey(),
      ),
    );
    _mdNoSnackBar('saved a sign');
    // Close the sheet and the word page.
    await tester.tapAt(const Offset(20, 20));
    await settle(tester);
    await tester.pageBack();
    await settle(tester);
  }

  // Rename it.
  await mdOpenListsTab(tester);
  await mdTapWhenVisible(
    tester,
    find.byIcon(Icons.edit_outlined),
    reason: 'edit lists',
  );
  await mdTapWhenVisible(
    tester,
    find.text(name),
    reason: 'the new list in edit mode',
  );
  await tester.enterText(find.byType(TextField).last, renamed);
  await tester.tap(find.text(mdL10n.alertConfirm));
  await _mdWithin(
    tester,
    () => userEntryListManager.getEntryLists().values.any(
      (l) => l.getName() == renamed,
    ),
    'renaming the list',
  );
  _mdNoSnackBar('renamed');
  await settle(tester);
  final list = userEntryListManager.getEntryLists().values.firstWhere(
    (l) => l.getName() == renamed,
  );
  expect(list.savedVideos.length, 2);

  // A revision session on it.
  await sharedPreferences.setStringList(KEY_LISTS_TO_REVIEW, [list.key]);
  final page = await _mdOpenRevision(tester);
  page.updateRevisionSettings();
  await settle(tester);
  final due = _mdDue(page);
  expect(due, greaterThan(0));
  final before = reviewHistory.read().length;
  await _mdRunSession(tester, due);
  await _mdWithin(
    tester,
    () => reviewHistory.read().length == before + due,
    'storing the session',
  );
  _mdNoSnackBar('revised');

  // A revision setting: the card limit (scrolled into view first: on a
  // small phone it sits below the Start panel).
  await tester.ensureVisible(find.byType(DropdownButton<int>));
  await settle(tester);
  await tester.tap(find.byType(DropdownButton<int>));
  await settle(tester);
  await tester.tap(find.text('$cardLimit').last);
  await _mdWithin(
    tester,
    () => sharedPreferences.getInt(KEY_REVISION_CARD_LIMIT) == cardLimit,
    'changing the card limit',
  );
  _mdNoSnackBar('changed a setting');
  await settle(tester);

  // Settings says what's going on, and nothing else does.
  await mdTapWhenVisible(
    tester,
    mdNavIcon(Icons.settings),
    reason: 'Settings tab',
  );
  await mdWaitForUi(
    tester,
    () => find.text(mdL10n.accountSyncStatusWaiting).evaluate().isNotEmpty,
    reason: 'Settings reads "Waiting for a connection"',
  );
  _mdNoSnackBar('offline');
  return (saved: saved, due: due);
}

/// The second run of the offline/online pair: a fresh install signing in as
/// the same person has both lists (renamed, with their signs), the answers
/// and the setting.
void runSoloOfflineOnlineAfter(MdSuiteConfig cfg) {
  mdConfig = cfg;
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('another device has everything done offline', (tester) async {
    await mdRequireServer();
    await mdSetup();
    final other = await MdOtherDevice.signIn(_mdOfflineUser);
    final lists = await other.liveLists();
    final keys = <String, Set<String>>{};
    for (final name in [_mdOfflineRenamed, _mdBlackholeRenamed]) {
      expect(lists.keys, contains(name), reason: 'run first');
      keys[name] = (await other.entryKeys(lists[name]!)).toSet();
    }
    final answers = (await other.answers()).length;
    await mdSignInAs(_mdOfflineUser, 'Md Offline');
    await mdWaitForAccountSync();
    for (final name in keys.keys) {
      expect(mdLocalKeys(name), keys[name]);
    }
    expect(reviewHistory.read(), hasLength(answers));
    expect(sharedPreferences.getInt(KEY_REVISION_CARD_LIMIT), 25);
    await mdPumpApp(tester);
    mdClearSnackBars();
    await mdExpectListOnScreen(tester, _mdOfflineRenamed);
    await mdExpectListOnScreen(tester, _mdBlackholeRenamed);
  });
}

// -------- Shared helpers for the suites below --------

/// Sign out the way a person does: Settings → Sign out → Confirm.
Future<void> _mdSignOutThroughSettings(WidgetTester tester) async {
  mdClearSnackBars();
  await mdTapWhenVisible(
    tester,
    mdNavIcon(Icons.settings),
    reason: 'Settings tab',
  );
  final row = find.text(mdL10n.settingsSignOutRow);
  await mdWaitForUi(
    tester,
    () => row.evaluate().isNotEmpty,
    reason: 'the Sign out row',
  );
  await tester.ensureVisible(row);
  await settle(tester);
  await tester.tap(row);
  await settle(tester);
  await mdTapWhenVisible(
    tester,
    find.text(mdL10n.alertConfirm),
    reason: 'confirm signing out',
  );
  await mdWaitForUi(
    tester,
    () => sharing.auth.store.current == null,
    reason: 'signed out',
  );
  await _mdSettingsRowVisible(tester, mdL10n.settingsSignInRow);
}

/// Scroll the Settings page (a lazy list) until the row called [text] is
/// built and on screen: the Sharing and syncing section shrinks when the
/// person signs out, which can leave it above the viewport.
Future<void> _mdSettingsRowVisible(WidgetTester tester, String text) async {
  final row = find.text(text);
  final list = find
      .descendant(
        of: find.byType(SettingsPage),
        matching: find.byType(Scrollable),
      )
      .first;
  for (var i = 0; i < 20 && row.evaluate().isEmpty; i++) {
    await tester.drag(list, const Offset(0, 300));
    await settle(tester);
  }
  for (var i = 0; i < 20 && row.evaluate().isEmpty; i++) {
    await tester.drag(list, const Offset(0, -300));
    await settle(tester);
  }
  expect(row, findsWidgets, reason: 'Settings shows "$text"');
}

/// Make a list called [name] through My Lists (edit, +, name, Confirm).
Future<void> _mdMakeListThroughUi(WidgetTester tester, String name) async {
  mdClearSnackBars();
  await mdOpenListsTab(tester);
  await mdOpenOverviewTab(tester, mdL10n.listMyLists);
  await mdTapWhenVisible(
    tester,
    find.byIcon(Icons.edit_outlined),
    reason: 'edit lists',
  );
  await mdTapWhenVisible(tester, find.byIcon(Icons.add), reason: 'new list');
  await tester.enterText(find.byType(TextField).last, name);
  await tester.tap(find.text(mdL10n.alertConfirm));
  await mdWaitForUi(
    tester,
    () => userEntryListManager.getEntryLists().containsKey(
      EntryList.getKeyFromName(name),
    ),
    reason: 'the list "$name" made',
  );
}

/// Names of the live lists in [other]'s account directory, each as often
/// as it appears.
Future<List<String>> _mdLiveNames(MdOtherDevice other) async {
  final dir = (await other.account())['directory'] as List;
  return [
    for (final r in dir)
      if (r['state'] == 'live') r['name'] as String,
  ]..sort();
}

// -------- Follows across devices --------

/// The person following, the person sharing, and the list (from the first
/// run, through the driver).
String get _mdFollowUser => mdSyncUser('follow');
String get _mdSharerUser => 'test:md-$mdRunId-sharer';
const String _mdFollowedName = 'Md Shared With Me';
const String _mdFollowListId = String.fromEnvironment('MD_FOLLOW_LIST_ID');

/// Follow 1, device A (kept installed for follow 3): someone else shares a
/// list; this device, signed in, follows it from the link, and the follow
/// reaches the account.
void runFollowFirstDevice(MdSuiteConfig cfg) {
  mdConfig = cfg;
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('device A follows a shared list from its link', (tester) async {
    await mdRequireServer();
    await mdSetup();
    await sharedPreferences.setInt(KEY_LISTS_OVERVIEW_TAB_INDEX, 0);
    await mdSignInAs(_mdFollowUser, 'Md Follow');
    await mdWaitForAccountSync();
    final sharer = await MdOtherDevice.signIn(_mdSharerUser);
    final listId = await sharer.oldBuildShare(_mdFollowedName, mdVideos(2));
    await mdPumpApp(tester);
    mdClearSnackBars();

    // The link arrives as the OS hands it over.
    final payload = extractSharePayload(
      Uri.parse(sharing.config.shareUrlFor(listId)),
      sharing.config,
    );
    expect(payload, isNotNull);
    GoRouter.of(rootNavigatorKey.currentContext!)
        .push(payload!.toRouteLocation());
    await mdWaitForUi(
      tester,
      () =>
          find.text(_mdFollowedName).evaluate().isNotEmpty &&
          sharing.lists.get(listId)?.meta.role == ListRole.subscriber,
      reason: 'the followed list on Subscribed',
    );
    await mdWaitForAccountSync();
    final me = await MdOtherDevice.signIn(_mdFollowUser);
    expect((await me.account())['follows'], contains(listId));
    mdEmit('MD_FOLLOW_LIST_ID', listId);
  });
}

/// Follow 2, device B: signing in as the same person brings the follow to
/// Subscribed; unfollowing it here takes it off the account.
void runFollowSecondDevice(MdSuiteConfig cfg) {
  mdConfig = cfg;
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('device B has the follow, and unfollows it', (tester) async {
    await mdRequireServer();
    expect(_mdFollowListId, isNotEmpty, reason: 'follow 1 ran first');
    await mdSetup();
    await mdSignInAs(_mdFollowUser, 'Md Follow');
    await mdWaitForAccountSync();
    expect(sharing.lists.get(_mdFollowListId)?.meta.role, ListRole.subscriber);
    await mdPumpApp(tester);
    mdClearSnackBars();
    await mdOpenListsTab(tester);
    await mdOpenOverviewTab(tester, mdL10n.listSharedWithMeTab);
    await mdTapWhenVisible(
      tester,
      find.text(_mdFollowedName),
      reason: 'the followed list on Subscribed',
    );
    await mdTapWhenVisible(
      tester,
      find.byTooltip('Show menu'),
      reason: "the list page's menu",
    );
    await mdTapWhenVisible(
      tester,
      find.text(mdL10n.unsubscribeConfirmTitle),
      reason: 'Unsubscribe in the menu',
    );
    await mdTapWhenVisible(
      tester,
      find.text(mdL10n.alertConfirm),
      reason: 'confirm unsubscribing',
    );
    await mdWaitForUi(
      tester,
      () => sharing.lists.get(_mdFollowListId) == null,
      reason: 'unfollowed here',
    );
    await mdWaitForAccountSync();
    final me = await MdOtherDevice.signIn(_mdFollowUser);
    expect((await me.account())['follows'], isNot(contains(_mdFollowListId)));
  });
}

/// Follow 3, device A again, on the install follow 1 left: the list it
/// followed is still here until it syncs, then it goes from Subscribed.
void runFollowFirstDeviceAgain(MdSuiteConfig cfg) {
  mdConfig = cfg;
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('device A loses the follow B dropped', (tester) async {
    await mdRequireServer();
    expect(_mdFollowListId, isNotEmpty, reason: 'follow 1 ran first');
    await mdSetup();
    expect(
      sharing.auth.store.current?.userId,
      _mdFollowUser,
      reason: 'the install follow 1 left (run with --no-uninstall)',
    );
    expect(
      sharing.lists.get(_mdFollowListId),
      isNotNull,
      reason: 'followed here before this device syncs',
    );
    await mdPumpApp(tester);
    mdClearSnackBars();
    await mdWaitForAccountSync();
    await mdOpenListsTab(tester);
    await mdOpenOverviewTab(tester, mdL10n.listSharedWithMeTab);
    await mdWaitForUi(
      tester,
      () =>
          sharing.lists.get(_mdFollowListId) == null &&
          find.text(_mdFollowedName).evaluate().isEmpty,
      reason: 'the follow B dropped is gone from Subscribed here',
    );
  });
}

// -------- Solo: two accounts on one device --------

/// Sign in as A, out, in as B (the device's lists go into B's account),
/// make a list under B, out, and back in as A: A's lists plus the one made
/// under B, each once.
void runSoloAccountSwitch(MdSuiteConfig cfg) {
  mdConfig = cfg;
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('switching accounts on one device: nothing doubled', (
    tester,
  ) async {
    await mdRequireServer();
    await mdSetup();
    await sharedPreferences.setInt(KEY_LISTS_OVERVIEW_TAB_INDEX, 0);
    final userA = mdSyncUser('switch-a');
    final userB = mdSyncUser('switch-b');
    final v = mdVideos(2);
    await mdLocalList('Before switch', [v[0]]);
    await mdSignInAs(userA, 'Md Switch A');
    await mdWaitForAccountSync();
    final a = await MdOtherDevice.signIn(userA);
    final favourites = userEntryListManager
        .getEntryLists()[userEntryListManager.defaultListKey]!
        .getName();
    expect(await _mdLiveNames(a), [favourites, 'Before switch']..sort());
    await mdPumpApp(tester);

    await _mdSignOutThroughSettings(tester);
    await sharing.auth.signInWithTestToken(
      testAuthToken: mdTestAuthToken,
      userId: userB,
      displayName: 'Md Switch B',
    );
    await mdWaitForAccountSync();
    final b = await MdOtherDevice.signIn(userB);
    expect(
      await _mdLiveNames(b),
      [favourites, 'Before switch']..sort(),
      reason: "the device's lists went into B's account",
    );
    await _mdMakeListThroughUi(tester, 'Made under B');
    await mdWaitForAccountSync();
    expect(
      await _mdLiveNames(b),
      [favourites, 'Before switch', 'Made under B']..sort(),
    );

    await _mdSignOutThroughSettings(tester);
    await sharing.auth.signInWithTestToken(
      testAuthToken: mdTestAuthToken,
      userId: userA,
      displayName: 'Md Switch A',
    );
    await mdWaitForAccountSync();
    final want = [favourites, 'Before switch', 'Made under B']..sort();
    expect(await _mdLiveNames(a), want, reason: "A's account, each once");
    expect(
      [for (final l in userEntryListManager.getEntryLists().values) l.getName()]
        ..sort(),
      want,
      reason: 'the device, each once',
    );
    expect(await _mdLiveNames(b), want, reason: "B's account unchanged");
    await mdExpectListOnScreen(tester, 'Made under B');
    for (final name in want) {
      expect(find.text(name), findsOneWidget, reason: '$name once on screen');
    }
  });
}

// -------- Account deletion seen from the other device --------

String get _mdDeleteUser => mdSyncUser('delete');
const String _mdKeptName = 'Kept after deletion';

/// Deletion 1, device B (kept installed for deletion 3): signed in, with a
/// list and answers on the account.
void runDeletionOtherDeviceBefore(MdSuiteConfig cfg) {
  mdConfig = cfg;
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('device B: signed in, a list and answers', (tester) async {
    await mdRequireServer();
    await mdSetup();
    await reviewHistory.reset(DateTime.now().microsecondsSinceEpoch);
    final v = mdVideos(2);
    await mdLocalList(_mdKeptName, v);
    await mdSignInAs(_mdDeleteUser, 'Md Delete');
    await mdWaitForAccountSync();
    await sharing.accountSync.recordAnswers([
      ..._mdLearnedAndResting(v[0]),
      ..._mdLearnedAndResting(v[1]),
    ]);
    await mdWaitForAccountSync();
    final other = await MdOtherDevice.signIn(_mdDeleteUser);
    expect((await other.liveLists()).keys, contains(_mdKeptName));
    expect(await other.answers(), hasLength(4));
  });
}

/// Deletion 2, device A: signs in as the same person and deletes the
/// account through Settings.
void runDeletionDeletingDevice(MdSuiteConfig cfg) {
  mdConfig = cfg;
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('device A deletes the account', (tester) async {
    await mdRequireServer();
    await mdSetup();
    await mdSignInAs(_mdDeleteUser, 'Md Delete');
    await mdWaitForAccountSync();
    expect(mdLocalKeys(_mdKeptName), isNotNull, reason: "B's list came");
    await mdPumpApp(tester);
    mdClearSnackBars();
    await mdTapWhenVisible(
      tester,
      mdNavIcon(Icons.settings),
      reason: 'Settings tab',
    );
    final row = find.text(mdL10n.settingsDeleteAccount);
    await mdWaitForUi(
      tester,
      () => row.evaluate().isNotEmpty,
      reason: 'the Delete account row',
    );
    await tester.ensureVisible(row.first);
    await settle(tester);
    await tester.tap(row.first);
    await settle(tester);
    await mdTapWhenVisible(
      tester,
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text(mdL10n.settingsDeleteAccountConfirmButton),
      ),
      reason: 'confirm deleting the account',
    );
    await mdWaitForUi(
      tester,
      () => sharing.auth.store.current == null,
      reason: 'signed out, the account gone',
      timeout: const Duration(seconds: 40),
    );
    await _mdSettingsRowVisible(tester, mdL10n.settingsSignInRow);
    // A new session finds an empty, new account. (Issued in a later
    // second than the deletion: the Worker refuses sessions issued up to
    // the second the account was deleted in, which sessions can't be told
    // apart within.)
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    final fresh = await MdOtherDevice.signIn(_mdDeleteUser);
    expect(await fresh.liveLists(), isEmpty);
    expect(await fresh.answers(), isEmpty);
  });
}

/// Deletion 3, device B again, on the install deletion 1 left: its next sync
/// finds the account gone and says so (signed out); it keeps every list and
/// answer, and signing in again starts a new account from them.
void runDeletionOtherDeviceAfter(MdSuiteConfig cfg) {
  mdConfig = cfg;
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('device B: signed out by the deletion, keeps everything', (
    tester,
  ) async {
    await mdRequireServer();
    await mdSetup();
    expect(
      sharing.auth.store.current?.userId,
      _mdDeleteUser,
      reason: 'the install deletion 1 left (run with --no-uninstall)',
    );
    final lists = {
      for (final l in userEntryListManager.getEntryLists().values)
        l.getName(): {for (final v in l.savedVideos) v.entryKey},
    };
    final answers = reviewHistory.read().length;
    expect(lists.keys, contains(_mdKeptName));
    expect(answers, 4);

    await mdPumpApp(tester);
    await mdWaitForUi(
      tester,
      () => find.text(mdL10n.engineSessionExpiredSnack).evaluate().isNotEmpty,
      reason: 'the next sync says the session is over',
      timeout: const Duration(seconds: 40),
    );
    expect(sharing.auth.store.current, isNull);
    expect({
      for (final l in userEntryListManager.getEntryLists().values)
        l.getName(): {for (final v in l.savedVideos) v.entryKey},
    }, lists);
    expect(reviewHistory.read(), hasLength(answers));

    // Signing in again: a new account, made from this device's lists and
    // answers.
    mdClearSnackBars();
    await mdSignInAs(_mdDeleteUser, 'Md Delete');
    await mdWaitForAccountSync();
    final other = await MdOtherDevice.signIn(_mdDeleteUser);
    final live = await other.liveLists();
    expect(live.keys.toSet(), lists.keys.toSet());
    expect(
      (await other.entryKeys(live[_mdKeptName]!)).toSet(),
      lists[_mdKeptName],
    );
    expect(await other.answers(), hasLength(answers));
    await mdExpectListOnScreen(tester, _mdKeptName);
  });
}

// -------- Solo: a heavy account --------

/// Twenty lists of fifty signs and two thousand answers, made on the
/// account over HTTP (another device of the same person); this device signs
/// in with the app on screen. The UI must keep answering taps during the
/// merge, and the Revision tab (revising all twenty lists) must open within
/// a few seconds once it is done. The timings go to the log
/// (`MD_OUT HEAVY_*`) for the progress file.
void runSoloHeavyAccount(MdSuiteConfig cfg) {
  mdConfig = cfg;
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('a heavy account: responsive during the merge, Revision quick '
      'after', (tester) async {
    await mdRequireServer();
    await mdSetup();
    await reviewHistory.reset(DateTime.now().microsecondsSinceEpoch);
    await _mdRevisionSettings();
    final user = mdSyncUser('heavy');
    final other = await MdOtherDevice.signIn(user);
    final videos = mdVideos(250);

    // Twenty private lists of fifty signs.
    final ids = <String>[];
    for (var start = 0; start < 20; start += 10) {
      final ops = <Map<String, dynamic>>[];
      for (var i = start; i < start + 10; i++) {
        final id = generateListId();
        ids.add(id);
        ops.add({
          'type': 'createList',
          'args': {
            'requestId': generateOpId(),
            'listId': id,
            'name': 'Heavy ${i + 1}',
            'visibility': 'private',
          },
        });
      }
      final out = await other.account(ops);
      for (final r in out['results'] as List) {
        expect(r['status'], 'applied', reason: 'create: $r');
      }
    }
    for (var i = 0; i < 20; i++) {
      final entries = videos.skip(i * 10).take(50).toList();
      final r = await http.post(
        Uri.parse('$mdApiBaseUrl/v1/lists/${ids[i]}/sync'),
        headers: other._headers(),
        body: jsonEncode({
          'lastKnownSeq': 0,
          'ops': [
            {
              'opId': other._opId(),
              'type': 'addEntries',
              'args': {
                'entries': [for (final v in entries) v.toJson()],
              },
              'clientTs': DateTime.now().millisecondsSinceEpoch ~/ 1000,
            },
          ],
        }),
      );
      expect(r.statusCode, 200, reason: 'seed list $i: ${r.body}');
    }
    // Two thousand answers over the last hundred days, on those signs.
    final now = DateTime.now();
    final answers = [
      for (var i = 0; i < 2000; i++)
        reviewToWire(
          Review(
            master: savedVideoMasterId(videos[i % 240]),
            combination: const Combination(front: [1], back: [0]),
            rating: Rating.Good,
            ts: now.subtract(Duration(minutes: 72 * (2000 - i))),
          ),
        ),
    ];
    for (var start = 0; start < answers.length; start += 200) {
      await other.account([
        {
          'type': 'addReviews',
          'args': {'reviews': answers.sublist(start, start + 200)},
        },
      ]);
    }
    // Revise all twenty (a synced setting, so it comes with the merge).
    await other.account([
      {
        'type': 'setSetting',
        'args': {
          'key': KEY_LISTS_TO_REVIEW,
          'value': jsonEncode([for (final id in ids) 'list:$id']),
        },
      },
    ]);
    expect(await other.answers(), hasLength(2000));

    // Sign in with the app on screen, and use it while the merge runs.
    await mdPumpApp(tester);
    mdClearSnackBars();
    final merge = Stopwatch()..start();
    await sharing.auth.signInWithTestToken(
      testAuthToken: mdTestAuthToken,
      userId: user,
      displayName: 'Md Heavy',
    );
    final tabs = [Icons.view_list, Icons.style, Icons.settings, Icons.search];
    final taps = <int>[];
    var t = 0;
    do {
      final target = t % tabs.length;
      final sw = Stopwatch()..start();
      await tester.tap(mdNavIcon(tabs[target]));
      while (tester
              .widget<BottomNavigationBar>(find.byType(BottomNavigationBar))
              .currentIndex !=
          [1, 2, 3, 0][target]) {
        if (sw.elapsed > const Duration(seconds: 10)) {
          fail('a tab tap went unanswered for 10 s during the merge');
        }
        await tester.pump(const Duration(milliseconds: 16));
      }
      taps.add(sw.elapsedMilliseconds);
      t++;
      await tester.pump(const Duration(milliseconds: 200));
      if (merge.isRunning && (sharing.accountSync.state?.mergeDone ?? false)) {
        merge.stop();
      }
      // Taps all through the merge, and a few after it (a fast machine can
      // finish the merge within the first one).
    } while ((merge.isRunning || taps.length < 8) &&
        merge.elapsed < const Duration(minutes: 3));
    merge.stop();
    expect(sharing.accountSync.state?.mergeDone, isTrue, reason: 'merged');
    await mdWaitForAccountSync();
    expect(reviewHistory.read(), hasLength(2000));
    final slowest = taps.reduce((a, b) => a > b ? a : b);
    mdEmit('HEAVY_MERGE_MS', '${merge.elapsedMilliseconds}');
    mdEmit('HEAVY_TAPS', '${taps.length}');
    mdEmit('HEAVY_SLOWEST_TAP_MS', '$slowest');
    expect(
      slowest,
      lessThan(2000),
      reason: 'every tap answered within 2 s during the merge ($taps ms)',
    );

    // The Revision tab, revising the twenty lists with the 2,000 answers.
    await mdTapWhenVisible(
      tester,
      mdNavIcon(Icons.search),
      reason: 'Search tab',
    );
    final open = Stopwatch()..start();
    await tester.tap(mdNavIcon(Icons.style));
    await mdWaitForUi(
      tester,
      () =>
          find.byKey(const ValueKey('startButton')).evaluate().isNotEmpty &&
          tester
                  .state<FlashcardsLandingPageState>(
                    find.byType(FlashcardsLandingPage),
                  )
                  .entryListsToRevise
                  .length ==
              20,
      reason: 'the Revision page with the twenty lists',
    );
    open.stop();
    mdEmit('HEAVY_REVISION_OPEN_MS', '${open.elapsedMilliseconds}');
    expect(
      open.elapsed,
      lessThan(const Duration(seconds: 10)),
      reason: 'the Revision tab opens within a few seconds',
    );
  });
}
