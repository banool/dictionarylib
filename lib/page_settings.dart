import 'dart:async';
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
    required this.privacyPolicyUrl,
    required this.termsOfServiceUrl,
  });

  final String appName;
  final List<Widget> additionalTopWidgets;
  final List<Widget> Function() buildLegalInformationChildren;
  final String reportDataProblemUrl;
  final String reportAppProblemUrl;
  final String iOSAppId;
  final String androidAppId;

  /// The privacy policy and terms of service are hosted on the app's website
  /// (the single source of truth) rather than rendered in-app; these are the
  /// URLs the Legal section links out to.
  final String privacyPolicyUrl;
  final String termsOfServiceUrl;

  @override
  SettingsPageState createState() => SettingsPageState();
}

class SettingsPageState extends State<SettingsPage> {
  bool checkingForNewData = false;

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
          final current = ThemeMode
              .values[sharedPreferences.getInt(KEY_THEME_MODE) ?? DEFAULT_THEME_MODE];
          final chosen = await showHearthPicker<ThemeMode>(
            context: context,
            title: l.settingsColourMode,
            selected: current,
            options: [
              HearthPickerOption(ThemeMode.system, l.settingsColourModeSystem),
              HearthPickerOption(ThemeMode.light, l.settingsColourModeLight),
              HearthPickerOption(ThemeMode.dark, l.settingsColourModeDark),
            ],
          );
          if (chosen != null) await _setThemeMode(chosen);
          if (mounted) setState(() {});
        }),
        navRow(l.settingsAppTheme,
            value: themeVariantNotifier.value.displayName, onTap: () async {
          final chosen = await showHearthPicker<AppThemeVariant>(
            context: context,
            title: l.settingsAppTheme,
            selected: themeVariantNotifier.value,
            options: [
              for (final variant in AppThemeVariant.values)
                HearthPickerOption(variant, variant.displayName),
            ],
          );
          if (chosen != null) await _setThemeVariant(chosen);
          if (mounted) setState(() {});
        }),
      ]),
      if (shareState.isEnabled)
        ...section(l.settingsSharing, [
          if (session == null)
            navRow(l.settingsSignIn, onTap: () async {
              final result = await showSignInDialog(context);
              if (result != null) {
                // Kick a sync fire-and-forget so any edits queued while
                // signed out drain immediately — same nudge the resume
                // banner and expiry-snack sign-in paths give.
                unawaited(sharing.engine.syncAll());
                if (context.mounted) await offerImportOwnedLists(context);
              }
              if (mounted) setState(() {});
            })
          else ...[
            // One row instead of a separate "Signed in with X" label row —
            // the provider rides along in the sign-out button's own label.
            navRow(l.settingsSignOut(session.provider.label(l)),
                onTap: () async {
              final pendingLists = shareState.lists.editableLists
                  .where((x) => x.meta.pendingOps.isNotEmpty)
                  .toList();
              final body = pendingLists.isNotEmpty
                  ? l.settingsSignOutConfirmBodyWithPending(pendingLists.length)
                  : l.settingsSignOutConfirmBody;
              // Pass [onConfirm] so the dialog keeps itself open with the
              // built-in spinner while sign-out runs (it does a best-effort
              // flush of queued edits first, so it isn't instant).
              final confirmed = await confirmAlert(context, Text(body),
                  title: l.settingsSignOutConfirmTitle,
                  onConfirm: () => shareState.signOut());
              if (confirmed && mounted) setState(() {});
            }),
            navRow(l.settingsDeleteAccount, onTap: () async {
              final confirmed = await confirmAlert(
                  context, Text(l.settingsDeleteAccountConfirmBody),
                  title: l.settingsDeleteAccountConfirmTitle,
                  confirmText: l.settingsDeleteAccountConfirmButton);
              if (!confirmed || !context.mounted) return;
              await runWithProgress(
                context: context,
                message: l.settingsDeleteAccountRunning,
                task: () => shareState.deleteAccount(),
                errorMessage: (e) => e is SyncException
                    ? l.settingsDeleteAccountFailed(e.message)
                    : '$e',
              );
              if (mounted) setState(() {});
            }),
          ],
        ]),
      ...section(l.settingsCache, [
        switchRow(l.settingsCacheVideos,
            sharedPreferences.getBool(KEY_SHOULD_CACHE) ?? true, (newValue) {
          sharedPreferences.setBool(KEY_SHOULD_CACHE, newValue);
          setState(() {});
        }),
        navRow(l.settingsDropCache, onTap: () async {
          await myCacheManager.emptyCache();
          if (!context.mounted) return;
          showSnack(context, l.settingsCacheDropped);
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
                final message =
                    (newData != null && newData.newDataIsActuallyNew())
                        ? l.settingsDataUpdated
                        : l.settingsDataUpToDate;
                if (!context.mounted) return;
                showSnack(context, message, backgroundColor: cs.primary);
              }),
        if (communityEntryListManager.getEntryLists().isNotEmpty)
          switchRow(l.settingsHideCommunityLists,
              sharedPreferences.getBool(KEY_HIDE_COMMUNITY_LISTS) ?? false,
              (newValue) {
            sharedPreferences.setBool(KEY_HIDE_COMMUNITY_LISTS, newValue);
            setState(() {});
          }),
      ]),
      if (enableFlashcardsKnob && !kIsWeb)
        ...section(l.settingsRevision, [
          switchRow(l.settingsHideRevision,
              sharedPreferences.getBool(KEY_HIDE_FLASHCARDS_FEATURE) ?? false,
              (newValue) {
            sharedPreferences.setBool(KEY_HIDE_FLASHCARDS_FEATURE, newValue);
            setState(() {});
          }),
          navRow(l.settingsDeleteRevisionProgress, onTap: () async {
            bool confirmed = await confirmAlert(
                context, Text(l.settingsDeleteRevisionProgressExplanation));
            if (confirmed) {
              await writeReviews([], [], force: true);
              await sharedPreferences.setInt(KEY_RANDOM_REVIEWS_COUNTER, 0);
              await sharedPreferences.remove(KEY_FIRST_RANDOM_REVIEW);
              if (!context.mounted) return;
              showSnack(context, l.settingsProgressDeleted);
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
        // The privacy policy and terms of service live on the website so
        // there's a single source of truth; just link out to them.
        navRow(l.settingsSeePrivacyPolicy, onTap: () async {
          await launchUrl(Uri.parse(widget.privacyPolicyUrl),
              mode: LaunchMode.externalApplication);
        }),
        navRow(l.settingsSeeTermsOfService, onTap: () async {
          await launchUrl(Uri.parse(widget.termsOfServiceUrl),
              mode: LaunchMode.externalApplication);
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
              to: ['daniel@dport.me'],
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
          sharedPreferences.setBool(KEY_USE_SYSTEM_HTTP_PROXY, newValue);
          setState(() {});
          showSnack(context, l.settingsRestartApp);
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
                      showSnack(context, l.backgroundLogsCopiedSnack);
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

String _getThemeModeString(BuildContext context) {
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

  // Don't pop an import dialog at all unless the account actually has lists to
  // pull down — a brand-new user signing in for the first time shouldn't be
  // asked to import zero lists. We also gather the lists' names so the dialog
  // can show exactly what will be pulled down. Snapshots are small (saved-video
  // references, not the videos), so fetching them here is cheap. If the
  // pre-check fails (offline, etc.) we skip the prompt silently rather than
  // block the freshly-completed sign-in; the user can sign out and back in to
  // retry once connectivity returns.
  final session = sharing.auth.store.current;
  if (session == null) return;
  final names = <String>[];
  try {
    final userLists =
        await sharing.api.userLists(sessionToken: session.sessionToken);
    final ids = [...userLists.ownedListIds, ...userLists.editorListIds];
    if (ids.isEmpty) return;
    for (final id in ids) {
      try {
        final snapshot = await sharing.api
            .getState(listId: id, sessionToken: session.sessionToken);
        if (snapshot.displayName.trim().isNotEmpty) {
          names.add(snapshot.displayName);
        }
      } catch (_) {
        // Skip a list we can't read; it just won't be listed (and the import
        // will skip it too).
      }
    }
  } catch (e) {
    printAndLog('offerImportOwnedLists: pre-check failed, skipping prompt: $e');
    return;
  }
  if (names.isEmpty || !context.mounted) return;

  // Capture the result via closure so we can format the snackbar after
  // [runWithProgress] returns success.
  ImportOwnedListsResult? result;
  final go = await confirmAlert(
    context,
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(l.importOwnedListsPromptBody),
        const SizedBox(height: 12),
        for (final name in names)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('•  '),
                Expanded(
                    child: Text(name,
                        style: const TextStyle(fontWeight: FontWeight.w600))),
              ],
            ),
          ),
      ],
    ),
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
  showSnackVia(
      messenger,
      r.total == 0
          ? l.importOwnedListsResultNone
          : l.importOwnedListsResultDone(r.imported, r.total));
}
