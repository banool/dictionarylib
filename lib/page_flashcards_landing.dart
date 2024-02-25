import 'package:dictionarylib/common.dart';
import 'package:dictionarylib/entry_list.dart';
import 'package:dictionarylib/entry_types.dart';
import 'package:dictionarylib/flashcards_logic.dart';
import 'package:dictionarylib/globals.dart';
import 'package:dictionarylib/page_revision_history.dart';
import 'package:dictionarylib/revision.dart';
import 'package:dolphinsr_dart/dolphinsr_dart.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:multi_select_flutter/multi_select_flutter.dart';
import 'package:settings_ui/settings_ui.dart';
import 'package:dictionarylib/dictionarylib.dart' show DictLibLocalizations;

import 'top_level_scaffold.dart';

// TODO deal with NaN

abstract class FlashcardsLandingPageController {
  /// This function should read in whatever configuration necessary to figure
  /// out what subentries to finally review.
  Map<Entry, List<SubEntry>> filterSubEntries(
      Map<Entry, List<SubEntry>> subEntries);

  DolphinInformation getDolphin(Map<Entry, List<SubEntry>> filteredSubEntries,
      List<Review>? existingReviews,
      {RevisionStrategy? revisionStrategy}) {
    revisionStrategy = revisionStrategy ?? loadRevisionStrategy();
    var wordToSign = sharedPreferences.getBool(KEY_WORD_TO_SIGN) ?? true;
    var signToEntry = sharedPreferences.getBool(KEY_SIGN_TO_WORD) ?? true;
    // If they haven't selected a revision language before default to English.
    // It'd be better to get the device language but it's a pain to get access
    // to it here.
    var revisionLocale = LANGUAGE_CODE_TO_LOCALE[
            sharedPreferences.getString(KEY_REVISION_LANGUAGE_CODE)] ??
        LOCALE_ENGLISH;
    var masters =
        getMasters(revisionLocale, filteredSubEntries, wordToSign, signToEntry);
    switch (revisionStrategy) {
      case RevisionStrategy.Random:
        return getDolphinInformation(filteredSubEntries, masters,
            reviews: existingReviews);
      case RevisionStrategy.SpacedRepetition:
        // existingReviews must be non-null for the SpacedRepetition case.
        return getDolphinInformation(filteredSubEntries, masters,
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

  List<SettingsTile> getExtraSettingsTiles(
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
  const FlashcardsLandingPage(
      {super.key,
      required this.controller,
      required this.mainColor,
      required this.appBarDisabledColor});

  final Color mainColor;
  final Color appBarDisabledColor;
  final FlashcardsLandingPageController controller;

  @override
  FlashcardsLandingPageState createState() => FlashcardsLandingPageState();
}

class FlashcardsLandingPageState extends State<FlashcardsLandingPage> {
  late int numEnabledFlashcardTypes;

  late final bool initialValueSignToEntry;
  late final bool initialValueEntryToSign;

  late List<String> listsToReview;
  late Set<Entry> entriesFromLists;

  Map<Entry, List<SubEntry>> filteredSubEntries = {};

  late DolphinInformation dolphinInformation;
  List<Review>? existingReviews;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addObserver(LifecycleEventHandler(resumeCallBack: () async {
      updateRevisionSettings();
      printAndLog("Updated revision settings on foregrounding");
    }));
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

  void updateFilteredSubentries() {
    // Get lists we intend to review.
    listsToReview = sharedPreferences.getStringList(KEY_LISTS_TO_REVIEW) ??
        [KEY_FAVOURITES_ENTRIES];

    // Filter out lists that no longer exist.
    listsToReview
        .removeWhere((element) => !getAllEntryLists().containsKey(element));

    // Get the entries from all these lists.
    entriesFromLists = getEntriesFromLists(listsToReview);

    // Get the subentries from all these entries.
    Map<Entry, List<SubEntry>> subEntriesToReview =
        getSubEntriesFromEntries(entriesFromLists);

    // Finally get the final list of filtered subentries.
    setState(() {
      filteredSubEntries =
          widget.controller.filterSubEntries(subEntriesToReview);
    });
  }

  void onPrefSwitch(String key, bool newValue, bool influencesStartValidity) {
    setState(() {
      sharedPreferences.setBool(key, newValue);
      if (influencesStartValidity) {
        if (newValue) {
          numEnabledFlashcardTypes += 1;
        } else {
          numEnabledFlashcardTypes -= 1;
        }
      }
    });
  }

  int getNumValidSubEntries() {
    if (filteredSubEntries.values.isEmpty) {
      return 0;
    }
    if (filteredSubEntries.values.length == 1) {
      return filteredSubEntries.values.toList()[0].length;
    }
    return filteredSubEntries.values
        .map((v) => v.length)
        .reduce((a, b) => a + b);
  }

  bool startValid() {
    var revisionStrategy = loadRevisionStrategy();
    bool flashcardTypesValid = numEnabledFlashcardTypes > 0;
    bool numfilteredSubEntriesValid = getNumValidSubEntries() > 0;
    bool numCardsValid =
        getNumDueCards(dolphinInformation.dolphin, revisionStrategy) > 0;
    bool validBasedOnRevisionStrategy = true;
    return flashcardTypesValid &&
        numfilteredSubEntriesValid &&
        numCardsValid &&
        validBasedOnRevisionStrategy;
  }

  // Call this within setState.
  void updateDolphin() {
    if (existingReviews == null) {
      existingReviews = readReviews();
      print("Start: Read ${existingReviews!.length} reviews from storage");
    }
    dolphinInformation =
        widget.controller.getDolphin(filteredSubEntries, existingReviews);
  }

  void updateRevisionSettings() {
    setState(() {
      updateFilteredSubentries();
      updateDolphin();
    });
  }

  @override
  Widget build(BuildContext context) {
    EdgeInsetsDirectional margin = const EdgeInsetsDirectional.only(
        start: 15, end: 15, top: 10, bottom: 10);

    var revisionStrategy = loadRevisionStrategy();

    int cardsToDo =
        getNumDueCards(dolphinInformation.dolphin, revisionStrategy);
    String cardNumberString;
    switch (revisionStrategy) {
      case RevisionStrategy.Random:
        cardNumberString =
            DictLibLocalizations.of(context)!.nFlashcardsSelected(cardsToDo);
        break;
      case RevisionStrategy.SpacedRepetition:
        cardNumberString =
            DictLibLocalizations.of(context)!.nFlashcardsDue(cardsToDo);
        break;
    }
    cardNumberString = "$cardsToDo $cardNumberString";

    SettingsSection? sourceListSection;
    sourceListSection = SettingsSection(
        title: Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Text(
              DictLibLocalizations.of(context)!.flashcardsRevisionSources,
              style: const TextStyle(fontSize: 16),
            )),
        tiles: [
          SettingsTile.navigation(
            title: getText(DictLibLocalizations.of(context)!
                .flashcardsSelectListsToRevise),
            trailing: Container(),
            onPressed: (BuildContext context) async {
              await showDialog(
                context: context,
                builder: (ctx) {
                  List<MultiSelectItem<String>> items = [];
                  for (MapEntry<String, EntryList> e
                      in getAllEntryLists().entries) {
                    items.add(MultiSelectItem(e.key, e.value.getName()));
                  }
                  return MultiSelectDialog<String>(
                    searchable: true,
                    listType: MultiSelectListType.CHIP,
                    title: Text(DictLibLocalizations.of(context)!
                        .flashcardsSelectLists),
                    items: items,
                    initialValue: listsToReview,
                    onConfirm: (List<String> values) async {
                      await sharedPreferences.setStringList(
                          KEY_LISTS_TO_REVIEW, values);
                      setState(() {
                        updateRevisionSettings();
                      });
                    },
                  );
                },
              );
            },
            description: Text(
              listsToReview
                  .map((key) => EntryList.getNameFromKey(key))
                  .toList()
                  .join(", "),
              textAlign: TextAlign.center,
            ),
          ),
        ]);

    List<AbstractSettingsSection?> sections = [
      sourceListSection,
      SettingsSection(
          title: Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Text(
                DictLibLocalizations.of(context)!.flashcardsTypes,
                style: const TextStyle(fontSize: 16),
              )),
          tiles: [
            SettingsTile.switchTile(
                title: Text(
                  DictLibLocalizations.of(context)!.flashcardsSignToWord,
                  style: const TextStyle(fontSize: 15),
                ),
                initialValue:
                    sharedPreferences.getBool(KEY_SIGN_TO_WORD) ?? true,
                onToggle: (newValue) {
                  onPrefSwitch(KEY_SIGN_TO_WORD, newValue, true);
                  updateRevisionSettings();
                }),
            SettingsTile.switchTile(
                title: Text(
                  DictLibLocalizations.of(context)!.flashcardsWordToSign,
                  style: const TextStyle(fontSize: 15),
                ),
                initialValue:
                    sharedPreferences.getBool(KEY_WORD_TO_SIGN) ?? true,
                onToggle: (newValue) {
                  onPrefSwitch(KEY_WORD_TO_SIGN, newValue, true);
                  updateRevisionSettings();
                }),
          ]),
      SettingsSection(
        title: Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Text(
              DictLibLocalizations.of(context)!.flashcardsRevisionSettings,
              style: const TextStyle(fontSize: 16),
            )),
        tiles: [
          SettingsTile.navigation(
            title: getText(DictLibLocalizations.of(context)!
                .flashcardsSelectRevisionStrategy),
            trailing: Container(),
            onPressed: (BuildContext context) async {
              await showDialog(
                  context: context,
                  builder: (BuildContext context) {
                    SimpleDialog dialog = SimpleDialog(
                      title: Text(
                          DictLibLocalizations.of(context)!.flashcardsStrategy),
                      children: RevisionStrategy.values
                          .map((e) => SimpleDialogOption(
                                child: Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                      border: Border.all(
                                          color: settingsBackgroundColor),
                                      color: settingsBackgroundColor,
                                      borderRadius: BorderRadius.circular(20)),
                                  child: Text(
                                    e.pretty,
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                                onPressed: () async {
                                  await sharedPreferences.setInt(
                                      KEY_REVISION_STRATEGY, e.index);
                                  setState(() {
                                    updateRevisionSettings();
                                  });
                                  if (!context.mounted) return;
                                  Navigator.of(context).pop();
                                },
                              ))
                          .toList(),
                    );
                    return dialog;
                  });
            },
            description: Text(
              revisionStrategy.pretty,
              textAlign: TextAlign.center,
            ),
          ),
          ...widget.controller.getExtraSettingsTiles(
              context, setState, onPrefSwitch, updateRevisionSettings),
          SettingsTile.switchTile(
            title: Text(
              DictLibLocalizations.of(context)!.flashcardsOnlyOneCard,
              style: const TextStyle(fontSize: 15),
            ),
            initialValue:
                sharedPreferences.getBool(KEY_ONE_CARD_PER_WORD) ?? false,
            onToggle: (newValue) {
              onPrefSwitch(KEY_ONE_CARD_PER_WORD, newValue, false);
              updateRevisionSettings();
            },
          )
        ],
        margin: margin,
      ),
    ];

    List<AbstractSettingsSection> nonNullSections = [];
    for (AbstractSettingsSection? section in sections) {
      if (section != null) {
        nonNullSections.add(section);
      }
    }

    Widget settings = SettingsList(
      sections: nonNullSections,
    );

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

    List<Widget> children = [
          Padding(
              padding: const EdgeInsets.only(top: 30, bottom: 10),
              child: TextButton(
                key: const ValueKey("startButton"),
                style: ButtonStyle(
                  backgroundColor: MaterialStateProperty.resolveWith(
                    (states) {
                      if (states.contains(MaterialState.disabled)) {
                        return Colors.grey;
                      } else {
                        return widget.mainColor;
                      }
                    },
                  ),
                  foregroundColor:
                      MaterialStateProperty.all<Color>(Colors.white),
                  minimumSize:
                      MaterialStateProperty.all<Size>(const Size(120, 50)),
                ),
                onPressed: onPressedStart,
                child: Text(
                  DictLibLocalizations.of(context)!.flashcardsStart,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 20),
                ),
              )),
          Text(
            cardNumberString,
            textAlign: TextAlign.center,
          ),
          Expanded(child: settings),
        ] +
        widget.controller
            .getExtraBottomWidgets(context, setState, updateRevisionSettings);

    Widget body = Container(
      color: settingsBackgroundColor,
      child: Center(
          child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: children,
      )),
    );

    List<Widget> actions = [
      buildActionButton(
        context,
        const Icon(Icons.timeline),
        () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) =>
                    RevisionHistoryPage(mainColor: widget.mainColor)),
          );
        },
        widget.appBarDisabledColor,
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
        widget.appBarDisabledColor,
      )
    ];

    return TopLevelScaffold(
        body: body,
        mainColor: widget.mainColor,
        title: DictLibLocalizations.of(context)!.revisionTitle,
        actions: actions);
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
