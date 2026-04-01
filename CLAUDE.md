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

### ☐ 5 — Hintergrundfarbe Picker
**Status: OFFEN**
**Dateien:** `brief_grid_editor_overlay.dart`, `grid_override_service.dart`, alle _applyOverride
**Was:** flutter_colorpicker oder Material ColorPicker im Sheet, speichern als `backgroundColor` (hex)

### ☐ 6 — Textfarbe Picker
**Status: OFFEN**
**Dateien:** wie #5
**Was:** Zweiter ColorPicker für `fontColor`

### ☐ 7 — Schriftgröße
**Status: OFFEN**
**Dateien:** `brief_grid_editor_overlay.dart`, `grid_override_service.dart`, alle _applyOverride
**Was:** Schieberegler 8–40pt, speichern als `fontSize` (double)

### ☐ 14 — Style-System (Named Styles)
**Status: OFFEN**
**Dateien:** neues `lib/services/grid_style_service.dart`, `brief_grid_editor_overlay.dart`
**Was:** 54 Styles aus styles.xml parsen → Dropdown im Cell-Editor → setzt backgroundColor + fontColor + shape en bloc

---

## RUNDE 2 — Wichtig für echten Workflow

### ☐ 17 — WordList-Editor
**Status: OFFEN**
**Was:** Wortlisten-Einträge hinzufügen / entfernen / umsortieren (Text + Symbol)

### ☐ 16 — Zelle kopieren / einfügen
**Status: OFFEN**
**Was:** In-Memory Clipboard im Editor-State, Ctrl+C / Ctrl+V

### ☐ 20 — Neue Zelle erstellen (Ghost → real)
**Status: OFFEN**
**Was:** Virtual-Cell-Konzept im Override-Service

---

## RUNDE 3 — Erweiterte Features

### ☐ 19 — Undo / Redo
### ☐ 22 — InsertText mit eingebettetem Symbol (Rich Text)
### ☐ 23 — Neues Grid erstellen

---

## Erledigte Vorarbeiten (vor diesem Plan)
- Grid3-XML-getriebene Screens: Brief, Tagebuch, Einkaufen, FreiesSchreiben ✅
- GridLayoutEditor: Drag, Resize, Ghost-Kacheln, Doppeltippen ✅
- Cell-Editor: Caption, Symbol, 1 Befehl ✅
- Override-Service: layout, cell (caption/symbolStem/commands), gridSize ✅
- NasiraTitleBar + Hamburger auf allen Screens ✅
- Reflow-Fix (nur bei echtem Overlap) ✅
- Header-Band → vollständig editierbares Grid ✅
