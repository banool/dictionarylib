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
  DictLibLocalizations(String locale) : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static DictLibLocalizations? of(BuildContext context) {
    return Localizations.of<DictLibLocalizations>(context, DictLibLocalizations);
  }

  static const LocalizationsDelegate<DictLibLocalizations> delegate = _DictLibLocalizationsDelegate();

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
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates = <LocalizationsDelegate<dynamic>>[
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

  /// No description provided for @startupFailureMessage.
  ///
  /// In en, this message translates to:
  /// **'Failed to start the app correctly. First, please confirm you are using the latest version of the app. If you are, please email daniel@dport.me with a screenshot showing this error.'**
  String get startupFailureMessage;

  /// No description provided for @unexpectedErrorLoadingVideo.
  ///
  /// In en, this message translates to:
  /// **'Unexpected error loading'**
  String get unexpectedErrorLoadingVideo;

  /// No description provided for @deviceDefault.
  ///
  /// In en, this message translates to:
  /// **'Device Default'**
  String get deviceDefault;
}

class _DictLibLocalizationsDelegate extends LocalizationsDelegate<DictLibLocalizations> {
  const _DictLibLocalizationsDelegate();

  @override
  Future<DictLibLocalizations> load(Locale locale) {
    return SynchronousFuture<DictLibLocalizations>(lookupDictLibLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>['en', 'si', 'ta'].contains(locale.languageCode);

  @override
  bool shouldReload(_DictLibLocalizationsDelegate old) => false;
}

DictLibLocalizations lookupDictLibLocalizations(Locale locale) {


  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en': return DictLibLocalizationsEn();
    case 'si': return DictLibLocalizationsSi();
    case 'ta': return DictLibLocalizationsTa();
  }

  throw FlutterError(
    'DictLibLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.'
  );
}
