// Apple gives a person's name once. These pin that it survives a failed
// first sign-in request, reaches the server on the retry, and is then
// forgotten.

import 'dart:convert';

import 'package:dictionarylib/sharing/auth/apple_sign_in.dart';
import 'package:dictionarylib/sharing/auth/auth_api.dart';
import 'package:dictionarylib/sharing/auth/auth_service.dart';
import 'package:dictionarylib/sharing/auth/auth_store.dart';
import 'package:dictionarylib/sharing/auth/pending_apple_name.dart';
import 'package:dictionarylib/sharing/sync_api.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../_helpers.dart';

/// An unsigned Apple-shaped identity token for the account [sub].
String idTokenFor(String sub) {
  String part(Object json) =>
      base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
  return '${part({'alg': 'none'})}.${part({'sub': sub})}.signature';
}

/// Secure storage that actually stores, unlike [installFakeSecureStorage].
void installWorkingSecureStorage() {
  final values = <String, String>{};
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
        (call) async {
          final key = (call.arguments as Map)['key'] as String?;
          switch (call.method) {
            case 'write':
              values[key!] = (call.arguments as Map)['value'] as String;
              return null;
            case 'read':
              return values[key];
            case 'delete':
              values.remove(key);
              return null;
          }
          return null;
        },
      );
}

void main() {
  setUp(installWorkingSecureStorage);

  test('appleSubject reads the sub claim, and null for anything else', () {
    expect(appleSubject(idTokenFor('000800.abc.2154')), '000800.abc.2154');
    expect(appleSubject('not-a-token'), isNull);
    expect(appleSubject('a.b.c'), isNull);
    expect(appleSubject(''), isNull);
  });

  group('sign-in with Apple', () {
    late List<Map<String, dynamic>> bodies;
    late bool serverUp;
    late List<AppleSignInResult> appleResults;

    AuthService buildService() {
      final client = MockClient((req) async {
        bodies.add(jsonDecode(req.body) as Map<String, dynamic>);
        if (!serverUp) return http.Response('{}', 500);
        return http.Response(
          jsonEncode({
            'sessionToken': 'session-jwt',
            'displayName': bodies.last['displayName'] ?? '',
            'userId': 'apple:alice',
          }),
          200,
        );
      });
      return AuthService(
        config: kTestSharingConfig,
        api: AuthApi(kTestSharingConfig, client: client),
        store: AuthStore.withSession(null),
        appleSignIn: (_) async => appleResults.removeAt(0),
      );
    }

    setUp(() {
      bodies = [];
      serverUp = true;
    });

    test(
      'a name from a failed first attempt is sent on the retry, then forgotten',
      () async {
        final token = idTokenFor('alice');
        appleResults = [
          // First authorisation: Apple shares the name.
          AppleSignInResult(idToken: token, freshName: 'Alice Smith'),
          // Every later one: it doesn't.
          AppleSignInResult(idToken: token),
          AppleSignInResult(idToken: token),
        ];
        final service = buildService();

        serverUp = false;
        await expectLater(
          service.signIn(AuthProvider.apple),
          throwsA(isA<SyncException>()),
        );
        expect(bodies.last['displayName'], 'Alice Smith');

        serverUp = true;
        final session = await service.signIn(AuthProvider.apple);
        expect(bodies.last['displayName'], 'Alice Smith');
        expect(session.displayName, 'Alice Smith');

        // Confirmed by the server, so the device's copy is gone.
        await service.signIn(AuthProvider.apple);
        expect(bodies.last.containsKey('displayName'), isFalse);
      },
    );

    test('a remembered name survives an app restart', () async {
      final token = idTokenFor('alice');
      appleResults = [
        AppleSignInResult(idToken: token, freshName: 'Alice Smith'),
        AppleSignInResult(idToken: token),
      ];
      serverUp = false;
      await expectLater(
        buildService().signIn(AuthProvider.apple),
        throwsA(isA<SyncException>()),
      );

      serverUp = true;
      await buildService().signIn(AuthProvider.apple);
      expect(bodies.last['displayName'], 'Alice Smith');
    });

    test('a remembered name is never sent for another Apple account', () async {
      appleResults = [
        AppleSignInResult(idToken: idTokenFor('alice'), freshName: 'Alice'),
        AppleSignInResult(idToken: idTokenFor('bob')),
      ];
      final service = buildService();
      serverUp = false;
      await expectLater(
        service.signIn(AuthProvider.apple),
        throwsA(isA<SyncException>()),
      );

      serverUp = true;
      await service.signIn(AuthProvider.apple);
      expect(bodies.last.containsKey('displayName'), isFalse);
    });
  });
}
