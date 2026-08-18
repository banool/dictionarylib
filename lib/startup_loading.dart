import 'package:flutter/material.dart';

import 'app_bootstrap.dart';
import 'common.dart';
import 'data_fetch.dart';
import 'entry_loader.dart';
import 'entry_types.dart';
import 'globals.dart';
import 'l10n/app_localizations.dart';
import 'theme.dart';

/// The theme/locale treatment shared by the interim startup screens (the
/// loading screen and ErrorFallback), which render outside the real app and
/// its router. Always the Hearth variant: the classic seed colour lives in
/// DictRootAppConfig, which these screens can't reach, and the native splash
/// colours these screens take over from are Hearth's anyway. Classic-variant
/// users see Hearth on these two rare screens, which is fine. Every pref read
/// is defensive because ErrorFallback can render before sharedPreferences is
/// initialized.
ThemeData startupScreenTheme(Brightness brightness) => buildAppTheme(
  variant: AppThemeVariant.hearth,
  brightness: brightness,
  // Unused by the Hearth variant; see above.
  classicSeed: Colors.blue,
);

/// The user's persisted light/dark preference, defaulting to following the
/// system, tolerating uninitialized prefs.
ThemeMode startupScreenThemeMode() {
  try {
    return ThemeMode.values[sharedPreferences.getInt(KEY_THEME_MODE) ??
        DEFAULT_THEME_MODE];
  } catch (e) {
    return ThemeMode.system;
  }
}

/// The user's persisted locale override (SLSL's language picker), or null to
/// let Flutter resolve from the system locale against supportedLocales. This
/// is how the loading screen comes up in Sinhala/Tamil before the app's
/// resolveStartingLocale has ever run.
Locale? startupScreenLocaleOverride() {
  try {
    final code = sharedPreferences.getString(KEY_LOCALE_OVERRIDE);
    return code == null ? null : LANGUAGE_CODE_TO_LOCALE[code];
  } catch (e) {
    return null;
  }
}

/// The interim app shown on a native cold start while the dictionary data
/// downloads (see runDictionaryApp — never shown on web or on warm starts).
/// A minimal MaterialApp with no router; the real app replaces it via a second
/// runApp when setup completes.
class StartupLoadingApp extends StatelessWidget {
  final DictAppBootstrapConfig config;

  /// The loader driving this startup attempt; we render its
  /// [EntryLoader.downloadStatusNotifier].
  final EntryLoader loader;

  const StartupLoadingApp({
    super.key,
    required this.config,
    required this.loader,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      localizationsDelegates: DictLibLocalizations.localizationsDelegates,
      supportedLocales: LANGUAGE_CODE_TO_LOCALE.values,
      locale: startupScreenLocaleOverride(),
      themeMode: startupScreenThemeMode(),
      theme: startupScreenTheme(Brightness.light),
      darkTheme: startupScreenTheme(Brightness.dark),
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: ValueListenableBuilder<DictionaryDownloadStatus?>(
                valueListenable: loader.downloadStatusNotifier,
                builder: (context, status, _) =>
                    _StartupLoadingBody(config: config, status: status),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StartupLoadingBody extends StatelessWidget {
  final DictAppBootstrapConfig config;
  final DictionaryDownloadStatus? status;

  const _StartupLoadingBody({required this.config, required this.status});

  String _mb(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final l = DictLibLocalizations.of(context)!;
    final theme = Theme.of(context);
    final status = this.status;

    // What the bar and the status line under it should show for each stage.
    // Before the first report (or in the applying stage) the bar is
    // indeterminate.
    double? barValue;
    String statusLine = l.startupApplyingData;
    String? attemptLine;
    if (status != null) {
      switch (status.stage) {
        case DictionaryDownloadStage.checking:
          statusLine = l.startupTryingSource(status.host ?? "");
        case DictionaryDownloadStage.downloading:
          barValue = status.fraction;
          final total = status.totalBytes;
          statusLine = total == null
              ? l.startupProgressNoTotal(_mb(status.receivedBytes))
              : l.startupProgressWithTotal(
                  _mb(status.receivedBytes),
                  _mb(total),
                );
        case DictionaryDownloadStage.applying:
          statusLine = l.startupApplyingData;
      }
      // Only meaningful when there are multiple sources to fall back
      // through (auslan's primary + mirror); SLSL has one source.
      if (status.urlCount > 1 &&
          status.stage != DictionaryDownloadStage.applying) {
        attemptLine = l.startupAttemptCount(
          status.urlIndex + 1,
          status.urlCount,
        );
      }
    }

    final logo = config.buildStartupLogo?.call(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (logo != null) ...[logo, const SizedBox(height: 32)],
        Text(
          l.startupDownloadingTitle,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: 24),
        Semantics(
          identifier: 'startup-loading-progress',
          child: LinearProgressIndicator(value: barValue),
        ),
        const SizedBox(height: 12),
        Semantics(
          identifier: 'startup-loading-status',
          child: Column(
            children: [
              Text(
                statusLine,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              if (attemptLine != null) ...[
                const SizedBox(height: 4),
                Text(
                  attemptLine,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 32),
        Text(
          l.startupDownloadingExplanation,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}
