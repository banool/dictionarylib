import 'dart:convert';

import '../common.dart';
import '../globals.dart';
import 'account_sync_api.dart';

/// SharedPreferences key of the account-sync state blob. One JSON object,
/// always written whole with a single `setString`, so an app killed
/// mid-write leaves either the old blob or the new one. Removed on
/// sign-out. Not shaped like a list key (lists end in `_words`).
const String KEY_ACCOUNT_SYNC_STATE = 'account_sync_state';

/// Version of the blob's layout. A blob with another version is dropped and
/// the next cycle starts a fresh merge, which is safe: the merge only ever
/// adds (decision 5 in the plan).
const int accountSyncStateSchema = 1;

/// Where the sign-in merge has got to (section 5.4 of the plan). Saved after
/// every step so a killed app resumes where it was.
class MergePhase {
  static const String directory = 'directory';
  static const String lists = 'lists';
  static const String follows = 'follows';
  static const String history = 'history';
  static const String done = 'done';
}

/// Steps of linking one local list to a list on the account.
class LinkStep {
  /// A `createList` is (or may be) in flight with these ids. Resending with
  /// the same request id finds what the first attempt made.
  static const String create = 'create';

  /// The server list is known ([LinkingRecord.listId]); what's left is to
  /// fetch it, merge it with the local list and install the wrapper.
  static const String seed = 'seed';

  /// A list on the account with no local copy yet: the local key in the
  /// record's map key has been chosen (and maybe created) for it.
  static const String install = 'install';
}

/// Why a local list doesn't sync.
class UnsyncableReason {
  /// More than `maxEntriesPerPrivateList` signs.
  static const String tooLarge = 'too_large';

  /// Deleted on another device while this one had unsent changes to it,
  /// which are kept here as a list of their own.
  static const String keptUnsent = 'kept_unsent';

  /// The account is at its list limit.
  static const String listLimit = 'list_limit';

  /// The account refused to make it (a name it won't take, say). Tried
  /// again after a rename.
  static const String refused = 'refused';
}

/// One local list on its way to being linked, keyed in
/// [AccountSyncState.linking] by its local key. Written before the first
/// network call of the link, so a kill at any point resumes with the same
/// ids (no second list on the server).
class LinkingRecord {
  String listId;
  String? requestId;
  String step;

  /// Set when this list is to become the account's default (the device's
  /// default list on an account that has none).
  bool makeDefault;

  /// For `create`: send the name match off (the first answer matched a list
  /// this device already has linked to another of its lists).
  bool noNameMatch;

  LinkingRecord({
    required this.listId,
    this.requestId,
    required this.step,
    this.makeDefault = false,
    this.noNameMatch = false,
  });

  Map<String, dynamic> toJson() => {
    'listId': listId,
    'requestId': requestId,
    'step': step,
    if (makeDefault) 'makeDefault': true,
    if (noNameMatch) 'noNameMatch': true,
  };

  static LinkingRecord? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final listId = raw['listId'];
    final step = raw['step'];
    if (listId is! String || step is! String) return null;
    return LinkingRecord(
      listId: listId,
      requestId: raw['requestId'] as String?,
      step: step,
      makeDefault: raw['makeDefault'] == true,
      noNameMatch: raw['noNameMatch'] == true,
    );
  }
}

/// The account-sync state of this device for one signed-in account
/// (section 5.1 of the plan), persisted as [KEY_ACCOUNT_SYNC_STATE].
///
/// Beyond the plan's fields it keeps the last directory, follows and editor
/// list ids the server sent (the steady-state reconciliation compares against
/// them, and the UI reads them offline), the last reset cut-off seen, and the
/// last error kind (for the Settings status line).
class AccountSyncState {
  /// The account this state belongs to (`provider:sub`).
  String userId;

  /// The account incarnation this device merged with (see
  /// [AccountSyncResponse.incarnation]). Empty until the first response.
  String incarnation;

  /// Account op seq this device has every answer and random session up to.
  int sinceSeq;

  /// See [MergePhase].
  String mergePhase;

  /// Local key → link in progress.
  Map<String, LinkingRecord> linking;

  /// Local key → why it stays on this device (see [UnsyncableReason]).
  Map<String, String> unsyncable;

  /// Account ops not yet acknowledged, oldest first.
  List<AccountOp> pendingOps;

  /// List id → unix seconds a follow from the account was last found gone
  /// (404/410). Retried at most once a day.
  Map<String, int> followsGone;

  /// Sum of every random-mode session's count, from the last response.
  int randomTotal;

  /// Unix seconds of the last complete cycle.
  int? lastSyncAt;

  /// Unix seconds before which background cycles don't run (kill switch,
  /// rate limiting). A pull-to-refresh ignores it.
  int? pausedUntil;

  /// The reset cut-off (microseconds) last applied on this device.
  int lastResetTsUs;

  /// Synced setting key → its value (wire JSON) as last known to be the
  /// same here and on the account. A setting whose value on the device
  /// differs from this was changed here and goes up (see
  /// `synced_settings.dart`).
  Map<String, String> settingsSynced;

  /// Synced setting key → the account's value (wire JSON) as last applied
  /// or found already here. An account value equal to this isn't applied
  /// again.
  Map<String, String> settingsSeen;

  /// What the server last said.
  List<DirectoryRow> directory;
  List<String> follows;
  List<String> editorListIds;

  /// [SyncErrorKind.name] of the failure that ended the last cycle, or null
  /// if it completed.
  String? lastErrorKind;

  /// A sign-out (or account switch) has started taking this device's links
  /// away. Saved before the first wrapper goes, so a kill part way is
  /// finished at the next cycle rather than read as lists that lost their
  /// links (which, still signed in, would install the account's copies
  /// beside them).
  bool clearing;

  AccountSyncState({
    required this.userId,
    this.incarnation = '',
    this.sinceSeq = 0,
    this.mergePhase = MergePhase.directory,
    Map<String, LinkingRecord>? linking,
    Map<String, String>? unsyncable,
    List<AccountOp>? pendingOps,
    Map<String, int>? followsGone,
    this.randomTotal = 0,
    this.lastSyncAt,
    this.pausedUntil,
    this.lastResetTsUs = 0,
    Map<String, String>? settingsSynced,
    Map<String, String>? settingsSeen,
    List<DirectoryRow>? directory,
    List<String>? follows,
    List<String>? editorListIds,
    this.lastErrorKind,
    this.clearing = false,
  }) : linking = linking ?? {},
       unsyncable = unsyncable ?? {},
       pendingOps = pendingOps ?? [],
       followsGone = followsGone ?? {},
       settingsSynced = settingsSynced ?? {},
       settingsSeen = settingsSeen ?? {},
       directory = directory ?? [],
       follows = follows ?? [],
       editorListIds = editorListIds ?? [];

  bool get mergeDone => mergePhase == MergePhase.done;

  Map<String, dynamic> toJson() => {
    'schema': accountSyncStateSchema,
    'userId': userId,
    'incarnation': incarnation,
    'sinceSeq': sinceSeq,
    'mergePhase': mergePhase,
    'linking': {for (final e in linking.entries) e.key: e.value.toJson()},
    'unsyncable': unsyncable,
    'pendingOps': pendingOps.map((o) => o.toJson()).toList(),
    'followsGone': followsGone,
    'randomTotal': randomTotal,
    'lastSyncAt': lastSyncAt,
    'pausedUntil': pausedUntil,
    'lastResetTsUs': lastResetTsUs,
    'settingsSynced': settingsSynced,
    'settingsSeen': settingsSeen,
    'directory': directory.map((d) => d.toJson()).toList(),
    'follows': follows,
    'editorListIds': editorListIds,
    'lastErrorKind': lastErrorKind,
    if (clearing) 'clearing': true,
  };

  /// Null for a blob from another layout version or one that can't be read.
  static AccountSyncState? fromJson(Map<String, dynamic> json) {
    if (json['schema'] != accountSyncStateSchema) return null;
    final userId = json['userId'];
    if (userId is! String) return null;
    final linking = <String, LinkingRecord>{};
    final rawLinking = json['linking'];
    if (rawLinking is Map) {
      for (final e in rawLinking.entries) {
        final rec = LinkingRecord.fromJson(e.value);
        if (e.key is String && rec != null) linking[e.key as String] = rec;
      }
    }
    final unsyncable = <String, String>{};
    final rawUnsyncable = json['unsyncable'];
    if (rawUnsyncable is Map) {
      for (final e in rawUnsyncable.entries) {
        if (e.key is String && e.value is String) {
          unsyncable[e.key as String] = e.value as String;
        }
      }
    }
    final followsGone = <String, int>{};
    final rawGone = json['followsGone'];
    if (rawGone is Map) {
      for (final e in rawGone.entries) {
        if (e.key is String && e.value is int) {
          followsGone[e.key as String] = e.value as int;
        }
      }
    }
    Map<String, String> stringMap(Object? raw) => {
      if (raw is Map)
        for (final e in raw.entries)
          if (e.key is String && e.value is String)
            e.key as String: e.value as String,
    };
    List<String> strings(Object? raw) => [
      for (final x in (raw is List ? raw : const []))
        if (x is String) x,
    ];
    return AccountSyncState(
      userId: userId,
      incarnation: json['incarnation'] as String? ?? '',
      sinceSeq: json['sinceSeq'] as int? ?? 0,
      mergePhase: json['mergePhase'] as String? ?? MergePhase.directory,
      linking: linking,
      unsyncable: unsyncable,
      pendingOps: [
        for (final raw in (json['pendingOps'] as List<dynamic>? ?? const []))
          ?AccountOp.fromJson(raw),
      ],
      followsGone: followsGone,
      randomTotal: json['randomTotal'] as int? ?? 0,
      lastSyncAt: json['lastSyncAt'] as int?,
      pausedUntil: json['pausedUntil'] as int?,
      lastResetTsUs: json['lastResetTsUs'] as int? ?? 0,
      settingsSynced: stringMap(json['settingsSynced']),
      settingsSeen: stringMap(json['settingsSeen']),
      directory: [
        for (final raw in (json['directory'] as List<dynamic>? ?? const []))
          if (raw is Map<String, dynamic>) DirectoryRow.fromJson(raw),
      ],
      follows: strings(json['follows']),
      editorListIds: strings(json['editorListIds']),
      lastErrorKind: json['lastErrorKind'] as String?,
      clearing: json['clearing'] == true,
    );
  }

  /// The stored state, or null when there is none (signed out, never
  /// synced) or it can't be read.
  static AccountSyncState? load() {
    final raw = sharedPreferences.getString(KEY_ACCOUNT_SYNC_STATE);
    if (raw == null) return null;
    try {
      return AccountSyncState.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (e) {
      printAndLog('AccountSyncState: unreadable blob, starting again: $e');
      return null;
    }
  }

  /// Write the whole blob with one `setString`.
  Future<void> save() =>
      sharedPreferences.setString(KEY_ACCOUNT_SYNC_STATE, jsonEncode(toJson()));

  static Future<void> clear() =>
      sharedPreferences.remove(KEY_ACCOUNT_SYNC_STATE);

  /// The directory row for [listId], if the server listed it.
  DirectoryRow? rowFor(String listId) {
    for (final d in directory) {
      if (d.listId == listId) return d;
    }
    return null;
  }
}
