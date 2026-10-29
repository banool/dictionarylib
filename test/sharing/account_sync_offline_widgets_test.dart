import 'dart:async';

import 'package:dictionarylib/entry_list.dart';
import 'package:dictionarylib/globals.dart';
import 'package:dictionarylib/hearth.dart';
import 'package:dictionarylib/l10n/app_localizations.dart';
import 'package:dictionarylib/page_entry_list.dart';
import 'package:dictionarylib/page_entry_list_overview.dart';
import 'package:dictionarylib/sharing/account_sync.dart';
import 'package:dictionarylib/top_level_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../_helpers.dart';
import '_account_sync_harness.dart';
import '_fake_account_server.dart';

/// The lists pages with the network a black hole and a sync cycle stuck
/// in it: what the person does shows at once, without the clock moving
/// (every pump below is zero-length).
void main() {
  setUpAll(installFakeSecureStorage);

  late FakeAccountServer server;
  late TestDevice phone;

  setUp(() {
    seedDictionary(const ['cat', 'dog', 'owl']);
    server = FakeAccountServer();
    communityEntryListManager = DummyEntryListManager();
  });

  tearDown(() {
    TestDevice(server, 'none').deactivate();
  });

  Future<void> signedInWithAnimals(WidgetTester tester) async {
    phone = TestDevice(server, 'phone');
    await tester.runAsync(() async {
      await phone.activate();
      await phone.addLocalList('Animals', ['cat', 'dog']);
      await phone.addLocalList('Gone', ['owl']);
      await phone.signIn('alice');
      await phone.settle();
    });
  }

  /// A cycle stuck in the black hole (started in the test's fake zone, as
  /// the app's would be).
  Future<void> stuckCycle(WidgetTester tester) async {
    server.net.blackhole();
    unawaited(sharing.accountSync.kick(SyncReason.pullToRefresh));
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }
    expect(server.net.held, greaterThan(0));
  }

  /// Zero-length pumps: microtasks and frames, never the clock.
  Future<void> settleNow(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump();
    }
  }

  /// A dialog's opening animation (UI time, far shorter than any request
  /// timeout, so it can't stand in for one).
  Future<void> openDialog(WidgetTester tester, Finder tap) async {
    await tester.tap(tap);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> pumpOverview(WidgetTester tester) async {
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
    await settleNow(tester);
  }

  testWidgets('My lists: create, rename and delete show at once', (
    tester,
  ) async {
    await signedInWithAnimals(tester);
    await pumpOverview(tester);
    await stuckCycle(tester);

    // Create (from edit mode, which creating leaves).
    await openDialog(tester, find.byIcon(Icons.edit_outlined));
    await openDialog(tester, find.byIcon(Icons.add));
    await tester.enterText(find.byType(TextField), 'Birds');
    await tester.tap(find.text('Confirm'));
    await settleNow(tester);
    // (The closing dialog's field still says Birds too: look at the row.)
    expect(
      find.ancestor(
        of: find.text('Birds'),
        matching: find.byType(HearthListRow),
      ),
      findsOneWidget,
    );

    // Rename (a linked list) and delete, in edit mode.
    await openDialog(tester, find.byIcon(Icons.edit_outlined));
    await openDialog(tester, find.text('Animals'));
    await tester.enterText(find.byType(TextField), 'Beasts');
    await tester.tap(find.text('Confirm'));
    await settleNow(tester);
    expect(
      find.ancestor(
        of: find.text('Beasts'),
        matching: find.byType(ReorderableDragStartListener),
      ),
      findsOneWidget,
    );
    expect(find.text('Animals'), findsNothing);

    final row = find.ancestor(
      of: find.text('Gone'),
      matching: find.byType(ReorderableDragStartListener),
    );
    await openDialog(
      tester,
      find.descendant(of: row, matching: find.byIcon(Icons.remove_circle)),
    );
    expect(find.text('Delete “Gone” from all your devices?'), findsOneWidget);
    await tester.tap(find.text('Confirm'));
    await settleNow(tester);
    expect(
      find.ancestor(
        of: find.text('Gone'),
        matching: find.byType(ReorderableDragStartListener),
      ),
      findsNothing,
    );
    expect(find.byType(SnackBar), findsNothing);

    // Back online: it all reaches the account.
    server.net.up();
    await tester.runAsync(() async {
      await sharing.accountSync.kick(SyncReason.resumed);
      await phone.settle();
    });
    expect(server.liveRows('alice').map((r) => r['name']).toSet(), {
      'Favourites',
      'Beasts',
      'Birds',
    });
    await tester.runAsync(() async => phone.deactivate());
  });

  testWidgets('a list page: a sign removed shows at once', (tester) async {
    await signedInWithAnimals(tester);
    final animals = sharing.lists.ownerForSourceKey('Animals_words')!;
    tester.view.physicalSize = const Size(1206, 2622);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: DictLibLocalizations.localizationsDelegates,
        supportedLocales: DictLibLocalizations.supportedLocales,
        home: EntryListPage(
          entryList: animals,
          navigateToEntryPage: (
            context,
            entry,
            showSaveButtons, {
            focusVideo,
            saveToList,
          }) async {},
        ),
      ),
    );
    await settleNow(tester);
    await stuckCycle(tester);
    expect(find.text('dog'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await settleNow(tester);
    final dogRow = find.ancestor(
      of: find.text('dog'),
      matching: find.byType(ListTile),
    );
    await tester.tap(
      find.descendant(of: dogRow, matching: find.byIcon(Icons.remove_circle)),
    );
    await settleNow(tester);
    expect(find.text('dog'), findsNothing);
    expect(find.text('cat'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    server.net.up();
    await tester.runAsync(() async {
      await sharing.accountSync.kick(SyncReason.resumed);
      await phone.settle();
    });
    expect(server.entryKeys(animals.listId), ['cat']);
    await tester.runAsync(() async => phone.deactivate());
  });
}
