import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../nasira_app_state.dart';
import '../models/grid_page.dart';
import '../services/grid_import_service.dart';
import '../services/grid_override_service.dart';
import '../theme/nasira_colors.dart';
import '../widgets/grid_layout_editor.dart';
import '../widgets/grid_page_editor_sheet.dart';
import '../widgets/nasira_grid_cell.dart';
import '../widgets/nasira_module_header.dart';
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

  // ── Haupt-Sequenz für Vorwärts-Navigation ──────────────────────────────────

  static const _mainSeq = [
    _BriefSchritt.begruessung,
    _BriefSchritt.personen,
    _BriefSchritt.einleitung,
    _BriefSchritt.inhaltsuebersicht,
    _BriefSchritt.ende,
    _BriefSchritt.endeGruesse,
  ];

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
          caption:      (cOv?['caption']    as String?) ?? c.caption,
          symbolStem:   (cOv?['symbolStem'] as String?) ?? c.symbolStem,
          symbolCategory: c.symbolCategory,
          metacmPath:   c.metacmPath,
          localImagePath: c.localImagePath,
          iconData: c.iconData,
          style: c.style, type: c.type, commands: c.commands,
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

  // ── Navigation ──────────────────────────────────────────────────────────────

  void _navigateTo(_BriefSchritt step) {
    setState(() {
      _history.add(_schritt);
      _schritt = step;
      _wlPage = 0;
    });
  }

  /// True wenn der aktuelle Schritt NICHT in der Haupt-Sequenz liegt
  /// (d. h. wir befinden uns in einem Sub- oder Hub-Screen).
  bool get _isSubScreen => !_mainSeq.contains(_schritt);

  void _vorwaerts() {
    if (_isSubScreen) {
      // Aus jedem Sub-Screen direkt zurück zur Inhaltsübersicht springen.
      _navigateTo(_BriefSchritt.inhaltsuebersicht);
      return;
    }
    final idx = _mainSeq.indexOf(_schritt);
    if (idx >= 0 && idx < _mainSeq.length - 1) {
      _navigateTo(_mainSeq[idx + 1]);
    }
  }

  void _zurueck() {
    if (_history.isNotEmpty) {
      setState(() => _schritt = _history.removeLast());
    } else {
      Navigator.pop(context);
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
        child: _editorOpen && page != null && gridName != null
            // ── WYSIWYG Layout-Editor (ersetzt Seiten-Inhalt direkt) ────
            ? GridLayoutEditor(
                page:      page,
                rawPage:   _rawPages[_schritt],
                pageName:  gridName,
                pageColor: page.backgroundColor,
                overrideService: _overrideService,
                cellBuilder: (cell) {
                  // AutoContent → echtes WL-Item anzeigen
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
            // ── Normal-Modus ─────────────────────────────────────────────
            : Column(
                children: [
                  NasiraModuleHeader(
                    controller: state.textController,
                    accentColor: NasiraColors.navGreen,
                    onBack: _zurueck,
                    onForward: _vorwaerts,
                    onMenu: _currentOnEdit(),
                    isForwardOval: _isSubScreen,
                  ),
                  Expanded(child: _buildStepContent(state)),
                ],
              ),
      ),
    );
  }

  /// Rendert eine Zelle für den Layout-Editor (ohne onTap — Editor verwaltet Gesten).
  Widget _buildCellForEditor(NasiraAppState state, GridCell cell) {
    final displayCaption = cell.caption?.isNotEmpty == true
        ? cell.caption
        : cell.insertText?.trim();
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
      fontSize:        cell.style.isOval ? 12 : 11,
      borderRadius:    cell.style.isOval ? 100 : 7,
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

  Widget _buildStepContent(NasiraAppState state) {
    return switch (_schritt) {
      // Haupt-Sequenz (parser-getrieben, WL-only)
      _BriefSchritt.begruessung       => _buildGridPage(state, _BriefSchritt.begruessung),
      _BriefSchritt.personen          => _buildGridPage(state, _BriefSchritt.personen),
      _BriefSchritt.einleitung        => _buildEinleitung(state),
      // Inhalt
      _BriefSchritt.inhaltsuebersicht => _buildGridPage(state, _BriefSchritt.inhaltsuebersicht),
      // Verabreden
      _BriefSchritt.verabreden        => _buildGridPage(state, _BriefSchritt.verabreden),
      _BriefSchritt.verabredenWann    => _buildGridPage(state, _BriefSchritt.verabredenWann),
      _BriefSchritt.verabredenWas     => _buildGridPage(state, _BriefSchritt.verabredenWas),
      _BriefSchritt.verabredenWo      => _buildGridPage(state, _BriefSchritt.verabredenWo),
      // Über dich und mich
      _BriefSchritt.uberDichUndMich   => _buildGridPage(state, _BriefSchritt.uberDichUndMich),
      _BriefSchritt.uberDich          => _buildGridPage(state, _BriefSchritt.uberDich),
      _BriefSchritt.uberMich          => _buildGridPage(state, _BriefSchritt.uberMich),
      _BriefSchritt.trinken           => _buildGridPage(state, _BriefSchritt.trinken),
      _BriefSchritt.kleidung          => _buildGridPage(state, _BriefSchritt.kleidung),
      _BriefSchritt.hobby             => _buildGridPage(state, _BriefSchritt.hobby),
      _BriefSchritt.essen             => _buildGridPage(state, _BriefSchritt.essen),
      _BriefSchritt.haustiere         => _buildGridPage(state, _BriefSchritt.haustiere),
      // Wünsche und Danken
      _BriefSchritt.wuenscheUndDanken => _buildGridPage(state, _BriefSchritt.wuenscheUndDanken),
      _BriefSchritt.wuenschen         => _buildGridPage(state, _BriefSchritt.wuenschen),
      _BriefSchritt.bedanken          => _buildGridPage(state, _BriefSchritt.bedanken),
      // Sonstiges
      _BriefSchritt.sonstiges         => _buildGridPage(state, _BriefSchritt.sonstiges),
      _BriefSchritt.wetter            => _buildGridPage(state, _BriefSchritt.wetter),
      _BriefSchritt.schule            => _buildGridPage(state, _BriefSchritt.schule),
      _BriefSchritt.gesundheit        => _buildGridPage(state, _BriefSchritt.gesundheit),
      _BriefSchritt.gesundheitDetail  => _buildGridPage(state, _BriefSchritt.gesundheitDetail),
      // Direkt
      _BriefSchritt.gefuehle          => _buildGridPage(state, _BriefSchritt.gefuehle),
      _BriefSchritt.beschreibungen    => _buildGridPage(state, _BriefSchritt.beschreibungen),
      // Abschluss
      _BriefSchritt.ende              => _buildGridPage(state, _BriefSchritt.ende),
      _BriefSchritt.endeGruesse       => _buildEndeGruesse(state),
    };
  }

  // ── Haupt-Layout-Methode (exaktes X/Y-Grid aus XML) ─────────────────────

  Widget _buildGridPage(NasiraAppState state, _BriefSchritt schritt) {
    final page = _pages[schritt];
    final leitfrage = _leitfragen[schritt] ?? '';
    final gridName = _stepToGridName[schritt];

    final VoidCallback? onEdit = (page != null && gridName != null)
        ? () => GridPageEditorSheet.show(
              context: context,
              page: page,
              overrideService: _overrideService,
              onSaved: () => setState(() {
                _applyOverrides();
                _wlPage = 0;
              }),
            )
        : null;

    if (page == null) {
      return Column(children: [
        Expanded(
          child: Center(
            child: Text(leitfrage,
                style: const TextStyle(color: Colors.grey, fontSize: 14)),
          ),
        ),
        _buildLeitfragenStrip(state, [leitfrage], onEdit: onEdit),
      ]);
    }

    return Column(children: [
      Expanded(child: _buildExactGrid(state, page)),
      _buildLeitfragenStrip(state, [leitfrage], onEdit: onEdit),
    ]);
  }

  /// Stack-basiertes Grid: jede Zelle sitzt an ihrer exakten XML-Position.
  ///
  /// Workspace-Zeilen (Grid3-Texteditor) werden übersprungen —
  /// deren Funktion übernimmt NasiraModuleHeader.
  Widget _buildExactGrid(NasiraAppState state, GridPage page) {
    // Workspace-Zeilen bestimmen und überspringen
    final wsCell = page.cells
        .where((c) => c.type == GridCellType.workspace)
        .firstOrNull;
    final firstContent = wsCell != null ? wsCell.y + wsCell.rowSpan : 0;
    final contentRows  = page.rows - firstContent;
    if (contentRows <= 0) return const SizedBox.shrink();

    final contentCells = page.cells
        .where((c) => c.type != GridCellType.workspace && c.y >= firstContent)
        .toList();

    final autoContent = contentCells
        .where((c) => c.type == GridCellType.autoContent)
        .toList()
      ..sort((a, b) => a.y != b.y ? a.y.compareTo(b.y) : a.x.compareTo(b.x));

    final regularCells = contentCells
        .where((c) => c.type != GridCellType.autoContent)
        .toList();

    const gap = 3.0;

    return Container(
      color: page.backgroundColor,
      child: LayoutBuilder(builder: (ctx, box) {
        final cellW = box.maxWidth  / page.columns;
        final cellH = box.maxHeight / contentRows;

        return Stack(children: [
          // ── Reguläre Zellen ──────────────────────────────────────────────
          for (final cell in regularCells)
            Positioned(
              left:   cell.x * cellW + gap / 2,
              top:    (cell.y - firstContent) * cellH + gap / 2,
              width:  cell.colSpan * cellW - gap,
              height: cell.rowSpan * cellH - gap,
              child:  _buildRegularCell(state, cell, page, autoContent.length),
            ),

          // ── AutoContent-Zellen mit paginierten WL-Items ──────────────────
          for (int i = 0; i < autoContent.length; i++)
            Builder(builder: (_) {
              final cell   = autoContent[i];
              final wlIdx  = _wlPage * autoContent.length + i;
              final item   = wlIdx < page.wordList.length
                  ? page.wordList[wlIdx] : null;
              return Positioned(
                left:   cell.x * cellW + gap / 2,
                top:    (cell.y - firstContent) * cellH + gap / 2,
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

  /// Rendert eine reguläre (nicht-AutoContent, nicht-Workspace) Zelle.
  Widget _buildRegularCell(
    NasiraAppState state,
    GridCell cell,
    GridPage page,
    int acCount,
  ) {
    VoidCallback? onTap;

    if (cell.isDeleteWord) {
      onTap = state.deleteLastWord;
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
      fontSize:        cell.style.isOval ? 12 : 11,
      onTap:           onTap,
      borderRadius:    cell.style.isOval ? 100 : 7,
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

  // ── Flaches Grid (nur für Einleitung mit customSentences) ────────────────

  Widget _buildFlatWordGrid(NasiraAppState state, List<GridWordListItem> words) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 140,
          crossAxisSpacing: 6,
          mainAxisSpacing: 6,
          childAspectRatio: 0.85,
        ),
        itemCount: words.length,
        itemBuilder: (_, i) {
          final item = words[i];
          final bg = item.text.endsWith('?')
              ? NasiraColors.briefQuestion
              : item.text.endsWith('.') || item.text.endsWith('!')
                  ? NasiraColors.briefSentence
                  : NasiraColors.briefTopic;
          final useCustomPng2 = item.localImagePath != null && item.metacmPath == null;
          final resolvedPath2 = useCustomPng2 ? null : _resolveSymbol(state, item.symbolStem);
          return NasiraGridCell(
            caption:         item.text,
            fileImagePath:   useCustomPng2 ? item.localImagePath : null,
            assetPath:       resolvedPath2,
            symbolWord:      (useCustomPng2 || resolvedPath2 != null)
                                 ? null
                                 : _keyWord(item.text),
            backgroundColor: bg,
            textColor:       Colors.white,
            fontSize:        11,
            onTap:           () => state.insertPhrase(item.text),
          );
        },
      ),
    );
  }

  // ── Einleitung (eigener Builder wegen customSentences) ───────────────────

  Widget _buildEinleitung(NasiraAppState state) {
    // Eigene Sätze aus dem CustomSentenceService voranstellen
    final custom = state.customSentences
        .forModule('brief')
        .map((s) => GridWordListItem(text: s.sentence))
        .toList();

    // Parser-Sätze aus dem Export
    final parserWl = _pages[_BriefSchritt.einleitung]?.wordList ?? const [];

    final all = [...custom, ...parserWl];

    return Column(children: [
      Expanded(child: _buildFlatWordGrid(state, all)),
      _buildLeitfragenStrip(state, [
        'Was schreibst du zur Einleitung?',
        'Was hast du gemacht?',
      ]),
    ]);
  }

  // ── Ende Grüße (bleibt hardcodiert – Grid6 hat Variablen) ────────────────

  Widget _buildEndeGruesse(NasiraAppState state) {
    const gruesse = [
      ('Liebe Grüße',     'Liebe'),
      ('Herzliche Grüße', 'herzlich'),
      ('Viele Grüße',     'viel'),
      ('Bis bald',        'bald'),
      ('Deine Nasira',    'Nasira'),
    ];
    return Column(children: [
      Expanded(child: _buildGrid(
        itemCount: gruesse.length,
        builder: (i) => NasiraGridCell(
          caption: gruesse[i].$1,
          symbolWord: gruesse[i].$2,
          backgroundColor: NasiraColors.briefTopic,
          onTap: () => state.insertPhrase('\n${gruesse[i].$1},\n'),
        ),
      )),
      _buildLeitfragenStrip(state, ['Mit welchem Gruß möchtest du schließen?']),
    ]);
  }

  // ── Leitfragen-Streifen ──────────────────────────────────────────────────

  Widget _buildLeitfragenStrip(
    NasiraAppState state,
    List<String> fragen, {
    VoidCallback? onEdit,
  }) {
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
            if (onEdit != null) ...[
              const SizedBox(width: 6),
              SizedBox(
                width: 44,
                child: Material(
                  color: NasiraColors.navGreen,
                  borderRadius: BorderRadius.circular(8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: onEdit,
                    child: const Center(
                      child: Icon(Icons.edit_outlined,
                          color: Colors.white, size: 22),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Shared grid helper ───────────────────────────────────────────────────

  Widget _buildGrid({
    required int itemCount,
    required Widget Function(int index) builder,
  }) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: GridView.builder(
        itemCount: itemCount,
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 140,
          crossAxisSpacing: 6,
          mainAxisSpacing: 6,
          childAspectRatio: 0.85,
        ),
        itemBuilder: (_, i) => builder(i),
      ),
    );
  }
}
