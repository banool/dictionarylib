import 'package:dictionarylib/common.dart';
import 'package:dictionarylib/entry_list.dart';
import 'package:dictionarylib/globals.dart';
import 'package:dictionarylib/l10n/app_localizations.dart';
import 'package:dictionarylib/lists_service.dart';
import 'package:dictionarylib/page_entry_list_overview.dart';
import 'package:dictionarylib/top_level_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '_helpers.dart';

/// The Lists page's edit mode says which list stays pinned to the top. It
/// has to name that list the way its row does, which stops being
/// "Favourites" once Favourites has been shared under another name.

Future<void> _pumpListsPage(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1206, 2622);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  // TopLevelScaffold reads the current tab from the router.
  final router = GoRouter(
    initialLocation: LISTS_ROUTE,
    routes: [
      GoRoute(
        path: LISTS_ROUTE,
        builder: (context, state) => EntryListsOverviewPage(
          buildEntryListWidgetCallback: (entryList) => const SizedBox.shrink(),
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
}

Future<void> _enterEditMode(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.edit_outlined));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() async {
    installFakeSecureStorage();
    SharedPreferences.setMockInitialValues({});
    sharedPreferences = await SharedPreferences.getInstance();
    seedDictionary(['apple']);
    userEntryListManager = UserEntryListManager.fromStartup();
    communityEntryListManager = DummyEntryListManager();
    installFakeSharing((req) async {
      if (req.method == 'POST' && req.url.path == '/v1/lists') {
        return stubCreateResponse(req);
      }
      // The page syncs every shared list when it opens.
      if (req.method == 'POST' && req.url.path.endsWith('/sync')) {
        return stubSyncApplyAll(req);
      }
      return http.Response('unexpected ${req.method} ${req.url.path}', 500);
    });
  });

  testWidgets('the reorder hint calls a shared Favourites by its share name', (
    tester,
  ) async {
    final favourites = userEntryListManager
        .getEntryLists()[KEY_FAVOURITES_ENTRIES]!;
    await listsService.shareList(
      sourceList: favourites,
      displayName: 'Tiny Tunks',
      sessionToken: kTestSession.sessionToken,
    );

    await _pumpListsPage(tester);
    await _enterEditMode(tester);

    expect(find.text('Tiny Tunks'), findsOneWidget);
    expect(find.textContaining('Tiny Tunks stays pinned'), findsOneWidget);
    expect(find.textContaining('Favourites'), findsNothing);
  });

  testWidgets('the reorder hint says Favourites while it is not shared', (
    tester,
  ) async {
    await _pumpListsPage(tester);
    await _enterEditMode(tester);

    expect(find.textContaining('Favourites stays pinned'), findsOneWidget);
  });
}
