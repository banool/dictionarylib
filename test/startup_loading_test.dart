import 'package:dictionarylib/app_bootstrap.dart';
import 'package:dictionarylib/common.dart';
import 'package:dictionarylib/data_fetch.dart';
import 'package:dictionarylib/entry_loader.dart';
import 'package:dictionarylib/entry_types.dart';
import 'package:dictionarylib/globals.dart';
import 'package:dictionarylib/startup_loading.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '_helpers.dart' show kTestSharingConfig;

class _FakeLoader extends EntryLoader {
  @override
  Set<Entry> loadEntriesInner(String data) => {};

  @override
  Future<NewData?> downloadNewData(
    int currentVersion,
    bool forceDownload, {
    Duration requestTimeout = kDataFetchTimeout,
  }) async => null;
}

final _config = DictAppBootstrapConfig(
  advisoriesUrl: Uri.parse('https://example.com/advisories.md'),
  yankedVersionsUrl: 'https://example.com/yanked_versions',
  knobUrlBase: 'https://example.com/knobs/',
  setupMediaAndEntryLoader: () async => _FakeLoader(),
  sharingConfig: kTestSharingConfig,
  buildStartupLogo: (context) => const FlutterLogo(),
);

void main() {
  late _FakeLoader loader;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    sharedPreferences = await SharedPreferences.getInstance();
    loader = _FakeLoader();
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(StartupLoadingApp(config: _config, loader: loader));
    await tester.pump();
  }

  LinearProgressIndicator bar(WidgetTester tester) =>
      tester.widget(find.byType(LinearProgressIndicator));

  testWidgets('before any status: title, logo, indeterminate bar', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('Downloading dictionary data…'), findsOneWidget);
    expect(find.byType(FlutterLogo), findsOneWidget);
    expect(bar(tester).value, null);
  });

  testWidgets('checking shows the host, and the attempt line iff >1 source', (
    tester,
  ) async {
    await pump(tester);
    loader.reportDownloadStatus(
      DictionaryDownloadStatus(
        stage: DictionaryDownloadStage.checking,
        url: Uri.parse('https://cdn.auslandictionary.org/data/latest_version'),
        urlIndex: 1,
        urlCount: 2,
      ),
    );
    await tester.pump();
    expect(
      find.text('Connecting to cdn.auslandictionary.org…'),
      findsOneWidget,
    );
    expect(find.text('Attempt 2 of 2'), findsOneWidget);

    loader.reportDownloadStatus(
      DictionaryDownloadStatus(
        stage: DictionaryDownloadStage.checking,
        url: Uri.parse('https://cdn.srilankansignlanguage.org/dump/dump.json'),
      ),
    );
    await tester.pump();
    expect(find.textContaining('Attempt'), findsNothing);
  });

  testWidgets('downloading with a total: determinate bar and MB of MB', (
    tester,
  ) async {
    await pump(tester);
    loader.reportDownloadStatus(
      DictionaryDownloadStatus(
        stage: DictionaryDownloadStage.downloading,
        url: Uri.parse('https://example.com/data-v2.json'),
        receivedBytes: 7 * 1024 * 1024,
        totalBytes: 14 * 1024 * 1024,
      ),
    );
    await tester.pump();
    expect(bar(tester).value, closeTo(0.5, 0.001));
    expect(find.text('7.0 MB of 14.0 MB'), findsOneWidget);
  });

  testWidgets('downloading without a total: indeterminate bar and MB count', (
    tester,
  ) async {
    await pump(tester);
    loader.reportDownloadStatus(
      DictionaryDownloadStatus(
        stage: DictionaryDownloadStage.downloading,
        url: Uri.parse('https://example.com/data-v2.json'),
        receivedBytes: 3 * 1024 * 1024 + 512 * 1024,
      ),
    );
    await tester.pump();
    expect(bar(tester).value, null);
    expect(find.text('3.5 MB downloaded'), findsOneWidget);
  });

  testWidgets('applying shows the preparing copy', (tester) async {
    await pump(tester);
    loader.reportDownloadStatus(
      const DictionaryDownloadStatus(stage: DictionaryDownloadStage.applying),
    );
    await tester.pump();
    expect(find.text('Preparing the dictionary…'), findsOneWidget);
    expect(bar(tester).value, null);
  });
}
