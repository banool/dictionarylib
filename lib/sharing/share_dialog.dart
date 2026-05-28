import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../common.dart';
import '../entry_list.dart';
import '../globals.dart';
import '../l10n/app_localizations.dart';
import '../lists_service.dart';
import 'auth/sign_in_dialog.dart';
import 'deep_link_handler.dart';
import 'list_id.dart' show exampleListId;
import 'sync_api.dart';
import 'synced_entry_list.dart';

// Example list id surfaced as a placeholder in the subscribe-dialog
// URL hint. Exported from list_id.dart so the example shape matches
// what generateListId() actually produces (strict base32, no 0/1/8/9).

String? _validateDisplayName(BuildContext context, String s) {
  final l = DictLibLocalizations.of(context)!;
  final trimmed = s.trim();
  if (trimmed.isEmpty) return l.shareValidationRequired;
  if (trimmed.length > maxDisplayNameLen) {
    return l.shareValidationMaxLen(maxDisplayNameLen);
  }
  if (EntryList.isReservedDisplayName(trimmed)) {
    return l.shareValidationReservedName(trimmed);
  }
  return null;
}

/// Show the "Share this list" dialog and create the synced list on confirm.
/// Returns the new [SyncedEntryList] on success, null if the user cancelled.
///
/// Asks only for a display name. The list ID is generated client-side as
/// a random 12-char base32 string and never shown — the share URL is the
/// thing the user copies / sends.
Future<SyncedEntryList?> showShareDialog({
  required BuildContext context,
  required EntryList sourceList,
}) async {
  if (!sharing.isEnabled) return null;

  // Server caps entries per list — refuse client-side with a friendly
  // message rather than letting the network call surface a generic 400.
  // Checked before allocating any dialog state so the early-return
  // path doesn't have to clean up controllers.
  if (sourceList.savedVideos.length > maxEntriesPerList) {
    final l = DictLibLocalizations.of(context)!;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.shareTooManyEntriesTitle),
        content: Text(l.shareTooManyEntriesBody(
            sourceList.savedVideos.length, maxEntriesPerList)),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(), child: Text(l.alertOk)),
        ],
      ),
    );
    return null;
  }

  final displayCtl = TextEditingController(text: sourceList.getName(context));
  String? displayError;
  String? generalError;
  bool submitting = false;

  try {
    final result = await showDialog<SyncedEntryList?>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
        final l = DictLibLocalizations.of(ctx)!;
        Future<void> doShare() async {
          final displayName = displayCtl.text.trim();
          final v = _validateDisplayName(ctx, displayName);
          if (v != null) {
            setLocal(() => displayError = v);
            return;
          }

          // Ensure we have a session. If the user hasn't signed in yet
          // (or their stored session is unreachable for some reason),
          // pop the sign-in dialog and continue once they're back. Any
          // failure / cancel there aborts the share cleanly.
          var session = sharing.auth.store.current;
          if (session == null) {
            if (!ctx.mounted) return;
            session = await showSignInDialog(ctx);
            if (session == null || !ctx.mounted) return;
          }

          setLocal(() {
            submitting = true;
            displayError = null;
            generalError = null;
          });

          try {
            final synced = await listsService.shareList(
              sourceList: sourceList,
              displayName: displayName,
              sessionToken: session.sessionToken,
            );
            if (ctx.mounted) Navigator.of(ctx).pop(synced);
          } on SyncException catch (e) {
            setLocal(() {
              submitting = false;
              generalError = localisedSyncError(ctx, e,
                  notFoundMessage: e.message, unknownMessage: e.message);
            });
          }
        }

        return AlertDialog(
          title: Text(l.shareDialogTitle),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.shareDialogBody, style: const TextStyle(fontSize: 13)),
                const SizedBox(height: 16),
                TextField(
                  controller: displayCtl,
                  decoration: InputDecoration(
                    labelText: l.shareDialogDisplayNameLabel,
                    errorText: displayError,
                    helperText: l.shareDialogDisplayNameHelper,
                  ),
                  enabled: !submitting,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => doShare(),
                  onChanged: (_) {
                    if (displayError != null || generalError != null) {
                      setLocal(() {
                        displayError = null;
                        generalError = null;
                      });
                    }
                  },
                ),
                if (generalError != null) ...[
                  const SizedBox(height: 12),
                  Text(generalError!,
                      style: TextStyle(
                          color: Theme.of(ctx).colorScheme.error,
                          fontSize: 13)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: submitting ? null : () => Navigator.of(ctx).pop(null),
              child: Text(l.alertCancel),
            ),
            FilledButton(
              onPressed: submitting ? null : doShare,
              child: submitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(l.shareDialogShareButton),
            ),
          ],
        );
      }),
    );
    return result;
  } finally {
    disposeAfterFrame(displayCtl);
  }
}

/// Shown after a share succeeds, or when the user re-opens an existing
/// share via the share icon — gives the user the public URL with
/// copy/share/QR options. Returns true if the user pressed the destructive
/// "Stop sharing" button (shown only when [showUnshareButton] is true);
/// the caller is responsible for actually performing the unshare so the
/// confirmation prompt lives in one place.
Future<bool> showShareLinkDialog({
  required BuildContext context,
  required String shareUrl,
  required String displayName,
  bool showUnshareButton = false,
}) async {
  var unshareRequested = false;
  await showDialog<void>(
    context: context,
    builder: (ctx) {
      final l = DictLibLocalizations.of(ctx)!;
      return AlertDialog(
        title: Text(l.shareLinkDialogTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.shareLinkDialogBody(displayName)),
            const SizedBox(height: 12),
            SelectableText(shareUrl,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
          ],
        ),
        actionsPadding:
            const EdgeInsets.only(left: 24, right: 24, bottom: 16, top: 8),
        actions: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: shareUrl));
                      if (ctx.mounted) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(content: Text(l.shareLinkCopiedSnack)));
                      }
                    },
                    icon: const Icon(Icons.copy),
                    label: Text(l.shareLinkCopyButton),
                  ),
                  const SizedBox(width: 8),
                  Builder(builder: (btnCtx) {
                    return FilledButton.tonalIcon(
                      onPressed: () async {
                        await Share.share(shareUrl,
                            sharePositionOrigin: sharePositionOrigin(btnCtx));
                      },
                      icon: const Icon(Icons.share),
                      label: Text(l.shareLinkShareButton),
                    );
                  }),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: () =>
                        _showQrCodeDialog(ctx, shareUrl, displayName),
                    icon: const Icon(Icons.qr_code),
                    label: Text(l.shareLinkQrButton),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: Text(l.shareLinkDoneButton),
                  ),
                ],
              ),
              if (showUnshareButton) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: () {
                        unshareRequested = true;
                        Navigator.of(ctx).pop();
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor:
                            Theme.of(ctx).colorScheme.errorContainer,
                        foregroundColor:
                            Theme.of(ctx).colorScheme.onErrorContainer,
                      ),
                      icon: const Icon(Icons.cloud_off),
                      label: Text(l.unshareConfirmTitle),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ],
      );
    },
  );
  return unshareRequested;
}

Future<void> _showQrCodeDialog(
    BuildContext context, String shareUrl, String displayName) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) {
      final l = DictLibLocalizations.of(ctx)!;
      // Explicit width: AlertDialog otherwise wraps `content` in
      // IntrinsicWidth, which walks down into QrImageView's internal
      // LayoutBuilder and throws ("LayoutBuilder does not support returning
      // intrinsic dimensions"). A SizedBox blocks that intrinsic descent.
      return AlertDialog(
        title: Text(displayName),
        content: SizedBox(
          width: 280,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l.qrCodeDialogBody,
                  style: const TextStyle(fontSize: 13),
                  textAlign: TextAlign.center),
              const SizedBox(height: 16),
              // White background so the QR scans cleanly even in dark mode.
              Container(
                color: Colors.white,
                padding: const EdgeInsets.all(12),
                child: QrImageView(
                  data: shareUrl,
                  version: QrVersions.auto,
                  size: 240,
                  backgroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              SelectableText(shareUrl,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                  textAlign: TextAlign.center),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l.qrCodeDialogClose),
          ),
        ],
      );
    },
  );
}

/// Show the "Subscribe to shared list" dialog. Accepts either a bare list
/// key or any of the supported share-URL shapes (see [parseShareInput]).
/// Returns the resulting [SyncedEntryList] on success, null if the user
/// cancelled.
Future<SyncedEntryList?> showSubscribeDialog(
    {required BuildContext context}) async {
  if (!sharing.isEnabled) return null;

  final inputCtl = TextEditingController();
  String? error;
  bool submitting = false;

  try {
    return await showDialog<SyncedEntryList?>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
        final l = DictLibLocalizations.of(ctx)!;
        Future<void> doSubscribe() async {
          final parsed = parseShareInput(inputCtl.text, sharing.config);
          if (parsed == null) {
            setLocal(() => error = l.subscribeInvalidInput);
            return;
          }
          // Invite URL pasted into the subscribe dialog. Refuse loudly
          // — silently subscribing as a non-editor would consume the
          // user's expectation of joining as editor. They should tap
          // the link directly to land on the invite landing page.
          if (parsed.isInvite) {
            setLocal(() => error = l.subscribeInputIsInviteUrl);
            return;
          }
          final listId = parsed.listId;
          // Already subscribed → just open it. Fire-and-forget a refresh
          // so the user sees fresh state when the entry list page builds.
          final existing = sharing.lists.get(listId);
          if (existing != null) {
            unawaited(sharing.engine.refreshSubscriber(listId));
            Navigator.of(ctx).pop(existing);
            return;
          }
          setLocal(() {
            submitting = true;
            error = null;
          });
          try {
            final list = await sharing.engine.subscribe(listId);
            if (ctx.mounted) Navigator.of(ctx).pop(list);
          } on SyncException catch (e) {
            setLocal(() {
              submitting = false;
              error = localisedSyncError(ctx, e,
                  notFoundMessage: l.subscribeNotFound,
                  unknownMessage: e.message);
            });
          }
        }

        return AlertDialog(
          title: Text(l.subscribeDialogTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.subscribeDialogBody, style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 12),
              TextField(
                controller: inputCtl,
                decoration: InputDecoration(
                  labelText: l.subscribeDialogUrlLabel,
                  errorText: error,
                  // Use a real example URL for this app so the user sees
                  // exactly what a valid share link looks like — including
                  // the format of the trailing list ID.
                  hintText: sharing.config.shareUrlFor(exampleListId),
                ),
                autofocus: true,
                enabled: !submitting,
                autocorrect: false,
                textInputAction: TextInputAction.go,
                onSubmitted: (_) => doSubscribe(),
                onChanged: (_) {
                  if (error != null) setLocal(() => error = null);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: submitting ? null : () => Navigator.of(ctx).pop(null),
              child: Text(l.alertCancel),
            ),
            FilledButton(
              onPressed: submitting ? null : doSubscribe,
              child: submitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(l.subscribeDialogSubscribeButton),
            ),
          ],
        );
      }),
    );
  } finally {
    disposeAfterFrame(inputCtl);
  }
}

