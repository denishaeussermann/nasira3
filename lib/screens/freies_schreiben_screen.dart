import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../nasira_app_state.dart';
import '../nasira_repository.dart';
import '../services/grid_import_service.dart';
import '../services/grid_override_service.dart';
import '../theme/nasira_colors.dart';
import '../widgets/composite_symbol.dart';
import '../widgets/grid_layout_editor.dart';
import '../widgets/nasira_grid_cell.dart';
import '../widgets/nasira_text_workspace.dart';
import '../widgets/nasira_title_bar.dart';

// ── Freies Schreiben — Grid3-XML-getrieben ────────────────────────────────────
//
// Lädt alle Tastatur-Grids (Haupt + Buchstaben-Sub-Grids) on demand aus dem
// Grid3-Export und rendert sie 1:1.  Navigation via Jump.To / Jump.Back /
// Jump.Home.  Vorhersage-Slots (AutoContent) werden mit dem 7-stufigen
// Suggestion-Engine befüllt.
//
// Haupt-Grid:  "1 Freies Schreiben Tastatur"  (25 × 8)
//   Zeilen 0-1:  Workspace / Home / Back / DeleteWord
//   Zeilen 2-3:  14 Vorhersage-Slots (7 × ColSpan3 je Zeile) + Mehr-Button
//   Zeilen 4-6:  QWERTZ-Tastatur
//   Zeile  7:    Navigationsleiste (ABC, 123, Space, …)

class FreiesSchreibenScreen extends StatefulWidget {
  const FreiesSchreibenScreen({super.key});

  @override
  State<FreiesSchreibenScreen> createState() => _FreiesSchreibenScreenState();
}

class _FreiesSchreibenScreenState extends State<FreiesSchreibenScreen> {
  static const _mainGrid   = '1 Freies Schreiben Tastatur';
  static const _headerRows = 2; // Rows 0-1 in allen FS-Grids

  final _importer       = GridImportService();
  final _overrideService = GridOverrideService();
  final Map<String, GridPage> _grids   = {};
  final List<String>          _history = [];
  final FocusNode             _focus   = FocusNode();

  String _current   = _mainGrid;
  bool   _capsLock  = false;
  bool   _shift     = false;
  int    _predPage  = 0; // Vorhersage-Seite (0 = Slots 0-13)
  bool   _editorOpen = false;

  GridPage? get _page => _grids[_current];

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _overrideService.load().then((_) {
      if (mounted) _loadGrid(_mainGrid);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  // ── Grid-Laden (mit Override-Anwendung) ────────────────────────────────────

  Future<void> _loadGrid(String name) async {
    if (_grids.containsKey(name)) return;
    final raw = await _importer.importPage(name);
    if (raw != null && mounted) {
      setState(() => _grids[name] = _applyOverride(name, raw));
    }
  }

  /// Wendet gespeicherte Layout-Overrides auf eine GridPage an.
  GridPage _applyOverride(String name, GridPage raw) {
    final cellOv   = _overrideService.getAllCellOverrides(name);
    final layoutOv = _overrideService.getLayoutOverrides(name);
    final sizeOv   = _overrideService.getGridSize(name);

    final hasCellOv   = cellOv   != null && cellOv.isNotEmpty;
    final hasLayoutOv = layoutOv != null && layoutOv.isNotEmpty;

    if (!hasCellOv && !hasLayoutOv && sizeOv == null) return raw;

    final cells = raw.cells.map((c) {
      final key = '${c.x},${c.y}';
      final cOv = hasCellOv   ? cellOv[key]   : null;
      final lOv = hasLayoutOv ? layoutOv[key] : null;
      if (cOv == null && lOv == null) return c;
      return GridCell(
        x:              lOv?['x']        ?? c.x,
        y:              lOv?['y']        ?? c.y,
        colSpan:        lOv?['colSpan']  ?? c.colSpan,
        rowSpan:        lOv?['rowSpan']  ?? c.rowSpan,
        caption:        (cOv?['caption']    as String?) ?? c.caption,
        symbolStem:     (cOv?['symbolStem'] as String?) ?? c.symbolStem,
        symbolCategory: c.symbolCategory,
        metacmPath:     c.metacmPath,
        localImagePath: c.localImagePath,
        iconData:       c.iconData,
        style:          c.style,
        type:           c.type,
        commands:       _parseCommandOverrides(cOv) ?? c.commands,
      );
    }).toList();

    return GridPage(
      name:            raw.name,
      columns:         sizeOv?['columns'] ?? raw.columns,
      rows:            sizeOv?['rows']    ?? raw.rows,
      backgroundColor: raw.backgroundColor,
      cells:           cells,
      wordList:        raw.wordList,
    );
  }

  static List<GridCellCommand>? _parseCommandOverrides(Map<String, dynamic>? cOv) {
    final raw = cOv?['commands'] as List?;
    if (raw == null) return null;
    return raw.map((e) {
      final m = e as Map<String, dynamic>;
      final type = GridCommandType.values.firstWhere(
        (t) => t.name == (m['type'] as String? ?? ''),
        orElse: () => GridCommandType.other,
      );
      return GridCellCommand(
        type:        type,
        insertText:  m['insertText']  as String?,
        jumpTarget:  m['jumpTarget']  as String?,
        punctuation: m['punctuation'] as String?,
      );
    }).toList();
  }

  /// Seite neu laden (nach Editor-Änderung): Cache leeren + XML+Override neu einlesen.
  Future<void> _reloadGrid(String name) async {
    _grids.remove(name);
    await _loadGrid(name);
  }

  // ── Navigation ─────────────────────────────────────────────────────────────

  void _navigate(String target) {
    setState(() {
      _history.add(_current);
      _current  = target;
      _predPage = 0;
    });
    _loadGrid(target);
  }

  void _goBack() {
    if (_history.isEmpty) { Navigator.pop(context); return; }
    setState(() {
      _current  = _history.removeLast();
      _predPage = 0;
    });
  }

  // ── Befehle ausführen ──────────────────────────────────────────────────────

  void _run(List<GridCellCommand> cmds, NasiraAppState state, NasiraData? data) {
    for (final cmd in cmds) {
      switch (cmd.type) {
        case GridCommandType.insertText:
          final raw = cmd.insertText ?? '';
          if (raw.isEmpty) break;
          // CapsLock XOR Shift → Großbuchstaben bei einzelnem Zeichen
          final upper = raw.length == 1 && (_capsLock != _shift);
          state.appendLetter(upper ? raw.toUpperCase() : raw.toLowerCase());
          if (_shift && !_capsLock) setState(() => _shift = false);

        case GridCommandType.punctuation:
          if (cmd.punctuation != null) state.appendLetter(cmd.punctuation!);

        case GridCommandType.deleteWord:
          state.deleteLastWord();

        case GridCommandType.deleteLetter:
          state.deleteLastLetter();

        case GridCommandType.enter:
          state.appendLetter('\n');

        case GridCommandType.jumpTo:
          if (cmd.jumpTarget != null) _navigate(cmd.jumpTarget!);

        case GridCommandType.jumpBack:
          _goBack();

        case GridCommandType.jumpHome:
          Navigator.pop(context);

        case GridCommandType.capsLock:
          setState(() => _capsLock = !_capsLock);

        case GridCommandType.shift:
          setState(() => _shift = !_shift);

        case GridCommandType.moreWords:
          setState(() => _predPage++);

        case GridCommandType.documentEnd:
        // Cursor ans Ende — TextEditingController ist immer am Ende
        case GridCommandType.speak:
        // TTS: nicht implementiert
        default:
          break;
      }
    }
  }

  // ── Zellen-Preview für Editor (kein onTap) ────────────────────────────────

  Widget _buildCellForEditor(GridCell cell) {
    IconData? icon;
    if (cell.isHome)         icon = Icons.home_outlined;
    if (cell.isBack)         icon = Icons.arrow_back_rounded;
    if (cell.isDeleteWord)   icon = Icons.backspace_outlined;
    if (cell.isDeleteLetter) icon = Icons.backspace_outlined;
    if (cell.isCapsLock)     icon = Icons.keyboard_capslock_rounded;
    if (cell.isShiftKey)     icon = Icons.arrow_upward_rounded;

    return NasiraGridCell(
      caption:         cell.caption,
      icon:            icon,
      backgroundColor: cell.backgroundColor,
      textColor:       cell.foregroundColor,
      fontSize:        cell.caption != null && cell.caption!.length <= 2 ? 20 : 11,
      onTap:           null,
      borderRadius:    5,
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final state = context.watch<NasiraAppState>();
    final page  = _page;

    return Scaffold(
      backgroundColor: NasiraColors.keyboardBg,
      body: SafeArea(
        child: Column(
          children: [
            NasiraTitleBar(
              backgroundColor: NasiraColors.keyboardBg,
              onMenuTap: (_editorOpen || page == null)
                  ? null
                  : () => setState(() => _editorOpen = true),
            ),
            Expanded(
              child: _editorOpen && page != null
                  ? GridLayoutEditor(
                      page:            page,
                      pageName:        _current,
                      overrideService: _overrideService,
                      pageColor:       NasiraColors.keyboardBg,
                      cellBuilder:     _buildCellForEditor,
                      onChanged:       () async {
                        setState(() => _editorOpen = false);
                        await _reloadGrid(_current);
                      },
                      onDismiss:       () => setState(() => _editorOpen = false),
                    )
                  : page == null
                      ? const Center(child: CircularProgressIndicator(color: Colors.white54))
                      : FutureBuilder<NasiraLoadResult>(
                          future: state.futureLoad,
                          builder: (ctx, snap) =>
                              _buildGrid(page, state, snap.data?.data),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Zweigeteiltes Grid: Header (Zeilen 0-1) + Inhalt (Zeilen 2-N) ──────────

  Widget _buildGrid(GridPage page, NasiraAppState state, NasiraData? data) {
    final cols        = page.columns;
    final contentRows = page.rows - _headerRows;
    const gap = 3.0;
    const pad = 3.0;

    final headerCells  = page.cells.where((c) => c.y < _headerRows).toList();
    final contentCells = page.cells.where((c) => c.y >= _headerRows).toList();

    // AutoContent-Zellen sortiert für Vorhersage-Slot-Zuweisung
    final predCells = (page.cells
        .where((c) => c.type == GridCellType.autoContent)
        .toList()
      ..sort((a, b) => a.y != b.y ? a.y.compareTo(b.y) : a.x.compareTo(b.x)));

    final suggestions = _suggestions(state, data);

    return Container(
      color: NasiraColors.keyboardBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header (Zeilen 0-1) ───────────────────────────────────────────
          Expanded(
            flex: _headerRows,
            child: LayoutBuilder(builder: (ctx, box) {
              final cW = (box.maxWidth  - gap * (cols - 1) - pad * 2) / cols;
              final cH = (box.maxHeight - gap * (_headerRows - 1) - pad * 2) / _headerRows;
              return Stack(children: [
                for (final cell in headerCells)
                  _positioned(cell, 0, cW, cH, gap, pad,
                      _cell(cell, state, data, suggestions, predCells)),
              ]);
            }),
          ),
          // ── Inhalt (Zeilen 2-N: Vorhersage + Tastatur + Nav) ─────────────
          Expanded(
            flex: contentRows,
            child: LayoutBuilder(builder: (ctx, box) {
              final cW = (box.maxWidth  - gap * (cols - 1) - pad * 2) / cols;
              final cH = (box.maxHeight - gap * (contentRows - 1) - pad * 2) / contentRows;
              return Stack(children: [
                for (final cell in contentCells)
                  _positioned(cell, _headerRows, cW, cH, gap, pad,
                      _cell(cell, state, data, suggestions, predCells)),
              ]);
            }),
          ),
        ],
      ),
    );
  }

  Positioned _positioned(GridCell cell, int yBase, double cW, double cH,
      double gap, double pad, Widget child) {
    return Positioned(
      left:   pad + cell.x * (cW + gap),
      top:    pad + (cell.y - yBase) * (cH + gap),
      width:  cell.colSpan * (cW + gap) - gap,
      height: cell.rowSpan * (cH + gap) - gap,
      child:  child,
    );
  }

  // ── Zellen-Dispatcher ─────────────────────────────────────────────────────

  Widget _cell(GridCell cell, NasiraAppState state, NasiraData? data,
      List<WordEntry> suggestions, List<GridCell> predCells) {

    // Workspace
    if (cell.type == GridCellType.workspace) {
      return NasiraTextWorkspace(
        controller:  state.textController,
        borderColor: NasiraColors.fsBorder,
        minHeight:   0,
        maxHeight:   double.infinity,
        readOnly:    false,
        focusNode:   _focus,
      );
    }

    // AutoContent → Vorhersage-Slot
    if (cell.type == GridCellType.autoContent) {
      final idx = predCells.indexOf(cell);
      if (idx >= 0 && idx < suggestions.length) {
        return _predCell(suggestions[idx], state, data);
      }
      return _empty();
    }

    // Normale Kachel
    return _normalCell(cell, state, data);
  }

  // ── Vorhersage-Kachel ─────────────────────────────────────────────────────

  Widget _predCell(WordEntry word, NasiraAppState state, NasiraData? data) {
    final sym  = data != null ? state.cachedLookup(data, word.text) : null;
    final path = sym != null ? state.assetResolver.resolveForSymbol(sym) : null;
    return Material(
      color: NasiraColors.fsPrediction,
      borderRadius: BorderRadius.circular(5),
      child: InkWell(
        borderRadius: BorderRadius.circular(5),
        onTap: data == null ? null : () => state.insertWord(data, word),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(2, 3, 2, 2),
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: CompositeSymbolWidget(
                    assetPath1: path,
                    isPlural:   state.isPlural(word.text),
                    fallbackText: word.text,
                    size: 40,
                  ),
                ),
              ),
              Text(
                word.text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: NasiraColors.fsPredictionText,
                  height: 1.0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Normale Kachel ────────────────────────────────────────────────────────

  Widget _normalCell(GridCell cell, NasiraAppState state, NasiraData? data) {
    Color bg = cell.backgroundColor;
    Color fg = cell.foregroundColor;

    // CapsLock / Shift visuell aktiv
    if (cell.isCapsLock && _capsLock) bg = NasiraColors.navGreen;
    if (cell.isShiftKey && _shift)    bg = NasiraColors.navGreen;

    // Icon
    IconData? icon;
    if (cell.isHome)         icon = Icons.home_outlined;
    if (cell.isBack)         icon = Icons.arrow_back_rounded;
    if (cell.isDeleteWord)   icon = Icons.backspace_outlined;
    if (cell.isDeleteLetter) icon = Icons.backspace_outlined;
    if (cell.isCapsLock)     icon = Icons.keyboard_capslock_rounded;
    if (cell.isShiftKey)     icon = Icons.arrow_upward_rounded;

    // Caption mit CapsLock/Shift-Anzeige für Buchstaben (1-2 Zeichen)
    String? caption = cell.caption;
    final isLetter = cell.isInsertCell &&
        !cell.isNavigation &&
        !cell.isPunctuation &&
        caption != null &&
        caption.length <= 2;
    if (isLetter) {
      final upper = _capsLock != _shift;
      caption = upper ? caption.toUpperCase() : caption.toLowerCase();
    }

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(5),
      child: InkWell(
        borderRadius: BorderRadius.circular(5),
        onTap: cell.commands.isEmpty ? null : () => _run(cell.commands, state, data),
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Expanded(child: Center(child: Icon(icon, color: fg, size: 22))),
                if (caption != null && caption.isNotEmpty)
                  Text(caption,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 8,
                          color: fg,
                          fontWeight: FontWeight.w600)),
              ] else if (caption != null && caption.isNotEmpty)
                Expanded(
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        caption,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: isLetter ? 20 : 11,
                          fontWeight: FontWeight.w600,
                          color: fg,
                          height: 1.1,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Vorhersagen (paginiert) ────────────────────────────────────────────────

  List<WordEntry> _suggestions(NasiraAppState state, NasiraData? data) {
    final all = state.suggestions.isNotEmpty
        ? state.suggestions
        : (data?.initialSuggestions(limit: 56) ?? []);
    final start = _predPage * 14;
    if (start >= all.length) {
      // Letzte Seite erreicht → zurück zu Seite 0
      if (_predPage > 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _predPage = 0);
        });
      }
      return all.sublist(0, all.length.clamp(0, 14));
    }
    return all.sublist(start, (start + 14).clamp(0, all.length));
  }

  // ── Leer-Kachel ──────────────────────────────────────────────────────────

  Widget _empty() => Container(
    decoration: BoxDecoration(
      color: const Color(0xFF1B2B38),
      borderRadius: BorderRadius.circular(5),
    ),
  );
}
