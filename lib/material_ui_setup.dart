// What every MaterialApp in the apps needs now that Material lives in
// package:material_ui rather than in the Flutter SDK (Flutter 3.50).
//
// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart' as legacy show Theme, ThemeData;
import 'package:material_ui/material_ui.dart';

import 'l10n/app_localizations.dart';

/// The localizations delegates for every MaterialApp: the library's own
/// strings, then material_ui's Material, Cupertino and Widgets strings.
///
/// Not DictLibLocalizations.localizationsDelegates: flutter gen-l10n still
/// writes that list with flutter_localizations' delegates, whose
/// MaterialLocalizations is a different type from the one material_ui's
/// widgets look up, so Sinhala and Tamil would fall back to English in
/// dialogs, tooltips and the back button.
const List<LocalizationsDelegate<dynamic>> dictLibLocalizationsDelegates = [
  DictLibLocalizations.delegate,
  ...GlobalMaterialLocalizations.delegates,
];

/// For MaterialApp.builder: gives widgets from packages that still use
/// package:flutter/material.dart (the markdown in advisories and news, the
/// video player, the carousel) the app's colours and text styles and their
/// own localizations. Without it they would see Flutter's default light
/// theme, so markdown would draw dark text on the dark theme.
///
/// Remove once flutter_markdown_plus, media_kit_video, carousel_slider,
/// qr_flutter and the sign-in packages have moved to material_ui.
Widget legacyMaterialBridge(Widget child) =>
    MaterialUiCompatibilityBridge(child: child);

/// The theme as package:flutter/material.dart sees it, for the APIs of
/// packages that have not moved to material_ui yet (such as
/// MarkdownStyleSheet.fromTheme). Needs [legacyMaterialBridge] above it.
legacy.ThemeData legacyThemeOf(BuildContext context) =>
    legacy.Theme.of(context);
