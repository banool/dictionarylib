import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dolphinsr/dolphinsr.dart';
import 'package:flutter/foundation.dart';

import 'common.dart';
import 'flashcards_logic.dart';
import 'globals.dart';
import 'sharing/account_sync_api.dart';
import 'sharing/sync_engine.dart' show AsyncLock;

/// SharedPreferences key of the answers this device has made and the
/// account hasn't acknowledged yet, in the stored encoding
/// ([encodeReview]). Written only while account sync runs for a signed-in
/// person; removed on sign-out.
const String KEY_REVIEWS_UNSENT = 'reviews_unsent';

/// The one reader and writer of the flashcard history ([KEY_STORED_REVIEWS])
/// and of [KEY_REVIEWS_UNSENT] (section 5.8 of the account-sync plan).
///
/// The history is one prefs entry, rewritten whole. Before account sync the
/// revision page read it at the start of a session and wrote back
/// `what it read + the session's answers` at the end, which was fine with
/// one writer. Account sync adds another: answers from the person's other
/// devices arrive in the background, possibly while a session is open, and
/// that old write would drop them. So every change goes through here, under
/// one lock, re-reading the stored list each time.
class ReviewHistory {
  final AsyncLock _lock = AsyncLock();
  final ValueNotifier<int> _version = ValueNotifier(0);

  /// Bumped whenever the history changes (answers stored here or arriving
  /// from elsewhere, a reset dropping some): pages that hold a copy of it
  /// re-read it.
  ValueListenable<int> get version => _version;

  /// Every stored answer. Undecodable lines are skipped.
  List<Review> read() {
    final encoded =
        sharedPreferences.getStringList(KEY_STORED_REVIEWS) ?? const [];
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

  /// How many answers are stored (without decoding them).
  int get storedCount =>
      (sharedPreferences.getStringList(KEY_STORED_REVIEWS) ?? const []).length;

  /// Append a session's [answers]. When [queueForUpload] (account sync runs
  /// for a signed-in person), they also go on the unsent queue, first: a
  /// kill between the two writes then leaves them queued but not stored,
  /// and they come back from the account with the next sync, rather than
  /// stored and never sent.
  Future<void> appendLocal(
    List<Review> answers, {
    required bool queueForUpload,
  }) {
    if (answers.isEmpty) return Future.value();
    return _lock.synchronized(() async {
      final encoded = answers.map(encodeReview).toList();
      if (queueForUpload) {
        final unsent =
            sharedPreferences.getStringList(KEY_REVIEWS_UNSENT) ?? const [];
        await sharedPreferences.setStringList(KEY_REVIEWS_UNSENT, [
          ...unsent,
          ...encoded,
        ]);
      }
      final stored =
          sharedPreferences.getStringList(KEY_STORED_REVIEWS) ?? const [];
      await sharedPreferences.setStringList(KEY_STORED_REVIEWS, [
        ...stored,
        ...encoded,
      ]);
      printAndLog(
        'Wrote ${answers.length} new reviews '
        '(making ${stored.length + encoded.length} in total) to storage',
      );
      _version.value++;
    });
  }

  /// Add every [incoming] answer that isn't stored yet (the same master,
  /// combination and time). Returns how many were new.
  Future<int> mergeRemote(List<Review> incoming) {
    if (incoming.isEmpty) return Future.value(0);
    return _lock.synchronized(() async {
      final stored =
          sharedPreferences.getStringList(KEY_STORED_REVIEWS) ?? const [];
      final have = <String>{};
      for (final line in stored) {
        final key = _identity(line);
        if (key != null) have.add(key);
      }
      final added = <String>[];
      for (final r in incoming) {
        final line = encodeReview(r);
        final key = _identity(line);
        if (key == null || !have.add(key)) continue;
        added.add(line);
      }
      if (added.isEmpty) return 0;
      await sharedPreferences.setStringList(KEY_STORED_REVIEWS, [
        ...stored,
        ...added,
      ]);
      _version.value++;
      return added.length;
    });
  }

  /// Drop every answer from before [tsUs] (microseconds): a reset of
  /// revision progress, here or on another device. Unsent answers from
  /// before it go too (the account would refuse them); later ones stay
  /// queued. (The plan clears the whole queue, which would lose this
  /// device's answers made after a reset made elsewhere.)
  Future<void> reset(int tsUs) {
    return _lock.synchronized(() async {
      bool keep(String line) {
        final t = _timeOf(line);
        return t != null && t >= tsUs;
      }

      final stored =
          sharedPreferences.getStringList(KEY_STORED_REVIEWS) ?? const [];
      await sharedPreferences.setStringList(KEY_STORED_REVIEWS, [
        for (final l in stored)
          if (keep(l)) l,
      ]);
      final unsent = sharedPreferences.getStringList(KEY_REVIEWS_UNSENT);
      if (unsent != null) {
        await sharedPreferences.setStringList(KEY_REVIEWS_UNSENT, [
          for (final l in unsent)
            if (keep(l)) l,
        ]);
      }
      _version.value++;
    });
  }

  /// Start uploading the whole stored history (the sign-in merge, M6): every
  /// stored answer joins the queue, after what is already in it (answers
  /// queued but not stored, by a kill inside [appendLocal], stay).
  Future<void> queueEverythingForUpload() {
    return _lock.synchronized(() async {
      final stored =
          sharedPreferences.getStringList(KEY_STORED_REVIEWS) ?? const [];
      final unsent =
          sharedPreferences.getStringList(KEY_REVIEWS_UNSENT) ?? const [];
      final queued = unsent.toSet();
      await sharedPreferences.setStringList(KEY_REVIEWS_UNSENT, [
        ...unsent,
        for (final l in stored)
          if (queued.add(l)) l,
      ]);
    });
  }

  /// The next batch to upload: up to [maxCount] unsent answers and about
  /// [maxBytes] of request JSON, from the front of the queue. The op id is
  /// derived from the batch's lines, so a batch re-sent after a lost answer
  /// is a `duplicate`.
  UploadBatch? nextUploadBatch({int maxCount = 500, int maxBytes = 40 * 1024}) {
    final unsent =
        sharedPreferences.getStringList(KEY_REVIEWS_UNSENT) ?? const [];
    if (unsent.isEmpty) return null;
    final lines = <String>[];
    final wire = <Map<String, dynamic>>[];
    var bytes = 0;
    for (final line in unsent) {
      if (lines.length >= maxCount) break;
      Map<String, dynamic> json;
      try {
        json = reviewToWire(decodeReview(line));
      } catch (_) {
        // Undecodable: still counted in the batch, so it leaves the queue
        // with it rather than blocking it forever.
        lines.add(line);
        continue;
      }
      final size = utf8.encode(jsonEncode(json)).length + 1;
      if (wire.isNotEmpty && bytes + size > maxBytes) break;
      lines.add(line);
      wire.add(json);
      bytes += size;
    }
    final digest = sha256.convert(utf8.encode(lines.join('\n'))).toString();
    return UploadBatch(
      opId: 'reviews-${digest.substring(0, 32)}',
      lines: lines,
      wire: wire,
    );
  }

  /// Take an acknowledged batch off the front of the queue.
  Future<void> removeUploaded(UploadBatch batch) {
    return _lock.synchronized(() async {
      final unsent =
          sharedPreferences.getStringList(KEY_REVIEWS_UNSENT) ?? const [];
      final n = batch.lines.length;
      // The queue only grows at the back, so the batch is still its head.
      if (unsent.length >= n && listEquals(unsent.sublist(0, n), batch.lines)) {
        await sharedPreferences.setStringList(
          KEY_REVIEWS_UNSENT,
          unsent.sublist(n),
        );
      } else {
        final remove = batch.lines.toSet();
        await sharedPreferences.setStringList(KEY_REVIEWS_UNSENT, [
          for (final l in unsent)
            if (!remove.contains(l)) l,
        ]);
      }
    });
  }

  int get unsentCount =>
      (sharedPreferences.getStringList(KEY_REVIEWS_UNSENT) ?? const []).length;

  /// Forget the unsent queue (sign-out, another account).
  Future<void> clearUnsent() =>
      _lock.synchronized(() => sharedPreferences.remove(KEY_REVIEWS_UNSENT));

  /// `master + combination + time`: what makes two answers the same one.
  static String? _identity(String line) {
    final parts = line.split(REVIEW_DELIMITER);
    if (parts.length < 4) return null;
    return '${parts[0]}$REVIEW_DELIMITER${parts[1]}$REVIEW_DELIMITER${parts[3]}';
  }

  static int? _timeOf(String line) {
    final parts = line.split(REVIEW_DELIMITER);
    if (parts.length < 4) return null;
    return int.tryParse(parts[3]);
  }
}

/// One batch of unsent answers, as an `addReviews` op.
class UploadBatch {
  final String opId;
  final List<String> lines;
  final List<Map<String, dynamic>> wire;
  const UploadBatch({
    required this.opId,
    required this.lines,
    required this.wire,
  });
}

/// An answer in the account's wire shape: `{m, c, r, t}`.
Map<String, dynamic> reviewToWire(Review r) => {
  'm': r.master,
  'c':
      '${r.combination!.front![0]}$COMBINATION_DELIMETER${r.combination!.back![0]}',
  'r': r.rating!.index,
  't': r.ts!.microsecondsSinceEpoch,
};

/// An answer from the account, or null if it can't be read.
Review? reviewFromWire(RemoteReview r) {
  try {
    final parts = r.c.split(COMBINATION_DELIMETER);
    return Review(
      master: r.m,
      combination: Combination(
        front: [int.parse(parts[0])],
        back: [int.parse(parts[1])],
      ),
      rating: Rating.values[r.r],
      ts: DateTime.fromMicrosecondsSinceEpoch(r.t),
    );
  } catch (_) {
    return null;
  }
}

/// The process-wide [ReviewHistory].
final ReviewHistory reviewHistory = ReviewHistory();
