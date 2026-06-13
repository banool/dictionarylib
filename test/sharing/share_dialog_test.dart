import 'dart:collection';
import 'dart:convert';

import 'package:dictionarylib/globals.dart';
import 'package:dictionarylib/l10n/app_localizations.dart';
import 'package:dictionarylib/saved_video.dart';
import 'package:dictionarylib/sharing/share_dialog.dart';
import 'package:dictionarylib/sharing/synced_entry_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../_helpers.dart';

/// Tiny harness that just opens the subscribe dialog when first shown.
class _OpenSubscribeDialog extends StatefulWidget {
  const _OpenSubscribeDialog();
  @override
  State<_OpenSubscribeDialog> createState() => _OpenSubscribeDialogState();
}

class _OpenSubscribeDialogState extends State<_OpenSubscribeDialog> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      showSubscribeDialog(context: context);
    });
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: SizedBox.shrink());
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    sharedPreferences = await SharedPreferences.getInstance();
    installFakeSharing((_) async => http.Response('not used', 500));
  });

  /// Regression test for a "TextEditingController used after dispose" crash
  /// on the subscribe dialog.
  ///
  /// Cause: `showSubscribeDialog` originally disposed its controller in a
  /// `finally` immediately after `showDialog`'s future returned. But
  /// `Navigator.pop` completes that future synchronously, while the
  /// dialog's `TextField` (which still references the controller) isn't
  /// unmounted until the next frame — so the next pump tried to access a
  /// disposed controller and threw. The fix defers disposal to a
  /// post-frame callback; this test guards against reintroducing the bug.
  testWidgets('cancelling the subscribe dialog does not throw', (tester) async {
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: DictLibLocalizations.localizationsDelegates,
      supportedLocales: DictLibLocalizations.supportedLocales,
      home: const _OpenSubscribeDialog(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Subscribe to a shared list'), findsOneWidget,
        reason: 'subscribe dialog should be open');

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  /// Pasting an editor-invite link into the subscribe dialog should not be
  /// rejected (the old behaviour) and should not silently subscribe the user
  /// as a non-editor. Instead the dialog explains it's an invite and offers to
  /// accept it; accepting joins the list as an editor. (Issue: "it should be
  /// possible for an editor to just paste the invite link in from the
  /// subscribe-via-link modal".)
  testWidgets(
      'pasting an invite link switches to accept-invite mode and accepting '
      'joins as editor', (tester) async {
    const listId = 'abc234xyz567';
    const name = 'Animals 101';
    final requests = installFakeSharing((req) async {
      // Public preview fetch — names the list in the invite copy.
      if (req.method == 'GET' && req.url.path == '/v1/lists/$listId') {
        return http.Response(
          jsonEncode(snapshotJson(listId: listId, displayName: name)),
          200,
          headers: {'content-type': 'application/json', 'etag': '"v1"'},
        );
      }
      // Accept-invite — registers the caller as an editor and returns the
      // full snapshot the engine installs locally.
      if (req.method == 'POST' &&
          req.url.path == '/v1/lists/$listId/accept-invite') {
        return http.Response(
          jsonEncode(snapshotJson(listId: listId, displayName: name)),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('unexpected ${req.method} ${req.url.path}', 500);
    });

    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: DictLibLocalizations.localizationsDelegates,
      supportedLocales: DictLibLocalizations.supportedLocales,
      home: const _OpenSubscribeDialog(),
    ));
    await tester.pumpAndSettle();

    // Paste an invite link and submit.
    await tester.enterText(find.byType(TextField),
        'https://share.example.test/l/$listId?invite=tok123');
    await tester.tap(find.text('Subscribe'));
    await tester.pumpAndSettle();

    // The dialog now explains it's an editor invite (naming the list from the
    // preview fetch) and offers to accept — not the plain subscribe UI.
    expect(find.textContaining('editor invite link'), findsOneWidget);
    expect(find.textContaining(name), findsWidgets);
    expect(find.text('Accept invitation'), findsOneWidget);
    expect(find.text('Subscribe'), findsNothing);

    // Accept it.
    await tester.tap(find.text('Accept invitation'));
    await tester.pumpAndSettle();

    // Dialog closed; the accept-invite endpoint was hit; the list is now
    // installed locally as an editor list.
    expect(find.text('Accept invitation'), findsNothing);
    expect(
        requests.any((r) =>
            r.method == 'POST' &&
            r.url.path == '/v1/lists/$listId/accept-invite'),
        isTrue,
        reason: 'accepting should POST to the accept-invite endpoint');
    final installed = sharing.lists.get(listId);
    expect(installed, isNotNull);
    expect(installed!.meta.role, ListRole.editor);
    expect(tester.takeException(), isNull);
  });

  /// An invite link for a list the user already edits should just open it,
  /// not try to re-accept (which would burn a fresh token for nothing).
  testWidgets(
      'invite link for an already-edited list opens it without a '
      'network accept', (tester) async {
    const listId = 'abc234xyz567';
    const name = 'Animals 101';
    final requests = installFakeSharing((req) async {
      // Preview fetch is harmless if it happens, but it shouldn't be needed.
      return http.Response(
        jsonEncode(snapshotJson(listId: listId, displayName: name)),
        200,
        headers: {'content-type': 'application/json', 'etag': '"v1"'},
      );
    });
    // Pre-install the list as an editor list.
    await sharing.lists.insert(SyncedEntryList.editor(
      meta: SyncedListMeta(
        listId: listId,
        displayName: name,
        role: ListRole.editor,
        lastKnownSeq: 1,
        etag: null,
        lastSyncedAt: 1700000000,
        serverUpdatedAt: 1700000000,
        orphaned: false,
      ),
      savedVideos: LinkedHashSet<SavedVideo>(),
    ));

    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: DictLibLocalizations.localizationsDelegates,
      supportedLocales: DictLibLocalizations.supportedLocales,
      home: const _OpenSubscribeDialog(),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField),
        'https://share.example.test/l/$listId?invite=tok123');
    await tester.tap(find.text('Subscribe'));
    await tester.pumpAndSettle();

    // It opened the existing list (dialog popped) and never hit accept-invite.
    expect(find.text('Accept invitation'), findsNothing);
    expect(requests.any((r) => r.url.path.endsWith('/accept-invite')), isFalse,
        reason: 'already an editor — no need to accept again');
    expect(tester.takeException(), isNull);
  });
}
