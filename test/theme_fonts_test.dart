import 'package:dictionarylib/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

// Guards the offline-first invariant: the Hearth typefaces must be bundled as
// assets and google_fonts must never reach out to the network for them.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('building the Hearth theme disables runtime font fetching', () {
    // Flip it back on first so we know buildAppTheme is what turns it off.
    GoogleFonts.config.allowRuntimeFetching = true;
    buildAppTheme(
      variant: AppThemeVariant.hearth,
      brightness: Brightness.light,
      classicSeed: Colors.blue,
    );
    expect(GoogleFonts.config.allowRuntimeFetching, isFalse);
  });

  test('every Hearth font weight google_fonts can load is bundled', () async {
    // The static instances that must ship with the app. Filenames follow the
    // "<Family>-<Weight>" convention google_fonts matches against.
    const fonts = <String>[
      'HankenGrotesk-Regular',
      'HankenGrotesk-Medium',
      'HankenGrotesk-SemiBold',
      'HankenGrotesk-Bold',
      'HankenGrotesk-ExtraBold',
      'BricolageGrotesque-Regular',
      'BricolageGrotesque-Bold',
    ];
    for (final name in fonts) {
      final data = await rootBundle.load('assets/fonts/$name.ttf');
      expect(data.lengthInBytes, greaterThan(0), reason: '$name.ttf is empty');
    }
  });

  test('the Google sign-in logo asset is bundled', () async {
    final data = await rootBundle.load('assets/brand/google-g.png');
    expect(data.lengthInBytes, greaterThan(0));
  });

  // Asset existence alone doesn't prove the theme actually uses the custom
  // typefaces — google_fonts silently falls back to the platform font if the
  // wiring breaks. Assert the families are threaded into the text theme. The
  // `contains` tolerates google_fonts' "<Family>_<variant>" family suffix.
  test('the Hearth theme wires text to the bundled typefaces', () {
    for (final brightness in Brightness.values) {
      final theme = buildAppTheme(
        variant: AppThemeVariant.hearth,
        brightness: brightness,
        classicSeed: Colors.blue,
      );
      // Body text → Hanken Grotesk.
      expect(theme.textTheme.bodyMedium?.fontFamily, contains('HankenGrotesk'),
          reason: 'body text should use Hanken Grotesk ($brightness)');
      // Display / headline text → Bricolage Grotesque.
      expect(theme.textTheme.displayLarge?.fontFamily,
          contains('BricolageGrotesque'),
          reason: 'display text should use Bricolage Grotesque ($brightness)');
    }
  });
}
