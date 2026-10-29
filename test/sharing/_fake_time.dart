import 'package:dictionarylib/sharing/sync_clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

/// A test that runs in fake time: timers (request timeouts, debounces,
/// backoff, Retry-After) fire only as the clock is moved, and the clock
/// moves only while the test is waiting on one. Sync's own clock
/// ([debugSyncClock]) follows it.
///
/// [FakeTime.instant] is the latency check: the operation it wraps must
/// complete without the clock moving at all, so it waited for no request,
/// timeout or backoff.
void fakeTimeTest(
  String description,
  Future<void> Function(FakeTime t) body, {
  Duration limit = const Duration(hours: 4),
  Duration step = const Duration(milliseconds: 250),
}) {
  test(description, () {
    fakeAsync((async) {
      final start = DateTime.now();
      debugSyncClock = () => start.add(async.elapsed);
      var done = false;
      Object? error;
      StackTrace? stack;
      body(FakeTime(async)).then<void>(
        (_) {
          done = true;
        },
        onError: (Object e, StackTrace s) {
          error = e;
          stack = s;
          done = true;
        },
      );
      try {
        while (true) {
          async.flushMicrotasks();
          if (done) break;
          if (async.elapsed > limit) {
            fail('still running after $limit of fake time');
          }
          async.elapse(step);
        }
      } finally {
        debugSyncClock = DateTime.now;
        debugSyncClockOffsetSeconds = 0;
      }
      if (error != null) Error.throwWithStackTrace(error!, stack!);
    });
  });
}

class FakeTime {
  final FakeAsync async;
  FakeTime(this.async);

  Duration get elapsed => async.elapsed;

  /// Await [f], failing unless it completed without the clock moving: it
  /// waited for no request, timeout, debounce or backoff.
  Future<T> instant<T>(Future<T> f, String what) async {
    final before = async.elapsed;
    final v = await f;
    expect(
      async.elapsed,
      before,
      reason: '$what should not wait (it took ${async.elapsed - before})',
    );
    return v;
  }

  /// Let [d] of fake time pass.
  Future<void> wait(Duration d) => Future<void>.delayed(d);
}
