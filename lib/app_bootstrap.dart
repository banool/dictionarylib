import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';

import 'advisories.dart';
import 'common.dart';
import 'entry_loader.dart';
import 'entry_types.dart';
import 'error_fallback.dart';
import 'flashcards_logic.dart';
import 'globals.dart';
import 'page_force_upgrade.dart';
import 'sharing/sharing_config.dart';

/// Everything app-specific about app startup. The orchestration itself —
/// binding/splash, MediaKit, the startup dependency graph, the review-history
/// migration + setupSharing after the data load, and the single runApp with the
/// force-upgrade / error fallbacks — is identical across the dictionary apps and
/// lives in [setupDictionaryApp] / [runDictionaryApp].
class DictAppBootstrapConfig {
  const DictAppBootstrapConfig({
    required this.advisoriesUrl,
    required this.yankedVersionsUrl,
    required this.knobUrlBase,
    this.extraStartupTasks = const [],
    required this.setupMediaAndEntryLoader,
    required this.sharingConfig,
  });

  /// The app's advisories file (GitHub raw). Fetched best-effort at startup.
  final Uri advisoriesUrl;

  /// The app's yanked_versions file (GitHub raw). A listed version makes
  /// startup throw YankedVersionError, which runDictionaryApp turns into the
  /// ForceUpgradePage.
  final String yankedVersionsUrl;

  /// The app's knob base URL.
  final String knobUrlBase;

  /// Extra startup work run concurrently with the other best-effort metadata
  /// fetches (e.g. SLSL's use_cdn_url knob read). The entry load waits on these
  /// (so [setupMediaAndEntryLoader] can read them) but the advisory / yanked /
  /// flashcards fetches do not. Must not throw for anything short of "the app
  /// cannot run".
  final List<Future<void> Function()> extraStartupTasks;

  /// Set [mediaBaseUrls] and build the app's EntryLoader. Awaits
  /// [extraStartupTasks] (so it can read knobs they fetch, e.g. use_cdn_url) and
  /// runs before the entry load (so the list / review migrations can resolve /
  /// strip saved-video paths against the bases).
  final Future<EntryLoader> Function() setupMediaAndEntryLoader;

  final SharingConfig sharingConfig;
}

/// The shared body of the apps' `setup()`.
///
/// Startup is expressed as a **dependency graph** rather than a fixed sequence
/// of phases: each unit of work below is a `Future` that awaits exactly its own
/// prerequisites, so the ordering is explicit (read the `await`s) and
/// everything that can run concurrently does. The only hard barrier is the
/// `Future.wait` near the end — the set of work that must be settled before the
/// first frame. To add startup work, wire a new future to the futures it truly
/// depends on; don't reach for a new "phase".
///
/// Timing: the best-effort metadata fetches (advisories, the flashcards knob,
/// the yanked check, the app's extra knobs) all run concurrently once the local
/// HTTP prerequisites are ready, so a slow/offline network delays startup by at
/// most one [kMetadataFetchTimeout], not the sum. The essential entry load runs
/// concurrently with them, gated only on the extra knobs it needs.
///
/// [checkYankedVersion] and [handleNativeSplash] default to true for real app
/// launches; the integration harness passes false (a forced upgrade must not
/// veto an e2e run, and the tests own the splash).
Future<void> setupDictionaryApp(
  DictAppBootstrapConfig config, {
  Set<Entry>? entriesGlobalReplacement,
  bool checkYankedVersion = true,
  bool handleNativeSplash = true,
}) async {
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();

  // Initialize media_kit for video playback (native only; web plays via the
  // HTML5 video_player path — see VideoSurface).
  if (!kIsWeb) {
    MediaKit.ensureInitialized();
  }

  // Preserve the splash screen while the app initializes. Native only —
  // there's no web splash configured, so calling this on web throws.
  if (!kIsWeb && handleNativeSplash) {
    FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  }

  // --- Startup dependency graph --------------------------------------------

  // Local prerequisites, independent of each other.
  final deviceInfoReady = loadDeviceInfo();
  final packageInfoReady = loadPackageInfo();

  // sharedPreferences + proxy + cache manager. Every network fetch waits on
  // this so it honours the user's proxy setting and has prefs for caching.
  final httpReady = setupHttpPrerequisites();

  // Best-effort metadata. Each awaits only what it needs; none blocks another,
  // and none throws (advisories → null, knob → cached/default on failure).
  final advisoriesReady = () async {
    // packageInfo gates version-bounded advisory filtering.
    await Future.wait([httpReady, packageInfoReady]);
    advisoriesResponse = await getAdvisories(config.advisoriesUrl);
  }();
  final flashcardsKnobReady = () async {
    await httpReady;
    enableFlashcardsKnob =
        await readKnob(config.knobUrlBase, "enable_flashcards", true);
  }();
  final extraKnobsReady = () async {
    await httpReady;
    await Future.wait(config.extraStartupTasks.map((task) => task()));
  }();

  // Force-upgrade check. Throws YankedVersionError only when the running
  // version is genuinely yanked (runDictionaryApp turns that into the
  // ForceUpgradePage); a failed fetch fails open to "not yanked".
  final yankedCheckReady = () async {
    if (!checkYankedVersion) return;
    await Future.wait([packageInfoReady, httpReady]);
    await GitHubYankedVersionChecker(config.yankedVersionsUrl)
        .throwIfShouldUpgrade();
  }();

  // Essential data: resolve media + build the loader (may read the extra knobs,
  // e.g. SLSL's use_cdn_url), then load the dictionary — from disk, or a
  // blocking download if the local cache is empty. Gated only on the extra
  // knobs, so it overlaps the advisory / yanked / flashcards fetches.
  final entriesReady = () async {
    await extraKnobsReady;
    final loader = await config.setupMediaAndEntryLoader();
    await loadEntriesIntoGlobal(loader,
        entriesGlobalReplacement: entriesGlobalReplacement);
  }();

  // Barrier: everything that must be settled before the first frame. A yanked
  // version surfaces here as YankedVersionError. Future.wait keeps the other
  // in-flight fetches attached, so no failure becomes an unhandled zone error.
  await Future.wait([
    deviceInfoReady,
    httpReady,
    advisoriesReady,
    flashcardsKnobReady,
    yankedCheckReady,
    entriesReady,
  ]);

  // Derived from the flashcards knob (awaited above).
  showFlashcards = getShowFlashcards();

  // One-shot migration of stored DolphinSR review history from the v1 master id
  // shape ("entryKey-firstVideoFilename") to the v2 shape (per-saved-video).
  // No-op after the first successful run. Runs after the entry load because it
  // walks the dictionary to resolve legacy master ids.
  await migrateLegacyReviewsIfNeeded();

  // Opt in to the shared-lists feature. Runs after the entry load because the
  // synced-list manager resolves owner-share metadata against
  // userEntryListManager, which the entry load initializes.
  await setupSharing(config.sharingConfig);

  // Remove the splash screen (native only; see preserve above).
  if (!kIsWeb && handleNativeSplash) {
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
