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
  /// (`APPLE_AUDIENCES`, `GOOGLE_AUDIENCES`, `FACEBOOK_APP_ID`). See
  /// `dictionarylib/lists/MANUAL_SETUP.md`.
  final SharingAuthConfig auth;

  /// Optional: enables a "Test sign-in" affordance in the sign-in
  /// dialog so a developer can drive the shared-lists feature on
  /// device without creating real Apple / Google / Facebook accounts.
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

  /// Google OAuth client id used in the iOS and Android `google_sign_in`
  /// flows. Matches one of the entries in the Worker's
  /// `GOOGLE_AUDIENCES` env.
  ///
  /// On iOS, this is the **iOS client id** (`google_sign_in` uses the
  /// reversed-client-id URL scheme registered in Info.plist).
  /// On Android, this should be the **Web client id** (the package looks
  /// it up automatically from `google-services.json` if present).
  /// Setting this here is mainly for ID token `aud` purposes; the package
  /// itself reads platform configs.
  final String googleServerClientId;

  /// Facebook app id (numeric string). Matches the Worker's
  /// `FACEBOOK_APP_ID`.
  final String facebookAppId;

  const SharingAuthConfig({
    required this.appleBundleId,
    required this.googleServerClientId,
    required this.facebookAppId,
    this.appleServicesId,
    this.appleRedirectUri,
  });
}

/// Configuration for the in-app "Test sign-in" debug affordance.
///
/// When set on the [SharingConfig], the sign-in dialog renders an
/// extra "Test sign-in" button (only in debug builds — see
/// [SharingConfig.testSignIn]) that mints a session via the worker's
/// gated test-provider path. Lets a developer drive the full
/// shared-lists feature on device or simulator without creating a
/// real Apple / Google / Facebook account.
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
