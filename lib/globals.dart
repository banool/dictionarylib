import 'dart:io' show HttpClient, HttpOverrides, SecurityContext, Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http_proxy/http_proxy.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'advisories.dart';
import 'common.dart';
import 'entry_list.dart';
import 'entry_loader.dart';
import 'entry_types.dart';
import 'sharing/sharing.dart';
import 'sharing/sharing_config.dart';
import 'theme.dart';

final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.light);

// Which visual style the app is currently using. The consuming app's
// MaterialApp listens to this to rebuild with the chosen theme. Initialised
// from KEY_THEME_VARIANT at startup (see the app's root widget) and updated
// from the settings page.
final ValueNotifier<AppThemeVariant> themeVariantNotifier =
    ValueNotifier(kDefaultThemeVariant);

Set<Entry> entriesGlobal = {};
Map<String, Entry> keyedByEnglishEntriesGlobal = {};

/// Base URLs the app serves media from, most-preferred first. A saved
/// video's identity is the media **path** ([SubEntry.getMedia] returns
/// paths, e.g. `/mp4video/11/11450.mp4`); the playable URL is built fresh
/// as `mediaBaseUrls.first + path`. Shipping the base in the app — rather
/// than baking it into the data or the saved identity — lets the content
/// move between hosts / CDNs without invalidating saved videos, and lets
/// a future release switch hosts. The app sets this in setup, before the
/// dictionary + lists load (so the list migration can resolve / strip it).
List<String> mediaBaseUrls = const [];

/// Resolve a media [path] (e.g. `/mp4video/11/11450.mp4`) to a full,
/// playable URL using the configured [mediaBaseUrls]. Returns the input
/// unchanged when it's already an absolute URL (defensive — an absolute
/// URL is its own identity) or when no base is configured (e.g. tests).
String mediaUrlForPath(String path) {
  if (path.startsWith('http://') || path.startsWith('https://')) return path;
  if (mediaBaseUrls.isEmpty) return path;
  return '${mediaBaseUrls.first}$path';
}

/// If [url] is a full URL under one of [mediaBaseUrls], return the media
/// path after the base (its stable identity); otherwise null. Used by the
/// v2→v3 list / review migrations to convert stored full URLs to paths.
String? mediaPathForUrl(String url) {
  for (final base in mediaBaseUrls) {
    if (url.startsWith(base)) return url.substring(base.length);
  }
  return null;
}

/// All candidate playable URLs for an already-resolved media [url],
/// most-preferred first — one per configured base in [mediaBaseUrls]. When
/// [url] is a media URL under one of the bases (the normal case: it was built
/// by [mediaUrlForPath] from `mediaBaseUrls.first`), this recovers the path and
/// re-attaches every base, so the video players can fall back to the next host
/// (e.g. an R2 mirror when the primary is down) without the caller having to
/// know about the paths. For an absolute/foreign URL under no base, or when no
/// bases are configured, returns just `[url]` — there is nothing to fall back
/// to. The first element always equals [url] when [url] was built from the
/// preferred base, so the preferred host is still tried first.
List<String> mediaFallbackUrlsFor(String url) {
  final path = mediaPathForUrl(url);
  if (path == null) return [url];
  return [for (final base in mediaBaseUrls) '$base$path'];
}

// For logging of things that occur in the background.
MaxLengthQueue<String> backgroundLogs = MaxLengthQueue(200);

late SharedPreferences sharedPreferences;
late MyCacheManager myCacheManager;

// Values of the knobs.
late bool enableFlashcardsKnob;

// This is whether to show the flashcard stuff as a result of the knob + switch.
late bool showFlashcards;

// Advisory if there is a new one.
AdvisoriesResponse? advisoriesResponse;
bool advisoryShownOnce = false;

// Manager for lists of entries defined by the user.
late UserEntryListManager userEntryListManager;

// In dictionarylib we set this to a dummy with no lists. Apps can replace this
// with an implementation that makes sense for them, e.g. for SLSL an entry list
// manager where the lists are derived from the category of the entries.
EntryListManager communityEntryListManager = DummyEntryListManager();

// Device info.
AndroidDeviceInfo? androidDeviceInfo;
IosDeviceInfo? iosDeviceInfo;

// Package info.
PackageInfo? packageInfo;

// Entry loader.
late EntryLoader entryLoader;

/// The sharing subsystem (config + API client + sync engine + deep-link
/// handler + synced-list manager). Starts out as an inert
/// [Sharing.disabled] so call sites never have to null-check —
/// every accessor returns empty / no-op until [setupSharing]
/// replaces it. Apps that don't want sharing simply don't call
/// [setupSharing] and the global stays inert.
///
/// UI surfaces that should only appear when sharing is actually
/// wired up (the "Shared with me" tab, share buttons, etc.) gate
/// on `sharing.isEnabled` instead of `sharing != null`.
Sharing sharing = Sharing.disabled();

class MyCacheManager extends CacheManager with ImageCacheManager {
  static const key = 'mySignLanguageCacheManager';

  static final MyCacheManager _instance = MyCacheManager._();
  factory MyCacheManager() {
    return _instance;
  }

  MyCacheManager._()
      : super(Config(
          key,
          stalePeriod: const Duration(days: NUM_DAYS_TO_CACHE),
          maxNrOfCacheObjects: 500,
        ));
}

// The individual startup operations live here as small, single-purpose
// functions; [setupDictionaryApp] wires them into a dependency graph (each
// awaits exactly its prerequisites) so independent work runs concurrently.
// They set globals rather than returning, matching the rest of this file.

/// Load the package info (app version etc.). The yanked-version check needs it,
/// and advisory version-filtering reads it. Best-effort: leaves [packageInfo]
/// null on failure, which downstream code tolerates.
Future<void> loadPackageInfo() async {
  try {
    packageInfo = await PackageInfo.fromPlatform();
    printAndLog("Successfully loaded package info");
  } catch (e) {
    printAndLog(
        "Failed to get package info: $e (continuing without raising any error)");
  }
}

/// Load device info into the globals. Best-effort; no dependencies.
Future<void> loadDeviceInfo() async {
  DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
  try {
    if (!kIsWeb && Platform.isAndroid) {
      androidDeviceInfo = await deviceInfo.androidInfo;
    } else if (!kIsWeb && Platform.isIOS) {
      iosDeviceInfo = await deviceInfo.iosInfo;
    }
    printAndLog("Successfully loaded device info");
  } catch (e) {
    printAndLog(
        "Failed to get device info: $e (continuing without raising any error)");
  }
}

/// The local prerequisites every network fetch and the entry load depend on:
/// [sharedPreferences] (knob caching, advisory bookkeeping, favourites),
/// then the system HTTP proxy if the user enabled it (installed globally so
/// every later fetch honours it), then the cache manager. No network of its
/// own.
Future<void> setupHttpPrerequisites() async {
  sharedPreferences = await SharedPreferences.getInstance();

  bool useSystemHttpProxy =
      sharedPreferences.getBool(KEY_USE_SYSTEM_HTTP_PROXY) ?? false;
  if (useSystemHttpProxy && !kIsWeb) {
    HttpProxy httpProxy = await HttpProxy.createHttpProxy();
    HttpOverrides.global = httpProxy;
    printAndLog("Set HTTP proxy overrides to $httpProxy");
  }

  myCacheManager = MyCacheManager();
}

/// Wire up shared lists. Call **after** the entry load ([loadEntriesIntoGlobal])
/// in apps that want sharing — the synced-list manager looks up local source
/// lists in `userEntryListManager`, which the entry load initializes. After
/// this returns the consuming app should subscribe to
/// `sharing.deepLinks.payloads` and route each [SharePayload] to its
/// `/share/:listId` route (carrying the invite token when present).
Future<void> setupSharing(SharingConfig config) async {
  assert(!sharing.isEnabled, 'setupSharing called more than once');
  sharing = await Sharing.setup(config);
}

/// Populate [entriesGlobal] using the already-built [loader]: from
/// [entriesGlobalReplacement] when given (tests), else local storage, else a
/// blocking download (the app cannot run without entry data). Requires
/// [mediaBaseUrls] already set so the list/review migrations can resolve /
/// strip saved-video paths. Stores the loader in the [entryLoader] global.
Future<void> loadEntriesIntoGlobal(
  EntryLoader loader, {
  Set<Entry>? entriesGlobalReplacement,
}) async {
  if (entriesGlobalReplacement != null && entriesGlobalReplacement.isEmpty) {
    throw ArgumentError("If given, entriesGlobalReplacement must not be empty");
  }

  // Load up the words information once at startup from disk. loadFavourites
  // depends on it later.
  if (entriesGlobalReplacement != null) {
    loader.setEntriesGlobal(entriesGlobalReplacement);
  } else {
    var entriesFromLocalStorage = await loader.loadEntriesFromLocalStorage();
    if (entriesFromLocalStorage.isNotEmpty) {
      loader.setEntriesGlobal(entriesFromLocalStorage);
    }
  }

  // If entriesGlobalReplacement was set, entriesGlobal should have something
  // in it at this point.
  if (entriesGlobalReplacement != null && entriesGlobal.isEmpty) {
    throw Exception(
        "entriesGlobal is empty after the loading phase despite entriesGlobalReplacement being set.");
  }

  // At this point if entriesGlobal is empty it means either there was no data
  // in local storage or the data there was invalid. If so, we must download
  // new data before proceeding, since the app depends on entriesGlobal and
  // friends being set.
  if (entriesGlobal.isEmpty) {
    printAndLog(
        "No entry data found in local storage, fetching data from the internet and waiting for it before proceeeding...");
    NewData? newData = await loader.downloadAndApplyNewData(true);
    if (newData == null) {
      // This implies that there is some incompatibility between the data upstream
      // and how the app interprets it.
      throw Exception(
          "No entry data was found in local storage but there was apparently no new data available from the internet. The app cannot operate without entries data, throwing...");
    }
  } else {
    printAndLog(
        "Entry data was found in local storage, fetching new data from the internet in the background...");
    loader.downloadAndApplyNewData(false);
  }

  // A final sanity check to ensure that we have entries data.
  if (entriesGlobal.isEmpty) {
    throw Exception(
        "entriesGlobal is empty even after the loading phase. The app cannot operate without entries data, throwing...");
  }

  entryLoader = loader;
}

class ProxiedHttpOverrides extends HttpOverrides {
  final String? _port;
  final String? _host;
  ProxiedHttpOverrides(this._host, this._port);

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      // Set proxy
      ..findProxy = (uri) {
        return _host != null ? "PROXY $_host:$_port;" : 'DIRECT';
      };
  }
}
