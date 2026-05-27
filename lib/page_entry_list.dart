import 'dart:async';

import 'package:dictionarylib/common.dart';
import 'package:dictionarylib/entry_list.dart';
import 'package:dictionarylib/entry_types.dart';
import 'package:dictionarylib/globals.dart';
import 'package:dictionarylib/lists_service.dart';
import 'package:dictionarylib/page_entry_list_help_en.dart';
import 'package:dictionarylib/sharing/list_members_page.dart';
import 'package:dictionarylib/sharing/share_dialog.dart';
import 'package:dictionarylib/sharing/sign_in_resume_banner.dart';
import 'package:dictionarylib/sharing/sync_api.dart';
import 'package:dictionarylib/sharing/synced_entry_list.dart';
import 'package:flutter/material.dart';
import 'package:dictionarylib/dictionarylib.dart' show DictLibLocalizations;

class EntryListPage extends StatefulWidget {
  final EntryList entryList;

  final NavigateToEntryPageFn navigateToEntryPage;

  const EntryListPage({
    super.key,
    required this.entryList,
    required this.navigateToEntryPage,
  });

  @override
  EntryListPageState createState() => EntryListPageState();
}

class EntryListPageState extends State<EntryListPage> {
  // The entries that match the user's search term.
  late List<Entry> entriesSearched;

  bool viewSortedList = false;
  bool enableSortButton = true;
  bool inEditMode = false;

  /// Guards the share / unshare / sync-now / unsubscribe / copy
  /// handlers against double-taps and re-entrant invocations. Each
  /// handler short-circuits when this is true and flips it via
  /// try/finally so an error path doesn't strand it as true.
  bool _actionInflight = false;

  String currentSearchTerm = "";

  final textFieldFocus = FocusNode();
  final _searchFieldController = TextEditingController();

  @override
  void initState() {
    entriesSearched = List.from(widget.entryList.entries);
    super.initState();
    // Re-run the search whenever sharing state changes — covers the
    // case where a background /sync brings in another editor's
    // additions/removals while this page is open. Without this, the
    // ListenableBuilder-driven rebuild would re-render with the same
    // stale `entriesSearched` list.
    sharing.addListener(_onSharingChanged);
  }

  @override
  void dispose() {
    sharing.removeListener(_onSharingChanged);
    textFieldFocus.dispose();
    _searchFieldController.dispose();
    super.dispose();
  }

  void _onSharingChanged() {
    if (!mounted) return;
    // Refresh entriesSearched against the latest entries set. search()
    // calls setState internally.
    search();
  }

  void toggleSort() {
    setState(() {
      viewSortedList = !viewSortedList;
      search();
    });
  }

  Color getFloatingActionButtonColor(BuildContext context) {
    ColorScheme currentTheme = Theme.of(context).colorScheme;
    return enableSortButton ? currentTheme.onPrimary : Colors.grey;
  }

  void updateCurrentSearchTerm(String term) {
    setState(() {
      currentSearchTerm = term;
      enableSortButton = currentSearchTerm.isEmpty;
    });
  }

  void search() {
    setState(() {
      if (currentSearchTerm.isNotEmpty) {
        if (inEditMode) {
          Set<Entry> entriesGlobalWithoutEntriesAlreadyInList =
              entriesGlobal.difference(widget.entryList.entries);
          entriesSearched = searchList(context, currentSearchTerm,
              EntryType.values, entriesGlobalWithoutEntriesAlreadyInList, {});
        } else {
          entriesSearched = searchList(
              context,
              currentSearchTerm,
              EntryType.values,
              widget.entryList.entries,
              widget.entryList.entries);
        }
      } else {
        entriesSearched = List.from(widget.entryList.entries);
        if (viewSortedList) {
          entriesSearched.sort();
        }
      }
    });
  }

  void clearSearch() {
    setState(() {
      entriesSearched = [];
      _searchFieldController.clear();
      updateCurrentSearchTerm("");
      search();
    });
  }

  Future<void> addEntry(Entry entry) async {
    await widget.entryList.addEntry(entry);
    setState(() {
      search();
    });
  }

  Future<void> removeEntry(Entry entry) async {
    await widget.entryList.removeEntry(entry);
    setState(() {
      search();
    });
  }

  Future<void> refreshEntries() async {
    setState(() {
      search();
    });
  }

  Future<void> _openMembersPage(SyncedEntryList list) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ListMembersPage(list: list),
    ));
    if (mounted) setState(() {});
  }

  /// Run [body] under the `_actionInflight` guard. Re-entrant /
  /// double-tap invocations short-circuit; the flag is always cleared
  /// in `finally` so an error doesn't strand it as `true`.
  Future<void> _runGuarded(Future<void> Function() body) async {
    if (_actionInflight) return;
    setState(() => _actionInflight = true);
    try {
      await body();
    } finally {
      if (mounted) setState(() => _actionInflight = false);
    }
  }

  Future<void> _onSharePressed() => _runGuarded(() async {
        if (!sharing.isEnabled) return;
        SyncedEntryList? owned = listsService.ownedShareFor(widget.entryList);
        final freshlyShared = owned == null;
        if (owned == null) {
          // Not shared yet — collect a display name and create the share first.
          owned = await showShareDialog(
              context: context, sourceList: widget.entryList);
          if (owned == null || !mounted) return;
        }
        final wantsUnshare = await showShareLinkDialog(
          context: context,
          shareUrl: sharing.config.shareUrlFor(owned.listId),
          displayName: owned.meta.displayName,
          showUnshareButton: true,
        );
        if (!mounted) return;
        if (wantsUnshare) {
          // Drop the inflight guard before re-entering: _onUnsharePressed
          // takes the same guard and would otherwise short-circuit.
          setState(() => _actionInflight = false);
          await _onUnsharePressed();
          return;
        }
        // The page was constructed with the plain local list; subsequent edits
        // through `widget.entryList.addEntry` would bypass the owner wrapper's
        // op-enqueue. Swap to the wrapper so this session keeps syncing.
        if (freshlyShared) {
          await Navigator.of(context).pushReplacement(MaterialPageRoute(
            builder: (_) => EntryListPage(
              entryList: owned!,
              navigateToEntryPage: widget.navigateToEntryPage,
            ),
          ));
        } else {
          setState(() {});
        }
      });

  Future<void> _onUnsharePressed() => _runGuarded(() async {
        final owned = listsService.ownedShareFor(widget.entryList);
        if (owned == null) return;
        final l = DictLibLocalizations.of(context)!;
        // Pass the unshare call as onConfirm so the dialog keeps the spinner
        // up while the DELETE is in flight and only dismisses on success.
        // Failure stays on the prompt with an error snackbar so the user can
        // retry.
        final confirmed = await confirmAlert(
          context,
          Text(l.unshareConfirmBody),
          title: l.unshareConfirmTitle,
          onConfirm: () => listsService.unshareList(owned),
          errorMessage: (e) =>
              e is SyncException ? l.unshareFailed(e.message) : e.toString(),
        );
        if (confirmed && mounted) setState(() {});
      });

  Future<void> _onSyncNowPressed() => _runGuarded(() async {
        final list = widget.entryList;
        if (list is! SyncedEntryList) return;
        final l = DictLibLocalizations.of(context)!;
        final ok = await runWithProgress(
          context: context,
          message: l.subscribedSyncInProgress,
          task: () => listsService.refreshSubscriber(list),
          errorMessage: (e) => e is SyncException
              ? l.subscribedSyncFailedSnack(e.message)
              : '$e',
        );
        if (!ok || !mounted) return;
        // refreshSubscriber may have replaced entries — rerun search so the
        // list view reflects the new contents.
        setState(() => search());
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l.subscribedSyncDoneSnack)));
      });

  Future<void> _onUnsubscribePressed() => _runGuarded(() async {
        final list = widget.entryList;
        if (list is! SyncedEntryList) return;
        final l = DictLibLocalizations.of(context)!;
        final confirmed = await confirmAlert(
          context,
          Text(l.unsubscribeConfirmBody),
          title: l.unsubscribeConfirmTitle,
        );
        if (!confirmed || !mounted) return;
        await listsService.unsubscribeList(list);
        if (mounted) Navigator.of(context).pop();
      });

  Future<void> _onCopyToMyListsPressed() => _runGuarded(() async {
        final l = DictLibLocalizations.of(context)!;
        final confirmed = await confirmAlert(
          context,
          Text(l.duplicateConfirmBody),
          title: l.duplicateConfirmTitle,
          confirmText: l.duplicateConfirmAction,
        );
        if (!confirmed || !mounted) return;

        final list = widget.entryList;
        final keys = list.entries.map((e) => e.getKey()).toList();
        final totalCount = keys.length;

        // Subscribed lists' display names are free-form (emoji, reserved
        // words, special chars); local list IDs are restricted. The shared
        // allocator routes unsupported names to a localised fallback and
        // appends a numeric suffix on collision.
        final localKey = listsService.allocateLocalKey(
          preferredName: list.getName(context),
          fallbackBase: l.duplicateFallbackName,
        );

        await userEntryListManager.createEntryList(localKey);
        final copy = userEntryListManager.getEntryLists()[localKey]!;
        var copiedCount = 0;
        for (final k in keys) {
          final entry = keyedByEnglishEntriesGlobal[k];
          if (entry != null) {
            copy.entries.add(entry);
            copiedCount++;
          }
        }
        await copy.write();
        if (mounted) {
          final messenger = ScaffoldMessenger.of(context);
          messenger.showSnackBar(SnackBar(
              content: Text(
                  l.copyToMyListsSnack(EntryList.getNameFromKey(localKey)))));
          // Surface a follow-up snack if some entries dropped because their
          // keys are no longer in the dictionary. Two snackbars stacked
          // (the first one will be dismissed by the second).
          if (copiedCount < totalCount) {
            final dropped = totalCount - copiedCount;
            messenger.showSnackBar(SnackBar(
                content: Text(l.forkPartialDrop(
                    copiedCount, totalCount, dropped))));
          }
          Navigator.of(context).pop();
        }
      });

  @override
  Widget build(BuildContext context) {
    // Rebuild whenever sharing state changes (push completes, share/unshare,
    // dirty flips) so the pending-sync badge on the share icon reflects
    // reality without explicit setState from those code paths. For the
    // disabled sentinel this is harmless — nothing ever calls
    // [Sharing.bumpState], so the builder never rebuilds.
    return ListenableBuilder(
      listenable: sharing,
      builder: (context, _) => _buildScaffold(context),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    List<Widget> actions = [];
    if (widget.entryList.canBeEdited()) {
      actions.add(buildActionButton(
        context,
        inEditMode ? const Icon(Icons.edit) : const Icon(Icons.edit_outlined),
        () async {
          setState(() {
            inEditMode = !inEditMode;
            if (!inEditMode) {
              clearSearch();
            }
            search();
          });
        },
      ));
    }

    if (sharing.isEnabled) {
      final list = widget.entryList;
      final isSubscribed =
          list is SyncedEntryList && list.meta.role == ListRole.subscriber;
      final ownedShare = listsService.ownedShareFor(list);

      if (isSubscribed) {
        // Subscriber — overflow menu (copy / unsubscribe). The share icon
        // doesn't apply because the user doesn't own this list.
        actions.add(PopupMenuButton<_ListMenuAction>(
          onSelected: (v) async {
            switch (v) {
              case _ListMenuAction.syncNow:
                await _onSyncNowPressed();
                break;
              case _ListMenuAction.copy:
                await _onCopyToMyListsPressed();
                break;
              case _ListMenuAction.unsubscribe:
                await _onUnsubscribePressed();
                break;
            }
          },
          itemBuilder: (ctx) {
            final l = DictLibLocalizations.of(ctx)!;
            // Bare `Icon` widgets inherit from the ambient IconTheme,
            // which inside a popup menu spawned from an AppBar can pick
            // up the AppBar's icon color (white on dark builds) instead
            // of the menu's surface color. Match the icon to the menu's
            // text colour so we're invariant to wherever the popup was
            // triggered from.
            final menuIconColor = Theme.of(ctx).colorScheme.onSurface;
            Widget item(IconData icon, String label) => Row(children: [
                  Icon(icon, size: 20, color: menuIconColor),
                  const SizedBox(width: 12),
                  Text(label),
                ]);
            return [
              PopupMenuItem(
                  value: _ListMenuAction.syncNow,
                  child: item(Icons.sync, l.subscribedSyncNowMenuItem)),
              PopupMenuItem(
                  value: _ListMenuAction.copy,
                  child: item(Icons.copy_all, l.subscribedCopyMenuItem)),
              PopupMenuItem(
                  value: _ListMenuAction.unsubscribe,
                  child: item(Icons.cloud_off, l.unsubscribeConfirmTitle)),
            ];
          },
        ));
      } else if (list is SyncedEntryList && list.meta.role == ListRole.editor) {
        // Editor-mode shared list: members button (no share icon —
        // editors can't reshare; the creator controls the membership).
        actions.add(buildActionButton(
          context,
          _PendingSyncIconBadge(
            dirty: list.meta.pendingOps.isNotEmpty,
            child: const Icon(Icons.group),
          ),
          () async => _openMembersPage(list),
        ));
      } else if (ownedShare != null || list.canBeEdited()) {
        // Both "share this list" and "re-open the share-link page for an
        // already-shared list" go through the same icon — the dialog
        // itself surfaces the destructive Unshare button when applicable.
        // A tiny spinner at the bottom-left indicates an unpushed local
        // edit (debounced push pending).
        actions.add(buildActionButton(
          context,
          _PendingSyncIconBadge(
            dirty: (ownedShare?.meta.pendingOps.isNotEmpty) ?? false,
            child: const Icon(Icons.share),
          ),
          () async => _onSharePressed(),
        ));
        if (ownedShare != null) {
          // Once published, owners also get a "Members" action to
          // invite editors and see the who's-who view.
          actions.add(buildActionButton(
            context,
            const Icon(Icons.group),
            () async => _openMembersPage(ownedShare),
          ));
        }
      }
    }

    actions.add(
      buildActionButton(
        context,
        const Icon(Icons.help),
        () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => getEntryListHelpPageEn()),
          );
        },
      ),
    );

    String listName = widget.entryList.getName(context);

    FloatingActionButton? floatingActionButton = FloatingActionButton(
        onPressed: () {
          if (!enableSortButton) {
            return;
          }
          toggleSort();
        },
        child: const Icon(Icons.sort));

    String hintText;
    if (inEditMode) {
      hintText = DictLibLocalizations.of(context)!.listSearchAdd;
      bool keyboardIsShowing = MediaQuery.of(context).viewInsets.bottom > 0;
      if (currentSearchTerm.isNotEmpty || keyboardIsShowing) {
        floatingActionButton = null;
      } else {
        floatingActionButton = FloatingActionButton(
            onPressed: () {
              textFieldFocus.requestFocus();
            },
            backgroundColor: Colors.green,
            child: const Icon(Icons.add));
      }
    } else {
      hintText =
          "${DictLibLocalizations.of(context)!.listSearchPrefix} $listName";
    }

    // Inline "session expired — sign in to push" banner. Visible only
    // for owner/editor lists that have queued ops the engine can't
    // flush without a session. Mirrors the overview-screen banner so
    // users editing in-place see the same call to action.
    final entryList = widget.entryList;
    final bannerLists = (entryList is SyncedEntryList &&
            (entryList.meta.role == ListRole.owner ||
                entryList.meta.role == ListRole.editor) &&
            !entryList.meta.orphaned &&
            entryList.meta.pendingOps.isNotEmpty)
        ? [entryList]
        : const <SyncedEntryList>[];

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.entryList.getName(context)),
        centerTitle: true,
        actions: buildActionButtons(actions),
      ),
      floatingActionButton: floatingActionButton,
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 0.0, vertical: 8.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          mainAxisSize: MainAxisSize.max,
          children: [
            if (bannerLists.isNotEmpty)
              SignInResumeBanner(lists: bannerLists),
            Padding(
              padding: const EdgeInsets.only(
                  bottom: 10, left: 32, right: 32, top: 0),
              child: Form(
                  child: Column(children: <Widget>[
                TextField(
                  controller: _searchFieldController,
                  focusNode: textFieldFocus,
                  decoration: InputDecoration(
                    hintText: hintText,
                    suffixIcon: IconButton(
                      onPressed: () {
                        clearSearch();
                      },
                      icon: const Icon(Icons.clear),
                    ),
                  ),
                  // The validator receives the text that the user has entered.
                  onChanged: (String value) {
                    updateCurrentSearchTerm(value);
                    search();
                  },
                  autofocus: false,
                  textInputAction: TextInputAction.search,
                  keyboardType: TextInputType.visiblePassword,
                  autocorrect: false,
                ),
              ])),
            ),
            Expanded(
                child: Padding(
              padding: const EdgeInsets.only(left: 8),
              child: listWidget(context, entriesSearched, refreshEntries,
                  widget.navigateToEntryPage,
                  showFavouritesButton:
                      widget.entryList.key == KEY_FAVOURITES_ENTRIES,
                  deleteEntryFn: inEditMode && currentSearchTerm.isEmpty
                      ? removeEntry
                      : null,
                  addEntryFn: inEditMode && currentSearchTerm.isNotEmpty
                      ? addEntry
                      : null),
            )),
          ],
        ),
      ),
    );
  }
}

Widget listWidget(
  BuildContext context,
  List<Entry?> entriesSearched,
  Function refreshEntriesFn,
  NavigateToEntryPageFn navigateToEntryPage, {
  bool showFavouritesButton = true,
  Future<void> Function(Entry)? deleteEntryFn,
  Future<void> Function(Entry)? addEntryFn,
}) {
  return ListView.builder(
    itemCount: entriesSearched.length,
    itemBuilder: (context, index) {
      Entry entry = entriesSearched[index]!;
      Widget? trailing;
      if (deleteEntryFn != null) {
        trailing = IconButton(
          padding: const EdgeInsets.only(left: 8, right: 16, top: 8, bottom: 8),
          icon: const Icon(
            Icons.remove_circle,
            color: Colors.red,
          ),
          onPressed: () async => await deleteEntryFn(entry),
        );
      }
      if (addEntryFn != null) {
        trailing = IconButton(
          padding: const EdgeInsets.only(left: 8, right: 16, top: 8, bottom: 8),
          icon: Icon(
            Icons.add_circle,
            color: Colors.green,
          ),
          onPressed: () async => await addEntryFn(entry),
        );
      }
      return ListTile(
        key: ValueKey(entry.getKey()),
        title: listItem(context, entry, refreshEntriesFn, navigateToEntryPage,
            showFavouritesButton: showFavouritesButton),
        trailing: trailing,
      );
    },
  );
}

// We can pass in showFavouritesButton and set it to false for lists that
// aren't the the favourites list, since that star icon might be confusing
// and lead people to beleive they're interacting with the non-favourites
// list they just came from.
Widget listItem(BuildContext context, Entry entry, Function refreshEntriesFn,
    NavigateToEntryPageFn navigateToEntryPage,
    {bool showFavouritesButton = true}) {
  // Try to show the text in the selected locale but if not possible,
  // fallback to the key, which in this case is the word in English.
  Locale currentLocale = Localizations.localeOf(context);
  var text = entry.getPhrase(currentLocale) ?? entry.getKey();

  return TextButton(
    child: Align(
        alignment: Alignment.topLeft,
        child: Text(
          text,
        )),
    onPressed: () async => {
      await navigateToEntryPage(context, entry, showFavouritesButton),
      await refreshEntriesFn(),
    },
  );
}

enum _ListMenuAction { syncNow, copy, unsubscribe }

/// AppBar icon with an optional small spinner overlay in the bottom-left
/// corner. Used by the share / members icons to signal there are local
/// pending ops the engine hasn't pushed to the server yet (debounced
/// push pending).
class _PendingSyncIconBadge extends StatelessWidget {
  final Widget child;
  final bool dirty;
  const _PendingSyncIconBadge({required this.child, required this.dirty});

  @override
  Widget build(BuildContext context) {
    if (!dirty) return child;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          left: 0,
          bottom: 0,
          child: SizedBox(
            width: 10,
            height: 10,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
      ],
    );
  }
}
