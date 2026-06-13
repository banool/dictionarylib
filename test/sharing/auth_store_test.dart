import 'dart:convert';

import 'package:dictionarylib/sharing/auth/auth_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// In-memory backing for the `flutter_secure_storage` MethodChannel so
/// the tests round-trip values through a real [FlutterSecureStorage]
/// instance instead of needing a mock implementation that subclasses
/// the concrete class. Returns a `reset` callback the test can call
/// between cases.
({void Function() reset, void Function(String? blob) seed})
    installInMemorySecureStorage() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final store = <String, String>{};
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
    (MethodCall call) async {
      final args = call.arguments as Map<Object?, Object?>?;
      final key = args?['key'] as String?;
      switch (call.method) {
        case 'read':
          return store[key];
        case 'write':
          final value = args!['value'] as String;
          store[key!] = value;
          return null;
        case 'delete':
          store.remove(key);
          return null;
        case 'deleteAll':
          store.clear();
          return null;
        case 'containsKey':
          return store.containsKey(key);
        case 'readAll':
          return Map<String, String>.from(store);
        default:
          return null;
      }
    },
  );
  return (
    reset: () => store.clear(),
    seed: (String? blob) {
      store.clear();
      if (blob != null) store['shared_lists_session'] = blob;
    },
  );
}

void main() {
  late void Function() reset;
  late void Function(String? blob) seed;

  setUp(() {
    final h = installInMemorySecureStorage();
    reset = h.reset;
    seed = h.seed;
    reset();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      null,
    );
  });

  group('AuthStore', () {
    test('save then load round-trips the session', () async {
      final store = AuthStore();
      const session = AuthSession(
        sessionToken: 'jwt-1',
        provider: AuthProvider.google,
        displayName: 'Alice',
        signedInAtMillis: 1700000000000,
      );

      await store.save(session);

      final fresh = AuthStore();
      final loaded = await fresh.load();
      expect(loaded, isNotNull);
      expect(loaded!.sessionToken, 'jwt-1');
      expect(loaded.provider, AuthProvider.google);
      expect(loaded.displayName, 'Alice');
      expect(loaded.signedInAtMillis, 1700000000000);
      expect(fresh.loaded, isTrue);
      expect(fresh.current, isNotNull);
    });

    test('clear removes the stored session', () async {
      final store = AuthStore();
      await store.save(const AuthSession(
        sessionToken: 'jwt-2',
        provider: AuthProvider.apple,
        signedInAtMillis: 1,
      ));

      await store.clear();
      expect(store.current, isNull);

      final fresh = AuthStore();
      final loaded = await fresh.load();
      expect(loaded, isNull);
      expect(fresh.loaded, isTrue);
    });

    test('load returns null when the persisted blob is corrupt', () async {
      seed('not valid json {');
      final store = AuthStore();
      final loaded = await store.load();
      expect(loaded, isNull);
      expect(store.current, isNull);
      // Loaded flag still flips so the UI knows the read settled.
      expect(store.loaded, isTrue);
    });

    test('load returns null when the persisted provider is unknown', () async {
      // Simulates a downgrade where a session stored under a provider
      // this build doesn't know about should fail gracefully — the
      // `firstWhere` throws `StateError`, the broad catch in
      // `_loadOnce` turns it into a null session.
      seed(jsonEncode({
        'sessionToken': 'jwt-3',
        'provider': 'martian',
        'displayName': '',
        'signedInAtMillis': 1,
      }));
      final store = AuthStore();
      final loaded = await store.load();
      expect(loaded, isNull);
    });

    test('AuthSession.fromJson parses minimal valid input', () {
      final session = AuthSession.fromJson({
        'sessionToken': 'jwt-min',
        'provider': 'facebook',
        'signedInAtMillis': 42,
      });
      expect(session.sessionToken, 'jwt-min');
      expect(session.provider, AuthProvider.facebook);
      expect(session.userId, '',
          reason: 'userId is empty for pre-cutover persisted sessions; UI '
              'treats empty as "viewer is unknown" and skips the "(you)" '
              'marker rather than crashing.');
      expect(session.displayName, '');
      expect(session.signedInAtMillis, 42);
    });

    test('AuthSession round-trips userId', () async {
      final store = AuthStore();
      const session = AuthSession(
        sessionToken: 'jwt-uid',
        provider: AuthProvider.google,
        userId: 'google:104abc',
        displayName: 'Alice',
        signedInAtMillis: 7,
      );
      await store.save(session);
      final loaded = await AuthStore().load();
      expect(loaded!.userId, 'google:104abc');
    });

    test('AuthStore.withSession synchronously exposes the session', () {
      const session = AuthSession(
        sessionToken: 'jwt-test',
        provider: AuthProvider.test,
        displayName: 'Test User',
        signedInAtMillis: 99,
      );
      final store = AuthStore.withSession(session);
      expect(store.loaded, isTrue);
      expect(store.current, isNotNull);
      expect(store.current!.sessionToken, 'jwt-test');
      expect(store.current!.provider, AuthProvider.test);
    });

    test('AuthStore.withSession(null) starts in a loaded, signed-out state',
        () {
      final store = AuthStore.withSession(null);
      expect(store.loaded, isTrue);
      expect(store.current, isNull);
    });
  });
}
