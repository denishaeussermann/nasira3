import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../nasira_app_state.dart';
import '../nasira_repository.dart';
import '../theme/nasira_colors.dart';
import '../widgets/composite_symbol.dart';
import '../widgets/nasira_grid_cell.dart';
import '../widgets/nasira_keyboard.dart';
import '../widgets/nasira_module_header.dart';

// ── Freies Schreiben ────────────────────────────────────────────────────────
//
// Layout:
//   NasiraModuleHeader
//   Row: [3-Reihen-Kategorie-Grid (horizontal scrollbar)] | [Toggle + Vorlesen]
//   — Tastatur-Modus: Vorhersage-Streifen + NasiraKeyboard
//   — Symbol-Modus:   (Satz-Vorschau) + Suchfeld + Symbol-Grid

class FreiesSchreibenScreen extends StatefulWidget {
  const FreiesSchreibenScreen({super.key});

  @override
  State<FreiesSchreibenScreen> createState() => _FreiesSchreibenScreenState();
}

class _FreiesSchreibenScreenState extends State<FreiesSchreibenScreen> {
  final TextEditingController _suchController = TextEditingController();
  final FocusNode _textFocusNode = FocusNode();

  String _selectedCategory = 'Alle';
  bool _symbolModus = false;

  // Bessere Suchwörter für Kategorie-Namen die keinen Direkt-Treffer haben
  static const _catHint = <String, String>{
    'arzt_gesundheit':                 'Gesundheit',
    'behaelter_taschen':               'Tasche',
    'buch_zeitung':                    'Buch',
    'buchstaben_schreiben':            'schreiben',
    'buero_basteln':                   'basteln',
    'didaktikmaterial':                'Schule',
    'eigenschaften_emotionen':         'glücklich',
    'fantasie':                        'vorstellen',
    'farben_formen':                   'Farben',
    'flaggen':                         'Fahne',
    'fragewoerter':                    'Fragen',
    'fragewörter':                     'Fragen',
    'geografie':                       'Landschaft',
    'hausarbeit':                      'putzen',
    'kleidung_accessoires':            'Kleidung',
    'kleine_worte':                    'und',
    'kleinewörter':                    'und',
    'koerperpflege':                   'waschen',
    'konversation_interaktion':        'sprechen',
    'lebensmittel_essen':              'Essen',
    'lebensmittel_trinken':            'trinken',
    'liebe_sexualitaet':               'Liebe',
    'lieder_bis_weihnachten':          'singen',
    'lieder_haende_auf_reisen':        'singen',
    'lieder_haeuptling_sprechende_hand': 'singen',
    'lieder_mit_den_haenden':          'singen',
    'musik':                           'Musik',
    'pfeile_funktionen':               'Pfeil',
    'pronomenartikel':                 'der',
    'raumschilder':                    'Tür',
    'raumschilder_tuer':               'Tür',
    'schule_foerdereinrichtung':       'Schule',
    'sonstiges':                       'verschiedenes',
    'stadt_verkehr':                   'Auto',
    'tv_audio_foto':                   'Fernseher',
    'urlaub_spass':                    'Urlaub',
    'verben':                          'spielen',
    'werkzeug_werkstatt':              'Werkzeug',
    'wetter_himmel':                   'Wetter',
    'zahlen_rechnen':                  'Zahlen',
    'zeit_alternativsymbole':          'Zeit',
  };

  @override
  void initState() {
    super.initState();
    _suchController.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _textFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _suchController.dispose();
    _textFocusNode.dispose();
    super.dispose();
  }

  // ── Toggle: Tastatur ↔ Symbole ────────────────────────────────────────────
  //
  // Beim Aufklappen wird die Kategorie automatisch auf das zuletzt eingetippte
  // Wort gesetzt. Ist das Feld leer, bleibt "Alle" aktiv.

  void _toggleModus(NasiraAppState state, NasiraData data) {
    if (!_symbolModus) {
      final text = state.textController.text.trim();
      if (text.isEmpty) {
        _selectedCategory = 'Alle';
      } else {
        final lastWord = text.split(RegExp(r'\s+')).last;
        final sym = state.cachedLookup(data, lastWord);
        if (sym != null) {
          final cat = sym.symbol.category;
          _selectedCategory = data.mappedCategories.contains(cat)
              ? cat
              : (data.mappedCategories.isNotEmpty
                  ? data.mappedCategories.first
                  : 'Alle');
        } else {
          _selectedCategory = data.mappedCategories.isNotEmpty
              ? data.mappedCategories.first
              : 'Alle';
        }
      }
    }
    setState(() => _symbolModus = !_symbolModus);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final state = context.watch<NasiraAppState>();
    return FutureBuilder<NasiraLoadResult>(
      future: state.futureLoad,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            backgroundColor: NasiraColors.keyboardBg,
            body: Center(
                child: CircularProgressIndicator(color: Colors.white)),
          );
        }
        if (snapshot.hasError) {
          return Scaffold(
            backgroundColor: NasiraColors.keyboardBg,
            body: Center(
                child: Text('Fehler: ${snapshot.error}',
                    style: const TextStyle(color: Colors.white))),
          );
        }

        final data = snapshot.data!.data;
        final text = state.textController.text.trim();
        final suggestions = state.suggestions.isEmpty
            ? data.initialSuggestions(limit: 14)
            : state.suggestions;

        // "Alle" nur einblenden wenn Schreibfeld leer ist
        final cats = [
          if (text.isEmpty) 'Alle',
          ...data.mappedCategories,
        ];

        return Scaffold(
          backgroundColor: NasiraColors.keyboardBg,
          body: SafeArea(
            child: Column(
              children: [
                // ── Kopfzeile ────────────────────────────────────────────
                NasiraModuleHeader(
                  controller: state.textController,
                  accentColor: NasiraColors.navGreen,
                  onBack: () => Navigator.pop(context),
                  focusNode: _textFocusNode,
                  readOnly: false,
                  autofocus: true,
                ),

                // ── Toggle-Streifen (immer) ──────────────────────────────
                _buildToggleStrip(state, data),

                // ── Kategorie-Grid (nur Symbol-Modus) ────────────────────
                if (_symbolModus) _buildCategoryGrid(state, data, cats),

                // ── Vorhersage-Streifen (nur Tastatur-Modus) ─────────────
                if (!_symbolModus)
                  _buildPredictionStrip(state, data, suggestions),

                // ── Satz-Vorschau (Symbol-Modus, Text vorhanden) ──────────
                if (_symbolModus && text.isNotEmpty)
                  _buildSatzVorschau(state, data, text),

                // ── Suchfeld (Symbol-Modus) ───────────────────────────────
                if (_symbolModus) _buildSearchField(),

                // ── Symbol-Grid oder Tastatur ────────────────────────────
                if (_symbolModus)
                  Expanded(child: _buildSymbolGrid(state, data))
                else
                  NasiraKeyboard(
                    controller: state.textController,
                    textFocusNode: _textFocusNode,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Toggle-Streifen (immer sichtbar, schmal) ─────────────────────────────

  Widget _buildToggleStrip(NasiraAppState state, NasiraData data) {
    return SizedBox(
      height: 52,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _buildToggleButton(state, data)),
          const SizedBox(width: 2),
          SizedBox(width: 76, child: _buildVorlesenButton(state)),
        ],
      ),
    );
  }

  // ── Kategorie-Grid (nur Symbol-Modus, 3 Spalten, vertikal scrollbar) ──────

  Widget _buildCategoryGrid(
      NasiraAppState state, NasiraData data, List<String> cats) {
    return SizedBox(
      height: 200,
      child: GridView.builder(
        padding: const EdgeInsets.all(4),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 82,
          crossAxisSpacing: 4,
          mainAxisSpacing: 4,
          childAspectRatio: 1.15,
        ),
        itemCount: cats.length,
        itemBuilder: (ctx, i) => _buildCatChip(state, data, cats[i]),
      ),
    );
  }

  // ── Kategorie-Chip ────────────────────────────────────────────────────────

  Widget _buildCatChip(
      NasiraAppState state, NasiraData data, String cat) {
    final isSelected = _selectedCategory == cat;
    final lookupWord = _catHint[cat.toLowerCase()] ?? cat;
    final sym = state.cachedLookup(data, lookupWord);
    final path =
        sym != null ? state.assetResolver.resolveForSymbol(sym) : null;

    return Material(
      color: isSelected
          ? NasiraColors.navGreen
          : NasiraColors.moduleDarkGreen,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => setState(() => _selectedCategory = cat),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(3, 3, 3, 2),
          child: Column(
            children: [
              Expanded(
                child: path != null
                    ? Image.asset(path,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Icon(
                            Icons.category_outlined,
                            color: Colors.white54,
                            size: 18))
                    : const Icon(Icons.category_outlined,
                        color: Colors.white54, size: 18),
              ),
              Text(
                cat,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 8,
                  color: isSelected ? Colors.white : Colors.white70,
                  fontWeight: FontWeight.w700,
                  height: 1.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Toggle-Button (Symbole auf-/zuklappen) ────────────────────────────────

  Widget _buildToggleButton(NasiraAppState state, NasiraData data) {
    return Material(
      color: NasiraColors.navGreen,
      child: InkWell(
        onTap: () => _toggleModus(state, data),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  Icons.data_usage_rounded,
                  size: 28,
                  color: Colors.white.withAlpha(200),
                ),
                Icon(
                  _symbolModus ? Icons.remove : Icons.add,
                  size: 14,
                  color: Colors.white,
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              _symbolModus ? 'Einklappen' : 'Ausklappen',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Vorlesen-Button ───────────────────────────────────────────────────────

  Widget _buildVorlesenButton(NasiraAppState state) {
    return Material(
      color: NasiraColors.navGreen,
      child: InkWell(
        onTap: () {
          // TODO: TTS-Integration
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Vorlesen nicht verfügbar'),
            duration: Duration(seconds: 2),
          ));
        },
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.volume_up_rounded, color: Colors.white, size: 28),
            SizedBox(height: 4),
            Text(
              'Vorlesen',
              style: TextStyle(
                color: Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Vorhersage-Streifen ───────────────────────────────────────────────────

  Widget _buildPredictionStrip(
      NasiraAppState state, NasiraData data, List<WordEntry> suggestions) {
    return Container(
      height: 88,
      color: NasiraColors.keyboardBg,
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        separatorBuilder: (_, __) => const SizedBox(width: 4),
        itemCount: suggestions.length.clamp(0, 14),
        itemBuilder: (context, i) {
          if (i >= suggestions.length) return const SizedBox.shrink();
          return _buildPredictionCell(state, data, suggestions[i]);
        },
      ),
    );
  }

  Widget _buildPredictionCell(
      NasiraAppState state, NasiraData data, WordEntry word) {
    final mapped = state.cachedLookup(data, word.text);
    final assetPath =
        mapped != null ? state.assetResolver.resolveForSymbol(mapped) : null;
    final plural = state.isPlural(word.text);

    return SizedBox(
      width: 76,
      child: Material(
        color: NasiraColors.fsPrediction,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => state.insertWord(data, word),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(3, 4, 3, 3),
            child: Column(
              children: [
                Expanded(
                  child: Center(
                    child: CompositeSymbolWidget(
                      assetPath1: assetPath,
                      isPlural: plural,
                      fallbackText: word.text,
                      size: 48,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  word.text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: NasiraColors.fsPredictionText,
                    height: 1.0,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Satz-Vorschau ─────────────────────────────────────────────────────────

  Widget _buildSatzVorschau(
      NasiraAppState state, NasiraData data, String text) {
    final tokens = text
        .trim()
        .split(RegExp(r'\s+'))
        .where((t) => t.trim().isNotEmpty && t.length >= 2)
        .toList();
    if (tokens.isEmpty) return const SizedBox.shrink();

    return Container(
      height: 76,
      color: NasiraColors.startseite,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        separatorBuilder: (_, __) => const SizedBox(width: 4),
        itemCount: tokens.length,
        itemBuilder: (context, i) {
          final token = tokens[i];
          final sym = state.cachedLookup(data, token);
          final path =
              sym != null ? state.assetResolver.resolveForSymbol(sym) : null;
          final plural = state.isPlural(token);
          return SizedBox(
            width: 58,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 46,
                  child: CompositeSymbolWidget(
                    assetPath1: path,
                    isPlural: plural,
                    fallbackText: token,
                    size: 40,
                  ),
                ),
                Text(
                  token,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 9,
                    color: Colors.white70,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ── Suchfeld ──────────────────────────────────────────────────────────────

  Widget _buildSearchField() {
    return Container(
      color: NasiraColors.startseite,
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
      child: TextField(
        controller: _suchController,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          filled: true,
          fillColor: NasiraColors.navGreen,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide.none,
          ),
          hintText: 'Symbol suchen …',
          hintStyle: TextStyle(color: Colors.white.withAlpha(150)),
          prefixIcon:
              const Icon(Icons.search, color: Colors.white70, size: 20),
          suffixIcon: _suchController.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close,
                      color: Colors.white70, size: 18),
                  onPressed: () => _suchController.clear(),
                ),
        ),
      ),
    );
  }

  // ── Symbol-Grid ───────────────────────────────────────────────────────────

  Widget _buildSymbolGrid(NasiraAppState state, NasiraData data) {
    final mapped = data.filteredMappedSymbols(
      category: _selectedCategory,
      search: _suchController.text,
    );
    return Container(
      color: NasiraColors.gridDark,
      child: GridView.builder(
        padding: const EdgeInsets.all(6),
        itemCount: mapped.length,
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 120,
          crossAxisSpacing: 6,
          mainAxisSpacing: 6,
          childAspectRatio: 0.85,
        ),
        itemBuilder: (context, i) =>
            _buildSymbolKachel(state, data, mapped[i]),
      ),
    );
  }

  Widget _buildSymbolKachel(
      NasiraAppState state, NasiraData data, MappedSymbol item) {
    final assetPath = state.assetResolver.resolveForSymbol(item);
    return NasiraGridCell(
      caption: item.word.text,
      assetPath: assetPath,
      backgroundColor: NasiraColors.cellWhite,
      textColor: NasiraColors.textDark,
      fontSize: 10,
      borderRadius: 10,
      onTap: () => state.insertWord(data, item.word),
    );
  }
}
