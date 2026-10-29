import 'package:flutter/foundation.dart';

/// Unix seconds now, as sync stamps the ops it queues (list ops' `clientTs`,
/// account ops' `clientTs`) and times its pauses. The server orders
/// renames, the list order, the default list, settings and deletes against
/// later edits by these times (the later intent wins), so tests that play
/// two devices with different clocks move it with
/// [debugSyncClockOffsetSeconds], and tests in fake time point
/// [debugSyncClock] at the fake clock.
int syncNowSecs() =>
    debugSyncClock().millisecondsSinceEpoch ~/ 1000 +
    debugSyncClockOffsetSeconds;

/// Seconds added to [syncNowSecs]; tests only.
@visibleForTesting
int debugSyncClockOffsetSeconds = 0;

/// Where [syncNowSecs] reads the time; tests only.
@visibleForTesting
DateTime Function() debugSyncClock = DateTime.now;
