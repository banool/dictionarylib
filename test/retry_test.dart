import 'package:dictionarylib/retry.dart';
import 'package:dictionarylib/sharing/sync_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  SyncException netError() => SyncException(SyncErrorKind.network, 'down');

  test('first success returns immediately with no retry feedback', () async {
    var calls = 0;
    var feedback = 0;
    final result = await retryWithFeedback(
      () async {
        calls++;
        return 42;
      },
      firstDelay: Duration.zero,
      onRetry: (_, __) => feedback++,
    );
    expect(result, 42);
    expect(calls, 1);
    expect(feedback, 0);
  });

  test('transient errors retry, reporting each upcoming attempt', () async {
    var calls = 0;
    final reported = <(int, int)>[];
    final result = await retryWithFeedback(
      () async {
        calls++;
        if (calls < 3) throw netError();
        return 'ok';
      },
      firstDelay: Duration.zero,
      onRetry: (attempt, max) => reported.add((attempt, max)),
    );
    expect(result, 'ok');
    expect(calls, 3);
    expect(reported, [(2, 3), (3, 3)]);
  });

  test('the final failure is rethrown once attempts are exhausted', () async {
    var calls = 0;
    await expectLater(
      retryWithFeedback(
        () async {
          calls++;
          throw netError();
        },
        firstDelay: Duration.zero,
      ),
      throwsA(isA<SyncException>()),
    );
    expect(calls, 3);
  });

  test('non-transient errors are rethrown without retrying', () async {
    var calls = 0;
    await expectLater(
      retryWithFeedback(
        () async {
          calls++;
          throw SyncException(SyncErrorKind.forbidden, 'not yours');
        },
        firstDelay: Duration.zero,
      ),
      throwsA(isA<SyncException>()),
    );
    expect(calls, 1);
  });

  test('isTransientSyncError classifies kinds correctly', () {
    expect(isTransientSyncError(SyncException(SyncErrorKind.network, 'x')),
        isTrue);
    expect(
        isTransientSyncError(SyncException(SyncErrorKind.server, 'x')), isTrue);
    expect(isTransientSyncError(SyncException(SyncErrorKind.rateLimited, 'x')),
        isTrue);
    expect(isTransientSyncError(SyncException(SyncErrorKind.unauthorized, 'x')),
        isFalse);
    expect(isTransientSyncError(SyncException(SyncErrorKind.notFound, 'x')),
        isFalse);
    expect(isTransientSyncError(StateError('x')), isFalse);
  });
}
