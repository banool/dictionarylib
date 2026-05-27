import 'package:dictionarylib/globals.dart';
import 'package:dictionarylib/l10n/app_localizations.dart';
import 'package:dictionarylib/sharing/auth/auth_store.dart';
import 'package:dictionarylib/sharing/auth/sign_in_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../_helpers.dart';

/// Test harness that exposes its [BuildContext] so the test body can
/// invoke [showSignInDialog] directly — same approach
/// `share_dialog_test.dart` uses for the subscribe dialog.
class _CaptureContext extends StatefulWidget {
  final void Function(BuildContext) onReady;
  const _CaptureContext({required this.onReady});
  @override
  State<_CaptureContext> createState() => _CaptureContextState();
}

class _CaptureContextState extends State<_CaptureContext> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onReady(context);
    });
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: SizedBox.shrink());
}

void main() {
  setUp(() async {
    installFakeSecureStorage();
    SharedPreferences.setMockInitialValues({});
    sharedPreferences = await SharedPreferences.getInstance();
    // Drop any stale session — the dialog short-circuits if `sharing`
    // is null and we want it to be installed below.
    installFakeSharing((_) async => http.Response('not used', 500));
  });

  /// Regression test for the sign-in dialog reentrancy guard. Two
  /// near-simultaneous code paths (e.g. "tap Share → no session →
  /// dialog" and "deep link arrives → landing page → also wants
  /// sign-in") previously stacked two dialogs and stranded one
  /// caller's future indefinitely. The new guard makes the second
  /// caller join the first caller's future instead.
  testWidgets('showSignInDialog re-entry returns the same future',
      (tester) async {
    Future<AuthSession?>? firstFuture;
    Future<AuthSession?>? secondFuture;

    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: DictLibLocalizations.localizationsDelegates,
      supportedLocales: DictLibLocalizations.supportedLocales,
      home: _CaptureContext(onReady: (ctx) {
        // Two callers race to open the dialog. The guard should
        // collapse them onto a single inflight future.
        firstFuture = showSignInDialog(ctx);
        secondFuture = showSignInDialog(ctx);
      }),
    ));
    await tester.pumpAndSettle();

    expect(firstFuture, isNotNull);
    expect(secondFuture, isNotNull);
    expect(identical(firstFuture, secondFuture), isTrue,
        reason: 'reentry guard must return the same Future instance');

    // Dialog is on screen; dismiss it via the Cancel button so the
    // shared future resolves to null and pumpAndSettle has something
    // to settle on.
    final l = DictLibLocalizations.of(
        tester.element(find.byType(_CaptureContext).first))!;
    await tester.tap(find.text(l.alertCancel));
    await tester.pumpAndSettle();

    expect(await firstFuture, isNull);
    expect(await secondFuture, isNull);
  });
}
