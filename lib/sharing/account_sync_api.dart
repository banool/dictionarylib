import 'sync_api.dart';
import 'sync_clock.dart';

/// Wire shapes for `POST /v1/account/sync`, the one call behind account
/// sync. Mirrors `AccountSyncResponse` and the op handlers in
/// `workers/src/account_do.ts` in the private backend repo; every field the
/// client reads is optional or defaulted so a newer server's additions are
/// ignored and an older one's absences don't throw.
///
/// The request is `{clientId, sinceSeq, ops}` (at most 50 ops and 64 KiB).
/// Every op is idempotent in effect, so resending after a lost response is
/// safe: within the server's retained log it answers `duplicate` with the
/// first application's [AccountOpResult].

// Op `reasonCode`s. Mirror the worker's `OP_REJECT_REASON_*`.
const String accountReasonNotPrivate = 'not_private';
const String accountReasonListLimit = 'list_limit';
const String accountReasonIdCollision = 'id_collision';
const String accountReasonRetry = 'retry';
const String accountReasonDefaultList = 'default_list';
const String accountReasonStillLive = 'still_live';
const String accountReasonInvalid = 'invalid';
const String accountReasonNotFound = 'not_found';
const String accountReasonUnknownType = 'unknown_type';
const String accountReasonFollowLimit = 'follow_limit';
const String accountReasonForbidden = 'forbidden';

/// A list `rename` to a reserved name while the list is shared (list /sync).
const String listReasonReserved = 'reserved';

/// Not a refusal: applied, changing nothing, because a later intent (by
/// client time) holds. On `rename` (list and account), `reorder`,
/// `setDefault` and `setSetting`.
const String reasonStale = 'stale';

/// One queued account op. [opId] is the server's dedupe key; ops that must
/// never count twice (a random session, a batch of answers) derive it from
/// their content or their origin rather than at random.
class AccountOp {
  final String opId;
  final String type;
  final Map<String, dynamic> args;

  /// Unix seconds on this device when the op was made. The account orders
  /// `rename`, `reorder`, `setDefault` and `setSetting` by it (the later
  /// intent wins, whichever device's op arrives last), and keeps a
  /// `delete`'s as the time unsent edits elsewhere are compared against.
  /// Null only for an op saved by a build before it existed (the account
  /// then takes its own time).
  final int? clientTs;

  AccountOp({
    required this.opId,
    required this.type,
    required this.args,
    int? clientTs,
    bool stampNow = true,
  }) : clientTs = clientTs ?? (stampNow ? syncNowSecs() : null);

  Map<String, dynamic> toJson() => {
    'opId': opId,
    'type': type,
    'args': args,
    'clientTs': ?clientTs,
  };

  static AccountOp? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final opId = raw['opId'];
    final type = raw['type'];
    final args = raw['args'];
    if (opId is! String || type is! String || args is! Map) return null;
    final clientTs = raw['clientTs'];
    return AccountOp(
      opId: opId,
      type: type,
      args: Map<String, dynamic>.from(args),
      clientTs: clientTs is int ? clientTs : null,
      stampNow: false,
    );
  }
}

/// Op-specific data on an outcome: `createList` sets [listId] and
/// [created]; `addReviews` the four counts.
class AccountOpResult {
  final String? listId;
  final bool? created;
  final int? accepted;
  final int? duplicates;
  final int? rejectedBeforeReset;
  final int? invalid;

  const AccountOpResult({
    this.listId,
    this.created,
    this.accepted,
    this.duplicates,
    this.rejectedBeforeReset,
    this.invalid,
  });

  factory AccountOpResult.fromJson(Map<String, dynamic> json) =>
      AccountOpResult(
        listId: json['listId'] as String?,
        created: json['created'] as bool?,
        accepted: json['accepted'] as int?,
        duplicates: json['duplicates'] as int?,
        rejectedBeforeReset: json['rejectedBeforeReset'] as int?,
        invalid: json['invalid'] as int?,
      );
}

class AccountOpOutcome {
  final String opId;
  final OpStatus status;
  final int? seq;
  final String? reason;
  final String? reasonCode;
  final AccountOpResult? result;

  const AccountOpOutcome({
    required this.opId,
    required this.status,
    this.seq,
    this.reason,
    this.reasonCode,
    this.result,
  });

  /// Applied now or earlier: the op has taken effect and can leave the
  /// queue.
  bool get isDone => status == OpStatus.applied || status == OpStatus.duplicate;

  /// Refused for now; the same op should be sent again later.
  bool get shouldRetry =>
      status == OpStatus.rejected && reasonCode == accountReasonRetry;

  factory AccountOpOutcome.fromJson(Map<String, dynamic> json) {
    final result = json['result'];
    return AccountOpOutcome(
      opId: json['opId'] as String,
      status: switch (json['status']) {
        'applied' => OpStatus.applied,
        'duplicate' => OpStatus.duplicate,
        _ => OpStatus.rejected,
      },
      seq: json['seq'] as int?,
      reason: json['reason'] as String?,
      reasonCode: json['reasonCode'] as String?,
      result: result is Map<String, dynamic>
          ? AccountOpResult.fromJson(result)
          : null,
    );
  }
}

/// Lifecycle of a list in the account directory.
const String directoryStateCreating = 'creating';
const String directoryStateLive = 'live';
const String directoryStateDeleted = 'deleted';

/// One of the person's lists, as the account directory knows it.
class DirectoryRow {
  final String listId;
  final int position;
  final bool isDefault;
  final String visibility;

  /// The list's name as the directory last heard it. The list itself is
  /// the authority; this is what the sign-in merge matches names against.
  final String name;
  final String state;

  /// Unix seconds; null unless [state] is `deleted`.
  final int? deletedAt;

  /// The deleting device's clock (unix seconds, clamped by the account)
  /// when it was deleted; null when nobody knows (found gone by `unlink`).
  /// Unsent edits here newer than this restore the list (section 5.5).
  final int? deletedClientTs;

  const DirectoryRow({
    required this.listId,
    required this.position,
    required this.isDefault,
    required this.visibility,
    required this.name,
    required this.state,
    this.deletedAt,
    this.deletedClientTs,
  });

  bool get isLive => state == directoryStateLive;
  bool get isDeleted => state == directoryStateDeleted;

  factory DirectoryRow.fromJson(Map<String, dynamic> json) => DirectoryRow(
    listId: json['listId'] as String,
    position: json['position'] as int? ?? 0,
    isDefault: json['isDefault'] as bool? ?? false,
    visibility: parseVisibility(json['visibility']),
    name: json['name'] as String? ?? '',
    state: json['state'] as String? ?? directoryStateLive,
    deletedAt: json['deletedAt'] as int?,
    deletedClientTs: json['deletedClientTs'] as int?,
  );

  Map<String, dynamic> toJson() => {
    'listId': listId,
    'position': position,
    'isDefault': isDefault,
    'visibility': visibility,
    'name': name,
    'state': state,
    'deletedAt': deletedAt,
    'deletedClientTs': deletedClientTs,
  };
}

/// A synced revision setting; [value] is JSON.
class SettingValue {
  final String key;
  final String value;
  final int seq;
  const SettingValue({
    required this.key,
    required this.value,
    required this.seq,
  });
  factory SettingValue.fromJson(Map<String, dynamic> json) => SettingValue(
    key: json['key'] as String,
    value: json['value'] as String,
    seq: json['seq'] as int? ?? 0,
  );
}

/// One flashcard answer as the server stores it: master, combination
/// (`<front>@@@<back>`), rating index, time in microseconds, and the op seq
/// that stored it.
class RemoteReview {
  final String m;
  final String c;
  final int r;
  final int t;
  final int seq;
  const RemoteReview({
    required this.m,
    required this.c,
    required this.r,
    required this.t,
    required this.seq,
  });
  factory RemoteReview.fromJson(Map<String, dynamic> json) => RemoteReview(
    m: json['m'] as String,
    c: json['c'] as String,
    r: json['r'] as int,
    t: json['t'] as int,
    seq: json['seq'] as int? ?? 0,
  );
}

class RandomSessionRow {
  final String opId;
  final int count;
  final int tsUs;
  final int seq;
  const RandomSessionRow({
    required this.opId,
    required this.count,
    required this.tsUs,
    required this.seq,
  });
  factory RandomSessionRow.fromJson(Map<String, dynamic> json) =>
      RandomSessionRow(
        opId: json['opId'] as String,
        count: json['count'] as int,
        tsUs: json['tsUs'] as int,
        seq: json['seq'] as int? ?? 0,
      );
}

class AccountSyncResponse {
  /// Random id of this incarnation of the account. It changes when the
  /// account is deleted (and a later sign-in starts a new one); a device
  /// that sees it change was linked to lists of an account that no longer
  /// exists.
  final String incarnation;

  /// The account's op sequence now.
  final int seq;

  /// What to save as the next `sinceSeq` once this page's answers and
  /// random sessions are stored. Equal to [seq] unless [hasMore].
  final int nextSinceSeq;
  final List<AccountOpOutcome> results;
  final List<DirectoryRow> directory;
  final List<String> follows;
  final List<SettingValue> settings;
  final int resetTsUs;
  final int randomTotal;
  final List<RemoteReview> reviews;
  final List<RandomSessionRow> randomSessions;
  final bool hasMore;
  final List<String> editorListIds;

  const AccountSyncResponse({
    required this.incarnation,
    required this.seq,
    required this.nextSinceSeq,
    required this.results,
    required this.directory,
    required this.follows,
    required this.settings,
    required this.resetTsUs,
    required this.randomTotal,
    required this.reviews,
    required this.randomSessions,
    required this.hasMore,
    required this.editorListIds,
  });

  factory AccountSyncResponse.fromJson(Map<String, dynamic> json) {
    List<T> list<T>(String key, T Function(Map<String, dynamic>) parse) => [
      for (final item in (json[key] as List<dynamic>? ?? const []))
        if (item is Map<String, dynamic>) parse(item),
    ];
    final seq = json['seq'] as int? ?? 0;
    return AccountSyncResponse(
      incarnation: json['incarnation'] as String? ?? '',
      seq: seq,
      nextSinceSeq: json['nextSinceSeq'] as int? ?? seq,
      results: list('results', AccountOpOutcome.fromJson),
      directory: list('directory', DirectoryRow.fromJson),
      follows: [
        for (final f in (json['follows'] as List<dynamic>? ?? const []))
          if (f is String) f,
      ],
      settings: list('settings', SettingValue.fromJson),
      resetTsUs: json['resetTsUs'] as int? ?? 0,
      randomTotal: json['randomTotal'] as int? ?? 0,
      reviews: list('reviews', RemoteReview.fromJson),
      randomSessions: list('randomSessions', RandomSessionRow.fromJson),
      hasMore: json['hasMore'] as bool? ?? false,
      editorListIds: [
        for (final f in (json['editorListIds'] as List<dynamic>? ?? const []))
          if (f is String) f,
      ],
    );
  }

  /// The outcome for [opId] in this response, if it was in the request.
  AccountOpOutcome? outcomeFor(String opId) {
    for (final r in results) {
      if (r.opId == opId) return r;
    }
    return null;
  }
}
