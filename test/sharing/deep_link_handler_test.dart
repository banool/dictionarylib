import 'dart:async';

import 'package:dictionarylib/sharing/deep_link_handler.dart';
import 'package:dictionarylib/sharing/sharing_config.dart';
import 'package:flutter_test/flutter_test.dart';

// Same shape as kTestSharingConfig but the deep-link tests assert on the
// auslan-specific host/scheme strings literally; keep the inline values
// here so the test contract is self-evident.
const _config = SharingConfig(
  appId: 'auslan',
  appName: 'Auslan Dictionary',
  apiBaseUrl: 'https://api.auslandictionary.org',
  shareLinkBaseUrl: 'https://share.auslandictionary.org/l',
  shareLinkHost: 'share.auslandictionary.org',
  urlScheme: 'auslan',
  auth: SharingAuthConfig(
    // Real iOS bundle id is camelCase (com.banool.auslanDictionary);
    // mirror that in the test fixture to avoid confusing future readers.
    appleBundleId: 'com.banool.auslanDictionary',
    googleServerClientId: 'test.google.client.id',
    facebookAppId: 'test-fb-app-id',
  ),
);

// 12-char base32-style keys — what generateListId() produces.
const _key = 'abc234xyz567';

/// Convenience: parse + project to listId only. The full payload (with
/// invite token) is covered by its own group below.
String? _listId(String input) =>
    extractSharePayload(Uri.parse(input), _config)?.listId;

void main() {
  group('extractSharePayload listId — Universal/App Link form', () {
    test('extracts from https://<host>/l/<key>', () {
      expect(_listId('https://share.auslandictionary.org/l/$_key'), _key);
    });

    test('ignores wrong host', () {
      expect(_listId('https://other.example.com/l/$_key'), isNull);
    });

    test('ignores http (only https is verified)', () {
      expect(_listId('http://share.auslandictionary.org/l/$_key'), isNull);
    });

    test('ignores non-share paths', () {
      expect(
          _listId('https://share.auslandictionary.org/search?q=foo'), isNull);
    });

    test('ignores /l/ with no key', () {
      expect(_listId('https://share.auslandictionary.org/l/'), isNull);
    });

    test('handles trailing query string', () {
      expect(_listId('https://share.auslandictionary.org/l/foo?bar=1'), 'foo');
    });
  });

  group('extractSharePayload listId — custom scheme', () {
    test('extracts from auslan://share/<key>', () {
      expect(_listId('auslan://share/$_key'), _key);
    });

    test('ignores wrong scheme', () {
      expect(_listId('slsl://share/$_key'), isNull);
    });

    test('ignores custom scheme without share/ host', () {
      // Anything other than the `share` host is not a list-id URL; the app
      // can use other deep-link routes (e.g. auslan://settings) without
      // them being misinterpreted as list IDs.
      expect(_listId('auslan://$_key'), isNull);
      expect(_listId('auslan://settings'), isNull);
    });

    test('ignores empty host', () {
      // Uri.parse('auslan://') has empty host
      expect(_listId('auslan://'), isNull);
    });
  });

  /// Convenience for tests that only assert on the listId.
  String? _parsedListId(String input) =>
      parseShareInput(input, _config)?.listId;

  group('parseShareInput — bare keys', () {
    test('accepts a random-style key', () {
      expect(_parsedListId(_key), _key);
    });

    test('lowercases bare key input', () {
      expect(_parsedListId('ABC234XYZ567'), 'abc234xyz567');
    });

    test('trims whitespace', () {
      expect(_parsedListId('  $_key  '), _key);
    });

    test('rejects invalid bare keys', () {
      expect(_parsedListId('hello world'), isNull); // space
      expect(_parsedListId('hello_world'), isNull); // underscore
      expect(_parsedListId('with-dash'), isNull); // dash
      expect(_parsedListId('a' * 65), isNull); // too long
    });

    test('rejects empty input', () {
      expect(parseShareInput('', _config), isNull);
      expect(parseShareInput('   ', _config), isNull);
    });

    test('bare keys never carry an invite token', () {
      expect(parseShareInput(_key, _config)!.isInvite, isFalse);
    });
  });

  group('parseShareInput — strict URL shapes', () {
    test('https://<configHost>/l/<key>', () {
      expect(_parsedListId('https://share.auslandictionary.org/l/$_key'), _key);
    });

    test('custom scheme share form', () {
      expect(_parsedListId('auslan://share/$_key'), _key);
    });
  });

  group('parseShareInput — loose / cross-env URLs', () {
    test('accepts share URL from a different host', () {
      expect(_parsedListId('https://example.com/l/$_key'), _key);
    });

    test('handles trailing slash', () {
      expect(_parsedListId('https://example.com/l/$_key/'), _key);
    });

    test('handles query string', () {
      expect(
          _parsedListId('https://example.com/l/$_key?utm_source=slack'), _key);
    });

    test('lowercases extracted key', () {
      expect(
          _parsedListId('https://example.com/l/ABC234XYZ567'), 'abc234xyz567');
    });
  });

  group('parseShareInput — rejects unrelated URLs', () {
    test('rejects URLs without /l/ segment', () {
      expect(
          parseShareInput('https://example.com/profile/jdoe', _config), isNull);
    });

    test('rejects /l/ with invalid key', () {
      expect(
          parseShareInput('https://example.com/l/UPPER_CASE', _config), isNull);
      expect(
          parseShareInput('https://example.com/l/with-dash', _config), isNull);
    });

    test('rejects garbage', () {
      expect(parseShareInput('not://a real url', _config), isNull);
    });
  });

  group('extractSharePayload — invite token', () {
    test('returns the listId with no token on a vanilla share link', () {
      final p = extractSharePayload(
          Uri.parse('https://share.auslandictionary.org/l/$_key'), _config);
      expect(p, isNotNull);
      expect(p!.listId, _key);
      expect(p.inviteToken, isNull);
      expect(p.isInvite, isFalse);
    });

    test('captures ?invite=<token> on a Universal Link', () {
      final p = extractSharePayload(
          Uri.parse('https://share.auslandictionary.org/l/$_key?invite=abc123'),
          _config);
      expect(p, isNotNull);
      expect(p!.listId, _key);
      expect(p.inviteToken, 'abc123');
      expect(p.isInvite, isTrue);
    });

    test('captures ?invite=<token> on a custom-scheme link', () {
      final p = extractSharePayload(
          Uri.parse('auslan://share/$_key?invite=xyz789'), _config);
      expect(p, isNotNull);
      expect(p!.listId, _key);
      expect(p.inviteToken, 'xyz789');
    });

    test('treats empty invite= as absent', () {
      final p = extractSharePayload(
          Uri.parse('https://share.auslandictionary.org/l/$_key?invite='),
          _config);
      expect(p, isNotNull);
      expect(p!.inviteToken, isNull);
      expect(p.isInvite, isFalse);
    });

    test('ignores wrong-host URLs entirely (no listId, no invite)', () {
      expect(
          extractSharePayload(
              Uri.parse('https://other.example/l/$_key?invite=tok'), _config),
          isNull);
    });

    test('parseShareInput surfaces the invite token on a strict URL', () {
      // The subscribe-by-pasting flow uses this — surfacing the token
      // lets the dialog reject invite URLs with a clear error rather
      // than silently subscribing the user without editor status.
      final p = parseShareInput(
          'https://share.auslandictionary.org/l/$_key?invite=tok', _config);
      expect(p, isNotNull);
      expect(p!.listId, _key);
      expect(p.inviteToken, 'tok');
      expect(p.isInvite, isTrue);
    });

    test('parseShareInput surfaces the invite token on a loose URL', () {
      final p = parseShareInput(
          'https://example.com/l/$_key?invite=tok&utm=x', _config);
      expect(p, isNotNull);
      expect(p!.listId, _key);
      expect(p.inviteToken, 'tok');
    });
  });

  group('SharePayload.toRouteLocation', () {
    test('plain share link maps to /share/<id>', () {
      final p = extractSharePayload(
          Uri.parse('https://share.auslandictionary.org/l/$_key'), _config);
      expect(p!.toRouteLocation(), '/share/$_key');
    });

    test(
        'custom-scheme invite link maps to /share/<id>?invite=<tok>, never the '
        'raw auslan:// URI GoRouter has no route for', () {
      // Regression for "GoException: no routes for location:
      // auslan://share/<id>?invite=<tok>". The inbound deep link must be
      // rewritten to the GoRouter `/share/:listId` location; routing the raw
      // custom-scheme URI threw because no route matches it.
      final p = extractSharePayload(
          Uri.parse('auslan://share/$_key?invite=tok123'), _config);
      final loc = p!.toRouteLocation();
      expect(loc, '/share/$_key?invite=tok123');
      expect(loc.startsWith('/share/'), isTrue);
      expect(loc.contains('://'), isFalse,
          reason: 'the router location must not carry the deep-link scheme');
    });

    test('invite token is query-encoded', () {
      const p = SharePayload(listId: 'abc', inviteToken: 'a&b');
      expect(p.toRouteLocation(), '/share/abc?invite=a%26b');
    });
  });

  group('DeepLinkHandler — cold-start replay + dedupe', () {
    /// Cold-start sequence: handler is constructed before the app UI
    /// subscribes. `start()` parses the initial link and parks it in
    /// the pending buffer; a late subscriber receives it on its first
    /// onData (scheduled via microtask so the controller has finished
    /// wiring up).
    test('initial-link buffered for a late subscriber', () async {
      final liveLinks = StreamController<Uri>.broadcast();
      final handler = DeepLinkHandler.forTesting(
        config: _config,
        initialLinkGetter: () async =>
            Uri.parse('https://share.auslandictionary.org/l/$_key'),
        linkStream: liveLinks.stream,
      );
      await handler.start();

      // No subscriber yet — payload should be in the pending buffer.
      // Subscribe now (simulating a late-arriving router) and collect.
      final received = <SharePayload>[];
      final sub = handler.payloads.listen(received.add);

      // Let the microtask fire.
      await Future<void>.delayed(Duration.zero);

      expect(received, hasLength(1));
      expect(received.single.listId, _key);

      await sub.cancel();
      handler.dispose();
      await liveLinks.close();
    });

    test('takePendingInitial returns the buffered payload then null', () async {
      final liveLinks = StreamController<Uri>.broadcast();
      final handler = DeepLinkHandler.forTesting(
        config: _config,
        initialLinkGetter: () async =>
            Uri.parse('https://share.auslandictionary.org/l/$_key'),
        linkStream: liveLinks.stream,
      );
      await handler.start();

      final first = handler.takePendingInitial();
      expect(first, isNotNull);
      expect(first!.listId, _key);

      final second = handler.takePendingInitial();
      expect(second, isNull,
          reason: 'pending buffer must clear after a synchronous read so '
              'a subsequent caller does not see a stale payload');

      handler.dispose();
      await liveLinks.close();
    });

    test('adjacent-duplicate URLs are suppressed', () async {
      final liveLinks = StreamController<Uri>.broadcast();
      final handler = DeepLinkHandler.forTesting(
        config: _config,
        initialLinkGetter: () async => null,
        linkStream: liveLinks.stream,
      );
      final received = <SharePayload>[];
      final sub = handler.payloads.listen(received.add);
      await handler.start();

      final url = Uri.parse('https://share.auslandictionary.org/l/$_key');
      liveLinks.add(url);
      liveLinks.add(url);
      await Future<void>.delayed(Duration.zero);

      expect(received, hasLength(1),
          reason: 'OS duplicate deliveries must be deduped so the subscriber '
              'only routes once');

      await sub.cancel();
      handler.dispose();
      await liveLinks.close();
    });
  });
}
