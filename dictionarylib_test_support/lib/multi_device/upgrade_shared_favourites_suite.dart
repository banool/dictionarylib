// Multi-device e2e, but one device and one person: the update that made
// Favourites an ordinary list, landing on the install with the most to lose.
//
// That is someone signed in, with their favourites shared. The share is
// stored against the list's storage key, the update moves the list to a new
// key, and sharing drops any share whose list it can't find. The single-
// device suite (default_list_migration_suite.dart) covers the move on a
// signed-out install with a made-up share; this is the same move with a
// session that is real and a share the worker knows about, so that what
// comes after can be checked too: the app is still signed in, and a sign
// saved to the list after the update reaches the worker.
//
// What the old version left behind is put in place before the app starts:
// the list and the session on the worker (made the way the app makes them),
// the session in the device's secure storage, and the old storage layout as
// a released build wrote it.

import 'dart:convert';

import 'package:dictionarylib/dictionarylib.dart';
import 'package:dictionarylib/list_storage.dart';
import 'package:dictionarylib/saved_video.dart';
import 'package:dictionarylib/sharing/auth/auth_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import '../helpers.dart';
import 'md_common.dart';

const String _oldKey = 'favourites_words';
const String _shareName = 'Tiny Tunks';

/// [storedVideos]: three saved videos from three entries, as a list stores
/// them (the app's test config has them; see DictAppTestConfig.storedVideos).
void runUpgradeWithSharedFavourites(
  MdSuiteConfig cfg, {
  required List<String> storedVideos,
}) {
  mdConfig = cfg;
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('an install with favourites shared and its owner signed in '
      'takes the update, keeps the share and goes on syncing', (
    WidgetTester tester,
  ) async {
    await mdRequireServer();
    expect(storedVideos.length, greaterThanOrEqualTo(3));
    final videos = [for (final s in storedVideos) SavedVideo.tryParse(s)!];
    final userId = 'test:md-$mdRunId-upgrade';
    const userName = 'Md Upgrader';

    // --- What the old version left behind. ---
    final config = mdSharingConfig();
    final auth = AuthService(
      config: config,
      api: AuthApi(config),
      store: AuthStore(),
    );
    // Signing in stores the session where the app will look for it.
    final session = await auth.signInWithTestToken(
      testAuthToken: mdTestAuthToken,
      userId: userId,
      displayName: userName,
    );
    auth.dispose();
    final api = SyncApi(config);
    final listId = generateListId();
    final created = await api.createList(
      listId: listId,
      displayName: _shareName,
      entries: videos.sublist(0, 2),
      sessionToken: session.sessionToken,
    );
    api.close();

    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    await prefs.setStringList('word_list_keys', [_oldKey]);
    await prefs.setStringList(_oldKey, storedVideos.sublist(0, 2));
    await prefs.setInt('${_oldKey}_schemaVersion', 3);
    await prefs.setStringList('lists_chosen_to_review', [_oldKey]);
    await prefs.setStringList('shared_list_ids', [listId]);
    // The share's details in the shape a released build stored them.
    await prefs.setString(
      'shared_${listId}_meta',
      jsonEncode({
        'schemaVersion': 2,
        'listId': listId,
        'displayName': _shareName,
        'role': 'owner',
        'lastKnownSeq': created.lastSeq,
        'etag': null,
        'lastSyncedAt': created.updatedAt,
        'serverUpdatedAt': created.updatedAt,
        'orphaned': false,
        'sourceLocalKey': _oldKey,
        'pendingOps': <Object>[],
        'cachedMembers': {
          'owner': {'userId': userId, 'displayName': userName},
          'editors': <Object>[],
        },
      }),
    );

    // --- The update's first launch. ---
    await mdSetup();

    final newKey = EntryList.getKeyFromName(mdL10n.favouritesListName);
    expect(userEntryListManager.defaultListKey, newKey);
    expect(sharedPreferences.getString(KEY_DEFAULT_LIST_KEY), newKey);
    expect(sharedPreferences.get(_oldKey), isNull);
    expect(sharedPreferences.getStringList(newKey), storedVideos.sublist(0, 2));

    // Still signed in, and the share is still this list's.
    expect(sharing.auth.store.current?.userId, userId);
    final share = sharing.lists.ownerForSourceKey(newKey);
    expect(share, isNotNull, reason: 'the share was dropped by the update');
    expect(share!.listId, listId);
    expect(share.getName(), _shareName);
    expect(loadListsToReview(), [newKey]);

    await sharedPreferences.setInt(KEY_LISTS_OVERVIEW_TAB_INDEX, 0);
    await sharedPreferences.setInt(
      KEY_REVISION_STRATEGY,
      RevisionStrategy.SpacedRepetition.index,
    );
    await sharedPreferences.setBool(KEY_WORD_TO_SIGN, false);
    await sharedPreferences.setBool(KEY_SIGN_TO_WORD, true);

    await mdPumpApp(tester);

    // --- The Lists page has it under the name it is shared as. ---
    await mdOpenListsTab(tester);
    await mdOpenOverviewTab(tester, mdL10n.listMyLists);
    final row = find.byKey(ValueKey(newKey));
    expect(find.descendant(of: row, matching: find.text(_shareName)), findsOne);
    expect(find.text(mdL10n.favouritesListName), findsNothing);

    // --- A sign saved to it now (the way the app saves to a shared list)
    // reaches the worker. ---
    await share.addVideo(videos[2]);
    await mdWaitFor(
      tester,
      () async => (await mdServerEntryKeys(listId)).length == 3,
      reason: 'the sign saved after the update should reach the worker',
    );
    final state = await mdServerState(listId);
    expect(
      state.entryKeys,
      unorderedEquals([for (final v in videos.sublist(0, 3)) v.entryKey]),
    );
    expect(state.displayName, _shareName);
    expect(state.ownerUserId, userId);
    // The worker took it from this session: nobody has been signed out.
    expect(sharing.auth.store.current?.userId, userId);
    expect(sharing.lists.ownerForSourceKey(newKey), isNotNull);
    expect(sharedPreferences.getStringList(newKey), storedVideos.sublist(0, 3));

    // Account sync's first run (the sign-in merge, started a few seconds
    // after launch) ends with a snackbar; let it finish and clear it so it
    // doesn't sit over the Start button.
    await mdWaitForAccountSync();
    mdClearSnackBars();
    await settle(tester);

    // --- And it is what revision draws from, by that name. ---
    await mdTapWhenVisible(
      tester,
      mdNavIcon(Icons.style),
      reason: 'Revision tab icon in the bottom navigation',
    );
    expect(find.text(_shareName), findsOneWidget);
    expect(find.text(mdL10n.revisionFlashcardCount(3)), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('startButton')));
    await settle(tester);
    expect(find.text('1 / 3'), findsOneWidget);
    await tester.tap(find.widgetWithIcon(IconButton, Icons.close));
    await settle(tester);
  });
}
