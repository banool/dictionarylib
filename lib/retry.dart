import 'dart:async';

import 'package:flutter/material.dart';

import 'common.dart';
import 'dictionarylib.dart' show DictLibLocalizations;
import 'sharing/sync_api.dart';

/// Whether [error] is worth retrying: transient transport and server-side
/// conditions that may clear up on their own. Auth, permission, and
/// validation failures will fail identically every time, so they surface
/// immediately instead. The canonical kind-set lives on
/// [SyncException.isTransient].
bool isTransientSyncError(Object error) =>
    error is SyncException && error.isTransient;

/// Run [action], retrying when it throws a transient error (see
/// [isTransientSyncError]; override with [shouldRetry]) up to [maxAttempts]
/// total attempts, doubling the delay from [firstDelay] between them.
///
/// Before each retry, [onRetry] is invoked with the upcoming attempt
/// number — surface that to the user (e.g. via [snackRetryFeedback]) so a
/// retry loop reads as "attempt 2 of 3" rather than a silent hang. The
/// final error (or any non-retriable one) is rethrown for the caller to
/// surface; nothing here is swallowed.
Future<T> retryWithFeedback<T>(
  Future<T> Function() action, {
  int maxAttempts = 3,
  Duration firstDelay = const Duration(seconds: 1),
  void Function(int attempt, int maxAttempts)? onRetry,
  bool Function(Object error)? shouldRetry,
}) async {
  final retriable = shouldRetry ?? isTransientSyncError;
  var delay = firstDelay;
  for (var attempt = 1; ; attempt++) {
    try {
      return await action();
    } catch (e) {
      if (attempt >= maxAttempts || !retriable(e)) rethrow;
      onRetry?.call(attempt + 1, maxAttempts);
      await Future<void>.delayed(delay);
      delay *= 2;
    }
  }
}

/// The standard [retryWithFeedback] onRetry callback: a snack reading
/// "Retrying — attempt 2 of 3…". Safe across the retry's async gaps — it
/// no-ops once [context] is unmounted.
void Function(int attempt, int maxAttempts) snackRetryFeedback(
    BuildContext context) {
  return (attempt, maxAttempts) {
    if (!context.mounted) return;
    showSnack(
        context,
        DictLibLocalizations.of(context)!
            .retryAttemptSnack(attempt, maxAttempts),
        replaceCurrent: true);
  };
}
