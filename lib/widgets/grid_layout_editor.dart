import 'package:flutter/material.dart';

import '../models/grid_page.dart';
import '../services/grid_override_service.dart';
import '../theme/nasira_colors.dart';
import 'brief_grid_editor_overlay.dart';
import 'grid_page_editor_sheet.dart';

// ── Enums ─────────────────────────────────────────────────────────────────────

enum _EditorMode { idle, dragging, resizing }

enum _ResizeDim { colSpan, rowSpan, both }

// ── Mutable Zelle ─────────────────────────────────────────────────────────────

class _EditCell {
  /// Anzuzeigende Zelle (ggf. content-overridden): wird an cellBuilder übergeben.
  final GridCell src;
  /// Rohe (nicht-overridden) Position — Grundlage für Override-Schlüssel und isModified.
  final int rawX, rawY, rawColSpan, rawRowSpan;
  /// Aktuelle Editor-Position (kann von rawX/rawY abweichen).
  int x, y, colSpan, rowSpan;

  _EditCell(
    this.src, {
    int? rawX,
    int? rawY,
    int? rawColSpan,
    int? rawRowSpan,
  })  : rawX       = rawX       ?? src.x,
        rawY       = rawY       ?? src.y,
        rawColSpan = rawColSpan ?? src.colSpan,
        rawRowSpan = rawRowSpan ?? src.rowSpan,
        x          = src.x,
        y          = src.y,
        colSpan    = src.colSpan,
        rowSpan    = src.rowSpan;

  /// Override-Schlüssel: immer die RAW-Position (nie die applied-Position).
  String get key => '$rawX,$rawY';

  /// True wenn aktuell verschoben/vergrößert gegenüber der RAW-Position.
  bool get isModified =>
      x != rawX || y != rawY || colSpan != rawColSpan || rowSpan != rawRowSpan;
}

// ── GridLayoutEditor ──────────────────────────────────────────────────────────

/// WYSIWYG-Editor für Grid-Layouts — rendert die echten Zellen.
///
/// Workspace-Zeilen (Texteingabe-Bereich) werden ausgeblendet, so dass der
/// Editor exakt die gleiche Inhaltsansicht zeigt wie der normale Screen.
/// Drag-and-Drop nutzt Block-Swap (kein Live-Reflow), Resize nutzt Reflow.
/// [cellBuilder] liefert das echte Cell-Widget (z.B. NasiraGridCell) für
/// jede Zelle — der Editor legt Selektions-Rahmen darüber.
class GridLayoutEditor extends StatefulWidget {
  /// Angezeigte (ggf. override-angewendete) Seite — für cellBuilder und Hintergrundfarbe.
  final GridPage page;
  /// Rohe Seite ohne Layout-Overrides — Grundlage für stabile Override-Schlüssel.
  /// Wenn null, wird [page] als Rohseite behandelt (für synthetische Seiten).
  final GridPage? rawPage;
  final String pageName;
  final GridOverrideService overrideService;
  final VoidCallback onDismiss;
  final VoidCallback onChanged;
  /// Liefert das echte Widget für eine GridCell (ohne onTap).
  final Widget Function(GridCell) cellBuilder;
  /// Hintergrundfarbe der Seite.
  final Color pageColor;

  const GridLayoutEditor({
    super.key,
    required this.page,
    this.rawPage,
    required this.pageName,
    required this.overrideService,
    required this.onDismiss,
    required this.onChanged,
    required this.cellBuilder,
    required this.pageColor,
  });

  @override
  State<GridLayoutEditor> createState() => _GridLayoutEditorState();
}

class _GridLayoutEditorState extends State<GridLayoutEditor> {
  // ── Grid-Dimensionen (nur Inhalts-Zeilen, ohne Workspace) ────────────────
  late int _columns;
  late int _rows; // Anzahl Inhalts-Zeilen (ohne Workspace)

  // ── Workspace-Offset: Anzahl der Zeilen vor dem Inhaltsbereich ───────────
  int _wsFirstContent = 0;

  // ── Zell-State (keine Workspace-Zellen) ──────────────────────────────────
  late List<_EditCell> _cells;

  // ── Drag-State ────────────────────────────────────────────────────────────
  _EditorMode _mode = _EditorMode.idle;
  _EditCell?  _dragging;
  Offset _dragPos   = Offset.zero;
  Offset _panStart  = Offset.zero;
  bool   _isDragging = false;
  int?   _dropTargetX; // Spalte im Seiten-Koordinatensystem
  int?   _dropTargetY; // Zeile  im Seiten-Koordinatensystem (page-y)

  // ── Resize-State ──────────────────────────────────────────────────────────
  _ResizeDim? _resizeDim;
  Offset _resizeStart       = Offset.zero;
  int    _resizeStartColSpan = 1;
  int    _resizeStartRowSpan = 1;

  // ── Selektion ─────────────────────────────────────────────────────────────
  _EditCell? _selected;

  // ── Clipboard (Kopieren / Einfügen) ───────────────────────────────────────
  GridCell? _clipboard;

  // ── Doppeltippen (Zell-Inhalts-Editor öffnen) ─────────────────────────────
  Offset _doubleTapPos = Offset.zero;

  // ── Grid-Metriken (aus LayoutBuilder) ────────────────────────────────────
  double _cellW = 1, _cellH = 1;

  // ── Status ────────────────────────────────────────────────────────────────
  bool _hasChanges = false;
  bool _saving     = false;

  // ── Konstanten ────────────────────────────────────────────────────────────
  static const double _handleRadius = 22.0;

  // ── Init ──────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _columns = widget.page.columns;
    _rebuildCells(); // setzt _wsFirstContent = 0, alle Zellen inkl. Workspace
    _rows = widget.page.rows;
  }

  @override
  void didUpdateWidget(GridLayoutEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Nach Undo/Redo liefert der Parent eine neue page — Editor neu initialisieren.
    if (!identical(oldWidget.page, widget.page)) {
      _columns = widget.page.columns;
      _rows    = widget.page.rows;
      _rebuildCells();
      _hasChanges = false;
      _selected   = null;
    }
  }

  /// Befüllt _cells mit ALLEN Zellen (inkl. Workspace) und setzt _wsFirstContent = 0.
  ///
  /// Wenn [widget.rawPage] gesetzt ist, werden rawX/rawY aus der Rohseite bezogen
  /// und die aktuellen Positionen aus den gespeicherten Layout-Overrides initialisiert.
  /// Dadurch sind Override-Schlüssel immer stabil (Rohposition), unabhängig davon,
  /// ob der Editor auf einer bereits-angewendeten Seite geöffnet wird.
  void _rebuildCells() {
    _wsFirstContent = 0; // Alle Zeilen editierbar – kein Header-Band-Offset

    if (widget.rawPage == null) {
      // Kein rawPage: einfacher Pfad (synthetische Seiten ohne Rohvorlage)
      _cells = widget.page.cells
          .map(_EditCell.new)
          .toList()
        ..sort((a, b) => a.y != b.y ? a.y.compareTo(b.y) : a.x.compareTo(b.x));
      return;
    }

    // ── rawPage vorhanden: stabile Schlüssel + korrekte Initialpositionen ──────

    final layoutOv = widget.overrideService.getLayoutOverrides(widget.pageName);

    // Rückwärts-Map: angewendete Position → Roh-Schlüssel
    final appliedPosToRawKey = <String, String>{};
    if (layoutOv != null) {
      for (final e in layoutOv.entries) {
        final ap = e.value;
        appliedPosToRawKey['${ap['x']},${ap['y']}'] = e.key;
      }
    }
    // Roh-Schlüssel → angewendete Zelle (für cellBuilder: zeigt overridden Inhalt)
    final rawKeyToApplied = <String, GridCell>{};
    for (final c in widget.page.cells) {
      final rawKey = appliedPosToRawKey['${c.x},${c.y}'] ?? '${c.x},${c.y}';
      rawKeyToApplied[rawKey] = c;
    }

    _cells = widget.rawPage!.cells
        .map((rawCell) {
          final rawKey     = '${rawCell.x},${rawCell.y}';
          final displayCell = rawKeyToApplied[rawKey] ?? rawCell;
          final ec = _EditCell(
            displayCell,
            rawX:       rawCell.x,
            rawY:       rawCell.y,
            rawColSpan: rawCell.colSpan,
            rawRowSpan: rawCell.rowSpan,
          );
          // Initialposition aus gespeichertem Override übernehmen
          final ov = layoutOv?[rawKey];
          if (ov != null) {
            ec.x       = ov['x']       ?? rawCell.x;
            ec.y       = ov['y']       ?? rawCell.y;
            ec.colSpan = ov['colSpan'] ?? rawCell.colSpan;
            ec.rowSpan = ov['rowSpan'] ?? rawCell.rowSpan;
          }
          return ec;
        })
        .toList()
      ..sort((a, b) => a.y != b.y ? a.y.compareTo(b.y) : a.x.compareTo(b.x));
  }

  // ── Auto-Place ────────────────────────────────────────────────────────────
  //
  // occ-Koordinaten sind immer Display-Space (0 … _rows-1).
  // Page-y = Display-y + _wsFirstContent.

  void _autoPlace(List<_EditCell> ordered) {
    final occ = _emptyOcc();
    for (final c in ordered) {
      bool placed = false;
      outer:
      for (int r = 0; r < _rows; r++) {
        for (int col = 0; col <= _columns - c.colSpan; col++) {
          if (_fits(occ, col, r, c.colSpan, c.rowSpan)) {
            c.x = col;
            c.y = r + _wsFirstContent; // display → page-y
            _markOcc(occ, col, r, c.colSpan, c.rowSpan);
            placed = true;
            break outer;
          }
        }
      }
      if (!placed) { c.x = c.src.x; c.y = c.src.y; }
    }
  }

  /// Platziert [fixed] an seiner aktuellen Position; alle anderen Zellen
  /// werden danach um sie herum neu platziert (für Resize-Reflow).
  void _autoPlaceAround(_EditCell fixed, List<_EditCell> others) {
    final fixedDispY = fixed.y - _wsFirstContent;
    fixed.colSpan = fixed.colSpan.clamp(1, _columns - fixed.x);
    fixed.rowSpan = fixed.rowSpan.clamp(1, _rows - fixedDispY);

    final occ = _emptyOcc();
    _markOcc(occ, fixed.x, fixedDispY, fixed.colSpan, fixed.rowSpan);

    for (final c in others) {
      bool placed = false;
      outer:
      for (int r = 0; r < _rows; r++) {
        for (int col = 0; col <= _columns - c.colSpan; col++) {
          if (_fits(occ, col, r, c.colSpan, c.rowSpan)) {
            c.x = col;
            c.y = r + _wsFirstContent;
            _markOcc(occ, col, r, c.colSpan, c.rowSpan);
            placed = true;
            break outer;
          }
        }
      }
      if (!placed) { c.x = c.src.x; c.y = c.src.y; }
    }
  }

  List<List<bool>> _emptyOcc() =>
      List.generate(_rows, (_) => List.filled(_columns, false));

  bool _fits(List<List<bool>> occ, int x, int y, int cs, int rs) {
    if (y + rs > _rows || x + cs > _columns) return false;
    for (int dy = 0; dy < rs; dy++) {
      for (int dx = 0; dx < cs; dx++) {
        if (occ[y + dy][x + dx]) return false;
      }
    }
    return true;
  }

  void _markOcc(List<List<bool>> occ, int x, int y, int cs, int rs) {
    for (int dy = 0; dy < rs; dy++) {
      for (int dx = 0; dx < cs; dx++) {
        occ[y + dy][x + dx] = true;
      }
    }
  }

  // ── Resize-Handle Treffererkennung ────────────────────────────────────────

  _ResizeDim? _hitTestHandle(Offset pos, _EditCell cell) {
    final dispY  = cell.y - _wsFirstContent;
    final right  = (cell.x + cell.colSpan) * _cellW;
    final bottom = (dispY + cell.rowSpan) * _cellH;
    final cx     = cell.x * _cellW;
    final cy     = dispY * _cellH;

    final nearRight  = (pos.dx - right).abs()  < _handleRadius;
    final nearBottom = (pos.dy - bottom).abs() < _handleRadius;
    final inColRange = pos.dx >= cx && pos.dx <= right  + _handleRadius;
    final inRowRange = pos.dy >= cy && pos.dy <= bottom + _handleRadius;

    if (nearRight && nearBottom) return _ResizeDim.both;
    if (nearRight  && inRowRange) return _ResizeDim.colSpan;
    if (nearBottom && inColRange) return _ResizeDim.rowSpan;
    return null;
  }

  // ── Gesamt-Geste (Drag + Resize über einen GestureDetector) ──────────────

  void _handlePanStart(Offset local) {
    // 1. Resize-Handle der ausgewählten Zelle prüfen
    if (_selected != null) {
      final dim = _hitTestHandle(local, _selected!);
      if (dim != null) {
        setState(() {
          _mode               = _EditorMode.resizing;
          _resizeDim          = dim;
          _resizeStart        = local;
          _resizeStartColSpan = _selected!.colSpan;
          _resizeStartRowSpan = _selected!.rowSpan;
        });
        return;
      }
    }

    // 2. Welche Zelle wurde angetippt?
    // gy ist Display-Space → in Page-y umrechnen
    final gx = (local.dx / _cellW).floor().clamp(0, _columns - 1);
    final gy = (local.dy / _cellH).floor().clamp(0, _rows - 1) + _wsFirstContent;
    _EditCell? hit;
    for (final c in _cells) {
      if (gx >= c.x && gx < c.x + c.colSpan &&
          gy >= c.y && gy < c.y + c.rowSpan) {
        hit = c;
        break;
      }
    }

    setState(() {
      _mode       = _EditorMode.idle;
      _dragging   = hit;
      _dragPos    = local;
      _panStart   = local;
      _isDragging = false;
    });
  }

  void _handlePanUpdate(Offset local) {
    // ── Resize ────────────────────────────────────────────────────────────
    if (_mode == _EditorMode.resizing && _selected != null) {
      setState(() {
        final dx = local.dx - _resizeStart.dx;
        final dy = local.dy - _resizeStart.dy;

        if (_resizeDim == _ResizeDim.colSpan || _resizeDim == _ResizeDim.both) {
          _selected!.colSpan = (_resizeStartColSpan + (dx / _cellW).round())
              .clamp(1, _columns - _selected!.x);
        }
        if (_resizeDim == _ResizeDim.rowSpan || _resizeDim == _ResizeDim.both) {
          _selected!.rowSpan = (_resizeStartRowSpan + (dy / _cellH).round())
              .clamp(1, _rows - (_selected!.y - _wsFirstContent));
        }
        // Nur reflow wenn die resizete Zelle tatsächlich eine andere überlappt
        final dispY = _selected!.y - _wsFirstContent;
        final hasOverlap = _cells.any((c) =>
          c != _selected &&
          c.x < _selected!.x + _selected!.colSpan && c.x + c.colSpan > _selected!.x &&
          (c.y - _wsFirstContent) < dispY + _selected!.rowSpan &&
          (c.y - _wsFirstContent) + c.rowSpan > dispY);
        if (hasOverlap) {
          _autoPlaceAround(_selected!, _cells.where((c) => c != _selected).toList());
        }
        _hasChanges = true;
      });
      return;
    }

    // ── Drag: nur Snap-Position berechnen, kein Reflow ───────────────────
    if (_dragging == null) return;

    if (!_isDragging && (local - _panStart).distance < 10) {
      setState(() => _dragPos = local);
      return;
    }

    setState(() {
      _isDragging = true;
      _mode       = _EditorMode.dragging;
      _dragPos    = local;

      // Snap-Position in Display-Space berechnen
      final gx = (local.dx / _cellW - _dragging!.colSpan / 2.0)
          .round()
          .clamp(0, _columns - _dragging!.colSpan);
      final gy = (local.dy / _cellH - _dragging!.rowSpan / 2.0)
          .round()
          .clamp(0, _rows - _dragging!.rowSpan);

      _dropTargetX = gx;
      _dropTargetY = gy + _wsFirstContent; // Display → Page-y
    });
  }

  void _handlePanEnd() {
    if (_mode == _EditorMode.resizing) {
      setState(() => _mode = _EditorMode.idle);
      return;
    }

    if (_dragging != null && _isDragging) {
      // ── Block-Swap Drop ───────────────────────────────────────────────
      final tx = _dropTargetX;
      final ty = _dropTargetY;
      if (tx != null && ty != null &&
          (tx != _dragging!.x || ty != _dragging!.y)) {
        setState(() {
          final oldX = _dragging!.x;
          final oldY = _dragging!.y; // page-y

          // Zellen, die mit der Zielposition überlappen
          final displaced = _cells.where((c) =>
            c != _dragging &&
            c.x < tx + _dragging!.colSpan && c.x + c.colSpan > tx &&
            c.y < ty + _dragging!.rowSpan && c.y + c.rowSpan > ty
          ).toList();

          // Gezogene Zelle an neue Position
          _dragging!.x = tx;
          _dragging!.y = ty;

          // occ mit allen unbewegten Zellen vorbelegen
          final occ = _emptyOcc();
          for (final c in _cells) {
            if (c != _dragging && !displaced.contains(c)) {
              _markOcc(occ, c.x, c.y - _wsFirstContent, c.colSpan, c.rowSpan);
            }
          }
          // Neue Position der gezogenen Zelle markieren
          _markOcc(occ, tx, ty - _wsFirstContent, _dragging!.colSpan, _dragging!.rowSpan);

          // Verdrängte Zellen an alte Position der gezogenen Zelle setzen (falls möglich)
          for (final c in displaced) {
            if (_fits(occ, oldX, oldY - _wsFirstContent, c.colSpan, c.rowSpan)) {
              c.x = oldX;
              c.y = oldY;
              _markOcc(occ, oldX, oldY - _wsFirstContent, c.colSpan, c.rowSpan);
            } else {
              // Fallback: nächster freier Slot
              bool placed = false;
              outer:
              for (int r = 0; r < _rows; r++) {
                for (int col = 0; col <= _columns - c.colSpan; col++) {
                  if (_fits(occ, col, r, c.colSpan, c.rowSpan)) {
                    c.x = col;
                    c.y = r + _wsFirstContent;
                    _markOcc(occ, col, r, c.colSpan, c.rowSpan);
                    placed = true;
                    break outer;
                  }
                }
              }
              if (!placed) {
                // Zelle auf Originalposition zurücksetzen
                c.x = oldX; c.y = oldY;
              }
            }
          }
          _hasChanges = true;
        });
      }
    } else if (_dragging != null && !_isDragging) {
      // Tap → Selektion umschalten
      setState(() {
        _selected = _selected == _dragging ? null : _dragging;
      });
    }

    setState(() {
      _dragging    = null;
      _isDragging  = false;
      _dropTargetX = null;
      _dropTargetY = null;
      _mode        = _EditorMode.idle;
    });
  }

  // ── Doppeltippen → Zell-Inhalts-Editor ───────────────────────────────────

  void _handleDoubleTap() {
    final col = (_doubleTapPos.dx / _cellW).floor().clamp(0, _columns - 1);
    final row = (_doubleTapPos.dy / _cellH).floor().clamp(0, _rows - 1);

    // Existierende Zelle an diesem Punkt suchen
    final hit = _cells.where(
      (c) => col >= c.x && col < c.x + c.colSpan &&
             row >= c.y && row < c.y + c.rowSpan,
    ).firstOrNull;

    // Zelle für den Editor: existierende oder leere Ghost-Zelle
    final editorCell = hit != null
        ? hit.src
        : GridCell(
            x: col, y: row,
            style: GridCellStyle.actionNav,
            type:  GridCellType.normal,
            commands: const [],
          );

    BriefGridEditorOverlay.showCellSheet(
      context: context,
      cell: editorCell,
      pageName: widget.pageName,
      overrideService: widget.overrideService,
      onChanged: widget.onChanged,
    );
  }

  // ── Ghost-Kacheln für leere Gitterpositionen ──────────────────────────────

  List<Widget> _buildGhostCells() {
    // Belegungs-Matrix aufbauen
    final occ = List.generate(_rows, (_) => List.filled(_columns, false));
    for (final c in _cells) {
      for (int r = c.y; r < c.y + c.rowSpan && r < _rows; r++) {
        for (int col = c.x; col < c.x + c.colSpan && col < _columns; col++) {
          if (r >= 0 && col >= 0) occ[r][col] = true;
        }
      }
    }
    final ghosts = <Widget>[];
    for (int r = 0; r < _rows; r++) {
      for (int col = 0; col < _columns; col++) {
        if (!occ[r][col]) {
          final gc = col, gr = r;
          ghosts.add(Positioned(
            left:   gc * _cellW + 3,
            top:    gr * _cellH + 3,
            width:  _cellW - 6,
            height: _cellH - 6,
            child: Tooltip(
              message: _clipboard != null
                  ? 'Doppeltippen: neue Zelle / Inhalt einfügen'
                  : 'Doppeltippen: neue Zelle erstellen',
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: _clipboard != null
                      ? NasiraColors.navGreen.withValues(alpha: 0.08)
                      : Colors.transparent,
                  border: Border.all(
                    color: _clipboard != null
                        ? NasiraColors.navGreen.withValues(alpha: 0.35)
                        : Colors.white12,
                    width: 1,
                  ),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Center(
                  child: Icon(
                    _clipboard != null ? Icons.paste_outlined : Icons.add,
                    size: 14,
                    color: _clipboard != null
                        ? NasiraColors.navGreen.withValues(alpha: 0.5)
                        : Colors.white12,
                  ),
                ),
              ),
            ),
          ));
        }
      }
    }
    return ghosts;
  }

  // ── Grid-Dimensionen anpassen ─────────────────────────────────────────────

  void _addColumn() => setState(() {
        _columns++;
        _hasChanges = true;
      });

  void _removeColumn() {
    if (_columns <= 1) return;
    setState(() {
      _columns--;
      for (final c in _cells) {
        if (c.x >= _columns) {
          c.x = _columns - 1;
          c.colSpan = 1;
        } else if (c.x + c.colSpan > _columns) {
          c.colSpan = _columns - c.x;
        }
      }
      _autoPlace(List.from(_cells));
      _hasChanges = true;
    });
  }

  void _addRow() => setState(() {
        _rows++;
        _hasChanges = true;
      });

  void _removeRow() {
    if (_rows <= 1) return;
    setState(() {
      _rows--;
      for (final c in _cells) {
        final dispY = c.y - _wsFirstContent;
        if (dispY >= _rows) {
          c.y = _rows - 1 + _wsFirstContent;
          c.rowSpan = 1;
        } else if (dispY + c.rowSpan > _rows) {
          c.rowSpan = _rows - dispY;
        }
      }
      _autoPlace(List.from(_cells));
      _hasChanges = true;
    });
  }

  // ── Undo / Redo ───────────────────────────────────────────────────────────

  Future<void> _performUndo() async {
    await widget.overrideService.undo();
    widget.onChanged();
    if (mounted) setState(() {});
  }

  Future<void> _performRedo() async {
    await widget.overrideService.redo();
    widget.onChanged();
    if (mounted) setState(() {});
  }

  // ── Speichern / Zurücksetzen ──────────────────────────────────────────────

  Future<void> _save() async {
    setState(() => _saving = true);

    final totalRows = _rows; // _wsFirstContent ist immer 0

    // ── Bounds-Validierung: keine Zelle darf außerhalb des Grids liegen ──────
    for (final c in _cells) {
      // x-Achse
      if (c.x < 0) c.x = 0;
      if (c.x >= _columns) c.x = _columns - 1;
      if (c.colSpan < 1) c.colSpan = 1;
      if (c.x + c.colSpan > _columns) c.colSpan = _columns - c.x;
      // y-Achse
      if (c.y < 0) c.y = 0;
      if (c.y >= totalRows) c.y = totalRows - 1;
      if (c.rowSpan < 1) c.rowSpan = 1;
      if (c.y + c.rowSpan > totalRows) c.rowSpan = totalRows - c.y;
    }

    // ── Layout-Overrides ─────────────────────────────────────────────────────
    final layoutOv = <String, Map<String, int>>{};
    for (final c in _cells) {
      if (c.isModified) {
        layoutOv[c.key] = {
          'x': c.x, 'y': c.y,
          'colSpan': c.colSpan, 'rowSpan': c.rowSpan,
        };
      }
    }
    // ── Layout + Grid-Größe in einem Undo-Schritt ────────────────────────────
    final origCols    = widget.page.columns;
    final origRows    = widget.page.rows;
    final sizeChanged = _columns != origCols || totalRows != origRows;
    await widget.overrideService.saveLayoutChanges(
      widget.pageName,
      layoutOverrides: layoutOv,
      newColumns: sizeChanged ? _columns    : null,
      newRows:    sizeChanged ? totalRows   : null,
    );

    if (mounted) {
      widget.onChanged();
      widget.onDismiss();
    }
  }

  Future<void> _confirmReset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Layout zurücksetzen?'),
        content: const Text(
            'Alle Positions-, Größen- und Inhalt-Änderungen auf dieser Seite '
            'werden auf den Original-Zustand zurückgesetzt.'),
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
    if (ok != true || !mounted) return;
    await widget.overrideService.clearLayoutOverrides(widget.pageName);
    await widget.overrideService.clearGridSize(widget.pageName);
    await widget.overrideService.clearAllCellOverrides(widget.pageName);
    if (mounted) {
      setState(() {
        _columns = widget.page.columns;
        _rebuildCells(); // setzt _wsFirstContent = 0
        _rows = widget.page.rows;
        _hasChanges = false;
        _selected   = null;
      });
      widget.onChanged();
    }
  }

  // ── Kopieren / Einfügen ───────────────────────────────────────────────────

  void _copySelected() {
    if (_selected == null) return;
    setState(() => _clipboard = _selected!.src);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Zelle kopiert'),
        duration: Duration(seconds: 1),
        backgroundColor: NasiraColors.navGreen,
      ),
    );
  }

  Future<void> _pasteToSelected() async {
    final target = _selected;
    final src    = _clipboard;
    if (target == null || src == null) return;

    // Befehle → JSON
    final cmds = src.commands.map((c) {
      final m = <String, dynamic>{'type': c.type.name};
      if (c.insertText  != null) m['insertText']  = c.insertText;
      if (c.jumpTarget  != null) m['jumpTarget']  = c.jumpTarget;
      if (c.punctuation != null) m['punctuation'] = c.punctuation;
      return m;
    }).toList();

    String? hexOf(Color? c) =>
        c?.toARGB32().toRadixString(16).padLeft(8, '0');

    await widget.overrideService.setCellOverride(
      widget.pageName,
      target.rawX,
      target.rawY,
      caption:         src.caption,
      symbolStem:      src.symbolStem,
      commands:        cmds,
      shape:           src.shapeOverride,
      backgroundColor: hexOf(src.backgroundColorOverride) ?? '',
      fontColor:       hexOf(src.fontColorOverride) ?? '',
      fontSize:        src.fontSizeOverride,
    );
    widget.onChanged();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Column(
        children: [
          _buildToolbar(),
          _buildDimensionBar(),
          Expanded(child: _buildGridArea()),
          _buildInfoPanel(),
        ],
      ),
    );
  }

  // ── Haupt-Toolbar ─────────────────────────────────────────────────────────

  Widget _buildToolbar() {
    return Container(
      color: NasiraColors.navGreen.withValues(alpha: 0.93),
      padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white, size: 22),
            tooltip: 'Schließen',
            onPressed: widget.onDismiss,
          ),
          IconButton(
            icon: Icon(
              Icons.undo,
              color: widget.overrideService.canUndo
                  ? Colors.white
                  : Colors.white30,
              size: 20,
            ),
            tooltip: 'Rückgängig',
            onPressed:
                widget.overrideService.canUndo ? _performUndo : null,
          ),
          IconButton(
            icon: Icon(
              Icons.redo,
              color: widget.overrideService.canRedo
                  ? Colors.white
                  : Colors.white30,
              size: 20,
            ),
            tooltip: 'Wiederholen',
            onPressed:
                widget.overrideService.canRedo ? _performRedo : null,
          ),
          Expanded(
            child: Text(
              widget.pageName,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Wortliste-Button — nur wenn die Seite AutoContent-Zellen hat
          if (widget.page.cells.any(
              (c) => c.type == GridCellType.autoContent))
            IconButton(
              icon: const Icon(Icons.list_alt_outlined,
                  color: Colors.white, size: 20),
              tooltip: 'Wortliste bearbeiten',
              onPressed: () => GridPageEditorSheet.show(
                context: context,
                page: widget.page,
                overrideService: widget.overrideService,
                onSaved: widget.onChanged,
              ),
            ),
          if (_hasChanges && !_saving)
            TextButton(
              onPressed: _confirmReset,
              style: TextButton.styleFrom(
                foregroundColor: Colors.white60,
                minimumSize: const Size(0, 32),
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: const Text('Reset', style: TextStyle(fontSize: 12)),
            ),
          const SizedBox(width: 4),
          FilledButton(
            onPressed: _saving || !_hasChanges ? null : _save,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: NasiraColors.navGreen,
              disabledBackgroundColor: Colors.white24,
              disabledForegroundColor: Colors.white54,
              minimumSize: const Size(80, 36),
            ),
            child: _saving
                ? const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: NasiraColors.navGreen))
                : const Text('Speichern',
                    style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  // ── Dimensions-Leiste ─────────────────────────────────────────────────────

  Widget _buildDimensionBar() {
    return Container(
      color: const Color(0xEE0E1A0E),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          const Icon(Icons.grid_on, color: Colors.white38, size: 14),
          const SizedBox(width: 8),
          // Spalten
          const Text('Sp.', style: TextStyle(color: Colors.white54, fontSize: 11)),
          const SizedBox(width: 4),
          _DimButton(icon: Icons.remove, onTap: _removeColumn),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text('$_columns',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700)),
          ),
          _DimButton(icon: Icons.add, onTap: _addColumn),

          const SizedBox(width: 20),

          // Zeilen
          const Text('Ze.', style: TextStyle(color: Colors.white54, fontSize: 11)),
          const SizedBox(width: 4),
          _DimButton(icon: Icons.remove, onTap: _removeRow),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text('$_rows',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700)),
          ),
          _DimButton(icon: Icons.add, onTap: _addRow),

          const Spacer(),
          Text(
            '$_columns × $_rows  |  ${_cells.length} Felder',
            style: const TextStyle(color: Colors.white38, fontSize: 10),
          ),
        ],
      ),
    );
  }

  // ── Grid-Fläche ───────────────────────────────────────────────────────────

  Widget _buildGridArea() {
    return LayoutBuilder(builder: (ctx, box) {
      // Alle Zeilen (inkl. Workspace) sind editierbar – kein Header-Band-Offset.
      final contentH = box.maxHeight;

      _cellW = box.maxWidth / _columns;
      _cellH = contentH / _rows;

      return Column(
        children: [
          // ── Volles Grid (alle Zeilen, inkl. Workspace) ────────────────────
          SizedBox(
            height: contentH,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onDoubleTapDown: (d) => _doubleTapPos = d.localPosition,
              onDoubleTap:     _handleDoubleTap,
              onPanStart:  (d) => _handlePanStart(d.localPosition),
              onPanUpdate: (d) => _handlePanUpdate(d.localPosition),
              onPanEnd:    (_) => _handlePanEnd(),
              child: ColoredBox(
                color: widget.pageColor,
                child: Stack(
                  clipBehavior: Clip.hardEdge,
                  children: [
                    // Gitterlinien
                    CustomPaint(
                      size: Size(box.maxWidth, contentH),
                      painter: _GridPainter(cols: _columns, rows: _rows),
                    ),

                    // Leere Gitterpositionen als anklickbare Platzhalter
                    ..._buildGhostCells(),

                    // Drop-Target-Vorschau während des Ziehens
                    if (_isDragging && _dropTargetX != null && _dropTargetY != null)
                      Positioned(
                        left:   _dropTargetX! * _cellW + 3,
                        top:    (_dropTargetY! - _wsFirstContent) * _cellH + 3,
                        width:  _dragging!.colSpan * _cellW - 6,
                        height: _dragging!.rowSpan * _cellH - 6,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border.all(
                                color: Colors.white54, width: 2,
                                style: BorderStyle.solid),
                            borderRadius: BorderRadius.circular(7),
                          ),
                        ),
                      ),

                    // Stationäre Zellen — Index-basierte Keys (kein Duplikat-Crash)
                    for (int i = 0; i < _cells.length; i++)
                      if (!(_cells[i] == _dragging && _isDragging))
                        AnimatedPositioned(
                          key: ValueKey(i),
                          duration: const Duration(milliseconds: 120),
                          curve: Curves.easeOut,
                          left:   _cells[i].x * _cellW + 3,
                          top:    (_cells[i].y - _wsFirstContent) * _cellH + 3,
                          width:  _cells[i].colSpan * _cellW - 6,
                          height: _cells[i].rowSpan * _cellH - 6,
                          child: _buildCellContent(
                            _cells[i],
                            isSelected: _cells[i] == _selected,
                            isDragging: false,
                            isResizing: _cells[i] == _selected && _mode == _EditorMode.resizing,
                          ),
                        ),

                    // Gezogene Zelle (folgt Zeiger)
                    if (_isDragging && _dragging != null)
                      Positioned(
                        left:   _dragPos.dx - _dragging!.colSpan * _cellW / 2 + 3,
                        top:    _dragPos.dy - _dragging!.rowSpan * _cellH / 2 + 3,
                        width:  _dragging!.colSpan * _cellW - 6,
                        height: _dragging!.rowSpan * _cellH - 6,
                        child: _buildCellContent(
                          _dragging!,
                          isSelected: false,
                          isDragging: true,
                          isResizing: false,
                        ),
                      ),

              // Resize-Handles (nur bei selektierter Zelle im Ruhezustand)
              if (_selected != null && _mode != _EditorMode.dragging)
                ..._buildResizeHandles(_selected!),
            ],
          ),
        ),
            ),
          ),
        ],
      );
    });
  }

  // ── Resize-Handles ────────────────────────────────────────────────────────

  List<Widget> _buildResizeHandles(_EditCell cell) {
    final dispY  = cell.y - _wsFirstContent;
    final right  = (cell.x + cell.colSpan) * _cellW;
    final bottom = (dispY + cell.rowSpan) * _cellH;
    final midX   = cell.x * _cellW + cell.colSpan * _cellW / 2;
    final midY   = dispY * _cellH + cell.rowSpan * _cellH / 2;
    const s = 14.0;
    const h = _handleRadius;

    Widget handle(double cx, double cy, IconData icon) => Positioned(
          left: cx - h, top: cy - h,
          width: h * 2, height: h * 2,
          child: Center(
            child: Container(
              width: s, height: s,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: NasiraColors.navGreen, width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 4,
                  )
                ],
              ),
              child: Icon(icon, size: 9, color: NasiraColors.navGreen),
            ),
          ),
        );

    return [
      handle(right,  midY,   Icons.open_in_full),
      handle(midX,   bottom, Icons.open_in_full),
      handle(right,  bottom, Icons.zoom_out_map),
    ];
  }

  // ── Echte Zelle mit Selektions-Overlay ───────────────────────────────────

  Widget _buildCellContent(
    _EditCell cell, {
    required bool isSelected,
    required bool isDragging,
    required bool isResizing,
  }) {
    Color borderColor;
    double borderWidth;
    if (isResizing)      { borderColor = Colors.amber; borderWidth = 3.0; }
    else if (isSelected) { borderColor = Colors.white; borderWidth = 2.5; }
    else                 { borderColor = Colors.white.withValues(alpha: 0.50); borderWidth = 1.0; }

    final radius = cell.src.isFullyRounded ? 1000.0 : 7.0;

    return Opacity(
      opacity: isDragging ? 0.82 : 1.0,
      child: Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.hardEdge,
        children: [
          IgnorePointer(child: widget.cellBuilder(cell.src)),
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: borderColor, width: borderWidth),
                borderRadius: BorderRadius.circular(radius),
              ),
            ),
          ),
          if (isSelected)
            const Positioned(
              top: 3, right: 3,
              child: SizedBox(
                width: 15, height: 15,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.check, size: 10, color: NasiraColors.navGreen),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Info-Panel ────────────────────────────────────────────────────────────

  Widget _buildInfoPanel() {
    final cell = _selected;
    if (cell == null) {
      return Container(
        height: 52,
        color: const Color(0xEE111E11),
        alignment: Alignment.center,
        child: const Text(
          'Antippen: Auswählen  ·  Ziehen: Verschieben  ·  Rand ziehen: Größe ändern',
          style: TextStyle(color: Colors.white38, fontSize: 11),
        ),
      );
    }

    final caption = cell.src.caption?.isNotEmpty == true
        ? cell.src.caption!
        : cell.src.insertText?.trim() ?? '—';

    return Container(
      color: const Color(0xEE111E11),
      padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
      child: Row(
        children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              color: cell.src.backgroundColor,
              borderRadius:
                  BorderRadius.circular(cell.src.isFullyRounded ? 16 : 5),
              border: Border.all(color: Colors.white30),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(caption,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                Text(
                  'Pos (${cell.x}, ${cell.y})  ·  '
                  '${cell.colSpan}×${cell.rowSpan} Felder  ·  '
                  '${cell.src.style.name}',
                  style: const TextStyle(color: Colors.white54, fontSize: 10),
                ),
              ],
            ),
          ),
          // Kopieren
          IconButton(
            icon: const Icon(Icons.copy_outlined,
                color: Colors.white54, size: 18),
            tooltip: 'Zelle kopieren',
            onPressed: _copySelected,
          ),
          // Einfügen — nur wenn Clipboard gefüllt
          if (_clipboard != null)
            IconButton(
              icon: const Icon(Icons.paste_outlined,
                  color: Colors.white70, size: 18),
              tooltip: 'Inhalt einfügen',
              onPressed: _pasteToSelected,
            ),
          IconButton(
            icon: const Icon(Icons.edit_outlined, color: Colors.white70, size: 20),
            tooltip: 'Beschriftung / Symbol / Funktion bearbeiten',
            onPressed: () => BriefGridEditorOverlay.showCellSheet(
              context: context,
              cell: cell.src,
              pageName: widget.pageName,
              overrideService: widget.overrideService,
              onChanged: widget.onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Hilfs-Widget: Dimensions-Button ───────────────────────────────────────────

class _DimButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _DimButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 24, height: 24,
        decoration: BoxDecoration(
          color: Colors.white12,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Icon(icon, color: Colors.white70, size: 14),
      ),
    );
  }
}

// ── _GridPainter ──────────────────────────────────────────────────────────────

class _GridPainter extends CustomPainter {
  final int cols, rows;
  const _GridPainter({required this.cols, required this.rows});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.16)
      ..strokeWidth = 0.8;
    final cw = size.width  / cols;
    final ch = size.height / rows;
    for (int c = 1; c < cols; c++) {
      canvas.drawLine(Offset(c * cw, 0), Offset(c * cw, size.height), paint);
    }
    for (int r = 1; r < rows; r++) {
      canvas.drawLine(Offset(0, r * ch), Offset(size.width, r * ch), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter o) => o.cols != cols || o.rows != rows;
}
