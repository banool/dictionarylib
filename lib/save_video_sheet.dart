import 'package:flutter/material.dart';

import 'common.dart';
import 'entry_list.dart';
import 'globals.dart';
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

    final rows = <EntryList>[];
    for (final el in listsService.myLists) {
      rows.add(listsService.ownedShareFor(el) ?? el);
    }
    if (sharing.isEnabled) {
      for (final el in sharing.lists.editorLists) {
        if (el.meta.orphaned) continue;
        rows.add(el);
      }
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
              child: Text(title,
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: rows.length,
                itemBuilder: (context, i) =>
                    _SaveVideoSheetRow(list: rows[i], video: video),
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
  const _SaveVideoSheetRow({required this.list, required this.video});

  @override
  State<_SaveVideoSheetRow> createState() => _SaveVideoSheetRowState();
}

class _SaveVideoSheetRowState extends State<_SaveVideoSheetRow> {
  @override
  Widget build(BuildContext context) {
    final saved = widget.list.containsVideo(widget.video);
    // Role can flip to subscriber at runtime (editor demoted on 403);
    // re-check here even though `myLists` / `editorLists` filtered
    // out subscribers at sheet-open time.
    final canEdit = widget.list.canBeEdited();
    return CheckboxListTile(
      value: saved,
      controlAffinity: ListTileControlAffinity.leading,
      title: Text(widget.list.getName(context)),
      secondary: _iconFor(widget.list),
      onChanged: canEdit
          ? (newValue) async {
              if (newValue == null) return;
              if (newValue) {
                await widget.list.addVideo(widget.video);
              } else {
                await widget.list.removeVideo(widget.video);
              }
              if (mounted) setState(() {});
            }
          : null,
    );
  }

  Widget _iconFor(EntryList list) {
    if (list is SyncedEntryList) {
      return Icon(iconForSharedList(list.meta), size: 20);
    }
    if (list.key == KEY_FAVOURITES_ENTRIES) {
      return const Icon(Icons.star, size: 20);
    }
    return const Icon(Icons.list_alt, size: 20);
  }
}
