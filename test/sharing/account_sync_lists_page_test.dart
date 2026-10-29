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
}
