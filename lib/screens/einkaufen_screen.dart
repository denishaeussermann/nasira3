import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../nasira_app_state.dart';
import '../nasira_repository.dart';
import '../models/models.dart';
import '../services/grid_override_service.dart';
import '../theme/nasira_colors.dart';
import '../widgets/grid_layout_editor.dart';
import '../widgets/nasira_grid_cell.dart';
import '../widgets/nasira_text_workspace.dart';
import '../widgets/nasira_title_bar.dart';
import 'freies_schreiben_screen.dart';

/// Stabiler Schlüssel für GridOverrideService-Einträge.
const _kEinkaufPageKey = 'Einkaufen';

// ── Einkaufen ────────────────────────────────────────────────────────────────
//
// Einheitliches Grid 6 × 8 = 48 Zellen:
//   Reihen 0-1, Spalten 0-5  → Header (Home / Workspace / DeleteWord)
//   Reihen 2-4, Spalte 0     → Modifier: 123 / Einheit / Eigenschaft
//   Reihen 2-4, Spalten 1-5  → 15 Kategorien (5 × 3)
//   Reihen 5-7, Spalten 0-4  → 15 Artikel-Slots (5 × 3, paginiert)
//   Reihe 5,    Spalte 5     → Weitere Vorhersagen vorwärts
//   Reihe 7,    Spalte 5     → Weitere Vorhersagen rückwärts

class _EinkaufKategorie {
  final String label;
  final IconData icon;
  final String symbolWord; // besseres Suchwort für Symbol-Engine
  final List<String> items;
  const _EinkaufKategorie(this.label, this.icon, this.symbolWord, this.items);
}

// 15 Kategorien = 5 Spalten × 3 Reihen
const _kategorien = <_EinkaufKategorie>[
  // ── Reihe 0 (Spalten 1-5) ─────────────────────────────────────────────────
  _EinkaufKategorie('Obst', Icons.eco_outlined, 'Obst',
      ['Apfel', 'Banane', 'Obst', 'Kiwi', 'Mandarine', 'Orange', 'Traube',
       'Zitrone']),
  _EinkaufKategorie('Gemüse', Icons.grass_outlined, 'Gemüse',
      ['Brokkoli', 'Gurke', 'Karotte', 'Kartoffel', 'Paprika', 'Petersilie',
       'Pilze', 'Salat', 'Tomate', 'Zucchini', 'Zwiebel']),
  _EinkaufKategorie('Fleisch und Wurst', Icons.kebab_dining_outlined, 'Fleisch',
      ['Fisch', 'Fleisch', 'Fleischküchle', 'Hack', 'Hähnchen', 'Hähnchenkeule',
       'Lamm', 'Geflügel', 'Schnitzel', 'Geschnetzeltes', 'Rindfleisch', 'Wurst',
       'Steak']),
  _EinkaufKategorie('Milchprodukte', Icons.local_cafe_outlined, 'Milch',
      ['Milch', 'Butter', 'Margarine', 'Käse', 'Joghurt', 'Quark', 'Sahne',
       'Buttermilch', 'saure Sahne', 'Schmand', 'Eis']),
  _EinkaufKategorie('Beilagen', Icons.rice_bowl_outlined, 'Nudeln',
      ['Nudeln', 'Spaghetti', 'Reis', 'Kartoffelpüree', 'Knödel', 'Linsen',
       'Spätzle']),
  // ── Reihe 1 (Spalten 1-5) ─────────────────────────────────────────────────
  _EinkaufKategorie('Backwaren', Icons.bakery_dining_outlined, 'Brot',
      ['Brot', 'Toast', 'Brötchen', 'Brezel', 'Kuchen', 'Süßes Stückchen']),
  _EinkaufKategorie('Würze', Icons.restaurant_menu_outlined, 'Salz',
      ['Salz', 'Pfeffer', 'Zucker', 'Öl', 'Essig', 'Senf', 'Ketchup',
       'Salatsoße', 'Gewürze', 'Brühe', 'Soße', 'Tomatensoße']),
  _EinkaufKategorie('Snacks', Icons.cookie_outlined, 'Schokolade',
      ['Schokolade', 'Chips', 'Kekse', 'Bonbons', 'Gummibärchen', 'Nüsse',
       'Salzstangen', 'Pudding', 'Eis', 'Süßigkeiten']),
  _EinkaufKategorie('Verschiedenes', Icons.category_outlined, 'Einkaufen',
      ['Mehl', 'Müsli', 'Marmelade', 'Nutella', 'Cornflakes', 'Honig',
       'Fertiggerichte', 'Maultasche']),
  _EinkaufKategorie('Getränke', Icons.local_drink_outlined, 'Getränke',
      ['Tee', 'Kaba', 'Kaffee', 'Sprudel', 'Schorle', 'Apfelschorle',
       'Apfelsaft', 'Orangensaft', 'Fanta', 'Spezi', 'Cola', 'Sekt', 'Bier',
       'Wein']),
  // ── Reihe 2 (Spalten 1-5) ─────────────────────────────────────────────────
  _EinkaufKategorie('Haushalt', Icons.cleaning_services_outlined, 'Putzen',
      ['Spülmittel', 'Geschirrspülmittel', 'Waschpulver', 'Bodenreiniger',
       'Putzlappen', 'Müllbeutel', 'Alufolie', 'Backpapier', 'Frischhaltefolie',
       'Gefrierbeutel', 'Küchenrolle', 'Kaffeefilter', 'Servietten',
       'Batterien', 'Kerzen']),
  _EinkaufKategorie('Bad', Icons.bathtub_outlined, 'Duschgel',
      ['Toilettenpapier', 'Seife', 'Deo', 'Duschgel', 'Shampoo', 'Haarspülung',
       'Zahnpasta', 'Gesichtscreme', 'Badezusatz', 'Pflaster', 'Sonnenschutz',
       'Taschentücher']),
  _EinkaufKategorie('Kleidung', Icons.checkroom_outlined, 'Kleidung',
      ['Hose', 'T-shirt', 'Strümpfe', 'Pullover', 'Kleid', 'Rock',
       'Schlafanzug', 'Bluse', 'Hemd', 'Badeanzug', 'Badehose', 'Bademantel',
       'Unterhose', 'BH', 'Unterhemd', 'Schuhe', 'Sandalen', 'Sportschuhe',
       'Stiefel', 'Handschuhe', 'Jacke', 'Mantel', 'Mütze', 'Hut', 'Schal',
       'Gürtel', 'Brille', 'Schmuck', 'Uhr', 'Armband', 'Kette', 'Ring']),
  _EinkaufKategorie('Freies Schreiben', Icons.edit_note_rounded, 'schreiben', []),
  _EinkaufKategorie('mehr Einkaufen', Icons.add_shopping_cart_outlined, 'Einkaufen', []),
];

// ── Modifier-Inhalte ──────────────────────────────────────────────────────────

// 123: 1-20 einzeln, dann 50 / 100 / 500
const _numberItems = <String>[
  '1', '2', '3', '4', '5', '6', '7', '8', '9', '10',
  '11', '12', '13', '14', '15', '16', '17', '18', '19', '20',
  '50', '100', '500',
];

// Einheit (aus Screenshot: Stück, Tafel, Packung, Dose, Netz, Tüte, Flasche, Liter, Kilogramm, Gramm)
const _einheitItems = <String>[
  'Stück', 'Tafel', 'Packung', 'Dose', 'Netz',
  'Tüte', 'Flasche', 'Liter', 'Kilogramm', 'Gramm',
];

// Eigenschaft: Seite 1 = Geschmack/Zustand, Seite 2+3 = Farben
const _eigenschaftItems = <String>[
  'süß', 'sauer', 'salzig', 'scharf', 'gefroren',
  'frisch', 'getrocknet', 'gebacken', 'fertig', 'bunt',
  'beige', 'blau', 'braun', 'gelb', 'grau',
  'grün', 'lila', 'orange', 'rosa', 'rot',
  'schwarz', 'silber', 'türkis', 'violett', 'weiß',
  'dunkel', 'hell',
];

// ── Screen ────────────────────────────────────────────────────────────────────

class EinkaufenScreen extends StatefulWidget {
  const EinkaufenScreen({super.key});

  @override
  State<EinkaufenScreen> createState() => _EinkaufenScreenState();
}

class _EinkaufenScreenState extends State<EinkaufenScreen> {
  // activeKey: null | '123' | 'Einheit' | 'Eigenschaft' | <Kategoriename>
  String? _activeKey;
  int _page = 0;

  static const _cols        = 6;
  static const _headerRows  = 2; // Zeilen 0-1: Workspace / Home / DeleteWord
  static const _contentRows = 6; // Zeilen 2-7: 3 Kat-Reihen + 3 Artikel-Reihen
  static const _rows        = _headerRows + _contentRows; // = 8
  static const _pageSize    = 15; // 5 Artikel-Slots × 3 Reihen

  // ── Editor ──────────────────────────────────────────────────────────────
  bool _editorOpen = false;
  final _overrideService = GridOverrideService();
  /// Effektive Seite: kanonische Zellen + gespeicherte Layout-Overrides.
  late GridPage _effectivePage;
  /// Gecachte NasiraData (aus FutureBuilder) für Stack-Rendering.
  NasiraData? _cachedData;

  @override
  void initState() {
    super.initState();
    _effectivePage = _buildCanonicalPage();
    _overrideService.load().then((_) {
      if (mounted) setState(_applyOverrides);
    });
  }

  // ── Kanonische GridPage (6 × 8, 48 Zellen mit stabilen symbolStem-Keys) ─

  /// symbolStem-Kodierung:
  ///   __mod_123__        → Modifier-Zelle "123"
  ///   __mod_Einheit__    → Modifier-Zelle "Einheit"
  ///   __mod_Eigenschaft__→ Modifier-Zelle "Eigenschaft"
  ///   __kat_N__          → Kategorie-Index N (0–14)
  ///   __item_N__         → Artikel-Slot N (0–14)
  ///   __nav_fwd__        → Navigation vorwärts (Zeile 5, Spalte 5)
  ///   __nav_bak__        → Navigation rückwärts (Zeile 7, Spalte 5)
  GridPage _buildCanonicalPage() {
    const modKeys = ['123', 'Einheit', 'Eigenschaft'];
    return GridPage(
      name: _kEinkaufPageKey,
      columns: _cols,
      rows: _rows,
      backgroundColor: const Color(0xFF1E2E1E),
      wordList: const [],
      cells: [
        // ── Header-Zeilen 0–1: Workspace + Home + DeleteWord ────────────
        const GridCell(
          x: 0, y: 0, rowSpan: 2,
          symbolStem: '__home__',
          style: GridCellStyle.actionNav,
          type: GridCellType.normal,
          commands: [GridCellCommand(type: GridCommandType.jumpHome)],
        ),
        const GridCell(
          x: 1, y: 0, colSpan: 4, rowSpan: 2,
          style: GridCellStyle.textfeld,
          type: GridCellType.workspace,
          commands: [],
        ),
        const GridCell(
          x: 5, y: 0, rowSpan: 2,
          symbolStem: '__deleteword__',
          style: GridCellStyle.actionNav,
          type: GridCellType.normal,
          commands: [GridCellCommand(type: GridCommandType.deleteWord)],
        ),
        // ── Inhalt (verschoben um 2 Zeilen nach unten) ──────────────────
        // Modifier (Spalte 0, Zeilen 2–4)
        for (int r = 0; r < 3; r++)
          GridCell(
            x: 0, y: 2 + r,
            caption: modKeys[r],
            symbolStem: '__mod_${modKeys[r]}__',
            style: GridCellStyle.actionNav,
            type: GridCellType.normal,
            commands: const [],
          ),
        // Kategorien (Spalten 1–5, Zeilen 2–4)
        for (int i = 0; i < _kategorien.length; i++)
          GridCell(
            x: 1 + i % 5, y: 2 + i ~/ 5,
            caption: _kategorien[i].label,
            symbolStem: '__kat_${i}__',
            style: GridCellStyle.actionNav,
            type: GridCellType.normal,
            commands: const [],
          ),
        // Artikel-Slots (Spalten 0–4, Zeilen 5–7)
        for (int i = 0; i < _pageSize; i++)
          GridCell(
            x: i % 5, y: 5 + i ~/ 5,
            symbolStem: '__item_${i}__',
            style: GridCellStyle.wortliste,
            type: GridCellType.autoContent,
            commands: const [],
          ),
        // Navigation vorwärts (Spalte 5, Zeile 5)
        const GridCell(
          x: 5, y: 5,
          caption: 'Weitere\nVorhersagen',
          symbolStem: '__nav_fwd__',
          style: GridCellStyle.weitereWoerter,
          type: GridCellType.normal,
          commands: [],
        ),
        // Navigation rückwärts (Spalte 5, Zeile 7 = unterste Reihe)
        const GridCell(
          x: 5, y: 7,
          caption: 'Weitere\nVorhersagen',
          symbolStem: '__nav_bak__',
          style: GridCellStyle.weitereWoerter,
          type: GridCellType.normal,
          commands: [],
        ),
      ],
    );
  }

  /// Wendet Layout- und Größen-Overrides des GridOverrideService an.
  void _applyOverrides() {
    final layoutOv = _overrideService.getLayoutOverrides(_kEinkaufPageKey);
    final sizeOv   = _overrideService.getGridSize(_kEinkaufPageKey);
    final canonical = _buildCanonicalPage();
    final cells = canonical.cells.map((c) {
      final lOv = layoutOv?['${c.x},${c.y}'];
      if (lOv == null) return c;
      return GridCell(
        x:       lOv['x']       ?? c.x,
        y:       lOv['y']       ?? c.y,
        colSpan: lOv['colSpan'] ?? c.colSpan,
        rowSpan: lOv['rowSpan'] ?? c.rowSpan,
        caption: c.caption, symbolStem: c.symbolStem,
        style: c.style, type: c.type, commands: c.commands,
      );
    }).toList();
    _effectivePage = GridPage(
      name: canonical.name,
      columns: sizeOv?['columns'] ?? canonical.columns,
      rows:    sizeOv?['rows']    ?? canonical.rows,
      backgroundColor: canonical.backgroundColor,
      cells: cells,
      wordList: const [],
    );
  }

  // ── Daten der aktuellen Auswahl ──────────────────────────────────────────

  List<String> get _allItems {
    switch (_activeKey) {
      case '123':          return _numberItems;
      case 'Einheit':      return _einheitItems;
      case 'Eigenschaft':  return _eigenschaftItems;
      case null:           return const [];
      default:
        return _kategorien
            .firstWhere((k) => k.label == _activeKey,
                orElse: () => _kategorien.first)
            .items;
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

  List<String> get _pageItems {
    final all   = _allItems;
    final start = _page * _pageSize;
    if (start >= all.length) return const [];
    return all.sublist(start, math.min(start + _pageSize, all.length));
  }

  bool get _canGoForward => (_page + 1) * _pageSize < _allItems.length;
  bool get _canGoBack    => _page > 0;

  void _activate(String key) => setState(() {
    _activeKey = (_activeKey == key) ? null : key;
    _page = 0;
  });

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final state = context.watch<NasiraAppState>();

    final items = _pageItems;

    return Scaffold(
      backgroundColor: NasiraColors.briefBg,
      body: SafeArea(
        child: Column(
          children: [
            // ── Titelleiste mit Hamburger ─────────────────────────────────
            NasiraTitleBar(
              onMenuTap: _editorOpen
                  ? null
                  : () => setState(() => _editorOpen = true),
            ),
            // ── Inhalt ────────────────────────────────────────────────────
            Expanded(
              child: _editorOpen
                  ? GridLayoutEditor(
                      page:     _effectivePage,
                      rawPage:  _buildCanonicalPage(),
                      pageName: _kEinkaufPageKey,
                      pageColor: const Color(0xFF1E2E1E),
                      overrideService: _overrideService,
                      cellBuilder: (cell) =>
                          _buildCellForEditor(state, cell, items),
                      onDismiss: () => setState(() => _editorOpen = false),
                      onChanged: () => setState(_applyOverrides),
                    )
                  : FutureBuilder<NasiraLoadResult>(
                      future: state.futureLoad,
                      builder: (ctx, snap) {
                        if (!snap.hasData) {
                          return const Center(
                              child: CircularProgressIndicator());
                        }
                        _cachedData = snap.data!.data;
                        return _buildStackGrid(state);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Zweigeteiltes Grid: Header (Zeilen 0-1) + Inhalt (Zeilen 2-7) ─────────
  //
  // Jeder Abschnitt bekommt seinen eigenen Expanded-Slot in einer Column,
  // sodass die Inhaltszellen (Kategorien + Artikel) garantiert sichtbar bleiben
  // unabhängig von Fensterhöhe oder Taskbar-Überlappung.

  Widget _buildStackGrid(NasiraAppState state) {
    final page = _effectivePage;
    final cols  = page.columns;
    const gap = 4.0;
    const pad = 4.0;

    final headerCells  = page.cells.where((c) => c.y < _headerRows).toList();
    final contentCells = page.cells.where((c) => c.y >= _headerRows).toList();

    return Container(
      color: page.backgroundColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header (Zeilen 0-1) ────────────────────────────────────────────
          Expanded(
            flex: _headerRows,
            child: LayoutBuilder(builder: (ctx, box) {
              final cellW = (box.maxWidth  - gap * (cols - 1)          - pad * 2) / cols;
              final cellH = (box.maxHeight - gap * (_headerRows - 1)   - pad * 2) / _headerRows;
              return Stack(
                children: [
                  for (final cell in headerCells)
                    Positioned(
                      left:   pad + cell.x * (cellW + gap),
                      top:    pad + cell.y * (cellH + gap),
                      width:  cell.colSpan * (cellW + gap) - gap,
                      height: cell.rowSpan * (cellH + gap) - gap,
                      child:  _renderCell(cell, state),
                    ),
                ],
              );
            }),
          ),
          // ── Inhalt (Zeilen 2-7: Modifier / Kat / Artikel / Nav) ───────────
          Expanded(
            flex: _contentRows,
            child: LayoutBuilder(builder: (ctx, box) {
              final cellW = (box.maxWidth  - gap * (cols - 1)           - pad * 2) / cols;
              final cellH = (box.maxHeight - gap * (_contentRows - 1)   - pad * 2) / _contentRows;
              return Stack(
                children: [
                  for (final cell in contentCells)
                    Positioned(
                      left:   pad + cell.x * (cellW + gap),
                      top:    pad + (cell.y - _headerRows) * (cellH + gap),
                      width:  cell.colSpan * (cellW + gap) - gap,
                      height: cell.rowSpan * (cellH + gap) - gap,
                      child:  _renderCell(cell, state),
                    ),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }

  // ── Zellen-Router: symbolStem → passendes Widget ──────────────────────────

  Widget _renderCell(GridCell cell, NasiraAppState state) {
    // ── Header-Zellen ────────────────────────────────────────────────────────
    if (cell.type == GridCellType.workspace) {
      return NasiraTextWorkspace(
        controller: state.textController,
        minHeight: 0,
        maxHeight: double.infinity,
      );
    }

    if (cell.isHome) {
      return NasiraGridCell(
        icon: Icons.home_outlined,
        backgroundColor: NasiraColors.navGreen,
        onTap: () => Navigator.of(context).popUntil((r) => r.isFirst),
      );
    }

    if (cell.isDeleteWord) {
      return NasiraGridCell(
        icon: Icons.backspace_outlined,
        backgroundColor: NasiraColors.navGreen,
        onTap: state.deleteLastWord,
        onLongPress: _confirmClearAll,
      );
    }

    final stem = cell.symbolStem ?? '';

    if (stem.startsWith('__mod_')) {
      final key = stem.substring(6, stem.length - 2);
      const icons = <String, IconData>{
        '123': Icons.tag,
        'Einheit': Icons.info_outline,
        'Eigenschaft': Icons.tune_outlined,
      };
      return _buildModifierCell(key, icons[key] ?? Icons.tag);
    }

    if (stem.startsWith('__kat_')) {
      final idx = int.tryParse(stem.substring(6, stem.length - 2)) ?? 0;
      if (idx < _kategorien.length) return _buildCatCell(idx, state, _cachedData);
      return _buildEmptySlot();
    }

    if (stem.startsWith('__item_')) {
      final slotIdx = int.tryParse(stem.substring(7, stem.length - 2)) ?? 0;
      final items = _pageItems;
      if (slotIdx < items.length) {
        return _buildItemCell(items[slotIdx], state, _cachedData);
      }
      return _buildEmptySlot();
    }

    if (stem == '__nav_fwd__') return _buildNavCell(forward: true);
    if (stem == '__nav_bak__') return _buildNavCell(forward: false);

    return _buildEmptySlot();
  }

  // ── cellBuilder für GridLayoutEditor (IgnorePointer kommt vom Editor) ────

  Widget _buildCellForEditor(
      NasiraAppState state, GridCell cell, List<String> items) {
    final stem = cell.symbolStem ?? '';

    if (stem.startsWith('__mod_')) {
      final key = stem.substring(6, stem.length - 2);
      const icons = <String, IconData>{
        '123': Icons.tag,
        'Einheit': Icons.info_outline,
        'Eigenschaft': Icons.tune_outlined,
      };
      return NasiraGridCell(
        caption: key,
        icon: icons[key] ?? Icons.tag,
        backgroundColor: _activeKey == key
            ? NasiraColors.navGreen
            : NasiraColors.moduleDarkGreen,
        textColor: Colors.white,
        fontSize: 11,
      );
    }

    if (stem.startsWith('__kat_')) {
      final idx = int.tryParse(stem.substring(6, stem.length - 2)) ?? 0;
      if (idx >= _kategorien.length) return _buildEmptySlot();
      final kat = _kategorien[idx];
      final resolvedPath = state.assetResolver.isReady
          ? state.assetResolver.resolve('${kat.symbolWord}.jpg')
          : null;
      return NasiraGridCell(
        caption: kat.label,
        assetPath: resolvedPath,
        symbolWord: resolvedPath == null ? kat.symbolWord : null,
        icon: kat.icon,
        backgroundColor: _activeKey == kat.label
            ? NasiraColors.navGreen
            : NasiraColors.moduleDarkGreen,
        textColor: Colors.white,
        fontSize: 10,
      );
    }

    if (stem.startsWith('__item_')) {
      final slotIdx = int.tryParse(stem.substring(7, stem.length - 2)) ?? 0;
      if (slotIdx >= items.length) return _buildEmptySlot();
      final item = items[slotIdx];
      final resolvedPath = state.assetResolver.isReady
          ? state.assetResolver.resolve('$item.jpg')
          : null;
      if (_activeKey == '123') {
        return Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          elevation: 2,
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Text(item,
                    style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w400,
                        color: NasiraColors.textDark)),
              ),
            ),
          ),
        );
      }
      return NasiraGridCell(
        caption: item,
        assetPath: resolvedPath,
        symbolWord: resolvedPath == null ? item : null,
        backgroundColor: NasiraColors.cellWhite,
        textColor: NasiraColors.textDark,
        fontSize: 11,
        borderRadius: 10,
      );
    }

    if (stem == '__nav_fwd__') return _buildNavCell(forward: true);
    if (stem == '__nav_bak__') return _buildNavCell(forward: false);

    return _buildEmptySlot();
  }

  // ── Modifier-Kachel ───────────────────────────────────────────────────────

  Widget _buildModifierCell(String key, IconData icon) {
    final active = _activeKey == key;
    return NasiraGridCell(
      caption: key,
      icon: icon,
      backgroundColor: active ? NasiraColors.navGreen : NasiraColors.moduleDarkGreen,
      textColor: Colors.white,
      fontSize: 11,
      onTap: () => _activate(key),
    );
  }

  // ── Kategorie-Kachel ──────────────────────────────────────────────────────

  Widget _buildCatCell(int katIdx, NasiraAppState state, NasiraData? data) {
    final kat = _kategorien[katIdx];

    // Freies Schreiben → navigiert zum gleichnamigen Modul
    if (kat.label == 'Freies Schreiben') {
      return NasiraGridCell(
        caption: kat.label,
        icon: kat.icon,
        backgroundColor: NasiraColors.moduleDarkGreen,
        textColor: Colors.white,
        fontSize: 10,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const FreiesSchreibenScreen()),
        ),
      );
    }

    final isActive = _activeKey == kat.label;
    final sym  = data != null ? state.cachedLookup(data, kat.symbolWord) : null;
    final path = sym != null
        ? state.assetResolver.resolveForSymbol(sym)
        : (state.assetResolver.isReady
            ? state.assetResolver.resolve('${kat.symbolWord}.jpg')
            : null);
    return NasiraGridCell(
      caption: kat.label,
      assetPath: path,
      symbolWord: path == null ? kat.symbolWord : null,
      icon: kat.icon,
      backgroundColor: isActive ? NasiraColors.navGreen : NasiraColors.moduleDarkGreen,
      textColor: Colors.white,
      fontSize: 10,
      onTap: () => _activate(kat.label),
    );
  }

  // ── Artikel-Kachel ────────────────────────────────────────────────────────

  Widget _buildItemCell(String item, NasiraAppState state, NasiraData? data) {
    if (_activeKey == '123') return _buildNumberCell(item, state);

    final sym  = data != null ? state.cachedLookup(data, item) : null;
    final path = sym != null
        ? state.assetResolver.resolveForSymbol(sym)
        : (state.assetResolver.isReady
            ? state.assetResolver.resolve('$item.jpg')
            : null);
    return NasiraGridCell(
      caption: item,
      assetPath: path,
      symbolWord: path == null ? item : null,
      backgroundColor: NasiraColors.cellWhite,
      textColor: NasiraColors.textDark,
      fontSize: 11,
      borderRadius: 10,
      onTap: () => state.insertPhrase(item),
    );
  }

  Widget _buildNumberCell(String number, NasiraAppState state) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      elevation: 2,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => state.insertPhrase(number),
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                number,
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w400,
                  color: NasiraColors.textDark,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Weitere Vorhersagen ───────────────────────────────────────────────────

  Widget _buildNavCell({required bool forward}) {
    final canGo = forward ? _canGoForward : _canGoBack;
    const enabledBg   = Color(0xFFB8D4B0);
    const disabledBg  = Color(0xFF2A3A2A);
    const enabledFg   = Color(0xFF2E4529);
    const disabledFg  = Colors.white24;

    final bg = canGo ? enabledBg : disabledBg;
    final fg = canGo ? enabledFg : disabledFg;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(8),
      elevation: 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: canGo ? (forward ? _nextPage : _prevPage) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.center,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
              Text(
                'Weitere\nVorhersagen',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 9,
                  color: fg,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: forward
                    ? [
                        _navDot(fg), const SizedBox(width: 3),
                        _navDot(fg), const SizedBox(width: 3),
                        Icon(Icons.play_arrow_rounded, size: 24, color: fg),
                      ]
                    : [
                        Transform.scale(
                          scaleX: -1,
                          child: Icon(Icons.play_arrow_rounded, size: 24, color: fg),
                        ),
                        const SizedBox(width: 3),
                        _navDot(fg), const SizedBox(width: 3),
                        _navDot(fg),
                      ],
              ),
            ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _navDot(Color color) => Container(
    width: 8, height: 8,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );

  void _nextPage() { if (_canGoForward) setState(() => _page++); }
  void _prevPage() { if (_canGoBack)    setState(() => _page--); }

  // ── Leer-Kachel ──────────────────────────────────────────────────────────

  Widget _buildEmptySlot() => Container(
    decoration: BoxDecoration(
      color: const Color(0xFF1E2E1E),
      borderRadius: BorderRadius.circular(8),
    ),
  );
}
