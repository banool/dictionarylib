import 'dart:collection';
import 'package:flutter/material.dart';

import 'common.dart';
import 'entry_types.dart';
import 'globals.dart';
import 'l10n/app_localizations.dart';

const String KEY_ENTRY_LIST_KEYS = "word_list_keys";
const int SUFFIX_LENGTH = 6;

/// Why a proposed list name failed validation. The UI looks up a
/// localised message per kind via [EntryListNameException.localise].
enum EntryListNameError {
  /// Name was empty or whitespace-only.
  empty,

  /// Name contained characters outside [EntryList.validNameCharacters].
  invalidChars,

  /// Name matched one of [EntryList._reservedNamesLower].
  reserved,

  /// A list with the resulting storage key already exists.
  alreadyExists,
}

/// Validation failure thrown by [EntryList.getKeyFromName] and
/// [UserEntryListManager.createEntryList]. Carries a typed [kind] +
/// the offending [name] so callers can render a localised message —
/// raw `throw "..."` strings would bypass the l10n flow.
class EntryListNameException implements Exception {
  final EntryListNameError kind;
  final String name;
  const EntryListNameException(this.kind, this.name);

  /// Map [kind] to a localised user-facing string. The [name] is
  /// substituted for the `{name}` placeholder where present.
  String localise(BuildContext context) {
    final l = DictLibLocalizations.of(context);
    if (l == null) return _fallbackMessage();
    switch (kind) {
      case EntryListNameError.empty:
        return l.listNameErrorEmpty;
      case EntryListNameError.invalidChars:
        return l.listNameErrorInvalid;
      case EntryListNameError.reserved:
        return l.listNameErrorReserved(name);
      case EntryListNameError.alreadyExists:
        return l.listNameErrorAlreadyExists;
    }
  }

  String _fallbackMessage() {
    switch (kind) {
      case EntryListNameError.empty:
        return 'List name cannot be empty';
      case EntryListNameError.invalidChars:
        return 'Invalid list name';
      case EntryListNameError.reserved:
        return 'List name "$name" is reserved';
      case EntryListNameError.alreadyExists:
        return 'List already exists';
    }
  }

  @override
  String toString() => 'EntryListNameException($kind, "$name")';
}

// A user created list of entries.
class EntryList {
  // TODO: Confirm that this works as intended for Sinhala and Tamil.
  // The pattern checks for all Unicode letters and numbers, spaces, comma, dot, dash, underscore, and exclamation mark.
  // If any other special character is present, it will not match and hence, the function will return false.
  static final validNameCharacters =
      RegExp(r'^[\p{L}\p{N}\s,.-_!]*$', unicode: true);

  String key;
  LinkedHashSet<Entry> entries; // Ordered by insertion order.
  bool _canBeEdited;

  EntryList(this.key, this.entries, this._canBeEdited);

  @override
  String toString() {
    return getName();
  }

  // This takes in the raw string key, pulls the list of raw strings from
  // storage, and converts them into a name and a list of entries respectively.
  // This is specific to user entry lists.
  factory EntryList.fromRaw(String key) {
    LinkedHashSet<Entry> entries = loadEntryList(key);
    return EntryList(key, entries, true);
  }

  // Load up a list of entries. If the key doesn't exist, it'll just return an
  // empty list. This is specific to user entry lists, which are in local
  // storage.
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

  bool canBeEdited() {
    return _canBeEdited;
  }

  /// Render a list's display name from its storage [key]. Pass a
  /// [context] to localise the built-in favourites name; without one
  /// the favourites name falls back to English (for `toString()`,
  /// background-log lines, etc. that have no widget tree).
  ///
  /// User-derived names are stored case-/separator-preserving in the
  /// key itself, so no l10n applies — every locale shows the name the
  /// user typed.
  static String getNameFromKey(String key, [BuildContext? context]) {
    if (key == KEY_FAVOURITES_ENTRIES) {
      if (context != null) {
        final l = DictLibLocalizations.of(context);
        if (l != null) return l.favouritesListName;
      }
      return "Favourites";
    }
    // This - 6 comes from the length of _words
    return key.substring(0, key.length - SUFFIX_LENGTH).replaceAll("_", " ");
  }

  /// Display name for this list. Pass a [context] to get the
  /// localised "Favourites" — without one it falls back to English.
  String getName([BuildContext? context]) {
    return EntryList.getNameFromKey(key, context);
  }

  /// Display names that conflict with the built-in favourites list. The
  /// check is case-insensitive on the trimmed input — `"Favourites"`,
  /// `"favourites"`, `"  FAVOURITES  "` all hit.
  ///
  /// Single source of truth on the client. The share-API Worker keeps its
  /// own copy in `lists/workers/src/validation.ts` — keep them in sync.
  static const Set<String> _reservedNamesLower = {'favourites'};

  /// True if [name] (trimmed, case-insensitive) collides with a reserved
  /// list name. Use this for inline UI validation before hitting the
  /// network — the server applies the same check.
  static bool isReservedDisplayName(String name) =>
      _reservedNamesLower.contains(name.trim().toLowerCase());

  static String getKeyFromName(String name, {String suffix = "_words"}) {
    if (suffix.length != SUFFIX_LENGTH) {
      // Programmer error, not user-facing; assert in debug, ignore in
      // release. Callers control the suffix.
      throw StateError('Suffix length must be $SUFFIX_LENGTH');
    }
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw EntryListNameException(EntryListNameError.empty, trimmed);
    }
    if (!validNameCharacters.hasMatch(trimmed)) {
      throw EntryListNameException(EntryListNameError.invalidChars, trimmed);
    }
    if (isReservedDisplayName(trimmed)) {
      throw EntryListNameException(EntryListNameError.reserved, trimmed);
    }
    return "$trimmed$suffix".replaceAll(" ", "_");
  }

  // No matter what locale they use we use the key of the entry for storage.
  Future<void> write() async {
    await sharedPreferences.setStringList(
        key, entries.map((e) => e.getKey()).toList());
  }

  /// Assert that this list is not the source of an owner-mode share.
  ///
  /// Owner-mode `SyncedEntryList` wrappers share their `entries` set
  /// with the underlying local list by reference (see
  /// `lib/sharing/synced_entry_list.dart`). Mutations made through the
  /// wrapper enqueue a sync op; mutations made directly on the source
  /// list — bypassing the wrapper — would NOT enqueue, and the
  /// server's view would silently diverge from the user's local one.
  ///
  /// Every UI path that mutates a shared list is engineered to hold the
  /// wrapper rather than the source list (see
  /// [ListsService.favouritesList] / `ownedShareFor` / the lists
  /// overview's owner-share routing). This assertion is a tripwire so
  /// a regression that re-introduces a direct-mutation path fails
  /// loudly in debug builds rather than corrupting the synced mirror
  /// silently in production. Stripped from release builds.
  void _assertNotOwnerShared() {
    assert(() {
      if (!sharing.isEnabled) return true;
      return sharing.lists.ownerForSourceKey(key) == null;
    }(),
        'EntryList "$key" is mutated directly while an owner-mode shared '
        'wrapper is observing it — go through the SyncedEntryList wrapper '
        'so the mutation enqueues a sync op (see ListsService.ownedShareFor).');
  }

  Future<void> addEntry(Entry entryToAdd) async {
    _assertNotOwnerShared();
    if (!entries.add(entryToAdd)) return;
    await write();
  }

  Future<void> removeEntry(Entry entryToRemove) async {
    _assertNotOwnerShared();
    if (!entries.remove(entryToRemove)) return;
    await write();
  }
}

// Note: If you have multiple entry list managers, make sure the keys between
// their entry lists are globally unique. Each entry list manager entry list key
// should have a prefix unique to that entry list manager for example.
abstract class EntryListManager {
  LinkedHashMap<String, EntryList> getEntryLists();
}

// This class does not deal with list names at all, only with keys.
class UserEntryListManager implements EntryListManager {
  LinkedHashMap<String, EntryList> _entryLists; // Maintains insertion order.

  UserEntryListManager(this._entryLists);

  @override
  LinkedHashMap<String, EntryList> getEntryLists() {
    return _entryLists;
  }

  factory UserEntryListManager.fromStartup() {
    printAndLog("Loading entry lists...");
    List<String> entryListKeys =
        sharedPreferences.getStringList(KEY_ENTRY_LIST_KEYS) ??
            [KEY_FAVOURITES_ENTRIES];
    LinkedHashMap<String, EntryList> entryLists = LinkedHashMap();
    for (String key in entryListKeys) {
      entryLists[key] = EntryList.fromRaw(key);
    }
    printAndLog("Loaded ${entryLists.length} entry lists");
    return UserEntryListManager(entryLists);
  }

  Future<void> createEntryList(String key) async {
    if (_entryLists.containsKey(key)) {
      throw EntryListNameException(
          EntryListNameError.alreadyExists, EntryList.getNameFromKey(key));
    }
    _entryLists[key] = EntryList.fromRaw(key);
    await _entryLists[key]!.write();
    await writeEntryListKeys();
  }

  Future<void> deleteEntryList(String key) async {
    _entryLists.remove(key);
    await sharedPreferences.remove(key);
    await writeEntryListKeys();
  }

  Future<void> writeEntryListKeys() async {
    await sharedPreferences.setStringList(
        KEY_ENTRY_LIST_KEYS, _entryLists.keys.toList());
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

    MapEntry<String, EntryList> toMove = _entryLists.entries.toList()[prev];

    LinkedHashMap<String, EntryList> modifiedList = LinkedHashMap();
    int i = 0;
    for (MapEntry<String, EntryList> e in _entryLists.entries) {
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

    _entryLists = modifiedList;
  }
}

class DummyEntryListManager implements EntryListManager {
  @override
  LinkedHashMap<String, EntryList> getEntryLists() {
    return LinkedHashMap();
  }
}
