import 'dart:io';

import 'package:flutter/material.dart';

import '../models/grid_page.dart';
import '../services/grid_override_service.dart';
import '../theme/nasira_colors.dart';

/// Modal-Bottom-Sheet zum Bearbeiten der Wortliste einer Grid-Seite.
///
/// Verwendung:
/// ```dart
/// GridPageEditorSheet.show(
///   context: context,
///   page: myPage,
///   overrideService: _overrideService,
///   onSaved: () { /* Seite neu laden */ },
/// );
/// ```
class GridPageEditorSheet extends StatefulWidget {
  final GridPage page;
  final GridOverrideService overrideService;
  final VoidCallback onSaved;
  final ScrollController scrollController;

  const GridPageEditorSheet._({
    required this.page,
    required this.overrideService,
    required this.onSaved,
    required this.scrollController,
  });

  /// Öffnet den Editor als modales Bottom-Sheet.
  static Future<void> show({
    required BuildContext context,
    required GridPage page,
    required GridOverrideService overrideService,
    required VoidCallback onSaved,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.50,
        maxChildSize: 0.95,
        expand: false,
        builder: (ctx, scrollController) => GridPageEditorSheet._(
          page: page,
          overrideService: overrideService,
          onSaved: onSaved,
          scrollController: scrollController,
        ),
      ),
    );
  }

  @override
  State<GridPageEditorSheet> createState() => _GridPageEditorSheetState();
}

class _GridPageEditorSheetState extends State<GridPageEditorSheet> {
  late List<GridWordListItem> _items;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // Startet mit der aktuellen Wortliste (ggf. bereits überschrieben).
    _items = List<GridWordListItem>.from(widget.page.wordList);
  }

  // ── Mutationen ────────────────────────────────────────────────────────────

  void _delete(int index) => setState(() => _items.removeAt(index));

  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final item = _items.removeAt(oldIndex);
      _items.insert(newIndex, item);
    });
  }

  Future<void> _editItem(int? index) async {
    final isNew = index == null;
    final result = await _showTextDialog(
      context,
      title: isNew ? 'Wort hinzufügen' : 'Wort bearbeiten',
      initialValue: isNew ? '' : _items[index].text,
    );
    if (result == null || result.trim().isEmpty) return;
    setState(() {
      if (isNew) {
        _items.add(GridWordListItem(text: result.trim()));
      } else {
        _items[index] = GridWordListItem(
          text: result.trim(),
          localImagePath: _items[index].localImagePath,
        );
      }
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await widget.overrideService.setWordList(widget.page.name, _items);
    if (mounted) {
      Navigator.pop(context);
      widget.onSaved();
    }
  }

  Future<void> _reset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Zurücksetzen?'),
        content: const Text(
          'Alle eigenen Änderungen an dieser Seite werden gelöscht '
          'und die Original-Wortliste wiederhergestellt.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Zurücksetzen'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await widget.overrideService.reset(widget.page.name);
    if (mounted) {
      Navigator.pop(context);
      widget.onSaved();
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final hasOverride = widget.overrideService.hasOverride(widget.page.name);

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          // Drag-Handle
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
            child: Row(
              children: [
                const Icon(Icons.edit_outlined,
                    size: 20, color: NasiraColors.navGreen),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.page.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: NasiraColors.textDark,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (hasOverride)
                  TextButton.icon(
                    onPressed: _reset,
                    icon: const Icon(Icons.restore, size: 16),
                    label: const Text('Zurücksetzen'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.red.shade700,
                      textStyle: const TextStyle(fontSize: 13),
                    ),
                  ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Wortliste
          Expanded(
            child: _items.isEmpty
                ? const Center(
                    child: Text(
                      'Keine Wörter vorhanden.\nTippe auf „Wort hinzufügen".',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey, fontSize: 14),
                    ),
                  )
                : ReorderableListView.builder(
                    scrollController: widget.scrollController,
                    padding: const EdgeInsets.only(bottom: 8),
                    itemCount: _items.length,
                    onReorder: _reorder,
                    itemBuilder: (ctx, i) {
                      final item = _items[i];
                      return _WordListRow(
                        key: ValueKey('${i}_${item.text}'),
                        item: item,
                        onEdit: () => _editItem(i),
                        onDelete: () => _delete(i),
                      );
                    },
                  ),
          ),

          const Divider(height: 1),

          // Footer
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _editItem(null),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Wort hinzufügen'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: NasiraColors.navGreen,
                      side: const BorderSide(color: NasiraColors.navGreen),
                    ),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: NasiraColors.navGreen,
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Speichern'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Zeile in der Wortliste ────────────────────────────────────────────────────

class _WordListRow extends StatelessWidget {
  final GridWordListItem item;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _WordListRow({
    super.key,
    required this.item,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
      leading: _buildThumbnail(),
      title: Text(
        item.text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 14, color: NasiraColors.textDark),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 20),
            color: NasiraColors.navGreen,
            tooltip: 'Bearbeiten',
            onPressed: onEdit,
          ),
          IconButton(
            icon: Icon(Icons.delete_outline, size: 20, color: Colors.red.shade400),
            tooltip: 'Löschen',
            onPressed: onDelete,
          ),
          const Icon(Icons.drag_handle, color: Colors.grey),
        ],
      ),
    );
  }

  Widget _buildThumbnail() {
    if (item.localImagePath == null) {
      return Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: const Color(0xFFEEF2EE),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Icon(Icons.image_not_supported_outlined,
            size: 18, color: Colors.grey),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Image.file(
        File(item.localImagePath!),
        width: 40,
        height: 40,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          width: 40,
          height: 40,
          color: const Color(0xFFEEF2EE),
          child: const Icon(Icons.broken_image_outlined,
              size: 18, color: Colors.grey),
        ),
      ),
    );
  }
}

// ── Text-Eingabe-Dialog ───────────────────────────────────────────────────────

Future<String?> _showTextDialog(
  BuildContext context, {
  required String title,
  required String initialValue,
}) {
  final ctrl = TextEditingController(text: initialValue);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        maxLines: 2,
        decoration: const InputDecoration(
          labelText: 'Text',
          border: OutlineInputBorder(),
        ),
        onSubmitted: (_) => Navigator.pop(ctx, ctrl.text),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, null),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, ctrl.text),
          style: FilledButton.styleFrom(
            backgroundColor: NasiraColors.navGreen,
          ),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}
