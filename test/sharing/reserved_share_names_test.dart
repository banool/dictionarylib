import 'package:dictionarylib/entry_list.dart';
import 'package:dictionarylib/entry_types.dart';
import 'package:dictionarylib/globals.dart';
import 'package:dictionarylib/l10n/app_localizations.dart';
import 'package:dictionarylib/lists_service.dart';
import 'package:dictionarylib/sharing/share_dialog.dart';
import 'package:dictionarylib/sharing/sync_api.dart';
import 'package:dictionarylib/sharing/synced_entry_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../_helpers.dart';

/// A list on the device can be called anything, "Favourites" included —
/// it's what the default list is called until it's renamed. A *shared*
/// list can't go by that name: most people never rename their own, so it
/// would sit next to theirs looking like it. That holds for the name in
/// every language the apps come in.

/// Opens the share dialog for the default list as soon as it's built.
class _ShareDefaultList extends StatefulWidget {
  const _ShareDefaultList();
  @override
  State<_ShareDefaultList> createState() => _ShareDefaultListState();
}

class _ShareDefaultListState extends State<_ShareDefaultList> {
  SyncedEntryList? shared;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final result = await showShareDialog(
        context: context,
        sourceList: userEntryListManager.getEntryLists()[kDefaultListKey]!,
      );
      if (mounted) setState(() => shared = result);
    });
  }

  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Text(shared == null ? 'not shared' : 'shared'));
}

void main() {
  late List<http.Request> requests;

  setUp(() async {
    installFakeSecureStorage();
    SharedPreferences.setMockInitialValues({});
    sharedPreferences = await SharedPreferences.getInstance();
    seedDictionary(['apple']);
    startingLocale = LOCALE_ENGLISH;
    userEntryListManager = UserEntryListManager.fromStartup();
    requests = installFakeSharing((req) async {
      if (req.method == 'POST' && req.url.path == '/v1/lists') {
        return stubCreateResponse(req);
      }
      return http.Response('unexpected ${req.method} ${req.url.path}', 500);
    });
  });

  group('isReservedShareName', () {
    test('covers the default list\'s starting name in every language', () {
      expect(reservedShareNamesLower, {
        for (final locale in DictLibLocalizations.supportedLocales)
          lookupDictLibLocalizations(locale).favouritesListName.toLowerCase(),
      });
      // Spelled out, because the share-API Worker carries its own copy of
      // exactly these (RESERVED_DISPLAY_NAMES in workers/src/validation.ts)
      // and a new translation has to be added there too.
      expect(reservedShareNamesLower, {'favourites', 'ප්‍රියතම', 'பிடித்தவை'});
    });

    test('ignores case and surrounding space', () {
      for (final name in [
        'Favourites',
        'favourites',
        'FAVOURITES',
        '  Favourites  ',
        'ප්‍රියතම',
        ' ප්‍රියතම ',
        'பிடித்தவை',
      ]) {
        expect(isReservedShareName(name), isTrue, reason: name);
      }
    });

    test('leaves every other name alone', () {
      for (final name in [
        'Favourites 2',
        'My Favourites',
        'Favorites',
        'Tiny Tunks',
        'ප්‍රියතම 2',
        '',
      ]) {
        expect(isReservedShareName(name), isFalse, reason: name);
      }
    });
  });

  group('a list on the device', () {
    test('can be called Favourites in any language', () async {
      // The default list has the English name; these are free.
      for (final name in ['favourites', 'ප්‍රියතම', 'பிடித்தவை']) {
        final key = EntryList.getKeyFromName(name);
        await userEntryListManager.createEntryList(key);
        expect(userEntryListManager.getEntryLists()[key]!.getName(), name);
      }
    });
  });

  group('sharing the default list while it is still called Favourites', () {
    Future<void> pumpDialog(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: DictLibLocalizations.localizationsDelegates,
          supportedLocales: DictLibLocalizations.supportedLocales,
          home: const _ShareDefaultList(),
        ),
      );
      await tester.pumpAndSettle();
      // Offered under its own name to begin with.
      expect(find.widgetWithText(TextField, 'Favourites'), findsOneWidget);
    }

    testWidgets('is refused under that name, before anything is sent', (
      tester,
    ) async {
      await pumpDialog(tester);
      await tester.tap(find.text('Share'));
      await tester.pumpAndSettle();

      expect(find.textContaining('is reserved'), findsOneWidget);
      expect(requests, isEmpty);
      expect(sharing.lists.ownerForSourceKey(kDefaultListKey), isNull);
    });

    for (final reserved in ['favourites', 'ප්‍රියතම', 'பிடித்தவை']) {
      testWidgets('is refused as "$reserved" too', (tester) async {
        await pumpDialog(tester);
        await tester.enterText(find.byType(TextField), reserved);
        await tester.tap(find.text('Share'));
        await tester.pumpAndSettle();

        expect(find.textContaining('is reserved'), findsOneWidget);
        expect(requests, isEmpty);
      });
    }

    testWidgets('goes through under another name, which the list then goes '
        'by', (tester) async {
      await pumpDialog(tester);
      await tester.enterText(find.byType(TextField), 'Tiny Tunks');
      await tester.tap(find.text('Share'));
      await tester.pumpAndSettle();

      expect(find.text('shared'), findsOneWidget);
      expect(requests.single.method, 'POST');
      final list = userEntryListManager.getEntryLists()[kDefaultListKey]!;
      expect(list.getName(), 'Tiny Tunks');
      // Underneath it is the same list, and still the one that can't go.
      expect(userEntryListManager.defaultListKey, kDefaultListKey);
      expect(list.canBeDeleted(), isFalse);
    });
  });

  group('renaming a share', () {
    for (final reserved in ['Favourites', 'ප්‍රියතම', 'பிடித்தவை']) {
      test('to "$reserved" is refused before anything is sent', () async {
        await userEntryListManager.createEntryList('cats_words');
        final owned = await listsService.shareList(
          sourceList: userEntryListManager.getEntryLists()['cats_words']!,
          displayName: 'Cats',
          sessionToken: kTestSession.sessionToken,
        );
        requests.clear();

        await expectLater(
          listsService.renameSharedList(owned, reserved),
          throwsA(
            isA<EntryListNameException>().having(
              (e) => e.kind,
              'kind',
              EntryListNameError.reserved,
            ),
          ),
        );
        expect(requests, isEmpty);
        expect(owned.getName(), 'Cats');
      });
    }
  });
}
