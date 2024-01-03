import 'package:dictionarylib/common.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:dictionarylib/dictionarylib.dart' show AppLocalizations;

const SEARCH_ROUTE = "/search";
const LISTS_ROUTE = "/lists";
const REVISION_ROUTE = "/revision";
const SETTINGS_ROUTE = "/settings";

class TopLevelScaffold extends StatelessWidget {
  const TopLevelScaffold({
    required this.title,
    required this.body,
    required this.mainColor,
    this.actions,
    this.floatingActionButton,
    super.key,
  });

  /// What title to show in the top app bar.
  final String title;

  /// The widget to display in the body of the Scaffold.
  final Widget body;

  final Color mainColor;

  /// Actions to show in the top app bar, if any.
  final List<Widget>? actions;

  /// Floating action button to show, if any.
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context) {
    var items = <BottomNavigationBarItem>[
      BottomNavigationBarItem(
        icon: const Icon(Icons.search),
        label: AppLocalizations.of(context)!.searchTitle,
      ),
      BottomNavigationBarItem(
        icon: const Icon(Icons.view_list),
        label: AppLocalizations.of(context)!.listsTitle,
      ),
    ];

    if (getShowFlashcards()) {
      items.add(
        BottomNavigationBarItem(
          icon: const Icon(Icons.style),
          label: AppLocalizations.of(context)!.revisionTitle,
        ),
      );
    }

    items.add(BottomNavigationBarItem(
      icon: const Icon(Icons.settings),
      label: AppLocalizations.of(context)!.settingsTitle,
    ));

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: buildActionButtons(actions ?? []),
        centerTitle: true,
      ),
      body: body,
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: BottomNavigationBar(
        items: items,
        currentIndex: calculateSelectedIndex(context),
        selectedItemColor: mainColor,
        onTap: (index) => onItemTapped(index, context),
        type: BottomNavigationBarType.fixed,
      ),
    );
  }

  static int calculateSelectedIndex(BuildContext context) {
    final GoRouter route = GoRouter.of(context);
    final String location = route.location;
    final int showFlashcardsOffset = getShowFlashcards() ? 0 : 1;
    if (location.startsWith(SEARCH_ROUTE)) {
      return 0;
    }
    if (location.startsWith(LISTS_ROUTE)) {
      return 1;
    }
    if (location.startsWith(REVISION_ROUTE)) {
      return 2 - showFlashcardsOffset;
    }
    if (location.startsWith(SETTINGS_ROUTE)) {
      return 3 - showFlashcardsOffset;
    }
    return 0;
  }

  void onItemTapped(int index, BuildContext context) {
    final bool showFlashcards = getShowFlashcards();
    switch (index) {
      case 0:
        GoRouter.of(context).go(SEARCH_ROUTE);
        break;
      case 1:
        GoRouter.of(context).go(LISTS_ROUTE);
        break;
      case 2:
        if (showFlashcards) {
          GoRouter.of(context).go(REVISION_ROUTE);
        } else {
          GoRouter.of(context).go(SETTINGS_ROUTE);
        }
        break;
      case 3:
        if (showFlashcards) {
          GoRouter.of(context).go(SETTINGS_ROUTE);
        } else {
          // Also just go to the settings route, though we shouldn't get to
          // this point.
          GoRouter.of(context).go(SETTINGS_ROUTE);
        }
        break;
    }
  }
}
