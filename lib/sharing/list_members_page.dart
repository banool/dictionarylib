import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../common.dart';
import '../globals.dart';
import '../hearth.dart';
import '../l10n/app_localizations.dart';
import '../lists_service.dart';
import '../sharing/sync_api.dart';
import 'synced_entry_list.dart';

/// "Members" page for a shared list. Renders the creator + each
/// editor with their display name, and surfaces owner-only actions
/// (invite, remove editor) and editor-self actions (leave).
///
/// Members data is sourced from `meta.cachedMembers`, refreshed by
/// every /sync response. The page subscribes to [sharing] so a
/// background sync that lands a new member updates the list without
/// the user having to refresh manually.
///
/// A member's display name only refreshes when *that member* does a
/// /sync — the server's `refreshActorDisplayName` updates the cached
/// name from the actor's own JWT claim. So if a co-editor renames
/// themselves at Google / Facebook and doesn't open the app, their
/// name here stays stale until they do. This is intentional: avoids
/// a round-trip per member on every load, and means historical
/// `actorDisplayName` snapshots in the op log keep their git-commit-
/// author-style semantics. To force a refresh, ask the member to
/// open the app.
class ListMembersPage extends StatefulWidget {
  final SyncedEntryList list;
  const ListMembersPage({super.key, required this.list});

  @override
  State<ListMembersPage> createState() => _ListMembersPageState();
}

class _ListMembersPageState extends State<ListMembersPage> {
  bool _invitingInflight = false;
  String? _generalError;

  @override
  void initState() {
    super.initState();
    sharing.addListener(_onSharingChanged);
  }

  @override
  void dispose() {
    sharing.removeListener(_onSharingChanged);
    super.dispose();
  }

  void _onSharingChanged() {
    if (mounted) setState(() {});
  }

  // Viewer role is inferred from the list's local role — owner-mode
  // wrappers belong to the owner; editor-mode wrappers belong to an
  // editor. The viewer's own userId is taken from the persisted
  // session (echoed by the worker at sign-in); used to render
  // "(you)" on the viewer's row.
  bool get _viewerIsOwner => widget.list.meta.role == ListRole.owner;
  bool get _viewerIsEditor => widget.list.meta.role == ListRole.editor;
  String get _viewerUserId => sharing.auth.store.current?.userId ?? '';

  Future<void> _invite() async {
    if (!sharing.isEnabled) return;
    setState(() {
      _invitingInflight = true;
      _generalError = null;
    });
    try {
      final invite = await sharing.engine.createInvite(widget.list.listId);
      final url = sharing.config.inviteUrlFor(widget.list.listId, invite.token);
      if (mounted) await _showInviteDialog(url);
    } on SyncException catch (e) {
      if (mounted) {
        final l = DictLibLocalizations.of(context)!;
        setState(() => _generalError = localisedSyncErrorSimple(
            context, e, l.inviteEditorFailed(e.message)));
      }
    } on StateError {
      // Session vanished mid-tap (engine throws when there's no current
      // session). Surface as unauthorized so the user knows to sign in.
      if (mounted) {
        setState(() => _generalError =
            DictLibLocalizations.of(context)!.shareErrorUnauthorized);
      }
    } finally {
      if (mounted) setState(() => _invitingInflight = false);
    }
  }

  Future<void> _showInviteDialog(String url) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        final l = DictLibLocalizations.of(ctx)!;
        return AlertDialog(
          title: Text(l.inviteEditorDialogTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.inviteEditorDialogBody),
              const SizedBox(height: 12),
              SelectableText(url,
                  style:
                      const TextStyle(fontFamily: 'monospace', fontSize: 13)),
              const SizedBox(height: 8),
              Text(l.inviteEditorExpiresIn,
                  style:
                      TextStyle(color: Theme.of(ctx).hintColor, fontSize: 12)),
            ],
          ),
          actions: [
            TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: url));
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                      content: Text(
                          DictLibLocalizations.of(ctx)!.shareLinkCopiedSnack)));
                }
              },
              icon: const Icon(Icons.copy),
              label: Text(l.shareLinkCopyButton),
            ),
            Builder(builder: (btnCtx) {
              return TextButton.icon(
                onPressed: () async {
                  await Share.share(url,
                      sharePositionOrigin: sharePositionOrigin(btnCtx));
                },
                icon: const Icon(Icons.share),
                label: Text(l.shareLinkShareButton),
              );
            }),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(l.shareLinkDoneButton),
            ),
          ],
        );
      },
    );
  }

  Future<void> _removeEditor(EditorRef editor) async {
    final l = DictLibLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.membersPageRemoveEditorConfirmTitle(
            editor.displayName.isEmpty ? editor.userId : editor.displayName)),
        content: Text(l.membersPageRemoveEditorConfirmBody),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l.alertCancel)),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(l.membersPageRemoveEditor)),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await sharing.engine.removeEditor(widget.list.listId, editor.userId);
    } on SyncException catch (e) {
      if (mounted) {
        final ll = DictLibLocalizations.of(context)!;
        setState(() => _generalError = localisedSyncErrorSimple(
            context, e, ll.inviteEditorFailed(e.message)));
      }
    } on StateError {
      if (mounted) {
        setState(() => _generalError =
            DictLibLocalizations.of(context)!.shareErrorUnauthorized);
      }
    }
  }

  Future<void> _leaveList() async {
    final l = DictLibLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.membersPageLeaveConfirmTitle),
        content: Text(l.membersPageLeaveConfirmBody),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l.alertCancel)),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(l.membersPageLeaveButton)),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await sharing.engine.leaveAsEditor(widget.list.listId);
    } on SyncException catch (e) {
      if (mounted) {
        final ll = DictLibLocalizations.of(context)!;
        setState(() => _generalError = localisedSyncErrorSimple(
            context, e, ll.leaveListFailed(e.message)));
      }
      return;
    } on StateError {
      if (mounted) {
        setState(() => _generalError =
            DictLibLocalizations.of(context)!.shareErrorUnauthorized);
      }
      return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l = DictLibLocalizations.of(context)!;
    final members = widget.list.meta.cachedMembers;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.membersPageTitle),
            Text(
              widget.list.meta.displayName,
              style: Theme.of(context).textTheme.labelSmall,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          HearthSectionLabel(
            l.membersPageCreator,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          ),
          if (members != null)
            _buildMemberTile(members.owner)
          else
            const ListTile(dense: true, title: Text('—')),
          HearthSectionLabel(
            l.membersPageEditors,
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
            trailing: _viewerIsOwner
                ? FilledButton.icon(
                    onPressed: _invitingInflight ? null : _invite,
                    icon: _invitingInflight
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.person_add),
                    label: Text(l.shareLinkInviteEditorButton),
                  )
                : null,
          ),
          if (members == null || members.editors.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(l.membersPageNoEditors,
                  style: TextStyle(color: Theme.of(context).hintColor)),
            )
          else
            for (final e in members.editors) _buildEditorTile(l, e),
          if (_generalError != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_generalError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          if (_viewerIsEditor) ...[
            const Divider(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: _leaveList,
                  icon: const Icon(Icons.logout),
                  label: Text(l.membersPageLeaveButton),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMemberTile(MemberRef member) {
    final l = DictLibLocalizations.of(context)!;
    final base = member.displayName.isEmpty ? member.userId : member.displayName;
    final name = member.userId == _viewerUserId && _viewerUserId.isNotEmpty
        ? l.membersPageNameYou(base)
        : base;
    return ListTile(
      leading: _avatar(name),
      title: Text(name),
    );
  }

  Widget _avatar(String name) {
    final cs = Theme.of(context).colorScheme;
    return CircleAvatar(
      backgroundColor: cs.primaryContainer,
      child: Text(_initial(name),
          style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: cs.onPrimaryContainer)),
    );
  }

  Widget _buildEditorTile(DictLibLocalizations l, EditorRef editor) {
    final base = editor.displayName.isEmpty ? editor.userId : editor.displayName;
    final isViewer = editor.userId == _viewerUserId && _viewerUserId.isNotEmpty;
    final name = isViewer ? l.membersPageNameYou(base) : base;
    final addedByName = _resolveAddedByName(editor);
    return ListTile(
      leading: _avatar(name),
      title: Text(name),
      subtitle: addedByName.isEmpty
          ? null
          : Text(l.membersPageEditorAddedBy(addedByName)),
      trailing: _viewerIsOwner && !isViewer
          ? IconButton(
              icon: const Icon(Icons.person_remove_outlined),
              tooltip: l.membersPageRemoveEditor,
              onPressed: () => _removeEditor(editor),
            )
          : null,
    );
  }

  /// Resolve `editor.addedBy` (a `provider:sub` user id) to a display
  /// name by checking the cached members. Falls back to a truncated
  /// id when we don't recognise it.
  String _resolveAddedByName(EditorRef editor) {
    final members = widget.list.meta.cachedMembers;
    if (members == null) return '';
    if (members.owner.userId == editor.addedBy) {
      return members.owner.displayName;
    }
    for (final e in members.editors) {
      if (e.userId == editor.addedBy) return e.displayName;
    }
    return editor.addedBy;
  }

  String _initial(String name) {
    if (name.isEmpty) return '?';
    final code = name.runes.first;
    return String.fromCharCode(code).toUpperCase();
  }
}

