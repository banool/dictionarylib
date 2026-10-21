import 'dart:async';
import 'dart:convert';

import 'common.dart';
import 'entry_list.dart';
import 'entry_types.dart';
import 'flashcards_logic.dart' show KEY_LISTS_TO_REVIEW;
import 'globals.dart';
import 'l10n/app_localizations.dart';
import 'sharing/synced_entry_list.dart'
    show KEY_SHARED_LIST_IDS, sharedMetaStorageKey;

/// How the user's lists are laid out in shared prefs, and the two operations
/// that have to keep that layout consistent: giving a list a new storage key,
/// and making sure the default list exists.
///
/// A list's saved videos live under its storage key, which is derived from
/// its name (see [EntryList.getKeyFromName]); [KEY_ENTRY_LIST_KEYS] holds the
/// keys in display order. Several other things refer to a list by that key:
/// [KEY_DEFAULT_LIST_KEY], the revision selection, and the metadata of a
/// share made from the list. A list changes key when it's renamed, so all of
/// them have to move together.
///
/// Shared prefs has no transactions, and the app can die between any two
/// writes. Writes are persisted in the order they're issued, so what's on
/// disk afterwards is always some prefix of the sequence. Everything here is
/// written so that every such prefix is a state the next launch can carry on
/// from without losing a saved video.

/// Names the **default list**: the one list that exists from first launch and
/// can't be deleted, so there's always somewhere to save a sign. It starts
/// out called "Favourites" and is otherwise an ordinary list — stored under a
/// key derived from its name like any other, and just as renamable,
/// reorderable and shareable. This pointer is all that sets it apart, and it
/// follows the list through a rename.
const String KEY_DEFAULT_LIST_KEY = 'default_list_key';

/// Journal of a list changing storage key, as a JSON `[oldKey, newKey]`.
/// Written before the first step of the change and removed after the last,
/// so a launch that finds it knows a change was cut short and which one.
const String KEY_LIST_KEY_MOVE = 'list_key_move';

/// Where the built-in favourites list used to be stored, back when it was
/// recognised by this fixed key rather than being an ordinary list (and, in
/// the earliest versions, where the app kept its only list). Only
/// [ensureDefaultList], which moves it out, has any business reading this.
const String legacyFavouritesListKey = 'favourites_words';

/// The default list's storage key. Null only before [ensureDefaultList] has
/// run, which the list manager does before it loads anything.
String? readDefaultListKey() =>
    sharedPreferences.getString(KEY_DEFAULT_LIST_KEY);

/// What the default list is called when it's created: "Favourites" in the
/// language the app starts in. After that it's the user's to rename, and it
/// no longer follows the app's language.
String startingDefaultListName() {
  try {
    return lookupDictLibLocalizations(startingLocale).favouritesListName;
  } catch (_) {
    // A locale the library has no strings for.
    return lookupDictLibLocalizations(LOCALE_ENGLISH).favouritesListName;
  }
}

/// Make sure the default list exists and [KEY_DEFAULT_LIST_KEY] names it,
/// and return its key. Call after [finishInterruptedListMove].
///
/// On nearly every launch this finds both in place and does nothing. The
/// cases where it has work to do:
///
///  * **An install from before the default list was an ordinary list.** The
///    built-in favourites list sits under [legacyFavouritesListKey]. It is
///    moved to the key for [startingDefaultListName] — the name the user has
///    been seeing — taking its saved videos, its place in the order, its
///    revision selection and any share made from it along.
///  * **A new install.** The same, with nothing to take along: the list
///    starts out empty under the key for [startingDefaultListName].
///  * **A pointer that's missing or names no list.** Not reachable through
///    the app, but cheap to recover from: the first list becomes the default.
///
/// Every write lands in the shared-prefs cache before this returns, so the
/// lists can be loaded straight afterwards.
String ensureDefaultList() {
  final prefs = sharedPreferences;
  final index = prefs.getStringList(KEY_ENTRY_LIST_KEYS);
  final pointer = prefs.getString(KEY_DEFAULT_LIST_KEY);
  if (pointer != null && index != null && index.contains(pointer)) {
    return pointer;
  }

  final writes = <Future<bool>>[];
  final String key;
  // An index that was never written is how the old layout said "just the
  // built-in list": it was only written once a list was created, deleted,
  // renamed or reordered.
  final hasLegacyList =
      pointer == null &&
      (index == null || index.contains(legacyFavouritesListKey));
  if (hasLegacyList) {
    final others = [...?index]..remove(legacyFavouritesListKey);
    key = _freeKeyForName(startingDefaultListName(), taken: others);
    // A new install comes through here as well: it is the old layout with
    // nothing in it yet. One path for both means a share or a revision
    // selection that names the built-in list is carried over even when
    // nothing was ever stored for the list itself.
    printAndLog('Setting up the default list as $key');
    if (key == legacyFavouritesListKey) {
      // Already where it would go (no starting name maps to this key today).
      writes.add(prefs.setStringList(KEY_ENTRY_LIST_KEYS, [key, ...others]));
      writes.add(prefs.setString(KEY_DEFAULT_LIST_KEY, key));
    } else {
      _startMove(legacyFavouritesListKey, key, writes);
      _applyMove(legacyFavouritesListKey, key, writes);
    }
  } else if (index != null && index.isNotEmpty) {
    key = index.first;
    printAndLog('Default list pointer was "$pointer"; now $key');
    writes.add(prefs.setString(KEY_DEFAULT_LIST_KEY, key));
  } else {
    key = _freeKeyForName(startingDefaultListName(), taken: const []);
    printAndLog('No lists stored; creating the default list as $key');
    _createEmptyList(key, writes);
    writes.add(prefs.setStringList(KEY_ENTRY_LIST_KEYS, [key]));
    writes.add(prefs.setString(KEY_DEFAULT_LIST_KEY, key));
  }
  unawaited(_settled(writes));
  return key;
}

/// Move the list stored under [oldKey] to [newKey], along with everything
/// that refers to it by key: its place in the index, the default-list
/// pointer, the revision selection, and the source of a share made from it.
/// The caller guarantees [oldKey] is a stored list and [newKey] isn't.
///
/// The cache reflects the whole move by the time this returns; the future
/// completes once the writes have reached the platform.
Future<void> moveListStorage(String oldKey, String newKey) {
  final writes = <Future<bool>>[];
  _startMove(oldKey, newKey, writes);
  _applyMove(oldKey, newKey, writes);
  return _settled(writes);
}

/// Carry on from a list key change that an earlier run started and didn't
/// finish. Call before anything reads the lists. A no-op when the last run
/// left nothing half-done, which is nearly always.
void finishInterruptedListMove() {
  final prefs = sharedPreferences;
  final raw = prefs.getString(KEY_LIST_KEY_MOVE);
  if (raw == null) return;
  final writes = <Future<bool>>[];
  final move = _parseMove(raw);
  // A missing index means the built-in list alone (see [ensureDefaultList]).
  final index =
      prefs.getStringList(KEY_ENTRY_LIST_KEYS) ??
      const [legacyFavouritesListKey];
  if (move == null) {
    printAndLog('Dropping an unreadable list key move: $raw');
    writes.add(prefs.remove(KEY_LIST_KEY_MOVE));
  } else if (index.contains(move.oldKey) != index.contains(move.newKey)) {
    // Exactly one of the two keys is a list, which is what a move looks like
    // part-way through: carry it the rest of the way.
    printAndLog('Finishing list key move ${move.oldKey} -> ${move.newKey}');
    _applyMove(move.oldKey, move.newKey, writes);
  } else {
    // Both are lists, or neither is. That isn't a move in progress, so
    // there's nothing here to finish and nothing it's safe to touch.
    printAndLog('Dropping a stale list key move: $raw');
    writes.add(prefs.remove(KEY_LIST_KEY_MOVE));
  }
  unawaited(_settled(writes));
}

/// Open the journal for a new move. Anything already stored against
/// [newKey] belongs to no list (the caller checked the index), so it's
/// debris, and it's cleared first: once the journal says a move to [newKey]
/// is underway, what's found there is taken to be the moved list's and is
/// never overwritten.
void _startMove(String oldKey, String newKey, List<Future<bool>> writes) {
  final prefs = sharedPreferences;
  if (prefs.containsKey(newKey)) {
    writes.add(prefs.remove(newKey));
  }
  if (prefs.containsKey(listSchemaVersionKey(newKey))) {
    writes.add(prefs.remove(listSchemaVersionKey(newKey)));
  }
  _forgetChosenForRevision(newKey, writes);
  writes.add(prefs.setString(KEY_LIST_KEY_MOVE, jsonEncode([oldKey, newKey])));
}

/// Take [key] out of the revision selection, if it's in there.
///
/// The selection is stored by key and outlives the lists it names: one that
/// has been deleted leaves its key behind, where it's ignored — until
/// another list comes to have that key, by being created or renamed, and
/// finds itself chosen for revision without anyone choosing it. So a key is
/// forgotten when its list goes, and again before a list takes it up.
void _forgetChosenForRevision(String key, List<Future<bool>> writes) {
  final chosen = sharedPreferences.getStringList(KEY_LISTS_TO_REVIEW);
  if (chosen == null || !chosen.contains(key)) return;
  writes.add(
    sharedPreferences.setStringList(KEY_LISTS_TO_REVIEW, [
      for (final k in chosen)
        if (k != key) k,
    ]),
  );
}

/// See [_forgetChosenForRevision]. For a list that has just been deleted, or
/// is about to be created.
Future<void> forgetChosenForRevision(String key) {
  final writes = <Future<bool>>[];
  _forgetChosenForRevision(key, writes);
  return _settled(writes);
}

/// True if something other than a list's saved videos is stored under
/// [key]. A list's key is derived from its name, and a few of the app's own
/// settings have keys of the same shape ("search for" lands on the key of
/// the search-direction switch), so a list can't be allowed to take one.
bool storageKeyHoldsSomethingElse(String key) {
  final stored = sharedPreferences.get(key);
  return stored != null && stored is! List;
}

/// The body of a move, from wherever it had got to. Every step checks what
/// is already in place, so running this again after any prefix of its own
/// writes ends in the same state.
void _applyMove(String oldKey, String newKey, List<Future<bool>> writes) {
  final prefs = sharedPreferences;

  // The saved videos, format version first so the videos never sit under the
  // new key without it. Left alone if they're already there: after an
  // interrupted move the new key may hold a newer copy than the old one.
  if (!prefs.containsKey(newKey)) {
    final version = prefs.getInt(listSchemaVersionKey(oldKey));
    if (version != null) {
      writes.add(prefs.setInt(listSchemaVersionKey(newKey), version));
    }
    writes.add(
      prefs.setStringList(
        newKey,
        prefs.getStringList(oldKey) ?? const <String>[],
      ),
    );
  }

  // A share made from the list finds it by key. This has to be in place
  // before sharing starts up: an owner share whose source list is missing is
  // dropped, along with its stored metadata.
  for (final id
      in prefs.getStringList(KEY_SHARED_LIST_IDS) ?? const <String>[]) {
    final metaKey = sharedMetaStorageKey(id);
    final rewritten = _withSourceKey(prefs.getString(metaKey), oldKey, newKey);
    if (rewritten != null) writes.add(prefs.setString(metaKey, rewritten));
  }

  final chosen = prefs.getStringList(KEY_LISTS_TO_REVIEW);
  if (chosen != null && chosen.contains(oldKey)) {
    writes.add(
      prefs.setStringList(KEY_LISTS_TO_REVIEW, [
        for (final k in chosen) k == oldKey ? newKey : k,
      ]),
    );
  }

  // Before there was a pointer, the default list was the one under the
  // built-in key.
  final pointer = prefs.getString(KEY_DEFAULT_LIST_KEY);
  final wasDefault = pointer == null
      ? oldKey == legacyFavouritesListKey
      : pointer == oldKey;
  if (wasDefault) {
    writes.add(prefs.setString(KEY_DEFAULT_LIST_KEY, newKey));
  }

  final index =
      prefs.getStringList(KEY_ENTRY_LIST_KEYS) ??
      const [legacyFavouritesListKey];
  if (index.contains(oldKey)) {
    writes.add(
      prefs.setStringList(KEY_ENTRY_LIST_KEYS, [
        for (final k in index) k == oldKey ? newKey : k,
      ]),
    );
  }

  // Nothing refers to the old key any more, so what's under it can go.
  if (prefs.containsKey(oldKey)) {
    writes.add(prefs.remove(oldKey));
  }
  if (prefs.containsKey(listSchemaVersionKey(oldKey))) {
    writes.add(prefs.remove(listSchemaVersionKey(oldKey)));
  }
  writes.add(prefs.remove(KEY_LIST_KEY_MOVE));
}

void _createEmptyList(String key, List<Future<bool>> writes) {
  final prefs = sharedPreferences;
  writes.add(prefs.setInt(listSchemaVersionKey(key), listSchemaVersion));
  writes.add(prefs.setStringList(key, const <String>[]));
}

/// The storage key for a list called [name], or for "[name] 2", "[name] 3"
/// and so on if lists with the earlier keys exist.
String _freeKeyForName(String name, {required List<String> taken}) {
  var candidate = name;
  for (var n = 2; ; n++) {
    final key = EntryList.getKeyFromName(candidate);
    if (!taken.contains(key)) return key;
    candidate = '$name $n';
  }
}

({String oldKey, String newKey})? _parseMove(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is List &&
        decoded.length == 2 &&
        decoded[0] is String &&
        decoded[1] is String) {
      return (oldKey: decoded[0] as String, newKey: decoded[1] as String);
    }
  } on FormatException {
    // Falls through.
  }
  return null;
}

/// [rawMeta] (a share's stored metadata) with its source list key changed
/// from [oldKey] to [newKey], or null if it isn't a share of that list. Works
/// on the raw JSON rather than through [SyncedListMeta] so that fields this
/// build doesn't know about survive the rewrite.
String? _withSourceKey(String? rawMeta, String oldKey, String newKey) {
  if (rawMeta == null) return null;
  final Object? decoded;
  try {
    decoded = jsonDecode(rawMeta);
  } on FormatException {
    return null;
  }
  if (decoded is! Map<String, dynamic> || decoded['sourceLocalKey'] != oldKey) {
    return null;
  }
  decoded['sourceLocalKey'] = newKey;
  return jsonEncode(decoded);
}

/// Completes when [writes] have all reached the platform. A write that
/// fails is logged rather than thrown: the cache already holds the new
/// state, so the session carries on, and the next launch picks up from
/// whatever did reach disk.
Future<void> _settled(List<Future<bool>> writes) async {
  try {
    final results = await Future.wait(writes);
    if (results.contains(false)) {
      printAndLog('A list storage write was not persisted');
    }
  } catch (e) {
    printAndLog('A list storage write failed: $e');
  }
}
