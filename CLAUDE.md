# Nasira Editor – Arbeitsplan (Grid3 Reverse Engineering)

## Arbeitsweise
- Jeder Punkt wird abgearbeitet, dann eigenständig der nächste vorgeschlagen
- Nach jedem Punkt: `flutter analyze` + commit + push
- Datei nach jedem Punkt aktualisieren (Status + Notizen)
- Tokens sparen: Code nicht neu lesen wenn bereits bekannt

## Architektur-Kurzreferenz
- Editor-Widget: `lib/widgets/grid_layout_editor.dart`
- Zell-Editor Sheet: `lib/widgets/brief_grid_editor_overlay.dart` → `_CellEditorSheet`
- Override-Service: `lib/services/grid_override_service.dart`
- Grid-Modell: `lib/models/grid_page.dart` (GridCell, GridCellCommand, GridCommandType, GridCellStyle)
- Screens: brief_screen, tagebuch_screen, einkaufen_screen, freies_schreiben_screen
- _applyOverride in jedem Screen wendet cellOv + layoutOv + sizeOv an
- Override-JSON: `nasira_grid_overrides.json` im App-Dokumente-Verzeichnis

## Grid3 XML Referenz
- BackgroundShape: 1=RoundedRect, 2=Oval, 5=Pill
- Befehle: Jump.To/Back/Home/SetBookmark, Action.Letter/Space/Clear/InsertText/DeleteWord/DeleteLetter/Punctuation/Enter, Prediction.MoreWords, ComputerControl.CapsLock/Shift, ClockWriteDate, WebBrowser.NavigateUrl, Settings.Exit
- Styles: 54 named styles in Settings0/Styles/styles.xml (BackColour, FontColour, BorderColour, FontName, FontSize, BackgroundShape)
- Zellen: X, Y, ColumnSpan, RowSpan, ScanBlock, Visibility=Hidden
- Mehrere Befehle pro Zelle möglich (Chain)

---

## RUNDE 1 — Hoher Nutzen, geringer Aufwand

### ✅ 13 — Mehrere Befehle pro Zelle
**Status: ERLEDIGT**
**Notizen:** _CmdEntry-Liste, ReorderableList, Speichern als commands-Array im Override-Service.

### ✅ 8 — BackgroundShape Selector
**Status: ERLEDIGT**
**Notizen:** `shapeOverride` in GridCell, `_ShapeSelector`-Widget (Original/Abgerundet/Oval/Pille), alle _applyOverride und Render-Stellen auf `isFullyRounded` umgestellt.

### ✅ 5+6 — Hintergrundfarbe + Textfarbe Picker
**Status: ERLEDIGT**
**Notizen:** _ColorSwatchPicker (24 Farben aus Nasira-Palette), backgroundColorOverride + fontColorOverride in GridCell, hex-Kodierung AARRGGBB, alle _applyOverride-Methoden aktualisiert.

### ✅ 7 — Schriftgröße
**Status: ERLEDIGT**
**Notizen:** Slider 8–40pt im Sheet, fontSizeOverride in GridCell, Screens nutzen fontSizeOverride ?? Standardgröße.

### ✅ 14 — Style-System (Named Styles)
**Status: ERLEDIGT**
**Notizen:** GridStyleService (28 hardcodierte Styles aus styles.xml), _NamedStylePicker als horizontale Chip-Leiste im Cell-Editor; Antippen setzt backgroundColor + fontColor + shape en bloc.

---

## RUNDE 2 — Wichtig für echten Workflow

### ✅ 17 — WordList-Editor
**Status: ERLEDIGT**
**Notizen:** GridPageEditorSheet mit Symbol-Suche (_WordListItemDialog); Wortliste-Button (list_alt) in GridLayoutEditor-Toolbar, nur sichtbar wenn AutoContent-Zellen vorhanden.

### ✅ 16 — Zelle kopieren / einfügen
**Status: ERLEDIGT**
**Notizen:** _clipboard (GridCell?) in GridLayoutEditorState; Copy/Paste-Buttons in InfoPanel; Ghost-Zellen zeigen Paste-Icon wenn Clipboard gefüllt.

### ✅ 20 — Neue Zelle erstellen (Ghost → real)
**Status: ERLEDIGT**
**Notizen:** Ghost-Doppeltippen öffnet Editor mit leerer Zelle (x,y); nach Speichern erzeugt _applyOverrides die Zelle als Virtual Cell aus Orphan-Override. Kein separates Datenmodell nötig.

---

## RUNDE 3 — Erweiterte Features

### ✅ 19 — Undo / Redo
**Status: ERLEDIGT**
**Notizen:** _GridState + _UndoEntry in GridOverrideService; setCellOverride + clearCellOverride + saveLayoutChanges pushen auf _undoStack; undo()/redo() stellen per _restoreGrid wieder her; GridLayoutEditor: didUpdateWidget reinit, _performUndo/_performRedo, Undo/Redo-Buttons in Toolbar.
### ✅ 23 — Neues Grid erstellen
**Status: ERLEDIGT**
**Notizen:** GridOverrideService: _userGridMeta (JSON-Schlüssel _userGridMeta), createUserGrid/deleteUserGrid/listUserGrids/buildUserGridPage; UserGridsScreen (Liste + FAB + Lösch-Dialog); _UserGridEditorPage (GridLayoutEditor ohne XML-Rohseite); _NewGridDialog mit _Counter (Spalten/Zeilen); Startseite: „Meine Grids"-Kachel (navGreen, ersetzt Raster).

### ✅ 22 — InsertText mit eingebettetem Symbol (Segment-Chip-Editor)
**Status: ERLEDIGT**
**Notizen:** InsertSegment-Klasse in grid_page.dart (type 'text'|'symbol', stem als eindeutige Symbolreferenz); GridCellCommand.segments optional; _Segment mutable + _CmdEntry.segments in brief_grid_editor_overlay.dart; _SegmentChipEditor: Chip-Leiste mit Text-/Symbol-Chips, Inline-Symbolsuche, PopupMenu zum Hinzufügen; toJson() generiert segments-Array + insertText-Plaintext-Fallback für AAC-Ausführung; alle drei Screens: _parseCommandOverrides parst segments.

---

## Erledigte Vorarbeiten (vor diesem Plan)
- Grid3-XML-getriebene Screens: Brief, Tagebuch, Einkaufen, FreiesSchreiben ✅
- GridLayoutEditor: Drag, Resize, Ghost-Kacheln, Doppeltippen ✅
- Cell-Editor: Caption, Symbol, 1 Befehl ✅
- Override-Service: layout, cell (caption/symbolStem/commands), gridSize ✅
- NasiraTitleBar + Hamburger auf allen Screens ✅
- Reflow-Fix (nur bei echtem Overlap) ✅
- Header-Band → vollständig editierbares Grid ✅
