import 'package:flutter/material.dart';

import '../common.dart';
import '../globals.dart';
import '../l10n/app_localizations.dart';
import '../lists_service.dart';
import '../page_entry_list.dart';
import 'auth/auth_store.dart';
import 'auth/sign_in_dialog.dart';
import 'sync_api.dart';
import 'synced_entry_list.dart';

/// Landing page shown when the user taps a share URL.
///
/// Two flavours:
/// - **Subscribe** (no `?invite=<token>` on the URL): subscribes to the
///   list anonymously and routes to the regular entry list page.
/// - **Accept invite** (with token): prompts for sign-in if needed,
///   then calls `acceptInvite` to register the caller as an editor.
class SharedListLandingPage extends StatefulWidget {
  final String listId;

  /// Set when the inbound URL carried `?invite=<token>` — the page
  /// branches into the "sign in to accept" flow instead of an anonymous
  /// subscribe.
  final String? inviteToken;
  final NavigateToEntryPageFn navigateToEntryPage;

  const SharedListLandingPage({
    super.key,
    required this.listId,
    required this.navigateToEntryPage,
    this.inviteToken,
  });

  @override
  State<SharedListLandingPage> createState() => _SharedListLandingPageState();
}

class _SharedListLandingPageState extends State<SharedListLandingPage> {
  Future<SyncedEntryList>? _future;
  String? _displayName; // Best-effort preview for the invite copy.

  /// Set once we've handed off to the destination page via
  /// `pushReplacement`. Guards the FutureBuilder against a second
  /// rebuild (theme change, locale change) scheduling another
  /// post-frame navigation after the page is detached.
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    // Auth state may still be hydrating from secure storage when this
    // page mounts on cold start from an invite link. Rebuild when the
    // session restores so the "Sign in to accept" / "Accept invite"
    // copy switches without the user having to do anything.
    sharing.auth.store.addListener(_onAuthChanged);
    if (widget.inviteToken == null) {
      _future = _subscribe();
    } else {
      _bootstrapInvitePreview();
    }
  }

  @override
  void dispose() {
    sharing.auth.store.removeListener(_onAuthChanged);
    super.dispose();
  }

  void _onAuthChanged() {
    if (mounted) setState(() {});
  }

  Future<SyncedEntryList> _subscribe() async {
    // Unreachable from real UI — the landing page only mounts when
    // sharing is configured. Assert so we don't carry an English
    // message all the way to the user.
    assert(sharing.isEnabled,
        'SharedListLandingPage mounted without sharing setup');
    final result = await sharing.engine.subscribe(widget.listId);
    if (result == null) {
      // The list was orphaned mid-subscribe (e.g., owner deleted it
      // between our GET and our local install). `gone` is handled by
      // [localisedSyncError] / the invite-error branch, so the message
      // string itself is never user-visible.
      throw SyncException(SyncErrorKind.gone, '');
    }
    return result;
  }

  /// Fetch the public subscriber payload just to learn the list's
  /// display name, so the invite-accept UI can say "join Animals
  /// 101" rather than just "join a list". Best-effort; on failure
  /// the UI falls back to a generic phrasing.
  Future<void> _bootstrapInvitePreview() async {
    if (!sharing.isEnabled) return;
    try {
      final result = await sharing.api.getList(widget.listId);
      if (result is FetchOk && mounted) {
        setState(() => _displayName = result.list.displayName);
      }
    } catch (_) {/* fall through to the unknown-list copy */}
  }

  Future<void> _acceptInvite() async {
    if (!sharing.isEnabled) return;
    final l = DictLibLocalizations.of(context)!;

    // Ensure we're signed in.
    AuthSession? session = sharing.auth.store.current;
    if (session == null) {
      session = await showSignInDialog(context,
          contextMessage: l.signInDialogContextInvite);
      // The sign-in dialog is an async gap: the user may have backed out of
      // this page (or it was torn down by a rebuild) while it was up. Bail
      // before touching state if we're no longer mounted or the sign-in
      // didn't produce a session.
      if (!mounted || session == null) return;
    }

    setState(() {
      _future = _doAccept();
    });
  }

  Future<SyncedEntryList> _doAccept() async {
    // Same unreachable case as in [_subscribe]; assert rather than
    // surfacing an English message through the error builder.
    assert(sharing.isEnabled,
        'SharedListLandingPage mounted without sharing setup');
    return await sharing.engine.acceptInvite(
      listId: widget.listId,
      token: widget.inviteToken!,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = DictLibLocalizations.of(context)!;
    final isInvite = widget.inviteToken != null;
    return Scaffold(
      appBar: AppBar(
          title: Text(isInvite
              ? l.acceptInviteLandingTitle
              : l.sharedListLandingLoading)),
      body: _future == null
          ? _buildInvitePrompt(l)
          : FutureBuilder<SyncedEntryList>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return Center(
                      child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 16),
                        Text(isInvite
                            ? l.acceptInviteLandingAccepting
                            : l.sharedListLandingLoading),
                      ]));
                }
                if (snap.hasError) return _buildError(l, snap.error, isInvite);
                final list = snap.data!;
                // Defer the swap to after the build so we don't
                // navigate during it. Guarded by `_navigated` so a
                // FutureBuilder rebuild between the future completing
                // and the post-frame firing doesn't schedule a second
                // pushReplacement on the unmounted state.
                if (!_navigated) {
                  _navigated = true;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    Navigator.of(context).pushReplacement(MaterialPageRoute(
                      builder: (_) => EntryListPage(
                        entryList: list,
                        navigateToEntryPage: widget.navigateToEntryPage,
                      ),
                    ));
                  });
                }
                return const Center(child: CircularProgressIndicator());
              },
            ),
    );
  }

  Widget _buildInvitePrompt(DictLibLocalizations l) {
    final name = _displayName;
    final signedIn = sharing.auth.store.current != null;
    // If the viewer already owns or edits this list (tapped their own
    // invite link, or a link they accepted earlier), frame the prompt
    // as "open the list" rather than asking them to accept an invite
    // they don't need.
    final existing = sharing.lists.get(widget.listId);
    final alreadyMember = existing != null &&
        (existing.meta.role == ListRole.owner ||
            existing.meta.role == ListRole.editor);

    final String body;
    final String buttonLabel;
    final VoidCallback onPressed;
    if (alreadyMember) {
      body = existing.meta.role == ListRole.owner
          ? l.acceptInviteLandingAlreadyOwner(existing.meta.displayName)
          : l.acceptInviteLandingAlreadyEditor(existing.meta.displayName);
      buttonLabel = l.acceptInviteLandingOpenList;
      onPressed = () => _openExisting(existing);
    } else if (signedIn) {
      // Already signed in — frame as "Accept invite" rather than
      // "Sign in to accept", and use copy that reflects the existing
      // session.
      body = name == null
          ? l.acceptInviteLandingUnknownList
          : l.acceptInviteLandingSignedIn(name);
      buttonLabel = l.acceptInviteLandingAcceptButton;
      onPressed = _acceptInvite;
    } else {
      body = name == null
          ? l.acceptInviteLandingUnknownList
          : l.acceptInviteLandingSignedOut(name);
      buttonLabel = l.acceptInviteLandingSignInButton;
      onPressed = _acceptInvite;
    }
    return _state(
      icon: alreadyMember ? Icons.playlist_add_check : Icons.group_add,
      heading: name,
      message: body,
      buttonLabel: buttonLabel,
      onPressed: onPressed,
    );
  }

  /// Shared centred "icon tile + heading + message + CTA" layout used by the
  /// invite-prompt and error states. Colours come from the active theme.
  Widget _state({
    required IconData icon,
    String? heading,
    required String message,
    required String buttonLabel,
    required VoidCallback onPressed,
  }) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(icon, size: 34, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 18),
            if (heading != null) ...[
              Text(heading,
                  textAlign: TextAlign.center,
                  style: tt.titleLarge?.copyWith(fontSize: 22)),
              const SizedBox(height: 8),
            ],
            Text(message,
                textAlign: TextAlign.center,
                style: tt.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant, height: 1.5)),
            const SizedBox(height: 22),
            FilledButton(onPressed: onPressed, child: Text(buttonLabel)),
          ],
        ),
      ),
    );
  }

  void _openExisting(SyncedEntryList list) {
    if (_navigated) return;
    _navigated = true;
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => EntryListPage(
        entryList: list,
        navigateToEntryPage: widget.navigateToEntryPage,
      ),
    ));
  }

  Widget _buildError(DictLibLocalizations l, Object? err, bool isInvite) {
    String message;
    if (err is SyncException) {
      // 403/404/410 on an invite typically mean expired or used.
      if (isInvite &&
          (err.kind == SyncErrorKind.forbidden ||
              err.kind == SyncErrorKind.notFound ||
              err.kind == SyncErrorKind.gone)) {
        message = l.acceptInviteLandingExpired;
      } else if (isInvite) {
        message = l.acceptInviteLandingFailed(err.message);
      } else {
        message = localisedSyncError(context, err,
            notFoundMessage: l.sharedListLandingNotFound,
            unknownMessage: err.message);
      }
    } else {
      message = l.sharedListLandingDefaultError;
    }
    return _state(
      icon: isInvite ? Icons.link_off : Icons.error_outline,
      message: message,
      buttonLabel: l.sharedListLandingTryAgain,
      onPressed: () => setState(() {
        _future = widget.inviteToken == null ? _subscribe() : _doAccept();
      }),
    );
  }
}
