import 'dart:io';
import 'package:flutter/material.dart';
import 'package:xml/xml.dart';
import '../models/grid_page.dart';

/// Liest Grid3-Export-Ordner und parst alle grid.xml Dateien
/// in [GridPage]-Objekte.
///
/// Pfad: C:\Users\<User>\Documents\Nasira EXPORT\Grids\
class GridImportService {
  /// Standardpfad zum Grid3-Export-Ordner.
  static const String defaultExportPath =
      r'C:\Users\denlu\Documents\Nasira EXPORT\Grids';

  final String exportPath;

  GridImportService({this.exportPath = defaultExportPath});

  // ── Öffentliche API ────────────────────────────────────────────────────────

  /// Liest alle grid.xml Dateien im Export-Ordner und gibt ein
  /// Map<gridName, GridPage> zurück.
  Future<Map<String, GridPage>> importAll() async {
    final dir = Directory(exportPath);
    if (!dir.existsSync()) {
      debugPrint('[GridImport] Ordner nicht gefunden: $exportPath');
      return {};
    }

    final result = <String, GridPage>{};
    final entries = dir.listSync().whereType<Directory>().toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    for (final entry in entries) {
      final name = entry.uri.pathSegments
          .where((s) => s.isNotEmpty)
          .last;
      final page = await importPage(name);
      if (page != null) result[name] = page;
    }

    debugPrint('[GridImport] ${result.length} Seiten geladen.');
    return result;
  }

  /// Importiert eine einzelne Seite nach Name.
  Future<GridPage?> importPage(String gridName) async {
    final file = File('$exportPath\\$gridName\\grid.xml');
    if (!file.existsSync()) return null;

    try {
      final xml = await file.readAsString();
      return _parseGrid(gridName, xml);
    } catch (e) {
      debugPrint('[GridImport] Fehler bei "$gridName": $e');
      return null;
    }
  }

  /// Synchrone Version für einen einzelnen Grid-Namen.
  GridPage? importPageSync(String gridName) {
    final file = File('$exportPath\\$gridName\\grid.xml');
    if (!file.existsSync()) return null;

    try {
      final xml = file.readAsStringSync();
      return _parseGrid(gridName, xml);
    } catch (e) {
      debugPrint('[GridImport] Fehler bei "$gridName": $e');
      return null;
    }
  }

  // ── Parser ─────────────────────────────────────────────────────────────────

  GridPage _parseGrid(String name, String xmlContent) {
    final doc = XmlDocument.parse(xmlContent);
    final root = doc.rootElement;

    // Layout
    final cols = root.findElements('ColumnDefinitions').firstOrNull
            ?.findElements('ColumnDefinition')
            .length ??
        7;
    final rows = root.findElements('RowDefinitions').firstOrNull
            ?.findElements('RowDefinition')
            .length ??
        6;

    // Hintergrundfarbe
    final bgHex =
        root.findElements('BackgroundColour').firstOrNull?.innerText ?? '';
    final bg = _parseColor(bgHex);

    // Zellen
    final cells = <GridCell>[];
    final cellsEl = root.findElements('Cells').firstOrNull;
    if (cellsEl != null) {
      for (final cellEl in cellsEl.findElements('Cell')) {
        final cell = _parseCell(cellEl, name);
        if (cell != null) cells.add(cell);
      }
    }

    // WordList
    final wordList = <GridWordListItem>[];
    final wlEl = root.findElements('WordList').firstOrNull;
    if (wlEl != null) {
      int wlIndex = 0;
      for (final itemEl in wlEl.findAllElements('WordListItem')) {
        final item = _parseWordListItem(itemEl, name, wlIndex);
        if (item != null) {
          wordList.add(item);
          wlIndex++;
        }
      }
    }

    return GridPage(
      name: name,
      columns: cols,
      rows: rows,
      backgroundColor: bg,
      cells: cells,
      wordList: wordList,
    );
  }

  GridCell? _parseCell(XmlElement cellEl, String gridName) {
    final x = int.tryParse(cellEl.getAttribute('X') ?? '0') ?? 0;
    final y = int.tryParse(cellEl.getAttribute('Y') ?? '0') ?? 0;
    final colSpan =
        int.tryParse(cellEl.getAttribute('ColumnSpan') ?? '1') ?? 1;
    final rowSpan =
        int.tryParse(cellEl.getAttribute('RowSpan') ?? '1') ?? 1;

    final content = cellEl.findElements('Content').firstOrNull;
    if (content == null) return null;

    // Typ
    final contentType =
        content.findElements('ContentType').firstOrNull?.innerText;
    final type = switch (contentType) {
      'AutoContent' => GridCellType.autoContent,
      'Workspace'   => GridCellType.workspace,
      'LiveCell'    => GridCellType.liveCell,
      _             => GridCellType.normal,
    };

    // Caption + Image
    final cap = content.findElements('CaptionAndImage').firstOrNull;
    final caption = cap?.findElements('Caption').firstOrNull?.innerText;
    final imageRaw = cap?.findElements('Image').firstOrNull?.innerText;
    var (metacmPath, symbolStem, symbolCategory) = _resolveMetacm(imageRaw);

    // Custom-PNG: Bild-Wert beginnt nicht mit [metacm]/[GRID3X] und endet mit .png
    // → Dateiname = "{X}-{Y}{imageRaw}" (z.B. ".png" → "1-2.png",
    //   "-0-text-0.png" → "0-2-0-text-0.png").
    String? localImagePath;
    if (imageRaw != null &&
        imageRaw.endsWith('.png') &&
        !imageRaw.startsWith('[')) {
      final candidate = File('$exportPath\\$gridName\\$x-$y$imageRaw');
      if (candidate.existsSync()) localImagePath = candidate.path;
    }

    // Fallback: InsertText <Parameter Key="text"> → <p><s Image="[metacm]...">
    // Phrase-Starter-Zellen haben ihr Symbol nicht in CaptionAndImage/Image,
    // sondern als Attribut am ersten <s>-Element im RTF-Text.
    if (metacmPath == null) {
      outer: for (final cmdEl in content.findAllElements('Command')) {
        if (cmdEl.getAttribute('ID') != 'Action.InsertText') continue;
        for (final pEl in cmdEl.findAllElements('p')) {
          for (final sEl in pEl.findElements('s')) {
            final img = sEl.getAttribute('Image');
            if (img != null) {
              final r = _resolveMetacm(img);
              if (r.$1 != null) {
                metacmPath     = r.$1;
                symbolStem     = r.$2;
                symbolCategory = r.$3;
                break outer;
              }
            }
          }
        }
      }
    }

    // Stil
    final styleEl = content.findElements('Style').firstOrNull;
    final basedOn =
        styleEl?.findElements('BasedOnStyle').firstOrNull?.innerText;
    final style = _parseStyle(basedOn);

    // Befehle
    final commands = <GridCellCommand>[];
    for (final cmdEl in content.findAllElements('Command')) {
      final cmd = _parseCommand(cmdEl);
      if (cmd != null) commands.add(cmd);
    }

    // Leere Zellen überspringen (kein caption, kein command, kein AutoContent)
    if (type == GridCellType.normal &&
        commands.isEmpty &&
        caption == null &&
        metacmPath == null &&
        localImagePath == null) {
      return null;
    }

    return GridCell(
      x: x,
      y: y,
      colSpan: colSpan,
      rowSpan: rowSpan,
      caption: caption,
      metacmPath: metacmPath,
      symbolStem: symbolStem,
      symbolCategory: symbolCategory,
      localImagePath: localImagePath,
      iconData: _resolveGrid3xIcon(imageRaw),
      style: style,
      type: type,
      commands: commands,
    );
  }

  GridWordListItem? _parseWordListItem(
      XmlElement itemEl, String gridName, int index) {
    // Text aus allen <r>-Tags zusammensetzen
    final textEl = itemEl.findElements('Text').firstOrNull;
    final rParts = textEl?.findAllElements('r').map((e) => e.innerText) ?? [];
    final text = rParts.join().trim();
    if (text.isEmpty) return null;

    final imageRaw = itemEl.findElements('Image').firstOrNull?.innerText;
    final (metacmPath, symbolStem, symbolCategory) = _resolveMetacm(imageRaw);

    // Custom-PNG aus Grid3-Export prüfen — zwei Namensmuster:
    // Einfach:  wordlist-{index}-0.png
    // Komplex:  {row}-{col}-{variant}-wordlist-wordlist-{index}-0.png
    final localImagePath = _findWordlistImage(gridName, index);

    return GridWordListItem(
      text: text,
      metacmPath: metacmPath,
      symbolStem: symbolStem,
      symbolCategory: symbolCategory,
      localImagePath: localImagePath,
    );
  }

  GridCellCommand? _parseCommand(XmlElement cmdEl) {
    final id = cmdEl.getAttribute('ID');
    return switch (id) {
      'Action.InsertText' => GridCellCommand(
          type: GridCommandType.insertText,
          insertText: _extractInsertText(cmdEl),
        ),
      'Jump.To' => GridCellCommand(
          type: GridCommandType.jumpTo,
          jumpTarget: _param(cmdEl, 'grid'),
        ),
      'Jump.Back' => const GridCellCommand(type: GridCommandType.jumpBack),
      'Jump.Home' => const GridCellCommand(type: GridCommandType.jumpHome),
      'Action.Punctuation' => GridCellCommand(
          type: GridCommandType.punctuation,
          punctuation: _param(cmdEl, 'letter'),
        ),
      'Action.Letter' => GridCellCommand(
          type: GridCommandType.insertText,
          insertText: _param(cmdEl, 'letter') ?? '',
        ),
      'Action.Space' => const GridCellCommand(
          type: GridCommandType.insertText,
          insertText: ' ',
        ),
      'Action.DeleteWord' =>
        const GridCellCommand(type: GridCommandType.deleteWord),
      'Action.DeleteLetter' =>
        const GridCellCommand(type: GridCommandType.deleteLetter),
      'Action.DocumentEnd' =>
        const GridCellCommand(type: GridCommandType.documentEnd),
      'Action.Enter' => const GridCellCommand(type: GridCommandType.enter),
      'Action.Speak' => const GridCellCommand(type: GridCommandType.speak),
      'Action.Clear' => const GridCellCommand(type: GridCommandType.deleteWord),
      'Prediction.MoreWords' =>
        const GridCellCommand(type: GridCommandType.moreWords),
      'Prediction.MorePredictions' =>
        const GridCellCommand(type: GridCommandType.moreWords),
      'ComputerControl.CapsLock' =>
        const GridCellCommand(type: GridCommandType.capsLock),
      'ComputerControl.Shift' =>
        const GridCellCommand(type: GridCommandType.shift),
      'Jump.SetBookmark' =>
        const GridCellCommand(type: GridCommandType.setBookmark),
      'Action.Copy' =>
        const GridCellCommand(type: GridCommandType.copyText),
      'Action.Paste' =>
        const GridCellCommand(type: GridCommandType.pasteText),
      'Action.Print' =>
        const GridCellCommand(type: GridCommandType.printText),
      'Settings.Exit' =>
        const GridCellCommand(type: GridCommandType.settingsExit),
      'TextEditor.New' =>
        const GridCellCommand(type: GridCommandType.textEditorNew),
      'TextEditor.Delete' =>
        const GridCellCommand(type: GridCommandType.textEditorDelete),
      'TextEditor.Previous' =>
        const GridCellCommand(type: GridCommandType.textEditorPrevious),
      'TextEditor.Next' =>
        const GridCellCommand(type: GridCommandType.textEditorNext),
      _ => null,
    };
  }

  // ── Hilfsfunktionen ────────────────────────────────────────────────────────

  /// Sucht die Custom-PNG für WordList-Item [index] im Grid-Ordner [gridName].
  ///
  /// Zwei Namensmuster aus Grid3-Export:
  /// - Einfach:  `wordlist-{index}-0.png`
  /// - Komplex:  `{row}-{col}-{v}-wordlist-wordlist-{index}-0.png`
  String? _findWordlistImage(String gridName, int index) {
    final simple = File('$exportPath\\$gridName\\wordlist-$index-0.png');
    if (simple.existsSync()) return simple.path;

    // Komplexes Muster: Dateiname endet auf wordlist-wordlist-{index}-0.png
    final suffix = 'wordlist-wordlist-$index-0.png';
    final dir = Directory('$exportPath\\$gridName');
    if (dir.existsSync()) {
      for (final entry in dir.listSync().whereType<File>()) {
        if (entry.path.endsWith(suffix)) return entry.path;
      }
    }
    return null;
  }

  /// Extrahiert den Wert des <Parameter Key="key"> innerhalb eines <Command>.
  String? _param(XmlElement cmdEl, String key) {
    for (final p in cmdEl.findElements('Parameter')) {
      if (p.getAttribute('Key') == key) return p.innerText.trim();
    }
    return null;
  }

  /// Concateniert alle <r>-Elemente im text-Parameter eines InsertText-Befehls.
  String _extractInsertText(XmlElement cmdEl) {
    for (final p in cmdEl.findElements('Parameter')) {
      if (p.getAttribute('Key') == 'text') {
        return p.findAllElements('r').map((e) => e.innerText).join().trim();
      }
    }
    return '';
  }

  /// Zerlegt einen [metacm]-Pfad in (normierter Pfad, Stem, Kategorie).
  ///
  /// Eingabe: "[metacm]eigenschaften_emotionen\froehlichfb.emf"
  /// Ausgabe: ("eigenschaften_emotionen/froehlichfb", "froehlichfb", "eigenschaften_emotionen")
  (String?, String?, String?) _resolveMetacm(String? raw) {
    if (raw == null || raw.isEmpty) return (null, null, null);
    if (!raw.contains('[metacm]')) return (null, null, null);

    final path = raw
        .replaceFirst('[metacm]', '')
        .replaceAll('\\', '/')
        .toLowerCase();

    final parts = path.split('/');
    if (parts.length < 2) return (path, null, null);

    final category = parts[0];
    final stem = parts[1].replaceAll(RegExp(r'\.[^.]+$'), '');
    final normalized = '$category/$stem';

    return (normalized, stem, category);
  }

  GridCellStyle _parseStyle(String? basedOn) =>
      switch (basedOn?.trim()) {
        'Action cell 1' || 'Action cell 2' => GridCellStyle.actionNav,
        'Aktionsfeld 2'                     => GridCellStyle.satzanfang,
        'Aktionsfeld 3'                     => GridCellStyle.frage,
        'Aktionsfeld 4'                     => GridCellStyle.neutral,
        'Auto content cell 2' ||
        'Auto content cell 3'               => GridCellStyle.wortliste,
        'style 4'                           => GridCellStyle.hauptthema,
        'style 17'                          => GridCellStyle.weitereWoerter,
        'style 18'                          => GridCellStyle.invertiert,
        'style 25'                          => GridCellStyle.textfeld,
        'style 31'                          => GridCellStyle.freiesSchreiben,
        'style 52'                          => GridCellStyle.satzanfangVergangenheit,
        'style 53'                          => GridCellStyle.frageVergangenheit,
        'style 49'                          => GridCellStyle.unterthema,
        'style 29'                          => GridCellStyle.dateiTextfeld,
        _                                   => GridCellStyle.unknown,
      };

  /// Mappt [GRID3X]-Systemsymbole auf Flutter-Icons.
  static IconData? _resolveGrid3xIcon(String? raw) {
    if (raw == null || !raw.startsWith('[GRID3X]')) return null;
    final name = raw.substring(8).toLowerCase(); // strip "[GRID3X]"
    return switch (name) {
      'autocells_next.wmf'     => Icons.more_horiz,
      'autocells_previous.wmf' => Icons.more_horiz,
      'jump_back.wmf'          => Icons.arrow_back_ios_new,
      'jump_forwards.wmf'      => Icons.arrow_forward_ios,
      'jump_home.wmf'          => Icons.home_outlined,
      'delete_word.wmf'        => Icons.backspace_outlined,
      'delete_letter.wmf'      => Icons.backspace_outlined,
      'clear.wmf'              => Icons.delete_sweep_outlined,
      'enter.wmf'              => Icons.keyboard_return,
      'space.wmf'              => Icons.space_bar,
      'speak_all.wmf'          => Icons.volume_up_outlined,
      'speak_stop.wmf'         => Icons.volume_off_outlined,
      'print.wmf'              => Icons.print_outlined,
      'shift.wmf'              => Icons.keyboard_capslock_outlined,
      'capslock.wmf'           => Icons.keyboard_capslock,
      'paste.wmf'              => Icons.content_paste,
      'word_next.wmf'          => Icons.skip_next_outlined,
      'word_previous.wmf'      => Icons.skip_previous_outlined,
      _                        => Icons.touch_app_outlined,
    };
  }

  /// Parst Grid3-Farbformat #RRGGBBAA → Flutter Color.
  static Color _parseColor(String hex) {
    if (hex.isEmpty) return const Color(0xFFF9FAFA);
    final clean = hex.replaceFirst('#', '');
    if (clean.length == 8) {
      // RRGGBBAA
      final r = int.parse(clean.substring(0, 2), radix: 16);
      final g = int.parse(clean.substring(2, 4), radix: 16);
      final b = int.parse(clean.substring(4, 6), radix: 16);
      final a = int.parse(clean.substring(6, 8), radix: 16);
      return Color.fromARGB(a, r, g, b);
    } else if (clean.length == 6) {
      return Color(int.parse('FF$clean', radix: 16));
    }
    return Colors.white;
  }
}

// ── Ergebnis-Statistik (für Debugging) ────────────────────────────────────────

class GridImportStats {
  final int totalPages;
  final int totalCells;
  final int totalWordListItems;
  final int symbolsResolved;  // Zellen mit metacmPath
  final List<String> pageNames;

  const GridImportStats({
    required this.totalPages,
    required this.totalCells,
    required this.totalWordListItems,
    required this.symbolsResolved,
    required this.pageNames,
  });

  factory GridImportStats.from(Map<String, GridPage> pages) {
    int cells = 0, wl = 0, sym = 0;
    for (final p in pages.values) {
      cells += p.cells.length;
      wl += p.wordList.length;
      sym += p.cells.where((c) => c.metacmPath != null).length;
      sym += p.wordList.where((i) => i.metacmPath != null).length;
    }
    return GridImportStats(
      totalPages: pages.length,
      totalCells: cells,
      totalWordListItems: wl,
      symbolsResolved: sym,
      pageNames: pages.keys.toList()..sort(),
    );
  }

  @override
  String toString() => 'GridImportStats: $totalPages Seiten, '
      '$totalCells Zellen, $totalWordListItems WL-Einträge, '
      '$symbolsResolved Symbole mit Pfad';
}
