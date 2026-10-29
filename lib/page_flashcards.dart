import 'dart:async';

import 'package:dictionarylib/analytics.dart';
import 'package:dictionarylib/common.dart';
import 'package:dictionarylib/flashcards_logic.dart';
import 'package:dictionarylib/globals.dart';
import 'package:dictionarylib/hearth.dart';
import 'package:dictionarylib/revision.dart';
import 'package:dictionarylib/theme.dart' show constrainContentWidth;
import 'package:dictionarylib/video_player_screen.dart';
import 'package:dolphinsr/dolphinsr.dart';
import 'package:flutter/material.dart';

import 'tv_focus.dart';

import 'package:dictionarylib/dictionarylib.dart' show DictLibLocalizations;

/// The centred region widget shown beneath a flashcard (flanked by the shared
/// nav arrows). Auslan renders its `MySubEntry.getRegionsString()`; SLSL uses
/// its `getRegionalInformationWidget`. The region is hidden until [revealed].
typedef FlashcardsRegionInfoBuilder = Widget Function(
  BuildContext context,
  ResolvedSavedVideo resolved,
  bool shouldUseHorizontalDisplay,
  bool revealed,
);

/// App-specific app-bar actions placed BEFORE the shared playback-speed
/// dropdown. Auslan returns the Signbank link (using the English [word] +
/// `MySubEntry.index`); SLSL has none (the field is null).
typedef FlashcardsAppBarActionsBuilder = List<Widget> Function(
  BuildContext context, {
  required String word,
  required ResolvedSavedVideo resolved,
  required bool revealed,
});

/// The per-app knobs the shared flashcards page reads. The two dictionary apps
/// run the identical DolphinSR review session but differ in a few leaf
/// concerns: the video aspect ratio, how a card's region prints, the app-bar
/// extras, and the row height under the card. Mirrors [WordPageConfig].
class FlashcardsConfig {
  const FlashcardsConfig({
    required this.videoAspectRatio,
    required this.navigateToEntryPage,
    required this.buildRegionInfo,
    this.buildExtraAppBarActions,
    required this.regionRowHeight,
  });

  /// The flashcard video's fallback aspect ratio. Auslan 16/9, SLSL 16/12.
  final double videoAspectRatio;

  /// Opens the full entry page from the "open dictionary entry" button. Reuses
  /// the app's own navigation (which carries its [WordPageConfig]); flashcards
  /// are native-only, so this is the imperative `EntryPage` push.
  final NavigateToEntryPageFn navigateToEntryPage;

  /// The centred region widget under the card.
  final FlashcardsRegionInfoBuilder buildRegionInfo;

  /// App-bar actions before the playback-speed dropdown (Auslan's Signbank
  /// link); null when the app adds none.
  final FlashcardsAppBarActionsBuilder? buildExtraAppBarActions;

  /// Height of the region + nav-arrows row beneath the card. Auslan 48,
  /// SLSL 56.
  final double regionRowHeight;
}

class FlashcardsPage extends StatefulWidget {
  const FlashcardsPage({
    super.key,
    required this.di,
    required this.revisionStrategy,
    required this.config,
  });

  final DolphinInformation di;
  final RevisionStrategy revisionStrategy;
  final FlashcardsConfig config;

  @override
  FlashcardsPageState createState() => FlashcardsPageState();
}

class FlashcardsPageState extends State<FlashcardsPage> {
  Map<DRCard, Review> answers = {};

  /// The cards this session goes through, in order: fixed when it starts
  /// (see [getSessionCards]), and each shown once.
  late final List<DRCard> _sessionCards;

  /// The video behind each of those cards, as it was when the session
  /// started. The landing page underneath builds its lookup afresh whenever
  /// it refreshes, and this page can be rebuilt with the new one part way
  /// through; a card whose video had since left its list would then have
  /// nothing to show.
  late final Map<String, ResolvedSavedVideo> _videos;

  late int numCardsToReview;

  DRCard? currentCard;
  bool currentCardRevealed = false;

  /// On Android TV the remote's focus goes where OK should act: the reveal
  /// button on each new card (a word-to-sign card has nothing else focusable,
  /// and on a sign-to-word card revealing is the next step once the video has
  /// played), then the positive answer ("Got it!" / "Next") once revealed,
  /// since the reveal button it was on disappears.
  final FocusNode _tvRevealFocus = FocusNode(debugLabel: 'flashcardReveal');
  final FocusNode _tvAnswerFocus = FocusNode(debugLabel: 'flashcardAnswer');

  /// The (card, revealed) state focus was last moved for, so it moves once
  /// per change rather than on every rebuild.
  Object? _tvFocusedFor;

  /// Where we are in [_sessionCards], and the furthest we've been. They
  /// differ once the user has stepped back to revisit an earlier card: the
  /// forward arrow then takes them through the cards already shown, back to
  /// exactly where they were.
  int _pos = -1;
  int _furthest = -1;

  bool forgotRatingWidgetActive = false;
  bool rememberedRatingWidgetActive = true;

  bool reviewsWritten = false;

  /// Set when [beforePop] failed to persist the session's reviews on the
  /// session-end path. Drives a retry banner on the summary screen so a
  /// silent write failure can't make the user think their progress was
  /// saved when it wasn't.
  bool reviewWriteFailed = false;

  PlaybackSpeed playbackSpeed = getDefaultPlaybackSpeed();

  Timer? nextCardTimer;

  @override
  void initState() {
    super.initState();
    var cards = getSessionCards(widget.di.dolphin, widget.revisionStrategy);
    // Apply the optional session-size cap the user set on the landing page.
    // 0 means no limit. The landing page caps its displayed count the same way.
    final cardLimit = sharedPreferences.getInt(KEY_REVISION_CARD_LIMIT) ?? 0;
    if (cardLimit > 0 && cards.length > cardLimit) {
      cards = cards.sublist(0, cardLimit);
    }
    _sessionCards = cards;
    _videos = widget.di.masterToVideoMap;
    numCardsToReview = cards.length;
    Analytics.track(
      'revision_started',
      props: {
        'cards_bucket': Analytics.bucket(numCardsToReview),
        'strategy': widget.revisionStrategy.name,
      },
    );
    nextCard();
  }

  @override
  void dispose() {
    _tvRevealFocus.dispose();
    _tvAnswerFocus.dispose();
    nextCardTimer?.cancel();
    super.dispose();
  }

  // The actual dispose function cannot await async functions. Instead, we
  // ban users from swiping back to ensure that if they want to exit revision,
  // they do it by pressing one of our buttons, which ensures this function
  // gets called.
  //
  // Returns true when the reviews are safely persisted (or there was
  // nothing to persist), false when the write threw — the caller is
  // expected to surface that so the user knows their progress wasn't
  // saved and can retry.
  Future<bool> beforePop() async {
    // Single-shot + re-entrancy guard: set the flag before the first await so a
    // concurrent caller — the session-end nextCard() and the user tapping close
    // — doesn't write the reviews twice. Reset on failure so an explicit close
    // can retry. A prior successful write (reviewsWritten still true) is itself
    // a success, so report it as one.
    if (reviewsWritten) return true;
    reviewsWritten = true;
    // Single-shot point (guarded above), so revision_completed fires exactly
    // once per session regardless of how it ends (natural end, out of cards, or
    // the user closing early).
    final reviewed = getCardsReviewed();
    Analytics.track(
      'revision_completed',
      props: {
        'cards_bucket': Analytics.bucket(reviewed),
        'early_exit': reviewed < numCardsToReview,
      },
    );
    try {
      switch (widget.revisionStrategy) {
        case RevisionStrategy.SpacedRepetition:
          // Appended to what is stored now (answers from the person's other
          // devices may have arrived during the session), never written over
          // it.
          await sharing.accountSync.recordAnswers(answers.values.toList());
          break;
        case RevisionStrategy.Random:
          await bumpRandomReviewCounter(answers.length);
          break;
      }
      return true;
    } catch (e) {
      reviewsWritten = false;
      printAndLog("Failed to write reviews on exit: $e");
      return false;
    }
  }

  /// End-of-session finish: persist the reviews and, if that fails,
  /// surface it. The session-end path used to call [beforePop]
  /// fire-and-forget, so a failed write left the user on the summary
  /// screen believing their progress was saved. Now a failure raises a
  /// retry banner on the summary screen and a snack with a retry action.
  /// Called (not awaited) from [nextCard]'s setState; the summary screen
  /// shows immediately and the banner/snack appear once the write
  /// resolves.
  Future<void> _finishSession() async {
    final ok = await beforePop();
    if (!mounted) return;
    if (!ok) {
      setState(() {
        reviewWriteFailed = true;
      });
      _showWriteFailedSnack();
    }
  }

  /// Snack telling the user their progress wasn't saved, with a retry
  /// action.
  void _showWriteFailedSnack() {
    final l = DictLibLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text(l.flashcardsSaveFailed),
        action: SnackBarAction(
          label: l.sharedListLandingTryAgain,
          onPressed: _retryWriteReviews,
        ),
      ),
    );
  }

  /// Retry a failed end-of-session write. Clears the single-shot guard
  /// so [beforePop] actually re-attempts, then re-surfaces success
  /// (clear the banner) or failure (keep it, re-offer the snack).
  Future<void> _retryWriteReviews() async {
    reviewsWritten = false;
    final ok = await beforePop();
    if (!mounted) return;
    setState(() {
      reviewWriteFailed = !ok;
    });
    if (!ok) {
      _showWriteFailedSnack();
    }
  }

  /// Sync the reveal / rating-widget flags to [currentCard]. A card that's
  /// already in [answers] (one we've revealed before, e.g. when stepping
  /// back/forward through the session) reappears revealed with its prior
  /// rating selected; a fresh card starts unrevealed with the default rating.
  /// Keeping this in one place means forward- and back-navigation can't drift
  /// into showing an already-answered card as if it were new (which would make
  /// the reveal tap skip it).
  void _syncRevealStateToCurrentCard() {
    final prior = currentCard == null ? null : answers[currentCard]?.rating;
    currentCardRevealed = prior != null;
    forgotRatingWidgetActive = prior == Rating.Again;
    rememberedRatingWidgetActive = prior != Rating.Again;
  }

  void nextCard() {
    // If the pause after "Forgot" is still running, this step forward (the
    // forward arrow, after stepping back) replaces the one it has pending.
    // Left to fire as well, it would move on a second time, past a card the
    // user hasn't answered.
    nextCardTimer?.cancel();
    nextCardTimer = null;
    setState(() {
      playbackSpeed = getDefaultPlaybackSpeed();
      if (_pos < _sessionCards.length - 1) {
        // On to the next card: a new one, or, if we'd stepped back earlier,
        // one already shown, so back-then-forward returns to exactly where
        // the user was.
        _pos++;
        if (_pos > _furthest) _furthest = _pos;
        currentCard = _sessionCards[_pos];
      } else {
        // That was the last card. Any that were forgotten, and new ones
        // still waiting on a second correct answer, are still due. We choose
        // to cut the user off here rather than bring those round again; they
        // can start a new session to review them if they wish. Accordingly
        // set currentCard to null and store the results.
        currentCard = null;
        _finishSession();
      }
      _syncRevealStateToCurrentCard();
    });
  }

  /// Step back to the card shown before the current one. Wired to the system
  /// back gesture (see [PopScope] in [build]) so an accidental swipe revisits
  /// the previous card instead of dumping the user out of the session. The card
  /// reappears with its earlier answer revealed (if it had one) so they can
  /// review or change it; re-rating overwrites the stored answer.
  void previousCard() {
    if (_pos <= 0) return;
    nextCardTimer?.cancel();
    nextCardTimer = null;
    setState(() {
      playbackSpeed = getDefaultPlaybackSpeed();
      _pos--;
      currentCard = _sessionCards[_pos];
      _syncRevealStateToCurrentCard();
    });
  }

  int getCardsReviewed() {
    return answers.values.length;
  }

  void completeCard(
    DRCard card, {
    Rating rating = Rating.Good,
    DateTime? when,
  }) {
    // Don't ack second taps if a timer is running.
    if (nextCardTimer != null) {
      return;
    }
    DateTime ts;
    if (when != null) {
      ts = when;
    } else {
      ts = DateTime.now();
    }
    Review review = Review(
      master: card.master!,
      combination: card.combination!,
      ts: ts,
      rating: rating,
    );
    Rating? previousRating = answers[card]?.rating;
    bool shouldNavigate = answers.containsKey(card);
    // One answer per card: re-rating a card replaces its earlier answer, and
    // what is in [answers] when the session ends is what gets stored.
    setState(() {
      answers[card] = review;
    });
    if (shouldNavigate) {
      // The pause before advancing exists purely as feedback for "Forgot" in
      // spaced repetition: the button fills red for a moment so the user sees
      // the changed rating registered. Every other press — "Got it!", and the
      // Next button in random mode — proceeds immediately, matching a tap on
      // the card itself.
      final saidForgot =
          review.rating == Rating.Again && previousRating != review.rating;
      if (widget.revisionStrategy == RevisionStrategy.SpacedRepetition &&
          saidForgot) {
        setState(() {
          nextCardTimer = Timer(const Duration(milliseconds: 750), () {
            if (mounted) {
              setState(() {
                nextCard();
                nextCardTimer = null;
              });
            }
          });
        });
      } else {
        nextCard();
      }
    } else {
      currentCardRevealed = true;
    }
  }

  // A rating button. The positive/negative meaning is carried by icon + label
  // + colour together (never colour alone) so it stays accessible.
  Widget getRatingButton(Rating rating, bool active, {bool isNext = false}) {
    final cs = Theme.of(context).colorScheme;
    final l = DictLibLocalizations.of(context)!;

    void onPressed() {
      switch (rating) {
        case Rating.Again:
          forgotRatingWidgetActive = true;
          rememberedRatingWidgetActive = false;
          break;
        case Rating.Good:
          rememberedRatingWidgetActive = true;
          forgotRatingWidgetActive = false;
          break;
        case Rating.Easy:
          break;
        default:
          throw UnsupportedError("Rating $rating not supported yet");
      }
      completeCard(currentCard!, rating: rating);
    }

    if (rating == Rating.Easy && isNext) {
      return FilledButton.icon(
        onPressed: onPressed,
        focusNode: _tvAnswerFocus,
        style: FilledButton.styleFrom(minimumSize: const Size(0, 54)),
        icon: const Icon(Icons.arrow_forward, size: 20),
        label: Text(l.ratingNext),
      );
    }
    // Forgot / Got it! fill when active and outline otherwise, so tapping one
    // visibly selects it (for the brief moment before the next card).
    if (rating == Rating.Again) {
      return active
          ? FilledButton.icon(
              onPressed: onPressed,
              style: FilledButton.styleFrom(
                backgroundColor: cs.error,
                foregroundColor: cs.onError,
                minimumSize: const Size(0, 54),
              ),
              icon: const Icon(Icons.close, size: 20),
              label: Text(l.ratingForgot),
            )
          : OutlinedButton.icon(
              onPressed: onPressed,
              style: OutlinedButton.styleFrom(
                foregroundColor: cs.error,
                side: BorderSide(color: cs.error, width: 1.5),
                minimumSize: const Size(0, 54),
              ),
              icon: const Icon(Icons.close, size: 20),
              label: Text(l.ratingForgot),
            );
    }
    // Rating.Good — the positive action.
    return active
        ? FilledButton.icon(
            onPressed: onPressed,
            focusNode: _tvAnswerFocus,
            style: FilledButton.styleFrom(
              backgroundColor: cs.tertiary,
              foregroundColor: cs.onTertiary,
              minimumSize: const Size(0, 54),
            ),
            icon: const Icon(Icons.check, size: 20),
            label: Text(l.ratingGotIt),
          )
        : OutlinedButton.icon(
            onPressed: onPressed,
            focusNode: _tvAnswerFocus,
            style: OutlinedButton.styleFrom(
              foregroundColor: cs.tertiary,
              side: BorderSide(color: cs.tertiary, width: 1.5),
              minimumSize: const Size(0, 54),
            ),
            icon: const Icon(Icons.check, size: 20),
            label: Text(l.ratingGotIt),
          );
  }

  /// The single "reveal the answer" call to action shown before a card is
  /// flipped. Shared by the vertical and horizontal layouts.
  Widget _revealButton() {
    final l = DictLibLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          key: const ValueKey("revealButton"),
          focusNode: _tvRevealFocus,
          onPressed: () => completeCard(currentCard!, rating: Rating.Good),
          style: FilledButton.styleFrom(minimumSize: const Size(0, 54)),
          icon: const Icon(Icons.visibility_outlined, size: 20),
          label: Text(l.tapToReveal),
        ),
      ),
    );
  }

  Widget buildFlashcardWidget(
    DRCard card,
    ResolvedSavedVideo resolved,
    String word, {
    required bool wordToSign,
    required bool revealed,
  }) {
    final l = DictLibLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    var shouldUseHorizontalDisplay = getShouldUseHorizontalLayout(context);

    // Render exactly the saved video the master represents — not every video of
    // the sub-entry. The per-video-revision model means each card is one
    // specific video the user chose to save.
    //
    // Tapping the video expands it over a dimmed backdrop — even while it's the
    // unrevealed "what does this sign mean?" video. Handled inside
    // VideoPlayerScreen (expandOnTap), so the inline tile pauses + hides while
    // expanded rather than a second player running. It's a nested gesture
    // target, so a tap on the video expands it while a tap elsewhere on the
    // card reveals; .jpg recordings are skipped automatically.
    final Widget tappableVideo = VideoPlayerScreen(
      mediaLinks: [resolved.videoUrl],
      fallbackAspectRatio: widget.config.videoAspectRatio,
      key: Key(resolved.videoUrl),
      expandOnTap: true,
    );

    Widget topWidget;
    if (wordToSign) {
      if (revealed) {
        topWidget = tappableVideo;
      } else {
        double top = shouldUseHorizontalDisplay ? 100 : 120;
        topWidget = Container(
          padding: EdgeInsets.only(top: top, bottom: 70),
          child: Text(
            l.studyPromptWordToSign,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20),
          ),
        );
      }
    } else {
      topWidget = tappableVideo;
    }

    Widget bottomWidget = Text(
      wordToSign || revealed ? word : l.studyPromptSignToWord,
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 20),
    );

    if (isAndroidTv && _tvFocusedFor != (card, revealed)) {
      _tvFocusedFor = (card, revealed);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        (revealed ? _tvAnswerFocus : _tvRevealFocus).requestFocus();
      });
    }

    Widget? ratingButtonsRow;
    if (revealed) {
      switch (widget.revisionStrategy) {
        case RevisionStrategy.SpacedRepetition:
          ratingButtonsRow = Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: KeyedSubtree(
                    key: const ValueKey("ratingButton.forgot"),
                    child: getRatingButton(
                      Rating.Again,
                      forgotRatingWidgetActive,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: KeyedSubtree(
                    key: const ValueKey("ratingButton.gotIt"),
                    child: getRatingButton(
                      Rating.Good,
                      rememberedRatingWidgetActive,
                    ),
                  ),
                ),
              ],
            ),
          );
          break;
        case RevisionStrategy.Random:
          ratingButtonsRow = Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: KeyedSubtree(
                    key: const ValueKey("ratingButton.next"),
                    child: getRatingButton(
                      Rating.Easy,
                      forgotRatingWidgetActive,
                      isNext: true,
                    ),
                  ),
                ),
              ],
            ),
          );
          break;
      }
    }

    List<Widget> openDictionaryEntryWidgets = [
      const Padding(padding: EdgeInsets.only(top: 24)),
      TextButton(
        onPressed: () =>
            widget.config.navigateToEntryPage(context, resolved.entry, true),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l.openDictionaryEntry,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.arrow_forward, size: 16),
          ],
        ),
      ),
    ];

    // The region line, flanked by plain (no-fill) back/forward arrows that are
    // absolutely positioned on either side. Back goes to the previous card;
    // forward only lights up once you've stepped back and there's a later card
    // to return to. Shown in both states so navigation is always available; the
    // region itself stays hidden until the card is revealed.
    Widget navArrow(bool forward) {
      final enabled = forward ? _pos < _furthest : _pos > 0;
      // An InkWell with a tap handler even when disabled (rather than an
      // IconButton) so the tap is ALWAYS consumed here — nav when enabled, a
      // no-op when disabled — and never falls through to the card's
      // reveal/proceed gesture. Focusable only when enabled, so a TV remote
      // can step between cards. The padding gives a comfortable hit area
      // around the small chevron.
      return InkWell(
        customBorder: const CircleBorder(),
        // No ripple, so touch looks exactly as it did with a GestureDetector.
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
        canRequestFocus: enabled,
        onTap: enabled ? (forward ? nextCard : previousCard) : () {},
        child: Tooltip(
          message: forward ? l.revisionNextCard : l.revisionPreviousCard,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Icon(
              forward ? Icons.chevron_right : Icons.chevron_left,
              size: 30,
              color: enabled
                  ? cs.onSurfaceVariant
                  : cs.onSurfaceVariant.withValues(alpha: 0.25),
            ),
          ),
        ),
      );
    }

    Widget regionWithArrows = SizedBox(
      height: widget.config.regionRowHeight,
      child: Stack(
        children: [
          Positioned.fill(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 52),
                child: widget.config.buildRegionInfo(
                  context,
                  resolved,
                  shouldUseHorizontalDisplay,
                  revealed,
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Center(child: navArrow(false)),
          ),
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: Center(child: navArrow(true)),
          ),
        ],
      ),
    );

    // Before the answer is shown, a tap anywhere reveals it; afterwards a tap
    // anywhere proceeds to the next card, keeping whatever rating is recorded
    // (the default "got it", or a previous answer when revisiting — it doesn't
    // override it). The video and the nav arrows are nested gesture targets, so
    // they keep their own behaviour. A pending "forgot" feedback timer
    // suppresses taps so we don't double-advance.
    void onCardTap() {
      if (nextCardTimer != null) return;
      if (!revealed) {
        completeCard(currentCard!, rating: Rating.Good);
      } else {
        nextCard();
      }
    }

    if (!shouldUseHorizontalDisplay) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onCardTap,
        child: SizedBox.expand(
          // Centred at the shared readable measure on tablets (the card and
          // its controls otherwise stretch edge to edge); no-op on phones.
          child: constrainContentWidth(
            context,
            Column(
              mainAxisAlignment: MainAxisAlignment.start,
              mainAxisSize: MainAxisSize.max,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                topWidget,
                const SizedBox(height: 28),
                bottomWidget,
                if (revealed) ...openDictionaryEntryWidgets,
                Expanded(child: Container()),
                const Padding(padding: EdgeInsets.only(bottom: 10)),
                if (revealed) ratingButtonsRow! else _revealButton(),
                regionWithArrows,
                const Padding(padding: EdgeInsets.only(bottom: 28)),
              ],
            ),
          ),
        ),
      );
    } else {
      // Mirror the word page's (verified) horizontal layout: give the video a
      // bounded half via Expanded + Center — Expanded hands the player a
      // definite width instead of letting it fight its own landscape sizing,
      // which is what left the right side blank and the frame missing while the
      // video loaded — and put the prompt, controls and nav arrows in the other
      // half.
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onCardTap,
        child: SafeArea(
          child: Row(
            children: [
              Expanded(flex: 5, child: Center(child: topWidget)),
              Expanded(
                flex: 4,
                // Cap the control column at a button-friendly measure: on a
                // TV / landscape tablet this half-pane is enormous and the
                // reveal/rating buttons would otherwise span all of it. A
                // phone's landscape half is narrower than the cap already.
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        bottomWidget,
                        if (revealed) ...openDictionaryEntryWidgets,
                        const SizedBox(height: 22),
                        if (revealed) ratingButtonsRow! else _revealButton(),
                        regionWithArrows,
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  Widget buildSummaryWidget() {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final l = DictLibLocalizations.of(context)!;
    int numCardsRemembered = answers.values
        .where((e) => e.rating == Rating.Good)
        .length;
    int numCardsForgotten = answers.values
        .where((e) => e.rating == Rating.Again)
        .length;
    int totalAnswers = answers.length;
    double rememberRate = totalAnswers == 0
        ? 0
        : numCardsRemembered / totalAnswers;

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
      children: [
        // Persisting the session's reviews failed. Make it unmissable on
        // the summary screen (alongside the transient snack) and offer an
        // inline retry so the user can save their progress without losing
        // the session.
        if (reviewWriteFailed) ...[
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
            decoration: BoxDecoration(
              color: cs.errorContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l.flashcardsSaveFailed,
                    style: TextStyle(color: cs.onErrorContainer),
                  ),
                ),
                TextButton(
                  onPressed: _retryWriteReviews,
                  child: Text(l.sharedListLandingTryAgain),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
        Text(
          l.sessionComplete.toUpperCase(),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.6,
            color: cs.primary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          l.sessionCompleteHeadline(totalAnswers),
          textAlign: TextAlign.center,
          style: tt.displaySmall?.copyWith(fontSize: 28),
        ),
        // How it went, for spaced repetition only. Random revision never
        // asks whether a card was remembered (its one button is "Next"), so
        // it has no tally to show, and a success rate worked out from its
        // answers came to 0% for anyone who used that button.
        if (widget.revisionStrategy == RevisionStrategy.SpacedRepetition) ...[
          const SizedBox(height: 26),
          Center(
            child: HearthRing(
              percent: rememberRate,
              size: 140,
              centerLabel: l.summarySuccess,
            ),
          ),
          const SizedBox(height: 28),
          Row(
            children: [
              Expanded(
                child: HearthStatTile(
                  value: "$totalAnswers",
                  label: l.summaryCards,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: HearthStatTile(
                  value: "$numCardsRemembered",
                  label: l.summaryGotIt,
                  valueColor: cs.tertiary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: HearthStatTile(
                  value: "$numCardsForgotten",
                  label: l.summaryForgot,
                  valueColor: cs.error,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l = DictLibLocalizations.of(context)!;
    Widget body;
    String appBarTitle;
    List<Widget> actions = [];
    if (currentCard != null) {
      DRCard card = currentCard!;

      final resolved = _videos[card.master];
      if (resolved == null) {
        // Defensive: we couldn't resolve the saved video for this card (e.g.
        // the dictionary data changed mid-session). Skip to the next card
        // rather than crash.
        printAndLog(
          "No resolved video for master ${card.master}; skipping card",
        );
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          showSnack(context, l.flashcardsCardUnavailable);
          nextCard();
        });
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }

      String word;
      bool wordToSign = card.back![0] == VIDEO_LINKS_MARKER;
      if (wordToSign) {
        // Word on front, video on back.
        word = card.front![0];
      } else {
        word = card.back![0];
      }

      bool videoIsShowing = currentCardRevealed || !wordToSign;

      body = Center(
        child: InheritedPlaybackSpeed(
          playbackSpeed: playbackSpeed,
          child: buildFlashcardWidget(
            card,
            resolved,
            word,
            wordToSign: wordToSign,
            revealed: currentCardRevealed,
          ),
        ),
      );
      // 1-based position of the current card in the session sequence. Using the
      // position (rather than the answered-count) keeps the counter correct when
      // the user steps back to revisit an earlier card.
      appBarTitle = "${_pos + 1} / $numCardsToReview";
      // App-specific app-bar extras (e.g. Auslan's Signbank link) before the
      // shared playback-speed dropdown; SLSL adds none.
      actions.addAll(
        widget.config.buildExtraAppBarActions?.call(
              context,
              word: word,
              resolved: resolved,
              revealed: currentCardRevealed,
            ) ??
            const <Widget>[],
      );
      actions.add(
        getPlaybackSpeedDropdownWidget(
          (p) {
            setState(() {
              playbackSpeed = p!;
            });
            showSnack(
              context,
              "${DictLibLocalizations.of(context)!.setPlaybackSpeedTo} ${getPlaybackSpeedString(playbackSpeed)}",
              duration: const Duration(milliseconds: 1000),
            );
          },
          enabled: videoIsShowing,
          current: playbackSpeed,
        ),
      );
    } else {
      body = buildSummaryWidget();
      appBarTitle = l.revisionSummaryTitle;
    }

    // Swiping back does nothing: card navigation is via the on-screen arrows,
    // and leaving revision is via the close (×) button. Disabling the gesture
    // avoids an accidental swipe dumping the user out mid-session. Mid-session
    // the × ends the session early and shows the summary (the answers so far
    // are persisted either way, so this matches finishing start-to-finish);
    // from the summary it pops back to the landing page via Navigator.pop(),
    // which isn't gated by canPop.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {},
      child: Scaffold(
        appBar: AppBar(
          centerTitle: true,
          title: Text(appBarTitle, textAlign: TextAlign.center),
          actions: buildActionButtons(actions),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () async {
              // Mid-session the × ends the session early. The answers so
              // far are persisted just the same, so show the summary
              // first — identical to finishing start-to-finish — rather
              // than dropping back to the landing page. _finishSession()
              // writes the reviews (and raises the retry banner on
              // failure), exactly as the normal session-end path does.
              // With nothing answered yet there's nothing to summarise, so
              // fall through and just leave.
              if (currentCard != null && answers.isNotEmpty) {
                nextCardTimer?.cancel();
                nextCardTimer = null;
                setState(() {
                  currentCard = null;
                });
                _finishSession();
                return;
              }
              final navigator = Navigator.of(context);
              final ok = await beforePop();
              if (!mounted) return;
              if (ok) {
                navigator.pop();
              } else {
                // The write failed. Don't drop the user out silently —
                // beforePop already reset its single-shot guard, so
                // surface the failure and let them retry (re-tapping
                // close, or the snack action, re-attempts the write).
                setState(() {
                  reviewWriteFailed = true;
                });
                _showWriteFailedSnack();
              }
            },
          ),
          bottom: currentCard == null
              ? null
              : PreferredSize(
                  preferredSize: const Size.fromHeight(3),
                  // Track the current card's position so the bar matches the
                  // "x / N" counter and doesn't jump on reveal (revealing
                  // adds a default answer, which the position is immune to)
                  // or when the user steps back to an earlier card.
                  child: Builder(
                    builder: (context) {
                      final cardsCompleted = _pos;
                      return LinearProgressIndicator(
                        value: numCardsToReview > 0
                            ? (cardsCompleted / numCardsToReview).clamp(
                                0.0,
                                1.0,
                              )
                            : null,
                        minHeight: 3,
                        backgroundColor: cs.surfaceContainerHighest,
                      );
                    },
                  ),
                ),
        ),
        body: body,
      ),
    );
  }
}
