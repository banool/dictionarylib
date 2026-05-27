import 'package:google_sign_in/google_sign_in.dart';

import '../../common.dart';
import '../sharing_config.dart';
import 'sign_in_exception.dart';

/// Future of the one-shot `GoogleSignIn.instance.initialize()` call.
/// Recorded so concurrent first-time calls await the same in-flight init.
/// v7 requires initialize to complete exactly once before any other method
/// on the singleton fires.
Future<void>? _initFuture;

Future<void> _ensureInitialized(SharingAuthConfig auth) async {
  try {
    return await (_initFuture ??= GoogleSignIn.instance
        .initialize(serverClientId: auth.googleServerClientId));
  } catch (e) {
    // A failed init future is cached in `_initFuture`; clear it so the
    // next sign-in attempt can re-try initialize from scratch rather
    // than awaiting the same failed future forever.
    _initFuture = null;
    rethrow;
  }
}

/// Trigger the Google sign-in flow and return the ID token.
/// Throws [ProviderSignInException] on cancellation or failure.
Future<String> signInWithGoogle(SharingAuthConfig auth) async {
  await _ensureInitialized(auth);
  if (!GoogleSignIn.instance.supportsAuthenticate()) {
    // e.g. Web — platform expects its own embedded sign-in UI rather than
    // an app-driven `authenticate()` call.
    throw ProviderSignInException(SignInErrorKind.notConfigured);
  }
  GoogleSignInAccount account;
  try {
    account = await GoogleSignIn.instance.authenticate();
  } on GoogleSignInException catch (e) {
    final kind = e.code == GoogleSignInExceptionCode.canceled
        ? SignInErrorKind.cancelled
        : SignInErrorKind.failed;
    printAndLog('google sign-in: $kind ($e)');
    throw ProviderSignInException(kind);
  } catch (e) {
    printAndLog('google sign-in: failed ($e)');
    throw ProviderSignInException(SignInErrorKind.failed);
  }
  final token = account.authentication.idToken;
  if (token == null || token.isEmpty) {
    throw ProviderSignInException(SignInErrorKind.noCredential);
  }
  return token;
}

/// Sign out of Google client-side. Doesn't revoke the underlying
/// Google access; it just clears the cached Google sign-in so the
/// next call to [signInWithGoogle] prompts again.
///
/// We initialize first because [GoogleSignIn] requires
/// [GoogleSignIn.initialize] to have completed before any other
/// method is called — even after an app restart, when [_initFuture]
/// is null and a previously-signed-in session is still cached
/// natively. Without the init step, the platform channel call can
/// silently no-op on some platforms and the user stays signed in.
Future<void> signOutOfGoogle(SharingAuthConfig auth) async {
  try {
    await _ensureInitialized(auth);
  } catch (e) {
    // If initialize fails (e.g. no Google services on this device),
    // there's nothing useful to sign out of either — swallow.
    printAndLog('google sign-out: initialize failed, skipping ($e)');
    return;
  }
  await GoogleSignIn.instance.signOut();
}
