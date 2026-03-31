import 'package:flutter/material.dart';
import '../theme/nasira_colors.dart';

// ── Zelltypen ─────────────────────────────────────────────────────────────────

enum GridCellType {
  normal,      // reguläre Kachel mit Befehl
  autoContent, // dynamischer Slot für WordList-Einträge
  workspace,   // Texteditor-Bereich
  empty,       // leere/unsichtbare Zelle
}

// ── Stilzuordnung (1:1 aus styles.xml) ───────────────────────────────────────

enum GridCellStyle {
  actionNav,               // "Action cell 2"  – Navigation (grün #5D8057)
  satzanfang,              // "Aktionsfeld 2"  – Satzstarter Gegenwart (rot #C4302B)
  frage,                   // "Aktionsfeld 3"  – Frage/Dunkelgrün #3B5936
  neutral,                 // "Aktionsfeld 4"  – und/nicht (beige #BFBBAC)
  wortliste,               // "Auto content cell 3" – weiß + grüner Rand
  hauptthema,              // "style 4"  – Hauptthema (hellgrün #91B38A)
  weitereWoerter,          // "style 17" – Mehr-Vorschläge (#E6F2E3)
  invertiert,              // "style 18" – weiß + grüner Rand
  textfeld,                // "style 25" – Workspace (weiß + grüner Rand)
  freiesSchreiben,         // "style 31" – FS-Navigation (blau #5E80C4)
  satzanfangVergangenheit, // "style 52" – Vergangenheit Satzstarter (hellrot #C97F7E)
  frageVergangenheit,      // "style 53" – Vergangenheit Frage (hellgrün #ACC2A8)
  unterthema,              // "style 49" – Brief Unterthema (hellgrün oval #BFDBB8)
  dateiTextfeld,           // "style 29" – Datei-Textfeld (weiß + grauer Rand)
  unknown,
}

extension GridCellStyleColors on GridCellStyle {
  Color get backgroundColor => switch (this) {
        GridCellStyle.actionNav             => NasiraColors.navGreen,
        GridCellStyle.satzanfang            => NasiraColors.briefSentence,
        GridCellStyle.frage                 => NasiraColors.briefQuestion,
        GridCellStyle.neutral               => NasiraColors.briefNeutral,
        GridCellStyle.wortliste             => Colors.white,
        GridCellStyle.hauptthema            => NasiraColors.briefTopic,
        GridCellStyle.weitereWoerter        => const Color(0xFFE6F2E3),
        GridCellStyle.invertiert            => Colors.white,
        GridCellStyle.textfeld              => Colors.white,
        GridCellStyle.freiesSchreiben       => const Color(0xFF5E80C4),
        GridCellStyle.satzanfangVergangenheit => const Color(0xFFC97F7E),
        GridCellStyle.frageVergangenheit    => const Color(0xFFACC2A8),
        GridCellStyle.unterthema            => const Color(0xFFBFDBB8),
        GridCellStyle.dateiTextfeld         => Colors.white,
        GridCellStyle.unknown               => NasiraColors.briefTopic,
      };

  Color get foregroundColor => switch (this) {
        GridCellStyle.neutral        => NasiraColors.textDark,
        GridCellStyle.wortliste      => NasiraColors.textDark,
        GridCellStyle.invertiert     => NasiraColors.navGreen,
        GridCellStyle.weitereWoerter => NasiraColors.navGreen,
        GridCellStyle.dateiTextfeld  => NasiraColors.textDark,
        _                            => Colors.white,
      };

  /// Ob die Zelle einen farbigen Rahmen braucht (grün #4B6E50)
  bool get hasBorder => switch (this) {
        GridCellStyle.wortliste     => true,
        GridCellStyle.invertiert    => true,
        GridCellStyle.textfeld      => true,
        GridCellStyle.dateiTextfeld => true,
        _                           => false,
      };

  /// Ob die Zelle als Ellipse (oval) dargestellt werden soll.
  /// style 4 = Hauptthema-Navigation, style 49 = Unterthema-Navigation.
  bool get isOval =>
      this == GridCellStyle.hauptthema || this == GridCellStyle.unterthema;
}

// ── Befehle ───────────────────────────────────────────────────────────────────

enum GridCommandType {
  insertText,
  jumpTo,
  jumpBack,
  jumpHome,
  punctuation,
  deleteWord,
  documentEnd,
  enter,
  moreWords,
  setBookmark,
  other,
}

class GridCellCommand {
  final GridCommandType type;
  final String? insertText;  // für insertText
  final String? jumpTarget;  // für jumpTo (Grid-Name)
  final String? punctuation; // für punctuation (".", "?", "!")

  const GridCellCommand({
    required this.type,
    this.insertText,
    this.jumpTarget,
    this.punctuation,
  });

  @override
  String toString() => switch (type) {
        GridCommandType.insertText  => 'insert("$insertText")',
        GridCommandType.jumpTo      => 'jumpTo("$jumpTarget")',
        GridCommandType.punctuation => 'punct("$punctuation")',
        _                           => type.name,
      };
}

// ── Zelle ─────────────────────────────────────────────────────────────────────

class GridCell {
  final int x;
  final int y;
  final int colSpan;
  final int rowSpan;
  final String? caption;
  final String? metacmPath;     // z.B. "eigenschaften_emotionen/froehlichfb"
  final String? symbolStem;     // Dateiname ohne Endung für DB-Lookup
  final String? symbolCategory; // lowercase Kategoriename aus [metacm]
  /// Absoluter Pfad zur Custom-PNG aus dem Grid3-Export (z.B. 1-2.png).
  /// Null wenn kein Custom-Bild vorhanden.
  final String? localImagePath;
  /// Flutter-Icon für [GRID3X]-Systemsymbole (z.B. MoreWords, Back, Home).
  final IconData? iconData;
  final GridCellStyle style;
  final GridCellType type;
  final List<GridCellCommand> commands;

  const GridCell({
    required this.x,
    required this.y,
    this.colSpan = 1,
    this.rowSpan = 1,
    this.caption,
    this.metacmPath,
    this.symbolStem,
    this.symbolCategory,
    this.localImagePath,
    this.iconData,
    required this.style,
    required this.type,
    required this.commands,
  });

  Color get backgroundColor => style.backgroundColor;
  Color get foregroundColor => style.foregroundColor;
  bool get hasBorder => style.hasBorder;

  /// Text der eingefügt wird (Action.InsertText)
  String? get insertText => commands
      .where((c) => c.type == GridCommandType.insertText)
      .map((c) => c.insertText)
      .firstOrNull;

  /// Satzzeichen (Action.Punctuation)
  String? get punctuationChar => commands
      .where((c) => c.type == GridCommandType.punctuation)
      .map((c) => c.punctuation)
      .firstOrNull;

  /// Navigationsziel (Jump.To)
  String? get jumpTarget => commands
      .where((c) => c.type == GridCommandType.jumpTo)
      .map((c) => c.jumpTarget)
      .firstOrNull;

  bool get isInsertCell    => insertText != null;
  bool get isPunctuation   => punctuationChar != null;
  bool get isNavigation    => jumpTarget != null;
  bool get isBack          => commands.any((c) => c.type == GridCommandType.jumpBack);
  bool get isHome          => commands.any((c) => c.type == GridCommandType.jumpHome);
  bool get isDeleteWord    => commands.any((c) => c.type == GridCommandType.deleteWord);
  bool get isMoreWords     => commands.any((c) => c.type == GridCommandType.moreWords);

  @override
  String toString() =>
      'GridCell($x,$y caption:"$caption" type:${type.name} style:${style.name} cmds:$commands)';
}

// ── WordList-Eintrag ──────────────────────────────────────────────────────────

class GridWordListItem {
  final String text;
  final String? metacmPath;
  final String? symbolStem;
  final String? symbolCategory;
  /// Absoluter Pfad zur Custom-PNG aus dem Grid3-Export (z.B. wordlist-0-0.png).
  /// Null wenn kein Custom-Bild vorhanden.
  final String? localImagePath;

  const GridWordListItem({
    required this.text,
    this.metacmPath,
    this.symbolStem,
    this.symbolCategory,
    this.localImagePath,
  });

  @override
  String toString() =>
      'WordListItem("$text" sym:$symbolCategory/$symbolStem localImg:${localImagePath != null})';
}

// ── Grid-Seite ────────────────────────────────────────────────────────────────

class GridPage {
  final String name;
  final int columns;
  final int rows;
  final Color backgroundColor;
  final List<GridCell> cells;
  final List<GridWordListItem> wordList;

  const GridPage({
    required this.name,
    required this.columns,
    required this.rows,
    required this.backgroundColor,
    required this.cells,
    required this.wordList,
  });

  /// Zelle an Position (x, y), oder null wenn nicht definiert.
  GridCell? cellAt(int x, int y) =>
      cells.where((c) => c.x == x && c.y == y).firstOrNull;

  /// Alle Satzstarter-Zellen (rote/grüne Aktionsfelder mit insertText).
  List<GridCell> get phraseButtons => cells
      .where((c) =>
          c.type == GridCellType.normal &&
          c.isInsertCell &&
          (c.style == GridCellStyle.satzanfang ||
           c.style == GridCellStyle.frage ||
           c.style == GridCellStyle.satzanfangVergangenheit ||
           c.style == GridCellStyle.frageVergangenheit))
      .toList()
    ..sort((a, b) => a.y != b.y ? a.y.compareTo(b.y) : a.x.compareTo(b.x));

  /// Satzzeichen-Zellen (rechte Spalte).
  List<GridCell> get punctuationCells =>
      cells.where((c) => c.isPunctuation).toList()
        ..sort((a, b) => a.y.compareTo(b.y));

  /// Neutral-Zellen (und / nicht).
  List<GridCell> get neutralCells => cells
      .where((c) =>
          c.style == GridCellStyle.neutral && c.isInsertCell)
      .toList();

  /// Navigations-Kacheln zu anderen Seiten.
  List<GridCell> get navigationCells =>
      cells.where((c) => c.isNavigation).toList();

  @override
  String toString() =>
      'GridPage("$name" ${columns}x$rows cells:${cells.length} wl:${wordList.length})';
}
