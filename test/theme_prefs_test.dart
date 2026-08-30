import 'package:dictionarylib/common.dart';
import 'package:dictionarylib/globals.dart';
import 'package:dictionarylib/startup_loading.dart';
import 'package:dictionarylib/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    // The theme notifiers are globals shared across tests — restore defaults.
    themeNotifier.value = ThemeMode.system;
    themeVariantNotifier.value = kDefaultThemeVariant;
  });

  test('applyPersistedThemePrefs applies the stored variant + mode', () async {
    SharedPreferences.setMockInitialValues({
      KEY_THEME_VARIANT: 'classic',
      KEY_THEME_MODE: ThemeMode.dark.index,
    });
    sharedPreferences = await SharedPreferences.getInstance();
    applyPersistedThemePrefs();
    expect(themeVariantNotifier.value, AppThemeVariant.classic);
    expect(themeNotifier.value, ThemeMode.dark);
  });

  test(
    'applyPersistedThemePrefs leaves defaults when nothing stored',
    () async {
      SharedPreferences.setMockInitialValues({});
      sharedPreferences = await SharedPreferences.getInstance();
      applyPersistedThemePrefs();
      expect(themeVariantNotifier.value, kDefaultThemeVariant);
      expect(themeNotifier.value, ThemeMode.system);
    },
  );
}
