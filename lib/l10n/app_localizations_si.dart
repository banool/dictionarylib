import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Sinhala Sinhalese (`si`).
class DictLibLocalizationsSi extends DictLibLocalizations {
  DictLibLocalizationsSi([String locale = 'si']) : super(locale);

  @override
  String get newsTitle => 'පුවත්';

  @override
  String get searchTitle => 'සොයන්න';

  @override
  String get listsTitle => 'ලැයිස්තු';

  @override
  String get revisionTitle => 'සංශෝධනය';

  @override
  String get settingsTitle => 'සැකසුම්';

  @override
  String get searchHintText => 'වචනයක් සොයන්න';

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
  String get flashcardsRevisionSources => 'සංශෝධන මූලාශ්‍ර';

  @override
  String get flashcardsSelectListsToRevise => 'සංශෝධනය කිරීමට ලැයිස්තු තෝරන්න';

  @override
  String get flashcardsSelectLists => 'ලැයිස්තු තෝරන්න';

  @override
  String get flashcardsTypes => 'ෆ්ලෑෂ්කාඩ් වර්ග';

  @override
  String get flashcardsSignToWord => 'සංඥා -> වචනය';

  @override
  String get flashcardsWordToSign => 'වචනය -> සංඥා';

  @override
  String get flashcardsRevisionSettings => 'සංශෝධන සැකසුම්';

  @override
  String get flashcardsSelectRevisionStrategy => 'සංශෝධන ක්‍රමය තෝරන්න';

  @override
  String get flashcardsStrategy => 'උපාය මාර්ගය';

  @override
  String get flashcardsSelectSignRegions => 'සංඥා කලාප තෝරන්න';

  @override
  String get flashcardsRegions => 'කළාප';

  @override
  String get flashcardsStart => 'ආරම්භ කරන්න';

  @override
  String get flashcardsOnlyOneCard => 'වචනයකට කාඩ් කට්ටලයක් පමණින් පෙන්වන්න';

  @override
  String get flashcardsRevisionLanguage => 'සංශෝධන භාෂාව';

  @override
  String get flashcardsAllOfSriLanka => 'මුළු ලංකාවම';

  @override
  String get flashcardsNorthEast => 'උතුරු නැගෙනහිර';

  @override
  String get flashcardsNext => 'මීළඟ';

  @override
  String get flashcardsForgot => 'අමතක වුනා';

  @override
  String get flashcardsGotIt => 'සොයා ගත්තා!';

  @override
  String get flashcardsWhatIsSignForWord => 'මෙම වචනය සඳහා සංඥා භාෂාව කුමක්ද?';

  @override
  String get flashcardsWhatDoesSignMean => 'මෙම සංඥාවේ අර්ථයකුමද?';

  @override
  String get flashcardsOpenDictionaryEntry => 'ශබ්දකෝෂය වචන මාලාව විවෘත කරන්න';

  @override
  String get flashcardsSuccessRate => 'සාර්ථකත්ව අනුපාතය';

  @override
  String get flashcardsTotalCards => 'සම්පූර්ණ කාඩ්';

  @override
  String get flashcardsSuccessfulCards => 'සාර්ථක කාඩ්';

  @override
  String get flashcardsIncorrectCards => 'වැරදි කාඩ්';

  @override
  String get flashcardsTotalReviews => 'මුළු සමාලෝචන';

  @override
  String get flashcardsUnsuccessfulCards => 'අසාර්ථක කාඩ්';

  @override
  String get flashcardsUniqueWords => 'අනන්‍ය වචන';

  @override
  String get flashcardsLongestStreak => 'දිගම ක්‍රියාවලිය';

  @override
  String get flashcardsStatsCollectedSince => 'සංඛ්‍යාන දැනට ඇතුලත් කර ඇත';

  @override
  String get flashcardsRevisionSummaryTitle => 'සංශෝධන සාරාංශය';

  @override
  String get flashcardsRevisionProgressTitle => 'සංශෝධන ප්‍රගතිය';

  @override
  String get flashcardsRevisionStategyToShow => 'සංඛ්‍යාලේඛන පෙන්වීමට සඳහා සංශෝධන උපාය මාර්ගය පෙන්වන්න';

  @override
  String get setPlaybackSpeedTo => 'ප්‍රතිවාදන වේගය සකසන්න';

  @override
  String get settingsPlayStoreFeedback => 'Play Store ප්‍රතිචාරය දෙන්න';

  @override
  String get settingsAppStoreFeedback => 'App Store ප්‍රතිචාරය දෙන්න';

  @override
  String get na => 'නොදනී';

  @override
  String get settingsLanguage => 'භාෂාව';

  @override
  String get settingsRevision => 'සංශෝධන';

  @override
  String get settingsHideRevision => 'සංශෝධන විශේෂාංග සඟවන්න';

  @override
  String get settingsHideCommunityLists => 'සමාජ ලැයිස්තු සඟවන්න';

  @override
  String get settingsDeleteRevisionProgress => 'සියලුම සංශෝධන ප්‍රගතිය මකන්න';

  @override
  String get settingsDeleteRevisionProgressExplanation => 'මෙය මගින් ඔබගේ සියලුම සමාලෝචන, ප්‍රගතිය මාකාදමයි. (ඔබගේ ලැයිස්තු ප්‍රියතමයන් බලපාන්නේ නැත.) ඔබට මෙය කිරීමට අවශ්‍ය බව 100% විශ්වාසද?';

  @override
  String get settingsProgressDeleted => 'සියලුම සමාලෝචන ප්‍රගතිය මකාදමා ඇත';

  @override
  String get settingsAppearance => 'පෙනුම';

  @override
  String get settingsColourMode => 'වර්ණ මාදිලිය';

  @override
  String get settingsColourModeLight => 'ආලෝක';

  @override
  String get settingsColourModeDark => 'අඳුරු';

  @override
  String get settingsColourModeSystem => 'පද්ධතිය';

  @override
  String get settingsCache => 'තාවකාලික මතකයන්';

  @override
  String get settingsCacheVideos => 'වීඩියෝ තාවකාලික මතකයන් කරන්න';

  @override
  String get settingsDropCache => 'තාවකාලික මතකයන් ඉවත් කරන්න';

  @override
  String get settingsCacheDropped => 'තාවකාලික මතකයන් ඉවත් කළ ඇත';

  @override
  String get settingsData => 'දත්ත';

  @override
  String get settingsCheckNewData => 'නව ශබ්දකෝෂ දත්ත සඳහා පරීක්ෂා කරන්න';

  @override
  String get settingsDataUpdated => 'ශබ්දකෝෂ දත්ත සාර්ථකව යාවත්කාලීන කළ ඇත';

  @override
  String get settingsDataUpToDate => 'දත්ත දැනටමත් යාවත්කාලීන වී ඇත';

  @override
  String get settingsLegal => 'නීතිය';

  @override
  String get settingsSeeLegal => 'නීතික තොරතුරු බලන්න';

  @override
  String get settingsBackgroundLogs => 'පසුබිම් ලොග';

  @override
  String get settingsHelp => 'උපකාරය';

  @override
  String get settingsReportDictionaryDataIssue => 'ශබ්දකෝෂ දත්ත ගැටළුව වාර්තා කරන්න';

  @override
  String get settingsReportAppIssueGithub => 'යෙදුමේ ගැටළුව (Github) වාර්තා කරන්න';

  @override
  String get settingsReportAppIssueEmail => 'යෙදුමේ ගැටළුව (Email) වාර්තා කරන්න';

  @override
  String get settingsShowBuildInformation => 'ගොඩනැගීමේ තොරතුරු පෙන්වන්න';

  @override
  String get settingsNetwork => 'ජාලය';

  @override
  String get settingsUseSystemHttpProxy => 'පද්ධති HTTP ප්‍රොක්සි භාවිතා කරන්න';

  @override
  String get settingsRestartApp => 'මෙම වෙනස ක්‍රියාත්මක වීමට යෙදුම නැවත ආරම්භ කළ යුතුය';

  @override
  String get listFavourites => 'ප්‍රියතම';

  @override
  String get listNameCannotBeEmpty => 'ලැයිස්තු නම හිස් විය නොහැක';

  @override
  String get listNameInvalid => 'වලංගු නොවන නම, මෙය දැනටමත් අල්ලාගෙන තිබිය යුතුය';

  @override
  String get listEnterNewName => 'නව නම ලැයිස්තු ඇතුළත් කරන්න';

  @override
  String get listFailedToMake => 'නව ලැයිස්තුව සාදා ගැනීමට අසාර්ථක විය';

  @override
  String get listNewList => 'නව ලැයිස්තු';

  @override
  String get listMyLists => 'මගේ ලැයිස්තු';

  @override
  String get listCommunity => 'ප්රජාව';

  @override
  String get listConfirmListDelete => 'ඔබට මෙම ලැයිස්තුව මැකීමට අවශ්‍ය බව විශ්වාසද?';

  @override
  String get listSearchAdd => 'එක් කිරීම සඳහා වචන සොයන්න';

  @override
  String get listSearchPrefix => 'සොයන්න';

  @override
  String get wordAlreadyFavourited => 'දැනටමත් ප්‍රියතම!';

  @override
  String get wordFavouriteThisWord => 'මෙම වචනය ප්‍රියතම කරන්න';

  @override
  String get wordNoDefinitions => 'මෙම වචනය / වාක්‍ය ඛණ්ඩය සඳහා නිර්වචන දත්ත නොමැත';

  @override
  String get wordDataMissing => 'දත්ත අතුරුදහන්';

  @override
  String get entryTypeWords => 'වචන';

  @override
  String get entryTypePhrases => 'වාක්ය ඛණ්ඩ';

  @override
  String get entryTypeFingerspelling => 'ඇඟිලි කථාව';

  @override
  String get entrySelectEntryTypes => 'ඇතුල්වීමේ වර්ග තෝරන්න';

  @override
  String get relatedWords => 'අදාළ වචන';

  @override
  String get alertCareful => 'පරිස්සමෙන්!';

  @override
  String get alertCancel => 'අවලංගු කරන්න';

  @override
  String get alertConfirm => 'තහවුරු කරන්න';

  @override
  String get startupFailureMessage => 'යෙදුම නිවැරදිව ආරම්භ කිරීමට අසමත් විය. කරුණාකර, පළමුව, ඔබ යෙදුමේ නවතම අනුවාදය භාවිතා කරන බව සහතික කරන්න. ඔබ එසේ නම්, කරුණාකර මෙම දෝෂය පෙන්වන පුනරුපුවරුවක් සමග daniel@dport.me වෙත ඊමේල් කරන්න.';

  @override
  String get unexpectedErrorLoadingVideo => 'අනපේක්ෂිත දෝෂය පූරණය කරමින්';

  @override
  String get deviceDefault => 'ප්‍රදාන උපාංග';
}
