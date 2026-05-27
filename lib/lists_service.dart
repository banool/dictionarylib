import 'dart:async';
import 'dart:collection';

import 'package:flutter/widgets.dart';

import 'common.dart';
import 'entry_list.dart';
import 'entry_types.dart';
import 'globals.dart';
import 'l10n/app_localizations.dart';
import 'sharing/sync_api.dart';
import 'sharing/synced_entry_list.dart';

/// Single coordination point for list operations across local user lists
/// ([userEntryListManager]) and the cloud-synced lists ([sharing]).
///
/// The model: **the server is the ultimate authority for shared list
/// content.** Owners and editors maintain a local mirror that's edited
/// optimistically — each user-driven mutation enqueues a typed op (via
/// [SyncedEntryList.addEntry] / [removeEntry], which is what every UI
/// path holds for shared lists) and the [SyncEngine] batches them to
/// the server. On every /sync the server's view is folded in: missed
/// ops from other editors are applied to the mirror, then any
/// still-pending local ops are re-applied on top.
///
/// All three roles — owner, editor, subscriber — exist as
/// [SyncedEntryList] wrappers. Owner-mode wrappers share their entries
/// set by reference with the underlying local list, so "My Lists"
/// shows the local list and edits through it remain visible there. UI
/// code that wants to edit a shared list reads through this service:
/// [ownedShareFor] returns the wrapper for a local list, [favouritesList]
/// returns the wrapper if favourites is shared, and the overview
/// navigates straight to the wrapper for shared lists.
class ListsService {
  ListsService._();

  static final ListsService instance = ListsService._();

  /// The lists shown in the "My Lists" overview, in display order: every
  /// local user list. Owner-shared lists appear here as their underlying
  /// local list (with a "shared by you" badge added by the overview).
  /// Subscribed lists have their own tab.
  List<EntryList> get myLists =>
      userEntryListManager.getEntryLists().values.toList();

  /// The favourites list. If favourites has been shared from this device,
  /// returns the owner-mode [SyncedEntryList] wrapper (whose [addEntry]
  /// also enqueues a sync op); otherwise returns the plain local list.
  /// Callers (e.g. the word-page star button) get the same `EntryList`
  /// surface either way and don't need to know about sharing.
  EntryList get favouritesList {
    final local = userEntryListManager.getEntryLists()[KEY_FAVOURITES_ENTRIES]!;
    return ownedShareFor(local) ?? local;
  }

  /// The owner-side sync metadata for [list] if it's been shared from this
  /// device, else null. UI surfaces a "shared by you" badge / unshare menu
  /// when this is non-null.
  ///
  /// Accepts either a plain local [EntryList] (the usual case — looks up
  /// the owner wrapper by source key) or a [SyncedEntryList] that the
  /// caller is already holding (returns it if it's an owner, null
  /// otherwise). One method, one answer.
  SyncedEntryList? ownedShareFor(EntryList list) {
    if (!sharing.isEnabled) return null;
    if (list is SyncedEntryList) {
      return list.meta.role == ListRole.owner ? list : null;
    }
    return sharing.lists.ownerForSourceKey(list.key);
  }

  /// Publish [sourceList] as a new shared list. The local list is
  /// untouched (its entries become the initial set the server gets);
  /// an owner-mode wrapper is created in the synced-list manager so
  /// subsequent mutations through it enqueue sync ops.
  ///
  /// Requires the user to be signed in; pass the current
  /// [AuthSession.sessionToken]. The "tap share → sign in if needed"
  /// orchestration lives in the share dialog, not here.
  Future<SyncedEntryList> shareList({
    required EntryList sourceList,
    required String displayName,
    required String sessionToken,
  }) async {
    if (!sharing.isEnabled) {
      throw StateError('sharing is not configured for this app');
    }
    final synced = await sharing.engine.createOwned(
      displayName: displayName,
      source: sourceList,
      sessionToken: sessionToken,
    );
    sharing.bumpState();
    return synced;
  }

  /// Stop publishing a shared list. Deletes the server-side copy and
  /// removes the local owner wrapper; the local list — which still
  /// holds the entries — is untouched.
  Future<void> unshareList(SyncedEntryList list) async {
    if (!sharing.isEnabled) return;
    if (list.meta.role != ListRole.owner) return;
    await sharing.engine.unshare(list.listId);
    sharing.bumpState();
  }

  /// Subscriber-only: force a refresh of [list] from the server now.
  /// No-op for owner lists.
  Future<void> refreshSubscriber(SyncedEntryList list) async {
    if (!sharing.isEnabled) return;
    if (list.meta.role != ListRole.subscriber) return;
    await sharing.engine.refreshSubscriber(list.listId);
  }

  /// Subscriber-only: stop following a list someone else owns. The local
  /// mirror is removed.
  Future<void> unsubscribeList(SyncedEntryList list) async {
    if (!sharing.isEnabled) return;
    if (list.meta.role != ListRole.subscriber) return;
    await sharing.engine.unsubscribe(list.listId);
  }

  /// Bootstrap flow for "I just signed in on a new device and want to
  /// see my existing shared lists". Asks the server which lists the
  /// current session owns + edits, fetches each one, and inserts it
  /// locally — owned lists get a paired local [EntryList] so they
  /// show up in "My lists"; edited lists install as editor-mode
  /// mirrors directly.
  ///
  /// Idempotent — lists already on the device are skipped. Local user
  /// lists are never overwritten; new ones get a numeric suffix on
  /// name collision (`Animals`, `Animals 2`, …).
  ///
  /// Fetches run in parallel since each /state call is independent;
  /// the apply phase is sequential so local-key allocation can avoid
  /// collisions and `userEntryListManager` / `sharing.lists` mutations don't
  /// interleave.
  ///
  /// [context] is used only to localise the fallback list name when the
  /// server-supplied display name can't be turned into a valid local
  /// storage key. Optional so test code can call this without a
  /// widget tree; pass a real context from real callers.
  Future<ImportOwnedListsResult> importOwnedLists({BuildContext? context}) async {
    if (!sharing.isEnabled) {
      throw StateError('sharing is not configured for this app');
    }
    final session = sharing.auth.store.current;
    if (session == null) {
      throw StateError('importOwnedLists: not signed in');
    }
    final userLists =
        await sharing.api.userLists(sessionToken: session.sessionToken);
    var imported = 0;
    var skipped = 0;
    final total =
        userLists.ownedListIds.length + userLists.editorListIds.length;

    // Pre-filter the already-present cases so we don't waste API calls
    // on lists the device already has in the target role.
    final ownedToFetch = <String>[];
    for (final listId in userLists.ownedListIds) {
      final existing = sharing.lists.get(listId);
      if (existing != null && existing.meta.role == ListRole.owner) {
        skipped++;
      } else {
        ownedToFetch.add(listId);
      }
    }
    final editorToFetch = <String>[];
    for (final listId in userLists.editorListIds) {
      final existing = sharing.lists.get(listId);
      if (existing != null &&
          (existing.meta.role == ListRole.owner ||
              existing.meta.role == ListRole.editor)) {
        skipped++;
      } else {
        editorToFetch.add(listId);
      }
    }

    // Fetch authoritative snapshots in parallel — each /state call is
    // independent.
    //
    // Errors are split two ways:
    //   - **Auth / network failures** (401, network) propagate as
    //     [SyncException] so the caller can abort the whole import
    //     rather than silently mis-classifying a token expiry as
    //     "0 imported, N skipped" with no actionable signal.
    //   - **Per-list failures** (404, 410, 403 on one specific list,
    //     500) are recorded as a null snapshot and folded into the
    //     skipped count, so a single broken list doesn't block the
    //     others from importing.
    Future<_FetchResult> fetch(String listId) async {
      try {
        final snapshot = await sharing.api
            .getState(listId: listId, sessionToken: session.sessionToken);
        return _FetchResult(listId: listId, snapshot: snapshot);
      } on SyncException catch (e) {
        if (e.kind == SyncErrorKind.unauthorized ||
            e.kind == SyncErrorKind.network) {
          rethrow;
        }
        return _FetchResult(listId: listId, snapshot: null);
      }
    }

    final ownedFutures = ownedToFetch.map(fetch).toList();
    final editorFutures = editorToFetch.map(fetch).toList();
    final ownedResults = await Future.wait(ownedFutures);
    final editorResults = await Future.wait(editorFutures);

    final nowSecs = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final importedListFallback = context == null
        ? 'Imported list'
        : DictLibLocalizations.of(context)?.importedListFallbackName ??
            'Imported list';

    for (final result in ownedResults) {
      final snapshot = result.snapshot;
      if (snapshot == null) {
        skipped++;
        continue;
      }
      // Reuse an existing local source if we already have one for this
      // listId (re-running the import after, say, a clear-then-restore
      // shouldn't orphan the user's data). When [existing] points at a
      // local list that's still in [userEntryListManager], we just
      // overwrite the entries in place; otherwise allocate a fresh
      // local key and create one.
      String localKey;
      EntryList local;
      final existing = sharing.lists.get(result.listId);
      final reusableSourceKey = existing?.meta.sourceLocalKey;
      final reusableSource = reusableSourceKey == null
          ? null
          : userEntryListManager.getEntryLists()[reusableSourceKey];
      if (existing != null && reusableSource != null) {
        await sharing.lists.removeLocal(result.listId);
        localKey = reusableSourceKey!;
        local = reusableSource;
        local.entries.clear();
      } else {
        if (existing != null) await sharing.lists.removeLocal(result.listId);
        localKey = allocateLocalKey(
            preferredName: snapshot.displayName,
            fallbackBase: importedListFallback);
        await userEntryListManager.createEntryList(localKey);
        local = userEntryListManager.getEntryLists()[localKey]!;
      }
      for (final k in snapshot.entries) {
        final entry = keyedByEnglishEntriesGlobal[k];
        if (entry != null) local.entries.add(entry);
      }
      await local.write();
      await sharing.lists.insert(SyncedEntryList.ownerFromSnapshot(
          snapshot: snapshot, source: local, localKey: localKey, nowSecs: nowSecs));
      imported++;
    }

    for (final result in editorResults) {
      final snapshot = result.snapshot;
      if (snapshot == null) {
        skipped++;
        continue;
      }
      final existing = sharing.lists.get(result.listId);
      if (existing != null) await sharing.lists.removeLocal(result.listId);
      final entries = <Entry>{};
      for (final k in snapshot.entries) {
        final entry = keyedByEnglishEntriesGlobal[k];
        if (entry != null) entries.add(entry);
      }
      await sharing.lists.insert(SyncedEntryList.editor(
        meta: SyncedListMeta(
          listId: snapshot.listId,
          displayName: snapshot.displayName,
          role: ListRole.editor,
          lastKnownSeq: snapshot.lastSeq,
          etag: null,
          lastSyncedAt: nowSecs,
          serverUpdatedAt: snapshot.updatedAt,
          orphaned: false,
          cachedMembers: snapshot.members,
        ),
        entries: LinkedHashSet<Entry>.from(entries),
      ));
      imported++;
    }

    sharing.bumpState();
    return ImportOwnedListsResult(
        imported: imported, skipped: skipped, total: total);
  }

  /// Allocate a local list key derived from a display name that's free in
  /// [userEntryListManager] and survives [EntryList.getKeyFromName]'s
  /// validity rules.
  ///
  /// [preferredName] is tried first. If it can't round-trip through
  /// `getKeyFromName` (empty, reserved, or contains characters the
  /// validator rejects), the algorithm switches to [fallbackBase] — which
  /// callers should pick from their own localisation (e.g. "Imported
  /// list", "Duplicated list"). Either way, a numeric suffix is appended
  /// until the resulting key is free.
  String allocateLocalKey(
      {required String preferredName, required String fallbackBase}) {
    String safeBase;
    try {
      EntryList.getKeyFromName(preferredName);
      safeBase = preferredName;
    } catch (_) {
      safeBase = fallbackBase;
    }
    var candidate = safeBase;
    for (var n = 2;; n++) {
      final k = EntryList.getKeyFromName(candidate);
      if (!userEntryListManager.getEntryLists().containsKey(k)) return k;
      // Space + digit only — the validNameCharacters regex doesn't allow
      // parens, so "$base ($n)" would re-throw inside getKeyFromName.
      candidate = '$safeBase $n';
    }
  }
}

/// Convenience global so callers don't have to type `ListsService.instance`
/// constantly. Mirrors the existing `userEntryListManager` / `sharing`
/// pattern.
ListsService get listsService => ListsService.instance;

/// One row in [ListsService.importOwnedLists]'s fetch phase. `snapshot`
/// is null when the /state call failed — the apply phase treats null
/// as a skip rather than aborting the whole import.
class _FetchResult {
  final String listId;
  final ListSnapshot? snapshot;
  const _FetchResult({required this.listId, required this.snapshot});
}

/// Outcome of [ListsService.importOwnedLists].
class ImportOwnedListsResult {
  final int imported;
  final int skipped;
  final int total;
  const ImportOwnedListsResult({
    required this.imported,
    required this.skipped,
    required this.total,
  });
}

/// Convenience wrapper around [localisedSyncError] for callers whose
/// notFound and unknown branches collapse to the same message. Most
/// call sites just want a single fallback string; the full
/// [localisedSyncError] is for code that distinguishes "list not
/// found" from "we don't know what happened".
String localisedSyncErrorSimple(
  BuildContext context,
  SyncException e,
  String fallback,
) {
  return localisedSyncError(context, e,
      notFoundMessage: fallback, unknownMessage: fallback);
}

/// User-facing message for a [SyncException]. The notFound branch is
/// caller-specific (a subscribe dialog says "no list with that key
/// exists"; a deep-link landing page says "this list has been deleted by
/// its owner"), so callers supply that copy. The unknownMessage fallback
/// covers `invalidBody` / `missingHeader` / `idCollision` — error kinds
/// that should be unreachable from real UI paths and don't have their
/// own localised copy.
String localisedSyncError(
  BuildContext context,
  SyncException e, {
  required String notFoundMessage,
  required String unknownMessage,
}) {
  final l = DictLibLocalizations.of(context)!;
  switch (e.kind) {
    case SyncErrorKind.notFound:
      return notFoundMessage;
    case SyncErrorKind.network:
      return l.shareNetworkError;
    case SyncErrorKind.unauthorized:
      return l.shareErrorUnauthorized;
    case SyncErrorKind.forbidden:
      return l.shareErrorForbidden;
    case SyncErrorKind.gone:
      return l.shareErrorGone;
    case SyncErrorKind.payloadTooLarge:
      return l.shareErrorPayloadTooLarge;
    case SyncErrorKind.rateLimited:
      return l.shareErrorRateLimited;
    case SyncErrorKind.server:
      return l.shareErrorServer;
    case SyncErrorKind.invalidBody:
    case SyncErrorKind.missingHeader:
    case SyncErrorKind.idCollision:
    case SyncErrorKind.unknownClient:
      return unknownMessage;
  }
}
