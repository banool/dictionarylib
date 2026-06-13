// Reusable "Hearth" UI widgets shared across the redesigned screens.
//
// These are the bespoke building blocks the Hearth design uses that aren't
// plain Material components: section labels, grouping cards, the video frame,
// page dots, the success ring, stat tiles, setting rows, empty states, etc.
//
// IMPORTANT: every colour here is pulled from the active `ColorScheme`, never
// hardcoded. That way these layouts adapt to whichever theme variant is
// selected (Hearth or Classic) instead of locking in the clay palette. See
// theme.dart for how the schemes are built.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme.dart' show kRadiusBox, kRadiusCard, kRadiusChip, kRadiusPill;

/// An uppercase section label, e.g. "RECENT" or "REVISION SOURCES". Optionally
/// shows a trailing widget (such as a "Clear" text button) on the right.
class HearthSectionLabel extends StatelessWidget {
  final String text;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  const HearthSectionLabel(
    this.text, {
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(4, 20, 4, 8),
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: Text(
              text.toUpperCase(),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// A soft outlined surface card used to group rows/content. Uses the subtle
/// `outlineVariant` border and the card radius.
class HearthCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;

  /// Border colour. Defaults to the subtle `outlineVariant`. Pass an accent
  /// (e.g. the scheme primary) to highlight the card — the News page uses this
  /// for an unseen "NEW" advisory.
  final Color? borderColor;

  /// Border width. Defaults to 1; pair with [borderColor] for a heavier accent
  /// border.
  final double borderWidth;

  const HearthCard({
    required this.child,
    this.padding,
    this.onTap,
    this.borderColor,
    this.borderWidth = 1,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final content =
        padding == null ? child : Padding(padding: padding!, child: child);
    return Material(
      color: cs.surface,
      borderRadius: BorderRadius.circular(kRadiusCard),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(kRadiusCard),
            border: Border.all(
                color: borderColor ?? cs.outlineVariant, width: borderWidth),
          ),
          child: content,
        ),
      ),
    );
  }
}

/// A small rounded type tag/pill, e.g. "Phrase" or "Fingerspelling", or a sync
/// status. Muted by default — the label uses `onSurfaceVariant` on the neutral
/// `surfaceContainerHighest` pill, which stays legible (WCAG AA) in both light
/// and dark. Pass [color]/[background] for a tonal accent variant (e.g. a
/// "NEW" pill).
class HearthTag extends StatelessWidget {
  final String label;
  final Color? color;
  final Color? background;

  const HearthTag(this.label, {this.color, this.background, super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: background ?? cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(kRadiusPill),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.1,
          color: color ?? cs.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// A productive empty / zero-result state: a rounded icon tile, a headline, a
/// body line, and an optional action button.
class HearthEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? body;
  final Widget? action;
  final EdgeInsetsGeometry padding;

  const HearthEmptyState({
    required this.icon,
    required this.title,
    this.body,
    this.action,
    this.padding = const EdgeInsets.fromLTRB(24, 54, 24, 24),
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: padding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(kRadiusCard),
            ),
            child: Icon(icon, size: 30, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: tt.titleLarge?.copyWith(fontSize: 20),
          ),
          if (body != null) ...[
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 280),
              child: Text(
                body!,
                textAlign: TextAlign.center,
                style: tt.bodyMedium
                    ?.copyWith(color: cs.onSurfaceVariant, height: 1.5),
              ),
            ),
          ],
          if (action != null) ...[
            const SizedBox(height: 18),
            action!,
          ],
        ],
      ),
    );
  }
}

/// The video "hero" frame: a rounded, subtly-shadowed, outlined surround for
/// the signing video. Pass the video widget as [child].
class HearthVideoFrame extends StatelessWidget {
  final Widget child;
  final double radius;

  const HearthVideoFrame({required this.child, this.radius = 22, super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: cs.outlineVariant, width: 0.5),
        boxShadow: [
          BoxShadow(
            // The scheme's shadow token is already brightness-appropriate
            // (warm/low-alpha in light, black/50% in dark).
            color: cs.shadow,
            blurRadius: 34,
            offset: const Offset(0, 16),
            spreadRadius: -14,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius - 5),
        child: child,
      ),
    );
  }
}

/// A row of page dots; the active dot is elongated. Used for the within-sign
/// video carousel and the variation pager.
class HearthDots extends StatelessWidget {
  final int count;
  final int index;

  /// Dot height/diameter. The active dot stretches to a pill ~2.6x this wide.
  /// Defaults to 6 (the standard, prominent indicator). Pass a smaller value
  /// for a subordinate/secondary indicator.
  final double size;

  /// Colour of the active dot. Defaults to the scheme primary (prominent).
  /// A muted colour (e.g. onSurfaceVariant) reads as secondary.
  final Color? activeColor;

  const HearthDots({
    required this.count,
    required this.index,
    this.size = 6,
    this.activeColor,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final onColor = activeColor ?? cs.primary;
    final offColor = cs.outline;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final active = i == index;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: EdgeInsets.symmetric(horizontal: size * 0.5),
          width: active ? size * 2.6 : size,
          height: size,
          decoration: BoxDecoration(
            color: active ? onColor : offColor,
            borderRadius: BorderRadius.circular(kRadiusPill),
          ),
        );
      }),
    );
  }
}

/// A circular progress ring with a percentage in the centre. Used by the
/// revision completion screen and progress dashboard.
class HearthRing extends StatelessWidget {
  final double percent; // 0..1
  final double size;
  final double stroke;
  final String? centerLabel;

  const HearthRing({
    required this.percent,
    this.size = 132,
    this.stroke = 12,
    this.centerLabel,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final ringColor = cs.tertiary;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size(size, size),
            painter: _RingPainter(
              percent: percent.clamp(0, 1),
              stroke: stroke,
              track: cs.surfaceContainerHighest,
              fill: ringColor,
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${(percent * 100).round()}%',
                style: tt.displaySmall?.copyWith(fontSize: size * 0.26),
              ),
              if (centerLabel != null)
                Text(
                  centerLabel!,
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double percent;
  final double stroke;
  final Color track;
  final Color fill;

  _RingPainter({
    required this.percent,
    required this.stroke,
    required this.track,
    required this.fill,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - stroke) / 2;
    final trackPaint = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    final fillPaint = Paint()
      ..color = fill
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, trackPaint);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * percent,
      false,
      fillPaint,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.percent != percent ||
      old.fill != fill ||
      old.track != track ||
      old.stroke != stroke;
}

/// A single stat tile: a big value over a small muted label, in an outlined
/// surface box.
class HearthStatTile extends StatelessWidget {
  final String value;
  final String label;
  final Color? valueColor;

  const HearthStatTile({
    required this.value,
    required this.label,
    this.valueColor,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(kRadiusBox),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: tt.headlineSmall?.copyWith(
                fontSize: 26, color: valueColor ?? cs.onSurface, height: 1),
          ),
          const SizedBox(height: 4),
          Text(label,
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }
}

/// A tappable row inside a [HearthCard]: leading icon, title (+ optional
/// subtitle), and a trailing widget (chevron / value / toggle).
class HearthRow extends StatelessWidget {
  final IconData? icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? iconColor;

  /// Horizontal inset of the row's content. Defaults to 15 (the grouped-card
  /// look). Callers that place rows inside a wider container — e.g. a dialog
  /// where the title sits at the Material 24dp inset — can bump this so the
  /// text lines up with that container's other content.
  final double horizontalPadding;

  const HearthRow({
    this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.iconColor,
    this.horizontalPadding = 15,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
        // A uniform minimum row height so rows with a tall trailing (Switch /
        // Checkbox, whose tap target is ~48dp) are the same height as plain
        // rows (chevron / value). Multi-line subtitles can still grow past it.
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 20, color: iconColor ?? cs.primary),
                const SizedBox(width: 13),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title,
                        style: tt.titleMedium?.copyWith(
                            fontSize: 15.5, fontWeight: FontWeight.w600)),
                    if (subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(subtitle!,
                            style: tt.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant, height: 1.35)),
                      ),
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 10),
                trailing!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A thin divider matching the design's faint row separators, inset to align
/// with [HearthRow] content.
class _HearthRowDivider extends StatelessWidget {
  const _HearthRowDivider();

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 1,
      indent: 15,
      endIndent: 15,
      color: Theme.of(context).colorScheme.outlineVariant,
    );
  }
}

/// The canonical "settings group": a [HearthCard] wrapping [rows] separated by
/// hairline dividers. Used by the settings and flashcards-landing screens so
/// the grouped-rows look stays in one place.
class HearthRowGroup extends StatelessWidget {
  final List<Widget> rows;
  final EdgeInsetsGeometry? padding;

  const HearthRowGroup({required this.rows, this.padding, super.key});

  @override
  Widget build(BuildContext context) {
    final kids = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      if (i > 0) kids.add(const _HearthRowDivider());
      kids.add(rows[i]);
    }
    return HearthCard(padding: padding, child: Column(children: kids));
  }
}

/// An option for [showHearthPicker].
class HearthPickerOption<T> {
  final T value;
  final String label;
  const HearthPickerOption(this.value, this.label);
}

/// A single-choice picker dialog styled with [HearthRow]s and a check on the
/// current selection. Returns the chosen value, or null if dismissed. Use this
/// instead of hand-rolling an AlertDialog full of raw ListTiles, so choice
/// dialogs (app theme, colour mode, …) match the rest of the Hearth UI.
Future<T?> showHearthPicker<T>({
  required BuildContext context,
  required String title,
  required T selected,
  required List<HearthPickerOption<T>> options,
}) {
  return showDialog<T>(
    context: context,
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      return AlertDialog(
        title: Text(title),
        // Zero horizontal content padding so each HearthRow's own inset + ripple
        // span the dialog width. The rows use the 24dp Material inset (matching
        // the title's default titlePadding) so option labels line up under the
        // title rather than sitting outdented to its left.
        contentPadding: const EdgeInsets.symmetric(vertical: 8),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final o in options)
                HearthRow(
                  title: o.label,
                  horizontalPadding: 24,
                  onTap: () => Navigator.of(ctx).pop(o.value),
                  trailing: o.value == selected
                      ? Icon(Icons.check, color: cs.primary)
                      : null,
                ),
            ],
          ),
        ),
      );
    },
  );
}

/// A list row presented as its own spaced, outlined card: a rounded leading
/// icon tile, a title (+ optional subtitle), and a trailing widget (defaults
/// to a chevron when tappable). Used by the Lists screens. Handles its own
/// outer spacing so it works regardless of the card theme's margin.
class HearthListRow extends StatelessWidget {
  final Widget? leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool showChevron;

  const HearthListRow({
    this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.showChevron = true,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    Widget? trailingWidget = trailing;
    trailingWidget ??= (showChevron && onTap != null)
        ? Icon(Icons.chevron_right, color: cs.onSurfaceVariant)
        : null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 5, 16, 5),
      child: HearthCard(
        onTap: onTap,
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            if (leading != null) ...[
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(kRadiusChip),
                ),
                child: leading,
              ),
              const SizedBox(width: 13),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title,
                      style: tt.titleMedium?.copyWith(
                          fontSize: 16, fontWeight: FontWeight.w600)),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(subtitle!,
                          style: tt.bodySmall
                              ?.copyWith(color: cs.onSurfaceVariant)),
                    ),
                ],
              ),
            ),
            if (trailingWidget != null) ...[
              const SizedBox(width: 8),
              trailingWidget,
            ],
          ],
        ),
      ),
    );
  }
}

/// A horizontal segmented control (e.g. Spaced Repetition / Random, or a
/// strategy chooser). Each option fills equal width.
class HearthSegmented extends StatelessWidget {
  final List<String> options;
  final int selected;
  final ValueChanged<int> onChanged;

  const HearthSegmented({
    required this.options,
    required this.selected,
    required this.onChanged,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        for (int i = 0; i < options.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            // Exposed to screen readers as a selectable button (with its
            // selected state), and given a ripple + a 48dp-tall tap target.
            child: Semantics(
              button: true,
              selected: i == selected,
              label: options[i],
              excludeSemantics: true,
              child: Material(
                color: i == selected ? cs.primaryContainer : Colors.transparent,
                borderRadius: BorderRadius.circular(kRadiusChip),
                child: InkWell(
                  onTap: () => onChanged(i),
                  borderRadius: BorderRadius.circular(kRadiusChip),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 48),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 11),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(kRadiusChip),
                      border: Border.all(
                        color: i == selected ? cs.primary : cs.outline,
                        width: 1.5,
                      ),
                    ),
                    child: Text(
                      options[i],
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: i == selected
                            ? cs.onPrimaryContainer
                            : cs.onSurface,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// A lightweight, theme-coloured decorative tile used where showing a real
/// sign video would be too heavy (e.g. the "sign of the day" card). It draws a
/// warm gradient with a couple of soft blobs and a hand glyph — no video player
/// or network — so it's cheap to put on the home screen. [seed] makes the motif
/// deterministic per sign (the same sign always gets the same glyph), purely
/// cosmetically.
class HearthSignIllustration extends StatelessWidget {
  final double width;
  final double height;
  final int seed;
  final double radius;

  const HearthSignIllustration({
    required this.width,
    required this.height,
    this.seed = 0,
    this.radius = 14,
    super.key,
  });

  // A small rotation of hand/sign glyphs so different signs look distinct.
  static const _glyphs = <IconData>[
    Icons.sign_language,
    Icons.front_hand,
    Icons.waving_hand,
    Icons.back_hand,
    Icons.pan_tool_alt,
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final glyph = _glyphs[seed.abs() % _glyphs.length];
    final blob = cs.onPrimaryContainer.withValues(alpha: 0.07);
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [cs.primaryContainer, cs.secondaryContainer],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              right: -height * 0.28,
              top: -height * 0.28,
              child: Container(
                width: height * 0.8,
                height: height * 0.8,
                decoration: BoxDecoration(shape: BoxShape.circle, color: blob),
              ),
            ),
            Positioned(
              left: -height * 0.22,
              bottom: -height * 0.32,
              child: Container(
                width: height * 0.7,
                height: height * 0.7,
                decoration: BoxDecoration(shape: BoxShape.circle, color: blob),
              ),
            ),
            Center(
              child: Icon(glyph,
                  size: height * 0.46, color: cs.onPrimaryContainer),
            ),
          ],
        ),
      ),
    );
  }
}
