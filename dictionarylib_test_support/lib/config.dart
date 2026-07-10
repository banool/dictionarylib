import 'package:dictionarylib/entry_loader.dart';
import 'package:dictionarylib/common.dart' show NavigateToEntryPageFn;
import 'package:flutter/material.dart';

/// Everything app-specific the single-device suites need. Each app defines one
/// of these in `integration_test/test_config.dart` and hands it to the
/// `run*Suite` entrypoints from its thin per-file stubs.
class DictAppTestConfig {
  const DictAppTestConfig({
    required this.setup,
    required this.buildApp,
    required this.navigateToEntryPage,
    this.seedFlashcardSettings,
    this.clearFlashcardSettings,
  });

  /// The app's `setup()` from lib/main.dart (loads the dictionary, prepares
  /// globals). Suites call it before pumping the app.
  final Future<void> Function() setup;

  /// Builds the app's root widget, e.g. `(l) => RootApp(startingLocale: l)`.
  final Widget Function(Locale startingLocale) buildApp;

  /// The app's entry-page navigation (its curried makeNavigateToEntryPage).
  final NavigateToEntryPageFn navigateToEntryPage;

  /// Seed any app-specific flashcard-pool settings so no seeded card is
  /// filtered out (Auslan: allow every region + unknown-region signs). Null →
  /// nothing to seed (SLSL doesn't filter the pool by region).
  final Future<void> Function()? seedFlashcardSettings;

  /// Teardown matching [seedFlashcardSettings]. Null → nothing to clear.
  final Future<void> Function()? clearFlashcardSettings;
}

/// App-specific knobs for the screenshot suite.
class ScreenshotSuiteConfig {
  const ScreenshotSuiteConfig({
    required this.localeDirName,
    required this.animalsSeedWords,
    required this.searchQuery,
    required this.heroEntryKey,
  });

  /// Directory segment in the screenshot path (and the completion-marker
  /// prefix), e.g. 'en-AU' or 'en'.
  final String localeDirName;

  /// English entry keys seeded into the "Animals" list so the captured list
  /// screens are populated. Missing words are skipped.
  final List<String> animalsSeedWords;

  /// Query typed into search for the results capture.
  final String searchQuery;

  /// Entry key opened for the word-page captures.
  final String heroEntryKey;
}

/// App-specific configuration for the multi-device sharing suite (md_common +
/// the phase A–D suites). Each app defines one in
/// `integration_test/multi_device/md_config.dart`.
class MdSuiteConfig {
  const MdSuiteConfig({
    required this.appId,
    required this.appName,
    required this.advisoriesUrl,
    required this.knobUrlBase,
    required this.mediaBaseUrls,
    required this.buildEntryLoader,
    required this.shareLinkBaseUrl,
    required this.shareLinkHost,
    required this.urlScheme,
    required this.appleBundleId,
    required this.buildApp,
  });

  /// Must match the worker dev env's APP_ID (the backend repo's
  /// workers/wrangler.toml).
  final String appId;

  final String appName;

  /// The app's advisories.md raw URL (passed to setupPhaseTwo).
  final Uri advisoriesUrl;

  /// The app's knob base URL (passed to setupPhaseThree).
  final String knobUrlBase;

  /// Media base URLs, set before phase three so the list migration can
  /// resolve saved-video paths.
  final List<String> mediaBaseUrls;

  /// Builds the app's EntryLoader. SLSL pins the loader at the direct bucket
  /// dump URL for determinism rather than going through the useCdnUrl knob.
  final EntryLoader Function() buildEntryLoader;

  /// Production link shape so minted invite links round-trip through the same
  /// parsing the share/subscribe dialogs apply to real links.
  final String shareLinkBaseUrl;
  final String shareLinkHost;
  final String urlScheme;
  final String appleBundleId;

  /// Builds the app's root widget, e.g. `(l) => RootApp(startingLocale: l)`.
  final Widget Function(Locale startingLocale) buildApp;
}
