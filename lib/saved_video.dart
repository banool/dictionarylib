import 'entry_types.dart';

/// One saved-video item in an [EntryList].
///
/// The unit of saving was historically a whole [Entry]; users wanted to
/// pick specific videos within an entry's sub-entries instead, so the
/// unit is now `(entryKey, videoUrl)`. `entryKey` makes lookups O(1)
/// without scanning every sub-entry; `videoUrl` is unique within an
/// entry, so the pair fully identifies one video.
///
/// Sub-entry index is intentionally NOT part of the identity — a video
/// migrating between sub-entries (rare, but happens when the upstream
/// dictionary data is re-scraped) is the same video, and shouldn't
/// reappear as a fresh save the user has to re-confirm.
class SavedVideo {
  final String entryKey;
  final String videoUrl;

  const SavedVideo({required this.entryKey, required this.videoUrl});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SavedVideo &&
          other.entryKey == entryKey &&
          other.videoUrl == videoUrl;

  @override
  int get hashCode => Object.hash(entryKey, videoUrl);

  @override
  String toString() => 'SavedVideo($entryKey, $videoUrl)';

  /// Storage encoding: `<entryKey>|<videoUrl>`. The pipe is not a URL
  /// character and not used in entry keys (English words/phrases), so
  /// a single-pass split on the first `|` round-trips cleanly.
  String toStorage() => '$entryKey$_sep$videoUrl';

  /// Returns null when [raw] doesn't contain the separator — legacy
  /// items (bare entry keys) are detected this way and expanded by
  /// migration code.
  static SavedVideo? tryParse(String raw) {
    final i = raw.indexOf(_sep);
    if (i < 0) return null;
    return SavedVideo(
      entryKey: raw.substring(0, i),
      videoUrl: raw.substring(i + 1),
    );
  }

  /// JSON shape used by the share API + pending-op args. Two short keys
  /// to keep wire payload small.
  Map<String, String> toJson() => {'entry': entryKey, 'video': videoUrl};

  factory SavedVideo.fromJson(Map<String, dynamic> json) => SavedVideo(
        entryKey: json['entry'] as String,
        videoUrl: json['video'] as String,
      );

  static const String _sep = '|';
}

/// Expand an [Entry] to one [SavedVideo] per video across all
/// sub-entries, preserving sub-entry and within-sub-entry order. Used
/// by migration (legacy entry-key items → per-video items) and by the
/// "save every video of this entry" path from the entry page.
List<SavedVideo> allVideosOf(Entry entry) {
  final out = <SavedVideo>[];
  final entryKey = entry.getKey();
  for (final sub in entry.getSubEntries()) {
    for (final url in sub.getMedia()) {
      out.add(SavedVideo(entryKey: entryKey, videoUrl: url));
    }
  }
  return out;
}
