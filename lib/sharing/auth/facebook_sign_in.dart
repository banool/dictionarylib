import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';

import '../../common.dart';
import 'sign_in_exception.dart';

/// Trigger Facebook Limited Login and return the OpenID Connect ID
/// token — a signed JWT the Worker verifies offline against Facebook's
/// JWKS, exactly like Apple/Google. The token is exposed by the plugin
/// via `result.accessToken?.tokenString` despite the field name.
///
/// Limited Login is requested explicitly so the SDK can't silently fall
/// back to a classic Graph login when ATT tracking is granted — the
/// Worker only verifies OIDC tokens and a classic Graph access token
/// would always fail verification server-side. The token type is
/// checked too: the Android plugin (7.x) ignores the tracking request
/// entirely and only ever returns classic tokens, which is why
/// [AuthService.isProviderAvailable] doesn't offer Facebook on Android;
/// this guard catches any other path that yields a non-OIDC token.
///
/// Throws [ProviderSignInException] on cancellation or failure.
Future<String> signInWithFacebook() async {
  LoginResult result;
  try {
    // No extra permissions — Facebook's default profile scope is enough
    // to give us a stable user_id, and the app does not collect any
    // user info beyond that.
    result = await FacebookAuth.instance.login(
      permissions: const [],
      loginTracking: LoginTracking.limited,
    );
  } catch (e) {
    printAndLog('facebook sign-in: failed ($e)');
    throw ProviderSignInException(SignInErrorKind.failed);
  }
  switch (result.status) {
    case LoginStatus.success:
      final accessToken = result.accessToken;
      final token = accessToken?.tokenString;
      if (accessToken == null || token == null || token.isEmpty) {
        throw ProviderSignInException(SignInErrorKind.noCredential);
      }
      if (accessToken is! LimitedToken) {
        // A classic Graph token reached us despite requesting Limited
        // Login; the server can't verify it, so fail fast with a clear
        // signal instead of a confusing server-side rejection.
        printAndLog('facebook sign-in: got ${accessToken.runtimeType}, '
            'expected a Limited Login OIDC token');
        throw ProviderSignInException(SignInErrorKind.notConfigured);
      }
      return token;
    case LoginStatus.cancelled:
      throw ProviderSignInException(SignInErrorKind.cancelled);
    case LoginStatus.failed:
    case LoginStatus.operationInProgress:
      printAndLog('facebook sign-in: ${result.status} (${result.message})');
      throw ProviderSignInException(SignInErrorKind.failed);
  }
}

/// Sign out of Facebook client-side. Doesn't deauth the app from the
/// user's Facebook session; just clears the cached login so the next
/// call to [signInWithFacebook] prompts again.
Future<void> signOutOfFacebook() async {
  try {
    await FacebookAuth.instance.logOut();
  } catch (_) {
    // Best-effort — clearing our session token is what matters.
  }
}
