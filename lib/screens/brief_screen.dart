import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../nasira_app_state.dart';
import '../models/grid_page.dart';
import '../services/grid_import_service.dart';
import '../services/grid_override_service.dart';
import '../theme/nasira_colors.dart';
import '../widgets/grid_layout_editor.dart';
import '../widgets/nasira_grid_cell.dart';
import '../widgets/nasira_text_workspace.dart';
import '../widgets/nasira_title_bar.dart';
import 'freies_schreiben_screen.dart';

// ── Hilfsfunktion: Hauptwort für Symbol-Lookup ────────────────────────────────

String _keyWord(String sentence) {
  const skip = {
    'ich', 'du', 'er', 'sie', 'es', 'wir', 'ihr',
    'mir', 'mich', 'dir', 'dich', 'ihn', 'uns', 'euch',
    'habe', 'haben', 'hat', 'hatte', 'bin', 'ist', 'war', 'sind', 'waren',
    'ein', 'eine', 'einen', 'einem', 'einer',
    'der', 'die', 'das', 'den', 'dem', 'des',
    'für', 'mit', 'von', 'zu', 'zum', 'zur', 'in', 'im', 'am', 'an', 'auf', 'bei',
    'und', 'oder', 'aber', 'nicht', 'auch', 'sehr', 'viel',
    'mein', 'meine', 'meinen', 'meinem', 'dein', 'deinen', 'deiner',
    'schon', 'noch', 'mal', 'immer', 'bald', 'wieder',
  };

  final words = sentence
      .replaceAll(RegExp(r'[.!?,;]'), '')
      .split(' ')
      .where((w) => w.isNotEmpty)
      .toList();

  if (words.isEmpty) return sentence;

  final nouns = words.length > 1
      ? words
          .skip(1)
          .where((w) =>
              w.length >= 3 &&
              w[0] == w[0].toUpperCase() &&
              !skip.contains(w.toLowerCase()))
          .toList()
      : <String>[];

  if (nouns.isNotEmpty) return nouns.last;

  final content = words
      .where((w) => w.length >= 3 && !skip.contains(w.toLowerCase()))
      .toList();
  return content.isEmpty ? words.last : content.last;
}

// ── Schritte ──────────────────────────────────────────────────────────────────

enum _BriefSchritt {
  begruessung,
  personen,
  einleitung,
  inhaltsuebersicht,
  // Haupt-Hubs
  verabreden,
  uberDichUndMich,
  wuenscheUndDanken,
  sonstiges,
  gefuehle,
  beschreibungen,
  // Verabreden Sub-Seiten
  verabredenWann,
  verabredenWas,
  verabredenWo,
  // Über dich und mich Sub-Seiten
  uberDich,
  uberMich,
  trinken,
  kleidung,
  hobby,
  essen,
  haustiere,
  // Wünsche und Danken Sub-Seiten
  wuenschen,
  bedanken,
  // Sonstiges Sub-Seiten
  wetter,
  schule,
  gesundheit,
  gesundheitDetail,   // Brief 4 Gesundheit (Körperteile/Krankheitsvokabular)
  // Abschluss
  ende,
  endeGruesse,
}

// ── Hauptscreen ───────────────────────────────────────────────────────────────

class BriefScreen extends StatefulWidget {
  const BriefScreen({super.key});

  @override
  State<BriefScreen> createState() => _BriefScreenState();
}

class _BriefScreenState extends State<BriefScreen> {
  _BriefSchritt _schritt = _BriefSchritt.begruessung;
  final List<_BriefSchritt> _history = [];
  final Map<_BriefSchritt, GridPage> _rawPages = {}; // Rohe Seiten (nie überschrieben)
  final Map<_BriefSchritt, GridPage> _pages = {};    // Override-angewendete Seiten
  /// Aktuelle WL-Seite für paginierte AutoContent-Slots (wird bei Navigation zurückgesetzt).
  int _wlPage = 0;
  /// Reverse-Lookup: Grid3-Name → _BriefSchritt (für Jump.To-Befehle).
  late final Map<String, _BriefSchritt> _gridNameToStep;
  /// Steuert den In-Place-Layout-Editor (transparentes Overlay).
  bool _editorOpen = false;
  /// Verwaltet benutzerdefinierte Wortlisten-Überschreibungen.
  final GridOverrideService _overrideService = GridOverrideService();

  // ── Grid-Namen aller Brief-Seiten ──────────────────────────────────────────

  static const _stepToGridName = <_BriefSchritt, String>{
    _BriefSchritt.begruessung:       'Brief 1 Begrüßung',
    _BriefSchritt.personen:          'Brief 1 Personen',
    _BriefSchritt.einleitung:        'Brief 2 Einleitung',
    _BriefSchritt.inhaltsuebersicht: 'Brief 3 Inhaltsübersicht',
    _BriefSchritt.verabreden:        'Brief 4 jemanden treffen',
    _BriefSchritt.verabredenWann:    'Brief 4 jemanden treffen wann',
    _BriefSchritt.verabredenWas:     'Brief 4 jemanden treffen was',
    _BriefSchritt.verabredenWo:      'Brief 4 jemanden treffen wo',
    _BriefSchritt.uberDichUndMich:   'Brief 3 Inhalt dich und mich',
    _BriefSchritt.uberDich:          'Brief 4 über dich',
    _BriefSchritt.uberMich:          'Brief 4 über mich',
    _BriefSchritt.trinken:           'Brief 4 Trinken',
    _BriefSchritt.kleidung:          'Brief 4 Kleidung',
    _BriefSchritt.hobby:             'Brief 4 Hobby',
    _BriefSchritt.essen:             'Brief 4 Essen',
    _BriefSchritt.haustiere:         'Brief 4 Haustiere',
    _BriefSchritt.wuenscheUndDanken: 'Brief 3 Inhalt Wünsche und Danken',
    _BriefSchritt.wuenschen:         'Brief 4 wünschen',
    _BriefSchritt.bedanken:          'Brief 4 Bedanken',
    _BriefSchritt.sonstiges:         'Brief 3 Inhalt Dies und Das',
    _BriefSchritt.wetter:            'Brief 4 Wetter',
    _BriefSchritt.schule:            'Brief 4 Schule',
    _BriefSchritt.gesundheit:        'Brief 4 Gesundheit Sätze',
    _BriefSchritt.gesundheitDetail:  'Brief 4 Gesundheit',
    _BriefSchritt.gefuehle:          'Brief 4 Gefühle',
    _BriefSchritt.beschreibungen:    'Brief 4 Beschreiben',
    _BriefSchritt.ende:              'Brief 5 Ende',
    _BriefSchritt.endeGruesse:       'Brief 6 Ende Grüße',
  };

  // ── Leitfragen ─────────────────────────────────────────────────────────────

  static const _leitfragen = <_BriefSchritt, String>{
    _BriefSchritt.begruessung:       'Wie möchtest du den Brief beginnen?',
    _BriefSchritt.personen:          'An wen schreibst du?',
    _BriefSchritt.einleitung:        'Was schreibst du zur Einleitung?',
    _BriefSchritt.inhaltsuebersicht: 'Über was möchtest du schreiben?',
    _BriefSchritt.verabreden:        'Verabreden',
    _BriefSchritt.verabredenWann:    'Wann kannst du?',
    _BriefSchritt.verabredenWas:     'Was wollt ihr machen?',
    _BriefSchritt.verabredenWo:      'Wo wollt ihr euch treffen?',
    _BriefSchritt.uberDichUndMich:   'Über dich und mich',
    _BriefSchritt.uberDich:          'Fragen über die andere Person',
    _BriefSchritt.uberMich:          'Über dich selbst',
    _BriefSchritt.trinken:           'Was trinkst du gerne?',
    _BriefSchritt.kleidung:          'Was trägst du gerne?',
    _BriefSchritt.hobby:             'Was machst du gerne in der Freizeit?',
    _BriefSchritt.essen:             'Was hast du gegessen?',
    _BriefSchritt.haustiere:         'Was hast du mit deinem Haustier gemacht?',
    _BriefSchritt.wuenscheUndDanken: 'Wünsche und Danken',
    _BriefSchritt.wuenschen:         'Was möchtest du wünschen?',
    _BriefSchritt.bedanken:          'Wofür möchtest du dich bedanken?',
    _BriefSchritt.sonstiges:         'Sonstiges',
    _BriefSchritt.wetter:            'Wie war das Wetter?',
    _BriefSchritt.schule:            'Wie war die Schule?',
    _BriefSchritt.gesundheit:        'Wie geht es dir gesundheitlich?',
    _BriefSchritt.gesundheitDetail:  'Was hast du / hattest du?',
    _BriefSchritt.gefuehle:          'Wie hast du dich gefühlt?',
    _BriefSchritt.beschreibungen:    'Wie war es?',
    _BriefSchritt.ende:              'Wie möchtest du den Brief beenden?',
    _BriefSchritt.endeGruesse:       'Mit welchem Gruß möchtest du schließen?',
  };

  // ── Initialisierung ────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _gridNameToStep = {
      for (final e in _stepToGridName.entries) e.value: e.key,
    };
    _loadPages();
    _overrideService.load().then((_) {
      if (mounted) setState(_applyOverrides);
    });
  }

  void _loadPages() {
    final svc = GridImportService();
    for (final entry in _stepToGridName.entries) {
      final page = svc.importPageSync(entry.value);
      if (page != null) {
        _rawPages[entry.key] = page;
        _pages[entry.key]    = page;
      }
    }
  }

  /// Wendet gespeicherte Überschreibungen (Wortliste + Zellen + Layout) auf alle Seiten an.
  /// Startet immer von _rawPages (nie von der bereits angewendeten Seite),
  /// damit Override-Schlüssel nach jedem App-Start korrekt gefunden werden.
  void _applyOverrides() {
    for (final entry in _stepToGridName.entries) {
      final existing = _rawPages[entry.key] ?? _pages[entry.key];
      if (existing == null) continue;

      final wl        = _overrideService.getWordList(entry.value);
      final cellOv    = _overrideService.getAllCellOverrides(entry.value);
      final layoutOv  = _overrideService.getLayoutOverrides(entry.value);
      final sizeOv    = _overrideService.getGridSize(entry.value);
      final hasCellOv   = cellOv  != null && cellOv.isNotEmpty;
      final hasLayoutOv = layoutOv != null && layoutOv.isNotEmpty;
      final hasSizeOv   = sizeOv  != null;

      if (wl == null && !hasCellOv && !hasLayoutOv && !hasSizeOv) continue;

      // Zell-Inhalte + Positionen zusammenführen
      final cells = existing.cells.map((c) {
        final origKey = '${c.x},${c.y}';
        final cOv = hasCellOv   ? cellOv[origKey]   : null;
        final lOv = hasLayoutOv ? layoutOv[origKey] : null;
        if (cOv == null && lOv == null) return c;
        return GridCell(
          x:        lOv?['x']        ?? c.x,
          y:        lOv?['y']        ?? c.y,
          colSpan:  lOv?['colSpan']  ?? c.colSpan,
          rowSpan:  lOv?['rowSpan']  ?? c.rowSpan,
          caption:        (cOv?['caption']    as String?) ?? c.caption,
          symbolStem:     (cOv?['symbolStem'] as String?) ?? c.symbolStem,
          symbolCategory: c.symbolCategory,
          metacmPath:     c.metacmPath,
          localImagePath: c.localImagePath,
          iconData:       c.iconData,
          style:          c.style, type: c.type,
          commands:               _parseCommandOverrides(cOv) ?? c.commands,
          shapeOverride:          cOv?['shape'] as String?,
          backgroundColorOverride: _hexToColor(cOv?['backgroundColor'] as String?),
          fontColorOverride:       _hexToColor(cOv?['fontColor']       as String?),
          fontSizeOverride:        (cOv?['fontSize'] as num?)?.toDouble(),
        );
      }).toList();

      _pages[entry.key] = GridPage(
        name: existing.name,
        columns: sizeOv?['columns'] ?? existing.columns,
        rows:    sizeOv?['rows']    ?? existing.rows,
        backgroundColor: existing.backgroundColor,
        cells: cells,
        wordList: wl ?? existing.wordList,
      );
    }
  }

  /// Wandelt rohe JSON-Befehlsliste aus einem Cell-Override in GridCellCommands um.
  /// Gibt null zurück wenn kein commands-Eintrag vorhanden (→ Original behalten).
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

  static Color? _hexToColor(String? hex) {
    if (hex == null || hex.length != 8) return null;
    final val = int.tryParse(hex, radix: 16);
    return val == null ? null : Color(val);
  }

  // ── Navigation ──────────────────────────────────────────────────────────────

  void _navigateTo(_BriefSchritt step) {
    setState(() {
      _history.add(_schritt);
      _schritt = step;
      _wlPage = 0;
    });
  }

  void _zurueck() {
    if (_history.isNotEmpty) {
      setState(() => _schritt = _history.removeLast());
    } else {
      Navigator.pop(context);
    }
  }

  Future<void> _confirmClearAll() async {
    Timer? timer;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        timer = Timer(const Duration(seconds: 3), () {
          if (ctx.mounted) Navigator.pop(ctx, false);
        });
        return AlertDialog(
          title: const Text('Alles löschen?'),
          content: const Text(
            'Soll der gesamte Text wirklich gelöscht werden?\n'
            '(Dialog schließt sich automatisch nach 3 Sekunden.)',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Nein'),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Ja, löschen'),
            ),
          ],
        );
      },
    );
    timer?.cancel();
    if ((confirmed ?? false) && mounted) {
      context.read<NasiraAppState>().clearText();
    }
  }

  // ── Symbol-Auflösung ──────────────────────────────────────────────────────

  /// Löst einen Grid3-Metacom-Stem direkt zu einem Flutter-Asset-Pfad auf.
  ///
  /// Bypass der NasiraData-Lookup-Pipeline — nutzt den AssetManifest-Basename-Index
  /// in [AssetResolverService]. Gibt null zurück, wenn der Index noch nicht geladen
  /// ist oder kein passender Asset gefunden wurde.
  String? _resolveSymbol(NasiraAppState state, String? stem) {
    if (stem == null) return null;
    if (!state.assetResolver.isReady) return null;
    return state.assetResolver.resolve('$stem.jpg');
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  /// Liefert die Edit-Aktion für den aktuellen Schritt (null wenn kein Grid geladen).
  VoidCallback? _currentOnEdit() {
    final gridName = _stepToGridName[_schritt];
    if (gridName == null || _pages[_schritt] == null) return null;
    return () => setState(() => _editorOpen = true);
  }

  @override
  Widget build(BuildContext context) {
    final state    = context.watch<NasiraAppState>();
    final gridName = _stepToGridName[_schritt];
    final page     = _pages[_schritt];

    // Für den Editor: AutoContent-Zellen → Wortlisten-Einträge vorberechnen.
    // (AutoContent-Zellen haben keine caption/symbolStem — Inhalt kommt aus wordList.)
    Map<String, GridWordListItem> autoMap = {};
    if (_editorOpen && page != null) {
      final autoSlots = page.cells
          .where((c) => c.type == GridCellType.autoContent)
          .toList()
        ..sort((a, b) => a.y != b.y ? a.y.compareTo(b.y) : a.x.compareTo(b.x));
      for (int i = 0; i < autoSlots.length && i < page.wordList.length; i++) {
        autoMap['${autoSlots[i].x},${autoSlots[i].y}'] = page.wordList[i];
      }
    }

    return Scaffold(
      backgroundColor: NasiraColors.briefBg,
      body: SafeArea(
        child: Column(
          children: [
            // ── Titelleiste mit Hamburger ─────────────────────────────────
            NasiraTitleBar(
              onMenuTap: _editorOpen ? null : _currentOnEdit(),
            ),
            // ── Inhalt ────────────────────────────────────────────────────
            Expanded(
              child: _editorOpen && page != null && gridName != null
                  // ── WYSIWYG Layout-Editor ──────────────────────────────
                  ? GridLayoutEditor(
                      page:      page,
                      rawPage:   _rawPages[_schritt],
                      pageName:  gridName,
                      pageColor: page.backgroundColor,
                      overrideService: _overrideService,
                      cellBuilder: (cell) {
                        final wlItem = autoMap['${cell.x},${cell.y}'];
                        if (wlItem != null) return _buildWordItem(state, wlItem);
                        return _buildCellForEditor(state, cell);
                      },
                      onDismiss: () => setState(() => _editorOpen = false),
                      onChanged: () => setState(() {
                        _applyOverrides();
                        _wlPage = 0;
                      }),
                    )
                  // ── Normal-Modus ───────────────────────────────────────
                  : _buildStepContent(state),
            ),
          ],
        ),
      ),
    );
  }

  /// Rendert eine Zelle für den Layout-Editor (ohne onTap — Editor verwaltet Gesten).
  Widget _buildCellForEditor(NasiraAppState state, GridCell cell) {
    // Caption-Fallback: auch jumpTarget anzeigen wenn kein Text vorhanden
    final displayCaption = cell.caption?.isNotEmpty == true
        ? cell.caption
        : cell.insertText?.trim() ?? cell.jumpTarget;
    final useLocalPng = cell.localImagePath != null;
    final resolvedAssetPath = useLocalPng ? null : _resolveSymbol(state, cell.symbolStem);
    final fallbackWord = (useLocalPng || resolvedAssetPath != null) ? null :
        cell.symbolStem ??
        (cell.insertText != null
            ? _keyWord(cell.insertText!)
            : (displayCaption != null && displayCaption.isNotEmpty
                ? _keyWord(displayCaption)
                : null));

    // Icon-Fallback: von Command-Typ ableiten wenn kein XML-Icon vorhanden
    IconData? resolvedIcon = cell.iconData;
    if (resolvedIcon == null) {
      if (cell.isHome)                                   { resolvedIcon = Icons.home_outlined; }
      else if (cell.isBack)                              { resolvedIcon = Icons.arrow_back_rounded; }
      else if (cell.isDeleteWord || cell.isDeleteLetter) { resolvedIcon = Icons.backspace_outlined; }
      else if (cell.isCapsLock)                          { resolvedIcon = Icons.keyboard_capslock_rounded; }
      else if (cell.isShiftKey)                          { resolvedIcon = Icons.arrow_upward_rounded; }
    }

    final inner = NasiraGridCell(
      caption:         displayCaption,
      fileImagePath:   cell.localImagePath,
      assetPath:       resolvedAssetPath,
      symbolWord:      fallbackWord,
      icon:            resolvedIcon,
      backgroundColor: cell.backgroundColor,
      textColor:       cell.foregroundColor,
      fontSize:        cell.fontSizeOverride ?? (cell.isFullyRounded ? 12 : 11),
      borderRadius:    cell.isFullyRounded ? 100 : 7,
    );

    if (cell.hasBorder) {
      return Container(
        decoration: BoxDecoration(
          border: Border.all(color: NasiraColors.briefBorder, width: 1.5),
          borderRadius: BorderRadius.circular(8),
        ),
        child: inner,
      );
    }
    return inner;
  }

  Widget _buildStepContent(NasiraAppState state) =>
      _buildGridPage(state, _schritt);

  // ── Haupt-Layout-Methode (exaktes X/Y-Grid aus XML) ─────────────────────

  Widget _buildGridPage(NasiraAppState state, _BriefSchritt schritt) {
    final page     = _pages[schritt];
    final leitfrage = _leitfragen[schritt] ?? '';

    if (page == null) {
      return Column(children: [
        Expanded(
          child: Center(
            child: Text(leitfrage,
                style: const TextStyle(color: Colors.grey, fontSize: 14)),
          ),
        ),
        _buildLeitfragenStrip(state, [leitfrage]),
      ]);
    }

    return Column(children: [
      Expanded(child: _buildExactGrid(state, page, schritt)),
      _buildLeitfragenStrip(state, [leitfrage]),
    ]);
  }

  /// Stack-basiertes Grid: rendert die gesamte Seite (Workspace + Nav + Inhalt)
  /// exakt nach den XML-Koordinaten — 1:1 wie im Grid3-Original.
  Widget _buildExactGrid(NasiraAppState state, GridPage page, _BriefSchritt schritt) {
    if (page.rows <= 0) return const SizedBox.shrink();

    // Wortliste je Schritt anpassen.
    final wordList = switch (schritt) {
      // Einleitung: eigene Sätze vorschalten
      _BriefSchritt.einleitung => [
          ...state.customSentences
              .forModule('brief')
              .map((s) => GridWordListItem(text: s.sentence)),
          ...page.wordList,
        ],
      // Begrüßung: Hallo / Liebe / Lieber garantiert sichtbar
      _BriefSchritt.begruessung => page.wordList.isNotEmpty
          ? page.wordList
          : const [
              GridWordListItem(
                text: 'Hallo',
                symbolStem: 'hallo2',
                symbolCategory: 'konversation_interaktion',
                metacmPath: 'konversation_interaktion/hallo2',
              ),
              GridWordListItem(
                text: 'Liebe',
                symbolStem: 'freundin',
                symbolCategory: 'liebe_sexualitaet',
                metacmPath: 'liebe_sexualitaet/freundin',
              ),
              GridWordListItem(
                text: 'Lieber',
                symbolStem: 'freund',
                symbolCategory: 'liebe_sexualitaet',
                metacmPath: 'liebe_sexualitaet/freund',
              ),
            ],
      _ => page.wordList,
    };

    final workspaceCells = page.cells
        .where((c) => c.type == GridCellType.workspace)
        .toList();

    final autoContent = page.cells
        .where((c) => c.type == GridCellType.autoContent)
        .toList()
      ..sort((a, b) => a.y != b.y ? a.y.compareTo(b.y) : a.x.compareTo(b.x));

    final regularCells = page.cells
        .where((c) =>
            c.type != GridCellType.workspace &&
            c.type != GridCellType.autoContent)
        .toList();

    const gap = 3.0;

    return Container(
      color: page.backgroundColor,
      child: LayoutBuilder(builder: (ctx, box) {
        final cellW = box.maxWidth  / page.columns;
        final cellH = box.maxHeight / page.rows;

        return Stack(children: [
          // ── Workspace-Zellen (Text-Editor-Bereich) ───────────────────────
          for (final cell in workspaceCells)
            Positioned(
              left:   cell.x * cellW + gap / 2,
              top:    cell.y * cellH + gap / 2,
              width:  cell.colSpan * cellW - gap,
              height: cell.rowSpan * cellH - gap,
              child:  _buildWorkspaceCell(state),
            ),

          // ── Reguläre Zellen (Nav + Inhalt) ───────────────────────────────
          for (final cell in regularCells)
            Positioned(
              left:   cell.x * cellW + gap / 2,
              top:    cell.y * cellH + gap / 2,
              width:  cell.colSpan * cellW - gap,
              height: cell.rowSpan * cellH - gap,
              child:  _buildRegularCell(state, cell, page, autoContent.length),
            ),

          // ── AutoContent-Zellen mit paginierten WL-Items ──────────────────
          for (int i = 0; i < autoContent.length; i++)
            Builder(builder: (_) {
              final cell  = autoContent[i];
              final wlIdx = _wlPage * autoContent.length + i;
              final item  = wlIdx < wordList.length ? wordList[wlIdx] : null;
              return Positioned(
                left:   cell.x * cellW + gap / 2,
                top:    cell.y * cellH + gap / 2,
                width:  cell.colSpan * cellW - gap,
                height: cell.rowSpan * cellH - gap,
                child:  item != null
                    ? _buildWordItem(state, item)
                    : _buildEmptyAutoSlot(),
              );
            }),
        ]);
      }),
    );
  }

  /// Rendert die NasiraTextWorkspace-Kachel (Texteingabe-Bereich).
  Widget _buildWorkspaceCell(NasiraAppState state) {
    return NasiraTextWorkspace(
      controller: state.textController,
      minHeight: 0,
      maxHeight: double.infinity,
    );
  }

  /// Rendert eine reguläre (nicht-AutoContent, nicht-Workspace) Zelle.
  Widget _buildRegularCell(
    NasiraAppState state,
    GridCell cell,
    GridPage page,
    int acCount,
  ) {
    VoidCallback? onTap;

    VoidCallback? onLongPress;

    if (cell.isDeleteWord) {
      onTap = state.deleteLastWord;
      onLongPress = _confirmClearAll;
    } else if (cell.isBack) {
      onTap = _zurueck;
    } else if (cell.isHome) {
      onTap = () => Navigator.popUntil(context, (r) => r.isFirst);
    } else if (cell.isMoreWords) {
      onTap = () => setState(() {
        if (acCount > 0) {
          final totalPages = (page.wordList.length / acCount).ceil();
          if (totalPages > 1) _wlPage = (_wlPage + 1) % totalPages;
        }
      });
    } else if (cell.isInsertCell) {
      onTap = () => state.insertPhrase(cell.insertText!);
    } else if (cell.isPunctuation) {
      onTap = () => state.insertPhrase(cell.punctuationChar!);
    } else if (cell.isNavigation) {
      final targetName = cell.jumpTarget;
      final step = targetName != null ? _gridNameToStep[targetName] : null;
      if (step != null) {
        onTap = () => _navigateTo(step);
      } else if (targetName != null &&
          targetName.toLowerCase().contains('freies schreiben')) {
        onTap = () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const FreiesSchreibenScreen()));
      }
    }

    // Caption: aus XML-Caption, sonst aus InsertText
    final displayCaption = cell.caption?.isNotEmpty == true
        ? cell.caption
        : cell.insertText?.trim();

    // Symbol: Custom-PNG hat Vorrang, dann AssetManifest-Index, dann Fallback-Lookup.
    final useLocalPng = cell.localImagePath != null;
    final resolvedAssetPath = useLocalPng ? null : _resolveSymbol(state, cell.symbolStem);
    final fallbackWord = (useLocalPng || resolvedAssetPath != null) ? null :
        cell.symbolStem ??
        (cell.insertText != null
            ? _keyWord(cell.insertText!)
            : (displayCaption != null && displayCaption.isNotEmpty
                ? _keyWord(displayCaption)
                : null));

    final inner = NasiraGridCell(
      caption:         displayCaption,
      fileImagePath:   cell.localImagePath,
      assetPath:       resolvedAssetPath,
      symbolWord:      fallbackWord,
      icon:            cell.iconData,
      backgroundColor: cell.backgroundColor,
      textColor:       cell.foregroundColor,
      fontSize:        cell.fontSizeOverride ?? (cell.isFullyRounded ? 12 : 11),
      onTap:           onTap,
      onLongPress:     onLongPress,
      borderRadius:    cell.isFullyRounded ? 100 : 7,
    );

    if (cell.hasBorder) {
      return Container(
        decoration: BoxDecoration(
          border: Border.all(color: NasiraColors.briefBorder, width: 1.5),
          borderRadius: BorderRadius.circular(8),
        ),
        child: inner,
      );
    }
    return inner;
  }

  /// Wort-Kachel für einen AutoContent-Slot (WL-Item).
  Widget _buildWordItem(NasiraAppState state, GridWordListItem item) {
    // Custom-PNG nur wenn kein [metacm]-Verweis vorhanden.
    final useCustomPng = item.localImagePath != null && item.metacmPath == null;
    // Stem direkt über AssetManifest-Index auflösen (bypass Engine).
    final resolvedPath = useCustomPng ? null : _resolveSymbol(state, item.symbolStem);

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: NasiraColors.briefBorder, width: 1.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: NasiraGridCell(
        caption:         item.text,
        fileImagePath:   useCustomPng ? item.localImagePath : null,
        assetPath:       resolvedPath,
        symbolWord:      (useCustomPng || resolvedPath != null)
                             ? null
                             : _keyWord(item.text),
        backgroundColor: Colors.white,
        textColor:       NasiraColors.textDark,
        fontSize:        11,
        elevation:       0,
        borderRadius:    6,
        onTap: () {
          debugPrint('[WORDITEM] "${item.text}" → stem=${item.symbolStem ?? '-'} | resolved=${resolvedPath ?? 'fallback:${_keyWord(item.text)}'}');
          state.insertPhrase(item.text);
        },
      ),
    );
  }

  /// Leerer AutoContent-Slot (kein WL-Item auf dieser Seite).
  Widget _buildEmptyAutoSlot() => Container(
    decoration: BoxDecoration(
      color: NasiraColors.briefBg,
      borderRadius: BorderRadius.circular(8),
    ),
  );

  // ── Leitfragen-Streifen ──────────────────────────────────────────────────

  Widget _buildLeitfragenStrip(
    NasiraAppState state,
    List<String> fragen,
  ) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: SizedBox(
        height: 52,
        child: Row(
          children: [
            for (int i = 0; i < fragen.length; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              Expanded(
                child: NasiraGridCell(
                  caption: fragen[i],
                  backgroundColor: NasiraColors.briefQuestion,
                  fontSize: 11,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

}
