import 'package:dictionarylib/common.dart';
import 'package:dictionarylib/globals.dart';
import 'package:dictionarylib/theme.dart';
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

    // In the Hearth look, tab roots use a large left-aligned display title.
    // Classic keeps its centred title so it matches the original design.
    final hearth = themeVariantNotifier.value == AppThemeVariant.hearth;
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
          title: Text(title),
          titleTextStyle: hearth
              ? textTheme.headlineMedium?.copyWith(
                  fontSize: 26, color: Theme.of(context).colorScheme.onSurface)
              : null,
          titleSpacing: hearth ? 20 : null,
          toolbarHeight: hearth ? 64 : null,
          actions: buildActionButtons(actions ?? []),
          centerTitle: !hearth,
          bottom: underAppBar,
          surfaceTintColor: Colors.transparent),
      body: body,
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: BottomNavigationBar(
        items: items,
        currentIndex: calculateSelectedIndex(context),
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
    final String path = route.routeInformationProvider.value.uri.path;
    var routes = getRoutes();
    final i = routes.indexOf(path);
    // When a non-tab route is pushed on top (e.g. the `/share/:id` landing
    // page), the four tab pages stay mounted underneath and rebuild on
    // theme/locale/sharing changes — but the current location isn't one of
    // the tab routes, so `indexOf` returns -1. A negative `currentIndex`
    // asserts in debug and throws a RangeError in release inside
    // BottomNavigationBar, so clamp it to the first tab.
    return i < 0 ? 0 : i;
  }

  void onItemTapped(int index, BuildContext context) {
    var routes = getRoutes();
    GoRouter.of(context).go(routes[index]);
  }
}
