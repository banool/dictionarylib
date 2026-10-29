import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import '../analytics.dart';
import '../common.dart';
import '../globals.dart';
import 'synced_entry_list.dart';

/// Telling a restored or cloned install from the original (section 5.10 of
/// the plan).
///
/// A phone restored from a backup brings SharedPreferences with it, and on
/// iOS the keychain session too, so it starts as a clone of the old phone,
/// down to its `KEY_SHARED_CLIENT_ID`. The marker is something that does
/// not travel: on iOS a keychain item readable on this device only, which
/// isn't migrated to a new one; on Android a file in the app's support
/// directory, which both apps' backup rules exclude. Found prefs and no
/// marker means a restore: the clone gets a client id of its own. Nothing
/// else needs changing, because every queued op is idempotent by its op id
/// (list ops, account ops, answer batches, random sessions).
const String _markerName = 'install_marker';

/// Prefs flag set once the marker has been written on this install. It
/// travels with a backup while the marker doesn't, which is what tells a
/// restore ("flag, no marker") from the first launch of a build with the
/// marker on an existing install ("no flag, no marker"; the plan's rule,
/// a stored client id without a marker, would count every upgrading
/// person who has used sharing as a restore).
const String KEY_INSTALL_MARKER_WRITTEN = 'install_marker_written';

/// iOS: readable once the device has been unlocked after a restart, and
/// never migrated to another device. (The plan named
/// `unlocked_this_device`; `first_unlock_this_device` has the same "this
/// device only" property and is also readable in the rare launch before the
/// device is unlocked, which would otherwise look like a restore.)
const IOSOptions _iosOptions = IOSOptions(
  accessibility: KeychainAccessibility.first_unlock_this_device,
);

enum InstallKind { normal, fresh, restored }

/// Check the marker and act on what it says. Call after prefs are loaded
/// and before sharing is set up (nothing may have read the client id yet).
/// Never throws: a failure to read or write the marker is logged and the
/// install treated as normal (the safe answer: nothing changes).
Future<InstallKind> checkInstallMarker({
  FlutterSecureStorage? secureStorage,
  Future<Directory> Function()? supportDirectory,
}) async {
  if (kIsWeb) return InstallKind.normal;
  try {
    final present = await _readMarker(secureStorage, supportDirectory);
    if (present) {
      if (sharedPreferences.getBool(KEY_INSTALL_MARKER_WRITTEN) != true) {
        await sharedPreferences.setBool(KEY_INSTALL_MARKER_WRITTEN, true);
      }
      return InstallKind.normal;
    }
    final wasMarked =
        sharedPreferences.getBool(KEY_INSTALL_MARKER_WRITTEN) == true;
    final hadClientId =
        (sharedPreferences.getString(KEY_SHARED_CLIENT_ID) ?? '').isNotEmpty;
    await _writeMarker(secureStorage, supportDirectory);
    await sharedPreferences.setBool(KEY_INSTALL_MARKER_WRITTEN, true);
    if (!wasMarked || !hadClientId) return InstallKind.fresh;
    // Restored from a backup (or cloned): this install gets a client id of
    // its own, so the server can tell the two apart.
    await regenerateClientId();
    printAndLog('Install marker missing with a stored client id: restored');
    Analytics.track('restore_detected');
    return InstallKind.restored;
  } catch (e) {
    printAndLog('Install marker check failed: $e');
    return InstallKind.normal;
  }
}

Future<bool> _readMarker(
  FlutterSecureStorage? secureStorage,
  Future<Directory> Function()? supportDirectory,
) async {
  if (Platform.isIOS || Platform.isMacOS) {
    final storage = secureStorage ?? const FlutterSecureStorage();
    return await storage.read(key: _markerName, iOptions: _iosOptions) != null;
  }
  final dir = await (supportDirectory ?? getApplicationSupportDirectory)();
  return File('${dir.path}/$_markerName').exists();
}

Future<void> _writeMarker(
  FlutterSecureStorage? secureStorage,
  Future<Directory> Function()? supportDirectory,
) async {
  if (Platform.isIOS || Platform.isMacOS) {
    final storage = secureStorage ?? const FlutterSecureStorage();
    await storage.write(key: _markerName, value: '1', iOptions: _iosOptions);
    return;
  }
  final dir = await (supportDirectory ?? getApplicationSupportDirectory)();
  await dir.create(recursive: true);
  await File('${dir.path}/$_markerName').writeAsString('1', flush: true);
}
