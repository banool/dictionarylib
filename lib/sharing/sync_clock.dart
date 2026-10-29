import 'package:flutter/foundation.dart';

/// Unix seconds now, as sync stamps the ops it queues (list ops' `clientTs`,
/// account ops' `clientTs`). The server orders renames, the list order, the
/// default list, settings and deletes against later edits by these times
/// (the later intent wins), so tests that play two devices with different
/// clocks move it with [debugSyncClockOffsetSeconds].
int syncNowSecs() =>
    DateTime.now().millisecondsSinceEpoch ~/ 1000 + debugSyncClockOffsetSeconds;

/// Seconds added to [syncNowSecs]; tests only.
@visibleForTesting
int debugSyncClockOffsetSeconds = 0;
