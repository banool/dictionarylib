import 'dart:collection';

import 'package:flutter/material.dart';

import 'common.dart';
import 'entry_types.dart';
import 'globals.dart';
import 'l10n/app_localizations.dart';
import 'list_storage.dart';
import 'saved_video.dart';

const String KEY_ENTRY_LIST_KEYS = "word_list_keys";
const int SUFFIX_LENGTH = 6;

/// Bumped when the on-disk format for a single list's saved videos
/// changes in a way [EntryList.loadSavedVideos] needs to adapt to.
/// Recorded per-list under [listSchemaVersionKey] after a successful
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
String listSchemaVersionKey(String listKey) => '${listKey}_schemaVersion';

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
        'EntryList: legacy entry "$item" not in dictionary; dropping',
      );
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
    out.add(
      SavedVideo(
        entryKey: parsed.entryKey,
        mediaPath: path ?? value,
      ).toStorage(),
    );
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

  /// Name contained an underscore, which the storage key can't tell apart
  /// from a space. Only raised on the user-typed create/rename paths
  /// (`getKeyFromName(..., rejectUnderscores: true)`); data-derived callers
  /// (community lists, imports) tolerate underscores.
  underscore,

  /// Name can't be used. For a share, it's one a shared list may not go by
  /// (see [isReservedShareName]). For a list on the device, which can
  /// otherwise be called anything, its storage key would land on one of the
  /// app's own settings (see [storageKeyBelongsToSomethingElse]).
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
      case EntryListNameError.underscore:
        return l.listNameErrorUnderscore;
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
      case EntryListNameError.underscore:
        return "List names can't contain underscores; use a space instead";
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
        sharedPreferences.getInt(listSchemaVersionKey(key)) ?? 1;

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
      printAndLog(
        'EntryList $key: migrated v$storedVersion → '
        'v$listSchemaVersion (${out.length} saved videos)',
      );
      sharedPreferences.setStringList(
        key,
        out.map((v) => v.toStorage()).toList(),
      );
      sharedPreferences.setInt(listSchemaVersionKey(key), listSchemaVersion);
    }
    printAndLog("Loaded ${out.length} saved videos in list $key");
    return out;
  }

  Widget getLeadingIcon({bool inEditMode = false}) {
    if (inEditMode) {
      return const Icon(Icons.drag_handle);
    } else {
      return const Icon(Icons.list_alt);
    }
  }

  /// Every list can be deleted but the default one, which is what
  /// guarantees there's always a list to save into.
  bool canBeDeleted() {
    return key != readDefaultListKey();
  }

  bool canBeEdited() {
    return _canBeEdited;
  }

  /// Render a list's display name from its storage [key]. The name is
  /// stored case-/separator-preserving in the key itself, so every locale
  /// shows the name the user typed.
  ///
  /// Lossy round-trip warning: [getKeyFromName] stores spaces as
  /// underscores, and this method maps *every* underscore in the key
  /// back to a space. So a name the user typed with a literal
  /// underscore (e.g. `a_b`) is indistinguishable from a space (`a b`)
  /// in the key and will display as a space. This is deliberately left
  /// as-is — changing the storage-key format would require migrating
  /// every existing on-disk list key.
  static String getNameFromKey(String key) {
    // This - 6 comes from the length of _words
    return key.substring(0, key.length - SUFFIX_LENGTH).replaceAll("_", " ");
  }

  /// Display name for this list.
  ///
  /// A list that's shared from this device goes by the share's display
  /// name, which is what the Lists page shows and need not match the name
  /// in [key]: a list can be shared under another name, and a share can be
  /// renamed afterwards. That's resolved here, rather than left to callers
  /// to fetch the owner wrapper first, so that every screen calls a list
  /// the same thing whichever object it happens to hold.
  String getName() {
    final owned = sharing.lists.ownerForSourceKey(key);
    if (owned != null) return owned.meta.displayName;
    return EntryList.getNameFromKey(key);
  }

  static String getKeyFromName(
    String name, {
    String suffix = "_words",
    bool rejectUnderscores = false,
  }) {
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
    // constrained by length. Emoji round-trip
    // through the key untouched: they contain no space or underscore, and
    // the 6-char ASCII suffix stripped by getNameFromKey never splits a
    // surrogate pair.
    //
    // The key stores spaces as underscores, so an underscore in the name
    // is indistinguishable from a space on the way back. User-typed paths
    // pass [rejectUnderscores] to refuse the ambiguity outright; data-
    // derived callers (community lists, imports) leave it off and let the
    // underscore display as a space.
    if (rejectUnderscores && trimmed.contains('_')) {
      throw EntryListNameException(EntryListNameError.underscore, trimmed);
    }
    if (trimmed.length > maxListNameLength) {
      throw EntryListNameException(EntryListNameError.tooLong, trimmed);
    }
    return "$trimmed$suffix".replaceAll(" ", "_");
  }

  /// Persist the current [savedVideos] set. Writes the schemaVersion
  /// flag alongside so a later load doesn't re-run the legacy expand.
  Future<void> write() async {
    await sharedPreferences.setStringList(
      key,
      savedVideos.map((v) => v.toStorage()).toList(),
    );
    await sharedPreferences.setInt(
      listSchemaVersionKey(key),
      listSchemaVersion,
    );
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
    assert(
      () {
        if (!sharing.isEnabled) return true;
        return sharing.lists.ownerForSourceKey(key) == null;
      }(),
      'EntryList "$key" is mutated directly while an owner-mode shared '
      'wrapper is observing it — go through the SyncedEntryList wrapper '
      'so the mutation enqueues a sync op (see ListsService.ownedShareFor).',
    );
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
        if (v.entryKey == key) v,
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
    // ignore: prefer_collection_literals — the getter's declared type is
    // LinkedHashMap; a map literal is statically typed Map and won't return.
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
  //
  // On a list linked to the account (or shared) the mutation is handed to
  // its owner wrapper, which queues the op for the server. Every UI path
  // already mutates through the wrapper (see ListsService.writableFor), so
  // this only catches a caller that held the plain list from before the
  // link appeared (account sync links lists in the background); without
  // it the change would stay on the device and the server never hear of it.

  EntryList? _linkedWrapper() {
    if (!sharing.isEnabled) return null;
    final wrapper = sharing.lists.ownerForSourceKey(key);
    return identical(wrapper, this) ? null : wrapper;
  }

  /// Add a single saved video. No-op if already present.
  Future<void> addVideo(SavedVideo video) async {
    final wrapper = _linkedWrapper();
    if (wrapper != null) return wrapper.addVideo(video);
    _assertNotOwnerShared();
    if (!savedVideos.add(video)) return;
    await write();
  }

  Future<void> removeVideo(SavedVideo video) async {
    final wrapper = _linkedWrapper();
    if (wrapper != null) return wrapper.removeVideo(video);
    _assertNotOwnerShared();
    if (!savedVideos.remove(video)) return;
    await write();
  }

  /// Add every video of [entry] across its sub-entries. Used by the
  /// "save all of this entry" path and the legacy-list migration.
  Future<void> addAllVideosOfEntry(Entry entry) async {
    final wrapper = _linkedWrapper();
    if (wrapper != null) return wrapper.addAllVideosOfEntry(entry);
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
    final wrapper = _linkedWrapper();
    if (wrapper != null) return wrapper.removeAllVideosOfEntry(entry);
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
    // Settle what's stored before reading it: finish a key change that an
    // earlier run was cut off in the middle of, then make sure the default
    // list exists (which is also where an install from before it was an
    // ordinary list gets moved over). See list_storage.dart.
    finishInterruptedListMove();
    ensureDefaultList();
    List<String> entryListKeys = sharedPreferences.getStringList(
      KEY_ENTRY_LIST_KEYS,
    )!;
    LinkedHashMap<String, EntryList> entryLists = LinkedHashMap();
    for (String key in entryListKeys) {
      entryLists[key] = EntryList.fromRaw(key);
    }
    printAndLog("Loaded ${entryLists.length} entry lists");
    return UserEntryListManager(entryLists);
  }

  /// The list that can't be deleted. See [KEY_DEFAULT_LIST_KEY].
  String get defaultListKey => readDefaultListKey()!;

  Future<void> createEntryList(String key) async {
    if (_entryLists.containsKey(key)) {
      throw EntryListNameException(
        EntryListNameError.alreadyExists,
        EntryList.getNameFromKey(key),
      );
    }
    _checkKeyIsFree(key);
    // A new list starts out not chosen for revision, whatever a deleted
    // list of the same name once was.
    await forgetChosenForRevision(key);
    _entryLists[key] = EntryList.fromRaw(key);
    await _entryLists[key]!.write();
    await writeEntryListKeys();
  }

  Future<void> deleteEntryList(String key) async {
    if (key == defaultListKey) {
      throw StateError('The default list cannot be deleted');
    }
    _entryLists.remove(key);
    await sharedPreferences.remove(key);
    await sharedPreferences.remove(listSchemaVersionKey(key));
    await writeEntryListKeys();
    await forgetChosenForRevision(key);
  }

  /// Refuse a storage key that one of the app's own settings already uses.
  void _checkKeyIsFree(String key) {
    if (storageKeyBelongsToSomethingElse(key)) {
      throw EntryListNameException(
        EntryListNameError.reserved,
        EntryList.getNameFromKey(key),
      );
    }
  }

  /// Rename the list stored under [oldKey] to [newKey], preserving its
  /// saved videos and its position in the overview. Throws
  /// [EntryListNameException] with [EntryListNameError.alreadyExists] if a
  /// list with [newKey] already exists.
  ///
  /// Everything stored against [oldKey] moves with it — the saved videos,
  /// the revision selection, and the default-list pointer if this is the
  /// default list — so nothing is stranded under the old key (see
  /// [moveListStorage]).
  ///
  /// Not for a list that's shared from this device: that one goes by its
  /// share's name, and renaming it means renaming the share.
  Future<void> renameEntryList(String oldKey, String newKey) async {
    if (oldKey == newKey) return;
    if (_entryLists.containsKey(newKey)) {
      throw EntryListNameException(
        EntryListNameError.alreadyExists,
        EntryList.getNameFromKey(newKey),
      );
    }
    final existing = _entryLists[oldKey];
    if (existing == null) return;
    if (sharing.lists.ownerForSourceKey(oldKey) != null) {
      throw StateError('"$oldKey" is shared; rename the share instead');
    }
    _checkKeyIsFree(newKey);
    // Rebuild the map preserving insertion order, swapping the key in place
    // so the renamed list stays exactly where it was in the overview.
    // ignore: prefer_collection_literals — assigned to a LinkedHashMap field.
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
    await moveListStorage(oldKey, newKey);
  }

  Future<void> writeEntryListKeys() async {
    await sharedPreferences.setStringList(
      KEY_ENTRY_LIST_KEYS,
      _entryLists.keys.toList(),
    );
  }

  /// Put the lists in the order of [keys] (account sync brings the order
  /// the person set on another device). Keys not in [keys] keep their
  /// relative order after the rest; unknown keys are ignored. The caller
  /// persists it with [writeEntryListKeys].
  void setOrder(List<String> keys) {
    // ignore: prefer_collection_literals — assigned to a LinkedHashMap field.
    final next = LinkedHashMap<String, EntryList>();
    for (final k in keys) {
      final list = _entryLists[k];
      if (list != null) next[k] = list;
    }
    for (final e in _entryLists.entries) {
      next.putIfAbsent(e.key, () => e.value);
    }
    _entryLists = next;
  }

  // Given an item that moved from index prev to index current,
  // reorder the lists and persist that.
  void reorder(int prev, int updated) {
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
