import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// An in-memory stand-in for the share API Worker, with account sync: the
/// account DO's ops and directory, list DOs (private and shared, soft
/// delete, `addEntries`, visibility), the owner and editor indexes, and
/// public snapshots. Mirrors `workers/src/account_do.ts`, `list_do.ts` and
/// `index.ts` in the private backend repo closely enough to test the
/// client's merge and reconciliation against; the same client runs against
/// the real Worker in `account_sync_multi_device_test.dart`.
///
/// Everything is plain JSON-shaped data, so [clone] is a deep copy: the
/// crash-point tests take one at every prefs write to put a "device" back
/// together with the server as it was at that moment.
class FakeAccountServer {
  /// Session token → user id.
  final Map<String, String> tokens = {};

  /// List id → list state (see [_newList]).
  Map<String, Map<String, dynamic>> lists = {};

  /// User id → account state (see [_newAccount]).
  Map<String, Map<String, dynamic>> accounts = {};

  /// Every request handled, as `METHOD path`.
  final List<String> log = [];

  /// Called before a request is handled; return true to fail it with a
  /// network error (nothing reaches the server).
  bool Function(http.Request req)? failBefore;

  /// Called after a request was handled; return true to lose the response
  /// (the server applied it, the client sees a network error).
  bool Function(http.Request req)? loseResponse;

  /// When set, account routes answer 503 UNAVAILABLE (the kill switch).
  bool accountSyncDisabled = false;

  /// Called for each account op not seen before; return true to answer it
  /// `rejected retry` (the list it needs unreachable for now, say).
  bool Function(Map<String, dynamic> op)? answerRetry;

  int _clock = 1700000000;
  int _ids = 0;

  int _now() => _clock;

  /// Move the server clock (unix seconds) on.
  void advance(int seconds) => _clock += seconds;

  String signIn(String userId) {
    final token = 'token-$userId-${tokens.length}';
    tokens[token] = userId;
    return token;
  }

  FakeAccountServer clone() {
    final c = FakeAccountServer()
      ..lists = _deep(lists)
      ..accounts = _deep(accounts)
      .._clock = _clock
      .._ids = _ids;
    c.tokens.addAll(tokens);
    return c;
  }

  static Map<String, Map<String, dynamic>> _deep(
    Map<String, Map<String, dynamic>> m,
  ) => {
    for (final e in m.entries)
      e.key: jsonDecode(jsonEncode(e.value)) as Map<String, dynamic>,
  };

  http.Client client() => MockClient(handle);

  Future<http.Response> handle(http.Request req) async {
    log.add('${req.method} ${req.url.path}');
    if (failBefore?.call(req) ?? false) {
      throw http.ClientException('fake network failure', req.url);
    }
    final resp = _route(req);
    if (loseResponse?.call(req) ?? false) {
      throw http.ClientException('fake lost response', req.url);
    }
    return resp;
  }

  // -------- helpers --------

  http.Response _json(Object body, [int status = 200]) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json'},
  );

  http.Response _err(
    int status,
    String code,
    String message, [
    Map<String, dynamic>? details,
    Map<String, String>? headers,
  ]) => http.Response(
    jsonEncode({
      'error': {'code': code, 'message': message, 'details': ?details},
    }),
    status,
    headers: {'content-type': 'application/json', ...?headers},
  );

  String? _user(http.Request req) {
    final auth = req.headers['authorization'];
    if (auth == null || !auth.startsWith('Bearer ')) return null;
    return tokens[auth.substring(7)];
  }

  Map<String, dynamic> _newAccount() => {
    'incarnation': 'inc${_ids++}',
    'lastSeq': 0,
    'resetTsUs': 0,
    'directory': <Map<String, dynamic>>[],
    'follows': <String>[],
    'reviews': <Map<String, dynamic>>[],
    'randomSessions': <Map<String, dynamic>>[],
    'settings': <String, dynamic>{},
    'opLog': <String, dynamic>{},
  };

  Map<String, dynamic> account(String userId) =>
      accounts.putIfAbsent(userId, _newAccount);

  Map<String, dynamic> _newList({
    required String listId,
    required String name,
    required String owner,
    required String visibility,
    List<List<String>> entries = const [],
  }) => {
    'listId': listId,
    'displayName': name,
    'owner': owner,
    'visibility': visibility,
    'tombstoned': false,
    'deletedAt': null,
    'lastSeq': 0,
    'entries': [for (final e in entries) List<String>.from(e)],
    'ops': <Map<String, dynamic>>[],
    'editors': <String>[],
    'createdAt': _now(),
    'updatedAt': _now(),
  };

  Map<String, dynamic> _snapshot(Map<String, dynamic> l) => {
    'schemaVersion': 3,
    'listId': l['listId'],
    'displayName': l['displayName'],
    'appId': 'auslan',
    'entries': [
      for (final e in (l['entries'] as List))
        {'entry': (e as List)[0], 'video': e[1]},
    ],
    'lastSeq': l['lastSeq'],
    'createdAt': l['createdAt'],
    'updatedAt': l['updatedAt'],
    'members': {
      'owner': {'userId': l['owner'], 'displayName': 'Owner'},
      'editors': [
        for (final e in (l['editors'] as List))
          {'userId': e, 'displayName': 'Editor', 'addedAt': 0, 'addedBy': ''},
      ],
    },
    'visibility': l['visibility'],
  };

  bool _hasEntry(Map<String, dynamic> l, String entry, String video) =>
      (l['entries'] as List).any((e) => e[0] == entry && e[1] == video);

  // -------- routing --------

  http.Response _route(http.Request req) {
    final path = req.url.path;
    final method = req.method;
    if (path == '/v1/account/sync' && method == 'POST') {
      return _accountSync(req);
    }
    if (path == '/v1/lists' && method == 'POST') return _createShared(req);
    final m = RegExp(r'^/v1/lists/([^/]+)(/.*)?$').firstMatch(path);
    if (m == null) return _err(404, 'NOT_FOUND', 'no route');
    final id = m.group(1)!;
    final sub = m.group(2) ?? '';
    if (sub == '' && method == 'GET') {
      final l = lists[id];
      if (l == null || l['tombstoned'] == true || l['visibility'] != 'shared') {
        return _err(404, 'NOT_FOUND', 'list not found');
      }
      final snap = _snapshot(l)
        ..remove('members')
        ..remove('visibility');
      return http.Response(
        jsonEncode(snap),
        200,
        headers: {'etag': '"${l['lastSeq']}-${l['displayName']}"'},
      );
    }
    final user = _user(req);
    if (user == null) return _err(401, 'UNAUTHORIZED', 'no session');
    if (sub == '/state' && method == 'GET') return _state(id, user);
    if (sub == '/sync' && method == 'POST') return _listSync(req, id, user);
    if (sub == '/visibility' && method == 'PUT') {
      if (accountSyncDisabled) return _unavailable();
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      return _setVisibility(
        id,
        user,
        body['visibility'] as String,
        body['displayName'] as String?,
      );
    }
    if (sub == '' && method == 'PUT') {
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      return _rename(id, user, body['displayName'] as String);
    }
    if (sub == '' && method == 'DELETE') {
      final hasCap = req.headers['x-sync-capabilities'] == 'account-sync';
      final acc = accounts[user];
      if (!hasCap && acc != null && (acc['directory'] as List).isNotEmpty) {
        final r = _setVisibility(id, user, 'private', null);
        return r.statusCode == 200 ? http.Response('', 204) : r;
      }
      final r = _deleteList(id, user);
      if (r != null) return r;
      if (hasCap && acc != null) {
        final row = _row(acc, id);
        if (row != null) _markDeleted(row);
      }
      return http.Response('', 204);
    }
    if (sub == '/restore' && method == 'POST') {
      if (accountSyncDisabled) return _unavailable();
      final r = _restoreList(id, user);
      if (r.statusCode == 200) _markRestored(account(user), id);
      return r;
    }
    return _err(405, 'INVALID_BODY', 'method');
  }

  http.Response _unavailable() => _err(
    503,
    'UNAVAILABLE',
    'account sync is switched off for now',
    {'reason': 'account_sync_disabled'},
    {'retry-after': '3600'},
  );

  // -------- lists --------

  http.Response _createShared(http.Request req) {
    final user = _user(req);
    if (user == null) return _err(401, 'UNAUTHORIZED', 'no session');
    final body = jsonDecode(req.body) as Map<String, dynamic>;
    final id = body['listId'] as String;
    final existing = lists[id];
    if (existing != null) {
      if (existing['owner'] == user && existing['tombstoned'] != true) {
        return _json({
          'listId': id,
          'lastSeq': existing['lastSeq'],
          'existed': true,
        });
      }
      return _err(409, 'ID_COLLISION', 'taken');
    }
    lists[id] = _newList(
      listId: id,
      name: body['displayName'] as String,
      owner: user,
      visibility: 'shared',
      entries: [
        for (final e in (body['entries'] as List))
          [e['entry'] as String, e['video'] as String],
      ],
    );
    return _json({
      'listId': id,
      'lastSeq': 0,
      'createdAt': _now(),
      'updatedAt': _now(),
    }, 201);
  }

  /// Public snapshot for a list someone owns, or the given error.
  http.Response _state(String id, String user) {
    final l = lists[id];
    if (l == null) return _err(404, 'NOT_FOUND', 'list not found');
    if (l['tombstoned'] == true) return _err(410, 'GONE', 'deleted');
    if (l['owner'] != user && !(l['editors'] as List).contains(user)) {
      return _err(403, 'FORBIDDEN', 'not a member');
    }
    return _json(_snapshot(l));
  }

  http.Response _listSync(http.Request req, String id, String user) {
    final l = lists[id];
    if (l == null) return _err(404, 'NOT_FOUND', 'list not found');
    if (l['tombstoned'] == true) return _err(410, 'GONE', 'deleted');
    if (l['owner'] != user && !(l['editors'] as List).contains(user)) {
      return _err(403, 'FORBIDDEN', 'not a member');
    }
    final body = jsonDecode(req.body) as Map<String, dynamic>;
    final lastKnownSeq = body['lastKnownSeq'] as int;
    if (lastKnownSeq > (l['lastSeq'] as int)) {
      return _err(400, 'INVALID_BODY', 'ahead', {'reason': 'stale_cursor'});
    }
    final ops = (body['ops'] as List).cast<Map<String, dynamic>>();
    final applied = <Map<String, dynamic>>[];
    final batchIds = <String>{};
    final cap = l['visibility'] == 'private' ? 5000 : 500;
    for (final op in ops) {
      final opId = op['opId'] as String;
      batchIds.add(opId);
      final dup = (l['ops'] as List).cast<Map<String, dynamic>>().where(
        (o) => o['opId'] == opId,
      );
      if (dup.isNotEmpty) {
        applied.add({
          'opId': opId,
          'status': 'duplicate',
          'seq': dup.first['seq'],
        });
        continue;
      }
      final type = op['type'] as String;
      final args = Map<String, dynamic>.from(op['args'] as Map);
      Map<String, dynamic> logged = args;
      String? reasonCode;
      if (type == 'addEntry') {
        final e = args['entry'] as String;
        final v = args['video'] as String;
        if (!_hasEntry(l, e, v)) {
          if ((l['entries'] as List).length >= cap) {
            applied.add({
              'opId': opId,
              'status': 'rejected',
              'reasonCode': 'list_full',
            });
            continue;
          }
          (l['entries'] as List).add([e, v]);
        }
      } else if (type == 'removeEntry') {
        (l['entries'] as List).removeWhere(
          (x) => x[0] == args['entry'] && x[1] == args['video'],
        );
      } else if (type == 'addEntries') {
        if (l['visibility'] != 'private') {
          applied.add({
            'opId': opId,
            'status': 'rejected',
            'reasonCode': 'not_private',
          });
          continue;
        }
        final inserted = <Map<String, dynamic>>[];
        var notAdded = 0;
        for (final item in (args['entries'] as List)) {
          final e = item['entry'] as String;
          final v = item['video'] as String;
          if (_hasEntry(l, e, v)) continue;
          if ((l['entries'] as List).length >= cap) {
            notAdded++;
            continue;
          }
          (l['entries'] as List).add([e, v]);
          inserted.add({'entry': e, 'video': v});
        }
        if (inserted.isEmpty && notAdded > 0) {
          applied.add({
            'opId': opId,
            'status': 'rejected',
            'reasonCode': 'list_full',
          });
          continue;
        }
        if (notAdded > 0) reasonCode = 'list_full';
        logged = {'entries': inserted};
      } else {
        return _err(400, 'INVALID_BODY', 'unknown op type');
      }
      final seq = (l['lastSeq'] as int) + 1;
      l['lastSeq'] = seq;
      (l['ops'] as List).add({
        'seq': seq,
        'opId': opId,
        'type': type,
        'args': logged,
        'userId': user,
      });
      applied.add({
        'opId': opId,
        'status': 'applied',
        'seq': seq,
        'reasonCode': ?reasonCode,
      });
    }
    final missed = <Map<String, dynamic>>[];
    for (final o in (l['ops'] as List).cast<Map<String, dynamic>>()) {
      if ((o['seq'] as int) <= lastKnownSeq || batchIds.contains(o['opId'])) {
        continue;
      }
      if (o['type'] == 'addEntries') {
        for (final e in (o['args']['entries'] as List)) {
          missed.add({
            'seq': o['seq'],
            'type': 'addEntry',
            'args': {'entry': e['entry'], 'video': e['video']},
            'userId': o['userId'],
            'actorDisplayName': '',
            'serverTs': 0,
          });
        }
        continue;
      }
      missed.add({
        'seq': o['seq'],
        'type': o['type'],
        'args': o['args'],
        'userId': o['userId'],
        'actorDisplayName': '',
        'serverTs': 0,
      });
    }
    final snap = _snapshot(l);
    return _json({
      'appliedSeq': l['lastSeq'],
      'applied': applied,
      'missedOps': missed,
      'snapshot': null,
      'members': snap['members'],
      'wasSnapshotCatchUp': false,
      'displayName': l['displayName'],
      'visibility': l['visibility'],
    });
  }

  http.Response _setVisibility(
    String id,
    String user,
    String visibility,
    String? displayName,
  ) {
    final l = lists[id];
    if (l == null) return _err(404, 'NOT_FOUND', 'list not found');
    if (l['tombstoned'] == true) return _err(410, 'GONE', 'deleted');
    if (l['owner'] != user) return _err(403, 'FORBIDDEN', 'not owner');
    if (l['visibility'] != visibility) {
      if (visibility == 'shared') {
        final name = displayName ?? l['displayName'] as String;
        if (name.trim().toLowerCase() == 'favourites') {
          return _err(400, 'INVALID_BODY', 'displayName "$name" is reserved');
        }
        if ((l['entries'] as List).length > 500) {
          return _err(400, 'INVALID_BODY', 'too large', {
            'reason': 'list_too_large_to_share',
            'limit': 500,
          });
        }
        l['displayName'] = name;
      } else {
        l['editors'] = <String>[];
      }
      l['visibility'] = visibility;
      final seq = (l['lastSeq'] as int) + 1;
      l['lastSeq'] = seq;
      (l['ops'] as List).add({
        'seq': seq,
        'opId': 'synthetic:visibility:$visibility:$seq',
        'type': 'setVisibility',
        'args': {'visibility': visibility},
        'userId': user,
      });
    }
    final acc = account(user);
    final row = _row(acc, id);
    if (row != null) {
      row['visibility'] = visibility;
      row['name'] = l['displayName'];
    } else {
      _insertRow(acc, id, l['displayName'] as String, visibility, 'live');
    }
    return _json(_snapshot(l));
  }

  http.Response _rename(String id, String user, String name) {
    final l = lists[id];
    if (l == null) return _err(404, 'NOT_FOUND', 'list not found');
    if (l['tombstoned'] == true) return _err(410, 'GONE', 'deleted');
    if (l['owner'] != user) return _err(403, 'FORBIDDEN', 'not owner');
    l['displayName'] = name;
    final row = _row(account(user), id);
    if (row != null) row['name'] = name;
    return _json(_snapshot(l));
  }

  /// Null on success, else the error.
  http.Response? _deleteList(String id, String user) {
    final l = lists[id];
    if (l == null) return _err(404, 'NOT_FOUND', 'list not found');
    if (l['tombstoned'] == true) return _err(410, 'GONE', 'deleted');
    if (l['owner'] != user) return _err(403, 'FORBIDDEN', 'not owner');
    l['tombstoned'] = true;
    l['deletedAt'] = _now();
    return null;
  }

  http.Response _restoreList(String id, String user) {
    final l = lists[id];
    if (l == null) return _err(404, 'NOT_FOUND', 'list not found');
    if (l['owner'] != user) return _err(403, 'FORBIDDEN', 'not owner');
    l['tombstoned'] = false;
    l['deletedAt'] = null;
    l['visibility'] = 'private';
    l['editors'] = <String>[];
    return _json(_snapshot(l));
  }

  /// Delete a list behind everyone's back (another device's op, a purge).
  void purgeList(String id) => lists.remove(id);

  // -------- account --------

  Map<String, dynamic>? _row(Map<String, dynamic> acc, String id) {
    for (final r in (acc['directory'] as List).cast<Map<String, dynamic>>()) {
      if (r['listId'] == id) return r;
    }
    return null;
  }

  int _nextPosition(Map<String, dynamic> acc) {
    var max = 0;
    for (final r in (acc['directory'] as List)) {
      if ((r['position'] as int) > max) max = r['position'] as int;
    }
    return max + 1;
  }

  Map<String, dynamic> _insertRow(
    Map<String, dynamic> acc,
    String id,
    String name,
    String visibility,
    String state, {
    String? requestId,
  }) {
    final row = {
      'listId': id,
      'position': _nextPosition(acc),
      'isDefault': false,
      'visibility': visibility,
      'name': name,
      'state': state,
      'deletedAt': state == 'deleted' ? _now() : null,
      'requestId': requestId,
    };
    (acc['directory'] as List).add(row);
    return row;
  }

  void _markDeleted(Map<String, dynamic> row) {
    row['state'] = 'deleted';
    row['deletedAt'] = _now();
    row['isDefault'] = false;
  }

  void _markRestored(Map<String, dynamic> acc, String id) {
    final l = lists[id]!;
    final row = _row(acc, id);
    if (row == null) {
      _insertRow(acc, id, l['displayName'] as String, 'private', 'live');
      return;
    }
    if (row['state'] == 'live') return;
    row
      ..['state'] = 'live'
      ..['visibility'] = 'private'
      ..['deletedAt'] = null
      ..['position'] = _nextPosition(acc);
  }

  static String normalize(String s) =>
      s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  /// Make a list on [userId]'s account as another device would.
  String createAccountList(
    String userId,
    String name, {
    List<List<String>> entries = const [],
    bool isDefault = false,
    String visibility = 'private',
  }) {
    final id = 'srv${_ids++}x';
    lists[id] = _newList(
      listId: id,
      name: name,
      owner: userId,
      visibility: visibility,
      entries: entries,
    );
    final acc = account(userId);
    final row = _insertRow(acc, id, name, visibility, 'live');
    if (isDefault) {
      for (final r in (acc['directory'] as List)) {
        r['isDefault'] = false;
      }
      row['isDefault'] = true;
    }
    return id;
  }

  /// Entries of [id] as `entry` keys, server order.
  List<String> entryKeys(String id) => [
    for (final e in (lists[id]!['entries'] as List)) e[0] as String,
  ];

  /// Live directory rows of [userId], in order.
  List<Map<String, dynamic>> liveRows(String userId) {
    final rows = (account(userId)['directory'] as List)
        .cast<Map<String, dynamic>>()
        .where((r) => r['state'] == 'live')
        .toList();
    rows.sort((a, b) => (a['position'] as int).compareTo(b['position'] as int));
    return rows;
  }

  http.Response _accountSync(http.Request req) {
    if (accountSyncDisabled) return _unavailable();
    final user = _user(req);
    if (user == null) return _err(401, 'UNAUTHORIZED', 'no session');
    final body = jsonDecode(req.body) as Map<String, dynamic>;
    final ops = (body['ops'] as List).cast<Map<String, dynamic>>();
    if (ops.length > 50) return _err(413, 'PAYLOAD_TOO_LARGE', 'too many ops');
    if (utf8.encode(req.body).length > 64 * 1024) {
      return _err(413, 'PAYLOAD_TOO_LARGE', 'too big');
    }
    final sinceSeq = body['sinceSeq'] as int;
    final clientId = body['clientId'] as String;
    final acc = account(user);
    // Reconcile shared lists this user owns that aren't in the directory.
    for (final l in lists.values) {
      if (l['owner'] == user &&
          l['visibility'] == 'shared' &&
          l['tombstoned'] != true &&
          _row(acc, l['listId'] as String) == null) {
        _insertRow(
          acc,
          l['listId'] as String,
          l['displayName'] as String,
          'shared',
          'live',
        );
      }
    }
    final results = <Map<String, dynamic>>[];
    for (final op in ops) {
      results.add(_applyAccountOp(acc, user, clientId, op));
    }
    return _json(_accountResponse(acc, user, sinceSeq, results));
  }

  Map<String, dynamic> _applyAccountOp(
    Map<String, dynamic> acc,
    String user,
    String clientId,
    Map<String, dynamic> op,
  ) {
    final opId = op['opId'] as String;
    final type = op['type'] as String;
    final a = Map<String, dynamic>.from(op['args'] as Map);
    final logged = (acc['opLog'] as Map)[opId];
    if (logged != null) {
      return {
        'opId': opId,
        'status': 'duplicate',
        'seq': logged['seq'],
        'result': ?logged['result'],
      };
    }
    Map<String, dynamic> rej(String code) => {
      'opId': opId,
      'status': 'rejected',
      'reasonCode': code,
    };
    if (answerRetry?.call(op) ?? false) return rej('retry');
    Map<String, dynamic>? result;
    final nextSeq = (acc['lastSeq'] as int) + 1;
    switch (type) {
      case 'createList':
        final requestId = a['requestId'] as String;
        final name = a['name'] as String;
        final byReq = (acc['directory'] as List)
            .cast<Map<String, dynamic>>()
            .where((r) => r['requestId'] == requestId)
            .toList();
        if (byReq.isNotEmpty) {
          final r = byReq.first;
          if (r['state'] == 'deleted') return rej('id_collision');
          if (r['state'] == 'creating') {
            final l = lists[r['listId']];
            if (l == null) {
              lists[r['listId'] as String] = _newList(
                listId: r['listId'] as String,
                name: r['name'] as String,
                owner: user,
                visibility: 'private',
              );
            }
            r['state'] = 'live';
          }
          result = {'listId': r['listId'], 'created': true};
          break;
        }
        if (a['nameMatch'] != false) {
          final live = liveRows(user);
          final match = live.where(
            (r) => normalize(r['name'] as String) == normalize(name),
          );
          if (match.isNotEmpty) {
            result = {'listId': match.first['listId'], 'created': false};
            break;
          }
        }
        final listId = a['listId'] as String;
        if (_row(acc, listId) != null) return rej('id_collision');
        final existing = lists[listId];
        if (existing != null &&
            (existing['owner'] != user || existing['tombstoned'] == true)) {
          return rej('id_collision');
        }
        if (liveRows(user).length >= 300) return rej('list_limit');
        _insertRow(acc, listId, name, 'private', 'live', requestId: requestId);
        lists[listId] ??= _newList(
          listId: listId,
          name: name,
          owner: user,
          visibility: 'private',
        );
        result = {'listId': listId, 'created': true};
      case 'setDefault':
        final row = _row(acc, a['listId'] as String);
        if (row == null || row['state'] != 'live') return rej('not_found');
        for (final r in (acc['directory'] as List)) {
          r['isDefault'] = r['listId'] == a['listId'];
        }
      case 'reorder':
        final ids = (a['listIds'] as List).cast<String>();
        final rows = (acc['directory'] as List).cast<Map<String, dynamic>>()
          ..sort(
            (x, y) => (x['position'] as int).compareTo(y['position'] as int),
          );
        final order = <Map<String, dynamic>>[
          for (final id in ids)
            ...rows.where((r) => r['listId'] == id && r['state'] == 'live'),
        ];
        for (final r in rows) {
          if (!order.contains(r) && r['state'] == 'live') order.add(r);
        }
        for (final r in rows) {
          if (!order.contains(r)) order.add(r);
        }
        for (var i = 0; i < order.length; i++) {
          order[i]['position'] = i + 1;
        }
      case 'rename':
        final row = _row(acc, a['listId'] as String);
        if (row == null) return rej('not_found');
        row['name'] = a['name'];
      case 'delete':
        final id = a['listId'] as String;
        final row = _row(acc, id);
        if (row != null && row['isDefault'] == true) return rej('default_list');
        final err = _deleteList(id, user);
        if (err != null && err.statusCode == 403) return rej('forbidden');
        if (row != null) {
          if (row['state'] != 'deleted') _markDeleted(row);
        } else if (err == null) {
          _insertRow(
            acc,
            id,
            lists[id]!['displayName'] as String,
            'private',
            'deleted',
          );
        }
      case 'unlink':
        final id = a['listId'] as String;
        final st = _state(id, user);
        final row = _row(acc, id);
        if (st.statusCode == 200) {
          if (row == null && lists[id]!['owner'] == user) {
            _insertRow(
              acc,
              id,
              lists[id]!['displayName'] as String,
              lists[id]!['visibility'] as String,
              'live',
            );
          }
          return rej('still_live');
        }
        if (row != null && row['state'] != 'deleted') _markDeleted(row);
      case 'restore':
        final id = a['listId'] as String;
        final row = _row(acc, id);
        if (row != null && row['state'] == 'live') break;
        final r = _restoreList(id, user);
        if (r.statusCode == 404) return rej('not_found');
        if (r.statusCode != 200) return rej('forbidden');
        _markRestored(acc, id);
      case 'follow':
        final f = acc['follows'] as List;
        if (!f.contains(a['listId'])) f.add(a['listId']);
      case 'unfollow':
        (acc['follows'] as List).remove(a['listId']);
      case 'addReviews':
        final reviews = (a['reviews'] as List).cast<Map<String, dynamic>>();
        var accepted = 0;
        var dups = 0;
        var before = 0;
        for (final r in reviews) {
          if ((r['t'] as int) < (acc['resetTsUs'] as int)) {
            before++;
            continue;
          }
          final exists = (acc['reviews'] as List).any(
            (x) => x['m'] == r['m'] && x['c'] == r['c'] && x['t'] == r['t'],
          );
          if (exists) {
            dups++;
            continue;
          }
          (acc['reviews'] as List).add({...r, 'seq': nextSeq});
          accepted++;
        }
        result = {
          'accepted': accepted,
          'duplicates': dups,
          'rejectedBeforeReset': before,
          'invalid': 0,
        };
      case 'resetProgress':
        final ts = a['tsUs'] as int;
        if (ts > (acc['resetTsUs'] as int)) acc['resetTsUs'] = ts;
        (acc['reviews'] as List).removeWhere((x) => (x['t'] as int) < ts);
        (acc['randomSessions'] as List).removeWhere(
          (x) => (x['tsUs'] as int) < ts,
        );
      case 'randomSession':
        final exists = (acc['randomSessions'] as List).any(
          (x) => x['opId'] == opId,
        );
        if (!exists && (a['tsUs'] as int) >= (acc['resetTsUs'] as int)) {
          (acc['randomSessions'] as List).add({
            'opId': opId,
            'count': a['count'],
            'tsUs': a['tsUs'],
            'seq': nextSeq,
          });
        }
      case 'setSetting':
        (acc['settings'] as Map)[a['key']] = {
          'key': a['key'],
          'value': a['value'],
          'seq': nextSeq,
        };
      default:
        return rej('unknown_type');
    }
    acc['lastSeq'] = nextSeq;
    (acc['opLog'] as Map)[opId] = {'seq': nextSeq, 'result': result};
    return {
      'opId': opId,
      'status': 'applied',
      'seq': nextSeq,
      'result': ?result,
    };
  }

  Map<String, dynamic> _accountResponse(
    Map<String, dynamic> acc,
    String user,
    int sinceSeq,
    List<Map<String, dynamic>> results,
  ) {
    final rows =
        (acc['directory'] as List).cast<Map<String, dynamic>>().toList()..sort(
          (a, b) => (a['position'] as int).compareTo(b['position'] as int),
        );
    final reviews =
        (acc['reviews'] as List)
            .cast<Map<String, dynamic>>()
            .where((r) => (r['seq'] as int) > sinceSeq)
            .toList()
          ..sort((a, b) => (a['seq'] as int).compareTo(b['seq'] as int));
    var hasMore = false;
    var next = acc['lastSeq'] as int;
    var page = reviews;
    if (reviews.length > 1000) {
      hasMore = true;
      final cut = reviews[1000]['seq'] as int;
      page = reviews.where((r) => (r['seq'] as int) < cut).toList();
      next = cut - 1;
    }
    var total = 0;
    for (final r in (acc['randomSessions'] as List)) {
      total += r['count'] as int;
    }
    return {
      'incarnation': acc['incarnation'],
      'seq': acc['lastSeq'],
      'nextSinceSeq': next,
      'results': results,
      'directory': [
        for (final r in rows)
          {
            'listId': r['listId'],
            'position': r['position'],
            'isDefault': r['isDefault'],
            'visibility': r['visibility'],
            'name': r['name'],
            'state': r['state'],
            'deletedAt': r['deletedAt'],
          },
      ],
      'follows': acc['follows'],
      'settings': (acc['settings'] as Map).values.toList(),
      'resetTsUs': acc['resetTsUs'],
      'randomTotal': total,
      'reviews': page,
      'randomSessions': [
        for (final r in (acc['randomSessions'] as List))
          if ((r['seq'] as int) > sinceSeq && (r['seq'] as int) <= next) r,
      ],
      'hasMore': hasMore,
      'editorListIds': [
        for (final l in lists.values)
          if ((l['editors'] as List).contains(user) && l['tombstoned'] != true)
            l['listId'],
      ],
    };
  }
}
