import 'dart:math';

import 'package:dictionarylib/common.dart';
import 'package:dictionarylib/flashcards_logic.dart';
import 'package:dictionarylib/globals.dart';
import 'package:dictionarylib/page_flashcards_landing.dart';
import 'package:dictionarylib/revision.dart';
import 'package:dolphinsr_dart/dolphinsr_dart.dart';
import 'package:flutter/material.dart';
import 'package:dictionarylib/dictionarylib.dart' show DictLibLocalizations;

class RevisionHistoryPage extends StatefulWidget {
  const RevisionHistoryPage({super.key});

  @override
  RevisionHistoryPageState createState() => RevisionHistoryPageState();
}

class RevisionHistoryPageState extends State<RevisionHistoryPage> {
  late RevisionStrategy revisionStrategy;

  @override
  void initState() {
    super.initState();
    revisionStrategy = loadRevisionStrategy();
  }

  @override
  Widget build(BuildContext context) {
    ColorScheme currentTheme = Theme.of(context).colorScheme;
    Widget getText(String s, {bool bold = false}) {
      FontWeight? weight;
      if (bold) {
        weight = FontWeight.w600;
      }
      return Padding(
        padding: const EdgeInsets.only(top: 30),
        child: Text(s, style: TextStyle(fontSize: 16, fontWeight: weight)),
      );
    }

    Widget getRevisionStrategyButton(RevisionStrategy rs) {
      return TextButton(
        onPressed: () {
          setState(() {
            revisionStrategy = rs;
          });
        },
        style: ButtonStyle(
            padding: WidgetStateProperty.all(const EdgeInsets.all(10)),
            backgroundColor: WidgetStateProperty.all(currentTheme.onPrimary),
            foregroundColor: WidgetStateProperty.all(rs == revisionStrategy
                ? currentTheme.primary
                : const Color.fromARGB(255, 145, 145, 145)),
            minimumSize: WidgetStateProperty.all<Size>(const Size(160, 45)),
            side: WidgetStateProperty.all(const BorderSide(
                /*color: Color.fromARGB(110, 185, 185, 185),*/ width: 1.5))),
        child: Text(rs.pretty),
      );
    }

    String getDatetimeString(DateTime dt) {
      return "${dt.year.toString()}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}";
    }

    List<Widget> leftColumn;
    List<Widget> rightColumn;

    Widget disclaimer = Container();

    switch (revisionStrategy) {
      case RevisionStrategy.SpacedRepetition:
        List<Review> reviewsRaw = readReviews();

        List<Review> reviews = [];
        for (Review r in reviewsRaw) {
          // Skip incomplete reviews.
          if (r.master == null || r.rating == null || r.ts == null) {
            printAndLog("Skipping incomplete review: $r");
            continue;
          }
          reviews.add(r);
        }

        int totalAnswers = reviews.length;
        int numCardsRemembered = 0;
        int numCardsForgotten = 0;
        double rememberRate = 0;
        Set<String> uniqueMasters = {};
        int longestStreakDays = 0;

        if (reviews.isNotEmpty) {
          reviews.sort((a, b) {
            return a.ts!.compareTo(b.ts!);
          });

          DateTime earliestDateTime = reviews[0].ts!;

          DateTime startOfStreak = earliestDateTime;
          DateTime previousDateTime = earliestDateTime;

          int i = 1;
          for (Review r in reviews) {
            // Build up unique words.
            uniqueMasters.add(r.master!);

            // Count up success / failure based on the ratings.
            switch (r.rating!) {
              case Rating.Good:
              case Rating.Easy:
                numCardsRemembered += 1;
                break;
              case Rating.Hard:
              case Rating.Again:
                numCardsForgotten += 1;
                break;
            }

            // Determine the longest streak.
            int daysSincePreviousDateTime =
                (r.ts!.difference(previousDateTime).inHours / 24).round();
            if (daysSincePreviousDateTime > 1 || i == reviews.length) {
              // If we're just in this block because we've hit the end of
              // the list, use this datetime if it has been 1 day since the
              // previous one. Otherwise just use the previous one, since in
              // any other case, we're here because the current datetime was
              // more than 1 day after the previous one, breaking the streak.
              DateTime comparison;
              if (daysSincePreviousDateTime == 1) {
                comparison = r.ts!;
              } else {
                comparison = previousDateTime;
              }
              int daysSinceStartOfStreak =
                  (comparison.difference(startOfStreak).inHours / 24).round();
              longestStreakDays =
                  max(longestStreakDays, daysSinceStartOfStreak);
              startOfStreak = r.ts!;
            }
            previousDateTime = r.ts!;
            i += 1;
          }

          rememberRate =
              totalAnswers == 0 ? 0 : numCardsRemembered / totalAnswers;

          String dateString = getDatetimeString(earliestDateTime);
          disclaimer = Text("Stats collected since $dateString");
        }

        String days = longestStreakDays == 1 ? "day" : "days";

        leftColumn = [
          getText(
              "${DictLibLocalizations.of(context)!.flashcardsTotalReviews}:",
              bold: true),
          getText("${DictLibLocalizations.of(context)!.flashcardsSuccessRate}:",
              bold: true),
          getText(
              "${DictLibLocalizations.of(context)!.flashcardsSuccessfulCards}:",
              bold: true),
          getText(
              "${DictLibLocalizations.of(context)!.flashcardsUnsuccessfulCards}:",
              bold: true),
          getText("${DictLibLocalizations.of(context)!.flashcardsUniqueWords}:",
              bold: true),
          getText(
              "${DictLibLocalizations.of(context)!.flashcardsLongestStreak}:",
              bold: true),
        ];
        rightColumn = [
          getText("$totalAnswers"),
          getText("${(rememberRate * 100).toStringAsFixed(1)}%"),
          getText("$numCardsRemembered"),
          getText("$numCardsForgotten"),
          getText("${uniqueMasters.length}"),
          getText("$longestStreakDays $days"),
        ];
        break;
      case RevisionStrategy.Random:
        int totalRandomReviews =
            sharedPreferences.getInt(KEY_RANDOM_REVIEWS_COUNTER) ?? 0;
        leftColumn = [
          getText(
              "${DictLibLocalizations.of(context)!.flashcardsTotalReviews}:",
              bold: true),
        ];
        rightColumn = [getText("$totalRandomReviews")];
        int? firstStartedTrackingRandomReviews =
            sharedPreferences.getInt(KEY_FIRST_RANDOM_REVIEW);
        if (firstStartedTrackingRandomReviews != null) {
          var dt = DateTime.fromMillisecondsSinceEpoch(
                  firstStartedTrackingRandomReviews * 1000)
              .toLocal();
          String dateString = getDatetimeString(dt);
          // TODO Localize this date string if this isn't happening already.
          disclaimer = Text(
              "${DictLibLocalizations.of(context)!.flashcardsStatsCollectedSince} $dateString");
        }
        break;
    }

    return Scaffold(
        appBar: AppBar(
          title: Text(DictLibLocalizations.of(context)!
              .flashcardsRevisionProgressTitle),
          centerTitle: true,
        ),
        body: CustomScrollView(slivers: [
          SliverFillRemaining(
              hasScrollBody: false,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 50),
                  ),
                  Text(DictLibLocalizations.of(context)!
                      .flashcardsRevisionStategyToShow),
                  const Padding(
                    padding: EdgeInsets.only(top: 15),
                  ),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    getRevisionStrategyButton(
                        RevisionStrategy.SpacedRepetition),
                    const Padding(
                      padding: EdgeInsets.only(left: 20),
                    ),
                    getRevisionStrategyButton(RevisionStrategy.Random),
                  ]),
                  const Padding(
                    padding: EdgeInsets.only(top: 30),
                  ),
                  const Divider(
                    height: 20,
                    thickness: 2,
                    indent: 20,
                    endIndent: 20,
                  ),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Padding(
                      padding: EdgeInsets.only(left: 60),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: leftColumn,
                    ),
                    const Spacer(),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: rightColumn,
                    ),
                    const Padding(
                      padding: EdgeInsets.only(left: 60),
                    ),
                  ]),
                  Expanded(child: Container()),
                  disclaimer,
                  const Padding(
                    padding: EdgeInsets.only(bottom: 50),
                  )
                ],
              ))
        ]));
  }
}
