import 'package:dictionarylib/common.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('compareDisplayNames', () {
    List<String> sorted(List<String> input) =>
        [...input]..sort(compareDisplayNames);

    test('sorts case-insensitively, not capitals-first', () {
      expect(sorted(['Cat', 'apple', 'Banana']), ['apple', 'Banana', 'Cat']);
    });

    test('ignores a leading emoji so it sorts by the first letter', () {
      expect(sorted(['Zebra', '🎉 Party', 'apple']),
          ['apple', '🎉 Party', 'Zebra']);
    });

    test('ignores any run of leading non-letters (emoji, symbols, spaces)', () {
      expect(sorted(['🌟🎊 Wonderful', '  apple', '#hash', 'zebra']),
          ['  apple', '#hash', '🌟🎊 Wonderful', 'zebra']);
    });

    test('keeps Sinhala and Tamil letters as sort keys', () {
      // Latin sorts before both Indic scripts by code point; the point here is
      // that a leading emoji is stripped while the script letter is not.
      expect(sorted(['🐘 මම', 'apple']), ['apple', '🐘 මම']);
      expect(sorted(['🎉 அம்மா', 'apple']), ['apple', '🎉 அம்மா']);
    });

    test('is a total order — distinct strings never compare equal', () {
      // Critical: this comparator keys a SplayTreeMap for community lists, so
      // two distinct keys returning 0 would silently collapse into one.
      expect(compareDisplayNames('🎉 Apple', 'Apple'), isNot(0));
      expect(compareDisplayNames('Apple', 'apple'), isNot(0));
      expect(compareDisplayNames('🎉🎊', '🎊'), isNot(0));
      expect(compareDisplayNames('🎉', '🎉'), 0); // identical ⇒ equal.
    });
  });
}
