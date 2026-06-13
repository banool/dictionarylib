import 'dart:async';

import 'package:dictionarylib/common.dart';
import 'package:dictionarylib/entry_list.dart';
import 'package:dictionarylib/globals.dart';
import 'package:dictionarylib/hearth.dart';
import 'package:dictionarylib/lists_service.dart';
import 'package:dictionarylib/retry.dart';
import 'package:dictionarylib/sharing/share_dialog.dart';
import 'package:dictionarylib/sharing/sign_in_resume_banner.dart';
import 'package:dictionarylib/sharing/sync_api.dart';
import 'package:dictionarylib/sharing/synced_entry_list.dart';
import 'package:dictionarylib/web_limitations.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dictionarylib/dictionarylib.dart'
    show DictLibLocalizations, getEntryListOverviewHelpPageEn;

import 'top_level_scaffold.dart';

typedef BuildEntryListWidgetCallback = Widget Function(EntryList entryList);

/// SharedPreferences key for the last-active tab on the lists overview.
const String KEY_LISTS_OVERVIEW_TAB_INDEX = 'lists_overview_tab_index';

class EntryListsOverviewPage extends StatefulWidget {
  final BuildEntryListWidgetCallback buildEntryListWidgetCallback;

  const EntryListsOverviewPage(
      {super.key, required this.buildEntryListWidgetCallback});

  @override
  EntryListsOverviewPageState createState() => EntryListsOverviewPageState();
}

class EntryListsOverviewPageState extends State<EntryListsOverviewPage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late TabController tabController;

  /// Tab descriptor — one per tab in display order. Used so we can give each
  /// tab a stable id (used for persistence) regardless of how many are
  /// actually visible at any moment.
  late List<_TabDescriptor> _tabs;

  bool inEditMode = false;

  @override
  void initState() {
    super.initState();
    _rebuildTabs();
    if (sharing.isEnabled) {
      // Fire-and-forget refresh of all synced lists on open.
      unawaited(sharing.engine.syncAll().then((_) {
        if (mounted) setState(() {});
      }));
      WidgetsBinding.instance.addObserver(this);
      // React to engine + auth changes (e.g. a /sync flush completes,
      // or a sign-out drops the session) so the unsynced banner reflects
      // the current state without the user pulling-to-refresh.
      sharing.addListener(_onSharingChanged);
      // Engine one-shot events (session expired, removed as editor, …)
      // are surfaced app-wide by installEngineNotificationSnackbars —
      // see engine_notification_listener.dart. Listening here too would
      // double the snackbars.
    }
  }

  void _onSharingChanged() {
    if (mounted) setState(() {});
  }

  void _rebuildTabs({int? initialIndex}) {
    final tabs = <_TabDescriptor>[
      _TabDescriptor.myLists,
    ];
    // Order: My Lists, Subscribed, Community.
    if (sharing.isEnabled) tabs.add(_TabDescriptor.sharedWithMe);
    if (_showCommunityLists()) tabs.add(_TabDescriptor.community);
    _tabs = tabs;

    final restored = initialIndex ?? _restoreTabIndex(tabs.length);
    tabController =
        TabController(initialIndex: restored, length: tabs.length, vsync: this);
    tabController.addListener(_onTabChange);
  }

  void _onTabChange() {
    if (!tabController.indexIsChanging) {
      // The animation has settled on a new tab. Persist + drop edit mode.
      sharedPreferences.setInt(
          KEY_LISTS_OVERVIEW_TAB_INDEX, _tabs[tabController.index].persistedId);
      if (inEditMode) {
        setState(() => inEditMode = false);
      } else {
        setState(() {});
      }
    }
  }

  int _restoreTabIndex(int length) {
    final saved = sharedPreferences.getInt(KEY_LISTS_OVERVIEW_TAB_INDEX);
    if (saved == null) return 0;
    final idx = _tabs.indexWhere((t) => t.persistedId == saved);
    if (idx < 0 || idx >= length) return 0;
    return idx;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!sharing.isEnabled) return;
    if (state == AppLifecycleState.resumed) {
      unawaited(sharing.engine.syncAll().then((_) {
        if (mounted) setState(() {});
      }));
    }
    // The pushAllDirty-on-paused hook used to live here too, but it's
    // now installed centrally in Sharing.setup so the flush happens
    // regardless of which screen is active when the OS backgrounds us.
  }

  // We only show community lists and therefore the tab view if there are
  // actually any community entry lists to show and user hasn't disabled it.
  bool _showCommunityLists() {
    var prefHideCommunityLists =
        sharedPreferences.getBool(KEY_HIDE_COMMUNITY_LISTS) ?? false;
    var communityLimitsPopulated =
        communityEntryListManager.getEntryLists().isNotEmpty;
    return communityLimitsPopulated && !prefHideCommunityLists;
  }

  @override
  void dispose() {
    if (sharing.isEnabled) {
      WidgetsBinding.instance.removeObserver(this);
      sharing.removeListener(_onSharingChanged);
    }
    tabController.removeListener(_onTabChange);
    tabController.dispose();
    super.dispose();
  }

  /// Pull-to-refresh over every shared list. [SyncEngine.syncAll] returns
  /// per-list failures rather than throwing; surface the first one (after
  /// retrying transient ones with on-screen feedback) so a dead network
  /// doesn't read as a successful refresh.
  Future<void> _refreshSynced() async {
    if (!sharing.isEnabled) return;
    try {
      await retryWithFeedback(
        () async {
          // User-initiated pull-to-refresh: bypass the worker edge cache so
          // a just-made change shows up immediately (see SyncApi.getList).
          final failures = await sharing.engine.syncAll(forceFresh: true);
          if (failures.isNotEmpty) throw failures.first;
        },
        onRetry: snackRetryFeedback(context),
      );
    } on SyncException catch (e) {
      if (mounted) {
        showSnack(
            context,
            DictLibLocalizations.of(context)!.subscribedSyncFailedSnack(
                localisedSyncErrorSimple(context, e, e.message)),
            replaceCurrent: true);
      }
    }
    if (mounted) setState(() {});
  }

  _TabDescriptor get _activeTab => _tabs[tabController.index];

  @override
  Widget build(BuildContext context) {
    FloatingActionButton? floatingActionButton;
    if (inEditMode) {
      floatingActionButton = FloatingActionButton(
          onPressed: () async {
            bool confirmed = await applyCreateListDialog(context);
            if (confirmed) {
              setState(() {
                inEditMode = false;
              });
            }
          },
          child: const Icon(Icons.add));
    }

    final activeTab = _activeTab;

    List<Widget> actions = [];

    // Only show the edit action for user lists — and not on web, where lists
    // can't be created or edited (no account).
    if (activeTab == _TabDescriptor.myLists && !kIsWeb) {
      actions.add(buildActionButton(
        context,
        inEditMode ? const Icon(Icons.edit) : const Icon(Icons.edit_outlined),
        () async {
          setState(() {
            inEditMode = !inEditMode;
          });
        },
      ));
    }

    // Subscribe-to-shared-list action — visible on the "Shared with me" tab
    // when sharing is wired up.
    if (activeTab == _TabDescriptor.sharedWithMe && sharing.isEnabled) {
      actions.add(buildActionButton(
        context,
        const Icon(Icons.cloud_download_outlined),
        () => _subscribeViaLink(),
      ));
    }

    actions.add(buildActionButton(
      context,
      const Icon(Icons.help),
      () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
              builder: (context) => getEntryListOverviewHelpPageEn()),
        );
      },
    ));

    final tabsUi = <Tab>[];
    final children = <Widget>[];
    for (final t in _tabs) {
      tabsUi.add(Tab(height: 38, child: Text(t.label(context))));
      children.add(_buildTabBody(t));
    }
    final cs = Theme.of(context).colorScheme;

    bool showTabs = tabsUi.length > 1;
    Widget body;
    if (showTabs) {
      body = TabBarView(controller: tabController, children: children);
    } else {
      body = children[0];
    }

    // Surface the sign-in nudge above the tab content so the user
    // sees it from any tab, not just "My lists". The banner widget
    // collapses to SizedBox.shrink when there's nothing to nudge about.
    if (sharing.isEnabled) {
      final editable =
          sharing.lists.editableLists.where((l) => !l.meta.orphaned).toList();
      body = Column(
        children: [
          SignInResumeBanner(lists: editable),
          Expanded(child: body),
        ],
      );
    }

    return TopLevelScaffold(
        underAppBar: showTabs
            ? PreferredSize(
                // 2 + 38 (tab) + 8 (container padding) + 10 = 58; matches the
                // content so the pill control doesn't overflow its slot.
                preferredSize: const Size.fromHeight(58),
                // A pill segmented control rather than an underline TabBar.
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
                  child: Container(
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    padding: const EdgeInsets.all(4),
                    child: TabBar(
                      controller: tabController,
                      tabs: tabsUi,
                      indicatorSize: TabBarIndicatorSize.tab,
                      dividerColor: Colors.transparent,
                      indicatorPadding: EdgeInsets.zero,
                      labelPadding: EdgeInsets.zero,
                      splashFactory: NoSplash.splashFactory,
                      overlayColor:
                          const WidgetStatePropertyAll(Colors.transparent),
                      indicator: BoxDecoration(
                        color: cs.surface,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: cs.shadow,
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                            spreadRadius: -4,
                          ),
                        ],
                      ),
                      labelColor: cs.onSurface,
                      unselectedLabelColor: cs.onSurfaceVariant,
                      labelStyle: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 13.5),
                      unselectedLabelStyle: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13.5),
                    ),
                  ),
                ),
              )
            : null,
        body: body,
        title: DictLibLocalizations.of(context)!.listsTitle,
        actions: actions,
        floatingActionButton: floatingActionButton);
  }

  Widget _buildTabBody(_TabDescriptor tab) {
    return switch (tab) {
      _TabDescriptor.myLists => () {
          var body = _getUserLists(context, setState,
              widget.buildEntryListWidgetCallback, inEditMode);
          // Pull-to-refresh, but not in edit mode (ReorderableListView
          // doesn't play nicely with it).
          if (sharing.isEnabled && !inEditMode) {
            body = RefreshIndicator(onRefresh: _refreshSynced, child: body);
          }
          if (kIsWeb) {
            // No local lists, favourites, or reorder hint on web — you can't
            // create or save them there. Just explain; the Community and
            // Shared-with-me tabs carry the read-only content.
            final l = DictLibLocalizations.of(context)!;
            return ListView(children: [
              WebLimitationsCard(
                heading: l.webLimitationsListsHeading,
                body: l.webLimitationsListsBody,
                footer: l.webLimitationsFooter,
              ),
            ]);
          }
          return body;
        }(),
      _TabDescriptor.community =>
        getCommunityLists(context, widget.buildEntryListWidgetCallback),
      _TabDescriptor.sharedWithMe => RefreshIndicator(
          onRefresh: _refreshSynced, child: _buildSharedWithMeTab(context)),
    };
  }

  /// Paste a share link / ID (or scan a QR) to follow a list. Following needs
  /// no account, so this lives in the tab content, not behind a sign-in wall.
  Future<void> _subscribeViaLink() async {
    final subscribed = await showSubscribeDialog(context: context);
    if (subscribed != null && context.mounted) {
      setState(() {});
      await Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => widget.buildEntryListWidgetCallback(subscribed)));
      if (mounted) setState(() {});
    }
  }

  Widget _subscribeViaLinkButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: _subscribeViaLink,
          icon: const Icon(Icons.add_link, size: 20),
          label: Text(DictLibLocalizations.of(context)!.listSubscribeViaLink),
        ),
      ),
    );
  }

  /// "Shared with me" — every synced list the user isn't the owner of:
  /// editor-mode (lists they were invited to and can edit) + subscriber-mode
  /// (read-only follows of someone else's share). Owner shares stay in My
  /// Lists alongside the local source list.
  Widget _buildSharedWithMeTab(BuildContext context) {
    if (!sharing.isEnabled) return const SizedBox.shrink();
    final l = DictLibLocalizations.of(context)!;
    final shared = [
      ...sharing.lists.editorLists,
      ...sharing.lists.subscribedLists,
    ];
    if (shared.isEmpty) {
      return ListView(
        // ListView (not Center) so pull-to-refresh still works on an empty
        // tab.
        children: [
          HearthEmptyState(
            icon: Icons.cloud_outlined,
            title: l.listSharedWithMeEmpty,
            body: l.listSubscribedEmptyBody,
            action: FilledButton.tonalIcon(
              onPressed: _subscribeViaLink,
              icon: const Icon(Icons.add_link, size: 18),
              label: Text(l.listSubscribeViaLink),
            ),
          ),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        for (final el in shared)
          HearthListRow(
            key: ValueKey('shared-${el.listId}'),
            leading: el.getLeadingIcon(),
            title: el.getName(context),
            subtitle: _formatSharedStatus(context, el),
            onTap: () async {
              await Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => widget.buildEntryListWidgetCallback(el)));
              if (mounted) setState(() {});
            },
          ),
        _subscribeViaLinkButton(),
      ],
    );
  }
}

/// One row in the lists overview's tab strip. [persistedId] is the stable
/// number written to prefs so the active tab survives tab-set changes
/// (e.g. community lists being enabled later) — don't renumber existing
/// values.
enum _TabDescriptor {
  myLists(0),
  community(1),
  sharedWithMe(2);

  final int persistedId;
  const _TabDescriptor(this.persistedId);

  String label(BuildContext context) {
    final l = DictLibLocalizations.of(context)!;
    return switch (this) {
      _TabDescriptor.myLists => l.listMyLists,
      _TabDescriptor.community => l.listCommunity,
      _TabDescriptor.sharedWithMe => l.listSharedWithMeTab,
    };
  }
}

Widget _getUserLists(
    BuildContext context,
    void Function(void Function() fn) setState,
    BuildEntryListWidgetCallback buildEntryListWidgetCallback,
    bool inEditMode) {
  if (inEditMode) {
    return _buildEditModeList(context, setState);
  }

  final tiles = <Widget>[];
  for (final el in listsService.myLists) {
    final owned = listsService.ownedShareFor(el);
    // Navigate to the owner wrapper when the list is shared, so that
    // edits made from the list page go through [SyncedEntryList.addEntry]
    // / [removeEntry] (which both mutate the underlying entries set and
    // enqueue a sync op). The wrapper shares its entries with the local
    // list, so the view stays identical to opening `el` directly.
    final target = owned ?? el;
    tiles.add(HearthListRow(
      key: ValueKey(el.key),
      leading: owned != null
          ? Icon(iconForSharedList(owned.meta))
          : el.getLeadingIcon(),
      // Owner-shared lists show the share's (renamable) display name.
      title: (owned ?? el).getName(context),
      // Shared lists show their sync status; plain lists show a word count.
      subtitle: owned != null
          ? _formatOwnedStatus(context, owned)
          : _wordCount(context, el),
      onTap: () async {
        await Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) => buildEntryListWidgetCallback(target)));
      },
    ));
  }
  // A gentle hint pointing at the edit (pencil) affordance, mirroring the
  // design's sparse-state guidance.
  tiles.add(Padding(
    padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
    child: Text(
      DictLibLocalizations.of(context)!.listsEditHint,
      textAlign: TextAlign.center,
      style: TextStyle(
          fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
    ),
  ));
  return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8), children: tiles);
}

/// A short "N words" subtitle for a list (counts distinct entries).
String _wordCount(BuildContext context, EntryList el) {
  return DictLibLocalizations.of(context)!
      .listWordCount(el.uniqueEntries.length);
}

/// Edit-mode list — reorders the local user lists. Favourites stays pinned
/// at the top.
Widget _buildEditModeList(
    BuildContext context, void Function(void Function() fn) setState) {
  final tiles = <Widget>[];
  var i = 0;
  for (final e in userEntryListManager.getEntryLists().entries) {
    final el = e.value;
    final isFavouritesLocal = el.key == KEY_FAVOURITES_ENTRIES;
    // Owner-shared lists can't be deleted directly: the local list is the
    // source of truth for the wrapper's entries, so dropping it would
    // strand the wrapper pointing at a missing source and leave the
    // server-side share unmanageable from this device. The user has to
    // unshare first (from the list page's share dialog).
    final ownedShare = listsService.ownedShareFor(el);
    final canDelete = el.canBeDeleted() && ownedShare == null;
    final trailing = canDelete
        ? IconButton(
            icon: Icon(Icons.remove_circle,
                color: Theme.of(context).colorScheme.error),
            onPressed: () async {
              final confirmed = await confirmAlert(
                  context,
                  Text(
                      DictLibLocalizations.of(context)!.listConfirmListDelete));
              if (confirmed) {
                await userEntryListManager.deleteEntryList(e.key);
                setState(() {});
              }
            })
        : (ownedShare != null
            ? IconButton(
                icon: Icon(iconForSharedList(ownedShare.meta),
                    color: Theme.of(context).hintColor),
                tooltip:
                    DictLibLocalizations.of(context)!.unshareToDeleteTooltip,
                onPressed: () {
                  showSnack(context,
                      DictLibLocalizations.of(context)!.unshareToDeleteTooltip);
                },
              )
            : null);
    // Tapping a list opens the rename dialog. Plain owned lists rename
    // locally; owner-shared lists rename on the server too (only the
    // creator — which is the user here, since owner-shares appear in My
    // Lists). Favourites (fixed name) stays untappable.
    final canRename = !isFavouritesLocal;
    Widget tile = HearthListRow(
      leading: el.getLeadingIcon(inEditMode: true),
      // Owner-shared lists show the share's display name (the renamable
      // one), not the underlying local key's name.
      title: (ownedShare ?? el).getName(context),
      trailing: trailing,
      showChevron: false,
      onTap: canRename
          ? () async {
              final renamed = ownedShare != null
                  ? await applyRenameSharedListDialog(context, ownedShare)
                  : await applyRenameListDialog(context, el);
              if (renamed) setState(() {});
            }
          : null,
    );
    if (isFavouritesLocal) {
      tile = IgnorePointer(key: ValueKey(el.key), child: tile);
    }
    tile = ReorderableDragStartListener(
        key: ValueKey(el.key), index: i, child: tile);
    tiles.add(tile);
    i++;
  }
  return ReorderableListView(
    // Match the non-edit list's top/bottom padding so toggling edit mode
    // doesn't shift the content vertically.
    padding: const EdgeInsets.symmetric(vertical: 8),
    // The reorder/rename hint sits below the last list rather than above
    // the first, so it reads as a footnote and doesn't push the lists down.
    footer: Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
      child: Text(
        DictLibLocalizations.of(context)!.listsReorderHint,
        textAlign: TextAlign.center,
        style: TextStyle(
            fontSize: 13,
            color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    ),
    children: tiles,
    onReorder: (prev, updated) async {
      setState(() {
        userEntryListManager.reorder(prev, updated);
      });
      await userEntryListManager.writeEntryListKeys();
    },
  );
}

/// Subtitle for a list this user owns + has shared. The cloud copy is just
/// a publication of the local list — what the user cares about is whether
/// it's been pushed yet, not the wall-clock time since the last poll
/// (which would look stale if they hadn't edited in a while).
String _formatOwnedStatus(BuildContext context, SyncedEntryList el) {
  final l = DictLibLocalizations.of(context)!;
  if (el.meta.orphaned) return l.ownedStatusOrphaned;
  final suffix = el.meta.pendingOps.isNotEmpty
      ? l.ownedStatusPendingSyncSuffix
      : l.ownedStatusSyncedSuffix;
  return '${l.ownedStatusSharedBy} · $suffix';
}

/// Subtitle for any list in "Shared with me" — editor or subscriber.
/// For editors with unpushed local ops, shows "pending sync" up front so
/// the user knows their edits haven't reached the server yet. Otherwise
/// shows the last-checked + last-server-updated pair.
String _formatSharedStatus(BuildContext context, SyncedEntryList el) {
  final l = DictLibLocalizations.of(context)!;
  if (el.meta.orphaned) return l.subscribedStatusOrphaned;
  if (el.meta.role == ListRole.editor && el.meta.pendingOps.isNotEmpty) {
    return l.ownedStatusPendingSyncSuffix;
  }
  final sync = _formatAgo(context, el.meta.lastSyncedAt);
  final updated = _formatAgo(context, el.meta.serverUpdatedAt);
  if (sync != null && updated != null) {
    return l.subscribedStatusSyncedAndUpdated(sync, updated);
  }
  // Either we never reached the server (sync==null) or the server hasn't
  // told us its updatedAt (updated==null); fall back to whichever we have.
  final syncedSentence = _formatLastSynced(context, el.meta.lastSyncedAt);
  return syncedSentence ?? l.subscribedStatusFallback;
}

/// Compact "5m ago" / "3h ago" / "2d ago" / "just now" for use inside
/// composite strings. For sentence-form ("synced 5m ago"), see
/// [_formatLastSynced].
String? _formatAgo(BuildContext context, int? secs) {
  if (secs == null) return null;
  final l = DictLibLocalizations.of(context)!;
  final age = DateTime.now().millisecondsSinceEpoch ~/ 1000 - secs;
  if (age < 60) return l.agoJustNow;
  if (age < 3600) return l.agoMinutes(age ~/ 60);
  if (age < 86400) return l.agoHours(age ~/ 3600);
  return l.agoDays(age ~/ 86400);
}

/// Sentence-form "synced 5m ago". Used as the subscriber-side fallback
/// when we have a `lastSyncedAt` but no `serverUpdatedAt` (which is the
/// case for lists subscribed before the `serverUpdatedAt` field existed).
String? _formatLastSynced(BuildContext context, int? lastSyncedSecs) {
  if (lastSyncedSecs == null) return null;
  final l = DictLibLocalizations.of(context)!;
  final age = DateTime.now().millisecondsSinceEpoch ~/ 1000 - lastSyncedSecs;
  if (age < 60) return l.syncedJustNow;
  if (age < 3600) return l.syncedMinutesAgo(age ~/ 60);
  if (age < 86400) return l.syncedHoursAgo(age ~/ 3600);
  return l.syncedDaysAgo(age ~/ 86400);
}

Widget getCommunityLists(BuildContext context,
    BuildEntryListWidgetCallback buildEntryListWidgetCallback) {
  List<Widget> tiles = [];
  for (MapEntry<String, EntryList> e
      in communityEntryListManager.getEntryLists().entries) {
    EntryList el = e.value;
    String name = el.getName(context);
    tiles.add(HearthListRow(
      key: ValueKey(name),
      leading: el.getLeadingIcon(inEditMode: false),
      title: name,
      subtitle: _wordCount(context, el),
      onTap: () async {
        await Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) => buildEntryListWidgetCallback(el)));
      },
    ));
  }

  return ListView(
    padding: const EdgeInsets.symmetric(vertical: 8),
    children: tiles,
  );
}

/// Shared rename dialog. Pre-fills [currentName] (caret at the end),
/// applies the same allowed-character rules as list creation, and calls
/// [onRename] with the entered text on confirm. On a validation / sync
/// failure it shows an error toast and stays unconfirmed. Returns true
/// on success.
Future<bool> _showRenameDialog(
  BuildContext context, {
  required String currentName,
  required Future<void> Function(String newName) onRename,
}) async {
  final controller = TextEditingController(text: currentName);
  // Put the caret at the end so editing starts from the existing name.
  controller.selection =
      TextSelection.collapsed(offset: controller.text.length);
  try {
    final l = DictLibLocalizations.of(context)!;
    final body = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(l.listNameAllowedChars),
        const Padding(padding: EdgeInsets.only(top: 10)),
        TextField(
          controller: controller,
          decoration: InputDecoration(hintText: l.listEnterNewName),
          autofocus: true,
          inputFormatters: [
            FilteringTextInputFormatter.allow(EntryList.validNameCharacters),
          ],
          textInputAction: TextInputAction.send,
          keyboardType: TextInputType.visiblePassword,
          textCapitalization: TextCapitalization.words,
        ),
      ],
    );
    var confirmed = await confirmAlert(context, body, title: l.listRenameList);
    if (confirmed) {
      try {
        await onRename(controller.text);
      } on EntryListNameException catch (e) {
        if (context.mounted) {
          showSnack(context, '${l.listFailedToRename}: ${e.localise(context)}.',
              backgroundColor: Theme.of(context).colorScheme.error);
        }
        confirmed = false;
      } on SyncException catch (e) {
        if (context.mounted) {
          showSnack(
              context,
              '${l.listFailedToRename}: '
              '${localisedSyncErrorSimple(context, e, l.listFailedToRename)}',
              backgroundColor: Theme.of(context).colorScheme.error);
        }
        confirmed = false;
      } catch (e) {
        if (context.mounted) {
          showSnack(context, '${l.listFailedToRename}: $e.',
              backgroundColor: Theme.of(context).colorScheme.error);
        }
        confirmed = false;
      }
    }
    return confirmed;
  } finally {
    disposeAfterFrame(controller);
  }
}

/// Returns true if [list] was renamed. Pre-fills the field with the
/// current name. Favourites can't be renamed, so callers should only
/// offer this for renamable lists.
Future<bool> applyRenameListDialog(BuildContext context, EntryList list) {
  return _showRenameDialog(
    context,
    currentName: list.getName(context),
    onRename: (newName) async {
      final newKey = EntryList.getKeyFromName(newName);
      await userEntryListManager.renameEntryList(list.key, newKey);
    },
  );
}

/// Returns true if the owner-shared list was renamed. Renames on the
/// server (which syncs the new name to editors + subscribers) and
/// refreshes the local owner wrapper.
Future<bool> applyRenameSharedListDialog(
    BuildContext context, SyncedEntryList owned) {
  return _showRenameDialog(
    context,
    currentName: owned.getName(context),
    // Renaming hits the server; retry transient failures with feedback
    // before the dialog's error handling surfaces the final failure.
    onRename: (newName) => retryWithFeedback(
        () => listsService.renameSharedList(owned, newName),
        onRetry: snackRetryFeedback(context)),
  );
}

// Returns true if a new list was created.
Future<bool> applyCreateListDialog(BuildContext context) async {
  final controller = TextEditingController();
  try {
    final l = DictLibLocalizations.of(context)!;
    final body = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(l.listNameAllowedChars),
        const Padding(padding: EdgeInsets.only(top: 10)),
        TextField(
          controller: controller,
          decoration: InputDecoration(hintText: l.listEnterNewName),
          autofocus: true,
          inputFormatters: [
            FilteringTextInputFormatter.allow(EntryList.validNameCharacters),
          ],
          textInputAction: TextInputAction.send,
          keyboardType: TextInputType.visiblePassword,
          textCapitalization: TextCapitalization.words,
        ),
      ],
    );
    var confirmed = await confirmAlert(context, body, title: l.listNewList);
    if (confirmed) {
      try {
        final key = EntryList.getKeyFromName(controller.text);
        await userEntryListManager.createEntryList(key);
      } on EntryListNameException catch (e) {
        if (context.mounted) {
          showSnack(context, '${l.listFailedToMake}: ${e.localise(context)}.',
              backgroundColor: Theme.of(context).colorScheme.error);
        }
        confirmed = false;
      } catch (e) {
        if (context.mounted) {
          showSnack(context, '${l.listFailedToMake}: $e.',
              backgroundColor: Theme.of(context).colorScheme.error);
        }
        confirmed = false;
      }
    }
    return confirmed;
  } finally {
    disposeAfterFrame(controller);
  }
}
