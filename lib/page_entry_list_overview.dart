import 'dart:async';

import 'package:dictionarylib/common.dart';
import 'package:dictionarylib/entry_list.dart';
import 'package:dictionarylib/globals.dart';
import 'package:dictionarylib/lists_service.dart';
import 'package:dictionarylib/sharing/auth/sign_in_dialog.dart';
import 'package:dictionarylib/sharing/share_dialog.dart';
import 'package:dictionarylib/sharing/sign_in_resume_banner.dart';
import 'package:dictionarylib/sharing/sync_engine.dart';
import 'package:dictionarylib/sharing/synced_entry_list.dart';
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

  /// Subscription to engine one-shot notifications (session expired,
  /// removed as editor). Surfaced as snackbars while this page is alive.
  StreamSubscription<SyncNotification>? _notificationSub;

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
      // Surface engine one-shot events (401 → sessionExpired, 403 →
      // removedAsEditor) as snackbars. Lives on this page because it's
      // the main entry point post-share.
      _notificationSub =
          sharing.engineNotifications.listen(_onEngineNotification);
    }
  }

  void _onEngineNotification(SyncNotification notification) {
    if (!mounted) return;
    final l = DictLibLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    switch (notification) {
      case SyncNotification.sessionExpired:
        messenger.showSnackBar(SnackBar(
          content: Text(l.engineSessionExpiredSnack),
          action: SnackBarAction(
            label: l.engineSessionExpiredSnackAction,
            onPressed: () async {
              if (!sharing.isEnabled) return;
              final session = await showSignInDialog(context,
                  contextMessage: l.signInDialogContextResume);
              if (session != null) {
                unawaited(sharing.engine.syncAll().then((_) {
                  if (mounted) setState(() {});
                }));
              }
            },
          ),
        ));
      case SyncNotification.removedAsEditor:
        messenger.showSnackBar(
            SnackBar(content: Text(l.engineRemovedAsEditorSnack)));
      case SyncNotification.snapshotCatchUp:
        messenger.showSnackBar(
            SnackBar(content: Text(l.engineSnapshotCatchUpSnack)));
    }
  }

  void _onSharingChanged() {
    if (mounted) setState(() {});
  }

  void _rebuildTabs({int? initialIndex}) {
    final tabs = <_TabDescriptor>[
      _TabDescriptor.myLists,
    ];
    if (_showCommunityLists()) tabs.add(_TabDescriptor.community);
    if (sharing.isEnabled) tabs.add(_TabDescriptor.sharedWithMe);
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
    _notificationSub?.cancel();
    tabController.removeListener(_onTabChange);
    tabController.dispose();
    super.dispose();
  }

  Future<void> _refreshSynced() async {
    if (!sharing.isEnabled) return;
    await sharing.engine.syncAll();
    if (mounted) setState(() {});
  }

  _TabDescriptor get _activeTab => _tabs[tabController.index];

  @override
  Widget build(BuildContext context) {
    FloatingActionButton? floatingActionButton;
    if (inEditMode) {
      floatingActionButton = FloatingActionButton(
          backgroundColor: Colors.green,
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

    // Only show the edit action for user lists.
    if (activeTab == _TabDescriptor.myLists) {
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
        () async {
          final subscribed = await showSubscribeDialog(context: context);
          if (subscribed != null && context.mounted) {
            setState(() {});
            await Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) =>
                        widget.buildEntryListWidgetCallback(subscribed)));
            if (mounted) setState(() {});
          }
        },
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
      tabsUi.add(Tab(text: t.label(context)));
      children.add(_buildTabBody(t));
    }

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
      final editable = sharing.lists.editableLists
          .where((l) => !l.meta.orphaned)
          .toList();
      body = Column(
        children: [
          SignInResumeBanner(lists: editable),
          Expanded(child: body),
        ],
      );
    }

    return TopLevelScaffold(
        underAppBar: showTabs
            ? TabBar(
                controller: tabController,
                tabs: tabsUi,
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
          return body;
        }(),
      _TabDescriptor.community =>
        getCommunityLists(context, widget.buildEntryListWidgetCallback),
      _TabDescriptor.sharedWithMe => RefreshIndicator(
          onRefresh: _refreshSynced, child: _buildSharedWithMeTab(context)),
    };
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
          Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              l.listSharedWithMeEmpty,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      );
    }
    return ListView(
      children: [
        for (final el in shared)
          Card(
            key: ValueKey('shared-${el.listId}'),
            child: ListTile(
              leading: el.getLeadingIcon(),
              minLeadingWidth: 10,
              title: Text(el.getName(context),
                  textAlign: TextAlign.start,
                  style: const TextStyle(fontSize: 16)),
              subtitle: Text(_formatSharedStatus(context, el),
                  style: const TextStyle(fontSize: 12)),
              onTap: () async {
                await Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) =>
                            widget.buildEntryListWidgetCallback(el)));
                if (mounted) setState(() {});
              },
            ),
          ),
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
    tiles.add(Card(
      key: ValueKey(el.key),
      child: ListTile(
        leading: owned != null
            ? Icon(iconForSharedList(owned.meta))
            : el.getLeadingIcon(),
        minLeadingWidth: 10,
        title: Text(el.getName(context),
            textAlign: TextAlign.start, style: const TextStyle(fontSize: 16)),
        subtitle: owned != null
            ? Text(_formatOwnedStatus(context, owned),
                style: const TextStyle(fontSize: 12))
            : null,
        onTap: () async {
          await Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (context) => buildEntryListWidgetCallback(target)));
        },
      ),
    ));
  }
  return ListView(children: tiles);
}

/// Edit-mode list — reorders the local user lists. Favourites stays pinned
/// at the top.
Widget _buildEditModeList(
    BuildContext context, void Function(void Function() fn) setState) {
  final tiles = <Widget>[];
  var i = 0;
  for (final e in userEntryListManager.getEntryLists().entries) {
    final el = e.value;
    final name = el.getName(context);
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
            icon: const Icon(Icons.remove_circle, color: Colors.red),
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
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(DictLibLocalizations.of(context)!
                          .unshareToDeleteTooltip)));
                },
              )
            : null);
    Widget tile = Card(
      key: ValueKey(name),
      child: ListTile(
        leading: el.getLeadingIcon(inEditMode: true),
        trailing: trailing,
        minLeadingWidth: 10,
        title: Text(name,
            textAlign: TextAlign.start, style: const TextStyle(fontSize: 16)),
      ),
    );
    if (isFavouritesLocal) {
      tile = IgnorePointer(key: ValueKey(name), child: tile);
    }
    tile = ReorderableDragStartListener(
        key: ValueKey(name), index: i, child: tile);
    tiles.add(tile);
    i++;
  }
  return ReorderableListView(
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
    Card card = Card(
      key: ValueKey(name),
      child: ListTile(
        leading: el.getLeadingIcon(inEditMode: false),
        minLeadingWidth: 10,
        title: Text(
          name,
          textAlign: TextAlign.start,
          style: const TextStyle(fontSize: 16),
        ),
        onTap: () async {
          await Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (context) => buildEntryListWidgetCallback(
                        el,
                      )));
        },
      ),
    );
    Widget toAdd = card;
    tiles.add(toAdd);
  }

  return ListView(
    children: tiles,
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
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('${l.listFailedToMake}: ${e.localise(context)}.'),
              backgroundColor: Colors.red));
        }
        confirmed = false;
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('${l.listFailedToMake}: $e.'),
              backgroundColor: Colors.red));
        }
        confirmed = false;
      }
    }
    return confirmed;
  } finally {
    disposeAfterFrame(controller);
  }
}
