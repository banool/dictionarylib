import 'package:dictionarylib/analytics.dart';
import 'package:flutter_test/flutter_test.dart';

// Analytics.errorDetail / errorTail split video failure classes without ever
// shipping a path or URL. These pin the sanitisers' contracts.
void main() {
  group('errorDetail', () {
    test('keeps mpv fixed strings, cuts before paths', () {
      expect(
        Analytics.errorDetail(
          "Cannot open file '/var/mobile/Containers/x/y.mp4': No such file",
        ),
        'cannot open file',
      );
      expect(
        Analytics.errorDetail('Errors when loading file.'),
        'errors when loading file',
      );
    });

    test('cuts at colon and http', () {
      // The disposal-race shapes (should be guarded out, but never shippable).
      expect(Analytics.errorDetail('Bad state: No element'), 'bad state');
      expect(
        Analytics.errorDetail('AssertionError: [Player] has been disposed'),
        'assertionerror',
      );
      expect(
        Analytics.errorDetail('failure fetching https://example.com/a.mp4'),
        'failure fetching',
      );
    });

    test('caps at four words', () {
      expect(
        Analytics.errorDetail('one two three four five six'),
        'one two three four',
      );
    });

    test('returns null when nothing legible remains', () {
      expect(Analytics.errorDetail(null), null);
      expect(Analytics.errorDetail('/private/path/only'), null);
      expect(Analytics.errorDetail('123 456'), null);
    });
  });

  group('errorTail', () {
    test('keeps the errno text after the last colon', () {
      expect(
        Analytics.errorTail(
          "Cannot open file '/var/mobile/x/y.mp4': No such file or directory",
        ),
        'no such file or directory',
      );
      expect(Analytics.errorTail('Bad state: No element'), 'no element');
      expect(
        Analytics.errorTail('open failed: Too many open files (errno 24)'),
        'too many open files errno',
      );
    });

    test('never ships a path, and is null without a tail', () {
      expect(Analytics.errorTail('Failed to open file: /var/x/y.mp4'), null);
      expect(Analytics.errorTail('Errors when loading file.'), null);
      expect(Analytics.errorTail(null), null);
      expect(Analytics.errorTail('trailing colon: 123'), null);
    });
  });
}
