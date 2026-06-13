import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';

import 'advisories.dart';
import 'globals.dart';
import 'hearth.dart';
import 'l10n/app_localizations.dart';

/// A dedicated "News" feed rendering the app's advisories newest-first as
/// Hearth cards, each with a date eyebrow and the advisory's markdown body.
/// The newest entry gets a "NEW" pill when there are unseen advisories.
class NewsPage extends StatelessWidget {
  const NewsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l = DictLibLocalizations.of(context);
    final advisories =
        advisoriesResponse?.advisories.reversed.toList() ?? const <Advisory>[];
    final hasNew = advisoriesResponse?.newAdvisories ?? false;

    // A centred, scroll-safe wrapper for the zero-content states.
    Widget centeredState(Widget child) => Center(
          child: SingleChildScrollView(
            child: child,
          ),
        );

    Widget body;
    if (advisoriesResponse == null) {
      // The advisories fetch failed at startup (offline / timeout) — distinct
      // from a successful fetch that simply had no announcements, so show a
      // connection-flavoured state rather than the empty "no news" one.
      body = centeredState(
        HearthEmptyState(
          icon: Icons.cloud_off_outlined,
          title: l?.newsErrorTitle ?? "Couldn't load news",
          body:
              l?.newsErrorBody ?? "Check your connection and try again later.",
        ),
      );
    } else if (advisories.isEmpty) {
      body = centeredState(
        HearthEmptyState(
          icon: Icons.campaign_outlined,
          title: l?.newsEmptyTitle ?? "No announcements yet",
          body: l?.newsEmptyBody ?? "App news and tips will show up here.",
        ),
      );
    } else {
      body = Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            itemCount: advisories.length,
            itemBuilder: (context, i) =>
                _AdvisoryCard(advisory: advisories[i], isNew: hasNew && i == 0),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(l?.newsTitle ?? "News")),
      body: body,
    );
  }
}

class _AdvisoryCard extends StatelessWidget {
  final Advisory advisory;
  final bool isNew;
  const _AdvisoryCard({required this.advisory, required this.isNew});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final sheet = MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
      p: tt.bodyLarge?.copyWith(height: 1.6, color: cs.onSurfaceVariant),
      a: TextStyle(color: cs.primary, decoration: TextDecoration.underline),
      code: TextStyle(
        fontFamily: 'monospace',
        fontSize: 13,
        color: cs.onSurface,
        backgroundColor: cs.surfaceContainerHighest,
      ),
      codeblockDecoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      h1: tt.titleLarge,
      h2: tt.titleLarge?.copyWith(fontSize: 18),
      h3: tt.titleMedium,
      blockquoteDecoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: HearthCard(
        // An unseen advisory gets a heavier accent border to draw the eye.
        borderColor: isNew ? cs.primary : null,
        borderWidth: isNew ? 1.5 : 1,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    advisory.date,
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                        color: cs.onSurfaceVariant),
                  ),
                ),
                if (isNew)
                  HearthTag("NEW", color: cs.onPrimary, background: cs.primary),
              ],
            ),
            const SizedBox(height: 10),
            MarkdownBody(
              data: advisory.lines.join("\n"),
              styleSheet: sheet,
              onTapLink: (text, href, title) async {
                if (href == null) return;
                final uri = Uri.tryParse(href);
                if (uri != null && await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
