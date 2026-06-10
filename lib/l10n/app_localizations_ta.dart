// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

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
  String get flashcardsSelectListsToRevise =>
      'மாற்றியமைக்க பட்டியல்களைத் தேர்ந்தெடுக்கவும்';

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
  String get flashcardsSelectRevisionStrategy =>
      'மீள்திருத்த முறையைத் தேர்ந்தெடு';

  @override
  String get flashcardsStrategy => 'மூலோபாயம்';

  @override
  String get flashcardsSelectSignRegions => 'சிக்னல் மண்டலங்களைத் தேர்ந்தெடு';

  @override
  String get flashcardsRegions => 'பிராந்தியங்கள்';

  @override
  String get flashcardsStart => 'தொடங்கு';

  @override
  String get flashcardsOnlyOneCard =>
      'ஒரு வார்த்தைக்கு ஒரு செட் கார்டுகளை மட்டும் காட்டு';

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
  String get flashcardsCardUnavailable =>
      'A card was unavailable and was skipped.';

  @override
  String get flashcardsWhatIsSignForWord =>
      'இந்த வார்த்தைக்கான சைகை மொழி என்ன?';

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
  String get flashcardsStatsCollectedSince =>
      'தற்போது உள்ளிடப்பட்டுள்ள புள்ளி விவரங்கள்';

  @override
  String get flashcardsRevisionSummaryTitle => 'திருத்தச் சுருக்கம்';

  @override
  String get flashcardsRevisionProgressTitle => 'திருத்த முன்னேற்றம்';

  @override
  String get flashcardsRevisionStategyToShow =>
      'புள்ளிவிவரங்களைக் காட்ட திருத்த உத்தியைக் காட்டு';

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
  String get settingsHideCommunityLists => 'சமூகப்பட்டியல்களை மறைக்கவும்';

  @override
  String get settingsDeleteRevisionProgress =>
      'அனைத்து மீள்திருத்த முன்னேற்றத்தையும் நீக்கு';

  @override
  String get settingsDeleteRevisionProgressExplanation =>
      'இது உங்கள் எல்லா மதிப்புரைகளையும், முன்னேற்றத்தையும் நீக்கும். (உங்கள் பட்டியலில் பிடித்தவை பாதிக்கப்படாது.) இதை 100% உறுதியாகச் செய்ய விரும்புகிறீர்களா?';

  @override
  String get settingsProgressDeleted =>
      'அனைத்து மதிப்பாய்வு முன்னேற்றமும் நீக்கப்பட்டது';

  @override
  String get settingsAppearance => 'தோற்றம்';

  @override
  String get settingsAppTheme => 'செயலி தீம்';

  @override
  String get settingsColourMode => 'நிற முறை';

  @override
  String get settingsColourModeLight => 'ஒளி';

  @override
  String get settingsColourModeDark => 'இருள்';

  @override
  String get settingsColourModeSystem => 'கணினி அமைப்பு';

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
  String get settingsDataUpdated =>
      'அகராதி தரவு வெற்றிகரமாக புதுப்பிக்கப்பட்டது';

  @override
  String get settingsDataUpToDate => 'தரவு ஏற்கனவே புதுப்பிக்கப்பட்டது';

  @override
  String get settingsLegal => 'சட்டம்';

  @override
  String get settingsSeeLegal => 'சட்டத் தகவலைக் காண்க';

  @override
  String get settingsSeePrivacyPolicy => 'தனியுரிமைக் கொள்கையைப் பார்க்கவும்';

  @override
  String get settingsSeeTermsOfService => 'See terms of service';

  @override
  String get settingsBackgroundLogs => 'பின்னணி பதிவுகள்';

  @override
  String get settingsHelp => 'உதவி';

  @override
  String get settingsReportDictionaryDataIssue =>
      'அகராதி தரவில் சிக்கலைப் புகாரளிக்கவும்';

  @override
  String get settingsReportAppIssueGithub =>
      'பயன்பாட்டுச் சிக்கலைப் புகாரளிக்கவும் (Github)';

  @override
  String get settingsReportAppIssueEmail =>
      'பயன்பாட்டுச் சிக்கலைப் புகாரளிக்கவும் (மின்னஞ்சல்)';

  @override
  String get settingsShowBuildInformation => 'உருவாக்க தகவலைக் காட்டு';

  @override
  String get settingsNetwork => 'நெட்வொர்க்';

  @override
  String get settingsUseSystemHttpProxy =>
      'கணினியின் HTTP ப்ராக்ஸி பயன்படுத்தவும்';

  @override
  String get settingsRestartApp =>
      'இந்த மாற்றம் செயல்பட பயன்பாட்டை மீண்டும் துவக்க வேண்டும்';

  @override
  String get listFavourites => 'பிடித்த';

  @override
  String get listNameCannotBeEmpty => 'பட்டியல் பெயர் காலியாக இருக்க முடியாது';

  @override
  String get listNameInvalid =>
      'தவறான பெயர், இது ஏற்கனவே எடுக்கப்பட்டிருக்க வேண்டும்';

  @override
  String get listEnterNewName => 'புதிய பெயர் பட்டியலைச் செருகு';

  @override
  String get listFailedToMake => 'புதிய பட்டியலை உருவாக்க முடியவில்லை';

  @override
  String get listFailedToRename => 'Failed to rename list';

  @override
  String get listNewList => 'புதிய பட்டியல்கள்';

  @override
  String get listRenameList => 'Rename List';

  @override
  String get listRenameOnlyCreator => 'Only the creator can rename this list.';

  @override
  String get listMyLists => 'எனது பட்டியல்கள்';

  @override
  String get listCommunity => 'சமூக';

  @override
  String get listSortAdded => 'Added';

  @override
  String get listSortAlpha => 'A-Z';

  @override
  String get listConfirmListDelete =>
      'இந்தப் பட்டியலை நிச்சயமாக நீக்க விரும்புகிறீர்களா?';

  @override
  String get listSearchAdd => 'சேர்க்க வார்த்தைகளைக் கண்டுபிடி';

  @override
  String get listSearchPrefix => 'தேடல்';

  @override
  String listSavedVideoCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count videos saved',
      one: '1 video saved',
    );
    return '$_temp0';
  }

  @override
  String get listRemoveAllVideosTitle => 'Remove from list?';

  @override
  String listRemoveAllVideosBody(int count, String word) {
    return 'Remove all $count saved videos of \"$word\" from this list?';
  }

  @override
  String get savedVideoSheetTitle => 'Save this video to…';

  @override
  String get wordAlreadyFavourited => 'ஏற்கனவே பிடித்தது!';

  @override
  String get wordFavouriteThisWord => 'இந்த வார்த்தை பிடித்தது';

  @override
  String get wordNoDefinitions =>
      'இந்த வார்த்தை/சொற்றொடருக்கு வரையறை தரவு எதுவும் இல்லை';

  @override
  String get wordDataMissing => 'காணாமல் தரவு';

  @override
  String get entryTypeWords => 'சொற்கள்';

  @override
  String get entryTypePhrases => 'வாக்கியங்கள்';

  @override
  String get entryTypeFingerspelling => 'விரல் எழுத்து';

  @override
  String get entrySelectEntryTypes => 'நுழைவு வகைகளைத் தேர்ந்தெடு';

  @override
  String get relatedWords => 'சம்பந்தமான வார்த்தைகள்';

  @override
  String get alertCareful => 'கவனமாக!';

  @override
  String get alertCancel => 'ரத்து செய்';

  @override
  String get alertConfirm => 'உறுதிப்படுத்தவும்';

  @override
  String get alertOk => 'OK';

  @override
  String get startupFailureMessage =>
      'பயன்பாடு சரியாகத் தொடங்குவதில் தோல்வி. தயவுசெய்து, முதலில், நீங்கள் பயன்பாட்டின் சமீபத்திய பதிப்பைப் பயன்படுத்துகிறீர்கள் என்பதை உறுதிப்படுத்திக் கொள்ளுங்கள். நீங்கள் இருந்தால், இந்தப் பிழையின் நகலுடன் daniel@dport.me ஐ மின்னஞ்சல் செய்யவும்.';

  @override
  String get unexpectedErrorLoadingVideo => 'எதிர்பாராத பிழை ஏற்றுதல்';

  @override
  String get deviceDefault => 'சாதனங்களை வழங்கு';

  @override
  String get shareDialogTitle => 'Share this list';

  @override
  String get shareDialogBody =>
      'Pick a display name for your list. Anyone with the share link can subscribe and follow your edits.';

  @override
  String get shareDialogDisplayNameLabel => 'Display name';

  @override
  String get shareDialogDisplayNameHelper => 'Emojis welcome 🎉';

  @override
  String get shareDialogShareButton => 'Share';

  @override
  String get shareValidationRequired => 'Required';

  @override
  String shareValidationMaxLen(int count) {
    return 'At most $count characters';
  }

  @override
  String shareValidationReservedName(String name) {
    return '\"$name\" is reserved — pick a different name';
  }

  @override
  String get shareNetworkError =>
      'Couldn\'t reach the server. Check your connection and try again.';

  @override
  String get shareErrorUnauthorized =>
      'Your session has expired. Please sign in again.';

  @override
  String get shareErrorForbidden => 'You don\'t have permission to do that.';

  @override
  String get shareErrorGone => 'This list has been deleted by its owner.';

  @override
  String get shareErrorPayloadTooLarge =>
      'That change is too big. Try again with a smaller batch.';

  @override
  String get shareErrorRateLimited =>
      'Slow down — too many requests. Try again in a moment.';

  @override
  String get shareErrorServer =>
      'The server is having trouble. Try again later.';

  @override
  String get unshareToDeleteTooltip =>
      'Stop sharing this list before deleting it.';

  @override
  String get shareTooManyEntriesTitle => 'List is too big to share';

  @override
  String shareTooManyEntriesBody(int count, int max) {
    return 'This list has $count entries, but shared lists are capped at $max. Remove some entries and try again.';
  }

  @override
  String get shareLinkDialogTitle => 'List shared';

  @override
  String shareLinkDialogBody(String displayName) {
    return 'Anyone with this link can subscribe to \"$displayName\":';
  }

  @override
  String get shareLinkCopiedSnack => 'Link copied to clipboard';

  @override
  String get shareLinkCopyButton => 'Copy';

  @override
  String get shareLinkShareButton => 'Share';

  @override
  String get shareLinkQrButton => 'QR code';

  @override
  String get shareLinkDoneButton => 'Done';

  @override
  String get qrCodeDialogBody => 'Other people can scan this to subscribe.';

  @override
  String get qrCodeDialogClose => 'Close';

  @override
  String get signInDialogTitle => 'Sign in to share';

  @override
  String get signInDialogBody =>
      'To share a list, sign in below. We only use this to prove that you\'re the one editing it later — we don\'t collect any personal information.';

  @override
  String signInLastUsedHint(String provider) {
    return 'Last time, you signed in with $provider.';
  }

  @override
  String get signInWithApple => 'Continue with Apple';

  @override
  String get signInWithGoogle => 'Continue with Google';

  @override
  String get signInWithFacebook => 'Continue with Facebook';

  @override
  String get signInFailed => 'Sign-in failed. Please try again.';

  @override
  String get signInCancelled => 'Sign-in cancelled.';

  @override
  String get signInProviderNotConfigured =>
      'This sign-in option isn\'t available on this device.';

  @override
  String get signInProviderNoCredential =>
      'Sign-in didn\'t return a valid response. Please try again.';

  @override
  String get providerApple => 'Apple';

  @override
  String get providerGoogle => 'Google';

  @override
  String get providerFacebook => 'Facebook';

  @override
  String get providerTest => 'Test session';

  @override
  String get subscribeDialogTitle => 'Subscribe to a shared list';

  @override
  String get subscribeDialogBody =>
      'Paste either a share link or just the list ID at the end of one.';

  @override
  String get subscribeDialogUrlLabel => 'Share URL';

  @override
  String get subscribeDialogSubscribeButton => 'Subscribe';

  @override
  String get alreadySubscribedSnack =>
      'You\'re already subscribed to this list.';

  @override
  String get alreadyOwnerSnack => 'You own this list.';

  @override
  String get alreadyEditorSnack => 'You\'re an editor of this list.';

  @override
  String get subscribeInvalidInput => 'Not a valid share link or list ID.';

  @override
  String get subscribeInputIsInviteUrl =>
      'That\'s an invite link — tap it from your phone to join as editor instead of subscribing.';

  @override
  String get subscribeNotFound => 'No list with that key exists.';

  @override
  String get sharedListLandingLoading => 'Loading shared list';

  @override
  String get sharedListLandingDefaultError => 'Couldn\'t load this list.';

  @override
  String get sharedListLandingNotFound =>
      'This shared list doesn\'t exist or has been deleted by its owner.';

  @override
  String get sharedListLandingTryAgain => 'Try again';

  @override
  String get unshareConfirmBody =>
      'Stop sharing this list? Subscribers will no longer be able to see it.';

  @override
  String get unshareConfirmTitle => 'Stop sharing?';

  @override
  String unshareFailed(String message) {
    return 'Failed to stop sharing: $message';
  }

  @override
  String get unsubscribeConfirmBody => 'Unsubscribe from this list?';

  @override
  String get unsubscribeConfirmTitle => 'Unsubscribe?';

  @override
  String copyToMyListsSnack(String name) {
    return 'Copied to \"$name\"';
  }

  @override
  String get subscribedSyncNowMenuItem => 'Sync now';

  @override
  String get subscribedCopyLinkMenuItem => 'Copy link';

  @override
  String get subscribedSyncInProgress => 'Syncing…';

  @override
  String get subscribedSyncDoneSnack => 'Up to date';

  @override
  String subscribedSyncFailedSnack(String message) {
    return 'Sync failed: $message';
  }

  @override
  String get subscribedCopyMenuItem => 'Duplicate';

  @override
  String get settingsSharing => 'Sharing';

  @override
  String get settingsSignIn => 'Sign in to share lists';

  @override
  String settingsSignedInAs(String provider) {
    return 'Signed in with $provider';
  }

  @override
  String get settingsSignOut => 'Sign out';

  @override
  String get settingsSignOutConfirmTitle => 'Sign out?';

  @override
  String get settingsSignOutConfirmBody =>
      'On this device:\n  • You\'re signed out of sharing.\n  • Lists you shared stop being managed from here — the local lists themselves keep their entries.\n\nYour shared lists stay on the server. Sign back in on any device to edit them again.';

  @override
  String get settingsDeleteAccount => 'Delete account';

  @override
  String get settingsDeleteAccountConfirmTitle => 'Delete account?';

  @override
  String get settingsDeleteAccountConfirmButton => 'Delete account';

  @override
  String get settingsDeleteAccountConfirmBody =>
      'This permanently deletes your account and everything we store for you:\n  • Every list you\'ve shared is deleted from the server — anyone subscribed keeps the copy already on their device, but it stops updating and is marked as removed.\n  • You\'re removed as an editor from other people\'s lists.\n  • We delete any personal information on file (your name).\n\nThe lists on this device keep their entries; only the sharing is removed. This can\'t be undone.';

  @override
  String get settingsDeleteAccountRunning => 'Deleting account…';

  @override
  String settingsDeleteAccountFailed(String message) {
    return 'Couldn\'t delete your account: $message';
  }

  @override
  String get alertSave => 'Save';

  @override
  String get alertDone => 'Done';

  @override
  String get listNameAllowedChars =>
      'No special characters besides these are allowed: , . - _ !';

  @override
  String forceUpgradeMessage(String version) {
    return 'You are using an unsupported version ($version) of the app, please update.';
  }

  @override
  String get forceUpgradeButton => 'Update';

  @override
  String get privacyPolicyPageTitle => 'Privacy Policy';

  @override
  String get importOwnedListsPromptTitle =>
      'Import lists you\'ve shared before?';

  @override
  String get importOwnedListsPromptBody =>
      'We\'ll ask the server which lists you\'re signed in to manage and import them as new local lists. Your existing local lists are untouched. Any name collisions get a numeric suffix (e.g. \"Cats\" → \"Cats 2\"). After import, your device is the source of truth — further edits stay local and push to the server in the background.';

  @override
  String get importOwnedListsActionImport => 'Import';

  @override
  String get importOwnedListsActionSkip => 'Skip';

  @override
  String get importOwnedListsRunning => 'Importing your shared lists…';

  @override
  String importOwnedListsFailed(String message) {
    return 'Couldn\'t import lists: $message';
  }

  @override
  String get importOwnedListsResultNone => 'No shared lists found.';

  @override
  String importOwnedListsResultDone(int imported, int total) {
    return 'Imported $imported of $total list(s).';
  }

  @override
  String get duplicateConfirmTitle => 'Duplicate list?';

  @override
  String get duplicateConfirmBody =>
      'This makes a personal, private copy of the list. It won\'t update when the original owner edits theirs.';

  @override
  String get duplicateConfirmAction => 'Duplicate';

  @override
  String get duplicateFallbackName => 'Duplicated list';

  @override
  String get listSharedWithMeTab => 'Subscribed';

  @override
  String get listSharedWithMeEmpty =>
      'Nothing here yet.\n\nTap the cloud-download icon up top to subscribe to a shared list, or open a share/invite link from someone else.';

  @override
  String get ownedStatusOrphaned => 'Shared — deleted by you';

  @override
  String get ownedStatusSharedBy => 'Shared by you';

  @override
  String get ownedStatusPendingSyncSuffix => 'pending sync';

  @override
  String get ownedStatusSyncedSuffix => 'synced';

  @override
  String get subscribedStatusOrphaned => 'Removed by owner';

  @override
  String get subscribedStatusFallback => 'Subscribed';

  @override
  String get syncedJustNow => 'synced just now';

  @override
  String syncedMinutesAgo(int count) {
    return 'synced ${count}m ago';
  }

  @override
  String syncedHoursAgo(int count) {
    return 'synced ${count}h ago';
  }

  @override
  String syncedDaysAgo(int count) {
    return 'synced ${count}d ago';
  }

  @override
  String get agoJustNow => 'just now';

  @override
  String agoMinutes(int count) {
    return '${count}m ago';
  }

  @override
  String agoHours(int count) {
    return '${count}h ago';
  }

  @override
  String agoDays(int count) {
    return '${count}d ago';
  }

  @override
  String subscribedStatusSyncedAndUpdated(String sync, String updated) {
    return 'synced $sync · updated $updated';
  }

  @override
  String get shareLinkInviteEditorButton => 'Invite an editor';

  @override
  String get inviteEditorDialogTitle => 'Invite an editor';

  @override
  String get inviteEditorDialogBody =>
      'Send this link to the person you want to add as an editor. They\'ll need to sign in to accept; once they do, they can add and remove entries on your list.';

  @override
  String get inviteEditorExpiresIn =>
      'Expires in 7 days. Each link can only be used once, you must create a new link per editor you want to invite.';

  @override
  String inviteEditorFailed(String message) {
    return 'Couldn\'t create an invite: $message';
  }

  @override
  String get acceptInviteLandingTitle => 'Accept invite';

  @override
  String acceptInviteLandingSignedOut(String displayName) {
    return 'Sign in to accept this invite. After you sign in, you\'ll be able to edit \"$displayName\" alongside the creator.';
  }

  @override
  String get acceptInviteLandingUnknownList =>
      'This invite is for a list we couldn\'t preview yet. Sign in to continue.';

  @override
  String get acceptInviteLandingSignInButton => 'Sign in to accept';

  @override
  String get acceptInviteLandingAccepting => 'Joining…';

  @override
  String acceptInviteLandingFailed(String message) {
    return 'Couldn\'t accept the invite: $message';
  }

  @override
  String get acceptInviteLandingExpired =>
      'This invite has expired or has already been used. Ask the list\'s creator for a new one.';

  @override
  String acceptInviteLandingSignedIn(String displayName) {
    return 'Join \"$displayName\" as an editor.';
  }

  @override
  String get acceptInviteLandingAcceptButton => 'Accept invite';

  @override
  String get acceptInviteLandingOpenList => 'Open list';

  @override
  String acceptInviteLandingAlreadyOwner(String displayName) {
    return 'You\'re the creator of \"$displayName\" — no need to accept your own invite.';
  }

  @override
  String acceptInviteLandingAlreadyEditor(String displayName) {
    return 'You already edit \"$displayName\".';
  }

  @override
  String get membersPageTitle => 'Members';

  @override
  String get membersPageYou => 'You';

  @override
  String get membersPageCreator => 'Creator';

  @override
  String get membersPageEditors => 'Editors';

  @override
  String get membersPageNoEditors =>
      'No other editors yet. Tap \"Invite an editor\" to add one.';

  @override
  String get membersPageRemoveEditor => 'Remove';

  @override
  String membersPageRemoveEditorConfirmTitle(String name) {
    return 'Remove $name?';
  }

  @override
  String get membersPageRemoveEditorConfirmBody =>
      'They will no longer be able to edit this list. Any of their pending offline edits will be discarded.';

  @override
  String get membersPageLeaveButton => 'Leave this list';

  @override
  String get membersPageLeaveConfirmTitle => 'Leave this list?';

  @override
  String get membersPageLeaveConfirmBody =>
      'You won\'t be able to make changes anymore. The list itself stays available to read from your share link.';

  @override
  String membersPageEditorAddedBy(String name) {
    return 'Added by $name';
  }

  @override
  String membersPageNameYou(String name) {
    return '$name (you)';
  }

  @override
  String leaveListFailed(String message) {
    return 'Couldn\'t leave list: $message';
  }

  @override
  String membersPageSubtitleFor(String name) {
    return 'Members of \"$name\"';
  }

  @override
  String get signInDialogContextInvite =>
      'Sign in to accept the invite. You\'ll be able to edit the list once you do.';

  @override
  String get signInDialogContextResume =>
      'Sign in again to push your queued edits.';

  @override
  String settingsSignOutConfirmBodyWithPending(int count) {
    return 'You have unsynced edits on $count list(s). Signing out won\'t push them to the server. Are you sure?';
  }

  @override
  String get overviewResumeSignInIdle =>
      'Sign in to sync your shared lists across devices.';

  @override
  String get overviewResumeSignInWithPending =>
      'You have unsynced edits. Sign in again to push them.';

  @override
  String get overviewResumeSignInButton => 'Sign in';

  @override
  String get expiredSessionBanner =>
      'Your session expired. Sign in again to push your edits.';

  @override
  String get expiredSessionBannerAction => 'Sign in';

  @override
  String get engineSessionExpiredSnack => 'Signed out — please sign in again';

  @override
  String get engineSessionExpiredSnackAction => 'Sign in';

  @override
  String get engineRemovedAsEditorSnack =>
      'You\'re no longer an editor of this list';

  @override
  String get engineSnapshotCatchUpSnack =>
      'This list changed a lot while you were offline — review your recent edits.';

  @override
  String get importedListFallbackName => 'Imported list';

  @override
  String get favouritesListName => 'Favourites';

  @override
  String get listNameErrorEmpty => 'List name cannot be empty';

  @override
  String get listNameErrorInvalid => 'Invalid list name';

  @override
  String listNameErrorReserved(String name) {
    return 'List name \"$name\" is reserved';
  }

  @override
  String get listNameErrorAlreadyExists =>
      'A list with that name already exists';

  @override
  String get legalInformationPageTitle => 'Legal Information';

  @override
  String get buildInformationPageTitle => 'Build Information';

  @override
  String get backgroundLogsPageTitle => 'Background Logs';

  @override
  String get backgroundLogsCopyButton => 'Copy logs to clipboard';

  @override
  String get backgroundLogsCopiedSnack => 'Logs copied to clipboard';

  @override
  String reportIssueEmailSubject(String appName) {
    return 'Issue with $appName';
  }

  @override
  String forkPartialDrop(int copied, int total, int dropped) {
    return 'Copied $copied of $total entries — $dropped signs are no longer in the dictionary.';
  }

  @override
  String get signInTestUserButton => 'Sign in as test user (debug)';

  @override
  String get signInTestPromptTitle => 'Test sign-in';

  @override
  String get signInTestPromptBody =>
      'Mints a session on the worker\'s test provider. Debug builds only. Use this to drive the shared-lists feature without a real provider account.';

  @override
  String get signInTestUserIdLabel => 'User id (test:<slug>)';

  @override
  String get signInTestDisplayNameLabel => 'Display name';

  @override
  String get signInTestPromptConfirm => 'Sign in';

  @override
  String get searchRecent => 'சமீபத்தியவை';

  @override
  String get searchRecentClear => 'அழி';

  @override
  String get searchSignOfTheDay => 'இன்றைய சைகை';

  @override
  String get signOfTheDayBlurb => 'ஒவ்வொரு நாளும் கற்க ஒரு புதிய சைகை.';

  @override
  String get signOfTheDayInfo =>
      'The sign of the day is a random word from the lists you\'ve created or subscribed to. It changes once a day.';

  @override
  String searchResultCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count முடிவுகள்',
      one: '1 முடிவு',
    );
    return '$_temp0';
  }

  @override
  String get entryTypePhrase => 'சொற்றொடர்';

  @override
  String searchNoMatchTitle(String query) {
    return '\"$query\" க்கு சைகைகள் இல்லை';
  }

  @override
  String get searchNoMatchBody =>
      'எழுத்துப்பிழையைச் சரிபார்க்கவும், அல்லது தொடர்புடைய சொல்லை முயற்சிக்கவும். சில சைகைகள் வேறு ஆங்கிலச் சொல்லின் கீழ் பட்டியலிடப்பட்டுள்ளன.';

  @override
  String get searchReportMissing => 'Report a missing word';

  @override
  String get searchReportMissingThanks =>
      'Thanks — we\'ll look into adding it.';

  @override
  String get newsEmptyTitle => 'இன்னும் அறிவிப்புகள் இல்லை';

  @override
  String get newsEmptyBody => 'செயலி செய்திகளும் குறிப்புகளும் இங்கே தோன்றும்.';

  @override
  String get newsErrorTitle => 'செய்தியை ஏற்ற முடியவில்லை';

  @override
  String get newsErrorBody =>
      'உங்கள் இணைப்பைச் சரிபார்த்து பின்னர் மீண்டும் முயற்சிக்கவும்.';

  @override
  String get saveVideoFailed =>
      'உங்கள் பட்டியல்களைப் புதுப்பிக்க முடியவில்லை. மீண்டும் முயற்சிக்கவும்.';

  @override
  String get videoOfflineError =>
      'வீடியோவை ஏற்ற முடியவில்லை. உங்கள் சாதனம் இணையத்துடன் இணைக்கப்பட்டுள்ளதா எனச் சரிபார்க்கவும். இணைக்கப்பட்டிருந்தால், சேவையகங்களில் சிக்கல் இருக்கலாம். இது செயலியின் சிக்கல் அல்ல.';

  @override
  String get listsEditHint =>
      'மறுவரிசைப்படுத்த, பெயர்மாற்ற, அல்லது புதிய பட்டியலை உருவாக்க பென்சிலைத் தட்டவும்.';

  @override
  String get listsReorderHint =>
      'Drag a list to reorder it, or tap it to rename. Favourites stays pinned to the top.';

  @override
  String listWordCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count சொற்கள்',
      one: '1 சொல்',
    );
    return '$_temp0';
  }

  @override
  String get listSubscribeViaLink => 'இணைப்பு வழியாக குழுசேரவும்';

  @override
  String get listSubscribedEmptyBody =>
      'யாரோ உங்களுடன் பகிர்ந்த பட்டியலைப் பின்தொடரவும். கணக்கு தேவையில்லை.';

  @override
  String revisionStreak(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days-நாள் தொடர்ச்சி',
      one: '1-நாள் தொடர்ச்சி',
    );
    return '$_temp0';
  }

  @override
  String get revisionStreakSubtitle => 'இதுவரை நீளமான தொடர் — தொடரவும்!';

  @override
  String get revisionBuildSessionHeader =>
      'ஒரு படிப்பு அமர்வை உருவாக்குங்கள். எதை மீள்பார்வை செய்வது என்பதைத் தேர்ந்து, பிறகு தொடங்குங்கள்.';

  @override
  String revisionSignCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count சைகைகள்',
      one: '1 சைகை',
    );
    return '$_temp0';
  }

  @override
  String get revisionNoListsChosen =>
      'இன்னும் பட்டியல்கள் தேர்ந்தெடுக்கப்படவில்லை';

  @override
  String get flashcardsAddAnotherList => 'மற்றொரு பட்டியலைச் சேர்க்கவும்';

  @override
  String get flashcardsSignToWordSubtitle =>
      'ஒரு சைகையைப் பார்த்து, சொல்லை நினைவுகூரவும்';

  @override
  String get flashcardsWordToSignSubtitle =>
      'ஒரு சொல்லைப் பார்த்து, சைகையை நினைவுகூரவும்';

  @override
  String get flashcardsChooseType =>
      'குறைந்தது ஒரு ஃபிளாஷ்கார்டு வகையைத் தேர்ந்தெடுக்கவும்.';

  @override
  String get flashcardsStrategyLabel => 'உத்தி';

  @override
  String get flashcardsCardLimitLabel => 'Card limit';

  @override
  String get flashcardsCardLimitNone => 'No limit';

  @override
  String get revisionPreviousCard => 'Previous card';

  @override
  String get revisionNextCard => 'Next card';

  @override
  String get revisionDueNow => 'இப்போது நிலுவையில்';

  @override
  String get revisionSelected => 'தேர்ந்தெடுக்கப்பட்டது';

  @override
  String revisionFlashcardCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ஃபிளாஷ்கார்டுகள்',
      one: '1 ஃபிளாஷ்கார்டு',
    );
    return '$_temp0';
  }

  @override
  String get playbackSpeedTitle => 'இயக்க வேகம்';

  @override
  String get playbackSpeedNormal => 'சாதாரண';

  @override
  String get regionSheetTitle => 'சைகை பகுதிகள்';

  @override
  String get regionSheetDescription =>
      'முழு ஆஸ்திரேலியாவிற்கும் குறிக்கப்பட்ட சைகைகள் எப்போதும் சேர்க்கப்படும். கீழே மேலும் பகுதிகளைச் சேர்க்கவும்.';

  @override
  String get regionSheetDialects => 'வட்டார வழக்குகள்';

  @override
  String get regionSheetStatesTerritories => 'மாநிலங்கள் & பிரதேசங்கள்';

  @override
  String get regionSheetRecommended => 'Recommended';

  @override
  String get regionSheetUnknownExplanation =>
      'Most signs aren\'t tagged with a region, so leaving this on keeps them in your revision.';

  @override
  String wordVariationWithHint(int index, int count) {
    return 'மாறுபாடு $index/$count · ஒப்பிட ஸ்வைப் செய்யவும்';
  }

  @override
  String wordVariation(int index, int count) {
    return 'மாறுபாடு $index/$count';
  }

  @override
  String videoIndicator(int index, int count) {
    return 'வீடியோ $index/$count';
  }

  @override
  String get seeAlso => 'இதையும் பார்க்கவும்';

  @override
  String get revealAnswer => 'Reveal answer';

  @override
  String get tapToReveal => 'வெளிப்படுத்த தட்டவும்';

  @override
  String get openDictionaryEntry => 'அகராதி உள்ளீட்டைத் திறக்கவும்';

  @override
  String get ratingForgot => 'மறந்துவிட்டேன்';

  @override
  String get ratingGotIt => 'புரிந்தது!';

  @override
  String get ratingNext => 'அடுத்து';

  @override
  String get sessionComplete => 'அமர்வு முடிந்தது';

  @override
  String sessionCompleteHeadline(int count) {
    return 'நல்ல வேலை — $count சைகைகள் மீள்பார்வை செய்யப்பட்டன';
  }

  @override
  String get summarySuccess => 'வெற்றி';

  @override
  String get summaryCards => 'அட்டைகள்';

  @override
  String get summaryGotIt => 'புரிந்தது';

  @override
  String get summaryForgot => 'மறந்தது';

  @override
  String get studyPromptSignToWord => 'இந்தச் சைகையின் பொருள் என்ன?';

  @override
  String get studyPromptWordToSign => 'இந்தச் சொல்லுக்கான சைகை என்ன?';

  @override
  String get videoRotate => 'வீடியோவைச் சுழற்று';

  @override
  String get saveVideoButton => 'சேமி';

  @override
  String savedToListCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count பட்டியல்களில் சேமிக்கப்பட்டது',
      one: '1 பட்டியலில் சேமிக்கப்பட்டது',
    );
    return '$_temp0';
  }

  @override
  String get revisionSummaryTitle => 'மீள்பார்வை சுருக்கம்';

  @override
  String get revisionStatsEmptyTitle => 'இன்னும் புள்ளிவிவரங்கள் இல்லை';

  @override
  String get revisionStatsEmptyBody =>
      'ஒரு மீள்பார்வை அமர்வை முடிக்கவும், உங்கள் முன்னேற்றம் இங்கே தோன்றும்.';

  @override
  String saveToNamedList(String listName) {
    return '$listName இல் சேமி';
  }

  @override
  String savedToNamedList(String listName) {
    return '$listName இல் சேமிக்கப்பட்டது';
  }
}
