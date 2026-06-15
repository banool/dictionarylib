import 'package:dictionarylib/flashcards_logic.dart';
import 'package:dictionarylib/globals.dart';
import 'package:dictionarylib/saved_video.dart';
import 'package:dolphinsr_dart/dolphinsr_dart.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '_helpers.dart';

/// The unit separator that [savedVideoMasterId] uses between entry key
/// and video URL. Pinning the literal here so test assertions stay
/// readable even when the encoded form contains it.
const _sep = '\x1F';

/// Encode a fake review with the supplied [master] id. Mirrors
/// [encodeReview]'s format inline rather than going through it so a
/// test that asserts on the encoded shape doesn't double-rely on the
/// production encoder.
String encodeFakeReview(
  String master, {
  int front = 0,
  int back = 1,
  Rating rating = Rating.Good,
  int tsMicros = 1700000000000000,
}) {
  return '$master===$front@@@$back===${rating.index}===$tsMicros';
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    sharedPreferences = await SharedPreferences.getInstance();
    keyedByEnglishEntriesGlobal.clear();
    // Deterministic default: no serving base configured, so a v2 master's
    // URL is kept verbatim (nothing to strip). The conversion group below
    // sets a base explicitly to exercise the v2→v3 path rewrite.
    mediaBaseUrls = const [];
  });

  group('migrateLegacyReviewsIfNeeded — short-circuits', () {
    test('no stored reviews + no flag → sets flag, writes nothing', () async {
      await migrateLegacyReviewsIfNeeded();
      expect(sharedPreferences.getInt(KEY_REVIEWS_SCHEMA_VERSION),
          reviewsSchemaVersion);
      // The function returns early after stamping the flag — it doesn't
      // touch the stored-reviews key at all when there's nothing there.
      expect(sharedPreferences.getStringList(KEY_STORED_REVIEWS), isNull);
    });

    test('empty stored reviews list + no flag → sets flag', () async {
      await sharedPreferences.setStringList(KEY_STORED_REVIEWS, const []);
      await migrateLegacyReviewsIfNeeded();
      expect(sharedPreferences.getInt(KEY_REVIEWS_SCHEMA_VERSION),
          reviewsSchemaVersion);
      expect(sharedPreferences.getStringList(KEY_STORED_REVIEWS), isEmpty);
    });

    test('already-v2 flag → no-op (reviews list untouched)', () async {
      // Stamp the flag and pre-populate with a deliberately broken
      // legacy entry to prove the function doesn't touch it.
      await sharedPreferences.setInt(
          KEY_REVIEWS_SCHEMA_VERSION, reviewsSchemaVersion);
      final legacy = [encodeFakeReview('apple-foo.mp4')];
      await sharedPreferences.setStringList(KEY_STORED_REVIEWS, legacy);

      await migrateLegacyReviewsIfNeeded();

      expect(sharedPreferences.getStringList(KEY_STORED_REVIEWS), legacy,
          reason: 'with the flag already set, migration must not run');
    });
  });

  group('migrateLegacyReviewsIfNeeded — v1 master rewrite', () {
    test(
        'legacy master with tail that endsWith a known video URL '
        'is rewritten to the v2 shape', () async {
      // Entry "apple" has one video. The legacy master uses just the
      // filename ("apple.mp4") as the tail; the migration matches it
      // against the full URL via endsWith.
      keyedByEnglishEntriesGlobal['apple'] =
          FakeEntry('apple', videos: const ['https://media.test/apple.mp4']);
      await sharedPreferences.setStringList(KEY_STORED_REVIEWS, [
        encodeFakeReview('apple-apple.mp4'),
      ]);

      await migrateLegacyReviewsIfNeeded();

      final stored = sharedPreferences.getStringList(KEY_STORED_REVIEWS) ?? [];
      expect(stored, hasLength(1));
      expect(stored.single,
          startsWith('apple${_sep}https://media.test/apple.mp4==='));
    });

    test(
        'legacy master with tail that "contains" a video URL '
        'segment is rewritten', () async {
      // Tail is a directory fragment of the URL. The migration's
      // contains-check catches this case.
      keyedByEnglishEntriesGlobal['friend'] = FakeEntry('friend',
          videos: const ['https://media.test/auslan/46/46930.mp4']);
      await sharedPreferences.setStringList(KEY_STORED_REVIEWS, [
        encodeFakeReview('friend-auslan/46/46930.mp4'),
      ]);

      await migrateLegacyReviewsIfNeeded();

      final stored = sharedPreferences.getStringList(KEY_STORED_REVIEWS) ?? [];
      expect(stored.single,
          startsWith('friend${_sep}https://media.test/auslan/46/46930.mp4==='));
    });

    test(
        'legacy master whose tail matches no video falls back to the '
        'entry\'s first sub-entry\'s first video', () async {
      // The exact tail "completely-different.mp4" is nowhere in the
      // entry's media, but the entry exists. Migration takes the
      // "first video" fallback rather than dropping the review.
      keyedByEnglishEntriesGlobal['apple'] =
          FakeEntry('apple', videos: const ['https://media.test/apple-v1.mp4']);
      await sharedPreferences.setStringList(KEY_STORED_REVIEWS, [
        encodeFakeReview('apple-completely-different.mp4'),
      ]);

      await migrateLegacyReviewsIfNeeded();

      final stored = sharedPreferences.getStringList(KEY_STORED_REVIEWS) ?? [];
      expect(stored.single,
          startsWith('apple${_sep}https://media.test/apple-v1.mp4==='));
    });

    test(
        'fallback picks the first sub-entry\'s first video when the '
        'entry has multiple sub-entries', () async {
      // Sanity check: the fallback walks sub-entries in order and
      // takes the first non-empty one's first video.
      keyedByEnglishEntriesGlobal['multi'] =
          FakeEntry('multi', subEntries: const [
        FakeSubEntryFixture(videos: ['s1.mp4', 's1b.mp4']),
        FakeSubEntryFixture(videos: ['s2.mp4']),
      ]);
      await sharedPreferences.setStringList(KEY_STORED_REVIEWS, [
        encodeFakeReview('multi-no-such-tail.mp4'),
      ]);

      await migrateLegacyReviewsIfNeeded();

      final stored = sharedPreferences.getStringList(KEY_STORED_REVIEWS) ?? [];
      expect(stored.single, startsWith('multi${_sep}s1.mp4==='));
    });

    test('legacy master whose entry no longer exists is dropped', () async {
      // No dictionary entry for "vanished" — migration can't recover
      // the review, drops it.
      await sharedPreferences.setStringList(KEY_STORED_REVIEWS, [
        encodeFakeReview('vanished-foo.mp4'),
      ]);

      await migrateLegacyReviewsIfNeeded();

      expect(sharedPreferences.getStringList(KEY_STORED_REVIEWS), isEmpty);
      // Flag still stamped — we made a one-shot attempt and don't
      // want to retry on every launch.
      expect(sharedPreferences.getInt(KEY_REVIEWS_SCHEMA_VERSION),
          reviewsSchemaVersion);
    });

    test('legacy master whose entry has zero videos is dropped', () async {
      // Entry exists but the dictionary refresh left it with no media.
      // The fallback loop finds nothing → master returns null → drop.
      keyedByEnglishEntriesGlobal['hollow'] = FakeEntry('hollow');
      await sharedPreferences.setStringList(KEY_STORED_REVIEWS, [
        encodeFakeReview('hollow-foo.mp4'),
      ]);

      await migrateLegacyReviewsIfNeeded();

      expect(sharedPreferences.getStringList(KEY_STORED_REVIEWS), isEmpty);
    });

    test('hyphenated entry key resolves via the right split point', () async {
      // For "welsh-corgi-vid.mp4" with entry "welsh-corgi" + no entry
      // "welsh", rightmost-first walk finds "welsh-corgi" first.
      keyedByEnglishEntriesGlobal['welsh-corgi'] = FakeEntry('welsh-corgi',
          videos: const ['https://media.test/vid.mp4']);
      await sharedPreferences.setStringList(KEY_STORED_REVIEWS, [
        encodeFakeReview('welsh-corgi-vid.mp4'),
      ]);

      await migrateLegacyReviewsIfNeeded();

      final stored = sharedPreferences.getStringList(KEY_STORED_REVIEWS) ?? [];
      expect(stored.single,
          startsWith('welsh-corgi${_sep}https://media.test/vid.mp4==='));
    });

    test(
        'longest matching entry key wins when a shorter prefix is also '
        'an entry', () async {
      // Regression: when both "welsh" and "welsh-corgi" exist, a v1
      // master "welsh-corgi-vid.mp4" must resolve to "welsh-corgi"
      // (the entry the review was actually for), NOT to "welsh"
      // (which a leftmost-first walk would silently pick). Otherwise
      // long-lived spaced-repetition history gets reattached to the
      // wrong entry forever.
      keyedByEnglishEntriesGlobal['welsh'] =
          FakeEntry('welsh', videos: const ['https://media.test/welsh.mp4']);
      keyedByEnglishEntriesGlobal['welsh-corgi'] = FakeEntry('welsh-corgi',
          videos: const ['https://media.test/corgi.mp4']);
      await sharedPreferences.setStringList(KEY_STORED_REVIEWS, [
        encodeFakeReview('welsh-corgi-corgi.mp4'),
      ]);

      await migrateLegacyReviewsIfNeeded();

      final stored = sharedPreferences.getStringList(KEY_STORED_REVIEWS) ?? [];
      expect(stored.single,
          startsWith('welsh-corgi${_sep}https://media.test/corgi.mp4==='));
    });
  });

  group('migrateLegacyReviewsIfNeeded — v2 inputs + mixed inputs', () {
    test('a v2 master whose URL is under no known base is kept verbatim',
        () async {
      // A v2 master is detected by the unit separator. Its URL is rewritten
      // to a path only when it's under a configured base; here no base is
      // set (see setUp), so it's kept verbatim.
      keyedByEnglishEntriesGlobal['apple'] =
          FakeEntry('apple', videos: const ['https://media.test/a.mp4']);
      final v2Encoded =
          encodeFakeReview('apple${_sep}https://media.test/a.mp4');
      await sharedPreferences.setStringList(KEY_STORED_REVIEWS, [v2Encoded]);

      await migrateLegacyReviewsIfNeeded();

      expect(sharedPreferences.getStringList(KEY_STORED_REVIEWS), [v2Encoded]);
    });

    test(
        'mixed input: v1 + v2 in same list — v1 migrated, v2 untouched, '
        'order preserved', () async {
      keyedByEnglishEntriesGlobal['apple'] =
          FakeEntry('apple', videos: const ['https://media.test/a.mp4']);
      keyedByEnglishEntriesGlobal['banana'] =
          FakeEntry('banana', videos: const ['https://media.test/b.mp4']);

      final v1 = encodeFakeReview('apple-a.mp4');
      final v2 = encodeFakeReview('banana${_sep}https://media.test/b.mp4');
      final v1Other = encodeFakeReview('banana-b.mp4');

      await sharedPreferences.setStringList(KEY_STORED_REVIEWS, [
        v1,
        v2,
        v1Other,
      ]);

      await migrateLegacyReviewsIfNeeded();

      final stored = sharedPreferences.getStringList(KEY_STORED_REVIEWS) ?? [];
      expect(stored, hasLength(3));
      expect(stored[0], startsWith('apple${_sep}https://media.test/a.mp4==='));
      expect(stored[1], v2);
      expect(stored[2], startsWith('banana${_sep}https://media.test/b.mp4==='));
    });

    test(
        'mixed input with one unresolvable v1 — bad one dropped, '
        'others retained in original order', () async {
      keyedByEnglishEntriesGlobal['apple'] =
          FakeEntry('apple', videos: const ['https://media.test/a.mp4']);
      keyedByEnglishEntriesGlobal['cherry'] =
          FakeEntry('cherry', videos: const ['https://media.test/c.mp4']);

      await sharedPreferences.setStringList(KEY_STORED_REVIEWS, [
        encodeFakeReview('apple-a.mp4'),
        encodeFakeReview('gone-anything.mp4'),
        encodeFakeReview('cherry-c.mp4'),
      ]);

      await migrateLegacyReviewsIfNeeded();

      final stored = sharedPreferences.getStringList(KEY_STORED_REVIEWS) ?? [];
      expect(stored, hasLength(2));
      expect(stored[0], startsWith('apple${_sep}'));
      expect(stored[1], startsWith('cherry${_sep}'));
    });

    test('malformed encoded review (no delimiter) is dropped silently',
        () async {
      // Production code shouldn't ever write something like this, but
      // a SharedPreferences corruption shouldn't crash the migration.
      keyedByEnglishEntriesGlobal['apple'] =
          FakeEntry('apple', videos: const ['https://media.test/a.mp4']);
      await sharedPreferences.setStringList(KEY_STORED_REVIEWS, [
        'this is not an encoded review',
        encodeFakeReview('apple-a.mp4'),
      ]);

      await migrateLegacyReviewsIfNeeded();

      final stored = sharedPreferences.getStringList(KEY_STORED_REVIEWS) ?? [];
      expect(stored, hasLength(1));
      expect(stored.single, startsWith('apple${_sep}'));
    });
  });

  group('migrateLegacyReviewsIfNeeded — semantic preservation', () {
    test(
        'a v1 review\'s ts / rating / combination round-trip through '
        'decodeReview after migration', () async {
      // Migration only rewrites the master; the rest of the encoded
      // string is appended verbatim. Verify decodeReview can still
      // parse the post-migration output.
      keyedByEnglishEntriesGlobal['apple'] =
          FakeEntry('apple', videos: const ['https://media.test/a.mp4']);
      final encoded = encodeFakeReview('apple-a.mp4',
          front: 1, back: 0, rating: Rating.Hard, tsMicros: 1234567890);
      await sharedPreferences.setStringList(KEY_STORED_REVIEWS, [encoded]);

      await migrateLegacyReviewsIfNeeded();

      final stored = sharedPreferences.getStringList(KEY_STORED_REVIEWS) ?? [];
      final decoded = decodeReview(stored.single);
      expect(decoded.master, 'apple${_sep}https://media.test/a.mp4');
      expect(decoded.combination!.front, [1]);
      expect(decoded.combination!.back, [0]);
      expect(decoded.rating, Rating.Hard);
      expect(decoded.ts!.microsecondsSinceEpoch, 1234567890);
    });

    test('decoded v2 master matches what savedVideoMasterId would produce',
        () async {
      // Pins the contract between the migration output and the master
      // ids that the runtime code generates for fresh saved videos —
      // they must be string-equal so future flashcard sessions can
      // line up old reviews with new masters.
      keyedByEnglishEntriesGlobal['apple'] =
          FakeEntry('apple', videos: const ['https://media.test/a.mp4']);
      await sharedPreferences.setStringList(KEY_STORED_REVIEWS, [
        encodeFakeReview('apple-a.mp4'),
      ]);

      await migrateLegacyReviewsIfNeeded();

      final stored = sharedPreferences.getStringList(KEY_STORED_REVIEWS) ?? [];
      final decoded = decodeReview(stored.single);
      final expected = savedVideoMasterId(
          SavedVideo(entryKey: 'apple', mediaPath: 'https://media.test/a.mp4'));
      expect(decoded.master, expected);
    });
  });

  group('migrateLegacyReviewsIfNeeded — idempotence', () {
    test('a second call is a no-op (flag check short-circuits)', () async {
      keyedByEnglishEntriesGlobal['apple'] =
          FakeEntry('apple', videos: const ['https://media.test/a.mp4']);
      await sharedPreferences.setStringList(KEY_STORED_REVIEWS, [
        encodeFakeReview('apple-a.mp4'),
      ]);

      await migrateLegacyReviewsIfNeeded();
      final afterFirst = sharedPreferences.getStringList(KEY_STORED_REVIEWS);

      // Tamper with state in a way the second call would notice if it
      // ran: stuff a legacy-looking review at the end. The flag
      // short-circuit must skip the second pass.
      final tampered = [...?afterFirst, encodeFakeReview('apple-a.mp4')];
      await sharedPreferences.setStringList(KEY_STORED_REVIEWS, tampered);

      await migrateLegacyReviewsIfNeeded();

      // The tampered entry is still there in its v1 shape — proof
      // the second call didn't run.
      expect(sharedPreferences.getStringList(KEY_STORED_REVIEWS), tampered);
    });

    test(
        'parsing post-migration output back through the migration '
        '(after wiping the flag) is stable', () async {
      // Even if some future bug wipes the schema-version flag, the
      // already-v2 entries in storage should pass through untouched
      // because the loop's v2 detection runs before the legacy expand.
      keyedByEnglishEntriesGlobal['apple'] =
          FakeEntry('apple', videos: const ['https://media.test/a.mp4']);
      await sharedPreferences.setStringList(KEY_STORED_REVIEWS, [
        encodeFakeReview('apple-a.mp4'),
      ]);

      await migrateLegacyReviewsIfNeeded();
      final afterFirst = sharedPreferences.getStringList(KEY_STORED_REVIEWS);

      // Wipe the flag and re-run.
      await sharedPreferences.remove(KEY_REVIEWS_SCHEMA_VERSION);
      await migrateLegacyReviewsIfNeeded();

      expect(sharedPreferences.getStringList(KEY_STORED_REVIEWS), afterFirst);
      expect(sharedPreferences.getInt(KEY_REVIEWS_SCHEMA_VERSION),
          reviewsSchemaVersion);
    });
  });

  group('migrateLegacyReviewsIfNeeded — v2→v3 path conversion', () {
    const base = 'https://media.test';

    test('a v2 master URL under the configured base is rewritten to a path',
        () async {
      mediaBaseUrls = const [base];
      final v2 = encodeFakeReview('apple$_sep$base/auslan/11/11450.mp4');
      await sharedPreferences.setStringList(KEY_STORED_REVIEWS, [v2]);

      await migrateLegacyReviewsIfNeeded();

      final stored = sharedPreferences.getStringList(KEY_STORED_REVIEWS) ?? [];
      // Base stripped → the master now carries the media path.
      expect(stored.single, startsWith('apple$_sep/auslan/11/11450.mp4==='));
      expect(sharedPreferences.getInt(KEY_REVIEWS_SCHEMA_VERSION),
          reviewsSchemaVersion);
    });

    test('a v2 master URL under no configured base is kept as-is', () async {
      mediaBaseUrls = const [base];
      final v2 = encodeFakeReview('apple${_sep}https://elsewhere.test/x.mp4');
      await sharedPreferences.setStringList(KEY_STORED_REVIEWS, [v2]);

      await migrateLegacyReviewsIfNeeded();

      final stored = sharedPreferences.getStringList(KEY_STORED_REVIEWS) ?? [];
      expect(stored.single, v2);
    });

    test('a v3 master (already a path) passes through unchanged', () async {
      mediaBaseUrls = const [base];
      final v3 = encodeFakeReview('apple$_sep/auslan/11/11450.mp4');
      await sharedPreferences.setStringList(KEY_STORED_REVIEWS, [v3]);

      await migrateLegacyReviewsIfNeeded();

      final stored = sharedPreferences.getStringList(KEY_STORED_REVIEWS) ?? [];
      expect(stored.single, v3);
    });
  });

  // SLSL stores review masters as "<video><entryKey>" (MySubEntry.getKey =
  // sorted(videos)[0] + entryKey) — the inverse of Auslan's
  // "<entryKey>-<video>". These guarantee an upgrading SLSL user's flashcard
  // history survives. The stored video half is a bare filename ("11450.mp4");
  // the current dictionary exposes it as the path "/media/11450.mp4", so
  // resolution is by filename.
  group('migrateLegacyReviewsIfNeeded — SLSL suffix-shaped masters', () {
    test('"<filename><entryKey>" resolves to the media path by filename',
        () async {
      keyedByEnglishEntriesGlobal['Sri Lanka'] =
          FakeEntry('Sri Lanka', videos: const ['/media/11450.mp4']);
      await sharedPreferences.setStringList(KEY_STORED_REVIEWS, [
        encodeFakeReview('11450.mp4Sri Lanka'),
      ]);

      await migrateLegacyReviewsIfNeeded();

      final stored = sharedPreferences.getStringList(KEY_STORED_REVIEWS) ?? [];
      expect(stored.single, startsWith('Sri Lanka$_sep/media/11450.mp4==='));
    });

    test('a multi-word entry key with a space resolves via the suffix match',
        () async {
      keyedByEnglishEntriesGlobal['good morning'] =
          FakeEntry('good morning', videos: const ['/media/77.mp4']);
      await sharedPreferences.setStringList(KEY_STORED_REVIEWS, [
        encodeFakeReview('77.mp4good morning'),
      ]);

      await migrateLegacyReviewsIfNeeded();

      final stored = sharedPreferences.getStringList(KEY_STORED_REVIEWS) ?? [];
      expect(stored.single, startsWith('good morning$_sep/media/77.mp4==='));
    });

    test('the longest entry-key suffix wins ("Sri Lanka" over "Lanka")',
        () async {
      // Both exist and end the master; a naive shortest/any match would
      // mis-attribute the review to "Lanka" forever.
      keyedByEnglishEntriesGlobal['Lanka'] =
          FakeEntry('Lanka', videos: const ['/media/lanka.mp4']);
      keyedByEnglishEntriesGlobal['Sri Lanka'] =
          FakeEntry('Sri Lanka', videos: const ['/media/11450.mp4']);
      await sharedPreferences.setStringList(KEY_STORED_REVIEWS, [
        encodeFakeReview('11450.mp4Sri Lanka'),
      ]);

      await migrateLegacyReviewsIfNeeded();

      final stored = sharedPreferences.getStringList(KEY_STORED_REVIEWS) ?? [];
      expect(stored.single, startsWith('Sri Lanka$_sep/media/11450.mp4==='));
    });

    test('an old full-URL video form still resolves by trailing filename',
        () async {
      // Some installs stored the video half as a full URL rather than a
      // bare filename; the trailing filename still pins the media path.
      keyedByEnglishEntriesGlobal['Sri Lanka'] =
          FakeEntry('Sri Lanka', videos: const ['/media/11450.mp4']);
      await sharedPreferences.setStringList(KEY_STORED_REVIEWS, [
        encodeFakeReview(
            'https://srilankansignlanguage.org/media/11450.mp4Sri Lanka'),
      ]);

      await migrateLegacyReviewsIfNeeded();

      final stored = sharedPreferences.getStringList(KEY_STORED_REVIEWS) ?? [];
      expect(stored.single, startsWith('Sri Lanka$_sep/media/11450.mp4==='));
    });

    test('entry matched but the filename is unknown → first-video fallback',
        () async {
      keyedByEnglishEntriesGlobal['Sri Lanka'] =
          FakeEntry('Sri Lanka', videos: const ['/media/real.mp4']);
      await sharedPreferences.setStringList(KEY_STORED_REVIEWS, [
        encodeFakeReview('99999.mp4Sri Lanka'),
      ]);

      await migrateLegacyReviewsIfNeeded();

      final stored = sharedPreferences.getStringList(KEY_STORED_REVIEWS) ?? [];
      expect(stored.single, startsWith('Sri Lanka$_sep/media/real.mp4==='));
    });

    test('a master whose entry is gone is dropped (others survive, no crash)',
        () async {
      keyedByEnglishEntriesGlobal['Sri Lanka'] =
          FakeEntry('Sri Lanka', videos: const ['/media/11450.mp4']);
      await sharedPreferences.setStringList(KEY_STORED_REVIEWS, [
        encodeFakeReview('11450.mp4Sri Lanka'),
        encodeFakeReview('123.mp4Vanished Word'),
      ]);

      await migrateLegacyReviewsIfNeeded();

      final stored = sharedPreferences.getStringList(KEY_STORED_REVIEWS) ?? [];
      expect(stored, hasLength(1));
      expect(stored.single, startsWith('Sri Lanka$_sep/media/11450.mp4==='));
    });

    test(
        'a filename whose pre-hyphen prefix is also an entry resolves to the '
        'real (suffix) entry, not the prefix one', () async {
      // Real SLSL data has filenames like "cold-snobbish_NE_Reg.mp4" while
      // "cold" is itself an entry. The review belongs to the master's SUFFIX
      // ("snobbish"); a hyphen-first resolver with a first-video fallback would
      // mis-attribute it to "cold". A strong (video-confirmed) match must win
      // over the weak fallback.
      keyedByEnglishEntriesGlobal['cold'] =
          FakeEntry('cold', videos: const ['/media/cold.mp4']);
      keyedByEnglishEntriesGlobal['snobbish'] = FakeEntry('snobbish',
          videos: const ['/media/cold-snobbish_NE_Reg.mp4']);
      await sharedPreferences.setStringList(KEY_STORED_REVIEWS, [
        encodeFakeReview('cold-snobbish_NE_Reg.mp4snobbish'),
      ]);

      await migrateLegacyReviewsIfNeeded();

      final stored = sharedPreferences.getStringList(KEY_STORED_REVIEWS) ?? [];
      expect(stored.single,
          startsWith('snobbish$_sep/media/cold-snobbish_NE_Reg.mp4==='));
    });

    test('the resolved master equals savedVideoMasterId for the same video',
        () async {
      // The migration output must be string-equal to the id the runtime
      // generates for a fresh save, so a migrated review lines up with the
      // new per-video master in future flashcard sessions.
      keyedByEnglishEntriesGlobal['Sri Lanka'] =
          FakeEntry('Sri Lanka', videos: const ['/media/11450.mp4']);
      await sharedPreferences.setStringList(KEY_STORED_REVIEWS, [
        encodeFakeReview('11450.mp4Sri Lanka'),
      ]);

      await migrateLegacyReviewsIfNeeded();

      final stored = sharedPreferences.getStringList(KEY_STORED_REVIEWS) ?? [];
      final expected = savedVideoMasterId(
          SavedVideo(entryKey: 'Sri Lanka', mediaPath: '/media/11450.mp4'));
      expect(decodeReview(stored.single).master, expected);
    });
  });
}
