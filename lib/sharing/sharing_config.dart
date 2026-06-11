/// Configuration for shared lists. Each consuming app constructs one of these
/// in `main()` and passes it to `setupSharing`.
class SharingConfig {
  /// Stable identifier for this app. Sent as the `X-App-Id` header on every
  /// API call. Must match the `APP_ID` env var of the Worker we're talking to.
  /// Examples: `auslan`, `slsl`.
  final String appId;

  /// Base URL of the share API, e.g. `https://api.auslandictionary.org`.
  /// No trailing slash.
  final String apiBaseUrl;

  /// Base URL for outbound share links — usually `https://share.<dictionary>/l`.
  /// We let the consumer override this in case the share landing page is
  /// ever hosted somewhere different from the API.
  final String shareLinkBaseUrl;

  /// Custom URL scheme registered by the app (e.g. `auslan`, `slsl`). Used
  /// when constructing in-app deep links from share URLs.
  final String urlScheme;

  /// Hostname the platform deep-link config (intent-filter / AASA) targets,
  /// e.g. `share.auslandictionary.org`. Used by the deep-link handler to
  /// recognise inbound links from this host.
  final String shareLinkHost;

  /// Human-readable app name used in user-facing share copy (e.g. the
  /// private-key backup share text). The auslan app passes "Auslan
  /// Dictionary"; slsl passes its own.
  final String appName;

  /// OAuth provider client identifiers. Required to sign in with each
  /// provider; the matching `aud` value(s) must be in the Worker's env
  /// (`APPLE_AUDIENCES`, `GOOGLE_AUDIENCES`, `FACEBOOK_APP_ID`,
  /// `MICROSOFT_CLIENT_ID`). See `dictionarylib/lists/MANUAL_SETUP.md`.
  final SharingAuthConfig auth;

  /// Optional: enables a "Test sign-in" affordance in the sign-in
  /// dialog so a developer can drive the shared-lists feature on
  /// device without creating real provider accounts.
  /// The affordance is additionally gated client-side by
  /// `kDebugMode` — release builds NEVER show it, regardless of
  /// config. Server-side, the test-provider sign-in is gated by
  /// `ENVIRONMENT !== 'production'` and a non-empty `TEST_AUTH_TOKEN`,
  /// so even a leaked debug build can't impersonate test users
  /// against production. Null disables the affordance entirely.
  final TestSignInConfig? testSignIn;

  const SharingConfig({
    required this.appId,
    required this.apiBaseUrl,
    required this.shareLinkBaseUrl,
    required this.urlScheme,
    required this.shareLinkHost,
    required this.appName,
    required this.auth,
    this.testSignIn,
  });

  /// Compose a public share URL for a given list ID. The result is what
  /// the user copies / shares with others.
  ///
  /// The listId is percent-encoded as a defensive measure even though
  /// the current generator's alphabet (base32, lowercase a-z + 2-7)
  /// has no characters that require escaping. A future generator that
  /// picks a wider alphabet would silently produce malformed URLs
  /// without this.
  String shareUrlFor(String listId) =>
      '$shareLinkBaseUrl/${Uri.encodeComponent(listId)}';

  /// Compose an invite URL — `<share base>/<listId>?invite=<token>`.
  /// The token is percent-encoded so a future change to the token
  /// alphabet (e.g. adding `+` or `=`) doesn't silently produce malformed
  /// URLs. The matching parser in [extractSharePayload] reads
  /// `uri.queryParameters` which auto-decodes.
  String inviteUrlFor(String listId, String token) =>
      '${shareUrlFor(listId)}?invite=${Uri.encodeQueryComponent(token)}';
}

/// OAuth provider client identifiers per app. Apple Sign In uses the iOS
/// bundle id natively (no per-app config), but Android / web flows need a
/// Services id; both Google and Facebook need explicit client / app ids.
class SharingAuthConfig {
  /// iOS bundle identifier used as the Apple `aud` claim on iOS Sign in
  /// with Apple. Matches one of the entries in the Worker's
  /// `APPLE_AUDIENCES` env. Required for Apple to work at all on iOS.
  final String appleBundleId;

  /// Apple Services ID used by the Android / web flow. Optional; if
  /// null, "Sign in with Apple" is hidden on platforms that need this.
  /// Configure in Apple Developer Portal → Identifiers → Services IDs.
  final String? appleServicesId;

  /// Backend redirect URI registered with the Apple Services ID for the
  /// web flow. Apple POSTs the form_post response here; the Worker
  /// 302s to an App-Link that the device routes back into the app.
  /// String-typed (not Uri) so the whole [SharingConfig] can stay a
  /// const expression in consumer apps. Null when [appleServicesId]
  /// is null.
  final String? appleRedirectUri;

  /// Google OAuth **Web application** client id, passed to `google_sign_in`
  /// as the server client id — it becomes the minted ID token's `aud`, so
  /// it must be listed in the Worker's `GOOGLE_AUDIENCES`. A Web-type id is
  /// a hard requirement on Android: `google_sign_in` v7 goes through
  /// Credential Manager, which rejects iOS/Android-type ids with a
  /// developer-console error. (iOS additionally uses the iOS client id from
  /// `GIDClientID` in Info.plist for the flow itself.) See
  /// `dictionarylib/lists/MANUAL_SETUP.md` §2.
  final String googleServerClientId;

  /// Facebook app id (numeric string). Matches the Worker's
  /// `FACEBOOK_APP_ID`.
  final String facebookAppId;

  /// Microsoft Entra (Azure AD) application (client) id. Matches the
  /// Worker's `MICROSOFT_CLIENT_ID`. Null treats Microsoft as unconfigured
  /// for this app, so the button never shows rather than failing at
  /// sign-in time. Provisioning: `dictionarylib/lists/MANUAL_SETUP.md` §4.
  final String? microsoftClientId;

  /// Android-only MSAL redirect URIs,
  /// `msauth://<android-package>/<url-encoded-base64-signature-hash>`, one
  /// per signing cert the app ships under (each registered in Azure and in
  /// the manifest — see MANUAL_SETUP §4). iOS derives its redirect URI
  /// from the bundle id and needs none of these. The sign-in wrapper picks
  /// whichever matches the running build's actual signature:
  ///
  ///   - [microsoftAndroidRedirectUri] — the Play App Signing key (what
  ///     store installs run under). Tried first in non-debug builds.
  ///   - [microsoftAndroidUploadRedirectUri] — the upload key, for
  ///     sideloaded release artifacts (e.g. the GitHub-released APK).
  ///     Tried when the Play URI doesn't match the signature.
  ///   - [microsoftAndroidDebugRedirectUri] — the local debug keystore,
  ///     tried first in `kDebugMode` so `flutter run` works untouched.
  ///
  /// With none set, Microsoft sign-in on Android fails with a localised
  /// "not configured" error and the button is hidden.
  final String? microsoftAndroidRedirectUri;

  /// See [microsoftAndroidRedirectUri].
  final String? microsoftAndroidUploadRedirectUri;

  /// See [microsoftAndroidRedirectUri].
  final String? microsoftAndroidDebugRedirectUri;

  const SharingAuthConfig({
    required this.appleBundleId,
    required this.googleServerClientId,
    required this.facebookAppId,
    this.appleServicesId,
    this.appleRedirectUri,
    this.microsoftClientId,
    this.microsoftAndroidRedirectUri,
    this.microsoftAndroidUploadRedirectUri,
    this.microsoftAndroidDebugRedirectUri,
  });
}

/// Configuration for the in-app "Test sign-in" debug affordance.
///
/// When set on the [SharingConfig], the sign-in dialog renders an
/// extra "Test sign-in" button (only in debug builds — see
/// [SharingConfig.testSignIn]) that mints a session via the worker's
/// gated test-provider path. Lets a developer drive the full
/// shared-lists feature on device or simulator without creating a
/// real provider account.
///
/// Pair with `wrangler dev --env dev` for local-only testing, or
/// with a staging deploy whose `TEST_AUTH_TOKEN` matches this value.
class TestSignInConfig {
  /// Pre-shared test-auth token. Must match the worker's
  /// `TEST_AUTH_TOKEN` env var. Empty string disables the affordance
  /// even in debug builds (treat as "configured but not enabled").
  final String testAuthToken;

  /// Default user id prefix used when the developer doesn't supply
  /// one in the dialog. Must be in the `test:<slug>` namespace —
  /// the worker rejects everything else even with a correct token.
  final String defaultUserIdPrefix;

  /// Default display name shown in the UI for the test user.
  final String defaultDisplayName;

  const TestSignInConfig({
    required this.testAuthToken,
    this.defaultUserIdPrefix = 'test:dev',
    this.defaultDisplayName = 'Dev Tester',
  });

  bool get enabled => testAuthToken.isNotEmpty;
}
