import 'dart:io';

import 'package:dictionarylib/entry_list.dart';
import 'package:dictionarylib/entry_types.dart';
import 'package:dictionarylib/globals.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'common.dart';

abstract class EntryLoader {
  /// Returns the local path where we store the dictionary data we download.
  Future<File> get _dictionaryDataFilePath async {
    final path = (await getApplicationDocumentsDirectory()).path;
    return File('$path/word_dictionary.json');
  }

  /// Try to load data from the local cache.
  Future<Set<Entry>> loadEntriesFromLocalStorage() async {
    String? data;

    // First try to read the data from local storage.
    try {
      if (kIsWeb) {
        // If we're on web use local storage, in which we just store all the data
        // as a value in the kv store.
        data = sharedPreferences.getString(KEY_WEB_DICTIONARY_DATA);
      } else {
        // If we're not on web, read data from the application directory, in
        // which we store it as an actual file.
        final path = await _dictionaryDataFilePath;
        data = await path.readAsString();
      }
    } catch (e) {
      printAndLog("Failed to load cached entries data from local storage: $e");
    }

    if (data == null) {
      printAndLog("No cached data was found");
      return {};
    }

    try {
      printAndLog(
          "Loaded entries from local storage (the data cached locally after downloading it from from the internet)");
      return loadEntriesInner(data);
    } catch (e) {
      printAndLog(
          "Failed to deserialize data from local storage, we'll try to download from the remote again: $e");
      return {};
    }
  }

  updateEnglishKeyedEntriesGlobal() {
    printAndLog("Updating keyed entriesGlobal variants");
    for (Entry e in entriesGlobal) {
      // The key is the word in English, which is always present.
      keyedByEnglishEntriesGlobal[e.getPhrase(LOCALE_ENGLISH)!] = e;
    }
    printAndLog("Updated keyed entriesGlobal variants");
  }

  /// Set entriesGlobal and all the stuff that depends on it. Subclasses may
  /// want to override this to first call super and then update additional
  /// keyed entries globals. They might want to set the communityListManager
  /// too if relevant.
  setEntriesGlobal(Set<Entry> entries) {
    entriesGlobal = entries;

    // Update the global entries variants keyed by each language.
    updateEnglishKeyedEntriesGlobal();

    // Update the list manager.
    userEntryListManager = UserEntryListManager.fromStartup();

    printAndLog("Updated entriesGlobal and all its downstream variables");
  }

  Future<void> writeEntries(String newData) async {
    if (kIsWeb) {
      // If we're on web use local storage. Currently the dump file is around
      // 1mb and local storage should support 5mb per site, so this should be
      // sufficient for now: https://stackoverflow.com/q/2989284/3846032.
      await sharedPreferences.setString(KEY_WEB_DICTIONARY_DATA, newData);
    } else {
      final path = await _dictionaryDataFilePath;
      await path.writeAsString(newData);
    }
  }

  /// This function should parse the data (probably JSON) and return a set of
  /// entries.
  Set<Entry> loadEntriesInner(String data);

  /// The implementor must define this. This downloads new data and returns it
  /// as a string. Likely this string is JSON. This will return None if there
  /// is no new data.
  Future<NewData?> downloadNewData(int currentVersion);

  /// Fetches new data
  /// Run this at startup.
  /// Downloads new dictionary data if available.
  /// First it checks how recently it attempted to do this, so we don't spam
  /// the dictionary data server.
  /// Returns true if new data was downloaded.
  Future<bool> getNewData(bool forceCheck) async {
    // Determine whether it is time to check for new dictionary data.
    int? lastCheckTime =
        sharedPreferences.getInt(KEY_LAST_DICTIONARY_DATA_CHECK_TIME);
    int now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (!(lastCheckTime == null ||
        now - DATA_CHECK_INTERVAL > lastCheckTime ||
        forceCheck)) {
      // No need to check again so soon.
      printAndLog(
          "Not checking for new dictionary data, it hasn't been long enough");
      return false;
    }

    if (forceCheck) {
      printAndLog("Forcing a check for new dictionary data");
    }

    int currentVersion =
        sharedPreferences.getInt(KEY_DICTIONARY_DATA_CURRENT_VERSION) ?? 0;

    NewData? newData = await downloadNewData(currentVersion);

    if (newData == null) {
      printAndLog("Current version ($currentVersion) is the newest data");
      // Record that we made this check so we don't check again too soon.
      await sharedPreferences.setInt(KEY_LAST_DICTIONARY_DATA_CHECK_TIME, now);
      return false;
    }

    // Assert that the data is valid. This will throw if it's not.
    loadEntriesInner(newData.data);

    // Write the data to file, which we read again afterwards to load it into
    // memory.
    await writeEntries(newData.data);

    // Now, record the new version that we downloaded.
    await sharedPreferences.setInt(
        KEY_DICTIONARY_DATA_CURRENT_VERSION, newData.newVersion);
    printAndLog(
        "Set KEY_LAST_DICTIONARY_DATA_CHECK_TIME to $now and KEY_DICTIONARY_DATA_CURRENT_VERSION to ${newData.newVersion}. Done!");

    return true;
  }

  Future<bool> updateWordsData(bool forceCheck) async {
    print("Trying to load data from the internet...");
    bool thereWasNewData = await getNewData(forceCheck);
    if (thereWasNewData) {
      printAndLog(
          "There was new data from the internet, loading it into memory...");
      var entries = await loadEntriesFromLocalStorage();
      setEntriesGlobal(entries);
    } else {
      printAndLog(
          "There was no new words data from the internet, not updating entriesGlobal");
    }
    return thereWasNewData;
  }
}

class NewData {
  /// This will be null if there is no new data.
  String data;
  int newVersion;

  NewData(this.data, this.newVersion);
}
