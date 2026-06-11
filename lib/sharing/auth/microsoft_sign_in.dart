import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:msal_auth/msal_auth.dart';

import '../../common.dart';
import '../sharing_config.dart';
import 'sign_in_exception.dart';

/// Asset path of the MSAL Android configuration JSON. Each consuming app
/// that enables Microsoft sign-in ships this file and lists it under
/// `assets:` in its pubspec. The file carries the broker / authority
/// settings; `client_id` + `redirect_uri` are injected programmatically
/// from [SharingAuthConfig]. See `dictionarylib/lists/MANUAL_SETUP.md` §4.
const String _msalAndroidConfigAsset = 'assets/msal_config.json';

/// Scopes requested from Microsoft. We only need to authenticate the user
/// and read back their stable id + name, both of which ride in the ID
/// token. MSAL adds the OIDC `openid` + `profile` + `offline_access` scopes
/// automatically (they're reserved — passing them explicitly throws), and
/// `profile` is what populates the `name` claim. We ask for the single
/// delegated `User.Read` Graph scope — granted by default, no admin consent
/// — purely so MSAL mints a proper ID token; we never call Graph and the
/// access token it returns is discarded.
const List<String> _microsoftScopes = ['User.Read'];

/// Pick the Android MSAL redirect URI matching the build's signing cert.
/// Debug builds are signed with the local debug keystore (a different
/// signature hash than the release/Play key), so when one is configured we
/// use [SharingAuthConfig.microsoftAndroidDebugRedirectUri] in `kDebugMode`
/// and fall back to the release [SharingAuthConfig.microsoftAndroidRedirectUri]
/// otherwise. Lets `flutter run` / emulator builds sign in without swapping
/// the production value.
String? _androidRedirectUri(SharingAuthConfig auth) {
  if (kDebugMode && auth.microsoftAndroidDebugRedirectUri != null) {
    return auth.microsoftAndroidDebugRedirectUri;
  }
  return auth.microsoftAndroidRedirectUri;
}

/// Cached one-per-process MSAL client. Built lazily on first sign-in; a
/// failed creation is not cached so the next attempt retries from scratch.
SingleAccountPca? _pca;

Future<SingleAccountPca> _ensurePca(SharingAuthConfig auth) async {
  final existing = _pca;
  if (existing != null) return existing;

  final clientId = auth.microsoftClientId;
  if (clientId == null) {
    // No client id configured for this app — should be unreachable because
    // [AuthService.isProviderAvailable] hides the button, but keep the
    // wrapper total.
    throw ProviderSignInException(SignInErrorKind.notConfigured);
  }
  final androidRedirectUri = _androidRedirectUri(auth);
  if (!kIsWeb && Platform.isAndroid && androidRedirectUri == null) {
    // Android can't complete the redirect without the registered URI.
    throw ProviderSignInException(SignInErrorKind.notConfigured);
  }

  try {
    final pca = await SingleAccountPca.create(
      clientId: clientId,
      androidConfig: AndroidConfig(
        configFilePath: _msalAndroidConfigAsset,
        redirectUri: androidRedirectUri ?? '',
      ),
      // iOS derives its redirect URI from the bundle id automatically. AAD
      // (Microsoft Entra ID) covers both work/school and personal accounts
      // via the multi-tenant authority baked into the app registration.
      appleConfig: AppleConfig(
        authorityType: AuthorityType.aad,
        broker: Broker.msAuthenticator,
      ),
    );
    _pca = pca;
    return pca;
  } catch (e) {
    printAndLog('microsoft sign-in: client init failed ($e)');
    throw ProviderSignInException(SignInErrorKind.notConfigured);
  }
}

/// Trigger the native MSAL sign-in flow and return the Microsoft v2.0 ID
/// token — a signed JWT the Worker verifies offline against Microsoft's
/// JWKS, exactly like Apple/Google. Carries `sub` (the app+user pairwise
/// id) and, via the `profile` scope, `name`.
///
/// Throws [ProviderSignInException] on cancellation or failure.
Future<String> signInWithMicrosoft(SharingAuthConfig auth) async {
  final pca = await _ensurePca(auth);
  AuthenticationResult result;
  try {
    result = await pca.acquireToken(
      scopes: _microsoftScopes,
      prompt: Prompt.selectAccount,
    );
  } on MsalUserCancelException {
    throw ProviderSignInException(SignInErrorKind.cancelled);
  } on MsalException catch (e) {
    printAndLog('microsoft sign-in: failed ($e)');
    throw ProviderSignInException(SignInErrorKind.failed);
  } catch (e) {
    printAndLog('microsoft sign-in: unexpected ($e)');
    throw ProviderSignInException(SignInErrorKind.failed);
  }

  final idToken = result.idToken;
  if (idToken == null || idToken.isEmpty) {
    // MSAL only omits the ID token when the app registration has no OIDC
    // configuration — a setup error, not a user one.
    printAndLog('microsoft sign-in: no id token in result');
    throw ProviderSignInException(SignInErrorKind.noCredential);
  }
  return idToken;
}

/// Sign out of Microsoft client-side. Clears the cached MSAL account so the
/// next [signInWithMicrosoft] prompts afresh; doesn't revoke the app's
/// access on the Microsoft side.
Future<void> signOutOfMicrosoft() async {
  final pca = _pca;
  if (pca == null) return;
  try {
    await pca.signOut();
  } catch (_) {
    // Best-effort — clearing our own session token is what matters.
  }
}
