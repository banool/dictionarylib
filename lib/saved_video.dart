import 'entry_types.dart';

/// One saved-video item in an [EntryList].
///
/// The unit of saving was historically a whole [Entry]; users wanted to
/// pick specific videos within an entry's sub-entries instead, so the
/// unit became `(entryKey, mediaPath)`. `entryKey` makes lookups O(1)
/// without scanning every sub-entry.
///
/// The video half is the media's **path** ([SubEntry.getMedia] returns
/// paths, e.g. `/mp4video/11/11450.mp4`), NOT a fully-qualified URL.
/// Keying off the path means a saved video survives the content moving
/// between hosts / CDNs: the identity is stable, and the playable URL is
/// rebuilt on demand via [mediaUrlForPath]. A path is unique within an
/// entry, so `(entryKey, mediaPath)` fully identifies one saved video.
///
/// Sub-entry index is intentionally NOT part of the identity — a video
/// migrating between sub-entries (rare, but happens when the upstream
/// dictionary data is re-scraped) is the same video, and shouldn't
/// reappear as a fresh save the user has to re-confirm.
class SavedVideo {
  final String entryKey;

  /// The media's path (its stable identity). Named for what it holds
  /// rather than `videoUrl` — it is deliberately not a full URL. Resolve
  /// it to a playable URL with [mediaUrlForPath].
  final String mediaPath;

  const SavedVideo({required this.entryKey, required this.mediaPath});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SavedVideo &&
          other.entryKey == entryKey &&
          other.mediaPath == mediaPath;

  @override
  int get hashCode => Object.hash(entryKey, mediaPath);

  @override
  String toString() => 'SavedVideo($entryKey, $mediaPath)';

  /// Separator between the entry key and the media path in the
  /// SharedPreferences storage encoding. Public so the list-migration
  /// code can detect already-per-video items.
  static const String storageSeparator = '|';

  /// Storage encoding: `<entryKey>|<mediaPath>`. The pipe is not used in
  /// entry keys (English words/phrases); a path could in theory contain
  /// one, so a single-pass split on the *first* `|` is used to round-trip
  /// cleanly (the path keeps any later pipes).
  String toStorage() => '$entryKey$storageSeparator$mediaPath';

  /// Returns null when [raw] doesn't contain the separator — legacy v1
  /// items (bare entry keys) are detected this way and expanded by the
  /// migration code in `entry_list.dart`.
  static SavedVideo? tryParse(String raw) {
    final i = raw.indexOf(storageSeparator);
    if (i < 0) return null;
    return SavedVideo(
      entryKey: raw.substring(0, i),
      mediaPath: raw.substring(i + 1),
    );
  }

  /// JSON shape used by the share API + pending-op args. Two short keys
  /// to keep the wire payload small. The `video` field carries the media
  /// path — the wire shape is unchanged (the field has always been an
  /// opaque string to the server).
  Map<String, String> toJson() => {'entry': entryKey, 'video': mediaPath};

  factory SavedVideo.fromJson(Map<String, dynamic> json) => SavedVideo(
        entryKey: json['entry'] as String,
        mediaPath: json['video'] as String,
      );
}

/// Expand an [Entry] to one [SavedVideo] per media item across all
/// sub-entries, preserving sub-entry and within-sub-entry order. Keyed
/// by media **path** (the stable identity, what [SubEntry.getMedia]
/// returns). Used by the "save every video of this entry" path from the
/// entry page and by list migration.
List<SavedVideo> allVideosOf(Entry entry) {
  final out = <SavedVideo>[];
  final entryKey = entry.getKey();
  for (final sub in entry.getSubEntries()) {
    for (final path in sub.getMedia()) {
      out.add(SavedVideo(entryKey: entryKey, mediaPath: path));
    }
  }
  return out;
}
