import 'dart:collection';

import 'common.dart';
import 'entry_list.dart';
import 'entry_types.dart';
import 'globals.dart';
import 'saved_video.dart';

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
        // Category names come from the dictionary data, not user input, but
        // they run through the same key derivation as user lists — so any
        // printable text (emoji included) is preserved. Skip a category only
        // when it can't form a valid list name (empty/whitespace, too long,
        // or the reserved favourites name); getKeyFromName throws in those
        // cases. Suffix length must equal 6, so "_categ" is short for
        // "_category".
        String key;
        try {
          key = EntryList.getKeyFromName(category, suffix: "_categ");
        } on EntryListNameException {
          continue;
        }

        if (!categoryToEntries.containsKey(key)) {
          categoryToEntries[key] = [];
        }
        categoryToEntries[key]!.add(e);
      }
    }

    // Build EntryLists from the previous map. Each entry is expanded
    // to every video across its sub-entries — same semantics as the
    // v1→v2 list migration: a "community list of entries" becomes a
    // community list of every video those entries contain.
    bool canBeEdited = false;
    // Case-insensitive key order so the community lists read alphabetically
    // rather than capitals-first (ASCII) order.
    SplayTreeMap<String, EntryList> entryLists =
        SplayTreeMap(compareDisplayNames);
    for (String key in categoryToEntries.keys) {
      final saved = LinkedHashSet<SavedVideo>();
      for (final e in categoryToEntries[key]!) {
        saved.addAll(allVideosOf(e));
      }
      entryLists[key] = EntryList(key, saved, canBeEdited);
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
