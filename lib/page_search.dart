import 'package:flutter/material.dart';
import 'package:dictionarylib/dictionarylib.dart' show DictLibLocalizations;

import 'common.dart';
import 'entry_types.dart';
import 'globals.dart';
import 'hearth.dart';
import 'page_news.dart';
import 'top_level_scaffold.dart';

class SearchPage extends StatefulWidget {
  // This will only ever be set if this page was opened via a deeplink.
  final String? initialQuery;

  // If this is set we'll navigate to the first match immediately upon load.
  final bool? navigateToFirstMatch;

  final NavigateToEntryPageFn navigateToEntryPage;

  final bool includeEntryTypeButton;

  /// Optional app-supplied hook returning a short plain-text definition
  /// preview for an entry (used in the "sign of the day" card). The shared
  /// library can't read app-specific definition shapes, so the app provides
  /// this. Null → no preview shown.
  final String? Function(Entry entry)? entryDefinitionPreview;

  const SearchPage(
      {super.key,
      this.initialQuery,
      this.navigateToFirstMatch,
      required this.navigateToEntryPage,
      required this.includeEntryTypeButton,
      this.entryDefinitionPreview});

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
      // Defer to after first build: searchList reads
      // Localizations.localeOf(context), which isn't available in initState.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) search(widget.initialQuery!, getEntryTypes());
      });
    }
  }

  @override
  void dispose() {
    _searchFieldController.dispose();
    super.dispose();
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

  // --- Recent searches (the productive empty state) ---

  List<String> _getRecents() =>
      sharedPreferences.getStringList(KEY_RECENT_SEARCHES) ?? [];

  Future<void> _recordRecent(String phrase) async {
    final list = _getRecents();
    list.remove(phrase);
    list.insert(0, phrase);
    if (list.length > 12) list.removeRange(12, list.length);
    await sharedPreferences.setStringList(KEY_RECENT_SEARCHES, list);
  }

  Future<void> _openEntry(BuildContext context, Entry entry) async {
    // Dismiss the keyboard before navigating (e.g. tapping the sign of the day
    // while the search field still holds focus).
    FocusScope.of(context).unfocus();
    Locale locale = Localizations.localeOf(context);
    final phrase = entry.getPhrase(locale);
    if (phrase != null) await _recordRecent(phrase);
    await widget.navigateToEntryPage(context, entry, true);
    if (mounted) setState(() {});
  }

  Entry? _findByPhrase(BuildContext context, String phrase) {
    Locale locale = Localizations.localeOf(context);
    for (final e in entriesGlobal) {
      if (e.getPhrase(locale) == phrase) return e;
    }
    return null;
  }

  /// Open the News page — the single surface for advisories. Viewing it clears
  /// the "new" flag for this session so the badge/pill stop drawing attention
  /// (the persisted seen-count was already advanced when the advisories were
  /// fetched, so subsequent launches are correct regardless).
  Future<void> _openNews() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const NewsPage()),
    );
    advisoriesResponse?.newAdvisories = false;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (advisoriesResponse != null &&
        advisoriesResponse!.newAdvisories &&
        advisoriesResponse!.advisories.isNotEmpty &&
        !advisoryShownOnce) {
      // Surface new announcements once per session through the News page (the
      // same surface the campaign button opens) rather than a separate dialog.
      advisoryShownOnce = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openNews();
      });
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

    final l = DictLibLocalizations.of(context)!;
    final q = (searchTerm ?? "").trim();

    Widget content;
    if (q.isEmpty) {
      content = _buildEmptyState(context);
    } else if (entriesSearched.isEmpty) {
      content = _buildNoMatch(context, q);
    } else {
      content = _buildResults(context);
    }

    Widget body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: Form(
                  key: const ValueKey("searchPage.searchForm"),
                  child: TextField(
                    controller: _searchFieldController,
                    decoration: InputDecoration(
                      hintText: l.searchHintText,
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: q.isEmpty
                          ? null
                          : IconButton(
                              onPressed: clearSearch,
                              icon: const Icon(Icons.close),
                            ),
                    ),
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
              if (widget.includeEntryTypeButton)
                Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child:
                        EntryTypeMultiPopUpMenu(onChanged: (entryTypes) async {
                      for (EntryType type in EntryType.values) {
                        String key;
                        if (type == EntryType.WORD) {
                          key = KEY_SEARCH_FOR_WORDS;
                        } else if (type == EntryType.PHRASE) {
                          key = KEY_SEARCH_FOR_PHRASES;
                        } else if (type == EntryType.FINGERSPELLING) {
                          key = KEY_SEARCH_FOR_FINGERSPELLING;
                        } else {
                          throw Exception("Unknown entry type: $type");
                        }
                        if (entryTypes.contains(type)) {
                          await sharedPreferences.setBool(key, true);
                        } else {
                          await sharedPreferences.setBool(key, false);
                        }
                        setState(() {
                          if (searchTerm != null) {
                            search(searchTerm!, getEntryTypes());
                          }
                        });
                      }
                    })),
            ],
          ),
        ),
        Expanded(child: content),
      ],
    );

    List<Widget> actions = [];
    if (advisoriesResponse != null &&
        advisoriesResponse!.advisories.isNotEmpty) {
      final icon = advisoriesResponse!.newAdvisories
          ? const Badge(smallSize: 9, child: Icon(Icons.campaign_outlined))
          : const Icon(Icons.campaign_outlined);
      actions.add(buildActionButton(context, icon, () => _openNews()));
    }

    return TopLevelScaffold(body: body, title: l.searchTitle, actions: actions);
  }

  Widget _buildResults(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l = DictLibLocalizations.of(context)!;
    final results = entriesSearched.whereType<Entry>().toList();
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 24),
      itemCount: results.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
            child: Text(
              l.searchResultCount(results.length),
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
            ),
          );
        }
        return _resultRow(context, results[index - 1]);
      },
    );
  }

  Widget _resultRow(BuildContext context, Entry entry) {
    final cs = Theme.of(context).colorScheme;
    final locale = Localizations.localeOf(context);
    final phrase = entry.getPhrase(locale) ?? "";
    final type = entry.getEntryType();
    final l = DictLibLocalizations.of(context)!;
    String? tag;
    if (type == EntryType.PHRASE) {
      tag = l.entryTypePhrase;
    } else if (type == EntryType.FINGERSPELLING) {
      tag = l.entryTypeFingerspelling;
    }
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _openEntry(context, entry),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Expanded(
              child: Text(phrase,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600)),
            ),
            if (tag != null) ...[
              HearthTag(tag),
              const SizedBox(width: 8),
            ],
            Icon(Icons.chevron_right, size: 20, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  Widget _buildNoMatch(BuildContext context, String q) {
    final l = DictLibLocalizations.of(context)!;
    return ListView(
      children: [
        HearthEmptyState(
          icon: Icons.search_off,
          title: l.searchNoMatchTitle(q),
          body: l.searchNoMatchBody,
        ),
      ],
    );
  }

  // Deterministic "sign of the day": same sign all day, picked from the words
  // the user has saved into their own lists (favourites + custom lists).
  // Drawing only from saved words keeps it personal and, crucially, means we
  // never feature a rude sign the user didn't choose to save — the full
  // dictionary contains vulgar entries we don't want to surface. Returns null
  // (so the card simply isn't shown) when nothing is saved, or if the lists
  // aren't available yet — this runs on the home screen, so it must never
  // bring the whole screen down if startup hasn't finished initialising.
  Entry? _signOfDay(Locale locale) {
    try {
      final saved = <Entry>{};
      // Lists you created (local) plus ones you subscribe to or co-edit —
      // never community lists.
      final lists = [
        ...userEntryListManager.getEntryLists().values,
        ...sharing.lists.subscribedLists,
        ...sharing.lists.editorLists,
      ];
      for (final list in lists) {
        for (final entry in list.uniqueEntries) {
          if (entry.getPhrase(locale) != null) saved.add(entry);
        }
      }
      if (saved.isEmpty) return null;
      final candidates = saved.toList()
        ..sort((a, b) => a.getPhrase(locale)!.compareTo(b.getPhrase(locale)!));
      // Roll over at local midnight (not UTC) by indexing off the local date.
      final now = DateTime.now();
      final dayIndex =
          DateTime(now.year, now.month, now.day).millisecondsSinceEpoch ~/
              Duration.millisecondsPerDay;
      return candidates[dayIndex % candidates.length];
    } catch (_) {
      return null;
    }
  }

  Widget _buildEmptyState(BuildContext context) {
    final l = DictLibLocalizations.of(context)!;
    final locale = Localizations.localeOf(context);
    final recents = _getRecents();
    final signOfDay = _signOfDay(locale);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        if (recents.isNotEmpty) ...[
          HearthSectionLabel(
            padding: EdgeInsets.fromLTRB(4, 16, 4, 0),
            l.searchRecent,
            trailing: TextButton(
              onPressed: () async {
                await sharedPreferences.remove(KEY_RECENT_SEARCHES);
                setState(() {});
              },
              child: Text(l.searchRecentClear),
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final w in recents)
                ActionChip(
                  avatar: const Icon(Icons.schedule, size: 16),
                  // Cap the width so a long saved term ellipsizes into a tidy
                  // chip instead of overflowing the row.
                  label: ConstrainedBox(
                    constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.6),
                    child: Text(w, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  onPressed: () {
                    final entry = _findByPhrase(context, w);
                    if (entry != null) {
                      _openEntry(context, entry);
                    } else {
                      _searchFieldController.text = w;
                      setState(() => searchTerm = w);
                      search(w, getEntryTypes());
                    }
                  },
                ),
            ],
          ),
        ],
        if (signOfDay != null) ...[
          HearthSectionLabel(
            l.searchSignOfTheDay,
            trailing: IconButton(
              icon: const Icon(Icons.info_outline, size: 18),
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(),
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              tooltip: l.signOfTheDayInfo,
              onPressed: () => showDialog<void>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text(l.searchSignOfTheDay),
                  content: Text(l.signOfTheDayInfo),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: Text(MaterialLocalizations.of(ctx).okButtonLabel),
                    ),
                  ],
                ),
              ),
            ),
          ),
          _signOfDayCard(context, signOfDay),
        ],
      ],
    );
  }

  Widget _signOfDayCard(BuildContext context, Entry entry) {
    final cs = Theme.of(context).colorScheme;
    final locale = Localizations.localeOf(context);
    final phrase = entry.getPhrase(locale) ?? "";
    final preview = widget.entryDefinitionPreview?.call(entry);
    return HearthCard(
      padding: const EdgeInsets.all(12),
      onTap: () => _openEntry(context, entry),
      child: Row(
        children: [
          // A light, themed illustration tile rather than a real video — the
          // home screen shouldn't spin up a video player just for a still.
          HearthSignIllustration(width: 96, height: 76, seed: phrase.hashCode),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(phrase,
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontSize: 22)),
                const SizedBox(height: 5),
                Text(
                  preview ??
                      DictLibLocalizations.of(context)!.signOfTheDayBlurb,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13, color: cs.onSurfaceVariant, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
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
              title:
                  Text(DictLibLocalizations.of(context)!.entrySelectEntryTypes),
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
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
  }
}

List<EntryType> getEntryTypes() {
  List<EntryType> entryTypes = [];
  if (sharedPreferences.getBool(KEY_SEARCH_FOR_WORDS) ?? true) {
    entryTypes.add(EntryType.WORD);
  }
  if (sharedPreferences.getBool(KEY_SEARCH_FOR_PHRASES) ?? true) {
    entryTypes.add(EntryType.PHRASE);
  }
  if (sharedPreferences.getBool(KEY_SEARCH_FOR_FINGERSPELLING) ?? true) {
    entryTypes.add(EntryType.FINGERSPELLING);
  }
  return entryTypes;
}
