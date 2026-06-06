import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:store_redirect/store_redirect.dart';
import 'package:mailto/mailto.dart';
import 'package:url_launcher/url_launcher.dart';

import 'common.dart';
import 'entry_loader.dart';
import 'flashcards_logic.dart';
import 'globals.dart';
import 'hearth.dart';
import 'l10n/app_localizations.dart';
import 'lists_service.dart';
import 'page_privacy_policy.dart';
import 'page_settings_help_en.dart';
import 'theme.dart';
import 'sharing/auth/auth_store.dart';
import 'sharing/auth/sign_in_dialog.dart';
import 'sharing/sync_api.dart';
import 'top_level_scaffold.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.additionalTopWidgets,
    required this.buildLegalInformationChildren,
    required this.reportDataProblemUrl,
    required this.reportAppProblemUrl,
    required this.appName,
    required this.iOSAppId,
    required this.androidAppId,
    required this.showPrivacyPolicy,
  });

  final String appName;
  final List<Widget> additionalTopWidgets;
  final List<Widget> Function() buildLegalInformationChildren;
  final String reportDataProblemUrl;
  final String reportAppProblemUrl;
  final String iOSAppId;
  final String androidAppId;
  final bool showPrivacyPolicy;

  @override
  SettingsPageState createState() => SettingsPageState();
}

class SettingsPageState extends State<SettingsPage> {
  bool checkingForNewData = false;

  @override
  void initState() {
    super.initState();
    if (widget.showPrivacyPolicy) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) => PrivacyPolicyPage(
                    appName: widget.appName, email: PRIVACY_POLICY_EMAIL)));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final l = DictLibLocalizations.of(context)!;
    String? appStoreTileString;
    if (kIsWeb) {
      appStoreTileString = null;
    } else if (Platform.isAndroid) {
      appStoreTileString = l.settingsPlayStoreFeedback;
    } else if (Platform.isIOS) {
      appStoreTileString = l.settingsAppStoreFeedback;
    }

    // --- Bespoke Hearth settings rows ---
    // A tappable navigation row; [value] shows the current setting on the
    // right (before the chevron). With no value it shows a bare chevron.
    Widget navRow(String title, {String? value, VoidCallback? onTap}) {
      Widget? trailing;
      if (value != null) {
        trailing = Row(mainAxisSize: MainAxisSize.min, children: [
          Flexible(
            child: Text(value,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14)),
          ),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
        ]);
      }
      return HearthRow(title: title, onTap: onTap, trailing: trailing);
    }

    // A toggle row. The Material Switch picks up the Hearth switchTheme
    // (clay track) automatically.
    Widget switchRow(String title, bool value, ValueChanged<bool> onChanged) {
      return HearthRow(
        title: title,
        onTap: () => onChanged(!value),
        trailing: Switch(value: value, onChanged: onChanged),
      );
    }

    // A labelled section: an uppercase header over an outlined card of rows
    // separated by hairline dividers. Null rows (conditional tiles) drop out.
    List<Widget> section(String title, List<Widget?> rows) {
      final clean = rows.whereType<Widget>().toList();
      if (clean.isEmpty) return const [];
      return [
        HearthSectionLabel(title,
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 8)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: HearthRowGroup(rows: clean),
        ),
      ];
    }

    final shareState = sharing;
    final session = shareState.isEnabled ? shareState.auth.store.current : null;

    final children = <Widget>[
      ...widget.additionalTopWidgets,
      ...section(l.settingsAppearance, [
        navRow(l.settingsColourMode, value: _getThemeModeString(context),
            onTap: () async {
          await showDialog(
            context: context,
            builder: (BuildContext context) {
              var currentMode = sharedPreferences.getInt(KEY_THEME_MODE) ?? 0;
              return AlertDialog(
                title: Text(l.settingsColourMode),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      title: Text(l.settingsColourModeSystem),
                      trailing: currentMode == ThemeMode.system.index
                          ? const Icon(Icons.check)
                          : null,
                      onTap: () {
                        _setThemeMode(ThemeMode.system);
                        Navigator.of(context).pop();
                      },
                    ),
                    ListTile(
                      title: Text(l.settingsColourModeLight),
                      trailing: currentMode == ThemeMode.light.index
                          ? const Icon(Icons.check)
                          : null,
                      onTap: () {
                        _setThemeMode(ThemeMode.light);
                        Navigator.of(context).pop();
                      },
                    ),
                    ListTile(
                      title: Text(l.settingsColourModeDark),
                      trailing: currentMode == ThemeMode.dark.index
                          ? const Icon(Icons.check)
                          : null,
                      onTap: () {
                        _setThemeMode(ThemeMode.dark);
                        Navigator.of(context).pop();
                      },
                    ),
                  ],
                ),
              );
            },
          );
          setState(() {});
        }),
        navRow(l.settingsAppTheme,
            value: themeVariantNotifier.value.displayName, onTap: () async {
          await showDialog(
            context: context,
            builder: (BuildContext context) {
              final current = themeVariantNotifier.value;
              return AlertDialog(
                title: Text(l.settingsAppTheme),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final variant in AppThemeVariant.values)
                      ListTile(
                        title: Text(variant.displayName),
                        trailing: current == variant
                            ? const Icon(Icons.check)
                            : null,
                        onTap: () {
                          _setThemeVariant(variant);
                          Navigator.of(context).pop();
                        },
                      ),
                  ],
                ),
              );
            },
          );
          setState(() {});
        }),
      ]),
      ...section(l.settingsCache, [
        switchRow(l.settingsCacheVideos,
            sharedPreferences.getBool(KEY_SHOULD_CACHE) ?? true, (newValue) {
          setState(() => sharedPreferences.setBool(KEY_SHOULD_CACHE, newValue));
        }),
        navRow(l.settingsDropCache, onTap: () async {
          await myCacheManager.emptyCache();
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l.settingsCacheDropped)));
        }),
      ]),
      ...section(l.settingsData, [
        checkingForNewData
            ? const HearthRow(
                title: '',
                trailing: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2)),
              )
            : navRow(l.settingsCheckNewData, onTap: () async {
                setState(() => checkingForNewData = true);
                NewData? newData =
                    await entryLoader.downloadAndApplyNewData(true);
                if (!mounted) return;
                setState(() => checkingForNewData = false);
                final message = (newData != null && newData.newDataIsActuallyNew())
                    ? l.settingsDataUpdated
                    : l.settingsDataUpToDate;
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(message), backgroundColor: cs.primary));
              }),
        if (communityEntryListManager.getEntryLists().isNotEmpty)
          switchRow(l.settingsHideCommunityLists,
              sharedPreferences.getBool(KEY_HIDE_COMMUNITY_LISTS) ?? false,
              (newValue) {
            setState(() =>
                sharedPreferences.setBool(KEY_HIDE_COMMUNITY_LISTS, newValue));
          }),
      ]),
      if (enableFlashcardsKnob && !kIsWeb)
        ...section(l.settingsRevision, [
          switchRow(l.settingsHideRevision,
              sharedPreferences.getBool(KEY_HIDE_FLASHCARDS_FEATURE) ?? false,
              (newValue) {
            setState(() => sharedPreferences.setBool(
                KEY_HIDE_FLASHCARDS_FEATURE, newValue));
          }),
          navRow(l.settingsDeleteRevisionProgress, onTap: () async {
            bool confirmed = await confirmAlert(
                context, Text(l.settingsDeleteRevisionProgressExplanation));
            if (confirmed) {
              await writeReviews([], [], force: true);
              await sharedPreferences.setInt(KEY_RANDOM_REVIEWS_COUNTER, 0);
              await sharedPreferences.remove(KEY_FIRST_RANDOM_REVIEW);
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l.settingsProgressDeleted)));
            }
          }),
        ]),
      if (shareState.isEnabled)
        ...section(l.settingsSharing, [
          if (session == null)
            navRow(l.settingsSignIn, onTap: () async {
              final result = await showSignInDialog(context);
              if (result != null && context.mounted) {
                await offerImportOwnedLists(context);
              }
              if (mounted) setState(() {});
            })
          else ...[
            HearthRow(
                title: session.displayName.isNotEmpty
                    ? l.settingsSignedInAsNamed(
                        session.displayName, _providerLabel(l, session.provider))
                    : l.settingsSignedInAs(
                        _providerLabel(l, session.provider))),
            navRow(l.settingsSignOut, onTap: () async {
              final pendingLists = shareState.lists.editableLists
                  .where((x) => x.meta.pendingOps.isNotEmpty)
                  .toList();
              final body = pendingLists.isNotEmpty
                  ? l.settingsSignOutConfirmBodyWithPending(pendingLists.length)
                  : l.settingsSignOutConfirmBody;
              final confirmed = await confirmAlert(context, Text(body),
                  title: l.settingsSignOutConfirmTitle);
              if (confirmed) {
                await shareState.signOut();
                if (mounted) setState(() {});
              }
            }),
          ],
          navRow(l.settingsClearSharingData, onTap: () async {
            final confirmed = await confirmAlert(
                context, Text(l.settingsClearSharingDataConfirmBody),
                title: l.settingsClearSharingDataConfirmTitle);
            if (confirmed) {
              await shareState.signOut();
              await shareState.lists.clearAll();
              shareState.bumpState();
              if (mounted) setState(() {});
            }
          }),
        ]),
      ...section(l.settingsLegal, [
        navRow(l.settingsSeeLegal, onTap: () async {
          await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => LegalInformationPage(
                    buildLegalInformationChildren:
                        widget.buildLegalInformationChildren),
              ));
        }),
        navRow(l.settingsSeePrivacyPolicy, onTap: () async {
          await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => PrivacyPolicyPage(
                    appName: widget.appName, email: PRIVACY_POLICY_EMAIL),
              ));
        }),
      ]),
      ...section(l.settingsHelp, [
        navRow(l.settingsReportDictionaryDataIssue, onTap: () async {
          await launchUrl(Uri.parse(widget.reportDataProblemUrl),
              mode: LaunchMode.externalApplication);
        }),
        navRow(l.settingsReportAppIssueGithub, onTap: () async {
          await launchUrl(Uri.parse(widget.reportAppProblemUrl),
              mode: LaunchMode.externalApplication);
        }),
        navRow(l.settingsReportAppIssueEmail, onTap: () async {
          var mailto = Mailto(
              to: ['d@dport.me'],
              subject: l.reportIssueEmailSubject(widget.appName),
              body:
                  'Please describe the issue in detail.\n\n--> Replace with description of issue <--\n\n${getBugInfo()}\nBackground logs:\n${backgroundLogs.items.join("\n")}\n');
          final uri = Uri.parse("$mailto");
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri);
          } else {
            printAndLog('Could not launch $uri');
          }
        }),
        if (appStoreTileString != null)
          navRow(appStoreTileString, onTap: () async {
            await StoreRedirect.redirect(
                iOSAppId: widget.iOSAppId, androidAppId: widget.androidAppId);
          }),
        navRow(l.settingsShowBuildInformation, onTap: () async {
          await Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (context) => const BuildInformationPage()));
        }),
        navRow(l.settingsBackgroundLogs, onTap: () async {
          await Navigator.push(context,
              MaterialPageRoute(builder: (context) => BackgroundLogsPage()));
        }),
      ]),
      ...section(l.settingsNetwork, [
        switchRow(l.settingsUseSystemHttpProxy,
            sharedPreferences.getBool(KEY_USE_SYSTEM_HTTP_PROXY) ?? false,
            (newValue) {
          setState(() =>
              sharedPreferences.setBool(KEY_USE_SYSTEM_HTTP_PROXY, newValue));
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l.settingsRestartApp)));
        }),
      ]),
      const SizedBox(height: 12),
    ];

    Widget body = ListView(
      padding: const EdgeInsets.only(top: 4),
      children: children,
    );

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
      )
    ];

    return TopLevelScaffold(
        body: body, title: l.settingsTitle, actions: actions);
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
      {super.key, required this.buildLegalInformationChildren});

  final List<Widget> Function() buildLegalInformationChildren;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title:
              Text(DictLibLocalizations.of(context)!.legalInformationPageTitle),
        ),
        // Comfortable long-form reading layout, matching the privacy page.
        body: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
              children: buildLegalInformationChildren(),
            ),
          ),
        ));
  }
}

List<Widget> getPackageDeviceInfo() {
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
    children.add(getText("System name: ${androidDeviceInfo!.version.release}"));
    children
        .add(getText("System version: ${androidDeviceInfo!.version.sdkInt}"));
  }
  return children;
}

class BuildInformationPage extends StatelessWidget {
  const BuildInformationPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title:
              Text(DictLibLocalizations.of(context)!.buildInformationPageTitle),
        ),
        body: Padding(
            padding:
                const EdgeInsets.only(bottom: 10, left: 20, right: 32, top: 20),
            child: Center(
                child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: getPackageDeviceInfo(),
            ))));
  }
}

class BackgroundLogsPage extends StatelessWidget {
  const BackgroundLogsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l = DictLibLocalizations.of(context)!;
    return Scaffold(
        appBar: AppBar(
          title: Text(l.backgroundLogsPageTitle),
        ),
        body: Padding(
            padding:
                const EdgeInsets.only(bottom: 10, left: 20, right: 32, top: 20),
            child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                mainAxisSize: MainAxisSize.max,
                children: [
                  TextButton(
                    child: Text(l.backgroundLogsCopyButton,
                        textAlign: TextAlign.center),
                    onPressed: () async {
                      await Clipboard.setData(
                          ClipboardData(text: backgroundLogs.items.join("\n")));
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(l.backgroundLogsCopiedSnack),
                      ));
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

String _providerLabel(DictLibLocalizations l, AuthProvider provider) {
  switch (provider) {
    case AuthProvider.apple:
      return l.providerApple;
    case AuthProvider.google:
      return l.providerGoogle;
    case AuthProvider.facebook:
      return l.providerFacebook;
    case AuthProvider.test:
      return l.providerTest;
  }
}

String _getThemeModeString(BuildContext context) {
  // Default to light mode.
  var themeMode =
      sharedPreferences.getInt(KEY_THEME_MODE) ?? DEFAULT_THEME_MODE;
  switch (themeMode) {
    case 0:
      return DictLibLocalizations.of(context)!.settingsColourModeSystem;
    case 1:
      return DictLibLocalizations.of(context)!.settingsColourModeLight;
    case 2:
      return DictLibLocalizations.of(context)!.settingsColourModeDark;
    default:
      throw ArgumentError("Unknown theme mode: $themeMode");
  }
}

Future<void> _setThemeMode(ThemeMode themeMode) async {
  // We set this to control which theme we load at startup.
  await sharedPreferences.setInt(KEY_THEME_MODE, themeMode.index);
  // We set this to affect the theme at runtime.
  themeNotifier.value = themeMode;
}

Future<void> _setThemeVariant(AppThemeVariant variant) async {
  // Persisted by name so we load the same look at startup.
  await sharedPreferences.setString(KEY_THEME_VARIANT, variant.name);
  // Drives the live theme switch via the app's MaterialApp.
  themeVariantNotifier.value = variant;
}

/// Prompt the user about pulling down any lists owned by their current
/// signed-in account, then run the import + show a summary. Designed to
/// be called right after sign-in completes (typically from the Settings
/// sign-in flow on a fresh install).
Future<void> offerImportOwnedLists(BuildContext context) async {
  final l = DictLibLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.of(context);
  // Capture the result via closure so we can format the snackbar after
  // [runWithProgress] returns success.
  ImportOwnedListsResult? result;
  final go = await confirmAlert(
    context,
    Text(l.importOwnedListsPromptBody),
    title: l.importOwnedListsPromptTitle,
    confirmText: l.importOwnedListsActionImport,
    cancelText: l.importOwnedListsActionSkip,
  );
  if (!go || !context.mounted) return;

  final ok = await runWithProgress(
    context: context,
    message: l.importOwnedListsRunning,
    task: () async =>
        result = await listsService.importOwnedLists(context: context),
    errorMessage: (e) =>
        e is SyncException ? l.importOwnedListsFailed(e.message) : '$e',
  );
  if (!ok || result == null) return;
  final r = result!;
  messenger.showSnackBar(SnackBar(
    content: Text(r.total == 0
        ? l.importOwnedListsResultNone
        : l.importOwnedListsResultDone(r.imported, r.total)),
  ));
}
