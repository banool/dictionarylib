import 'dart:collection';
import 'dart:io';

import 'package:edit_distance/edit_distance.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:multi_select_flutter/multi_select_flutter.dart';

import 'entry_types.dart';
import 'globals.dart';
import 'l10n/app_localizations.dart';

const String KEY_LOCALE_OVERRIDE = "locale_override";

const String KEY_SHOULD_CACHE = "should_cache";

const String KEY_WEB_DICTIONARY_DATA = "web_dictionary_data";

const String KEY_ADVISORY_VERSION = "advisory_version";

const String KEY_SEARCH_FOR_WORDS = "search_for_words";
const String KEY_SEARCH_FOR_PHRASES = "search_for_phrases";
const String KEY_SEARCH_FOR_FINGERSPELLING = "search_for_fingerspelling";

const String KEY_FAVOURITES_ENTRIES = "favourites_words";
const String KEY_LAST_DICTIONARY_DATA_CHECK_TIME_SECS = "last_data_check_time";
const String KEY_DICTIONARY_DATA_CURRENT_VERSION = "current_data_version";
const String KEY_HIDE_FLASHCARDS_FEATURE = "hide_flashcards_feature";
const String KEY_HIDE_COMMUNITY_LISTS = "hide_community_lists";
const String KEY_FLASHCARD_REGIONS = "flashcard_regions";
const String KEY_REVISION_STRATEGY = "revision_strategy";
const String KEY_REVISION_LANGUAGE_CODE = "revision_language_code";
const String KEY_THEME_MODE = "theme_mode";
const String KEY_USE_SYSTEM_HTTP_PROXY = "use_system_http_proxy";

const int DEFAULT_THEME_MODE = 1; // Light.

const String PRIVACY_POLICY_EMAIL = 'srilankansignlanguage1@gmail.com';

const int DATA_CHECK_INTERVAL = 30 * 60 * 1; // 30 minutes.

const int NUM_DAYS_TO_CACHE = 21;

const int SEARCH_FOR_NUM_ITEMS = 25;

final GlobalKey<NavigatorState> rootNavigatorKey =
    GlobalKey<NavigatorState>(debugLabel: 'root');

bool getShouldUseHorizontalLayout(BuildContext context) {
  var screenSize = MediaQuery.of(context).size;
  var shouldUseHorizontalDisplay = screenSize.width > screenSize.height * 1.2;
  return shouldUseHorizontalDisplay;
}

// Reaches out to check the value of the knob. If this succeeds, we store the
// value locally. If this fails, we first check the local store to attempt to
// use the value the value we last saw for the knob. If there is nothing there,
// we use the hardcoded `fallback` value.
Future<bool> readKnob(String urlBase, String key, bool fallback) async {
  String sharedPrefsKey = "knob_$key";
  try {
    String url = '$urlBase$key';
    var result =
        await http.get(Uri.parse(url)).timeout(const Duration(seconds: 4));
    String raw = result.body.replaceAll("\n", "");
    bool out;
    if (raw == "true") {
      out = true;
    } else if (raw == "false") {
      out = false;
    } else {
      throw "Failed to check knob at $url, using fallback value: $fallback, due to ${result.body}";
    }
    await sharedPreferences.setBool(sharedPrefsKey, out);
    print("Value of knob $key is $out, stored at $sharedPrefsKey");
    return out;
  } catch (e, stacktrace) {
    print("$e:\n$stacktrace");
    var out = sharedPreferences.getBool(sharedPrefsKey) ?? fallback;
    print("Returning fallback value for knob $key: $out");
    return out;
  }
}

bool getShowFlashcards() {
  // Don't show flashcards on web.
  if (kIsWeb) {
    return false;
  }
  if (!enableFlashcardsKnob) {
    return false;
  }
  return !(sharedPreferences.getBool(KEY_HIDE_FLASHCARDS_FEATURE) ?? false);
}

bool getShowLists() {
  return !kIsWeb;
}

// Search a list of entries and return top matching items.
List<Entry> searchList(BuildContext context, String searchTerm,
    List<EntryType> entryTypes, Set<Entry> entries, Set<Entry> fallback) {
  final SplayTreeMap<double, List<Entry>> st =
      SplayTreeMap<double, List<Entry>>();
  if (searchTerm == "") {
    return List.from(fallback);
  }
  searchTerm = searchTerm.toLowerCase();
  JaroWinkler d = JaroWinkler();
  RegExp noParenthesesRegExp = RegExp(
    r"^[^ (]*",
    caseSensitive: false,
    multiLine: false,
  );
  print("Searching ${entries.length} entries with entryTypes $entryTypes");
  Locale currentLocale = Localizations.localeOf(context);
  for (Entry e in entries) {
    if (!entryTypes.contains(e.getEntryType())) {
      continue;
    }
    String? phrase = e.getPhrase(currentLocale);
    if (phrase == null) {
      continue;
    }
    String noPunctuation = phrase.replaceAll(" ", "").replaceAll(",", "");
    String lowerCase = noPunctuation.toLowerCase();
    String noParenthesesContent = noParenthesesRegExp.stringMatch(lowerCase)!;
    String normalisedEntry = noParenthesesContent;
    double difference = d.normalizedDistance(normalisedEntry, searchTerm);
    if (difference == 1.0) {
      continue;
    }
    st.putIfAbsent(difference, () => []).add(e);
  }
  List<Entry> out = [];
  for (List<Entry> entries in st.values) {
    out.addAll(entries);
    if (out.length > SEARCH_FOR_NUM_ITEMS) {
      break;
    }
  }
  return out;
}

Future<bool> confirmAlert(BuildContext context, Widget content,
    {String? title, String? cancelText, String? confirmText}) async {
  title = title ?? DictLibLocalizations.of(context)!.alertCareful;
  cancelText = cancelText ?? DictLibLocalizations.of(context)!.alertCancel;
  confirmText = confirmText ?? DictLibLocalizations.of(context)!.alertConfirm;
  bool confirmed = false;
  Widget cancelButton = TextButton(
    child: Text(cancelText, style: const TextStyle()),
    onPressed: () {
      Navigator.of(context).pop();
    },
  );
  Widget continueButton = TextButton(
    child: Text(confirmText, style: const TextStyle()),
    onPressed: () {
      confirmed = true;
      Navigator.of(context).pop();
    },
  );
  AlertDialog alert = AlertDialog(
    title: Text(title),
    content: content,
    actions: [
      cancelButton,
      continueButton,
      const Padding(padding: EdgeInsets.only(right: 0))
    ],
  );
  await showDialog(
    context: context,
    builder: (BuildContext context) {
      return alert;
    },
  );
  return confirmed;
}

Widget buildActionButton(
    BuildContext context, Icon icon, void Function() onPressed,
    {bool enabled = true}) {
  void Function()? onPressedFunc = onPressed;
  if (!enabled) {
    onPressedFunc = null;
  }
  return IconButton(
      onPressed: onPressedFunc,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(
        minWidth: 45,
        maxWidth: 45,
      ),
      icon: icon);
}

List<Widget> buildActionButtons(List<Widget> actions) {
  actions =
      actions + <Widget>[const Padding(padding: EdgeInsets.only(right: 5))];
  return actions;
}

extension StripString on String {
  String lstrip(String pattern) {
    return replaceFirst(RegExp('^$pattern*'), '');
  }

  String rstrip(String pattern) {
    return replaceFirst(RegExp(pattern + r'*$'), '');
  }
}

// For logging of things that occur in the background, particularly errors.
void printAndLog(Object? obj) {
  print(obj);
  backgroundLogs.enqueue("$obj");
}

// This is a queue that has a maximum length. When you add an item to the queue
// and it is already at maximum length, the oldest item is removed.
class MaxLengthQueue<T> {
  final int _maxLength;
  final List<T> _items = [];

  MaxLengthQueue(this._maxLength);

  void enqueue(T item) {
    if (_items.length >= _maxLength) {
      _items.removeAt(0);
    }
    _items.add(item);
  }

  T? dequeue() {
    if (_items.isEmpty) {
      return null;
    }
    return _items.removeAt(0);
  }

  List<T> get items => _items;

  @override
  String toString() => _items.toString();
}

String convertUnixTimeToHttpDate(int unixTime) {
  // Convert the Unix time to a DateTime object
  DateTime dateTime =
      DateTime.fromMillisecondsSinceEpoch(unixTime * 1000, isUtc: true);

  // Use the HttpDate class to format the DateTime object to an HTTP date
  String httpDate = HttpDate.format(dateTime);

  return httpDate;
}

Text getText(String s, {bool larger = false, Color? color}) {
  double size = 15;
  if (larger) {
    size = 18;
  }
  return Text(
    s,
    textAlign: TextAlign.center,
    style: TextStyle(fontSize: size, color: color),
  );
}

typedef NavigateToEntryPageFn = Future<void> Function(
  BuildContext context,
  Entry entry,
  bool showFavouritesButton,
);

/// The selected chips look weird in dark mode so we have to override the colors
/// here based on the theme.
Widget buildMultiSelectDialog<T>({
  required BuildContext context,
  required String title,
  required List<MultiSelectItem<T>> items,
  required List<T> initialValue,
  required void Function(List<T>) onConfirm,
  bool searchable = false,
}) {
  Brightness brightness = Theme.of(context).brightness;
  ColorScheme colorScheme = Theme.of(context).colorScheme;
  return MultiSelectDialog(
    listType: MultiSelectListType.CHIP,
    title: Text(title),
    items: items,
    initialValue: initialValue,
    onConfirm: onConfirm,
    selectedColor: brightness == Brightness.dark ? colorScheme.primary : null,
    unselectedColor: brightness == Brightness.dark ? colorScheme.surface : null,
    // It seems like checkColor doesn't do anything.
    checkColor: brightness == Brightness.dark ? colorScheme.onPrimary : null,
    selectedItemsTextStyle: brightness == Brightness.dark
        ? TextStyle(color: colorScheme.onPrimary)
        : null,
    searchable: searchable,
  );
}

Widget? getInnerRelatedEntriesWidget(
    {required BuildContext context,
    required SubEntry subEntry,
    required bool shouldUseHorizontalDisplay,
    required Entry? Function(String) getRelatedEntry,
    required Future<void> Function(
            BuildContext context, Entry entry, bool showFavouritesButton)
        navigateToEntryPage}) {
  ColorScheme colorScheme = Theme.of(context).colorScheme;
  int numRelatedWords = subEntry.getRelatedWords().length;
  if (numRelatedWords == 0) {
    return null;
  }

  List<TextSpan> textSpans = [];

  int idx = 0;
  for (String relatedWord in subEntry.getRelatedWords()) {
    bool isRelated = false;
    void Function()? navFunction;
    Entry? relatedEntry = getRelatedEntry(relatedWord);

    if (relatedEntry != null) {
      navFunction = () => navigateToEntryPage(context, relatedEntry, true);
      isRelated = true;
    } else {
      navFunction = null;
    }
    String suffix;
    if (idx < numRelatedWords - 1) {
      suffix = ", ";
    } else {
      suffix = "";
    }
    textSpans.add(TextSpan(
      text: relatedWord,
      style: TextStyle(
          color: colorScheme.onSurface,
          decoration: isRelated ? TextDecoration.underline : null),
      recognizer: TapGestureRecognizer()..onTap = navFunction,
    ));
    textSpans.add(
        TextSpan(text: suffix, style: TextStyle(color: colorScheme.onSurface)));
    idx += 1;
  }

  var initial = TextSpan(
      text: "Related words: ",
      style:
          TextStyle(color: colorScheme.onSurface, fontWeight: FontWeight.bold));
  textSpans = [initial] + textSpans;
  var richText = RichText(
    text: TextSpan(children: textSpans),
    textAlign: TextAlign.center,
  );

  if (shouldUseHorizontalDisplay) {
    return Padding(
        padding: const EdgeInsets.only(left: 10.0, right: 20.0, top: 5.0),
        child: richText);
  } else {
    return Padding(
        padding: const EdgeInsets.only(left: 20.0, right: 20.0, top: 15.0),
        child: richText);
  }
}
