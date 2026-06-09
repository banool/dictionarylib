import 'dart:collection';

import 'package:dictionarylib/common.dart';
import 'package:dictionarylib/entry_list.dart';
import 'package:dictionarylib/entry_types.dart';
import 'package:dictionarylib/flashcards_logic.dart';
import 'package:dictionarylib/globals.dart';
import 'package:dictionarylib/lists_service.dart';
import 'package:dictionarylib/page_revision_history.dart';
import 'package:dictionarylib/revision.dart';
import 'package:dolphinsr_dart/dolphinsr_dart.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:dictionarylib/dictionarylib.dart' show DictLibLocalizations;

import 'hearth.dart';
import 'top_level_scaffold.dart';

abstract class FlashcardsLandingPageController {
  /// Filter the pool of saved videos that revision will run over.
  /// Implementations apply per-app rules (region filter,
  /// "one card per entry" toggle, etc.) and return the videos that
  /// should actually become cards this session.
  List<ResolvedSavedVideo> filterSavedVideos(List<ResolvedSavedVideo> videos);

  DolphinInformation getDolphin(List<ResolvedSavedVideo> filteredVideos,
      List<Review>? existingReviews,
      {RevisionStrategy? revisionStrategy}) {
    revisionStrategy = revisionStrategy ?? loadRevisionStrategy();
    var wordToSign = sharedPreferences.getBool(KEY_WORD_TO_SIGN) ?? true;
    var signToEntry = sharedPreferences.getBool(KEY_SIGN_TO_WORD) ?? true;
    var revisionLocale = LANGUAGE_CODE_TO_LOCALE[
            sharedPreferences.getString(KEY_REVISION_LANGUAGE_CODE)] ??
        LOCALE_ENGLISH;
    var masters = getMastersFromVideos(
        revisionLocale, filteredVideos, wordToSign, signToEntry);
    switch (revisionStrategy) {
      case RevisionStrategy.Random:
        return getDolphinInformationFromVideos(filteredVideos, masters,
            reviews: existingReviews);
      case RevisionStrategy.SpacedRepetition:
        return getDolphinInformationFromVideos(filteredVideos, masters,
            reviews: existingReviews!);
    }
  }

  Widget buildFlashcardsPage(
      {required DolphinInformation dolphinInformation,
      required RevisionStrategy revisionStrategy,
      required List<Review> existingReviews});

  Widget buildHelpPage(BuildContext context);

  List<Widget> getExtraBottomWidgets(
      BuildContext context,
      void Function(void Function() fn) setState,
      void Function() updateRevisionSettings) {
    return [];
  }

  /// Extra rows to insert into the "Revision settings" card. Return
  /// [HearthRow]s (or other widgets) so they sit cohesively in the bespoke
  /// settings card. Used by apps with extra knobs (e.g. Auslan's sign-region
  /// configurator).
  List<Widget> getExtraSettingsRows(
      BuildContext context,
      void Function(void Function() fn) setState,
      void Function(String key, bool newValue, bool influencesStartValidity)
          onPrefSwitch,
      void Function() updateRevisionSettings) {
    return [];
  }
}

RevisionStrategy loadRevisionStrategy() {
  int revisionStrategyIndex = sharedPreferences.getInt(KEY_REVISION_STRATEGY) ??
      RevisionStrategy.SpacedRepetition.index;
  RevisionStrategy revisionStrategy =
      RevisionStrategy.values[revisionStrategyIndex];
  return revisionStrategy;
}

class FlashcardsLandingPage extends StatefulWidget {
  const FlashcardsLandingPage({super.key, required this.controller});

  final FlashcardsLandingPageController controller;

  @override
  FlashcardsLandingPageState createState() => FlashcardsLandingPageState();
}

class FlashcardsLandingPageState extends State<FlashcardsLandingPage> {
  late int numEnabledFlashcardTypes;

  late final bool initialValueSignToEntry;
  late final bool initialValueEntryToSign;

  late LinkedHashMap<String, EntryList> candidateEntryLists;

  late LinkedHashMap<String, EntryList> entryListsToRevise;

  /// Saved videos in scope this session, after [filterSavedVideos] has
  /// applied region / "one card per entry" / etc. filters.
  List<ResolvedSavedVideo> filteredVideos = [];

  late DolphinInformation dolphinInformation;
  List<Review>? existingReviews;

  /// Lifecycle observer that refreshes revision settings when the app is
  /// foregrounded. Held in a field so it can be removed in [dispose] —
  /// otherwise it leaks and keeps firing on a disposed state.
  LifecycleEventHandler? _lifecycleObserver;

  @override
  void initState() {
    super.initState();
    candidateEntryLists = getCandidateEntryLists();
    _lifecycleObserver = LifecycleEventHandler(resumeCallBack: () async {
      if (!mounted) return;
      updateRevisionSettings();
      printAndLog("Updated revision settings on foregrounding");
    });
    WidgetsBinding.instance.addObserver(_lifecycleObserver!);
    updateRevisionSettings();
    initialValueSignToEntry =
        sharedPreferences.getBool(KEY_SIGN_TO_WORD) ?? true;
    initialValueEntryToSign =
        sharedPreferences.getBool(KEY_WORD_TO_SIGN) ?? true;
    numEnabledFlashcardTypes = 0;
    if (initialValueSignToEntry) {
      numEnabledFlashcardTypes += 1;
    }
    if (initialValueEntryToSign) {
      numEnabledFlashcardTypes += 1;
    }
  }

  @override
  void dispose() {
    if (_lifecycleObserver != null) {
      WidgetsBinding.instance.removeObserver(_lifecycleObserver!);
    }
    super.dispose();
  }

  void updateFilteredSubentries() {
    var listsToReview = sharedPreferences.getStringList(KEY_LISTS_TO_REVIEW) ??
        [KEY_FAVOURITES_ENTRIES];

    entryListsToRevise =
        getEntryListsToRevise(candidateEntryLists, listsToReview);

    final resolved = resolveSavedVideos(entryListsToRevise);

    setState(() {
      filteredVideos = widget.controller.filterSavedVideos(resolved);
    });
  }

  void onPrefSwitch(String key, bool newValue, bool influencesStartValidity) {
    // Persist outside setState (setBool returns a Future; setState must not
    // be handed a callback that returns one). The cache updates synchronously
    // so the next build reads the new value immediately.
    sharedPreferences.setBool(key, newValue);
    setState(() {
      if (influencesStartValidity) {
        if (newValue) {
          numEnabledFlashcardTypes += 1;
        } else {
          numEnabledFlashcardTypes -= 1;
        }
      }
    });
  }

  int getNumValidSubEntries() => filteredVideos.length;

  bool startValid() {
    var revisionStrategy = loadRevisionStrategy();
    bool flashcardTypesValid = numEnabledFlashcardTypes > 0;
    bool numFilteredValid = getNumValidSubEntries() > 0;
    bool numCardsValid =
        getNumDueCards(dolphinInformation.dolphin, revisionStrategy) > 0;
    return flashcardTypesValid && numFilteredValid && numCardsValid;
  }

  void updateDolphin() {
    if (existingReviews == null) {
      existingReviews = readReviews();
      printAndLog("Start: Read ${existingReviews!.length} reviews from storage");
    }
    dolphinInformation =
        widget.controller.getDolphin(filteredVideos, existingReviews);
  }

  void updateRevisionSettings() {
    setState(() {
      updateFilteredSubentries();
      updateDolphin();
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l = DictLibLocalizations.of(context)!;

    final revisionStrategy = loadRevisionStrategy();
    // Honour the optional session-size cap so the count shown on the Start bar
    // matches what the session will actually serve (FlashcardsPage applies the
    // same cap). 0 = no limit.
    final cardLimit = sharedPreferences.getInt(KEY_REVISION_CARD_LIMIT) ?? 0;
    final rawCardsToDo =
        getNumDueCards(dolphinInformation.dolphin, revisionStrategy);
    final cardsToDo = (cardLimit > 0 && rawCardsToDo > cardLimit)
        ? cardLimit
        : rawCardsToDo;
    final signToWord = sharedPreferences.getBool(KEY_SIGN_TO_WORD) ?? true;
    final wordToSign = sharedPreferences.getBool(KEY_WORD_TO_SIGN) ?? true;
    final typesValid = numEnabledFlashcardTypes > 0;

    // Sheet to pick which lists to study from, grouped into the same
    // sections as the Lists page (My Lists / Subscribed / Community) so
    // they're easy to find.
    Future<void> openSourcesPicker() async {
      // Cap the sheet so it never reaches the top of the screen. That leaves a
      // tappable scrim above it and keeps the drag handle reachable, so it can
      // be dismissed by tapping outside or dragging down — no Done button needed.
      final maxSheetHeight = MediaQuery.of(context).size.height * 0.85;
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        constraints: BoxConstraints(maxHeight: maxSheetHeight),
        builder: (ctx) {
          return StatefulBuilder(builder: (ctx, setSheet) {
            final cs = Theme.of(ctx).colorScheme;
            final selected = (sharedPreferences.getStringList(KEY_LISTS_TO_REVIEW) ??
                    [KEY_FAVOURITES_ENTRIES])
                .toSet();

            void toggle(String key) {
              final s = (sharedPreferences.getStringList(KEY_LISTS_TO_REVIEW) ??
                      [KEY_FAVOURITES_ENTRIES])
                  .toSet();
              if (!s.add(key)) s.remove(key);
              sharedPreferences.setStringList(KEY_LISTS_TO_REVIEW, s.toList());
              setState(() => updateRevisionSettings());
              setSheet(() {});
            }

            Widget listRow(EntryList el) => HearthRow(
                  icon: el.key == KEY_FAVOURITES_ENTRIES
                      ? Icons.star
                      : Icons.list_alt,
                  title: el.getName(context),
                  trailing: Checkbox(
                      value: selected.contains(el.key),
                      onChanged: (_) => toggle(el.key)),
                  onTap: () => toggle(el.key),
                );

            // A collapsible section. Its expanded/collapsed state is remembered
            // across sessions in shared prefs.
            Widget collapsibleSection(
                String id, String label, Iterable<EntryList> lists) {
              if (lists.isEmpty) return const SizedBox.shrink();
              final prefKey = 'flashcards_sources_expanded_$id';
              return ExpansionTile(
                // Drop ExpansionTile's default divider lines for a clean look.
                shape: const Border(),
                collapsedShape: const Border(),
                tilePadding: const EdgeInsets.symmetric(horizontal: 20),
                childrenPadding: EdgeInsets.zero,
                iconColor: cs.onSurfaceVariant,
                collapsedIconColor: cs.onSurfaceVariant,
                initiallyExpanded: sharedPreferences.getBool(prefKey) ?? true,
                onExpansionChanged: (v) =>
                    sharedPreferences.setBool(prefKey, v),
                title: Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                children: lists.map(listRow).toList(),
              );
            }

            final List<EntryList> myLists = <EntryList>[
              ...listsService.myLists,
              if (sharing.isEnabled)
                ...sharing.lists.editorLists.where((e) => !e.meta.orphaned),
            ];
            final List<EntryList> subscribed = sharing.isEnabled
                ? <EntryList>[...sharing.lists.subscribedLists]
                : const <EntryList>[];
            final List<EntryList> community =
                (sharedPreferences.getBool(KEY_HIDE_COMMUNITY_LISTS) ?? false)
                    ? const <EntryList>[]
                    : <EntryList>[...communityEntryListManager.getEntryLists().values];

            return SafeArea(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 2, 20, 8),
                        child: Text(l.flashcardsSelectLists,
                            style: Theme.of(ctx).textTheme.titleLarge),
                      ),
                      collapsibleSection('mylists', l.listMyLists, myLists),
                      collapsibleSection(
                          'subscribed', l.listSharedWithMeTab, subscribed),
                      collapsibleSection(
                          'community', l.listCommunity, community),
                    ],
                  ),
                ),
              ),
            );
          });
        },
      );
    }

    // An outlined card wrapping rows separated by hairline dividers.
    Widget settingsCard(List<Widget> rows, {EdgeInsetsGeometry? padding}) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: HearthRowGroup(rows: rows, padding: padding),
      );
    }

    // Selected revision sources (Favourites + any chosen lists).
    final sourceRows = <Widget>[];
    for (final e in entryListsToRevise.entries) {
      final el = e.value;
      final count = el.uniqueEntries.length;
      sourceRows.add(HearthRow(
        icon: el.key == KEY_FAVOURITES_ENTRIES ? Icons.star : Icons.list_alt,
        title: el.getName(context),
        subtitle: l.revisionSignCount(count),
        onTap: openSourcesPicker,
      ));
    }
    if (sourceRows.isEmpty) {
      sourceRows
          .add(HearthRow(title: l.revisionNoListsChosen, onTap: openSourcesPicker));
    }

    // The "Revision settings" card rows — currently the app-specific extras
    // (e.g. Auslan's sign-region configurator).
    final settingRows = widget.controller.getExtraSettingsRows(
        context, setState, onPrefSwitch, updateRevisionSettings);

    Function()? onPressedStart;
    if (startValid()) {
      onPressedStart = () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
              builder: (context) => widget.controller.buildFlashcardsPage(
                    dolphinInformation: dolphinInformation,
                    revisionStrategy: revisionStrategy,
                    existingReviews: existingReviews ?? [],
                  )),
        );
        setState(() {
          existingReviews = readReviews();
        });
        printAndLog(
            "Pop: Read ${existingReviews!.length} reviews from storage");
        updateRevisionSettings();
      };
    }

    final listChildren = <Widget>[
      // --- Revision sources ---
      HearthSectionLabel(l.flashcardsRevisionSources,
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 8)),
      settingsCard(sourceRows),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 2, 12, 0),
        child: Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: openSourcesPicker,
            icon: const Icon(Icons.add, size: 20),
            label: Text(l.flashcardsAddAnotherList),
          ),
        ),
      ),
      // --- Flashcard types ---
      HearthSectionLabel(l.flashcardsTypes,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8)),
      settingsCard([
        HearthRow(
          icon: Icons.style,
          title: l.flashcardsSignToWord,
          subtitle: l.flashcardsSignToWordSubtitle,
          trailing: Switch(
              value: signToWord,
              onChanged: (v) {
                onPrefSwitch(KEY_SIGN_TO_WORD, v, true);
                updateRevisionSettings();
              }),
          onTap: () {
            onPrefSwitch(KEY_SIGN_TO_WORD, !signToWord, true);
            updateRevisionSettings();
          },
        ),
        HearthRow(
          icon: Icons.search,
          title: l.flashcardsWordToSign,
          subtitle: l.flashcardsWordToSignSubtitle,
          trailing: Switch(
              value: wordToSign,
              onChanged: (v) {
                onPrefSwitch(KEY_WORD_TO_SIGN, v, true);
                updateRevisionSettings();
              }),
          onTap: () {
            onPrefSwitch(KEY_WORD_TO_SIGN, !wordToSign, true);
            updateRevisionSettings();
          },
        ),
      ]),
      if (!typesValid)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Text(l.flashcardsChooseType,
              style: TextStyle(fontSize: 12.5, color: cs.error)),
        ),
      // --- Revision settings ---
      HearthSectionLabel(l.flashcardsRevisionSettings,
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 8)),
      settingsCard(
        [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.flashcardsStrategyLabel,
                  style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface)),
              const SizedBox(height: 10),
              HearthSegmented(
                options: [
                  RevisionStrategy.SpacedRepetition.pretty,
                  RevisionStrategy.Random.pretty,
                ],
                selected: revisionStrategy == RevisionStrategy.SpacedRepetition
                    ? 0
                    : 1,
                onChanged: (i) async {
                  await sharedPreferences.setInt(
                      KEY_REVISION_STRATEGY,
                      i == 0
                          ? RevisionStrategy.SpacedRepetition.index
                          : RevisionStrategy.Random.index);
                  setState(() {
                    updateRevisionSettings();
                  });
                },
              ),
              const SizedBox(height: 18),
              Text(l.flashcardsCardLimitLabel,
                  style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface)),
              const SizedBox(height: 6),
              // How many cards a session serves at most. 0 = no limit, and the
              // choice is remembered across sessions.
              Align(
                alignment: Alignment.centerLeft,
                child: DropdownButton<int>(
                  value: cardLimit,
                  items: [
                    DropdownMenuItem(
                        value: 0, child: Text(l.flashcardsCardLimitNone)),
                    for (final n in const [10, 25, 50, 100])
                      DropdownMenuItem(value: n, child: Text('$n')),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    sharedPreferences.setInt(KEY_REVISION_CARD_LIMIT, v);
                    setState(() {});
                  },
                ),
              ),
            ],
          ),
        ],
        padding: const EdgeInsets.all(14),
      ),
      // App-specific extra rows (e.g. Auslan's sign-region configurator). Drop
      // the card entirely when an app has none, so there's no empty outlined box.
      // Give it clear separation from the settings card above it.
      if (settingRows.isNotEmpty) ...[
        const SizedBox(height: 16),
        settingsCard(settingRows),
      ],
      ...widget.controller
          .getExtraBottomWidgets(context, setState, updateRevisionSettings),
      const SizedBox(height: 8),
    ];

    // Sticky bottom bar with the live count + Start.
    final dueLabel = revisionStrategy == RevisionStrategy.SpacedRepetition
        ? l.revisionDueNow
        : l.revisionSelected;
    Widget startBar = Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(top: BorderSide(color: cs.outlineVariant)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(dueLabel,
                  style: TextStyle(fontSize: 13.5, color: cs.onSurfaceVariant)),
              const Spacer(),
              Text(l.revisionFlashcardCount(cardsToDo),
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: cs.onSurface)),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const ValueKey("startButton"),
              onPressed: onPressedStart,
              style: FilledButton.styleFrom(minimumSize: const Size(0, 54)),
              icon: const Icon(Icons.play_arrow),
              label: Text(l.flashcardsStart),
            ),
          ),
        ],
      ),
    );

    Widget body = Column(children: [
      Expanded(
        child: ListView(
            padding: const EdgeInsets.only(top: 4, bottom: 16),
            children: listChildren),
      ),
      startBar,
    ]);

    List<Widget> actions = [
      buildActionButton(
        context,
        const Icon(Icons.timeline),
        () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => RevisionHistoryPage()),
          );
        },
      ),
      buildActionButton(
        context,
        const Icon(Icons.help),
        () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) => widget.controller.buildHelpPage(context)),
          );
        },
      )
    ];

    return TopLevelScaffold(
        body: body, title: l.revisionTitle, actions: actions);
  }
}

class LifecycleEventHandler extends WidgetsBindingObserver {
  final AsyncCallback resumeCallBack;

  LifecycleEventHandler({
    required this.resumeCallBack,
  });

  @override
  Future<void> didChangeAppLifecycleState(AppLifecycleState state) async {
    switch (state) {
      case AppLifecycleState.resumed:
        await resumeCallBack();
        break;
      case AppLifecycleState.hidden:
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        break;
    }
  }
}
