import 'package:dictionarylib/globals.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

/// Shared prefs for tests that care about what reaches disk and in what
/// order — above all, what's left there if the app dies part-way through a
/// run of writes.
///
/// The app talks to prefs through a cache that takes every write at once
/// and passes it on to the platform, which persists writes in the order it
/// gets them. So the states a crash can leave behind are exactly the
/// prefixes of the write sequence. [RecordingPrefsStore] logs that
/// sequence, and [replayWrites] rebuilds any prefix of it.

const String _prefix = 'flutter.';

/// One write as the platform saw it. A null [value] is a removal.
class PrefsWrite {
  PrefsWrite.set(this.key, Object value) : value = _copy(value);
  PrefsWrite.remove(this.key) : value = null;

  /// The key as the app names it (without the plugin's prefix).
  final String key;
  final Object? value;

  @override
  String toString() => value == null ? 'remove $key' : 'set $key = $value';
}

class RecordingPrefsStore extends InMemorySharedPreferencesStore {
  RecordingPrefsStore(Map<String, Object> values)
    : super.withData({
        for (final e in values.entries) '$_prefix${e.key}': _copy(e.value),
      });

  /// Every write since the store was created, oldest first.
  final List<PrefsWrite> writes = [];

  @override
  Future<bool> setValue(String valueType, String key, Object value) {
    writes.add(PrefsWrite.set(_unprefixed(key), value));
    return super.setValue(valueType, key, value);
  }

  @override
  Future<bool> remove(String key) {
    writes.add(PrefsWrite.remove(_unprefixed(key)));
    return super.remove(key);
  }
}

/// Point the app's [sharedPreferences] at a fresh store holding [values],
/// as if it had just launched with them on disk.
Future<RecordingPrefsStore> installPrefs(Map<String, Object> values) async {
  final store = RecordingPrefsStore(values);
  SharedPreferencesStorePlatform.instance = store;
  SharedPreferences.resetStatic();
  sharedPreferences = await SharedPreferences.getInstance();
  return store;
}

/// Everything the app's prefs hold right now.
Map<String, Object> prefsSnapshot() => {
  for (final key in sharedPreferences.getKeys())
    key: _copy(sharedPreferences.get(key)!),
};

/// [initial] with the first [count] of [writes] applied: what would be on
/// disk had the app died at that point.
Map<String, Object> replayWrites(
  Map<String, Object> initial,
  List<PrefsWrite> writes,
  int count,
) {
  final out = {for (final e in initial.entries) e.key: _copy(e.value)};
  for (final write in writes.take(count)) {
    final value = write.value;
    if (value == null) {
      out.remove(write.key);
    } else {
      out[write.key] = _copy(value);
    }
  }
  return out;
}

String _unprefixed(String key) =>
    key.startsWith(_prefix) ? key.substring(_prefix.length) : key;

/// Lists are copied so that a later mutation of the original can't rewrite
/// history.
Object _copy(Object value) => value is List ? List<String>.from(value) : value;
