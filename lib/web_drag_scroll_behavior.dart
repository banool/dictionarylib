import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// A scroll behavior that also treats a **mouse** as a drag device. Flutter
/// web disables mouse-drag scrolling by default, which leaves a PageView /
/// carousel swipe frozen mid-drag (it never settles to a page). Wrap a
/// carousel in `ScrollConfiguration(behavior: const WebDragScrollBehavior())`
/// **on web only** so grab-and-swipe + snap-on-release work like touch does.
///
/// Applied per-carousel rather than app-wide on purpose: enabling mouse-drag
/// globally would hijack text selection in the definitions/lists. Native is
/// never wrapped (callers gate on `kIsWeb`), so the mobile experience is
/// untouched.
class WebDragScrollBehavior extends MaterialScrollBehavior {
  const WebDragScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        ...super.dragDevices,
        PointerDeviceKind.mouse,
      };
}
