import 'package:dictionarylib/common.dart';
import 'package:dictionarylib/entry_list.dart';
import 'package:dictionarylib/globals.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dictionarylib/dictionarylib.dart'
    show DictLibLocalizations, getEntryListOverviewHelpPageEn;

import 'top_level_scaffold.dart';

typedef BuildEntryListWidgetCallback = Widget Function(EntryList entryList);

class EntryListsOverviewPage extends StatefulWidget {
  final BuildEntryListWidgetCallback buildEntryListWidgetCallback;

  const EntryListsOverviewPage(
      {super.key, required this.buildEntryListWidgetCallback});

  @override
  EntryListsOverviewPageState createState() => EntryListsOverviewPageState();
}

class EntryListsOverviewPageState extends State<EntryListsOverviewPage>
    with SingleTickerProviderStateMixin {
  late TabController tabController;

  bool onFirstTab = true;
  bool inEditMode = false;

  @override
  void initState() {
    super.initState();
    var length = showCommunityLists() ? 2 : 1;
    tabController = TabController(initialIndex: 0, length: length, vsync: this);
    tabController.animation!.addListener(() {
      final double value = tabController.animation!.value;
      setState(() {
        onFirstTab = value < 0.5;
        inEditMode = false;
        //
      });
    });
  }

  // We only show community lists and therefore the tab view if there are
  // actually any community entry lists to show and user hasn't disabled it.
  bool showCommunityLists() {
    var prefHideCommunityLists =
        sharedPreferences.getBool(KEY_HIDE_COMMUNITY_LISTS) ?? false;
    var communityLimitsPopulated =
        communityEntryListManager.getEntryLists().isNotEmpty;
    return communityLimitsPopulated && !prefHideCommunityLists;
  }

  @override
  void dispose() {
    // Dispose of the TabController to avoid memory leaks
    tabController.dispose();
    super.dispose();
  }

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

    List<Widget> actions = [];

    // Only show the edit action for user lists.
    if (onFirstTab) {
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

    List<Widget> tabs = [
      Tab(text: DictLibLocalizations.of(context)!.listMyLists),
    ];
    List<Widget> children = [
      getUserLists(
          context, setState, widget.buildEntryListWidgetCallback, inEditMode),
    ];

    if (showCommunityLists()) {
      tabs.add(Tab(text: DictLibLocalizations.of(context)!.listCommunity));
      children
          .add(getCommunityLists(context, widget.buildEntryListWidgetCallback));
    }

    bool showTabs = tabs.length > 1;

    Widget body;
    if (showTabs) {
      body = TabBarView(controller: tabController, children: children);
    } else {
      body = children[0];
    }

    return TopLevelScaffold(
        underAppBar: showTabs
            ? TabBar(
                controller: tabController,
                tabs: tabs,
              )
            : null,
        body: body,
        title: DictLibLocalizations.of(context)!.listsTitle,
        actions: actions,
        floatingActionButton: floatingActionButton);
  }
}

Widget getUserLists(
    BuildContext context,
    void Function(void Function() fn) setState,
    BuildEntryListWidgetCallback buildEntryListWidgetCallback,
    bool inEditMode) {
  List<Widget> tiles = [];
  int i = 0;
  for (MapEntry<String, EntryList> e
      in userEntryListManager.getEntryLists().entries) {
    String key = e.key;
    EntryList el = e.value;
    String name = el.getName();
    Widget? trailing;
    if (inEditMode && el.canBeDeleted()) {
      trailing = IconButton(
          icon: const Icon(
            Icons.remove_circle,
            color: Colors.red,
          ),
          onPressed: () async {
            bool confirmed = await confirmAlert(context,
                Text(DictLibLocalizations.of(context)!.listConfirmListDelete));
            if (confirmed) {
              await userEntryListManager.deleteEntryList(key);
              setState(() {
                inEditMode = false;
              });
            }
          });
    }
    Card card = Card(
      key: ValueKey(name),
      child: ListTile(
        leading: el.getLeadingIcon(inEditMode: inEditMode),
        trailing: trailing,
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
    if (el.key == KEY_FAVOURITES_ENTRIES && inEditMode) {
      toAdd = IgnorePointer(
        key: ValueKey(name),
        child: toAdd,
      );
    }
    if (inEditMode) {
      toAdd = ReorderableDragStartListener(
          key: ValueKey(name), index: i, child: toAdd);
    }
    tiles.add(toAdd);
    i += 1;
  }

  if (inEditMode) {
    return ReorderableListView(
        children: tiles,
        onReorder: (prev, updated) async {
          setState(() {
            userEntryListManager.reorder(prev, updated);
          });
          await userEntryListManager.writeEntryListKeys();
        });
  } else {
    return ListView(
      children: tiles,
    );
  }
}

Widget getCommunityLists(BuildContext context,
    BuildEntryListWidgetCallback buildEntryListWidgetCallback) {
  List<Widget> tiles = [];
  for (MapEntry<String, EntryList> e
      in communityEntryListManager.getEntryLists().entries) {
    EntryList el = e.value;
    String name = el.getName();
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
  TextEditingController controller = TextEditingController();

  List<Widget> children = [
    const Text(
      "No special characters besides these are allowed: , . - _ !",
    ),
    const Padding(padding: EdgeInsets.only(top: 10)),
    TextField(
      controller: controller,
      decoration: InputDecoration(
        hintText: DictLibLocalizations.of(context)!.listEnterNewName,
      ),
      autofocus: true,
      inputFormatters: [
        FilteringTextInputFormatter.allow(EntryList.validNameCharacters),
      ],
      textInputAction: TextInputAction.send,
      keyboardType: TextInputType.visiblePassword,
      textCapitalization: TextCapitalization.words,
    )
  ];

  Widget body = Column(
    mainAxisSize: MainAxisSize.min,
    children: children,
  );
  bool confirmed = await confirmAlert(context, body,
      title: DictLibLocalizations.of(context)!.listNewList);
  if (confirmed) {
    String name = controller.text;
    try {
      String key = EntryList.getKeyFromName(name);
      await userEntryListManager.createEntryList(key);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              "${DictLibLocalizations.of(context)!.listFailedToMake}: $e."),
          backgroundColor: Colors.red));
      confirmed = false;
    }
  }
  return confirmed;
}
