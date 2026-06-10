import 'package:flutter/material.dart';

import 'hearth.dart';

class HelpPage extends StatelessWidget {
  final String title;
  final Map<String, List<String>> items;

  const HelpPage({super.key, required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tiles = <Widget>[];
    for (final e in items.entries) {
      tiles.add(Padding(
        padding: const EdgeInsets.fromLTRB(16, 5, 16, 5),
        // A rounded, outlined card containing an expand/collapse FAQ entry —
        // the answer reveals inline rather than in a dialog.
        child: HearthCard(
          child: ExpansionTile(
            // Drop the default top/bottom divider lines so the card reads
            // as one clean surface.
            shape: const Border(),
            collapsedShape: const Border(),
            tilePadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            iconColor: cs.primary,
            collapsedIconColor: cs.onSurfaceVariant,
            title: Text(
              e.key,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            children: [
              for (int i = 0; i < e.value.length; i++)
                Padding(
                  padding: EdgeInsets.only(top: i == 0 ? 0 : 14),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      e.value[i],
                      style: TextStyle(
                          fontSize: 15, height: 1.5, color: cs.onSurface),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ));
    }
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: tiles,
      ),
    );
  }
}
