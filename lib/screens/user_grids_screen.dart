import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/grid_page.dart';
import '../nasira_app_state.dart';
import '../services/grid_override_service.dart';
import '../theme/nasira_colors.dart';
import '../widgets/grid_layout_editor.dart';

// ── Meine Grids Screen ────────────────────────────────────────────────────────

/// Liste aller vom User erstellten Grids mit Erstellen- und Löschen-Funktion.
class UserGridsScreen extends StatefulWidget {
  const UserGridsScreen({super.key});

  @override
  State<UserGridsScreen> createState() => _UserGridsScreenState();
}

class _UserGridsScreenState extends State<UserGridsScreen> {
  late final GridOverrideService _svc;
  List<({String name, int columns, int rows})> _grids = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _svc = GridOverrideService();
    _loadService();
  }

  Future<void> _loadService() async {
    await _svc.load();
    if (mounted) {
      setState(() {
        _grids   = _svc.listUserGrids();
        _loading = false;
      });
    }
  }

  void _refresh() => setState(() => _grids = _svc.listUserGrids());

  // ── Erstellen ─────────────────────────────────────────────────────────────

  Future<void> _createGrid() async {
    final result = await showDialog<({String name, int cols, int rows})>(
      context: context,
      builder: (_) => const _NewGridDialog(),
    );
    if (result == null || !mounted) return;

    // Name darf nicht leer und nicht bereits vorhanden sein
    if (_grids.any((g) => g.name == result.name)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('„${result.name}" existiert bereits.'),
          backgroundColor: Colors.red.shade700,
        ),
      );
      return;
    }
    await _svc.createUserGrid(result.name, result.cols, result.rows);
    _refresh();
    if (mounted) _openGrid(result.name);
  }

  // ── Öffnen ────────────────────────────────────────────────────────────────

  Future<void> _openGrid(String name) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _UserGridEditorPage(name: name, svc: _svc),
      ),
    );
    _refresh();
  }

  // ── Löschen ───────────────────────────────────────────────────────────────

  Future<void> _deleteGrid(String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Grid löschen?'),
        content: Text('„$name" und alle darin enthaltenen Zellen werden '
            'unwiderruflich gelöscht.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _svc.deleteUserGrid(name);
    _refresh();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A2A1A),
      appBar: AppBar(
        title: const Text('Meine Grids',
            style: TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: NasiraColors.navGreen,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createGrid,
        icon: const Icon(Icons.add),
        label: const Text('Neues Grid'),
        backgroundColor: NasiraColors.navGreen,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: NasiraColors.navGreen))
          : _grids.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'Noch keine Grids erstellt.\n\n'
                      'Tippe auf „Neues Grid", um ein leeres Kommunikations-Grid '
                      'zu erstellen und mit dem Editor zu befüllen.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white54, fontSize: 14, height: 1.5),
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                  itemCount: _grids.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _buildTile(_grids[i]),
                ),
    );
  }

  Widget _buildTile(({String name, int columns, int rows}) grid) {
    return Material(
      color: const Color(0xFF253525),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _openGrid(grid.name),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Row(
            children: [
              const Icon(Icons.grid_view_rounded,
                  color: NasiraColors.navGreen, size: 32),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(grid.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        )),
                    const SizedBox(height: 2),
                    Text(
                      '${grid.columns} Spalten × ${grid.rows} Zeilen',
                      style: const TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline,
                    color: Colors.red, size: 20),
                tooltip: 'Grid löschen',
                onPressed: () => _deleteGrid(grid.name),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Grid-Editor-Seite ─────────────────────────────────────────────────────────

class _UserGridEditorPage extends StatefulWidget {
  final String name;
  final GridOverrideService svc;

  const _UserGridEditorPage({required this.name, required this.svc});

  @override
  State<_UserGridEditorPage> createState() => _UserGridEditorPageState();
}

class _UserGridEditorPageState extends State<_UserGridEditorPage> {
  late GridPage _page;

  @override
  void initState() {
    super.initState();
    _page = widget.svc.buildUserGridPage(widget.name);
  }

  void _onChanged() =>
      setState(() => _page = widget.svc.buildUserGridPage(widget.name));

  Widget _buildCell(GridCell cell, dynamic assetResolver) {
    final caption = cell.caption?.isNotEmpty == true ? cell.caption! : '';
    final radius  = cell.isFullyRounded ? 100.0 : 8.0;
    return Container(
      decoration: BoxDecoration(
        color: cell.backgroundColor,
        borderRadius: BorderRadius.circular(radius),
      ),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(4),
      child: caption.isNotEmpty
          ? Text(
              caption,
              style: TextStyle(
                color: cell.foregroundColor,
                fontSize: cell.fontSizeOverride ?? 12,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            )
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final assetResolver =
        context.read<NasiraAppState>().assetResolver;
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: GridLayoutEditor(
          page:            _page,
          pageName:        widget.name,
          pageColor:       Colors.white,
          overrideService: widget.svc,
          cellBuilder:     (cell) => _buildCell(cell, assetResolver),
          onDismiss:       () => Navigator.pop(context),
          onChanged:       _onChanged,
        ),
      ),
    );
  }
}

// ── Dialog: Neues Grid erstellen ──────────────────────────────────────────────

class _NewGridDialog extends StatefulWidget {
  const _NewGridDialog();

  @override
  State<_NewGridDialog> createState() => _NewGridDialogState();
}

class _NewGridDialogState extends State<_NewGridDialog> {
  final _nameCtrl = TextEditingController();
  int _cols = 8;
  int _rows = 5;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    Navigator.pop(context, (name: name, cols: _cols, rows: _rows));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Neues Grid erstellen'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameCtrl,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Name',
              hintText: 'z. B. „Freizeit" oder „Gefühle"',
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              const Text('Spalten:', style: TextStyle(fontSize: 14)),
              const Spacer(),
              _Counter(
                value: _cols,
                min: 1,
                max: 16,
                onChanged: (v) => setState(() => _cols = v),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('Zeilen:', style: TextStyle(fontSize: 14)),
              const Spacer(),
              _Counter(
                value: _rows,
                min: 1,
                max: 12,
                onChanged: (v) => setState(() => _rows = v),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: _submit,
          style: FilledButton.styleFrom(
              backgroundColor: NasiraColors.navGreen),
          child: const Text('Erstellen'),
        ),
      ],
    );
  }
}

// ── Zähler-Widget (+ / –) ─────────────────────────────────────────────────────

class _Counter extends StatelessWidget {
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  const _Counter({
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.remove_circle_outline),
          onPressed: value > min ? () => onChanged(value - 1) : null,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        ),
        SizedBox(
          width: 28,
          child: Text(
            '$value',
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.add_circle_outline),
          onPressed: value < max ? () => onChanged(value + 1) : null,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        ),
      ],
    );
  }
}
