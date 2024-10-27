import 'package:dictionarylib/common.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:dictionarylib/dictionarylib.dart' show DictLibLocalizations;

const SEARCH_ROUTE = "/search";
const LISTS_ROUTE = "/lists";
const REVISION_ROUTE = "/revision";
const SETTINGS_ROUTE = "/settings";

class TopLevelScaffold extends StatelessWidget {
  const TopLevelScaffold({
    required this.title,
    required this.body,
    this.actions,
    this.floatingActionButton,
    this.underAppBar,
    super.key,
  });

  /// What title to show in the top app bar.
  final String title;

  /// The widget to display in the body of the Scaffold.
  final Widget body;

  /// Actions to show in the top app bar, if any.
  final List<Widget>? actions;

  /// Floating action button to show, if any.
  final Widget? floatingActionButton;

  /// What goes under the app bar, if anything.
  final PreferredSizeWidget? underAppBar;

  @override
  Widget build(BuildContext context) {
    ColorScheme currentTheme = Theme.of(context).colorScheme;
    var items = <BottomNavigationBarItem>[
      BottomNavigationBarItem(
        icon: const Icon(Icons.search),
        label: DictLibLocalizations.of(context)!.searchTitle,
      ),
    ];

    if (getShowLists()) {
      items.add(BottomNavigationBarItem(
        icon: const Icon(Icons.view_list),
        label: DictLibLocalizations.of(context)!.listsTitle,
      ));
    }

    if (getShowFlashcards()) {
      items.add(
        BottomNavigationBarItem(
          icon: const Icon(Icons.style),
          label: DictLibLocalizations.of(context)!.revisionTitle,
        ),
      );
    }

    items.add(BottomNavigationBarItem(
      icon: const Icon(Icons.settings),
      label: DictLibLocalizations.of(context)!.settingsTitle,
    ));

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: buildActionButtons(actions ?? []),
        centerTitle: true,
        bottom: underAppBar,
      ),
      body: body,
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: BottomNavigationBar(
        items: items,
        currentIndex: calculateSelectedIndex(context),
        selectedItemColor: currentTheme.primary,
        onTap: (index) => onItemTapped(index, context),
        type: BottomNavigationBarType.fixed,
      ),
    );
  }

  static List<String> getRoutes() {
    var routes = [SEARCH_ROUTE];
    if (getShowLists()) {
      routes.add(LISTS_ROUTE);
    }
    if (getShowFlashcards()) {
      routes.add(REVISION_ROUTE);
    }
    routes.add(SETTINGS_ROUTE);
    return routes;
  }

  static int calculateSelectedIndex(BuildContext context) {
    final GoRouter route = GoRouter.of(context);
    final String location = route.routeInformationProvider.value.location;
    var routes = getRoutes();
    return routes.indexOf(location);
  }

  void onItemTapped(int index, BuildContext context) {
    var routes = getRoutes();
    GoRouter.of(context).go(routes[index]);
  }
}
