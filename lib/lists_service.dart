import 'dart:async';

import 'package:flutter/widgets.dart';

import 'analytics.dart';
import 'entry_list.dart';
import 'globals.dart';
import 'l10n/app_localizations.dart';
import 'list_storage.dart';
import 'sharing/account_sync.dart';
import 'sharing/account_sync_api.dart';
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
/// [ownedShareFor] returns the wrapper for a local list, and the overview
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

  /// Every list a video can be saved into, in the order the save sheet
  /// shows them: the local user lists (each routed through its owner-mode
  /// wrapper when shared, so toggles enqueue sync ops) followed by the
  /// editor-mode shared lists. Read-only subscriber lists and the
  /// separate community lists are excluded — you can't save into either.
  ///
  /// Single source of truth for "which lists hold this video": both the
  /// save sheet and the word-page "saved to N lists" count build from
  /// this, so the count can never drift from what the sheet lets you
  /// toggle (e.g. an editor list the count used to miss).
  List<EntryList> get writableLists {
    final out = <EntryList>[];
    for (final el in myLists) {
      out.add(ownedShareFor(el) ?? el);
    }
    if (sharing.isEnabled) {
      for (final el in sharing.lists.editorLists) {
        if (el.meta.orphaned) continue;
        out.add(el);
      }
    }
    return out;
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

  /// The object to mutate for [list]: its owner wrapper when it's linked
  /// to the account (so changes are queued for the server), the plain list
  /// otherwise.
  EntryList writableFor(EntryList list) => ownedShareFor(list) ?? list;

  /// Create a list called [name] (validated as a user-typed name; throws
  /// [EntryListNameException]). Returns its storage key.
  Future<String> createList(String name) async {
    final key = EntryList.getKeyFromName(name, rejectUnderscores: true);
    await createListWithKey(key);
    Analytics.track('list_created', props: {'shared': false});
    return key;
  }

  /// Create a list under [key] (already free). On a signed-in device the
  /// list and the record that it is to be linked are made in one step under
  /// the account-sync lock, and a cycle links it shortly after; changes made
  /// before then go to the plain list and are carried over by the link.
  Future<void> createListWithKey(String key) async {
    final sync = sharing.accountSync;
    if (!sync.isSignedInAndSupported) {
      await userEntryListManager.createEntryList(key);
      return;
    }
    await sync.exclusive(() async {
      await userEntryListManager.createEntryList(key);
      await sync.noteCreatedLocally(key);
    });
    unawaited(sync.kick(SyncReason.localChange));
  }

  /// True if [list] can be deleted from this device: every list but the
  /// default, and (before this device has synced with the account) not a
  /// list shared from it, which has to be unshared first as before.
  bool canDelete(EntryList list) {
    if (!list.canBeDeleted()) return false;
    final owned = ownedShareFor(list);
    return owned == null || sharing.accountSync.ownsLinks;
  }

  /// Delete [list]. A linked list is deleted on every device (the
  /// confirmation says so): the account's `delete` op is queued first, then
  /// the wrapper and the local list go. A list still being linked is
  /// deleted locally and a `delete` queued for the id its link chose (a
  /// no-op on the server if the create never landed).
  Future<void> deleteList(EntryList list) async {
    final source = list is SyncedEntryList ? list.ownerSource : list;
    if (source == null) {
      throw StateError('only a list of your own can be deleted');
    }
    final key = source.key;
    if (key == readDefaultListKey()) {
      throw StateError('The default list cannot be deleted');
    }
    final sync = sharing.accountSync;
    await sync.exclusive(() async {
      final wrapper = sharing.lists.ownerForSourceKey(key);
      if (wrapper != null) {
        if (!sync.ownsLinks) {
          throw StateError('"$key" is shared; stop sharing it first');
        }
        await sync.enqueue(
          AccountOp(
            opId: generateOpId(),
            type: 'delete',
            args: {'listId': wrapper.listId},
          ),
        );
        await sharing.engine.dropOwned(wrapper.listId);
        await userEntryListManager.deleteEntryList(key);
        await sync.noteDeletedLocally(key);
        return;
      }
      final linkingTo = await sync.noteDeletedLocally(key);
      if (linkingTo != null) {
        await sync.enqueue(
          AccountOp(
            opId: generateOpId(),
            type: 'delete',
            args: {'listId': linkingTo},
          ),
        );
      }
      await userEntryListManager.deleteEntryList(key);
    });
    sharing.bumpState();
    unawaited(sync.kick(SyncReason.localChange));
  }

  /// Rename [list] to [newName]. A linked list is renamed on the server
  /// (its local key never moves; every screen shows the server's name). Any
  /// other list moves to the key for the new name, and a link in progress
  /// moves with it.
  Future<void> renameList(EntryList list, String newName) async {
    final owned = ownedShareFor(list);
    if (owned != null) {
      await renameSharedList(owned, newName);
      return;
    }
    final newKey = EntryList.getKeyFromName(newName, rejectUnderscores: true);
    final oldKey = list.key;
    final sync = sharing.accountSync;
    var linkedMeanwhile = false;
    await sync.exclusive(() async {
      if (sharing.lists.ownerForSourceKey(oldKey) != null) {
        linkedMeanwhile = true;
        return;
      }
      await userEntryListManager.renameEntryList(oldKey, newKey);
      await sync.noteKeyMoved(oldKey, newKey);
    });
    if (linkedMeanwhile) {
      final linked = sharing.lists.ownerForSourceKey(oldKey);
      if (linked != null) await renameSharedList(linked, newName);
    }
  }

  /// Move the list at [prev] to [updated] in My Lists, and tell the account
  /// (the order is the same on every device).
  Future<void> reorderLists(int prev, int updated) async {
    userEntryListManager.reorder(prev, updated);
    await userEntryListManager.writeEntryListKeys();
    final sync = sharing.accountSync;
    if (!sync.ownsLinks) return;
    final ids = [
      for (final key in userEntryListManager.getEntryLists().keys)
        ?sharing.lists.ownerForSourceKey(key)?.listId,
    ];
    if (ids.isEmpty) return;
    await sync.enqueue(
      AccountOp(opId: generateOpId(), type: 'reorder', args: {'listIds': ids}),
    );
    unawaited(sync.kick(SyncReason.localChange));
  }

  /// Share [sourceList] under [displayName]. With account sync the list is
  /// linked first (running a cycle if it isn't yet) and then flipped to
  /// shared (`PUT .../visibility`), keeping its id and everything on it. On
  /// a device where account sync is switched off by the knob it is shared
  /// the old way, as a new list (`POST /v1/lists`), which account sync finds
  /// later through the owner index. Throws [SyncException] on failure and
  /// [ListNotSyncableException] for a list that stays on this device.
  Future<SyncedEntryList> shareList({
    required EntryList sourceList,
    required String displayName,
    required String sessionToken,
  }) async {
    if (!sharing.isEnabled) {
      throw StateError('sharing is not configured for this app');
    }
    final sync = sharing.accountSync;
    final source = sourceList is SyncedEntryList
        ? sourceList.ownerSource ?? sourceList
        : sourceList;
    if (!sync.supported) {
      final synced = await sharing.engine.createOwned(
        displayName: displayName,
        source: source,
        sessionToken: sessionToken,
      );
      sharing.bumpState();
      return synced;
    }
    final reason = sync.unsyncableReason(source.key);
    if (reason != null) throw ListNotSyncableException(reason);
    final wrapper = await sync.ensureLinked(source.key);
    if (wrapper == null) {
      throw SyncException(
        SyncErrorKind.network,
        'the list is not on your account yet',
      );
    }
    await sharing.engine.setOwnedVisibility(
      wrapper.listId,
      listVisibilityShared,
      displayName: displayName,
    );
    Analytics.track('list_shared');
    sharing.bumpState();
    return wrapper;
  }

  /// Stop sharing [list]: it goes private (`PUT .../visibility`), its
  /// followers and editors lose it, and it stays on the person's devices.
  Future<void> stopSharing(SyncedEntryList list) async {
    if (!sharing.isEnabled) return;
    if (list.meta.role != ListRole.owner) return;
    await sharing.engine.setOwnedVisibility(list.listId, listVisibilityPrivate);
    sharing.bumpState();
  }

  /// Owner-only: rename a linked list on the server. The new name
  /// propagates to the owner's other devices and editors (on their next
  /// /sync) and subscribers (on their next R2 poll). The owner wrapper's
  /// local display name is refreshed from the server's reply.
  ///
  /// Validates [newName] with the same rules as a local list name
  /// (throwing [EntryListNameException] on empty / invalid / reserved)
  /// so the rename dialog can surface a localised message; the server
  /// re-validates as a backstop. A shared list may not take a reserved name
  /// (Favourites); a private one may. Throws [SyncException] on a network /
  /// server failure.
  Future<void> renameSharedList(SyncedEntryList owned, String newName) async {
    if (!sharing.isEnabled) {
      throw StateError('sharing is not configured for this app');
    }
    if (owned.meta.role != ListRole.owner) {
      // Only the creator can rename. The UI gates this with a toast; the
      // guard here stops a stray caller pushing a non-owner's rename.
      throw StateError('only the owner can rename a shared list');
    }
    // Validate the name (throws on empty / too long). The derived key is
    // discarded — linked lists keep their local key and go by the server's
    // name.
    EntryList.getKeyFromName(newName);
    final name = newName.trim();
    if (owned.meta.isShared && isReservedShareName(name)) {
      throw EntryListNameException(EntryListNameError.reserved, name);
    }
    final session = sharing.auth.store.current;
    if (session == null) {
      throw StateError('renameSharedList: not signed in');
    }
    await sharing.engine.renameOwned(owned.listId, name, session.sessionToken);
  }

  /// Subscriber-only: force a refresh of [list] from the server now.
  /// No-op for owner lists.
  Future<void> refreshSubscriber(SyncedEntryList list) async {
    if (!sharing.isEnabled) return;
    if (list.meta.role != ListRole.subscriber) return;
    await sharing.engine.refreshSubscriber(list.listId);
  }

  /// Force a refresh of any shared [list] from the server now, whatever
  /// the viewer's role (owner/editor/subscriber). Backs the pull-to-
  /// refresh on the shared-list and members pages.
  Future<void> refreshSyncedList(SyncedEntryList list) async {
    if (!sharing.isEnabled) return;
    Analytics.track('pull_to_refresh', props: {'scope': 'list'});
    await sharing.engine.refreshList(list.listId);
  }

  /// Subscriber-only: stop following a list someone else owns. The local
  /// mirror is removed (and, signed in, the account stops following it).
  Future<void> unsubscribeList(SyncedEntryList list) async {
    if (!sharing.isEnabled) return;
    if (list.meta.role != ListRole.subscriber) return;
    await sharing.engine.unsubscribe(list.listId);
  }

  /// Allocate a local list key derived from a display name that's free in
  /// [userEntryListManager] and survives [EntryList.getKeyFromName]'s
  /// validity rules.
  ///
  /// [preferredName] is tried first. If it can't round-trip through
  /// `getKeyFromName` (empty or too long), the algorithm switches to
  /// [fallbackBase] — which
  /// callers should pick from their own localisation (e.g. "Imported
  /// list", "Duplicated list"). Either way, a numeric suffix is appended
  /// until the resulting key is free: not another list's, and not one the
  /// app keeps a setting under (see [storageKeyBelongsToSomethingElse]).
  String allocateLocalKey({
    required String preferredName,
    required String fallbackBase,
  }) {
    String safeBase;
    try {
      EntryList.getKeyFromName(preferredName);
      safeBase = preferredName;
    } catch (_) {
      safeBase = fallbackBase;
    }
    var candidate = safeBase;
    for (var n = 2; ; n++) {
      final k = EntryList.getKeyFromName(candidate);
      // A key one of the app's own settings lives under counts as taken
      // too, the same as createEntryList would refuse it: a list that
      // arrives from elsewhere with such a name gets the suffix rather
      // than failing the import or the copy.
      if (!userEntryListManager.getEntryLists().containsKey(k) &&
          !storageKeyBelongsToSomethingElse(k)) {
        return k;
      }
      // Disambiguate with a " $n" suffix (space + digit) — keeps the
      // derived name readable and always survives getKeyFromName.
      candidate = '$safeBase $n';
    }
  }
}

/// Convenience global so callers don't have to type `ListsService.instance`
/// constantly. Mirrors the existing `userEntryListManager` / `sharing`
/// pattern.
ListsService get listsService => ListsService.instance;

/// Thrown by [ListsService.shareList] for a list that stays on this device
/// (see `UnsyncableReason`): too large to sync, say.
class ListNotSyncableException implements Exception {
  final String reason;
  const ListNotSyncableException(this.reason);
  @override
  String toString() => 'ListNotSyncableException($reason)';
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
  return localisedSyncError(
    context,
    e,
    notFoundMessage: fallback,
    unknownMessage: fallback,
  );
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
  // Checked ahead of the switch: this is a 403, but "you're at your list
  // limit" is a different thing to tell the user than "you don't have
  // permission", and only the reason discriminator separates them.
  if (e.isListLimitReached) {
    return l.shareTooManyListsBody(e.listLimit);
  }
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
    case SyncErrorKind.unavailable:
      return l.shareErrorServer;
    case SyncErrorKind.invalidBody:
    case SyncErrorKind.missingHeader:
    case SyncErrorKind.idCollision:
    case SyncErrorKind.unknownClient:
      return unknownMessage;
  }
}
