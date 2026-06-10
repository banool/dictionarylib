import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:dictionarylib/entry_list.dart';
import 'package:dictionarylib/globals.dart';
import 'package:dictionarylib/l10n/app_localizations.dart';
import 'package:dictionarylib/saved_video.dart';
import 'package:dictionarylib/sharing/list_members_page.dart';
import 'package:dictionarylib/sharing/sync_api.dart';
import 'package:dictionarylib/sharing/synced_entry_list.dart';
import 'package:dictionarylib/top_level_scaffold.dart' show LISTS_ROUTE;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../_helpers.dart';

void main() {
  setUp(() async {
    installFakeSecureStorage();
    SharedPreferences.setMockInitialValues({});
    sharedPreferences = await SharedPreferences.getInstance();
    seedDictionary(['apple']);
    userEntryListManager = UserEntryListManager.fromStartup();
  });

  /// Build an owner-mode shared list with one editor (Bob) in its cached
  /// member directory, installed into the manager so the post-delete /sync
  /// can update it in place.
  Future<SyncedEntryList> installOwnerListWithBob() async {
    await userEntryListManager.createEntryList('owner_words');
    final source = userEntryListManager.getEntryLists()['owner_words']!;
    final list = SyncedEntryList.owner(
      meta: SyncedListMeta(
        listId: 'ownerlist001',
        displayName: 'My List',
        role: ListRole.owner,
        lastKnownSeq: 1,
        etag: null,
        lastSyncedAt: 1700000000,
        serverUpdatedAt: 1700000000,
        orphaned: false,
        sourceLocalKey: 'owner_words',
        cachedMembers: MembersBlock(
          owner: const MemberRef(userId: 'apple:alice', displayName: 'Alice'),
          editors: [
            EditorRef(
              userId: 'apple:bob',
              displayName: 'Bob',
              addedAt: 1700000000,
              addedBy: 'apple:alice',
            ),
          ],
        ),
      ),
      source: source,
    );
    await sharing.lists.insert(list);
    return list;
  }

  Widget wrap(SyncedEntryList list) => MaterialApp(
        localizationsDelegates: DictLibLocalizations.localizationsDelegates,
        supportedLocales: DictLibLocalizations.supportedLocales,
        home: ListMembersPage(list: list),
      );

  /// Regression test: removing an editor used to give no progress feedback
  /// while the network call was in flight. The row should swap its remove
  /// button for a spinner until the removal completes.
  testWidgets('removing an editor shows an inline spinner until it completes',
      (tester) async {
    // Gate the DELETE so we can observe the in-flight UI before it returns.
    final gate = Completer<void>();
    installFakeSharing((req) async {
      if (req.method == 'DELETE' && req.url.path.contains('/editors/')) {
        await gate.future;
        return http.Response('', 204);
      }
      if (req.method == 'POST' && req.url.path.endsWith('/sync')) {
        // Post-removal /sync: Bob is gone from the member directory.
        return stubSyncApplyAll(req, members: {
          'owner': {'userId': 'apple:alice', 'displayName': 'Alice'},
          'editors': <Map<String, dynamic>>[],
        });
      }
      return http.Response('unexpected ${req.method} ${req.url.path}', 500);
    });

    final list = await installOwnerListWithBob();
    await tester.pumpWidget(wrap(list));
    await tester.pumpAndSettle();

    // Baseline: Bob is shown with a remove button, no spinner.
    expect(find.text('Bob'), findsOneWidget);
    expect(find.byIcon(Icons.person_remove_outlined), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    // Tap remove → confirm.
    await tester.tap(find.byIcon(Icons.person_remove_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove')); // confirm-dialog button
    // Can't pumpAndSettle while the spinner animates; pump enough to close
    // the confirm dialog and apply the in-flight setState.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // In-flight: the remove button is replaced by a spinner.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byIcon(Icons.person_remove_outlined), findsNothing);

    // Complete the request → spinner clears and Bob drops off the list.
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Bob'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  /// Regression test: an editor who leaves a list used to be left sitting on
  /// the (now-defunct) list page. Leaving should pop all the way back to the
  /// top-level lists overview.
  testWidgets('leaving a list as an editor returns to the lists overview',
      (tester) async {
    installFakeSharing((req) async {
      if (req.method == 'DELETE' && req.url.path.contains('/editors/')) {
        return http.Response('', 204);
      }
      return http.Response('unexpected ${req.method} ${req.url.path}', 500);
    });

    // We're an editor (so the "Leave this list" button shows).
    final list = SyncedEntryList.editor(
      meta: SyncedListMeta(
        listId: 'editlist0001',
        displayName: 'Shared',
        role: ListRole.editor,
        lastKnownSeq: 1,
        etag: null,
        lastSyncedAt: 1700000000,
        serverUpdatedAt: 1700000000,
        orphaned: false,
        cachedMembers: MembersBlock(
          owner: const MemberRef(userId: 'apple:alice', displayName: 'Alice'),
          editors: [
            EditorRef(
              userId: 'apple:bob',
              displayName: 'Bob',
              addedAt: 1700000000,
              addedBy: 'apple:alice',
            ),
          ],
        ),
      ),
      savedVideos: LinkedHashSet<SavedVideo>(),
    );
    await sharing.lists.insert(list);

    // Minimal router: a `/lists` overview that pushes the members page on
    // top, mirroring the real stack (overview → list page → members page).
    final router = GoRouter(
      initialLocation: LISTS_ROUTE,
      routes: [
        GoRoute(
          path: LISTS_ROUTE,
          builder: (c, s) => Scaffold(
            body: Center(
              child: Builder(
                builder: (ctx) => TextButton(
                  onPressed: () => Navigator.of(ctx).push(MaterialPageRoute(
                      builder: (_) => ListMembersPage(list: list))),
                  child: const Text('OVERVIEW'),
                ),
              ),
            ),
          ),
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(
      localizationsDelegates: DictLibLocalizations.localizationsDelegates,
      supportedLocales: DictLibLocalizations.supportedLocales,
      routerConfig: router,
    ));
    await tester.pumpAndSettle();

    // Open the members page.
    await tester.tap(find.text('OVERVIEW'));
    await tester.pumpAndSettle();
    expect(find.text('Leave this list'), findsOneWidget);
    expect(find.text('OVERVIEW'), findsNothing);

    // Leave → confirm in the dialog.
    await tester.tap(find.text('Leave this list'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog), matching: find.text('Leave this list')));
    await tester.pumpAndSettle();

    // Back on the overview; the members page is gone.
    expect(find.text('OVERVIEW'), findsOneWidget);
    expect(find.text('Leave this list'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  /// The invite-editor dialog should offer a QR code (like the regular
  /// subscribe-link dialog it now shares an implementation with).
  testWidgets('the invite-editor dialog offers a QR-code option',
      (tester) async {
    // The QR dialog is taller than the default 800x600 test surface (fine on
    // a real phone); give it phone-like height so it doesn't overflow.
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    installFakeSharing((req) async {
      if (req.method == 'POST' && req.url.path.endsWith('/invites')) {
        return http.Response(
          jsonEncode({
            'token': 'tok123',
            'expiresAt': 1700600000,
            'listId': 'ownerlist001',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('unexpected ${req.method} ${req.url.path}', 500);
    });

    final list = await installOwnerListWithBob();
    await tester.pumpWidget(wrap(list));
    await tester.pumpAndSettle();

    // Owner taps "Invite an editor".
    await tester.tap(find.byIcon(Icons.person_add));
    await tester.pumpAndSettle();

    // The invite dialog now offers copy/share/QR (deduped with the
    // subscribe-link dialog), so the QR button is present.
    expect(find.text('QR code'), findsOneWidget);

    // Tapping it opens the QR dialog with a rendered code.
    await tester.tap(find.text('QR code'));
    await tester.pumpAndSettle();
    expect(find.byType(QrImageView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
