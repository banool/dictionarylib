// Multi-device e2e, but one device and one person: following a shared list
// from its link, and being shown where it lives.
//
// Opening a share link used to show the list and nothing else, and people
// who did that couldn't find the list again afterwards. Now the link lands on
// the Lists tab's Subscribed tab with the list marked as new and a line
// saying links' lists are kept there, so they learn the place. The mark is a
// one-off: back on the Lists tab later it's an ordinary row.

import 'package:dictionarylib/dictionarylib.dart';
import 'package:dictionarylib/page_entry_list.dart';
import 'package:dictionarylib/saved_video.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import '../config.dart';
import '../helpers.dart';
import 'md_common.dart';

const String _listName = 'Md Followed';

void runSoloFollowLink(MdSuiteConfig cfg) {
  mdConfig = cfg;
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a share link lands on Subscribed with the list marked new, '
      'once', (WidgetTester tester) async {
    await mdRequireServer();
    await mdSetup();

    // Someone else shares a list. (The worker takes a test user id of up to
    // 32 characters after "test:".)
    final now = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    await mdSignInAs('test:md-$mdRunId-f-$now', 'Md Sharer');
    final entry = mdEntryWithVideo();
    final listId = generateListId();
    await sharing.api.createList(
      listId: listId,
      displayName: _listName,
      entries: [
        SavedVideo(
          entryKey: entry.getKey(),
          mediaPath: entry
              .getSubEntries()
              .firstWhere((s) => s.getMedia().isNotEmpty)
              .getMedia()
              .first,
        ),
      ],
      sessionToken: sharing.auth.store.current!.sessionToken,
    );
    // This person follows it without an account, starting from the My lists
    // tab, which is where the Lists tab opens for someone new.
    await sharing.signOut();
    await sharedPreferences.setInt(KEY_LISTS_OVERVIEW_TAB_INDEX, 0);
    await mdPumpApp(tester);

    // The link arrives the way the OS hands it over: parsed by the deep-link
    // handler's parser and pushed over the current screen, as RootApp does.
    final link = Uri.parse(sharing.config.shareUrlFor(listId));
    final payload = extractSharePayload(link, sharing.config);
    expect(payload, isNotNull, reason: '$link should parse as a share link');
    GoRouter.of(rootNavigatorKey.currentContext!)
        .push(payload!.toRouteLocation());

    await mdWaitForUi(
      tester,
      () => find.text(mdL10n.listNewTag).evaluate().isNotEmpty,
      reason: 'the followed list should be shown on the Lists tab, marked new',
    );
    expect(find.text(_listName), findsOneWidget);
    expect(find.text(mdL10n.listSubscribedNewHint), findsOneWidget);
    expect(find.byType(EntryListsOverviewPage), findsOneWidget);
    expect(find.byType(EntryListPage), findsNothing);
    expect(
      sharing.lists.get(listId)?.meta.role,
      ListRole.subscriber,
      reason: 'following a link should subscribe, with no account',
    );

    // It opens from there.
    await tester.tap(find.text(_listName));
    await settle(tester);
    expect(find.byType(EntryListPage), findsOneWidget);
    await tester.pageBack();
    await settle(tester);

    // Next time on the Lists tab it opens on Subscribed, and the list is an
    // ordinary row there.
    await mdTapWhenVisible(
      tester,
      mdNavIcon(Icons.search),
      reason: 'Search tab icon in the bottom navigation',
    );
    await mdOpenListsTab(tester);
    await mdWaitForUi(
      tester,
      () => find.text(_listName).evaluate().isNotEmpty,
      reason: 'the Lists tab should reopen on Subscribed with the list',
    );
    expect(find.text(mdL10n.listNewTag), findsNothing);
    expect(find.text(mdL10n.listSubscribedNewHint), findsNothing);

    // Leave the install as it was found.
    await sharing.engine.unsubscribe(listId);
  });
}
