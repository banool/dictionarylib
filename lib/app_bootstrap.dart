import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';

import 'common.dart';
import 'entry_loader.dart';
import 'entry_types.dart';
import 'error_fallback.dart';
import 'flashcards_logic.dart';
import 'globals.dart';
import 'page_force_upgrade.dart';
import 'sharing/sharing_config.dart';

/// Everything app-specific about app startup. The orchestration itself —
/// binding/splash, MediaKit, the phased setup order, the concurrent
/// advisories + yanked-version fetch, the review-history migration,
/// setupSharing after phase three, and the single runApp with the
/// force-upgrade / error fallbacks — is identical across the dictionary apps
/// and lives in [setupDictionaryApp] / [runDictionaryApp].
class DictAppBootstrapConfig {
  const DictAppBootstrapConfig({
    required this.advisoriesUrl,
    required this.yankedVersionsUrl,
    required this.knobUrlBase,
    this.extraStartupTasks = const [],
    required this.setupMediaAndEntryLoader,
    required this.sharingConfig,
  });

  /// The app's advisories file (GitHub raw; passed to setupPhaseTwo).
  final Uri advisoriesUrl;

  /// The app's yanked_versions file (GitHub raw). A listed version makes
  /// startup throw YankedVersionError, which runDictionaryApp turns into the
  /// ForceUpgradePage.
  final String yankedVersionsUrl;

  /// The app's knob base URL (passed to setupPhaseThree).
  final String knobUrlBase;

  /// Extra startup work run concurrently with the phase-two/yanked-version
  /// network calls (e.g. SLSL's use_cdn_url knob read). Must not throw for
  /// anything short of "the app cannot run".
  final List<Future<void> Function()> extraStartupTasks;

  /// Set [mediaBaseUrls] and build the app's EntryLoader. Runs after
  /// [extraStartupTasks] complete (so it can read knobs they fetched) and
  /// before setupPhaseThree (so the list migration can resolve / strip
  /// saved-video paths against the bases).
  final Future<EntryLoader> Function() setupMediaAndEntryLoader;

  final SharingConfig sharingConfig;
}

/// The shared body of the apps' `setup()`: phases one → three in order, with
/// the review-history migration and setupSharing after phase three. Be
/// careful reordering anything here — later steps implicitly depend on the
/// side effects of earlier ones.
Future<void> setupDictionaryApp(DictAppBootstrapConfig config,
    {Set<Entry>? entriesGlobalReplacement}) async {
  var widgetsBinding = WidgetsFlutterBinding.ensureInitialized();

  // Initialize media_kit for video playback (native only; web plays via the
  // HTML5 video_player path — see VideoSurface).
  if (!kIsWeb) {
    MediaKit.ensureInitialized();
  }

  // Preserve the splash screen while the app initializes. Native only —
  // there's no web splash configured, so calling this on web throws.
  if (!kIsWeb) {
    FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  }

  // Loads the package info, which the yanked-version checker needs.
  await setupPhaseOne();

  // It is okay to check for yanked versions and do phase two setup at the same
  // time because phase two setup never throws. We want to do them together
  // because they both make network calls, so we can do them concurrently.
  await Future.wait<void>([
    (() async {
      await setupPhaseTwo(config.advisoriesUrl);
    })(),
    (() async {
      // If the user needs to upgrade, this will throw a specific error that
      // runDictionaryApp catches to show the ForceUpgradePage.
      await GitHubYankedVersionChecker(config.yankedVersionsUrl)
          .throwIfShouldUpgrade();
    })(),
    for (final task in config.extraStartupTasks) task(),
  ]);

  // Configure how saved-video paths resolve to playable URLs and build the
  // dictionary loader (app-specific: bundled data vs runtime dump, knob-driven
  // CDN ordering, debug backend overrides).
  final entryLoader = await config.setupMediaAndEntryLoader();

  await setupPhaseThree(
      paramEntryLoader: entryLoader,
      knobUrlBase: config.knobUrlBase,
      entriesGlobalReplacement: entriesGlobalReplacement);

  // One-shot migration of stored DolphinSR review history from the
  // v1 master id shape ("entryKey-firstVideoFilename") to the v2
  // shape (per-saved-video). No-op after the first successful run.
  // Must run after setupPhaseThree because it walks the dictionary
  // to resolve legacy master ids.
  await migrateLegacyReviewsIfNeeded();

  // Opt in to the shared-lists feature. Runs after phase three because the
  // synced-list manager resolves owner-share metadata against
  // userEntryListManager, which phase three initializes.
  await setupSharing(config.sharingConfig);

  // Remove the splash screen (native only; see preserve above).
  if (!kIsWeb) {
    FlutterNativeSplash.remove();
  }

  printAndLog("Setup complete, running app");
}

/// The shared body of the apps' `main()`.
///
/// Deliberately a single runApp() — NOT an early runApp() with a loading
/// screen. A first runApp() before setup makes Flutter's web engine normalise
/// the browser URL to "/" and clear the title before go_router and
/// MaterialApp.title read them, which dropped /share/<id> deep links onto the
/// home tab and left the tab title showing the bare URL. The web boot/loading
/// indication lives in web/index.html instead, which Flutter replaces on its
/// first frame without touching routing.
Future<void> runDictionaryApp(
  DictAppBootstrapConfig config, {
  required String appName,
  required String iOSAppId,
  required String androidAppId,
  required Widget Function(Locale startingLocale) buildApp,
  Future<Locale> Function()? resolveStartingLocale,
}) async {
  // Clean web URLs (e.g. /share/<id>) instead of the default hash routing, so
  // the share-link deep routes resolve. No-op on mobile.
  if (kIsWeb) {
    usePathUrlStrategy();
    // go_router only reflects `go()` in the browser URL by default; `push` /
    // `replace` (which is how an entry page is opened, see
    // defaultNavigateToEntryPage) leave the URL unchanged unless this is set.
    // Without it /word/<key> never shows up in the address bar.
    GoRouter.optionURLReflectsImperativeAPIs = true;
  }
  printAndLog("Start of main");
  try {
    await setupDictionaryApp(config);
    final locale = resolveStartingLocale == null
        ? LOCALE_ENGLISH
        : await resolveStartingLocale();
    runApp(buildApp(locale));
  } on YankedVersionError catch (e) {
    runApp(ForceUpgradePage(
        error: e, iOSAppId: iOSAppId, androidAppId: androidAppId));
  } catch (error, stackTrace) {
    runApp(ErrorFallback(
      appName: appName,
      error: error,
      stackTrace: stackTrace,
    ));
  }
}
