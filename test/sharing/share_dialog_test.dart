import 'package:dictionarylib/globals.dart';
import 'package:dictionarylib/l10n/app_localizations.dart';
import 'package:dictionarylib/sharing/share_dialog.dart';
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
}
