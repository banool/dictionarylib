import 'package:dictionarylib/analytics.dart';
import 'package:flutter_test/flutter_test.dart';

// Analytics.errorDetail splits errorType's `other` class without ever
// shipping a path or URL. These pin the sanitiser's contract.
void main() {
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
}
