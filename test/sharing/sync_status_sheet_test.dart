import 'package:dictionarylib/entry_list.dart';
import 'package:dictionarylib/flashcards_logic.dart';
import 'package:dictionarylib/globals.dart';
import 'package:dictionarylib/l10n/app_localizations.dart';
import 'package:dictionarylib/revision_history.dart';
import 'package:dictionarylib/sharing/account_sync.dart';
import 'package:dictionarylib/sharing/account_sync_state.dart';
import 'package:dictionarylib/sharing/sync_api.dart';
import 'package:dictionarylib/sharing/sync_status_sheet.dart';
import 'package:dolphinsr/dolphinsr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../_helpers.dart';
import '_account_sync_harness.dart';
import '_fake_account_server.dart';

/// The sync status sheet (Settings → "Signed in with …"), in each state it
/// can be in, and its Sync now button.
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

  Future<void> signedIn(WidgetTester tester) async {
    phone = TestDevice(server, 'phone');
    await tester.runAsync(() async {
      await phone.activate();
      await phone.addLocalList('Animals', ['cat', 'dog']);
      await phone.signIn('alice');
      await phone.settle();
    });
  }

  Future<void> pumpSheet(WidgetTester tester) async {
    tester.view.physicalSize = const Size(750, 1334);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: DictLibLocalizations.localizationsDelegates,
        supportedLocales: DictLibLocalizations.supportedLocales,
        home: const Scaffold(body: SyncStatusSheet()),
      ),
    );
    await tester.pump();
  }

  /// The row's value (its subtitle), or null when the row isn't shown.
  String? value(WidgetTester tester, Key key) {
    final row = find.byKey(key);
    if (row.evaluate().isEmpty) return null;
    final texts = tester
        .widgetList<Text>(find.descendant(of: row, matching: find.byType(Text)))
        .map((t) => t.data ?? '')
        .toList();
    return texts.skip(1).join('\n');
  }

  testWidgets('synced, nothing waiting: no problem row', (tester) async {
    await signedIn(tester);
    await pumpSheet(tester);
    expect(find.text('Sync status'), findsOneWidget);
    expect(value(tester, SyncStatusKeys.account), 'Test session');
    expect(value(tester, SyncStatusKeys.status), 'Synced just now');
    expect(value(tester, SyncStatusKeys.lastSynced), isNot('Never'));
    expect(value(tester, SyncStatusKeys.lastSynced), contains(','));
    expect(value(tester, SyncStatusKeys.lists), '2 syncing');
    expect(value(tester, SyncStatusKeys.follows), '0');
    expect(value(tester, SyncStatusKeys.pending), 'Nothing');
    expect(value(tester, SyncStatusKeys.problem), isNull);
    await tester.runAsync(() async => phone.deactivate());
  });

  testWidgets('never synced, the server out of reach', (tester) async {
    phone = TestDevice(server, 'phone');
    await tester.runAsync(() async {
      await phone.activate();
      final big = await phone.addLocalList('Huge', []);
      for (var i = 0; i <= maxEntriesPerPrivateList; i++) {
        big.savedVideos.add(video('w$i'));
      }
      await big.write();
      server.net.down();
      await phone.signIn('alice');
      await sharing.accountSync.kick(SyncReason.pullToRefresh);
    });
    await pumpSheet(tester);
    expect(value(tester, SyncStatusKeys.lastSynced), 'Never');
    expect(value(tester, SyncStatusKeys.status), 'Waiting for a connection');
    expect(value(tester, SyncStatusKeys.problem), "Couldn't reach the server");
    // Too large to sync even before a merge has said so.
    expect(
      value(tester, SyncStatusKeys.lists),
      '1 syncing\n1 not syncing\nHuge: more than 500 signs',
    );
    await tester.runAsync(() async => phone.deactivate());
  });

  testWidgets('lists that stay on the device, each with its reason', (
    tester,
  ) async {
    phone = TestDevice(server, 'phone');
    await tester.runAsync(() async {
      await phone.activate();
      final big = await phone.addLocalList('Huge', []);
      for (var i = 0; i <= maxEntriesPerPrivateList; i++) {
        big.savedVideos.add(video('w$i'));
      }
      await big.write();
      await phone.addLocalList('Extra', ['cat']);
      await phone.addLocalList('Odd', ['dog']);
      await phone.signIn('alice');
      await phone.settle();
      // The other two reasons, as the controller records them.
      final st = sharing.accountSync.state!;
      st.unsyncable['Extra_words'] = UnsyncableReason.listLimit;
      st.unsyncable['Odd_words'] = UnsyncableReason.refused;
    });
    await pumpSheet(tester);
    expect(
      value(tester, SyncStatusKeys.lists),
      '1 syncing\n'
      '3 not syncing\n'
      'Extra: the account is full\n'
      'Odd: a name the account refused\n'
      'Huge: more than 500 signs',
    );
    await tester.runAsync(() async => phone.deactivate());
  });

  testWidgets('what is waiting to go up, and the followed lists', (
    tester,
  ) async {
    await signedIn(tester);
    await tester.runAsync(() async {
      final listId = server.createAccountList(
        'bob',
        'Bob shares',
        visibility: 'shared',
        entries: [
          ['owl', videoFor('owl')],
        ],
      );
      await sharing.engine.subscribe(listId);
      // The follow goes up with the next cycle.
      await sharing.accountSync.kick(SyncReason.pullToRefresh);
      server.net.down();
      final animals = sharing.lists.ownerForSourceKey('Animals_words')!;
      await animals.addVideo(video('owl'));
      await animals.removeVideo(video('cat'));
      await reviewHistory.appendLocal([answerFor('dog')], queueForUpload: true);
    });
    await pumpSheet(tester);
    expect(value(tester, SyncStatusKeys.follows), '1');
    expect(
      value(tester, SyncStatusKeys.pending),
      '2 list changes, 1 revision answer',
    );
    await tester.runAsync(() async => phone.deactivate());
  });

  testWidgets('the server failing: when it will try again', (tester) async {
    await signedIn(tester);
    await tester.runAsync(() async {
      server.net.flaky(1.0);
      await sharing.accountSync.kick(SyncReason.pullToRefresh);
    });
    await pumpSheet(tester);
    expect(
      value(tester, SyncStatusKeys.problem),
      startsWith('The server is unavailable, trying again at '),
    );
    expect(sharing.accountSync.nextRetryAt, isNotNull);
    await tester.runAsync(() async => phone.deactivate());
  });

  testWidgets('paused by the server (the kill switch): until when', (
    tester,
  ) async {
    await signedIn(tester);
    await tester.runAsync(() async {
      server.accountSyncDisabled = true;
      await sharing.accountSync.kick(SyncReason.pullToRefresh);
    });
    await pumpSheet(tester);
    expect(value(tester, SyncStatusKeys.status), 'Sync is paused');
    expect(
      value(tester, SyncStatusKeys.problem),
      startsWith('Paused by the server until '),
    );
    await tester.runAsync(() async => phone.deactivate());
  });

  testWidgets('the session expired', (tester) async {
    await signedIn(tester);
    await tester.runAsync(() async {
      server.tokens.clear();
      await sharing.accountSync.kick(SyncReason.pullToRefresh);
    });
    await pumpSheet(tester);
    expect(value(tester, SyncStatusKeys.account), 'Signed out');
    expect(value(tester, SyncStatusKeys.problem), 'Signed-in session expired');
    await tester.runAsync(() async => phone.deactivate());
  });

  for (final locale in const [Locale('si'), Locale('ta')]) {
    testWidgets('fits a small phone in ${locale.languageCode}, with every row '
        'shown', (tester) async {
      phone = TestDevice(server, 'phone');
      await tester.runAsync(() async {
        await phone.activate();
        final big = await phone.addLocalList('Huge', []);
        for (var i = 0; i <= maxEntriesPerPrivateList; i++) {
          big.savedVideos.add(video('w$i'));
        }
        await big.write();
        await phone.addLocalList('Animals', ['cat']);
        await phone.signIn('alice');
        await phone.settle();
        server.net.flaky(1.0);
        await sharing.lists
            .ownerForSourceKey('Animals_words')!
            .addVideo(video('dog'));
        await sharing.accountSync.kick(SyncReason.pullToRefresh);
      });
      // An iPhone SE (1st generation): 320 x 568.
      tester.view.physicalSize = const Size(640, 1136);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          locale: locale,
          localizationsDelegates: DictLibLocalizations.localizationsDelegates,
          supportedLocales: DictLibLocalizations.supportedLocales,
          home: const Scaffold(body: SyncStatusSheet()),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      for (final key in [
        SyncStatusKeys.account,
        SyncStatusKeys.status,
        SyncStatusKeys.lastSynced,
        SyncStatusKeys.lists,
        SyncStatusKeys.follows,
        SyncStatusKeys.pending,
        SyncStatusKeys.problem,
      ]) {
        expect(value(tester, key), isNotEmpty, reason: '$key');
      }
      await tester.runAsync(() async => phone.deactivate());
    });
  }

  testWidgets('Sync now spins while it runs, then the rows say how it went, '
      'with no snackbar', (tester) async {
    await signedIn(tester);
    await tester.runAsync(() async {
      server.net.down();
      await sharing.accountSync.kick(SyncReason.pullToRefresh);
    });
    await pumpSheet(tester);
    expect(value(tester, SyncStatusKeys.problem), "Couldn't reach the server");

    server.net.slow(const Duration(seconds: 1));
    await tester.tap(find.byKey(SyncStatusKeys.syncNow));
    await tester.pump();
    expect(
      find.descendant(
        of: find.byKey(SyncStatusKeys.syncNow),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
    for (var i = 0; i < 30 && sharing.accountSync.isSyncing; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    await tester.pump(const Duration(seconds: 1));
    expect(
      find.descendant(
        of: find.byKey(SyncStatusKeys.syncNow),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsNothing,
    );
    expect(value(tester, SyncStatusKeys.status), 'Synced just now');
    expect(value(tester, SyncStatusKeys.problem), isNull);
    expect(find.byType(SnackBar), findsNothing);
    await tester.runAsync(() async => phone.deactivate());
  });
}

/// One sign-to-word answer for [key], a minute ago.
Review answerFor(String key) => Review(
  master: savedVideoMasterId(video(key)),
  combination: const Combination(front: [1], back: [0]),
  rating: Rating.Good,
  ts: DateTime.now().subtract(const Duration(minutes: 1)),
);
