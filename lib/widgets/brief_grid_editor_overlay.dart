import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/grid_page.dart';
import '../nasira_app_state.dart';
import '../services/grid_override_service.dart';
import '../services/grid_style_service.dart';
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

    final radius = cell.isFullyRounded ? 100.0 : 6.0;

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
      GridCellType.liveCell    => 'LiveCell',
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
                  BorderRadius.circular(cell.isFullyRounded ? 21 : 6),
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
  GridCommandType.setBookmark:          'Lesezeichen setzen',
  GridCommandType.documentEnd:          'Cursor ans Ende',
  GridCommandType.copyText:             'Text kopieren',
  GridCommandType.pasteText:            'Text einfügen (Clipboard)',
  GridCommandType.printText:            'Drucken',
  GridCommandType.settingsExit:         'Beenden',
  GridCommandType.textEditorNew:        'Neues Dokument',
  GridCommandType.textEditorDelete:     'Dokument löschen',
  GridCommandType.textEditorPrevious:   'Vorheriges Dokument',
  GridCommandType.textEditorNext:       'Nächstes Dokument',
  GridCommandType.previousLetter:       'Vorheriger Buchstabe',
  GridCommandType.nextLetter:           'Nächster Buchstabe',
  GridCommandType.previousWord:         'Vorheriges Wort',
  GridCommandType.nextWord:             'Nächstes Wort',
  GridCommandType.previousSentence:     'Vorheriger Satz',
  GridCommandType.nextSentence:         'Nächster Satz',
  GridCommandType.previousLine:         'Vorherige Zeile',
  GridCommandType.nextLine:             'Nächste Zeile',
  GridCommandType.documentStart:        'Textanfang',
  GridCommandType.changeWordList:       'Wortliste wechseln',
  GridCommandType.revertWordList:       'Standard-Wortliste',
};

// ── Mutable Segment (für insertText-Chip-Editor) ──────────────────────────────

class _Segment {
  String type;  // 'text' | 'symbol'
  String value; // Textinhalt oder Symbol-Stem

  _Segment.text(this.value) : type = 'text';
  _Segment.symbol(this.value) : type = 'symbol';
}

// ── Mutable Befehlseintrag ────────────────────────────────────────────────────

/// Hält den veränderbaren Zustand eines einzelnen Befehls im Editor.
class _CmdEntry {
  GridCommandType? type;
  final TextEditingController paramCtrl;
  /// Nur für insertText: strukturierte Segmente (Text + konkrete Symbole).
  final List<_Segment> segments;

  _CmdEntry(this.type, String param, [List<_Segment>? segs])
      : paramCtrl = TextEditingController(text: param),
        segments  = segs ?? [];

  /// Wandelt in JSON-Map um (für Override-Service).
  Map<String, dynamic> toJson() {
    if (type == null) return {};
    final m = <String, dynamic>{'type': type!.name};
    final p = paramCtrl.text;
    if (type == GridCommandType.insertText) {
      if (segments.isNotEmpty) {
        // Segment-Modus: strukturierte Liste + Plaintext-Fallback für AAC-Ausführung
        m['segments'] = segments.map((s) => {
          'type': s.type,
          if (s.type == 'text')   'value': s.value,
          if (s.type == 'symbol') 'stem':  s.value,
        }).toList();
        m['insertText'] = segments
            .where((s) => s.type == 'text')
            .map((s) => s.value)
            .join('');
      } else {
        m['insertText'] = p;
      }
    } else if (type == GridCommandType.jumpTo) {
      m['jumpTarget'] = p.trim();
    } else if (type == GridCommandType.punctuation) {
      m['punctuation'] = p.isNotEmpty ? p[0] : '.';
    }
    return m;
  }

  void dispose() => paramCtrl.dispose();
}

class _CellEditorSheetState extends State<_CellEditorSheet> {
  late TextEditingController _captionCtrl;
  late TextEditingController _searchCtrl;

  /// Der aktuell gewählte Symbol-Stem (null = kein Override).
  String? _pendingStem;

  /// Form-Überschreibung: 'roundedRect' | 'oval' | 'pill' | null (= Originalform).
  String? _pendingShape;

  /// Hintergrundfarbe-Override (null = Originalfarbe).
  Color? _pendingBgColor;

  /// Textfarbe-Override (null = Originalfarbe).
  Color? _pendingFgColor;

  /// Schriftgröße-Override in pt (null = Standardgröße des Screens).
  double? _pendingFontSize;

  /// Suchergebnisse (Asset-Pfade).
  List<String> _searchResults = const [];

  /// Alle Befehle dieser Zelle (kann leer sein).
  List<_CmdEntry> _commands = [];

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
    _pendingStem    = existing?['symbolStem'] as String? ?? widget.cell.symbolStem;
    _pendingShape   = existing?['shape']     as String?;
    _pendingBgColor  = _hexToColor(existing?['backgroundColor'] as String?);
    _pendingFgColor  = _hexToColor(existing?['fontColor']       as String?);
    _pendingFontSize = (existing?['fontSize'] as num?)?.toDouble();
    _searchCtrl = TextEditingController(text: _pendingStem ?? '');

    // Befehle laden: Override hat Vorrang, sonst alle XML-Befehle
    final rawCmds = existing?['commands'] as List?;
    if (rawCmds != null) {
      _commands = rawCmds.map((e) {
        final m    = e as Map<String, dynamic>;
        final type = GridCommandType.values.firstWhere(
          (t) => t.name == (m['type'] as String? ?? ''),
          orElse: () => GridCommandType.other,
        );
        final param = (m['insertText'] ?? m['jumpTarget'] ?? m['punctuation'] ?? '') as String;
        // Segmente für insertText-Befehle laden (oder Legacy-Text als ein Segment)
        List<_Segment>? segs;
        if (type == GridCommandType.insertText) {
          final rawSegs = m['segments'] as List?;
          if (rawSegs != null && rawSegs.isNotEmpty) {
            segs = rawSegs.map((s) {
              final sm = s as Map<String, dynamic>;
              return sm['type'] == 'symbol'
                  ? _Segment.symbol(sm['stem'] as String? ?? '')
                  : _Segment.text(sm['value'] as String? ?? '');
            }).toList();
          } else if (param.isNotEmpty) {
            segs = [_Segment.text(param)];
          } else {
            segs = [];
          }
        }
        return _CmdEntry(type, param, segs);
      }).toList();
    } else {
      _commands = widget.cell.commands.map((cmd) {
        final param = cmd.insertText ?? cmd.jumpTarget ?? cmd.punctuation ?? '';
        List<_Segment>? segs;
        if (cmd.type == GridCommandType.insertText) {
          if (cmd.segments != null && cmd.segments!.isNotEmpty) {
            segs = cmd.segments!.map((s) => s.type == 'symbol'
                ? _Segment.symbol(s.stem ?? '')
                : _Segment.text(s.text ?? '')).toList();
          } else if (param.isNotEmpty) {
            segs = [_Segment.text(param)];
          } else {
            segs = [];
          }
        }
        return _CmdEntry(cmd.type, param, segs);
      }).toList();
    }
  }

  @override
  void dispose() {
    _captionCtrl.dispose();
    _searchCtrl.dispose();
    for (final c in _commands) { c.dispose(); }
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

    // Befehlsliste aus allen _CmdEntry zusammenstellen
    final commands = _commands
        .where((c) => c.type != null)
        .map((c) => c.toJson())
        .toList();

    await widget.overrideService.setCellOverride(
      widget.pageName,
      widget.cell.x,
      widget.cell.y,
      caption:         caption.isNotEmpty ? caption : null,
      symbolStem:      _pendingStem,
      commands:        commands,
      shape:           _pendingShape,
      backgroundColor: _pendingBgColor != null
          ? _colorToHex(_pendingBgColor!)
          : '',   // '' = Eintrag löschen wenn kein Override
      fontColor:       _pendingFgColor != null
          ? _colorToHex(_pendingFgColor!)
          : '',
      fontSize:        _pendingFontSize,
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

  // ── Einzelne Befehl-Zeile ─────────────────────────────────────────────────

  Widget _buildCommandRow(int index) {
    final entry = _commands[index];

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
      decoration: BoxDecoration(
        color: const Color(0xFF253525),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Nummer
              SizedBox(
                width: 20,
                child: Text('${index + 1}.',
                    style: const TextStyle(
                        color: Colors.white38, fontSize: 11)),
              ),
              // Typ-Dropdown
              Expanded(
                child: DropdownButton<GridCommandType?>(
                  value: _kCommandLabels.containsKey(entry.type) ? entry.type : null,
                  isExpanded: true,
                  dropdownColor: const Color(0xFF253525),
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  underline: const SizedBox.shrink(),
                  hint: const Text('Funktion wählen …',
                      style: TextStyle(color: Colors.white38, fontSize: 12)),
                  items: [
                    const DropdownMenuItem(
                        value: null,
                        child: Text('— Keine —',
                            style: TextStyle(color: Colors.white38))),
                    ...GridCommandType.values
                        .where((t) => _kCommandLabels.containsKey(t))
                        .map((t) => DropdownMenuItem(
                              value: t,
                              child: Text(_kCommandLabels[t]!,
                                  style: const TextStyle(fontSize: 12)),
                            )),
                  ],
                  onChanged: (val) => setState(() => entry.type = val),
                ),
              ),
              // Reihenfolge: hoch
              if (index > 0)
                IconButton(
                  icon: const Icon(Icons.arrow_upward,
                      size: 16, color: Colors.white38),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  onPressed: () => setState(() {
                    _commands.insert(index - 1, _commands.removeAt(index));
                  }),
                ),
              // Reihenfolge: runter
              if (index < _commands.length - 1)
                IconButton(
                  icon: const Icon(Icons.arrow_downward,
                      size: 16, color: Colors.white38),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  onPressed: () => setState(() {
                    _commands.insert(index + 1, _commands.removeAt(index));
                  }),
                ),
              // Löschen
              IconButton(
                icon: const Icon(Icons.close, size: 16, color: Colors.red),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                onPressed: () => setState(() {
                  _commands[index].dispose();
                  _commands.removeAt(index);
                }),
              ),
            ],
          ),
          // Parameter-Feld (typ-abhängig)
          if (entry.type == GridCommandType.insertText) ...[
            const SizedBox(height: 8),
            _SegmentChipEditor(
              segments:      entry.segments,
              assetResolver: widget.assetResolver,
              onChanged:     () => setState(() {}),
            ),
          ] else if (entry.type == GridCommandType.jumpTo ||
                     entry.type == GridCommandType.punctuation) ...[
            const SizedBox(height: 6),
            TextField(
              controller: entry.paramCtrl,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              maxLines:   1,
              maxLength:  entry.type == GridCommandType.punctuation ? 1 : null,
              decoration: _inputDeco(
                entry.type == GridCommandType.jumpTo
                    ? 'Zielseiten-Name (exakt)'
                    : 'Zeichen (. , ? ! …)',
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Farb-Hilfsfunktionen ──────────────────────────────────────────────────

  /// Parst einen 8-stelligen AARRGGBB-Hex-String in eine Color (oder null).
  static Color? _hexToColor(String? hex) {
    if (hex == null || hex.length != 8) return null;
    final val = int.tryParse(hex, radix: 16);
    return val == null ? null : Color(val);
  }

  /// Wandelt eine Color in einen 8-stelligen AARRGGBB-Hex-String um.
  static String _colorToHex(Color c) =>
      c.toARGB32().toRadixString(16).padLeft(8, '0');

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

                  const SizedBox(height: 20),

                  // ── Form ────────────────────────────────────────────────
                  const Text('Form',
                      style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  _ShapeSelector(
                    value: _pendingShape,
                    onChanged: (v) => setState(() => _pendingShape = v),
                  ),

                  const SizedBox(height: 20),

                  // ── Stil-Vorlage (Named Styles) ──────────────────────────
                  const Text('Stil-Vorlage',
                      style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  const Text(
                    'Setzt Hintergrundfarbe, Textfarbe und Form auf einmal.',
                    style: TextStyle(color: Colors.white38, fontSize: 10.5),
                  ),
                  const SizedBox(height: 8),
                  _NamedStylePicker(
                    pendingBgColor: _pendingBgColor,
                    pendingFgColor: _pendingFgColor,
                    pendingShape:   _pendingShape,
                    onPick: (bg, fg, shape) => setState(() {
                      _pendingBgColor = bg;
                      _pendingFgColor = fg;
                      _pendingShape   = shape;
                    }),
                  ),

                  const SizedBox(height: 20),

                  // ── Hintergrundfarbe ─────────────────────────────────────
                  Row(
                    children: [
                      const Text('Hintergrundfarbe',
                          style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                      const Spacer(),
                      if (_pendingBgColor != null)
                        GestureDetector(
                          onTap: () => setState(() => _pendingBgColor = null),
                          child: const Text('Original',
                              style: TextStyle(
                                  color: Colors.white38, fontSize: 11)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _ColorSwatchPicker(
                    selected: _pendingBgColor,
                    onChanged: (c) => setState(() => _pendingBgColor = c),
                  ),

                  const SizedBox(height: 20),

                  // ── Textfarbe ────────────────────────────────────────────
                  Row(
                    children: [
                      const Text('Textfarbe',
                          style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                      const Spacer(),
                      if (_pendingFgColor != null)
                        GestureDetector(
                          onTap: () => setState(() => _pendingFgColor = null),
                          child: const Text('Original',
                              style: TextStyle(
                                  color: Colors.white38, fontSize: 11)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _ColorSwatchPicker(
                    selected: _pendingFgColor,
                    onChanged: (c) => setState(() => _pendingFgColor = c),
                  ),

                  const SizedBox(height: 20),

                  // ── Schriftgröße ─────────────────────────────────────────
                  Row(
                    children: [
                      const Text('Schriftgröße',
                          style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                      const Spacer(),
                      Text(
                        _pendingFontSize != null
                            ? '${_pendingFontSize!.round()} pt'
                            : 'Original',
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 12),
                      ),
                      if (_pendingFontSize != null) ...[
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () =>
                              setState(() => _pendingFontSize = null),
                          child: const Icon(Icons.close,
                              size: 14, color: Colors.white38),
                        ),
                      ],
                    ],
                  ),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: NasiraColors.navGreen,
                      thumbColor: NasiraColors.navGreen,
                      inactiveTrackColor: Colors.white12,
                      overlayColor:
                          NasiraColors.navGreen.withValues(alpha: 0.2),
                      trackHeight: 3,
                    ),
                    child: Slider(
                      value: _pendingFontSize ?? 13,
                      min: 8,
                      max: 40,
                      divisions: 32,
                      onChanged: (v) =>
                          setState(() => _pendingFontSize = v),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // ── Funktionen / Befehle (Liste) ─────────────────────────
                  Row(
                    children: [
                      const Text('Funktionen',
                          style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () => setState(
                            () => _commands.add(_CmdEntry(null, ''))),
                        icon: const Icon(Icons.add, size: 14),
                        label: const Text('Hinzufügen',
                            style: TextStyle(fontSize: 12)),
                        style: TextButton.styleFrom(
                            foregroundColor: NasiraColors.navGreen),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),

                  if (_commands.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2A3E2A),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text('Keine Funktion',
                          style: TextStyle(
                              color: Colors.white38, fontSize: 13)),
                    )
                  else
                    for (int i = 0; i < _commands.length; i++)
                      _buildCommandRow(i),

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

// ── Form-Auswahl (3 Toggle-Buttons) ──────────────────────────────────────────

class _ShapeSelector extends StatelessWidget {
  /// Aktuell gewählte Form: 'roundedRect' | 'oval' | 'pill' | null (= Original).
  final String? value;
  final ValueChanged<String?> onChanged;

  const _ShapeSelector({required this.value, required this.onChanged});

  static const _shapes = [
    ('roundedRect', 'Abgerundet', 8.0),
    ('oval',        'Oval',       100.0),
    ('pill',        'Pille',      100.0),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // "Original"-Button
        _ShapeBtn(
          label: 'Original',
          borderRadius: 8,
          isSelected: value == null,
          onTap: () => onChanged(null),
        ),
        const SizedBox(width: 6),
        for (final (key, label, radius) in _shapes) ...[
          _ShapeBtn(
            label: label,
            borderRadius: radius,
            isSelected: value == key,
            onTap: () => onChanged(key),
          ),
          const SizedBox(width: 6),
        ],
      ],
    );
  }
}

class _ShapeBtn extends StatelessWidget {
  final String label;
  final double borderRadius;
  final bool isSelected;
  final VoidCallback onTap;

  const _ShapeBtn({
    required this.label,
    required this.borderRadius,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: 68,
        height: 44,
        decoration: BoxDecoration(
          color: isSelected ? NasiraColors.navGreen : const Color(0xFF2A3E2A),
          borderRadius: BorderRadius.circular(borderRadius.clamp(0, 22)),
          border: Border.all(
            color: isSelected ? Colors.white : Colors.white24,
            width: isSelected ? 2 : 1,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.white60,
            fontSize: 10,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

// ── Named-Style-Picker ────────────────────────────────────────────────────────

/// Horizontale Chip-Leiste mit allen Named Styles aus [GridStyleService].
/// Tippt der User einen Chip an, werden bg-Farbe, fg-Farbe und Form
/// gleichzeitig gesetzt (en-bloc). Ein zweites Antippen hebt die Auswahl auf.
class _NamedStylePicker extends StatelessWidget {
  final Color?  pendingBgColor;
  final Color?  pendingFgColor;
  final String? pendingShape;

  /// Callback: (backgroundColor, fontColor, shape)
  final void Function(Color bg, Color fg, String? shape) onPick;

  const _NamedStylePicker({
    required this.pendingBgColor,
    required this.pendingFgColor,
    required this.pendingShape,
    required this.onPick,
  });

  bool _matches(GridStyleEntry s) {
    if (pendingBgColor == null) return false;
    final bgMatch = pendingBgColor!.toARGB32() == s.backgroundColor.toARGB32();
    final fgMatch = pendingFgColor?.toARGB32() == s.fontColor.toARGB32();
    final shapeMatch = pendingShape == s.shape;
    return bgMatch && fgMatch && shapeMatch;
  }

  @override
  Widget build(BuildContext context) {
    const styles = GridStyleService.styles;
    return SizedBox(
      height: 68,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: styles.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (ctx, i) {
          final s = styles[i];
          final selected = _matches(s);
          return GestureDetector(
            onTap: () => onPick(s.backgroundColor, s.fontColor, s.shape),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: 72,
              decoration: BoxDecoration(
                color: s.backgroundColor,
                borderRadius: BorderRadius.circular(
                  s.shape == 'oval' || s.shape == 'pill' ? 34 : 8,
                ),
                border: Border.all(
                  color: selected ? Colors.white : Colors.white24,
                  width: selected ? 2.5 : 1,
                ),
                boxShadow: selected
                    ? [BoxShadow(
                        color: Colors.white.withValues(alpha: 0.3),
                        blurRadius: 5)]
                    : null,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (selected)
                    const Icon(Icons.check, size: 16, color: Colors.white),
                  Expanded(
                    child: Center(
                      child: Text(
                        s.name,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: s.fontColor,
                          fontSize: 8.5,
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Farb-Palette-Picker ───────────────────────────────────────────────────────

class _ColorSwatchPicker extends StatelessWidget {
  final Color? selected;
  final ValueChanged<Color?> onChanged;

  const _ColorSwatchPicker({required this.selected, required this.onChanged});

  static const _palette = <Color>[
    // Nasira-Palette
    Color(0xFF5D8057), // navGreen
    Color(0xFF91B38A), // briefTopic
    Color(0xFF3B5936), // briefQuestion
    Color(0xFF2E4529), // briefTopicDark
    Color(0xFFC4302B), // briefSentence (Rot)
    Color(0xFFBFBBAC), // briefNeutral (Beige)
    Color(0xFF5E80C4), // freiesSchreiben (Blau)
    Color(0xFFBFDBB8), // unterthema
    Color(0xFFC97F7E), // satzanfangVergangenheit
    Color(0xFFACC2A8), // frageVergangenheit
    Color(0xFFE6F2E3), // weitereWoerter
    Color(0xFF807C72), // navTaupe
    // Tagebuch
    Color(0xFFE6A800), // Montag
    Color(0xFF2E7D32), // Dienstag
    Color(0xFF1565C0), // Mittwoch
    Color(0xFFC62828), // Donnerstag
    Color(0xFFE65100), // Freitag
    Color(0xFFAD1457), // Sonntag
    // Neutral
    Colors.white,
    Color(0xFFE0E0E0),
    Color(0xFF9E9E9E),
    Color(0xFF616161),
    Color(0xFF212121),
    Colors.black,
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: _palette.map((color) {
        final isSelected = selected != null &&
            selected!.toARGB32() == color.toARGB32();
        return GestureDetector(
          onTap: () => onChanged(isSelected ? null : color),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isSelected ? Colors.white : Colors.white24,
                width: isSelected ? 2.5 : 1,
              ),
              boxShadow: isSelected
                  ? [BoxShadow(
                      color: Colors.white.withValues(alpha: 0.3),
                      blurRadius: 4)]
                  : null,
            ),
            child: isSelected
                ? const Icon(Icons.check, size: 16, color: Colors.white)
                : null,
          ),
        );
      }).toList(),
    );
  }
}

// ── InsertText Segment-Chip-Editor ────────────────────────────────────────────

/// Zeigt InsertText-Inhalte als horizontale Chip-Leiste aus Text- und Symbol-
/// Segmenten. Jedes Symbol-Segment referenziert einen eindeutigen Stem (Datei-
/// name ohne Endung). Beim Antippen eines Symbol-Chips öffnet sich eine
/// Inline-Suche direkt im Editor-Sheet.
class _SegmentChipEditor extends StatefulWidget {
  final List<_Segment> segments;
  final dynamic assetResolver;
  final VoidCallback onChanged;

  const _SegmentChipEditor({
    required this.segments,
    required this.assetResolver,
    required this.onChanged,
  });

  @override
  State<_SegmentChipEditor> createState() => _SegmentChipEditorState();
}

class _SegmentChipEditorState extends State<_SegmentChipEditor> {
  // Index des gerade inline bearbeiteten Text-Segments (-1 = keines)
  int _textEditIndex = -1;
  TextEditingController? _textCtrl;

  // Index des Symbol-Segments, für das gerade gesucht wird (-1 = keines)
  int _symbolSearchIndex = -1;
  final _searchCtrl = TextEditingController();
  List<String> _searchResults = [];

  @override
  void dispose() {
    _textCtrl?.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Text-Segment bearbeiten ────────────────────────────────────────────────

  void _startTextEdit(int index) {
    _textCtrl?.dispose();
    _textCtrl = TextEditingController(text: widget.segments[index].value)
      ..selection = TextSelection(
        baseOffset: 0,
        extentOffset: widget.segments[index].value.length,
      );
    setState(() {
      _textEditIndex     = index;
      _symbolSearchIndex = -1;
      _searchResults     = [];
    });
  }

  void _commitTextEdit() {
    if (_textEditIndex < 0) return;
    final newText = _textCtrl?.text ?? '';
    if (newText.isEmpty) {
      widget.segments.removeAt(_textEditIndex);
    } else {
      widget.segments[_textEditIndex].value = newText;
    }
    _textCtrl?.dispose();
    _textCtrl = null;
    setState(() => _textEditIndex = -1);
    widget.onChanged();
  }

  // ── Symbol-Segment suchen ──────────────────────────────────────────────────

  void _startSymbolSearch(int index) {
    setState(() {
      _symbolSearchIndex = index;
      _textEditIndex     = -1;
      _searchCtrl.clear();
      _searchResults     = [];
    });
  }

  void _runSymbolSearch(String query) {
    if (query.isEmpty) {
      setState(() => _searchResults = []);
      return;
    }
    final results =
        widget.assetResolver.search(query, limit: 24) as List<String>;
    setState(() => _searchResults = results);
  }

  void _pickSymbol(String assetPath) {
    final base = assetPath.split('/').last;
    final dot  = base.lastIndexOf('.');
    final stem = dot >= 0 ? base.substring(0, dot) : base;
    widget.segments[_symbolSearchIndex].value = stem;
    setState(() {
      _symbolSearchIndex = -1;
      _searchCtrl.clear();
      _searchResults     = [];
    });
    widget.onChanged();
  }

  void _cancelSymbolSearch() {
    // Leeres Symbol-Segment entfernen
    if (_symbolSearchIndex >= 0 &&
        _symbolSearchIndex < widget.segments.length &&
        widget.segments[_symbolSearchIndex].value.isEmpty) {
      widget.segments.removeAt(_symbolSearchIndex);
      widget.onChanged();
    }
    setState(() {
      _symbolSearchIndex = -1;
      _searchCtrl.clear();
      _searchResults     = [];
    });
  }

  // ── Segment entfernen ──────────────────────────────────────────────────────

  void _removeSegment(int index) {
    widget.segments.removeAt(index);
    if (_textEditIndex == index) {
      _textCtrl?.dispose();
      _textCtrl      = null;
      _textEditIndex = -1;
    } else if (_textEditIndex > index) {
      _textEditIndex--;
    }
    if (_symbolSearchIndex == index) {
      _symbolSearchIndex = -1;
      _searchCtrl.clear();
      _searchResults = [];
    } else if (_symbolSearchIndex > index) {
      _symbolSearchIndex--;
    }
    setState(() {});
    widget.onChanged();
  }

  // ── Segment hinzufügen ─────────────────────────────────────────────────────

  void _addText() {
    widget.segments.add(_Segment.text(''));
    _startTextEdit(widget.segments.length - 1);
    widget.onChanged();
  }

  void _addSymbol() {
    widget.segments.add(_Segment.symbol(''));
    _startSymbolSearch(widget.segments.length - 1);
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Chip-Zeile
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (int i = 0; i < widget.segments.length; i++) _buildChip(i),
            _buildAddButton(),
          ],
        ),

        // Inline Symbol-Suche
        if (_symbolSearchIndex >= 0) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  autofocus: true,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: const Color(0xFF2A3E2A),
                    hintText: 'Symbol suchen …',
                    hintStyle:
                        const TextStyle(color: Colors.white38, fontSize: 12),
                    prefixIcon: const Icon(Icons.search,
                        color: Colors.white38, size: 16),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 8),
                  ),
                  onChanged: _runSymbolSearch,
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white38, size: 18),
                onPressed: _cancelSymbolSearch,
                tooltip: 'Suche abbrechen',
              ),
            ],
          ),
          if (_searchResults.isNotEmpty) ...[
            const SizedBox(height: 6),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 5,
                crossAxisSpacing: 5,
                mainAxisSpacing: 5,
                childAspectRatio: 1,
              ),
              itemCount: _searchResults.length,
              itemBuilder: (ctx, i) {
                final path = _searchResults[i];
                final base = path.split('/').last;
                final dot  = base.lastIndexOf('.');
                final stem = dot >= 0 ? base.substring(0, dot) : base;
                return GestureDetector(
                  onTap: () => _pickSymbol(path),
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF2A3E2A),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Column(
                      children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(3),
                            child: Image.asset(path,
                                fit: BoxFit.contain,
                                errorBuilder: (_, __, ___) => const Icon(
                                    Icons.broken_image_outlined,
                                    color: Colors.white24,
                                    size: 18)),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(2, 0, 2, 3),
                          child: Text(stem,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white38, fontSize: 7.5)),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ] else if (_searchCtrl.text.isNotEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text('Keine Ergebnisse',
                  style: TextStyle(color: Colors.white38, fontSize: 11)),
            ),
        ],
      ],
    );
  }

  // ── Einzelner Chip ─────────────────────────────────────────────────────────

  Widget _buildChip(int index) {
    final seg = widget.segments[index];

    if (seg.type == 'text') {
      // ── Text-Chip ──────────────────────────────────────────────────────────
      if (_textEditIndex == index) {
        return Container(
          width: 150,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xFF2A3E2A),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: NasiraColors.navGreen, width: 1.5),
          ),
          child: TextField(
            controller: _textCtrl,
            autofocus: true,
            style: const TextStyle(color: Colors.white, fontSize: 12),
            decoration: const InputDecoration(
              isDense: true,
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
            ),
            onSubmitted: (_) => setState(_commitTextEdit),
          ),
        );
      }
      return GestureDetector(
        onTap: () => _startTextEdit(index),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 180),
          padding: const EdgeInsets.fromLTRB(6, 5, 4, 5),
          decoration: BoxDecoration(
            color: const Color(0xFF2A3E2A),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.text_fields, size: 11, color: Colors.white38),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  seg.value.isEmpty ? '(leer)' : seg.value,
                  style: TextStyle(
                    color: seg.value.isEmpty ? Colors.white38 : Colors.white,
                    fontSize: 12,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: () => _removeSegment(index),
                child:
                    const Icon(Icons.close, size: 12, color: Colors.red),
              ),
            ],
          ),
        ),
      );
    } else {
      // ── Symbol-Chip ────────────────────────────────────────────────────────
      final stem = seg.value;
      final path = stem.isNotEmpty
          ? widget.assetResolver.resolve('$stem.jpg') as String?
          : null;
      final isSearching = _symbolSearchIndex == index;

      return GestureDetector(
        onTap: () => _startSymbolSearch(index),
        child: Container(
          padding: const EdgeInsets.fromLTRB(6, 4, 4, 4),
          decoration: BoxDecoration(
            color: isSearching
                ? NasiraColors.navGreen.withValues(alpha: 0.15)
                : const Color(0xFF1E3A3A),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isSearching
                  ? NasiraColors.navGreen
                  : const Color(0xFF3A5A5A),
              width: isSearching ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: path != null
                    ? Image.asset(path,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Icon(
                            Icons.broken_image_outlined,
                            size: 16,
                            color: Colors.white38))
                    : const Icon(Icons.image_search,
                        size: 16, color: Colors.white38),
              ),
              const SizedBox(width: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 90),
                child: Text(
                  stem.isEmpty ? 'Symbol…' : stem,
                  style: TextStyle(
                    color: stem.isEmpty ? Colors.white38 : Colors.white70,
                    fontSize: 11,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: () => _removeSegment(index),
                child:
                    const Icon(Icons.close, size: 12, color: Colors.red),
              ),
            ],
          ),
        ),
      );
    }
  }

  // ── Hinzufügen-Button ──────────────────────────────────────────────────────

  Widget _buildAddButton() {
    return PopupMenuButton<String>(
      onSelected: (val) {
        if (val == 'text') _addText();
        if (val == 'symbol') _addSymbol();
      },
      color: const Color(0xFF253525),
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: 'text',
          child: Row(children: [
            Icon(Icons.text_fields, size: 15, color: Colors.white70),
            SizedBox(width: 8),
            Text('Text', style: TextStyle(color: Colors.white, fontSize: 13)),
          ]),
        ),
        PopupMenuItem(
          value: 'symbol',
          child: Row(children: [
            Icon(Icons.image_outlined, size: 15, color: Colors.white70),
            SizedBox(width: 8),
            Text('Symbol', style: TextStyle(color: Colors.white, fontSize: 13)),
          ]),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: NasiraColors.navGreen.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
              color: NasiraColors.navGreen.withValues(alpha: 0.4)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add, size: 13, color: NasiraColors.navGreen),
            SizedBox(width: 4),
            Text('Hinzufügen',
                style: TextStyle(
                    color: NasiraColors.navGreen, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
