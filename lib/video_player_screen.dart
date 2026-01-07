import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:dictionarylib/common.dart';
import 'package:dictionarylib/globals.dart';
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
    {bool enabled = true, Color? disabledColor}) {
  Color? color;
  if (!enabled) {
    color = disabledColor;
  }
  return Align(
      alignment: Alignment.center,
      child: PopupMenuButton<PlaybackSpeed>(
        icon: Icon(
          Icons.slow_motion_video,
          color: color,
        ),
        enabled: enabled,
        itemBuilder: (BuildContext context) {
          return PlaybackSpeed.values.map((PlaybackSpeed value) {
            return PopupMenuItem<PlaybackSpeed>(
              value: value,
              child: Text(getPlaybackSpeedString(value)),
            );
          }).toList();
        },
        onSelected: enabled ? onChanged : null,
      ));
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
  // Track if playback speed retries have been scheduled to avoid scheduling
  // them multiple times on each rebuild.
  bool playbackSpeedRetriesScheduled = false;
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
  const VideoPlayerScreen(
      {super.key, required this.mediaLinks, required this.fallbackAspectRatio});

  final List<String> mediaLinks;
  final double fallbackAspectRatio;

  @override
  _VideoPlayerScreenState createState() => _VideoPlayerScreenState(
      mediaLinks: mediaLinks, fallbackAspectRatio: fallbackAspectRatio);
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  _VideoPlayerScreenState(
      {required this.mediaLinks, required this.fallbackAspectRatio});

  final List<String> mediaLinks;
  final double fallbackAspectRatio;

  Map<int, _PlayerData> players = {};

  CarouselSliderController? carouselController;

  int currentPage = 0;

  @override
  void initState() {
    super.initState();
    // Make carousel slider controller.
    carouselController = CarouselSliderController();

    // Create players and controllers immediately (synchronously) so that
    // the Video widgets can be in the tree when we open the media.
    // This is important for Android where the texture surface needs to be
    // set up before opening media.
    for (int idx = 0; idx < mediaLinks.length; idx++) {
      final mediaLink = mediaLinks[idx];
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
          print("Building video controller with custom .bak behaviour");
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
      // Setting volume to 0 is not enough - it still acquires audio focus.
      // Disabling the audio track entirely prevents audio focus acquisition.
      await playerData.player.setAudioTrack(AudioTrack.no());

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
          const Text(
            "Failed to load video. Please confirm your device is connected to the internet. If it is, the servers may be having issues. This is not an issue with the app itself.",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14),
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
  }

  @override
  void dispose() {
    // Ensure disposing of the Players to free up resources.
    for (var playerData in players.values) {
      playerData.dispose();
    }
    super.dispose();
  }

  void setPlaybackSpeed(BuildContext context, Player player) {
    if (mounted) {
      double playbackSpeedDouble = getDoubleFromPlaybackSpeed(
          InheritedPlaybackSpeed.of(context)!.playbackSpeed);
      player.setRate(playbackSpeedDouble);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Get height of screen to ensure that the video only takes up
    // a certain proportion of it.
    List<Widget> items = [];
    for (int idx = 0; idx < mediaLinks.length; idx++) {
      var mediaLink = mediaLinks[idx];
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
          // Set playback speed here, since we need the context.
          if (playerData.isReady) {
            setPlaybackSpeed(context, playerData.player);

            // Schedule delayed retries only once per player to avoid
            // accumulating callbacks on each rebuild.
            if (!playerData.playbackSpeedRetriesScheduled) {
              playerData.playbackSpeedRetriesScheduled = true;
              // Set it again repeatedly since there can be a weird race.
              // Check mounted before each call to avoid issues after dispose.
              Future.delayed(const Duration(milliseconds: 100), () {
                if (mounted) setPlaybackSpeed(context, playerData.player);
              });
              Future.delayed(const Duration(milliseconds: 250), () {
                if (mounted) setPlaybackSpeed(context, playerData.player);
              });
              Future.delayed(const Duration(milliseconds: 500), () {
                if (mounted) setPlaybackSpeed(context, playerData.player);
              });
              Future.delayed(const Duration(milliseconds: 1000), () {
                if (mounted) setPlaybackSpeed(context, playerData.player);
              });
            }

            // Set initial play/pause state only once per player to avoid
            // calling play/pause on every rebuild.
            if (!playerData.initialPlaybackSet) {
              playerData.initialPlaybackSet = true;
              if (idx == currentPage) {
                playerData.player.play();
              } else {
                playerData.player.pause();
              }
            }
          }

          // Build the Video widget immediately so the texture surface is available.
          // This is crucial for Android - the Video widget must be in the tree
          // when player.open() is called.
          item = LayoutBuilder(
            builder: (context, constraints) {
              final videoAspectRatio =
                  playerData.aspectRatio ?? fallbackAspectRatio;
              // Calculate dimensions based on available width
              double videoWidth = constraints.maxWidth;
              double videoHeight = videoWidth / videoAspectRatio;
              // If height exceeds available space, constrain by height instead
              if (constraints.maxHeight.isFinite &&
                  videoHeight > constraints.maxHeight - 15) {
                videoHeight = constraints.maxHeight - 15;
                videoWidth = videoHeight * videoAspectRatio;
              }
              return Container(
                padding: const EdgeInsets.only(top: 15),
                child: SizedBox(
                  width: videoWidth,
                  height: videoHeight,
                  child: Video(
                    controller: playerData.controller,
                    // Show loading indicator only on initial load, not on loop.
                    controls: (state) => getLoadingVideoControls(
                        state, playerData.hasPlayedOnce),
                    // Use fill since the SizedBox is already sized to match
                    // the video's aspect ratio - no need for letterboxing
                    fit: BoxFit.fill,
                  ),
                ),
              );
            },
          );
        }
      }
      items.add(item);
    }
    double aspectRatio;
    if (players.containsKey(currentPage) &&
        players[currentPage]!.aspectRatio != null) {
      aspectRatio = players[currentPage]!.aspectRatio!;
    } else {
      // This is a fallback value for if the video hasn't loaded yet.
      aspectRatio = fallbackAspectRatio;
    }
    var slider = CarouselSlider(
      carouselController: carouselController,
      items: items,
      options: CarouselOptions(
        aspectRatio: aspectRatio,
        autoPlay: false,
        viewportFraction: 0.8,
        enableInfiniteScroll: false,
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
