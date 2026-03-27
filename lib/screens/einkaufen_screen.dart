import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../nasira_app_state.dart';
import '../nasira_repository.dart';
import '../models/models.dart';
import '../theme/nasira_colors.dart';
import '../widgets/nasira_grid_cell.dart';
import '../widgets/nasira_module_header.dart';
import 'freies_schreiben_screen.dart';

// ── Einkaufen ────────────────────────────────────────────────────────────────
//
// Einheitliches Grid 6 × 5 = 30 Zellen:
//   Reihen 0-2, Spalte 0   → Modifier: 123 / Einheit / Eigenschaft
//   Reihen 0-2, Spalten 1-5 → 15 Kategorien (5 × 3)
//   Reihen 3-4, Spalten 0-4 → 10 Artikel-Slots (5 × 2, paginiert)
//   Reihen 3-4, Spalte 5   → Weitere Vorhersagen (vor / zurück)

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
      ['Apfel', 'Banane', 'Kiwi', 'Mandarine', 'Orange', 'Traube', 'Zitrone',
       'Erdbeere', 'Birne', 'Melone']),
  _EinkaufKategorie('Gemüse', Icons.grass_outlined, 'Gemüse',
      ['Brokkoli', 'Gurke', 'Karotte', 'Kartoffel', 'Paprika', 'Petersilie',
       'Pilze', 'Salat', 'Tomate', 'Zucchini', 'Zwiebel']),
  _EinkaufKategorie('Fleisch und Wurst', Icons.kebab_dining_outlined, 'Fleisch',
      ['Fleisch', 'Fisch', 'Hähnchen', 'Hähnchenkeule', 'Wurst', 'Schinken',
       'Hack', 'Schnitzel', 'Rindfleisch', 'Lamm', 'Geflügel', 'Steak']),
  _EinkaufKategorie('Milchprodukte', Icons.local_cafe_outlined, 'Milch',
      ['Milch', 'Butter', 'Margarine', 'Käse', 'Joghurt', 'Quark', 'Sahne',
       'Buttermilch', 'saure Sahne', 'Schmand', 'Eis']),
  _EinkaufKategorie('Beilagen', Icons.rice_bowl_outlined, 'Nudeln',
      ['Nudeln', 'Spaghetti', 'Reis', 'Kartoffelpüree', 'Knödel', 'Linsen',
       'Spätzle']),
  // ── Reihe 1 (Spalten 1-5) ─────────────────────────────────────────────────
  _EinkaufKategorie('Backwaren', Icons.bakery_dining_outlined, 'Brot',
      ['Brot', 'Brötchen', 'Toast', 'Brezel', 'Kuchen']),
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
      ['Wasser', 'Sprudel', 'Apfelschorle', 'Apfelsaft', 'Orangensaft',
       'Tee', 'Kaffee', 'Cola', 'Fanta', 'Limonade', 'Sekt', 'Bier', 'Wein']),
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
      ['Hose', 'T-Shirt', 'Strümpfe', 'Pullover', 'Kleid', 'Rock',
       'Schlafanzug', 'Bluse', 'Hemd', 'Badeanzug', 'Badehose', 'Jacke',
       'Mantel', 'Schuhe', 'Handschuhe', 'Schal', 'Mütze']),
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

  static const _cols       = 6;
  static const _rows       = 5; // 3 Kat-Reihen + 2 Artikel-Reihen
  static const _totalCells = _cols * _rows; // 30
  static const _pageSize   = 10; // 5 Artikel-Slots × 2 Reihen

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
    return Scaffold(
      backgroundColor: NasiraColors.briefBg,
      body: SafeArea(
        child: Column(
          children: [
            NasiraModuleHeader(
              controller: state.textController,
              accentColor: NasiraColors.navGreen,
              onBack: () {
                if (_activeKey != null) {
                  setState(() { _activeKey = null; _page = 0; });
                } else {
                  Navigator.pop(context);
                }
              },
            ),
            Expanded(
              child: FutureBuilder<NasiraLoadResult>(
                future: state.futureLoad,
                builder: (ctx, snap) {
                  if (!snap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  return _buildGrid(state, snap.data!.data);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Einheitliches 6 × 5-Grid ─────────────────────────────────────────────

  Widget _buildGrid(NasiraAppState state, NasiraData data) {
    return LayoutBuilder(builder: (ctx, box) {
      const gap = 4.0;
      final cellW = (box.maxWidth  - gap * (_cols - 1) - 8) / _cols;
      final cellH = (box.maxHeight - gap * (_rows - 1) - 8) / _rows;
      final ratio = cellH > 0 ? cellW / cellH : 1.0;

      return GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(4),
        itemCount: _totalCells,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: _cols,
          crossAxisSpacing: gap,
          mainAxisSpacing: gap,
          childAspectRatio: ratio,
        ),
        itemBuilder: (ctx, i) => _cellAt(i, state, data),
      );
    });
  }

  // ── Zellen-Router ─────────────────────────────────────────────────────────

  Widget _cellAt(int i, NasiraAppState state, NasiraData data) {
    final row = i ~/ _cols;
    final col = i % _cols;

    // Modifier (Spalte 0, Reihen 0-2)
    if (col == 0 && row < 3) {
      const keys  = ['123', 'Einheit', 'Eigenschaft'];
      const icons = [Icons.tag, Icons.info_outline, Icons.tune_outlined];
      return _buildModifierCell(keys[row], icons[row]);
    }

    // Weitere Vorhersagen (Spalte 5, Reihen 3-4)
    if (col == 5 && row >= 3) {
      return _buildNavCell(forward: row == 3);
    }

    // Kategorie-Zellen (Spalten 1-5, Reihen 0-2)
    if (row < 3) {
      final katIdx = row * 5 + (col - 1);
      if (katIdx < _kategorien.length) {
        return _buildCatCell(katIdx, state, data);
      }
      return _buildEmptySlot();
    }

    // Artikel-Slots (Spalten 0-4, Reihen 3-4)
    final slotIdx = (row - 3) * 5 + col;
    final items   = _pageItems;
    if (slotIdx < items.length) {
      return _buildItemCell(items[slotIdx], state, data);
    }
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

  Widget _buildCatCell(int katIdx, NasiraAppState state, NasiraData data) {
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
    final sym  = state.cachedLookup(data, kat.symbolWord);
    final path = sym != null ? state.assetResolver.resolveForSymbol(sym) : null;
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

  Widget _buildItemCell(String item, NasiraAppState state, NasiraData data) {
    if (_activeKey == '123') return _buildNumberCell(item, state);

    final sym  = state.cachedLookup(data, item);
    final path = sym != null ? state.assetResolver.resolveForSymbol(sym) : null;
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
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
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
