import 'dart:collection';
import 'package:flutter/material.dart';

import 'common.dart';
import 'entry_types.dart';
import 'globals.dart';

const String KEY_ENTRY_LIST_KEYS = "word_list_keys";

// A user created list of entries.
class EntryList {
  // TODO: Confirm that this works as intended for Sinhala and Tamil.
  // The pattern checks for all Unicode letters and numbers, spaces, comma, dot, dash, underscore, and exclamation mark.
  // If any other special character is present, it will not match and hence, the function will return false.
  static final validNameCharacters =
      RegExp(r'^[\p{L}\p{N}\s,.-_!]*$', unicode: true);

  String key;
  LinkedHashSet<Entry> entries; // Ordered by insertion order.

  EntryList(this.key, this.entries);

  @override
  String toString() {
    return getName();
  }

  // This takes in the raw string key, pulls the list of raw strings from
  // storage, and converts them into a name and a list of entries respectively.
  factory EntryList.fromRaw(String key) {
    LinkedHashSet<Entry> entries = loadEntryList(key);
    return EntryList(key, entries);
  }

  // Load up a list of entries. If the key doesn't exist, it'll just return an
  // empty list.
  static LinkedHashSet<Entry> loadEntryList(String key) {
    LinkedHashSet<Entry> entries = LinkedHashSet();
    List<String> entriesRaw = sharedPreferences.getStringList(key) ?? [];
    printAndLog("Loaded ${entriesRaw.length} entries in list $key");
    for (String s in entriesRaw) {
      // We use the one keyed by English because for this app the value returned
      // by getKey is the word / phrase in English, since that field is required
      // to be set on entries.
      Entry? matchingEntry = keyedByEnglishEntriesGlobal[s];
      if (matchingEntry != null) {
        entries.add(matchingEntry);
      } else {
        // In this case, the next time the user alters this list, the missing
        // entries will be removed from storage permanently. Otherwise we'll
        // keep filtering them out, which is no big deal.
        printAndLog(
            'Entry "$s" in entry list $key is no longer in the dictionary, removing from list (only in memory, not on disk until the list is modified)');
      }
    }
    return entries;
  }

  Widget getLeadingIcon({bool inEditMode = false}) {
    if (key == KEY_FAVOURITES_ENTRIES) {
      return const Icon(
        Icons.star,
      );
    }
    if (inEditMode) {
      return const Icon(Icons.drag_handle);
    } else {
      return const Icon(Icons.list_alt);
    }
  }

  bool canBeDeleted() {
    return !(key == KEY_FAVOURITES_ENTRIES);
  }

  static String getNameFromKey(String key) {
    if (key == KEY_FAVOURITES_ENTRIES) {
      return "Favourites";
    }
    // This - 6 comes from the length of _words
    return key.substring(0, key.length - 6).replaceAll("_", " ");
  }

  String getName() {
    return EntryList.getNameFromKey(key);
  }

  static String getKeyFromName(String name) {
    if (name.isEmpty) {
      throw "List name cannot be empty";
    }
    if (!validNameCharacters.hasMatch(name)) {
      throw "Invalid name, this should have been caught already";
    }
    return "${name}_words".replaceAll(" ", "_");
  }

  // No matter what locale they use we use the key of the entry for storage.
  Future<void> write() async {
    await sharedPreferences.setStringList(
        key, entries.map((e) => e.getKey()).toList());
  }

  Future<void> addEntry(Entry entryToAdd) async {
    entries.add(entryToAdd);
    await write();
  }

  Future<void> removeEntry(Entry entryToRemove) async {
    entries.remove(entryToRemove);
    await write();
  }
}

// This class does not deal with list names at all, only with keys.
class EntryListManager {
  LinkedHashMap<String, EntryList> entryLists; // Maintains insertion order.

  EntryListManager(this.entryLists);

  factory EntryListManager.fromStartup() {
    printAndLog("Loading entry lists...");
    List<String> entryListKeys =
        sharedPreferences.getStringList(KEY_ENTRY_LIST_KEYS) ??
            [KEY_FAVOURITES_ENTRIES];
    LinkedHashMap<String, EntryList> entryLists = LinkedHashMap();
    for (String key in entryListKeys) {
      entryLists[key] = EntryList.fromRaw(key);
    }
    printAndLog("Loaded ${entryLists.length} lists");
    return EntryListManager(entryLists);
  }

  Future<void> createEntryList(String key) async {
    if (entryLists.containsKey(key)) {
      throw "List already exists";
    }
    entryLists[key] = EntryList.fromRaw(key);
    await entryLists[key]!.write();
    await writeEntryListKeys();
  }

  Future<void> deleteEntryList(String key) async {
    entryLists.remove(key);
    await sharedPreferences.remove(key);
    await writeEntryListKeys();
  }

  Future<void> writeEntryListKeys() async {
    await sharedPreferences.setStringList(
        KEY_ENTRY_LIST_KEYS, entryLists.keys.toList());
  }

  // Given an item that moved from index prev to index current,
  // reorder the lists and persist that. Deny reordering the favourites.
  void reorder(int prev, int updated) {
    if (prev == 0 || updated == 0) {
      printAndLog(
          "Refusing to reorder with favourites list: $prev and $updated");
      return;
    }
    printAndLog("Moving item from $prev to $updated");

    MapEntry<String, EntryList> toMove = entryLists.entries.toList()[prev];

    LinkedHashMap<String, EntryList> modifiedList = LinkedHashMap();
    int i = 0;
    for (MapEntry<String, EntryList> e in entryLists.entries) {
      if (i == prev) {
        i += 1;
        continue;
      }
      if (i == updated) {
        modifiedList[toMove.key] = toMove.value;
      }
      modifiedList[e.key] = e.value;
      i += 1;
    }

    if (!modifiedList.containsKey(toMove.key)) {
      modifiedList[toMove.key] = toMove.value;
    }

    entryLists = modifiedList;
  }
}
