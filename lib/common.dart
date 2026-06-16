import 'dart:collection';
import 'dart:io';

import 'package:edit_distance/edit_distance.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';

import 'entry_list.dart';
import 'entry_types.dart';
import 'saved_video.dart';
import 'globals.dart';
import 'l10n/app_localizations.dart';

const String KEY_LOCALE_OVERRIDE = "locale_override";

const String KEY_SHOULD_CACHE = "should_cache";

const String KEY_WEB_DICTIONARY_DATA = "web_dictionary_data";

const String KEY_ADVISORY_VERSION = "advisory_version";

const String KEY_SEARCH_FOR_WORDS = "search_for_words";
const String KEY_SEARCH_FOR_PHRASES = "search_for_phrases";
const String KEY_SEARCH_FOR_FINGERSPELLING = "search_for_fingerspelling";

// Recently opened words (their phrases), most-recent-first, shown as the
// productive empty state on the search screen.
const String KEY_RECENT_SEARCHES = "recent_searches";

const String KEY_FAVOURITES_ENTRIES = "favourites_words";

const String KEY_LAST_DICTIONARY_DATA_CHECK_TIME_SECS = "last_data_check_time";
const String KEY_DICTIONARY_DATA_CURRENT_VERSION = "current_data_version";
const String KEY_HIDE_FLASHCARDS_FEATURE = "hide_flashcards_feature";
const String KEY_HIDE_COMMUNITY_LISTS = "hide_community_lists";
const String KEY_FLASHCARD_REGIONS = "flashcard_regions";
const String KEY_REVISION_STRATEGY = "revision_strategy";
const String KEY_REVISION_LANGUAGE_CODE = "revision_language_code";

// Optional cap on how many cards a revision session serves. 0 means no limit
// (do every due/selected card). Remembered across sessions.
const String KEY_REVISION_CARD_LIMIT = "revision_card_limit";
const String KEY_THEME_MODE = "theme_mode";
const String KEY_USE_SYSTEM_HTTP_PROXY = "use_system_http_proxy";

// The auth provider (by AuthProvider.name) the user last signed in with, so
// the sign-in dialog can remind a returning, signed-out user which one to use.
const String KEY_LAST_AUTH_PROVIDER = "last_auth_provider";

// Which visual style ("theme variant") to use, e.g. "hearth" or "classic".
// Stored by name so the enum order can change without invalidating it. See
// AppThemeVariant in theme.dart.
const String KEY_THEME_VARIANT = "theme_variant";

// Follow the OS light/dark setting until the user pins one explicitly.
// Index into ThemeMode.values (0 = system, 1 = light, 2 = dark). Keep in
// sync with the startup read in the app's root widget.
const int DEFAULT_THEME_MODE = 0; // System.

/// Defer disposing [controller] until after the current frame so any widget
/// still holding a reference (typically a `TextField` inside a closing
/// dialog) finishes its own disposal first. Disposing synchronously after
/// `showDialog` returns can fire a "used after dispose" assertion because
/// `Navigator.pop` completes the future before the dialog widget tree is
/// unmounted.
void disposeAfterFrame(ChangeNotifier controller) {
  WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
}

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

/// Case-insensitive lexicographic comparison for *display* sorting, so mixed
/// case sorts sensibly ("Apple", "banana", "Cat") instead of all capitals
/// first the way raw code-unit order (String.compareTo) does. Strings that
/// differ only by case fall back to a stable code-unit compare so the order is
/// deterministic.
int compareDisplayNames(String a, String b) {
  final c = a.toLowerCase().compareTo(b.toLowerCase());
  return c != 0 ? c : a.compareTo(b);
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
      throw Exception(
          "Failed to check knob at $url, using fallback value: $fallback, due to ${result.body}");
    }
    await sharedPreferences.setBool(sharedPrefsKey, out);
    printAndLog("Value of knob $key is $out, stored at $sharedPrefsKey");
    return out;
  } catch (e, stacktrace) {
    printAndLog("$e:\n$stacktrace");
    var out = sharedPreferences.getBool(sharedPrefsKey) ?? fallback;
    printAndLog("Returning fallback value for knob $key: $out");
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
  // Shown on web too: you can browse and subscribe to community lists
  // read-only without an account. Creating/editing lists needs the mobile
  // app — those affordances are gated separately (see kIsWeb checks in the
  // lists overview, the share/save buttons, and settings).
  return true;
}

// Matches everything up to the first space or "(", i.e. the head of the phrase
// before any parenthetical content. Hoisted so it's compiled once, not per
// search.
final RegExp _searchNormaliseRegExp = RegExp(r"^[^ (]*");

// Cache of phrase -> normalised search key. Normalisation (strip spaces/commas,
// lowercase, drop parenthetical content) is a pure function of the phrase
// string, so this is keyed by the phrase and never needs invalidation: the same
// phrase always normalises the same way, even across a data refresh. It saves
// recomputing the normalisation for every entry on every keystroke.
final Map<String, String> _normalisedSearchCache = {};

String _normaliseForSearch(String phrase) {
  return _normalisedSearchCache.putIfAbsent(phrase, () {
    final noPunctuation = phrase.replaceAll(" ", "").replaceAll(",", "");
    return _searchNormaliseRegExp.stringMatch(noPunctuation.toLowerCase())!;
  });
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
  Locale currentLocale = Localizations.localeOf(context);
  for (Entry e in entries) {
    if (!entryTypes.contains(e.getEntryType())) {
      continue;
    }
    String? phrase = e.getPhrase(currentLocale);
    if (phrase == null) {
      continue;
    }
    String normalisedEntry = _normaliseForSearch(phrase);
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

/// A confirm/cancel alert.
///
/// In the simple form (no [onConfirm]) tapping Confirm closes the dialog
/// and returns true; Cancel returns false. The caller does whatever it
/// needs after.
///
/// When [onConfirm] is supplied, the dialog stays open while the callback
/// runs: the Confirm button is replaced by a spinner and Cancel is
/// disabled. On success the dialog closes and returns true. On failure
/// the dialog stays open (so the user can retry) and an error snackbar
/// is shown; the message comes from [errorMessage] if provided, else
/// `e.toString()`. This means a caller doesn't have to write its own
/// "show a spinner, await the future, show a snackbar on error" boilerplate
/// — and crucially the user gets visible feedback that the network call
/// is in flight before any UI dismissal.
Future<bool> confirmAlert(
  BuildContext context,
  Widget content, {
  String? title,
  String? cancelText,
  String? confirmText,
  Future<void> Function()? onConfirm,
  String Function(Object error)? errorMessage,
}) async {
  title ??= DictLibLocalizations.of(context)!.alertCareful;
  cancelText ??= DictLibLocalizations.of(context)!.alertCancel;
  confirmText ??= DictLibLocalizations.of(context)!.alertConfirm;
  // Captured before any await so we don't reach across an async gap.
  final messenger = ScaffoldMessenger.of(context);
  final errorColor = Theme.of(context).colorScheme.error;

  bool confirmed = false;
  await showDialog<void>(
    context: context,
    // While an async confirm is in-flight the user shouldn't be able to
    // tap-outside-to-dismiss — that'd leave the task running with no UI.
    barrierDismissible: onConfirm == null,
    // `running` lives here (in the showDialog builder, run once) rather than
    // inside the StatefulBuilder's builder — otherwise every setLocal rebuild
    // re-initialises it to false and the spinner never shows.
    builder: (ctx) {
      bool running = false;
      return StatefulBuilder(builder: (ctx, setLocal) {
        Future<void> handleConfirm() async {
          if (onConfirm == null) {
            confirmed = true;
            Navigator.of(ctx).pop();
            return;
          }
          setLocal(() => running = true);
          try {
            await onConfirm();
            confirmed = true;
            if (ctx.mounted) Navigator.of(ctx).pop();
          } catch (e) {
            if (ctx.mounted) setLocal(() => running = false);
            messenger.showSnackBar(_tapToDismissSnackBar(
              messenger,
              Text(errorMessage?.call(e) ?? e.toString()),
              backgroundColor: errorColor,
            ));
          }
        }

        return AlertDialog(
          title: Text(title!),
          content: content,
          actions: [
            TextButton(
              onPressed: running ? null : () => Navigator.of(ctx).pop(),
              child: Text(cancelText!),
            ),
            TextButton(
              onPressed: running ? null : handleConfirm,
              child: running
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(confirmText!),
            ),
          ],
        );
      });
    },
  );
  return confirmed;
}

/// Run [task] behind a non-dismissible spinner dialog. On success the
/// dialog closes silently; on failure it closes and an error snackbar is
/// shown (message via [errorMessage], default `e.toString()`). Returns
/// true on success, false on failure — handy for "tap a thing → it should
/// show a spinner → then either complete or surface an error" flows where
/// there's no preceding confirm step (e.g. Sync now).
Future<bool> runWithProgress({
  required BuildContext context,
  required String message,
  required Future<void> Function() task,
  String Function(Object error)? errorMessage,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final cs = Theme.of(context).colorScheme;
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => Center(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 12),
            Text(message),
          ]),
        ),
      ),
    ),
  );
  bool ok = false;
  try {
    await task();
    ok = true;
  } catch (e) {
    messenger.showSnackBar(_tapToDismissSnackBar(
      messenger,
      Text(errorMessage?.call(e) ?? e.toString(),
          style: TextStyle(color: cs.onError)),
      backgroundColor: cs.error,
    ));
  } finally {
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
  }
  return ok;
}

/// Build a SnackBar whose *entire* surface — the text and the padding around
/// it — dismisses on tap.
///
/// Wrapping only the text in the tap target leaves a dead zone in the toast's
/// own vertical padding (~14px above and below the text) that swallows taps, so
/// the toast feels un-dismissible when tapped anywhere but dead-centre. We zero
/// the SnackBar's padding and re-add it *inside* the GestureDetector so the
/// whole toast is tappable. All toasts go through here so this stays consistent.
SnackBar _tapToDismissSnackBar(
  ScaffoldMessengerState messenger,
  Widget content, {
  Color? backgroundColor,
  Duration? duration,
}) {
  return SnackBar(
    padding: EdgeInsets.zero,
    backgroundColor: backgroundColor,
    duration: duration ?? const Duration(seconds: 4),
    content: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => messenger.hideCurrentSnackBar(),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        child: content,
      ),
    ),
  );
}

/// Show a toast that dismisses on tap (in addition to the usual auto-timeout /
/// swipe). Prefer this over `ScaffoldMessenger...showSnackBar` so toasts are
/// consistently tappable-to-dismiss across the app.
void showSnack(
  BuildContext context,
  String message, {
  Duration? duration,
  Color? backgroundColor,
  Color? textColor,
  bool replaceCurrent = false,
}) {
  final messenger = ScaffoldMessenger.of(context);
  // For rapidly-evolving status (retry progress, then the final outcome)
  // the default queueing would hold each message for its full duration and
  // delay the one that matters; replacing keeps the latest state on screen.
  if (replaceCurrent) messenger.removeCurrentSnackBar();
  messenger.showSnackBar(_tapToDismissSnackBar(
    messenger,
    Text(message,
        style: textColor != null ? TextStyle(color: textColor) : null),
    backgroundColor: backgroundColor,
    duration: duration,
  ));
}

/// Like [showSnack] but for callers that captured a [ScaffoldMessengerState]
/// before an `await` (so they can't safely touch a possibly-unmounted
/// `BuildContext`). Same tap-anywhere-to-dismiss behaviour.
void showSnackVia(ScaffoldMessengerState messenger, String message,
    {Color? backgroundColor}) {
  messenger.showSnackBar(_tapToDismissSnackBar(
    messenger,
    Text(message),
    backgroundColor: backgroundColor,
  ));
}

/// Anchor rect for `Share.share`'s `sharePositionOrigin`. iOS uses this to
/// position the share popover (required on iPad; required by recent
/// share_plus versions on iPhone too). Pass a context from inside the
/// button you want the popover to emerge from.
Rect? sharePositionOrigin(BuildContext context) {
  final box = context.findRenderObject() as RenderBox?;
  if (box == null || !box.hasSize) return null;
  return box.localToGlobal(Offset.zero) & box.size;
}

Widget buildActionButton(
    BuildContext context, Widget icon, void Function() onPressed,
    {bool enabled = true}) {
  return IconButton(
      onPressed: enabled ? onPressed : null,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 45, height: 45),
      icon: icon);
}

List<Widget> buildActionButtons(List<Widget> actions) {
  actions =
      actions + <Widget>[const Padding(padding: EdgeInsets.only(right: 5))];
  return actions;
}

/// A small in-button progress spinner, sized to sit inside a button without
/// resizing it, used while an async button action is in flight.
///
/// On a filled/tonal button the default progress colour (`primary`) is the
/// button's own background and so is invisible, so callers should pass the
/// button's foreground (e.g. `onPrimary`, `onSecondaryContainer`) as [color].
/// Pass null on a plain/text button to inherit the theme's indicator colour.
Widget buttonSpinner(BuildContext context, {double size = 16, Color? color}) {
  return SizedBox(
    width: size,
    height: size,
    child: CircularProgressIndicator(strokeWidth: 2, color: color),
  );
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

/// Route path for an entry page. The entry's key (its English phrase) is the
/// `:key` path segment; `?variation=N&video=M` optionally deep-link to a
/// specific sub-entry / video within it. Shared by both apps' routers.
const String WORD_ROUTE = "/word";

/// Non-URL-serialisable args carried to the [WORD_ROUTE] page by an in-app
/// navigation (the entry object is re-resolved from the URL key, but these
/// can't be). Absent on a cold deep link, where the route falls back to
/// sensible defaults (full UI, no focused video, no save-to-list target).
class EntryPageArgs {
  const EntryPageArgs({
    this.showFavouritesButton = true,
    this.focusVideo,
    this.saveToList,
  });

  final bool showFavouritesButton;
  final SavedVideo? focusVideo;
  final EntryList? saveToList;
}

typedef NavigateToEntryPageFn = Future<void> Function(
  BuildContext context,
  Entry entry,
  bool showSaveButtons, {
  /// If supplied, the entry page jumps to the sub-entry containing
  /// [focusVideo] on first build. Used by the list view so tapping
  /// "hello" with three saved videos lands the user on the first one
  /// they saved.
  SavedVideo? focusVideo,

  /// If supplied, the entry page's per-video save button adds the video
  /// directly to this list (toggling membership) instead of opening the
  /// "choose a list" picker. Used by the list-edit "add videos from this
  /// entry" flow, so the user lands on the entry already in the context of
  /// the list they came from.
  EntryList? saveToList,
});

Widget? getInnerRelatedEntriesWidget(
    {required BuildContext context,
    required SubEntry subEntry,
    required bool shouldUseHorizontalDisplay,
    required Entry? Function(String) getRelatedEntry,
    required NavigateToEntryPageFn navigateToEntryPage}) {
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
          color: isRelated ? colorScheme.primary : colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
          decoration: isRelated ? TextDecoration.underline : null),
      recognizer: TapGestureRecognizer()..onTap = navFunction,
    ));
    textSpans.add(TextSpan(
        text: suffix, style: TextStyle(color: colorScheme.onSurfaceVariant)));
    idx += 1;
  }

  // A quiet, de-emphasised "See also" footer line (Related is rarely used).
  var initial = TextSpan(
      text: "${DictLibLocalizations.of(context)!.seeAlso} ",
      style: TextStyle(
          color: colorScheme.onSurfaceVariant, fontWeight: FontWeight.w700));
  textSpans = [initial] + textSpans;
  var richText = RichText(
    text: TextSpan(style: const TextStyle(fontSize: 13.5), children: textSpans),
    textAlign: TextAlign.start,
  );

  if (shouldUseHorizontalDisplay) {
    return Padding(
        padding: const EdgeInsets.only(left: 10.0, right: 20.0, top: 5.0),
        child: richText);
  } else {
    return richText;
  }
}
