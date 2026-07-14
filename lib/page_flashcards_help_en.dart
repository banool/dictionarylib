import 'package:flutter/material.dart';

import 'help_common.dart';

/// The shared "Revision FAQ" help page, mirroring the other shared help pages
/// (`page_settings_help_en.dart`, `page_entry_list_help_en.dart`, etc.).
///
/// [subjectNoun] is the word each app uses for a single revisable item — "word"
/// for Auslan, "sign" for SLSL — woven into the questions about where the
/// flashcards come from. [extraItems] lets an app append its own questions
/// (e.g. Auslan's region-selection options); they are added after the common
/// set, preserving insertion order.
Widget getFlashcardsHelpPageEn({
  required String subjectNoun,
  Map<String, List<String>> extraItems = const {},
}) {
  return HelpPage(title: "Revision FAQ", items: {
    "What do the flashcard types mean?": const [
      "There are two types of flashcards you can choose to revise. You must select at least one.",
      "Sign -> Word: We show you someone performing a sign and you must recall what word that sign represents.",
      "Word -> Sign: We show you a word and you must recall a sign for that word."
    ],
    "How do I navigate through each flashcard?": const [
      "Once you have hit \"Start\" you'll be presented with a flashcard "
          "showing you a sign / word and a question like \"What sign "
          "is this?\". Take a moment to think about it and when you're ready, "
          "tap on the screen to reveal the answer. From there you can select "
          "whether you remembered the answer correctly or not.",
      "You can also just tap again anywhere if you got the answer right, as "
          "we select that option by default.",
      "Use the back and forward chevrons at the bottom of the screen to move "
          "between cards. The back chevron lets you revisit the previous card if "
          "you want to take another look or change your answer; the forward "
          "chevron advances to the next card.",
    ],
    "Where do the ${subjectNoun}s for the flashcards come from?": [
      "You may select one or more lists as the flashcard source. By default "
          "there is only one list, your favourites, but you may create additional "
          "lists and use ${subjectNoun}s from many of them at once in a single "
          "revision session. ",
      "Lists that other people have shared with you can be revision sources too. "
          "On the revision settings the lists are grouped just like on the Lists "
          "page: your own under \"My Lists\", and ones you follow or help edit "
          "under \"Subscribed\".",
      "If two lists contain the same $subjectNoun, we will still only show the "
          "$subjectNoun once."
    ],
    "What is a revision strategy?": const [
      "A revision strategy determines how we decide what flashcards to show "
          "you and what information we store about your progress.",
    ],
    "How does the random revision strategy work?": const [
      "The random revision strategy is the simplest option. We simply take "
          "the cards you have selected, shuffle them up, and show them to you. "
          "The cards we show you are not influenced by any previous revision "
          "session, nor do we store any progress information as a result of the "
          "revision session. Think of it as bonus, untracked revision.",
    ],
    "How does the spaced repetition revision strategy work?": const [
      "This strategy follows a Spaced Repetition Learning approach to revision. "
          "Imagine a set of buckets. When a card is first added, it is put in the "
          "first bucket. If you successfully recall what that card is, we move it "
          "into the second bucket. If you get it right again, we move it into the "
          "third bucket. Conversely, if you forget a card, we move it back a bucket.",
      "When a card is in the earlier buckets, we show it to you more frequently "
          "to help you learn. As you become more confident with a card and it "
          "moves into higher buckets, we show you the card less and less "
          "frequently.",
      "When you select this option, we figure out which cards are "
          "due at that particular time. You may not see every card in every "
          "review session, as some cards might not be due until a later date.",
      "Spaced Repetition Learning is most effective if you check in often, "
          "ideally every day (otherwise the cards can tend to pile up). Fortunately, "
          "if a single session seems overwhelming because there are so many "
          "cards to review, you can exit early and we will save your progress "
          "so far, leaving you fewer cards to review next time."
    ],
    ...extraItems,
  });
}
