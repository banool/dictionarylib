import 'dart:async';
import 'dart:convert';

import 'package:dictionarylib/data_fetch.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// Short bounds so the timeout tests run in milliseconds. The stall/headers
// distinction is the point of the design: a blackholed host must fail at the
// headers bound, while a slow-but-alive body stream must be allowed to take
// longer than any single bound overall, as long as chunks keep arriving.
const headersTimeout = Duration(milliseconds: 300);
const stallTimeout = Duration(milliseconds: 300);

Future<DataFetchResult> fetch(
  http.Client client, {
  void Function(int, int?)? onProgress,
  Map<String, String> headers = const {},
}) => fetchWithProgress(
  Uri.parse('https://example.com/data.json'),
  client: client,
  headers: headers,
  headersTimeout: headersTimeout,
  stallTimeout: stallTimeout,
  onProgress: onProgress,
);

void main() {
  test('assembles a chunked body and reports cumulative progress', () async {
    final client = MockClient.streaming((request, bodyStream) async {
      final chunks = Stream.fromIterable([
        utf8.encode('hello '),
        utf8.encode('world'),
      ]);
      return http.StreamedResponse(chunks, 200, contentLength: 11);
    });

    final progress = <(int, int?)>[];
    final result = await fetch(
      client,
      onProgress: (received, total) => progress.add((received, total)),
    );

    expect(result.statusCode, 200);
    expect(result.body, 'hello world');
    expect(progress, [(6, 11), (11, 11)]);
  });

  test('reports null total when Content-Length is absent', () async {
    final client = MockClient.streaming((request, bodyStream) async {
      return http.StreamedResponse(
        Stream.fromIterable([utf8.encode('data')]),
        200,
      );
    });

    final progress = <(int, int?)>[];
    await fetch(
      client,
      onProgress: (received, total) => progress.add((received, total)),
    );

    expect(progress, [(4, null)]);
  });

  test('times out when response headers never arrive', () async {
    final client = MockClient.streaming((request, bodyStream) async {
      // A blackholed host: the request just hangs.
      return Completer<http.StreamedResponse>().future;
    });

    await expectLater(fetch(client), throwsA(isA<TimeoutException>()));
  });

  test('times out when the body stream stalls mid-download', () async {
    final controller = StreamController<List<int>>();
    final client = MockClient.streaming((request, bodyStream) async {
      controller.add(utf8.encode('start'));
      // Never add more and never close: a stalled connection.
      return http.StreamedResponse(controller.stream, 200, contentLength: 100);
    });

    await expectLater(fetch(client), throwsA(isA<TimeoutException>()));
    await controller.close();
  });

  test('a slow-but-alive download outlasting both bounds completes', () async {
    // 5 chunks, 100ms apart: ~500ms total, over both 300ms bounds, but no
    // single inter-chunk gap exceeds the stall bound. This is the case a
    // whole-request timeout would wrongly kill.
    final client = MockClient.streaming((request, bodyStream) async {
      final chunks = () async* {
        for (var i = 0; i < 5; i++) {
          await Future.delayed(const Duration(milliseconds: 100));
          yield utf8.encode('x');
        }
      }();
      return http.StreamedResponse(chunks, 200, contentLength: 5);
    });

    final result = await fetch(client);
    expect(result.body, 'xxxxx');
  });

  test('non-200 statuses are returned, not thrown', () async {
    final client = MockClient.streaming((request, bodyStream) async {
      return http.StreamedResponse(
        Stream.fromIterable([utf8.encode('not found')]),
        404,
      );
    });

    final result = await fetch(client);
    expect(result.statusCode, 404);
    expect(result.body, 'not found');
  });

  test('passes request headers through and returns response headers', () async {
    late Map<String, String> seenRequestHeaders;
    final client = MockClient.streaming((request, bodyStream) async {
      seenRequestHeaders = request.headers;
      return http.StreamedResponse(
        Stream.fromIterable([utf8.encode('')]),
        304,
        headers: {'last-modified': 'Wed, 01 Jan 2025 00:00:00 GMT'},
      );
    });

    final result = await fetch(
      client,
      headers: {'If-Modified-Since': 'Tue, 31 Dec 2024 00:00:00 GMT'},
    );
    expect(
      seenRequestHeaders['If-Modified-Since'],
      'Tue, 31 Dec 2024 00:00:00 GMT',
    );
    expect(result.headers['last-modified'], 'Wed, 01 Jan 2025 00:00:00 GMT');
  });

  test('an injected client is not closed', () async {
    final client = MockClient.streaming((request, bodyStream) async {
      return http.StreamedResponse(
        Stream.fromIterable([utf8.encode('ok')]),
        200,
      );
    });

    await fetch(client);
    // A closed MockClient throws on use; a second fetch proves it wasn't.
    final again = await fetch(client);
    expect(again.body, 'ok');
  });

  group('DictionaryDownloadStatus', () {
    test('fraction is null without a total and clamped with one', () {
      const noTotal = DictionaryDownloadStatus(
        stage: DictionaryDownloadStage.downloading,
        receivedBytes: 5,
      );
      expect(noTotal.fraction, null);

      const overshoot = DictionaryDownloadStatus(
        stage: DictionaryDownloadStage.downloading,
        receivedBytes: 15,
        totalBytes: 10,
      );
      expect(overshoot.fraction, 1.0);
    });

    test('host comes from the url', () {
      final status = DictionaryDownloadStatus(
        stage: DictionaryDownloadStage.checking,
        url: Uri.parse('https://cdn.auslandictionary.org/data/latest_version'),
      );
      expect(status.host, 'cdn.auslandictionary.org');
    });
  });
}
