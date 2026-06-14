// ignore_for_file: prefer_const_constructors
// ignore_for_file: prefer_const_literals_to_create_immutables

import 'package:flutter/material.dart';

import 'help_common.dart';

Widget getEntryListHelpPageEn() {
  return HelpPage(title: "List FAQ", items: {
    "How do I add words to a list?": [
      "In the app bar in the top right corner, there is a pencil icon. "
          "Tap this to enter edit mode. Once in edit mode, you can use the search "
          "bar to search for words that you would like to add to the list. Press "
          "the green button to the right of each item to add it your list.",
      "The green plus button in the bottom right is just a convenience "
          "that opens the keyboard up for you.",
      "Once you are done, press the pencil icon again to exit edit mode."
    ],
    "How do I remove words from a list?": [
      "In the app bar in the top right corner, there is a pencil icon. "
          "Tap this to enter edit mode. Once in edit mode, you can press the "
          "red icon beside a word to remove it from the list.",
      "Note that if you search for a word, this will show words not currently "
          "in the list so you can add them to the list, it will not show you "
          "words already in the list.",
    ],
    "What does the star icon do on a word page?": [
      "When you tap this, it adds the word to your Favourites. This is a convenience "
          "for the Favourites list only. ",
      "To add a word to any other list, you must add "
          "it from the page for that list directly. See \"How do I add words to a list?\"",
    ],
    "What does the sort button in the bottom right do?": [
      "This button toggles between two different sort orders. By default, we show "
          "items in the order you added them to the list. If you press this button, "
          "we instead show the items in alphabetical order. Each time you press the "
          "button the sort order will switch between these two options."
    ],
    "Why can't I see the star icon on a word page?": [
      "Originally, when you visited a word page from a list other than your favourites, "
          "we showed the star icon. How it actually worked was it would add the word to "
          "your Favourites no matter what, but some users expected it to add the word "
          "to the list they just came from. To avoid this confusing situation, we just "
          "do not show that button when visiting a word from a list (unless that list "
          "is your Favourites)."
    ],
    "How do I share this list?": [
      "Tap the share icon in the top right of the list. The first time, we'll ask "
          "you to pick a display name so people know what they're following, then "
          "give you a share link to send around (along with a QR code for sharing in "
          "person). Tapping the share icon again later brings the link back up.",
      "Anyone who opens the link can subscribe and will follow along with your "
          "edits. Sharing needs an account, so you'll be asked to sign in the first "
          "time.",
      "To stop sharing, open the share link again and choose to unshare. The list "
          "stays on your device — it just stops syncing, and anyone who was "
          "following it will see it as removed.",
    ],
    "How do I let someone else help edit my list?": [
      "Open the list and tap the people icon in the top right to see its members. "
          "As the owner you can invite an editor from here, and we'll generate an "
          "invite link to send them. Invites expire after a while, so it's best to "
          "send one when the person is ready to accept it.",
      "Once they accept, they can add and remove words just like you can, and "
          "everyone's changes sync together. You can remove an editor at any time "
          "from that same members page, and an editor can choose to leave a list "
          "they no longer want to help with.",
      "Inviting an editor needs an account on both sides. Simply following a list "
          "to read it does not.",
    ],
    "I'm following a list someone shared — why can't I edit it?": [
      "When you subscribe to someone else's shared list, you get a read-only copy "
          "that follows their changes, so the edit (pencil) option isn't shown. "
          "Editing is kept to the owner and anyone they've invited as an editor.",
      "If you'd like to help look after the list, ask the owner to invite you as an "
          "editor. If you just want a copy you can change freely, you can always "
          "make a new list of your own and add the words you want.",
    ],
  });
}
