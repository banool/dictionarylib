import 'package:dictionarylib/sharing/list_id.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('generateListId', () {
    test('produces 12 chars in lowercase base32', () {
      for (var i = 0; i < 20; i++) {
        final k = generateListId();
        expect(k.length, 12);
        expect(RegExp(r'^[a-z2-7]{12}$').hasMatch(k), isTrue,
            reason: 'unexpected char in $k');
      }
    });

    test('two consecutive generations are different', () {
      expect(generateListId(), isNot(generateListId()));
    });
  });

  group('isPlausibleListId', () {
    test('accepts lowercase + digits up to 64 chars', () {
      expect(isPlausibleListId('abc123'), isTrue);
      expect(isPlausibleListId('z'), isTrue);
      expect(isPlausibleListId('z' * 64), isTrue);
    });

    test('rejects empty + too long', () {
      expect(isPlausibleListId(''), isFalse);
      expect(isPlausibleListId('z' * 65), isFalse);
    });

    test('rejects uppercase / dashes / underscores / punctuation', () {
      expect(isPlausibleListId('Abc123'), isFalse);
      expect(isPlausibleListId('with-dash'), isFalse);
      expect(isPlausibleListId('with_underscore'), isFalse);
      expect(isPlausibleListId('with space'), isFalse);
      expect(isPlausibleListId('weird!chars'), isFalse);
    });
  });
}
