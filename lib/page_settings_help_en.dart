import 'package:flutter/material.dart';

import 'common.dart';
import 'help_common.dart';

Widget getSettingsHelpPageEn() {
  return const HelpPage(title: "Settings FAQ", items: {
    "What does it mean to cache videos?": [
      "If you have this setting enabled, when you view a word and the app downloads a video, "
          "it saves the video locally. The next time you look at the word, you don't need to download the "
          "video from the internet again because you already have a copy. This helps save your mobile data "
          "and reduces load on the media servers.",
      "Note that the caching is best effort. If loading a video from cache "
          "fails, the app will just download the video directly from the internet. ",
      "Videos are only cached for $NUM_DAYS_TO_CACHE days, after that the app will "
          "need to download them again. This is to help save space on your device. ",
      "Generally you should keep this feature enabled unless you're running "
          "out of storage space on your device.",
    ],
    "What does \"Drop cache\" do?": [
      "All the videos saved locally due to the caching feature will be deleted. "
          "After this, when you look at a word you've looked at before, the app "
          "will have to download the video again."
    ],
    "What does \"Check for new dictionary data\" do?": [
      "This makes the app check for new data, such as new words / updates to existing "
          "words.",
      "Generally speaking you should not need to do this manually, the app does "
          "this automatically every time it opens."
    ],
    "Which help option should I use?": [
      "You'll notice that on the settings page that there are multiple options for getting help, "
          "specifically a distinction between an issue with the data the app uses and an "
          "issue with the app itself.",
      "An example of a data issue would be an inaccurate definition, an incorrect sign, a missing word, etc. "
          "If a video doesn't load, this is generally also an issue with the data, or the media servers themselves.",
      "An example of an issue with the app would be when you use a feature and it doesn't work, the app crashes, "
          "something doesn't look right visually, etc.",
      "If you encounter an issue, I appreciate you using the appropriate option for getting help.",
    ],
    "What does signing in do?": [
      "Signing in gives you an account, which is what makes list sharing work. With "
          "an account you can share your own lists, accept invitations to help edit "
          "other people's, and keep all of that in sync across your devices.",
      "You can sign in with Apple, Google, Microsoft or Facebook — you'll see "
          "whichever of these are available on your device. If you only want to "
          "search, save Favourites and revise, you don't need to sign in at all.",
    ],
    "What happens if I delete my account?": [
      "We remove every list you own and your editor access to other people's lists "
          "from our servers, along with the display name you chose when sharing. "
          "Anything that doesn't need an account — your local lists, your Favourites "
          "and any lists you've only subscribed to — stays right where it is.",
      "This can't be undone, so we'll ask you to confirm first. If you just want to "
          "step away without removing anything, signing out is the gentler option.",
    ],
  });
}
