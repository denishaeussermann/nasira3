# Nasira – App-Dokumentation (Stand 2026-04-02)

Nasira ist eine Flutter-AAC-App (Augmentative and Alternative Communication) für Windows/Android.
Sie bildet das Grid3-Kommunikationssystem nach: Grids werden 1:1 aus dem Grid3-Export gelesen,
per Override-System angepasst und mit Metacom-Symbolunterstützung angezeigt.

---

## Arbeitsweise (KI-Richtlinien)
- Nach jedem Arbeitsschritt: `flutter analyze` + commit + push
- CLAUDE.md nach größeren Änderungen aktualisieren
- Tokens sparen: Code nicht neu lesen, wenn bereits bekannt
- Kein spekulatives Refactoring – nur was explizit gefragt ist

---

## Projektstruktur

```
lib/
├── main.dart                        # Entry Point, Provider-Setup, Windows-Semantics-Fix
├── nasira_app_state.dart            # Zentraler ChangeNotifier: Text, Symbole, Vorschläge
├── nasira_repository.dart           # Datenladen (words/symbols/mappings JSON)
├── nasira_home_page.dart            # Shim → FreiesSchreibenScreen
├── nasira_import_service.dart       # Kontext-Vorschläge, Partizip-II-Mapping
├── embedding_service.dart           # Semantische Einbettungen (Float32List, O(1)-Lookup)
│
├── models/
│   ├── grid_page.dart               # KERN-MODELL: GridPage, GridCell, GridCellCommand,
│   │                                #   GridCommandType, GridCellType, GridCellStyle,
│   │                                #   InsertSegment, GridWordListItem
│   ├── nasira_data.dart             # NasiraData: Wörter, Symbole, Mappings + Indizes
│   ├── word_entry.dart              # WordEntry (id, text, rank, nextWords)
│   ├── symbol_entry.dart            # SymbolEntry (label, fileName, category, assetPath)
│   ├── word_symbol_mapping.dart     # WordSymbolMapping (wordId ↔ symbolId)
│   ├── mapped_symbol.dart           # MappedSymbol (WordEntry + SymbolEntry)
│   ├── custom_sentence.dart         # CustomSentence (text, module: brief|tagebuch|alle)
│   ├── search_result.dart           # SearchResult + SearchMatchType-Enum
│   └── models.dart                  # Barrel-Export
│
├── services/
│   ├── grid_import_service.dart     # Grid3-XML → GridPage (Pfad: Nasira EXPORT\Grids\)
│   ├── grid_override_service.dart   # Zell-/Layout-Overrides + Undo/Redo, User-Grids
│   ├── grid_style_service.dart      # 28 Named Styles aus styles.xml (hardcodiert)
│   ├── document_service.dart        # SavedDocument-Verwaltung (nasira_documents.json)
│   ├── custom_sentences_service.dart# User-Sätze (nasira_custom_sentences.json, PIN-geschützt)
│   ├── symbol_lookup_service.dart   # 7-stufiger Symbol-Lookup (exakt→normalisiert→…→Embedding)
│   ├── suggestion_engine.dart       # Wortvorschläge (7 Prioritäten, max. 14 Slots)
│   ├── asset_resolver_service.dart  # AssetManifest → schnelle Pfadauflösung per Basename
│   ├── search_log_service.dart      # Logging für Symbol-Suchanfragen
│   └── services.dart                # Barrel-Export
│
├── screens/
│   ├── startseite_screen.dart       # Startseite (10×6, #171947): Modul-Kacheln + Datei + Settings
│   ├── brief_screen.dart            # Brief-Modul: Satzstarter → Thema → Unterthema
│   ├── tagebuch_screen.dart         # Tagebuch-Modul: Wochentage → Themen → Sätze
│   ├── einkaufen_screen.dart        # Einkaufen-Modul: Grid3-XML-getrieben
│   ├── freies_schreiben_screen.dart # Freies Schreiben: QWERTZ-Tastatur (25×8) + Vorhersage
│   ├── datei_screen.dart            # Datei-Manager: Grid3 "Datei"-Grid (11×8) + Sub-Pages
│   ├── user_grids_screen.dart       # Meine Grids: User-erstellte Grids (Liste + FAB)
│   └── setup_screen.dart            # Einstellungen: PIN, Custom Sentences, Datenquelle
│
├── widgets/
│   ├── nasira_grid_cell.dart        # Universelle Grid3-Kachel (Symbol + Caption + Farben)
│   ├── nasira_text_workspace.dart   # Textfeld mit Metacom-Symbolen + sichtbarem Cursor
│   ├── nasira_title_bar.dart        # Titelleiste + Hamburger-Menü (öffnet Layout-Editor)
│   ├── nasira_nav_bar.dart          # Navigationsleiste (Home, Zurück, Löschen, etc.)
│   ├── nasira_keyboard.dart         # QWERTZ-Tastatur (kein System-Keyboard)
│   ├── grid_layout_editor.dart      # Visueller Grid-Editor: Drag, Resize, Ghost, Undo/Redo
│   ├── brief_grid_editor_overlay.dart # Zell-Editor Sheet (_CellEditorSheet): Caption,
│   │                                #   Symbol, Befehle, Farben, Form, Style, Segmente
│   ├── grid_page_editor_sheet.dart  # WordList-Editor (Symbol-Suche pro Slot)
│   ├── composite_symbol.dart        # Symbol+Wort-Paar-Widget (Metacom über Text)
│   ├── symbol_tile.dart             # Einzelnes Symbol-Tile
│   └── nasira_module_header.dart    # Modul-Header-Widget
│
├── theme/
│   └── nasira_colors.dart           # Komplette Farbpalette (Grid3-Styles, Wochentage, etc.)
│
└── core/
    └── text_normalizer.dart         # Unicode-Normalisierung (Umlaute, Combining Marks)
```

---

## Kern-Modell: grid_page.dart

### GridCellType
```
normal       – reguläre Kachel mit Befehl(en)
autoContent  – dynamischer Slot für WordList-Einträge (Vorhersage)
workspace    – Texteditor-Bereich (NasiraTextWorkspace)
liveCell     – Dokumenten-Liste im Datei-Screen (ContentType=LiveCell)
empty        – unsichtbare Zelle
```

### GridCommandType (alle 32 Werte)
```
insertText, jumpTo, jumpBack, jumpHome, punctuation,
deleteWord, deleteLetter, documentEnd, enter, moreWords,
setBookmark, capsLock, shift, speak,
copyText, pasteText, printText, settingsExit,
textEditorNew, textEditorDelete, textEditorPrevious, textEditorNext,
previousLetter, nextLetter, previousWord, nextWord,
previousSentence, nextSentence, previousLine, nextLine,
documentStart, other
```

### GridCellStyle (13 Werte + unknown)
```
actionNav, satzanfang, frage, neutral, wortliste, hauptthema,
weitereWoerter, invertiert, textfeld, freiesSchreiben,
satzanfangVergangenheit, frageVergangenheit, unterthema,
dateiTextfeld, unknown
```

### GridCell – Override-Felder
```dart
shapeOverride:           String?   // 'rounded'|'oval'|'pill' überschreibt XML-Form
backgroundColorOverride: Color?    // AARRGGBB-Farbe
fontColorOverride:       Color?    // AARRGGBB-Farbe
fontSizeOverride:        double?   // 8–40pt
```

### InsertSegment
Für strukturierte InsertText-Befehle mit eingebetteten Symbolen:
```dart
type: 'text' | 'symbol'
text: String?   // bei type='text'
stem: String?   // bei type='symbol': eindeutiger Dateiname ohne Endung
```

---

## Persistenz-Dateien (App-Dokumente-Verzeichnis)

| Datei | Inhalt |
|---|---|
| `nasira_grid_overrides.json` | Alle Zell-, Layout-, Größen-Overrides + User-Grid-Metadaten |
| `nasira_documents.json` | Gespeicherte Dokumente `[{text, timestamp}]` max. 50 |
| `nasira_custom_sentences.json` | User-definierte Sätze mit Modul-Zuordnung, PIN-geschützt |
| `app_state.json` | Datenquelle (bundled vs. importiert), weitere Einstellungen |

---

## Grid3-Export-Pfad
```
C:\Users\denlu\Documents\Nasira EXPORT\Grids\
  <GridName>\grid.xml   ← wird von GridImportService gelesen
```

### XML → GridCommandType Mapping (grid_import_service.dart)
```
Action.InsertText       → insertText
Action.Letter           → insertText
Action.Space            → insertText (' ')
Action.Punctuation      → punctuation
Action.DeleteWord       → deleteWord
Action.DeleteLetter     → deleteLetter
Action.Clear            → deleteWord
Action.DocumentEnd      → documentEnd
Action.Enter            → enter
Action.Speak            → speak
Action.Copy             → copyText
Action.Paste            → pasteText
Action.Print            → printText
Action.PreviousLetter   → previousLetter
Action.NextLetter       → nextLetter
Action.PreviousWord     → previousWord
Action.NextWord         → nextWord
Action.PreviousSentence → previousSentence
Action.NextSentence     → nextSentence
Action.PreviousLine     → previousLine
Action.NextLine         → nextLine
Action.DocumentStart    → documentStart
Jump.To                 → jumpTo
Jump.Back               → jumpBack
Jump.Home               → jumpHome
Jump.SetBookmark        → setBookmark
Prediction.MoreWords    → moreWords
Prediction.MorePredictions → moreWords
ComputerControl.CapsLock → capsLock
ComputerControl.Shift   → shift
Settings.Exit           → settingsExit
TextEditor.New          → textEditorNew
TextEditor.Delete       → textEditorDelete
TextEditor.Previous     → textEditorPrevious
TextEditor.Next         → textEditorNext
```

### Bekannte nicht gemappte Befehle (→ null, Zelle wird ignoriert)
```
Action.UndoClear, ClockWriteDate, WebBrowser.NavigateUrl
```

---

## Screen-Architektur (Muster)

Alle Haupt-Screens folgen demselben Muster:

```dart
// 1. Lazy-Grid-Cache
final Map<String, GridPage> _grids = {};
final _importer       = GridImportService();
final _overrideService = GridOverrideService();

// 2. Laden + Override anwenden
Future<void> _loadGrid(String name) async { ... }
GridPage _applyOverride(String name, GridPage raw) { ... }

// 3. Interner Navigations-Stack
final List<String> _history = [];
void _navigate(String target) { ... }
void _goBack() { ... }

// 4. Befehle ausführen
void _run(List<GridCellCommand> cmds, NasiraAppState state) {
  for (final cmd in cmds) {
    switch (cmd.type) { ... }
  }
}

// 5. Rendern: LayoutBuilder → Stack → Positioned pro Zelle
```

### _applyOverride – Standard-Implementierung
Jeder Screen hat eine lokale Kopie von `_applyOverride()` + `_parseCommandOverrides()` + `_hexToColor()`.
Alle lesen aus `GridOverrideService`: `getAllCellOverrides`, `getLayoutOverrides`, `getGridSize`.
**Virtuelle Zellen** (Overrides ohne XML-Zelle) werden als neue `GridCell` eingefügt.

---

## NasiraAppState – Text-Operationen (cursor-aware seit 2026-04-02)

Alle Methoden arbeiten an der aktuellen **Cursor-Position** (`textController.selection`):

```dart
insertPhrase(String phrase)   // Phrase an Cursor, Leerzeichen automatisch
insertWord(NasiraData, WordEntry) // Ersetzt Token vor Cursor (Vorhersage)
appendLetter(String chars)    // Einzelnes Zeichen/Sequenz an Cursor
deleteLastLetter()            // Zeichen vor Cursor löschen (Unicode-sicher)
deleteLastWord()              // Wort vor Cursor löschen
clearText()                   // Alles löschen + Symbol-Cache leeren
```

---

## NasiraTextWorkspace – Cursor-Anzeige (seit 2026-04-02)

- Baut Token-Liste um `controller.selection.baseOffset` herum auf
- Zeigt blauen 2px-Strich (`_buildCursorWidget`) an der Cursor-Position im Wrap
- Unsichtbares `TextField` für USB-Tastatur-Eingabe (Opacity 0.0)
- Cursor im sichtbaren Bereich: `Colors.blue.shade600`, Höhe 50px

---

## GridLayoutEditor (grid_layout_editor.dart)

Visueller Editor für alle Screens – wird per Hamburger-Menü geöffnet:

- **Drag**: Zellen verschieben (Overlap-Erkennung + Reflow)
- **Resize**: Größenänderung über Handles an allen 4 Ecken (`Clip.none` für sichtbare Handles)
- **Ghost-Kacheln**: leere Slots als gestrichelte Kacheln; Doppeltippen → neue Zelle
- **Copy/Paste**: `_clipboard` (GridCell?) in State; Paste-Icon auf Ghost-Zellen
- **Undo/Redo**: `_undoStack`/`_redoStack` in `GridOverrideService`
- **Toolbar**: Undo, Redo, WordList (wenn AutoContent-Slots vorhanden), Speichern, Schließen
- **ExcludeSemantics**: verhindert Windows-AXTree-Fehler (gesetzt am Stack)

---

## Cell-Editor Sheet (brief_grid_editor_overlay.dart → _CellEditorSheet)

Öffnet sich bei Doppeltippen auf eine Zelle im GridLayoutEditor:

- **Caption**: Textfeld
- **Symbol**: Symbol-Suche mit Vorschau
- **Befehle**: ReorderableList von `_CmdEntry`-Objekten
  - DropdownButton für `GridCommandType` (alle in `_kCommandLabels` eingetragen)
  - Safety-Guard: `_kCommandLabels.containsKey(entry.type) ? entry.type : null`
  - Jump-Target-Feld (Textfeld, erscheint bei jumpTo)
  - InsertText: `_SegmentChipEditor` (Text-Chips + Symbol-Chips)
- **Farben**: `_ColorSwatchPicker` (24 Farben, Hintergrund + Text)
- **Form**: `_ShapeSelector` (Original/Abgerundet/Oval/Pille)
- **Named Style**: `_NamedStylePicker` (28 Styles als horizontale Chip-Leiste)
- **Schriftgröße**: Slider 8–40pt

---

## DateiScreen (datei_screen.dart) – Grid3-basiert seit 2026-04-02

Lädt `"Datei"`-Grid (11×8, #171947) + Sub-Pages on demand:

| Sub-Page | Beschreibung |
|---|---|
| `Korrektur` | Cursor-Navigation: Vor/Zurück Buchstabe/Wort/Satz/Zeile + Textanfang/-ende |
| `Telegram-Startseite` | Telegram-Integration (Copy+Navigate+Paste) |
| `Threema-Startseite` | Threema-Integration |
| `Whatsapp-Startseite` | WhatsApp-Integration |

**Zell-Typen im Datei-Grid:**
- `liveCell` → scrollbare Dokumenten-Liste (links, Spalten 0-1, Zeilen 1-6)
- `workspace` → `NasiraTextWorkspace` (rechts, Spalten 2-10, Zeilen 1-6)

**Implementierte Befehle:**
```
textEditorNew      → speichert aktuellen Text, leert Controller (kein Jump.Back!)
textEditorDelete   → löscht aktuelles Dokument aus DocumentService
textEditorPrevious → vorheriges Dokument laden (_docIndex--)
textEditorNext     → nächstes Dokument laden (_docIndex++)
copyText           → Clipboard.setData
settingsExit       → Navigator.pop
jumpBack           → _goBack() (→ Navigator.pop wenn History leer)
documentEnd        → Cursor ans Ende
documentStart      → Cursor an Anfang
previousLetter/nextLetter/previousWord/nextWord/
previousSentence/nextSentence/previousLine/nextLine → Cursor-Navigation
deleteLetter       → state.deleteLastLetter()
deleteWord         → state.deleteLastWord()
```

---

## Tagebuch-Screen (tagebuch_screen.dart) – Besonderheiten

- **Jump.To "Datei"**: wird interceptet → `Navigator.push(DateiScreen)` statt interner Navigation
- Alle anderen Jump.To → `_navigateTo(pageName)` (interner Page-Stack)

---

## Startseite-Screen (startseite_screen.dart) – Kacheln

```
Tagebuch       → TagebuchScreen
Brief          → BriefScreen
Einkaufen      → EinkaufenScreen
Freies Schreiben → FreiesSchreibenScreen
Meine Grids    → UserGridsScreen
Datei          → DateiScreen (speichert Text davor per DocumentService)
Einstellungen  → SetupScreen
```

---

## GridOverrideService – Datenstruktur (nasira_grid_overrides.json)

```json
{
  "<gridName>": {
    "cells": {
      "<x>,<y>": {
        "caption": "...",
        "symbolStem": "...",
        "shape": "oval",
        "backgroundColor": "FF5D8057",
        "fontColor": "FFFFFFFF",
        "fontSize": 14.0,
        "commands": [
          { "type": "jumpTo", "jumpTarget": "Mein Grid",
            "segments": [{"type":"text","value":"Hallo"},{"type":"symbol","stem":"hallo2"}] }
        ]
      }
    },
    "layout": { "<x>,<y>": { "x":0,"y":0,"colSpan":2,"rowSpan":1 } },
    "gridSize": { "columns": 7, "rows": 6 }
  },
  "_userGridMeta": {
    "<gridName>": { "columns": 5, "rows": 4 }
  }
}
```

---

## Grid3 XML Referenz

- **BackgroundShape**: 1=RoundedRect, 2=Oval, 5=Pill
- **ContentType**: (leer)=normal, `AutoContent`, `Workspace`, `LiveCell`
- **Styles**: 54 named styles in `Settings0/Styles/styles.xml`
  (BackColour, FontColour, BorderColour, FontName, FontSize, BackgroundShape)
- **Zellen**: X, Y, ColumnSpan, RowSpan, ScanBlock, Visibility=Hidden
- **Mehrere Befehle** pro Zelle möglich (Command-Chain, werden sequenziell ausgeführt)

---

## Bekannte technische Entscheidungen

| Problem | Lösung |
|---|---|
| Windows AXTree-Fehler (70+ pro Navigation) | `ExcludeSemantics` um gesamte `MaterialApp` auf Windows |
| Resize-Handles unsichtbar | `Stack(clipBehavior: Clip.none)` im GridLayoutEditor |
| DropdownButton crash bei unbekannten CommandTypes | Safety-Guard: `containsKey` vor Wert-Zuweisung |
| Virtuelle Zellen (Override ohne XML-Zelle) | Orphan-Overrides werden als neue GridCell eingefügt |
| Cursor immer am Ende | Alle State-Operationen lesen `textController.selection.baseOffset` |
| Neues Dokument schließt DateiScreen | `return` nach `textEditorNew` in `_run()` – kein Jump.Back |
| Hallo/Liebe/Lieber zeigen grüne Platzhalter | `_effectiveWordList()` in BriefScreen für autoMap |
