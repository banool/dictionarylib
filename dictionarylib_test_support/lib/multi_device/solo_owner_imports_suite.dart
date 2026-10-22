// Multi-device e2e, but one device and one person: a list arriving on a
// device under the one name a list on the device can't have.
//
// A list's storage key is made from its name, and "search for" makes the key
// the search page keeps one of its settings under. A list stored there broke
// every search, so the name is refused when a list is made or renamed on the
// device (default_list_suite.dart). A share can be called anything, though,
// and someone who shared a list as "search for" on one device gets it on
// their others when they sign in. There it takes the next free key instead,
// keeps its name, and search goes on working.

import 'package:dictionarylib/dictionarylib.dart';
import 'package:dictionarylib/saved_video.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../config.dart';
import '../helpers.dart';
import 'md_common.dart';

const String _shareName = 'search for';

void runSoloOwnerImports(MdSuiteConfig cfg) {
  mdConfig = cfg;
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a list its owner shared as "search for" arrives on another of '
      'their devices under that name, and search still works', (
    WidgetTester tester,
  ) async {
    await mdRequireServer();
    await mdSetup();

    // Someone new each time, so that the one list made below is all the
    // worker has for them however often this is run against it. (The worker
    // takes a test user id of up to 32 characters after "test:".)
    final now = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    final userId = 'test:md-$mdRunId-i-$now';
    await mdSignInAs(userId, 'Md Importer');
    expect(
      userEntryListManager.getEntryLists().keys.where(
        (key) => key.startsWith('search_for'),
      ),
      isEmpty,
      reason: 'expected an install with no such list yet',
    );

    // What they did on their other device: shared a list under that name.
    final entry = mdEntryWithVideo();
    final video = SavedVideo(
      entryKey: entry.getKey(),
      mediaPath: entry
          .getSubEntries()
          .firstWhere((s) => s.getMedia().isNotEmpty)
          .getMedia()
          .first,
    );
    final listId = generateListId();
    await sharing.api.createList(
      listId: listId,
      displayName: _shareName,
      entries: [video],
      sessionToken: sharing.auth.store.current!.sessionToken,
    );

    // This device fetches their lists, as it does once they have signed in.
    final result = await listsService.importEditableLists();
    expect(result.imported, 1);
    expect(result.skipped, 0);

    // It is here, not where the search setting lives, with its sign and
    // under its own name.
    final lists = userEntryListManager.getEntryLists();
    expect(lists.containsKey(KEY_SEARCH_FOR_WORDS), isFalse);
    expect(sharedPreferences.get(KEY_SEARCH_FOR_WORDS), isNot(isA<List>()));
    final share = sharing.lists.get(listId);
    expect(share, isNotNull);
    expect(share!.getName(), _shareName);
    final local = lists[share.key];
    expect(local, isNotNull, reason: 'the share should have a list behind it');
    expect(share.key, isNot(KEY_SEARCH_FOR_WORDS));
    expect(local!.containsVideo(video), isTrue);
    expect(local.getName(), _shareName);

    await sharedPreferences.setInt(KEY_LISTS_OVERVIEW_TAB_INDEX, 0);
    await mdPumpApp(tester);

    // The Lists page has it by its name.
    await mdOpenListsTab(tester);
    await mdOpenOverviewTab(tester, mdL10n.listMyLists);
    expect(
      find.descendant(
        of: find.byKey(ValueKey(share.key)),
        matching: find.text(_shareName),
      ),
      findsOne,
    );

    // And a search finds things.
    await mdTapWhenVisible(
      tester,
      mdNavIcon(Icons.search),
      reason: 'Search tab icon in the bottom navigation',
    );
    final searchField = find.byKey(const ValueKey('searchPage.searchForm'));
    await tester.tap(searchField);
    await settle(tester);
    await tester.enterText(searchField, entry.getKey());
    await settle(tester);
    expect(find.text(entry.getKey()), findsWidgets);
    FocusManager.instance.primaryFocus?.unfocus();
    await settle(tester);
  });
}
