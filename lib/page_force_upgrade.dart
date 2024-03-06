import 'dart:io';

import 'package:launch_review/launch_review.dart';
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:http/http.dart' as http;

import 'common.dart';
import 'globals.dart';

abstract class YankedVersionChecker {
  /// Private. Just can't mark it as such bc unimplemented private superclass
  /// methods don't play nice.
  Future<List<String>> getYankedVersions();

  // Call this after setupPhaseOne, since that's where we set up the package info.
  Future<void> throwIfShouldUpgrade() async {
    if (packageInfo == null) {
      printAndLog(
          "packageInfo is null, can't decide whether app is a yanked version. Not forcing upgrade.");
      return;
    }
    var version = packageInfo!.version;
    var yankedVersions = await getYankedVersions();
    printAndLog("App version: $version // Yanked versions: $yankedVersions");

    if (yankedVersions.contains(version)) {
      printAndLog(
          "User is running yanked version, throwing exception to force upgrade");
      throw YankedVersionError(version, yankedVersions);
    }
  }
}

class YankedVersionError extends Error {
  final String version;
  final List<String> yankedVersions;

  YankedVersionError(this.version, this.yankedVersions);
}

// We set a short timeout because if we fail to get the yanked versions and it
// turns out they're running a yanked version, the worst case is just that
// they'll go to the error fallback page instead, which is just more confusing.
// Given most people will not be on yanked versions we don't want to make this
// add too much startup latency.
class GitHubYankedVersionChecker extends YankedVersionChecker {
  final String uri;

  GitHubYankedVersionChecker(this.uri);

  @override
  Future<List<String>> getYankedVersions() async {
    try {
      var response = await http
          .get(Uri.parse(uri))
          .timeout(const Duration(milliseconds: 2250));
      if (response.statusCode != 200) {
        throw "HTTP response for getting yanked versions was non 200: ${response.statusCode}";
      }
      return response.body.split("\n");
    } catch (e) {
      printAndLog(
          "Failed to get yanked versions, continuing without raising an error: $e");
      return [];
    }
  }
}

// If we see that the app is using a yanked version, we show this page.
class ForceUpgradePage extends StatelessWidget {
  final YankedVersionError error;
  final String iOSAppId;
  final String androidAppId;

  const ForceUpgradePage(
      {super.key,
      required this.error,
      required this.iOSAppId,
      required this.androidAppId});

  @override
  Widget build(BuildContext context) {
    // Remove the splash screen.
    FlutterNativeSplash.remove();

    Widget updateButton = Container();
    if (Platform.isIOS || Platform.isAndroid) {
      updateButton = OutlinedButton(
          onPressed: () async {
            await LaunchReview.launch(
                iOSAppId: iOSAppId,
                androidAppId: androidAppId,
                writeReview: true);
          },
          child: const Text("Update"));
    }

    List<Widget> children = [
      const Padding(padding: EdgeInsets.only(top: 50)),
      Text(
        "You are using an unsupported version (${error.version}) of the app, please update.",
        textAlign: TextAlign.center,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      const Padding(padding: EdgeInsets.only(top: 20)),
      updateButton,
    ];

    return MaterialApp(
        title: "Update",
        debugShowCheckedModeBanner: false,
        home: Scaffold(
            body: Padding(
                padding: const EdgeInsets.all(40),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          children: children,
                        ),
                      ),
                    ),
                  ],
                ))));
  }
}
