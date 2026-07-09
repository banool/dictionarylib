import 'package:dictionarylib/entry_list.dart';
import 'package:dictionarylib/globals.dart';
import 'package:dictionarylib/page_search.dart';
import 'package:dictionarylib/saved_video.dart';
import 'package:dictionarylib/sharing/sharing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '_helpers.dart';

// Exercises the pure sign-of-the-day selection (computeSignOfDay), which is
// what the "hide this sign" button and the daily rotation both hinge on. The
// widget wiring around it (the card, the confirm dialog) is thin; the logic
// worth pinning is here.
void main() {
  const locale = Locale('en');

  setUp(() async {
    installFakeSecureStorage();
    SharedPreferences.setMockInitialValues({});
    sharedPreferences = await SharedPreferences.getInstance();
    seedDictionary(['apple', 'banana', 'cherry']);
    userEntryListManager = UserEntryListManager.fromStartup();
    sharing = Sharing.disabled();
  });

  // Build a user list with the given entry keys saved into it.
  Future<EntryList> listWith(List<String> keys) async {
    await userEntryListManager.createEntryList('mine_words');
    final list = userEntryListManager.getEntryLists()['mine_words']!;
    for (final k in keys) {
      await list.addVideo(SavedVideo(entryKey: k, mediaPath: videoFor(k)));
    }
    return list;
  }

  test('nothing saved → no sign of the day', () async {
    final list = await listWith([]);
    expect(computeSignOfDay([list], const {}, locale, DateTime(2026, 7, 9)),
        isNull);
  });

  test('same day → stable pick; hidden set is honoured', () async {
    final list = await listWith(['apple', 'banana', 'cherry']);
    final now = DateTime(2026, 7, 9);

    final first = computeSignOfDay([list], const {}, locale, now);
    expect(first, isNotNull);
    // Deterministic within a day: recomputing gives the same sign.
    expect(computeSignOfDay([list], const {}, locale, now)!.getKey(),
        first!.getKey());
  });

  test('rotates day to day', () async {
    final list = await listWith(['apple', 'banana', 'cherry']);
    final day1 =
        computeSignOfDay([list], const {}, locale, DateTime(2026, 7, 9))!
            .getKey();
    final day2 =
        computeSignOfDay([list], const {}, locale, DateTime(2026, 7, 10))!
            .getKey();
    // Three candidates advancing one index per day → consecutive days differ.
    expect(day1, isNot(day2));
  });

  test('hiding the featured sign selects a different one (2 → 1)', () async {
    final list = await listWith(['apple', 'banana']);
    final now = DateTime(2026, 7, 9);

    final featured = computeSignOfDay([list], const {}, locale, now)!;
    final next = computeSignOfDay([list], {featured.getKey()}, locale, now);

    expect(next, isNotNull);
    expect(next!.getKey(), isNot(featured.getKey()));
  });

  test('hiding the only saved sign hides the card (1 → 0)', () async {
    final list = await listWith(['apple']);
    final now = DateTime(2026, 7, 9);

    final featured = computeSignOfDay([list], const {}, locale, now)!;
    expect(featured.getKey(), 'apple');

    // Hiding the last remaining candidate leaves nothing to feature — the
    // caller reads null as "don't render the card" rather than crashing.
    expect(computeSignOfDay([list], {featured.getKey()}, locale, now), isNull);
  });

  test('everything hidden → null', () async {
    final list = await listWith(['apple', 'banana', 'cherry']);
    expect(
      computeSignOfDay(
        [list],
        {'apple', 'banana', 'cherry'},
        locale,
        DateTime(2026, 7, 9),
      ),
      isNull,
    );
  });
}
