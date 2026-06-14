// ignore_for_file: prefer_const_constructors
// ignore_for_file: prefer_const_literals_to_create_immutables

import 'package:dictionarylib/help_common.dart';
import 'package:flutter/material.dart';

Widget getEntryListOverviewHelpPageEn() {
  return HelpPage(title: "Lists FAQ", items: {
    "How do I make a new list?": [
      "In the app bar in the top right corner, there is a pencil icon. Tap this to enter edit mode. "
          "Once in edit mode, tap the green plus button. This will allow you to make a new list.",
    ],
    "How do I delete a list?": [
      "In the app bar in the top right corner, there is a pencil icon. Tap this to enter edit mode. "
          "Once in edit mode, tap the red icon to the right of the list you want to delete.",
      "Note that you cannot delete the Favourites list.",
    ],
    "How do I change the order of my lists?": [
      "In the app bar in the top right corner, there is a pencil icon. "
          "First, tap this icon to enter edit mode. "
          "After that, you can drag the lists around to change the order.",
      "Note that you cannot reorder the Favourites list, it will always be first."
    ],
    "How does the Favourites list work?": [
      "The Favourites list is a special list that you cannot delete. When you visit "
          "a word page, there is a star icon that you can use to save words to your "
          "Favourites. The intention here is to make it easy to quickly save a word "
          "that you come across while searching.",
      "To add words to any other list, you must add them from the page for that list. "
          "To see more information about how to do this, open any list (e.g. "
          "Favourites), click the help icon in the top right, and read the information "
          "under \"How do I add words to a list?\"",
    ],
    "What do the tabs at the top of the page mean?": [
      "\"My Lists\" holds the lists that live on this device — your Favourites, any "
          "lists you have made yourself, and any of those you have shared with other "
          "people.",
      "\"Subscribed\" holds lists other people have shared with you: ones you are "
          "following along, plus any you have been invited to help edit.",
      "\"Community\" holds the ready-made lists we ship with the app, each grouped "
          "around a topic like \"Animals\" or \"Colours\".",
      "The Subscribed and Community tabs only show up when there's something in "
          "them, so you may not always see all three.",
    ],
    "What are community lists?": [
      "Community lists are predefined collections of entries centered around a "
          "particular topic, such as \"Animals\" or \"Colors\".",
      "These lists and the entries within them cannot be deleted or reordered.",
    ],
    "Can I share my lists with other people?": [
      "Yes. Open one of your lists and tap the share icon in the top right. We'll "
          "ask you to pick a display name for the list, then hand you a share link "
          "you can send to anyone — there's a QR code too, which is handy when you're "
          "sharing with someone sitting right next to you.",
      "Anyone who opens the link can subscribe to your list and will see your "
          "changes as you make them. If you'd rather someone help you edit the list "
          "than just follow along, you can invite them as an editor. There's more on "
          "both of these in the List FAQ — open a list and tap the help icon.",
      "Sharing is tied to an account, so the first time you share a list we'll ask "
          "you to sign in. See \"Do I need an account?\" below.",
    ],
    "How do I follow a list someone shared with me?": [
      "If they sent you a share link, the easiest way is to just open it — the app "
          "will offer to subscribe you. Otherwise, go to the \"Subscribed\" tab, tap "
          "the cloud icon in the top right, and either paste the share link (or list "
          "ID) or scan the other person's QR code.",
      "Once you're subscribed, the list appears under \"Subscribed\" and quietly "
          "updates whenever the owner changes it. If the owner ever deletes the "
          "list, it sticks around for you, marked \"Removed by owner\".",
      "You don't need an account to follow someone else's list — only to make and "
          "share your own.",
    ],
    "Do I need an account?": [
      "Only for sharing. Searching, your Favourites, your own lists, revision, and "
          "following other people's shared lists all work perfectly well without "
          "one.",
      "You'll be asked to sign in when you want to share a list of your own, or "
          "accept an invitation to help edit someone else's. You can do this any "
          "time from Settings using the \"Sign in to share lists\" option — there's "
          "more in the Settings FAQ.",
    ],
  });
}
