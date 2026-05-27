import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';

import '../../common.dart';
import 'sign_in_exception.dart';

/// Trigger Facebook login and return the access token (which the Worker
/// verifies via Facebook's /debug_token endpoint — Facebook isn't OIDC
/// by default, so we don't get a JWT).
///
/// Throws [ProviderSignInException] on cancellation or failure.
Future<String> signInWithFacebook() async {
  LoginResult result;
  try {
    // No extra permissions — Facebook's default profile scope is enough
    // to give us a stable user_id, and the app does not collect any
    // user info beyond that.
    result = await FacebookAuth.instance.login(permissions: const []);
  } catch (e) {
    printAndLog('facebook sign-in: failed ($e)');
    throw ProviderSignInException(SignInErrorKind.failed);
  }
  switch (result.status) {
    case LoginStatus.success:
      final token = result.accessToken?.tokenString;
      if (token == null || token.isEmpty) {
        throw ProviderSignInException(SignInErrorKind.noCredential);
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
