import 'package:dictionarylib/common.dart';
import 'package:dictionarylib/entry_list.dart';
import 'package:dictionarylib/flashcards_logic.dart';
import 'package:dictionarylib/globals.dart';
import 'package:dictionarylib/l10n/app_localizations.dart';
import 'package:dictionarylib/lists_service.dart';
import 'package:dictionarylib/page_flashcards.dart';
import 'package:dictionarylib/page_flashcards_landing.dart';
import 'package:dictionarylib/saved_video.dart';
import 'package:dictionarylib/top_level_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '_helpers.dart';

/// Tests for which lists the Revision page offers as sources, and what it
/// calls them.
///
/// A list shared from this device shows on the Lists page under the share's
/// display name, which need not match the local list it wraps: Favourites
/// can be shared as anything, and a share can be renamed afterwards. The
/// picker used to show the local name instead, so the person who made a
/// shared list couldn't find it to revise from while everyone they shared
/// it with could.

class _Controller extends FlashcardsLandingPageController {
  @override
  List<ResolvedSavedVideo> filterSavedVideos(List<ResolvedSavedVideo> videos) =>
      videos;

  @override
  FlashcardsConfig get flashcardsConfig => throw UnimplementedError();

  @override
  Widget buildHelpPage(BuildContext context) => const SizedBox.shrink();
}

SavedVideo _video(String entryKey) =>
    SavedVideo(entryKey: entryKey, mediaPath: videoFor(entryKey));

Future<void> _pumpLandingPage(WidgetTester tester) async {
  // A phone-sized surface, so the sources sheet lays out as it does on device.
  tester.view.physicalSize = const Size(1206, 2622);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  // TopLevelScaffold reads the current tab from the router.
  final router = GoRouter(
    initialLocation: REVISION_ROUTE,
    routes: [
      GoRoute(
        path: REVISION_ROUTE,
        builder: (context, state) =>
            FlashcardsLandingPage(controller: _Controller()),
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

Future<void> _openSourcesPicker(WidgetTester tester) async {
  await tester.tap(find.text('No lists chosen yet'));
  await tester.pumpAndSettle();
  expect(find.text('Select Lists'), findsOneWidget);
}

/// Dismiss the sources sheet by tapping the scrim above it.
Future<void> _closeSourcesPicker(WidgetTester tester) async {
  await tester.tapAt(const Offset(20, 20));
  await tester.pumpAndSettle();
  expect(find.text('Select Lists'), findsNothing);
}

bool _startEnabled(WidgetTester tester) =>
    tester
        .widget<FilledButton>(find.byKey(const ValueKey('startButton')))
        .onPressed !=
    null;

void main() {
  setUp(() async {
    installFakeSecureStorage();
    // Nothing chosen for revision yet, as in the report.
    SharedPreferences.setMockInitialValues({KEY_LISTS_TO_REVIEW: <String>[]});
    sharedPreferences = await SharedPreferences.getInstance();
    seedDictionary(['apple', 'banana', 'cherry']);
    userEntryListManager = UserEntryListManager.fromStartup();
    communityEntryListManager = DummyEntryListManager();
    installFakeSharing((req) async {
      if (req.method == 'POST' && req.url.path == '/v1/lists') {
        return stubCreateResponse(req);
      }
      return http.Response('unexpected ${req.method} ${req.url.path}', 500);
    });
  });

  testWidgets('Favourites shared under another name is offered, and can be '
      'revised, under that name', (tester) async {
    final favourites = userEntryListManager
        .getEntryLists()[KEY_FAVOURITES_ENTRIES]!;
    await favourites.addVideo(_video('apple'));
    await listsService.shareList(
      sourceList: favourites,
      displayName: 'Tiny Tunks',
      sessionToken: kTestSession.sessionToken,
    );

    await _pumpLandingPage(tester);
    await _openSourcesPicker(tester);

    // The same name the Lists page gives it, not the local list's.
    expect(find.text('Tiny Tunks'), findsOneWidget);
    expect(find.text('Favourites'), findsNothing);

    await tester.tap(find.text('Tiny Tunks'));
    await tester.pumpAndSettle();
    await _closeSourcesPicker(tester);

    expect(find.text('Tiny Tunks'), findsOneWidget);
    expect(find.text('1 sign'), findsOneWidget);
    expect(find.text('No lists chosen yet'), findsNothing);
    expect(_startEnabled(tester), isTrue);
  });

  testWidgets('a list created and shared while the page is up can be chosen '
      'straight away', (tester) async {
    await _pumpLandingPage(tester);

    // The page stays mounted under a pushed route (a share link's landing
    // page, say), so lists can come and go without it being rebuilt.
    await userEntryListManager.createEntryList('animals_words');
    final animals = userEntryListManager.getEntryLists()['animals_words']!;
    await animals.addVideo(_video('banana'));
    await animals.addVideo(_video('cherry'));
    await listsService.shareList(
      sourceList: animals,
      displayName: 'Zoo Signs',
      sessionToken: kTestSession.sessionToken,
    );

    await _openSourcesPicker(tester);
    expect(find.text('Zoo Signs'), findsOneWidget);
    expect(find.text('animals'), findsNothing);

    await tester.tap(find.text('Zoo Signs'));
    await tester.pumpAndSettle();
    await _closeSourcesPicker(tester);

    expect(find.text('Zoo Signs'), findsOneWidget);
    expect(find.text('2 signs'), findsOneWidget);
    expect(find.text('No lists chosen yet'), findsNothing);
    expect(_startEnabled(tester), isTrue);
  });

  testWidgets('an unshared list keeps its own name', (tester) async {
    await userEntryListManager.createEntryList('animals_words');
    final animals = userEntryListManager.getEntryLists()['animals_words']!;
    await animals.addVideo(_video('banana'));

    await _pumpLandingPage(tester);
    await _openSourcesPicker(tester);

    expect(find.text('Favourites'), findsOneWidget);
    expect(find.text('animals'), findsOneWidget);
  });
}
