import 'package:flutter/material.dart';

import 'models/models.dart';
import 'nasira_context_service.dart'; // enthält NasiraImportService
import 'nasira_repository.dart';
import 'services/services.dart';

enum InputMode {
  keyboard,
  symbols,
}

class NasiraHomePage extends StatefulWidget {
  const NasiraHomePage({super.key});

  @override
  State<NasiraHomePage> createState() => _NasiraHomePageState();
}

class _NasiraHomePageState extends State<NasiraHomePage> {
  final NasiraRepository _repository = NasiraRepository();
  final AssetResolverService _assetResolver = AssetResolverService();
  final SearchLogService _searchLog = SearchLogService();
  late final SymbolLookupService _symbolLookup =
      SymbolLookupService(log: _searchLog);
  final SuggestionEngine _suggestionEngine = SuggestionEngine();

  late Future<NasiraLoadResult> _futureLoad;

  final TextEditingController _textController = TextEditingController();
  final TextEditingController _symbolSearchController = TextEditingController();
  final ScrollController _editorScrollController = ScrollController();

  InputMode _inputMode = InputMode.keyboard;
  List<WordEntry> _suggestions = [];
  bool _isImporting = false;
  String _statusText = 'Nasira startet ...';
  String _selectedCategory = 'Alle';
  int _lastLoggedTokenCount = 0;

  @override
  void initState() {
    super.initState();
    _futureLoad = _repository.loadPreferred();
    _textController.addListener(_handleTextChanged);
    _symbolSearchController.addListener(_handleSymbolSearchChanged);
    _loadAssetIndex();
  }

  @override
  void dispose() {
    _textController.removeListener(_handleTextChanged);
    _symbolSearchController.removeListener(_handleSymbolSearchChanged);
    _textController.dispose();
    _symbolSearchController.dispose();
    _editorScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadAssetIndex() async {
    try {
      await _assetResolver.loadIndex();
      if (!mounted) return;
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statusText = 'Asset-Index konnte nicht geladen werden: $e';
      });
    }
  }

  void _handleSymbolSearchChanged() {
    if (!mounted) return;
    setState(() {});
  }

  Future<NasiraData> _resolveActiveData() async {
    final result = await _futureLoad;
    return result.data;
  }

  Future<void> _handleTextChanged() async {
    final data = await _resolveActiveData();
    final text = _textController.text;

    // Log nur wenn neue Wörter abgeschlossen sind (mit Leerzeichen)
    final endsWithSpace = RegExp(r'\s$').hasMatch(text);
    if (endsWithSpace) {
      final tokens = text.trim().split(RegExp(r'\s+'))
          .where((t) => t.trim().isNotEmpty).toList();
      // Nur neue Tokens loggen
      for (var i = _lastLoggedTokenCount; i < tokens.length; i++) {
        _symbolLookup.lookup(data, tokens[i]); // verbose (logs)
      }
      _lastLoggedTokenCount = tokens.length;
    }

    final suggestions = _suggestionEngine.computeSuggestions(data, text);
    if (!mounted) return;
    setState(() {
      _suggestions = suggestions;
    });
  }

  // ── Texteingabe ───────────────────────────────────────────────────────

  String _replaceTrailingToken(String currentText, String newWord) {
    if (currentText.trim().isEmpty) return '$newWord ';
    final endsWithWhitespace = RegExp(r'\s$').hasMatch(currentText);
    final trimmedRight = currentText.replaceFirst(RegExp(r'\s+$'), '');
    if (endsWithWhitespace) return '$trimmedRight $newWord ';
    final lastSpace = trimmedRight.lastIndexOf(' ');
    if (lastSpace == -1) return '$newWord ';
    final prefix = trimmedRight.substring(0, lastSpace + 1);
    return '$prefix$newWord ';
  }

  void _insertWord(WordEntry word) {
    final updated = _replaceTrailingToken(_textController.text, word.text);
    _textController.value = TextEditingValue(
      text: updated,
      selection: TextSelection.collapsed(offset: updated.length),
    );
  }

  void _clearText() {
    _textController.clear();
    _lastLoggedTokenCount = 0;
  }

  // ── Datenverwaltung ───────────────────────────────────────────────────

  Future<void> _switchToBundledData() async {
    await _repository.setPreferredSourceImported(false);
    setState(() {
      _futureLoad = _repository.loadPreferred();
      _suggestions = [];
      _selectedCategory = 'Alle';
      _symbolSearchController.clear();
      _statusText = 'Es wurden wieder die eingebauten Testdaten aktiviert.';
    });
  }

  Future<void> _switchToImportedData() async {
    await _repository.setPreferredSourceImported(true);
    setState(() {
      _futureLoad = _repository.loadPreferred();
      _suggestions = [];
      _selectedCategory = 'Alle';
      _symbolSearchController.clear();
      _statusText = 'Die importierten Arbeitsdaten wurden aktiviert.';
    });
  }

  Future<void> _reloadImportedData() async {
    await _repository.setPreferredSourceImported(true);
    setState(() {
      _futureLoad = _repository.loadImported();
      _suggestions = [];
      _selectedCategory = 'Alle';
      _symbolSearchController.clear();
      _statusText = 'Die importierten JSON-Dateien wurden neu geladen.';
    });
  }

  Future<void> _runImport() async {
    setState(() {
      _isImporting = true;
      _statusText = 'Import läuft ...';
    });

    try {
      final report = await NasiraImportService().pickAndImport();
      if (report == null) {
        setState(() {
          _isImporting = false;
          _statusText = 'Import abgebrochen.';
        });
        return;
      }
      await _repository.setPreferredSourceImported(true);
      setState(() {
        _futureLoad = _repository.loadPreferred();
        _suggestions = [];
        _selectedCategory = 'Alle';
        _symbolSearchController.clear();
        _isImporting = false;
        _statusText =
            'Import erfolgreich: Grundwortschatz ${report.excelWordCount}, '
            'ergänzte Wörter ${report.addedWordCount}, '
            'Symbole ${report.txtSymbolCount}, '
            'Verknüpfungen ${report.mappedCount}. '
            'Arbeitsordner: ${report.exportFolder}';
      });
    } catch (e) {
      setState(() {
        _isImporting = false;
        _statusText = 'Importfehler: $e';
      });
    }
  }

  // ── Satz-Tokens ───────────────────────────────────────────────────────

  List<String> _sentenceTokens(String text) {
    return text
        .trim()
        .split(RegExp(r'\s+'))
        .where((token) => token.trim().isNotEmpty)
        .toList();
  }

  // ── Widget-Builder ────────────────────────────────────────────────────

  Widget _buildSuggestionSymbolArea(WordEntry word, MappedSymbol mapped) {
    final resolvedAssetPath = _assetResolver.resolveForSymbol(mapped);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: resolvedAssetPath == null
            ? Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.indigo.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  word.text,
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                  ),
                ),
              )
            : Image.asset(
                resolvedAssetPath,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.indigo.shade50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      word.text,
                      textAlign: TextAlign.center,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }

  Widget _buildSuggestionTextOnlyArea(WordEntry word) {
    return Container(
      width: double.infinity,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.blueGrey.shade50,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Text(
          word.text,
          textAlign: TextAlign.center,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildSuggestionTile(NasiraData data, WordEntry? word) {
    if (word == null) {
      return const Card(elevation: 1, child: SizedBox.expand());
    }

    final mapped = _symbolLookup.lookup(data, word.text, silent: true).symbol;

    return Tooltip(
      message: word.text,
      waitDuration: const Duration(milliseconds: 250),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _insertWord(word),
        child: Card(
          elevation: 1,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 6, 6, 4),
            child: Column(
              children: [
                Expanded(
                  child: mapped != null
                      ? _buildSuggestionSymbolArea(word, mapped)
                      : _buildSuggestionTextOnlyArea(word),
                ),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    word.text,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      height: 1.0,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSuggestionsGrid(NasiraData data, List<WordEntry> suggestions) {
    final tiles = List<WordEntry?>.generate(
      14,
      (index) => index < suggestions.length ? suggestions[index] : null,
    );
    return SizedBox(
      height: 270,
      child: GridView.builder(
        itemCount: tiles.length,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 7,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 0.60,
        ),
        itemBuilder: (context, index) {
          return _buildSuggestionTile(data, tiles[index]);
        },
      ),
    );
  }

  Widget _buildSourceInfo(NasiraLoadResult loadResult) {
    final color = loadResult.usingImportedData
        ? Colors.green.shade50
        : Colors.orange.shade50;
    final border = loadResult.usingImportedData
        ? Colors.green.shade200
        : Colors.orange.shade200;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Text(
        'Aktive Datenquelle: ${loadResult.sourceLabel}\n'
        'Import-Ordner: ${loadResult.importFolderPath}\n'
        'Asset-Index: ${_assetResolver.isReady ? "${_assetResolver.imageCount} Bilder gefunden" : "wird geladen ..."}\n'
        'Such-Log: ${_searchLog.summary}',
      ),
    );
  }

  Widget _buildSentenceToken(NasiraData data, String word) {
    final mapped = _symbolLookup.lookup(data, word, silent: true).symbol;
    final resolvedAssetPath =
        mapped != null ? _assetResolver.resolveForSymbol(mapped) : null;
    return SizedBox(
      width: 92,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 52,
            child: resolvedAssetPath != null
                ? Image.asset(
                    resolvedAssetPath,
                    width: 44,
                    height: 44,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      return const SizedBox(width: 44, height: 44);
                    },
                  )
                : const SizedBox(width: 44, height: 44),
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 36,
            child: Center(
              child: Text(
                word,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSentencePreview(NasiraData data) {
    final tokens = _sentenceTokens(_textController.text);
    return SizedBox(
      height: 130,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: tokens.isEmpty
            ? Center(
                child: Text(
                  'Hier erscheinen über jedem geschriebenen Wort die zugehörigen Symbole.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              )
            : SingleChildScrollView(
                child: Wrap(
                  spacing: 2,
                  runSpacing: 10,
                  children: tokens
                      .map((token) => _buildSentenceToken(data, token))
                      .toList(),
                ),
              ),
      ),
    );
  }

  Widget _buildEditorPanel(
    BuildContext context,
    NasiraData data,
    NasiraLoadResult loadResult,
    List<WordEntry> displayedSuggestions,
  ) {
    final displayedStatusText = _statusText == 'Nasira startet ...'
        ? 'Bereit. ${loadResult.sourceLabel} ist geladen.'
        : _statusText;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Scrollbar(
          controller: _editorScrollController,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _editorScrollController,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Textfeld',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SegmentedButton<InputMode>(
                      segments: const [
                        ButtonSegment(
                          value: InputMode.keyboard,
                          label: Text('Tastatur'),
                          icon: Icon(Icons.keyboard),
                        ),
                        ButtonSegment(
                          value: InputMode.symbols,
                          label: Text('Symbole'),
                          icon: Icon(Icons.grid_view),
                        ),
                      ],
                      selected: {_inputMode},
                      onSelectionChanged: (selection) {
                        setState(() {
                          _inputMode = selection.first;
                        });
                      },
                    ),
                    FilledButton.icon(
                      onPressed: _isImporting ? null : _runImport,
                      icon: const Icon(Icons.upload_file),
                      label: Text(
                        _isImporting
                            ? 'Import läuft ...'
                            : 'Excel + TXT importieren',
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: loadResult.importedDataAvailable
                          ? _reloadImportedData
                          : null,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Importierte Daten neu laden'),
                    ),
                    OutlinedButton.icon(
                      onPressed: loadResult.importedDataAvailable &&
                              !loadResult.usingImportedData
                          ? _switchToImportedData
                          : null,
                      icon: const Icon(Icons.folder_open),
                      label: const Text('Importierte Daten aktivieren'),
                    ),
                    OutlinedButton.icon(
                      onPressed: loadResult.usingImportedData
                          ? _switchToBundledData
                          : null,
                      icon: const Icon(Icons.science_outlined),
                      label: const Text('Zu Testdaten wechseln'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _clearText,
                      icon: const Icon(Icons.clear),
                      label: const Text('Text löschen'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildSourceInfo(loadResult),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.indigo.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.indigo.shade100),
                  ),
                  child: Text(displayedStatusText),
                ),
                const SizedBox(height: 16),
                Text(
                  'Satz mit Symbolen',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                _buildSentencePreview(data),
                const SizedBox(height: 12),
                SizedBox(
                  height: 260,
                  child: TextField(
                    controller: _textController,
                    readOnly: _inputMode == InputMode.symbols,
                    maxLines: null,
                    expands: true,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'Hier entsteht der Text ...',
                      alignLabelWithHint: true,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Wortvorschläge',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                _buildSuggestionsGrid(data, displayedSuggestions),
                const SizedBox(height: 12),
                Text(
                  'Wörter: ${data.words.length} | Symbole: ${data.symbols.length} | Verknüpfungen: ${data.mappings.length}',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryBar(NasiraData data) {
    final categories = ['Alle', ...data.mappedCategories];
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 120),
      child: SingleChildScrollView(
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: categories.map((category) {
            final selected = _selectedCategory == category;
            return ChoiceChip(
              label: Text(category),
              selected: selected,
              onSelected: (_) {
                setState(() {
                  _selectedCategory = category;
                });
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildSymbolTile(MappedSymbol item) {
    final resolvedAssetPath = _assetResolver.resolveForSymbol(item);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _insertWord(item.word),
      child: Card(
        elevation: 1,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            children: [
              Expanded(
                child: resolvedAssetPath != null
                    ? Image.asset(
                        resolvedAssetPath,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: Colors.indigo.shade50,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              item.word.text,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          );
                        },
                      )
                    : Container(
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.indigo.shade50,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          item.word.text,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
              ),
              const SizedBox(height: 8),
              Text(
                item.word.text,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSymbolPanel(NasiraData data) {
    final mapped = data.filteredMappedSymbols(
      category: _selectedCategory,
      search: _symbolSearchController.text,
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Symbolauswahl',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text('Nur korrekt verknüpfte Symbole werden angezeigt.'),
            const SizedBox(height: 12),
            _buildCategoryBar(data),
            const SizedBox(height: 12),
            TextField(
              controller: _symbolSearchController,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                hintText: 'Symbol oder Wort suchen ...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _symbolSearchController.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () => _symbolSearchController.clear(),
                        icon: const Icon(Icons.close),
                      ),
              ),
            ),
            const SizedBox(height: 12),
            Text('Treffer: ${mapped.length}'),
            const SizedBox(height: 12),
            Expanded(
              child: GridView.builder(
                itemCount: mapped.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 0.92,
                ),
                itemBuilder: (context, index) {
                  return _buildSymbolTile(mapped[index]);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<NasiraLoadResult>(
      future: _futureLoad,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Text('Fehler beim Laden: ${snapshot.error}'),
            ),
          );
        }
        final loadResult = snapshot.data!;
        final data = loadResult.data;
        final displayedSuggestions = _suggestions.isEmpty
            ? data.initialSuggestions(limit: 14)
            : _suggestions;

        return Scaffold(
          appBar: AppBar(title: const Text('Nasira')),
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  flex: 5,
                  child: _buildEditorPanel(
                    context,
                    data,
                    loadResult,
                    displayedSuggestions,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 4,
                  child: _buildSymbolPanel(data),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
