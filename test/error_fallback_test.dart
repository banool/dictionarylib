import 'package:dictionarylib/common.dart';
import 'package:dictionarylib/entry_loader.dart';
import 'package:dictionarylib/error_fallback.dart';
import 'package:dictionarylib/globals.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '_helpers.dart' show installFakeSecureStorage;

Future<void> pumpErrorFallback(
  WidgetTester tester, {
  Object? error,
  String? faqUrl,
  VoidCallback? onRetry,
}) async {
  await tester.pumpWidget(
    ErrorFallback(
      appName: 'Test Dictionary',
      error:
          error ??
          DictionaryDataUnavailableError(
            Exception('the download exploded'),
            StackTrace.current,
          ),
      stackTrace: StackTrace.current,
      faqUrl: faqUrl,
      onRetry: onRetry ?? () {},
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() async {
    installFakeSecureStorage();
    SharedPreferences.setMockInitialValues({});
    sharedPreferences = await SharedPreferences.getInstance();
  });

  testWidgets('data-unavailable error shows the download-specific copy', (
    tester,
  ) async {
    await pumpErrorFallback(tester);
    expect(find.text("We couldn't download the dictionary"), findsOneWidget);
    // The generic copy is absent.
    expect(find.text('Something went wrong starting the app'), findsNothing);
    // The underlying error is tucked behind the collapsed disclosure.
    expect(find.textContaining('the download exploded'), findsNothing);
  });

  testWidgets('any other error shows the generic copy', (tester) async {
    await pumpErrorFallback(tester, error: Exception('unrelated crash'));
    expect(find.text('Something went wrong starting the app'), findsOneWidget);
    expect(find.text("We couldn't download the dictionary"), findsNothing);
  });

  testWidgets('the disclosure reveals the underlying error and logs', (
    tester,
  ) async {
    await pumpErrorFallback(tester);
    await tester.tap(find.text('Technical details'));
    await tester.pumpAndSettle();
    expect(find.textContaining('the download exploded'), findsOneWidget);
    expect(find.textContaining('Background logs:'), findsOneWidget);
  });

  testWidgets('Retry fires the callback and shows a spinner', (tester) async {
    var retried = false;
    await pumpErrorFallback(tester, onRetry: () => retried = true);
    await tester.tap(find.text('Try again'));
    await tester.pump();
    expect(retried, true);
    expect(
      find.descendant(
        of: find.byType(FilledButton),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the proxy switch writes the pref', (tester) async {
    await pumpErrorFallback(tester);
    expect(sharedPreferences.getBool(KEY_USE_SYSTEM_HTTP_PROXY), null);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(sharedPreferences.getBool(KEY_USE_SYSTEM_HTTP_PROXY), true);
  });

  testWidgets('Background logs opens the logs page', (tester) async {
    await pumpErrorFallback(tester);
    await tester.tap(find.text('Background logs'));
    await tester.pumpAndSettle();
    // The page shows its copy button; that's proof it mounted fine outside
    // the real app (no router, no late globals).
    expect(find.text('Copy logs to clipboard'), findsOneWidget);
  });

  testWidgets('the FAQ link is only shown when a URL is configured', (
    tester,
  ) async {
    await pumpErrorFallback(tester);
    expect(find.text('More help on our website'), findsNothing);

    await pumpErrorFallback(tester, faqUrl: 'https://example.com/faq.html');
    expect(find.text('More help on our website'), findsOneWidget);
  });
}
