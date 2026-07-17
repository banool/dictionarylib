import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart'
    show
        defaultTargetPlatform,
        kDebugMode,
        kIsWeb,
        TargetPlatform,
        visibleForTesting;
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import 'common.dart' show printAndLog;
import 'globals.dart'
    show androidDeviceInfo, iosDeviceInfo, packageInfo, themeVariantNotifier;

/// Privacy-first, anonymous product analytics (Aptabase).
///
/// We talk to Aptabase's documented ingest endpoint (`/api/v0/events`)
/// **directly over HTTP** rather than via the `aptabase_flutter` package: that
/// SDK is unmaintained (last published 2024) and its constraints force
/// `device_info_plus` / `package_info_plus` downgrades across both apps and pull
/// in Hive. The wire format is trivial and stable, so a ~self-contained client
/// using the `http` dependency we already have is cleaner and carries no extra
/// packages. If Aptabase is ever swapped for another tool, this file is the only
/// thing that changes — every call site goes through [track].
///
/// Why this needs no consent banner: Aptabase stores **no** device identifier
/// and discards the IP after deriving a daily-rotating anonymous hash
/// server-side, so no persistent identifier ever exists. The [sessionId] below
/// is a random value held only in memory for the current launch.
///
/// PRIVACY DISCIPLINE — enforced at this boundary. Only enums, counts, and
/// bucketed numbers may leave the device. Never pass a raw search term, list
/// name, entry key, user id, display name, or media path as an event name or a
/// property value. Bucket or hash first (see the call sites).
class Analytics {
  Analytics._();

  /// A new session starts after this much inactivity (matches Aptabase's SDK).
  static const Duration _sessionTimeout = Duration(hours: 1);

  /// How often buffered events are flushed to the network.
  static const Duration _flushInterval = Duration(seconds: 30);

  /// Flush eagerly once this many events are buffered.
  static const int _maxBuffer = 25;

  static const String _sdkVersion = 'dictionarylib-aptabase@1';

  /// Cloud regions are encoded in the app key (`A-EU-…` / `A-US-…`); the `DEV`
  /// region points at a local Aptabase for manual testing. `A-SH-…` keys are
  /// self-hosted and resolve to our own Aptabase instance below.
  static const Map<String, String> _regionHosts = {
    'EU': 'https://eu.aptabase.com',
    'US': 'https://us.aptabase.com',
    'SH': 'https://analytics.auslandictionary.org',
    'DEV': 'http://localhost:3000',
  };

  static final Random _rnd = Random();
  static final List<Map<String, dynamic>> _buffer = [];

  /// Base routes already counted this session, so `screen_view` is emitted at
  /// most once per screen per session (see [trackScreenView]). Cleared whenever
  /// the session id rotates.
  static final Set<String> _screensThisSession = {};

  static bool _enabled = false;
  static String _appKey = '';
  static Uri? _ingestUrl;
  static String _sessionId = '';
  static DateTime _lastTouch = DateTime.now().toUtc();
  static Timer? _timer;
  static AppLifecycleListener? _lifecycle;

  /// True once [init] has succeeded with a valid key. Call sites don't need to
  /// check this — [track] is a safe no-op when disabled — but the router uses it
  /// to avoid attaching the observer at all when analytics is off.
  static bool get isEnabled => _enabled;

  /// Initialise with the app's public Aptabase app key (format
  /// `A-REG-0000000000`). An empty key — the default the apps ship until one is
  /// configured, and what every test uses — makes this a permanent no-op, so no
  /// analytics is collected. Never throws.
  static Future<void> init(String appKey) async {
    if (_enabled || appKey.isEmpty || _isUnderTest) return;
    final parts = appKey.split('-');
    final host = parts.length == 3 ? _regionHosts[parts[1]] : null;
    if (host == null) {
      printAndLog('Analytics: Aptabase key looks invalid; analytics disabled');
      return;
    }
    _appKey = appKey;
    _ingestUrl = Uri.parse('$host/api/v0/events');
    _sessionId = _newSessionId();
    _enabled = true;

    // Flush on a timer and whenever the app is backgrounded (mobile apps are
    // often killed from the background, so this is where events would be lost).
    _timer = Timer.periodic(_flushInterval, (_) => unawaited(_flush()));
    _lifecycle = AppLifecycleListener(
      onInactive: () => unawaited(_flush()),
      onPause: () => unawaited(_flush()),
    );

    track('app_opened');
    // Flush the launch event promptly so daily-active-user counts are reliable
    // even for very short sessions.
    unawaited(_flush());
    printAndLog('Analytics initialised (anonymous, no persistent identifier)');
  }

  /// Record an event. [props] values must be strings or numbers; booleans are
  /// coerced to `'true'`/`'false'`, everything else to its `toString()`, and
  /// nulls are dropped. Global properties (platform, theme, coarse device
  /// model) are merged in automatically. Never throws; a no-op when disabled.
  static void track(String event, {Map<String, Object?>? props}) {
    if (!_enabled) return;
    final merged = <String, dynamic>{
      'platform': _platform,
      'theme': themeVariantNotifier.value.name,
    };
    final model = _deviceModel;
    if (model != null) merged['device_model'] = model;
    if (props != null) {
      props.forEach((key, value) {
        if (value == null) return;
        merged[key] = (value is String || value is num)
            ? value
            : (value is bool ? (value ? 'true' : 'false') : value.toString());
      });
    }
    _buffer.add({
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'sessionId': _evalSessionId(),
      'eventName': event,
      'systemProps': _systemProps(),
      'props': merged,
    });
    if (_buffer.length >= _maxBuffer) unawaited(_flush());
  }

  /// Coarse bucket label for a count. Use this for every numeric property so
  /// exact values — which are noisier and, in aggregate, closer to identifying —
  /// never leave the device (e.g. search result counts, cards reviewed, list
  /// size, query length).
  static String bucket(int n) {
    if (n <= 0) return '0';
    if (n == 1) return '1';
    if (n <= 3) return '2-3';
    if (n <= 5) return '4-5';
    if (n <= 10) return '6-10';
    if (n <= 20) return '11-20';
    if (n <= 50) return '21-50';
    if (n <= 100) return '51-100';
    return '100+';
  }

  /// Record a screen view, **deduplicated per session**: each base route emits
  /// at most once per session. Screen views on every navigation would dominate
  /// event volume (and Aptabase's free tier is small), whereas once-per-session
  /// still answers "which screens does a session reach". Search depth is covered
  /// separately by the debounced `search_performed` event.
  static void trackScreenView(String route) {
    if (!_enabled) return;
    _evalSessionId(); // rotates + clears the seen-set if the session aged out
    if (!_screensThisSession.add(route)) return;
    track('screen_view', props: {'route': route});
  }

  /// Coarse, non-identifying classification of an error for failure events.
  /// Never send the raw exception — it can contain URLs, media paths, or list
  /// keys (all PII per this file's discipline). Returns one of
  /// `network` / `timeout` / `other`.
  static String errorType(Object? e) {
    final s = (e?.toString() ?? '').toLowerCase();
    if (s.contains('timeout') || s.contains('timed out')) return 'timeout';
    if (s.contains('socketexception') ||
        s.contains('failed host lookup') ||
        s.contains('resolve hostname') ||
        s.contains('failed to resolve') ||
        s.contains('nodename') ||
        s.contains('connection') ||
        s.contains('refused') ||
        s.contains('unreachable') ||
        s.contains('network') ||
        s.contains('tcp:')) {
      return 'network';
    }
    return 'other';
  }

  /// Best-effort flush of buffered events. Exposed for tests / explicit flush;
  /// safe to call when empty or disabled.
  static Future<void> flush() => _flush();

  /// Cancel the flush timer + lifecycle listener and reset all state. The app
  /// never calls this (analytics lives for the whole process); it exists so
  /// tests can tear down between cases and so the timer/listener have an owner.
  @visibleForTesting
  static void reset() {
    _timer?.cancel();
    _timer = null;
    _lifecycle?.dispose();
    _lifecycle = null;
    _buffer.clear();
    _screensThisSession.clear();
    _enabled = false;
    _appKey = '';
    _ingestUrl = null;
  }

  static Future<void> _flush() async {
    final url = _ingestUrl;
    if (!_enabled || url == null || _buffer.isEmpty) return;
    final batch = List<Map<String, dynamic>>.from(_buffer);
    _buffer.clear();
    try {
      final resp = await http.post(
        url,
        headers: {
          'App-Key': _appKey,
          'Content-Type': 'application/json; charset=UTF-8',
        },
        body: jsonEncode(batch),
      );
      if (resp.statusCode >= 500) {
        // Transient server error — requeue (bounded) for the next tick.
        _requeue(batch);
      } else if (resp.statusCode >= 300 && kDebugMode) {
        printAndLog('Analytics: ingest ${resp.statusCode}: ${resp.body}');
      }
    } catch (_) {
      // Network/DNS error: analytics must never surface to the user. Requeue a
      // bounded number so a brief blip doesn't drop everything.
      _requeue(batch);
    }
  }

  static void _requeue(List<Map<String, dynamic>> batch) {
    final room = _maxBuffer - _buffer.length;
    if (room <= 0) return;
    _buffer.insertAll(0, batch.take(room));
  }

  static Map<String, dynamic> _systemProps() => {
        'isDebug': kDebugMode,
        'osName': _osName,
        'osVersion': _osVersion,
        'locale': _locale,
        'appVersion': packageInfo?.version ?? '',
        'appBuildNumber': packageInfo?.buildNumber ?? '',
        'sdkVersion': _sdkVersion,
      };

  /// True under any Flutter test binding (unit, widget, or integration). We
  /// never start analytics in tests: it would leak a periodic Timer (which
  /// fails widget tests) and send test/CI traffic to Aptabase. Detected via the
  /// binding's runtime type so production code needn't depend on flutter_test,
  /// and it stays web-safe (no dart:io). Real bindings are `WidgetsFlutterBinding`
  /// (no "Test"); test bindings are `*TestWidgetsFlutterBinding`.
  static bool get _isUnderTest =>
      WidgetsBinding.instance.runtimeType.toString().contains('Test');

  static String get _platform {
    if (kIsWeb) return 'web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      default:
        return 'other';
    }
  }

  /// Aptabase's OS-name convention (`iOS` / `iPadOS` / `Android`); coarse and
  /// non-identifying.
  static String get _osName {
    if (kIsWeb) return 'Web';
    if (iosDeviceInfo != null) {
      return iosDeviceInfo!.model.toLowerCase().contains('ipad')
          ? 'iPadOS'
          : 'iOS';
    }
    if (androidDeviceInfo != null) return 'Android';
    return '';
  }

  static String get _osVersion {
    if (iosDeviceInfo != null) return iosDeviceInfo!.systemVersion;
    if (androidDeviceInfo != null) return androidDeviceInfo!.version.release;
    return '';
  }

  /// Hardware model *type* (e.g. `iPhone14,3`, `Pixel 7`) — shared by millions
  /// of devices, not a per-device identifier. Deliberately NOT the user-set
  /// device name (`iosDeviceInfo.name`), which is personal.
  static String? get _deviceModel {
    if (iosDeviceInfo != null) return iosDeviceInfo!.utsname.machine;
    if (androidDeviceInfo != null) return androidDeviceInfo!.model;
    return null;
  }

  static String get _locale {
    try {
      return WidgetsBinding.instance.platformDispatcher.locale.toLanguageTag();
    } catch (_) {
      return '';
    }
  }

  static String _newSessionId() {
    final epochSeconds = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    final rand = _rnd.nextInt(100000000).toString().padLeft(8, '0');
    return '$epochSeconds$rand';
  }

  /// Reuse the current session id, rotating it after [_sessionTimeout] of
  /// inactivity (matches Aptabase's SDK so sessions line up on the dashboard).
  static String _evalSessionId() {
    final now = DateTime.now().toUtc();
    if (now.difference(_lastTouch) > _sessionTimeout) {
      _sessionId = _newSessionId();
      _screensThisSession.clear();
    }
    _lastTouch = now;
    return _sessionId;
  }
}

/// A [NavigatorObserver] that emits a `screen_view` event on each navigation,
/// tagged with the route's **base path only** (`/word/abc?video=1` → `/word`)
/// so entry keys, list ids, and query strings never leave the device. Attach it
/// to the app's `GoRouter` via its `observers:` list.
class AnalyticsNavigatorObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _send(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _send(newRoute);

  // Deliberately NOT didPop: back-navigation returns to an already-seen screen,
  // so counting it would double up and inflate volume. Forward navigation
  // (push/replace) is what we track, and it's deduplicated per session.

  void _send(Route<dynamic>? route) {
    final name = _baseRoute(route?.settings.name);
    if (name == null) return;
    Analytics.trackScreenView(name);
  }

  /// Reduce a full location to its first path segment. Returns null for unnamed
  /// routes (e.g. dialogs), which we don't count as screen views.
  static String? _baseRoute(String? location) {
    if (location == null || location.isEmpty) return null;
    final path = Uri.tryParse(location)?.path ?? location;
    final segments = path.split('/').where((s) => s.isNotEmpty).toList();
    return segments.isEmpty ? '/' : '/${segments.first}';
  }
}
