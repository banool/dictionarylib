import 'package:carousel_slider/carousel_slider.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'analytics.dart';
import 'common.dart' show getShouldUseHorizontalLayout, printAndLog;
import 'globals.dart' show mediaFallbackUrlsFor;
import 'hearth.dart' show HearthVideoFrame;
import 'package:dictionarylib/dictionarylib.dart' show DictLibLocalizations;
import 'video_player_screen.dart'
    show InheritedPlaybackSpeed, getDoubleFromPlaybackSpeed;
import 'web_drag_scroll_behavior.dart';

/// Web-only video carousel, built on package:video_player (an HTML5 `<video>`
/// element under the hood).
///
/// media_kit drives video on native, but on web its player loads and then sits
/// paused — needing a tap or fullscreen to start — and trips wakelock errors.
/// The browser's own `<video>` plays a muted, looped sign smoothly with none of
/// that, so the web build routes every [VideoPlayerScreen] here instead.
///
/// It mirrors the native screen's behaviour: a swipeable carousel of the
/// sub-entry's recordings, auto-playing the centred one (muted + looped) and
/// pausing the rest. Web has no touch swipe, so it adds mouse-drag scrolling
/// (via [WebDragScrollBehavior]) and prev/next arrows over the video.
class WebVideoCarousel extends StatefulWidget {
  const WebVideoCarousel({
    super.key,
    required this.mediaLinks,
    required this.fallbackAspectRatio,
    this.initialPage = 0,
    this.onPageChanged,
    this.expandOnTap = false,
    this.isActive = true,
    this.overlayBuilder,
  });

  final List<String> mediaLinks;
  final double fallbackAspectRatio;
  final int initialPage;
  final void Function(int)? onPageChanged;
  final bool expandOnTap;
  final bool isActive;

  /// Per-video overlay painted at the framed video's top-left (see
  /// [VideoPlayerScreen.overlayBuilder]).
  final Widget? Function(int index)? overlayBuilder;

  @override
  State<WebVideoCarousel> createState() => _WebVideoCarouselState();
}

class _WebVideoCarouselState extends State<WebVideoCarousel> {
  final Map<int, VideoPlayerController> _controllers = {};
  final CarouselSliderController _carouselController =
      CarouselSliderController();
  int _currentPage = 0;
  double _playbackSpeed = 1.0;

  /// Keep a live controller for the current page and its immediate neighbours
  /// so an adjacent swipe is instant, without initialising every recording (and
  /// downloading them all) up front. Matches the native screen's radius.
  static const int _neighbourRadius = 1;

  @override
  void initState() {
    super.initState();
    if (widget.initialPage > 0 &&
        widget.initialPage < widget.mediaLinks.length) {
      _currentPage = widget.initialPage;
    }
    _ensureControllersAround(_currentPage);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Mirror the playback speed set from the entry page (the slow-motion
    // dropdown) onto every controller.
    final speed = InheritedPlaybackSpeed.of(context);
    if (speed != null) {
      _playbackSpeed = getDoubleFromPlaybackSpeed(speed.playbackSpeed);
      for (final c in _controllers.values) {
        if (c.value.isInitialized) c.setPlaybackSpeed(_playbackSpeed);
      }
    }
  }

  @override
  void didUpdateWidget(WebVideoCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Off-screen kept-alive pages (e.g. an adjacent variation) flip isActive so
    // their video pauses instead of looping unseen.
    if (oldWidget.isActive != widget.isActive) {
      final c = _controllers[_currentPage];
      if (c != null && c.value.isInitialized) {
        widget.isActive ? c.play() : c.pause();
      }
    }
  }

  bool _isImage(String link) => link.endsWith('.jpg');

  void _ensureControllersAround(int page) {
    if (widget.mediaLinks.isEmpty) return;
    final last = widget.mediaLinks.length - 1;
    final lower = (page - _neighbourRadius).clamp(0, last);
    final upper = (page + _neighbourRadius).clamp(0, last);
    for (int i = lower; i <= upper; i++) {
      _ensureController(i);
    }
  }

  void _ensureController(int idx) {
    if (idx < 0 || idx >= widget.mediaLinks.length) return;
    final link = widget.mediaLinks[idx];
    if (_isImage(link)) return;
    if (_controllers.containsKey(idx)) return;
    // Try each configured host in turn (e.g. primary then R2 mirror), moving on
    // when a controller fails to initialise. Single-base apps get a one-element
    // list — the original single-URL behaviour.
    _initControllerWithFallback(idx, mediaFallbackUrlsFor(link));
  }

  /// Initialise the controller for [idx], falling back through [candidates]
  /// (most-preferred first) when initialisation fails. On success the winning
  /// controller is kept and played; if every candidate fails the last one is
  /// kept so build()'s hasError branch shows the error widget.
  Future<void> _initControllerWithFallback(
      int idx, List<String> candidates) async {
    for (int i = 0; i < candidates.length; i++) {
      final isLast = i == candidates.length - 1;
      final controller =
          VideoPlayerController.networkUrl(Uri.parse(candidates[i]));
      // Register synchronously so build() shows a spinner and a concurrent
      // _ensureController(idx) skips (it's already keyed).
      _controllers[idx] = controller;
      try {
        await controller.initialize();
        // If unmounted mid-init, leave the controller in the map for the
        // dispose() loop to tear down — don't double-dispose here.
        if (!mounted) return;
        // A non-primary host initialising means the primary failed: a
        // "degraded but recovered" CDN-health signal.
        if (i > 0) {
          Analytics.track('video_fallback', props: {'host_index': i});
        }
        controller.setLooping(true);
        controller.setVolume(0);
        controller.setPlaybackSpeed(_playbackSpeed);
        // Only the centred, on-screen recording plays.
        if (idx == _currentPage && widget.isActive) controller.play();
        setState(() {});
        return;
      } catch (e) {
        printAndLog(
            'web video init failed for ${candidates[i]} (candidate ${i + 1}/${candidates.length}): $e');
        if (isLast) {
          // Every host failed — the user sees the error widget. Key
          // "poor connection / broken CDN" signal (web).
          Analytics.track('video_load_failed',
              props: {'error_type': Analytics.errorType(e)});
          // Keep the failed controller so build() shows the error widget.
          if (mounted) setState(() {});
        } else {
          // Discard and try the next host.
          controller.dispose();
        }
      }
    }
  }

  void _onPageChanged(int newPage) {
    _ensureControllersAround(newPage);
    setState(() {
      for (final entry in _controllers.entries) {
        if (entry.key != newPage) entry.value.pause();
      }
      _currentPage = newPage;
      final c = _controllers[newPage];
      if (c != null && c.value.isInitialized && widget.isActive) c.play();
    });
    widget.onPageChanged?.call(newPage);
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = DictLibLocalizations.of(context)!;
    final current = _controllers[_currentPage];
    final aspectRatio = (current != null && current.value.isInitialized)
        ? current.value.aspectRatio
        : widget.fallbackAspectRatio;

    final items = [
      for (int idx = 0; idx < widget.mediaLinks.length; idx++)
        _buildItem(context, idx),
    ];

    Widget slider = CarouselSlider(
      carouselController: _carouselController,
      items: items,
      options: CarouselOptions(
        aspectRatio: aspectRatio,
        autoPlay: false,
        viewportFraction: 0.94,
        enableInfiniteScroll: false,
        initialPage: _currentPage,
        onPageChanged: (index, _) => _onPageChanged(index),
        enlargeCenterPage: true,
      ),
    );

    // Web disables mouse-drag scrolling, which freezes a carousel swipe
    // mid-drag — re-enable it so grab-and-swipe + snap work like touch.
    slider = ScrollConfiguration(
      behavior: const WebDragScrollBehavior(),
      child: slider,
    );
    if (widget.mediaLinks.length > 1) {
      // Arrows over the video (no touch swipe affordance on web). The band is
      // constrained to the centred video's width so they sit on the video, not
      // over the side peek.
      slider = Stack(
        alignment: Alignment.center,
        children: [
          slider,
          Positioned.fill(
            child: FractionallySizedBox(
              widthFactor: 0.94,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: _arrow(
                              Icons.chevron_left,
                              () => _carouselController.previousPage(),
                              l.videoCarouselPrevious))),
                  Align(
                      alignment: Alignment.centerRight,
                      child: Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: _arrow(
                              Icons.chevron_right,
                              () => _carouselController.nextPage(),
                              l.videoCarouselNext))),
                ],
              ),
            ),
          ),
        ],
      );
    }

    final shouldUseHorizontal = getShouldUseHorizontalLayout(context);
    final size = MediaQuery.of(context).size;
    final boxConstraints = shouldUseHorizontal
        ? BoxConstraints(
            maxWidth: size.width * 0.55, maxHeight: size.height * 0.67)
        : BoxConstraints(maxHeight: size.height * 0.46);

    return Container(
      alignment: Alignment.center,
      child: ConstrainedBox(constraints: boxConstraints, child: slider),
    );
  }

  Widget _buildItem(BuildContext context, int idx) {
    final link = widget.mediaLinks[idx];
    Widget item;
    if (_isImage(link)) {
      item = Padding(
        padding: const EdgeInsets.all(10),
        child: Image.network(
          link,
          fit: BoxFit.contain,
          loadingBuilder: (context, child, progress) => progress == null
              ? child
              : const Padding(
                  padding: EdgeInsets.only(top: 20),
                  child: Center(child: CircularProgressIndicator()),
                ),
          errorBuilder: (context, error, _) => _errorWidget(context, link),
        ),
      );
    } else {
      final controller = _controllers[idx];
      if (controller == null || !controller.value.isInitialized) {
        item = const Padding(
          padding: EdgeInsets.only(top: 20),
          child: Center(child: CircularProgressIndicator()),
        );
      } else if (controller.value.hasError) {
        item = _errorWidget(context, link);
      } else {
        item = LayoutBuilder(
          builder: (context, constraints) {
            final videoAspectRatio = controller.value.aspectRatio;
            const frameTotal =
                10.0; // HearthVideoFrame's 5px padding each side.
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
            Widget framed = HearthVideoFrame(
              child: SizedBox(
                width: videoWidth,
                height: videoHeight,
                child: VideoPlayer(controller),
              ),
            );
            final overlay = widget.overlayBuilder?.call(idx);
            if (overlay != null) {
              framed = Stack(
                children: [
                  framed,
                  // 15 from the frame's outer edge ≈ 10 from the video itself
                  // (HearthVideoFrame insets the video by its 5px padding).
                  Positioned(top: 15, left: 15, child: overlay),
                ],
              );
            }
            return Container(
              padding: const EdgeInsets.symmetric(vertical: verticalMargin),
              alignment: Alignment.center,
              child: framed,
            );
          },
        );
      }
    }
    if (widget.expandOnTap && !_isImage(link)) {
      item = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _expand(link),
        child: item,
      );
    }
    return item;
  }

  Widget _errorWidget(BuildContext context, String link) => Padding(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: Text(
            "${DictLibLocalizations.of(context)!.webVideoLoadError}\n$link",
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12),
          ),
        ),
      );

  Widget _arrow(IconData icon, VoidCallback onTap, String tooltip) {
    return Material(
      color: Colors.black.withValues(alpha: 0.32),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: IconButton(
        iconSize: 22,
        icon: Icon(icon, color: Colors.white),
        onPressed: onTap,
        tooltip: tooltip,
      ),
    );
  }

  Future<void> _expand(String link) async {
    // Pause the inline copy while expanded so the video isn't playing twice.
    final inline = _controllers[_currentPage];
    final wasPlaying = inline?.value.isPlaying ?? false;
    inline?.pause();
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.82),
      builder: (ctx) => _WebExpandedVideo(mediaLink: link),
    );
    if (!mounted) return;
    if (wasPlaying && widget.isActive) inline?.play();
  }
}

/// Fullscreen-ish expanded view of a single web video: enlarged, muted, looped,
/// over a heavy dim. Tap anywhere (or the close button) to dismiss. Mirrors the
/// native [showExpandedVideo] overlay with a video_player controller.
class _WebExpandedVideo extends StatefulWidget {
  const _WebExpandedVideo({required this.mediaLink});

  final String mediaLink;

  @override
  State<_WebExpandedVideo> createState() => _WebExpandedVideoState();
}

class _WebExpandedVideoState extends State<_WebExpandedVideo> {
  // Reassigned as the fallback walks the candidate hosts, so not `final`. Set
  // synchronously in initState before the first await, so build()/dispose()
  // always see a controller.
  late VideoPlayerController _controller;

  @override
  void initState() {
    super.initState();
    _initWithFallback(mediaFallbackUrlsFor(widget.mediaLink));
  }

  /// Initialise the expanded controller, falling back through [candidates]
  /// (most-preferred first) when a host fails to initialise.
  Future<void> _initWithFallback(List<String> candidates) async {
    for (int i = 0; i < candidates.length; i++) {
      final controller =
          VideoPlayerController.networkUrl(Uri.parse(candidates[i]));
      _controller = controller;
      try {
        await controller.initialize();
        // If unmounted mid-init, leave it for dispose() to tear down.
        if (!mounted) return;
        controller.setLooping(true);
        controller.setVolume(0);
        controller.play();
        setState(() {});
        return;
      } catch (e) {
        printAndLog(
            'web expanded video init failed for ${candidates[i]} (candidate ${i + 1}/${candidates.length}): $e');
        // Discard and try the next host; keep the last so build() shows its
        // spinner/error state.
        if (i < candidates.length - 1) controller.dispose();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Tap the dimmed area to dismiss.
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.of(context).pop(),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: _controller.value.isInitialized
                  ? AspectRatio(
                      aspectRatio: _controller.value.aspectRatio,
                      child: VideoPlayer(_controller),
                    )
                  : const CircularProgressIndicator(color: Colors.white),
            ),
          ),
        ),
        SafeArea(
          child: Align(
            alignment: Alignment.topLeft,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 28),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ),
      ],
    );
  }
}
