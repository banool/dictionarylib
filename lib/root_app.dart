import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'analytics.dart';
import 'common.dart';
import 'entry_list.dart';
import 'entry_types.dart';
import 'globals.dart';
import 'l10n/app_localizations.dart';
import 'page_entry_list.dart';
import 'page_entry_list_overview.dart';
import 'page_flashcards_landing.dart';
import 'page_search.dart';
import 'page_settings.dart';
import 'page_word.dart';
import 'saved_video.dart';
import 'sharing/deep_link_handler.dart';
import 'sharing/engine_notification_listener.dart';
import 'sharing/shared_list_landing_page.dart';
import 'sharing/sync_engine.dart' show SyncNotification;
import 'theme.dart';
import 'top_level_scaffold.dart'
    show LISTS_ROUTE, REVISION_ROUTE, SEARCH_ROUTE, SETTINGS_ROUTE;

// Debug-only launch overrides for testing a specific screen / theme without
// hand-editing app code (and risking leaving the edit in). They're set via
// --dart-define, default to empty when absent, and are ignored entirely
// outside debug builds — so the shipped app always boots to SEARCH_ROUTE with
// the user's persisted theme. Examples:
//   flutter run --dart-define=DEBUG_INITIAL_LOCATION='/search?query=dog&navigate_to_first_match=true'
//   flutter run --dart-define=DEBUG_THEME_VARIANT=classic --dart-define=DEBUG_THEME_MODE=dark
const String _kDebugInitialLocation =
    String.fromEnvironment('DEBUG_INITIAL_LOCATION');
const String _kDebugThemeVariant =
    String.fromEnvironment('DEBUG_THEME_VARIANT');
const String _kDebugThemeMode = String.fromEnvironment('DEBUG_THEME_MODE');

/// The device locale, assigned by the app's main() before runApp. Defaults to
/// English so anything that reads it before main() assigns the real device
/// locale (e.g. a language dropdown in widget/integration tests that pump the
/// root app without going through main()) doesn't hit a LateInitializationError.
Locale systemLocale = LOCALE_ENGLISH;

/// Everything app-specific about the root MaterialApp + router. The route
/// table, deep-link handling, engine-event snackbars, and theme plumbing are
/// identical across the dictionary apps; this is the seam where they differ.
class DictRootAppConfig {
  const DictRootAppConfig({
    required this.appName,
    this.appTitle,
    required this.classicSeed,
    required this.wordPageConfig,
    required this.navigateToEntryPage,
    required this.includeEntryTypeButton,
    this.entryDefinitionPreview,
    required this.buildFlashcardsLandingPageController,
    this.buildSettingsTopWidgets,
    required this.buildLegalInformationChildren,
    required this.reportDataProblemUrl,
    required this.reportAppProblemUrl,
    required this.privacyPolicyUrl,
    required this.termsOfServiceUrl,
    required this.iOSAppId,
    required this.androidAppId,
  });

  final String appName;

  /// Locale-aware window/tab title (onGenerateTitle). Null → [appName].
  final String Function(Locale locale)? appTitle;

  /// Seed color for the Classic theme variant.
  final Color classicSeed;

  final WordPageConfig wordPageConfig;

  final NavigateToEntryPageFn navigateToEntryPage;

  /// Whether the search page shows the words/phrases entry type filter.
  final bool includeEntryTypeButton;

  /// Short plain-text preview of an entry's definition for the search page's
  /// "sign of the day" card. Null → no preview shown.
  final String? Function(Entry entry)? entryDefinitionPreview;

  final FlashcardsLandingPageController Function()
      buildFlashcardsLandingPageController;

  /// Extra widgets at the top of the settings page (e.g. a language picker).
  /// Null → none.
  final List<Widget> Function(BuildContext context)? buildSettingsTopWidgets;

  final List<Widget> Function() buildLegalInformationChildren;
  final String reportDataProblemUrl;
  final String reportAppProblemUrl;
  final String privacyPolicyUrl;
  final String termsOfServiceUrl;
  final String iOSAppId;
  final String androidAppId;
}

/// Open an entry, matching [NavigateToEntryPageFn] once curried with
/// [makeNavigateToEntryPage].
///
/// Web: pushes a real `/word/<key>` go_router route so the URL reflects the
/// entry and it's deep-linkable (a pasted link resolves the entry from the
/// key). Native: keeps the proven imperative push — URLs are invisible there
/// anyway, and going through go_router would clobber a raw-pushed parent
/// (e.g. the list view) and break its back button. The non-serialisable bits
/// ([focusVideo], [saveToList]) ride along as `extra`.
Future<void> defaultNavigateToEntryPage(
    BuildContext context, Entry entry, bool showFavouritesButton,
    {SavedVideo? focusVideo,
    EntryList? saveToList,
    required WordPageConfig config}) async {
  if (kIsWeb) {
    await context.push(
      "$WORD_ROUTE/${Uri.encodeComponent(entry.getKey())}",
      extra: EntryPageArgs(
        showFavouritesButton: showFavouritesButton,
        focusVideo: focusVideo,
        saveToList: saveToList,
      ),
    );
  } else {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EntryPage(
            entry: entry,
            config: config,
            showFavouritesButton: showFavouritesButton,
            focusVideo: focusVideo,
            saveToList: saveToList),
      ),
    );
  }
}

/// Curry [defaultNavigateToEntryPage] with the app's [WordPageConfig] so it
/// matches the [NavigateToEntryPageFn] typedef used throughout the library.
NavigateToEntryPageFn makeNavigateToEntryPage(WordPageConfig config) {
  return (BuildContext context, Entry entry, bool showFavouritesButton,
      {SavedVideo? focusVideo, EntryList? saveToList}) {
    return defaultNavigateToEntryPage(context, entry, showFavouritesButton,
        focusVideo: focusVideo, saveToList: saveToList, config: config);
  };
}

/// The shared root widget: MaterialApp.router + the full route table. Apps
/// wrap this in a thin RootApp of their own that supplies their
/// [DictRootAppConfig].
class DictRootApp extends StatefulWidget {
  const DictRootApp(
      {super.key, required this.startingLocale, required this.config});

  final Locale startingLocale;
  final DictRootAppConfig config;

  @override
  State<DictRootApp> createState() => _DictRootAppState();

  static void applyLocaleOverride(BuildContext context, Locale newLocale) {
    _DictRootAppState state =
        context.findAncestorStateOfType<_DictRootAppState>()!;
    state._setLocale(newLocale);
  }

  static void clearLocaleOverride(BuildContext context) {
    _DictRootAppState state =
        context.findAncestorStateOfType<_DictRootAppState>()!;
    state._setLocale(systemLocale);
  }
}

class _DictRootAppState extends State<DictRootApp> {
  late Locale locale;

  void _setLocale(Locale newLocale) {
    setState(() {
      locale = newLocale;
    });
  }

  StreamSubscription<SharePayload>? _deepLinkSub;
  StreamSubscription<SyncNotification>? _engineNotificationSub;

  late final GoRouter router;

  SearchPage _buildSearchPage(
      {String? initialQuery, bool? navigateToFirstMatch}) {
    return SearchPage(
      navigateToEntryPage: widget.config.navigateToEntryPage,
      initialQuery: initialQuery,
      navigateToFirstMatch: navigateToFirstMatch,
      includeEntryTypeButton: widget.config.includeEntryTypeButton,
      entryDefinitionPreview: widget.config.entryDefinitionPreview,
    );
  }

  @override
  void initState() {
    super.initState();
    locale = widget.startingLocale;
    // Default to following the OS light/dark setting; the user can pin
    // light or dark explicitly in settings. The native splash also
    // follows the OS appearance, so a fresh install gets a consistent
    // splash → first frame in both modes.
    themeNotifier.value = ThemeMode
        .values[sharedPreferences.getInt(KEY_THEME_MODE) ?? DEFAULT_THEME_MODE];
    themeVariantNotifier.value =
        appThemeVariantFromName(sharedPreferences.getString(KEY_THEME_VARIANT));
    // Debug-only theme overrides (see _kDebug* consts above). No-ops in release
    // and when the corresponding --dart-define isn't set.
    if (kDebugMode && _kDebugThemeMode.isNotEmpty) {
      themeNotifier.value =
          _kDebugThemeMode == 'dark' ? ThemeMode.dark : ThemeMode.light;
    }
    if (kDebugMode && _kDebugThemeVariant.isNotEmpty) {
      themeVariantNotifier.value = appThemeVariantFromName(_kDebugThemeVariant);
    }
    router = _buildRouter();
    // Forward incoming share deep-links to the share landing route. The
    // invite token (when present) is carried through as a query parameter
    // so the landing page can drive the accept-invite flow instead of the
    // anonymous subscribe.
    //
    // We `push` rather than `go` so the app's existing screen stays
    // underneath: the landing page (and the list page it swaps itself for)
    // then has something to pop back to. On a cold start the initial
    // location (search) is the base, so opening a shared list still leaves a
    // working back button instead of stranding the user on a rootless route.
    _deepLinkSub = sharing.deepLinks.payloads.listen((payload) {
      router.push(payload.toRouteLocation());
    });
    // Surface engine one-shot events (session expired, removed as editor,
    // snapshot catch-up) as snackbars from any page — the engine stream is
    // a broadcast stream, so events without a live listener are lost.
    if (sharing.isEnabled) {
      _engineNotificationSub = installEngineNotificationSnackbars();
    }
  }

  @override
  void dispose() {
    _deepLinkSub?.cancel();
    _engineNotificationSub?.cancel();
    super.dispose();
  }

  GoRouter _buildRouter() {
    return GoRouter(
        navigatorKey: rootNavigatorKey,
        // Anonymous screen-view analytics (base path only; no query/path params
        // ever leave the device). Only attached when analytics is enabled.
        observers: [
          if (Analytics.isEnabled) AnalyticsNavigatorObserver(),
        ],
        initialLocation: kDebugMode && _kDebugInitialLocation.isNotEmpty
            ? _kDebugInitialLocation
            : SEARCH_ROUTE,
        // An unknown location (a stale deep-link, a typo'd path, a malformed
        // share link that didn't match `/share/:listId`) should drop the user
        // on the search screen rather than a bare error page — search is the
        // app's home and always safe to render. A malformed `/share/<id>` that
        // *does* match the route is handled gracefully by the landing page's
        // own error branch (it surfaces an "expired / unknown list" state).
        errorBuilder: (context, state) => _buildSearchPage(),
        routes: [
          GoRoute(
            path: "/",
            redirect: (context, state) => SEARCH_ROUTE,
          ),
          GoRoute(
              path: SEARCH_ROUTE,
              pageBuilder: (BuildContext context, GoRouterState state) {
                String? initialQuery = state.uri.queryParameters["query"];
                bool navigateToFirstMatch =
                    state.uri.queryParameters["navigate_to_first_match"] ==
                        "true";
                // No per-rebuild key: a `UniqueKey()` here forced the whole
                // SearchPage to be torn down and rebuilt from scratch (losing
                // search state) on every router rebuild — the other tabs don't
                // do this. The route path already keys the page.
                return NoTransitionPage(
                  name: SEARCH_ROUTE, // for the screen-view analytics observer
                  child: _buildSearchPage(
                    initialQuery: initialQuery,
                    navigateToFirstMatch: navigateToFirstMatch,
                  ),
                );
              }),
          GoRoute(
              path: LISTS_ROUTE,
              pageBuilder: (BuildContext context, GoRouterState state) {
                return NoTransitionPage(
                  name: LISTS_ROUTE, // for the screen-view analytics observer
                  child: EntryListsOverviewPage(
                    buildEntryListWidgetCallback: (entryList) => EntryListPage(
                      entryList: entryList,
                      navigateToEntryPage: widget.config.navigateToEntryPage,
                    ),
                  ),
                );
              }),
          GoRoute(
              path: REVISION_ROUTE,
              pageBuilder: (BuildContext context, GoRouterState state) {
                var controller =
                    widget.config.buildFlashcardsLandingPageController();
                return NoTransitionPage(
                    name:
                        REVISION_ROUTE, // for the screen-view analytics observer
                    child: FlashcardsLandingPage(
                      controller: controller,
                    ));
              }),
          GoRoute(
              path: '/share/:listId',
              pageBuilder: (BuildContext context, GoRouterState state) {
                final id = state.pathParameters['listId']!;
                final invite = state.uri.queryParameters['invite'];
                // Stable key per (listId, inviteToken) so re-tapping the
                // same share link doesn't tear down + rebuild the page
                // (which would re-trigger subscribe / sign-in). Different
                // links still get distinct keys so navigation between
                // shares mounts a fresh page.
                return NoTransitionPage(
                  key: ValueKey('share-$id-${invite ?? ''}'),
                  name: '/share', // base only (no list id) for analytics
                  child: SharedListLandingPage(
                    listId: id,
                    inviteToken:
                        invite != null && invite.isNotEmpty ? invite : null,
                    navigateToEntryPage: widget.config.navigateToEntryPage,
                  ),
                );
              }),
          GoRoute(
              path: SETTINGS_ROUTE,
              pageBuilder: (BuildContext context, GoRouterState state) {
                return NoTransitionPage(
                    name:
                        SETTINGS_ROUTE, // for the screen-view analytics observer
                    child: SettingsPage(
                      appName: widget.config.appName,
                      additionalTopWidgets: widget
                              .config.buildSettingsTopWidgets
                              ?.call(context) ??
                          const [],
                      buildLegalInformationChildren:
                          widget.config.buildLegalInformationChildren,
                      reportDataProblemUrl: widget.config.reportDataProblemUrl,
                      reportAppProblemUrl: widget.config.reportAppProblemUrl,
                      iOSAppId: widget.config.iOSAppId,
                      androidAppId: widget.config.androidAppId,
                      privacyPolicyUrl: widget.config.privacyPolicyUrl,
                      termsOfServiceUrl: widget.config.termsOfServiceUrl,
                    ));
              }),
          GoRoute(
              path: "$WORD_ROUTE/:key",
              pageBuilder: (BuildContext context, GoRouterState state) {
                final key = Uri.decodeComponent(state.pathParameters['key']!);
                final entry = keyedByEnglishEntriesGlobal[key];
                // Unknown / not-yet-loaded word (a stale or hand-typed
                // /word/<x> URL) → fall back to search rather than a broken page.
                if (entry == null) {
                  return NoTransitionPage(
                    name: SEARCH_ROUTE, // fallback shows search
                    child: _buildSearchPage(),
                  );
                }
                final args = state.extra is EntryPageArgs
                    ? state.extra as EntryPageArgs
                    : null;
                // Stable key per entry so updating only the ?variation/?video
                // query as the user swipes preserves the page's state instead of
                // tearing it down and rebuilding (which would reset the carousel).
                return NoTransitionPage(
                  key: ValueKey('word-$key'),
                  name: WORD_ROUTE, // base only (no entry key) for analytics
                  child: EntryPage(
                    entry: entry,
                    config: widget.config.wordPageConfig,
                    showFavouritesButton: args?.showFavouritesButton ?? true,
                    focusVideo: args?.focusVideo,
                    saveToList: args?.saveToList,
                    initialVariation: int.tryParse(
                        state.uri.queryParameters['variation'] ?? ''),
                    initialVideo:
                        int.tryParse(state.uri.queryParameters['video'] ?? ''),
                  ),
                );
              }),
        ]);
  }

  @override
  Widget build(BuildContext context) {
    // Outer listener: the light/dark mode. Inner listener: which visual style
    // ("theme variant") to build, e.g. Hearth or Classic. Both themes are
    // built here in the shared library so all the theming lives in one place.
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, themeMode, child) {
        return ValueListenableBuilder<AppThemeVariant>(
          valueListenable: themeVariantNotifier,
          builder: (context, themeVariant, child) {
            return GestureDetector(
                onTap: () {
                  FocusScopeNode currentFocus = FocusScope.of(context);
                  if (!currentFocus.hasPrimaryFocus &&
                      currentFocus.focusedChild != null) {
                    FocusManager.instance.primaryFocus!.unfocus();
                  }
                },
                child: MaterialApp.router(
                  title: widget.config.appName,
                  // onGenerateTitle so locale-aware titles work; see
                  // https://stackoverflow.com/q/77759180/3846032 for why this
                  // is set manually.
                  onGenerateTitle: (context) =>
                      widget.config.appTitle?.call(locale) ??
                      widget.config.appName,
                  scaffoldMessengerKey: rootScaffoldMessengerKey,
                  localizationsDelegates:
                      DictLibLocalizations.localizationsDelegates,
                  supportedLocales: LANGUAGE_CODE_TO_LOCALE.values,
                  locale: locale,
                  debugShowCheckedModeBanner: false,
                  // Scale text up on tablet-sized displays so the phone
                  // layouts don't read as tiny on a 13" panel; phones are
                  // untouched. See kLargeScreenTextScale.
                  builder: largeScreenTextScaleBuilder,
                  themeMode: themeMode,
                  theme: buildAppTheme(
                    variant: themeVariant,
                    brightness: Brightness.light,
                    classicSeed: widget.config.classicSeed,
                  ),
                  darkTheme: buildAppTheme(
                    variant: themeVariant,
                    brightness: Brightness.dark,
                    classicSeed: widget.config.classicSeed,
                  ),
                  routerConfig: router,
                ));
          },
        );
      },
    );
  }
}
