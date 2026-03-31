import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../nasira_app_state.dart';
import '../models/models.dart';
import '../services/grid_import_service.dart';
import '../services/grid_override_service.dart';
import '../theme/nasira_colors.dart';
import '../widgets/grid_layout_editor.dart';
import '../widgets/nasira_grid_cell.dart';
import '../widgets/nasira_text_workspace.dart';

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

// ── Hauptscreen ───────────────────────────────────────────────────────────────

class TagebuchScreen extends StatefulWidget {
  const TagebuchScreen({super.key});

  @override
  State<TagebuchScreen> createState() => _TagebuchScreenState();
}

class _TagebuchScreenState extends State<TagebuchScreen> {
  static const _startPage = 'Tagebuch 1 Wochentage 3x6';

  // ── Navigations-Stack (Seitenname-basiert, kein Enum) ──────────────────────
  final List<String> _navStack = [];
  String _currentPageName = _startPage;

  // ── Geladene Seiten (Lazy-Cache: wird bei Navigation befüllt) ──────────────
  final Map<String, GridPage> _rawPages = {}; // Rohe Seiten (nie überschrieben)
  final Map<String, GridPage> _pages = {};    // Override-angewendete Seiten
  int _wlPage = 0;

  // ── Editor ─────────────────────────────────────────────────────────────────
  bool _editorOpen = false;
  final _overrideService = GridOverrideService();
  final _importSvc = GridImportService();

  // ── Initialisierung ────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _ensurePage(_startPage);
    _overrideService.load().then((_) {
      if (mounted) setState(_refreshAllPages);
    });
  }

  /// Lädt eine Seite (falls noch nicht im Cache) und wendet Overrides an.
  GridPage? _ensurePage(String name) {
    if (_pages.containsKey(name)) return _pages[name];
    final raw = _importSvc.importPageSync(name);
    if (raw == null) {
      debugPrint('[Tagebuch] Seite nicht gefunden: $name');
      return null;
    }
    _rawPages[name] = raw;
    _pages[name] = _applyOverrideTo(name, raw);
    return _pages[name];
  }

  /// Wendet Overrides auf alle bereits gecachten Seiten neu an (nach Speichern).
  void _refreshAllPages() {
    for (final name in _pages.keys.toList()) {
      final raw = _importSvc.importPageSync(name);
      if (raw != null) _pages[name] = _applyOverrideTo(name, raw);
    }
  }

  /// Mischt GridOverrideService-Daten in eine rohe [GridPage].
  GridPage _applyOverrideTo(String name, GridPage raw) {
    final wl       = _overrideService.getWordList(name);
    final cellOv   = _overrideService.getAllCellOverrides(name);
    final layoutOv = _overrideService.getLayoutOverrides(name);
    final sizeOv   = _overrideService.getGridSize(name);

    final hasCellOv   = cellOv   != null && cellOv.isNotEmpty;
    final hasLayoutOv = layoutOv != null && layoutOv.isNotEmpty;

    if (wl == null && !hasCellOv && !hasLayoutOv && sizeOv == null) return raw;

    final cells = raw.cells.map((c) {
      final key = '${c.x},${c.y}';
      final cOv = hasCellOv   ? cellOv[key]   : null;
      final lOv = hasLayoutOv ? layoutOv[key] : null;
      if (cOv == null && lOv == null) return c;
      return GridCell(
        x:              lOv?['x']        ?? c.x,
        y:              lOv?['y']        ?? c.y,
        colSpan:        lOv?['colSpan']  ?? c.colSpan,
        rowSpan:        lOv?['rowSpan']  ?? c.rowSpan,
        caption:        (cOv?['caption']    as String?) ?? c.caption,
        symbolStem:     (cOv?['symbolStem'] as String?) ?? c.symbolStem,
        symbolCategory: c.symbolCategory,
        metacmPath:     c.metacmPath,
        localImagePath: c.localImagePath,
        iconData:       c.iconData,
        style:          c.style,
        type:           c.type,
        commands:       c.commands,
      );
    }).toList();

    return GridPage(
      name:            raw.name,
      columns:         sizeOv?['columns'] ?? raw.columns,
      rows:            sizeOv?['rows']    ?? raw.rows,
      backgroundColor: raw.backgroundColor,
      cells:           cells,
      wordList:        wl ?? raw.wordList,
    );
  }

  // ── Navigation ──────────────────────────────────────────────────────────────

  void _navigateTo(String pageName) {
    _ensurePage(pageName);
    setState(() {
      _navStack.add(_currentPageName);
      _currentPageName = pageName;
      _wlPage = 0;
    });
  }

  void _zurueck() {
    if (_navStack.isNotEmpty) {
      setState(() {
        _currentPageName = _navStack.removeLast();
        _wlPage = 0;
      });
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

  // ── Symbol-Auflösung ────────────────────────────────────────────────────────

  String? _resolveSymbol(NasiraAppState state, String? stem) {
    if (stem == null) return null;
    if (!state.assetResolver.isReady) return null;
    return state.assetResolver.resolve('$stem.jpg');
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final state = context.watch<NasiraAppState>();
    final page  = _pages[_currentPageName];

    // ── Editor-Modus ─────────────────────────────────────────────────────────
    if (_editorOpen && page != null) {
      Map<String, GridWordListItem> autoMap = {};
      final autoSlots = page.cells
          .where((c) => c.type == GridCellType.autoContent)
          .toList()
        ..sort((a, b) => a.y != b.y ? a.y.compareTo(b.y) : a.x.compareTo(b.x));
      for (int i = 0; i < autoSlots.length && i < page.wordList.length; i++) {
        autoMap['${autoSlots[i].x},${autoSlots[i].y}'] = page.wordList[i];
      }

      return Scaffold(
        backgroundColor: NasiraColors.briefBg,
        body: SafeArea(
          child: GridLayoutEditor(
            page:            page,
            rawPage:         _rawPages[_currentPageName],
            pageName:        _currentPageName,
            pageColor:       page.backgroundColor,
            overrideService: _overrideService,
            cellBuilder: (cell) {
              final wlItem = autoMap['${cell.x},${cell.y}'];
              if (wlItem != null) return _buildWordItem(state, wlItem);
              return _buildCellForEditor(state, cell);
            },
            onDismiss: () => setState(() => _editorOpen = false),
            onChanged: () => setState(() {
              _refreshAllPages();
              _wlPage = 0;
            }),
          ),
        ),
      );
    }

    // ── Normal-Modus ─────────────────────────────────────────────────────────
    return Scaffold(
      backgroundColor: NasiraColors.briefBg,
      body: SafeArea(
        child: page != null
            ? _buildExactGrid(state, page)
            : const Center(child: CircularProgressIndicator()),
      ),
    );
  }

  // ── Grid-Rendering: gesamte Seite 1:1 aus XML ────────────────────────────

  Widget _buildExactGrid(NasiraAppState state, GridPage page) {
    if (page.rows <= 0) return const SizedBox.shrink();

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
          for (final cell in workspaceCells)
            Positioned(
              left:   cell.x * cellW + gap / 2,
              top:    cell.y * cellH + gap / 2,
              width:  cell.colSpan * cellW - gap,
              height: cell.rowSpan * cellH - gap,
              child:  _buildWorkspaceCell(state),
            ),
          for (final cell in regularCells)
            Positioned(
              left:   cell.x * cellW + gap / 2,
              top:    cell.y * cellH + gap / 2,
              width:  cell.colSpan * cellW - gap,
              height: cell.rowSpan * cellH - gap,
              child:  _buildRegularCell(state, cell, page, autoContent.length),
            ),
          for (int i = 0; i < autoContent.length; i++)
            Builder(builder: (_) {
              final cell  = autoContent[i];
              final wlIdx = _wlPage * autoContent.length + i;
              final item  = wlIdx < page.wordList.length
                  ? page.wordList[wlIdx]
                  : null;
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

  Widget _buildWorkspaceCell(NasiraAppState state) => NasiraTextWorkspace(
        controller: state.textController,
        minHeight: 0,
        maxHeight: double.infinity,
      );

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
    } else if (cell.isInsertCell && cell.isNavigation) {
      // Tagebuch-Kacheln: Text einfügen UND zur nächsten Seite navigieren.
      final target = cell.jumpTarget!;
      onTap = () {
        state.insertPhrase(cell.insertText!);
        _navigateTo(target);
      };
    } else if (cell.isInsertCell) {
      onTap = () => state.insertPhrase(cell.insertText!);
    } else if (cell.isPunctuation) {
      onTap = () => state.insertPhrase(cell.punctuationChar!);
    } else if (cell.isNavigation) {
      final target = cell.jumpTarget;
      if (target != null) onTap = () => _navigateTo(target);
    }

    final displayCaption = cell.caption?.isNotEmpty == true
        ? cell.caption
        : cell.insertText?.trim();
    final useLocalPng = cell.localImagePath != null;
    final resolvedAssetPath = useLocalPng ? null : _resolveSymbol(state, cell.symbolStem);
    final fallbackWord = (useLocalPng || resolvedAssetPath != null) ? null :
        cell.symbolStem ??
        (cell.insertText != null
            ? _keyWord(cell.insertText!)
            : (displayCaption?.isNotEmpty == true
                ? _keyWord(displayCaption!)
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
      onLongPress:     onLongPress,
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

  Widget _buildWordItem(NasiraAppState state, GridWordListItem item) {
    final useCustomPng = item.localImagePath != null && item.metacmPath == null;
    final resolvedPath = useCustomPng ? null : _resolveSymbol(state, item.symbolStem);

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: NasiraColors.briefBorder, width: 1.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: NasiraGridCell(
        caption:       item.text,
        fileImagePath: useCustomPng ? item.localImagePath : null,
        assetPath:     resolvedPath,
        symbolWord:    (useCustomPng || resolvedPath != null)
            ? null
            : _keyWord(item.text),
        backgroundColor: Colors.white,
        textColor:       NasiraColors.textDark,
        fontSize:        11,
        elevation:       0,
        borderRadius:    6,
        onTap: () => state.insertPhrase(item.text),
      ),
    );
  }

  Widget _buildEmptyAutoSlot() => Container(
        decoration: BoxDecoration(
          color:        NasiraColors.briefBg,
          borderRadius: BorderRadius.circular(8),
        ),
      );

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
            : (displayCaption?.isNotEmpty == true
                ? _keyWord(displayCaption!)
                : null));

    final inner = NasiraGridCell(
      caption:         displayCaption,
      fileImagePath:   cell.localImagePath,
      assetPath:       resolvedAssetPath,
      symbolWord:      fallbackWord,
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
}
