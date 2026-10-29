import 'package:dictionarylib/common.dart' show rootNavigatorKey;
import 'package:dictionarylib/entry_list.dart';
import 'package:dictionarylib/globals.dart';
import 'package:dictionarylib/l10n/app_localizations.dart';
import 'package:dictionarylib/lists_service.dart';
import 'package:dictionarylib/page_settings.dart';
import 'package:dictionarylib/save_video_sheet.dart';
import 'package:dictionarylib/sharing/sync_status_sheet.dart';
import 'package:dictionarylib/sharing/account_sync.dart';
import 'package:dictionarylib/sharing/engine_notification_listener.dart';
import 'package:dictionarylib/top_level_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../_helpers.dart';
import '_account_sync_harness.dart';
import '_fake_account_server.dart';

/// Account sync as the person sees it outside My lists: Settings keeping up
/// with a sign-in made elsewhere, and the save sheet showing a list that is
/// on the account but private like any other list.
void main() {
  setUpAll(installFakeSecureStorage);

  Widget app(Widget home) => MaterialApp(
    localizationsDelegates: DictLibLocalizations.localizationsDelegates,
    supportedLocales: DictLibLocalizations.supportedLocales,
    home: home,
  );

  testWidgets('Settings follows a sign-in made elsewhere (the session-expired '
      'snackbar, the share flow) while it is on screen', (tester) async {
    seedDictionary(const []);
    final server = FakeAccountServer();
    final phone = TestDevice(server, 'phone');
    await tester.runAsync(() async => phone.activate());
    communityEntryListManager = DummyEntryListManager();
    tester.view.physicalSize = const Size(750, 4000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: SETTINGS_ROUTE,
      routes: [
        GoRoute(
          path: SETTINGS_ROUTE,
          builder: (context, state) => SettingsPage(
            appName: 'Test',
            additionalTopWidgets: const [],
            buildLegalInformationChildren: () => const [],
            reportDataProblemUrl: 'https://example.com',
            reportAppProblemUrl: 'https://example.com',
            iOSAppId: '1',
            androidAppId: 'a',
            privacyPolicyUrl: 'https://example.com',
            termsOfServiceUrl: 'https://example.com',
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
    expect(find.text('Sharing and syncing'.toUpperCase()), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Sign out'), findsNothing);

    await tester.runAsync(() async {
      await phone.signIn('alice');
      await phone.settle();
    });
    await tester.pumpAndSettle();
    expect(find.text('Sign out'), findsOneWidget);
    expect(find.textContaining('Synced'), findsOneWidget);
    expect(find.text('Sign in'), findsNothing);

    // "Signed in with …" opens the sync status sheet.
    await tester.tap(find.byKey(const ValueKey('settings.syncStatusRow')));
    await tester.pumpAndSettle();
    expect(find.text('Sync status'), findsOneWidget);
    expect(find.byKey(SyncStatusKeys.syncNow), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.text('Sync status'), findsNothing);

    await tester.runAsync(() async => sharing.signOut());
    await tester.pumpAndSettle();
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Sign out'), findsNothing);
    await tester.runAsync(() async => phone.deactivate());
  });

  testWidgets('a "signed out, sign in again" snackbar goes once a session is '
      'back, however the person signed in', (tester) async {
    seedDictionary(const []);
    final server = FakeAccountServer();
    final phone = TestDevice(server, 'phone');
    await tester.runAsync(() async {
      await phone.activate();
      await phone.signIn('alice');
      await phone.settle();
    });
    final sub = installEngineNotificationSnackbars();
    addTearDown(sub.cancel);
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: rootNavigatorKey,
        scaffoldMessengerKey: rootScaffoldMessengerKey,
        localizationsDelegates: DictLibLocalizations.localizationsDelegates,
        supportedLocales: DictLibLocalizations.supportedLocales,
        home: const Scaffold(body: SizedBox.shrink()),
      ),
    );
    // The session expires.
    await tester.runAsync(() async {
      server.tokens.clear();
      await sharing.accountSync.kick(SyncReason.pullToRefresh);
    });
    await tester.pumpAndSettle();
    expect(find.text('Signed out — please sign in again'), findsOneWidget);
    // Signed in again from Settings, not from the snackbar.
    await tester.runAsync(() async {
      phone.token = null;
      await phone.signIn('alice');
      await phone.settle();
    });
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(find.text('Signed out — please sign in again'), findsNothing);
    await tester.runAsync(() async => phone.deactivate());
  });

  testWidgets('the save sheet shows a private list on the account with the '
      'usual list icon, and only a shared one with the share icon', (
    tester,
  ) async {
    seedDictionary(const ['cat']);
    final server = FakeAccountServer();
    final phone = TestDevice(server, 'phone');
    await tester.runAsync(() async {
      await phone.activate();
      await phone.addLocalList('Animals', ['cat']);
      await phone.addLocalList('Birds', []);
      await phone.signIn('alice');
      await phone.settle();
      await listsService.shareList(
        sourceList: userEntryListManager.getEntryLists()['Birds_words']!,
        displayName: 'Birds',
        sessionToken: phone.token!,
      );
    });
    communityEntryListManager = DummyEntryListManager();
    tester.view.physicalSize = const Size(750, 1334);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      app(
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showSaveVideoSheet(context, video: video('cat')),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    IconData iconOf(String name) {
      final row = find.ancestor(
        of: find.text(name),
        matching: find.byType(Row),
      );
      final icon = find.descendant(of: row.first, matching: find.byType(Icon));
      return tester.widget<Icon>(icon.first).icon!;
    }

    expect(iconOf('Animals'), Icons.list_alt);
    expect(iconOf('Favourites'), Icons.list_alt);
    expect(iconOf('Birds'), isNot(Icons.list_alt));
    await tester.runAsync(() async => phone.deactivate());
  });
}
