import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';

import '../common.dart';
import '../entry_list.dart';
import '../entry_types.dart';
import '../globals.dart';
import 'sync_api.dart';

/// Top-level SharedPreferences key — the index of synced list IDs.
const String KEY_SHARED_LIST_IDS = 'shared_list_ids';

/// Top-level SharedPreferences key — stable per-install client UUID.
/// Used as the `x-client-id` on /sync calls so the server (or a future
/// audit query) can attribute ops to a specific device.
const String KEY_SHARED_CLIENT_ID = 'shared_client_id';

/// Schema version persisted in each list's meta blob. Bump when a
/// future change to [SyncedListMeta.toJson] becomes load-incompatible
/// so [SyncedEntryList.loadFromRaw] can detect-and-drop a stale blob
/// rather than throw or load it wrong.
const int sharedSchemaVersion = 1;

/// Per-list payload key, used by subscriber- and editor-side mirrors.
/// Owner lists don't get their own payload storage — their entries live
/// in the local source list that was shared (see [SyncedEntryList.owner]).
String sharedPayloadStorageKey(String listId) => 'shared_${listId}_words';

/// Per-list metadata key.
String sharedMetaStorageKey(String listId) => 'shared_${listId}_meta';

/// Role this device plays for a given synced list.
enum ListRole {
  /// User created the list. Has delete + member-management rights.
  owner,

  /// User has been added to the list as an editor by its owner. Can
  /// add/remove entries and rename.
  editor,

  /// User has subscribed via a share link. Read-only.
  subscriber,
}

/// One place that maps a [SyncedListMeta]'s state to the icon every
/// UI surface uses for that state. Without a single source of truth
/// `Icons.cloud_off` ended up meaning "orphaned" in some places and
/// "subscribed" in others; centralising here keeps the mapping
/// honest:
///   - **owner**     `cloud_upload` while pending, otherwise
///                   `cloud_done` (or `cloud_off` if orphaned).
///   - **editor**    `cloud_upload` while pending, otherwise
///                   `edit_note` (or `cloud_off` if orphaned).
///   - **subscriber** `cloud_download` (or `cloud_off` if orphaned).
///
/// "Pending" only applies to editor-class roles; subscribers can't
/// produce pending ops.
IconData iconForSharedList(SyncedListMeta meta) {
  if (meta.orphaned) return Icons.cloud_off;
  final hasPending = meta.pendingOps.isNotEmpty;
  switch (meta.role) {
    case ListRole.owner:
      return hasPending ? Icons.cloud_upload : Icons.cloud_done;
    case ListRole.editor:
      return hasPending ? Icons.cloud_upload : Icons.edit_note;
    case ListRole.subscriber:
      return Icons.cloud_download;
  }
}

/// One client-side queued operation, persisted in the meta JSON so it
/// survives app death + offline periods. Server-assigned `seq` is not
/// stored here — once the server applies the op, the entry is dropped
/// from the queue.
class PendingOp {
  /// Client-generated UUID; the server's dedupe key on retries.
  final String opId;

  /// Op type — matches the server's `OpType` enum verbatim
  /// (`addEntry`, `removeEntry`, etc.).
  final String type;

  /// Op-specific arguments.
  final Map<String, dynamic> args;

  /// Unix seconds when the user made this edit. Advisory only — server
  /// never uses this for ordering — kept for any future "edited 2
  /// minutes ago" UI rendered from the op log.
  final int clientTs;

  PendingOp({
    required this.opId,
    required this.type,
    required this.args,
    required this.clientTs,
  });

  Map<String, dynamic> toJson() => {
        'opId': opId,
        'type': type,
        'args': args,
        'clientTs': clientTs,
      };

  factory PendingOp.fromJson(Map<String, dynamic> json) => PendingOp(
        opId: json['opId'] as String,
        type: json['type'] as String,
        args: Map<String, dynamic>.from(json['args'] as Map),
        clientTs: json['clientTs'] as int,
      );
}

/// Mutable per-list metadata persisted alongside the entry payload.
class SyncedListMeta {
  String listId;
  String displayName;
  ListRole role;

  /// Monotonic server sequence the client has seen. Sent on /sync as
  /// `lastKnownSeq`; the server returns ops with seq > this. Bumped
  /// to `appliedSeq` after a successful /sync.
  int lastKnownSeq;

  /// Subscriber-poll cache header. Set on each successful GET; sent
  /// as `If-None-Match` on the next poll for cheap 304s. Editor and
  /// owner lists go through /sync and don't use this.
  String? etag;

  /// Wall-clock seconds of the last successful round-trip with the
  /// server. Drives "synced N minutes ago" UI.
  int? lastSyncedAt;

  /// Wall-clock seconds the server itself last mutated this list.
  /// For subscribers, sourced from `Last-Modified`. For editor/owner,
  /// from snapshot.updatedAt.
  int? serverUpdatedAt;

  /// True once the server has 404/410/403'd this list. Stops sync
  /// attempts; UI surfaces a "no longer available" affordance.
  bool orphaned;

  /// For owner lists: the local list ID whose entries are the source
  /// of truth for this share. Owners always have a local source list
  /// — the share is just a publication of it. Null for editor and
  /// subscriber lists, which carry their own mirror.
  String? sourceLocalKey;

  /// FIFO queue of locally-applied-but-not-yet-server-acked ops.
  /// The engine flushes these to the server on every sync attempt;
  /// they survive app kills via the persisted meta JSON. Always empty
  /// for subscriber lists.
  ///
  /// Always a mutable list — never assigned to `const []`. See
  /// [SyncedListMeta.fromJson] for the fallback.
  List<PendingOp> pendingOps;

  /// Cached members directory from the last /sync or /state response.
  /// Lets the UI render the owner / editors with display names while
  /// offline. Null for subscriber lists (the public payload doesn't
  /// carry member identity).
  MembersBlock? cachedMembers;

  SyncedListMeta({
    required this.listId,
    required this.displayName,
    required this.role,
    required this.lastKnownSeq,
    required this.etag,
    required this.lastSyncedAt,
    required this.serverUpdatedAt,
    required this.orphaned,
    this.sourceLocalKey,
    List<PendingOp>? pendingOps,
    this.cachedMembers,
  }) : pendingOps = pendingOps ?? <PendingOp>[];

  Map<String, dynamic> toJson() => {
        'schemaVersion': sharedSchemaVersion,
        'listId': listId,
        'displayName': displayName,
        'role': role.name,
        'lastKnownSeq': lastKnownSeq,
        'etag': etag,
        'lastSyncedAt': lastSyncedAt,
        'serverUpdatedAt': serverUpdatedAt,
        'orphaned': orphaned,
        'sourceLocalKey': sourceLocalKey,
        'pendingOps': pendingOps.map((o) => o.toJson()).toList(),
        'cachedMembers': cachedMembers?.toJson(),
      };

  /// Returns null if the persisted blob has a [schemaVersion] this build
  /// doesn't recognise, or names a role this build doesn't know. The
  /// caller treats that the same as a parse failure — the entry is
  /// dropped from the index and its shared-prefs keys are GC'd. A
  /// missing `schemaVersion` (pre-versioning blobs) is treated as
  /// version 1 for forward compatibility.
  static SyncedListMeta? fromJson(Map<String, dynamic> json) {
    final v = json['schemaVersion'] as int? ?? sharedSchemaVersion;
    if (v != sharedSchemaVersion) {
      printAndLog('SyncedListMeta.fromJson: unsupported schemaVersion $v '
          '(build supports $sharedSchemaVersion); dropping blob');
      return null;
    }
    final roleName = json['role'];
    final role = ListRole.values
        .where((r) => r.name == roleName)
        .cast<ListRole?>()
        .firstWhere((_) => true, orElse: () => null);
    if (role == null) {
      printAndLog('SyncedListMeta.fromJson: unknown role "$roleName"; '
          'dropping blob');
      return null;
    }
    final cachedMembersRaw = json['cachedMembers'] as Map<String, dynamic>?;
    return SyncedListMeta(
      listId: json['listId'] as String,
      displayName: json['displayName'] as String,
      role: role,
      lastKnownSeq: json['lastKnownSeq'] as int? ?? 0,
      etag: json['etag'] as String?,
      lastSyncedAt: json['lastSyncedAt'] as int?,
      serverUpdatedAt: json['serverUpdatedAt'] as int?,
      orphaned: json['orphaned'] as bool? ?? false,
      sourceLocalKey: json['sourceLocalKey'] as String?,
      pendingOps: (json['pendingOps'] as List<dynamic>?)
              ?.map((e) => PendingOp.fromJson(e as Map<String, dynamic>))
              .toList() ??
          <PendingOp>[],
      cachedMembers: cachedMembersRaw == null
          ? null
          : MembersBlock.fromJson(cachedMembersRaw),
    );
  }
}

/// An [EntryList] that's mirrored to the share API.
///
/// **Owner** mode: a thin wrapper around a local [EntryList]. The
/// local list is the surface the user interacts with; mutations
/// trigger an op being enqueued and pushed via [SyncEngine].
///
/// **Editor** mode: a separately-stored mirror of someone else's
/// list. Mutable — edits enqueue ops just like owner mode.
///
/// **Subscriber** mode: read-only mirror, populated by
/// `/v1/lists/:id` polls.
///
/// ## Persistence invariants
///
/// Two kinds of writes to disk:
///
///   1. **User-mutation writes** (`addEntry`, `removeEntry`): persist
///      meta FIRST (so the pending op is durable), then entries. If
///      the app dies in between, [loadFromRaw]'s replay step folds
///      pending ops back into the in-memory entries set — no edits
///      are lost.
///
///   2. **Server-ack writes** (after a successful /sync that drops
///      ops from the queue): persist entries FIRST (so the new local
///      state is durable), then meta. If the app dies in between,
///      the pending op is still on disk; the engine retries on next
///      launch and the server returns "duplicate" — idempotent.
///
/// Never reorder these without thinking through both crash windows.
class SyncedEntryList extends EntryList {
  final SyncedListMeta meta;

  /// Non-null in owner mode. Wrapper delegates entries + storage
  /// to this list.
  final EntryList? ownerSource;

  /// Owner-mode constructor. Shares the source list's storage key
  /// and entries set by reference.
  SyncedEntryList.owner({
    required this.meta,
    required EntryList source,
  })  : ownerSource = source,
        super(source.key, source.entries,
            meta.role == ListRole.owner && !meta.orphaned);

  /// Editor-mode constructor. Independent local mirror, mutable.
  SyncedEntryList.editor({
    required this.meta,
    required LinkedHashSet<Entry> entries,
  })  : ownerSource = null,
        super(sharedPayloadStorageKey(meta.listId), entries,
            meta.role == ListRole.editor && !meta.orphaned);

  /// Subscriber-mode constructor. Independent mirror, read-only.
  SyncedEntryList.subscriber({
    required this.meta,
    required LinkedHashSet<Entry> entries,
  })  : ownerSource = null,
        super(sharedPayloadStorageKey(meta.listId), entries, false);

  /// Owner-mode factory for the "import my lists from the server on a
  /// fresh device" path. Pulls the metadata from a [ListSnapshot]
  /// (which carries `members`, unlike the `CreateResult` that the
  /// publish path uses), pairs it with the caller-allocated local
  /// list, and snapshots `lastSyncedAt` to [nowSecs].
  factory SyncedEntryList.ownerFromSnapshot({
    required ListSnapshot snapshot,
    required EntryList source,
    required String localKey,
    required int nowSecs,
  }) {
    return SyncedEntryList.owner(
      meta: SyncedListMeta(
        listId: snapshot.listId,
        displayName: snapshot.displayName,
        role: ListRole.owner,
        lastKnownSeq: snapshot.lastSeq,
        etag: null,
        lastSyncedAt: nowSecs,
        serverUpdatedAt: snapshot.updatedAt,
        orphaned: false,
        sourceLocalKey: localKey,
        cachedMembers: snapshot.members,
      ),
      source: source,
    );
  }

  String get listId => meta.listId;

  /// Display name shown in the UI. `meta.displayName` is authoritative
  /// — it's set by the share dialog on create, refreshed from every
  /// /sync, and free-form (emoji, reserved words, etc.). The local
  /// source key (when present) is just a storage handle; on a second
  /// device after `importOwnedLists` it can fall back to "Imported
  /// list" when the display name contains characters the local-key
  /// validator rejects, so reading from it would surface a wrong name.
  ///
  /// [context] is accepted for compatibility with the base class
  /// signature but ignored — shared list names are user-provided and
  /// don't go through l10n.
  @override
  String getName([BuildContext? context]) => meta.displayName;

  /// Re-derives from [meta] on every call rather than reading the
  /// base-class field captured at construction, because role can flip
  /// at runtime (editor demoted to subscriber on 403, list orphaned
  /// on 404/410). The base-class field is stale after those events.
  @override
  bool canBeEdited() =>
      (meta.role == ListRole.owner || meta.role == ListRole.editor) &&
      !meta.orphaned;

  /// Override so that user-initiated edits made *through* the wrapper
  /// enqueue a sync op. Every UI path that mutates a shared list is
  /// engineered to hold the wrapper, not the underlying source list:
  ///   - The lists overview's `target = owned ?? el` routes navigation
  ///     to the wrapper for owner shares.
  ///   - [ListsService.favouritesList] returns the wrapper when
  ///     favourites is owner-shared, so the word-page star button
  ///     goes through this same path.
  ///   - Editor / subscriber wrappers are their own source — no parallel
  ///     local list exists.
  ///
  /// Direct mutations on the source [EntryList] (bypassing the wrapper)
  /// will NOT enqueue, by design — the parallel test
  /// `lists_service_test.dart::"mutating the source directly does NOT
  /// enqueue an op"` pins this so we don't accidentally re-introduce a
  /// duplicate enqueue path.
  ///
  /// Persistence ordering: enqueue the pending op + writeMeta() FIRST,
  /// then the entries write. This way an app death between writes
  /// leaves a pending op on disk that load-time replay restores — no
  /// edit is lost. See the class-level docstring for the full
  /// invariant.
  @override
  Future<void> addEntry(Entry entryToAdd) async {
    if (!canBeEdited()) return;
    if (!entries.add(entryToAdd)) return;
    try {
      await sharing.engine.enqueueAddEntry(listId, entryToAdd.getKey());
    } catch (_) {
      // Enqueue failed (meta-write failure surfaced by the engine).
      // Roll back the optimistic mirror update so the visible state
      // matches what's durable on disk. Re-throw so the UI can show
      // a "couldn't save edit" snackbar.
      entries.remove(entryToAdd);
      rethrow;
    }
    await write();
  }

  @override
  Future<void> removeEntry(Entry entryToRemove) async {
    if (!canBeEdited()) return;
    if (!entries.remove(entryToRemove)) return;
    try {
      await sharing.engine.enqueueRemoveEntry(listId, entryToRemove.getKey());
    } catch (_) {
      // See [addEntry]. The re-added entry lands at the end of the
      // LinkedHashSet rather than its original slot — accepted as a
      // minor cosmetic side-effect of a rare disk-write failure.
      entries.add(entryToRemove);
      rethrow;
    }
    await write();
  }

  @override
  Widget getLeadingIcon({bool inEditMode = false}) {
    return Icon(iconForSharedList(meta));
  }

  /// Shared lists go away via unshare / unsubscribe / leave, not the
  /// normal "delete" path in the user lists UI.
  @override
  bool canBeDeleted() => false;

  /// Persist meta + entries using the **ack order**: entries first
  /// (new local state durable), then meta (pending-op clear durable).
  /// Use from [SyncEngine] after applying a /sync response.
  ///
  /// The dual case — meta first, entries second — is the **mutation
  /// order** used during user edits. That ordering is enforced inline
  /// by [addEntry] / [removeEntry] calling `engine.enqueue…` (which
  /// writes meta with the new pending op) before `await write()`
  /// (which writes entries). See the class-level docstring for the
  /// crash-window analysis.
  Future<void> writeAllAfterServerAck() async {
    await write();
    await writeMeta();
  }

  Future<void> writeMeta() async {
    await sharedPreferences.setString(
        sharedMetaStorageKey(meta.listId), jsonEncode(meta.toJson()));
  }

  /// Replace the entire entries set from a server response. Editor
  /// + subscriber modes only — owners apply remote ops via
  /// per-entry add/remove on the underlying source.
  void replaceEntriesFromServer(List<String> entryKeys) {
    entries.clear();
    for (final k in entryKeys) {
      final matching = keyedByEnglishEntriesGlobal[k];
      if (matching != null) {
        entries.add(matching);
      } else {
        printAndLog(
            'Synced list ${meta.listId}: server entry key "$k" not in dictionary; skipping');
      }
    }
  }

  /// Apply a remote add to the mirror. Used by the engine when it
  /// pulls down missedOps and by [loadFromRaw]'s pending-op replay.
  /// Logs a warning if the key isn't in the local dictionary so the
  /// silent-skip case is observable.
  void applyRemoteAdd(String entryKey) {
    final entry = keyedByEnglishEntriesGlobal[entryKey];
    if (entry == null) {
      printAndLog('Synced list ${meta.listId}: applyRemoteAdd skipping '
          'unknown entry key "$entryKey"');
      return;
    }
    entries.add(entry);
  }

  void applyRemoteRemove(String entryKey) {
    final entry = keyedByEnglishEntriesGlobal[entryKey];
    if (entry == null) {
      printAndLog('Synced list ${meta.listId}: applyRemoteRemove skipping '
          'unknown entry key "$entryKey"');
      return;
    }
    entries.remove(entry);
  }

  /// Apply a single op to the local entries mirror. Single dispatch
  /// point used by both the engine (folding in missedOps from /sync)
  /// and the load-time pending-op replay below. Owner-mode wrappers
  /// share their entries set with the source list by reference (see
  /// [SyncedEntryList.owner]), so one mutation path serves all three
  /// roles — owner edits land on the source list, editor / subscriber
  /// edits on the wrapper's own set.
  ///
  /// Idempotent under set semantics — re-applying an op whose effect
  /// is already present is a no-op. Unknown op types log and skip
  /// rather than throw so a future server can introduce ops without
  /// breaking older clients.
  void applyOpToEntries(String type, Map<String, dynamic> args) {
    switch (type) {
      case 'addEntry':
        final key = args['key'];
        if (key is String) applyRemoteAdd(key);
      case 'removeEntry':
        final key = args['key'];
        if (key is String) applyRemoteRemove(key);
      case 'addEditor':
      case 'removeEditor':
        // Synthetic membership ops the server logs when editors join /
        // leave. The engine reflects these via the members block on the
        // sync response, not by replaying them on the entries mirror.
        break;
      default:
        printAndLog('Synced list ${meta.listId}: unknown op type "$type"');
    }
  }

  /// Replay any persisted pending ops against the in-memory entries
  /// set. Used at load time so an app death between the meta-write
  /// and the entries-write (the mutation-order persistence pair)
  /// doesn't lose the user's edit: meta has the op on disk, replay
  /// puts the entry back into the in-memory set, the engine flushes
  /// the op on next /sync, the server returns "applied", and the
  /// next ack-order write persists the entry to disk.
  ///
  /// Idempotent — replaying an op whose effect is already present in
  /// the entries set is a no-op (set semantics). Safe to call
  /// multiple times.
  void replayPendingOpsLocally() {
    for (final op in meta.pendingOps) {
      applyOpToEntries(op.type, op.args);
    }
  }

  static SyncedEntryList? loadFromRaw(String listId) {
    final metaRaw = sharedPreferences.getString(sharedMetaStorageKey(listId));
    if (metaRaw == null) return null;
    final meta =
        SyncedListMeta.fromJson(jsonDecode(metaRaw) as Map<String, dynamic>);
    if (meta == null) return null;
    SyncedEntryList? list;
    if (meta.role == ListRole.owner) {
      final sourceKey = meta.sourceLocalKey;
      if (sourceKey == null) {
        printAndLog('SyncedEntryList: owner meta $listId has no '
            'sourceLocalKey; dropping');
        return null;
      }
      final source = userEntryListManager.getEntryLists()[sourceKey];
      if (source == null) {
        printAndLog('SyncedEntryList: owner meta $listId points at '
            'missing local source "$sourceKey"; dropping');
        return null;
      }
      list = SyncedEntryList.owner(meta: meta, source: source);
    } else {
      final entries = EntryList.loadEntryList(sharedPayloadStorageKey(listId));
      if (meta.role == ListRole.editor) {
        list = SyncedEntryList.editor(meta: meta, entries: entries);
      } else {
        list = SyncedEntryList.subscriber(meta: meta, entries: entries);
      }
    }
    // Recovery: fold any persisted pending ops into the loaded entries
    // set, in case an app death between the mutation-order writes
    // (meta first, entries second — see the class-level docstring)
    // left them out of sync. Replay is idempotent — when meta and
    // entries were both persisted cleanly, this is a no-op.
    list.replayPendingOpsLocally();
    return list;
  }
}

/// Manager for the device's synced lists. Holds owner, editor, and
/// subscriber wrappers in one collection. Insertion order is the
/// stable display order in the UI — Dart `Map` literals are
/// `LinkedHashMap` under the hood.
class SyncedEntryListManager {
  final Map<String, SyncedEntryList> _lists;
  final Map<String, SyncedEntryList> _ownersBySourceKey = {};

  SyncedEntryListManager(this._lists) {
    for (final l in _lists.values) {
      _indexIfOwner(l);
    }
  }

  Iterable<String> get listIds => _lists.keys;

  Iterable<SyncedEntryList> get ownedLists => _ownersBySourceKey.values;
  Iterable<SyncedEntryList> get editorLists =>
      _lists.values.where((l) => l.meta.role == ListRole.editor);
  Iterable<SyncedEntryList> get subscribedLists =>
      _lists.values.where((l) => l.meta.role == ListRole.subscriber);

  /// All lists the user can edit (owner or editor).
  Iterable<SyncedEntryList> get editableLists => _lists.values.where(
      (l) => l.meta.role == ListRole.owner || l.meta.role == ListRole.editor);

  SyncedEntryList? get(String listId) => _lists[listId];

  SyncedEntryList? ownerForSourceKey(String sourceLocalKey) =>
      _ownersBySourceKey[sourceLocalKey];

  factory SyncedEntryListManager.fromStartup() {
    final keys = sharedPreferences.getStringList(KEY_SHARED_LIST_IDS) ?? [];
    final lists = <String, SyncedEntryList>{};
    final orphanedKeys = <String>[];
    for (final k in keys) {
      final loaded = SyncedEntryList.loadFromRaw(k);
      if (loaded != null) {
        lists[k] = loaded;
      } else {
        printAndLog('SyncedEntryListManager: index entry "$k" '
            'is unloadable; cleaning up shared-prefs entries');
        orphanedKeys.add(k);
      }
    }
    // Garbage-collect shared-prefs for unloadable entries — without this,
    // an owner wrapper whose local source was deleted (or a meta blob that
    // failed to parse) would leak its meta + payload keys forever, since
    // the index re-write below silently drops them.
    if (orphanedKeys.isNotEmpty) {
      for (final k in orphanedKeys) {
        unawaited(sharedPreferences.remove(sharedMetaStorageKey(k)));
        unawaited(sharedPreferences.remove(sharedPayloadStorageKey(k)));
      }
      unawaited(sharedPreferences.setStringList(
          KEY_SHARED_LIST_IDS, lists.keys.toList()));
    }
    return SyncedEntryListManager(lists);
  }

  Future<void> _writeIndex() async {
    await sharedPreferences.setStringList(
        KEY_SHARED_LIST_IDS, _lists.keys.toList());
  }

  /// Add a list to the manager and persist it. Uses ack-order
  /// (entries first, then meta) since the typical caller is the
  /// engine after a fresh server fetch where there are no pending ops.
  Future<void> insert(SyncedEntryList list) async {
    _lists[list.listId] = list;
    _indexIfOwner(list);
    await list.writeAllAfterServerAck();
    await _writeIndex();
  }

  /// Remove a list locally. Owner-mode shares the local list's
  /// storage (the source's own payload key, not [sharedPayloadStorageKey]),
  /// which is the user's data and we don't touch it here.
  Future<void> removeLocal(String listId) async {
    final list = _lists.remove(listId);
    if (list != null) {
      final sourceKey = list.meta.sourceLocalKey;
      if (sourceKey != null) _ownersBySourceKey.remove(sourceKey);
      if (list.meta.role != ListRole.owner) {
        await sharedPreferences.remove(sharedPayloadStorageKey(listId));
      }
    }
    await sharedPreferences.remove(sharedMetaStorageKey(listId));
    await _writeIndex();
  }

  bool hasList(String listId) => _lists.containsKey(listId);

  Future<void> clearAll() async {
    for (final id in _lists.keys.toList()) {
      await removeLocal(id);
    }
  }

  void _indexIfOwner(SyncedEntryList list) {
    if (list.meta.role != ListRole.owner) return;
    final sourceKey = list.meta.sourceLocalKey;
    if (sourceKey != null) _ownersBySourceKey[sourceKey] = list;
  }
}

/// Stable per-install client UUID. Lazily generated on first read,
/// persisted in SharedPreferences. Sent on every /sync as
/// `x-client-id` so the server can attribute ops to a specific device.
///
/// The first read's generated id is also cached in-process so back-to-back
/// /sync calls within a session always see the same value even if the
/// shared-prefs write hasn't flushed to disk yet.
String? _cachedClientId;
String getOrCreateClientId() {
  final cached = _cachedClientId;
  if (cached != null) return cached;
  final existing = sharedPreferences.getString(KEY_SHARED_CLIENT_ID);
  if (existing != null && existing.isNotEmpty) {
    _cachedClientId = existing;
    return existing;
  }
  final id = _generateRandomHexId(16);
  _cachedClientId = id;
  // Fire-and-forget — losing the write here just costs us regenerating
  // the in-memory value next launch. Client id is advisory.
  unawaited(sharedPreferences.setString(KEY_SHARED_CLIENT_ID, id));
  return id;
}

/// Test-only: reset the in-memory client-id cache so the next call to
/// [getOrCreateClientId] re-reads from shared-prefs (and generates one
/// if missing).
@visibleForTesting
void resetClientIdCacheForTesting() {
  _cachedClientId = null;
}

/// Generate a per-op UUID-ish for [PendingOp.opId]. Random 128-bit hex.
/// Distinct from [getOrCreateClientId] (which generates a similar
/// shape) so a future change to either generator doesn't silently
/// change the other.
String generateOpId() => _generateRandomHexId(16);

String _generateRandomHexId(int byteCount) {
  const hex = '0123456789abcdef';
  final r = Random.secure();
  final buf = StringBuffer();
  for (var i = 0; i < byteCount * 2; i++) {
    buf.write(hex[r.nextInt(16)]);
  }
  return buf.toString();
}
