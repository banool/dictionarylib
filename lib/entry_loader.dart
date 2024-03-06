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

  /// Try to load data from local storage. If there was an error we won't throw
  /// but instead log and return an empty set.
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
      printAndLog("Failed to load entries data from local storage: $e");
      return {};
    }

    if (data == null) {
      printAndLog("No entries data was found in local storage");
      return {};
    }

    try {
      var entries = loadEntriesInner(data);
      printAndLog("Loaded entries data from local storage");
      return entries;
    } catch (e) {
      printAndLog(
          "Failed to deserialize data from local storage, we'll try to download from the remote again: $e");
      return {};
    }
  }

  /// Set entriesGlobal and all the stuff that depends on it. Subclasses may
  /// want to override this to first call super and then update additional
  /// keyed entries globals. They might want to set the communityListManager
  /// too if relevant.
  setEntriesGlobal(Set<Entry> entries) {
    entriesGlobal = entries;

    // Update the global entries variant keyed by English.
    printAndLog("Updating keyedByEnglishEntriesGlobal");
    for (Entry e in entriesGlobal) {
      // The key is the word in English, which is always present.
      keyedByEnglishEntriesGlobal[e.getPhrase(LOCALE_ENGLISH)!] = e;
    }
    printAndLog("Updated keyedByEnglishEntriesGlobal");

    // Update the list manager.
    userEntryListManager = UserEntryListManager.fromStartup();

    printAndLog(
        "Updated entriesGlobal and all its downstream variables (super class)");
  }

  Future<void> _writeEntries(String newData) async {
    printAndLog("Writing new data to local storage");
    if (kIsWeb) {
      // If we're on web use local storage. Currently the dump file is around
      // 1mb and local storage should support 5mb per site, so this should be
      // sufficient for now: https://stackoverflow.com/q/2989284/3846032.
      // TODO: This is no longer true, the dump file is like 11mb.
      await sharedPreferences.setString(KEY_WEB_DICTIONARY_DATA, newData);
    } else {
      final path = await _dictionaryDataFilePath;
      await path.writeAsString(newData);
    }
    print("Wrote new data to local storage");
  }

  /// Private. I just can't mark it as such because subclasses don't really
  /// work with private superclass methods.
  ///
  /// This function should parse the data (probably JSON) and return a set of
  /// entries. It should not have any side effects.
  Set<Entry> loadEntriesInner(String data);

  /// Private. I just can't mark it as such because subclasses don't really
  /// work with private superclass methods.
  ///
  /// The implementor must define this. This downloads new data and returns it
  /// as a string. Likely this string is JSON. This will return None if there
  /// is no new data. If forceDownload is true it should attempt to download
  /// new data even if it seems like the current data is the latest data.
  Future<NewData?> downloadNewData(int currentVersion, bool forceDownload);

  bool _shouldCheckForNewData(int nowSecs, bool forceDownload) {
    if (forceDownload) {
      printAndLog("Forcing download of new dictionary data");
      return true;
    }
    int? lastCheckTimeSecs =
        sharedPreferences.getInt(KEY_LAST_DICTIONARY_DATA_CHECK_TIME_SECS);
    if (lastCheckTimeSecs == null) {
      print(
          "Downloading new dictionary data because it seems we've never checked before");
      return true;
    }
    if (nowSecs > (lastCheckTimeSecs + DATA_CHECK_INTERVAL)) {
      printAndLog(
          "Checking for new dictionary data because it has been long enough since the last check. Now: $nowSecs, last check: $lastCheckTimeSecs, check interval: $DATA_CHECK_INTERVAL");
      return true;
    }
    return false;
  }

  // First we check if we should check for new data based on how long ago we
  // checked. If has been long enough, or forceDownload is true, we download
  // new data. If there was no new data, the return value will be null. If
  // forceDownload was true, the response should always be non null because we
  // download the data again even if it looks like the remote data matches
  // the local data.
  Future<NewData?> _downloadNewDataIfAppropriate(bool forceDownload) async {
    // Determine whether it is time to check for new dictionary data.
    int nowSecs = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (!_shouldCheckForNewData(nowSecs, forceDownload)) {
      // No need to check again so soon.
      printAndLog(
          "Not checking for new dictionary data, it hasn't been long enough and forceDownload was false");
      return null;
    }

    int currentVersion =
        sharedPreferences.getInt(KEY_DICTIONARY_DATA_CURRENT_VERSION) ?? 0;

    return await downloadNewData(currentVersion, forceDownload);
  }

  Future<void> recordLastCheckTime() async {
    int nowSecs = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await sharedPreferences.setInt(
        KEY_LAST_DICTIONARY_DATA_CHECK_TIME_SECS, nowSecs);
    printAndLog(
        "Recording that we just checked for data by setting KEY_LAST_DICTIONARY_DATA_CHECK_TIME to $nowSecs");
  }

  // This is the top level function to call to download new data. Overall it will
  // download new data if appropriate (if it is time or forceDownload is set),
  // deserialize the data, write it to disk, and update the app state with the
  // new data. It will return the new data if it was downloaded, or null if it
  // was not. It updates the local kv data with the new version number and
  // records the time of the check.
  Future<NewData?> downloadAndApplyNewData(bool forceDownload) async {
    // Check for new data.
    NewData? newData = await _downloadNewDataIfAppropriate(forceDownload);
    if (newData == null) {
      if (forceDownload) {
        throw "forceDownload was true but no new data was downloaded, this should be impossible";
      }
      printAndLog(
          "No new data was downloaded, not updating any downstream variables");
      await recordLastCheckTime();
      return null;
    }

    // Deserialize the data before anything else.
    Set<Entry> entries = loadEntriesInner(newData.data);
    printAndLog(
        "Successfully deserialized new data from the internet, ${entries.length} entries");

    // Write the new data to disk.
    await _writeEntries(newData.data);

    // Update the app state with the new entries.
    setEntriesGlobal(entries);

    // Record the new version of data that we just downloaded. We do this right
    // at the end because if we crash before this point we will download the
    // data again next time.
    await sharedPreferences.setInt(
        KEY_DICTIONARY_DATA_CURRENT_VERSION, newData.newVersion);
    printAndLog(
        "Set KEY_DICTIONARY_DATA_CURRENT_VERSION to ${newData.newVersion}.");

    // Record that we just checked for new data.
    await recordLastCheckTime();

    print("downloadAndApplyNewData is done");

    return newData;
  }
}

class NewData {
  // Raw JSON as a string.
  String data;
  // This was the value of KEY_DICTIONARY_DATA_CURRENT_VERSION before we did
  // anything.
  int oldVersion;
  int newVersion;

  NewData(this.data, this.oldVersion, this.newVersion);

  bool newDataIsActuallyNew() => oldVersion != newVersion;
}
