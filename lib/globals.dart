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

// Setup just enough that we can show the force upgrade page.
Future<void> setupPhaseOne() async {
  // Load package info once at startup.
  try {
    packageInfo = await PackageInfo.fromPlatform();
    printAndLog("Successfully loaded package info");
  } catch (e) {
    printAndLog(
        "Failed to get package info: $e (continuing without raising any error)");
  }
}

// Set up up until we fetch knobs. This includes shared device / package info,
// shared prefs, proxy stuff, advisories, and the cache manager.
Future<void> setupPhaseTwo(Uri advisoriesFileUri) async {
  // Load device info once at startup.
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

  // Load shared preferences. We do this first because the later futures,
  // such as loadFavourites and the knobs, depend on it being initialized.
  sharedPreferences = await SharedPreferences.getInstance();

  // Set the HTTP proxy if necessary.
  bool useSystemHttpProxy =
      sharedPreferences.getBool(KEY_USE_SYSTEM_HTTP_PROXY) ?? false;
  if (useSystemHttpProxy && !kIsWeb) {
    HttpProxy httpProxy = await HttpProxy.createHttpProxy();
    HttpOverrides.global = httpProxy;
    printAndLog("Set HTTP proxy overrides to $httpProxy");
  }

  // Load up the advisories before doing anything else so it can be displayed
  // in the error page.
  advisoriesResponse = await getAdvisories(advisoriesFileUri);

  // Build the cache manager.
  myCacheManager = MyCacheManager();
}

/// Wire up shared lists. Call **after** `setupPhaseThree` in apps that want
/// sharing — the synced-list manager looks up local source lists in
/// `userEntryListManager`, which `setupPhaseThree` initializes. After this
/// returns the consuming app should subscribe to
/// `sharing.deepLinks.payloads` and route each [SharePayload] to its
/// `/share/:listId` route (carrying the invite token when present).
Future<void> setupSharing(SharingConfig config) async {
  assert(!sharing.isEnabled, 'setupSharing called more than once');
  sharing = await Sharing.setup(config);
}

// Pull knobs, load up entry data. Make sure you have pulled other knobs you
// might care about / done other stuff with the shared prefs before this.
// This expects that some knobs (e.g. enable_flashcards) exist upstream.
Future<void> setupPhaseThree(
    {required EntryLoader paramEntryLoader,
    required String knobUrlBase,
    Set<Entry>? entriesGlobalReplacement}) async {
  if (entriesGlobalReplacement != null && entriesGlobalReplacement.isEmpty) {
    throw ArgumentError("If given, entriesGlobalReplacement must not be empty");
  }

  await Future.wait<void>([
    // Load up the words information once at startup from disk.
    // We do this first because loadFavourites depends on it later.
    (() async {
      if (entriesGlobalReplacement != null) {
        paramEntryLoader.setEntriesGlobal(entriesGlobalReplacement);
      } else {
        var entriesFromLocalStorage =
            await paramEntryLoader.loadEntriesFromLocalStorage();
        if (entriesFromLocalStorage.isNotEmpty) {
          paramEntryLoader.setEntriesGlobal(entriesFromLocalStorage);
        }
      }
    })(),

    // Get knob values.
    (() async => enableFlashcardsKnob =
        await readKnob(knobUrlBase, "enable_flashcards", true))(),
  ]);

  // Resolve values based on knobs.
  showFlashcards = getShowFlashcards();

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
    NewData? newData = await paramEntryLoader.downloadAndApplyNewData(true);
    if (newData == null) {
      // This implies that there is some incompatibility between the data upstream
      // and how the app interprets it.
      throw Exception(
          "No entry data was found in local storage but there was apparently no new data available from the internet. The app cannot operate without entries data, throwing...");
    }
  } else {
    printAndLog(
        "Entry data was found in local storage, fetching new data from the internet in the background...");
    paramEntryLoader.downloadAndApplyNewData(false);
  }

  // A final sanity check to ensure that we have entries data.
  if (entriesGlobal.isEmpty) {
    throw Exception(
        "entriesGlobal is empty even after the loading phase. The app cannot operate without entries data, throwing...");
  }

  entryLoader = paramEntryLoader;
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
