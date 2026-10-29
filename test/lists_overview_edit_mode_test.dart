import 'dart:convert';

import 'package:dictionarylib/entry_list.dart';
import 'package:dictionarylib/globals.dart';
import 'package:dictionarylib/hearth.dart';
import 'package:dictionarylib/l10n/app_localizations.dart';
import 'package:dictionarylib/lists_service.dart';
import 'package:dictionarylib/page_entry_list_overview.dart';
import 'package:dictionarylib/top_level_scaffold.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '_helpers.dart';

/// The Lists page's edit mode, and in particular how it treats the default
/// list (the one that starts out as "Favourites"). It is an ordinary list
/// there in every way but one: it can be renamed and dragged like the rest,
/// it has the same icon, and it just has no delete button.

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

/// Tap [name]'s row in edit mode and type [newName] into the rename dialog.
Future<void> _rename(WidgetTester tester, String name, String newName) async {
  await tester.tap(find.text(name));
  await tester.pumpAndSettle();
  expect(find.text('Rename List'), findsOneWidget);
  expect(find.widgetWithText(TextField, name), findsOneWidget);
  await tester.enterText(find.byType(TextField), newName);
  await tester.tap(find.text('Confirm'));
  await tester.pumpAndSettle();
}

/// Press and hold [name]'s row, then drag it down past the row below.
Future<void> _dragDownOneRow(WidgetTester tester, String name) async {
  final gesture = await tester.startGesture(tester.getCenter(find.text(name)));
  await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
  for (var i = 0; i < 6; i++) {
    await gesture.moveBy(const Offset(0, 20));
    await tester.pump(const Duration(milliseconds: 50));
  }
  await gesture.up();
  await tester.pumpAndSettle();
}

/// A share server that accepts creates, syncs and renames. Returns the
/// requests it receives.
List<http.Request> _installShareServer() => installFakeSharing((req) async {
  if (req.method == 'POST' && req.url.path == '/v1/lists') {
    return stubCreateResponse(req);
  }
  // The page syncs every shared list when it opens.
  if (req.method == 'POST' && req.url.path.endsWith('/sync')) {
    return stubSyncApplyAll(req);
  }
  if (req.method == 'PUT') {
    final body = jsonDecode(req.body) as Map<String, dynamic>;
    return http.Response(
      jsonEncode(
        snapshotJson(
          listId: req.url.pathSegments.last,
          displayName: body['displayName'] as String,
        ),
      ),
      200,
      headers: {'content-type': 'application/json'},
    );
  }
  return http.Response('unexpected ${req.method} ${req.url.path}', 500);
});

Future<void> _share(String key, String as) => listsService.shareList(
  sourceList: userEntryListManager.getEntryLists()[key]!,
  displayName: as,
  sessionToken: kTestSession.sessionToken,
);

List<String> _keys() => userEntryListManager.getEntryLists().keys.toList();

/// The leading icon(s) on [name]'s row of the Lists page (not edit mode).
List<IconData?> _iconsOnRow(String name) {
  final row = find.ancestor(
    of: find.text(name),
    matching: find.byType(HearthListRow),
  );
  expect(row, findsOneWidget, reason: 'row for $name');
  return [
    for (final e
        in find.descendant(of: row, matching: find.byType(Icon)).evaluate())
      if ((e.widget as Icon).icon != Icons.chevron_right)
        (e.widget as Icon).icon,
  ];
}

void main() {
  late List<http.Request> requests;

  setUp(() async {
    installFakeSecureStorage();
    SharedPreferences.setMockInitialValues({});
    sharedPreferences = await SharedPreferences.getInstance();
    seedDictionary(['apple']);
    userEntryListManager = UserEntryListManager.fromStartup();
    communityEntryListManager = DummyEntryListManager();
    requests = _installShareServer();
  });

  testWidgets('a list called Favourites has a star; in edit mode every list '
      'has a drag handle', (tester) async {
    await userEntryListManager.createEntryList('cats_words');
    await _pumpListsPage(tester);

    expect(find.text('Favourites'), findsOneWidget);
    expect(_iconsOnRow('Favourites'), [Icons.star]);
    expect(_iconsOnRow('cats'), [Icons.list_alt]);

    await _enterEditMode(tester);
    expect(find.byIcon(Icons.star), findsNothing);
    expect(find.byIcon(Icons.drag_handle), findsNWidgets(2));
    // Nothing is pinned any more, and the hint doesn't say otherwise.
    expect(
      find.text('Drag a list to reorder it, or tap it to rename.'),
      findsOneWidget,
    );
  });

  testWidgets('the star goes with the name, not with being the default '
      'list', (tester) async {
    await userEntryListManager.createEntryList('cats_words');
    // The default list gives the name up, and another list takes it.
    await userEntryListManager.renameEntryList(
      kDefaultListKey,
      'Everyday_Signs_words',
    );
    await userEntryListManager.renameEntryList(
      'cats_words',
      'Favourites_words',
    );
    await _pumpListsPage(tester);

    expect(userEntryListManager.defaultListKey, 'Everyday_Signs_words');
    expect(_iconsOnRow('Everyday Signs'), [Icons.list_alt]);
    expect(_iconsOnRow('Favourites'), [Icons.star]);
  });

  testWidgets('the name counts in any case and in every language the apps '
      'come in', (tester) async {
    for (final name in [
      'favourites',
      'ප්‍රියතම',
      'பிடித்தவை',
      'My Favourites',
    ]) {
      await userEntryListManager.createEntryList(
        EntryList.getKeyFromName(name),
      );
    }
    await _pumpListsPage(tester);

    expect(_iconsOnRow('Favourites'), [Icons.star]);
    expect(_iconsOnRow('favourites'), [Icons.star]);
    expect(_iconsOnRow('ප්‍රියතම'), [Icons.star]);
    expect(_iconsOnRow('பிடித்தவை'), [Icons.star]);
    // Only the name itself, not a name that contains it.
    expect(_iconsOnRow('My Favourites'), [Icons.list_alt]);
  });

  testWidgets('only the default list has no delete button', (tester) async {
    await userEntryListManager.createEntryList('cats_words');
    await userEntryListManager.createEntryList('dogs_words');
    await _pumpListsPage(tester);
    await _enterEditMode(tester);

    expect(find.byIcon(Icons.remove_circle), findsNWidgets(2));
    final favouritesRow = find.ancestor(
      of: find.text('Favourites'),
      matching: find.byType(ReorderableDragStartListener),
    );
    expect(
      find.descendant(
        of: favouritesRow,
        matching: find.byIcon(Icons.remove_circle),
      ),
      findsNothing,
    );
  });

  testWidgets('the default list can be renamed, and is still the one that '
      'cannot be deleted', (tester) async {
    await userEntryListManager.createEntryList('cats_words');
    await _pumpListsPage(tester);
    await _enterEditMode(tester);

    await _rename(tester, 'Favourites', 'Everyday Signs');

    expect(find.text('Everyday Signs'), findsOneWidget);
    expect(find.text('Favourites'), findsNothing);
    expect(_keys(), ['Everyday_Signs_words', 'cats_words']);
    expect(userEntryListManager.defaultListKey, 'Everyday_Signs_words');
    // Still one delete button, and it isn't this list's.
    expect(find.byIcon(Icons.remove_circle), findsOneWidget);
    expect(
      userEntryListManager
          .getEntryLists()['Everyday_Signs_words']!
          .canBeDeleted(),
      isFalse,
    );
  });

  testWidgets('once the default list is renamed, another list can be called '
      'Favourites', (tester) async {
    await userEntryListManager.createEntryList('cats_words');
    await _pumpListsPage(tester);
    await _enterEditMode(tester);

    // Taken while the default list has it.
    await _rename(tester, 'cats', 'Favourites');
    expect(find.textContaining('already exists'), findsOneWidget);
    expect(_keys(), [kDefaultListKey, 'cats_words']);
    ScaffoldMessenger.of(tester.element(find.text('cats'))).clearSnackBars();
    await tester.pumpAndSettle();

    await _rename(tester, 'Favourites', 'Everyday Signs');
    await _rename(tester, 'cats', 'Favourites');

    expect(_keys(), ['Everyday_Signs_words', 'Favourites_words']);
    // The name carries no status: this one is deletable.
    expect(userEntryListManager.defaultListKey, 'Everyday_Signs_words');
    expect(
      userEntryListManager.getEntryLists()['Favourites_words']!.canBeDeleted(),
      isTrue,
    );
  });

  testWidgets('the default list can be dragged out of first place', (
    tester,
  ) async {
    await userEntryListManager.createEntryList('cats_words');
    await userEntryListManager.createEntryList('dogs_words');
    await _pumpListsPage(tester);
    await _enterEditMode(tester);

    await _dragDownOneRow(tester, 'Favourites');

    expect(_keys(), ['cats_words', kDefaultListKey, 'dogs_words']);
    expect(sharedPreferences.getStringList(KEY_ENTRY_LIST_KEYS), [
      'cats_words',
      kDefaultListKey,
      'dogs_words',
    ]);
    // Where it sits has nothing to do with which list it is.
    expect(userEntryListManager.defaultListKey, kDefaultListKey);
    expect(find.byIcon(Icons.remove_circle), findsNWidgets(2));
  });

  testWidgets('another list can be dragged into first place', (tester) async {
    await userEntryListManager.createEntryList('cats_words');
    await userEntryListManager.createEntryList('dogs_words');
    userEntryListManager.reorder(1, 0);
    await userEntryListManager.writeEntryListKeys();
    expect(_keys(), ['cats_words', kDefaultListKey, 'dogs_words']);

    // And it stays that way across a restart.
    userEntryListManager = UserEntryListManager.fromStartup();
    expect(_keys(), ['cats_words', kDefaultListKey, 'dogs_words']);
    expect(userEntryListManager.defaultListKey, kDefaultListKey);
  });

  group('when the default list is shared', () {
    setUp(() async {
      await userEntryListManager.createEntryList('cats_words');
      await _share(kDefaultListKey, 'Tiny Tunks');
    });

    testWidgets('it goes by the share name and shows the share\'s icon, not '
        'a star', (tester) async {
      await _pumpListsPage(tester);
      expect(find.text('Tiny Tunks'), findsOneWidget);
      expect(find.text('Favourites'), findsNothing);
      expect(find.byIcon(Icons.star), findsNothing);
      expect(_iconsOnRow('Tiny Tunks'), [Icons.cloud_done]);
      await _enterEditMode(tester);
      expect(find.text('Tiny Tunks'), findsOneWidget);
      expect(find.byIcon(Icons.star), findsNothing);
    });

    testWidgets('tapping it renames the share, and the list underneath keeps '
        'its key', (tester) async {
      await _pumpListsPage(tester);
      await _enterEditMode(tester);

      await _rename(tester, 'Tiny Tunks', 'Wee Tunks');

      // Renamed here at once, queued for the server (no PUT any more).
      expect(requests.where((r) => r.method == 'PUT'), isEmpty);
      final share = sharing.lists.ownerForSourceKey(kDefaultListKey)!;
      expect(share.meta.pendingOps.last.type, 'rename');
      expect(share.meta.pendingOps.last.args, {'displayName': 'Wee Tunks'});
      expect(find.text('Wee Tunks'), findsOneWidget);
      expect(find.text('Tiny Tunks'), findsNothing);
      expect(_keys(), [kDefaultListKey, 'cats_words']);
      expect(userEntryListManager.defaultListKey, kDefaultListKey);
      expect(
        userEntryListManager.getEntryLists()[kDefaultListKey]!.getName(),
        'Wee Tunks',
      );
      // Let the queued rename's flush run (it is debounced).
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
    });

    for (final reserved in [
      'Favourites',
      'favourites',
      'ප්‍රියතම',
      'பிடித்தவை',
    ]) {
      testWidgets('its share cannot be renamed to "$reserved"', (tester) async {
        await _pumpListsPage(tester);
        await _enterEditMode(tester);

        await _rename(tester, 'Tiny Tunks', reserved);

        // Refused before it reaches the server.
        expect(requests.where((r) => r.method == 'PUT'), isEmpty);
        expect(find.textContaining('is reserved'), findsOneWidget);
        expect(
          userEntryListManager.getEntryLists()[kDefaultListKey]!.getName(),
          'Tiny Tunks',
        );
      });
    }

    testWidgets('before account sync has run here, a shared list has no '
        'delete button (and nothing tells you to stop sharing first)', (
      tester,
    ) async {
      await _share('cats_words', 'Cat Signs');
      await _pumpListsPage(tester);
      await _enterEditMode(tester);
      // Neither the shared list nor the shared default list can be deleted
      // from here: a share made the old way has to be unshared first, and
      // the default list never can be. With account sync, a linked list is
      // deleted everywhere (sharing/account_sync_test.dart).
      expect(find.byIcon(Icons.remove_circle), findsNothing);
      expect(
        find.byTooltip('Stop sharing this list before deleting it.'),
        findsNothing,
      );
    });

    testWidgets('it can still be dragged', (tester) async {
      await _pumpListsPage(tester);
      await _enterEditMode(tester);

      await _dragDownOneRow(tester, 'Tiny Tunks');

      expect(_keys(), ['cats_words', kDefaultListKey]);
    });
  });
}
