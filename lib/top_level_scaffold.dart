import 'package:dictionarylib/common.dart';
import 'package:dictionarylib/globals.dart';
import 'package:dictionarylib/theme.dart';
import 'package:dictionarylib/tv_focus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
      items.add(
        BottomNavigationBarItem(
          icon: const Icon(Icons.view_list),
          label: DictLibLocalizations.of(context)!.listsTitle,
        ),
      );
    }

    if (getShowFlashcards()) {
      items.add(
        BottomNavigationBarItem(
          icon: const Icon(Icons.style),
          label: DictLibLocalizations.of(context)!.revisionTitle,
        ),
      );
    }

    items.add(
      BottomNavigationBarItem(
        icon: const Icon(Icons.settings),
        label: DictLibLocalizations.of(context)!.settingsTitle,
      ),
    );

    // In the Hearth look, tab roots use a large left-aligned display title.
    // Classic keeps its centred title so it matches the original design.
    final hearth = themeVariantNotifier.value == AppThemeVariant.hearth;
    final textTheme = Theme.of(context).textTheme;
    final selectedIndex = calculateSelectedIndex(context);
    // A phone in landscape with the keyboard up leaves only ~150pt above it:
    // not enough for the app bar as well as a search field, which ended up
    // under the keyboard. In that case the app bar steps aside until the
    // keyboard goes, and the body's SafeArea takes over the status bar.
    // Portrait phones and tablets never get this short.
    final cramped =
        MediaQuery.sizeOf(context).height -
            MediaQuery.viewInsetsOf(context).bottom <
        300;
    return _TvTabFocus(
      selectedIndex: selectedIndex,
      builder: (context, navBarFocus) => Scaffold(
        appBar: cramped
            ? null
            : AppBar(
                title: Text(title),
                titleTextStyle: hearth
                    ? textTheme.headlineMedium?.copyWith(
                        fontSize: 26,
                        color: Theme.of(context).colorScheme.onSurface,
                      )
                    : null,
                titleSpacing: hearth ? 20 : null,
                toolbarHeight: hearth ? 64 : null,
                actions: buildActionButtons(actions ?? []),
                centerTitle: !hearth,
                bottom: underAppBar,
                surfaceTintColor: Colors.transparent,
              ),
        // On tablets the tab pages centre their content at a readable
        // measure instead of stretching phone rows across the full panel.
        // The SafeArea is always there (only its top flips) so the body
        // keeps its place in the tree, and the search field its focus, as
        // the app bar comes and goes.
        body: SafeArea(
          top: cramped,
          bottom: false,
          left: false,
          right: false,
          child: constrainContentWidth(context, body),
        ),
        floatingActionButton: floatingActionButton,
        bottomNavigationBar: Focus(
          focusNode: navBarFocus,
          child: BottomNavigationBar(
            items: items,
            currentIndex: selectedIndex,
            onTap: (index) => onItemTapped(index, context),
            type: BottomNavigationBarType.fixed,
          ),
        ),
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
    _TvTabFocus.focusAfterSwitch = isAndroidTv;
    GoRouter.of(context).go(routes[index]);
  }
}

/// Remote-control behaviour for the top-level tabs on Android TV (inert
/// elsewhere):
///
/// - Each tab builds its own bottom bar, so switching tabs would drop focus
///   along with the old bar; a switch made from the bar puts focus back on the
///   selected item of the new one.
/// - Back first takes focus to the bottom bar, and only exits the app from
///   there. A long list (47 topic lists) would otherwise be dozens of presses
///   from the bar, and Back would leave the app.
class _TvTabFocus extends StatefulWidget {
  const _TvTabFocus({required this.selectedIndex, required this.builder});

  /// Set when a bar item is chosen; consumed by the next tab to be built.
  static bool focusAfterSwitch = false;

  final int selectedIndex;
  final Widget Function(BuildContext context, FocusNode navBarFocus) builder;

  @override
  State<_TvTabFocus> createState() => _TvTabFocusState();
}

class _TvTabFocusState extends State<_TvTabFocus> {
  late final FocusNode _navBar = FocusNode(
    debugLabel: 'bottomNavigationBar',
    canRequestFocus: false,
    skipTraversal: true,
    onKeyEvent: _onNavBarKey,
  );

  @override
  void initState() {
    super.initState();
    // Rebuild when focus enters or leaves the bar: it decides whether Back
    // may leave the app (see build).
    _navBar.addListener(_onNavBarFocusChange);
    if (!_TvTabFocus.focusAfterSwitch) return;
    _TvTabFocus.focusAfterSwitch = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusSelectedItem();
    });
  }

  @override
  void dispose() {
    _navBar.removeListener(_onNavBarFocusChange);
    _navBar.dispose();
    super.dispose();
  }

  void _onNavBarFocusChange() {
    if (isAndroidTv && mounted) setState(() {});
  }

  bool _focusSelectedItem() {
    final items = _navBar.traversalDescendants.toList();
    if (widget.selectedIndex >= items.length) return false;
    items[widget.selectedIndex].requestFocus();
    return true;
  }

  /// Left and right move strictly between the bar's items. Left to Flutter's
  /// directional search they can land in the list above instead: a list keeps
  /// its next row built just past the visible area, behind the bar, where it
  /// reads as being beside the bar's items.
  KeyEventResult _onNavBarKey(FocusNode node, KeyEvent event) {
    if (!isAndroidTv || event is! KeyDownEvent) return KeyEventResult.ignored;
    final int step;
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      step = -1;
    } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      step = 1;
    } else {
      return KeyEventResult.ignored;
    }
    final items = _navBar.traversalDescendants.toList();
    final current = items.indexWhere((item) => item.hasPrimaryFocus);
    if (current < 0) return KeyEventResult.ignored;
    final next = current + step;
    if (next >= 0 && next < items.length) items[next].requestFocus();
    return KeyEventResult.handled;
  }

  // Back reaches Flutter as a route pop (Android's back callback), not as a
  // key event, so it's caught here rather than in a key handler.
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !isAndroidTv || _navBar.hasFocus,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop && !_focusSelectedItem()) SystemNavigator.pop();
    },
    child: widget.builder(context, _navBar),
  );
}
