import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';

import 'advisories.dart';
import 'globals.dart';
import 'page_settings.dart';

// When the app fails to load we show this widget instead.
class ErrorFallback extends StatelessWidget {
  final Object error;
  final StackTrace stackTrace;
  final String appName;

  const ErrorFallback(
      {super.key,
      required this.error,
      required this.stackTrace,
      required this.appName});

  @override
  Widget build(BuildContext context) {
    // Remove the splash screen.
    FlutterNativeSplash.remove();

    Widget advisoryWidget;
    if (advisoriesResponse == null) {
      advisoryWidget = Container();
    } else {
      advisoryWidget = getAdvisoriesInner();
    }
    List<Widget> children = [
      const Padding(padding: EdgeInsets.only(top: 50)),
      const Text(
        "Failed to start the app correctly. First, please confirm you are using the latest version of the app. Go to the App Store / Play Store and look for an update. If you are using the latest version, please email daniel@dport.me with a screenshot showing this error. You might need to take multiple screenshots to capture it all. Apologies for the issue and thanks in advance for reporting it!",
        textAlign: TextAlign.center,
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      const Padding(padding: EdgeInsets.only(top: 20)),
      const Text(
        "If this is your first time using the app, make sure you are connected to the internet so we can download the data!",
        textAlign: TextAlign.center,
      ),
      const Padding(padding: EdgeInsets.only(top: 30)),
      const Text(
        "Advisories",
        textAlign: TextAlign.center,
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      advisoryWidget,
      const Padding(padding: EdgeInsets.only(top: 30)),
      const Text(
        "Error",
        textAlign: TextAlign.center,
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      Text(
        "$error",
        textAlign: TextAlign.center,
      ),
      Text(
        "$stackTrace",
      ),
      const Padding(padding: EdgeInsets.only(top: 20)),
      const Text(
        "Background logs",
        textAlign: TextAlign.center,
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      const Padding(padding: EdgeInsets.only(top: 20)),
      Text(backgroundLogs.items.join("\n")),
      const Padding(padding: EdgeInsets.only(top: 20)),
    ];
    try {
      String s = "";
      for (String key in sharedPreferences.getKeys()) {
        s += "$key: ${sharedPreferences.get(key).toString()}\n";
      }
      children.add(const Text(
        "Shared Preferences",
        textAlign: TextAlign.center,
        style: TextStyle(fontWeight: FontWeight.bold),
      ));
      children.add(Text(
        s,
        textAlign: TextAlign.left,
      ));
    } catch (e) {
      children.add(Text("Failed to get shared prefs: $e"));
    }

    var packageDeviceInfo = getPackageDeviceInfo();
    children.add(const Padding(padding: EdgeInsets.only(top: 20)));
    children.add(const Text(
      "Package and device info",
      textAlign: TextAlign.center,
      style: TextStyle(fontWeight: FontWeight.bold),
    ));
    children.addAll(packageDeviceInfo);

    return MaterialApp(
        title: appName,
        debugShowCheckedModeBanner: false,
        home: Scaffold(
            body: Padding(
                padding: const EdgeInsets.all(15),
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
