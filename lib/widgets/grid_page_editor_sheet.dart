import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/grid_page.dart';
import '../nasira_app_state.dart';
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
  final dynamic assetResolver;

  const GridPageEditorSheet._({
    required this.page,
    required this.overrideService,
    required this.onSaved,
    required this.scrollController,
    required this.assetResolver,
  });

  /// Öffnet den Editor als modales Bottom-Sheet.
  static Future<void> show({
    required BuildContext context,
    required GridPage page,
    required GridOverrideService overrideService,
    required VoidCallback onSaved,
  }) {
    final assetResolver = context.read<NasiraAppState>().assetResolver;
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
          assetResolver: assetResolver,
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
    final current = isNew ? null : _items[index];
    final result = await showDialog<GridWordListItem>(
      context: context,
      builder: (ctx) => _WordListItemDialog(
        initialText:      current?.text ?? '',
        initialStem:      current?.symbolStem,
        assetResolver:    widget.assetResolver,
        title:            isNew ? 'Wort hinzufügen' : 'Wort bearbeiten',
      ),
    );
    if (result == null) return;
    setState(() {
      if (isNew) {
        _items.add(result);
      } else {
        _items[index] = GridWordListItem(
          text:          result.text,
          symbolStem:    result.symbolStem,
          localImagePath: current?.localImagePath,
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

// ── WordList-Item-Dialog (Text + Symbol) ──────────────────────────────────────

class _WordListItemDialog extends StatefulWidget {
  final String initialText;
  final String? initialStem;
  final dynamic assetResolver;
  final String title;

  const _WordListItemDialog({
    required this.initialText,
    required this.initialStem,
    required this.assetResolver,
    required this.title,
  });

  @override
  State<_WordListItemDialog> createState() => _WordListItemDialogState();
}

class _WordListItemDialogState extends State<_WordListItemDialog> {
  late TextEditingController _textCtrl;
  late TextEditingController _searchCtrl;
  String? _stem;
  List<String> _results = const [];

  @override
  void initState() {
    super.initState();
    _textCtrl   = TextEditingController(text: widget.initialText);
    _stem       = widget.initialStem;
    _searchCtrl = TextEditingController(text: _stem ?? '');
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _search(String q) {
    final r = widget.assetResolver.search(q, limit: 32) as List<String>;
    setState(() => _results = r);
  }

  void _pick(String path) {
    final base = path.split('/').last;
    final dot  = base.lastIndexOf('.');
    final stem = dot >= 0 ? base.substring(0, dot) : base;
    setState(() {
      _stem = stem;
      _results = const [];
      _searchCtrl.text = stem;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Text
              TextField(
                controller: _textCtrl,
                autofocus: true,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Text',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),

              // Symbol-Suche
              const Text('Symbol (optional)',
                  style: TextStyle(fontSize: 12, color: Colors.black54,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              if (_stem != null) ...[
                _SymbolChip(
                  stem: _stem!,
                  assetResolver: widget.assetResolver,
                  onRemove: () => setState(() {
                    _stem = null;
                    _searchCtrl.clear();
                    _results = const [];
                  }),
                ),
                const SizedBox(height: 8),
              ],
              TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  hintText: 'Symbol suchen …',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _searchCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _results = const []);
                          })
                      : null,
                  border: const OutlineInputBorder(),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 10),
                ),
                onChanged: _search,
                onSubmitted: _search,
              ),
              if (_results.isNotEmpty) ...[
                const SizedBox(height: 8),
                SizedBox(
                  height: 140,
                  child: GridView.builder(
                    shrinkWrap: true,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 5,
                      crossAxisSpacing: 4,
                      mainAxisSpacing: 4,
                      childAspectRatio: 1,
                    ),
                    itemCount: _results.length,
                    itemBuilder: (ctx, i) {
                      final path = _results[i];
                      final base = path.split('/').last;
                      final dot  = base.lastIndexOf('.');
                      final stem = dot >= 0 ? base.substring(0, dot) : base;
                      final sel  = stem == _stem;
                      return GestureDetector(
                        onTap: () => _pick(path),
                        child: Container(
                          decoration: BoxDecoration(
                            color: sel
                                ? NasiraColors.navGreen
                                : const Color(0xFFEEF2EE),
                            borderRadius: BorderRadius.circular(6),
                            border: sel
                                ? Border.all(
                                    color: NasiraColors.navGreen, width: 2)
                                : null,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(3),
                            child: Image.asset(path,
                                fit: BoxFit.contain,
                                errorBuilder: (_, __, ___) =>
                                    const Icon(Icons.broken_image_outlined,
                                        size: 16, color: Colors.grey)),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () {
            final text = _textCtrl.text.trim();
            if (text.isEmpty) return;
            Navigator.pop(context,
                GridWordListItem(text: text, symbolStem: _stem));
          },
          style: FilledButton.styleFrom(
              backgroundColor: NasiraColors.navGreen),
          child: const Text('OK'),
        ),
      ],
    );
  }
}

// ── Gewähltes Symbol als Chip ──────────────────────────────────────────────────

class _SymbolChip extends StatelessWidget {
  final String stem;
  final dynamic assetResolver;
  final VoidCallback onRemove;

  const _SymbolChip(
      {required this.stem,
      required this.assetResolver,
      required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final path = assetResolver.resolve('$stem.jpg') as String?;
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFEEF5EE),
        borderRadius: BorderRadius.circular(8),
        border:
            Border.all(color: NasiraColors.navGreen.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (path != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Image.asset(path,
                  width: 36, height: 36, fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) =>
                      const Icon(Icons.image_not_supported_outlined,
                          size: 20, color: Colors.grey)),
            ),
          const SizedBox(width: 8),
          Text(stem,
              style: const TextStyle(fontSize: 13, color: NasiraColors.textDark)),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.close, size: 16, color: Colors.black45),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}
