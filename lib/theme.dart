// Theme system for the sign-language dictionary apps.
//
// The app ships more than one visual style ("theme variant") so users can
// switch between the modern "Hearth" redesign and the original stock-Material
// look. Each variant is a pair of [ThemeData] (light + dark) built here, so all
// the theming lives in the shared library rather than in each consuming app.
//
// See `Auslan Dictionary - Hearth` design handoff for the Hearth tokens.

import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// The visual style of the app. Persisted by name (see `KEY_THEME_VARIANT`) so
/// the order of these values can change without breaking stored preferences.
enum AppThemeVariant {
  /// The "Hearth" redesign: a warm clay-and-cream palette, Bricolage Grotesque
  /// display type over Hanken Grotesk body, and cohesively-styled Material 3
  /// components. This is the default.
  hearth,

  /// The original stock-Material look — a coloured app bar seeded from the
  /// app's [MaterialColor]. Kept so users can return to the familiar design.
  classic;

  /// Human-readable name shown in the settings chooser. Not localised: these
  /// are effectively proper nouns for the two looks.
  String get displayName {
    switch (this) {
      case AppThemeVariant.hearth:
        return 'Hearth';
      case AppThemeVariant.classic:
        return 'Classic';
    }
  }
}

/// The variant used when nothing has been chosen yet. Flip this single
/// constant to change which look new installs (and users who never visit the
/// chooser) get.
const AppThemeVariant kDefaultThemeVariant = AppThemeVariant.hearth;

/// Parse a stored variant name back into an [AppThemeVariant], falling back to
/// [kDefaultThemeVariant] for unknown / null values.
AppThemeVariant appThemeVariantFromName(String? name) {
  for (final v in AppThemeVariant.values) {
    if (v.name == name) return v;
  }
  return kDefaultThemeVariant;
}

/// Build the [ThemeData] for the given [variant] and [brightness].
///
/// [classicSeed] is the app-specific [MaterialColor] the Classic look is
/// seeded from (e.g. `Colors.blue` for Auslan). It is ignored by the Hearth
/// variant, which has its own fixed palette.
ThemeData buildAppTheme({
  required AppThemeVariant variant,
  required Brightness brightness,
  required Color classicSeed,
}) {
  // These apps are offline-first, so never reach out to the Google Fonts CDN.
  // The Hearth typefaces are bundled as assets (see pubspec.yaml); google_fonts
  // loads them from the asset bundle and falls back to the platform font if a
  // weight is somehow missing, rather than making a network request.
  GoogleFonts.config.allowRuntimeFetching = false;
  switch (variant) {
    case AppThemeVariant.hearth:
      return _buildHearthTheme(brightness);
    case AppThemeVariant.classic:
      return _buildClassicTheme(brightness, classicSeed);
  }
}

/* ============================ HEARTH TOKENS ============================ */

/// The "Hearth" colour tokens, transcribed from the design handoff. One
/// instance per brightness.
class _HearthTokens {
  final Color bg, surface, surfaceAlt, surface2;
  final Color onSurface, muted, faint;
  final Color outline, faintOutline;
  final Color primary, onPrimary, primaryCont, onPrimaryCont;
  final Color accent;
  final Color success, successCont, onSuccess;
  final Color danger, dangerCont, onDanger;
  final Color appbar, scrim, shadow;

  const _HearthTokens({
    required this.bg,
    required this.surface,
    required this.surfaceAlt,
    required this.surface2,
    required this.onSurface,
    required this.muted,
    required this.faint,
    required this.outline,
    required this.faintOutline,
    required this.primary,
    required this.onPrimary,
    required this.primaryCont,
    required this.onPrimaryCont,
    required this.accent,
    required this.success,
    required this.successCont,
    required this.onSuccess,
    required this.danger,
    required this.dangerCont,
    required this.onDanger,
    required this.appbar,
    required this.scrim,
    required this.shadow,
  });

  static const light = _HearthTokens(
    bg: Color(0xFFFBF5EE),
    surface: Color(0xFFFFFDFB),
    surfaceAlt: Color(0xFFF4EADF),
    surface2: Color(0xFFF8EFE5),
    onSurface: Color(0xFF2A201A),
    muted: Color(0xFF6F6155),
    faint: Color(0xFF9A8B7D),
    outline: Color(0xFFE7D8C9),
    faintOutline: Color(0xFFF0E5D9),
    primary: Color(0xFFBF5C36),
    onPrimary: Color(0xFFFFFFFF),
    primaryCont: Color(0xFFF7DFD1),
    onPrimaryCont: Color(0xFF56230F),
    accent: Color(0xFFC98A2E),
    success: Color(0xFF2E7D58),
    successCont: Color(0xFFD6ECE0),
    onSuccess: Color(0xFF0E3B27),
    danger: Color(0xFFB23A2C),
    dangerCont: Color(0xFFF6DBD6),
    onDanger: Color(0xFF5A170F),
    appbar: Color(0xFFFBF5EE),
    scrim: Color.fromRGBO(40, 24, 14, 0.42),
    shadow: Color.fromRGBO(120, 70, 40, 0.16),
  );

  static const dark = _HearthTokens(
    bg: Color(0xFF191310),
    surface: Color(0xFF221A15),
    surfaceAlt: Color(0xFF2C2219),
    surface2: Color(0xFF2A211B),
    onSurface: Color(0xFFF3E9E0),
    muted: Color(0xFFB7A899),
    // Nudged lighter than the original tokens so dividers, card borders, and
    // hint text actually separate from the dark surfaces (the originals —
    // faint 8A7C6F, outline 43342A, faintOutline 2E241C — read as nearly flat).
    faint: Color(0xFF998A7B),
    outline: Color(0xFF4E3D30),
    faintOutline: Color(0xFF382C22),
    primary: Color(0xFFE89070),
    onPrimary: Color(0xFF46190A),
    primaryCont: Color(0xFF6A3320),
    onPrimaryCont: Color(0xFFFBDFD2),
    accent: Color(0xFFE6B65F),
    success: Color(0xFF86CBA6),
    successCont: Color(0xFF234234),
    onSuccess: Color(0xFFD8F0E3),
    danger: Color(0xFFEC9385),
    dangerCont: Color(0xFF4A211B),
    onDanger: Color(0xFFF7DBD5),
    appbar: Color(0xFF221A15),
    scrim: Color.fromRGBO(0, 0, 0, 0.6),
    shadow: Color.fromRGBO(0, 0, 0, 0.5),
  );
}

// Corner radii from the Hearth tokens. Public so the bespoke Hearth widgets
// (see hearth.dart) can reuse the exact same values instead of re-hardcoding
// them, keeping the radii in one place.
const double kRadiusCard = 20;
const double kRadiusBox = 16; // Stat tiles and the revision ring box.
const double kRadiusButton = 14;
const double kRadiusChip = 12;
const double kRadiusPill = 999;

/* ========================= LARGE-SCREEN SIZING ========================= */

// Phone layouts render at the same logical sizes on a 13" tablet, which
// makes the whole UI read as tiny: hairline search field, edge-to-edge
// list rows with small text, oceans of empty space. The two knobs below
// fix that WITHOUT touching the phone experience: text (and the
// text-driven component metrics) scales up, and top-level page content
// is centred at a readable measure instead of stretching edge to edge.

/// Shortest-side breakpoint above which a display is treated as a
/// tablet / large screen (Material's conventional 600dp).
const double kLargeScreenBreakpoint = 600;

/// How much text is scaled up on large screens, composed with whatever
/// accessibility scaling the user has set at the OS level.
const double kLargeScreenTextScale = 1.25;

/// Maximum width top-level page content stretches to on large screens.
const double kLargeScreenContentMaxWidth = 760;

/// True when the display is tablet-sized (independent of orientation).
bool isLargeScreen(BuildContext context) =>
    MediaQuery.sizeOf(context).shortestSide >= kLargeScreenBreakpoint;

/// MaterialApp.builder hook: applies [kLargeScreenTextScale] on large
/// screens, on top of the user's accessibility text scaling. Returns
/// phones unchanged.
Widget largeScreenTextScaleBuilder(BuildContext context, Widget? child) {
  if (child == null) return const SizedBox.shrink();
  final mq = MediaQuery.of(context);
  if (mq.size.shortestSide < kLargeScreenBreakpoint) return child;
  final accessibilityFactor = mq.textScaler.scale(1.0);
  return MediaQuery(
    data: mq.copyWith(
        textScaler:
            TextScaler.linear(accessibilityFactor * kLargeScreenTextScale)),
    child: child,
  );
}

/// Centre [child] at a readable measure on large screens; a no-op on
/// phones. Wrap page bodies (not whole scaffolds) so app bars and nav
/// bars keep their natural full-width treatment.
Widget constrainContentWidth(BuildContext context, Widget child,
    {double maxWidth = kLargeScreenContentMaxWidth}) {
  if (!isLargeScreen(context)) return child;
  return Center(
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: child,
    ),
  );
}

/* ============================ HEARTH THEME ============================ */

ColorScheme _hearthScheme(Brightness b, _HearthTokens t) {
  // Start from a seeded scheme so every (deprecated and new) slot has a sane
  // value, then override the ones the design specifies.
  final base = ColorScheme.fromSeed(seedColor: t.primary, brightness: b);
  final isDark = b == Brightness.dark;
  return base.copyWith(
    brightness: b,
    primary: t.primary,
    onPrimary: t.onPrimary,
    primaryContainer: t.primaryCont,
    onPrimaryContainer: t.onPrimaryCont,
    secondary: t.accent,
    onSecondary: isDark ? const Color(0xFF3A2A12) : Colors.white,
    secondaryContainer: t.surface2,
    onSecondaryContainer: t.onSurface,
    tertiary: t.success,
    onTertiary: isDark ? const Color(0xFF0E3B27) : Colors.white,
    tertiaryContainer: t.successCont,
    onTertiaryContainer: t.onSuccess,
    error: t.danger,
    onError: isDark ? const Color(0xFF46190A) : Colors.white,
    errorContainer: t.dangerCont,
    onErrorContainer: t.onDanger,
    surface: t.surface,
    onSurface: t.onSurface,
    onSurfaceVariant: t.muted,
    surfaceContainerLowest: t.surface,
    surfaceContainerLow: t.surface2,
    surfaceContainer: t.surfaceAlt,
    surfaceContainerHigh: t.surfaceAlt,
    surfaceContainerHighest: t.surfaceAlt,
    outline: t.outline,
    outlineVariant: t.faintOutline,
    scrim: t.scrim,
    shadow: t.shadow,
    inverseSurface: t.onSurface,
    onInverseSurface: t.bg,
  );
}

TextTheme _hearthTextTheme(Brightness b) {
  final baseTextTheme = b == Brightness.dark
      ? Typography.material2021().white
      : Typography.material2021().black;
  // Body / labels in Hanken Grotesk.
  final body = GoogleFonts.hankenGroteskTextTheme(baseTextTheme);
  // Display / headline / large title in Bricolage Grotesque.
  final displayFamily = GoogleFonts.bricolageGrotesque().fontFamily;
  return body.copyWith(
    displayLarge: body.displayLarge?.copyWith(
        fontFamily: displayFamily,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5),
    displayMedium: body.displayMedium?.copyWith(
        fontFamily: displayFamily,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5),
    displaySmall: body.displaySmall?.copyWith(
        fontFamily: displayFamily,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3),
    headlineLarge: body.headlineLarge?.copyWith(
        fontFamily: displayFamily,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3),
    headlineMedium: body.headlineMedium
        ?.copyWith(fontFamily: displayFamily, fontWeight: FontWeight.w700),
    headlineSmall: body.headlineSmall
        ?.copyWith(fontFamily: displayFamily, fontWeight: FontWeight.w700),
    titleLarge: body.titleLarge
        ?.copyWith(fontFamily: displayFamily, fontWeight: FontWeight.w700),
  );
}

ThemeData _buildHearthTheme(Brightness brightness) {
  final t =
      brightness == Brightness.dark ? _HearthTokens.dark : _HearthTokens.light;
  final cs = _hearthScheme(brightness, t);
  final textTheme = _hearthTextTheme(brightness);
  final bodyFamily = GoogleFonts.hankenGrotesk().fontFamily;

  OutlineInputBorder inputBorder(Color color, double width) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(kRadiusButton),
        borderSide: BorderSide(color: color, width: width),
      );

  ButtonStyle filledLikeStyle(Color bg, Color fg) => ButtonStyle(
        backgroundColor: WidgetStatePropertyAll(bg),
        foregroundColor: WidgetStatePropertyAll(fg),
        elevation: const WidgetStatePropertyAll(0.0),
        minimumSize: const WidgetStatePropertyAll(Size(0, 48)),
        padding:
            const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 18)),
        textStyle: WidgetStatePropertyAll(TextStyle(
            fontFamily: bodyFamily, fontWeight: FontWeight.w700, fontSize: 15)),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(kRadiusButton))),
      );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: cs,
    scaffoldBackgroundColor: t.bg,
    canvasColor: t.bg,
    fontFamily: bodyFamily,
    textTheme: textTheme,
    primaryColor: t.primary,
    dividerColor: t.faintOutline,
    splashColor: t.primaryCont,
    highlightColor: Colors.transparent,
    visualDensity: VisualDensity.adaptivePlatformDensity,
    appBarTheme: AppBarTheme(
      backgroundColor: t.appbar,
      foregroundColor: t.onSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      iconTheme: IconThemeData(color: t.muted),
      actionsIconTheme: IconThemeData(color: t.muted),
      titleTextStyle: textTheme.titleLarge?.copyWith(fontSize: 18),
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: t.appbar,
      selectedItemColor: t.primary,
      unselectedItemColor: t.muted,
      type: BottomNavigationBarType.fixed,
      elevation: 0,
      showUnselectedLabels: true,
      selectedLabelStyle:
          const TextStyle(fontWeight: FontWeight.w800, fontSize: 11),
      unselectedLabelStyle:
          const TextStyle(fontWeight: FontWeight.w600, fontSize: 11),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: t.appbar,
      indicatorColor: t.primaryCont,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? t.onPrimaryCont
              : t.muted)),
      labelTextStyle: WidgetStatePropertyAll(TextStyle(
          fontFamily: bodyFamily,
          fontWeight: FontWeight.w700,
          fontSize: 12,
          color: t.onSurface)),
    ),
    cardTheme: CardThemeData(
      color: t.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kRadiusCard),
        side: BorderSide(color: t.outline),
      ),
    ),
    dividerTheme: DividerThemeData(color: t.faintOutline, thickness: 1),
    iconTheme: IconThemeData(color: t.muted),
    primaryIconTheme: IconThemeData(color: t.onSurface),
    filledButtonTheme:
        FilledButtonThemeData(style: filledLikeStyle(t.primary, t.onPrimary)),
    elevatedButtonTheme:
        ElevatedButtonThemeData(style: filledLikeStyle(t.primary, t.onPrimary)),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: t.primary,
        textStyle: TextStyle(
            fontFamily: bodyFamily, fontWeight: FontWeight.w700, fontSize: 15),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(kRadiusButton)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: t.primary,
        minimumSize: const Size(0, 48),
        side: BorderSide(color: t.outline, width: 1.5),
        textStyle: TextStyle(
            fontFamily: bodyFamily, fontWeight: FontWeight.w700, fontSize: 15),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(kRadiusButton)),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: t.primary,
      foregroundColor: t.onPrimary,
      elevation: 2,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kRadiusButton)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: t.surfaceAlt,
      hintStyle: TextStyle(color: t.faint),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: inputBorder(Colors.transparent, 0),
      enabledBorder: inputBorder(t.outline, 1),
      focusedBorder: inputBorder(t.primary, 2),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: const WidgetStatePropertyAll(Colors.white),
      trackColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected) ? t.primary : t.outline),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected)
              ? t.primary
              : Colors.transparent),
      checkColor: WidgetStatePropertyAll(t.onPrimary),
      side: BorderSide(color: t.outline, width: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected) ? t.primary : t.faint),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: t.surfaceAlt,
      selectedColor: t.primaryCont,
      secondarySelectedColor: t.primaryCont,
      labelStyle: TextStyle(
          color: t.onSurface,
          fontWeight: FontWeight.w600,
          fontFamily: bodyFamily),
      side: BorderSide(color: t.outline),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kRadiusChip)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: t.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titleTextStyle: textTheme.titleLarge?.copyWith(fontSize: 21),
      contentTextStyle: textTheme.bodyMedium?.copyWith(color: t.muted),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: t.surface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: t.onSurface,
      contentTextStyle: TextStyle(color: t.bg, fontWeight: FontWeight.w600),
      actionTextColor: t.primary,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kRadiusChip)),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: t.primary,
      unselectedLabelColor: t.muted,
      indicatorColor: t.primary,
      dividerColor: Colors.transparent,
      labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
      unselectedLabelStyle:
          const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: t.muted,
      textColor: t.onSurface,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: t.primary),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: t.primary,
      selectionColor: t.primaryCont,
      selectionHandleColor: t.primary,
    ),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: CupertinoPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    }),
  );
}

/* ============================ CLASSIC THEME ============================ */

// The original stock-Material look, preserved verbatim from the app's previous
// inline theme so users can switch back to the familiar design. Seeded from
// the app-specific [seed] colour (e.g. Colors.blue for Auslan).
ThemeData _buildClassicTheme(Brightness brightness, Color seed) {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: seed,
    brightness: brightness,
  );
  final isDark = brightness == Brightness.dark;
  return ThemeData(
    colorScheme: colorScheme,
    appBarTheme: AppBarTheme(
      backgroundColor: isDark ? const Color(0xFF1F1F1F) : seed,
      foregroundColor: Colors.white,
      elevation: 0,
    ),
    scaffoldBackgroundColor: isDark ? const Color(0xFF121212) : Colors.white,
    cardTheme: CardThemeData(
      color: isDark ? const Color(0xFF2C2C2C) : Colors.white,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
    ),
    typography: Typography.material2021(colorScheme: colorScheme),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        foregroundColor:
            WidgetStatePropertyAll(isDark ? Colors.white : Colors.black),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith<Color>(
          (Set<WidgetState> states) => states.contains(WidgetState.disabled)
              ? (isDark ? Colors.white24 : Colors.black38)
              : (isDark ? Colors.white : Colors.black),
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      focusedBorder: UnderlineInputBorder(
        borderSide: BorderSide(color: seed),
      ),
      enabledBorder: UnderlineInputBorder(
        borderSide: BorderSide(color: seed),
      ),
      hintStyle: TextStyle(color: isDark ? Colors.white60 : Colors.black54),
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: Colors.white,
      unselectedLabelColor: Colors.white,
      labelStyle: TextStyle(
        fontSize: 16.0,
        fontWeight: FontWeight.bold,
      ),
      unselectedLabelStyle: TextStyle(
        fontSize: 16.0,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: seed,
      contentTextStyle: TextStyle(color: isDark ? Colors.black : Colors.white),
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      selectedItemColor: seed,
      unselectedItemColor: Colors.grey,
      backgroundColor: isDark ? const Color(0xFF121212) : Colors.white,
    ),
    visualDensity: VisualDensity.adaptivePlatformDensity,
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: CupertinoPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    }),
  );
}
