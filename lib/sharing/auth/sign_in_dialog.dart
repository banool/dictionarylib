import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

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

/// Sign-in dialog with Apple / Google / Facebook buttons.
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
          if (ctx.mounted) Navigator.of(ctx).pop(session);
        } on ProviderSignInException catch (e) {
          // Platform SDK rejection (cancel, missing credential, etc.).
          // The wrapper has already logged the underlying error.
          setLocal(() {
            inflight = null;
            error = _localiseProviderError(l, e.kind);
          });
        } on SyncException catch (e) {
          // Server rejected the provider credential.
          printAndLog('sign-in (${provider.name}): server rejected '
              '(${e.kind}): ${e.message}');
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
            const SizedBox(height: 16),
            if (sharing.auth.isProviderAvailable(AuthProvider.apple))
              _ProviderButton(
                label: l.signInWithApple,
                icon: Icons.apple,
                onPressed:
                    inflight == null ? () => attempt(AuthProvider.apple) : null,
                inflight: inflight == AuthProvider.apple,
              ),
            if (sharing.auth.isProviderAvailable(AuthProvider.google)) ...[
              const SizedBox(height: 8),
              _ProviderButton(
                label: l.signInWithGoogle,
                iconWidget: const _GoogleLogo(),
                onPressed: inflight == null
                    ? () => attempt(AuthProvider.google)
                    : null,
                inflight: inflight == AuthProvider.google,
              ),
            ],
            if (sharing.auth.isProviderAvailable(AuthProvider.facebook)) ...[
              const SizedBox(height: 8),
              _ProviderButton(
                label: l.signInWithFacebook,
                icon: Icons.facebook,
                onPressed: inflight == null
                    ? () => attempt(AuthProvider.facebook)
                    : null,
                inflight: inflight == AuthProvider.facebook,
              ),
            ],
            // Test-only affordance. Visible only in debug builds AND
            // when the consuming app configures [TestSignInConfig].
            // Sends to the worker's gated test-provider path —
            // production deploys reject this even if a release build
            // somehow tried.
            if (kDebugMode && (sharing.config.testSignIn?.enabled ?? false)) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              _ProviderButton(
                label: l.signInTestUserButton,
                icon: Icons.bug_report,
                onPressed: inflight == null
                    ? () => _attemptTestSignIn(ctx, sharing.config.testSignIn!,
                        (err) => setLocal(() => error = err))
                    : null,
                inflight: inflight == AuthProvider.test,
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
            child: Text(l.alertCancel),
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

  /// Monochrome icon for providers whose mark is a simple glyph (Apple,
  /// Facebook). Mutually exclusive with [iconWidget].
  final IconData? icon;

  /// A bespoke leading widget for providers that need their own branded mark
  /// (e.g. Google's multi-colour "G"). Takes precedence over [icon].
  final Widget? iconWidget;
  final VoidCallback? onPressed;
  final bool inflight;

  const _ProviderButton({
    required this.label,
    this.icon,
    this.iconWidget,
    required this.onPressed,
    required this.inflight,
  }) : assert(icon != null || iconWidget != null);

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonalIcon(
      onPressed: onPressed,
      icon: inflight
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : (iconWidget ?? Icon(icon)),
      label: Text(label),
    );
  }
}

/// Google's official multi-colour "G" mark, sat on the white rounded tile its
/// branding guidelines call for, so the Sign in with Google button uses the
/// real logo rather than a generic letter glyph.
class _GoogleLogo extends StatelessWidget {
  const _GoogleLogo();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.all(1),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Image.asset(
        'assets/brand/google-g.png',
        package: 'dictionarylib',
        fit: BoxFit.contain,
      ),
    );
  }
}
