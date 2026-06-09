import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:dictionarylib/common.dart';
import 'package:dictionarylib/globals.dart';
import 'package:dictionarylib/hearth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dictionarylib/dictionarylib.dart' show DictLibLocalizations;

enum PlaybackSpeed {
  PointFiveZero,
  PointSevenFive,
  One,
  OneTwoFive,
  OneFiveZero,
}

String getPlaybackSpeedString(PlaybackSpeed playbackSpeed) {
  switch (playbackSpeed) {
    case PlaybackSpeed.PointFiveZero:
      return "0.5x";
    case PlaybackSpeed.PointSevenFive:
      return "0.75x";
    case PlaybackSpeed.One:
      return "1x";
    case PlaybackSpeed.OneTwoFive:
      return "1.25x";
    case PlaybackSpeed.OneFiveZero:
      return "1.5x";
  }
}

double getDoubleFromPlaybackSpeed(PlaybackSpeed playbackSpeed) {
  switch (playbackSpeed) {
    case PlaybackSpeed.One:
      return 1.0;
    case PlaybackSpeed.PointSevenFive:
      return 0.75;
    case PlaybackSpeed.PointFiveZero:
      return 0.5;
    case PlaybackSpeed.OneFiveZero:
      return 1.5;
    case PlaybackSpeed.OneTwoFive:
      return 1.25;
  }
}

Widget getPlaybackSpeedDropdownWidget(void Function(PlaybackSpeed?) onChanged,
    {bool enabled = true, Color? disabledColor, PlaybackSpeed? current}) {
  return Builder(builder: (context) {
    return IconButton(
      icon: Icon(Icons.slow_motion_video,
          color: enabled ? null : disabledColor),
      tooltip: DictLibLocalizations.of(context)!.playbackSpeedTitle,
      onPressed: enabled
          ? () => _showPlaybackSpeedSheet(context, onChanged, current)
          : null,
    );
  });
}

/// A bottom sheet listing the playback speeds, with the current one ticked.
Future<void> _showPlaybackSpeedSheet(
    BuildContext context,
    void Function(PlaybackSpeed?) onChanged,
    PlaybackSpeed? current) async {
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 2, 20, 8),
                child: Text(DictLibLocalizations.of(ctx)!.playbackSpeedTitle,
                    style: Theme.of(ctx).textTheme.titleLarge),
              ),
              for (final s in PlaybackSpeed.values)
                ListTile(
                  title: Text(
                    s == PlaybackSpeed.One
                        ? "${getPlaybackSpeedString(s)}  ·  ${DictLibLocalizations.of(ctx)!.playbackSpeedNormal}"
                        : getPlaybackSpeedString(s),
                    style: TextStyle(
                        fontWeight:
                            s == current ? FontWeight.w800 : FontWeight.w500,
                        color: s == current ? cs.primary : cs.onSurface),
                  ),
                  trailing: s == current
                      ? Icon(Icons.check, color: cs.primary)
                      : null,
                  onTap: () {
                    Navigator.of(ctx).pop();
                    onChanged(s);
                  },
                ),
            ],
          ),
        ),
      );
    },
  );
}

class InheritedPlaybackSpeed extends InheritedWidget {
  const InheritedPlaybackSpeed(
      {super.key, required this.child, required this.playbackSpeed})
      : super(child: child);

  final PlaybackSpeed playbackSpeed;
  @override
  final Widget child;

  static InheritedPlaybackSpeed? of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<InheritedPlaybackSpeed>();
  }

  @override
  bool updateShouldNotify(InheritedPlaybackSpeed oldWidget) {
    return oldWidget.playbackSpeed != playbackSpeed;
  }
}

/// Data class to hold a Player and its associated VideoController.
class _PlayerData {
  final Player player;
  final VideoController controller;
  double? aspectRatio;
  bool isReady = false;
  String? error;
  // Track whether video has played at least once - used to avoid showing
  // loading spinner on loop.
  bool hasPlayedOnce = false;
  // Track if initial play/pause has been set to avoid calling on every rebuild.
  bool initialPlaybackSet = false;
  StreamSubscription? _playingSubscription;

  _PlayerData({required this.player, required this.controller});

  void dispose() {
    _playingSubscription?.cancel();
    player.dispose();
  }
}

class VideoPlayerScreen extends StatefulWidget {
  const VideoPlayerScreen({
    super.key,
    required this.mediaLinks,
    required this.fallbackAspectRatio,
    this.initialPage = 0,
    this.onPageChanged,
    this.expandOnTap = false,
  });

  final List<String> mediaLinks;
  final double fallbackAspectRatio;

  /// When true, tapping a (non-image) video opens it expanded over a dimmed
  /// backdrop via [showExpandedVideo]. The inline tile is paused and hidden
  /// while it's expanded, so the video appears to move into the overlay rather
  /// than playing in two places at once.
  final bool expandOnTap;

  /// Video index to land on when the carousel first builds. Useful for
  /// jump-to-saved-video flows from the list view.
  final int initialPage;

  /// Notified each time the carousel settles on a new video.
  /// Used by callers that render UI keyed to the currently-visible
  /// video (e.g. the per-video bookmark button on the entry page).
  final void Function(int)? onPageChanged;

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen>
    with WidgetsBindingObserver {
  Map<int, _PlayerData> players = {};

  CarouselSliderController? carouselController;

  int currentPage = 0;

  /// The carousel index currently shown expanded (see [expandOnTap]); its
  /// inline tile is hidden while the overlay is open. Null when nothing is
  /// expanded.
  int? _expandedIndex;

  /// The playback rate currently applied to the players, mirrored from the
  /// inherited [InheritedPlaybackSpeed] in [didChangeDependencies]. Stored so
  /// the playing-stream listener can re-apply it (outside build, with no
  /// BuildContext) after media_kit resets the rate when playback starts.
  double _playbackRate = 1.0;

  @override
  void initState() {
    super.initState();
    // Observe app lifecycle so we can resume playback after the app is
    // backgrounded (e.g. the user opened an external link and came back).
    WidgetsBinding.instance.addObserver(this);
    // Make carousel slider controller.
    carouselController = CarouselSliderController();
    // Honour the caller-supplied initial page so jump-to-video lands on
    // the right slide on first build. Clamp to a valid index so a stale
    // saved video URL whose sub-entry has fewer videos than expected
    // doesn't render an empty carousel.
    if (widget.initialPage > 0 &&
        widget.initialPage < widget.mediaLinks.length) {
      currentPage = widget.initialPage;
    }

    // Create players and controllers immediately (synchronously) so that
    // the Video widgets can be in the tree when we open the media.
    // This is important for Android where the texture surface needs to be
    // set up before opening media.
    for (int idx = 0; idx < widget.mediaLinks.length; idx++) {
      final mediaLink = widget.mediaLinks[idx];
      // Skip non-video files
      if (mediaLink.endsWith(".jpg")) continue;

      // Create Player and VideoController following media-kit README:
      // https://github.com/media-kit/media-kit
      final player = Player();
      final controller = VideoController(player);
      players[idx] = _PlayerData(player: player, controller: controller);

      // Open the media asynchronously after the widget is in the tree.
      // Use addPostFrameCallback to ensure Video widget is mounted first.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _openMedia(mediaLink, idx);
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // React to the inherited playback speed (set/changed from the entry page).
    // Apply it to every ready player now; players that become ready later pick
    // it up when they start playing (see the playing-stream listener), which
    // also re-applies after the open/play rate reset media_kit can do.
    final speed = InheritedPlaybackSpeed.of(context);
    if (speed != null) {
      _playbackRate = getDoubleFromPlaybackSpeed(speed.playbackSpeed);
      for (final pd in players.values) {
        if (pd.isReady) pd.player.setRate(_playbackRate);
      }
    }
  }

  Future<void> _openMedia(String mediaLink, int idx) async {
    if (!mounted) return;

    final playerData = players[idx];
    if (playerData == null) return;

    bool shouldCache = sharedPreferences.getBool(KEY_SHOULD_CACHE) ?? true;

    try {
      // Don't cache .bak files.
      if (mediaLink.endsWith(".bak")) {
        shouldCache = false;
      }
      bool shouldDownloadDirectly = !shouldCache || kIsWeb;

      String mediaSource = mediaLink;

      if (shouldCache) {
        try {
          printAndLog(
              "Attempting to pull video $mediaLink from the cache / internet");
          File file = await myCacheManager.getSingleFile(mediaLink);
          mediaSource = file.path;
        } catch (e) {
          printAndLog(
              "Failed to use cache for $mediaLink despite caching being enabled, just trying to download directly: $e");
          shouldDownloadDirectly = true;
        }
      }

      if (shouldDownloadDirectly) {
        if (!shouldCache) {
          printAndLog(
              "Caching is disabled, pulling $mediaLink from the network");
        }
        if (mediaLink.endsWith(".bak")) {
          printAndLog("Building video controller with custom .bak behaviour");
          HttpClient httpClient = HttpClient();
          var request = await httpClient.getUrl(Uri.parse(mediaLink));
          var response = await request.close();
          if (response.statusCode != 200) {
            throw "Failed to load $mediaLink with custom .bak behaviour: $response";
          }
          String dir = (await getTemporaryDirectory()).path;
          var bytes = await consolidateHttpClientResponseBytes(response);
          String newFileName = mediaLink.split("/").last.replaceAll(".bak", "");
          File file = File("$dir/$newFileName");
          await file.writeAsBytes(bytes);
          mediaSource = file.path;
        } else {
          mediaSource = mediaLink;
        }
      }

      // Disable audio completely to prevent interrupting other audio (like music).
      // On native, disabling the audio track entirely prevents audio focus
      // acquisition (setVolume(0) alone still acquires it). On web, media_kit
      // only supports AudioTrack.uri so we fall back to muting the volume.
      if (kIsWeb) {
        await playerData.player.setVolume(0);
      } else {
        await playerData.player.setAudioTrack(AudioTrack.no());
      }

      // Use PlaylistMode.loop instead of PlaylistMode.single for smoother loops.
      // PlaylistMode.single can cause stuttering/freezing when the video loops.
      // PlaylistMode.loop is designed for seamless playlist transitions and handles
      // single-video looping more smoothly.
      await playerData.player.setPlaylistMode(PlaylistMode.loop);

      // Open the media.
      Media media;
      if (mediaSource.startsWith('/') || mediaSource.startsWith('file://')) {
        media = Media(
            'file://$mediaSource'.replaceAll('file://file://', 'file://'));
      } else {
        media = Media(mediaSource);
      }
      await playerData.player.open(media, play: false);

      // Wait for the video to be ready and get aspect ratio.
      await playerData.player.stream.width.first.timeout(
        const Duration(seconds: 10),
        onTimeout: () => null,
      );
      final width = playerData.player.state.width;
      final height = playerData.player.state.height;
      if (width != null && height != null && height > 0) {
        playerData.aspectRatio = width / height;
      }

      // Listen to the playing stream to track when video first starts playing.
      // This is used to avoid showing loading spinner on loop.
      playerData._playingSubscription =
          playerData.player.stream.playing.listen((isPlaying) {
        if (isPlaying) {
          // media_kit can reset the rate to 1.0 when playback (re)starts, so
          // re-apply the desired speed every time it begins playing. This is
          // what makes the speed stick on initial load without the old timed
          // retries.
          playerData.player.setRate(_playbackRate);
        }
        if (isPlaying && !playerData.hasPlayedOnce) {
          playerData.hasPlayedOnce = true;
          // Trigger rebuild so the controls get the updated hasPlayedOnce value.
          if (mounted) {
            setState(() {});
          }
        }
      });

      if (mounted) {
        setState(() {
          playerData.isReady = true;
        });
      }
    } catch (e) {
      printAndLog("Error loading video: $e");
      if (mounted) {
        setState(() {
          playerData.error = "$e";
        });
      }
    }
  }

  Widget createErrorWidget(Object error, String mediaLink) {
    Column out;
    if ("$error".contains("Socket")) {
      out = Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            DictLibLocalizations.of(context)!.videoOfflineError,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14),
          ),
          const Padding(padding: EdgeInsets.only(top: 10)),
          Text(
            "$mediaLink: $error",
            style: const TextStyle(fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      );
    } else {
      out = Column(children: [
        Text(
          "${DictLibLocalizations.of(context)!.unexpectedErrorLoadingVideo} $mediaLink: $error",
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12),
        )
      ]);
    }
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Center(child: out),
    );
  }

  void onPageChanged(BuildContext context, int newPage) {
    setState(() {
      for (var playerData in players.values) {
        playerData.player.pause();
      }
      currentPage = newPage;
      players[currentPage]?.player.play();
    });
    widget.onPageChanged?.call(newPage);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // The OS pauses media playback when the app is backgrounded (e.g. when the
    // user follows an external link). On return, resume the visible video so it
    // never stays stuck paused. Players that aren't ready yet auto-play once
    // they load (see the build-time initial play/pause), so guard on isReady.
    if (state == AppLifecycleState.resumed) {
      final pd = players[currentPage];
      if (pd != null && pd.isReady) pd.player.play();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Ensure disposing of the Players to free up resources.
    for (var playerData in players.values) {
      playerData.dispose();
    }
    super.dispose();
  }

  /// Pause + hide the inline tile at [idx], show its video expanded over a
  /// dimmed backdrop, then restore the tile (resuming playback if it had been
  /// playing). Doing the pause/hide here — rather than spinning a second player
  /// in the overlay alongside the inline one — means the video appears to move
  /// into the overlay instead of two copies playing at once.
  Future<void> _expand(int idx) async {
    final pd = players[idx];
    final wasPlaying = pd?.player.state.playing ?? false;
    await pd?.player.pause();
    if (!mounted) return;
    setState(() => _expandedIndex = idx);
    await showExpandedVideo(context, widget.mediaLinks[idx]);
    if (!mounted) return;
    setState(() => _expandedIndex = null);
    if (wasPlaying) await pd?.player.play();
  }

  @override
  Widget build(BuildContext context) {
    // Get height of screen to ensure that the video only takes up
    // a certain proportion of it.
    List<Widget> items = [];
    for (int idx = 0; idx < widget.mediaLinks.length; idx++) {
      var mediaLink = widget.mediaLinks[idx];
      Widget item;
      if (mediaLink.endsWith(".jpg")) {
        item = Padding(
            padding: const EdgeInsets.all(10),
            child: CachedNetworkImage(
                imageUrl: mediaLink,
                cacheManager: myCacheManager,
                // Disable fade animation so spinner just disappears
                fadeInDuration: Duration.zero,
                fadeOutDuration: Duration.zero,
                progressIndicatorBuilder: (context, url, downloadProgress) =>
                    Padding(
                        padding: const EdgeInsets.only(top: 20),
                        child: SizedBox(
                          height: 100.0,
                          width: 100.0,
                          child: Center(
                            child: CircularProgressIndicator(
                              value: downloadProgress.progress,
                            ),
                          ),
                        )),
                errorWidget: (context, url, error) =>
                    createErrorWidget(error, mediaLink)));
      } else {
        // Build video widget - the playerData should exist since we create it synchronously
        final playerData = players[idx];
        if (playerData == null) {
          item = const Padding(
              padding: EdgeInsets.only(top: 20),
              child: Center(child: CircularProgressIndicator()));
        } else if (playerData.error != null) {
          item = createErrorWidget(playerData.error!, mediaLink);
        } else {
          // Set the initial play/pause state once per player. Playback speed is
          // applied via didChangeDependencies (live changes) and the
          // playing-stream listener (the open/play rate reset) — not here — so
          // there's no per-build work or timed retries.
          if (playerData.isReady && !playerData.initialPlaybackSet) {
            playerData.initialPlaybackSet = true;
            if (idx == currentPage) {
              playerData.player.play();
            } else {
              playerData.player.pause();
            }
          }

          // Build the Video widget immediately so the texture surface is available.
          // This is crucial for Android - the Video widget must be in the tree
          // when player.open() is called.
          item = LayoutBuilder(
            builder: (context, constraints) {
              final videoAspectRatio =
                  playerData.aspectRatio ?? widget.fallbackAspectRatio;
              // Reserve room for HearthVideoFrame's padding (5px each side) so
              // the framed card fits within the carousel slide without
              // overflowing.
              const frameTotal = 10.0;
              // Small breathing room above and below the framed video (room for
              // the drop shadow). Kept small so the video stays wide — landscape
              // sign videos are otherwise height-capped here and end up much
              // narrower than the full content width.
              const verticalMargin = 8.0;
              double videoWidth = constraints.maxWidth - frameTotal;
              double videoHeight = videoWidth / videoAspectRatio;
              if (constraints.maxHeight.isFinite &&
                  videoHeight >
                      constraints.maxHeight - verticalMargin * 2 - frameTotal) {
                videoHeight =
                    constraints.maxHeight - verticalMargin * 2 - frameTotal;
                videoWidth = videoHeight * videoAspectRatio;
              }
              return Container(
                padding: const EdgeInsets.symmetric(vertical: verticalMargin),
                alignment: Alignment.center,
                // The signing video framed as the hero (shared Hearth widget:
                // soft surface card, subtle border + warm shadow, rounded
                // video inside).
                child: HearthVideoFrame(
                  child: SizedBox(
                    width: videoWidth,
                    height: videoHeight,
                    child: Video(
                      controller: playerData.controller,
                      // Loading indicator on initial load only, not on loop.
                      controls: (state) => getLoadingVideoControls(
                          state, playerData.hasPlayedOnce),
                      fit: BoxFit.fill,
                    ),
                  ),
                ),
              );
            },
          );
        }
      }
      // Tap a (non-image) video to open it expanded over a dimmed backdrop.
      if (widget.expandOnTap && !mediaLink.endsWith(".jpg")) {
        item = GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _expand(idx),
          child: item,
        );
      }
      // Hide this tile while it's the one being shown expanded, so the video
      // reads as having moved into the overlay rather than playing twice. Kept
      // in the tree (Opacity, not removed) so its player isn't torn down.
      item = Opacity(opacity: idx == _expandedIndex ? 0.0 : 1.0, child: item);
      items.add(item);
    }
    double aspectRatio;
    if (players.containsKey(currentPage) &&
        players[currentPage]!.aspectRatio != null) {
      aspectRatio = players[currentPage]!.aspectRatio!;
    } else {
      // This is a fallback value for if the video hasn't loaded yet.
      aspectRatio = widget.fallbackAspectRatio;
    }
    var slider = CarouselSlider(
      carouselController: carouselController,
      items: items,
      options: CarouselOptions(
        aspectRatio: aspectRatio,
        autoPlay: false,
        // A higher fraction lets the centred video take more width, leaving a
        // smaller peek of the adjacent slide on each side — and brings a
        // landscape/square video close to the width of the save button below.
        viewportFraction: 0.94,
        enableInfiniteScroll: false,
        initialPage: currentPage,
        onPageChanged: (index, reason) => onPageChanged(context, index),
        enlargeCenterPage: true,
      ),
    );

    var size = MediaQuery.of(context).size;
    var screenWidth = size.width;
    var screenHeight = size.height;
    var shouldUseHorizontalDisplay = getShouldUseHorizontalLayout(context);
    BoxConstraints boxConstraints;
    if (shouldUseHorizontalDisplay) {
      boxConstraints = BoxConstraints(
          maxWidth: screenWidth * 0.55, maxHeight: screenHeight * 0.67);
    } else {
      boxConstraints = BoxConstraints(maxHeight: screenHeight * 0.46);
    }

    // Ensure that the video doesn't take up the whole screen.
    // This only applies a maximum bound.
    var sliderContainer = Container(
        alignment: Alignment.center,
        child: ConstrainedBox(
          constraints: boxConstraints,
          child: slider,
        ));

    return sliderContainer;
  }
}

/// Show [mediaLink] expanded over the current screen: the video grows to the
/// full screen width, the page behind is heavily dimmed (rather than replaced
/// by an opaque black page), and close + rotate-to-landscape controls are
/// offered. Tapping the dimmed area — or the close button — dismisses it. The
/// video plays muted + looped. Opened by tapping a sign video.
Future<void> showExpandedVideo(BuildContext context, String mediaLink) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    // Heavy dim so the video is the focus while the page stays faintly visible
    // behind it.
    barrierColor: Colors.black.withValues(alpha: 0.82),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (ctx, _, __) => _ExpandedVideoOverlay(mediaLink: mediaLink),
    transitionBuilder: (ctx, anim, _, child) => FadeTransition(
        opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
        child: child),
  );
}

class _ExpandedVideoOverlay extends StatefulWidget {
  final String mediaLink;
  const _ExpandedVideoOverlay({required this.mediaLink});

  @override
  State<_ExpandedVideoOverlay> createState() => _ExpandedVideoOverlayState();
}

class _ExpandedVideoOverlayState extends State<_ExpandedVideoOverlay> {
  late final Player _player;
  late final VideoController _controller;

  // Whether the user tapped rotate to view the video turned a quarter turn.
  //
  // This is a *purely visual* rotation (a [RotatedBox]) — we never call
  // SystemChrome.setPreferredOrientations to rotate the device itself. Forcing
  // the device orientation and then restoring it on close was the source of the
  // "extra rotation on exit" bug: restoring re-evaluates the orientation and
  // flicks the screen to landscape and back. On the iOS Simulator it's
  // unavoidable, because forcing an orientation also dirties the simulator's
  // device-orientation sensor, which the restore then chases.
  //
  // Rotating the *content* instead looks identical on this full-screen black
  // overlay (the status bar is hidden either way), costs nothing to undo, and
  // leaves the screen tracking the real hardware orientation — so closing never
  // triggers a stray rotation, and physically turning the device still rotates
  // the overlay naturally. The manual turn only applies while the device is
  // portrait; in landscape the video already fills the screen upright.
  bool _manualLandscape = false;

  // The video's natural aspect ratio, learned once it's open, so the box can be
  // sized to fill the width rather than letterboxed. 16/9 until then.
  double? _aspectRatio;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _controller = VideoController(_player);
    _open();
  }

  Future<void> _open() async {
    try {
      if (kIsWeb) {
        await _player.setVolume(0);
      } else {
        await _player.setAudioTrack(AudioTrack.no());
      }
      await _player.setPlaylistMode(PlaylistMode.loop);

      String source = widget.mediaLink;
      final shouldCache = sharedPreferences.getBool(KEY_SHOULD_CACHE) ?? true;
      if (shouldCache && !kIsWeb && !widget.mediaLink.endsWith(".bak")) {
        try {
          final file = await myCacheManager.getSingleFile(widget.mediaLink);
          source = file.path;
        } catch (_) {/* fall back to streaming */}
      }
      final media = (source.startsWith('/') || source.startsWith('file://'))
          ? Media('file://$source'.replaceAll('file://file://', 'file://'))
          : Media(source);
      await _player.open(media);

      // Learn the natural aspect ratio so the video fills the width instead of
      // being letterboxed.
      await _player.stream.width.first
          .timeout(const Duration(seconds: 10), onTimeout: () => null);
      final width = _player.state.width;
      final height = _player.state.height;
      if (width != null && height != null && height > 0 && mounted) {
        setState(() => _aspectRatio = width / height);
      }
    } catch (e) {
      printAndLog("Expanded video error: $e");
    }
  }

  void _toggleRotation() =>
      setState(() => _manualLandscape = !_manualLandscape);

  /// Dismiss the overlay. Nothing to restore — the overlay never forces the
  /// device orientation, so the screen is already at the hardware orientation.
  void _close() => Navigator.of(context).pop();

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isPortrait =
        MediaQuery.of(context).orientation == Orientation.portrait;
    // The manual quarter-turn only applies in portrait; in landscape the video
    // already fills the screen the right way up.
    final quarterTurns = (isPortrait && _manualLandscape) ? 1 : 0;

    // The video deliberately ignores the app theme: it plays with white chrome
    // over the dim backdrop in both light and dark mode, like every video
    // player. The Colors.white here are intentional, not theme leaks.
    return Stack(
      children: [
        // Tap the dimmed area around the video to dismiss.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _close,
          ),
        ),
        // The expanded video: filling the screen, sized to its aspect ratio and
        // centred, with the dimmed page showing above and below. Tapping rotate
        // (in portrait) turns it a quarter turn so it fills the screen like a
        // landscape video — a pure visual rotation, no device-orientation change
        // (see [_manualLandscape]).
        Positioned.fill(
          child: RotatedBox(
            quarterTurns: quarterTurns,
            child: Center(
              child: AspectRatio(
                aspectRatio: _aspectRatio ?? 16 / 9,
                child: Video(
                  controller: _controller,
                  fit: BoxFit.contain,
                  controls: (state) => const SizedBox.shrink(),
                ),
              ),
            ),
          ),
        ),
        SafeArea(
          child: Align(
            alignment: Alignment.topLeft,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 28),
              tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              onPressed: _close,
            ),
          ),
        ),
        // Only offer the rotate toggle in portrait — in landscape the video is
        // already full-screen, so the turn would be a no-op.
        if (isPortrait)
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: IconButton(
                icon: const Icon(Icons.screen_rotation,
                    color: Colors.white, size: 26),
                tooltip: DictLibLocalizations.of(context)!.videoRotate,
                onPressed: _toggleRotation,
              ),
            ),
          ),
      ],
    );
  }
}

/// A controls builder that shows a loading indicator on initial load only.
/// The hasPlayedOnce flag prevents the spinner from appearing when the video
/// loops (which can trigger brief buffering states).
Widget getLoadingVideoControls(VideoState state, bool hasPlayedOnce) {
  return StreamBuilder<bool>(
    stream: state.widget.controller.player.stream.buffering,
    initialData: state.widget.controller.player.state.buffering,
    builder: (context, snapshot) {
      final isBuffering = snapshot.data ?? false;
      final width = state.widget.controller.player.state.width;
      final height = state.widget.controller.player.state.height;

      // Only show loading on initial load, not when looping.
      final showLoading =
          !hasPlayedOnce && (isBuffering || width == null || height == null);

      if (showLoading) {
        return const Center(
          child: CircularProgressIndicator(
            color: Colors.white,
          ),
        );
      }
      return const SizedBox.shrink();
    },
  );
}
