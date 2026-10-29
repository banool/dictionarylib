import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:store_redirect/store_redirect.dart';
import 'package:mailto/mailto.dart';
import 'package:url_launcher/url_launcher.dart';

import 'analytics.dart';
import 'common.dart';
import 'entry_loader.dart';
import 'flashcards_logic.dart';
import 'globals.dart';
import 'hearth.dart';
import 'l10n/app_localizations.dart';
import 'page_settings_help_en.dart';
import 'revision_history.dart';
import 'theme.dart';
import 'sharing/account_sync.dart';
import 'sharing/auth/auth_store.dart';
import 'sharing/auth/sign_in_dialog.dart';
import 'sharing/sync_api.dart';
import 'top_level_scaffold.dart';
import 'video_player_screen.dart';
import 'tv_focus.dart';

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

  /// "Syncing…", "Synced 3 minutes ago", "Waiting for a connection" or
  /// "Sync is paused", from the account-sync controller.
  String _accountSyncStatusLine(DictLibLocalizations l) {
    final sync = sharing.accountSync;
    switch (sync.status) {
      case AccountSyncStatus.syncing:
      case AccountSyncStatus.signedOut:
        return l.accountSyncStatusSyncing;
      case AccountSyncStatus.paused:
        return l.accountSyncStatusPaused;
      case AccountSyncStatus.waitingForConnection:
        return l.accountSyncStatusWaiting;
      case AccountSyncStatus.synced:
        final at = sync.lastSyncAt;
        // Signed in, first cycle not finished yet.
        if (at == null) return l.accountSyncStatusSyncing;
        final minutes =
            (DateTime.now().millisecondsSinceEpoch ~/ 1000 - at) ~/ 60;
        if (minutes < 1) return l.accountSyncStatusJustNow;
        if (minutes < 60) return l.accountSyncStatusMinutesAgo(minutes);
        if (minutes < 24 * 60) {
          return l.accountSyncStatusHoursAgo(minutes ~/ 60);
        }
        return l.accountSyncStatusDaysAgo(minutes ~/ (24 * 60));
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
        trailing = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                value,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14),
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
          ],
        );
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
        HearthSectionLabel(
          title,
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
        ),
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
        navRow(
          l.settingsColourMode,
          value: _getThemeModeString(context),
          onTap: () async {
            final current =
                ThemeMode.values[sharedPreferences.getInt(KEY_THEME_MODE) ??
                    DEFAULT_THEME_MODE];
            final chosen = await showHearthPicker<ThemeMode>(
              context: context,
              title: l.settingsColourMode,
              selected: current,
              options: [
                HearthPickerOption(
                  ThemeMode.system,
                  l.settingsColourModeSystem,
                ),
                HearthPickerOption(ThemeMode.light, l.settingsColourModeLight),
                HearthPickerOption(ThemeMode.dark, l.settingsColourModeDark),
              ],
            );
            if (chosen != null) await _setThemeMode(chosen);
            if (mounted) setState(() {});
          },
        ),
        navRow(
          l.settingsAppTheme,
          value: themeVariantNotifier.value.displayName,
          onTap: () async {
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
          },
        ),
      ]),
      ...section(l.settingsVideo, [
        navRow(
          l.settingsDefaultPlaybackSpeed,
          value: getPlaybackSpeedString(getDefaultPlaybackSpeed()),
          onTap: () async {
            final chosen = await showHearthPicker<PlaybackSpeed>(
              context: context,
              title: l.settingsDefaultPlaybackSpeed,
              selected: getDefaultPlaybackSpeed(),
              options: [
                for (final s in PlaybackSpeed.values)
                  HearthPickerOption(
                    s,
                    s == PlaybackSpeed.One
                        ? "${getPlaybackSpeedString(s)}  ·  ${l.playbackSpeedNormal}"
                        : getPlaybackSpeedString(s),
                  ),
              ],
            );
            if (chosen != null) await _setDefaultPlaybackSpeed(chosen);
            if (mounted) setState(() {});
          },
        ),
      ]),
      // Hidden on web and Android TV: there's no sign-in / account there.
      // Signing in is syncing (no separate switch): the section says what
      // it does, then how it's going.
      if (shareState.isEnabled && !kIsWeb && !isAndroidTv)
        ...section(l.settingsAccount, [
          if (session == null)
            navRow(
              l.settingsAccountSignIn,
              onTap: () async {
                // The sign-in itself kicks the first sync (the merge).
                await showSignInDialog(context);
                if (mounted) setState(() {});
              },
            )
          else ...[
            // Rebuilt as cycles start and finish.
            ListenableBuilder(
              listenable: shareState,
              builder: (context, _) => HearthRow(
                title: l.settingsSignedInWith(session.provider.label(l)),
                subtitle: _accountSyncStatusLine(l),
              ),
            ),
            navRow(
              l.settingsSignOutRow,
              onTap: () async {
                // Pass [onConfirm] so the dialog keeps itself open with the
                // built-in spinner while sign-out runs (it does a best-effort
                // flush of queued changes first, so it isn't instant).
                final confirmed = await confirmAlert(
                  context,
                  Text(l.settingsSignOutConfirmBodySync),
                  title: l.settingsSignOutConfirmTitle,
                  onConfirm: () => shareState.signOut(),
                );
                if (confirmed && mounted) setState(() {});
              },
            ),
            navRow(
              l.settingsDeleteAccount,
              onTap: () async {
                final confirmed = await confirmAlert(
                  context,
                  Text(l.settingsDeleteAccountConfirmBody),
                  title: l.settingsDeleteAccountConfirmTitle,
                  confirmText: l.settingsDeleteAccountConfirmButton,
                );
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
              },
            ),
          ],
        ]),
      ...section(l.settingsCache, [
        switchRow(
          l.settingsCacheVideos,
          sharedPreferences.getBool(KEY_SHOULD_CACHE) ?? true,
          (newValue) {
            sharedPreferences.setBool(KEY_SHOULD_CACHE, newValue);
            setState(() {});
          },
        ),
        navRow(
          l.settingsDropCache,
          onTap: () async {
            await myCacheManager.emptyCache();
            if (!context.mounted) return;
            showSnack(context, l.settingsCacheDropped);
          },
        ),
      ]),
      ...section(l.settingsData, [
        checkingForNewData
            ? const HearthRow(
                title: '',
                trailing: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : navRow(
                l.settingsCheckNewData,
                onTap: () async {
                  setState(() => checkingForNewData = true);
                  NewData? newData = await entryLoader.downloadAndApplyNewData(
                    true,
                  );
                  if (!mounted) return;
                  setState(() => checkingForNewData = false);
                  final message =
                      (newData != null && newData.newDataIsActuallyNew())
                      ? l.settingsDataUpdated
                      : l.settingsDataUpToDate;
                  if (!context.mounted) return;
                  showSnack(context, message, backgroundColor: cs.primary);
                },
              ),
        if (communityEntryListManager.getEntryLists().isNotEmpty)
          switchRow(
            l.settingsHideCommunityLists,
            sharedPreferences.getBool(KEY_HIDE_COMMUNITY_LISTS) ?? false,
            (newValue) {
              sharedPreferences.setBool(KEY_HIDE_COMMUNITY_LISTS, newValue);
              setState(() {});
            },
          ),
      ]),
      if (enableFlashcardsKnob && !kIsWeb)
        ...section(l.settingsRevision, [
          switchRow(
            l.settingsHideRevision,
            sharedPreferences.getBool(KEY_HIDE_FLASHCARDS_FEATURE) ?? false,
            (newValue) {
              sharedPreferences.setBool(KEY_HIDE_FLASHCARDS_FEATURE, newValue);
              setState(() {});
            },
          ),
          navRow(
            l.settingsDeleteRevisionProgress,
            onTap: () async {
              bool confirmed = await confirmAlert(
                context,
                Text(l.settingsDeleteRevisionProgressExplanation),
              );
              if (confirmed) {
                final nowUs = DateTime.now().microsecondsSinceEpoch;
                // Signed in, from the account and so every device too. The
                // account's op is queued first: if the app dies before the
                // rest, the account's answer resets this device as well.
                await sharing.accountSync.recordReset(nowUs);
                await reviewHistory.reset(nowUs);
                await sharedPreferences.setInt(KEY_RANDOM_REVIEWS_COUNTER, 0);
                await sharedPreferences.remove(KEY_FIRST_RANDOM_REVIEW);
                if (!context.mounted) return;
                showSnack(context, l.settingsProgressDeleted);
              }
            },
          ),
        ]),
      ...section(l.settingsLegal, [
        navRow(
          l.settingsSeeLegal,
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => LegalInformationPage(
                  buildLegalInformationChildren:
                      widget.buildLegalInformationChildren,
                ),
              ),
            );
          },
        ),
        // The privacy policy and terms of service live on the website so
        // there's a single source of truth; just link out to them.
        navRow(
          l.settingsSeePrivacyPolicy,
          onTap: () async {
            await launchUrl(
              Uri.parse(widget.privacyPolicyUrl),
              mode: LaunchMode.externalApplication,
            );
          },
        ),
        navRow(
          l.settingsSeeTermsOfService,
          onTap: () async {
            await launchUrl(
              Uri.parse(widget.termsOfServiceUrl),
              mode: LaunchMode.externalApplication,
            );
          },
        ),
      ]),
      ...section(l.settingsHelp, [
        navRow(
          l.settingsReportDictionaryDataIssue,
          onTap: () async {
            await launchUrl(
              Uri.parse(widget.reportDataProblemUrl),
              mode: LaunchMode.externalApplication,
            );
          },
        ),
        navRow(
          l.settingsReportAppIssueGithub,
          onTap: () async {
            await launchUrl(
              Uri.parse(widget.reportAppProblemUrl),
              mode: LaunchMode.externalApplication,
            );
          },
        ),
        navRow(
          l.settingsReportAppIssueEmail,
          onTap: () async {
            const supportEmail = 'daniel@dport.me';
            final mailto = Mailto(
              to: [supportEmail],
              subject: l.reportIssueEmailSubject(widget.appName),
              body:
                  'Please describe the issue in detail.\n\n--> Replace with description of issue <--\n\n${getBugInfo()}\nBackground logs:\n${backgroundLogs.items.join("\n")}\n',
            );
            final uri = Uri.parse("$mailto");
            // Capture the messenger before the async gap so the fallback can
            // snack safely without touching a possibly-unmounted context.
            final messenger = ScaffoldMessenger.of(context);
            // Deliberately NOT gating on canLaunchUrl: for a mailto: URI it
            // returns false on iOS unless the scheme is whitelisted in
            // LSApplicationQueriesSchemes, and on Android 11+ unless a matching
            // <queries> intent is declared — even when a mail app is installed.
            // That false-negative is what made this button look broken. Try to
            // launch, and if it genuinely can't be handled fall back to showing
            // the address so the user is never left tapping a dead button.
            bool launched = false;
            try {
              launched = await launchUrl(
                uri,
                mode: LaunchMode.externalApplication,
              );
            } catch (e) {
              printAndLog('Could not launch $uri: $e');
            }
            if (!launched && context.mounted) {
              await showDialog<void>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text(l.reportIssueEmailFailedTitle),
                  content: Text(l.reportIssueEmailFailedBody(supportEmail)),
                  actions: [
                    TextButton(
                      onPressed: () async {
                        await Clipboard.setData(
                          const ClipboardData(text: supportEmail),
                        );
                        if (ctx.mounted) Navigator.of(ctx).pop();
                        showSnackVia(messenger, l.reportIssueEmailCopied);
                      },
                      child: Text(l.reportIssueEmailCopy),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: Text(
                        MaterialLocalizations.of(ctx).closeButtonLabel,
                      ),
                    ),
                  ],
                ),
              );
            }
          },
        ),
        if (appStoreTileString != null)
          navRow(
            appStoreTileString,
            onTap: () async {
              await StoreRedirect.redirect(
                iOSAppId: widget.iOSAppId,
                androidAppId: widget.androidAppId,
              );
            },
          ),
        navRow(
          l.settingsShowBuildInformation,
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const BuildInformationPage(),
              ),
            );
          },
        ),
        navRow(
          l.settingsBackgroundLogs,
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => BackgroundLogsPage()),
            );
          },
        ),
      ]),
      ...section(l.settingsNetwork, [
        switchRow(
          l.settingsUseSystemHttpProxy,
          sharedPreferences.getBool(KEY_USE_SYSTEM_HTTP_PROXY) ?? false,
          (newValue) {
            sharedPreferences.setBool(KEY_USE_SYSTEM_HTTP_PROXY, newValue);
            setState(() {});
            showSnack(context, l.settingsRestartApp);
          },
        ),
      ]),
      const SizedBox(height: 12),
    ];

    Widget body = ListView(
      padding: const EdgeInsets.only(top: 4),
      children: children,
    );

    List<Widget> actions = [
      buildActionButton(context, const Icon(Icons.help), () async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => getSettingsHelpPageEn()),
        );
      }),
    ];

    return TopLevelScaffold(
      body: body,
      title: l.settingsTitle,
      actions: actions,
    );
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
  const LegalInformationPage({
    super.key,
    required this.buildLegalInformationChildren,
  });

  final List<Widget> Function() buildLegalInformationChildren;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          DictLibLocalizations.of(context)!.legalInformationPageTitle,
        ),
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
      ),
    );
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
    children.add(
      getText("System version: ${androidDeviceInfo!.version.sdkInt}"),
    );
  }
  return children;
}

class BuildInformationPage extends StatelessWidget {
  const BuildInformationPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          DictLibLocalizations.of(context)!.buildInformationPageTitle,
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.only(
          bottom: 10,
          left: 20,
          right: 32,
          top: 20,
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: getPackageDeviceInfo(),
          ),
        ),
      ),
    );
  }
}

class BackgroundLogsPage extends StatelessWidget {
  const BackgroundLogsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l = DictLibLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l.backgroundLogsPageTitle)),
      body: Padding(
        padding: const EdgeInsets.only(
          bottom: 10,
          left: 20,
          right: 32,
          top: 20,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          mainAxisSize: MainAxisSize.max,
          children: [
            TextButton(
              child: Text(
                l.backgroundLogsCopyButton,
                textAlign: TextAlign.center,
              ),
              onPressed: () async {
                await Clipboard.setData(
                  ClipboardData(text: backgroundLogs.items.join("\n")),
                );
                showSnack(context, l.backgroundLogsCopiedSnack);
              },
            ),
            Container(padding: const EdgeInsets.only(top: 10)),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.vertical,
                child: Text(
                  backgroundLogs.items.join("\n"),
                  style: const TextStyle(
                    height: 1.8, //You can set your custom height here
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
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
  Analytics.track(
    'theme_changed',
    props: {'setting': 'mode', 'value': themeMode.name},
  );
}

Future<void> _setThemeVariant(AppThemeVariant variant) async {
  // Persisted by name so we load the same look at startup.
  await sharedPreferences.setString(KEY_THEME_VARIANT, variant.name);
  // Drives the live theme switch via the app's MaterialApp.
  themeVariantNotifier.value = variant;
  Analytics.track(
    'theme_changed',
    props: {'setting': 'variant', 'value': variant.name},
  );
}

Future<void> _setDefaultPlaybackSpeed(PlaybackSpeed speed) async {
  // Persisted by name (not index) so PlaybackSpeed can be reordered safely.
  // Read lazily by getDefaultPlaybackSpeed at each page/carousel construction,
  // so no notifier is needed. Deliberately a different event from
  // playback_speed_changed, which keeps meaning "per-session override".
  await sharedPreferences.setString(KEY_DEFAULT_PLAYBACK_SPEED, speed.name);
  Analytics.track(
    'default_playback_speed_changed',
    props: {'speed': speed.name},
  );
}
