import 'package:dictionarylib/tv_focus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// The remote-control support must change nothing off Android TV: phones and
// tablets (even with a hardware keyboard) keep the arrow keys' text-editing
// meaning and draw no focus ring.

final _ring = find.byKey(const ValueKey('tvFocusRing'));

Future<(FocusNode, FocusNode)> _pumpFieldAboveButton(
  WidgetTester tester,
) async {
  final field = FocusNode();
  final button = FocusNode();
  addTearDown(field.dispose);
  addTearDown(button.dispose);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => FocusRingOverlay(child: child!),
      home: Scaffold(
        body: Column(
          children: [
            TextField(focusNode: field, autofocus: true),
            TextButton(
              focusNode: button,
              onPressed: () {},
              child: const Text('below'),
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pump();
  return (field, button);
}

void main() {
  tearDown(() {
    isAndroidTv = false;
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic;
  });

  testWidgets('off TV, down stays in the text field and no ring is drawn', (
    tester,
  ) async {
    applyTvFocusDefaults(const ['android.hardware.touchscreen']);
    expect(isAndroidTv, isFalse);
    final (field, button) = await _pumpFieldAboveButton(tester);
    expect(field.hasPrimaryFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();

    expect(field.hasPrimaryFocus, isTrue);
    expect(button.hasPrimaryFocus, isFalse);
    expect(_ring, findsNothing);
  });

  testWidgets('on TV, down leaves the text field and the ring follows', (
    tester,
  ) async {
    applyTvFocusDefaults(const ['android.software.leanback']);
    expect(isAndroidTv, isTrue);
    final (field, button) = await _pumpFieldAboveButton(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.pump();

    expect(button.hasPrimaryFocus, isTrue);
    expect(_ring, findsOneWidget);
  });
}
