import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

import '../sharing_config.dart';
import 'apple_sign_in.dart';
import 'auth_api.dart';
import 'auth_store.dart';
import 'facebook_sign_in.dart';
import 'google_sign_in.dart';

/// Coordinates "tap a provider button → get a session" end-to-end:
/// invokes the platform SDK, exchanges the resulting provider
/// credential with the Worker, persists the session in [AuthStore].
///
/// One instance, constructed by `Sharing.setup`. UI components don't
/// touch the provider wrappers directly — they go through
/// `sharing.auth.signIn(...)`.
class AuthService {
  final SharingConfig _config;
  final AuthApi _api;
  final AuthStore _store;

  AuthService({
    required SharingConfig config,
    required AuthApi api,
    required AuthStore store,
  })  : _config = config,
        _api = api,
        _store = store;

  AuthStore get store => _store;

  /// Provider availability hint — "can the runtime physically attempt
  /// this on this platform?" Used by the dialog to hide buttons that
  /// could never work, but NOT to hide buttons whose config might just
  /// be missing. Missing config surfaces as a localised
  /// [SignInErrorKind.notConfigured] error at sign-in time, not a
  /// hidden button. Facebook on Android is the one structural
  /// exception — see the case below.
  ///
  /// Web is treated as unsupported for every provider for now. None
  /// of the SDKs we use are wired up for the browser flow, so showing
  /// buttons that always fail isn't useful. Re-enable per-provider
  /// here once the web embeds are tested.
  bool isProviderAvailable(AuthProvider provider) {
    if (kIsWeb) return false;
    switch (provider) {
      case AuthProvider.apple:
        return appleSignInAvailable();
      case AuthProvider.google:
        return true;
      case AuthProvider.facebook:
        // Facebook is Limited Login (OIDC) only — the Worker deliberately
        // has no classic Graph-token verification path. Limited Login is
        // an iOS-only Facebook SDK feature, and the Android plugin
        // ignores the tracking request and can only mint classic Graph
        // tokens, so on Android the button would always fail server-side
        // verification. Hide it there rather than offer a dead end.
        return defaultTargetPlatform != TargetPlatform.android;
      case AuthProvider.test:
        // Not selectable from the dialog — never offered to end users,
        // only available via [signInWithTestToken] for integration tests.
        return false;
    }
  }

  /// Drive the full sign-in flow for [provider]. Returns the session on
  /// success. Throws on failure; the caller is responsible for
  /// surfacing a localised error.
  Future<AuthSession> signIn(AuthProvider provider) async {
    final session = await _signInImpl(provider);
    await _store.save(session);
    return session;
  }

  Future<AuthSession> _signInImpl(AuthProvider provider) async {
    switch (provider) {
      case AuthProvider.apple:
        // Apple is the only provider that surfaces the display name
        // through the platform SDK, and ONLY on the first sign-in for
        // a given Apple ID. Forward just that fresh value — never the
        // locally-cached fallback — so the server's record can't be
        // overwritten by a stale client cache on every sign-in.
        final apple = await signInWithApple(_config.auth);
        return _api.signInWithApple(
          idToken: apple.idToken,
          displayName: apple.freshName.isEmpty ? null : apple.freshName,
        );
      case AuthProvider.google:
        return _api.signInWithGoogle(
            idToken: await signInWithGoogle(_config.auth));
      case AuthProvider.facebook:
        return _api.signInWithFacebook(accessToken: await signInWithFacebook());
      case AuthProvider.test:
        throw StateError('signIn(AuthProvider.test) — use '
            'signInWithTestToken() directly; the test provider isn\'t '
            'a user-pickable sign-in option.');
    }
  }

  /// Forget the local session and, where possible, clear the platform
  /// SDK's cached account so the next sign-in is a fresh prompt.
  ///
  /// Only the provider that issued the current session is asked to
  /// sign out — signing out of Google when the user signed in via
  /// Apple just wastes a platform-channel round-trip.
  Future<void> signOut() async {
    final session = _store.current;
    if (session == null) return;
    // Apple doesn't expose a sign-out on the device (the user manages
    // it under Settings → Apple ID); Google and Facebook do. Test
    // sessions are server-minted and have nothing to clear.
    switch (session.provider) {
      case AuthProvider.google:
        await signOutOfGoogle(_config.auth);
      case AuthProvider.facebook:
        await signOutOfFacebook();
      case AuthProvider.apple:
      case AuthProvider.test:
        break;
    }
    await _store.clear();
  }

  /// Drop the local session without touching the platform SDKs. Used
  /// when the server tells us the session is invalid (401/forbidden) —
  /// we still want the user to see "you're signed out" without an extra
  /// network call to Google/Facebook.
  Future<void> dropSessionLocally() => _store.clear();

  /// Permanently delete the signed-in user's account on the server (all
  /// owned lists, editor memberships, and the stored display name), then
  /// forget the local session + platform SDK login like a sign-out.
  ///
  /// The server call runs first: if it throws the local session is left
  /// intact, so the user can retry rather than ending up "signed out"
  /// with their data still on the server. Prefer
  /// `Sharing.deleteAccount`, which also clears the local list mirrors.
  Future<void> deleteAccount() async {
    final session = _store.current;
    if (session == null) return;
    await _api.deleteAccount(sessionToken: session.sessionToken);
    await signOut();
  }

  /// Mint a session via the worker's test sign-in path and persist it
  /// like a real sign-in. Used by:
  ///   - the in-app "Test sign-in" debug affordance (gated by
  ///     [TestSignInConfig.enabled] + `kDebugMode`),
  ///   - the smoke script + integration tests.
  ///
  /// The server rejects this path on production deploys
  /// (`ENVIRONMENT === 'production'`) and on deploys without a
  /// configured `TEST_AUTH_TOKEN`.
  ///
  /// [userId] must be in the `test:<slug>` namespace — anything else
  /// is rejected server-side.
  Future<AuthSession> signInWithTestToken({
    required String testAuthToken,
    required String userId,
    String? displayName,
  }) async {
    final session = await _api.signInWithTestToken(
        testAuthToken: testAuthToken, userId: userId, displayName: displayName);
    await _store.save(session);
    return session;
  }

  void dispose() => _api.close();
}
