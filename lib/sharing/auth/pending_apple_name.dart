import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../common.dart';

/// Holds the name Apple gave us until our server has confirmed a sign-in.
///
/// Apple hands over a person's name once, on their first authorisation, and
/// never again. If the request that carries it to our server then fails (no
/// signal, a timeout, a server error), the retry gets no name from Apple, and
/// the server won't create an account without one. So the name stays on the
/// device, tied to the Apple account it came from, until a sign-in for that
/// account succeeds; then it's forgotten, and the server's record is the only
/// copy. It is never sent for a different Apple account.
class PendingAppleName {
  static const String _storageKey = 'shared_lists_pending_apple_name';

  final FlutterSecureStorage _storage;

  PendingAppleName({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  /// Remember [name] as Apple's name for the account [idToken] belongs to.
  Future<void> remember({required String idToken, required String name}) async {
    final sub = appleSubject(idToken);
    if (sub == null || name.isEmpty) return;
    try {
      await _storage.write(
        key: _storageKey,
        value: jsonEncode({'sub': sub, 'name': name}),
      );
    } catch (e) {
      // Best effort: never fail a sign-in over this.
      printAndLog('pending apple name: could not save ($e)');
    }
  }

  /// The remembered name for the account [idToken] belongs to, or '' if
  /// there is none or it belongs to a different Apple account.
  Future<String> recall(String idToken) async {
    final sub = appleSubject(idToken);
    if (sub == null) return '';
    try {
      final raw = await _storage.read(key: _storageKey);
      if (raw == null) return '';
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return json['sub'] == sub ? (json['name'] as String? ?? '') : '';
    } catch (e) {
      printAndLog('pending apple name: could not read ($e)');
      return '';
    }
  }

  /// Forget the remembered name: the server has it now.
  Future<void> clear() async {
    try {
      await _storage.delete(key: _storageKey);
    } catch (e) {
      printAndLog('pending apple name: could not clear ($e)');
    }
  }
}

/// Apple's stable id for the account an identity token belongs to (its `sub`
/// claim), or null if the token can't be read. Not verified here: it only
/// ties a remembered name to its account, and the server verifies the token.
String? appleSubject(String idToken) {
  final parts = idToken.split('.');
  if (parts.length != 3) return null;
  try {
    final payload = utf8.decode(
      base64Url.decode(base64Url.normalize(parts[1])),
    );
    final sub = (jsonDecode(payload) as Map<String, dynamic>)['sub'];
    return sub is String && sub.isNotEmpty ? sub : null;
  } catch (_) {
    return null;
  }
}
