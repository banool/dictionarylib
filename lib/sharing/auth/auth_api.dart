import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../sharing_config.dart';
import '../sync_api.dart';
import 'auth_store.dart';

/// Thin client around the Worker's `/v1/auth/sign-in` endpoint. Takes
/// a provider credential (the token the platform SDK gave us), POSTs
/// it to the Worker, and returns the Worker-issued session JWT.
///
/// The optional `displayName` is the Apple-first-sign-in passthrough:
/// Apple gives the user's name *only* on the very first sign-in, and
/// we forward it so the server can persist it in
/// `users/<userIdHash>.json` for the JWT `name` claim. Google and
/// Facebook can leave it empty — the server pulls the name from those
/// providers directly.
///
/// Errors surface as [SyncException] — same envelope as the rest of
/// the sync API, so callers can localise via [localisedSyncError].
class AuthApi {
  final SharingConfig _config;
  final http.Client _client;
  final Duration _timeout;

  AuthApi(this._config,
      {http.Client? client, Duration timeout = const Duration(seconds: 15)})
      : _client = client ?? http.Client(),
        _timeout = timeout;

  void close() => _client.close();

  Future<AuthSession> signInWithApple({
    required String idToken,
    String? displayName,
  }) {
    return _signIn(AuthProvider.apple, {'idToken': idToken},
        displayName: displayName);
  }

  Future<AuthSession> signInWithGoogle({required String idToken}) {
    return _signIn(AuthProvider.google, {'idToken': idToken});
  }

  Future<AuthSession> signInWithFacebook({required String accessToken}) {
    return _signIn(AuthProvider.facebook, {'accessToken': accessToken});
  }

  /// Exchange a pre-shared test-auth token for a session under an
  /// arbitrary `test:<slug>` user id. Gated server-side by
  /// `ENVIRONMENT !== 'production'` AND a non-empty `TEST_AUTH_TOKEN`;
  /// production deploys reject this path even if a token leaks.
  ///
  /// Used both by integration tests (via [AuthService.signInWithTestToken])
  /// and by the in-app "Test sign-in" debug affordance — see
  /// [TestSignInConfig].
  Future<AuthSession> signInWithTestToken({
    required String testAuthToken,
    required String userId,
    String? displayName,
  }) {
    return _signIn(
        AuthProvider.test, {'testAuthToken': testAuthToken, 'userId': userId},
        displayName: displayName);
  }

  /// POST `/v1/auth/sign-in` with `{provider, ...credential, displayName?}`.
  Future<AuthSession> _signIn(
      AuthProvider provider, Map<String, String> credential,
      {String? displayName}) async {
    final url = Uri.parse('${_config.apiBaseUrl}/v1/auth/sign-in');
    final body = <String, dynamic>{
      'provider': provider.name,
      ...credential,
      if (displayName != null && displayName.isNotEmpty)
        'displayName': displayName,
    };
    http.Response resp;
    try {
      resp = await _client
          .post(url,
              headers: {
                'x-app-id': _config.appId,
                'content-type': 'application/json',
              },
              body: jsonEncode(body))
          .timeout(_timeout);
    } on TimeoutException {
      throw SyncException(SyncErrorKind.network, 'sign-in request timed out');
    } catch (e) {
      throw SyncException(SyncErrorKind.network, 'sign-in network error: $e');
    }

    if (resp.statusCode == 200) {
      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      final token = json['sessionToken'] as String;
      // The worker always populates `displayName` and `userId` on a
      // 200 response. `displayName` may be empty (provider returned
      // nothing and no prior record exists); `userId` is always the
      // canonical `provider:sub` string.
      return AuthSession(
        sessionToken: token,
        provider: provider,
        userId: json['userId'] as String? ?? '',
        displayName: json['displayName'] as String? ?? '',
        signedInAtMillis: DateTime.now().millisecondsSinceEpoch,
      );
    }
    throw SyncException.fromResponse(resp);
  }

  /// DELETE `/v1/account` — permanently delete the signed-in user's
  /// server-side data: every list they own, their editor membership on
  /// other people's lists, and the display name we store for them. The
  /// caller ([AuthService.deleteAccount]) is responsible for clearing the
  /// local session + lists afterwards.
  ///
  /// Returns normally on success; throws [SyncException] otherwise so the
  /// caller can surface a localised error and leave the local session
  /// intact for a retry.
  Future<void> deleteAccount({required String sessionToken}) async {
    final url = Uri.parse('${_config.apiBaseUrl}/v1/account');
    http.Response resp;
    try {
      resp = await _client.delete(url, headers: {
        'x-app-id': _config.appId,
        'authorization': 'Bearer $sessionToken',
      }).timeout(_timeout);
    } on TimeoutException {
      throw SyncException(
          SyncErrorKind.network, 'delete-account request timed out');
    } catch (e) {
      throw SyncException(
          SyncErrorKind.network, 'delete-account network error: $e');
    }
    if (resp.statusCode == 200) return;
    throw SyncException.fromResponse(resp);
  }
}
