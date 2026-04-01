import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/grid_page.dart';
import '../nasira_app_state.dart';
import '../services/grid_override_service.dart';
import '../theme/nasira_colors.dart';

/// Vollbild-Overlay – Rasterstruktur anzeigen, Zellen markieren und bearbeiten.
///
/// Session A: Overlay-Struktur, Zellen markieren, Info-Panel, Seiten-Wechsel.
/// Session B: Caption umbenennen, Symbol suchen + zuweisen (via GridOverrideService).
class BriefGridEditorOverlay extends StatefulWidget {
  /// Alle geladenen Seiten: Grid-Name → GridPage.
  final Map<String, GridPage> pages;

  /// Name der Seite, die beim Öffnen angezeigt wird.
  final String initialPage;

  /// Service zum Persistieren von Zellen-Overrides.
  final GridOverrideService overrideService;

  /// Wird aufgerufen, wenn Änderungen gespeichert wurden (z. B. zum Neu-Laden).
  final VoidCallback onChanged;

  const BriefGridEditorOverlay({
    super.key,
    required this.pages,
    required this.initialPage,
    required this.overrideService,
    required this.onChanged,
  });

  /// Öffnet das Overlay als Vollbild-Dialog.
  static Future<void> show({
    required BuildContext context,
    required Map<String, GridPage> pages,
    required String initialPage,
    required GridOverrideService overrideService,
    required VoidCallback onChanged,
  }) =>
      Navigator.push<void>(
        context,
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => BriefGridEditorOverlay(
            pages: pages,
            initialPage: initialPage,
            overrideService: overrideService,
            onChanged: onChanged,
          ),
        ),
      );

  /// Öffnet den Zellen-Editor direkt für eine einzelne Zelle (Bottom-Sheet).
  static Future<void> showCellSheet({
    required BuildContext context,
    required GridCell cell,
    required String pageName,
    required GridOverrideService overrideService,
    required VoidCallback onChanged,
  }) async {
    final state = context.read<NasiraAppState>();
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CellEditorSheet(
        cell: cell,
        pageName: pageName,
        overrideService: overrideService,
        assetResolver: state.assetResolver,
      ),
    );
    if (changed == true) onChanged();
  }

  @override
  State<BriefGridEditorOverlay> createState() =>
      _BriefGridEditorOverlayState();
}

class _BriefGridEditorOverlayState extends State<BriefGridEditorOverlay> {
  late String _currentPageName;
  GridCell? _selectedCell;

  @override
  void initState() {
    super.initState();
    _currentPageName = widget.initialPage;
  }

  GridPage? get _page => widget.pages[_currentPageName];

  List<String> get _sortedNames => widget.pages.keys.toList()..sort();

  void _selectCell(GridCell cell) {
    setState(() {
      _selectedCell = identical(_selectedCell, cell) ? null : cell;
    });
  }

  // ── Session B: Zelle bearbeiten ───────────────────────────────────────────

  Future<void> _openCellEditor(GridCell cell) async {
    final state = context.read<NasiraAppState>();
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CellEditorSheet(
        cell: cell,
        pageName: _currentPageName,
        overrideService: widget.overrideService,
        assetResolver: state.assetResolver,
      ),
    );
    if (changed == true) {
      widget.onChanged();
      setState(() => _selectedCell = null);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A2B1A),
      appBar: _buildAppBar(),
      body: Column(
        children: [
          Expanded(
            child: _page == null
                ? const Center(
                    child: Text('Seite nicht geladen.',
                        style: TextStyle(color: Colors.white60)))
                : _buildEditGrid(_page!),
          ),
          _buildInfoPanel(),
        ],
      ),
    );
  }

  // ── App Bar ───────────────────────────────────────────────────────────────

  AppBar _buildAppBar() {
    return AppBar(
      backgroundColor: NasiraColors.navGreen,
      foregroundColor: Colors.white,
      leading: IconButton(
        icon: const Icon(Icons.close),
        tooltip: 'Schließen',
        onPressed: () => Navigator.pop(context),
      ),
      title: const Text('Seite bearbeiten',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      titleSpacing: 0,
      actions: [
        // Seiten-Auswahl Dropdown
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _currentPageName,
              dropdownColor: const Color(0xFF3A5A3A),
              style: const TextStyle(color: Colors.white, fontSize: 12),
              icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
              items: _sortedNames
                  .map((name) => DropdownMenuItem(
                        value: name,
                        child: Text(name,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 12)),
                      ))
                  .toList(),
              onChanged: (name) {
                if (name != null) {
                  setState(() {
                    _currentPageName = name;
                    _selectedCell = null;
                  });
                }
              },
            ),
          ),
        ),
      ],
    );
  }

  // ── Edit-Raster ───────────────────────────────────────────────────────────

  Widget _buildEditGrid(GridPage page) {
    final wsCell =
        page.cells.where((c) => c.type == GridCellType.workspace).firstOrNull;
    final firstContent = wsCell != null ? wsCell.y + wsCell.rowSpan : 0;
    final contentRows = page.rows - firstContent;
    if (contentRows <= 0) return const SizedBox.shrink();

    final contentCells = page.cells
        .where((c) => c.type != GridCellType.workspace && c.y >= firstContent)
        .toList();

    const gap = 4.0;

    return Padding(
      padding: const EdgeInsets.all(6),
      child: LayoutBuilder(builder: (ctx, box) {
        final cellW = box.maxWidth / page.columns;
        final cellH = box.maxHeight / contentRows;

        return Stack(
          children: contentCells.map((cell) {
            final isSelected = identical(_selectedCell, cell);
            return Positioned(
              left: cell.x * cellW + gap / 2,
              top: (cell.y - firstContent) * cellH + gap / 2,
              width: cell.colSpan * cellW - gap,
              height: cell.rowSpan * cellH - gap,
              child: _buildEditCell(cell, isSelected),
            );
          }).toList(),
        );
      }),
    );
  }

  // ── Einzelne Edit-Kachel ─────────────────────────────────────────────────

  Widget _buildEditCell(GridCell cell, bool isSelected) {
    final caption = cell.caption?.isNotEmpty == true
        ? cell.caption!
        : cell.insertText?.trim() ?? '';

    final radius = cell.style.isOval ? 100.0 : 6.0;

    return GestureDetector(
      onTap: () => _selectCell(cell),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        decoration: BoxDecoration(
          color: isSelected
              ? cell.backgroundColor
              : cell.backgroundColor.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(
            color: isSelected ? Colors.white : Colors.white38,
            width: isSelected ? 2.5 : 1.0,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.white.withValues(alpha: 0.25),
                    blurRadius: 6,
                    spreadRadius: 1,
                  )
                ]
              : null,
        ),
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            // Caption-Text
            if (caption.isNotEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Text(
                    caption,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.white70,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                    ),
                  ),
                ),
              ),

            // AutoContent-Indikator (≡ Symbol)
            if (cell.type == GridCellType.autoContent)
              Positioned(
                bottom: 2,
                right: 3,
                child: Icon(Icons.list,
                    size: 9, color: Colors.white.withValues(alpha: 0.5)),
              ),

            // Ausgewählt-Badge
            if (isSelected)
              const Positioned(
                top: 2,
                right: 2,
                child: SizedBox(
                  width: 15,
                  height: 15,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.check,
                        size: 10, color: NasiraColors.navGreen),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── Info-Panel (unten) ───────────────────────────────────────────────────

  Widget _buildInfoPanel() {
    final cell = _selectedCell;

    if (cell == null) {
      return Container(
        height: 68,
        color: const Color(0xFF243024),
        alignment: Alignment.center,
        child: const Text(
          'Kachel antippen zum Auswählen',
          style: TextStyle(color: Colors.white54, fontSize: 13),
        ),
      );
    }

    final caption = cell.caption?.isNotEmpty == true
        ? cell.caption!
        : cell.insertText?.trim() ?? '—';

    final typeLabel = switch (cell.type) {
      GridCellType.autoContent => 'AutoContent',
      GridCellType.workspace   => 'Workspace',
      GridCellType.normal      => 'Normal',
      GridCellType.empty       => 'Leer',
    };

    final sizeLabel =
        '${cell.colSpan}×${cell.rowSpan}  |  Pos (${cell.x}, ${cell.y})';

    final styleLabel = cell.style.name;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: const BoxDecoration(
        color: Color(0xFF243024),
        border: Border(top: BorderSide(color: Colors.white12, width: 1)),
      ),
      child: Row(
        children: [
          // Farbvorschau der Zelle
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: cell.backgroundColor,
              borderRadius:
                  BorderRadius.circular(cell.style.isOval ? 21 : 6),
              border: Border.all(color: Colors.white30),
            ),
          ),
          const SizedBox(width: 12),

          // Infos
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  caption,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '$typeLabel  |  $styleLabel  |  $sizeLabel',
                  style: const TextStyle(color: Colors.white54, fontSize: 10.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // Bearbeiten-Button (Session B)
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            color: Colors.white,
            iconSize: 22,
            tooltip: 'Zelle bearbeiten',
            onPressed: () => _openCellEditor(cell),
          ),
        ],
      ),
    );
  }
}

// ── Zellen-Editor Bottom-Sheet ────────────────────────────────────────────────

class _CellEditorSheet extends StatefulWidget {
  final GridCell cell;
  final String pageName;
  final GridOverrideService overrideService;
  final dynamic assetResolver; // AssetResolverService

  const _CellEditorSheet({
    required this.cell,
    required this.pageName,
    required this.overrideService,
    required this.assetResolver,
  });

  @override
  State<_CellEditorSheet> createState() => _CellEditorSheetState();
}

// ── Befehlstyp-Labels (Deutsch) ──────────────────────────────────────────────
const _kCommandLabels = <GridCommandType, String>{
  GridCommandType.insertText:   'Text einfügen',
  GridCommandType.jumpTo:       'Springe zu Seite',
  GridCommandType.jumpBack:     'Zurück',
  GridCommandType.jumpHome:     'Startseite',
  GridCommandType.punctuation:  'Satzzeichen',
  GridCommandType.deleteWord:   'Wort löschen',
  GridCommandType.deleteLetter: 'Buchstabe löschen',
  GridCommandType.enter:        'Enter / Neue Zeile',
  GridCommandType.moreWords:    'Mehr Wörter',
  GridCommandType.capsLock:     'Großschreibung (CapsLock)',
  GridCommandType.shift:        'Shift',
  GridCommandType.speak:        'Vorlesen (TTS)',
};

class _CellEditorSheetState extends State<_CellEditorSheet> {
  late TextEditingController _captionCtrl;
  late TextEditingController _searchCtrl;
  late TextEditingController _insertTextCtrl;
  late TextEditingController _jumpTargetCtrl;
  late TextEditingController _punctuationCtrl;

  /// Der aktuell gewählte Symbol-Stem (null = kein Override).
  String? _pendingStem;

  /// Suchergebnisse (Asset-Pfade).
  List<String> _searchResults = const [];

  /// Aktuell gewählter Befehlstyp (null = kein Befehl).
  GridCommandType? _cmdType;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.overrideService.getCellOverride(
      widget.pageName, widget.cell.x, widget.cell.y,
    );
    _captionCtrl = TextEditingController(
      text: existing?['caption'] as String? ??
          widget.cell.caption ??
          widget.cell.insertText?.trim() ??
          '',
    );
    _pendingStem = existing?['symbolStem'] as String? ?? widget.cell.symbolStem;
    _searchCtrl = TextEditingController(text: _pendingStem ?? '');

    // Befehl initialisieren: Override hat Vorrang, sonst erster XML-Befehl
    final rawCmds = existing?['commands'] as List?;
    if (rawCmds != null && rawCmds.isNotEmpty) {
      final m = rawCmds.first as Map<String, dynamic>;
      _cmdType = GridCommandType.values.firstWhere(
        (t) => t.name == (m['type'] as String? ?? ''),
        orElse: () => GridCommandType.other,
      );
      _insertTextCtrl  = TextEditingController(text: m['insertText']  as String? ?? '');
      _jumpTargetCtrl  = TextEditingController(text: m['jumpTarget']  as String? ?? '');
      _punctuationCtrl = TextEditingController(text: m['punctuation'] as String? ?? '');
    } else if (widget.cell.commands.isNotEmpty) {
      final cmd = widget.cell.commands.first;
      _cmdType         = cmd.type;
      _insertTextCtrl  = TextEditingController(text: cmd.insertText  ?? '');
      _jumpTargetCtrl  = TextEditingController(text: cmd.jumpTarget  ?? '');
      _punctuationCtrl = TextEditingController(text: cmd.punctuation ?? '');
    } else {
      _cmdType         = null;
      _insertTextCtrl  = TextEditingController();
      _jumpTargetCtrl  = TextEditingController();
      _punctuationCtrl = TextEditingController();
    }
  }

  @override
  void dispose() {
    _captionCtrl.dispose();
    _searchCtrl.dispose();
    _insertTextCtrl.dispose();
    _jumpTargetCtrl.dispose();
    _punctuationCtrl.dispose();
    super.dispose();
  }

  // ── Suche ─────────────────────────────────────────────────────────────────

  void _runSearch(String query) {
    final results = widget.assetResolver.search(query, limit: 48) as List<String>;
    setState(() => _searchResults = results);
  }

  void _pickAsset(String assetPath) {
    final base  = assetPath.split('/').last;
    final dot   = base.lastIndexOf('.');
    final stem  = dot >= 0 ? base.substring(0, dot) : base;
    setState(() {
      _pendingStem    = stem;
      _searchResults  = const [];
      _searchCtrl.text = stem;
    });
  }

  // ── Speichern / Reset ─────────────────────────────────────────────────────

  Future<void> _save() async {
    setState(() => _saving = true);
    final caption = _captionCtrl.text.trim();

    // Befehlsliste aus Dialog-Feldern zusammenstellen
    List<Map<String, dynamic>>? commands;
    if (_cmdType != null) {
      final cmd = <String, dynamic>{'type': _cmdType!.name};
      if (_cmdType == GridCommandType.insertText) {
        cmd['insertText'] = _insertTextCtrl.text;
      } else if (_cmdType == GridCommandType.jumpTo) {
        cmd['jumpTarget'] = _jumpTargetCtrl.text.trim();
      } else if (_cmdType == GridCommandType.punctuation) {
        cmd['punctuation'] = _punctuationCtrl.text.isNotEmpty
            ? _punctuationCtrl.text[0]
            : '.';
      }
      commands = [cmd];
    } else {
      commands = []; // Leere Liste = alle Befehle entfernen
    }

    await widget.overrideService.setCellOverride(
      widget.pageName,
      widget.cell.x,
      widget.cell.y,
      caption:    caption.isNotEmpty ? caption : null,
      symbolStem: _pendingStem,
      commands:   commands,
    );
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _resetCell() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Zelle zurücksetzen?'),
        content: const Text('Caption und Symbol werden auf den Original-Wert zurückgesetzt.'),
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
    await widget.overrideService.clearCellOverride(
      widget.pageName, widget.cell.x, widget.cell.y,
    );
    if (mounted) Navigator.pop(context, true);
  }

  InputDecoration _inputDeco(String hint) => InputDecoration(
    filled: true,
    fillColor: const Color(0xFF2A3E2A),
    hintText: hint,
    hintStyle: const TextStyle(color: Colors.white38),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide.none,
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
  );

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final hasOverride = widget.overrideService.getCellOverride(
          widget.pageName, widget.cell.x, widget.cell.y) !=
        null;

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.50,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1E2E1E),
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
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),

            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 8, 10),
              child: Row(
                children: [
                  const Icon(Icons.edit_outlined,
                      size: 18, color: NasiraColors.navGreen),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Zelle (${widget.cell.x}, ${widget.cell.y}) bearbeiten',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  if (hasOverride)
                    TextButton.icon(
                      onPressed: _resetCell,
                      icon: const Icon(Icons.restore, size: 16),
                      label: const Text('Zurücksetzen'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.red.shade300,
                        textStyle: const TextStyle(fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),

            const Divider(height: 1, color: Colors.white12),

            // Scrollbarer Inhalt
            Expanded(
              child: ListView(
                controller: scrollCtrl,
                padding: const EdgeInsets.all(16),
                children: [
                  // ── Caption ─────────────────────────────────────────────
                  const Text('Beschriftung',
                      style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _captionCtrl,
                    style: const TextStyle(color: Colors.white),
                    maxLines: 2,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: const Color(0xFF2A3E2A),
                      hintText: 'Beschriftung eingeben …',
                      hintStyle: const TextStyle(color: Colors.white38),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // ── Symbol ──────────────────────────────────────────────
                  Row(
                    children: [
                      const Text('Symbol',
                          style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                      const Spacer(),
                      if (_pendingStem != null)
                        TextButton.icon(
                          onPressed: () => setState(() {
                            _pendingStem = null;
                            _searchCtrl.clear();
                            _searchResults = const [];
                          }),
                          icon: const Icon(Icons.close, size: 14),
                          label: const Text('Entfernen',
                              style: TextStyle(fontSize: 12)),
                          style: TextButton.styleFrom(
                              foregroundColor: Colors.white54),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),

                  // Aktuelle Symbol-Vorschau
                  if (_pendingStem != null)
                    _SymbolPreview(
                      stem: _pendingStem!,
                      assetResolver: widget.assetResolver,
                    ),

                  const SizedBox(height: 10),

                  // Suchfeld
                  TextField(
                    controller: _searchCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: const Color(0xFF2A3E2A),
                      hintText: 'Symbol suchen (z. B. „katze") …',
                      hintStyle: const TextStyle(color: Colors.white38),
                      prefixIcon: const Icon(Icons.search,
                          color: Colors.white54, size: 20),
                      suffixIcon: _searchCtrl.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear,
                                  color: Colors.white38, size: 18),
                              onPressed: () {
                                _searchCtrl.clear();
                                setState(() => _searchResults = const []);
                              },
                            )
                          : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                    ),
                    onChanged: _runSearch,
                    onSubmitted: _runSearch,
                  ),

                  // Suchergebnisse
                  if (_searchResults.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 4,
                        crossAxisSpacing: 6,
                        mainAxisSpacing: 6,
                        childAspectRatio: 1,
                      ),
                      itemCount: _searchResults.length,
                      itemBuilder: (ctx, i) {
                        final path = _searchResults[i];
                        final base = path.split('/').last;
                        final dot  = base.lastIndexOf('.');
                        final stem = dot >= 0 ? base.substring(0, dot) : base;
                        final isActive = stem == _pendingStem;
                        return GestureDetector(
                          onTap: () => _pickAsset(path),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 100),
                            decoration: BoxDecoration(
                              color: isActive
                                  ? NasiraColors.navGreen
                                  : const Color(0xFF2A3E2A),
                              borderRadius: BorderRadius.circular(8),
                              border: isActive
                                  ? Border.all(
                                      color: Colors.white, width: 2)
                                  : null,
                            ),
                            child: Column(
                              children: [
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.all(4),
                                    child: Image.asset(
                                      path,
                                      fit: BoxFit.contain,
                                      errorBuilder: (_, __, ___) =>
                                          const Icon(Icons.image_not_supported,
                                              size: 24, color: Colors.white24),
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(2, 0, 2, 3),
                                  child: Text(
                                    stem,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: isActive
                                          ? Colors.white
                                          : Colors.white54,
                                      fontSize: 8,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ],

                  const SizedBox(height: 24),

                  // ── Funktion / Befehl ────────────────────────────────────
                  const Text('Funktion',
                      style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<GridCommandType?>(
                    initialValue: _cmdType,
                    dropdownColor: const Color(0xFF2A3E2A),
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: const Color(0xFF2A3E2A),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                    ),
                    items: [
                      const DropdownMenuItem(
                          value: null,
                          child: Text('Keine Funktion',
                              style: TextStyle(color: Colors.white54))),
                      ...GridCommandType.values
                          .where((t) => _kCommandLabels.containsKey(t))
                          .map((t) => DropdownMenuItem(
                                value: t,
                                child: Text(_kCommandLabels[t]!),
                              )),
                    ],
                    onChanged: (val) => setState(() => _cmdType = val),
                  ),

                  // Bedingte Eingabefelder je nach Befehlstyp
                  if (_cmdType == GridCommandType.insertText) ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: _insertTextCtrl,
                      style: const TextStyle(color: Colors.white),
                      decoration: _inputDeco('Einzufügender Text …'),
                    ),
                  ],
                  if (_cmdType == GridCommandType.jumpTo) ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: _jumpTargetCtrl,
                      style: const TextStyle(color: Colors.white),
                      decoration: _inputDeco('Zielseiten-Name (exakt wie im Grid3-Export)'),
                    ),
                  ],
                  if (_cmdType == GridCommandType.punctuation) ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: _punctuationCtrl,
                      style: const TextStyle(color: Colors.white),
                      maxLength: 1,
                      decoration: _inputDeco('Zeichen (z. B. . , ? ! …)'),
                    ),
                  ],

                  const SizedBox(height: 80), // Platz für Footer
                ],
              ),
            ),

            // Footer
            const Divider(height: 1, color: Colors.white12),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                child: Row(
                  children: [
                    OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white54,
                        side: const BorderSide(color: Colors.white24),
                      ),
                      child: const Text('Abbrechen'),
                    ),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.check, size: 18),
                      label: const Text('Speichern'),
                      style: FilledButton.styleFrom(
                        backgroundColor: NasiraColors.navGreen,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Aktuelles-Symbol-Vorschau ─────────────────────────────────────────────────

class _SymbolPreview extends StatelessWidget {
  final String stem;
  final dynamic assetResolver;

  const _SymbolPreview({required this.stem, required this.assetResolver});

  @override
  Widget build(BuildContext context) {
    final path = assetResolver.resolve('$stem.jpg') as String?;

    return Container(
      height: 72,
      decoration: BoxDecoration(
        color: const Color(0xFF2A3E2A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: NasiraColors.navGreen.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 12),
          SizedBox(
            width: 56,
            height: 56,
            child: path != null
                ? Image.asset(path, fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(
                        Icons.broken_image_outlined,
                        color: Colors.white38))
                : const Icon(Icons.image_not_supported_outlined,
                    color: Colors.white38, size: 28),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              stem,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (path == null)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Text('nicht gefunden',
                  style: TextStyle(color: Colors.red, fontSize: 11)),
            ),
          const SizedBox(width: 12),
        ],
      ),
    );
  }
}
