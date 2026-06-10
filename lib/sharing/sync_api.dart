import 'dart:async';
import 'dart:convert';
import 'dart:io' show HttpDate;

import 'package:http/http.dart' as http;

import '../saved_video.dart';
import 'sharing_config.dart';

/// Schema version the client understands on incoming snapshots /
/// list payloads. The server sends `schemaVersion: 3` on
/// [RemoteList] and [ListSnapshot]; anything else triggers a
/// [SyncErrorKind.server] so a stale client doesn't misinterpret
/// future-format fields. Bump in lockstep with the worker.
///
/// History:
///   - v2: `entries: string[]` of entry keys (whole-entry saves).
///   - v3: `entries: SavedVideoDto[]` (per-video saves). Op args
///     `{key}` become `{entry, video}`.
const int supportedSchemaVersion = 3;

/// Mirror of the server's `MAX_DISPLAY_NAME_LEN` (see
/// `lists/workers/src/validation.ts`). Used for client-side validation
/// so the user gets immediate feedback rather than a 400 round-trip;
/// the server re-checks on every accepted request.
const int maxDisplayNameLen = 80;

/// Mirror of the server's `MAX_ENTRIES` cap on entries per list. The
/// share dialog refuses to publish a list larger than this with a
/// friendly message rather than letting the create call surface a
/// generic 400.
const int maxEntriesPerList = 500;

/// Parse an HTTP-date header value (RFC 7231) into unix seconds, or 0
/// if the header is missing / malformed.
int _parseLastModifiedSeconds(http.Response resp) {
  final raw = resp.headers['last-modified'];
  if (raw == null) return 0;
  try {
    return HttpDate.parse(raw).millisecondsSinceEpoch ~/ 1000;
  } catch (_) {
    return 0;
  }
}

/// Discriminator string the worker stamps on a 403's `details.reason`
/// when the rejection comes from the `x-app-id` check (config drift)
/// rather than a real membership failure. Mirrors
/// `FORBID_REASON_WRONG_APP` in `lists/workers/src/index.ts` — keep
/// in lockstep. Consumers use the typed [SyncException.isWrongAppForbid]
/// rather than reading this literal.
const String _forbidReasonWrongApp = 'wrong_app';

/// Error envelope returned by the API.
class SyncException implements Exception {
  final SyncErrorKind kind;
  final String message;
  final Map<String, dynamic>? details;
  SyncException(this.kind, this.message, [this.details]);

  /// True if this is a 403 from the worker's `x-app-id` check (config
  /// drift), distinguishable from a DO-level membership 403. The
  /// engine treats these very differently: a wrong-app 403 backs off
  /// and retries (preserving pending ops); a membership 403 demotes
  /// the local editor wrapper to subscriber and drops the queue.
  bool get isWrongAppForbid =>
      kind == SyncErrorKind.forbidden &&
      details?['reason'] == _forbidReasonWrongApp;

  @override
  String toString() => 'SyncException($kind, $message)';

  /// Parse a non-2xx [http.Response] into a [SyncException]. Shared by
  /// every API client (sync_api, auth_api) so the status-code → kind
  /// mapping has one home.
  static SyncException fromResponse(http.Response resp) {
    Map<String, dynamic>? envelope;
    String message = 'HTTP ${resp.statusCode}';
    try {
      final decoded = jsonDecode(resp.body);
      if (decoded is Map<String, dynamic> &&
          decoded['error'] is Map<String, dynamic>) {
        envelope = (decoded['error'] as Map<String, dynamic>);
        message = envelope['message'] as String? ?? message;
      }
    } catch (_) {/* keep the HTTP-status fallback */}
    final code = envelope?['code'] as String?;
    final details = envelope?['details'] as Map<String, dynamic>?;

    final kind = switch (resp.statusCode) {
      400 => code == 'MISSING_HEADER'
          ? SyncErrorKind.missingHeader
          : SyncErrorKind.invalidBody,
      401 => SyncErrorKind.unauthorized,
      403 => SyncErrorKind.forbidden,
      404 => SyncErrorKind.notFound,
      409 => SyncErrorKind.idCollision,
      410 => SyncErrorKind.gone,
      413 => SyncErrorKind.payloadTooLarge,
      429 => SyncErrorKind.rateLimited,
      _ => resp.statusCode >= 500
          ? SyncErrorKind.server
          : SyncErrorKind.unknownClient,
    };

    final detailsOut = <String, dynamic>{...?details};
    final retryAfter = resp.headers['retry-after'];
    if (retryAfter != null) detailsOut['retryAfter'] = retryAfter;
    return SyncException(kind, message, detailsOut.isEmpty ? null : detailsOut);
  }
}

enum SyncErrorKind {
  /// 400 — request body or path was invalid.
  invalidBody,

  /// 400 — missing required header (app id).
  missingHeader,

  /// 401 — missing / invalid / expired session token. Distinct from
  /// [forbidden] — clients should drop the local session and re-prompt
  /// sign-in.
  unauthorized,

  /// 403 — current user lacks permission (not a member, not the owner,
  /// or wrong app id).
  forbidden,

  /// 404 — list no longer exists.
  notFound,

  /// 410 — list was deleted by its owner. Clients should drop the
  /// local mirror; this is a more specific NOT_FOUND.
  gone,

  /// 409 — random list ID collided with an existing one. Caller should
  /// generate a new key and retry.
  idCollision,

  /// 413 — payload too large.
  payloadTooLarge,

  /// 429 — rate limited. `details['retryAfter']` if known.
  rateLimited,

  /// 5xx — server error.
  server,

  /// Network failure / timeout / connection refused / DNS, etc.
  network,

  /// Non-recognised 4xx (405, 408, 411, 422, …) — never returned by
  /// our own worker today, but lets clients distinguish "the server
  /// said something we don't model" from "validation error" (which
  /// has its own user-facing copy).
  unknownClient,
}

// -------- Subscriber-read shapes --------

/// Outcome of a subscriber GET — either an unchanged 304 or a fresh payload.
sealed class FetchResult {}

class FetchNotModified extends FetchResult {}

class FetchOk extends FetchResult {
  final RemoteList list;
  final String etag;

  /// Unix seconds parsed from the response's `Last-Modified` header.
  /// Informational; the engine uses `list.lastSeq` for sync state.
  final int serverUpdatedAt;
  FetchOk(this.list, this.etag, this.serverUpdatedAt);
}

/// Subscriber-facing payload as served from R2 by the worker.
/// Excludes the `members` block (no editor identities leaked publicly).
class RemoteList {
  final String listId;
  final String displayName;
  final String appId;

  /// Saved videos in this list. The schema-v3 wire shape sends one
  /// `{entry, video}` object per saved video.
  final List<SavedVideo> entries;

  /// Monotonic per-list sequence as of the snapshot. Clients use this
  /// to bootstrap their `lastKnownSeq` when subscribing.
  final int lastSeq;
  final int createdAt;
  final int updatedAt;

  RemoteList({
    required this.listId,
    required this.displayName,
    required this.appId,
    required this.entries,
    required this.lastSeq,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Parse a server response. Validates `schemaVersion` is one we
  /// support — see [supportedSchemaVersion] — and throws
  /// [SyncException] with kind [SyncErrorKind.server] otherwise so a
  /// stale client fails closed rather than misinterpreting future
  /// fields.
  factory RemoteList.fromJson(Map<String, dynamic> json) {
    _validateSchemaVersion(json);
    final lastSeq = json['lastSeq'];
    if (lastSeq is! int) {
      throw SyncException(
          SyncErrorKind.server, 'list payload missing required field lastSeq');
    }
    return RemoteList(
      listId: json['listId'] as String,
      displayName: json['displayName'] as String,
      appId: json['appId'] as String,
      entries: _parseEntriesArray(json['entries']),
      lastSeq: lastSeq,
      createdAt: json['createdAt'] as int,
      updatedAt: json['updatedAt'] as int,
    );
  }
}

/// Parse the `entries` field on a v3 server response into [SavedVideo]
/// objects. The wire shape is `[{entry: string, video: string}, ...]`.
/// Any malformed item is rejected at the request boundary so the local
/// mirror never ends up holding partial garbage.
List<SavedVideo> _parseEntriesArray(dynamic raw) {
  if (raw is! List) {
    throw SyncException(
        SyncErrorKind.server, 'entries must be an array of objects');
  }
  final out = <SavedVideo>[];
  for (var i = 0; i < raw.length; i++) {
    final item = raw[i];
    if (item is! Map) {
      throw SyncException(SyncErrorKind.server, 'entries[$i] must be an object');
    }
    final entry = item['entry'];
    final video = item['video'];
    if (entry is! String || video is! String) {
      throw SyncException(SyncErrorKind.server,
          'entries[$i] must have string `entry` and `video` fields');
    }
    out.add(SavedVideo(entryKey: entry, videoUrl: video));
  }
  return out;
}

void _validateSchemaVersion(Map<String, dynamic> json) {
  final v = json['schemaVersion'];
  if (v != supportedSchemaVersion) {
    throw SyncException(
        SyncErrorKind.server,
        'unsupported schemaVersion ${v ?? "(missing)"} '
        '(client supports $supportedSchemaVersion). Update the app.');
  }
}

// -------- Authenticated reads — members + ops --------

/// A user's identity for rendering. Same shape as the worker's
/// `MemberRef` interface.
class MemberRef {
  final String userId;
  final String displayName;
  const MemberRef({required this.userId, required this.displayName});
  factory MemberRef.fromJson(Map<String, dynamic> json) => MemberRef(
        userId: json['userId'] as String,
        displayName: json['displayName'] as String,
      );
  Map<String, dynamic> toJson() =>
      {'userId': userId, 'displayName': displayName};
}

/// An editor's identity with provenance ("added by X on date").
class EditorRef extends MemberRef {
  final int addedAt;
  final String addedBy;
  const EditorRef({
    required super.userId,
    required super.displayName,
    required this.addedAt,
    required this.addedBy,
  });
  factory EditorRef.fromJson(Map<String, dynamic> json) => EditorRef(
        userId: json['userId'] as String,
        displayName: json['displayName'] as String,
        addedAt: json['addedAt'] as int,
        addedBy: json['addedBy'] as String,
      );
  @override
  Map<String, dynamic> toJson() => {
        ...super.toJson(),
        'addedAt': addedAt,
        'addedBy': addedBy,
      };
}

/// Full membership view of a list. Owner is always present; editors
/// may be empty.
class MembersBlock {
  final MemberRef owner;
  final List<EditorRef> editors;
  const MembersBlock({required this.owner, required this.editors});

  factory MembersBlock.fromJson(Map<String, dynamic> json) => MembersBlock(
        owner: MemberRef.fromJson(json['owner'] as Map<String, dynamic>),
        editors: (json['editors'] as List<dynamic>)
            .map((e) => EditorRef.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'owner': owner.toJson(),
        'editors': editors.map((e) => e.toJson()).toList(),
      };
}

/// Full authenticated snapshot from /state or /sync (catch-up case).
/// Includes everything the editor UI needs to render: entries +
/// membership + cursor.
class ListSnapshot {
  final String listId;
  final String displayName;
  final String appId;
  final List<SavedVideo> entries;
  final int lastSeq;
  final int createdAt;
  final int updatedAt;
  final MembersBlock members;
  ListSnapshot({
    required this.listId,
    required this.displayName,
    required this.appId,
    required this.entries,
    required this.lastSeq,
    required this.createdAt,
    required this.updatedAt,
    required this.members,
  });
  factory ListSnapshot.fromJson(Map<String, dynamic> json) {
    _validateSchemaVersion(json);
    return ListSnapshot(
      listId: json['listId'] as String,
      displayName: json['displayName'] as String,
      appId: json['appId'] as String,
      entries: _parseEntriesArray(json['entries']),
      lastSeq: json['lastSeq'] as int,
      createdAt: json['createdAt'] as int,
      updatedAt: json['updatedAt'] as int,
      members: MembersBlock.fromJson(json['members'] as Map<String, dynamic>),
    );
  }
}

// -------- Op-log types --------

/// Server-assigned outcome for a client-submitted op. `seq` is set when
/// `status == applied | duplicate`; `reason` when `rejected`.
///
/// Note `duplicate` means "the server saw this exact opId before"
/// (replay dedupe via [PendingOp.opId]), NOT "no-op". Idempotent
/// no-ops like `removeEntry` on an absent key are returned as
/// `applied`.
enum OpStatus { applied, duplicate, rejected }

class OpOutcome {
  final String opId;
  final OpStatus status;
  final int? seq;
  final String? reason;
  const OpOutcome({
    required this.opId,
    required this.status,
    this.seq,
    this.reason,
  });
  factory OpOutcome.fromJson(Map<String, dynamic> json) => OpOutcome(
        opId: json['opId'] as String,
        status: switch (json['status'] as String) {
          'applied' => OpStatus.applied,
          'duplicate' => OpStatus.duplicate,
          _ => OpStatus.rejected,
        },
        seq: json['seq'] as int?,
        reason: json['reason'] as String?,
      );
}

/// Materialised op-log row returned in /sync `missedOps`.
class AppliedOp {
  final int seq;
  final String type;
  final Map<String, dynamic> args;
  final String userId;

  /// Display name snapshotted at op time. Never changes when the user
  /// renames themselves later.
  final String actorDisplayName;
  final int serverTs;
  AppliedOp({
    required this.seq,
    required this.type,
    required this.args,
    required this.userId,
    required this.actorDisplayName,
    required this.serverTs,
  });
  factory AppliedOp.fromJson(Map<String, dynamic> json) => AppliedOp(
        seq: json['seq'] as int,
        type: json['type'] as String,
        args: json['args'] as Map<String, dynamic>,
        userId: json['userId'] as String,
        actorDisplayName: json['actorDisplayName'] as String? ?? '',
        serverTs: json['serverTs'] as int,
      );
}

/// Response to POST /v1/lists/:id/sync.
class SyncResponse {
  /// DO's `last_seq` after the batch applied. Becomes the client's
  /// new `lastKnownSeq`.
  final int appliedSeq;
  final List<OpOutcome> applied;

  /// Ops the server applied that the client didn't submit (other
  /// editors' work). Null when the catch-up gap was larger than the
  /// retained op-log; in that case `snapshot` is set instead.
  final List<AppliedOp>? missedOps;

  /// Full state when the client was too far behind for an op diff.
  final ListSnapshot? snapshot;

  /// Fresh membership directory — always included so the UI can keep
  /// display names up to date without an extra round-trip.
  final MembersBlock members;

  /// True when the server returned a catch-up snapshot because the
  /// client's `lastKnownSeq` had fallen out of the retained op-log
  /// window. The UI surfaces a "list changed substantially while you
  /// were offline; your changes may have been overwritten" banner so
  /// users aren't blindsided by silent overwrites. Older servers may
  /// not set the field; fall back to `snapshot != null`.
  final bool wasSnapshotCatchUp;

  /// The list's current display name, echoed on every /sync so a rename
  /// by the owner reaches editors on their next sync. Null when talking
  /// to an older server that doesn't send it — the client then leaves
  /// its local name untouched.
  final String? displayName;

  SyncResponse({
    required this.appliedSeq,
    required this.applied,
    required this.missedOps,
    required this.snapshot,
    required this.members,
    required this.wasSnapshotCatchUp,
    required this.displayName,
  });
  factory SyncResponse.fromJson(Map<String, dynamic> json) {
    final snapshotRaw = json['snapshot'];
    final snapshot = snapshotRaw == null
        ? null
        : ListSnapshot.fromJson(snapshotRaw as Map<String, dynamic>);
    return SyncResponse(
      appliedSeq: json['appliedSeq'] as int,
      applied: (json['applied'] as List<dynamic>)
          .map((e) => OpOutcome.fromJson(e as Map<String, dynamic>))
          .toList(),
      missedOps: (json['missedOps'] as List<dynamic>?)
          ?.map((e) => AppliedOp.fromJson(e as Map<String, dynamic>))
          .toList(),
      snapshot: snapshot,
      members: MembersBlock.fromJson(json['members'] as Map<String, dynamic>),
      wasSnapshotCatchUp: json['wasSnapshotCatchUp'] as bool? ?? snapshot != null,
      displayName: json['displayName'] as String?,
    );
  }
}

/// Response shape for POST /v1/lists.
class CreateResult {
  final String listId;
  final int lastSeq;
  final int createdAt;
  final int updatedAt;
  CreateResult({
    required this.listId,
    required this.lastSeq,
    required this.createdAt,
    required this.updatedAt,
  });
}

/// Response shape for POST /v1/lists/:id/invites.
class InviteTokenResult {
  final String token;
  final int expiresAt;
  final String listId;
  const InviteTokenResult({
    required this.token,
    required this.expiresAt,
    required this.listId,
  });
}

/// Response shape for GET /v1/my-lists.
class UserListsResult {
  /// Lists this user is the creator of.
  final List<String> ownedListIds;

  /// Lists this user has been added to as an editor.
  final List<String> editorListIds;
  const UserListsResult({
    required this.ownedListIds,
    required this.editorListIds,
  });
}

// -------- Client --------

/// Thin client around the share API. Stateless — the sync engine owns
/// the session-token / etag state and passes them in per call.
class SyncApi {
  final SharingConfig config;
  final http.Client _client;
  final Duration timeout;

  SyncApi(this.config,
      {http.Client? client, this.timeout = const Duration(seconds: 10)})
      : _client = client ?? http.Client();

  void close() => _client.close();

  Uri _listUrl(String key) =>
      Uri.parse('${config.apiBaseUrl}/v1/lists/${Uri.encodeComponent(key)}');
  Uri _listSubUrl(String key, String sub) => Uri.parse(
      '${config.apiBaseUrl}/v1/lists/${Uri.encodeComponent(key)}/$sub');
  Uri _listsUrl() => Uri.parse('${config.apiBaseUrl}/v1/lists');
  Uri _ownedListsUrl() => Uri.parse('${config.apiBaseUrl}/v1/my-lists');

  Map<String, String> _baseHeaders() => {'x-app-id': config.appId};

  /// Create a new list owned by the caller. The worker forwards this
  /// into the per-list DO, which writes the initial R2 snapshot.
  Future<CreateResult> createList({
    required String listId,
    required String displayName,
    required List<SavedVideo> entries,
    required String sessionToken,
  }) async {
    final body = jsonEncode({
      'listId': listId,
      'displayName': displayName,
      'entries': entries.map((v) => v.toJson()).toList(),
      'schemaVersion': supportedSchemaVersion,
    });
    final resp = await _request(
      method: 'POST',
      url: _listsUrl(),
      headers: {
        ..._baseHeaders(),
        'content-type': 'application/json',
        'authorization': 'Bearer $sessionToken',
      },
      body: body,
    );
    if (resp.statusCode == 201) {
      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      return CreateResult(
        listId: json['listId'] as String,
        lastSeq: json['lastSeq'] as int,
        createdAt: json['createdAt'] as int? ?? 0,
        updatedAt: json['updatedAt'] as int? ?? _parseLastModifiedSeconds(resp),
      );
    }
    throw SyncException.fromResponse(resp);
  }

  /// Subscriber poll. Reads the R2 snapshot via the worker's edge
  /// cache. Pass [ifNoneMatch] to get a 304 when unchanged.
  Future<FetchResult> getList(String listId, {String? ifNoneMatch}) async {
    final headers = _baseHeaders();
    if (ifNoneMatch != null) headers['if-none-match'] = ifNoneMatch;
    final resp =
        await _request(method: 'GET', url: _listUrl(listId), headers: headers);
    if (resp.statusCode == 304) return FetchNotModified();
    if (resp.statusCode == 200) {
      final etag = resp.headers['etag'] ?? '';
      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      return FetchOk(
          RemoteList.fromJson(json), etag, _parseLastModifiedSeconds(resp));
    }
    throw SyncException.fromResponse(resp);
  }

  /// Authenticated full-state read. Editors + owner only; returns the
  /// snapshot with the `members` block.
  Future<ListSnapshot> getState({
    required String listId,
    required String sessionToken,
  }) async {
    final resp = await _request(
      method: 'GET',
      url: _listSubUrl(listId, 'state'),
      headers: {..._baseHeaders(), 'authorization': 'Bearer $sessionToken'},
    );
    if (resp.statusCode == 200) {
      return ListSnapshot.fromJson(
          jsonDecode(resp.body) as Map<String, dynamic>);
    }
    throw SyncException.fromResponse(resp);
  }

  /// Submit a batch of ops + receive applied outcomes, missedOps, and
  /// refreshed membership. The core editor sync endpoint.
  ///
  /// Pass an empty `ops` to do a pull-only sync.
  Future<SyncResponse> syncOps({
    required String listId,
    required int lastKnownSeq,
    required List<Map<String, dynamic>> ops,
    required String sessionToken,
    required String clientId,
  }) async {
    final body = jsonEncode({'lastKnownSeq': lastKnownSeq, 'ops': ops});
    final resp = await _request(
      method: 'POST',
      url: _listSubUrl(listId, 'sync'),
      headers: {
        ..._baseHeaders(),
        'content-type': 'application/json',
        'authorization': 'Bearer $sessionToken',
        'x-client-id': clientId,
      },
      body: body,
    );
    if (resp.statusCode == 200) {
      return SyncResponse.fromJson(
          jsonDecode(resp.body) as Map<String, dynamic>);
    }
    throw SyncException.fromResponse(resp);
  }

  /// Owner-only: mint a 7-day single-use invite token.
  Future<InviteTokenResult> createInvite({
    required String listId,
    required String sessionToken,
  }) async {
    final resp = await _request(
      method: 'POST',
      url: _listSubUrl(listId, 'invites'),
      headers: {..._baseHeaders(), 'authorization': 'Bearer $sessionToken'},
    );
    if (resp.statusCode == 200) {
      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      return InviteTokenResult(
        token: json['token'] as String,
        expiresAt: json['expiresAt'] as int,
        listId: json['listId'] as String,
      );
    }
    throw SyncException.fromResponse(resp);
  }

  /// Consume an invite token. Server adds the caller to editors and
  /// returns the full snapshot.
  Future<ListSnapshot> acceptInvite({
    required String listId,
    required String token,
    required String sessionToken,
  }) async {
    final resp = await _request(
      method: 'POST',
      url: _listSubUrl(listId, 'accept-invite'),
      headers: {
        ..._baseHeaders(),
        'content-type': 'application/json',
        'authorization': 'Bearer $sessionToken',
      },
      body: jsonEncode({'token': token}),
    );
    if (resp.statusCode == 200) {
      return ListSnapshot.fromJson(
          jsonDecode(resp.body) as Map<String, dynamic>);
    }
    throw SyncException.fromResponse(resp);
  }

  /// Remove an editor. Owner can remove any editor; editors can
  /// remove themselves with `userIdOrMe = 'me'`.
  Future<void> removeEditor({
    required String listId,
    required String userIdOrMe,
    required String sessionToken,
  }) async {
    final encoded = Uri.encodeComponent(userIdOrMe);
    final resp = await _request(
      method: 'DELETE',
      url: _listSubUrl(listId, 'editors/$encoded'),
      headers: {..._baseHeaders(), 'authorization': 'Bearer $sessionToken'},
    );
    if (resp.statusCode == 204) return;
    throw SyncException.fromResponse(resp);
  }

  /// Enumerate the caller's owned + editor list ids. Used by the
  /// post-sign-in bootstrap on a fresh device.
  Future<UserListsResult> userLists({required String sessionToken}) async {
    final resp = await _request(
      method: 'GET',
      url: _ownedListsUrl(),
      headers: {..._baseHeaders(), 'authorization': 'Bearer $sessionToken'},
    );
    if (resp.statusCode == 200) {
      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      return UserListsResult(
        ownedListIds:
            (json['ownedListIds'] as List<dynamic>?)?.cast<String>() ??
                const [],
        editorListIds:
            (json['editorListIds'] as List<dynamic>?)?.cast<String>() ??
                const [],
      );
    }
    throw SyncException.fromResponse(resp);
  }

  Future<void> deleteList(
      {required String listId, required String sessionToken}) async {
    final resp = await _request(
      method: 'DELETE',
      url: _listUrl(listId),
      headers: {..._baseHeaders(), 'authorization': 'Bearer $sessionToken'},
    );
    if (resp.statusCode == 204) return;
    throw SyncException.fromResponse(resp);
  }

  /// Owner-only: rename a shared list. Returns the updated snapshot so
  /// the caller can refresh its local display name + cursor. The server
  /// rejects non-owners with 403 and reserved / over-long names with 400.
  Future<ListSnapshot> renameList({
    required String listId,
    required String displayName,
    required String sessionToken,
  }) async {
    final resp = await _request(
      method: 'PUT',
      url: _listUrl(listId),
      headers: {
        ..._baseHeaders(),
        'content-type': 'application/json',
        'authorization': 'Bearer $sessionToken',
      },
      body: jsonEncode({'displayName': displayName}),
    );
    if (resp.statusCode == 200) {
      return ListSnapshot.fromJson(
          jsonDecode(resp.body) as Map<String, dynamic>);
    }
    throw SyncException.fromResponse(resp);
  }

  Future<http.Response> _request({
    required String method,
    required Uri url,
    required Map<String, String> headers,
    String? body,
  }) async {
    try {
      switch (method) {
        case 'GET':
          return await _client.get(url, headers: headers).timeout(timeout);
        case 'POST':
          return await _client
              .post(url, headers: headers, body: body)
              .timeout(timeout);
        case 'PUT':
          return await _client
              .put(url, headers: headers, body: body)
              .timeout(timeout);
        case 'DELETE':
          return await _client.delete(url, headers: headers).timeout(timeout);
        default:
          throw ArgumentError('unsupported method: $method');
      }
    } on TimeoutException {
      throw SyncException(SyncErrorKind.network, 'request timed out');
    } catch (e) {
      throw SyncException(SyncErrorKind.network, 'network error: $e');
    }
  }
}
