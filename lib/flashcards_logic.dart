import 'dart:collection';

import 'package:dolphinsr_dart/dolphinsr_dart.dart';
import 'package:flutter/material.dart';

import 'common.dart';
import 'entry_list.dart';
import 'entry_types.dart';
import 'globals.dart';
import 'lists_service.dart';
import 'revision.dart';
import 'saved_video.dart';

const String VIDEO_LINKS_MARKER = "videolinks";
const String KEY_RANDOM_REVIEWS_COUNTER = "mykey_random_reviews_counter";
const String KEY_FIRST_RANDOM_REVIEW = "mykey_first_random_review";

const String KEY_SIGN_TO_WORD = "sign_to_word";
const String KEY_WORD_TO_SIGN = "word_to_sign";
const String KEY_USE_UNKNOWN_REGION_SIGNS = "use_unknown_region_signs";

const String KEY_LISTS_TO_REVIEW = "lists_chosen_to_review";

/// SharedPreferences flag that marks the review-history migration as
/// having been attempted. Set unconditionally after a launch where
/// [migrateLegacyReviewsIfNeeded] runs, even if it migrated nothing —
/// repeat launches don't re-scan.
///
/// History mirrors the saved-video identity (see [SavedVideo]):
///   - v1: master `<entryKey>-<firstVideoFilename>` (no separator we own).
///   - v2: master `<entryKey>\x1F<videoUrl>` (per-video, full URL).
///   - v3: master `<entryKey>\x1F<mediaPath>` (per-video, path identity).
/// [migrateLegacyReviewsIfNeeded] steps any older shape up to v3.
const String KEY_REVIEWS_SCHEMA_VERSION = "reviews_schema_version";
const int reviewsSchemaVersion = 3;

/// Composite key used as a DolphinSR master id and as the master field
/// in stored reviews. Format: `<entryKey>\x1F<mediaPath>`. ASCII unit
/// separator chosen so it can't collide with anything in an entry key or
/// path.
const String _masterKeySep = '\x1F';

String savedVideoMasterId(SavedVideo video) =>
    '${video.entryKey}$_masterKeySep${video.mediaPath}';

/// Parse a master id back into the (entryKey, mediaPath) pair. Returns
/// null for legacy v1 ids (which used the older "entryKey-firstVideo"
/// shape with no separator we control). Used by review-history
/// migration to skip legacy-shaped masters that were already dropped.
SavedVideo? parseSavedVideoMasterId(String id) {
  final i = id.indexOf(_masterKeySep);
  if (i < 0) return null;
  return SavedVideo(
      entryKey: id.substring(0, i), mediaPath: id.substring(i + 1));
}

class DolphinInformation {
  DolphinInformation({
    required this.dolphin,
    required this.masterToVideoMap,
    required this.masters,
    required this.seedReviews,
    required this.sessionReviews,
  });

  DolphinSR dolphin;

  /// Lookup from master id → the [SavedVideo] it represents, plus the
  /// resolved [SubEntry] and parent [Entry]. The flashcard page reads
  /// from this to render the right video.
  Map<String, ResolvedSavedVideo> masterToVideoMap;

  /// The exact masters this [dolphin] was built from. Retained so the
  /// session can rebuild a fresh [DolphinSR] from scratch (the package
  /// throws if you re-add masters to a non-empty instance, so any
  /// rebuild needs the original list to hand to a new instance).
  final List<Master> masters;

  /// The exact seed reviews used to randomise card order when no real
  /// history exists. Retained verbatim — they're built from a shuffle
  /// plus staggered epoch timestamps, so a deterministic rebuild can
  /// only reproduce the same ordering by re-applying these exact
  /// reviews rather than regenerating them. See
  /// [getDolphinInformationFromVideos].
  final List<Review> seedReviews;

  /// The persisted reviews (already filtered to this build's masters /
  /// combinations) that were applied on top of [seedReviews]. Retained
  /// so a rebuild doesn't have to re-filter the caller's raw history.
  final List<Review> sessionReviews;
}

/// Resolved view of a [SavedVideo] — the saved video itself plus the
/// dictionary [Entry] / [SubEntry] / video URL it currently points
/// at. Null sub-entry means the video isn't in the dictionary anymore
/// (data refresh dropped it); the resolver skips such items.
class ResolvedSavedVideo {
  final SavedVideo video;
  final Entry entry;
  final SubEntry subEntry;
  final String videoUrl;
  const ResolvedSavedVideo({
    required this.video,
    required this.entry,
    required this.subEntry,
    required this.videoUrl,
  });
}

LinkedHashMap<String, EntryList> getCandidateEntryLists() {
  LinkedHashMap<String, EntryList> candidateEntryLists = LinkedHashMap();
  for (final el in listsService.myLists) {
    candidateEntryLists[el.key] = el;
  }
  for (final el in sharing.lists.editorLists) {
    candidateEntryLists[el.key] = el;
  }
  for (final el in sharing.lists.subscribedLists) {
    candidateEntryLists[el.key] = el;
  }
  if (!(sharedPreferences.getBool(KEY_HIDE_COMMUNITY_LISTS) ?? false)) {
    candidateEntryLists.addAll(communityEntryListManager.getEntryLists());
  }
  return candidateEntryLists;
}

LinkedHashMap<String, EntryList> getEntryListsToRevise(
    LinkedHashMap<String, EntryList> candidateEntryLists,
    List<String> listsToUse) {
  LinkedHashMap<String, EntryList> entryLists = LinkedHashMap();
  for (String key in listsToUse) {
    var entryList = candidateEntryLists[key];
    if (entryList != null) {
      entryLists[key] = entryList;
    }
  }
  return entryLists;
}

/// Resolve every saved video across the given lists into a unique,
/// dictionary-backed set. Dedupes saved videos shared between lists
/// (e.g. favourites + another list both holding the same one) so
/// they don't produce duplicate cards.
List<ResolvedSavedVideo> resolveSavedVideos(
    LinkedHashMap<String, EntryList> entryLists) {
  final seen = <SavedVideo>{};
  final out = <ResolvedSavedVideo>[];
  for (final list in entryLists.values) {
    for (final v in list.savedVideos) {
      if (!seen.add(v)) continue;
      final entry = keyedByEnglishEntriesGlobal[v.entryKey];
      if (entry == null) continue;
      // Find the sub-entry the saved media path belongs to.
      SubEntry? matched;
      for (final sub in entry.getSubEntries()) {
        if (sub.getMedia().contains(v.mediaPath)) {
          matched = sub;
          break;
        }
      }
      if (matched == null) continue;
      out.add(ResolvedSavedVideo(
        video: v,
        entry: entry,
        subEntry: matched,
        // Resolve the stored path to a playable URL for the card.
        videoUrl: mediaUrlForPath(v.mediaPath),
      ));
    }
  }
  return out;
}

/// Build a DolphinSR Master per resolved saved video.
List<Master> getMastersFromVideos(Locale revisionLocale,
    List<ResolvedSavedVideo> videos, bool entryToSign, bool signToEntry) {
  printAndLog("Making masters from ${videos.length} saved videos");
  final masters = <Master>[];
  final seen = <String>{};
  for (final r in videos) {
    final phrase = r.entry.getPhrase(revisionLocale);
    if (phrase == null) continue;
    final combinations = <Combination>[];
    if (entryToSign) {
      combinations.add(const Combination(front: [0], back: [1]));
    }
    if (signToEntry) {
      combinations.add(const Combination(front: [1], back: [0]));
    }
    final masterKey = savedVideoMasterId(r.video);
    if (!seen.add(masterKey)) continue;
    masters.add(Master(
      id: masterKey,
      fields: [phrase, VIDEO_LINKS_MARKER],
      combinations: combinations,
    ));
  }
  masters.shuffle();
  printAndLog("Built ${masters.length} masters");
  return masters;
}

int getNumCards(DolphinSR dolphin) {
  return dolphin.cardsLength();
}

DolphinInformation getDolphinInformationFromVideos(
    List<ResolvedSavedVideo> videos, List<Master> masters,
    {List<Review>? reviews}) {
  reviews = reviews ?? [];
  final masterToVideoMap = <String, ResolvedSavedVideo>{};
  for (final r in videos) {
    masterToVideoMap[savedVideoMasterId(r.video)] = r;
  }
  final dolphin = DolphinSR();
  dolphin.addMasters(masters);

  // Seed reviews with rating=Again at staggered epoch timestamps so
  // cards come out in a random order from `nextCard` when no real
  // history exists. Same trick as the v1 implementation.
  final mastersEntries = <MapEntry<String, Combination>>[];
  for (final m in masters) {
    for (final c in m.combinations!) {
      mastersEntries.add(MapEntry(m.id!, c));
    }
  }
  mastersEntries.shuffle();
  final seedReviews = <Review>[];
  int epoch = 1000000;
  for (final e in mastersEntries) {
    seedReviews.add(Review(
        master: e.key,
        combination: e.value,
        ts: DateTime.fromMillisecondsSinceEpoch(epoch),
        rating: Rating.Again));
    epoch += 100000000;
  }
  dolphin.addReviews(seedReviews);

  // Filter to reviews for known masters / combinations — DolphinSR
  // crashes on unknown masters. Don't write the filtered set back; the
  // dropped reviews may still be valid for a future session that
  // includes their masters.
  final filteredReviews = filterReviewsToMasters(reviews, masters);
  printAndLog(
      "Added ${filteredReviews.length} total reviews to Dolphin (excluding seed reviews)");
  dolphin.addReviews(filteredReviews);
  return DolphinInformation(
    dolphin: dolphin,
    masterToVideoMap: masterToVideoMap,
    masters: masters,
    seedReviews: seedReviews,
    sessionReviews: filteredReviews,
  );
}

/// Keep only the reviews whose master id is in [masters] and whose
/// combination that master actually defines. DolphinSR throws when a
/// review references an unknown master or combination, so any review
/// list handed to it must be filtered first.
List<Review> filterReviewsToMasters(
    List<Review> reviews, List<Master> masters) {
  final masterLookup = {for (final m in masters) m.id!: m};
  final filtered = <Review>[];
  for (final r in reviews) {
    final m = masterLookup[r.master!];
    if (m == null) continue;
    if (!m.combinations!.contains(r.combination!)) continue;
    filtered.add(r);
  }
  return filtered;
}

/// Rebuild a fresh [DolphinSR] from scratch so its in-session state
/// reflects exactly one review per card. The package mutates card
/// state cumulatively on every `addReviews` call and refuses to re-add
/// masters to a populated instance, so re-rating a card can't be undone
/// in place — the only correct fix is to discard the old instance and
/// replay the canonical review set.
///
/// [di] supplies the original masters and the exact seed reviews used
/// to build it (so card ordering stays deterministic). [sessionAnswers]
/// is the latest review per card from the live session (typically
/// `answers.values`).
///
/// Reviews are sorted by timestamp before being applied: DolphinSR's
/// `applyToCardState` throws if a review predates a card's current
/// `lastReviewed`, and seed reviews use 1970-era epochs while persisted
/// and session reviews use real timestamps, so ascending-ts order is
/// the only safe order. The returned [DolphinInformation] carries the
/// same masters / seed reviews / persisted reviews so it too can be
/// rebuilt.
DolphinInformation rebuildDolphin(
    DolphinInformation di, Iterable<Review> sessionAnswers) {
  final dolphin = DolphinSR();
  dolphin.addMasters(di.masters);
  dolphin.addReviews(di.seedReviews);

  // Apply persisted history plus the session's latest-per-card answers,
  // filtered to this build's masters and sorted ascending by ts. The
  // session answers are already one-per-card (the page keys them by
  // card), so there are no phantom duplicates to reconcile here.
  final replay = <Review>[
    ...di.sessionReviews,
    ...filterReviewsToMasters(sessionAnswers.toList(), di.masters),
  ];
  replay.sort((a, b) => a.ts!.compareTo(b.ts!));
  dolphin.addReviews(replay);

  return DolphinInformation(
    dolphin: dolphin,
    masterToVideoMap: di.masterToVideoMap,
    masters: di.masters,
    seedReviews: di.seedReviews,
    sessionReviews: di.sessionReviews,
  );
}

const String KEY_STORED_REVIEWS = "stored_reviews";
const String REVIEW_DELIMITER = "===";
const String COMBINATION_DELIMETER = "@@@";

String encodeReview(Review review) {
  String combination =
      "${review.combination!.front![0]}$COMBINATION_DELIMETER${review.combination!.back![0]}";
  return "${review.master}$REVIEW_DELIMITER$combination$REVIEW_DELIMITER${review.rating!.index}$REVIEW_DELIMITER${review.ts!.microsecondsSinceEpoch}";
}

Review decodeReview(String s) {
  List<String> split = s.split(REVIEW_DELIMITER);
  List<String> combinationSplit = split[1].split(COMBINATION_DELIMETER);
  int front = int.parse(combinationSplit[0]);
  int back = int.parse(combinationSplit[1]);
  Combination combination = Combination(front: [front], back: [back]);
  Rating rating = Rating.values[int.parse(split[2])];
  DateTime ts = DateTime.fromMicrosecondsSinceEpoch(int.parse(split[3]));
  return Review(
    master: split[0],
    combination: combination,
    rating: rating,
    ts: ts,
  );
}

/// Migrate stored review history forward to the current v3 master-id
/// shape (`<entryKey>\x1F<mediaPath>`); see [reviewsSchemaVersion].
///
/// Steps any older shape:
///   - v1 `<entryKey>-<firstVideoFilename>` → resolved to a path master
///     via [_tryMigrateLegacyMaster] (best-effort; unresolvable reviews
///     are dropped rather than crashing DolphinSR with a bad master).
///   - v2 `<entryKey>\x1F<videoUrl>` → the serving base is stripped off
///     the URL to get the path (see [mediaPathForUrl]); a URL under no
///     known base is kept as-is.
///   - v3 `<entryKey>\x1F<mediaPath>` → passed through.
///
/// Runs once per install, gated by [KEY_REVIEWS_SCHEMA_VERSION]. Safe to
/// call on every launch; a no-op after the first successful run.
Future<void> migrateLegacyReviewsIfNeeded() async {
  final stored = sharedPreferences.getInt(KEY_REVIEWS_SCHEMA_VERSION) ?? 1;
  if (stored >= reviewsSchemaVersion) return;
  final encoded =
      sharedPreferences.getStringList(KEY_STORED_REVIEWS) ?? const <String>[];
  if (encoded.isEmpty) {
    await sharedPreferences.setInt(
        KEY_REVIEWS_SCHEMA_VERSION, reviewsSchemaVersion);
    return;
  }
  final out = <String>[];
  var converted = 0;
  var unchanged = 0;
  var dropped = 0;
  for (final raw in encoded) {
    // The master field is the first delimited segment, so split on the
    // first REVIEW_DELIMITER only.
    final firstDelim = raw.indexOf(REVIEW_DELIMITER);
    if (firstDelim < 0) {
      dropped++;
      continue;
    }
    final master = raw.substring(0, firstDelim);
    final tail = raw.substring(firstDelim);
    final sepIdx = master.indexOf(_masterKeySep);
    if (sepIdx >= 0) {
      // v2 (URL) or already v3 (path). Strip the serving base off a URL
      // to get the path; keep a path / unknown-base URL as-is.
      final entryKey = master.substring(0, sepIdx);
      final value = master.substring(sepIdx + 1);
      if (value.startsWith('http://') || value.startsWith('https://')) {
        final path = mediaPathForUrl(value);
        out.add('$entryKey$_masterKeySep${path ?? value}$tail');
        path != null ? converted++ : unchanged++;
      } else {
        out.add(raw); // already a path.
        unchanged++;
      }
      continue;
    }
    // Legacy v1 shape: `<entryKey>-<firstVideoFilenameOrUrl>`. We don't
    // know exactly where the entry key ends, so try the leftmost `-` and
    // walk rightward until we find an entry that exists.
    final newMaster = _tryMigrateLegacyMaster(master);
    if (newMaster == null) {
      dropped++;
      continue;
    }
    out.add('$newMaster$tail');
    converted++;
  }
  await sharedPreferences.setStringList(KEY_STORED_REVIEWS, out);
  await sharedPreferences.setInt(
      KEY_REVIEWS_SCHEMA_VERSION, reviewsSchemaVersion);
  printAndLog(
      'Reviews migration → v$reviewsSchemaVersion: $converted converted, '
      '$unchanged unchanged, $dropped dropped (of ${encoded.length} total)');
}

/// Try to rewrite a v1 master id `<entryKey>-<videoSuffix>` to the v2
/// shape. Returns the v2 master id on success, null when nothing
/// resolves.
///
/// Walks `-` positions **rightmost first** so that a hyphenated entry
/// key like `"welsh-corgi"` wins over the shorter `"welsh"` when both
/// exist in the dictionary — without this, a v1 review for
/// `"welsh-corgi"` would silently rewrite to `"welsh"` and the review
/// would attach to the wrong entry forever.
String? _tryMigrateLegacyMaster(String legacyMaster) {
  var idx = legacyMaster.lastIndexOf('-');
  while (idx >= 0) {
    final candidate = legacyMaster.substring(0, idx);
    final tail = legacyMaster.substring(idx + 1);
    final entry = keyedByEnglishEntriesGlobal[candidate];
    if (entry != null) {
      for (final sub in entry.getSubEntries()) {
        for (final path in sub.getMedia()) {
          if (path.endsWith(tail) || path.contains(tail)) {
            return savedVideoMasterId(
                SavedVideo(entryKey: candidate, mediaPath: path));
          }
        }
      }
      // Tail didn't match any media path — fall back to the entry's
      // first sub-entry's first video so a stored review keeps some
      // signal instead of being dropped wholesale. Best-effort.
      for (final sub in entry.getSubEntries()) {
        final media = sub.getMedia();
        if (media.isNotEmpty) {
          return savedVideoMasterId(
              SavedVideo(entryKey: candidate, mediaPath: media.first));
        }
      }
    }
    idx = legacyMaster.lastIndexOf('-', idx - 1);
  }
  return null;
}

List<Review> readReviews() {
  List<String> encoded =
      sharedPreferences.getStringList(KEY_STORED_REVIEWS) ?? [];
  // Decode defensively: a single malformed stored review (e.g. from an older
  // encoding) must not throw and blank out the whole revision-progress page.
  // Skip anything we can't parse rather than aborting the lot.
  final out = <Review>[];
  for (final e in encoded) {
    try {
      out.add(decodeReview(e));
    } catch (err) {
      printAndLog("Skipping undecodable stored review '$e': $err");
    }
  }
  return out;
}

Future<void> writeReviews(List<Review> existing, List<Review> additional,
    {bool force = false}) async {
  if (!force && additional.isEmpty) {
    printAndLog("No reviews to write and force = $force");
    return;
  }
  List<Review> toWrite = existing + additional;
  List<String> encoded = toWrite
      .map(
        (e) => encodeReview(e),
      )
      .toList();
  await sharedPreferences.setStringList(KEY_STORED_REVIEWS, encoded);
  printAndLog(
      "Wrote ${additional.length} new reviews (making ${toWrite.length} in total) to storage");
}

int getNumDueCards(DolphinSR dolphin, RevisionStrategy revisionStrategy) {
  switch (revisionStrategy) {
    case RevisionStrategy.Random:
      return getNumCards(dolphin);
    case RevisionStrategy.SpacedRepetition:
      SummaryStatics summary = dolphin.summary();
      int due =
          (summary.due ?? 0) + (summary.overdue ?? 0) + (summary.learning ?? 0);
      return due;
  }
}

Future<void> bumpRandomReviewCounter(int bumpAmount) async {
  int current = sharedPreferences.getInt(KEY_RANDOM_REVIEWS_COUNTER) ?? 0;
  int updated = current + bumpAmount;
  await sharedPreferences.setInt(KEY_RANDOM_REVIEWS_COUNTER, updated);
  printAndLog(
      "Incremented random review counter by $bumpAmount ($current to $updated)");
  int? firstUnixtime = sharedPreferences.getInt(KEY_FIRST_RANDOM_REVIEW);
  if (firstUnixtime == null) {
    await sharedPreferences.setInt(
        KEY_FIRST_RANDOM_REVIEW, DateTime.now().millisecondsSinceEpoch ~/ 1000);
  }
}
