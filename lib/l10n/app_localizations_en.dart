import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'SLSL Dictionary';

  @override
  String get newsTitle => 'News';

  @override
  String get searchTitle => 'Search';

  @override
  String get listsTitle => 'Lists';

  @override
  String get revisionTitle => 'Revision';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get searchHintText => 'Search for a word';

  @override
  String nFlashcardsSelected(num count) {
    final intl.NumberFormat countNumberFormat = intl.NumberFormat.compact(
      locale: localeName,
      
    );
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'cards',
      one: 'cards',
      zero: 'cards',
    );
    return '$_temp0';
  }

  @override
  String nFlashcardsDue(num count) {
    final intl.NumberFormat countNumberFormat = intl.NumberFormat.compact(
      locale: localeName,
      
    );
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'cards',
      one: 'cards',
      zero: 'cards',
    );
    return '$_temp0';
  }

  @override
  String get flashcardsRevisionSources => 'Revision Sources';

  @override
  String get flashcardsSelectListsToRevise => 'Select lists to revise';

  @override
  String get flashcardsSelectLists => 'Select Lists';

  @override
  String get flashcardsTypes => 'Flashcard Types';

  @override
  String get flashcardsSignToWord => 'Sign -> Word';

  @override
  String get flashcardsWordToSign => 'Word -> Sign';

  @override
  String get flashcardsRevisionSettings => 'Revision Settings';

  @override
  String get flashcardsSelectRevisionStrategy => 'Select revision strategy';

  @override
  String get flashcardsStrategy => 'Strategy';

  @override
  String get flashcardsSelectSignRegions => 'Select sign regions';

  @override
  String get flashcardsRegions => 'Regions';

  @override
  String get flashcardsStart => 'Start';

  @override
  String get flashcardsOnlyOneCard => 'Show only one set of cards per word';

  @override
  String get flashcardsRevisionLanguage => 'Revision Language';

  @override
  String get flashcardsAllOfSriLanka => 'All of Sri Lanka';

  @override
  String get flashcardsNorthEast => 'North East';

  @override
  String get flashcardsNext => 'Next';

  @override
  String get flashcardsForgot => 'Forgot';

  @override
  String get flashcardsGotIt => 'Got it!';

  @override
  String get flashcardsWhatIsSignForWord => 'What is the sign for this word?';

  @override
  String get flashcardsWhatDoesSignMean => 'What does this sign mean?';

  @override
  String get flashcardsOpenDictionaryEntry => 'Open dictionary entry';

  @override
  String get flashcardsSuccessRate => 'Success Rate';

  @override
  String get flashcardsTotalCards => 'Total Cards';

  @override
  String get flashcardsSuccessfulCards => 'Successful Cards';

  @override
  String get flashcardsIncorrectCards => 'Incorrect Cards';

  @override
  String get flashcardsTotalReviews => 'Total Reviews';

  @override
  String get flashcardsUnsuccessfulCards => 'Unsuccessful Cards';

  @override
  String get flashcardsUniqueWords => 'Unique Words';

  @override
  String get flashcardsLongestStreak => 'Longest Streak';

  @override
  String get flashcardsStatsCollectedSince => 'Stats collected since';

  @override
  String get flashcardsRevisionSummaryTitle => 'Revision Summary';

  @override
  String get flashcardsRevisionProgressTitle => 'Revision Progress';

  @override
  String get flashcardsRevisionStategyToShow => 'Revision strategy to show stats for';

  @override
  String get setPlaybackSpeedTo => 'Set playback speed to';

  @override
  String get settingsPlayStoreFeedback => 'Give feedback on Play Store';

  @override
  String get settingsAppStoreFeedback => 'Give feedback on App Store';

  @override
  String get na => 'N/A';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsRevision => 'Revision';

  @override
  String get settingsHideRevision => 'Hide revision feature';

  @override
  String get settingsDeleteRevisionProgress => 'Delete all revision progress';

  @override
  String get settingsDeleteRevisionProgressExplanation => 'This will delete all your review progress from all time for both the spaced repetition and random review strategies. Your lists (including favourites) will not be affected. Are you 100% sure you want to do this?';

  @override
  String get settingsProgressDeleted => 'All review progress deleted';

  @override
  String get settingsCache => 'Cache';

  @override
  String get settingsCacheVideos => 'Cache videos';

  @override
  String get settingsDropCache => 'Drop cache';

  @override
  String get settingsCacheDropped => 'Cache dropped';

  @override
  String get settingsData => 'Data';

  @override
  String get settingsCheckNewData => 'Check for new dictionary data';

  @override
  String get settingsDataUpdated => 'Successfully updated dictionary data';

  @override
  String get settingsDataUpToDate => 'Data is already up to date';

  @override
  String get settingsLegal => 'Legal';

  @override
  String get settingsSeeLegal => 'See legal information';

  @override
  String get settingsBackgroundLogs => 'Background logs';

  @override
  String get settingsHelp => 'Help';

  @override
  String get settingsReportDictionaryDataIssue => 'Report issue with dictionary data';

  @override
  String get settingsReportAppIssueGithub => 'Report issue with app (GitHub)';

  @override
  String get settingsReportAppIssueEmail => 'Report issue with app (Email)';

  @override
  String get settingsShowBuildInformation => 'Show build information';

  @override
  String get listFavourites => 'Favourites';

  @override
  String get listNameCannotBeEmpty => 'List name cannot be empty';

  @override
  String get listNameInvalid => 'Invalid name, this should have been caught already';

  @override
  String get listEnterNewName => 'Enter new list name';

  @override
  String get listFailedToMake => 'Failed to make new list';

  @override
  String get listNewList => 'New List';

  @override
  String get listSearchAdd => 'Search for words to add';

  @override
  String get listSearchPrefix => 'Search';

  @override
  String get wordAlreadyFavourited => 'Already favourited!';

  @override
  String get wordFavouriteThisWord => 'Favourite this word';

  @override
  String get wordNoDefinitions => 'No definitions data available for this word / phrase';

  @override
  String get wordDataMissing => 'Data missing';

  @override
  String get entryTypeWords => 'Words';

  @override
  String get entryTypePhrases => 'Phrases';

  @override
  String get entryTypeFingerspelling => 'Fingerspelling';

  @override
  String get entrySelectEntryTypes => 'Select Entry Types';

  @override
  String get relatedWords => 'Related words';

  @override
  String get startupFailureMessage => 'Failed to start the app correctly. First, please confirm you are using the latest version of the app. If you are, please email daniel@dport.me with a screenshot showing this error.';

  @override
  String get unexpectedErrorLoadingVideo => 'Unexpected error loading';

  @override
  String get deviceDefault => 'Device Default';
}
