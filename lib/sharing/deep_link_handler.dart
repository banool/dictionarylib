import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';

import '../common.dart';
import 'list_id.dart';
import 'sharing_config.dart';

/// Payload emitted by [DeepLinkHandler]. Always carries a `listId`; the
/// optional `inviteToken` is set when the URL had `?invite=<token>`,
/// signalling the recipient should be added as an editor rather than
/// just subscribing.
class SharePayload {
  final String listId;
  final String? inviteToken;
  const SharePayload({required this.listId, this.inviteToken});

  bool get isInvite => inviteToken != null && inviteToken!.isNotEmpty;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SharePayload &&
          other.listId == listId &&
          other.inviteToken == inviteToken);

  @override
  int get hashCode => Object.hash(listId, inviteToken);
}

/// Listens for share URLs delivered to the app via the OS deep-link /
/// app-link machinery. Consumer apps subscribe to [payloads] and route
/// accordingly (typically `router.go('/share/$listId')` for subscribe,
/// or push the accept-invite landing page when [SharePayload.isInvite]
/// is true).
///
/// Handles two URL shapes:
///   - `https://<shareLinkHost>/l/<key>[?invite=<token>]`  (Universal / App Link)
///   - `<scheme>://share/<key>[?invite=<token>]`           (custom scheme fallback)
///
/// ## Cold-start replay
///
/// [Sharing.setup] runs `start()` from `main()`, which fires the
/// initial OS-delivered URL into the stream synchronously. App UI
/// (router etc.) typically subscribes a frame later, in `initState`,
/// so without replay the cold-start link would be dropped.
///
/// To fix that, the most recent payload is cached and replayed to any
/// subscriber that joins late — once, on subscribe. After replay the
/// cache is cleared so a subscriber that disconnects-and-rejoins
/// doesn't re-route to a stale link. Live links delivered while a
/// listener is active follow the usual broadcast semantics.
class DeepLinkHandler {
  final SharingConfig config;
  final AppLinks? _appLinks;

  /// Test-only override for the platform's "what was the initial cold-
  /// start link" call. When set, [start] uses this instead of
  /// `AppLinks().getInitialLink()`.
  final Future<Uri?> Function()? _initialLinkGetter;

  /// Test-only override for the platform's live deep-link stream. When
  /// set, [start] subscribes to this instead of `AppLinks().uriLinkStream`.
  final Stream<Uri>? _linkStream;

  /// Buffers the most-recent payload until *one* subscriber has read
  /// it. Cleared on first delivery to a new subscriber.
  SharePayload? _pendingInitial;

  /// Suppresses adjacent-duplicate emissions — the OS occasionally
  /// delivers the same URL twice (cold-start + lifecycle resume,
  /// back-to-back within a few hundred ms). The dedupe only kicks
  /// in within [_dedupeWindow] so a user re-tapping the same share
  /// link a moment later still routes.
  SharePayload? _lastEmitted;
  DateTime? _lastEmittedAt;
  static const Duration _dedupeWindow = Duration(seconds: 2);

  late final StreamController<SharePayload> _controller;
  StreamSubscription<Uri>? _sub;
  bool _started = false;

  DeepLinkHandler({required this.config, AppLinks? appLinks})
      : _appLinks = appLinks,
        _initialLinkGetter = null,
        _linkStream = null {
    _controller = StreamController<SharePayload>.broadcast(
      onListen: _onListen,
    );
  }

  /// Test-only constructor that bypasses the [AppLinks] platform plugin
  /// (which is hard to mock cleanly because [AppLinks] is a singleton
  /// with a private constructor). Pass an [initialLinkGetter] that
  /// returns whatever the OS would have delivered on cold-start, and a
  /// [linkStream] that emits live deep-links.
  @visibleForTesting
  DeepLinkHandler.forTesting({
    required this.config,
    required Future<Uri?> Function() initialLinkGetter,
    required Stream<Uri> linkStream,
  })  : _appLinks = null,
        _initialLinkGetter = initialLinkGetter,
        _linkStream = linkStream {
    _controller = StreamController<SharePayload>.broadcast(
      onListen: _onListen,
    );
  }

  /// Broadcast stream of share payloads parsed out of incoming URLs.
  /// Late subscribers receive any payload buffered prior to subscribe
  /// (the cold-start initial link) on their first `onData` callback,
  /// then live emissions thereafter.
  Stream<SharePayload> get payloads => _controller.stream;

  /// The most-recently-parsed payload, if one is buffered for
  /// late-subscriber replay. Exposed for the host app's GoRouter
  /// `initialLocation` callback, which can branch on a cold-start link
  /// without waiting for the stream event. Consuming this clears the
  /// buffer.
  SharePayload? takePendingInitial() {
    final p = _pendingInitial;
    _pendingInitial = null;
    return p;
  }

  Future<void> start() async {
    if (_started || kIsWeb) {
      // On web, deep-linking happens through the browser URL + GoRouter
      // directly — no app_links plumbing needed.
      return;
    }
    _started = true;
    final getInitial =
        _initialLinkGetter ?? () => (_appLinks ?? AppLinks()).getInitialLink();
    final stream = _linkStream ?? (_appLinks ?? AppLinks()).uriLinkStream;
    try {
      final initial = await getInitial();
      if (initial != null) _handle(initial);
    } catch (e) {
      printAndLog('DeepLinkHandler: initial link error: $e');
    }
    _sub = stream.listen(_handle, onError: (Object e) {
      printAndLog('DeepLinkHandler: stream error: $e');
    });
  }

  void dispose() {
    _sub?.cancel();
    _controller.close();
  }

  void _handle(Uri uri) {
    final payload = extractSharePayload(uri, config);
    if (payload == null) return;
    final now = DateTime.now();
    final last = _lastEmittedAt;
    if (payload == _lastEmitted &&
        last != null &&
        now.difference(last) < _dedupeWindow) {
      // OS dupe — already routed. Same payload past the window is
      // treated as a user-initiated re-tap and re-emitted.
      return;
    }
    _lastEmitted = payload;
    _lastEmittedAt = now;
    final hasInvite = payload.isInvite;
    printAndLog('DeepLinkHandler: matched share link for "${payload.listId}"'
        '${hasInvite ? " (with invite token)" : ""}');
    if (!_controller.hasListener) {
      // Cold-start: nobody's subscribed yet. Buffer for replay.
      _pendingInitial = payload;
      return;
    }
    _controller.add(payload);
  }

  void _onListen() {
    final pending = _pendingInitial;
    if (pending == null) return;
    _pendingInitial = null;
    // Push into the event loop so the new subscriber's onData fires
    // *after* the StreamController finishes wiring up.
    scheduleMicrotask(() {
      if (!_controller.isClosed) _controller.add(pending);
    });
  }
}

/// Extract a [SharePayload] from an inbound URI, or null if not a share
/// link this app handles. Pure / top-level for testability.
SharePayload? extractSharePayload(Uri uri, SharingConfig config) {
  String? listId;
  if (uri.scheme == 'https' && uri.host == config.shareLinkHost) {
    final seg = uri.pathSegments;
    if (seg.length >= 2 && seg[0] == 'l' && seg[1].isNotEmpty) {
      listId = seg[1];
    }
  } else if (uri.scheme == config.urlScheme && uri.host == 'share') {
    if (uri.pathSegments.isNotEmpty && uri.pathSegments[0].isNotEmpty) {
      listId = uri.pathSegments[0];
    }
  }
  if (listId == null) return null;
  final inviteRaw = uri.queryParameters['invite'];
  final invite = inviteRaw != null && inviteRaw.isNotEmpty ? inviteRaw : null;
  return SharePayload(listId: listId, inviteToken: invite);
}

/// Parse a free-form input field — either a bare list ID or any of the
/// supported share-URL shapes — into a [SharePayload]. Returns null if
/// the input can't be coerced into a valid list ID.
///
/// Surfaces invite tokens in the result so callers can branch (the
/// subscribe-by-pasting dialog refuses pasted invite URLs explicitly
/// rather than silently subscribing the user as a non-editor).
SharePayload? parseShareInput(String input, SharingConfig config) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return null;

  if (trimmed.contains('://')) {
    Uri uri;
    try {
      uri = Uri.parse(trimmed);
    } catch (_) {
      return null;
    }

    final strict = extractSharePayload(uri, config);
    if (strict != null) return _normaliseAndValidate(strict);

    // Loose fallback: any URL whose path has `/l/<segment>`. Pick up
    // the invite token from the same URL when present so an inbound
    // invite URL from an unrecognised host still reaches the
    // accept-invite flow.
    final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    final lIdx = segs.indexOf('l');
    if (lIdx >= 0 && lIdx + 1 < segs.length) {
      final inviteRaw = uri.queryParameters['invite'];
      return _normaliseAndValidate(SharePayload(
        listId: segs[lIdx + 1],
        inviteToken:
            inviteRaw != null && inviteRaw.isNotEmpty ? inviteRaw : null,
      ));
    }
    return null;
  }

  return _normaliseAndValidate(SharePayload(listId: trimmed));
}

SharePayload? _normaliseAndValidate(SharePayload p) {
  final lower = p.listId.toLowerCase();
  if (!isPlausibleListId(lower)) return null;
  return SharePayload(listId: lower, inviteToken: p.inviteToken);
}
