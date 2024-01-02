import 'package:flutter/cupertino.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'dart:io' show HttpClient, HttpOverrides, SecurityContext, Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:system_proxy/system_proxy.dart';

import 'advisories.dart';
import 'common.dart';
import 'entry_list.dart';
import 'entry_loader.dart';
import 'entry_types.dart';

Set<Entry> entriesGlobal = {};
Map<String, Entry> keyedByEnglishEntriesGlobal = {};

// For logging of things that occur in the background.
MaxLengthQueue<String> backgroundLogs = MaxLengthQueue(200);

late SharedPreferences sharedPreferences;
late MyCacheManager myCacheManager;

// Values of the knobs.
late bool enableFlashcardsKnob;
bool downloadWordsDataKnob = true;

// This is whether to show the flashcard stuff as a result of the knob + switch.
late bool showFlashcards;

// The settings page background color.
late Color settingsBackgroundColor;

// Advisory if there is a new one.
AdvisoriesResponse? advisoriesResponse;
bool advisoryShownOnce = false;

// Manager for lists of entries.
late EntryListManager entryListManager;

// Device info.
AndroidDeviceInfo? androidDeviceInfo;
IosDeviceInfo? iosDeviceInfo;

// Package info.
PackageInfo? packageInfo;

// Entry loader.
late EntryLoader entryLoader;

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

// Set up up until we fetch knobs. This includes shared device / package info,
// shared prefs, proxy stuff, advisories, and the cache manager.
Future<void> setupPhaseOne() async {
  // Load device info once at startup.
  DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
  try {
    if (Platform.isAndroid) {
      androidDeviceInfo = await deviceInfo.androidInfo;
    } else if (Platform.isIOS) {
      iosDeviceInfo = await deviceInfo.iosInfo;
    }
    printAndLog("Successfully loaded device info");
  } catch (e) {
    printAndLog(
        "Failed to get device info: $e (continuing without raising any error)");
  }

  // Load package info once at startup.
  try {
    packageInfo = await PackageInfo.fromPlatform();
    printAndLog("Successfully loaded package info");
  } catch (e) {
    printAndLog(
        "Failed to get package info: $e (continuing without raising any error)");
  }

  // Load shared preferences. We do this first because the later futures,
  // such as loadFavourites and the knobs, depend on it being initialized.
  sharedPreferences = await SharedPreferences.getInstance();

  // Set the HTTP proxy if necessary.
  if (!kIsWeb) {
    Map<String, String> proxy = await SystemProxy.getProxySettings() ?? {};
    HttpOverrides.global = ProxiedHttpOverrides(proxy["host"], proxy["port"]);
    printAndLog("Set HTTP proxy overrides to $proxy");
  }

  // Load up the advisories before doing anything else so it can be displayed
  // in the error page.
  advisoriesResponse = await getAdvisories(Uri.parse(
      "https://raw.githubusercontent.com/banool/slsl_dictionary/main/frontend/assets/advisories.md"));

  // Build the cache manager.
  myCacheManager = MyCacheManager();

  // Get background color of settings pages.
  if (kIsWeb) {
    settingsBackgroundColor = const Color.fromRGBO(240, 240, 240, 1);
  } else if (Platform.isAndroid) {
    settingsBackgroundColor = const Color.fromRGBO(240, 240, 240, 1);
  } else if (Platform.isIOS) {
    settingsBackgroundColor = const Color.fromRGBO(242, 242, 247, 1);
  } else {
    settingsBackgroundColor = const Color.fromRGBO(240, 240, 240, 1);
  }
}

// Pull knobs, load up entry data. Make sure you have pulled other knobs you
// might care about / done other stuff with the shared prefs before this.
// This expects that some knobs (e.g. enable_flashcards) exist upstream.
Future<void> setupPhaseTwo(
    {required EntryLoader paramEntryLoader,
    required String knobUrlBase,
    Set<Entry>? entriesGlobalReplacement}) async {
  await Future.wait<void>([
    // Load up the words information once at startup from disk.
    // We do this first because loadFavourites depends on it later.
    (() async {
      if (entriesGlobalReplacement == null) {
        paramEntryLoader.setEntriesGlobal(
            await paramEntryLoader.loadEntriesFromLocalStorage());
      } else {
        paramEntryLoader.setEntriesGlobal(entriesGlobalReplacement);
      }
    })(),

    // Get knob values.
    (() async => enableFlashcardsKnob =
        await readKnob(knobUrlBase, "enable_flashcards", true))(),
  ]);

  // This depends on the knob values above being set so it is important that
  // this appears after that block above and after any knobs set between phases
  // one and two.
  if (downloadWordsDataKnob && entriesGlobalReplacement == null) {
    if (entriesGlobal.isEmpty) {
      printAndLog(
          "No local entry data cache found, fetching updates from the internet and waiting for them before proceeeding...");
      await paramEntryLoader.updateWordsData(true);
    } else {
      printAndLog(
          "Local entry data cache found, fetching updates from the internet in the background...");
      paramEntryLoader.updateWordsData(false);
    }
  }

  entryLoader = paramEntryLoader;

  // Resolve values based on knobs.
  showFlashcards = getShowFlashcards();
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
