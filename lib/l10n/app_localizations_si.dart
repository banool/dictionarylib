// ignore: unused_import
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
  String get flashcardsCardUnavailable =>
      'A card was unavailable and was skipped.';

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
  String get flashcardsRevisionStategyToShow =>
      'සංඛ්‍යාලේඛන පෙන්වීමට සඳහා සංශෝධන උපාය මාර්ගය පෙන්වන්න';

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
  String get settingsDeleteRevisionProgressExplanation =>
      'මෙය මගින් ඔබගේ සියලුම සමාලෝචන, ප්‍රගතිය මාකාදමයි. (ඔබගේ ලැයිස්තු ප්‍රියතමයන් බලපාන්නේ නැත.) ඔබට මෙය කිරීමට අවශ්‍ය බව 100% විශ්වාසද?';

  @override
  String get settingsProgressDeleted => 'සියලුම සමාලෝචන ප්‍රගතිය මකාදමා ඇත';

  @override
  String get settingsAppearance => 'පෙනුම';

  @override
  String get settingsAppTheme => 'යෙදුම් තේමාව';

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
  String get settingsSeePrivacyPolicy => 'පෞද්ගලිකත්ව ප්රතිපත්තිය බලන්න';

  @override
  String get settingsSeeTermsOfService => 'See terms of service';

  @override
  String get settingsBackgroundLogs => 'පසුබිම් ලොග';

  @override
  String get settingsHelp => 'උපකාරය';

  @override
  String get settingsReportDictionaryDataIssue =>
      'ශබ්දකෝෂ දත්ත ගැටළුව වාර්තා කරන්න';

  @override
  String get settingsReportAppIssueGithub =>
      'යෙදුමේ ගැටළුව (Github) වාර්තා කරන්න';

  @override
  String get settingsReportAppIssueEmail =>
      'යෙදුමේ ගැටළුව (Email) වාර්තා කරන්න';

  @override
  String get settingsShowBuildInformation => 'ගොඩනැගීමේ තොරතුරු පෙන්වන්න';

  @override
  String get settingsNetwork => 'ජාලය';

  @override
  String get settingsUseSystemHttpProxy => 'පද්ධති HTTP ප්‍රොක්සි භාවිතා කරන්න';

  @override
  String get settingsRestartApp =>
      'මෙම වෙනස ක්‍රියාත්මක වීමට යෙදුම නැවත ආරම්භ කළ යුතුය';

  @override
  String get listFavourites => 'ප්‍රියතම';

  @override
  String get listNameCannotBeEmpty => 'ලැයිස්තු නම හිස් විය නොහැක';

  @override
  String get listNameInvalid =>
      'වලංගු නොවන නම, මෙය දැනටමත් අල්ලාගෙන තිබිය යුතුය';

  @override
  String get listEnterNewName => 'නව නම ලැයිස්තු ඇතුළත් කරන්න';

  @override
  String get listFailedToMake => 'නව ලැයිස්තුව සාදා ගැනීමට අසාර්ථක විය';

  @override
  String get listFailedToRename => 'Failed to rename list';

  @override
  String get listNewList => 'නව ලැයිස්තු';

  @override
  String get listRenameList => 'Rename List';

  @override
  String get listMyLists => 'මගේ ලැයිස්තු';

  @override
  String get listCommunity => 'ප්රජාව';

  @override
  String get listSortAdded => 'Added';

  @override
  String get listSortAlpha => 'A-Z';

  @override
  String get listConfirmListDelete =>
      'ඔබට මෙම ලැයිස්තුව මැකීමට අවශ්‍ය බව විශ්වාසද?';

  @override
  String get listSearchAdd => 'එක් කිරීම සඳහා වචන සොයන්න';

  @override
  String get listSearchPrefix => 'සොයන්න';

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
  String get wordAlreadyFavourited => 'දැනටමත් ප්‍රියතම!';

  @override
  String get wordFavouriteThisWord => 'මෙම වචනය ප්‍රියතම කරන්න';

  @override
  String get wordNoDefinitions =>
      'මෙම වචනය / වාක්‍ය ඛණ්ඩය සඳහා නිර්වචන දත්ත නොමැත';

  @override
  String get wordDataMissing => 'දත්ත අතුරුදහන්';

  @override
  String get entryTypeWords => 'වචන';

  @override
  String get entryTypePhrases => 'වාක්ය ඛණ්ඩ';

  @override
  String get entryTypeFingerspelling => 'ඇඟිලි අකුරු';

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
  String get alertOk => 'OK';

  @override
  String get startupFailureMessage =>
      'යෙදුම නිවැරදිව ආරම්භ කිරීමට අසමත් විය. කරුණාකර, පළමුව, ඔබ යෙදුමේ නවතම අනුවාදය භාවිතා කරන බව සහතික කරන්න. ඔබ එසේ නම්, කරුණාකර මෙම දෝෂය පෙන්වන පුනරුපුවරුවක් සමග daniel@dport.me වෙත ඊමේල් කරන්න.';

  @override
  String get unexpectedErrorLoadingVideo => 'අනපේක්ෂිත දෝෂය පූරණය කරමින්';

  @override
  String get deviceDefault => 'ප්‍රදාන උපාංග';

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
  String subscribeInviteDetected(String displayName) {
    return 'This is an editor invite link, not a regular subscribe link. Accept it to edit \"$displayName\" alongside the creator.';
  }

  @override
  String get subscribeInviteDetectedUnknown =>
      'This is an editor invite link, not a regular subscribe link. Accept it to become an editor of this list.';

  @override
  String get subscribeInviteAcceptButton => 'Accept invitation';

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
  String get ownedStatusPendingSyncSuffix => 'Pending sync';

  @override
  String get ownedStatusSyncedSuffix => 'Synced';

  @override
  String get subscribedStatusOrphaned => 'Removed by owner';

  @override
  String get subscribedStatusFallback => 'Subscribed';

  @override
  String get syncedJustNow => 'Synced just now';

  @override
  String syncedMinutesAgo(int count) {
    return 'Synced ${count}m ago';
  }

  @override
  String syncedHoursAgo(int count) {
    return 'Synced ${count}h ago';
  }

  @override
  String syncedDaysAgo(int count) {
    return 'Synced ${count}d ago';
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
    return 'Synced $sync · Updated $updated';
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
  String get searchRecent => 'මෑත';

  @override
  String get searchRecentClear => 'හිස් කරන්න';

  @override
  String get searchSignOfTheDay => 'අද දවසේ සංඥාව';

  @override
  String get signOfTheDayBlurb => 'සෑම දිනකම ඉගෙන ගැනීමට නව සංඥාවක්.';

  @override
  String get signOfTheDayInfo =>
      'The sign of the day is a random word from the lists you\'ve created or subscribed to. It changes once a day.';

  @override
  String searchResultCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'ප්‍රතිඵල $count',
      one: 'ප්‍රතිඵල 1',
    );
    return '$_temp0';
  }

  @override
  String get entryTypePhrase => 'වාක්‍ය ඛණ්ඩය';

  @override
  String searchNoMatchTitle(String query) {
    return '\"$query\" සඳහා සංඥා නැත';
  }

  @override
  String get searchNoMatchBody =>
      'අක්ෂර වින්‍යාසය පරීක්ෂා කරන්න, නැතහොත් සම්බන්ධ වචනයක් උත්සාහ කරන්න. සමහර සංඥා වෙනත් ඉංග්‍රීසි වචනයක් යටතේ ඇත.';

  @override
  String get searchReportMissing => 'Report a missing word';

  @override
  String get searchReportMissingThanks =>
      'Thanks — we\'ll look into adding it.';

  @override
  String get newsEmptyTitle => 'තවම නිවේදන නැත';

  @override
  String get newsEmptyBody => 'යෙදුම් පුවත් සහ ඉඟි මෙහි පෙන්වනු ඇත.';

  @override
  String get newsErrorTitle => 'පුවත් පූරණය කළ නොහැකි විය';

  @override
  String get newsErrorBody =>
      'ඔබගේ සම්බන්ධතාවය පරීක්ෂා කර පසුව නැවත උත්සාහ කරන්න.';

  @override
  String get saveVideoFailed =>
      'ඔබගේ ලැයිස්තු යාවත්කාලීන කළ නොහැකි විය. කරුණාකර නැවත උත්සාහ කරන්න.';

  @override
  String get videoOfflineError =>
      'වීඩියෝව පූරණය කිරීමට අසමත් විය. ඔබගේ උපාංගය අන්තර්ජාලයට සම්බන්ධ දැයි තහවුරු කරගන්න. එසේ නම්, සේවාදායකවල ගැටලුවක් තිබිය හැක. මෙය යෙදුමේම ගැටලුවක් නොවේ.';

  @override
  String get listsEditHint =>
      'නැවත පිළිවෙළට, නැවත නම් කිරීමට, හෝ නව ලැයිස්තුවක් සෑදීමට පැන්සල තට්ටු කරන්න.';

  @override
  String get listsReorderHint =>
      'Drag a list to reorder it, or tap it to rename. Favourites stays pinned to the top.';

  @override
  String listWordCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'වචන $count',
      one: 'වචන 1',
    );
    return '$_temp0';
  }

  @override
  String get listSubscribeViaLink => 'සබැඳිය හරහා දායක වන්න';

  @override
  String get listSubscribedEmptyBody =>
      'යමෙකු ඔබ සමඟ බෙදාගත් ලැයිස්තුවක් අනුගමනය කරන්න. ගිණුමක් අවශ්‍ය නැත.';

  @override
  String revisionStreak(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: 'දින $days ක අඛණ්ඩතාව',
      one: 'දින 1 ක අඛණ්ඩතාව',
    );
    return '$_temp0';
  }

  @override
  String get revisionStreakSubtitle =>
      'මේ දක්වා දිගම ධාවනය — දිගටම කරගෙන යන්න!';

  @override
  String get revisionBuildSessionHeader =>
      'අධ්‍යයන සැසියක් සාදන්න. පුණරීක්ෂණය කළ යුතු දේ තෝරා, පසුව ආරම්භ කරන්න.';

  @override
  String revisionSignCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'සංඥා $count',
      one: 'සංඥා 1',
    );
    return '$_temp0';
  }

  @override
  String get revisionNoListsChosen => 'තවම ලැයිස්තු තෝරා නැත';

  @override
  String get flashcardsAddAnotherList => 'තවත් ලැයිස්තුවක් එක් කරන්න';

  @override
  String get flashcardsSignToWordSubtitle => 'සංඥාවක් බලා, වචනය මතක් කරන්න';

  @override
  String get flashcardsWordToSignSubtitle => 'වචනයක් බලා, සංඥාව මතක් කරන්න';

  @override
  String get flashcardsChooseType =>
      'අවම වශයෙන් එක් ෆ්ලෑෂ්කාඩ් වර්ගයක් තෝරන්න.';

  @override
  String get flashcardsStrategyLabel => 'උපාය මාර්ගය';

  @override
  String get flashcardsCardLimitLabel => 'Card limit';

  @override
  String get flashcardsCardLimitNone => 'No limit';

  @override
  String get revisionPreviousCard => 'Previous card';

  @override
  String get revisionNextCard => 'Next card';

  @override
  String get revisionDueNow => 'දැන් නියමිතයි';

  @override
  String get revisionSelected => 'තෝරාගත්';

  @override
  String revisionFlashcardCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'ෆ්ලෑෂ්කාඩ් $count',
      one: 'ෆ්ලෑෂ්කාඩ් 1',
    );
    return '$_temp0';
  }

  @override
  String get playbackSpeedTitle => 'ධාවන වේගය';

  @override
  String get playbackSpeedNormal => 'සාමාන්‍ය';

  @override
  String get regionSheetTitle => 'සංඥා කලාප';

  @override
  String get regionSheetDescription =>
      'මුළු ඕස්ට්‍රේලියාව සඳහා සලකුණු කළ සංඥා සැමවිටම ඇතුළත් වේ. පහතින් තවත් කලාප එක් කරන්න.';

  @override
  String get regionSheetDialects => 'උපභාෂා';

  @override
  String get regionSheetStatesTerritories => 'ප්‍රාන්ත සහ ප්‍රදේශ';

  @override
  String get regionSheetRecommended => 'Recommended';

  @override
  String get regionSheetUnknownExplanation =>
      'Most signs aren\'t tagged with a region, so leaving this on keeps them in your revision.';

  @override
  String wordVariationWithHint(int index, int count) {
    return 'විචලනය $index/$count · සැසඳීමට ස්වයිප් කරන්න';
  }

  @override
  String wordVariation(int index, int count) {
    return 'විචලනය $index/$count';
  }

  @override
  String videoIndicator(int index, int count) {
    return 'වීඩියෝ $index/$count';
  }

  @override
  String get seeAlso => 'මෙයත් බලන්න';

  @override
  String get revealAnswer => 'Reveal answer';

  @override
  String get tapToReveal => 'හෙළි කිරීමට තට්ටු කරන්න';

  @override
  String get openDictionaryEntry => 'ශබ්දකෝෂ ඇතුළත් කිරීම විවෘත කරන්න';

  @override
  String get ratingForgot => 'අමතක විය';

  @override
  String get ratingGotIt => 'තේරුණා!';

  @override
  String get ratingNext => 'ඊළඟ';

  @override
  String get sessionComplete => 'සැසිය සම්පූර්ණයි';

  @override
  String sessionCompleteHeadline(int count) {
    return 'හොඳ වැඩක් — සංඥා $count ක් පුණරීක්ෂණය කළා';
  }

  @override
  String get summarySuccess => 'සාර්ථකත්වය';

  @override
  String get summaryCards => 'කාඩ්';

  @override
  String get summaryGotIt => 'තේරුණා';

  @override
  String get summaryForgot => 'අමතක විය';

  @override
  String get studyPromptSignToWord => 'මෙම සංඥාවේ අර්ථය කුමක්ද?';

  @override
  String get studyPromptWordToSign => 'මෙම වචනය සඳහා සංඥාව කුමක්ද?';

  @override
  String get videoRotate => 'වීඩියෝව කරකවන්න';

  @override
  String get saveVideoButton => 'සුරකින්න';

  @override
  String savedToListCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'ලැයිස්තු $countකට සුරකින ලදී',
      one: 'ලැයිස්තු 1කට සුරකින ලදී',
    );
    return '$_temp0';
  }

  @override
  String get revisionSummaryTitle => 'පුණරීක්ෂණ සාරාංශය';

  @override
  String get revisionStatsEmptyTitle => 'තවම සංඛ්‍යාලේඛන නැත';

  @override
  String get revisionStatsEmptyBody =>
      'පුණරීක්ෂණ සැසියක් අවසන් කරන්න, එවිට ඔබේ ප්‍රගතිය මෙහි පෙන්වනු ඇත.';

  @override
  String saveToNamedList(String listName) {
    return '$listName වෙත සුරකින්න';
  }

  @override
  String savedToNamedList(String listName) {
    return '$listName වෙත සුරකින ලදී';
  }
}
