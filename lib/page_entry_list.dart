import 'dart:async';

import 'package:dictionarylib/common.dart';
import 'package:dictionarylib/entry_list.dart';
import 'package:dictionarylib/entry_types.dart';
import 'package:dictionarylib/globals.dart';
import 'package:dictionarylib/lists_service.dart';
import 'package:dictionarylib/page_entry_list_help_en.dart';
import 'package:dictionarylib/page_entry_list_overview.dart'
    show attemptRenameSharedList;
import 'package:dictionarylib/saved_video.dart';
import 'package:dictionarylib/sharing/list_members_page.dart';
import 'package:dictionarylib/sharing/share_dialog.dart';
import 'package:dictionarylib/sharing/sign_in_resume_banner.dart';
import 'package:dictionarylib/sharing/sync_api.dart';
import 'package:dictionarylib/sharing/synced_entry_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  /// Entries shown in the list — one row per unique entry that has at
  /// least one saved video. Filtered by [currentSearchTerm].
  late List<Entry> entriesSearched;

  bool viewSortedList = false;
  bool enableSortButton = true;
  bool inEditMode = false;

  bool _actionInflight = false;

  String currentSearchTerm = "";

  final textFieldFocus = FocusNode();
  final _searchFieldController = TextEditingController();

  @override
  void initState() {
    entriesSearched = widget.entryList.uniqueEntries.toList();
    super.initState();
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
    search();
  }

  void toggleSort() {
    setState(() {
      viewSortedList = !viewSortedList;
      search();
    });
  }

  void updateCurrentSearchTerm(String term) {
    setState(() {
      currentSearchTerm = term;
      enableSortButton = currentSearchTerm.isEmpty;
    });
  }

  void search() {
    setState(() {
      final unique = widget.entryList.uniqueEntries;
      if (currentSearchTerm.isNotEmpty) {
        if (inEditMode) {
          // Offer every entry that isn't already *fully* in the list — this
          // includes partially-saved entries (some of their videos saved, some
          // not) so the user can come back and add the rest. Only entries
          // whose every video is already saved drop out. We only need to test
          // the entries that have any saved video (a small set), then subtract
          // the fully-saved ones from the corpus.
          final fullySaved = <Entry>{
            for (final e in unique)
              if (widget.entryList.containsAllVideosOf(e)) e
          };
          final available = entriesGlobal.difference(fullySaved);
          entriesSearched = searchList(context, currentSearchTerm,
              EntryType.values, available, {});
        } else {
          entriesSearched = searchList(context, currentSearchTerm,
              EntryType.values, unique, unique);
        }
      } else {
        entriesSearched = unique.toList();
        if (viewSortedList) {
          // Sort by the displayed phrase, case-insensitively, so it reads
          // alphabetically rather than ASCII order (all capitals first).
          final locale = Localizations.localeOf(context);
          entriesSearched.sort((a, b) => compareDisplayNames(
              a.getPhrase(locale) ?? a.getKey(),
              b.getPhrase(locale) ?? b.getKey()));
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

  /// Edit-mode "add this entry" — adds every video of the entry, then
  /// the row falls out of the search results since it's no longer in
  /// the "available to add" set.
  Future<void> addEntry(Entry entry) async {
    await widget.entryList.addAllVideosOfEntry(entry);
    setState(() {
      search();
    });
  }

  /// Edit-mode "remove this entry" — removes every video the user had
  /// saved for the entry, after a confirm when more than one is saved.
  Future<void> removeEntry(Entry entry) async {
    final videos = widget.entryList.videosForEntry(entry);
    if (videos.length > 1) {
      final l = DictLibLocalizations.of(context)!;
      final confirmed = await confirmAlert(
        context,
        Text(l.listRemoveAllVideosBody(
            videos.length, entry.getPhrase(LOCALE_ENGLISH) ?? entry.getKey())),
        title: l.listRemoveAllVideosTitle,
      );
      if (!confirmed) return;
    }
    await widget.entryList.removeAllVideosOfEntry(entry);
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
          setState(() => _actionInflight = false);
          await _onUnsharePressed();
          return;
        }
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
        setState(() => search());
        showSnack(context, l.subscribedSyncDoneSnack);
      });

  Future<void> _onCopyLinkPressed() async {
    final list = widget.entryList;
    if (list is! SyncedEntryList) return;
    final l = DictLibLocalizations.of(context)!;
    await Clipboard.setData(
        ClipboardData(text: sharing.config.shareUrlFor(list.listId)));
    if (mounted) showSnack(context, l.shareLinkCopiedSnack);
  }

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
        final videos = list.savedVideos.toList();

        final localKey = listsService.allocateLocalKey(
          preferredName: list.getName(context),
          fallbackBase: l.duplicateFallbackName,
        );

        await userEntryListManager.createEntryList(localKey);
        final copy = userEntryListManager.getEntryLists()[localKey]!;
        for (final v in videos) {
          await copy.addVideo(v);
        }
        if (mounted) {
          final messenger = ScaffoldMessenger.of(context);
          showSnackVia(
              messenger, l.copyToMyListsSnack(EntryList.getNameFromKey(localKey)));
          Navigator.of(context).pop();
        }
      });

  @override
  Widget build(BuildContext context) {
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

    // Shared lists carry extra app-bar icons (share / members / sync menu).
    // Dropping the help button for them keeps the action count low enough
    // that the title stays centred (a 4th icon pushes it off-centre).
    bool isSharedList = false;
    if (sharing.isEnabled) {
      final list = widget.entryList;
      final isSubscribed =
          list is SyncedEntryList && list.meta.role == ListRole.subscriber;
      final ownedShare = listsService.ownedShareFor(list);
      isSharedList = list is SyncedEntryList || ownedShare != null;

      if (isSubscribed) {
        actions.add(PopupMenuButton<_ListMenuAction>(
          onSelected: (v) async {
            switch (v) {
              case _ListMenuAction.syncNow:
                await _onSyncNowPressed();
                break;
              case _ListMenuAction.copyLink:
                await _onCopyLinkPressed();
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
                  value: _ListMenuAction.copyLink,
                  child: item(Icons.link, l.subscribedCopyLinkMenuItem)),
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
        actions.add(buildActionButton(
          context,
          _PendingSyncIconBadge(
            dirty: list.meta.pendingOps.isNotEmpty,
            child: const Icon(Icons.group),
          ),
          () async => _openMembersPage(list),
        ));
      } else if (ownedShare != null || list.canBeEdited()) {
        actions.add(buildActionButton(
          context,
          _PendingSyncIconBadge(
            dirty: (ownedShare?.meta.pendingOps.isNotEmpty) ?? false,
            child: const Icon(Icons.share),
          ),
          () async => _onSharePressed(),
        ));
        if (ownedShare != null) {
          actions.add(buildActionButton(
            context,
            const Icon(Icons.group),
            () async => _openMembersPage(ownedShare),
          ));
        }
      }
    }

    if (!isSharedList) {
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
    }

    String listName = widget.entryList.getName(context);

    // Sort button. It's hidden while a search is active (below), so its
    // onPressed can sort unconditionally. The label names the *current* mode
    // ("Added" = insertion order, "A-Z" = alphabetical) and the up/down arrows
    // hint that tapping toggles it.
    FloatingActionButton? floatingActionButton = FloatingActionButton.extended(
      onPressed: toggleSort,
      icon: const Icon(Icons.swap_vert),
      label: Text(viewSortedList
          ? DictLibLocalizations.of(context)!.listSortAlpha
          : DictLibLocalizations.of(context)!.listSortAdded),
    );

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
            child: const Icon(Icons.add));
      }
    } else {
      hintText =
          "${DictLibLocalizations.of(context)!.listSearchPrefix} $listName";
      // Sorting a filtered view is meaningless — hide the sort button while a
      // search is active rather than leaving a dead no-op button.
      if (!enableSortButton) floatingActionButton = null;
    }

    final entryList = widget.entryList;
    final bannerLists = (entryList is SyncedEntryList &&
            (entryList.meta.role == ListRole.owner ||
                entryList.meta.role == ListRole.editor) &&
            !entryList.meta.orphaned &&
            entryList.meta.pendingOps.isNotEmpty)
        ? [entryList]
        : const <SyncedEntryList>[];

    // The app-bar title doubles as a rename affordance for shared lists
    // the user can edit: owners get the rename dialog, editors get a
    // "only the creator can rename" toast. Plain local + subscriber
    // lists keep a static title.
    Widget titleWidget = Text(widget.entryList.getName(context),
        overflow: TextOverflow.ellipsis);
    if (entryList is SyncedEntryList &&
        !entryList.meta.orphaned &&
        (entryList.meta.role == ListRole.owner ||
            entryList.meta.role == ListRole.editor)) {
      titleWidget = InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () async {
          final renamed = await attemptRenameSharedList(context, entryList);
          if (renamed && mounted) setState(() {});
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(entryList.getName(context),
                    overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 6),
              Icon(Icons.edit,
                  size: 15,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: titleWidget,
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
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Form(
                  child: Column(children: <Widget>[
                TextField(
                  controller: _searchFieldController,
                  focusNode: textFieldFocus,
                  decoration: InputDecoration(
                    hintText: hintText,
                    prefixIcon: const Icon(Icons.search),
                    // Match the main search page: only offer the clear button
                    // once there's something to clear.
                    suffixIcon: currentSearchTerm.isEmpty
                        ? null
                        : IconButton(
                            onPressed: clearSearch,
                            icon: const Icon(Icons.close),
                          ),
                  ),
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
              child: listWidget(
                context,
                entriesSearched,
                refreshEntries,
                widget.navigateToEntryPage,
                entryList: widget.entryList,
                deleteEntryFn: inEditMode && currentSearchTerm.isEmpty
                    ? removeEntry
                    : null,
                addEntryFn: inEditMode && currentSearchTerm.isNotEmpty
                    ? addEntry
                    : null,
              ),
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
  /// The list we're showing rows from. Used to look up "how many videos
  /// of this entry are saved" for the subtitle, and the first saved
  /// video for the focus-on-tap target. Null when the caller is in
  /// edit-mode "add to list" search results (where rows represent
  /// entries NOT yet in the list).
  EntryList? entryList,
  Future<void> Function(Entry)? deleteEntryFn,
  Future<void> Function(Entry)? addEntryFn,
}) {
  return ListView.builder(
    itemCount: entriesSearched.length,
    itemBuilder: (context, index) {
      Entry entry = entriesSearched[index]!;
      Widget? trailing;
      final cs = Theme.of(context).colorScheme;
      if (deleteEntryFn != null) {
        trailing = IconButton(
          padding: const EdgeInsets.only(left: 8, right: 16, top: 8, bottom: 8),
          icon: Icon(Icons.remove_circle, color: cs.error),
          onPressed: () async => await deleteEntryFn(entry),
        );
      }
      if (addEntryFn != null) {
        // Only offer one-tap "add" when the entry has a single video overall —
        // there's no ambiguity about what gets saved. When an entry has
        // multiple videos (across its sub-entries), show an arrow into the
        // entry instead, so the user can pick which video(s) to save in the
        // context of this list.
        if (allVideosOf(entry).length <= 1) {
          trailing = IconButton(
            padding:
                const EdgeInsets.only(left: 8, right: 16, top: 8, bottom: 8),
            icon: Icon(Icons.add_circle, color: cs.tertiary),
            onPressed: () async => await addEntryFn(entry),
          );
        } else {
          trailing = IconButton(
            padding:
                const EdgeInsets.only(left: 8, right: 16, top: 8, bottom: 8),
            icon: Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
            onPressed: () async {
              await navigateToEntryPage(context, entry, true,
                  saveToList: entryList);
              await refreshEntriesFn();
            },
          );
        }
      }
      // View mode shows a chevron affordance into the entry.
      trailing ??= Icon(Icons.chevron_right, color: cs.onSurfaceVariant);
      return ListTile(
        key: ValueKey(entry.getKey()),
        title: listItem(context, entry, refreshEntriesFn, navigateToEntryPage,
            entryList: entryList,
            // In edit-mode "add" search, tapping the row should also land the
            // user in the save-to-this-list context.
            saveToList: addEntryFn != null ? entryList : null),
        trailing: trailing,
      );
    },
  );
}

/// Single row for an entry in the list view.
///
/// Subtitle shows how many of the entry's videos are saved in this list
/// ("1 video saved", "3 videos saved"). Tap navigates to the
/// entry page, jumped to the user's first saved video for the entry
/// (so a list of three favourite "hello" videos opens directly on the
/// one they care about, not the corpus-default first one).
Widget listItem(BuildContext context, Entry entry, Function refreshEntriesFn,
    NavigateToEntryPageFn navigateToEntryPage,
    {EntryList? entryList, EntryList? saveToList}) {
  Locale currentLocale = Localizations.localeOf(context);
  var text = entry.getPhrase(currentLocale) ?? entry.getKey();

  final saved = entryList?.videosForEntry(entry) ?? const <SavedVideo>[];
  final focus = saved.isNotEmpty ? saved.first : null;

  Widget? subtitle;
  if (saved.isNotEmpty) {
    final l = DictLibLocalizations.of(context);
    final label = l?.listSavedVideoCount(saved.length) ??
        (saved.length == 1 ? '1 video saved' : '${saved.length} videos saved');
    subtitle = Text(label,
        style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant));
  }

  return TextButton(
    style: TextButton.styleFrom(
      alignment: Alignment.topLeft,
      padding: EdgeInsets.zero,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(text,
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface)),
        if (subtitle != null) Padding(
            padding: const EdgeInsets.only(top: 2), child: subtitle),
      ],
    ),
    onPressed: () async {
      await navigateToEntryPage(context, entry, true,
          focusVideo: focus, saveToList: saveToList);
      await refreshEntriesFn();
    },
  );
}

enum _ListMenuAction { syncNow, copyLink, copy, unsubscribe }

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
