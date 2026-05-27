import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../common.dart';
import '../sharing_config.dart';
import 'sign_in_exception.dart';

/// Whether the host platform can run any form of Sign in with Apple.
/// Native (iOS / macOS / Android) is always true — Android uses the
/// web flow via [SharingAuthConfig.appleServicesId] +
/// [SharingAuthConfig.appleRedirectUri]; if those aren't configured,
/// the actual [signInWithApple] call will throw
/// [SignInErrorKind.notConfigured] which the dialog l10n's into a
/// graceful error.
bool appleSignInAvailable() {
  if (kIsWeb) return false;
  return Platform.isIOS || Platform.isMacOS || Platform.isAndroid;
}

/// Server-side cap on display name length. Mirrors
/// `MAX_DISPLAY_NAME_LEN` in `lists/workers/src/validation.ts`; we
/// clamp client-side too so the worker doesn't have to reject the
/// request just because Apple gave us a very long full name.
const int _maxAppleDisplayNameLen = 80;

/// Result of a successful Apple sign-in: the credential (id token) the
/// server verifies, plus the user's display name when Apple supplied
/// one.
class AppleSignInResult {
  final String idToken;

  /// Display name Apple returned on THIS sign-in attempt, after
  /// trimming and clamping to [_maxAppleDisplayNameLen]. Empty unless
  /// this is the first-ever sign-in for the Apple user (Apple only
  /// surfaces the name on the very first authorization).
  ///
  /// This is the only value safe to forward to the server: it's
  /// authoritative for "the user just told Apple their name". The
  /// server-side `users/<hash>.json` record covers the "user already
  /// has a name on file" path for subsequent sign-ins, so we don't
  /// keep a local cache of Apple's once-only name — that would risk
  /// replaying a stale name and clobbering whatever the user has
  /// updated server-side.
  final String freshName;

  const AppleSignInResult({
    required this.idToken,
    this.freshName = '',
  });
}

/// Trigger the platform's Sign in with Apple flow.
///
/// Requests the `name` scope so Apple returns `givenName` / `familyName`
/// on the FIRST sign-in. Subsequent sign-ins for the same Apple ID get
/// no name back (Apple's design); the server's `users/<hash>.json`
/// record is the persistence layer that lets the worker keep returning
/// the user's name to the client on later sign-ins.
Future<AppleSignInResult> signInWithApple(SharingAuthConfig auth) async {
  if (!appleSignInAvailable()) {
    throw ProviderSignInException(SignInErrorKind.notConfigured);
  }
  WebAuthenticationOptions? web;
  if (!kIsWeb && Platform.isAndroid) {
    if (auth.appleServicesId == null || auth.appleRedirectUri == null) {
      throw ProviderSignInException(SignInErrorKind.notConfigured);
    }
    web = WebAuthenticationOptions(
      clientId: auth.appleServicesId!,
      redirectUri: Uri.parse(auth.appleRedirectUri!),
    );
  }

  AuthorizationCredentialAppleID cred;
  try {
    cred = await SignInWithApple.getAppleIDCredential(
      scopes: const [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
      webAuthenticationOptions: web,
    );
  } on SignInWithAppleAuthorizationException catch (e) {
    // `invalidResponse` from Apple usually means the Services ID /
    // redirect URI / bundle ID config doesn't line up with what
    // Apple's authorization server expects — surface as
    // `notConfigured` so the l10n message ("provider not
    // configured") points the developer at the actual problem
    // instead of the generic "failed".
    final SignInErrorKind kind;
    switch (e.code) {
      case AuthorizationErrorCode.canceled:
        kind = SignInErrorKind.cancelled;
        break;
      case AuthorizationErrorCode.invalidResponse:
        kind = SignInErrorKind.notConfigured;
        break;
      default:
        kind = SignInErrorKind.failed;
    }
    printAndLog('apple sign-in: $kind ($e)');
    throw ProviderSignInException(kind);
  } catch (e) {
    printAndLog('apple sign-in: failed ($e)');
    throw ProviderSignInException(SignInErrorKind.failed);
  }
  final token = cred.identityToken;
  if (token == null || token.isEmpty) {
    throw ProviderSignInException(SignInErrorKind.noCredential);
  }

  // `freshName` is the name Apple just gave us on THIS attempt. It's
  // the only value the server should see — replaying any other source
  // (e.g. a local cache) on every sign-in would let a stale value
  // overwrite the server's authoritative `users/<hash>.json` record.
  final composed = _composeDisplayName(cred.givenName, cred.familyName);
  final freshName = composed.length > _maxAppleDisplayNameLen
      ? composed.substring(0, _maxAppleDisplayNameLen)
      : composed;

  return AppleSignInResult(idToken: token, freshName: freshName);
}

String _composeDisplayName(String? given, String? family) {
  final parts = <String>[
    if (given != null && given.trim().isNotEmpty) given.trim(),
    if (family != null && family.trim().isNotEmpty) family.trim(),
  ];
  return parts.join(' ');
}
