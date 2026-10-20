import 'dart:convert';

import 'package:dictionarylib/common.dart';
import 'package:dictionarylib/globals.dart';
import 'package:dictionarylib/l10n/app_localizations.dart';
import 'package:dictionarylib/sharing/auth/apple_sign_in.dart';
import 'package:dictionarylib/sharing/auth/auth_store.dart';
import 'package:dictionarylib/sharing/auth/sign_in_dialog.dart';
import 'package:flutter/foundation.dart';
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
  testWidgets('showSignInDialog re-entry returns the same future', (
    tester,
  ) async {
    Future<AuthSession?>? firstFuture;
    Future<AuthSession?>? secondFuture;

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: DictLibLocalizations.localizationsDelegates,
        supportedLocales: DictLibLocalizations.supportedLocales,
        home: _CaptureContext(
          onReady: (ctx) {
            // Two callers race to open the dialog. The guard should
            // collapse them onto a single inflight future.
            firstFuture = showSignInDialog(ctx);
            secondFuture = showSignInDialog(ctx);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(firstFuture, isNotNull);
    expect(secondFuture, isNotNull);
    expect(
      identical(firstFuture, secondFuture),
      isTrue,
      reason: 'reentry guard must return the same Future instance',
    );

    // Dialog is on screen; dismiss it via the Cancel button so the
    // shared future resolves to null and pumpAndSettle has something
    // to settle on.
    final l = DictLibLocalizations.of(
      tester.element(find.byType(_CaptureContext).first),
    )!;
    await tester.tap(find.text(l.alertCancel));
    await tester.pumpAndSettle();

    expect(await firstFuture, isNull);
    expect(await secondFuture, isNull);
  });

  /// A new account Apple sends no name for is refused by the server. The
  /// dialog has to say exactly how to make Apple share the name again, and
  /// those steps live in a different place on an iPhone than on Android.
  testWidgets('a nameless Apple sign-in shows the steps to fix it', (
    tester,
  ) async {
    installFakeSharing(
      (req) async => http.Response(
        jsonEncode({
          'error': {
            'code': 'FORBIDDEN',
            'message': 'no name was shared for this account',
            'details': {'reason': 'name_required'},
          },
        }),
        403,
      ),
      appleSignIn: (_) async => const AppleSignInResult(idToken: 'a.b.c'),
    );

    Future<void> signInWithAppleOn(TargetPlatform platform) async {
      debugDefaultTargetPlatformOverride = platform;
      await tester.pumpWidget(
        MaterialApp(
          key: ValueKey(platform),
          localizationsDelegates: DictLibLocalizations.localizationsDelegates,
          supportedLocales: DictLibLocalizations.supportedLocales,
          home: _CaptureContext(
            onReady: (ctx) {
              showSignInDialog(ctx);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue with Apple'));
      await tester.pumpAndSettle();
    }

    try {
      await signInWithAppleOn(TargetPlatform.iOS);
      expect(
        find.textContaining(
          'Settings → your name → Sign in with Apple → Test App → Delete',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      await signInWithAppleOn(TargetPlatform.android);
      expect(
        find.textContaining(
          'account.apple.com, open Sign-In & Security → Sign in with Apple → '
          'Test App',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Settings → your name'), findsNothing);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // The message is long: on a phone in landscape it must scroll, not
      // overflow.
      await tester.binding.setSurfaceSize(const Size(667, 375));
      await signInWithAppleOn(TargetPlatform.iOS);
      expect(tester.takeException(), isNull);
      expect(find.textContaining('Settings → your name'), findsOneWidget);
      // Close it: an open dialog is shared with the next caller.
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    } finally {
      debugDefaultTargetPlatformOverride = null;
      await tester.binding.setSurfaceSize(null);
    }
  });

  /// The "last time you signed in with X" hint must not name a provider
  /// whose button is no longer offered (killswitched or platform-hidden) —
  /// a user should not be teased with a provider they can't tap.
  testWidgets('last-used hint is suppressed for unavailable providers', (
    tester,
  ) async {
    Future<void> openDialogWithLastProvider(String providerName) async {
      await sharedPreferences.setString(KEY_LAST_AUTH_PROVIDER, providerName);
      // Key the harness per case — otherwise the second pumpWidget updates
      // the existing element in place and initState/onReady never refires.
      await tester.pumpWidget(
        MaterialApp(
          key: ValueKey(providerName),
          localizationsDelegates: DictLibLocalizations.localizationsDelegates,
          supportedLocales: DictLibLocalizations.supportedLocales,
          home: _CaptureContext(
            onReady: (ctx) {
              showSignInDialog(ctx);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    // Microsoft is unconfigured in kTestSharingConfig (no client id), so its
    // button is hidden and the hint must not appear either.
    await openDialogWithLastProvider('microsoft');
    var l = DictLibLocalizations.of(
      tester.element(find.byType(_CaptureContext).first),
    )!;
    expect(
      find.text(l.signInLastUsedHint(l.providerMicrosoft)),
      findsNothing,
      reason: 'no hint for a provider with no button',
    );
    await tester.tap(find.text(l.alertCancel));
    await tester.pumpAndSettle();

    // Google is available, so the same record shows the hint.
    await openDialogWithLastProvider('google');
    l = DictLibLocalizations.of(
      tester.element(find.byType(_CaptureContext).first),
    )!;
    expect(
      find.text(l.signInWithGoogle),
      findsOneWidget,
      reason: 'sanity: the second dialog should be open',
    );
    expect(
      find.text(l.signInLastUsedHint(l.providerGoogle)),
      findsOneWidget,
      reason: 'available providers keep the hint',
    );
    await tester.tap(find.text(l.alertCancel));
    await tester.pumpAndSettle();
  });
}
