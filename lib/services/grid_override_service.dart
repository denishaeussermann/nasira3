import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/grid_page.dart';

// ── Undo / Redo Datentypen ────────────────────────────────────────────────────

/// Snapshot des Override-Zustands für ein einzelnes Grid.
class _GridState {
  final Map<String, Map<String, dynamic>>? cells;
  final Map<String, Map<String, int>>? layout;
  final Map<String, int>? gridSize;
  const _GridState({this.cells, this.layout, this.gridSize});
}

/// Ein Undo-Eintrag enthält den Zustand vor und nach einer Operation.
class _UndoEntry {
  final String gridName;
  final _GridState before;
  final _GridState after;
  const _UndoEntry({
    required this.gridName,
    required this.before,
    required this.after,
  });
}

/// Persistiert benutzerdefinierte Änderungen an Grid-Wortlisten und -Zellen.
///
/// Datei: `nasira_grid_overrides.json` im App-Dokumentenverzeichnis.
/// Format:
/// ```json
/// {
///   "Brief 4 über dich": {
///     "wordList": [{ "text": "Wie alt bist du?" }],
///     "cells": { "2,1": { "caption": "Neuer Text", "symbolStem": "freund2" } }
///   }
/// }
/// ```
class GridOverrideService {
  static const _fileName = 'nasira_grid_overrides.json';

  // pageName → wordList
  final Map<String, List<Map<String, dynamic>>> _data = {};
  // pageName → "origX,origY" → { "caption"?, "symbolStem"? }
  final Map<String, Map<String, Map<String, dynamic>>> _cellData = {};
  // pageName → "origX,origY" → { x, y, colSpan, rowSpan }
  final Map<String, Map<String, Map<String, int>>> _layoutData = {};
  // pageName → { columns, rows }
  final Map<String, Map<String, int>> _gridSizeData = {};
  bool _loaded = false;

  // ── Undo / Redo ───────────────────────────────────────────────────────────
  static const _kMaxUndo = 50;
  final List<_UndoEntry> _undoStack = [];
  final List<_UndoEntry> _redoStack = [];

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  // ── Datei-Zugriff ─────────────────────────────────────────────────────────

  Future<File> _getFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  // ── Laden ─────────────────────────────────────────────────────────────────

  Future<void> load() async {
    if (_loaded) return;
    try {
      final file = await _getFile();
      if (!await file.exists()) {
        _loaded = true;
        return;
      }
      final outer = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      for (final entry in outer.entries) {
        final inner = entry.value as Map<String, dynamic>;
        final wl = (inner['wordList'] as List<dynamic>? ?? [])
            .cast<Map<String, dynamic>>();
        _data[entry.key] = wl;
        final rawCells = inner['cells'] as Map<String, dynamic>?;
        if (rawCells != null) {
          _cellData[entry.key] = rawCells.map(
            (k, v) => MapEntry(k, Map<String, dynamic>.from(v as Map)),
          );
        }
        final rawLayout = inner['layout'] as Map<String, dynamic>?;
        if (rawLayout != null) {
          _layoutData[entry.key] = rawLayout.map(
            (k, v) => MapEntry(
              k,
              (v as Map).map((lk, lv) => MapEntry(lk as String, lv as int)),
            ),
          );
        }
        final rawSize = inner['gridSize'] as Map<String, dynamic>?;
        if (rawSize != null) {
          _gridSizeData[entry.key] = rawSize
              .map((k, v) => MapEntry(k, v as int));
        }
      }
      _loaded = true;
    } catch (e) {
      debugPrint('[GridOverride] load error: $e');
      _loaded = true;
    }
  }

  // ── Speichern ─────────────────────────────────────────────────────────────

  Future<void> _save() async {
    try {
      final file  = await _getFile();
      final pages = <String, dynamic>{};
      final allKeys = {
        ..._data.keys, ..._cellData.keys,
        ..._layoutData.keys, ..._gridSizeData.keys,
      };
      for (final key in allKeys) {
        pages[key] = {
          if (_data.containsKey(key))         'wordList': _data[key],
          if (_cellData.containsKey(key))     'cells':    _cellData[key],
          if (_layoutData.containsKey(key))   'layout':   _layoutData[key],
          if (_gridSizeData.containsKey(key)) 'gridSize': _gridSizeData[key],
        };
      }
      await file.writeAsString(jsonEncode(pages));
    } catch (e) {
      debugPrint('[GridOverride] save error: $e');
    }
  }

  // ── Undo / Redo Hilfsmethoden ─────────────────────────────────────────────

  /// Erstellt einen tiefen Snapshot des Override-Zustands für [gridName].
  _GridState _snapshotGrid(String gridName) => _GridState(
        cells: _cellData[gridName]
            ?.map((k, v) => MapEntry(k, Map<String, dynamic>.from(v))),
        layout: _layoutData[gridName]
            ?.map((k, v) => MapEntry(k, Map<String, int>.from(v))),
        gridSize: _gridSizeData[gridName] != null
            ? Map<String, int>.from(_gridSizeData[gridName]!)
            : null,
      );

  /// Stellt einen Snapshot für [gridName] wieder her (in-memory, kein _save).
  void _restoreGrid(String gridName, _GridState state) {
    if (state.cells == null) {
      _cellData.remove(gridName);
    } else {
      _cellData[gridName] =
          state.cells!.map((k, v) => MapEntry(k, Map<String, dynamic>.from(v)));
    }
    if (state.layout == null) {
      _layoutData.remove(gridName);
    } else {
      _layoutData[gridName] =
          state.layout!.map((k, v) => MapEntry(k, Map<String, int>.from(v)));
    }
    if (state.gridSize == null) {
      _gridSizeData.remove(gridName);
    } else {
      _gridSizeData[gridName] = Map<String, int>.from(state.gridSize!);
    }
  }

  /// Legt einen Eintrag auf den Undo-Stack und löscht den Redo-Stack.
  void _pushUndo(_UndoEntry entry) {
    _undoStack.add(entry);
    if (_undoStack.length > _kMaxUndo) _undoStack.removeAt(0);
    _redoStack.clear();
  }

  // ── Öffentliche API — Undo / Redo ─────────────────────────────────────────

  /// Macht die letzte gespeicherte Änderung rückgängig und schreibt die Datei.
  Future<void> undo() async {
    if (_undoStack.isEmpty) return;
    final entry = _undoStack.removeLast();
    _redoStack.add(entry);
    _restoreGrid(entry.gridName, entry.before);
    await _save();
  }

  /// Stellt eine rückgängig gemachte Änderung wieder her und schreibt die Datei.
  Future<void> redo() async {
    if (_redoStack.isEmpty) return;
    final entry = _redoStack.removeLast();
    _undoStack.add(entry);
    _restoreGrid(entry.gridName, entry.after);
    await _save();
  }

  // ── Öffentliche API — Wortliste ───────────────────────────────────────────

  /// Gibt die überschriebene Wortliste zurück, oder null wenn keine vorhanden.
  List<GridWordListItem>? getWordList(String gridName) {
    final raw = _data[gridName];
    if (raw == null) return null;
    return raw.map(_itemFromMap).toList();
  }

  /// Speichert [items] als Überschreibung für [gridName].
  Future<void> setWordList(
      String gridName, List<GridWordListItem> items) async {
    _data[gridName] = items.map(_itemToMap).toList();
    await _save();
  }

  /// Löscht die Wortlisten-Überschreibung für [gridName].
  Future<void> reset(String gridName) async {
    _data.remove(gridName);
    await _save();
  }

  /// Gibt true zurück wenn [gridName] eine gespeicherte Überschreibung hat.
  bool hasOverride(String gridName) =>
      _data.containsKey(gridName) || _cellData.containsKey(gridName);

  // ── Öffentliche API — Zellen ──────────────────────────────────────────────

  /// Alle Zellen-Overrides für [gridName]: "x,y" → {caption?, symbolStem?}.
  Map<String, Map<String, dynamic>>? getAllCellOverrides(String gridName) =>
      _cellData[gridName];

  /// Override für eine einzelne Zelle, oder null.
  Map<String, dynamic>? getCellOverride(String gridName, int x, int y) =>
      _cellData[gridName]?['$x,$y'];

  /// Setzt Caption, symbolStem, Befehle und/oder Form für die Zelle (x, y) auf [gridName].
  /// [commands]: Liste von Befehl-Maps, z. B. [{'type': 'jumpTo', 'jumpTarget': 'Brief 4'}].
  ///             null = nicht ändern, [] = Befehle löschen.
  /// [shape]: 'roundedRect' | 'oval' | 'pill' | null (null = nicht ändern).
  /// [backgroundColor] / [fontColor]: 8-stelliger Hex-String 'AARRGGBB', oder
  ///   Leer-String '' = Override löschen, null = nicht ändern.
  Future<void> setCellOverride(
    String gridName,
    int x,
    int y, {
    String? caption,
    String? symbolStem,
    List<Map<String, dynamic>>? commands,
    String? shape,
    String? backgroundColor,
    String? fontColor,
    double? fontSize,
  }) async {
    final before = _snapshotGrid(gridName);
    _cellData.putIfAbsent(gridName, () => {});
    final key      = '$x,$y';
    final existing = Map<String, dynamic>.from(_cellData[gridName]![key] ?? {});
    if (caption    != null) existing['caption']    = caption;
    if (symbolStem != null) existing['symbolStem'] = symbolStem;
    if (commands   != null) existing['commands']   = commands;
    if (shape      != null) existing['shape']      = shape;
    if (backgroundColor != null) {
      if (backgroundColor.isEmpty) { existing.remove('backgroundColor'); }
      else { existing['backgroundColor'] = backgroundColor; }
    }
    if (fontColor != null) {
      if (fontColor.isEmpty) { existing.remove('fontColor'); }
      else { existing['fontColor'] = fontColor; }
    }
    if (fontSize != null) existing['fontSize'] = fontSize;
    _cellData[gridName]![key] = existing;
    await _save();
    _pushUndo(_UndoEntry(
      gridName: gridName,
      before: before,
      after: _snapshotGrid(gridName),
    ));
  }

  /// Löscht alle Zell-Overrides für [gridName].
  Future<void> clearAllCellOverrides(String gridName) async {
    _cellData.remove(gridName);
    await _save();
  }

  /// Löscht den Override für eine einzelne Zelle.
  Future<void> clearCellOverride(String gridName, int x, int y) async {
    final before = _snapshotGrid(gridName);
    _cellData[gridName]?.remove('$x,$y');
    if (_cellData[gridName]?.isEmpty == true) _cellData.remove(gridName);
    await _save();
    _pushUndo(_UndoEntry(
      gridName: gridName,
      before: before,
      after: _snapshotGrid(gridName),
    ));
  }

  // ── Öffentliche API — Layout + Undo ──────────────────────────────────────

  /// Speichert Layout- und Grid-Größen-Overrides in einem einzigen Undo-Schritt.
  ///
  /// [newColumns] / [newRows]: null = keine Größenänderung.
  Future<void> saveLayoutChanges(
    String gridName, {
    required Map<String, Map<String, int>> layoutOverrides,
    int? newColumns,
    int? newRows,
  }) async {
    final before = _snapshotGrid(gridName);
    if (layoutOverrides.isEmpty) {
      _layoutData.remove(gridName);
    } else {
      _layoutData[gridName] = layoutOverrides;
    }
    if (newColumns != null && newRows != null) {
      _gridSizeData[gridName] = {'columns': newColumns, 'rows': newRows};
    }
    await _save();
    _pushUndo(_UndoEntry(
      gridName: gridName,
      before: before,
      after: _snapshotGrid(gridName),
    ));
  }

  // ── Öffentliche API — Layout ──────────────────────────────────────────────

  /// Alle Layout-Overrides für [gridName]: "origX,origY" → {x, y, colSpan, rowSpan}.
  Map<String, Map<String, int>>? getLayoutOverrides(String gridName) =>
      _layoutData[gridName];

  /// Speichert neue Positionen/Größen für Zellen einer Seite.
  /// [overrides]: "origX,origY" → {x, y, colSpan, rowSpan}
  Future<void> setLayoutOverrides(
    String gridName,
    Map<String, Map<String, int>> overrides,
  ) async {
    if (overrides.isEmpty) {
      _layoutData.remove(gridName);
    } else {
      _layoutData[gridName] = overrides;
    }
    await _save();
  }

  /// Löscht alle Layout-Overrides für [gridName].
  Future<void> clearLayoutOverrides(String gridName) async {
    _layoutData.remove(gridName);
    await _save();
  }

  // ── Öffentliche API — Grid-Größe ──────────────────────────────────────────

  /// Gespeicherte Spalten/Zeilen-Überschreibung für [gridName], oder null.
  Map<String, int>? getGridSize(String gridName) => _gridSizeData[gridName];

  /// Speichert neue Spalten/Zeilen-Anzahl für [gridName].
  Future<void> setGridSize(String gridName, int columns, int rows) async {
    _gridSizeData[gridName] = {'columns': columns, 'rows': rows};
    await _save();
  }

  /// Löscht die Größen-Überschreibung für [gridName].
  Future<void> clearGridSize(String gridName) async {
    _gridSizeData.remove(gridName);
    await _save();
  }

  // ── Serialisierung ────────────────────────────────────────────────────────

  static GridWordListItem _itemFromMap(Map<String, dynamic> m) =>
      GridWordListItem(
        text: m['text'] as String? ?? '',
        localImagePath: m['localImagePath'] as String?,
      );

  static Map<String, dynamic> _itemToMap(GridWordListItem item) => {
        'text': item.text,
        if (item.localImagePath != null) 'localImagePath': item.localImagePath,
      };
}
