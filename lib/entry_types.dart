import 'package:flutter/material.dart';

import 'l10n/app_localizations.dart';

enum EntryType {
  WORD,
  PHRASE,
  FINGERSPELLING,
}

String getEntryTypePretty(BuildContext context, EntryType entryType) {
  switch (entryType) {
    case EntryType.WORD:
      return DictLibLocalizations.of(context)!.entryTypeWords;
    case EntryType.PHRASE:
      return DictLibLocalizations.of(context)!.entryTypePhrases;
    case EntryType.FINGERSPELLING:
      return DictLibLocalizations.of(context)!.entryTypeFingerspelling;
  }
}

abstract class Entry implements Comparable<Entry> {
  // Used for comparing entries.
  String getKey();

  // This could be a word or phrase. This can return null if there is nothing
  // available for the given locale.
  String? getPhrase(Locale locale);

  // Get categories that this entry corresponds to, e.g. ["Animals", "Birds"].
  List<String> getCategories();

  // Get the type of this entry.
  EntryType getEntryType();

  List<SubEntry> getSubEntries();
}

// Takes a generic R for region and D for definition.
abstract class SubEntry<R, D> {
  // Used for comparing sub-entries.
  String getKey(Entry parentEntry);

  // Return the media **paths** (video / image) in display order — each
  // the path after the serving base, e.g. `/mp4video/11/11450.mp4`. This
  // is the stable identity a saved video is keyed by (so it survives the
  // content moving between hosts / CDNs); resolve a path to a playable
  // URL with [mediaUrlForPath] (globals.dart). The app ships the base(s)
  // in [mediaBaseUrls] rather than baking a host into the data.
  List<String> getMedia();

  List<String> getRelatedWords();

  // Gets definitions.
  // todo define return type
  List<D> getDefinitions(Locale locale);

  // Return what regions this entry is appropriate for.
  List<R> getRegions();
}

const LANGUAGE_CODE_ENGLISH = "en";
const LANGUAGE_CODE_SINHALA = "si";
const LANGUAGE_CODE_TAMIL = "ta";

const LANGUAGE_ENGLISH = "English";
const LANGUAGE_SINHALA = "සිංහල";
const LANGUAGE_TAMIL = "தமிழ்";

const Map<String, String> LANGUAGE_CODE_TO_PRETTY = {
  LANGUAGE_CODE_ENGLISH: LANGUAGE_ENGLISH,
  LANGUAGE_CODE_SINHALA: LANGUAGE_SINHALA,
  LANGUAGE_CODE_TAMIL: LANGUAGE_TAMIL,
};

Map<String, Locale> LANGUAGE_CODE_TO_LOCALE = Map.fromEntries(
    LANGUAGE_CODE_TO_PRETTY.keys.map((e) => MapEntry(e, Locale(e))));

Locale LOCALE_ENGLISH = LANGUAGE_CODE_TO_LOCALE[LANGUAGE_CODE_ENGLISH]!;
Locale LOCALE_SINHALA = LANGUAGE_CODE_TO_LOCALE[LANGUAGE_CODE_SINHALA]!;
Locale LOCALE_TAMIL = LANGUAGE_CODE_TO_LOCALE[LANGUAGE_CODE_TAMIL]!;
