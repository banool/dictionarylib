import 'package:flutter/material.dart';
import 'package:json_annotation/json_annotation.dart';

import 'l10n/app_localizations.dart';

part 'entry_types.g.dart';

enum EntryType {
  WORD,
  PHRASE,
  FINGERSPELLING,
}

String getEntryTypePretty(BuildContext context, EntryType entryType) {
  switch (entryType) {
    case EntryType.WORD:
      return AppLocalizations.of(context)!.entryTypeWords;
    case EntryType.PHRASE:
      return AppLocalizations.of(context)!.entryTypePhrases;
    case EntryType.FINGERSPELLING:
      return AppLocalizations.of(context)!.entryTypeFingerspelling;
  }
}

abstract class Entry implements Comparable<Entry> {
  // Used for comparing entries.
  String getKey();

  // This could be a word or phrase. This can return null if there is nothing
  // available for the given locale.
  String? getPhrase(Locale locale);

  // Get the type of this entry.
  EntryType getEntryType();

  List<SubEntry> getSubEntries();
}

// Takes a generic R for region.
abstract class SubEntry<R> {
  // Used for comparing sub-entries.
  String getKey(Entry parentEntry);

  // Return the URLs of the media.
  List<String> getMedia();

  List<String> getRelatedWords();

  // Gets definitions.
  // todo define return type
  List<Definition> getDefinitions(Locale locale);

  // Return what regions this entry is appropriate for.
  List<R> getRegions();
}

@JsonSerializable()
class Definition {
  final String language;
  final String category;
  final String definition;

  String get categoryPretty {
    return getCategoryPretty(category);
  }

  Definition(
      {required this.language,
      required this.category,
      required this.definition});
  factory Definition.fromJson(Map<String, dynamic> json) =>
      _$DefinitionFromJson(json);

  Map<String, dynamic> toJson() => _$DefinitionToJson(this);
}

String getCategoryPretty(String s) {
  switch (s) {
    case "AS_A_NOUN":
      return "As a noun";
    case "AS_A_VERB_OR_ADJECTIVE":
      return "As a verb or adjective";
    case "AS_MODIFIER":
      return "As modifier";
    case "AS_QUESTION":
      return "As question";
    case "INTERACTIVE":
      return "Interactive";
    case "GENERAL_DEFINITION":
      return "General definition";
    case "NOTE":
      return "Note";
    case "AUGMENTED_MEANING":
      return "Augmented meaning";
    case "AS_A_POINTING_SIGN":
      return "As a pointing sign";
    default:
      return s;
  }
}
