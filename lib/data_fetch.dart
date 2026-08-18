import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'common.dart';

/// Where the blocking cold-start dictionary download is up to. Reported by the
/// apps' EntryLoader.downloadNewData implementations and rendered by
/// StartupLoadingApp.
enum DictionaryDownloadStage {
  /// Talking to a candidate host to work out whether/what to download.
  checking,

  /// Streaming the dictionary data itself.
  downloading,

  /// Data is fully downloaded; deserializing and applying it.
  applying,
}

/// A snapshot of an in-flight dictionary download, published via
/// [EntryLoader.downloadStatusNotifier]. Immutable — report a fresh instance
/// per update.
class DictionaryDownloadStatus {
  final DictionaryDownloadStage stage;

  /// The URL currently being fetched. Null in the [applying] stage, when no
  /// request is in flight.
  final Uri? url;

  /// Which candidate base URL this request belongs to, 0-based, out of
  /// [urlCount]. Auslan has a primary host and a mirror; SLSL has one host.
  /// The loading screen only shows an "attempt n of m" line when urlCount > 1.
  final int urlIndex;
  final int urlCount;

  final int receivedBytes;

  /// Total size of the body being downloaded, from Content-Length. Null when
  /// the server didn't say (e.g. some gzip transfer encodings), in which case
  /// the UI falls back to an indeterminate bar plus a bytes counter.
  final int? totalBytes;

  const DictionaryDownloadStatus({
    required this.stage,
    this.url,
    this.urlIndex = 0,
    this.urlCount = 1,
    this.receivedBytes = 0,
    this.totalBytes,
  });

  String? get host => url?.host;

  /// Download completion in [0, 1], or null when the total is unknown.
  double? get fraction {
    final total = totalBytes;
    if (total == null || total <= 0) return null;
    return (receivedBytes / total).clamp(0.0, 1.0);
  }

  @override
  String toString() =>
      "DictionaryDownloadStatus(stage: $stage, url: $url, urlIndex: $urlIndex, "
      "urlCount: $urlCount, receivedBytes: $receivedBytes, totalBytes: $totalBytes)";
}

/// What [fetchWithProgress] hands back. Deliberately does NOT throw on non-200
/// statuses: SLSL's conditional GET needs the 304 passed through, and auslan
/// rejects non-200 itself so it can fall through to its mirror (which also
/// stops a captive portal's 200-with-HTML being silently accepted as data —
/// callers must check the status).
class DataFetchResult {
  final int statusCode;

  /// Response headers with lowercase keys, as package:http returns them.
  final Map<String, String> headers;

  /// The utf8-decoded body.
  final String body;

  const DataFetchResult({
    required this.statusCode,
    required this.headers,
    required this.body,
  });
}

/// GET [url] with bounded waits and byte-level progress reporting.
///
/// Two separate timeouts, both defaulting to [kDataFetchTimeout]:
/// [headersTimeout] bounds the wait for the response headers (connect + first
/// byte — where a blackholed host hangs), and [stallTimeout] bounds the gap
/// between body chunks while streaming. There is intentionally no
/// whole-request timeout: a slow-but-alive download of the ~15mb dictionary
/// must not be killed for taking its time (which is what SLSL's old
/// whole-request timeout would have done on a slow link).
///
/// [onProgress] fires per received chunk with the cumulative byte count and
/// the Content-Length-derived total (null when the server didn't send one).
///
/// [client] is injectable for tests; when null a client is created and closed
/// internally. An injected client is never closed.
Future<DataFetchResult> fetchWithProgress(
  Uri url, {
  Map<String, String> headers = const {},
  http.Client? client,
  Duration headersTimeout = kDataFetchTimeout,
  Duration stallTimeout = kDataFetchTimeout,
  void Function(int receivedBytes, int? totalBytes)? onProgress,
}) async {
  final ownsClient = client == null;
  final http.Client effectiveClient = client ?? http.Client();
  try {
    final request = http.Request('GET', url);
    request.headers.addAll(headers);

    final streamed = await effectiveClient
        .send(request)
        .timeout(
          headersTimeout,
          onTimeout: () => throw TimeoutException(
            "No response headers from $url within $headersTimeout",
          ),
        );

    final totalBytes = streamed.contentLength;
    final bytes = BytesBuilder(copy: false);
    // stream.timeout re-arms per event, giving exactly the per-chunk stall
    // semantics we want; the injected error surfaces out of the await below.
    final stream = streamed.stream.timeout(
      stallTimeout,
      onTimeout: (sink) {
        sink.addError(
          TimeoutException(
            "Download from $url stalled: no data for $stallTimeout",
          ),
        );
        sink.close();
      },
    );
    await for (final chunk in stream) {
      bytes.add(chunk);
      onProgress?.call(bytes.length, totalBytes);
    }

    return DataFetchResult(
      statusCode: streamed.statusCode,
      headers: streamed.headers,
      body: utf8.decode(bytes.takeBytes()),
    );
  } finally {
    if (ownsClient) {
      effectiveClient.close();
    }
  }
}
