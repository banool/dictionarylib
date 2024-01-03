import 'package:flutter/material.dart';
import 'package:dictionarylib/dictionarylib.dart' show AppLocalizations;

import 'advisories.dart';
import 'common.dart';
import 'entry_types.dart';
import 'globals.dart';
import 'top_level_scaffold.dart';

class SearchPage extends StatefulWidget {
  // This will only ever be set if this page was opened via a deeplink.
  final String? initialQuery;

  // If this is set we'll navigate to the first match immediately upon load.
  final bool? navigateToFirstMatch;

  final Color mainColor;
  final Color appBarDisabledColor;

  final Future<void> Function(
    BuildContext context,
    Entry entry,
    bool showFavouritesButton,
  ) navigateToEntryPage;

  final bool includeEntryTypeButton;

  const SearchPage(
      {super.key,
      this.initialQuery,
      this.navigateToFirstMatch,
      required this.mainColor,
      required this.appBarDisabledColor,
      required this.navigateToEntryPage,
      required this.includeEntryTypeButton});

  @override
  SearchPageState createState() => SearchPageState();
}

class SearchPageState extends State<SearchPage> {
  List<Entry?> entriesSearched = [];
  int currentNavBarIndex = 0;

  String? searchTerm;

  final _searchFieldController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.initialQuery != null) {
      searchTerm = widget.initialQuery;
      _searchFieldController.text = widget.initialQuery!;
      search(widget.initialQuery!, getEntryTypes());
    }
  }

  void search(String searchTerm, List<EntryType> entryTypes) {
    setState(() {
      entriesSearched =
          searchList(context, searchTerm, entryTypes, entriesGlobal, {});
    });
  }

  void clearSearch() {
    setState(() {
      searchTerm = null;
      entriesSearched = [];
      _searchFieldController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (advisoriesResponse != null &&
        advisoriesResponse!.newAdvisories &&
        advisoriesResponse!.advisories.isNotEmpty &&
        !advisoryShownOnce) {
      Future.delayed(
          const Duration(milliseconds: 500), () => showAdvisoryDialog());
      advisoryShownOnce = true;
    }

    // Navigate to the first match if words have been searched and the page
    // was built with that setting enabled.
    if (widget.navigateToFirstMatch ?? false) {
      if (entriesSearched.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          printAndLog(
              "Navigating to first match because navigateToFirstMatch was set");
          widget.navigateToEntryPage(context, entriesSearched[0]!, true);
        });
      }
    }

    Widget body = Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 0.0, vertical: 8.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          mainAxisSize: MainAxisSize.max,
          children: [
            Padding(
                padding: const EdgeInsets.only(
                    bottom: 10, left: 32, right: 10, top: 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Form(
                        key: const ValueKey("searchPage.searchForm"),
                        child: TextField(
                          controller: _searchFieldController,
                          decoration: InputDecoration(
                            hintText:
                                AppLocalizations.of(context)!.searchHintText,
                            suffixIcon: IconButton(
                              onPressed: () {
                                clearSearch();
                              },
                              icon: const Icon(Icons.clear),
                            ),
                          ),
                          // The validator receives the text that the user has entered.
                          onChanged: (String value) {
                            setState(() {
                              searchTerm = value;
                            });
                            search(value, getEntryTypes());
                          },
                          autofocus: true,
                          textInputAction: TextInputAction.search,
                          keyboardType: TextInputType.visiblePassword,
                          autocorrect: false,
                        ),
                      ),
                    ),
                    ...widget.includeEntryTypeButton
                        ? [
                            Padding(
                                padding: const EdgeInsets.only(left: 4),
                                child: EntryTypeMultiPopUpMenu(
                                    onChanged: (entryTypes) async {
                                  for (EntryType type in EntryType.values) {
                                    String key;
                                    if (type == EntryType.WORD) {
                                      key = KEY_SEARCH_FOR_WORDS;
                                    } else if (type == EntryType.PHRASE) {
                                      key = KEY_SEARCH_FOR_PHRASES;
                                    } else if (type ==
                                        EntryType.FINGERSPELLING) {
                                      key = KEY_SEARCH_FOR_FINGERSPELLING;
                                    } else {
                                      throw Exception(
                                          "Unknown entry type: $type");
                                    }
                                    // It would be best to wait for this to complete but
                                    // given this generally happens lightning fast I'll
                                    // leave it as a todo.
                                    if (entryTypes.contains(type)) {
                                      await sharedPreferences.setBool(
                                          key, true);
                                    } else {
                                      await sharedPreferences.setBool(
                                          key, false);
                                    }
                                    setState(() {
                                      if (searchTerm != null) {
                                        search(searchTerm!, getEntryTypes());
                                      }
                                    });
                                  }
                                }))
                          ]
                        : [],
                  ],
                )),
            Expanded(
              child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: buildListWidget(context, entriesSearched)),
            ),
          ],
        ),
      ),
    );

    List<Widget> actions = [];
    if (advisoriesResponse != null &&
        advisoriesResponse!.advisories.isNotEmpty) {
      actions.add(buildActionButton(
        context,
        const Icon(Icons.article),
        () async {
          showAdvisoryDialog();
        },
        widget.appBarDisabledColor,
      ));
    }

    return TopLevelScaffold(
        body: body,
        mainColor: widget.mainColor,
        title: AppLocalizations.of(context)!.searchTitle,
        actions: actions);
  }

  Widget buildListWidget(BuildContext context, List<Entry?> entriesSearched) {
    return ListView.builder(
      itemCount: entriesSearched.length,
      itemBuilder: (context, index) {
        return ListTile(title: buildListItem(context, entriesSearched[index]!));
      },
    );
  }

  Widget buildListItem(BuildContext context, Entry entry) {
    Locale currentLocale = Localizations.localeOf(context);
    return TextButton(
      child: Align(
          alignment: Alignment.topLeft,
          child: Text("${entry.getPhrase(currentLocale)}",
              style: const TextStyle(color: Colors.black))),
      onPressed: () => widget.navigateToEntryPage(context, entry, true),
    );
  }
}

// This widget lets users select which entry types they want to see.
class EntryTypeMultiPopUpMenu extends StatefulWidget {
  final Future<void> Function(List<EntryType>) onChanged;

  const EntryTypeMultiPopUpMenu({super.key, required this.onChanged});

  @override
  EntryTypeMultiPopUpMenuState createState() => EntryTypeMultiPopUpMenuState();
}

class EntryTypeMultiPopUpMenuState extends State<EntryTypeMultiPopUpMenu> {
  List<EntryType> _selectedEntryTypes = [];

  @override
  void initState() {
    super.initState();
    _selectedEntryTypes = getEntryTypes();
  }

  Future<void> _showDialog(BuildContext context) async {
    await showDialog(
        context: context,
        builder: (BuildContext context) {
          return StatefulBuilder(
              builder: (BuildContext context, StateSetter setState) {
            return AlertDialog(
              title: Text(AppLocalizations.of(context)!.entrySelectEntryTypes),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: EntryType.values
                    .map((entryType) => CheckboxListTile(
                          title: Text(getEntryTypePretty(context, entryType)),
                          value: _selectedEntryTypes.contains(entryType),
                          onChanged: (bool? value) {
                            setState(() {
                              if (value == true) {
                                setState(() {
                                  _selectedEntryTypes.add(entryType);
                                });
                              } else {
                                // Ensure at least one entry type is selected.
                                if (_selectedEntryTypes.length == 1) {
                                  return;
                                }
                                setState(() {
                                  _selectedEntryTypes.remove(entryType);
                                });
                              }
                            });
                          },
                        ))
                    .toList(),
              ),
            );
          });
        });
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.filter_list),
      onPressed: () async {
        await _showDialog(context);
        await widget.onChanged(_selectedEntryTypes);
      },
    );
  }
}

List<EntryType> getEntryTypes() {
  List<EntryType> entryTypes = [];
  if (sharedPreferences.getBool(KEY_SEARCH_FOR_WORDS) ?? true) {
    entryTypes.add(EntryType.WORD);
  }
  if (sharedPreferences.getBool(KEY_SEARCH_FOR_PHRASES) ?? false) {
    entryTypes.add(EntryType.PHRASE);
  }
  if (sharedPreferences.getBool(KEY_SEARCH_FOR_FINGERSPELLING) ?? false) {
    entryTypes.add(EntryType.FINGERSPELLING);
  }
  return entryTypes;
}
