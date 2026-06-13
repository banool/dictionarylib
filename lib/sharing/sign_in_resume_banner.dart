import 'dart:async';

import 'package:flutter/material.dart';

import '../globals.dart';
import '../l10n/app_localizations.dart';
import 'auth/sign_in_dialog.dart';
import 'synced_entry_list.dart';

/// "Sign in to push your edits" banner shared between the lists overview
/// (global, shown whenever the user has at least one editable list with
/// no current session) and the per-list page (mirrors the global one
/// when the user is actively editing).
///
/// Visibility logic: returns a [SizedBox.shrink] when there's no session
/// to nudge about — when [sharing] is null, when the user is already
/// signed in, or when [lists] is empty. The "pending edits" framing
/// flips on if any list in [lists] has queued ops; otherwise the
/// nudge is the idle "sign in to sync across devices" copy.
///
/// Pressing the action opens the sign-in dialog with the
/// [DictLibLocalizations.signInDialogContextResume] framing; on a
/// successful sign-in the engine's `syncAll` is kicked fire-and-forget
/// so any queued ops drain immediately.
class SignInResumeBanner extends StatefulWidget {
  /// The lists this banner is reacting to. Typically every editable
  /// list (overview-page case) or a single list (per-list case). Each
  /// must be non-orphaned — the caller filters.
  final Iterable<SyncedEntryList> lists;

  const SignInResumeBanner({super.key, required this.lists});

  @override
  State<SignInResumeBanner> createState() => _SignInResumeBannerState();
}

class _SignInResumeBannerState extends State<SignInResumeBanner> {
  @override
  Widget build(BuildContext context) {
    if (!sharing.isEnabled) return const SizedBox.shrink();
    if (sharing.auth.store.current != null) return const SizedBox.shrink();
    final lists = widget.lists.toList();
    if (lists.isEmpty) return const SizedBox.shrink();
    final hasPending = lists.any((l) => l.meta.pendingOps.isNotEmpty);
    final l = DictLibLocalizations.of(context)!;
    // Always use the neutral "you have unsynced edits" copy when there are
    // pending ops. The old single-list branch claimed "your session
    // expired", which is misleading after a deliberate sign-out (the common
    // case) — the session didn't expire, the user signed out. The neutral
    // copy is correct in both situations.
    final message = hasPending
        ? l.overviewResumeSignInWithPending
        : l.overviewResumeSignInIdle;
    return MaterialBanner(
      content: Text(message),
      leading: Icon(
        hasPending ? Icons.cloud_upload : Icons.cloud_off,
        color: Theme.of(context).colorScheme.primary,
      ),
      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      actions: [
        TextButton(
          onPressed: () async {
            final session = await showSignInDialog(context,
                contextMessage: l.signInDialogContextResume);
            // Kick a sync fire-and-forget on success; the banner
            // listens for the auth state change via `Sharing`'s
            // bumpState (which the auth store forwards through), so
            // we don't need a local setState here — the rebuild
            // propagates automatically.
            if (session != null) unawaited(sharing.engine.syncAll());
            if (mounted) setState(() {});
          },
          child: Text(l.overviewResumeSignInButton),
        ),
      ],
    );
  }
}
