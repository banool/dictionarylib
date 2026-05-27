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

  /// No description provided for @nFlashcardsSelected.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{cards} =1{cards} other{cards}}'**
  String nFlashcardsSelected(num count);

  /// No description provided for @nFlashcardsDue.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{cards} =1{cards} other{cards}}'**
  String nFlashcardsDue(num count);

  /// No description provided for @flashcardsRevisionSources.
  ///
  /// In en, this message translates to:
  /// **'Revision Sources'**
  String get flashcardsRevisionSources;

  /// No description provided for @flashcardsSelectListsToRevise.
  ///
  /// In en, this message translates to:
  /// **'Select lists to revise'**
  String get flashcardsSelectListsToRevise;

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
  /// **'Sign -> Word'**
  String get flashcardsSignToWord;

  /// No description provided for @flashcardsWordToSign.
  ///
  /// In en, this message translates to:
  /// **'Word -> Sign'**
  String get flashcardsWordToSign;

  /// No description provided for @flashcardsRevisionSettings.
  ///
  /// In en, this message translates to:
  /// **'Revision Settings'**
  String get flashcardsRevisionSettings;

  /// No description provided for @flashcardsSelectRevisionStrategy.
  ///
  /// In en, this message translates to:
  /// **'Select revision strategy'**
  String get flashcardsSelectRevisionStrategy;

  /// No description provided for @flashcardsStrategy.
  ///
  /// In en, this message translates to:
  /// **'Strategy'**
  String get flashcardsStrategy;

  /// No description provided for @flashcardsSelectSignRegions.
  ///
  /// In en, this message translates to:
  /// **'Select sign regions'**
  String get flashcardsSelectSignRegions;

  /// No description provided for @flashcardsRegions.
  ///
  /// In en, this message translates to:
  /// **'Regions'**
  String get flashcardsRegions;

  /// No description provided for @flashcardsStart.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get flashcardsStart;

  /// No description provided for @flashcardsOnlyOneCard.
  ///
  /// In en, this message translates to:
  /// **'Show only one set of cards per word'**
  String get flashcardsOnlyOneCard;

  /// No description provided for @flashcardsRevisionLanguage.
  ///
  /// In en, this message translates to:
  /// **'Revision Language'**
  String get flashcardsRevisionLanguage;

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

  /// No description provided for @flashcardsNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get flashcardsNext;

  /// No description provided for @flashcardsForgot.
  ///
  /// In en, this message translates to:
  /// **'Forgot'**
  String get flashcardsForgot;

  /// No description provided for @flashcardsGotIt.
  ///
  /// In en, this message translates to:
  /// **'Got it!'**
  String get flashcardsGotIt;

  /// No description provided for @flashcardsWhatIsSignForWord.
  ///
  /// In en, this message translates to:
  /// **'What is the sign for this word?'**
  String get flashcardsWhatIsSignForWord;

  /// No description provided for @flashcardsWhatDoesSignMean.
  ///
  /// In en, this message translates to:
  /// **'What does this sign mean?'**
  String get flashcardsWhatDoesSignMean;

  /// No description provided for @flashcardsOpenDictionaryEntry.
  ///
  /// In en, this message translates to:
  /// **'Open dictionary entry'**
  String get flashcardsOpenDictionaryEntry;

  /// No description provided for @flashcardsSuccessRate.
  ///
  /// In en, this message translates to:
  /// **'Success Rate'**
  String get flashcardsSuccessRate;

  /// No description provided for @flashcardsTotalCards.
  ///
  /// In en, this message translates to:
  /// **'Total Cards'**
  String get flashcardsTotalCards;

  /// No description provided for @flashcardsSuccessfulCards.
  ///
  /// In en, this message translates to:
  /// **'Successful Cards'**
  String get flashcardsSuccessfulCards;

  /// No description provided for @flashcardsIncorrectCards.
  ///
  /// In en, this message translates to:
  /// **'Incorrect Cards'**
  String get flashcardsIncorrectCards;

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

  /// No description provided for @flashcardsLongestStreak.
  ///
  /// In en, this message translates to:
  /// **'Longest Streak'**
  String get flashcardsLongestStreak;

  /// No description provided for @flashcardsStatsCollectedSince.
  ///
  /// In en, this message translates to:
  /// **'Stats collected since'**
  String get flashcardsStatsCollectedSince;

  /// No description provided for @flashcardsRevisionSummaryTitle.
  ///
  /// In en, this message translates to:
  /// **'Revision Summary'**
  String get flashcardsRevisionSummaryTitle;

  /// No description provided for @flashcardsRevisionProgressTitle.
  ///
  /// In en, this message translates to:
  /// **'Revision Progress'**
  String get flashcardsRevisionProgressTitle;

  /// No description provided for @flashcardsRevisionStategyToShow.
  ///
  /// In en, this message translates to:
  /// **'Revision strategy to show stats for'**
  String get flashcardsRevisionStategyToShow;

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

  /// No description provided for @na.
  ///
  /// In en, this message translates to:
  /// **'N/A'**
  String get na;

  /// No description provided for @settingsLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguage;

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

  /// No description provided for @listFavourites.
  ///
  /// In en, this message translates to:
  /// **'Favourites'**
  String get listFavourites;

  /// No description provided for @listNameCannotBeEmpty.
  ///
  /// In en, this message translates to:
  /// **'List name cannot be empty'**
  String get listNameCannotBeEmpty;

  /// No description provided for @listNameInvalid.
  ///
  /// In en, this message translates to:
  /// **'Invalid name, this should have been caught already'**
  String get listNameInvalid;

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

  /// No description provided for @listNewList.
  ///
  /// In en, this message translates to:
  /// **'New List'**
  String get listNewList;

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

  /// No description provided for @wordAlreadyFavourited.
  ///
  /// In en, this message translates to:
  /// **'Already favourited!'**
  String get wordAlreadyFavourited;

  /// No description provided for @wordFavouriteThisWord.
  ///
  /// In en, this message translates to:
  /// **'Favourite this word'**
  String get wordFavouriteThisWord;

  /// No description provided for @wordNoDefinitions.
  ///
  /// In en, this message translates to:
  /// **'No definitions data available for this word / phrase'**
  String get wordNoDefinitions;

  /// No description provided for @wordDataMissing.
  ///
  /// In en, this message translates to:
  /// **'Data missing'**
  String get wordDataMissing;

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

  /// No description provided for @relatedWords.
  ///
  /// In en, this message translates to:
  /// **'Related words'**
  String get relatedWords;

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

  /// No description provided for @startupFailureMessage.
  ///
  /// In en, this message translates to:
  /// **'Failed to start the app correctly. First, please confirm you are using the latest version of the app. If you are, please email daniel@dport.me with a screenshot showing this error.'**
  String get startupFailureMessage;

  /// No description provided for @unexpectedErrorLoadingVideo.
  ///
  /// In en, this message translates to:
  /// **'Unexpected error loading media'**
  String get unexpectedErrorLoadingVideo;

  /// No description provided for @deviceDefault.
  ///
  /// In en, this message translates to:
  /// **'Device Default'**
  String get deviceDefault;

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
  /// **'To share a list, sign in below. We only use this to prove that you\'re the one editing it later — we don\'t collect any personal information.'**
  String get signInDialogBody;

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
  /// **'Paste either a share link or just the list ID at the end of one.'**
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

  /// No description provided for @subscribeInvalidInput.
  ///
  /// In en, this message translates to:
  /// **'Not a valid share link or list ID.'**
  String get subscribeInvalidInput;

  /// No description provided for @subscribeInputIsInviteUrl.
  ///
  /// In en, this message translates to:
  /// **'That\'s an invite link — tap it from your phone to join as editor instead of subscribing.'**
  String get subscribeInputIsInviteUrl;

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

  /// No description provided for @settingsSignedInAs.
  ///
  /// In en, this message translates to:
  /// **'Signed in with {provider}'**
  String settingsSignedInAs(String provider);

  /// No description provided for @settingsSignOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get settingsSignOut;

  /// No description provided for @settingsSignOutConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign out?'**
  String get settingsSignOutConfirmTitle;

  /// No description provided for @settingsSignOutConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'Your shared lists stay on the server. You\'ll need to sign in again to edit or unshare them.'**
  String get settingsSignOutConfirmBody;

  /// No description provided for @settingsClearSharingData.
  ///
  /// In en, this message translates to:
  /// **'Clear sharing data'**
  String get settingsClearSharingData;

  /// No description provided for @settingsClearSharingDataConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Clear sharing data?'**
  String get settingsClearSharingDataConfirmTitle;

  /// No description provided for @settingsClearSharingDataConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'On this device:\n  • You\'re signed out of sharing.\n  • Lists you shared stop being managed from here — the local lists themselves keep their entries.\n  • Your subscriptions are removed.\n\nYour shared lists stay on the server. Sign back in on any device to edit them again.'**
  String get settingsClearSharingDataConfirmBody;

  /// No description provided for @alertSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get alertSave;

  /// No description provided for @alertDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get alertDone;

  /// No description provided for @listNameAllowedChars.
  ///
  /// In en, this message translates to:
  /// **'No special characters besides these are allowed: , . - _ !'**
  String get listNameAllowedChars;

  /// No description provided for @forceUpgradeMessage.
  ///
  /// In en, this message translates to:
  /// **'You are using an unsupported version ({version}) of the app, please update.'**
  String forceUpgradeMessage(String version);

  /// No description provided for @forceUpgradeButton.
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get forceUpgradeButton;

  /// No description provided for @privacyPolicyPageTitle.
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get privacyPolicyPageTitle;

  /// No description provided for @importOwnedListsPromptTitle.
  ///
  /// In en, this message translates to:
  /// **'Import your shared lists?'**
  String get importOwnedListsPromptTitle;

  /// No description provided for @importOwnedListsPromptBody.
  ///
  /// In en, this message translates to:
  /// **'We\'ll fetch any shared lists tied to this account — both the ones you created and the ones you\'ve been added to as an editor — and install them on this device. Existing local lists are untouched; name collisions get a numeric suffix (e.g. \"Cats\" → \"Cats 2\"). Edits sync automatically when you\'re online.'**
  String get importOwnedListsPromptBody;

  /// No description provided for @importOwnedListsActionImport.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get importOwnedListsActionImport;

  /// No description provided for @importOwnedListsActionSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get importOwnedListsActionSkip;

  /// No description provided for @importOwnedListsRunning.
  ///
  /// In en, this message translates to:
  /// **'Importing your shared lists…'**
  String get importOwnedListsRunning;

  /// No description provided for @importOwnedListsFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t import lists: {message}'**
  String importOwnedListsFailed(String message);

  /// No description provided for @importOwnedListsResultNone.
  ///
  /// In en, this message translates to:
  /// **'No shared lists found.'**
  String get importOwnedListsResultNone;

  /// No description provided for @importOwnedListsResultDone.
  ///
  /// In en, this message translates to:
  /// **'Imported {imported} of {total} list(s).'**
  String importOwnedListsResultDone(int imported, int total);

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
  /// **'Shared with me'**
  String get listSharedWithMeTab;

  /// No description provided for @listSharedWithMeEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing here yet.\n\nTap the cloud-download icon up top to subscribe to a shared list, or open a share/invite link from someone else.'**
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
  /// **'pending sync'**
  String get ownedStatusPendingSyncSuffix;

  /// No description provided for @ownedStatusSyncedSuffix.
  ///
  /// In en, this message translates to:
  /// **'synced'**
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
  /// **'synced just now'**
  String get syncedJustNow;

  /// No description provided for @syncedMinutesAgo.
  ///
  /// In en, this message translates to:
  /// **'synced {count}m ago'**
  String syncedMinutesAgo(int count);

  /// No description provided for @syncedHoursAgo.
  ///
  /// In en, this message translates to:
  /// **'synced {count}h ago'**
  String syncedHoursAgo(int count);

  /// No description provided for @syncedDaysAgo.
  ///
  /// In en, this message translates to:
  /// **'synced {count}d ago'**
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
  /// **'synced {sync} · updated {updated}'**
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
  /// **'Expires in 7 days. The link can be used once.'**
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
  /// **'You\'re the creator of "{displayName}" — no need to accept your own invite.'**
  String acceptInviteLandingAlreadyOwner(String displayName);

  /// No description provided for @acceptInviteLandingAlreadyEditor.
  ///
  /// In en, this message translates to:
  /// **'You already edit "{displayName}".'**
  String acceptInviteLandingAlreadyEditor(String displayName);

  /// No description provided for @membersPageTitle.
  ///
  /// In en, this message translates to:
  /// **'Members'**
  String get membersPageTitle;

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

  /// No description provided for @membersPageSubtitleFor.
  ///
  /// In en, this message translates to:
  /// **'Members of \"{name}\"'**
  String membersPageSubtitleFor(String name);

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

  /// No description provided for @settingsSignedInAsNamed.
  ///
  /// In en, this message translates to:
  /// **'Signed in as {name} via {provider}'**
  String settingsSignedInAsNamed(String name, String provider);

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

  /// No description provided for @expiredSessionBanner.
  ///
  /// In en, this message translates to:
  /// **'Your session expired. Sign in again to push your edits.'**
  String get expiredSessionBanner;

  /// No description provided for @expiredSessionBannerAction.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get expiredSessionBannerAction;

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
  /// **'List name "{name}" is reserved'**
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

  /// No description provided for @forkPartialDrop.
  ///
  /// In en, this message translates to:
  /// **'Copied {copied} of {total} entries — {dropped} signs are no longer in the dictionary.'**
  String forkPartialDrop(int copied, int total, int dropped);

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
