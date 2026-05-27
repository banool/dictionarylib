import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stores the user's session JWT in secure storage (Keychain on iOS,
/// EncryptedSharedPreferences on Android) and broadcasts changes.
///
/// One [AuthStore] per app process. UI components should listen via
/// [ChangeNotifier] so the sign-in state badge re-renders on sign in
/// and sign out.
class AuthStore extends ChangeNotifier {
  static const String _storageKey = 'shared_lists_session';

  final FlutterSecureStorage _storage;
  AuthSession? _current;
  bool _loaded = false;
  Future<void>? _loadFuture;

  AuthStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  /// Construct an [AuthStore] pre-populated with [session] and marked
  /// [loaded] — synchronous. Used in two contexts:
  ///
  ///   * Unit tests, where it skips secure storage so the test
  ///     doesn't have to await an async setup step or stub the
  ///     platform Keychain plugin.
  ///   * [Sharing.disabled], where the app didn't wire sharing in
  ///     and there's nothing to load from secure storage.
  ///
  /// The instance is otherwise indistinguishable from one that
  /// finished a real [load]; subsequent [save] / [clear] calls hit
  /// [storage] like normal. Pass `session: null` to construct an
  /// empty-but-loaded store.
  AuthStore.withSession(AuthSession? session, {FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage(),
        _current = session,
        _loaded = true;

  /// The current session, if any. Returns null before [load] has run, or
  /// after sign-out, or if the stored token has been cleared by 401
  /// handling.
  AuthSession? get current => _current;

  /// True once [load] has completed at least once. UI can show a
  /// progress placeholder while this is false on first launch.
  bool get loaded => _loaded;

  /// Read the persisted session from secure storage. Idempotent —
  /// concurrent calls share one in-flight read.
  Future<AuthSession?> load() {
    final inflight = _loadFuture;
    if (inflight != null) return inflight.then((_) => _current);
    final f = _loadOnce();
    _loadFuture = f;
    f.whenComplete(() => _loadFuture = null);
    return f;
  }

  Future<AuthSession?> _loadOnce() async {
    try {
      final raw = await _storage.read(key: _storageKey);
      if (raw == null) {
        _current = null;
      } else {
        _current =
            AuthSession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      }
    } catch (_) {
      // Corrupted blob — treat as no session and overwrite next save.
      // This also swallows `StateError` from
      // `AuthProvider.values.firstWhere(...)` in
      // [AuthSession.fromJson] when a session was persisted under a
      // provider this build no longer knows about (e.g. downgrade
      // from a build that added a new provider). Same recovery: drop
      // the unreadable session, force the user to sign in again.
      _current = null;
    }
    _loaded = true;
    notifyListeners();
    return _current;
  }

  /// Persist a freshly-signed-in session and broadcast.
  Future<void> save(AuthSession session) async {
    await _storage.write(key: _storageKey, value: jsonEncode(session.toJson()));
    _current = session;
    _loaded = true;
    notifyListeners();
  }

  /// Drop the persisted session. Used both by user-initiated sign-out and
  /// by 401 handling when the server rejects a token.
  Future<void> clear() async {
    await _storage.delete(key: _storageKey);
    _current = null;
    notifyListeners();
  }
}

/// A signed-in session — the JWT we send back to the API plus the local
/// metadata the UI needs to render "signed in as Alice via Google"
/// without having to decode the token.
class AuthSession {
  /// The session JWT issued by our Worker. Sent as `Authorization:
  /// Bearer <sessionToken>` on every write.
  final String sessionToken;

  /// Which provider the user signed in with. Display only — the server
  /// derives the canonical user id from the verified provider token.
  final AuthProvider provider;

  /// Canonical user id (`provider:sub`), echoed from the sign-in
  /// response. Stored so the UI can mark the viewer's own row in the
  /// members page with "(you)" without decoding the JWT. Empty for
  /// pre-cutover sessions persisted before the field existed; treat
  /// empty as "unknown".
  final String userId;

  /// User's display name as resolved at sign-in time. Sourced server-
  /// side via the provider (Google `name` claim, Facebook `/me?fields=name`)
  /// or the Apple first-sign-in passthrough; falls back to the
  /// server's previously-stored value in `users/<hash>.json`. Empty
  /// only when nothing has ever been captured for this user.
  final String displayName;

  /// Local timestamp of when this session was issued (`millisSinceEpoch`).
  /// We treat sessions as opaque on the client — the server is the
  /// authority on expiry — but record this so the UI can show "signed
  /// in 3 days ago".
  final int signedInAtMillis;

  const AuthSession({
    required this.sessionToken,
    required this.provider,
    required this.signedInAtMillis,
    this.userId = '',
    this.displayName = '',
  });

  Map<String, dynamic> toJson() => {
        'sessionToken': sessionToken,
        'provider': provider.name,
        'userId': userId,
        'displayName': displayName,
        'signedInAtMillis': signedInAtMillis,
      };

  factory AuthSession.fromJson(Map<String, dynamic> json) => AuthSession(
        sessionToken: json['sessionToken'] as String,
        // `firstWhere` throws `StateError` on unknown providers — the
        // catch in `AuthStore._loadOnce` swallows it and reports no
        // session, which is the right recovery for "saved a provider
        // we don't recognise".
        provider:
            AuthProvider.values.firstWhere((p) => p.name == json['provider']),
        userId: json['userId'] as String? ?? '',
        displayName: json['displayName'] as String? ?? '',
        signedInAtMillis: json['signedInAtMillis'] as int,
      );
}

enum AuthProvider {
  apple,
  google,
  facebook,

  /// Integration-test bypass — only ever set when [AuthApi.signInWithTestToken]
  /// is used (gated server-side; see RUNBOOK). Surfacing it as a distinct
  /// value lets the settings UI label the session as "Test session" instead
  /// of impersonating a real provider, which keeps debug builds honest.
  test,
}
