import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_si.dart';
import 'app_localizations_ta.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of DictLibLocalizations
/// returned by `DictLibLocalizations.of(context)`.
///
/// Applications need to include `DictLibLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: DictLibLocalizations.localizationsDelegates,
///   supportedLocales: DictLibLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the DictLibLocalizations.supportedLocales
/// property.
abstract class DictLibLocalizations {
  DictLibLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static DictLibLocalizations? of(BuildContext context) {
    return Localizations.of<DictLibLocalizations>(
        context, DictLibLocalizations);
  }

  static const LocalizationsDelegate<DictLibLocalizations> delegate =
      _DictLibLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('si'),
    Locale('ta')
  ];

  /// No description provided for @newsTitle.
  ///
  /// In en, this message translates to:
  /// **'News'**
  String get newsTitle;

  /// No description provided for @searchTitle.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get searchTitle;

  /// No description provided for @listsTitle.
  ///
  /// In en, this message translates to:
  /// **'Lists'**
  String get listsTitle;

  /// No description provided for @revisionTitle.
  ///
  /// In en, this message translates to:
  /// **'Revision'**
  String get revisionTitle;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @searchHintText.
  ///
  /// In en, this message translates to:
  /// **'Search for a word'**
  String get searchHintText;

  /// No description provided for @flashcardsRevisionSources.
  ///
  /// In en, this message translates to:
  /// **'Revision Sources'**
  String get flashcardsRevisionSources;

  /// No description provided for @flashcardsSelectLists.
  ///
  /// In en, this message translates to:
  /// **'Select Lists'**
  String get flashcardsSelectLists;

  /// No description provided for @flashcardsTypes.
  ///
  /// In en, this message translates to:
  /// **'Flashcard Types'**
  String get flashcardsTypes;

  /// No description provided for @flashcardsSignToWord.
  ///
  /// In en, this message translates to:
  /// **'Sign → Word'**
  String get flashcardsSignToWord;

  /// No description provided for @flashcardsWordToSign.
  ///
  /// In en, this message translates to:
  /// **'Word → Sign'**
  String get flashcardsWordToSign;

  /// No description provided for @flashcardsRevisionSettings.
  ///
  /// In en, this message translates to:
  /// **'Revision Settings'**
  String get flashcardsRevisionSettings;

  /// No description provided for @flashcardsStart.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get flashcardsStart;

  /// No description provided for @flashcardsCardUnavailable.
  ///
  /// In en, this message translates to:
  /// **'A card was unavailable and was skipped.'**
  String get flashcardsCardUnavailable;

  /// No description provided for @flashcardsSuccessRate.
  ///
  /// In en, this message translates to:
  /// **'Success Rate'**
  String get flashcardsSuccessRate;

  /// No description provided for @flashcardsSuccessfulCards.
  ///
  /// In en, this message translates to:
  /// **'Successful Cards'**
  String get flashcardsSuccessfulCards;

  /// No description provided for @flashcardsTotalReviews.
  ///
  /// In en, this message translates to:
  /// **'Total Reviews'**
  String get flashcardsTotalReviews;

  /// No description provided for @flashcardsUnsuccessfulCards.
  ///
  /// In en, this message translates to:
  /// **'Unsuccessful Cards'**
  String get flashcardsUnsuccessfulCards;

  /// No description provided for @flashcardsUniqueWords.
  ///
  /// In en, this message translates to:
  /// **'Unique Words'**
  String get flashcardsUniqueWords;

  /// No description provided for @flashcardsRevisionProgressTitle.
  ///
  /// In en, this message translates to:
  /// **'Revision Progress'**
  String get flashcardsRevisionProgressTitle;

  /// No description provided for @setPlaybackSpeedTo.
  ///
  /// In en, this message translates to:
  /// **'Set playback speed to'**
  String get setPlaybackSpeedTo;

  /// No description provided for @settingsPlayStoreFeedback.
  ///
  /// In en, this message translates to:
  /// **'Give feedback on Play Store'**
  String get settingsPlayStoreFeedback;

  /// No description provided for @settingsAppStoreFeedback.
  ///
  /// In en, this message translates to:
  /// **'Give feedback on App Store'**
  String get settingsAppStoreFeedback;

  /// No description provided for @settingsRevision.
  ///
  /// In en, this message translates to:
  /// **'Revision'**
  String get settingsRevision;

  /// No description provided for @settingsHideRevision.
  ///
  /// In en, this message translates to:
  /// **'Hide revision feature'**
  String get settingsHideRevision;

  /// No description provided for @settingsHideCommunityLists.
  ///
  /// In en, this message translates to:
  /// **'Hide community lists'**
  String get settingsHideCommunityLists;

  /// No description provided for @settingsDeleteRevisionProgress.
  ///
  /// In en, this message translates to:
  /// **'Delete all revision progress'**
  String get settingsDeleteRevisionProgress;

  /// No description provided for @settingsDeleteRevisionProgressExplanation.
  ///
  /// In en, this message translates to:
  /// **'This will delete all your review progress from all time for both the spaced repetition and random review strategies. Your lists (including favourites) will not be affected. Are you 100% sure you want to do this?'**
  String get settingsDeleteRevisionProgressExplanation;

  /// No description provided for @settingsProgressDeleted.
  ///
  /// In en, this message translates to:
  /// **'All review progress deleted'**
  String get settingsProgressDeleted;

  /// No description provided for @settingsAppearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get settingsAppearance;

  /// No description provided for @settingsAppTheme.
  ///
  /// In en, this message translates to:
  /// **'App theme'**
  String get settingsAppTheme;

  /// No description provided for @settingsColourMode.
  ///
  /// In en, this message translates to:
  /// **'Colour mode'**
  String get settingsColourMode;

  /// No description provided for @settingsColourModeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get settingsColourModeLight;

  /// No description provided for @settingsColourModeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get settingsColourModeDark;

  /// No description provided for @settingsColourModeSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get settingsColourModeSystem;

  /// No description provided for @settingsCache.
  ///
  /// In en, this message translates to:
  /// **'Cache'**
  String get settingsCache;

  /// No description provided for @settingsCacheVideos.
  ///
  /// In en, this message translates to:
  /// **'Cache videos'**
  String get settingsCacheVideos;

  /// No description provided for @settingsDropCache.
  ///
  /// In en, this message translates to:
  /// **'Drop cache'**
  String get settingsDropCache;

  /// No description provided for @settingsCacheDropped.
  ///
  /// In en, this message translates to:
  /// **'Cache dropped'**
  String get settingsCacheDropped;

  /// No description provided for @settingsData.
  ///
  /// In en, this message translates to:
  /// **'Data'**
  String get settingsData;

  /// No description provided for @settingsCheckNewData.
  ///
  /// In en, this message translates to:
  /// **'Check for new dictionary data'**
  String get settingsCheckNewData;

  /// No description provided for @settingsDataUpdated.
  ///
  /// In en, this message translates to:
  /// **'Successfully updated dictionary data'**
  String get settingsDataUpdated;

  /// No description provided for @settingsDataUpToDate.
  ///
  /// In en, this message translates to:
  /// **'Data is already up to date'**
  String get settingsDataUpToDate;

  /// No description provided for @settingsLegal.
  ///
  /// In en, this message translates to:
  /// **'Legal'**
  String get settingsLegal;

  /// No description provided for @settingsSeeLegal.
  ///
  /// In en, this message translates to:
  /// **'See legal information'**
  String get settingsSeeLegal;

  /// No description provided for @settingsSeePrivacyPolicy.
  ///
  /// In en, this message translates to:
  /// **'See privacy policy'**
  String get settingsSeePrivacyPolicy;

  /// No description provided for @settingsSeeTermsOfService.
  ///
  /// In en, this message translates to:
  /// **'See terms of service'**
  String get settingsSeeTermsOfService;

  /// No description provided for @settingsBackgroundLogs.
  ///
  /// In en, this message translates to:
  /// **'Background logs'**
  String get settingsBackgroundLogs;

  /// No description provided for @settingsHelp.
  ///
  /// In en, this message translates to:
  /// **'Help'**
  String get settingsHelp;

  /// No description provided for @settingsReportDictionaryDataIssue.
  ///
  /// In en, this message translates to:
  /// **'Report issue with dictionary data'**
  String get settingsReportDictionaryDataIssue;

  /// No description provided for @settingsReportAppIssueGithub.
  ///
  /// In en, this message translates to:
  /// **'Report issue with app (GitHub)'**
  String get settingsReportAppIssueGithub;

  /// No description provided for @settingsReportAppIssueEmail.
  ///
  /// In en, this message translates to:
  /// **'Report issue with app (Email)'**
  String get settingsReportAppIssueEmail;

  /// No description provided for @settingsShowBuildInformation.
  ///
  /// In en, this message translates to:
  /// **'Show build information'**
  String get settingsShowBuildInformation;

  /// No description provided for @settingsNetwork.
  ///
  /// In en, this message translates to:
  /// **'Network'**
  String get settingsNetwork;

  /// No description provided for @settingsUseSystemHttpProxy.
  ///
  /// In en, this message translates to:
  /// **'Use system HTTP proxy'**
  String get settingsUseSystemHttpProxy;

  /// No description provided for @settingsRestartApp.
  ///
  /// In en, this message translates to:
  /// **'You need to restart the app for this change to take effect'**
  String get settingsRestartApp;

  /// No description provided for @listEnterNewName.
  ///
  /// In en, this message translates to:
  /// **'Enter new list name'**
  String get listEnterNewName;

  /// No description provided for @listFailedToMake.
  ///
  /// In en, this message translates to:
  /// **'Failed to make new list'**
  String get listFailedToMake;

  /// No description provided for @listFailedToRename.
  ///
  /// In en, this message translates to:
  /// **'Failed to rename list'**
  String get listFailedToRename;

  /// No description provided for @listNewList.
  ///
  /// In en, this message translates to:
  /// **'New List'**
  String get listNewList;

  /// No description provided for @listRenameList.
  ///
  /// In en, this message translates to:
  /// **'Rename List'**
  String get listRenameList;

  /// No description provided for @listMyLists.
  ///
  /// In en, this message translates to:
  /// **'My Lists'**
  String get listMyLists;

  /// No description provided for @listCommunity.
  ///
  /// In en, this message translates to:
  /// **'Community'**
  String get listCommunity;

  /// No description provided for @listSortAdded.
  ///
  /// In en, this message translates to:
  /// **'Added'**
  String get listSortAdded;

  /// No description provided for @listSortAlpha.
  ///
  /// In en, this message translates to:
  /// **'A-Z'**
  String get listSortAlpha;

  /// No description provided for @listConfirmListDelete.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this list?'**
  String get listConfirmListDelete;

  /// No description provided for @listSearchAdd.
  ///
  /// In en, this message translates to:
  /// **'Search for words to add'**
  String get listSearchAdd;

  /// No description provided for @listSearchPrefix.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get listSearchPrefix;

  /// No description provided for @listSavedVideoCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 video saved} other{{count} videos saved}}'**
  String listSavedVideoCount(int count);

  /// No description provided for @listRemoveAllVideosTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove from list?'**
  String get listRemoveAllVideosTitle;

  /// No description provided for @listRemoveAllVideosBody.
  ///
  /// In en, this message translates to:
  /// **'Remove all {count} saved videos of \"{word}\" from this list?'**
  String listRemoveAllVideosBody(int count, String word);

  /// No description provided for @savedVideoSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Save this video to…'**
  String get savedVideoSheetTitle;

  /// No description provided for @entryTypeWords.
  ///
  /// In en, this message translates to:
  /// **'Words'**
  String get entryTypeWords;

  /// No description provided for @entryTypePhrases.
  ///
  /// In en, this message translates to:
  /// **'Phrases'**
  String get entryTypePhrases;

  /// No description provided for @entryTypeFingerspelling.
  ///
  /// In en, this message translates to:
  /// **'Fingerspelling'**
  String get entryTypeFingerspelling;

  /// No description provided for @entrySelectEntryTypes.
  ///
  /// In en, this message translates to:
  /// **'Select Entry Types'**
  String get entrySelectEntryTypes;

  /// No description provided for @alertCareful.
  ///
  /// In en, this message translates to:
  /// **'Careful!'**
  String get alertCareful;

  /// No description provided for @alertCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get alertCancel;

  /// No description provided for @alertConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get alertConfirm;

  /// No description provided for @alertOk.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get alertOk;

  /// No description provided for @unexpectedErrorLoadingVideo.
  ///
  /// In en, this message translates to:
  /// **'Unexpected error loading media'**
  String get unexpectedErrorLoadingVideo;

  /// No description provided for @shareDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Share this list'**
  String get shareDialogTitle;

  /// No description provided for @shareDialogBody.
  ///
  /// In en, this message translates to:
  /// **'Pick a display name for your list. Anyone with the share link can subscribe and follow your edits.'**
  String get shareDialogBody;

  /// No description provided for @shareDialogDisplayNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Display name'**
  String get shareDialogDisplayNameLabel;

  /// No description provided for @shareDialogDisplayNameHelper.
  ///
  /// In en, this message translates to:
  /// **'Emojis welcome 🎉'**
  String get shareDialogDisplayNameHelper;

  /// No description provided for @shareDialogShareButton.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get shareDialogShareButton;

  /// No description provided for @shareValidationRequired.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get shareValidationRequired;

  /// No description provided for @shareValidationMaxLen.
  ///
  /// In en, this message translates to:
  /// **'At most {count} characters'**
  String shareValidationMaxLen(int count);

  /// No description provided for @shareValidationReservedName.
  ///
  /// In en, this message translates to:
  /// **'\"{name}\" is reserved — pick a different name'**
  String shareValidationReservedName(String name);

  /// No description provided for @shareNetworkError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t reach the server. Check your connection and try again.'**
  String get shareNetworkError;

  /// No description provided for @shareErrorUnauthorized.
  ///
  /// In en, this message translates to:
  /// **'Your session has expired. Please sign in again.'**
  String get shareErrorUnauthorized;

  /// No description provided for @shareErrorForbidden.
  ///
  /// In en, this message translates to:
  /// **'You don\'t have permission to do that.'**
  String get shareErrorForbidden;

  /// No description provided for @shareErrorGone.
  ///
  /// In en, this message translates to:
  /// **'This list has been deleted by its owner.'**
  String get shareErrorGone;

  /// No description provided for @shareErrorPayloadTooLarge.
  ///
  /// In en, this message translates to:
  /// **'That change is too big. Try again with a smaller batch.'**
  String get shareErrorPayloadTooLarge;

  /// No description provided for @shareErrorRateLimited.
  ///
  /// In en, this message translates to:
  /// **'Slow down — too many requests. Try again in a moment.'**
  String get shareErrorRateLimited;

  /// No description provided for @shareErrorServer.
  ///
  /// In en, this message translates to:
  /// **'The server is having trouble. Try again later.'**
  String get shareErrorServer;

  /// No description provided for @unshareToDeleteTooltip.
  ///
  /// In en, this message translates to:
  /// **'Stop sharing this list before deleting it.'**
  String get unshareToDeleteTooltip;

  /// No description provided for @shareTooManyEntriesTitle.
  ///
  /// In en, this message translates to:
  /// **'List is too big to share'**
  String get shareTooManyEntriesTitle;

  /// No description provided for @shareTooManyEntriesBody.
  ///
  /// In en, this message translates to:
  /// **'This list has {count} entries, but shared lists are capped at {max}. Remove some entries and try again.'**
  String shareTooManyEntriesBody(int count, int max);

  /// No description provided for @shareLinkDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'List shared'**
  String get shareLinkDialogTitle;

  /// No description provided for @shareLinkDialogBody.
  ///
  /// In en, this message translates to:
  /// **'Anyone with this link can subscribe to \"{displayName}\":'**
  String shareLinkDialogBody(String displayName);

  /// No description provided for @shareLinkCopiedSnack.
  ///
  /// In en, this message translates to:
  /// **'Link copied to clipboard'**
  String get shareLinkCopiedSnack;

  /// No description provided for @shareLinkCopyButton.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get shareLinkCopyButton;

  /// No description provided for @shareLinkShareButton.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get shareLinkShareButton;

  /// No description provided for @shareLinkQrButton.
  ///
  /// In en, this message translates to:
  /// **'QR code'**
  String get shareLinkQrButton;

  /// No description provided for @shareLinkDoneButton.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get shareLinkDoneButton;

  /// No description provided for @qrCodeDialogBody.
  ///
  /// In en, this message translates to:
  /// **'Other people can scan this to subscribe.'**
  String get qrCodeDialogBody;

  /// No description provided for @qrCodeDialogClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get qrCodeDialogClose;

  /// No description provided for @signInDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign in to share'**
  String get signInDialogTitle;

  /// No description provided for @signInDialogBody.
  ///
  /// In en, this message translates to:
  /// **'To share a list you must sign in.'**
  String get signInDialogBody;

  /// No description provided for @signInLastUsedHint.
  ///
  /// In en, this message translates to:
  /// **'Last time, you signed in with {provider}.'**
  String signInLastUsedHint(String provider);

  /// No description provided for @signInWithApple.
  ///
  /// In en, this message translates to:
  /// **'Continue with Apple'**
  String get signInWithApple;

  /// No description provided for @signInWithGoogle.
  ///
  /// In en, this message translates to:
  /// **'Continue with Google'**
  String get signInWithGoogle;

  /// No description provided for @signInWithMicrosoft.
  ///
  /// In en, this message translates to:
  /// **'Continue with Microsoft'**
  String get signInWithMicrosoft;

  /// No description provided for @signInWithFacebook.
  ///
  /// In en, this message translates to:
  /// **'Continue with Facebook'**
  String get signInWithFacebook;

  /// No description provided for @signInFailed.
  ///
  /// In en, this message translates to:
  /// **'Sign-in failed. Please try again.'**
  String get signInFailed;

  /// No description provided for @signInCancelled.
  ///
  /// In en, this message translates to:
  /// **'Sign-in cancelled.'**
  String get signInCancelled;

  /// No description provided for @signInProviderNotConfigured.
  ///
  /// In en, this message translates to:
  /// **'This sign-in option isn\'t available on this device.'**
  String get signInProviderNotConfigured;

  /// No description provided for @signInProviderNoCredential.
  ///
  /// In en, this message translates to:
  /// **'Sign-in didn\'t return a valid response. Please try again.'**
  String get signInProviderNoCredential;

  /// No description provided for @providerApple.
  ///
  /// In en, this message translates to:
  /// **'Apple'**
  String get providerApple;

  /// No description provided for @providerGoogle.
  ///
  /// In en, this message translates to:
  /// **'Google'**
  String get providerGoogle;

  /// No description provided for @providerMicrosoft.
  ///
  /// In en, this message translates to:
  /// **'Microsoft'**
  String get providerMicrosoft;

  /// No description provided for @providerFacebook.
  ///
  /// In en, this message translates to:
  /// **'Facebook'**
  String get providerFacebook;

  /// No description provided for @providerTest.
  ///
  /// In en, this message translates to:
  /// **'Test session'**
  String get providerTest;

  /// No description provided for @subscribeDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Subscribe to a shared list'**
  String get subscribeDialogTitle;

  /// No description provided for @subscribeDialogBody.
  ///
  /// In en, this message translates to:
  /// **'Paste a share link / list ID.'**
  String get subscribeDialogBody;

  /// No description provided for @subscribeDialogUrlLabel.
  ///
  /// In en, this message translates to:
  /// **'Share URL'**
  String get subscribeDialogUrlLabel;

  /// No description provided for @subscribeDialogSubscribeButton.
  ///
  /// In en, this message translates to:
  /// **'Subscribe'**
  String get subscribeDialogSubscribeButton;

  /// No description provided for @alreadySubscribedSnack.
  ///
  /// In en, this message translates to:
  /// **'You\'re already subscribed to this list.'**
  String get alreadySubscribedSnack;

  /// No description provided for @alreadyOwnerSnack.
  ///
  /// In en, this message translates to:
  /// **'You own this list.'**
  String get alreadyOwnerSnack;

  /// No description provided for @alreadyEditorSnack.
  ///
  /// In en, this message translates to:
  /// **'You\'re an editor of this list.'**
  String get alreadyEditorSnack;

  /// No description provided for @subscribeInvalidInput.
  ///
  /// In en, this message translates to:
  /// **'Not a valid share link or list ID.'**
  String get subscribeInvalidInput;

  /// No description provided for @subscribeInviteDetected.
  ///
  /// In en, this message translates to:
  /// **'This is an editor invite link, not a regular subscribe link. Accept it to edit \"{displayName}\" alongside the creator.'**
  String subscribeInviteDetected(String displayName);

  /// No description provided for @subscribeInviteDetectedUnknown.
  ///
  /// In en, this message translates to:
  /// **'This is an editor invite link, not a regular subscribe link. Accept it to become an editor of this list.'**
  String get subscribeInviteDetectedUnknown;

  /// No description provided for @subscribeInviteAcceptButton.
  ///
  /// In en, this message translates to:
  /// **'Accept invitation'**
  String get subscribeInviteAcceptButton;

  /// No description provided for @subscribeNotFound.
  ///
  /// In en, this message translates to:
  /// **'No list with that key exists.'**
  String get subscribeNotFound;

  /// No description provided for @sharedListLandingLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading shared list'**
  String get sharedListLandingLoading;

  /// No description provided for @sharedListLandingDefaultError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load this list.'**
  String get sharedListLandingDefaultError;

  /// No description provided for @sharedListLandingNotFound.
  ///
  /// In en, this message translates to:
  /// **'This shared list doesn\'t exist or has been deleted by its owner.'**
  String get sharedListLandingNotFound;

  /// No description provided for @sharedListLandingTryAgain.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get sharedListLandingTryAgain;

  /// No description provided for @unshareConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'Stop sharing this list? Subscribers will no longer be able to see it.'**
  String get unshareConfirmBody;

  /// No description provided for @unshareConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Stop sharing?'**
  String get unshareConfirmTitle;

  /// No description provided for @unshareFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to stop sharing: {message}'**
  String unshareFailed(String message);

  /// No description provided for @unsubscribeConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'Unsubscribe from this list?'**
  String get unsubscribeConfirmBody;

  /// No description provided for @unsubscribeConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Unsubscribe?'**
  String get unsubscribeConfirmTitle;

  /// No description provided for @copyToMyListsSnack.
  ///
  /// In en, this message translates to:
  /// **'Copied to \"{name}\"'**
  String copyToMyListsSnack(String name);

  /// No description provided for @subscribedSyncNowMenuItem.
  ///
  /// In en, this message translates to:
  /// **'Sync now'**
  String get subscribedSyncNowMenuItem;

  /// No description provided for @subscribedCopyLinkMenuItem.
  ///
  /// In en, this message translates to:
  /// **'Copy link'**
  String get subscribedCopyLinkMenuItem;

  /// No description provided for @subscribedSyncInProgress.
  ///
  /// In en, this message translates to:
  /// **'Syncing…'**
  String get subscribedSyncInProgress;

  /// No description provided for @subscribedSyncDoneSnack.
  ///
  /// In en, this message translates to:
  /// **'Up to date'**
  String get subscribedSyncDoneSnack;

  /// No description provided for @subscribedSyncFailedSnack.
  ///
  /// In en, this message translates to:
  /// **'Sync failed: {message}'**
  String subscribedSyncFailedSnack(String message);

  /// No description provided for @retryAttemptSnack.
  ///
  /// In en, this message translates to:
  /// **'That didn\'t work — retrying (attempt {attempt} of {maxAttempts})…'**
  String retryAttemptSnack(int attempt, int maxAttempts);

  /// No description provided for @subscribedCopyMenuItem.
  ///
  /// In en, this message translates to:
  /// **'Duplicate'**
  String get subscribedCopyMenuItem;

  /// No description provided for @settingsSharing.
  ///
  /// In en, this message translates to:
  /// **'Sharing'**
  String get settingsSharing;

  /// No description provided for @settingsSignIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in to share lists'**
  String get settingsSignIn;

  /// No description provided for @settingsSignOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out (signed in with {provider})'**
  String settingsSignOut(String provider);

  /// No description provided for @settingsSignOutConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign out?'**
  String get settingsSignOutConfirmTitle;

  /// No description provided for @settingsSignOutConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'On this device:\n  • You\'re signed out of sharing.\n  • Lists you shared stop being managed from here — the local lists themselves keep their entries.\n\nYour shared lists stay on the server. Sign back in on any device to edit them again.'**
  String get settingsSignOutConfirmBody;

  /// No description provided for @settingsDeleteAccount.
  ///
  /// In en, this message translates to:
  /// **'Delete account'**
  String get settingsDeleteAccount;

  /// No description provided for @settingsDeleteAccountConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete account?'**
  String get settingsDeleteAccountConfirmTitle;

  /// No description provided for @settingsDeleteAccountConfirmButton.
  ///
  /// In en, this message translates to:
  /// **'Delete account'**
  String get settingsDeleteAccountConfirmButton;

  /// No description provided for @settingsDeleteAccountConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'This permanently deletes your account and everything we store for you:\n  • Every list you\'ve shared is deleted from the server — anyone subscribed keeps the copy already on their device, but it stops updating and is marked as removed.\n  • You\'re removed as an editor from other people\'s lists.\n  • We delete any personal information on file (your name).\n\nThe lists on this device keep their entries; only the sharing is removed. This can\'t be undone.'**
  String get settingsDeleteAccountConfirmBody;

  /// No description provided for @settingsDeleteAccountRunning.
  ///
  /// In en, this message translates to:
  /// **'Deleting account…'**
  String get settingsDeleteAccountRunning;

  /// No description provided for @settingsDeleteAccountFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t delete your account: {message}'**
  String settingsDeleteAccountFailed(String message);

  /// No description provided for @listNameAllowedChars.
  ///
  /// In en, this message translates to:
  /// **'No special characters besides these are allowed: , . - _ !'**
  String get listNameAllowedChars;

  /// No description provided for @importEditableListsPromptTitle.
  ///
  /// In en, this message translates to:
  /// **'Import your shared lists?'**
  String get importEditableListsPromptTitle;

  /// No description provided for @importEditableListsPromptBody.
  ///
  /// In en, this message translates to:
  /// **'We\'ll fetch any shared lists tied to this account — both the ones you created and the ones you\'ve been added to as an editor — and install them on this device. Existing local lists are untouched; name collisions get a numeric suffix (e.g. \"Cats\" → \"Cats 2\"). Edits sync automatically when you\'re online.'**
  String get importEditableListsPromptBody;

  /// No description provided for @importEditableListsActionImport.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get importEditableListsActionImport;

  /// No description provided for @importEditableListsActionSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get importEditableListsActionSkip;

  /// No description provided for @importEditableListsRunning.
  ///
  /// In en, this message translates to:
  /// **'Importing your shared lists…'**
  String get importEditableListsRunning;

  /// No description provided for @importEditableListsFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t import lists: {message}'**
  String importEditableListsFailed(String message);

  /// No description provided for @importEditableListsResultNone.
  ///
  /// In en, this message translates to:
  /// **'No shared lists found.'**
  String get importEditableListsResultNone;

  /// No description provided for @importEditableListsResultDone.
  ///
  /// In en, this message translates to:
  /// **'Imported {imported} of {total} list(s).'**
  String importEditableListsResultDone(int imported, int total);

  /// No description provided for @duplicateConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Duplicate list?'**
  String get duplicateConfirmTitle;

  /// No description provided for @duplicateConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'This makes a personal, private copy of the list. It won\'t update when the original owner edits theirs.'**
  String get duplicateConfirmBody;

  /// No description provided for @duplicateConfirmAction.
  ///
  /// In en, this message translates to:
  /// **'Duplicate'**
  String get duplicateConfirmAction;

  /// No description provided for @duplicateFallbackName.
  ///
  /// In en, this message translates to:
  /// **'Duplicated list'**
  String get duplicateFallbackName;

  /// No description provided for @listSharedWithMeTab.
  ///
  /// In en, this message translates to:
  /// **'Subscribed'**
  String get listSharedWithMeTab;

  /// No description provided for @listSharedWithMeEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing here yet.'**
  String get listSharedWithMeEmpty;

  /// No description provided for @ownedStatusOrphaned.
  ///
  /// In en, this message translates to:
  /// **'Shared — deleted by you'**
  String get ownedStatusOrphaned;

  /// No description provided for @ownedStatusSharedBy.
  ///
  /// In en, this message translates to:
  /// **'Shared by you'**
  String get ownedStatusSharedBy;

  /// No description provided for @ownedStatusPendingSyncSuffix.
  ///
  /// In en, this message translates to:
  /// **'Pending sync'**
  String get ownedStatusPendingSyncSuffix;

  /// No description provided for @ownedStatusSyncedSuffix.
  ///
  /// In en, this message translates to:
  /// **'Synced'**
  String get ownedStatusSyncedSuffix;

  /// No description provided for @subscribedStatusOrphaned.
  ///
  /// In en, this message translates to:
  /// **'Removed by owner'**
  String get subscribedStatusOrphaned;

  /// No description provided for @subscribedStatusFallback.
  ///
  /// In en, this message translates to:
  /// **'Subscribed'**
  String get subscribedStatusFallback;

  /// No description provided for @syncedJustNow.
  ///
  /// In en, this message translates to:
  /// **'Synced just now'**
  String get syncedJustNow;

  /// No description provided for @syncedMinutesAgo.
  ///
  /// In en, this message translates to:
  /// **'Synced {count}m ago'**
  String syncedMinutesAgo(int count);

  /// No description provided for @syncedHoursAgo.
  ///
  /// In en, this message translates to:
  /// **'Synced {count}h ago'**
  String syncedHoursAgo(int count);

  /// No description provided for @syncedDaysAgo.
  ///
  /// In en, this message translates to:
  /// **'Synced {count}d ago'**
  String syncedDaysAgo(int count);

  /// No description provided for @agoJustNow.
  ///
  /// In en, this message translates to:
  /// **'just now'**
  String get agoJustNow;

  /// No description provided for @agoMinutes.
  ///
  /// In en, this message translates to:
  /// **'{count}m ago'**
  String agoMinutes(int count);

  /// No description provided for @agoHours.
  ///
  /// In en, this message translates to:
  /// **'{count}h ago'**
  String agoHours(int count);

  /// No description provided for @agoDays.
  ///
  /// In en, this message translates to:
  /// **'{count}d ago'**
  String agoDays(int count);

  /// No description provided for @subscribedStatusSyncedAndUpdated.
  ///
  /// In en, this message translates to:
  /// **'Synced {sync} · Updated {updated}'**
  String subscribedStatusSyncedAndUpdated(String sync, String updated);

  /// No description provided for @shareLinkInviteEditorButton.
  ///
  /// In en, this message translates to:
  /// **'Invite an editor'**
  String get shareLinkInviteEditorButton;

  /// No description provided for @inviteEditorDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Invite an editor'**
  String get inviteEditorDialogTitle;

  /// No description provided for @inviteEditorDialogBody.
  ///
  /// In en, this message translates to:
  /// **'Send this link to the person you want to add as an editor. They\'ll need to sign in to accept; once they do, they can add and remove entries on your list.'**
  String get inviteEditorDialogBody;

  /// No description provided for @inviteEditorExpiresIn.
  ///
  /// In en, this message translates to:
  /// **'Expires in 7 days. Each link can only be used once, you must create a new link per editor you want to invite.'**
  String get inviteEditorExpiresIn;

  /// No description provided for @inviteEditorFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t create an invite: {message}'**
  String inviteEditorFailed(String message);

  /// No description provided for @acceptInviteLandingTitle.
  ///
  /// In en, this message translates to:
  /// **'Accept invite'**
  String get acceptInviteLandingTitle;

  /// No description provided for @acceptInviteLandingSignedOut.
  ///
  /// In en, this message translates to:
  /// **'Sign in to accept this invite. After you sign in, you\'ll be able to edit \"{displayName}\" alongside the creator.'**
  String acceptInviteLandingSignedOut(String displayName);

  /// No description provided for @acceptInviteLandingUnknownList.
  ///
  /// In en, this message translates to:
  /// **'This invite is for a list we couldn\'t preview yet. Sign in to continue.'**
  String get acceptInviteLandingUnknownList;

  /// No description provided for @acceptInviteLandingSignInButton.
  ///
  /// In en, this message translates to:
  /// **'Sign in to accept'**
  String get acceptInviteLandingSignInButton;

  /// No description provided for @acceptInviteLandingAccepting.
  ///
  /// In en, this message translates to:
  /// **'Joining…'**
  String get acceptInviteLandingAccepting;

  /// No description provided for @acceptInviteLandingFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t accept the invite: {message}'**
  String acceptInviteLandingFailed(String message);

  /// No description provided for @acceptInviteLandingExpired.
  ///
  /// In en, this message translates to:
  /// **'This invite has expired or has already been used. Ask the list\'s creator for a new one.'**
  String get acceptInviteLandingExpired;

  /// No description provided for @acceptInviteLandingSignedIn.
  ///
  /// In en, this message translates to:
  /// **'Join \"{displayName}\" as an editor.'**
  String acceptInviteLandingSignedIn(String displayName);

  /// No description provided for @acceptInviteLandingAcceptButton.
  ///
  /// In en, this message translates to:
  /// **'Accept invite'**
  String get acceptInviteLandingAcceptButton;

  /// No description provided for @acceptInviteLandingOpenList.
  ///
  /// In en, this message translates to:
  /// **'Open list'**
  String get acceptInviteLandingOpenList;

  /// No description provided for @acceptInviteLandingAlreadyOwner.
  ///
  /// In en, this message translates to:
  /// **'You\'re the creator of \"{displayName}\" — no need to accept your own invite.'**
  String acceptInviteLandingAlreadyOwner(String displayName);

  /// No description provided for @acceptInviteLandingAlreadyEditor.
  ///
  /// In en, this message translates to:
  /// **'You already edit \"{displayName}\".'**
  String acceptInviteLandingAlreadyEditor(String displayName);

  /// No description provided for @membersPageTitle.
  ///
  /// In en, this message translates to:
  /// **'Members'**
  String get membersPageTitle;

  /// No description provided for @membersPageYou.
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get membersPageYou;

  /// No description provided for @membersPageCreator.
  ///
  /// In en, this message translates to:
  /// **'Creator'**
  String get membersPageCreator;

  /// No description provided for @membersPageEditors.
  ///
  /// In en, this message translates to:
  /// **'Editors'**
  String get membersPageEditors;

  /// No description provided for @membersPageNoEditors.
  ///
  /// In en, this message translates to:
  /// **'No other editors yet. Tap \"Invite an editor\" to add one.'**
  String get membersPageNoEditors;

  /// No description provided for @membersPageRemoveEditor.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get membersPageRemoveEditor;

  /// No description provided for @membersPageRemoveEditorConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove {name}?'**
  String membersPageRemoveEditorConfirmTitle(String name);

  /// No description provided for @membersPageRemoveEditorConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'They will no longer be able to edit this list. Any of their pending offline edits will be discarded.'**
  String get membersPageRemoveEditorConfirmBody;

  /// No description provided for @membersPageLeaveButton.
  ///
  /// In en, this message translates to:
  /// **'Leave this list'**
  String get membersPageLeaveButton;

  /// No description provided for @membersPageLeaveConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Leave this list?'**
  String get membersPageLeaveConfirmTitle;

  /// No description provided for @membersPageLeaveConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'You won\'t be able to make changes anymore. The list itself stays available to read from your share link.'**
  String get membersPageLeaveConfirmBody;

  /// No description provided for @membersPageEditorAddedBy.
  ///
  /// In en, this message translates to:
  /// **'Added by {name}'**
  String membersPageEditorAddedBy(String name);

  /// No description provided for @membersPageNameYou.
  ///
  /// In en, this message translates to:
  /// **'{name} (you)'**
  String membersPageNameYou(String name);

  /// No description provided for @leaveListFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t leave list: {message}'**
  String leaveListFailed(String message);

  /// No description provided for @signInDialogContextInvite.
  ///
  /// In en, this message translates to:
  /// **'Sign in to accept the invite. You\'ll be able to edit the list once you do.'**
  String get signInDialogContextInvite;

  /// No description provided for @signInDialogContextResume.
  ///
  /// In en, this message translates to:
  /// **'Sign in again to push your queued edits.'**
  String get signInDialogContextResume;

  /// No description provided for @settingsSignOutConfirmBodyWithPending.
  ///
  /// In en, this message translates to:
  /// **'You have unsynced edits on {count} list(s). Signing out won\'t push them to the server. Are you sure?'**
  String settingsSignOutConfirmBodyWithPending(int count);

  /// No description provided for @overviewResumeSignInIdle.
  ///
  /// In en, this message translates to:
  /// **'Sign in to sync your shared lists across devices.'**
  String get overviewResumeSignInIdle;

  /// No description provided for @overviewResumeSignInWithPending.
  ///
  /// In en, this message translates to:
  /// **'You have unsynced edits. Sign in again to push them.'**
  String get overviewResumeSignInWithPending;

  /// No description provided for @overviewResumeSignInButton.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get overviewResumeSignInButton;

  /// No description provided for @flashcardsSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save your revision progress.'**
  String get flashcardsSaveFailed;

  /// No description provided for @engineSessionExpiredSnack.
  ///
  /// In en, this message translates to:
  /// **'Signed out — please sign in again'**
  String get engineSessionExpiredSnack;

  /// No description provided for @engineSessionExpiredSnackAction.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get engineSessionExpiredSnackAction;

  /// No description provided for @engineRemovedAsEditorSnack.
  ///
  /// In en, this message translates to:
  /// **'You\'re no longer an editor of this list'**
  String get engineRemovedAsEditorSnack;

  /// No description provided for @engineSnapshotCatchUpSnack.
  ///
  /// In en, this message translates to:
  /// **'This list changed a lot while you were offline — review your recent edits.'**
  String get engineSnapshotCatchUpSnack;

  /// No description provided for @importedListFallbackName.
  ///
  /// In en, this message translates to:
  /// **'Imported list'**
  String get importedListFallbackName;

  /// No description provided for @favouritesListName.
  ///
  /// In en, this message translates to:
  /// **'Favourites'**
  String get favouritesListName;

  /// No description provided for @listNameErrorEmpty.
  ///
  /// In en, this message translates to:
  /// **'List name cannot be empty'**
  String get listNameErrorEmpty;

  /// No description provided for @listNameErrorInvalid.
  ///
  /// In en, this message translates to:
  /// **'Invalid list name'**
  String get listNameErrorInvalid;

  /// No description provided for @listNameErrorReserved.
  ///
  /// In en, this message translates to:
  /// **'List name \"{name}\" is reserved'**
  String listNameErrorReserved(String name);

  /// No description provided for @listNameErrorAlreadyExists.
  ///
  /// In en, this message translates to:
  /// **'A list with that name already exists'**
  String get listNameErrorAlreadyExists;

  /// No description provided for @legalInformationPageTitle.
  ///
  /// In en, this message translates to:
  /// **'Legal Information'**
  String get legalInformationPageTitle;

  /// No description provided for @buildInformationPageTitle.
  ///
  /// In en, this message translates to:
  /// **'Build Information'**
  String get buildInformationPageTitle;

  /// No description provided for @backgroundLogsPageTitle.
  ///
  /// In en, this message translates to:
  /// **'Background Logs'**
  String get backgroundLogsPageTitle;

  /// No description provided for @backgroundLogsCopyButton.
  ///
  /// In en, this message translates to:
  /// **'Copy logs to clipboard'**
  String get backgroundLogsCopyButton;

  /// No description provided for @backgroundLogsCopiedSnack.
  ///
  /// In en, this message translates to:
  /// **'Logs copied to clipboard'**
  String get backgroundLogsCopiedSnack;

  /// No description provided for @reportIssueEmailSubject.
  ///
  /// In en, this message translates to:
  /// **'Issue with {appName}'**
  String reportIssueEmailSubject(String appName);

  /// No description provided for @signInTestUserButton.
  ///
  /// In en, this message translates to:
  /// **'Sign in as test user (debug)'**
  String get signInTestUserButton;

  /// No description provided for @signInTestPromptTitle.
  ///
  /// In en, this message translates to:
  /// **'Test sign-in'**
  String get signInTestPromptTitle;

  /// No description provided for @signInTestPromptBody.
  ///
  /// In en, this message translates to:
  /// **'Mints a session on the worker\'s test provider. Debug builds only. Use this to drive the shared-lists feature without a real provider account.'**
  String get signInTestPromptBody;

  /// No description provided for @signInTestUserIdLabel.
  ///
  /// In en, this message translates to:
  /// **'User id (test:<slug>)'**
  String get signInTestUserIdLabel;

  /// No description provided for @signInTestDisplayNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Display name'**
  String get signInTestDisplayNameLabel;

  /// No description provided for @signInTestPromptConfirm.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get signInTestPromptConfirm;

  /// No description provided for @searchRecent.
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get searchRecent;

  /// No description provided for @searchRecentClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get searchRecentClear;

  /// No description provided for @searchSignOfTheDay.
  ///
  /// In en, this message translates to:
  /// **'Sign of the day'**
  String get searchSignOfTheDay;

  /// No description provided for @signOfTheDayBlurb.
  ///
  /// In en, this message translates to:
  /// **'A new sign to learn each day.'**
  String get signOfTheDayBlurb;

  /// No description provided for @signOfTheDayInfo.
  ///
  /// In en, this message translates to:
  /// **'The sign of the day is a random word from the lists you\'ve created or subscribed to. It changes once a day.'**
  String get signOfTheDayInfo;

  /// No description provided for @searchResultCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 result} other{{count} results}}'**
  String searchResultCount(int count);

  /// No description provided for @entryTypePhrase.
  ///
  /// In en, this message translates to:
  /// **'Phrase'**
  String get entryTypePhrase;

  /// No description provided for @searchNoMatchTitle.
  ///
  /// In en, this message translates to:
  /// **'No signs for \"{query}\"'**
  String searchNoMatchTitle(String query);

  /// No description provided for @searchNoMatchBody.
  ///
  /// In en, this message translates to:
  /// **'Check the spelling, or try a related word. Some signs are listed under a different English word.'**
  String get searchNoMatchBody;

  /// No description provided for @newsEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No announcements yet'**
  String get newsEmptyTitle;

  /// No description provided for @newsEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'App news and tips will show up here.'**
  String get newsEmptyBody;

  /// No description provided for @newsErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load news'**
  String get newsErrorTitle;

  /// No description provided for @newsErrorBody.
  ///
  /// In en, this message translates to:
  /// **'Check your connection and try again later.'**
  String get newsErrorBody;

  /// No description provided for @saveVideoFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t update your lists. Please try again.'**
  String get saveVideoFailed;

  /// No description provided for @videoOfflineError.
  ///
  /// In en, this message translates to:
  /// **'Failed to load video. Please confirm your device is connected to the internet. If it is, the servers may be having issues. This is not an issue with the app itself.'**
  String get videoOfflineError;

  /// No description provided for @listsEditHint.
  ///
  /// In en, this message translates to:
  /// **'Tap the pencil to reorder, rename, or create a new list.'**
  String get listsEditHint;

  /// No description provided for @listsReorderHint.
  ///
  /// In en, this message translates to:
  /// **'Drag a list to reorder it, or tap it to rename. Favourites stays pinned to the top.'**
  String get listsReorderHint;

  /// No description provided for @listWordCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 word} other{{count} words}}'**
  String listWordCount(int count);

  /// No description provided for @listSubscribeViaLink.
  ///
  /// In en, this message translates to:
  /// **'Subscribe via link'**
  String get listSubscribeViaLink;

  /// No description provided for @listSubscribedEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Tap the cloud icon up top to subscribe to a shared list, or open a share link from someone else. No account needed.'**
  String get listSubscribedEmptyBody;

  /// No description provided for @revisionStreak.
  ///
  /// In en, this message translates to:
  /// **'{days, plural, =1{1-day streak} other{{days}-day streak}}'**
  String revisionStreak(int days);

  /// No description provided for @revisionStreakSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Longest run yet — keep it going!'**
  String get revisionStreakSubtitle;

  /// No description provided for @revisionSignCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 sign} other{{count} signs}}'**
  String revisionSignCount(int count);

  /// No description provided for @revisionNoListsChosen.
  ///
  /// In en, this message translates to:
  /// **'No lists chosen yet'**
  String get revisionNoListsChosen;

  /// No description provided for @flashcardsAddAnotherList.
  ///
  /// In en, this message translates to:
  /// **'Add another list'**
  String get flashcardsAddAnotherList;

  /// No description provided for @flashcardsSignToWordSubtitle.
  ///
  /// In en, this message translates to:
  /// **'See a sign, recall the word'**
  String get flashcardsSignToWordSubtitle;

  /// No description provided for @flashcardsWordToSignSubtitle.
  ///
  /// In en, this message translates to:
  /// **'See a word, recall the sign'**
  String get flashcardsWordToSignSubtitle;

  /// No description provided for @flashcardsChooseType.
  ///
  /// In en, this message translates to:
  /// **'Choose at least one flashcard type.'**
  String get flashcardsChooseType;

  /// No description provided for @flashcardsStrategyLabel.
  ///
  /// In en, this message translates to:
  /// **'Strategy'**
  String get flashcardsStrategyLabel;

  /// No description provided for @flashcardsCardLimitLabel.
  ///
  /// In en, this message translates to:
  /// **'Card limit'**
  String get flashcardsCardLimitLabel;

  /// No description provided for @flashcardsCardLimitNone.
  ///
  /// In en, this message translates to:
  /// **'No limit'**
  String get flashcardsCardLimitNone;

  /// No description provided for @revisionPreviousCard.
  ///
  /// In en, this message translates to:
  /// **'Previous card'**
  String get revisionPreviousCard;

  /// No description provided for @revisionNextCard.
  ///
  /// In en, this message translates to:
  /// **'Next card'**
  String get revisionNextCard;

  /// No description provided for @revisionDueNow.
  ///
  /// In en, this message translates to:
  /// **'Due now'**
  String get revisionDueNow;

  /// No description provided for @revisionSelected.
  ///
  /// In en, this message translates to:
  /// **'Selected'**
  String get revisionSelected;

  /// No description provided for @revisionFlashcardCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 flashcard} other{{count} flashcards}}'**
  String revisionFlashcardCount(int count);

  /// No description provided for @playbackSpeedTitle.
  ///
  /// In en, this message translates to:
  /// **'Playback speed'**
  String get playbackSpeedTitle;

  /// No description provided for @playbackSpeedNormal.
  ///
  /// In en, this message translates to:
  /// **'Normal'**
  String get playbackSpeedNormal;

  /// No description provided for @regionSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign regions'**
  String get regionSheetTitle;

  /// No description provided for @regionSheetDescription.
  ///
  /// In en, this message translates to:
  /// **'Signs marked for all of Australia are always included. Add more regions below.'**
  String get regionSheetDescription;

  /// No description provided for @regionSheetDialects.
  ///
  /// In en, this message translates to:
  /// **'Dialects'**
  String get regionSheetDialects;

  /// No description provided for @regionSheetStatesTerritories.
  ///
  /// In en, this message translates to:
  /// **'States & territories'**
  String get regionSheetStatesTerritories;

  /// No description provided for @regionSheetRecommended.
  ///
  /// In en, this message translates to:
  /// **'Recommended'**
  String get regionSheetRecommended;

  /// No description provided for @regionSheetUnknownExplanation.
  ///
  /// In en, this message translates to:
  /// **'Most signs aren\'t tagged with a region, so leaving this on keeps them in your revision.'**
  String get regionSheetUnknownExplanation;

  /// No description provided for @regionSheetUnknownSignsTitle.
  ///
  /// In en, this message translates to:
  /// **'Signs with unknown region'**
  String get regionSheetUnknownSignsTitle;

  /// No description provided for @regionSubtitleAllAustralia.
  ///
  /// In en, this message translates to:
  /// **'All of Australia'**
  String get regionSubtitleAllAustralia;

  /// No description provided for @regionSubtitleRegionCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 region} other{{count} regions}}'**
  String regionSubtitleRegionCount(int count);

  /// No description provided for @regionSubtitleUnknownSigns.
  ///
  /// In en, this message translates to:
  /// **'unknown-region signs'**
  String get regionSubtitleUnknownSigns;

  /// No description provided for @wordVariationWithHint.
  ///
  /// In en, this message translates to:
  /// **'Variation {index} of {count}'**
  String wordVariationWithHint(int index, int count);

  /// No description provided for @videoIndicator.
  ///
  /// In en, this message translates to:
  /// **'Video {index} of {count}'**
  String videoIndicator(int index, int count);

  /// No description provided for @seeAlso.
  ///
  /// In en, this message translates to:
  /// **'See also'**
  String get seeAlso;

  /// No description provided for @tapToReveal.
  ///
  /// In en, this message translates to:
  /// **'Tap to reveal'**
  String get tapToReveal;

  /// No description provided for @openDictionaryEntry.
  ///
  /// In en, this message translates to:
  /// **'Open dictionary entry'**
  String get openDictionaryEntry;

  /// No description provided for @ratingForgot.
  ///
  /// In en, this message translates to:
  /// **'Forgot'**
  String get ratingForgot;

  /// No description provided for @ratingGotIt.
  ///
  /// In en, this message translates to:
  /// **'Got it!'**
  String get ratingGotIt;

  /// No description provided for @ratingNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get ratingNext;

  /// No description provided for @sessionComplete.
  ///
  /// In en, this message translates to:
  /// **'Session complete'**
  String get sessionComplete;

  /// No description provided for @sessionCompleteHeadline.
  ///
  /// In en, this message translates to:
  /// **'Nice work — that\'s {count, plural, =1{1 sign revised} other{{count} signs revised}}'**
  String sessionCompleteHeadline(int count);

  /// No description provided for @summarySuccess.
  ///
  /// In en, this message translates to:
  /// **'success'**
  String get summarySuccess;

  /// No description provided for @summaryCards.
  ///
  /// In en, this message translates to:
  /// **'Cards'**
  String get summaryCards;

  /// No description provided for @summaryGotIt.
  ///
  /// In en, this message translates to:
  /// **'Got it'**
  String get summaryGotIt;

  /// No description provided for @summaryForgot.
  ///
  /// In en, this message translates to:
  /// **'Forgot'**
  String get summaryForgot;

  /// No description provided for @studyPromptSignToWord.
  ///
  /// In en, this message translates to:
  /// **'What does this sign mean?'**
  String get studyPromptSignToWord;

  /// No description provided for @studyPromptWordToSign.
  ///
  /// In en, this message translates to:
  /// **'What is the sign for this word?'**
  String get studyPromptWordToSign;

  /// No description provided for @videoRotate.
  ///
  /// In en, this message translates to:
  /// **'Rotate video'**
  String get videoRotate;

  /// No description provided for @saveVideoButton.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get saveVideoButton;

  /// No description provided for @savedToListCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Saved to 1 list} other{Saved to {count} lists}}'**
  String savedToListCount(int count);

  /// No description provided for @revisionSummaryTitle.
  ///
  /// In en, this message translates to:
  /// **'Revision summary'**
  String get revisionSummaryTitle;

  /// No description provided for @revisionStatsEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No stats yet'**
  String get revisionStatsEmptyTitle;

  /// No description provided for @revisionStatsEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Finish a revision session and your progress will show up here.'**
  String get revisionStatsEmptyBody;

  /// No description provided for @saveToNamedList.
  ///
  /// In en, this message translates to:
  /// **'Save to {listName}'**
  String saveToNamedList(String listName);

  /// No description provided for @savedToNamedList.
  ///
  /// In en, this message translates to:
  /// **'Saved to {listName}'**
  String savedToNamedList(String listName);

  /// No description provided for @webLimitationsHeading.
  ///
  /// In en, this message translates to:
  /// **'Using the web version'**
  String get webLimitationsHeading;

  /// No description provided for @webLimitationsNoSaving.
  ///
  /// In en, this message translates to:
  /// **'You can\'t save signs or favourites'**
  String get webLimitationsNoSaving;

  /// No description provided for @webLimitationsNoLists.
  ///
  /// In en, this message translates to:
  /// **'You can\'t create your own lists'**
  String get webLimitationsNoLists;

  /// No description provided for @webLimitationsNoRevision.
  ///
  /// In en, this message translates to:
  /// **'No revision or flashcards'**
  String get webLimitationsNoRevision;

  /// No description provided for @webLimitationsNoSignIn.
  ///
  /// In en, this message translates to:
  /// **'No signing in or editing shared lists'**
  String get webLimitationsNoSignIn;

  /// No description provided for @webLimitationsListsHeading.
  ///
  /// In en, this message translates to:
  /// **'Lists on the web'**
  String get webLimitationsListsHeading;

  /// No description provided for @webLimitationsListsBody.
  ///
  /// In en, this message translates to:
  /// **'You can\'t create or save your own lists on the web version — that\'s a mobile-app feature. Browse the Community tab, or open a list someone shares with you, to view signs read-only.'**
  String get webLimitationsListsBody;

  /// No description provided for @webLimitationsFooter.
  ///
  /// In en, this message translates to:
  /// **'For all of that, install the mobile app.'**
  String get webLimitationsFooter;

  /// No description provided for @webSharingUnavailableTitle.
  ///
  /// In en, this message translates to:
  /// **'Use the mobile app'**
  String get webSharingUnavailableTitle;

  /// No description provided for @webSharingUnavailableBody.
  ///
  /// In en, this message translates to:
  /// **'Signing in, and publishing or editing shared lists, aren\'t available in the web version. Install the {appName} app on your phone to create, publish and edit shared lists. You can still browse the dictionary and open shared lists read-only here.'**
  String webSharingUnavailableBody(String appName);

  /// No description provided for @videoCarouselPrevious.
  ///
  /// In en, this message translates to:
  /// **'Previous video'**
  String get videoCarouselPrevious;

  /// No description provided for @videoCarouselNext.
  ///
  /// In en, this message translates to:
  /// **'Next video'**
  String get videoCarouselNext;

  /// No description provided for @variationPrevious.
  ///
  /// In en, this message translates to:
  /// **'Previous variation'**
  String get variationPrevious;

  /// No description provided for @variationNext.
  ///
  /// In en, this message translates to:
  /// **'Next variation'**
  String get variationNext;

  /// No description provided for @webVideoLoadError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load this video.'**
  String get webVideoLoadError;

  /// No description provided for @settingsLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguage;

  /// No description provided for @deviceDefault.
  ///
  /// In en, this message translates to:
  /// **'Device default'**
  String get deviceDefault;

  /// No description provided for @wordDataMissing.
  ///
  /// In en, this message translates to:
  /// **'No data available for this language.'**
  String get wordDataMissing;

  /// No description provided for @wordNoDefinitions.
  ///
  /// In en, this message translates to:
  /// **'No definitions available.'**
  String get wordNoDefinitions;

  /// No description provided for @flashcardsAllOfSriLanka.
  ///
  /// In en, this message translates to:
  /// **'All of Sri Lanka'**
  String get flashcardsAllOfSriLanka;

  /// No description provided for @flashcardsNorthEast.
  ///
  /// In en, this message translates to:
  /// **'North East'**
  String get flashcardsNorthEast;
}

class _DictLibLocalizationsDelegate
    extends LocalizationsDelegate<DictLibLocalizations> {
  const _DictLibLocalizationsDelegate();

  @override
  Future<DictLibLocalizations> load(Locale locale) {
    return SynchronousFuture<DictLibLocalizations>(
        lookupDictLibLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'si', 'ta'].contains(locale.languageCode);

  @override
  bool shouldReload(_DictLibLocalizationsDelegate old) => false;
}

DictLibLocalizations lookupDictLibLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return DictLibLocalizationsEn();
    case 'si':
      return DictLibLocalizationsSi();
    case 'ta':
      return DictLibLocalizationsTa();
  }

  throw FlutterError(
      'DictLibLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
