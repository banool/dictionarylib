import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';

import '../common.dart';
import '../entry_list.dart';
import '../globals.dart';
import '../saved_video.dart';
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
///
/// v2 carries `pendingOps` whose args are `{entry, video}` shaped to
/// match the new per-video model. Pre-v2 metas (carrying v1 `{key}`
/// ops) are dropped on load — those ops were never live in production.
const int sharedSchemaVersion = 2;

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
  /// add/remove entries; renaming stays owner-only (enforced by the
  /// worker).
  editor,

  /// User has subscribed via a share link. Read-only.
  subscriber,
}

/// One place that maps a [SyncedListMeta]'s state to the icon every
/// UI surface uses for that state.
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
/// survives app death + offline periods.
class PendingOp {
  /// Client-generated UUID; the server's dedupe key on retries.
  final String opId;

  /// Op type — matches the server's `OpType` enum verbatim
  /// (`addEntry`, `removeEntry`).
  final String type;

  /// Op-specific arguments. For `addEntry` / `removeEntry` this is
  /// `{entry: String, video: String}` — the schema-v3 shape.
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
  /// of truth for this share.
  String? sourceLocalKey;

  /// FIFO queue of locally-applied-but-not-yet-server-acked ops.
  List<PendingOp> pendingOps;

  /// Cached members directory from the last /sync or /state response.
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
/// **Owner** mode: a thin wrapper around a local [EntryList]. Mutations
/// trigger an op being enqueued and pushed via the engine.
///
/// **Editor** mode: a separately-stored mirror of someone else's list.
/// Mutable — edits enqueue ops just like owner mode.
///
/// **Subscriber** mode: read-only mirror.
///
/// Persistence ordering follows the same invariants as before — see
/// the engine docs.
class SyncedEntryList extends EntryList {
  final SyncedListMeta meta;

  /// Non-null in owner mode. Wrapper delegates savedVideos + storage
  /// to this list.
  final EntryList? ownerSource;

  /// Owner-mode constructor. Shares the source list's storage key
  /// and saved-videos set by reference.
  SyncedEntryList.owner({
    required this.meta,
    required EntryList source,
  })  : ownerSource = source,
        super(source.key, source.savedVideos,
            meta.role == ListRole.owner && !meta.orphaned);

  /// Editor-mode constructor. Independent local mirror, mutable.
  SyncedEntryList.editor({
    required this.meta,
    required LinkedHashSet<SavedVideo> savedVideos,
  })  : ownerSource = null,
        super(sharedPayloadStorageKey(meta.listId), savedVideos,
            meta.role == ListRole.editor && !meta.orphaned);

  /// Subscriber-mode constructor. Independent mirror, read-only.
  SyncedEntryList.subscriber({
    required this.meta,
    required LinkedHashSet<SavedVideo> savedVideos,
  })  : ownerSource = null,
        super(sharedPayloadStorageKey(meta.listId), savedVideos, false);

  /// Owner-mode factory for the "import my lists from the server on a
  /// fresh device" path.
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

  @override
  String getName([BuildContext? context]) => meta.displayName;

  @override
  bool canBeEdited() =>
      (meta.role == ListRole.owner || meta.role == ListRole.editor) &&
      !meta.orphaned;

  /// Add a saved video and enqueue the corresponding sync op. Direct
  /// mutations on the underlying source list (bypassing the wrapper)
  /// will NOT enqueue — every UI path that mutates a shared list is
  /// engineered to hold the wrapper.
  @override
  Future<void> addVideo(SavedVideo video) async {
    if (!canBeEdited()) return;
    if (!savedVideos.add(video)) return;
    try {
      await sharing.engine.enqueueAddVideo(listId, video);
    } catch (_) {
      savedVideos.remove(video);
      rethrow;
    }
    await write();
  }

  @override
  Future<void> removeVideo(SavedVideo video) async {
    if (!canBeEdited()) return;
    if (!savedVideos.remove(video)) return;
    try {
      await sharing.engine.enqueueRemoveVideo(listId, video);
    } catch (_) {
      savedVideos.add(video);
      rethrow;
    }
    await write();
  }

  /// Add every video of [entry]. Each video produces its own pending
  /// op so the server-side log records the granular intent — matters
  /// for editors who follow the op stream.
  @override
  Future<void> addAllVideosOfEntry(entry) async {
    if (!canBeEdited()) return;
    for (final v in allVideosOf(entry)) {
      if (containsVideo(v)) continue;
      await addVideo(v);
    }
  }

  @override
  Future<void> removeAllVideosOfEntry(entry) async {
    if (!canBeEdited()) return;
    for (final v in videosForEntry(entry).toList()) {
      await removeVideo(v);
    }
  }

  @override
  Widget getLeadingIcon({bool inEditMode = false}) {
    return Icon(iconForSharedList(meta));
  }

  @override
  bool canBeDeleted() => false;

  /// Persist meta + entries using the **ack order**: entries first,
  /// then meta. Use from [SyncEngine] after applying a /sync response.
  Future<void> writeAllAfterServerAck() async {
    await write();
    await writeMeta();
  }

  Future<void> writeMeta() async {
    await sharedPreferences.setString(
        sharedMetaStorageKey(meta.listId), jsonEncode(meta.toJson()));
  }

  /// Replace the entire saved-videos set from a server response.
  /// Editor + subscriber modes only — owners apply remote ops via
  /// per-video add/remove on the underlying source.
  void replaceEntriesFromServer(List<SavedVideo> serverEntries) {
    savedVideos.clear();
    savedVideos.addAll(serverEntries);
  }

  /// Apply a remote add op to the local mirror.
  void applyRemoteAdd(SavedVideo video) {
    savedVideos.add(video);
  }

  void applyRemoteRemove(SavedVideo video) {
    savedVideos.remove(video);
  }

  /// Apply a single op to the local saved-videos mirror. Used by the
  /// engine (folding in missedOps) and by load-time pending-op replay.
  ///
  /// Idempotent under set semantics. Unknown op types log and skip so
  /// a future server can introduce ops without breaking older clients.
  void applyOpToSavedVideos(String type, Map<String, dynamic> args) {
    switch (type) {
      case 'addEntry':
        final video = _videoFromArgs(args);
        if (video != null) applyRemoteAdd(video);
      case 'removeEntry':
        final video = _videoFromArgs(args);
        if (video != null) applyRemoteRemove(video);
      case 'addEditor':
      case 'removeEditor':
        break;
      default:
        printAndLog('Synced list ${meta.listId}: unknown op type "$type"');
    }
  }

  /// Best-effort decode of op args into a [SavedVideo]. Returns null
  /// on malformed args so a bad op is skipped rather than crashing the
  /// mirror replay.
  SavedVideo? _videoFromArgs(Map<String, dynamic> args) {
    final entry = args['entry'];
    final video = args['video'];
    if (entry is! String || video is! String) {
      printAndLog('Synced list ${meta.listId}: malformed op args $args');
      return null;
    }
    return SavedVideo(entryKey: entry, videoUrl: video);
  }

  /// Replay any persisted pending ops against the in-memory savedVideos
  /// set. Used at load time so an app death between the meta-write
  /// and the entries-write doesn't lose the user's edit.
  void replayPendingOpsLocally() {
    for (final op in meta.pendingOps) {
      applyOpToSavedVideos(op.type, op.args);
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
      final entries =
          EntryList.loadSavedVideos(sharedPayloadStorageKey(listId));
      if (meta.role == ListRole.editor) {
        list = SyncedEntryList.editor(meta: meta, savedVideos: entries);
      } else {
        list = SyncedEntryList.subscriber(meta: meta, savedVideos: entries);
      }
    }
    list.replayPendingOpsLocally();
    return list;
  }
}

/// Manager for the device's synced lists. Holds owner, editor, and
/// subscriber wrappers in one collection.
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

  Future<void> insert(SyncedEntryList list) async {
    _lists[list.listId] = list;
    _indexIfOwner(list);
    await list.writeAllAfterServerAck();
    await _writeIndex();
  }

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

  /// Remove every owned + editor list mirror, leaving subscriptions intact.
  /// Owner mirrors wrap a local list, which keeps its entries — only the
  /// sharing wrapper is dropped. Used on sign-out and account deletion so
  /// account-bound state doesn't carry over to a different account, while
  /// anonymous public subscriptions stay.
  Future<void> clearEditableLists() async {
    for (final list in editableLists.toList()) {
      await removeLocal(list.listId);
    }
  }

  void _indexIfOwner(SyncedEntryList list) {
    if (list.meta.role != ListRole.owner) return;
    final sourceKey = list.meta.sourceLocalKey;
    if (sourceKey != null) _ownersBySourceKey[sourceKey] = list;
  }
}

/// Stable per-install client UUID.
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
  unawaited(sharedPreferences.setString(KEY_SHARED_CLIENT_ID, id));
  return id;
}

@visibleForTesting
void resetClientIdCacheForTesting() {
  _cachedClientId = null;
}

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
