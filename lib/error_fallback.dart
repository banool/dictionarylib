import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:url_launcher/url_launcher.dart';

import 'advisories.dart';
import 'common.dart';
import 'entry_loader.dart';
import 'entry_types.dart';
import 'globals.dart';
import 'l10n/app_localizations.dart';
import 'page_settings.dart';
import 'startup_loading.dart';

/// Shown when app startup fails (see runDictionaryApp). Replaces the whole
/// app: it is its own MaterialApp, with the same interim theme/locale
/// treatment as StartupLoadingApp but no router — so it must not touch any
/// `late` global that a failed setup may have left unset (every such read here
/// is defensive; this screen can render even before sharedPreferences exists).
///
/// A [DictionaryDataUnavailableError] (a cold start couldn't download the
/// dictionary — by far the most common way to land here) gets plain-language
/// copy about the download with likely causes; anything else gets the generic
/// crash copy. Both variants offer Retry (re-runs the whole setup), the
/// system-proxy toggle (a user behind a school/corporate proxy needs it
/// precisely when startup fails; Retry applies it), Background logs, and the
/// full technical details behind a disclosure.
class ErrorFallback extends StatefulWidget {
  final Object error;
  final StackTrace stackTrace;
  final String appName;

  /// The app's help/FAQ page. Null hides the link.
  final String? faqUrl;

  /// Called when the user taps Retry. Null hides the button (defensive
  /// default; runDictionaryApp always passes one).
  final VoidCallback? onRetry;

  const ErrorFallback({
    super.key,
    required this.error,
    required this.stackTrace,
    required this.appName,
    this.faqUrl,
    this.onRetry,
  });

  @override
  State<ErrorFallback> createState() => _ErrorFallbackState();
}

class _ErrorFallbackState extends State<ErrorFallback> {
  // Once tapped, the button shows a spinner until setup either succeeds (this
  // whole widget is replaced) or fails again (a fresh ErrorFallback replaces
  // this one, with the button re-enabled).
  bool retryInFlight = false;

  bool get isDataUnavailable => widget.error is DictionaryDataUnavailableError;

  /// Whether prefs are usable (startup can fail before setupHttpPrerequisites
  /// completes, in which case the proxy toggle is meaningless and hidden).
  bool get prefsAvailable {
    try {
      sharedPreferences.getKeys();
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Everything a bug report needs, as one copyable string.
  String buildDiagnostics() {
    final buffer = StringBuffer();
    if (isDataUnavailable) {
      final e = widget.error as DictionaryDataUnavailableError;
      buffer.writeln("Error: ${e.cause}");
      buffer.writeln();
      buffer.writeln("Stack trace:\n${e.causeStackTrace}");
    } else {
      buffer.writeln("Error: ${widget.error}");
      buffer.writeln();
      buffer.writeln("Stack trace:\n${widget.stackTrace}");
    }
    buffer.writeln();
    buffer.writeln("Background logs:");
    buffer.writeln(backgroundLogs.items.join("\n"));
    buffer.writeln();
    try {
      buffer.writeln("Shared preferences:");
      for (String key in sharedPreferences.getKeys()) {
        buffer.writeln("$key: ${sharedPreferences.get(key)}");
      }
    } catch (e) {
      buffer.writeln("Failed to get shared prefs: $e");
    }
    buffer.writeln();
    buffer.writeln("Package and device info:");
    if (packageInfo != null) {
      buffer.writeln("App version: ${packageInfo!.version}");
      buffer.writeln("Build number: ${packageInfo!.buildNumber}");
    }
    if (iosDeviceInfo != null) {
      buffer.writeln("Device: ${iosDeviceInfo!.name}");
      buffer.writeln("Model: ${iosDeviceInfo!.model}");
      buffer.writeln("System: iOS ${iosDeviceInfo!.systemVersion}");
    }
    if (androidDeviceInfo != null) {
      buffer.writeln("Device: ${androidDeviceInfo!.device}");
      buffer.writeln("Model: ${androidDeviceInfo!.model}");
      buffer.writeln(
        "System: Android ${androidDeviceInfo!.version.release} "
        "(SDK ${androidDeviceInfo!.version.sdkInt})",
      );
    }
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    // Remove the splash screen (native only — no web splash configured).
    if (!kIsWeb) {
      FlutterNativeSplash.remove();
    }

    return MaterialApp(
      title: widget.appName,
      debugShowCheckedModeBanner: false,
      localizationsDelegates: DictLibLocalizations.localizationsDelegates,
      supportedLocales: LANGUAGE_CODE_TO_LOCALE.values,
      locale: startupScreenLocaleOverride(),
      themeMode: startupScreenThemeMode(),
      theme: startupScreenTheme(Brightness.light),
      darkTheme: startupScreenTheme(Brightness.dark),
      home: Builder(builder: (context) => _buildPage(context)),
    );
  }

  Widget _buildPage(BuildContext context) {
    final l = DictLibLocalizations.of(context)!;
    final theme = Theme.of(context);

    List<Widget> children = [
      Text(
        isDataUnavailable ? l.startupFailedTitle : l.errorFallbackGenericTitle,
        textAlign: TextAlign.center,
        style: theme.textTheme.titleLarge,
      ),
      const SizedBox(height: 16),
      if (isDataUnavailable) ...[
        Text(l.startupFailedBody),
        const SizedBox(height: 12),
        Text(l.startupFailedLikelyCauses),
        const SizedBox(height: 8),
        for (final cause in [
          l.startupFailedCauseInternet,
          l.startupFailedCauseCaptivePortal,
          l.startupFailedCauseNetworkBlocks,
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("•  "),
                Expanded(child: Text(cause)),
              ],
            ),
          ),
      ] else
        Text(l.errorFallbackGenericBody("daniel@dport.me")),
      const SizedBox(height: 24),
      if (widget.onRetry != null)
        Semantics(
          identifier: 'error-fallback-retry',
          child: FilledButton.icon(
            onPressed: retryInFlight
                ? null
                : () {
                    setState(() {
                      retryInFlight = true;
                    });
                    widget.onRetry!();
                  },
            icon: retryInFlight
                ? buttonSpinner(context)
                : const Icon(Icons.refresh),
            label: Text(l.errorFallbackRetryButton),
          ),
        ),
      if (widget.faqUrl != null) ...[
        const SizedBox(height: 8),
        Semantics(
          identifier: 'error-fallback-faq-link',
          child: TextButton.icon(
            onPressed: () async {
              await launchUrl(
                Uri.parse(widget.faqUrl!),
                mode: LaunchMode.externalApplication,
              );
            },
            icon: const Icon(Icons.open_in_new, size: 18),
            label: Text(l.errorFallbackFaqLink),
          ),
        ),
      ],
      const SizedBox(height: 24),
      if (prefsAvailable && !kIsWeb) ...[
        Text(l.errorFallbackProxyHint, style: theme.textTheme.bodySmall),
        Semantics(
          identifier: 'error-fallback-proxy-switch',
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l.settingsUseSystemHttpProxy),
            value:
                sharedPreferences.getBool(KEY_USE_SYSTEM_HTTP_PROXY) ?? false,
            onChanged: (newValue) {
              sharedPreferences.setBool(KEY_USE_SYSTEM_HTTP_PROXY, newValue);
              // Applied by the Retry path re-running setupHttpPrerequisites;
              // no restart needed, so no restart snack here.
              setState(() {});
            },
          ),
        ),
        const SizedBox(height: 8),
      ],
      Semantics(
        identifier: 'error-fallback-background-logs',
        child: OutlinedButton.icon(
          onPressed: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => BackgroundLogsPage()),
            );
          },
          icon: const Icon(Icons.article_outlined, size: 18),
          label: Text(l.settingsBackgroundLogs),
        ),
      ),
      const SizedBox(height: 24),
      if (advisoriesResponse != null &&
          advisoriesResponse!.advisories.isNotEmpty) ...[
        Text(
          l.errorFallbackAdvisoriesTitle,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        getAdvisoriesInner(),
        const SizedBox(height: 16),
      ],
      Semantics(
        identifier: 'error-fallback-details',
        child: ExpansionTile(
          title: Text(l.errorFallbackDetailsTitle),
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 12),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(
                    ClipboardData(text: buildDiagnostics()),
                  );
                  if (context.mounted) {
                    showSnack(context, l.errorFallbackDetailsCopiedSnack);
                  }
                },
                icon: const Icon(Icons.copy, size: 18),
                label: Text(l.errorFallbackCopyDetailsButton),
              ),
            ),
            SelectableText(
              buildDiagnostics(),
              style: theme.textTheme.bodySmall!.copyWith(
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    ];

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
    );
  }
}
