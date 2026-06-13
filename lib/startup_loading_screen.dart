import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// A minimal loading screen shown while the app initialises (loads the
/// dictionary and makes its first network calls). It runs *before* the real
/// app and before localisation/theme setup, so it carries its own hard-coded
/// brand colours rather than reading from context.
///
/// Deliberately a **bare** widget tree — no [MaterialApp], no Navigator/Router.
/// It's shown via a first `runApp(...)` on web (where there's no native splash
/// and `setup()` would otherwise leave a blank page for a few seconds), then
/// replaced by the real app once setup completes. A [MaterialApp] here would
/// install a Navigator that, finding no route for a deep link like
/// `/share/<id>`, falls back to `/` and reports it to the engine — clobbering
/// the deep link before the real router (go_router) ever reads it. A bare tree
/// never reports a route, so the initial URL is preserved.
///
/// The colours mirror the native splash (cream background) and the Hearth
/// primary so the handoff to the real themed app is seamless, and the text uses
/// the bundled Hanken Grotesk — a default font here would hit CanvasKit's
/// `.AppleSystemUIFont` abort on web.
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
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: _bg,
        child: Center(
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
