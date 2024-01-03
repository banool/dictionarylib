import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:launch_review/launch_review.dart';
import 'package:mailto/mailto.dart';
import 'package:settings_ui/settings_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import 'common.dart';
import 'flashcards_logic.dart';
import 'globals.dart';
import 'l10n/app_localizations.dart';
import 'page_settings_help_en.dart';
import 'top_level_scaffold.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage(
      {super.key,
      required this.mainColor,
      required this.appBarDisabledColor,
      required this.additionalTopWidgets,
      required this.buildLegalInformationChildren,
      required this.reportDataProblemUrl,
      required this.reportAppProblemUrl,
      required this.appName,
      required this.iOSAppId,
      required this.androidAppId});

  final String appName;
  final Color mainColor;
  final Color appBarDisabledColor;
  final List<Widget> additionalTopWidgets;
  final List<Widget> Function(Color mainColor) buildLegalInformationChildren;
  final String reportDataProblemUrl;
  final String reportAppProblemUrl;
  final String iOSAppId;
  final String androidAppId;

  @override
  SettingsPageState createState() => SettingsPageState();
}

class SettingsPageState extends State<SettingsPage> {
  bool checkingForNewData = false;

  void onChangeShouldCache(bool newValue) {
    setState(() {
      sharedPreferences.setBool(KEY_SHOULD_CACHE, newValue);
    });
  }

  void onChangeHideFlashcardsFeature(bool newValue) {
    setState(() {
      sharedPreferences.setBool(KEY_HIDE_FLASHCARDS_FEATURE, newValue);
      //myHomePageController.toggleFlashcards(newValue);
    });
  }

  @override
  Widget build(BuildContext context) {
    String? appStoreTileString;
    if (kIsWeb) {
      appStoreTileString = null;
    } else if (Platform.isAndroid) {
      appStoreTileString =
          AppLocalizations.of(context)!.settingsPlayStoreFeedback;
    } else if (Platform.isIOS) {
      appStoreTileString =
          AppLocalizations.of(context)!.settingsAppStoreFeedback;
    }

    EdgeInsetsDirectional margin = const EdgeInsetsDirectional.only(
        start: 15, end: 15, top: 10, bottom: 10);

    SettingsSection? featuresSection;
    if (enableFlashcardsKnob && !getShouldUseHorizontalLayout(context)) {
      featuresSection = SettingsSection(
        title: Text(AppLocalizations.of(context)!.settingsRevision),
        tiles: [
          SettingsTile.switchTile(
            title: Text(
              AppLocalizations.of(context)!.settingsHideRevision,
              style: const TextStyle(fontSize: 15),
            ),
            initialValue:
                sharedPreferences.getBool(KEY_HIDE_FLASHCARDS_FEATURE) ?? false,
            onToggle: onChangeHideFlashcardsFeature,
          ),
          SettingsTile.navigation(
              title: getText(
                AppLocalizations.of(context)!.settingsDeleteRevisionProgress,
              ),
              trailing: Container(),
              onPressed: (BuildContext context) async {
                bool confirmed = await confirmAlert(
                    context,
                    Text(AppLocalizations.of(context)!
                        .settingsDeleteRevisionProgressExplanation));
                if (confirmed) {
                  await writeReviews([], [], force: true);
                  await sharedPreferences.setInt(KEY_RANDOM_REVIEWS_COUNTER, 0);
                  await sharedPreferences.remove(KEY_FIRST_RANDOM_REVIEW);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(
                        AppLocalizations.of(context)!.settingsProgressDeleted),
                    backgroundColor: widget.mainColor,
                  ));
                }
              }),
        ],
        margin: margin,
      );
    }

    List<AbstractSettingsSection?> sections = [
      SettingsSection(
        title: Text(AppLocalizations.of(context)!.settingsCache),
        tiles: [
          SettingsTile.switchTile(
            title: Text(
              AppLocalizations.of(context)!.settingsCacheVideos,
              style: const TextStyle(fontSize: 15),
            ),
            initialValue: sharedPreferences.getBool(KEY_SHOULD_CACHE) ?? true,
            onToggle: onChangeShouldCache,
          ),
          SettingsTile.navigation(
              title: getText(AppLocalizations.of(context)!.settingsDropCache),
              trailing: Container(),
              onPressed: (BuildContext context) async {
                await myCacheManager.emptyCache();
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content:
                      Text(AppLocalizations.of(context)!.settingsCacheDropped),
                  backgroundColor: widget.mainColor,
                ));
              }),
        ],
        margin: margin,
      ),
      SettingsSection(
        title: Text(AppLocalizations.of(context)!.settingsData),
        tiles: [
          SettingsTile.navigation(
            title: checkingForNewData
                ? const Center(
                    child: CircularProgressIndicator(),
                  )
                : getText(AppLocalizations.of(context)!.settingsCheckNewData),
            trailing: Container(),
            onPressed: (BuildContext context) async {
              setState(() {
                checkingForNewData = true;
              });
              bool thereWasNewData = await entryLoader.updateWordsData(true);
              setState(() {
                checkingForNewData = false;
              });
              String message;
              if (thereWasNewData) {
                message = AppLocalizations.of(context)!.settingsDataUpdated;
              } else {
                message = AppLocalizations.of(context)!.settingsDataUpToDate;
              }
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(message), backgroundColor: widget.mainColor));
            },
          )
        ],
        margin: margin,
      ),
      featuresSection,
      SettingsSection(
        title: Text(AppLocalizations.of(context)!.settingsLegal),
        tiles: [
          SettingsTile.navigation(
            title: getText(AppLocalizations.of(context)!.settingsSeeLegal),
            trailing: Container(),
            onPressed: (BuildContext context) async {
              return await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => LegalInformationPage(
                        mainColor: widget.mainColor,
                        buildLegalInformationChildren:
                            widget.buildLegalInformationChildren),
                  ));
            },
          )
        ],
        margin: margin,
      ),
      SettingsSection(
          title: Text(AppLocalizations.of(context)!.settingsHelp),
          tiles: [
            SettingsTile.navigation(
              title: getText(AppLocalizations.of(context)!
                  .settingsReportDictionaryDataIssue),
              trailing: Container(),
              onPressed: (BuildContext context) async {
                await launch(widget.reportDataProblemUrl, forceSafariVC: false);
              },
            ),
            SettingsTile.navigation(
              title: getText(
                  AppLocalizations.of(context)!.settingsReportAppIssueGithub),
              trailing: Container(),
              onPressed: (BuildContext context) async {
                await launch(widget.reportAppProblemUrl, forceSafariVC: false);
              },
            ),
            SettingsTile.navigation(
              title: getText(
                  AppLocalizations.of(context)!.settingsReportAppIssueEmail),
              trailing: Container(),
              onPressed: (BuildContext context) async {
                var mailto = Mailto(
                    to: ['d@dport.me'],
                    subject: 'Issue with ${widget.appName}',
                    body:
                        'Please describe the issue in detail.\n\n--> Replace with description of issue <--\n\n${getBugInfo()}\nBackground logs:\n${backgroundLogs.items.join("\n")}\n');
                String url = "$mailto";
                if (await canLaunch(url)) {
                  await launch(url);
                } else {
                  printAndLog('Could not launch $url');
                }
              },
            ),
            appStoreTileString != null
                ? SettingsTile.navigation(
                    title: getText(appStoreTileString),
                    trailing: Container(),
                    onPressed: (BuildContext context) async {
                      await LaunchReview.launch(
                          iOSAppId: widget.iOSAppId,
                          androidAppId: widget.androidAppId,
                          writeReview: true);
                    },
                  )
                : null,
            SettingsTile.navigation(
              title: getText(
                AppLocalizations.of(context)!.settingsShowBuildInformation,
              ),
              trailing: Container(),
              onPressed: (BuildContext context) async {
                return await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const BuildInformationPage(),
                    ));
              },
            ),
            SettingsTile.navigation(
                title: getText(
                    AppLocalizations.of(context)!.settingsBackgroundLogs),
                trailing: Container(),
                onPressed: (BuildContext context) async {
                  return await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            BackgroundLogsPage(mainColor: widget.mainColor),
                      ));
                }),
          ].where((element) => element != null).cast<SettingsTile>().toList(),
          margin: margin),
    ];

    List<AbstractSettingsSection> nonNullSections = [];
    for (AbstractSettingsSection? section in sections) {
      if (section != null) {
        nonNullSections.add(section);
      }
    }

    Widget body =
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ...widget.additionalTopWidgets,
      Expanded(child: SettingsList(sections: nonNullSections))
    ]);

    List<Widget> actions = [
      buildActionButton(
        context,
        const Icon(Icons.help),
        () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => getSettingsHelpPageEn()),
          );
        },
        widget.appBarDisabledColor,
      )
    ];

    return TopLevelScaffold(
        body: body,
        title: AppLocalizations.of(context)!.settingsTitle,
        mainColor: widget.mainColor,
        actions: actions);
  }
}

String getBugInfo() {
  String info = "Package and device info:\n";
  if (packageInfo != null) {
    info += "App version: ${packageInfo!.version}\n";
    info += "Build number: ${packageInfo!.buildNumber}\n";
  }
  if (iosDeviceInfo != null) {
    info += "Device: ${iosDeviceInfo!.name}\n";
    info += "Model: ${iosDeviceInfo!.model}\n";
    info += "System name: ${iosDeviceInfo!.systemName}\n";
    info += "System version: ${iosDeviceInfo!.systemVersion}\n";
  }
  if (androidDeviceInfo != null) {
    info += "Device: ${androidDeviceInfo!.device}\n";
    info += "Model: ${androidDeviceInfo!.model}\n";
    info += "System name: ${androidDeviceInfo!.version.release}\n";
    info += "System version: ${androidDeviceInfo!.version.sdkInt}\n";
  }
  return info;
}

class LegalInformationPage extends StatelessWidget {
  const LegalInformationPage(
      {super.key,
      required this.mainColor,
      required this.buildLegalInformationChildren});

  final Color mainColor;
  final List<Widget> Function(Color mainColor) buildLegalInformationChildren;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: const Text("Legal Information"),
        ),
        body: Padding(
            padding:
                const EdgeInsets.only(bottom: 10, left: 20, right: 32, top: 20),
            child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                mainAxisSize: MainAxisSize.max,
                children: buildLegalInformationChildren(mainColor))));
  }
}

class BuildInformationPage extends StatelessWidget {
  const BuildInformationPage({super.key});

  @override
  Widget build(BuildContext context) {
    List<Widget> children = [];
    if (packageInfo != null) {
      children.add(getText("App version: ${packageInfo!.version}"));
      children.add(getText("Build number: ${packageInfo!.buildNumber}"));
    }
    if (iosDeviceInfo != null) {
      children.add(getText("Device: ${iosDeviceInfo!.name}"));
      children.add(getText("Model: ${iosDeviceInfo!.model}"));
      children.add(getText("System name: ${iosDeviceInfo!.systemName}"));
      children.add(getText("System version: ${iosDeviceInfo!.systemVersion}"));
    }
    if (androidDeviceInfo != null) {
      children.add(getText("Device: ${androidDeviceInfo!.device}"));
      children.add(getText("Model: ${androidDeviceInfo!.model}"));
      children
          .add(getText("System name: ${androidDeviceInfo!.version.release}"));
      children
          .add(getText("System version: ${androidDeviceInfo!.version.sdkInt}"));
    }
    return Scaffold(
        appBar: AppBar(
          title: const Text("Build Information"),
        ),
        body: Padding(
            padding:
                const EdgeInsets.only(bottom: 10, left: 20, right: 32, top: 20),
            child: Center(
                child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: children,
            ))));
  }
}

class BackgroundLogsPage extends StatelessWidget {
  const BackgroundLogsPage({super.key, required this.mainColor});

  final Color mainColor;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: const Text("Background Logs"),
        ),
        body: Padding(
            padding:
                const EdgeInsets.only(bottom: 10, left: 20, right: 32, top: 20),
            child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                mainAxisSize: MainAxisSize.max,
                children: [
                  TextButton(
                    child: Text("Copy logs to clipboard",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: mainColor)),
                    onPressed: () async {
                      await Clipboard.setData(
                          ClipboardData(text: backgroundLogs.items.join("\n")));
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: const Text("Logs copied to clipboard"),
                          backgroundColor: mainColor));
                    },
                  ),
                  Container(
                    padding: const EdgeInsets.only(top: 10),
                  ),
                  Expanded(
                      child: SingleChildScrollView(
                          scrollDirection: Axis.vertical,
                          child: Text(backgroundLogs.items.join("\n"),
                              style: const TextStyle(
                                  height:
                                      1.8 //You can set your custom height here
                                  )))),
                ])));
  }
}
