// The two things every MaterialApp needs since Material moved out of the
// Flutter SDK into package:material_ui (Flutter 3.50): material_ui's own
// localizations, and a bridge so widgets from packages still on
// package:flutter/material.dart see the app's theme.

// ignore_for_file: deprecated_member_use
import 'package:dictionarylib/material_ui_setup.dart';
import 'package:flutter/material.dart' as legacy;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('legacy Material widgets see the app\'s dark theme', (
    tester,
  ) async {
    late legacy.ThemeData seen;
    final dark = ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.teal,
        brightness: Brightness.dark,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: dark,
        builder: (context, child) => legacyMaterialBridge(child!),
        home: Builder(
          builder: (context) {
            seen = legacyThemeOf(context);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(seen.brightness, Brightness.dark);
    expect(seen.colorScheme.surface, dark.colorScheme.surface);
    expect(seen.colorScheme.primary, dark.colorScheme.primary);
  });

  testWidgets('Material strings come in Sinhala, not English', (tester) async {
    late MaterialLocalizations material;
    late legacy.MaterialLocalizations legacyMaterial;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: dictLibLocalizationsDelegates,
        supportedLocales: const [Locale('en'), Locale('si')],
        locale: const Locale('si'),
        builder: (context, child) => legacyMaterialBridge(child!),
        home: Builder(
          builder: (context) {
            material = MaterialLocalizations.of(context);
            legacyMaterial = legacy.MaterialLocalizations.of(context);
            return const SizedBox();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(material.backButtonTooltip, 'ආපසු');
    expect(legacyMaterial.backButtonTooltip, 'ආපසු');
  });
}
