import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:dictionarylib/dictionarylib.dart' show DictLibLocalizations;

import 'common.dart';
import 'entry_list.dart';
import 'entry_types.dart';
import 'globals.dart';
import 'hearth.dart';
import 'lists_service.dart';
import 'save_video_sheet.dart';
import 'saved_video.dart';
import 'video_player_screen.dart';
import 'web_drag_scroll_behavior.dart';

/// The per-app knobs the shared word page reads. The two dictionary apps
/// (Auslan, SLSL) render the same page but differ in a handful of leaf
/// concerns — the related-word lookup, how a region prints, how a definition
/// is laid out, the video aspect ratio, and the app-bar extras (Auslan's
/// Signbank link vs SLSL's language dropdown). Each app constructs one of
/// these and hands it to [EntryPage]; everything else is shared verbatim.
///
/// This follows the same dependency-injection idiom as [SearchPage]
/// ([NavigateToEntryPageFn] + the `entryDefinitionPreview` callback) rather
/// than an abstract controller, because the word page has no shared behaviour
/// to inherit — every app-specific piece is a pure leaf callback or scalar.
class WordPageConfig {
  const WordPageConfig({
    required this.getRelatedEntry,
    required this.navigateToEntryPage,
    required this.buildDefinition,
    required this.regionsString,
    required this.videoAspectRatio,
    required this.buildExtraAppBarActions,
  });

  /// Resolve a related-word keyword to an entry, or null if there's no entry
  /// for it. Auslan looks up its English map only; SLSL falls back through
  /// English → Tamil → Sinhala.
  final Entry? Function(String keyword) getRelatedEntry;

  /// The app's own navigation function (its `/word/<key>` push on web, an
  /// imperative push on native). Used for related-word taps. Routed through
  /// [getInnerRelatedEntriesWidget], which itself drops focusVideo/saveToList,
  /// so a "see also" tap never carries the current entry's save context.
  final NavigateToEntryPageFn navigateToEntryPage;

  /// Render ONE of the app's definitions. Typed `dynamic` because `Definition`
  /// is a different app-local class in each app; the callback downcasts to its
  /// own type. The shared page maps this over the locale-filtered list.
  final Widget Function(BuildContext context, dynamic definition)
      buildDefinition;

  /// The sub-entry's region(s) as a display string. Auslan reads its
  /// `MySubEntry.getRegionsString()`; SLSL maps `getRegions()` through its
  /// context-aware `getRegionPretty`. An empty string hides the region line.
  final String Function(BuildContext context, SubEntry subEntry) regionsString;

  /// The video's fallback aspect ratio. Drives BOTH the inline player's
  /// `fallbackAspectRatio` AND the landscape pane's max video height
  /// (`pane.maxWidth / videoAspectRatio`). Auslan 16/9, SLSL 16/12.
  final double videoAspectRatio;

  /// App-specific app-bar actions placed BEFORE the shared playback-speed
  /// dropdown. Auslan builds the Signbank external-link button (from the
  /// English word + current variation); SLSL builds the language dropdown,
  /// whose selection calls [WordPageActionContext.setLocaleOverride].
  final List<Widget> Function(BuildContext context, WordPageActionContext ctx)
      buildExtraAppBarActions;
}

/// The live state the app-bar-actions builder needs from the page: which
/// entry / variation is on screen (for Auslan's Signbank URL) and a setter to
/// override the displayed language (for SLSL's dropdown).
class WordPageActionContext {
  const WordPageActionContext({
    required this.entry,
    required this.currentVariation,
    required this.setLocaleOverride,
  });

  final Entry entry;
  final int currentVariation;
  final void Function(Locale) setLocaleOverride;
}

class EntryPage extends StatefulWidget {
  const EntryPage({
    super.key,
    required this.entry,
    required this.showFavouritesButton,
    required this.config,
    this.focusVideo,
    this.saveToList,
    this.initialVariation,
    this.initialVideo,
  });

  final Entry entry;

  /// Per-app rendering config (related-word lookup, definition/region
  /// rendering, video aspect ratio, app-bar extras).
  final WordPageConfig config;

  /// Whether to render the per-video save UI. Named `showFavouritesButton`
  /// for source-compat with the pre-per-video-saves callers — the button is no
  /// longer a favourites star; it's a per-video bookmark that opens the
  /// all-lists picker.
  final bool showFavouritesButton;

  /// If supplied, the page lands on the sub-entry containing this video and
  /// starts the sub-entry's video carousel on that video (the list view's
  /// tap-to-jump flow).
  final SavedVideo? focusVideo;

  /// If supplied, the per-video save button adds the video straight to this
  /// list (toggling membership) instead of opening the all-lists picker.
  final EntryList? saveToList;

  /// Deep-link starting position from the URL (`?variation=N&video=M`). Used
  /// only on first build, and only when [focusVideo] isn't driving the initial
  /// position instead. Null when absent.
  final int? initialVariation;
  final int? initialVideo;

  @override
  State<EntryPage> createState() => _EntryPageState();
}

class _EntryPageState extends State<EntryPage> {
  int currentPage = 0;

  /// Within-sub-entry video index used when first building the focused
  /// sub-entry. Null when [EntryPage.focusVideo] is unset or its path isn't in
  /// the entry's data. After first build, per-sub-entry video position is owned
  /// by [SubEntryPage]'s own state — kept alive across sub-entry swipes by
  /// [AutomaticKeepAliveClientMixin].
  int? _focusedVideoInitialIndex;

  PlaybackSpeed playbackSpeed = PlaybackSpeed.One;

  /// On the word page we let people override the displayed language (set via
  /// the app-bar language dropdown SLSL builds; never set for Auslan, which is
  /// English-only — so it stays null and the override is the ambient locale).
  Locale? localeOverride;

  /// Pages between the entry's sub-entries (variations). Created once in
  /// [initState] (not per build) so it isn't leaked/recreated on every rebuild
  /// and an in-progress swipe isn't interrupted.
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    _applyFocusVideo();
    // No jump-to-video focus? Honour the deep-link position from the URL.
    if (widget.focusVideo == null) {
      final subEntries = widget.entry.getSubEntries();
      if (widget.initialVariation != null && subEntries.isNotEmpty) {
        currentPage = widget.initialVariation!.clamp(0, subEntries.length - 1);
      }
      if (widget.initialVideo != null) {
        _focusedVideoInitialIndex = widget.initialVideo;
      }
    }
    _pageController = PageController(initialPage: currentPage);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _applyFocusVideo() {
    final focus = widget.focusVideo;
    if (focus == null) return;
    final subEntries = widget.entry.getSubEntries();
    for (var i = 0; i < subEntries.length; i++) {
      final idx = subEntries[i].getMedia().indexOf(focus.mediaPath);
      if (idx >= 0) {
        currentPage = i;
        _focusedVideoInitialIndex = idx;
        return;
      }
    }
  }

  void onPageChanged(int index) {
    // Don't reset the playback speed: a user-chosen speed should survive
    // swiping between sub-entries. Flipping currentPage flips each
    // SubEntryPage's isActive flag, which pauses the now-offscreen sub-entry's
    // video and resumes the newly-visible one.
    setState(() {
      currentPage = index;
    });
    _syncUrlToVariation(index);
  }

  /// Reflect the current sub-entry in the URL so the entry stays deep-linkable
  /// as you swipe. Web only — a no-op route update on mobile the user never
  /// sees. Re-passes [EntryPageArgs] so the page's non-URL state (focused
  /// video, save target, save-button flag) survives the in-place replace; the
  /// route's stable page key keeps the carousel from resetting.
  void _syncUrlToVariation(int variation) {
    if (!kIsWeb) return;
    final key = Uri.encodeComponent(widget.entry.getKey());
    final loc = variation == 0
        ? "$WORD_ROUTE/$key"
        : "$WORD_ROUTE/$key?variation=$variation";
    GoRouter.of(context).replace(
      loc,
      extra: EntryPageArgs(
        showFavouritesButton: widget.showFavouritesButton,
        focusVideo: widget.focusVideo,
        saveToList: widget.saveToList,
      ),
    );
  }

  /// On web, allow a mouse to drag the variation pager. Native is unchanged.
  Widget _maybeWebDrag(Widget child) {
    if (!kIsWeb) return child;
    return ScrollConfiguration(
        behavior: const WebDragScrollBehavior(), child: child);
  }

  @override
  Widget build(BuildContext context) {
    // If there is no locale override just use the app-level locale. Auslan
    // never overrides and its getPhrase/getDefinitions ignore the locale, so
    // this is equivalent to its old English-only path.
    final locale = localeOverride ?? Localizations.localeOf(context);

    return InheritedPlaybackSpeed(
        playbackSpeed: playbackSpeed,
        child: Localizations.override(
            context: context,
            locale: locale,
            child: Builder(builder: (context) {
              final subEntries = widget.entry.getSubEntries();
              final phrase = widget.entry.getPhrase(locale) ??
                  DictLibLocalizations.of(context)!.wordDataMissing;

              final actions = <Widget>[
                ...widget.config.buildExtraAppBarActions(
                  context,
                  WordPageActionContext(
                    entry: widget.entry,
                    currentVariation: currentPage,
                    setLocaleOverride: (l) =>
                        setState(() => localeOverride = l),
                  ),
                ),
                getPlaybackSpeedDropdownWidget(
                  (p) {
                    setState(() {
                      playbackSpeed = p!;
                    });
                    showSnack(context,
                        "${DictLibLocalizations.of(context)!.setPlaybackSpeedTo} ${getPlaybackSpeedString(p!)}",
                        duration: const Duration(milliseconds: 1000));
                  },
                  current: playbackSpeed,
                ),
              ];

              return Scaffold(
                appBar: AppBar(
                  title: Text(phrase),
                  actions: buildActionButtons(actions),
                  // A cold-start web deep link to /word/<key> is the navigation
                  // root with nothing to pop back to; give it an explicit way
                  // back to search. Normal in-app navigation keeps the default
                  // back arrow.
                  leading: kIsWeb && !Navigator.of(context).canPop()
                      ? IconButton(
                          icon: const Icon(Icons.arrow_back),
                          onPressed: () => context.go('/'),
                        )
                      : null,
                ),
                // On web, wrap so a mouse can drag-swipe between variations
                // (Flutter disables mouse-drag scrolling by default, freezing
                // the swipe). Native uses its default behaviour.
                body: _maybeWebDrag(PageView.builder(
                  controller: _pageController,
                  itemCount: subEntries.length,
                  itemBuilder: (context, index) => SubEntryPage(
                    entry: widget.entry,
                    subEntry: subEntries[index],
                    config: widget.config,
                    subEntryIndex: index,
                    subEntryCount: subEntries.length,
                    initialVideoIndex:
                        index == currentPage ? _focusedVideoInitialIndex : null,
                    // No saving on web (no account / favourites there).
                    showSaveButton: widget.showFavouritesButton && !kIsWeb,
                    saveToList: widget.saveToList,
                    // Only the on-screen sub-entry's video should play;
                    // kept-alive off-screen pages pause via this flag.
                    isActive: index == currentPage,
                    // Web-only nav arrows beside the variation label (no swipe
                    // affordance there); null on native so they never render.
                    onPrevVariation: kIsWeb
                        ? () => _pageController.previousPage(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut)
                        : null,
                    onNextVariation: kIsWeb
                        ? () => _pageController.nextPage(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut)
                        : null,
                  ),
                  onPageChanged: onPageChanged,
                )),
              );
            })));
  }
}

Widget? _relatedEntriesWidget(BuildContext context, SubEntry subEntry,
    bool shouldUseHorizontalDisplay, WordPageConfig config) {
  return getInnerRelatedEntriesWidget(
      context: context,
      subEntry: subEntry,
      shouldUseHorizontalDisplay: shouldUseHorizontalDisplay,
      getRelatedEntry: config.getRelatedEntry,
      navigateToEntryPage: config.navigateToEntryPage);
}

/// A quiet footer under the definitions: a demoted "See also" related-words
/// line first, then a globe + region line beneath it, separated from the
/// content above by a hairline.
Widget _buildWordFooter(BuildContext context, SubEntry subEntry,
    Widget? keywordsWidget, WordPageConfig config) {
  final cs = Theme.of(context).colorScheme;
  final region = config.regionsString(context, subEntry);
  final hasRegion = region.trim().isNotEmpty;
  if (!hasRegion && keywordsWidget == null) return const SizedBox.shrink();
  return Container(
    width: double.infinity,
    margin: const EdgeInsets.only(top: 8),
    padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
    decoration: BoxDecoration(
      border: Border(top: BorderSide(color: cs.outlineVariant)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (keywordsWidget != null) keywordsWidget,
        if (hasRegion)
          Padding(
            padding: EdgeInsets.only(top: keywordsWidget != null ? 8 : 0),
            child: Row(children: [
              Icon(Icons.public, size: 18, color: cs.onSurfaceVariant),
              const SizedBox(width: 8),
              Flexible(
                child: Text(region,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: cs.onSurfaceVariant)),
              ),
            ]),
          ),
      ],
    ),
  );
}

/// The scrollable definitions list shown in the portrait layout's [Expanded].
/// An entry with no definitions for the current locale shows a quiet
/// placeholder rather than an empty void.
Widget _definitionsList(
    BuildContext context, List<dynamic> definitions, WordPageConfig config) {
  if (definitions.isEmpty) {
    return Center(
        child: Text(
      DictLibLocalizations.of(context)!.wordNoDefinitions,
      textAlign: TextAlign.center,
    ));
  }
  return ListView.builder(
    itemCount: definitions.length,
    itemBuilder: (context, index) =>
        config.buildDefinition(context, definitions[index]),
  );
}

class SubEntryPage extends StatefulWidget {
  const SubEntryPage({
    super.key,
    required this.entry,
    required this.subEntry,
    required this.config,
    this.subEntryIndex = 0,
    this.subEntryCount = 1,
    this.initialVideoIndex,
    this.showSaveButton = true,
    this.saveToList,
    this.isActive = true,
    this.onPrevVariation,
    this.onNextVariation,
  });

  final Entry entry;
  final SubEntry subEntry;
  final WordPageConfig config;

  /// This sub-entry's position among the entry's variations, for the dots.
  final int subEntryIndex;
  final int subEntryCount;

  /// Within-sub-entry video index to land on (first build only).
  final int? initialVideoIndex;

  /// Whether to render the per-video bookmark button.
  final bool showSaveButton;

  /// When set, the bookmark toggles membership of this one list directly.
  final EntryList? saveToList;

  /// Whether this sub-entry is the one currently on screen. Forwarded to
  /// [VideoPlayerScreen] so off-screen kept-alive pages pause their video.
  final bool isActive;

  /// Web-only: move to the previous / next variation. These drive the arrows
  /// flanking the variation label, since web has no touch-swipe affordance.
  /// Null on native (you swipe there), so the arrows never render on mobile.
  final VoidCallback? onPrevVariation;
  final VoidCallback? onNextVariation;

  @override
  SubEntryPageState createState() => SubEntryPageState();
}

class SubEntryPageState extends State<SubEntryPage>
    with AutomaticKeepAliveClientMixin {
  late int _currentVideo;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _currentVideo = widget.initialVideoIndex ?? 0;
  }

  void _onVideoChanged(int index) {
    if (index == _currentVideo) return;
    setState(() => _currentVideo = index);
  }

  /// Inner tier: which video *within* this variation you're on. Subdued, muted
  /// dots directly under the video. Null when there's only one recording —
  /// unless [reserveSpace] is set, in which case a single-recording page gets
  /// an invisible, same-height placeholder so the video and save button sit at
  /// exactly the same spot as on multi-video pages instead of shifting.
  /// Shared by the vertical and horizontal layouts so tablets/TVs get it too.
  Widget? _videoIndicator(BuildContext context, {bool reserveSpace = false}) {
    final videoCount = widget.subEntry.getMedia().length;
    if (videoCount == 0 || (videoCount == 1 && !reserveSpace)) return null;
    final cs = Theme.of(context).colorScheme;
    final l = DictLibLocalizations.of(context)!;
    final currentVideo = _currentVideo.clamp(0, videoCount - 1);
    final indicator = Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 2),
      child: SizedBox(
        width: double.infinity,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            HearthDots(
              count: videoCount,
              index: currentVideo,
              size: 5,
              activeColor: cs.onSurfaceVariant,
            ),
            const SizedBox(height: 5),
            Text(
              l.videoIndicator(currentVideo + 1, videoCount),
              style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
    if (videoCount == 1) {
      return Visibility(
        visible: false,
        maintainSize: true,
        maintainAnimation: true,
        maintainState: true,
        child: indicator,
      );
    }
    return indicator;
  }

  /// Outer tier: which variation of the word you're on. Prominent clay dots +
  /// a "Variation n of m" label. On web the label is flanked by prev/next
  /// arrows (no touch swipe affordance there). Shown even for a single
  /// variation so the page reads consistently.
  Widget _variationIndicator(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l = DictLibLocalizations.of(context)!;
    final label = Text(
      l.wordVariationWithHint(widget.subEntryIndex + 1, widget.subEntryCount),
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
    );
    final Widget labelRow = (kIsWeb && widget.subEntryCount > 1)
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Disabled at the ends for a clear "can't go further" cue.
              _variationArrow(context, Icons.chevron_left,
                  widget.subEntryIndex > 0 ? widget.onPrevVariation : null),
              Flexible(child: label),
              _variationArrow(
                  context,
                  Icons.chevron_right,
                  widget.subEntryIndex < widget.subEntryCount - 1
                      ? widget.onNextVariation
                      : null),
            ],
          )
        : label;
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 18),
      child: SizedBox(
        width: double.infinity,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            HearthDots(
                count: widget.subEntryCount, index: widget.subEntryIndex),
            const SizedBox(height: 8),
            labelRow,
          ],
        ),
      ),
    );
  }

  /// Web-only compact arrow beside the variation label. `onTap` is null at the
  /// first/last variation, which disables (greys out) the button.
  Widget _variationArrow(
      BuildContext context, IconData icon, VoidCallback? onTap) {
    final cs = Theme.of(context).colorScheme;
    final l = DictLibLocalizations.of(context)!;
    return IconButton(
      icon: Icon(icon),
      iconSize: 20,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      color: cs.onSurfaceVariant,
      onPressed: onTap,
      tooltip:
          icon == Icons.chevron_left ? l.variationPrevious : l.variationNext,
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final locale = Localizations.localeOf(context);

    // getMedia() returns paths (the saved-video identity); resolve each to a
    // playable URL. Tapping the video expands it over a dimmed backdrop
    // (handled inside VideoPlayerScreen so the inline tile pauses + hides while
    // expanded — no second player); image (.jpg) recordings are skipped.
    final tappableVideo = VideoPlayerScreen(
      mediaLinks: widget.subEntry.getMedia().map(mediaUrlForPath).toList(),
      fallbackAspectRatio: widget.config.videoAspectRatio,
      initialPage: _currentVideo,
      onPageChanged: _onVideoChanged,
      expandOnTap: true,
      isActive: widget.isActive,
    );

    Widget? bookmarkRow;
    final paths = widget.subEntry.getMedia();
    if (widget.showSaveButton && getShowLists() && paths.isNotEmpty) {
      final path = paths[_currentVideo.clamp(0, paths.length - 1)];
      bookmarkRow = _BookmarkButton(
          key: const ValueKey('wordPage.saveButton'),
          entry: widget.entry,
          mediaPath: path,
          saveToList: widget.saveToList);
    }

    final shouldUseHorizontalDisplay = getShouldUseHorizontalLayout(context);
    final relatedWordsWidget = _relatedEntriesWidget(
        context, widget.subEntry, shouldUseHorizontalDisplay, widget.config);
    final videoIndicator = _videoIndicator(context);
    final variationIndicator = _variationIndicator(context);
    final List<dynamic> definitions = widget.subEntry.getDefinitions(locale);

    if (!shouldUseHorizontalDisplay) {
      final children = <Widget>[];
      // Loose Flexible: the video keeps its natural size when there's room but
      // yields under pressure (e.g. a short transition frame during a route
      // pop) so the column never overflows. Definitions below is the Expanded.
      children.add(Flexible(child: tappableVideo));
      if (bookmarkRow != null) children.add(bookmarkRow);
      // Inner tier: which video within this variation (only if >1 recording).
      if (videoIndicator != null) children.add(videoIndicator);
      children.add(Expanded(
          child: _definitionsList(context, definitions, widget.config)));
      // Quiet footer: a demoted "See also" line, then the region info.
      children.add(_buildWordFooter(
          context, widget.subEntry, relatedWordsWidget, widget.config));
      // Outer tier: which variation of the word, anchored at the bottom.
      children.add(variationIndicator);
      return Column(
        mainAxisAlignment: MainAxisAlignment.start,
        mainAxisSize: MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      );
    } else {
      // Landscape / wide: the video — with the save button and video dots
      // under it, in the same order as the vertical layout — sits on the left,
      // and the definitions, "see also" and region go in a scrollable panel on
      // the right so nothing is ever clipped. The indicator slot reserves its
      // height even for single-video pages so the video and save button never
      // shift between pages. SafeArea keeps it all clear of the notch / rounded
      // corners.
      final videoIndicatorSlot = _videoIndicator(context, reserveSpace: true);
      return SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 5,
              child: LayoutBuilder(builder: (context, pane) {
                // VideoPlayerScreen expands to fill whatever bounded height
                // it's given (centring the video inside), so cap its box at the
                // height of one video and let Flexible shrink it when a cramped
                // landscape phone can't fit that plus the controls. The
                // constant-height box also keeps the save button and dots at
                // the same spot on every page, whatever each video's aspect
                // ratio and however many recordings it has (the indicator slot
                // below reserves its space when there's one).
                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                            maxHeight:
                                pane.maxWidth / widget.config.videoAspectRatio),
                        child: tappableVideo,
                      ),
                    ),
                    if (bookmarkRow != null) bookmarkRow,
                    if (videoIndicatorSlot != null) videoIndicatorSlot,
                  ],
                );
              }),
            ),
            Expanded(
              flex: 4,
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 12),
                children: [
                  ...definitions
                      .map((d) => widget.config.buildDefinition(context, d)),
                  _buildWordFooter(context, widget.subEntry, relatedWordsWidget,
                      widget.config),
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Center(child: variationIndicator),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
  }
}

/// Per-video save toggle rendered beneath the video player. Owns its own state
/// so swiping to a new video — or toggling the picker sheet — repaints just
/// this button rather than the whole entry page.
class _BookmarkButton extends StatefulWidget {
  final Entry entry;

  /// The media **path** (stable identity) of the video this button saves.
  final String mediaPath;

  /// When set, the button toggles this video's membership in [saveToList]
  /// directly (the user arrived here to add to a specific list). When null,
  /// it opens the all-lists picker sheet.
  final EntryList? saveToList;

  const _BookmarkButton({
    super.key,
    required this.entry,
    required this.mediaPath,
    this.saveToList,
  });

  @override
  State<_BookmarkButton> createState() => _BookmarkButtonState();
}

class _BookmarkButtonState extends State<_BookmarkButton> {
  @override
  Widget build(BuildContext context) {
    final v = SavedVideo(
        entryKey: widget.entry.getKey(), mediaPath: widget.mediaPath);
    final l = DictLibLocalizations.of(context)!;

    // Direct mode: we came from a specific list, so the button just adds (or
    // removes) this video to/from that one list — no picker.
    final target = widget.saveToList;
    if (target != null) {
      final saved = target.containsVideo(v);
      // Capture before the await so we don't touch BuildContext across the gap.
      final messenger = ScaffoldMessenger.of(context);
      Future<void> toggle() async {
        try {
          if (saved) {
            await target.removeVideo(v);
          } else {
            await target.addVideo(v);
          }
        } catch (e) {
          printAndLog("Failed to toggle video in list ${target.key}: $e");
          if (mounted) {
            showSnackVia(messenger, l.saveVideoFailed);
          }
        }
        if (mounted) setState(() {});
      }

      final name = target.getName(context);
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: SizedBox(
          width: double.infinity,
          child: saved
              ? FilledButton.icon(
                  onPressed: toggle,
                  icon: const Icon(Icons.bookmark, size: 20),
                  label: Text(l.savedToNamedList(name)),
                )
              : OutlinedButton.icon(
                  onPressed: toggle,
                  icon: const Icon(Icons.bookmark_border, size: 20),
                  label: Text(l.saveToNamedList(name)),
                ),
        ),
      );
    }

    // Count against the same set the save sheet shows (local lists routed
    // through owner wrappers + editor lists), so the label and the sheet never
    // disagree — e.g. an editor list the old myLists-only count missed,
    // leaving "saved to N lists" stuck after an unsave.
    var savedCount = 0;
    for (final list in listsService.writableLists) {
      if (list.containsVideo(v)) savedCount++;
    }
    final saved = savedCount > 0;

    // Tapping always opens the "save to list" sheet — it never silently
    // un-saves. The button just reflects how many lists hold this video.
    Future<void> openSheet() async {
      await showSaveVideoSheet(context, video: v);
      if (mounted) setState(() {});
    }

    final label = saved ? l.savedToListCount(savedCount) : l.saveVideoButton;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: SizedBox(
        width: double.infinity,
        child: saved
            ? FilledButton.icon(
                onPressed: openSheet,
                icon: const Icon(Icons.bookmark, size: 20),
                label: Text(label),
              )
            : OutlinedButton.icon(
                onPressed: openSheet,
                icon: const Icon(Icons.bookmark_border, size: 20),
                label: Text(label),
              ),
      ),
    );
  }
}
