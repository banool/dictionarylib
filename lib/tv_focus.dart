import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

// Remote-control (D-pad) support, for Android TV and for anyone driving the
// app from a keyboard. Flutter already moves focus with the arrow keys and
// activates with the remote's centre button; what it lacks out of the box is
// a focus indicator you can see from across a room, a way out of a text field
// with the arrows, and scrolling for pages that have nothing focusable on
// them. Those three gaps are what this file fills.

/// Whether the app is running on an Android TV device. Set at startup by
/// [applyTvFocusDefaults].
bool isAndroidTv = false;

/// On Android TV everything is driven by the remote, so focus is shown from
/// the start rather than only after the first key press. It also sidesteps
/// Flutter ignoring, for highlight purposes, key events that Android files
/// under the virtual keyboard device, which some remotes' events are.
void applyTvFocusDefaults(List<String> androidSystemFeatures) {
  isAndroidTv = androidSystemFeatures.contains('android.software.leanback');
  if (isAndroidTv) {
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
  }
}

/// A focus node the [FocusRingOverlay] never draws a ring around: for focus
/// holders that are whole regions rather than controls (see [DpadScrollView]).
class NoFocusRingNode extends FocusNode {
  NoFocusRingNode({super.debugLabel});
}

/// On Android TV, draws a ring around whatever has focus. Off TV it draws
/// nothing (phones and tablets keep Material's own focus highlights), and on
/// TV it also holds [_TvTextFieldShortcuts]. Material's own focus highlights are faint overlays meant for a desktop
/// at arm's length; on a TV they're close to invisible, and they differ per
/// widget. One ring drawn over the whole app is consistent and needs nothing
/// from the individual widgets.
///
/// Sits in MaterialApp's builder, so it's above the navigator and every route
/// but below nothing: it paints over dialogs and sheets too.
class FocusRingOverlay extends StatefulWidget {
  const FocusRingOverlay({super.key, required this.child});

  final Widget child;

  @override
  State<FocusRingOverlay> createState() => _FocusRingOverlayState();
}

class _FocusRingOverlayState extends State<FocusRingOverlay>
    with SingleTickerProviderStateMixin {
  final GlobalKey _stackKey = GlobalKey();
  // Ticks only while a ring is showing, so it follows its target through
  // scrolling and route transitions without a listener on every scrollable.
  late final Ticker _ticker = createTicker((_) => _updateRect());
  final ShortcutManager _shortcuts = _TvTextFieldShortcuts();
  Rect? _rect;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_sync);
    FocusManager.instance.addHighlightModeListener(_onHighlightMode);
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_sync);
    FocusManager.instance.removeHighlightModeListener(_onHighlightMode);
    _ticker.dispose();
    _shortcuts.dispose();
    super.dispose();
  }

  void _onHighlightMode(FocusHighlightMode _) => _sync();

  bool get _keyNavigation =>
      FocusManager.instance.highlightMode == FocusHighlightMode.traditional;

  FocusNode? get _target {
    final node = FocusManager.instance.primaryFocus;
    if (node == null || node is FocusScopeNode || node is NoFocusRingNode) {
      return null;
    }
    return node.context == null ? null : node;
  }

  void _sync() {
    if (!mounted || kIsWeb || !isAndroidTv) return;
    final active = _keyNavigation && _target != null;
    if (active && !_ticker.isActive) {
      _ticker.start();
    } else if (!active && _ticker.isActive) {
      _ticker.stop();
    }
    _updateRect();
  }

  void _updateRect() {
    Rect? rect;
    final target = _target;
    if (_keyNavigation && target != null) {
      final stack = _stackKey.currentContext?.findRenderObject();
      final box = target.context?.findRenderObject();
      if (stack is RenderBox &&
          stack.hasSize &&
          box is RenderBox &&
          box.attached &&
          box.hasSize) {
        final topLeft = stack.globalToLocal(box.localToGlobal(Offset.zero));
        rect = topLeft & box.size;
      }
    }
    if (rect != _rect) setState(() => _rect = rect);
  }

  @override
  Widget build(BuildContext context) {
    // Desktop browsers default to keyboard-style focus, so on web the ring
    // would sit on the search field from load and after mouse clicks; the web
    // build keeps its own look.
    if (kIsWeb) return widget.child;
    final rect = _rect;
    return Stack(
      key: _stackKey,
      fit: StackFit.passthrough,
      alignment: Alignment.topLeft,
      children: [
        // Below DefaultTextEditingShortcuts, so these win over a text field's
        // own up/down handling.
        Shortcuts.manager(manager: _shortcuts, child: widget.child),
        if (rect != null)
          Positioned.fill(
            key: const ValueKey('tvFocusRing'),
            child: IgnorePointer(
              child: CustomPaint(
                painter: _FocusRingPainter(
                  rect: rect,
                  color: Theme.of(context).colorScheme.primary,
                  halo: Theme.of(context).colorScheme.surface,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _FocusRingPainter extends CustomPainter {
  _FocusRingPainter({
    required this.rect,
    required this.color,
    required this.halo,
  });

  final Rect rect;
  final Color color;
  final Color halo;

  @override
  void paint(Canvas canvas, Size size) {
    final ring = RRect.fromRectAndRadius(
      rect.inflate(3),
      const Radius.circular(12),
    );
    // A thin halo in the surface colour outside the ring keeps it legible
    // when the focused control is itself the ring's colour.
    canvas.drawRRect(
      ring.inflate(2),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = halo,
    );
    canvas.drawRRect(
      ring,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_FocusRingPainter old) =>
      old.rect != rect || old.color != color || old.halo != halo;
}

/// Makes a page with nothing focusable on it (news, long read-only text)
/// scroll with the D-pad's up and down. On Android TV it takes focus when the
/// page opens;
/// at either end the key passes through, so up from the top still reaches
/// the app bar's back button.
class DpadScrollView extends StatefulWidget {
  const DpadScrollView({
    super.key,
    required this.controller,
    required this.child,
  });

  final ScrollController controller;
  final Widget child;

  @override
  State<DpadScrollView> createState() => _DpadScrollViewState();
}

class _DpadScrollViewState extends State<DpadScrollView> {
  final FocusNode _node = NoFocusRingNode(debugLabel: 'DpadScrollView');

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final double direction;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      direction = 1;
    } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      direction = -1;
    } else {
      return KeyEventResult.ignored;
    }
    final controller = widget.controller;
    if (!controller.hasClients) return KeyEventResult.ignored;
    final position = controller.position;
    final target =
        (position.pixels + direction * position.viewportDimension * 0.4).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        );
    if (target == position.pixels) return KeyEventResult.ignored;
    controller.animateTo(
      target,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _node,
      autofocus: isAndroidTv,
      onKeyEvent: _onKey,
      child: widget.child,
    );
  }
}

/// On Android TV, the remote's up and down move focus out of text fields.
/// By default a text field keeps those keys to move its cursor, which strands
/// the remote in the field with no way to reach the results beneath it. Does
/// nothing off TV, where arrow keys keep their usual text-editing meaning.
class _TvTextFieldShortcuts extends ShortcutManager {
  _TvTextFieldShortcuts()
    : super(
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.arrowDown): DirectionalFocusIntent(
            TraversalDirection.down,
            ignoreTextFields: false,
          ),
          SingleActivator(LogicalKeyboardKey.arrowUp): DirectionalFocusIntent(
            TraversalDirection.up,
            ignoreTextFields: false,
          ),
        },
      );

  @override
  KeyEventResult handleKeypress(BuildContext context, KeyEvent event) =>
      isAndroidTv
      ? super.handleKeypress(context, event)
      : KeyEventResult.ignored;
}
