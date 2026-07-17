import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../analytics.dart';
import '../../common.dart';
import '../../globals.dart';
import '../../l10n/app_localizations.dart';
import '../../lists_service.dart';
import '../sharing_config.dart';
import '../sync_api.dart';
import 'auth_store.dart';
import 'sign_in_exception.dart';

/// Single-instance guard state. While a sign-in dialog is showing,
/// a second caller of [showSignInDialog] joins the same future rather
/// than stacking another dialog. The dialog body is a live
/// [ValueNotifier] so a second caller's [contextMessage] swaps the
/// copy in place — "tap Share → open dialog" + "deep link arrives,
/// invite landing page also wants sign-in" now end up with the invite
/// framing rather than the stale share copy. The live dialog updates
/// without rebuilding from scratch.
Future<AuthSession?>? _inflightSignIn;
final ValueNotifier<String?> _inflightContextMessage = ValueNotifier(null);

/// Sign-in dialog with Apple / Google / Microsoft / Facebook buttons.
///
/// [contextMessage] replaces the default "to share a list…" body so
/// callers can frame the dialog for the situation (accepting an
/// invite, re-authing after session expiry, etc.). Pass null to use
/// the default share-flow copy.
///
/// If a sign-in dialog is already open, the second caller awaits the
/// same future. The second caller's [contextMessage] (if non-null)
/// replaces the displayed body — last write wins — so a deep-link
/// arrival mid-share doesn't strand the user with the wrong copy.
Future<AuthSession?> showSignInDialog(BuildContext context,
    {String? contextMessage}) {
  // Web has no sign-in (every provider is unavailable — see auth_service), so
  // the provider dialog would be empty. Any flow that reaches for a session on
  // web gets a clear pointer to the mobile app instead of a dead dialog.
  if (kIsWeb) return _showWebSharingUnavailableDialog(context);
  final existing = _inflightSignIn;
  if (existing != null) {
    if (contextMessage != null) _inflightContextMessage.value = contextMessage;
    return existing;
  }
  _inflightContextMessage.value = contextMessage;
  // Wrap in an inner async closure so the `finally` clears the
  // inflight slot *before* the returned future resolves. With the
  // earlier `.whenComplete` approach there was a microtask gap during
  // which a fresh `showSignInDialog` call would attach to the
  // already-resolved future instead of opening a new dialog.
  late final Future<AuthSession?> future;
  future = (() async {
    try {
      return await _showSignInDialogImpl(context);
    } finally {
      if (identical(_inflightSignIn, future)) {
        _inflightSignIn = null;
        _inflightContextMessage.value = null;
      }
    }
  })();
  _inflightSignIn = future;
  return future;
}

/// Return the current session, or prompt sign-in and return the freshly
/// created one. Returns null if there is no session and the user cancelled
/// the dialog, OR if [context] is no longer mounted after the dialog's async
/// gap — so callers can simply `if (session == null) return;` to bail safely.
///
/// Dedupes the "get session or show the sign-in dialog, bail if unmounted"
/// preamble shared by the share / accept-invite flows. [contextMessage] frames
/// the dialog for the situation (see [showSignInDialog]).
Future<AuthSession?> ensureSession(BuildContext context,
    {String? contextMessage}) async {
  final existing = sharing.auth.store.current;
  if (existing != null) return existing;
  if (!context.mounted) return null;
  final session =
      await showSignInDialog(context, contextMessage: contextMessage);
  if (session == null || !context.mounted) return null;
  return session;
}

/// Web stand-in for the sign-in dialog: there's no web sign-in, so explain
/// that publishing/editing shared lists needs the mobile app and return null
/// (the caller treats that as "no session", same as a cancel).
Future<AuthSession?> _showWebSharingUnavailableDialog(
    BuildContext context) async {
  final l = DictLibLocalizations.of(context)!;
  final appName = sharing.isEnabled ? sharing.config.appName : 'mobile';
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l.webSharingUnavailableTitle),
      content: Text(l.webSharingUnavailableBody(appName)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(MaterialLocalizations.of(ctx).okButtonLabel),
        ),
      ],
    ),
  );
  return null;
}

Future<AuthSession?> _showSignInDialogImpl(BuildContext context) async {
  if (!sharing.isEnabled) return null;

  String? error;
  AuthProvider? inflight;

  return await showDialog<AuthSession?>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
      final l = DictLibLocalizations.of(ctx)!;

      Future<void> attempt(AuthProvider provider) async {
        setLocal(() {
          inflight = provider;
          error = null;
        });
        try {
          final session = await sharing.auth.signIn(provider);
          // Remember which provider worked so a future signed-out visit can
          // remind the user how they got in last time.
          await sharedPreferences.setString(
              KEY_LAST_AUTH_PROVIDER, provider.name);
          if (ctx.mounted) Navigator.of(ctx).pop(session);
        } on ProviderSignInException catch (e) {
          // Platform SDK rejection (cancel, missing credential, etc.).
          // The wrapper has already logged the underlying error. `kind` cleanly
          // separates a user cancel from a real error (no PII in the enum name).
          Analytics.track('sign_in_failed',
              props: {'provider': provider.name, 'reason': e.kind.name});
          setLocal(() {
            inflight = null;
            error = _localiseProviderError(l, e.kind);
          });
        } on SyncException catch (e) {
          // Server rejected the provider credential.
          printAndLog('sign-in (${provider.name}): server rejected '
              '(${e.kind}): ${e.message}');
          Analytics.track('sign_in_failed', props: {
            'provider': provider.name,
            'reason': 'server_rejected',
          });
          setLocal(() {
            inflight = null;
            error = localisedSyncError(ctx, e,
                notFoundMessage: l.signInFailed,
                unknownMessage: l.signInFailed);
          });
        } catch (e) {
          // Anything we didn't anticipate. Log the detail, show the
          // generic l10n string — we never want raw English exception
          // text in the UI.
          printAndLog('sign-in (${provider.name}): unexpected: $e');
          Analytics.track('sign_in_failed', props: {
            'provider': provider.name,
            'reason': 'unexpected',
          });
          setLocal(() {
            inflight = null;
            error = l.signInFailed;
          });
        }
      }

      return AlertDialog(
        title: Text(l.signInDialogTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ValueListenableBuilder<String?>(
              valueListenable: _inflightContextMessage,
              builder: (_, msg, __) => Text(
                msg ?? l.signInDialogBody,
                style: const TextStyle(fontSize: 13),
              ),
            ),
            if (_lastProviderHint() case final last?) ...[
              const SizedBox(height: 10),
              Text(
                l.signInLastUsedHint(last.label(l)),
                style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: 16),
            if (sharing.auth.isProviderAvailable(AuthProvider.apple))
              _ProviderButton(
                label: l.signInWithApple,
                icon: const FaIcon(FontAwesomeIcons.apple),
                onPressed:
                    inflight == null ? () => attempt(AuthProvider.apple) : null,
              ),
            if (sharing.auth.isProviderAvailable(AuthProvider.google)) ...[
              const SizedBox(height: 8),
              _ProviderButton(
                label: l.signInWithGoogle,
                icon: const FaIcon(FontAwesomeIcons.google),
                onPressed: inflight == null
                    ? () => attempt(AuthProvider.google)
                    : null,
              ),
            ],
            if (sharing.auth.isProviderAvailable(AuthProvider.microsoft)) ...[
              const SizedBox(height: 8),
              _ProviderButton(
                label: l.signInWithMicrosoft,
                icon: const FaIcon(FontAwesomeIcons.microsoft),
                onPressed: inflight == null
                    ? () => attempt(AuthProvider.microsoft)
                    : null,
              ),
            ],
            if (sharing.auth.isProviderAvailable(AuthProvider.facebook)) ...[
              const SizedBox(height: 8),
              _ProviderButton(
                label: l.signInWithFacebook,
                icon: const FaIcon(FontAwesomeIcons.facebook),
                onPressed: inflight == null
                    ? () => attempt(AuthProvider.facebook)
                    : null,
              ),
            ],
            // Test-only affordance. Visible only in debug builds AND
            // when the consuming app configures [TestSignInConfig].
            // Sends to the worker's gated test-provider path —
            // production deploys reject this even if a release build
            // somehow tried.
            if (kDebugMode &&
                (sharing.config.testSignIn?.enabled ?? false)) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              _ProviderButton(
                label: l.signInTestUserButton,
                icon: const Icon(Icons.bug_report),
                onPressed: inflight == null
                    ? () => _attemptTestSignIn(ctx, sharing.config.testSignIn!,
                        (err) => setLocal(() => error = err))
                    : null,
              ),
            ],
            if (error != null) ...[
              const SizedBox(height: 12),
              Text(error!,
                  style: TextStyle(
                      color: Theme.of(ctx).colorScheme.error, fontSize: 13)),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed:
                inflight != null ? null : () => Navigator.of(ctx).pop(null),
            // While a sign-in is finalising (the in-app browser has returned but
            // we're still completing), turn Cancel into a spinner rather than
            // hiding the provider's logo. Disabled meanwhile so a stray tap
            // can't tear down the in-flight request.
            child: inflight != null ? buttonSpinner(ctx) : Text(l.alertCancel),
          ),
        ],
      );
    }),
  );
}

/// Debug-only: prompt for a test user id + name, then mint a session
/// via the worker's gated test provider. Visible only when both
/// `kDebugMode` is true and [TestSignInConfig.enabled] is true.
Future<void> _attemptTestSignIn(
  BuildContext context,
  TestSignInConfig cfg,
  void Function(String?) setError,
) async {
  if (!sharing.isEnabled) return;
  final l = DictLibLocalizations.of(context)!;
  final userIdCtl = TextEditingController(text: cfg.defaultUserIdPrefix);
  final displayNameCtl = TextEditingController(text: cfg.defaultDisplayName);
  try {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.signInTestPromptTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l.signInTestPromptBody, style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 12),
            TextField(
              controller: userIdCtl,
              decoration: InputDecoration(labelText: l.signInTestUserIdLabel),
              autocorrect: false,
            ),
            TextField(
              controller: displayNameCtl,
              decoration:
                  InputDecoration(labelText: l.signInTestDisplayNameLabel),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l.alertCancel)),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(l.signInTestPromptConfirm)),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final session = await sharing.auth.signInWithTestToken(
        testAuthToken: cfg.testAuthToken,
        userId: userIdCtl.text.trim(),
        displayName: displayNameCtl.text.trim().isEmpty
            ? null
            : displayNameCtl.text.trim(),
      );
      if (context.mounted) Navigator.of(context).pop(session);
    } on SyncException catch (e) {
      setError(localisedSyncError(context, e,
          notFoundMessage: l.signInFailed, unknownMessage: e.message));
    } catch (e) {
      printAndLog('test sign-in: unexpected: $e');
      setError(l.signInFailed);
    }
  } finally {
    disposeAfterFrame(userIdCtl);
    disposeAfterFrame(displayNameCtl);
  }
}

/// The provider the user last successfully signed in with, or null if there's
/// no record (or it was the debug-only test provider, which we never surface).
/// A provider that is no longer offered (killswitched or platform-hidden) is
/// also suppressed — a hint naming a provider with no button is just
/// confusing.
AuthProvider? _lastProviderHint() {
  final name = sharedPreferences.getString(KEY_LAST_AUTH_PROVIDER);
  if (name == null) return null;
  for (final p in AuthProvider.values) {
    if (p.name == name &&
        p != AuthProvider.test &&
        sharing.auth.isProviderAvailable(p)) {
      return p;
    }
  }
  return null;
}

String _localiseProviderError(DictLibLocalizations l, SignInErrorKind kind) {
  switch (kind) {
    case SignInErrorKind.cancelled:
      return l.signInCancelled;
    case SignInErrorKind.notConfigured:
      return l.signInProviderNotConfigured;
    case SignInErrorKind.noCredential:
      return l.signInProviderNoCredential;
    case SignInErrorKind.failed:
      return l.signInFailed;
  }
}

class _ProviderButton extends StatelessWidget {
  final String label;

  /// The provider's brand mark. Passed as a widget (an [Icon] or [FaIcon]) so
  /// each provider can use its proper glyph; it inherits the button's
  /// foreground colour and size from the ambient icon theme, so they all look
  /// consistent.
  final Widget icon;
  final VoidCallback? onPressed;

  const _ProviderButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonalIcon(
      onPressed: onPressed,
      // Left-align the icon + label instead of centring them in the
      // full-width button.
      style: FilledButton.styleFrom(alignment: Alignment.centerLeft),
      // Brand glyphs have different intrinsic widths (Apple is narrow, Google /
      // Facebook wider), which would shift each label to a different x. Pin the
      // icon into a fixed-width, centred slot so all the labels line up. The
      // logo stays put while signing in — the Cancel button shows the spinner.
      icon: SizedBox(width: 26, child: Center(child: icon)),
      label: Text(label),
    );
  }
}
