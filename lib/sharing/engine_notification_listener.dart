import 'dart:async';

import 'package:flutter/material.dart';

import '../common.dart';
import '../dictionarylib.dart' show DictLibLocalizations;
import '../globals.dart';
import 'auth/sign_in_dialog.dart';
import 'sync_engine.dart';

/// The app's one ScaffoldMessenger, attached by the consuming app to its
/// `MaterialApp.scaffoldMessengerKey` so engine snackbars can show from
/// any page.
final GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

/// App-lifetime surface for the engine's one-shot notifications (401 →
/// sessionExpired, 403 → removedAsEditor, snapshot catch-up).
///
/// The engine stream is a broadcast stream, so an event emitted while no
/// listener exists is simply lost. These events used to be listened to by
/// the lists-overview page only, which meant an editor demoted while on
/// any other tab (the flush is debounced, so "add a word, pop back to
/// Search" is enough) never saw the snackbar. Install this once from the
/// app root instead, and attach [rootScaffoldMessengerKey] to the
/// `MaterialApp`'s `scaffoldMessengerKey` so the snackbar can show
/// regardless of which page is on screen.
///
/// Returns the subscription; the app root owns it for the process
/// lifetime (cancel only in tests).
StreamSubscription<SyncNotification> installEngineNotificationSnackbars() {
  return sharing.engineNotifications.listen((notification) {
    final messenger = rootScaffoldMessengerKey.currentState;
    // L10n comes from the navigator context — present whenever the app
    // is rendering, which is the only time a snackbar could show anyway.
    final context = rootNavigatorKey.currentContext;
    if (messenger == null || context == null || !context.mounted) return;
    final l = DictLibLocalizations.of(context)!;
    switch (notification) {
      case SyncNotification.sessionExpired:
        messenger.showSnackBar(SnackBar(
          content: Text(l.engineSessionExpiredSnack),
          action: SnackBarAction(
            label: l.engineSessionExpiredSnackAction,
            onPressed: () async {
              if (!sharing.isEnabled) return;
              final dialogContext = rootNavigatorKey.currentContext;
              if (dialogContext == null || !dialogContext.mounted) return;
              final session = await showSignInDialog(dialogContext,
                  contextMessage: DictLibLocalizations.of(dialogContext)!
                      .signInDialogContextResume);
              // Pages repaint via their `sharing.addListener` hooks once
              // the sync lands; nothing page-specific to do here.
              if (session != null) unawaited(sharing.engine.syncAll());
            },
          ),
        ));
      case SyncNotification.removedAsEditor:
        showSnackVia(messenger, l.engineRemovedAsEditorSnack);
      case SyncNotification.snapshotCatchUp:
        showSnackVia(messenger, l.engineSnapshotCatchUpSnack);
    }
  });
}
