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
import 'package:dolphinsr/dolphinsr.dart' show Combination, Review;
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
    await mdPumpApp(tester);
    await mdExpectListOnScreen(tester, 'Garden birds');
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
  });
}

// -------- Solo: offline, then online --------

/// The person behind [mdSyncUser] for the offline/online pair.
String get _mdOfflineUser => mdSyncUser('offline');

const String _mdOfflineName = 'Offline list';
const String _mdOfflineRenamed = 'Offline renamed';

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
  testWidgets('offline: everything shows at once; online: it all goes up', (
    tester,
  ) async {
    await mdRequireServer();
    final proxy = await NetProxy.start(Uri.parse(mdApiBaseUrl));
    addTearDown(proxy.close);
    await mdSetup(apiBaseUrl: proxy.baseUrl);
    await sharedPreferences.setInt(KEY_LISTS_OVERVIEW_TAB_INDEX, 0);
    await _mdRevisionSettings();
    await mdSignInAs(_mdOfflineUser, 'Md Offline');
    await mdWaitForAccountSync();

    await proxy.down();
    await mdPumpApp(tester);
    mdClearSnackBars();

    // Make a list.
    await mdOpenListsTab(tester);
    await mdOpenOverviewTab(tester, mdL10n.listMyLists);
    await mdTapWhenVisible(
      tester,
      find.byIcon(Icons.edit_outlined),
      reason: 'edit lists',
    );
    await mdTapWhenVisible(tester, find.byIcon(Icons.add), reason: 'new list');
    await tester.enterText(find.byType(TextField).last, _mdOfflineName);
    await tester.tap(find.text(mdL10n.alertConfirm));
    final key = EntryList.getKeyFromName(_mdOfflineName);
    await _mdWithin(
      tester,
      () =>
          userEntryListManager.getEntryLists().containsKey(key) &&
          find.text(_mdOfflineName).evaluate().isNotEmpty,
      'making a list',
    );
    _mdNoSnackBar('made a list');
    await settle(tester);

    // Save two signs into it, from their word pages.
    final saved = <SavedVideo>[];
    for (final entry in [
      mdEntryWithVideo(),
      mdEntryWithVideo(exclude: {mdEntryWithVideo().getKey()}),
    ]) {
      final video = SavedVideo(
        entryKey: entry.getKey(),
        mediaPath: entry
            .getSubEntries()
            .firstWhere((s) => s.getMedia().isNotEmpty)
            .getMedia()
            .first,
      );
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
        () =>
            userEntryListManager.getEntryLists()[key]!.savedVideos.isNotEmpty &&
            userEntryListManager.getEntryLists()[key]!.savedVideos.any(
              (v) => v.entryKey == video.entryKey,
            ),
        'saving ${entry.getKey()}',
      );
      saved.add(
        userEntryListManager.getEntryLists()[key]!.savedVideos.firstWhere(
          (v) => v.entryKey == video.entryKey,
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
      find.text(_mdOfflineName),
      reason: 'the new list in edit mode',
    );
    await tester.enterText(find.byType(TextField).last, _mdOfflineRenamed);
    await tester.tap(find.text(mdL10n.alertConfirm));
    final renamedKey = EntryList.getKeyFromName(_mdOfflineRenamed);
    await _mdWithin(
      tester,
      () => userEntryListManager.getEntryLists().values.any(
        (l) => l.getName() == _mdOfflineRenamed,
      ),
      'renaming the list',
    );
    _mdNoSnackBar('renamed');
    await settle(tester);
    final renamed = userEntryListManager.getEntryLists().values.firstWhere(
      (l) => l.getName() == _mdOfflineRenamed,
    );
    expect(renamed.savedVideos.length, 2);

    // A revision session on it.
    await sharedPreferences.setStringList(KEY_LISTS_TO_REVIEW, [renamed.key]);
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

    // A revision setting: the card limit.
    await tester.tap(find.byType(DropdownButton<int>));
    await settle(tester);
    await tester.tap(find.text('10').last);
    await _mdWithin(
      tester,
      () => sharedPreferences.getInt(KEY_REVISION_CARD_LIMIT) == 10,
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

    // Back online (the app comes back to the foreground).
    await proxy.up();
    await sharing.accountSync.kick(SyncReason.resumed);
    await mdWaitForAccountSync();
    final other = await MdOtherDevice.signIn(_mdOfflineUser);
    final lists = await other.liveLists();
    expect(lists.keys, contains(_mdOfflineRenamed));
    expect((await other.entryKeys(lists[_mdOfflineRenamed]!)).toSet(), {
      for (final v in saved) v.entryKey,
    });
    expect(sharing.lists.ownerForSourceKey(renamedKey), isNotNull);
    expect(await other.answers(), hasLength(due));
    final settings = (await other.account())['settings'] as List;
    expect(
      settings.firstWhere((x) => x['key'] == KEY_REVISION_CARD_LIMIT)['value'],
      '10',
    );
    mdEmit('MD_OFFLINE_ANSWERS', '$due');
  });
}

/// The second run of the offline/online pair: a fresh install signing in as
/// the same person has the list (renamed, with its signs), the answers and
/// the setting.
void runSoloOfflineOnlineAfter(MdSuiteConfig cfg) {
  mdConfig = cfg;
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('another device has everything done offline', (tester) async {
    await mdRequireServer();
    await mdSetup();
    final other = await MdOtherDevice.signIn(_mdOfflineUser);
    final lists = await other.liveLists();
    expect(lists.keys, contains(_mdOfflineRenamed), reason: 'run first');
    final keys = (await other.entryKeys(lists[_mdOfflineRenamed]!)).toSet();
    final answers = (await other.answers()).length;
    await mdSignInAs(_mdOfflineUser, 'Md Offline');
    await mdWaitForAccountSync();
    expect(mdLocalKeys(_mdOfflineRenamed), keys);
    expect(reviewHistory.read(), hasLength(answers));
    expect(sharedPreferences.getInt(KEY_REVISION_CARD_LIMIT), 10);
    await mdPumpApp(tester);
    mdClearSnackBars();
    await mdExpectListOnScreen(tester, _mdOfflineRenamed);
  });
}
