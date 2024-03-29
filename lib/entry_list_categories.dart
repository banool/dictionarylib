import 'dart:collection';

import 'common.dart';
import 'entry_list.dart';
import 'entry_types.dart';
import 'globals.dart';

// Entry list manager for the communityEntryListManager in globals.dart from
// dictionarylib based on the categories of the entries.
class CategoryEntryListManager implements EntryListManager {
  // Whereas LinkedHashMap maintains insertion order, the order of SplayTreeMap
  // is based on comparing the keys.
  SplayTreeMap<String, EntryList> _entryLists;

  CategoryEntryListManager(this._entryLists);

  factory CategoryEntryListManager.fromStartup() {
    SplayTreeMap<String, List<Entry>> categoryToEntries = SplayTreeMap();

    // Build up the entryies keyed by category. Because an entry can have
    // multiple categories, a single entry can appear in multiple entry lists.
    for (Entry e in entriesGlobal.cast<Entry>()) {
      for (var category in e.getCategories()) {
        var cleanCategory = removeNonMatchingCharacters(
            category, EntryList.validNameCharacters);

        if (cleanCategory == "") {
          continue;
        }

        // Suffix lengths must equal 6, so this is a short form of "_category".
        var key = EntryList.getKeyFromName(cleanCategory, suffix: "_categ");

        if (!categoryToEntries.containsKey(key)) {
          categoryToEntries[key] = [];
        }
        categoryToEntries[key]!.add(e);
      }
    }

    // Build EntryLists from the previous map.
    bool canBeEdited = false;
    SplayTreeMap<String, EntryList> entryLists = SplayTreeMap();
    for (String key in categoryToEntries.keys) {
      entryLists[key] = EntryList(
          key, LinkedHashSet.from(categoryToEntries[key]!), canBeEdited);
    }

    printAndLog(
        "Loaded ${entryLists.length} lists for the community entry list manager");
    return CategoryEntryListManager(entryLists);
  }

  @override
  LinkedHashMap<String, EntryList> getEntryLists() {
    return LinkedHashMap.from(_entryLists);
  }
}

// Helper function to remove illegal characters from the category name so we can
// use it as the key for an entry list.
String removeNonMatchingCharacters(String input, RegExp pattern) {
  // Find all matches of the pattern in the input string
  Iterable<RegExpMatch> matches = pattern.allMatches(input);

  // Concatenate all matched substrings
  String result = matches.map((m) => m.group(0)).join('');

  return result;
}
