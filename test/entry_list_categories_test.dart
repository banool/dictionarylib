import 'package:dictionarylib/common.dart';
import 'package:dictionarylib/entry_list_categories.dart';
import 'package:dictionarylib/entry_types.dart';
import 'package:dictionarylib/globals.dart';
import 'package:flutter_test/flutter_test.dart';

import '_helpers.dart';

// Community lists are auto-generated from the dictionary's category strings
// (never user input) but run through the same key derivation as user lists,
// so they must preserve any printable text — emoji included.
void main() {
  List<String> communityListNames() => CategoryEntryListManager.fromStartup()
      .getEntryLists()
      .values
      .map((l) => l.getName())
      .toList();

  test('preserves emoji in category names and dedupes shared categories', () {
    entriesGlobal = <Entry>{
      FakeEntry('dog', categories: const ['Animals 🐘']),
      FakeEntry('cat', categories: const ['Animals 🐘', 'Pets 🐾']),
    };
    final names = communityListNames();
    expect(names, containsAll(<String>['Animals 🐘', 'Pets 🐾']));
    // 'Animals 🐘' appears on both entries but yields a single list.
    expect(names.where((n) => n == 'Animals 🐘').length, 1);
  });

  test('skips categories that cannot form a valid list name', () {
    entriesGlobal = <Entry>{
      FakeEntry('a', categories: [
        'Favourites', // reserved
        'a' * (maxListNameLength + 1), // too long
        '   ', // whitespace-only → empty after trim
        'Sport', // valid
      ]),
    };
    expect(communityListNames(), ['Sport']);
  });
}
