import 'dart:collection';
import 'package:flutter/material.dart';

import 'common.dart';
import 'entry_types.dart';
import 'globals.dart';
import 'l10n/app_localizations.dart';
import 'saved_video.dart';

const String KEY_ENTRY_LIST_KEYS = "word_list_keys";
const int SUFFIX_LENGTH = 6;

/// Bumped when the on-disk format for a single list's saved videos
/// changes in a way [EntryList.loadSavedVideos] needs to adapt to.
/// Recorded per-list under [_listSchemaVersionKey] after a successful
/// migration so we don't re-scan / re-rewrite every launch.
///
/// History (each step is applied in order by [_migrateRawList], so a list
/// at any older version converges to the current one):
///   - v1: `List<String>` of entry keys (one whole entry per item).
///   - v2: `List<String>` of `"<entryKey>|<videoUrl>"` (one saved video
///     per item, the video half a fully-qualified URL). The v1→v2 step
///     expands each legacy entry key to every video of the entry.
///   - v3: `List<String>` of `"<entryKey>|<mediaPath>"` — same per-video
///     shape, but the video half is now the media **path** (its stable
///     identity — see [SavedVideo]), so a saved video survives the
///     content moving between hosts / CDNs. The v2→v3 step strips the
///     serving base off each stored URL (see [mediaPathForUrl]).
///
/// To add a v(N)→v(N+1) migration: bump [listSchemaVersion], add a
/// `_migrateListV{N}toV{N+1}` that maps the raw `List<String>` forward,
/// and wire it into [_migrateRawList]'s switch.
const int listSchemaVersion = 3;

/// Per-list shared-prefs key that records the schema version of the last
/// successful migration. Lists without this key are treated as v1 and
/// stepped all the way forward on load.
String _listSchemaVersionKey(String listKey) => '${listKey}_schemaVersion';

/// Upgrade a list's raw stored `List<String>` from [fromVersion] to the
/// current [listSchemaVersion], applying one ordered step at a time. Each
/// step takes the previous version's on-disk shape and returns the next
/// version's. Pure (no I/O) so it's trivially testable; the caller
/// persists the result.
List<String> _migrateRawList(List<String> raw, int fromVersion) {
  var working = raw;
  for (var v = fromVersion; v < listSchemaVersion; v++) {
    switch (v) {
      case 1:
        working = _migrateListV1toV2(working);
        break;
      case 2:
        working = _migrateListV2toV3(working);
        break;
    }
  }
  return working;
}

/// v1→v2: expand each bare entry key to one `"<entryKey>|<videoUrl>"`
/// item per video of the entry (full URLs — the v2 shape), in sub-entry /
/// within-sub-entry order. Items already in `"<entryKey>|..."` shape (a
/// partially-rolled-out v2 write) pass through untouched. Entries no
/// longer in the dictionary, or with no videos, are dropped — the same
/// "entry missing" behaviour the pre-per-video loader had.
List<String> _migrateListV1toV2(List<String> raw) {
  final out = <String>[];
  for (final item in raw) {
    if (item.contains(SavedVideo.storageSeparator)) {
      out.add(item); // already v2+.
      continue;
    }
    final entry = keyedByEnglishEntriesGlobal[item];
    if (entry == null) {
      printAndLog(
          'EntryList: legacy entry "$item" not in dictionary; dropping');
      continue;
    }
    for (final sub in entry.getSubEntries()) {
      // getMedia() returns paths; resolve to the v2 full-URL shape so the
      // v2→v3 step below can strip it back down uniformly.
      for (final path in sub.getMedia()) {
        out.add('$item${SavedVideo.storageSeparator}${mediaUrlForPath(path)}');
      }
    }
  }
  return out;
}

/// v2→v3: rewrite each `"<entryKey>|<videoUrl>"` to
/// `"<entryKey>|<mediaPath>"` by stripping the serving base off the URL
/// (see [mediaPathForUrl]). An item whose video half isn't an absolute
/// URL is already a path and passes through. A URL not under any known
/// base (orphaned, or an unexpected host) is kept as-is rather than
/// dropped — it simply won't resolve for display, exactly as before, and
/// we avoid silently deleting a user's save.
List<String> _migrateListV2toV3(List<String> raw) {
  final out = <String>[];
  for (final item in raw) {
    final parsed = SavedVideo.tryParse(item);
    if (parsed == null) continue;
    final value = parsed.mediaPath;
    if (!_looksAbsoluteUrl(value)) {
      out.add(item); // already a path.
      continue;
    }
    final path = mediaPathForUrl(value);
    out.add(SavedVideo(entryKey: parsed.entryKey, mediaPath: path ?? value)
        .toStorage());
  }
  return out;
}

bool _looksAbsoluteUrl(String s) =>
    s.startsWith('http://') || s.startsWith('https://');

/// Why a proposed list name failed validation. The UI looks up a
/// localised message per kind via [EntryListNameException.localise].
enum EntryListNameError {
  /// Name was empty or whitespace-only.
  empty,

  /// Name contained characters outside the old allowed-character whitelist.
  /// No longer produced by [EntryList.getKeyFromName] (which now accepts
  /// any printable text); kept for compatibility.
  invalidChars,

  /// Name exceeded [maxListNameLength] characters.
  tooLong,

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
      case EntryListNameError.tooLong:
        return l.listNameErrorTooLong(maxListNameLength);
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
      case EntryListNameError.tooLong:
        return 'List name is too long (max $maxListNameLength characters)';
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
/// Storage model: each item is a [SavedVideo] = `(entryKey, mediaPath)`,
/// persisted in SharedPreferences as `"entryKey|mediaPath"`. The same
/// entry can contribute multiple saved videos, in which case the list
/// view groups them under a single entry row but the underlying
/// container preserves per-video insertion order.
class EntryList {
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
  /// migrations on the fly (see [listSchemaVersion] / [_migrateRawList]):
  /// the stored form is stepped forward and written back immediately so
  /// subsequent loads skip the work.
  factory EntryList.fromRaw(String key) {
    final saved = loadSavedVideos(key);
    return EntryList(key, saved, true);
  }

  /// Load the saved videos for [key], applying ordered schema migrations
  /// from the stored version up to [listSchemaVersion]. A list with no
  /// recorded version is treated as v1 (the pre-per-video format) and
  /// stepped all the way forward; see [_migrateRawList] for the steps.
  /// The migration write is fire-and-forget — the returned in-memory set
  /// is authoritative regardless of whether the write lands.
  static LinkedHashSet<SavedVideo> loadSavedVideos(String key) {
    final raw = sharedPreferences.getStringList(key) ?? const <String>[];
    // Absent flag ⇒ v1 (the pre-per-video format). Step forward from there.
    final storedVersion =
        sharedPreferences.getInt(_listSchemaVersionKey(key)) ?? 1;

    final migrated = storedVersion < listSchemaVersion
        ? _migrateRawList(raw, storedVersion)
        : raw;

    final out = LinkedHashSet<SavedVideo>();
    for (final item in migrated) {
      final parsed = SavedVideo.tryParse(item);
      if (parsed != null) out.add(parsed);
    }

    if (storedVersion != listSchemaVersion) {
      // Persist the migrated, de-duplicated form and stamp the version so
      // the next launch is a plain read. Fire-and-forget: the in-memory
      // result above is already authoritative.
      printAndLog('EntryList $key: migrated v$storedVersion → '
          'v$listSchemaVersion (${out.length} saved videos)');
      sharedPreferences.setStringList(
          key, out.map((v) => v.toStorage()).toList());
      sharedPreferences.setInt(_listSchemaVersionKey(key), listSchemaVersion);
    }
    printAndLog("Loaded ${out.length} saved videos in list $key");
    return out;
  }

  Widget getLeadingIcon({bool inEditMode = false}) {
    if (key == KEY_FAVOURITES_ENTRIES) {
      // The favourites star uses the warm accent (gold) colour.
      return Builder(
          builder: (context) =>
              Icon(Icons.star, color: Theme.of(context).colorScheme.secondary));
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
  ///
  /// Lossy round-trip warning: [getKeyFromName] stores spaces as
  /// underscores, and this method maps *every* underscore in the key
  /// back to a space. So a name the user typed with a literal
  /// underscore (e.g. `a_b`) is indistinguishable from a space (`a b`)
  /// in the key and will display as a space. This is deliberately left
  /// as-is — changing the storage-key format would require migrating
  /// every existing on-disk list key.
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
  /// own copy in `workers/src/validation.ts` in the private backend repo — keep them in sync.
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
    // Any printable text is allowed (emoji included) — the name is only
    // constrained by length and the reserved-name check, matching the
    // shared-list rule in sharing/share_dialog.dart. Emoji round-trip
    // through the key untouched: they contain no space or underscore, and
    // the 6-char ASCII suffix stripped by getNameFromKey never splits a
    // surrogate pair.
    if (trimmed.length > maxListNameLength) {
      throw EntryListNameException(EntryListNameError.tooLong, trimmed);
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
    return [
      for (final v in savedVideos)
        if (v.entryKey == key) v
    ];
  }

  /// True when *every* video of [entry] is already saved in this list, i.e.
  /// there's nothing left to add for it. An entry with no videos is never
  /// "fully contained" (there's nothing to contain). Used by the list-edit
  /// "add" search to keep showing partially-saved entries.
  bool containsAllVideosOf(Entry entry) {
    final all = allVideosOf(entry);
    if (all.isEmpty) return false;
    for (final v in all) {
      if (!savedVideos.contains(v)) return false;
    }
    return true;
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

  /// Rename the list stored under [oldKey] to [newKey], preserving its
  /// saved videos and its position in the overview. The favourites list
  /// can't be renamed (its key is fixed). Throws
  /// [EntryListNameException] with [EntryListNameError.alreadyExists] if a
  /// list with [newKey] already exists.
  ///
  /// Moves the persisted entries (and schema-version flag) from [oldKey]
  /// to [newKey] on disk so nothing is stranded under the old key.
  Future<void> renameEntryList(String oldKey, String newKey) async {
    if (oldKey == newKey) return;
    if (oldKey == KEY_FAVOURITES_ENTRIES) {
      throw EntryListNameException(
          EntryListNameError.reserved, EntryList.getNameFromKey(oldKey));
    }
    if (_entryLists.containsKey(newKey)) {
      throw EntryListNameException(
          EntryListNameError.alreadyExists, EntryList.getNameFromKey(newKey));
    }
    final existing = _entryLists[oldKey];
    if (existing == null) return;
    // Rebuild the map preserving insertion order, swapping the key in place
    // so the renamed list stays exactly where it was in the overview.
    final rebuilt = LinkedHashMap<String, EntryList>();
    for (final e in _entryLists.entries) {
      if (e.key == oldKey) {
        existing.key = newKey;
        rebuilt[newKey] = existing;
      } else {
        rebuilt[e.key] = e.value;
      }
    }
    _entryLists = rebuilt;
    // Persist the entries under the new key, then clear the old key.
    await existing.write();
    await sharedPreferences.remove(oldKey);
    await sharedPreferences.remove(_listSchemaVersionKey(oldKey));
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
