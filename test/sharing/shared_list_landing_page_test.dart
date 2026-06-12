import 'dart:convert';

import 'package:dictionarylib/entry_list.dart';
import 'package:dictionarylib/globals.dart';
import 'package:dictionarylib/l10n/app_localizations.dart';
import 'package:dictionarylib/page_entry_list.dart';
import 'package:dictionarylib/sharing/auth/auth_api.dart';
import 'package:dictionarylib/sharing/auth/auth_service.dart';
import 'package:dictionarylib/sharing/auth/auth_store.dart';
import 'package:dictionarylib/sharing/shared_list_landing_page.dart';
import 'package:dictionarylib/sharing/sharing.dart';
import 'package:dictionarylib/sharing/sync_api.dart';
import 'package:dictionarylib/sharing/synced_entry_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../_helpers.dart';

/// Install a signed-OUT [sharing] singleton (no current session) with a
/// stubbed HTTP client. The landing-page invite flow needs a session-less
/// store so the "Sign in to accept" branch shows.
void installSignedOutSharing(
    Future<http.Response> Function(http.Request) handle) {
  final client = MockClient((req) async => handle(req));
  final api = SyncApi(kTestSharingConfig, client: client);
  final authApi = AuthApi(kTestSharingConfig, client: client);
  final authStore = AuthStore.withSession(null);
  final auth =
      AuthService(config: kTestSharingConfig, api: authApi, store: authStore);
  final lists = SyncedEntryListManager.fromStartup();
  sharing = Sharing.forTesting(
      config: kTestSharingConfig, api: api, lists: lists, auth: auth);
}

void main() {
  setUp(() async {
    installFakeSecureStorage();
    SharedPreferences.setMockInitialValues({});
    sharedPreferences = await SharedPreferences.getInstance();
    seedDictionary(['apple']);
    userEntryListManager = UserEntryListManager.fromStartup();
  });

  Widget wrap() => MaterialApp(
        localizationsDelegates: DictLibLocalizations.localizationsDelegates,
        supportedLocales: DictLibLocalizations.supportedLocales,
        home: SharedListLandingPage(
          listId: 'list000001',
          inviteToken: 'tok-abc',
          navigateToEntryPage: (context, entry, _, {focusVideo, saveToList}) async {},
        ),
      );

  /// M10 regression: tapping "Sign in to accept" then cancelling the
  /// sign-in dialog (no session produced) must not navigate away and must
  /// not throw a setState-after-dispose. The accept handler now bails on
  /// `!mounted || session == null` after the sign-in await.
  testWidgets('cancelling sign-in on the invite landing page is a clean no-op',
      (tester) async {
    installSignedOutSharing((req) async {
      // Best-effort invite preview fetch (GET the public list payload);
      // return 404 so the page falls back to the generic "unknown list"
      // copy without crashing.
      return http.Response('not found', 404);
    });

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    // Signed out + invite → the "Sign in to accept" CTA is shown.
    expect(find.text('Sign in to accept'), findsOneWidget);

    // Tap it: the sign-in dialog opens.
    await tester.tap(find.text('Sign in to accept'));
    await tester.pumpAndSettle();
    expect(find.text('Sign in to share'), findsOneWidget);

    // Cancel the dialog (returns a null session).
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    // No exception, and we're still on the invite prompt — not navigated
    // into an accepting / error state.
    expect(tester.takeException(), isNull);
    expect(find.text('Sign in to accept'), findsOneWidget);
    expect(find.text('Joining…'), findsNothing);
  });

  /// If the viewer already owns the list, the invite landing page should
  /// frame the prompt as "open the list" rather than asking them to accept
  /// an invite they don't need. (Cheap coverage of the landing page's
  /// already-member branch, which sits alongside the M10 fix.)
  testWidgets('invite link to a list you already own offers "open the list"',
      (tester) async {
    installSignedOutSharing((req) async => http.Response('not found', 404));

    // Install an owner-mode mirror for this listId.
    await userEntryListManager.createEntryList('mine');
    final source = userEntryListManager.getEntryLists()['mine']!;
    await sharing.lists.insert(SyncedEntryList.owner(
      meta: SyncedListMeta(
        listId: 'list000001',
        displayName: 'My List',
        role: ListRole.owner,
        lastKnownSeq: 1,
        etag: null,
        lastSyncedAt: 1700000000,
        serverUpdatedAt: 1700000000,
        orphaned: false,
        sourceLocalKey: 'mine',
      ),
      source: source,
    ));

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    expect(find.text('Open list'), findsOneWidget);
    expect(find.text('Sign in to accept'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  Widget wrapSubscribe() => MaterialApp(
        localizationsDelegates: DictLibLocalizations.localizationsDelegates,
        supportedLocales: DictLibLocalizations.supportedLocales,
        home: SharedListLandingPage(
          listId: 'list000001',
          navigateToEntryPage: (context, entry, _,
              {focusVideo, saveToList}) async {},
        ),
      );

  String listPayload() => jsonEncode({
        'schemaVersion': 3,
        'listId': 'list000001',
        'displayName': 'Greetings',
        'appId': 'auslan',
        'entries': [
          {'entry': 'apple', 'video': videoFor('apple')},
        ],
        'lastSeq': 4,
        'createdAt': 1700000000,
        'updatedAt': 1700000050,
      });

  /// The "scanned the QR code straight after sharing" case: the public
  /// payload 404s while R2 propagates, then appears. The page must show
  /// its retry notice (not a flash of "list doesn't exist") and land on
  /// the list once an attempt succeeds.
  testWidgets(
      'subscribe retries a transient 404 with a visible notice, then lands',
      (tester) async {
    var gets = 0;
    installFakeSharing((req) async {
      gets++;
      if (gets < 3) return http.Response('not found', 404);
      return http.Response(listPayload(), 200, headers: {
        'content-type': 'application/json',
        'etag': '"e1"',
        'last-modified': 'Mon, 14 Nov 2023 12:00:00 GMT',
      });
    });

    await tester.pumpWidget(wrapSubscribe());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('attempt 2 of 3'), findsOneWidget);
    expect(find.textContaining("doesn't exist"), findsNothing);

    await tester.pump(const Duration(milliseconds: 1100));
    expect(find.textContaining('attempt 3 of 3'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 2100));
    await tester.pumpAndSettle();
    expect(find.byType(EntryListPage), findsOneWidget);
    expect(gets, 3);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'subscribe that keeps failing ends in a specific error + Try again',
      (tester) async {
    installFakeSharing(
        (req) async => throw http.ClientException('connection refused'));

    await tester.pumpWidget(wrapSubscribe());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1100));
    await tester.pump(const Duration(milliseconds: 2100));
    await tester.pump();

    expect(find.textContaining("Couldn't reach the server"), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('accepting an invite retries transient failures with a notice',
      (tester) async {
    var posts = 0;
    installFakeSharing((req) async {
      if (req.method == 'GET') {
        // Best-effort display-name preview; generic copy is fine.
        return http.Response('not found', 404);
      }
      posts++;
      if (posts == 1) throw http.ClientException('connection refused');
      return http.Response(
        jsonEncode({
          'schemaVersion': 3,
          'listId': 'list000001',
          'displayName': 'Greetings',
          'appId': 'auslan',
          'entries': [
            {'entry': 'apple', 'video': videoFor('apple')},
          ],
          'lastSeq': 4,
          'createdAt': 1700000000,
          'updatedAt': 1700000050,
          'members': {
            'owner': {'userId': 'apple:alice', 'displayName': 'Alice'},
            'editors': [
              {
                'userId': 'apple:tester',
                'displayName': 'Test User',
                'addedAt': 1700000000,
                'addedBy': 'apple:alice',
              },
            ],
          },
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Accept invite'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('attempt 2 of 3'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1100));
    await tester.pumpAndSettle();
    expect(find.byType(EntryListPage), findsOneWidget);
    expect(posts, 2);
    expect(tester.takeException(), isNull);
  });
}
