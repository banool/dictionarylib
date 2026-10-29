import 'dart:async';

import 'package:flutter/material.dart';

import '../entry_list.dart';
import '../globals.dart';
import '../hearth.dart';
import '../l10n/app_localizations.dart';
import '../lists_service.dart';
import '../revision_history.dart';
import 'account_sync.dart';
import 'account_sync_state.dart';
import 'auth/auth_store.dart';
import 'sync_api.dart';
import 'sync_clock.dart';

/// "Syncing…", "Synced 3 minutes ago", "Waiting for a connection" or
/// "Sync is paused": the status line under "Signed in with …" in Settings,
/// and the Status row of the sync status sheet.
String accountSyncStatusText(
  DictLibLocalizations l,
  AccountSyncController sync,
) {
  switch (sync.status) {
    case AccountSyncStatus.syncing:
    case AccountSyncStatus.signedOut:
      return l.accountSyncStatusSyncing;
    case AccountSyncStatus.paused:
      return l.accountSyncStatusPaused;
    case AccountSyncStatus.waitingForConnection:
      return l.accountSyncStatusWaiting;
    case AccountSyncStatus.synced:
      final at = sync.lastSyncAt;
      // Signed in, first cycle not finished yet.
      if (at == null) return l.accountSyncStatusSyncing;
      final minutes = (syncNowSecs() - at) ~/ 60;
      if (minutes < 1) return l.accountSyncStatusJustNow;
      if (minutes < 60) return l.accountSyncStatusMinutesAgo(minutes);
      if (minutes < 24 * 60) {
        return l.accountSyncStatusHoursAgo(minutes ~/ 60);
      }
      return l.accountSyncStatusDaysAgo(minutes ~/ (24 * 60));
  }
}

/// Keys of the sheet's rows, for tests and the on-device suites.
class SyncStatusKeys {
  static const account = ValueKey('syncStatus.account');
  static const status = ValueKey('syncStatus.status');
  static const lastSynced = ValueKey('syncStatus.lastSynced');
  static const lists = ValueKey('syncStatus.lists');
  static const follows = ValueKey('syncStatus.follows');
  static const pending = ValueKey('syncStatus.pending');
  static const problem = ValueKey('syncStatus.problem');
  static const syncNow = ValueKey('syncStatus.syncNow');
}

/// The sync status sheet, opened from "Signed in with …" in Settings: who
/// is signed in, how sync is doing, what is waiting to go up, the last
/// problem in plain words, and a button to sync now.
Future<void> showSyncStatusSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => const SyncStatusSheet(),
  );
}

class SyncStatusSheet extends StatefulWidget {
  const SyncStatusSheet({super.key});

  @override
  State<SyncStatusSheet> createState() => _SyncStatusSheetState();
}

class _SyncStatusSheetState extends State<SyncStatusSheet> {
  late final _sharing = sharing;
  bool _running = false;

  // Relative times ("synced 3 minutes ago") move on while the sheet is up.
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _sharing.addListener(_changed);
    reviewHistory.version.addListener(_changed);
    _tick = Timer.periodic(const Duration(seconds: 30), (_) => _changed());
  }

  @override
  void dispose() {
    _sharing.removeListener(_changed);
    reviewHistory.version.removeListener(_changed);
    _tick?.cancel();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _syncNow() async {
    setState(() => _running = true);
    try {
      await _sharing.accountSync.kick(SyncReason.pullToRefresh);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  String _time(BuildContext context, int unixSeconds, {bool withDate = false}) {
    final ml = MaterialLocalizations.of(context);
    final dt = DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000);
    final time = ml.formatTimeOfDay(
      TimeOfDay.fromDateTime(dt),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    return withDate ? '${ml.formatMediumDate(dt)}, $time' : time;
  }

  /// The last problem in plain words, or null when the last cycle went
  /// through.
  String? _problem(BuildContext context, DictLibLocalizations l) {
    final sync = _sharing.accountSync;
    final st = sync.state;
    final kind = st?.lastErrorKind;
    if (kind == null) return null;
    if (kind == SyncErrorKind.network.name) return l.syncStatusProblemNetwork;
    if (kind == SyncErrorKind.server.name) {
      final at = sync.nextRetryAt;
      return at == null
          ? l.syncStatusProblemServerNoTime
          : l.syncStatusProblemServer(_time(context, at));
    }
    if (kind == SyncErrorKind.unavailable.name ||
        kind == SyncErrorKind.rateLimited.name) {
      final until = st?.pausedUntil;
      if (until != null && until > syncNowSecs()) {
        return l.syncStatusProblemPaused(_time(context, until));
      }
      return l.syncStatusProblemServerNoTime;
    }
    if (kind == SyncErrorKind.unauthorized.name) {
      return l.syncStatusProblemSessionExpired;
    }
    return l.syncStatusProblemOther;
  }

  String _reason(DictLibLocalizations l, String reason) {
    switch (reason) {
      case UnsyncableReason.tooLarge:
        return l.syncStatusReasonTooLarge(maxEntriesPerPrivateList);
      case UnsyncableReason.listLimit:
        return l.syncStatusReasonListLimit;
      default:
        return l.syncStatusReasonRefused;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = DictLibLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final sync = _sharing.accountSync;
    final AuthSession? session = _sharing.auth.store.current;

    final account = session == null
        ? l.syncStatusSignedOut
        : session.displayName.trim().isEmpty
        ? session.provider.label(l)
        : l.syncStatusAccountValue(
            session.provider.label(l),
            session.displayName.trim(),
          );

    final lastSyncAt = sync.lastSyncAt;
    final lastSynced = lastSyncAt == null
        ? l.syncStatusNever
        : _time(context, lastSyncAt, withDate: true);

    final mine = listsService.myLists;
    // A list too large to sync can't, whether or not a cycle has said so
    // yet (before the first merge, say).
    String? reasonFor(EntryList el) =>
        sync.unsyncableReason(el.key) ??
        (el.savedVideos.length > maxEntriesPerPrivateList
            ? UnsyncableReason.tooLarge
            : null);
    final notSyncing = [
      for (final el in mine)
        if (reasonFor(el) case final reason?) (el, reason),
    ];
    final listLines = [
      l.syncStatusListsSyncing(mine.length - notSyncing.length),
      if (notSyncing.isNotEmpty) ...[
        l.syncStatusListsNotSyncing(notSyncing.length),
        for (final (el, reason) in notSyncing)
          l.syncStatusListReason(el.getName(), _reason(l, reason)),
      ],
    ];

    var listChanges = sync.state?.pendingOps.length ?? 0;
    for (final w in _sharing.lists.editableLists) {
      listChanges += w.meta.pendingOps.length;
    }
    final answers = reviewHistory.unsentCount;
    final pending = listChanges == 0 && answers == 0
        ? l.syncStatusNothing
        : l.syncStatusPendingValue(
            l.syncStatusListChanges(listChanges),
            l.syncStatusAnswers(answers),
          );

    final problem = _problem(context, l);
    final busy = _running || sync.isSyncing;

    Widget row(Key key, String title, String value) =>
        HearthRow(key: key, title: title, subtitle: value);

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
                child: Text(
                  l.syncStatusTitle,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              HearthRowGroup(
                rows: [
                  row(SyncStatusKeys.account, l.syncStatusAccount, account),
                  row(
                    SyncStatusKeys.status,
                    l.syncStatusStatus,
                    session == null
                        ? l.syncStatusSignedOut
                        : accountSyncStatusText(l, sync),
                  ),
                  row(
                    SyncStatusKeys.lastSynced,
                    l.syncStatusLastSynced,
                    lastSynced,
                  ),
                  row(
                    SyncStatusKeys.lists,
                    l.syncStatusLists,
                    listLines.join('\n'),
                  ),
                  row(
                    SyncStatusKeys.follows,
                    l.syncStatusFollowed,
                    '${_sharing.lists.subscribedLists.length}',
                  ),
                  row(SyncStatusKeys.pending, l.syncStatusPending, pending),
                  if (problem != null)
                    row(SyncStatusKeys.problem, l.syncStatusProblem, problem),
                ],
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                key: SyncStatusKeys.syncNow,
                onPressed: busy || session == null ? null : _syncNow,
                icon: busy
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: cs.onSurfaceVariant,
                        ),
                      )
                    : const Icon(Icons.sync),
                label: Text(l.syncStatusSyncNow),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
