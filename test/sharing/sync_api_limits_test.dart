// Client-side mirrors of the server's create-time limits, and the typed
// accessors the UI uses to tell a limit refusal apart from a generic
// permission failure. The constants here must track
// `workers/src/validation.ts` in the private backend repo.

import 'dart:convert';

import 'package:dictionarylib/saved_video.dart';
import 'package:dictionarylib/sharing/sync_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

http.Response _errorResponse(
  int status,
  String code,
  String message, {
  Map<String, dynamic>? details,
}) {
  return http.Response(
    jsonEncode({
      'error': {
        'code': code,
        'message': message,
        if (details != null) 'details': details,
      }
    }),
    status,
  );
}

void main() {
  group('SyncException.isListLimitReached', () {
    test('true for a 403 carrying the list_limit reason', () {
      final e = SyncException.fromResponse(_errorResponse(
        403,
        'FORBIDDEN',
        'you can own at most 100 shared lists; unshare one to make room',
        details: {'reason': 'list_limit', 'limit': 100},
      ));
      expect(e.kind, SyncErrorKind.forbidden);
      expect(e.isListLimitReached, isTrue);
      expect(e.listLimit, 100);
    });

    test('false for a plain membership 403', () {
      final e = SyncException.fromResponse(
          _errorResponse(403, 'FORBIDDEN', 'not a member'));
      expect(e.isListLimitReached, isFalse);
    });

    test('false for the wrong-app 403 (the other reason discriminator)', () {
      final e = SyncException.fromResponse(_errorResponse(
        403,
        'FORBIDDEN',
        'wrong app',
        details: {'reason': 'wrong_app'},
      ));
      expect(e.isListLimitReached, isFalse);
      expect(e.isWrongAppForbid, isTrue);
    });

    test('listLimit falls back to the compiled-in cap when absent', () {
      // An older worker that stamps the reason but not the limit.
      final e = SyncException.fromResponse(_errorResponse(
        403,
        'FORBIDDEN',
        'too many lists',
        details: {'reason': 'list_limit'},
      ));
      expect(e.isListLimitReached, isTrue);
      expect(e.listLimit, maxListsPerUser);
    });
  });

  group('OpOutcome rejection reasons', () {
    test('parses reasonCode and flags a list-full rejection', () {
      final o = OpOutcome.fromJson({
        'opId': 'op1',
        'status': 'rejected',
        'reason': 'list is at the 10000-entry limit',
        'reasonCode': 'list_full',
      });
      expect(o.status, OpStatus.rejected);
      expect(o.reasonCode, opRejectedReasonListFull);
      expect(o.isListFullRejection, isTrue);
    });

    test('a rejection without a reasonCode is not a list-full rejection', () {
      final o = OpOutcome.fromJson({
        'opId': 'op1',
        'status': 'rejected',
        'reason': 'addEntry.entry required',
      });
      expect(o.reasonCode, isNull);
      expect(o.isListFullRejection, isFalse);
    });

    test('an applied op is never a list-full rejection', () {
      final o = OpOutcome.fromJson({
        'opId': 'op1',
        'status': 'applied',
        'seq': 4,
      });
      expect(o.isListFullRejection, isFalse);
    });
  });

  group('estimateCreateBodyBytes', () {
    SavedVideo v(String entry, String path) =>
        SavedVideo(entryKey: entry, mediaPath: path);

    test('is just the envelope allowance for an empty list', () {
      expect(estimateCreateBodyBytes(const <SavedVideo>[]),
          lessThan(maxCreateBodyBytes));
      expect(estimateCreateBodyBytes(const <SavedVideo>[]), greaterThan(0));
    });

    test('grows with entry count', () {
      final one = estimateCreateBodyBytes([v('dog', '/mp4video/11/1.mp4')]);
      final two = estimateCreateBodyBytes([
        v('dog', '/mp4video/11/1.mp4'),
        v('cat', '/mp4video/11/2.mp4'),
      ]);
      expect(two, greaterThan(one));
    });

    test('counts UTF-8 bytes, not code units', () {
      // A three-byte character must cost more than a one-byte one.
      final ascii = estimateCreateBodyBytes([v('abc', '/x.mp4')]);
      final multibyte = estimateCreateBodyBytes([v('中中中', '/x.mp4')]);
      expect(multibyte, ascii + 6);
    });

    test('never undershoots the real encoded body', () {
      // The estimate exists to pre-empt a 413, so undershooting is the
      // failure that matters: it would wave through a body the server
      // then rejects. Compared against the full create body, envelope
      // included, since that is what actually goes over the wire.
      for (final count in [1, 200, 5000]) {
        final entries = [
          for (var i = 0; i < count; i++) v('entry$i', '/mp4video/11/$i.mp4'),
        ];
        final actual = utf8
            .encode(jsonEncode({
              'listId': 'greetings101',
              'displayName': 'Greetings 101',
              'entries': entries.map((e) => e.toJson()).toList(),
              'schemaVersion': supportedSchemaVersion,
            }))
            .length;
        final estimate = estimateCreateBodyBytes(entries);
        expect(estimate, greaterThanOrEqualTo(actual),
            reason: 'estimate must not undershoot at $count entries');
        // ...and not so loose that it refuses shares that would work.
        expect(estimate, lessThan((actual * 1.2).round() + 512),
            reason: 'estimate must stay tight at $count entries');
      }
    });

    test('a full-size list of realistic entries fits the create cap', () {
      // Guards the pairing of the two constants: if maxEntriesPerList is
      // raised without maxCreateBodyBytes keeping up, an ordinary full
      // list stops being shareable.
      final entries = [
        for (var i = 0; i < maxEntriesPerList; i++)
          v('some-entry-key-$i', '/mp4video/11/11450-$i.mp4'),
      ];
      expect(estimateCreateBodyBytes(entries), lessThan(maxCreateBodyBytes));
    });
  });
}
