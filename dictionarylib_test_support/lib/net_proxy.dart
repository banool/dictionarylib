import 'dart:async';
import 'dart:io';

/// What a [NetProxy] does with the requests it gets.
enum ProxyMode {
  /// Forward them.
  up,

  /// Nothing listening: connection refused.
  down,

  /// Accept them and never answer (a captive portal, dead Wi-Fi), until
  /// the mode changes, when the connections drop.
  blackhole,

  /// Forward them and drop the answer: the server does the work and the
  /// device never hears (what proves every request idempotent).
  lossy,
}

/// An HTTP proxy on a loopback port in front of [upstream], whose network
/// tests switch: up, down, a black hole, lossy. Used against the real Worker
/// by dictionarylib's tests and inside the app by the on-device suites. Only
/// `dart:io`, so both can use it.
class NetProxy {
  final Uri upstream;
  final int port;
  HttpServer? _server;
  ProxyMode _mode = ProxyMode.up;
  final List<HttpRequest> _held = [];
  // The answer's bytes go through as they came (gzip and all).
  final HttpClient _client = HttpClient()..autoUncompress = false;

  /// Requests that reached the proxy (whatever happened to them).
  int requests = 0;

  NetProxy._(this.upstream, this.port, this._server);

  /// A proxy for [upstream] on a free loopback port.
  static Future<NetProxy> start(Uri upstream) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final proxy = NetProxy._(upstream, server.port, server);
    proxy._listen(server);
    return proxy;
  }

  /// Where to point a client: `http://127.0.0.1:<port>`.
  String get baseUrl => 'http://127.0.0.1:$port';

  ProxyMode get mode => _mode;

  /// Forward requests again (listening again on the same port if down).
  Future<void> up() => _set(ProxyMode.up);

  /// Stop listening: connection refused.
  Future<void> down() => _set(ProxyMode.down);

  Future<void> blackhole() => _set(ProxyMode.blackhole);

  Future<void> lossy() => _set(ProxyMode.lossy);

  Future<void> _set(ProxyMode mode) async {
    _mode = mode;
    for (final r in _held) {
      try {
        (await r.response.detachSocket()).destroy();
      } catch (_) {}
    }
    _held.clear();
    if (mode == ProxyMode.down) {
      await _server?.close(force: true);
      _server = null;
    } else if (_server == null) {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
      _server = server;
      _listen(server);
    }
  }

  Future<void> close() async {
    _mode = ProxyMode.down;
    for (final r in _held) {
      try {
        (await r.response.detachSocket()).destroy();
      } catch (_) {}
    }
    _held.clear();
    await _server?.close(force: true);
    _server = null;
    _client.close(force: true);
  }

  void _listen(HttpServer server) {
    server.listen((req) {
      requests++;
      unawaited(_handle(req).catchError((Object _) {}));
    });
  }

  Future<void> _handle(HttpRequest req) async {
    if (_mode == ProxyMode.blackhole) {
      _held.add(req);
      return;
    }
    final lossy = _mode == ProxyMode.lossy;
    final out = await _client.openUrl(
      req.method,
      upstream.replace(path: req.uri.path, query: req.uri.query),
    );
    req.headers.forEach((name, values) {
      if (name == HttpHeaders.hostHeader) return;
      for (final v in values) {
        out.headers.add(name, v);
      }
    });
    await out.addStream(req);
    final resp = await out.close();
    if (lossy) {
      await resp.drain<void>();
      (await req.response.detachSocket()).destroy();
      return;
    }
    req.response.statusCode = resp.statusCode;
    resp.headers.forEach((name, values) {
      if (name == HttpHeaders.transferEncodingHeader ||
          name == HttpHeaders.contentLengthHeader) {
        return;
      }
      for (final v in values) {
        req.response.headers.add(name, v);
      }
    });
    await resp.pipe(req.response);
  }
}
