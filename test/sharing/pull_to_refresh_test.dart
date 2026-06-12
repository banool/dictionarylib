import 'dart:collection';
import 'dart:convert';

import 'package:dictionarylib/entry_list.dart';
import 'package:dictionarylib/globals.dart';
import 'package:dictionarylib/l10n/app_localizations.dart';
import 'package:dictionarylib/page_entry_list.dart';
import 'package:dictionarylib/saved_video.dart';
import 'package:dictionarylib/sharing/synced_entry_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../_helpers.dart';

/// End-to-end coverage (engine + page + snacks, stubbed HTTP) for the
/// pull-to-refresh failure UX on a subscribed list. This automates the
/// manual repro of the original bug — a subscriber pulling to refresh
/// against an unreachable server saw the spinner end with no update and
/// no message. Now: transient failures retry with visible "attempt n of
/// m" feedback, a hard failure ends in a snack naming the actual
/// problem, and a failure that recovers mid-retry needs no error at all.
void main() {
  setUp(() async {
    installFakeSecureStorage();
    SharedPreferences.setMockInitialValues({});
    sharedPreferences = await SharedPreferences.getInstance();
    seedDictionary(['apple', 'banana']);
    userEntryListManager = UserEntryListManager.fromStartup();
  });

  Future<SyncedEntryList> installSubscribedList() async {
    final list = SyncedEntryList.subscriber(
      meta: SyncedListMeta(
        listId: 'subbed123456',
        displayName: 'Subbed',
        role: ListRole.subscriber,
        lastKnownSeq: 1,
        etag: null,
        lastSyncedAt: 1700000000,
        serverUpdatedAt: 1700000000,
        orphaned: false,
      ),
      savedVideos: LinkedHashSet.of(
          {SavedVideo(entryKey: 'apple', videoUrl: videoFor('apple'))}),
    );
    await sharing.lists.insert(list);
    return list;
  }

  Widget wrap(SyncedEntryList list) => MaterialApp(
        localizationsDelegates: DictLibLocalizations.localizationsDelegates,
        supportedLocales: DictLibLocalizations.supportedLocales,
        home: EntryListPage(
          entryList: list,
          navigateToEntryPage: (context, entry, showSaveButtons,
              {focusVideo, saveToList}) async {},
        ),
      );

  /// Drag far enough to trigger the [RefreshIndicator] and let it settle
  /// into the refreshing state.
  Future<void> pullToRefresh(WidgetTester tester) async {
    await tester.fling(
        find.byType(RefreshIndicator), const Offset(0, 300), 1000);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets(
      'unreachable server: pull-to-refresh retries with attempt feedback '
      'and ends in a snack naming the problem', (tester) async {
    final requests = installFakeSharing(
        (req) async => throw http.ClientException('connection refused'));
    final list = await installSubscribedList();
    await tester.pumpWidget(wrap(list));
    await tester.pumpAndSettle();

    await pullToRefresh(tester);

    // Attempt 1 fails immediately, so the attempt-2 notice is up while
    // the 1s retry delay runs.
    expect(find.textContaining('attempt 2 of 3'), findsOneWidget);

    // Through the 1s delay: attempt 2 fails and its notice replaces the
    // previous one rather than queueing behind it.
    await tester.pump(const Duration(milliseconds: 1100));
    expect(find.textContaining('attempt 3 of 3'), findsOneWidget);
    expect(find.textContaining('attempt 2 of 3'), findsNothing);

    // Through the 2s delay: attempt 3 fails and the final snack says
    // specifically what went wrong instead of failing silently.
    await tester.pump(const Duration(milliseconds: 2100));
    await tester.pump();
    expect(find.textContaining('Sync failed'), findsOneWidget);
    expect(find.textContaining("Couldn't reach the server"), findsOneWidget);
    expect(requests, hasLength(3), reason: 'three attempts should be made');

    // Drain the snack's auto-dismiss timer so the test ends clean.
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('a transient failure that recovers needs no error snack',
      (tester) async {
    var calls = 0;
    installFakeSharing((req) async {
      calls++;
      if (calls < 3) throw http.ClientException('connection refused');
      return http.Response(
        jsonEncode({
          'schemaVersion': 3,
          'listId': 'subbed123456',
          'displayName': 'Subbed',
          'appId': 'auslan',
          'entries': [
            {'entry': 'apple', 'video': videoFor('apple')},
            {'entry': 'banana', 'video': videoFor('banana')},
          ],
          'lastSeq': 2,
          'createdAt': 1700000000,
          'updatedAt': 1700000100,
        }),
        200,
        headers: {
          'content-type': 'application/json',
          'etag': '"etag2"',
          'last-modified': 'Mon, 14 Nov 2023 12:00:00 GMT',
        },
      );
    });
    final list = await installSubscribedList();
    await tester.pumpWidget(wrap(list));
    await tester.pumpAndSettle();

    await pullToRefresh(tester);
    // Walk through both retry delays; the third attempt succeeds.
    await tester.pump(const Duration(milliseconds: 1100));
    await tester.pump(const Duration(milliseconds: 2100));
    await tester.pump();

    expect(calls, 3);
    expect(find.textContaining('Sync failed'), findsNothing);
    // The recovered pull replaced local entries with the server payload.
    expect(find.textContaining('banana'), findsOneWidget);

    // Drain the last attempt-notice snack's timer.
    await tester.pump(const Duration(seconds: 5));
  });
}
