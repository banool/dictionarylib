import 'package:flutter/material.dart';

import 'analytics.dart';
import 'common.dart';
import 'entry_list.dart';
import 'l10n/app_localizations.dart';
import 'lists_service.dart';
import 'saved_video.dart';
import 'sharing/synced_entry_list.dart';

/// Bottom sheet that lets the user toggle which writable lists [video]
/// is saved in. Designed for the entry page's per-video bookmark
/// button: tap → see every list as a row, with a checkbox indicating
/// membership of this specific video, then tap rows to toggle.
///
/// Owner-shared local lists are routed through their wrapper so
/// toggles enqueue sync ops correctly. Subscriber lists (read-only)
/// are excluded; editor lists are included.
///
/// Returns void: the sheet's effect is the toggles themselves, which
/// commit immediately (no apply button).
Future<void> showSaveVideoSheet(
  BuildContext context, {
  required SavedVideo video,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _SaveVideoSheet(video: video),
  );
}

class _SaveVideoSheet extends StatelessWidget {
  final SavedVideo video;
  const _SaveVideoSheet({required this.video});

  @override
  Widget build(BuildContext context) {
    final l = DictLibLocalizations.of(context);
    final title = l?.savedVideoSheetTitle ?? 'Save this video to…';

    // The lists a video can be saved into — the same set the word-page
    // bookmark counts against (see ListsService.writableLists), so the
    // sheet and the "saved to N lists" label always agree.
    final rows = listsService.writableLists;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
              child: Text(title, style: Theme.of(context).textTheme.titleLarge),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: rows.length,
                itemBuilder: (context, i) => _SaveVideoSheetRow(
                  key: ValueKey('saveVideoSheet.row.${rows[i].key}'),
                  list: rows[i],
                  video: video,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One row of the save sheet. Holds its own state so toggling the
/// checkbox only repaints this row, not every other list in the sheet.
class _SaveVideoSheetRow extends StatefulWidget {
  final EntryList list;
  final SavedVideo video;
  const _SaveVideoSheetRow(
      {super.key, required this.list, required this.video});

  @override
  State<_SaveVideoSheetRow> createState() => _SaveVideoSheetRowState();
}

class _SaveVideoSheetRowState extends State<_SaveVideoSheetRow> {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final saved = widget.list.containsVideo(widget.video);
    // Role can flip to subscriber at runtime (editor demoted on 403);
    // re-check here even though `myLists` / `editorLists` filtered
    // out subscribers at sheet-open time.
    final canEdit = widget.list.canBeEdited();

    Future<void> toggle() async {
      if (!canEdit) return;
      // Capture before the await so we don't touch BuildContext across the gap.
      final messenger = ScaffoldMessenger.of(context);
      final failMessage = DictLibLocalizations.of(context)?.saveVideoFailed ??
          "Couldn't update your lists. Please try again.";
      final isShared = widget.list is SyncedEntryList;
      try {
        if (saved) {
          await widget.list.removeVideo(widget.video);
        } else {
          await widget.list.addVideo(widget.video);
          Analytics.track('save',
              props: {'granularity': 'video', 'is_shared': isShared});
        }
      } catch (e) {
        printAndLog("Failed to toggle video in list ${widget.list.key}: $e");
        // Only a failed *add* is a failed save (removes aren't saves).
        if (!saved) {
          Analytics.track('save_failed', props: {
            'granularity': 'video',
            'is_shared': isShared,
            'error_type': Analytics.errorType(e),
          });
        }
        if (mounted) {
          showSnackVia(messenger, failMessage);
        }
      }
      // Re-read membership either way so the checkbox reflects reality even if
      // the toggle failed midway.
      if (mounted) setState(() {});
    }

    final isFav = widget.list.key == KEY_FAVOURITES_ENTRIES;
    Widget row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: canEdit ? toggle : null,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              // Icon in a rounded tile; the favourites star is gold.
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(_iconDataFor(widget.list),
                    size: 21, color: isFav ? cs.secondary : cs.primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(widget.list.getName(context),
                    style: const TextStyle(
                        fontSize: 15.5, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 8),
              Checkbox(
                value: saved,
                onChanged: canEdit ? (_) => toggle() : null,
              ),
            ],
          ),
        ),
      ),
    );
    // Read-only (subscriber) lists are shown but dimmed and non-interactive.
    if (!canEdit) row = Opacity(opacity: 0.5, child: row);
    return row;
  }

  IconData _iconDataFor(EntryList list) {
    if (list is SyncedEntryList) {
      return iconForSharedList(list.meta);
    }
    if (list.key == KEY_FAVOURITES_ENTRIES) {
      return Icons.star;
    }
    return Icons.list_alt;
  }
}
