import 'package:dictionarylib/analytics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('timeout errors classify as timeout', () {
    expect(Analytics.errorType('TimeoutException after 0:00:10.000000'),
        'timeout');
    expect(Analytics.errorType('request timed out'), 'timeout');
  });

  test('cache manager HTTP status errors classify by status class', () {
    expect(
        Analytics.errorType(
            'HttpExceptionWithStatus: Invalid statusCode: 403, uri = https://example.com/a.mp4'),
        'http_403');
    expect(
        Analytics.errorType(
            'HttpExceptionWithStatus: Invalid statusCode: 404, uri = https://example.com/a.mp4'),
        'http_404');
    expect(
        Analytics.errorType(
            'HttpExceptionWithStatus: Invalid statusCode: 429, uri = https://example.com/a.mp4'),
        'http_4xx');
    expect(
        Analytics.errorType(
            'HttpExceptionWithStatus: Invalid statusCode: 503, uri = https://example.com/a.mp4'),
        'http_5xx');
  });

  test('connectivity errors classify as network', () {
    expect(
        Analytics.errorType(
            "SocketException: Failed host lookup: 'cdn.example.com'"),
        'network');
    expect(Analytics.errorType('Connection refused'), 'network');
  });

  test("mpv's opaque open failure gets its own class", () {
    expect(Analytics.errorType('Failed to open https://example.com/a.mp4.'),
        'open_failed');
  });

  test('demux/codec errors classify as decode', () {
    expect(Analytics.errorType('Failed to recognize file format.'), 'decode');
    expect(Analytics.errorType('no decoder for codec h999'), 'decode');
  });

  test('anything unrecognised stays other', () {
    expect(Analytics.errorType('something exploded'), 'other');
    expect(Analytics.errorType(null), 'other');
  });
}
