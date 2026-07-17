import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:dictionarylib/dictionarylib.dart' show DictLibLocalizations;

import 'analytics.dart';
import 'common.dart';
import 'entry_list.dart';
import 'entry_types.dart';
import 'globals.dart';
import 'hearth.dart';
import 'page_news.dart';
import 'top_level_scaffold.dart';
import 'web_limitations.dart';

/// Deterministic "sign of the day" selection, factored out of the widget so it
/// can be unit-tested without the whole search page (and its GoRouter-backed
/// scaffold). Same sign all day, drawn only from [lists] — the user's saved,
/// subscribed and co-edited lists, never the community lists or the full
/// dictionary (which contains vulgar entries we don't want to surface).
///
/// Entries whose key is in [hiddenKeys] are excluded — that's how "hide this
/// sign of the day" works. Returns null when nothing eligible remains (nothing
/// saved, or every saved sign has been hidden), which is the signal for the
/// caller to simply not render the card.
@visibleForTesting
Entry? computeSignOfDay(
  Iterable<EntryList> lists,
  Set<String> hiddenKeys,
  Locale locale,
  DateTime now,
) {
  final saved = <Entry>{};
  for (final list in lists) {
    for (final entry in list.uniqueEntries) {
      if (hiddenKeys.contains(entry.getKey())) continue;
      if (entry.getPhrase(locale) != null) saved.add(entry);
    }
  }
  if (saved.isEmpty) return null;
  final candidates = saved.toList()
    ..sort((a, b) => a.getPhrase(locale)!.compareTo(b.getPhrase(locale)!));
  // Roll over at local midnight (not UTC) by indexing off the local date.
  final dayIndex =
      DateTime(now.year, now.month, now.day).millisecondsSinceEpoch ~/
          Duration.millisecondsPerDay;
  return candidates[dayIndex % candidates.length];
}

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

  /// Guards the [widget.navigateToFirstMatch] jump so it fires at most once.
  /// Without it, popping back to this page (or any rebuild) re-schedules the
  /// post-frame navigation and traps the user on the entry page.
  bool _navigatedToFirstMatchOnce = false;

  String? searchTerm;

  /// Debounces the anonymous `search_performed` analytics event: search runs on
  /// every keystroke (incremental results), but we only want one event once the
  /// query settles, so it isn't emitted per character.
  Timer? _searchAnalyticsDebounce;

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
    _searchAnalyticsDebounce?.cancel();
    _searchFieldController.dispose();
    super.dispose();
  }

  void search(String searchTerm, List<EntryType> entryTypes) {
    setState(() {
      entriesSearched =
          searchList(context, searchTerm, entryTypes, entriesGlobal, {});
    });
    // Emit one anonymous analytics event once the query settles (never the term
    // itself — only its bucketed length, the bucketed result count, and how many
    // entry-type filters are active).
    _searchAnalyticsDebounce?.cancel();
    if (searchTerm.trim().isEmpty) return;
    final resultCount = entriesSearched.length;
    _searchAnalyticsDebounce = Timer(const Duration(milliseconds: 1200), () {
      Analytics.track('search_performed', props: {
        'term_length_bucket': Analytics.bucket(searchTerm.trim().length),
        'result_count_bucket': Analytics.bucket(resultCount),
        'filters_count': entryTypes.length,
      });
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
    // Not auto-shown on web: every visit is effectively a fresh session there
    // (no persisted "seen" state), so it would pop the news every load. The
    // campaign button in the app bar still opens it on demand.
    if (!kIsWeb &&
        advisoriesResponse != null &&
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
    // was built with that setting enabled. Guarded to fire at most once (and
    // only while mounted) so popping back here doesn't re-push the entry page
    // in a loop — mirrors the advisory once-guard above.
    if ((widget.navigateToFirstMatch ?? false) &&
        !_navigatedToFirstMatchOnce &&
        entriesSearched.isNotEmpty) {
      _navigatedToFirstMatchOnce = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        printAndLog(
            "Navigating to first match because navigateToFirstMatch was set");
        widget.navigateToEntryPage(context, entriesSearched[0]!, true);
      });
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
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
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
      // Entries the user has permanently hidden from the sign of the day.
      final hidden = sharedPreferences
              .getStringList(KEY_HIDDEN_SIGNS_OF_THE_DAY)
              ?.toSet() ??
          const <String>{};
      // Lists you created (local) plus ones you subscribe to or co-edit —
      // never community lists.
      final lists = [
        ...userEntryListManager.getEntryLists().values,
        ...sharing.lists.subscribedLists,
        ...sharing.lists.editorLists,
      ];
      return computeSignOfDay(lists, hidden, locale, DateTime.now());
    } catch (_) {
      return null;
    }
  }

  // Confirm, then permanently exclude [entry] from the sign of the day. On
  // confirmation the entry's key is recorded and setState re-runs _signOfDay,
  // which now skips it and surfaces a different saved sign for today.
  Future<void> _hideSignOfDay(BuildContext context, Entry entry) async {
    final l = DictLibLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.signOfTheDayHideTitle),
        content: Text(l.signOfTheDayHideBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l.signOfTheDayHideConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final hidden =
        sharedPreferences.getStringList(KEY_HIDDEN_SIGNS_OF_THE_DAY) ??
            <String>[];
    final key = entry.getKey();
    if (!hidden.contains(key)) {
      hidden.add(key);
      await sharedPreferences.setStringList(
          KEY_HIDDEN_SIGNS_OF_THE_DAY, hidden);
      // The entry key is deliberately NOT sent — only that the action happened.
      Analytics.track('sign_of_the_day_hidden');
    }
    if (mounted) setState(() {});
  }

  Widget _buildEmptyState(BuildContext context) {
    final l = DictLibLocalizations.of(context)!;
    final locale = Localizations.localeOf(context);
    final recents = _getRecents();
    // No sign of the day on web — it's drawn from saved/subscribed lists and
    // the web build has no personal saved words, so it'd be empty or arbitrary.
    final signOfDay = kIsWeb ? null : _signOfDay(locale);
    // Web-only limitations card, dismissible — remembered in local storage. A
    // storage wipe / different browser just re-shows it, which is fine for a
    // hint.
    const webCardDismissedKey = 'webLimitationsDismissed';
    final webCardDismissed =
        kIsWeb && (sharedPreferences.getBool(webCardDismissedKey) ?? false);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        if (recents.isNotEmpty) ...[
          // Default section-label rhythm (20 above, 8 below) so this and
          // the sign-of-the-day section breathe identically. The compact
          // Clear button keeps the label row at text height.
          HearthSectionLabel(
            l.searchRecent,
            trailing: TextButton(
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: () async {
                await sharedPreferences.remove(KEY_RECENT_SEARCHES);
                setState(() {});
              },
              child: Text(l.searchRecentClear),
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final w in recents)
                ActionChip(
                  avatar: const Icon(Icons.schedule, size: 16),
                  // Cap the width so a long saved term ellipsizes into a tidy
                  // chip instead of overflowing the row.
                  label: ConstrainedBox(
                    constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.6),
                    child:
                        Text(w, maxLines: 1, overflow: TextOverflow.ellipsis),
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
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
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
                          child:
                              Text(MaterialLocalizations.of(ctx).okButtonLabel),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.visibility_off_outlined, size: 18),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(),
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  tooltip: l.signOfTheDayHide,
                  onPressed: () => _hideSignOfDay(context, signOfDay),
                ),
              ],
            ),
          ),
          _signOfDayCard(context, signOfDay),
        ],
        if (kIsWeb && !webCardDismissed) ...[
          // Always give the card generous space above it (recents or not) so it
          // reads as the focus of the otherwise-empty web search screen, and
          // cap it to about half the width — it's a compact notice, not
          // full-bleed content.
          SizedBox(height: MediaQuery.of(context).size.height * 0.16),
          Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.5),
              child: WebLimitationsCard(
                heading: l.webLimitationsHeading,
                points: [
                  l.webLimitationsNoSaving,
                  l.webLimitationsNoLists,
                  l.webLimitationsNoRevision,
                  l.webLimitationsNoSignIn,
                ],
                footer: l.webLimitationsFooter,
                // Web is Auslan-only for now, so this points at the Auslan
                // marketing site where the install buttons live.
                footerUrl: 'https://auslandictionary.org/',
                onDismiss: () {
                  sharedPreferences.setBool(webCardDismissedKey, true);
                  setState(() {});
                },
              ),
            ),
          ),
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
      padding: const EdgeInsets.all(14),
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
                const SizedBox(height: 6),
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
