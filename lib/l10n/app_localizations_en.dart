// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class DictLibLocalizationsEn extends DictLibLocalizations {
  DictLibLocalizationsEn([String locale = 'en']) : super(locale);

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
  String get flashcardsRevisionSources => 'Revision Sources';

  @override
  String get flashcardsSelectLists => 'Select Lists';

  @override
  String get flashcardsTypes => 'Flashcard Types';

  @override
  String get flashcardsSignToWord => 'Sign → Word';

  @override
  String get flashcardsWordToSign => 'Word → Sign';

  @override
  String get flashcardsRevisionSettings => 'Revision Settings';

  @override
  String get flashcardsStart => 'Start';

  @override
  String get flashcardsCardUnavailable =>
      'A card was unavailable and was skipped.';

  @override
  String get flashcardsSuccessRate => 'Success Rate';

  @override
  String get flashcardsSuccessfulCards => 'Successful Cards';

  @override
  String get flashcardsTotalReviews => 'Total Reviews';

  @override
  String get flashcardsUnsuccessfulCards => 'Unsuccessful Cards';

  @override
  String get flashcardsUniqueWords => 'Unique Words';

  @override
  String get flashcardsRevisionProgressTitle => 'Revision Progress';

  @override
  String get setPlaybackSpeedTo => 'Set playback speed to';

  @override
  String get settingsPlayStoreFeedback => 'Give feedback on Play Store';

  @override
  String get settingsAppStoreFeedback => 'Give feedback on App Store';

  @override
  String get settingsRevision => 'Revision';

  @override
  String get settingsHideRevision => 'Hide revision feature';

  @override
  String get settingsHideCommunityLists => 'Hide community lists';

  @override
  String get settingsDeleteRevisionProgress => 'Delete all revision progress';

  @override
  String get settingsDeleteRevisionProgressExplanation =>
      'This will delete all your review progress from all time for both the spaced repetition and random review strategies. Your lists (including favourites) will not be affected. Are you 100% sure you want to do this?';

  @override
  String get settingsProgressDeleted => 'All review progress deleted';

  @override
  String get settingsAppearance => 'Appearance';

  @override
  String get settingsAppTheme => 'App theme';

  @override
  String get settingsColourMode => 'Colour mode';

  @override
  String get settingsColourModeLight => 'Light';

  @override
  String get settingsColourModeDark => 'Dark';

  @override
  String get settingsColourModeSystem => 'System';

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
  String get settingsSeePrivacyPolicy => 'See privacy policy';

  @override
  String get settingsSeeTermsOfService => 'See terms of service';

  @override
  String get settingsBackgroundLogs => 'Background logs';

  @override
  String get settingsHelp => 'Help';

  @override
  String get settingsReportDictionaryDataIssue =>
      'Report issue with dictionary data';

  @override
  String get settingsReportAppIssueGithub => 'Report issue with app (GitHub)';

  @override
  String get settingsReportAppIssueEmail => 'Report issue with app (Email)';

  @override
  String get settingsShowBuildInformation => 'Show build information';

  @override
  String get settingsNetwork => 'Network';

  @override
  String get settingsUseSystemHttpProxy => 'Use system HTTP proxy';

  @override
  String get settingsRestartApp =>
      'You need to restart the app for this change to take effect';

  @override
  String get listEnterNewName => 'Enter new list name';

  @override
  String get listFailedToMake => 'Failed to make new list';

  @override
  String get listFailedToRename => 'Failed to rename list';

  @override
  String get listNewList => 'New List';

  @override
  String get listRenameList => 'Rename List';

  @override
  String get listMyLists => 'My Lists';

  @override
  String get listCommunity => 'Community';

  @override
  String get listSortAdded => 'Added';

  @override
  String get listSortAlpha => 'A-Z';

  @override
  String get listConfirmListDelete =>
      'Are you sure you want to delete this list?';

  @override
  String get listSearchAdd => 'Search for words to add';

  @override
  String get listSearchPrefix => 'Search';

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
  String get entryTypeWords => 'Words';

  @override
  String get entryTypePhrases => 'Phrases';

  @override
  String get entryTypeFingerspelling => 'Fingerspelling';

  @override
  String get entrySelectEntryTypes => 'Select Entry Types';

  @override
  String get alertCareful => 'Careful!';

  @override
  String get alertCancel => 'Cancel';

  @override
  String get alertConfirm => 'Confirm';

  @override
  String get alertOk => 'OK';

  @override
  String get unexpectedErrorLoadingVideo => 'Unexpected error loading media';

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
  String get signInDialogBody => 'To share a list you must sign in.';

  @override
  String signInLastUsedHint(String provider) {
    return 'Last time, you signed in with $provider.';
  }

  @override
  String get signInWithApple => 'Continue with Apple';

  @override
  String get signInWithGoogle => 'Continue with Google';

  @override
  String get signInWithMicrosoft => 'Continue with Microsoft';

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
  String get providerMicrosoft => 'Microsoft';

  @override
  String get providerFacebook => 'Facebook';

  @override
  String get providerTest => 'Test session';

  @override
  String get subscribeDialogTitle => 'Subscribe to a shared list';

  @override
  String get subscribeDialogBody => 'Paste a share link / list ID.';

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
  String retryAttemptSnack(int attempt, int maxAttempts) {
    return 'That didn\'t work — retrying (attempt $attempt of $maxAttempts)…';
  }

  @override
  String get subscribedCopyMenuItem => 'Duplicate';

  @override
  String get settingsSharing => 'Sharing';

  @override
  String get settingsSignIn => 'Sign in to share lists';

  @override
  String settingsSignOut(String provider) {
    return 'Sign out (signed in with $provider)';
  }

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
  String get listNameAllowedChars =>
      'No special characters besides these are allowed: , . - _ !';

  @override
  String get importEditableListsPromptTitle => 'Import your shared lists?';

  @override
  String get importEditableListsPromptBody =>
      'We\'ll fetch any shared lists tied to this account — both the ones you created and the ones you\'ve been added to as an editor — and install them on this device. Existing local lists are untouched; name collisions get a numeric suffix (e.g. \"Cats\" → \"Cats 2\"). Edits sync automatically when you\'re online.';

  @override
  String get importEditableListsActionImport => 'Import';

  @override
  String get importEditableListsActionSkip => 'Skip';

  @override
  String get importEditableListsRunning => 'Importing your shared lists…';

  @override
  String importEditableListsFailed(String message) {
    return 'Couldn\'t import lists: $message';
  }

  @override
  String get importEditableListsResultNone => 'No shared lists found.';

  @override
  String importEditableListsResultDone(int imported, int total) {
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
  String get listSharedWithMeEmpty => 'Nothing here yet.';

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
  String get flashcardsSaveFailed => 'Couldn\'t save your revision progress.';

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
  String get searchRecent => 'Recent';

  @override
  String get searchRecentClear => 'Clear';

  @override
  String get searchSignOfTheDay => 'Sign of the day';

  @override
  String get signOfTheDayBlurb => 'A new sign to learn each day.';

  @override
  String get signOfTheDayInfo =>
      'The sign of the day is a random word from the lists you\'ve created or subscribed to. It changes once a day.';

  @override
  String searchResultCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count results',
      one: '1 result',
    );
    return '$_temp0';
  }

  @override
  String get entryTypePhrase => 'Phrase';

  @override
  String searchNoMatchTitle(String query) {
    return 'No signs for \"$query\"';
  }

  @override
  String get searchNoMatchBody =>
      'Check the spelling, or try a related word. Some signs are listed under a different English word.';

  @override
  String get newsEmptyTitle => 'No announcements yet';

  @override
  String get newsEmptyBody => 'App news and tips will show up here.';

  @override
  String get newsErrorTitle => 'Couldn\'t load news';

  @override
  String get newsErrorBody => 'Check your connection and try again later.';

  @override
  String get saveVideoFailed =>
      'Couldn\'t update your lists. Please try again.';

  @override
  String get videoOfflineError =>
      'Failed to load video. Please confirm your device is connected to the internet. If it is, the servers may be having issues. This is not an issue with the app itself.';

  @override
  String get listsEditHint =>
      'Tap the pencil to reorder, rename, or create a new list.';

  @override
  String get listsReorderHint =>
      'Drag a list to reorder it, or tap it to rename. Favourites stays pinned to the top.';

  @override
  String listWordCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count words',
      one: '1 word',
    );
    return '$_temp0';
  }

  @override
  String get listSubscribeViaLink => 'Subscribe via link';

  @override
  String get listSubscribedEmptyBody =>
      'Tap the cloud icon up top to subscribe to a shared list, or open a share link from someone else. No account needed.';

  @override
  String revisionStreak(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days-day streak',
      one: '1-day streak',
    );
    return '$_temp0';
  }

  @override
  String get revisionStreakSubtitle => 'Longest run yet — keep it going!';

  @override
  String revisionSignCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count signs',
      one: '1 sign',
    );
    return '$_temp0';
  }

  @override
  String get revisionNoListsChosen => 'No lists chosen yet';

  @override
  String get flashcardsAddAnotherList => 'Add another list';

  @override
  String get flashcardsSignToWordSubtitle => 'See a sign, recall the word';

  @override
  String get flashcardsWordToSignSubtitle => 'See a word, recall the sign';

  @override
  String get flashcardsChooseType => 'Choose at least one flashcard type.';

  @override
  String get flashcardsStrategyLabel => 'Strategy';

  @override
  String get flashcardsCardLimitLabel => 'Card limit';

  @override
  String get flashcardsCardLimitNone => 'No limit';

  @override
  String get revisionPreviousCard => 'Previous card';

  @override
  String get revisionNextCard => 'Next card';

  @override
  String get revisionDueNow => 'Due now';

  @override
  String get revisionSelected => 'Selected';

  @override
  String revisionFlashcardCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count flashcards',
      one: '1 flashcard',
    );
    return '$_temp0';
  }

  @override
  String get playbackSpeedTitle => 'Playback speed';

  @override
  String get playbackSpeedNormal => 'Normal';

  @override
  String get regionSheetTitle => 'Sign regions';

  @override
  String get regionSheetDescription =>
      'Signs marked for all of Australia are always included. Add more regions below.';

  @override
  String get regionSheetDialects => 'Dialects';

  @override
  String get regionSheetStatesTerritories => 'States & territories';

  @override
  String get regionSheetRecommended => 'Recommended';

  @override
  String get regionSheetUnknownExplanation =>
      'Most signs aren\'t tagged with a region, so leaving this on keeps them in your revision.';

  @override
  String wordVariationWithHint(int index, int count) {
    return 'Variation $index of $count';
  }

  @override
  String videoIndicator(int index, int count) {
    return 'Video $index of $count';
  }

  @override
  String get seeAlso => 'See also';

  @override
  String get tapToReveal => 'Tap to reveal';

  @override
  String get openDictionaryEntry => 'Open dictionary entry';

  @override
  String get ratingForgot => 'Forgot';

  @override
  String get ratingGotIt => 'Got it!';

  @override
  String get ratingNext => 'Next';

  @override
  String get sessionComplete => 'Session complete';

  @override
  String sessionCompleteHeadline(int count) {
    return 'Nice work — that\'s $count signs revised';
  }

  @override
  String get summarySuccess => 'success';

  @override
  String get summaryCards => 'Cards';

  @override
  String get summaryGotIt => 'Got it';

  @override
  String get summaryForgot => 'Forgot';

  @override
  String get studyPromptSignToWord => 'What does this sign mean?';

  @override
  String get studyPromptWordToSign => 'What is the sign for this word?';

  @override
  String get videoRotate => 'Rotate video';

  @override
  String get saveVideoButton => 'Save';

  @override
  String savedToListCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Saved to $count lists',
      one: 'Saved to 1 list',
    );
    return '$_temp0';
  }

  @override
  String get revisionSummaryTitle => 'Revision summary';

  @override
  String get revisionStatsEmptyTitle => 'No stats yet';

  @override
  String get revisionStatsEmptyBody =>
      'Finish a revision session and your progress will show up here.';

  @override
  String saveToNamedList(String listName) {
    return 'Save to $listName';
  }

  @override
  String savedToNamedList(String listName) {
    return 'Saved to $listName';
  }
}
