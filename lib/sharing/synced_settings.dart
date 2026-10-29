import 'dart:convert';

import '../common.dart';
import '../flashcards_logic.dart';
import '../globals.dart';
import '../revision.dart';
import 'account_sync_api.dart';
import 'account_sync_state.dart';
import 'synced_entry_list.dart';

/// The revision settings account sync keeps the same on every device
/// (section 5.8 of the plan). Must match `SYNCED_SETTING_KEYS` in the
/// worker's `validation.ts`.
const List<String> syncedSettingKeys = [
  KEY_SIGN_TO_WORD,
  KEY_WORD_TO_SIGN,
  KEY_REVISION_STRATEGY,
  KEY_REVISION_CARD_LIMIT,
  KEY_USE_UNKNOWN_REGION_SIGNS,
  KEY_FLASHCARD_REGIONS,
  KEY_REVISION_LANGUAGE_CODE,
  KEY_LISTS_TO_REVIEW,
];

// How changes are found: not by routing every write through a setter (the
// apps write the region settings straight to prefs), but by comparing each
// setting with the value last known to be in sync ([AccountSyncState]'s
// `settingsSynced`) at the start of every account round trip. Whatever wrote
// it, a changed setting goes up then, before the account's values are
// applied, so an incoming value never overwrites a change this device hasn't
// sent; one already sent and still unacknowledged is pending, and the
// incoming value waits for it too. Last writer, in the account's order,
// wins.

/// A list chosen for revision, on the wire: `list:<server id>` for a list on
/// the account (or one followed or edited), `community:<key>` for a
/// community list, `local:<key>` for a list on this device only (which other
/// devices drop).
List<String> encodeListsToReview(List<String> keys) {
  final community = communityEntryListManager.getEntryLists();
  final out = <String>[];
  for (final k in keys) {
    final owned = sharing.lists.ownerForSourceKey(k);
    if (owned != null) {
      out.add('list:${owned.listId}');
      continue;
    }
    final mirrored = _mirrorIdForKey(k);
    if (mirrored != null) {
      out.add('list:$mirrored');
      continue;
    }
    if (community.containsKey(k)) {
      out.add('community:$k');
      continue;
    }
    out.add('local:$k');
  }
  return out;
}

/// This device's keys for a wire selection; ones it doesn't have are left
/// out, as a chosen list that isn't found always was.
List<String> decodeListsToReview(List<String> wire) {
  final community = communityEntryListManager.getEntryLists();
  final local = userEntryListManager.getEntryLists();
  final out = <String>[];
  for (final w in wire) {
    final i = w.indexOf(':');
    if (i < 0) continue;
    final kind = w.substring(0, i);
    final value = w.substring(i + 1);
    switch (kind) {
      case 'list':
        final wrapper = sharing.lists.get(value);
        if (wrapper == null) break;
        out.add(wrapper.key);
      case 'community':
        if (community.containsKey(value)) out.add(value);
      case 'local':
        if (local.containsKey(value)) out.add(value);
    }
  }
  return out;
}

String? _mirrorIdForKey(String key) {
  for (final l in [
    ...sharing.lists.editorLists,
    ...sharing.lists.subscribedLists,
  ]) {
    if (l.key == key) return l.listId;
  }
  return null;
}

/// [key]'s value as the account stores it (JSON), or null when unset here.
String? settingWireValue(String key) {
  final v = sharedPreferences.get(key);
  if (v == null) return null;
  if (key == KEY_LISTS_TO_REVIEW && v is List) {
    return jsonEncode(encodeListsToReview(v.cast<String>()));
  }
  if (v is bool || v is int || v is String) return jsonEncode(v);
  if (v is List) return jsonEncode(v.cast<String>());
  return null;
}

/// Whether [v] (decoded) is a value this build can store for [key]: the
/// right type, and in range where a wrong one would break a page (a value
/// from a newer build may not be).
bool _validSetting(String key, Object? v) {
  switch (key) {
    case KEY_SIGN_TO_WORD:
    case KEY_WORD_TO_SIGN:
    case KEY_USE_UNKNOWN_REGION_SIGNS:
      return v is bool;
    case KEY_REVISION_STRATEGY:
      return v is int && v >= 0 && v < RevisionStrategy.values.length;
    case KEY_REVISION_CARD_LIMIT:
      return v is int && revisionCardLimitOptions.contains(v);
    case KEY_REVISION_LANGUAGE_CODE:
      return v is String;
    case KEY_FLASHCARD_REGIONS:
      return v is List &&
          v.every((e) => e is String && int.tryParse(e) != null);
    case KEY_LISTS_TO_REVIEW:
      return v is List && v.every((e) => e is String);
  }
  return false;
}

/// Store an account [value] for [key] on this device. Returns false, and
/// stores nothing, for a value this build can't use.
bool applySettingWireValue(String key, String value) {
  Object? decoded;
  try {
    decoded = jsonDecode(value);
  } catch (_) {
    // Unreadable: refused below like any other unusable value.
  }
  if (!_validSetting(key, decoded)) {
    printAndLog('AccountSync: ignoring setting $key: $value');
    return false;
  }
  if (key == KEY_LISTS_TO_REVIEW) {
    sharedPreferences.setStringList(
      key,
      decodeListsToReview((decoded as List).cast<String>()),
    );
    return true;
  }
  switch (decoded) {
    case bool b:
      sharedPreferences.setBool(key, b);
    case int n:
      sharedPreferences.setInt(key, n);
    case String s:
      sharedPreferences.setString(key, s);
    case List l:
      sharedPreferences.setStringList(key, l.cast<String>());
  }
  return true;
}

/// Settings changed here since they were last in sync, as `setSetting` ops;
/// marks them in sync (they're pending from here on).
List<AccountOp> detectSettingChanges(AccountSyncState st) {
  final ops = <AccountOp>[];
  for (final key in syncedSettingKeys) {
    final current = settingWireValue(key);
    if (current == null || current == st.settingsSynced[key]) continue;
    ops.add(
      AccountOp(
        opId: generateOpId(),
        type: 'setSetting',
        args: {'key': key, 'value': current},
      ),
    );
    st.settingsSynced[key] = current;
  }
  return ops;
}

/// Apply the account's [settings]: each value the account holds that this
/// device hasn't applied yet, except for keys in [pendingKeys] (a change
/// from here is on its way and will be the last writer) and, unless
/// [accountWins] (the sign-in merge), keys changed here since the last
/// round trip looked (they go up with the next one).
void applyIncomingSettings(
  AccountSyncState st,
  List<SettingValue> settings,
  Set<String?> pendingKeys, {
  bool accountWins = false,
}) {
  for (final s in settings) {
    if (!syncedSettingKeys.contains(s.key)) continue;
    if (pendingKeys.contains(s.key)) continue;
    if (st.settingsSeen[s.key] == s.value) continue;
    final current = settingWireValue(s.key);
    if (!accountWins &&
        current != null &&
        current != st.settingsSynced[s.key]) {
      continue;
    }
    st.settingsSeen[s.key] = s.value;
    // A value this build can't use (from a newer build, say) stays on the
    // account; this device keeps its own and doesn't send it over that.
    if (current != s.value && !applySettingWireValue(s.key, s.value)) {
      if (current != null) st.settingsSynced[s.key] = current;
      continue;
    }
    // What this device now holds, as change detection will see it: for the
    // lists to revise that can be less than what came (lists this device
    // doesn't have are left out), and it must not read as a change to send
    // back, or two devices would whittle each other's selection down.
    st.settingsSynced[s.key] = settingWireValue(s.key) ?? s.value;
    // A chosen list that is on the account but not yet on this device (its
    // install still to come) is picked up by applying the value again later.
    if (s.key == KEY_LISTS_TO_REVIEW && _awaitsInstall(st, s.value)) {
      st.settingsSeen.remove(s.key);
    }
  }
}

bool _awaitsInstall(AccountSyncState st, String wire) {
  final Object? decoded;
  try {
    decoded = jsonDecode(wire);
  } catch (_) {
    return false;
  }
  if (decoded is! List) return false;
  for (final w in decoded.whereType<String>()) {
    if (!w.startsWith('list:')) continue;
    final id = w.substring(5);
    if (sharing.lists.get(id) != null) continue;
    if (st.directory.any((d) => d.listId == id && d.isLive)) return true;
  }
  return false;
}
