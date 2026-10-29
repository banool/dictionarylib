import 'package:dictionarylib/entry_list.dart';
import 'package:dictionarylib/globals.dart';
import 'package:dictionarylib/l10n/app_localizations.dart';
import 'package:dictionarylib/page_entry_list_overview.dart';
import 'package:dictionarylib/sharing/sync_api.dart';
import 'package:dictionarylib/top_level_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../_helpers.dart';
import '_account_sync_harness.dart';
import '_fake_account_server.dart';

/// My lists while signed in with account sync: a list too large to sync
/// says so on its row, quietly, for as long as it is too large (no
/// snackbar; section 5.11 of the plan).
void main() {
  setUpAll(installFakeSecureStorage);

  testWidgets('a list too large to sync says so on its row while it is', (
    tester,
  ) async {
    seedDictionary(const []);
    final server = FakeAccountServer();
    final phone = TestDevice(server, 'phone');
    await tester.runAsync(() async {
      await phone.activate();
      final big = await phone.addLocalList('Huge', []);
      for (var i = 0; i <= maxEntriesPerPrivateList; i++) {
        big.savedVideos.add(video('w$i'));
      }
      await big.write();
      await phone.addLocalList('Small', ['a']);
      await phone.signIn('alice');
      await phone.settle();
    });
    communityEntryListManager = DummyEntryListManager();

    tester.view.physicalSize = const Size(1206, 2622);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: LISTS_ROUTE,
      routes: [
        GoRoute(
          path: LISTS_ROUTE,
          builder: (context, state) => EntryListsOverviewPage(
            buildEntryListWidgetCallback: (entryList) =>
                const SizedBox.shrink(),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: DictLibLocalizations.localizationsDelegates,
        supportedLocales: DictLibLocalizations.supportedLocales,
      ),
    );
    await tester.pumpAndSettle();
    const note = 'Not synced: more than $maxEntriesPerPrivateList signs';
    expect(find.textContaining(note), findsOneWidget);
    // Only one list is too large, so only one row says so.
    // No snackbar about it.
    expect(find.byType(SnackBar), findsNothing);

    // Small enough again: the note goes at once.
    await tester.runAsync(() async {
      await userEntryListManager.getEntryLists()['Huge_words']!.removeVideo(
        video('w0'),
      );
    });
    sharing.bumpState();
    await tester.pumpAndSettle();
    expect(find.textContaining(note), findsNothing);
    await tester.runAsync(() async => phone.deactivate());
  });

  testWidgets('signed out, My lists says what signing in would do, in plain '
      'text under the edit hint; signed in, nothing extra', (tester) async {
    seedDictionary(const ['cat']);
    final server = FakeAccountServer();
    final phone = TestDevice(server, 'phone');
    await tester.runAsync(() async {
      await phone.activate();
      await phone.addLocalList('Animals', ['cat']);
    });
    communityEntryListManager = DummyEntryListManager();
    tester.view.physicalSize = const Size(750, 1334);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: LISTS_ROUTE,
      routes: [
        GoRoute(
          path: LISTS_ROUTE,
          builder: (context, state) => EntryListsOverviewPage(
            buildEntryListWidgetCallback: (entryList) =>
                const SizedBox.shrink(),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: DictLibLocalizations.localizationsDelegates,
        supportedLocales: DictLibLocalizations.supportedLocales,
      ),
    );
    await tester.pumpAndSettle();
    const hint = 'Sign in to sync lists between your own devices';
    expect(find.textContaining(hint), findsOneWidget);
    expect(find.textContaining('Tap the pencil'), findsOneWidget);
    expect(
      find.ancestor(
        of: find.textContaining(hint),
        matching: find.byType(TextButton),
      ),
      findsNothing,
      reason: 'plain text, not a button',
    );
    // The Animals row looks like any list: no badge, a word count.
    expect(find.text('1 word'), findsOneWidget);

    await tester.runAsync(() async {
      await phone.signIn('alice');
      await phone.settle();
    });
    sharing.bumpState();
    await tester.pumpAndSettle();
    expect(find.textContaining(hint), findsNothing);
    expect(find.textContaining('Tap the pencil'), findsOneWidget);
    // Linked and private, it still looks like an ordinary list.
    expect(sharing.lists.ownerForSourceKey('Animals_words'), isNotNull);
    expect(find.text('1 word'), findsOneWidget);
    await tester.runAsync(() async => phone.deactivate());
  });
}
