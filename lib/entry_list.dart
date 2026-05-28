import 'dart:collection';
import 'package:flutter/material.dart';

import 'common.dart';
import 'entry_types.dart';
import 'globals.dart';
import 'l10n/app_localizations.dart';
import 'saved_video.dart';

const String KEY_ENTRY_LIST_KEYS = "word_list_keys";
const int SUFFIX_LENGTH = 6;

/// Bumped when the on-disk format for a single list's entries changes
/// in a way [EntryList.loadEntryList] needs to adapt to. Recorded
/// per-list under [_listSchemaVersionKey] after a successful migration so
/// we don't re-scan legacy items every launch.
///
/// History:
///   - implicit v1: `List<String>` of entry keys (one entry per item).
///   - v2: `List<String>` of `"<entryKey>|<videoUrl>"` (one saved video
///     per item). Legacy items are detected by absence of `|` and
///     expanded to all videos of the entry on first load.
const int listSchemaVersion = 2;

/// Per-list shared-prefs key that records the schema version of the
/// last successful migration. Lists without this key are treated as
/// pre-v2 and re-scanned for legacy items on load.
String _listSchemaVersionKey(String listKey) => '${listKey}_schemaVersion';

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

/// A user-created list of saved videos.
///
/// Storage model: each item is a [SavedVideo] = `(entryKey, videoUrl)`,
/// persisted in SharedPreferences as `"entryKey|videoUrl"`. The same
/// entry can contribute multiple saved videos, in which case the list
/// view groups them under a single entry row but the underlying
/// container preserves per-video insertion order.
class EntryList {
  // TODO: Confirm that this works as intended for Sinhala and Tamil.
  // The pattern checks for all Unicode letters and numbers, spaces, comma, dot, dash, underscore, and exclamation mark.
  // If any other special character is present, it will not match and hence, the function will return false.
  static final validNameCharacters =
      RegExp(r'^[\p{L}\p{N}\s,.-_!]*$', unicode: true);

  String key;

  /// Canonical container. Insertion-ordered set of saved videos.
  /// Owner-mode [SyncedEntryList] shares this set by reference with
  /// its wrapper so mutations are visible from both surfaces.
  LinkedHashSet<SavedVideo> savedVideos;

  bool _canBeEdited;

  EntryList(this.key, this.savedVideos, this._canBeEdited);

  @override
  String toString() {
    return getName();
  }

  /// Load this list from SharedPreferences. Performs the v1→v2
  /// migration on the fly: legacy bare-entry-key items are expanded to
  /// every video of the entry (in sub-entry / within-sub-entry order)
  /// and the migrated list is written back immediately so subsequent
  /// loads skip the work.
  factory EntryList.fromRaw(String key) {
    final saved = loadSavedVideos(key);
    return EntryList(key, saved, true);
  }

  /// Load saved videos for [key], handling the v1→v2 migration.
  ///
  /// v1 storage was `List<String>` of entry keys. v2 stores one
  /// `"entryKey|videoUrl"` per item. A list is considered already
  /// migrated when its [_listSchemaVersionKey] equals
  /// [listSchemaVersion]; otherwise legacy items are detected by
  /// absence of `|` and expanded. The migration write is fire-and-forget
  /// async — the in-memory result is correct regardless.
  static LinkedHashSet<SavedVideo> loadSavedVideos(String key) {
    final out = LinkedHashSet<SavedVideo>();
    final raw = sharedPreferences.getStringList(key) ?? const <String>[];
    final storedVersion = sharedPreferences.getInt(_listSchemaVersionKey(key));
    final alreadyMigrated = storedVersion == listSchemaVersion;
    var migratedAnything = false;
    var droppedAnything = false;

    for (final item in raw) {
      final parsed = SavedVideo.tryParse(item);
      if (parsed != null) {
        out.add(parsed);
        continue;
      }
      // Legacy item: an entry key with no separator. Expand to every
      // video of the entry. If the entry isn't in the dictionary
      // anymore (data refresh dropped it), drop the item — same
      // behaviour as the pre-refactor "entry missing" path.
      final entry = keyedByEnglishEntriesGlobal[item];
      if (entry == null) {
        printAndLog('EntryList $key: legacy entry "$item" '
            'not in dictionary; dropping');
        droppedAnything = true;
        continue;
      }
      final expanded = allVideosOf(entry);
      if (expanded.isEmpty) {
        printAndLog('EntryList $key: legacy entry "$item" has no videos; '
            'dropping');
        droppedAnything = true;
        continue;
      }
      out.addAll(expanded);
      migratedAnything = true;
    }

    if (!alreadyMigrated && (migratedAnything || droppedAnything)) {
      printAndLog('EntryList $key: migrated to schemaVersion '
          '$listSchemaVersion (expanded ${out.length} videos)');
    }

    if (!alreadyMigrated) {
      // Fire-and-forget the migration write. Even if the user is
      // currently offline / shared-prefs is being unusually slow, the
      // in-memory state is already correct, and the next mutation will
      // re-persist with the new format anyway.
      sharedPreferences.setStringList(
          key, out.map((v) => v.toStorage()).toList());
      sharedPreferences.setInt(_listSchemaVersionKey(key), listSchemaVersion);
    }
    printAndLog("Loaded ${out.length} saved videos in list $key");
    return out;
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

  /// Persist the current [savedVideos] set. Writes the schemaVersion
  /// flag alongside so a later load doesn't re-run the legacy expand.
  Future<void> write() async {
    await sharedPreferences.setStringList(
        key, savedVideos.map((v) => v.toStorage()).toList());
    await sharedPreferences.setInt(
        _listSchemaVersionKey(key), listSchemaVersion);
  }

  /// Assert that this list is not the source of an owner-mode share.
  ///
  /// Owner-mode `SyncedEntryList` wrappers share their `savedVideos` set
  /// with the underlying local list by reference (see
  /// `lib/sharing/synced_entry_list.dart`). Mutations made through the
  /// wrapper enqueue a sync op; mutations made directly on the source
  /// list — bypassing the wrapper — would NOT enqueue, and the
  /// server's view would silently diverge from the user's local one.
  void _assertNotOwnerShared() {
    assert(() {
      if (!sharing.isEnabled) return true;
      return sharing.lists.ownerForSourceKey(key) == null;
    }(),
        'EntryList "$key" is mutated directly while an owner-mode shared '
        'wrapper is observing it — go through the SyncedEntryList wrapper '
        'so the mutation enqueues a sync op (see ListsService.ownedShareFor).');
  }

  // -------- Read API --------

  /// True if [video] is saved in this list.
  bool containsVideo(SavedVideo video) => savedVideos.contains(video);

  /// True if at least one video of [entry] is saved in this list.
  /// Equivalent to "would the entry appear as a row in the list view?".
  bool containsEntry(Entry entry) {
    final key = entry.getKey();
    for (final v in savedVideos) {
      if (v.entryKey == key) return true;
    }
    return false;
  }

  /// Saved videos belonging to [entry], in insertion order. Empty when
  /// no video of the entry has been saved.
  List<SavedVideo> videosForEntry(Entry entry) {
    final key = entry.getKey();
    return [for (final v in savedVideos) if (v.entryKey == key) v];
  }

  /// All saved videos grouped by entry, in first-saved-video order.
  /// Skips saved videos whose entry isn't in the dictionary (i.e.
  /// orphaned by a data refresh) — same behaviour as v1's
  /// "missing entry" path.
  LinkedHashMap<Entry, List<SavedVideo>> get groupedByEntry {
    final out = LinkedHashMap<Entry, List<SavedVideo>>();
    for (final v in savedVideos) {
      final entry = keyedByEnglishEntriesGlobal[v.entryKey];
      if (entry == null) continue;
      out.putIfAbsent(entry, () => <SavedVideo>[]).add(v);
    }
    return out;
  }

  /// Unique entries that have at least one saved video, in
  /// first-saved-video order. Convenience around [groupedByEntry] for
  /// callers that just want "which entry rows do I render".
  LinkedHashSet<Entry> get uniqueEntries =>
      LinkedHashSet<Entry>.from(groupedByEntry.keys);

  // -------- Mutation API --------

  /// Add a single saved video. No-op if already present.
  Future<void> addVideo(SavedVideo video) async {
    _assertNotOwnerShared();
    if (!savedVideos.add(video)) return;
    await write();
  }

  Future<void> removeVideo(SavedVideo video) async {
    _assertNotOwnerShared();
    if (!savedVideos.remove(video)) return;
    await write();
  }

  /// Add every video of [entry] across its sub-entries. Used by the
  /// "save all of this entry" path and the legacy-list migration.
  Future<void> addAllVideosOfEntry(Entry entry) async {
    _assertNotOwnerShared();
    var changed = false;
    for (final v in allVideosOf(entry)) {
      if (savedVideos.add(v)) changed = true;
    }
    if (changed) await write();
  }

  /// Remove every video belonging to [entry]. Used by the list view's
  /// long-press "remove from list" affordance.
  Future<void> removeAllVideosOfEntry(Entry entry) async {
    _assertNotOwnerShared();
    final key = entry.getKey();
    final initial = savedVideos.length;
    savedVideos.removeWhere((v) => v.entryKey == key);
    if (savedVideos.length != initial) await write();
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
    await sharedPreferences.remove(_listSchemaVersionKey(key));
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
