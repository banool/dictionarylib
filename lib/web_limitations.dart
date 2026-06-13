import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// A small info card explaining a limitation of the web version. The web build
/// has no account features (no sign-in, no favourites/saving, no creating or
/// editing lists, no revision) — the mobile app is the full experience. Used
/// on the search page (the full rundown) and the lists page (list creation).
///
/// All copy is passed in by the caller (already localised via
/// [DictLibLocalizations]); this widget is just the layout shell.
class WebLimitationsCard extends StatelessWidget {
  const WebLimitationsCard({
    super.key,
    required this.heading,
    this.points = const [],
    this.body,
    this.footer,
    this.footerUrl,
  });

  /// Bold heading line.
  final String heading;

  /// Bulleted limitations (used on the search page).
  final List<String> points;

  /// A freeform paragraph instead of bullets (used on the lists page).
  final String? body;

  /// Closing line pointing at the mobile app. Pass null to omit.
  final String? footer;

  /// If set, [footer] becomes a tappable link to this URL (the marketing site,
  /// where the App Store / Play Store install buttons live).
  final String? footerUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurfaceVariant;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, color: onSurface),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(heading,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  if (body != null) ...[
                    const SizedBox(height: 6),
                    Text(body!, style: theme.textTheme.bodyMedium),
                  ],
                  for (final p in points) ...[
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('•  ', style: theme.textTheme.bodyMedium),
                        Expanded(
                            child: Text(p, style: theme.textTheme.bodyMedium)),
                      ],
                    ),
                  ],
                  if (footer != null) ...[
                    const SizedBox(height: 10),
                    if (footerUrl != null)
                      InkWell(
                        onTap: () => launchUrl(Uri.parse(footerUrl!),
                            mode: LaunchMode.externalApplication),
                        child: Text(footer!,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.primary,
                              decoration: TextDecoration.underline,
                              decorationColor: theme.colorScheme.primary,
                            )),
                      )
                    else
                      Text(footer!,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
