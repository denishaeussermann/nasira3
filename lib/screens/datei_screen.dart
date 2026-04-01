import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../nasira_app_state.dart';
import '../services/grid_import_service.dart';
import '../services/grid_override_service.dart';
import '../theme/nasira_colors.dart';
import '../widgets/grid_layout_editor.dart';
import '../widgets/nasira_grid_cell.dart';
import '../widgets/nasira_text_workspace.dart';
import '../widgets/nasira_title_bar.dart';

// ── DateiScreen ───────────────────────────────────────────────────────────────
//
// Grid3-XML-getriebener Dokumenten-Manager.
// Haupt-Grid: "Datei" (11×8, dunkel-navy).
//   Zeile 0:   Aktionsleiste (Home, Neues Dokument, Weiter schreiben, Drucken,
//              Kopieren, Beenden)
//   Zeilen 1-6 links:  LiveCell → Dokumenten-Liste
//   Zeilen 1-6 rechts: Workspace → NasiraTextWorkspace
//   Zeile 7:   Untere Navigation (Vor/Zurück-Dokument, Korrektur, Telegram,
//              Threema, Whatsapp, Alles löschen)
// Sub-Grids: Korrektur, Telegram-Startseite, Threema-Startseite, Whatsapp-Startseite

class DateiScreen extends StatefulWidget {
  const DateiScreen({super.key});

  @override
  State<DateiScreen> createState() => _DateiScreenState();
}

class _DateiScreenState extends State<DateiScreen> {
  static const _mainGrid = 'Datei';

  final _importer       = GridImportService();
  final _overrideService = GridOverrideService();
  final Map<String, GridPage> _grids   = {};
  final List<String>          _history = [];

  String _current    = _mainGrid;
  int    _docIndex   = -1; // -1 = neues/ungespeichertes Dokument
  bool   _editorOpen = false;

  GridPage? get _page => _grids[_current];

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _overrideService.load().then((_) {
      if (mounted) _loadGrid(_mainGrid);
    });
    // Dokumentenliste beim ersten Öffnen laden
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<NasiraAppState>().documentService.load();
    });
  }

  // ── Grid-Laden ─────────────────────────────────────────────────────────────

  Future<void> _loadGrid(String name) async {
    if (_grids.containsKey(name)) return;
    final raw = await _importer.importPage(name);
    if (raw != null && mounted) {
      setState(() => _grids[name] = _applyOverride(name, raw));
    }
  }

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
        shapeOverride:           cOv?['shape']           as String?,
        backgroundColorOverride: _hexToColor(cOv?['backgroundColor'] as String?),
        fontColorOverride:       _hexToColor(cOv?['fontColor']       as String?),
        fontSizeOverride:        (cOv?['fontSize'] as num?)?.toDouble(),
      );
    }).toList();

    if (hasCellOv) {
      final occupied = { for (final c in cells) '${c.x},${c.y}' };
      for (final e in cellOv.entries) {
        if (occupied.contains(e.key)) continue;
        final parts = e.key.split(',');
        if (parts.length != 2) continue;
        final vx = int.tryParse(parts[0]);
        final vy = int.tryParse(parts[1]);
        if (vx == null || vy == null) continue;
        final cOv = e.value;
        cells.add(GridCell(
          x: vx, y: vy, colSpan: 1, rowSpan: 1,
          caption:                 cOv['caption']    as String?,
          symbolStem:              cOv['symbolStem'] as String?,
          style:                   GridCellStyle.actionNav,
          type:                    GridCellType.normal,
          commands:                _parseCommandOverrides(cOv) ?? const [],
          shapeOverride:           cOv['shape']           as String?,
          backgroundColorOverride: _hexToColor(cOv['backgroundColor'] as String?),
          fontColorOverride:       _hexToColor(cOv['fontColor']       as String?),
          fontSizeOverride:        (cOv['fontSize'] as num?)?.toDouble(),
        ));
      }
    }

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
      final rawSegs = m['segments'] as List?;
      final segs = rawSegs?.map((s) =>
          InsertSegment.fromJson(s as Map<String, dynamic>)).toList();
      return GridCellCommand(
        type:        type,
        insertText:  m['insertText']  as String?,
        jumpTarget:  m['jumpTarget']  as String?,
        punctuation: m['punctuation'] as String?,
        segments:    segs,
      );
    }).toList();
  }

  static Color? _hexToColor(String? hex) {
    if (hex == null || hex.length != 8) return null;
    final val = int.tryParse(hex, radix: 16);
    return val == null ? null : Color(val);
  }

  Future<void> _reloadGrid(String name) async {
    _grids.remove(name);
    await _loadGrid(name);
  }

  // ── Navigation ─────────────────────────────────────────────────────────────

  void _navigate(String target) {
    setState(() {
      _history.add(_current);
      _current = target;
    });
    _loadGrid(target);
  }

  void _goBack() {
    if (_history.isEmpty) {
      Navigator.pop(context);
      return;
    }
    setState(() => _current = _history.removeLast());
  }

  // ── Dokument-Management ────────────────────────────────────────────────────

  void _newDocument(NasiraAppState state) async {
    final text = state.textController.text.trim();
    if (text.isNotEmpty) {
      await state.documentService.saveDocument(text);
    }
    state.textController.clear();
    if (mounted) setState(() => _docIndex = -1);
  }

  void _loadDocument(NasiraAppState state, int index) {
    final docs = state.documentService.documents;
    if (index < 0 || index >= docs.length) return;
    state.textController.text = docs[index].text;
    state.textController.selection = TextSelection.collapsed(
        offset: docs[index].text.length);
    setState(() => _docIndex = index);
  }

  void _deleteDocument(NasiraAppState state) async {
    if (_docIndex >= 0 && _docIndex < state.documentService.documents.length) {
      await state.documentService.deleteDocument(_docIndex);
      final newDocs = state.documentService.documents;
      if (newDocs.isEmpty) {
        state.textController.clear();
        setState(() => _docIndex = -1);
      } else {
        final newIdx = _docIndex.clamp(0, newDocs.length - 1);
        _loadDocument(state, newIdx);
      }
    } else {
      // Kein gespeichertes Dokument: aktuellen Text löschen
      state.textController.clear();
      setState(() => _docIndex = -1);
    }
  }

  void _previousDocument(NasiraAppState state) {
    final count = state.documentService.documents.length;
    if (count == 0) return;
    final newIdx = _docIndex <= 0 ? count - 1 : _docIndex - 1;
    _loadDocument(state, newIdx);
  }

  void _nextDocument(NasiraAppState state) {
    final count = state.documentService.documents.length;
    if (count == 0) return;
    final newIdx = (_docIndex + 1) % count;
    _loadDocument(state, newIdx);
  }

  // ── Cursor-Hilfsfunktionen ─────────────────────────────────────────────────

  void _moveCursor(TextEditingController ctrl, int newOffset) {
    final clamped = newOffset.clamp(0, ctrl.text.length);
    ctrl.selection = TextSelection.collapsed(offset: clamped);
  }

  int _prevWordOffset(String text, int offset) {
    int i = offset;
    while (i > 0 && text[i - 1] == ' ') { i--; }
    while (i > 0 && text[i - 1] != ' ') { i--; }
    return i;
  }

  int _nextWordOffset(String text, int offset) {
    int i = offset;
    while (i < text.length && text[i] != ' ') { i++; }
    while (i < text.length && text[i] == ' ') { i++; }
    return i;
  }

  int _prevSentenceOffset(String text, int offset) {
    const ends = {'.', '!', '?'};
    int i = offset - 1;
    while (i > 0 && !ends.contains(text[i])) { i--; }
    if (i > 0) { i--; } // vor das Satzzeichen
    while (i > 0 && !ends.contains(text[i])) { i--; }
    return i > 0 ? i + 1 : 0;
  }

  int _nextSentenceOffset(String text, int offset) {
    const ends = {'.', '!', '?'};
    int i = offset;
    while (i < text.length && !ends.contains(text[i])) { i++; }
    if (i < text.length) { i++; } // nach das Satzzeichen
    while (i < text.length && text[i] == ' ') { i++; }
    return i;
  }

  int _prevLineOffset(String text, int offset) {
    int i = offset - 1;
    while (i > 0 && text[i] != '\n') { i--; }
    if (i > 0) {
      final lineEnd = i;
      i--;
      while (i > 0 && text[i - 1] != '\n') { i--; }
      final col = offset - (lineEnd + 1);
      return (i + col).clamp(i, lineEnd);
    }
    return 0;
  }

  int _nextLineOffset(String text, int offset) {
    int lineStart = offset;
    while (lineStart > 0 && text[lineStart - 1] != '\n') { lineStart--; }
    final col = offset - lineStart;
    int nextNl = offset;
    while (nextNl < text.length && text[nextNl] != '\n') { nextNl++; }
    if (nextNl >= text.length) { return text.length; }
    final nextLineStart = nextNl + 1;
    int nextLineEnd = nextLineStart;
    while (nextLineEnd < text.length && text[nextLineEnd] != '\n') { nextLineEnd++; }
    return (nextLineStart + col).clamp(nextLineStart, nextLineEnd);
  }

  // ── Befehle ausführen ──────────────────────────────────────────────────────

  void _run(List<GridCellCommand> cmds, NasiraAppState state) {
    for (final cmd in cmds) {
      switch (cmd.type) {
        case GridCommandType.jumpTo:
          if (cmd.jumpTarget != null) _navigate(cmd.jumpTarget!);

        case GridCommandType.jumpBack:
          _goBack();

        case GridCommandType.jumpHome:
          Navigator.popUntil(context, (r) => r.isFirst);

        case GridCommandType.textEditorNew:
          _newDocument(state);
          return; // Jump.Back danach nicht ausführen (Screen soll offen bleiben)

        case GridCommandType.textEditorDelete:
          _deleteDocument(state);

        case GridCommandType.textEditorPrevious:
          _previousDocument(state);

        case GridCommandType.textEditorNext:
          _nextDocument(state);

        case GridCommandType.copyText:
          final text = state.textController.text;
          if (text.isNotEmpty) {
            Clipboard.setData(ClipboardData(text: text));
          }

        case GridCommandType.settingsExit:
          Navigator.pop(context);
          return;

        case GridCommandType.documentEnd:
          final ctrl = state.textController;
          _moveCursor(ctrl, ctrl.text.length);

        case GridCommandType.documentStart:
          _moveCursor(state.textController, 0);

        case GridCommandType.previousLetter:
          final ctrl = state.textController;
          _moveCursor(ctrl, ctrl.selection.baseOffset - 1);

        case GridCommandType.nextLetter:
          final ctrl = state.textController;
          _moveCursor(ctrl, ctrl.selection.baseOffset + 1);

        case GridCommandType.previousWord:
          final ctrl = state.textController;
          _moveCursor(ctrl,
              _prevWordOffset(ctrl.text, ctrl.selection.baseOffset));

        case GridCommandType.nextWord:
          final ctrl = state.textController;
          _moveCursor(ctrl,
              _nextWordOffset(ctrl.text, ctrl.selection.baseOffset));

        case GridCommandType.previousSentence:
          final ctrl = state.textController;
          _moveCursor(ctrl,
              _prevSentenceOffset(ctrl.text, ctrl.selection.baseOffset));

        case GridCommandType.nextSentence:
          final ctrl = state.textController;
          _moveCursor(ctrl,
              _nextSentenceOffset(ctrl.text, ctrl.selection.baseOffset));

        case GridCommandType.previousLine:
          final ctrl = state.textController;
          _moveCursor(ctrl,
              _prevLineOffset(ctrl.text, ctrl.selection.baseOffset));

        case GridCommandType.nextLine:
          final ctrl = state.textController;
          _moveCursor(ctrl,
              _nextLineOffset(ctrl.text, ctrl.selection.baseOffset));

        case GridCommandType.deleteLetter:
          state.deleteLastLetter();

        case GridCommandType.deleteWord:
          state.deleteLastWord();

        case GridCommandType.setBookmark:
        case GridCommandType.pasteText:
        case GridCommandType.printText:
        case GridCommandType.insertText:
        case GridCommandType.punctuation:
        case GridCommandType.enter:
        case GridCommandType.moreWords:
        case GridCommandType.capsLock:
        case GridCommandType.shift:
        case GridCommandType.speak:
        case GridCommandType.other:
          break;
      }
    }
  }

  // ── Zellen-Preview für Editor ──────────────────────────────────────────────

  Widget _buildCellForEditor(GridCell cell) {
    IconData? icon;
    if (cell.isHome) icon = Icons.home_outlined;
    if (cell.isBack) icon = Icons.arrow_back_rounded;
    return NasiraGridCell(
      caption:         cell.caption,
      icon:            icon,
      backgroundColor: cell.backgroundColor,
      textColor:       cell.foregroundColor,
      fontSize:        11,
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
      backgroundColor: const Color(0xFF171947),
      body: SafeArea(
        child: Column(
          children: [
            NasiraTitleBar(
              backgroundColor: const Color(0xFF171947),
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
                      pageColor:       const Color(0xFF171947),
                      cellBuilder:     _buildCellForEditor,
                      onChanged: () async {
                        setState(() => _editorOpen = false);
                        await _reloadGrid(_current);
                      },
                      onDismiss: () => setState(() => _editorOpen = false),
                    )
                  : page == null
                      ? const Center(
                          child: CircularProgressIndicator(color: Colors.white54))
                      : _buildGrid(page, state),
            ),
          ],
        ),
      ),
    );
  }

  // ── Grid rendern ───────────────────────────────────────────────────────────

  Widget _buildGrid(GridPage page, NasiraAppState state) {
    const gap = 3.0;
    const pad = 3.0;

    return LayoutBuilder(builder: (ctx, box) {
      final cW = (box.maxWidth  - gap * (page.columns - 1) - pad * 2) / page.columns;
      final cH = (box.maxHeight - gap * (page.rows    - 1) - pad * 2) / page.rows;

      return ColoredBox(
        color: page.backgroundColor,
        child: Stack(
          children: [
            for (final cell in page.cells)
              _positioned(cell, cW, cH, gap, pad,
                  _cellWidget(cell, page, state)),
          ],
        ),
      );
    });
  }

  Positioned _positioned(GridCell cell, double cW, double cH,
      double gap, double pad, Widget child) {
    return Positioned(
      left:   pad + cell.x * (cW + gap),
      top:    pad + cell.y * (cH + gap),
      width:  cell.colSpan * (cW + gap) - gap,
      height: cell.rowSpan * (cH + gap) - gap,
      child:  child,
    );
  }

  Widget _cellWidget(GridCell cell, GridPage page, NasiraAppState state) {
    // Workspace → Textfeld
    if (cell.type == GridCellType.workspace) {
      return NasiraTextWorkspace(
        controller:  state.textController,
        borderColor: NasiraColors.fsBorder,
        minHeight:   0,
        maxHeight:   double.infinity,
        readOnly:    false,
      );
    }

    // LiveCell → Dokumenten-Liste
    if (cell.type == GridCellType.liveCell) {
      return _buildDocList(state);
    }

    // Normale Kachel
    IconData? icon;
    if (cell.isHome) icon = Icons.home_outlined;
    if (cell.isBack) icon = Icons.arrow_back_rounded;

    // Icon-Mapping für Datei-Befehle
    for (final cmd in cell.commands) {
      if (icon != null) break;
      switch (cmd.type) {
        case GridCommandType.textEditorNew:        icon = Icons.add_outlined; break;
        case GridCommandType.textEditorDelete:     icon = Icons.delete_outline; break;
        case GridCommandType.textEditorPrevious:   icon = Icons.arrow_upward_rounded; break;
        case GridCommandType.textEditorNext:       icon = Icons.arrow_downward_rounded; break;
        case GridCommandType.copyText:             icon = Icons.copy_outlined; break;
        case GridCommandType.printText:            icon = Icons.print_outlined; break;
        case GridCommandType.settingsExit:         icon = Icons.close_rounded; break;
        default: break;
      }
    }

    // Symbol-Icon aus Grid3X-Icons (falls gesetzt und kein Override)
    icon ??= cell.iconData;

    final onTap = cell.commands.isEmpty
        ? null
        : () => _run(cell.commands, state);

    return NasiraGridCell(
      caption:         cell.caption,
      icon:            icon,
      backgroundColor: cell.backgroundColor,
      textColor:       cell.foregroundColor,
      fontSize:        cell.fontSizeOverride ?? 11,
      onTap:           onTap,
      borderRadius:    cell.isFullyRounded ? 100 : 5,
    );
  }

  // ── Dokumenten-Liste ───────────────────────────────────────────────────────

  Widget _buildDocList(NasiraAppState state) {
    return ListenableBuilder(
      listenable: state.documentService,
      builder: (ctx, _) {
        final docs = state.documentService.documents;
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: NasiraColors.briefBorder, width: 1.5),
          ),
          child: docs.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(8),
                    child: Text('Keine Dokumente',
                        style: TextStyle(fontSize: 11, color: Colors.black54),
                        textAlign: TextAlign.center),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: docs.length,
                  itemBuilder: (ctx, i) {
                    final doc   = docs[i];
                    final isSel = i == _docIndex;
                    return GestureDetector(
                      onTap: () => _loadDocument(state, i),
                      child: Container(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 2),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 4),
                        decoration: BoxDecoration(
                          color: isSel
                              ? NasiraColors.navGreen.withAlpha(40)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(4),
                          border: isSel
                              ? Border.all(
                                  color: NasiraColors.navGreen, width: 1)
                              : null,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(doc.timeLabel,
                                style: TextStyle(
                                    fontSize: 9,
                                    color: isSel
                                        ? NasiraColors.navGreen
                                        : Colors.black38)),
                            const SizedBox(height: 1),
                            Text(doc.preview,
                                style: const TextStyle(
                                    fontSize: 10, color: Colors.black87),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        );
      },
    );
  }
}
