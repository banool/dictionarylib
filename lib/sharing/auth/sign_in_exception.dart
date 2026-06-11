/// Failure surface for the provider sign-in wrappers
/// ([apple_sign_in.dart] / [google_sign_in.dart] / [facebook_sign_in.dart] /
/// [microsoft_sign_in.dart]).
///
/// The dialog layer maps [SignInErrorKind] to a localised string. The
/// provider wrappers must NOT include English text in the exception
/// itself — the underlying SDK error is logged via `printAndLog` and
/// dropped here.
class ProviderSignInException implements Exception {
  final SignInErrorKind kind;
  ProviderSignInException(this.kind);

  @override
  String toString() => 'ProviderSignInException($kind)';
}

enum SignInErrorKind {
  /// The user dismissed / cancelled the platform sheet.
  cancelled,

  /// The platform SDK isn't wired up on this OS (e.g. Sign in with
  /// Apple on Android without WebAuthenticationOptions). Should be
  /// unreachable from the UI — `isProviderAvailable` gates buttons —
  /// but defined so the dispatcher is total.
  notConfigured,

  /// The provider returned success but no credential we can verify.
  /// Usually means the OS-level integration is misconfigured.
  noCredential,

  /// Anything else — network failure, SDK exception, unexpected state.
  failed,
}
