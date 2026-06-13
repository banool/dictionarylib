import 'dart:math';

import 'package:dictionarylib/common.dart';
import 'package:dictionarylib/flashcards_logic.dart';
import 'package:dictionarylib/globals.dart';
import 'package:dictionarylib/hearth.dart';
import 'package:dictionarylib/page_flashcards_landing.dart';
import 'package:dictionarylib/revision.dart';
import 'package:dictionarylib/theme.dart' show kRadiusBox, kRadiusCard;
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
    final cs = Theme.of(context).colorScheme;
    final l = DictLibLocalizations.of(context)!;

    Widget content;

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

            // Determine the longest streak. The gap is measured in hours and
            // rounded to days, so it takes more than ~36h between reviews to
            // break a streak (a 36h gap rounds to 2 days > 1; anything up to
            // 36h rounds to <= 1 and counts as consecutive). This is a
            // deliberate grace window rather than strict calendar days, so an
            // evening session followed by a late next-evening session still
            // counts as a streak.
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
        }

        content = reviews.isEmpty
            ? _emptyState(context)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Only celebrate a streak once there is one.
                  if (longestStreakDays > 0) ...[
                    _streakBanner(context, longestStreakDays),
                    const SizedBox(height: 14),
                  ],
                  // The success-rate ring on top, then the rest of the numbers
                  // in a tidy 2×2 grid below.
                  Center(
                    child: _ringBox(
                        context, rememberRate, l.flashcardsSuccessRate),
                  ),
                  const SizedBox(height: 14),
                  Row(children: [
                    Expanded(
                        child: HearthStatTile(
                            value: "$totalAnswers",
                            label: l.flashcardsTotalReviews)),
                    const SizedBox(width: 12),
                    Expanded(
                        child: HearthStatTile(
                            value: "${uniqueMasters.length}",
                            label: l.flashcardsUniqueWords)),
                  ]),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                        child: HearthStatTile(
                            value: "$numCardsRemembered",
                            label: l.flashcardsSuccessfulCards,
                            valueColor: cs.tertiary)),
                    const SizedBox(width: 12),
                    Expanded(
                        child: HearthStatTile(
                            value: "$numCardsForgotten",
                            label: l.flashcardsUnsuccessfulCards,
                            valueColor: cs.error)),
                  ]),
                ],
              );
        break;
      case RevisionStrategy.Random:
        int totalRandomReviews =
            sharedPreferences.getInt(KEY_RANDOM_REVIEWS_COUNTER) ?? 0;
        content = totalRandomReviews == 0
            ? _emptyState(context)
            : HearthStatTile(
                value: "$totalRandomReviews", label: l.flashcardsTotalReviews);
        break;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l.flashcardsRevisionProgressTitle),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          HearthSegmented(
            options: [
              RevisionStrategy.SpacedRepetition.pretty,
              RevisionStrategy.Random.pretty,
            ],
            selected:
                revisionStrategy == RevisionStrategy.SpacedRepetition ? 0 : 1,
            onChanged: (i) {
              setState(() {
                revisionStrategy = i == 0
                    ? RevisionStrategy.SpacedRepetition
                    : RevisionStrategy.Random;
              });
            },
          ),
          const SizedBox(height: 20),
          content,
        ],
      ),
    );
  }

  /// Shown for whichever strategy has no recorded reviews yet.
  Widget _emptyState(BuildContext context) {
    final l = DictLibLocalizations.of(context)!;
    return HearthEmptyState(
      icon: Icons.insights_outlined,
      title: l.revisionStatsEmptyTitle,
      body: l.revisionStatsEmptyBody,
    );
  }

  Widget _streakBanner(BuildContext context, int streakDays) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        borderRadius: BorderRadius.circular(kRadiusCard),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(kRadiusBox),
            ),
            child:
                Icon(Icons.local_fire_department, size: 28, color: cs.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  DictLibLocalizations.of(context)!.revisionStreak(streakDays),
                  style: tt.headlineSmall
                      ?.copyWith(fontSize: 24, color: cs.onPrimaryContainer),
                ),
                Text(
                  DictLibLocalizations.of(context)!.revisionStreakSubtitle,
                  style: TextStyle(fontSize: 13, color: cs.onPrimaryContainer),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _ringBox(BuildContext context, double rate, String label) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(kRadiusBox),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          HearthRing(percent: rate, size: 104, stroke: 10),
          const SizedBox(height: 8),
          Text(label,
              style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }
}
