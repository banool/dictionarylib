import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// A minimal loading screen shown while the app initialises (loads the
/// dictionary and makes its first network calls). It runs *before* the real
/// [MaterialApp] and before localisation/theme setup, so it carries its own
/// tiny MaterialApp and hard-coded brand colours rather than reading from
/// context.
///
/// Only used on web: native platforms hold their configured native splash
/// across startup, whereas web has no splash and `setup()` would otherwise
/// leave a blank page for a few seconds. The colours mirror the native splash
/// (cream background) and the Hearth primary so the handoff to the real themed
/// app is seamless, and the text uses the bundled Hanken Grotesk — a default
/// font here would hit CanvasKit's `.AppleSystemUIFont` abort on web.
class StartupLoadingScreen extends StatelessWidget {
  const StartupLoadingScreen({super.key, required this.appName});

  final String appName;

  // Mirrors theme.dart's Hearth palette + the flutter_native_splash colour so
  // there's no visible jump when the real themed app replaces this.
  static const Color _bg = Color(0xFFFBF5EE);
  static const Color _primary = Color(0xFFBF5C36);
  static const Color _onSurface = Color(0xFF2A201A);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: _bg,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                appName,
                textAlign: TextAlign.center,
                style: GoogleFonts.hankenGrotesk(
                  color: _onSurface,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 24),
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: _primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
