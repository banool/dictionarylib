import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app_links_platform_interface/app_links_platform_interface.dart';
import 'package:dictionarylib/common.dart';
import 'package:dictionarylib/entry_list.dart';
import 'package:dictionarylib/entry_loader.dart';
import 'package:dictionarylib/entry_types.dart';
import 'package:dictionarylib/globals.dart';
import 'package:dictionarylib/list_storage.dart';
import 'package:dictionarylib/lists_service.dart';
import 'package:dictionarylib/saved_video.dart';
import 'package:dictionarylib/sharing/sharing.dart';
import 'package:dictionarylib/sharing/synced_entry_list.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import '../_helpers.dart';
import '../_recording_prefs.dart';

/// Sharing starting up while a background dictionary refresh is still in
/// flight, which is what every warm start with new data waiting looks like.
///
/// This goes through the real startup sequence (loadEntriesIntoGlobal, then
/// setupSharing, as setupDictionaryApp does) and the real Sharing.setup,
/// with only the order of the two waits pinned. The other sharing tests
/// install a ready-made instance instead, so nothing else would notice
/// Sharing.setup taking hold of the user's lists at the wrong moment. A
/// second pre-release review of the default-list change found exactly that.

SavedVideo _video(String entry) =>
    SavedVideo(entryKey: entry, mediaPath: videoFor(entry));

String _v3(String entry) => _video(entry).toStorage();

const List<String> _words = ['apple', 'banana', 'cherry', 'dog', 'eel'];

const String _key = 'Favourites_words';
const String _shareId = 'own000000001';

String _ownerMeta(String id, String source) => jsonEncode(
  SyncedListMeta(
    listId: id,
    displayName: 'Tiny Tunks',
    role: ListRole.owner,
    lastKnownSeq: 4,
    etag: null,
    lastSyncedAt: 1700000000,
    serverUpdatedAt: 1700000001,
    orphaned: false,
    sourceLocalKey: source,
  ).toJson(),
);

/// An already-migrated install whose default list is shared from this
/// device.
Map<String, Object> _installWithSharedDefaultList() => {
  KEY_ENTRY_LIST_KEYS: [_key, 'Zoo_words'],
  KEY_DEFAULT_LIST_KEY: _key,
  _key: [_v3('apple')],
  listSchemaVersionKey(_key): 3,
  'Zoo_words': [_v3('dog')],
  listSchemaVersionKey('Zoo_words'): 3,
  KEY_SHARED_LIST_IDS: [_shareId],
  sharedMetaStorageKey(_shareId): _ownerMeta(_shareId, _key),
};

/// A loader whose background download finishes when the test says so, the
/// way a real one finishes whenever the network gets round to it.
class _GatedLoader extends EntryLoader {
  _GatedLoader(this._entries);

  final Set<Entry> _entries;

  /// Completes once the background refresh has asked for new data.
  final Completer<void> downloadStarted = Completer<void>();

  /// Complete this to let the download return.
  final Completer<void> downloadGate = Completer<void>();

  /// Completes when the refreshed data has been applied.
  final Completer<void> refreshApplied = Completer<void>();

  int _applied = 0;

  @override
  Set<Entry> loadEntriesInner(String data) => _entries;

  @override
  Future<NewData?> downloadNewData(
    int currentVersion,
    bool forceDownload, {
    Duration requestTimeout = kDataFetchTimeout,
  }) async {
    if (!downloadStarted.isCompleted) downloadStarted.complete();
    await downloadGate.future;
    return NewData('{"data": []}', currentVersion, currentVersion + 1);
  }

  @override
  void setEntriesGlobal(Set<Entry> entries) {
    super.setEntriesGlobal(entries);
    _applied++;
    if (_applied == 2 && !refreshApplied.isCompleted) refreshApplied.complete();
  }
}

/// A launch with no deep link, and none arriving later.
class _NoDeepLinks extends AppLinksPlatform {
  @override
  Future<Uri?> getInitialLink() async => null;

  @override
  Stream<Uri> get uriLinkStream => const Stream<Uri>.empty();
}

/// Hands out [path] as the documents directory.
class _DocumentsIn extends PathProviderPlatform {
  _DocumentsIn(this.path);

  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

void main() {
  late Completer<void> secureStorageGate;
  late Directory documents;
  late AppLinksPlatform realAppLinks;
  late PathProviderPlatform realPathProvider;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    // Reading the session back from the Keychain / Keystore takes as long as
    // the platform takes; here, until the test lets it through.
    secureStorageGate = Completer<void>();
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        if (call.method == 'read') await secureStorageGate.future;
        return null;
      },
    );
    // No deep link on this launch, and a temporary directory for the
    // downloaded dictionary to be written to. Both are set on the plugins'
    // platform interfaces rather than by mocking their channels, so they
    // hold whichever implementation the machine running the tests would
    // otherwise pick (the Linux ones don't go through channels at all).
    realAppLinks = AppLinksPlatform.instance;
    AppLinksPlatform.instance = _NoDeepLinks();
    documents = Directory.systemTemp.createTempSync('sharing_startup_refresh');
    realPathProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _DocumentsIn(documents.path);

    seedDictionary(_words);
    entriesGlobal = {};
    startingLocale = LOCALE_ENGLISH;
    sharing = Sharing.disabled();
  });

  tearDown(() {
    if (!secureStorageGate.isCompleted) secureStorageGate.complete();
    if (sharing.isEnabled) sharing.dispose();
    sharing = Sharing.disabled();
    entriesGlobal = {};
    AppLinksPlatform.instance = realAppLinks;
    PathProviderPlatform.instance = realPathProvider;
    if (documents.existsSync()) documents.deleteSync(recursive: true);
  });

  group('a dictionary refresh that lands while sharing is starting up', () {
    // setEntriesGlobal skips rebuilding the user's lists "once sharing is
    // up", judged by sharing.isEnabled. Sharing.setup used to take hold of
    // the list objects (SyncedEntryListManager.fromStartup) and only then
    // wait for the session to be read from secure storage and for the
    // deep-link plugin; the `sharing` global was assigned after that wait. A
    // background refresh whose download completed inside the wait still saw
    // isEnabled == false, rebuilt the lists, and left the share holding the
    // old objects: two copies of the list, one the share edited and one
    // everything else read. Sharing.setup now does its waiting first.
    Future<void> launch({required bool refreshLandsMidSetup}) async {
      await installPrefs(_installWithSharedDefaultList());
      final entries = <Entry>{
        for (final w in _words) FakeEntry(w, videos: [videoFor(w)]),
      };
      final loader = _GatedLoader(entries);

      // Warm start: the cached dictionary loads, the lists are built, and a
      // background check for new data goes out.
      await loadEntriesIntoGlobal(loader, entriesGlobalReplacement: entries);
      await loader.downloadStarted.future;

      // Sharing starts. It finds the lists and waits on secure storage.
      final sharingUp = setupSharing(kTestSharingConfig);
      await Future<void>.delayed(Duration.zero);
      expect(sharing.isEnabled, isFalse, reason: 'still waiting on storage');

      if (refreshLandsMidSetup) {
        // The new data arrives and is applied, then secure storage answers
        // and sharing finishes starting.
        loader.downloadGate.complete();
        await loader.refreshApplied.future;
        secureStorageGate.complete();
        await sharingUp;
      } else {
        // The other way round: sharing is up before the new data arrives.
        secureStorageGate.complete();
        await sharingUp;
        loader.downloadGate.complete();
        await loader.refreshApplied.future;
      }
      expect(sharing.isEnabled, isTrue);
    }

    void expectShareAndListsPageOnTheSameList() {
      final share = sharing.lists.ownerForSourceKey(_key);
      expect(share, isNotNull, reason: 'the share loaded');
      final list = userEntryListManager.getEntryLists()[_key]!;
      expect(
        identical(share!.savedVideos, list.savedVideos),
        isTrue,
        reason:
            'the share wraps a different copy of the list from the one the '
            'Lists page, revision and the save sheet read',
      );
    }

    test('control: a refresh that lands after sharing is up leaves the '
        'share and the Lists page on the same list', () async {
      await launch(refreshLandsMidSetup: false);
      expectShareAndListsPageOnTheSameList();
    });

    test('leaves the share and the Lists page on the same list', () async {
      await launch(refreshLandsMidSetup: true);
      expectShareAndListsPageOnTheSameList();
    });

    test('does not lose a sign saved to the shared list once it is '
        'unshared', () async {
      await launch(refreshLandsMidSetup: true);

      // Save a sign through the share (what the save sheet does for a
      // shared list), stop sharing, save another sign, restart.
      final share = sharing.lists.ownerForSourceKey(_key)!;
      await share.addVideo(_video('cherry'));
      await listsService.unshareList(share);
      await userEntryListManager.getEntryLists()[_key]!.addVideo(_video('eel'));

      await installPrefs(prefsSnapshot());
      sharing.dispose();
      sharing = Sharing.disabled();
      userEntryListManager = UserEntryListManager.fromStartup();
      expect(
        userEntryListManager.getEntryLists()[_key]!.savedVideos.map(
          (v) => v.entryKey,
        ),
        ['apple', 'cherry', 'eel'],
      );
    });
  });
}
