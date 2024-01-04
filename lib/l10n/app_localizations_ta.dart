import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

/// The translations for Tamil (`ta`).
class DictLibLocalizationsTa extends DictLibLocalizations {
  DictLibLocalizationsTa([String locale = 'ta']) : super(locale);

  @override
  String get newsTitle => 'செய்தி';

  @override
  String get searchTitle => 'தேடல்';

  @override
  String get listsTitle => 'பட்டியல்கள்';

  @override
  String get revisionTitle => 'திருத்தம்';

  @override
  String get settingsTitle => 'அமைப்புகள்';

  @override
  String get searchHintText => 'ஒரு வார்த்தையை கண்டுபிடி';

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
  String get flashcardsRevisionSources => 'திருத்த ஆதாரங்கள்';

  @override
  String get flashcardsSelectListsToRevise => 'மாற்றியமைக்க பட்டியல்களைத் தேர்ந்தெடுக்கவும்';

  @override
  String get flashcardsSelectLists => 'பட்டியலைத் தேர்ந்தெடு';

  @override
  String get flashcardsTypes => 'ஃபிளாஷ் கார்டுகளின் வகைகள்';

  @override
  String get flashcardsSignToWord => 'கையெழுத்து -> சொல்';

  @override
  String get flashcardsWordToSign => 'சொல் -> அl;டையாளம்';

  @override
  String get flashcardsRevisionSettings => 'மீள்திருத்த அமைப்புகள்';

  @override
  String get flashcardsSelectRevisionStrategy => 'மீள்திருத்த முறையைத் தேர்ந்தெடு';

  @override
  String get flashcardsStrategy => 'மூலோபாயம்';

  @override
  String get flashcardsSelectSignRegions => 'சிக்னல் மண்டலங்களைத் தேர்ந்தெடு';

  @override
  String get flashcardsRegions => 'பிராந்தியங்கள்';

  @override
  String get flashcardsStart => 'தொடங்கு';

  @override
  String get flashcardsOnlyOneCard => 'ஒரு வார்த்தைக்கு ஒரு செட் கார்டுகளை மட்டும் காட்டு';

  @override
  String get flashcardsRevisionLanguage => 'திருத்த மொழி';

  @override
  String get flashcardsAllOfSriLanka => 'முழு இலங்கையும்';

  @override
  String get flashcardsNorthEast => 'வட கிழக்கு';

  @override
  String get flashcardsNext => 'அடுத்தது';

  @override
  String get flashcardsForgot => 'மறந்துவிட்டேன்';

  @override
  String get flashcardsGotIt => 'கண்டறியப்பட்டது!';

  @override
  String get flashcardsWhatIsSignForWord => 'இந்த வார்த்தைக்கான சைகை மொழி என்ன?';

  @override
  String get flashcardsWhatDoesSignMean => 'இந்த சிக்னல் எதையாவது குறிக்கிறதா?';

  @override
  String get flashcardsOpenDictionaryEntry => 'திறந்த அகராதி சொல்லகராதி';

  @override
  String get flashcardsSuccessRate => 'வெற்றி விகிதம்';

  @override
  String get flashcardsTotalCards => 'முழு அட்டை';

  @override
  String get flashcardsSuccessfulCards => 'வெற்றி அட்டை';

  @override
  String get flashcardsIncorrectCards => 'தவறான அட்டை';

  @override
  String get flashcardsTotalReviews => 'மொத்த மதிப்புரைகள்';

  @override
  String get flashcardsUnsuccessfulCards => 'ஃபெயில் கார்டு';

  @override
  String get flashcardsUniqueWords => 'தனித்துவமான வார்த்தைகள்';

  @override
  String get flashcardsLongestStreak => 'நீண்ட செயல்முறை';

  @override
  String get flashcardsStatsCollectedSince => 'தற்போது உள்ளிடப்பட்டுள்ள புள்ளி விவரங்கள்';

  @override
  String get flashcardsRevisionSummaryTitle => 'திருத்தச் சுருக்கம்';

  @override
  String get flashcardsRevisionProgressTitle => 'திருத்த முன்னேற்றம்';

  @override
  String get flashcardsRevisionStategyToShow => 'புள்ளிவிவரங்களைக் காட்ட திருத்த உத்தியைக் காட்டு';

  @override
  String get setPlaybackSpeedTo => 'பிளேபேக் வேகத்தை அமைக்கவும்';

  @override
  String get settingsPlayStoreFeedback => 'Play Store கருத்துகளை வழங்கவும்';

  @override
  String get settingsAppStoreFeedback => 'App Store கருத்தை வழங்கவும்';

  @override
  String get na => 'N/A';

  @override
  String get settingsLanguage => 'மொழி';

  @override
  String get settingsRevision => 'திருத்தம்';

  @override
  String get settingsHideRevision => 'எடிட்டிங் அம்சங்களை மறை';

  @override
  String get settingsDeleteRevisionProgress => 'அனைத்து மீள்திருத்த முன்னேற்றத்தையும் நீக்கு';

  @override
  String get settingsDeleteRevisionProgressExplanation => 'இது உங்கள் எல்லா மதிப்புரைகளையும், முன்னேற்றத்தையும் நீக்கும். (உங்கள் பட்டியலில் பிடித்தவை பாதிக்கப்படாது.) இதை 100% உறுதியாகச் செய்ய விரும்புகிறீர்களா?';

  @override
  String get settingsProgressDeleted => 'அனைத்து மதிப்பாய்வு முன்னேற்றமும் நீக்கப்பட்டது';

  @override
  String get settingsCache => 'தற்காலிக நினைவுகள்';

  @override
  String get settingsCacheVideos => 'வீடியோ நினைவுகளை உருவாக்கு';

  @override
  String get settingsDropCache => 'தற்காலிக நினைவுகளை அழிக்கவும்';

  @override
  String get settingsCacheDropped => 'தற்காலிக நினைவுகள் அழிக்கப்பட்டன';

  @override
  String get settingsData => 'தகவல்கள்';

  @override
  String get settingsCheckNewData => 'புதிய அகராதித் தரவைச் சரிபார்க்கவும்';

  @override
  String get settingsDataUpdated => 'அகராதி தரவு வெற்றிகரமாக புதுப்பிக்கப்பட்டது';

  @override
  String get settingsDataUpToDate => 'தரவு ஏற்கனவே புதுப்பிக்கப்பட்டது';

  @override
  String get settingsLegal => 'சட்டம்';

  @override
  String get settingsSeeLegal => 'சட்டத் தகவலைக் காண்க';

  @override
  String get settingsBackgroundLogs => 'பின்னணி பதிவுகள்';

  @override
  String get settingsHelp => 'உதவி';

  @override
  String get settingsReportDictionaryDataIssue => 'அகராதி தரவில் சிக்கலைப் புகாரளிக்கவும்';

  @override
  String get settingsReportAppIssueGithub => 'பயன்பாட்டுச் சிக்கலைப் புகாரளிக்கவும் (Github)';

  @override
  String get settingsReportAppIssueEmail => 'பயன்பாட்டுச் சிக்கலைப் புகாரளிக்கவும் (மின்னஞ்சல்)';

  @override
  String get settingsShowBuildInformation => 'உருவாக்க தகவலைக் காட்டு';

  @override
  String get listFavourites => 'பிடித்த';

  @override
  String get listNameCannotBeEmpty => 'பட்டியல் பெயர் காலியாக இருக்க முடியாது';

  @override
  String get listNameInvalid => 'தவறான பெயர், இது ஏற்கனவே எடுக்கப்பட்டிருக்க வேண்டும்';

  @override
  String get listEnterNewName => 'புதிய பெயர் பட்டியலைச் செருகு';

  @override
  String get listFailedToMake => 'புதிய பட்டியலை உருவாக்க முடியவில்லை';

  @override
  String get listNewList => 'புதிய பட்டியல்கள்';

  @override
  String get listSearchAdd => 'சேர்க்க வார்த்தைகளைக் கண்டுபிடி';

  @override
  String get listSearchPrefix => 'தேடல்';

  @override
  String get wordAlreadyFavourited => 'ஏற்கனவே பிடித்தது!';

  @override
  String get wordFavouriteThisWord => 'இந்த வார்த்தை பிடித்தது';

  @override
  String get wordNoDefinitions => 'இந்த வார்த்தை/சொற்றொடருக்கு வரையறை தரவு எதுவும் இல்லை';

  @override
  String get wordDataMissing => 'காணாமல் தரவு';

  @override
  String get entryTypeWords => 'சொற்கள்';

  @override
  String get entryTypePhrases => 'வாக்கியங்கள்';

  @override
  String get entryTypeFingerspelling => 'விரல் பேச்சு';

  @override
  String get entrySelectEntryTypes => 'நுழைவு வகைகளைத் தேர்ந்தெடு';

  @override
  String get relatedWords => 'சம்பந்தமான வார்த்தைகள்';

  @override
  String get startupFailureMessage => 'பயன்பாடு சரியாகத் தொடங்குவதில் தோல்வி. தயவுசெய்து, முதலில், நீங்கள் பயன்பாட்டின் சமீபத்திய பதிப்பைப் பயன்படுத்துகிறீர்கள் என்பதை உறுதிப்படுத்திக் கொள்ளுங்கள். நீங்கள் இருந்தால், இந்தப் பிழையின் நகலுடன் daniel@dport.me ஐ மின்னஞ்சல் செய்யவும்.';

  @override
  String get unexpectedErrorLoadingVideo => 'எதிர்பாராத பிழை ஏற்றுதல்';

  @override
  String get deviceDefault => 'சாதனங்களை வழங்கு';
}
