import 'package:flutter/material.dart';
import 'models/models.dart';
import 'nasira_repository.dart';
import 'services/services.dart';

// ignore_for_file: avoid_print

class NasiraAppState extends ChangeNotifier {
  final NasiraRepository _repository = NasiraRepository();
  final AssetResolverService assetResolver = AssetResolverService();
  final SearchLogService searchLog = SearchLogService();
  final CustomSentencesService customSentences = CustomSentencesService();
  final DocumentService documentService = DocumentService();
  late final SymbolLookupService symbolLookup =
      SymbolLookupService(log: searchLog);
  final SuggestionEngine suggestionEngine = SuggestionEngine();

  final TextEditingController textController = TextEditingController();
  final Map<String, MappedSymbol?> symbolCache = {};
  final Map<String, bool> _pluralCache = {};

  late Future<NasiraLoadResult> futureLoad;
  List<WordEntry> suggestions = [];
  int _suggestionVersion = 0;
  String _lastHandledText = '';

  String statusText = 'Nasira startet ...';

  NasiraAppState() {
    futureLoad = _repository.loadPreferred();
    assetResolver.loadIndex().then((_) => notifyListeners());
    textController.addListener(_handleTextChanged);
    customSentences.load();
    documentService.load();
  }

  // ── Symbol-Cache & Lookup ─────────────────────────────────────────────

  void clearSymbolCache() {
    symbolCache.clear();
    _pluralCache.clear();
  }

  /// Gibt `true` zurück, wenn [word] als Plural-Form aufgelöst wurde
  /// (d. h. `SearchMatchType.stemmed` und Eingabe ≠ Grundform).
  bool isPlural(String word) {
    final key = word.toLowerCase().trim().replaceAll(RegExp(r'[^\wäöüß]'), '');
    return _pluralCache[key] ?? false;
  }

  MappedSymbol? cachedLookup(NasiraData data, String word) {
    final cacheKey =
        word.toLowerCase().trim().replaceAll(RegExp(r'[^\wäöüß]'), '');
    if (symbolCache.containsKey(cacheKey)) return symbolCache[cacheKey];

    final result = symbolLookup.lookup(data, cacheKey, silent: false);
    if (result.symbol != null && result.searchResult.score >= 0.3) {
      symbolCache[cacheKey] = result.symbol;
      _pluralCache[cacheKey] =
          result.searchResult.matchType == SearchMatchType.stemmed &&
          _isUmlautPlural(cacheKey, result.searchResult.matchedWord);
      return result.symbol;
    }

    final base = NasiraContextService.partizipToBase(cacheKey);
    if (base != null) {
      final baseResult = symbolLookup.lookup(data, base, silent: false);
      if (baseResult.symbol != null && baseResult.searchResult.score >= 0.5) {
        symbolCache[cacheKey] = baseResult.symbol;
        return baseResult.symbol;
      }
    }

    symbolCache[cacheKey] = null;
    symbolLookup.lookupWithFallback(
      data,
      cacheKey,
      silent: true,
      onEmbeddingResult: (embResult) {
        if (embResult.symbol != null) {
          symbolCache[cacheKey] = embResult.symbol;
          notifyListeners();
        }
      },
    );
    return null;
  }

  /// Gibt `true` nur wenn [inputWord] eine Umlaut-Mutation gegenüber
  /// [matchedWord] aufweist (z. B. Stühle→Stuhl, Männer→Mann).
  /// Schließt Adjektivflexion (gute→gut, vielen→viel) und
  /// Fremdwörter (super→sup, burger→burg) aus.
  static bool _isUmlautPlural(String inputWord, String matchedWord) {
    final input = inputWord.toLowerCase();
    final matched = matchedWord.toLowerCase();
    if (input == matched || matched.isEmpty) return false;

    // Umlaute im Input rückgängig machen (ä→a, ö→o, ü→u)
    final deumlauted = input
        .replaceAll('ä', 'a')
        .replaceAll('ö', 'o')
        .replaceAll('ü', 'u');

    // Kein Umlaut vorhanden → kein Umlaut-Plural
    if (deumlauted == input) return false;

    // Deumlautes Input muss dem Grundwort entsprechen (ggf. + Pluralendung)
    return deumlauted == matched ||
        deumlauted == '${matched}e' ||
        deumlauted == '${matched}en' ||
        deumlauted == '${matched}er';
  }

  // ── Text-Manipulation ─────────────────────────────────────────────────

  void insertPhrase(String phrase) {
    final current = textController.text;
    final trimmed = current.trimRight();
    final updated = trimmed.isEmpty ? '$phrase ' : '$trimmed $phrase ';
    textController.value = TextEditingValue(
      text: updated,
      selection: TextSelection.collapsed(offset: updated.length),
    );
  }

  /// Fügt ein [WordEntry] ein (ersetzt laufendes Token, wie im Freies Schreiben).
  void insertWord(NasiraData data, WordEntry word) {
    symbolLookup.lookup(data, word.text.toLowerCase().trim(), silent: false);
    final insertText =
        word.text.replaceAll(RegExp(r'(?<=[a-zA-ZäöüÄÖÜß])\d+$'), '');
    final current = textController.text;
    final updated = _replaceTrailingToken(current, insertText);
    textController.value = TextEditingValue(
      text: updated,
      selection: TextSelection.collapsed(offset: updated.length),
    );
  }

  String _replaceTrailingToken(String currentText, String newWord) {
    if (currentText.trim().isEmpty) return '$newWord ';
    final endsWithWhitespace = RegExp(r'\s$').hasMatch(currentText);
    final trimmedRight = currentText.replaceFirst(RegExp(r'\s+$'), '');
    if (endsWithWhitespace) return '$trimmedRight $newWord ';
    final lastSpace = trimmedRight.lastIndexOf(' ');
    if (lastSpace == -1) return '$newWord ';
    return '${trimmedRight.substring(0, lastSpace + 1)}$newWord ';
  }

  void deleteLastWord() {
    final text = textController.text;
    final trimmedRight = text.trimRight();
    final lastSpace = trimmedRight.lastIndexOf(' ');
    final newText =
        lastSpace == -1 ? '' : trimmedRight.substring(0, lastSpace + 1);
    textController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newText.length),
    );
  }

  /// Hängt ein einzelnes Zeichen / eine kurze Zeichenfolge direkt ans Ende an
  /// (für Freies Schreiben Tastatur: kein Leerzeichen-Padding, kein Trimmen).
  void appendLetter(String chars) {
    final current = textController.text;
    final updated = current + chars;
    textController.value = TextEditingValue(
      text: updated,
      selection: TextSelection.collapsed(offset: updated.length),
    );
  }

  /// Löscht das letzte Zeichen (Backspace).
  void deleteLastLetter() {
    final text = textController.text;
    if (text.isEmpty) return;
    final updated = text.characters.skipLast(1).string;
    textController.value = TextEditingValue(
      text: updated,
      selection: TextSelection.collapsed(offset: updated.length),
    );
  }

  void clearText() {
    textController.clear();
    clearSymbolCache();
  }

  // ── Datenverwaltung ───────────────────────────────────────────────────

  Future<void> switchToBundledData() async {
    await _repository.setPreferredSourceImported(false);
    clearSymbolCache();
    futureLoad = _repository.loadPreferred();
    suggestions = [];
    statusText = 'Eingebaute Testdaten aktiviert.';
    notifyListeners();
  }

  Future<void> switchToImportedData() async {
    await _repository.setPreferredSourceImported(true);
    clearSymbolCache();
    futureLoad = _repository.loadPreferred();
    suggestions = [];
    statusText = 'Importierte Arbeitsdaten aktiviert.';
    notifyListeners();
  }

  Future<void> reloadImportedData() async {
    await _repository.setPreferredSourceImported(true);
    clearSymbolCache();
    futureLoad = _repository.loadImported();
    suggestions = [];
    statusText = 'Importierte JSON-Dateien neu geladen.';
    notifyListeners();
  }

  // ── Suggestion-Engine ─────────────────────────────────────────────────

  Future<void> _handleTextChanged() async {
    final currentText = textController.text;
    if (currentText == _lastHandledText) return;
    _lastHandledText = currentText;

    final myVersion = ++_suggestionVersion;
    final result = await futureLoad;
    if (myVersion != _suggestionVersion) return;
    final data = result.data;
    final text = textController.text;

    final normal = suggestionEngine.computeSuggestions(data, text,
        symbolCache: symbolCache);
    final logTokens = text.trim().split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    final logCtx = logTokens.length > 2
        ? '…${logTokens.sublist(logTokens.length - 2).join(' ')}'
        : text.trim();
    debugPrint('[SUGGEST] "$logCtx" → ${normal.map((w) => w.text).join(', ')}');

    final contextTokens = text
        .split(RegExp(r'\s+'))
        .where((t) => t.length >= 2)
        .toList()
        .reversed
        .take(3)
        .toList();

    final lookupWords = <WordEntry>[];
    for (final token in contextTokens) {
      final r = symbolLookup.lookup(data, token, silent: true);
      if (r.symbol != null && r.searchResult.score >= 0.3) {
        final matchText = r.searchResult.matchedWord;
        final matchEntry = data.words
            .where((w) =>
                w.text.toLowerCase() == token.toLowerCase() ||
                w.text.toLowerCase() == matchText.toLowerCase())
            .firstOrNull;
        if (matchEntry != null) lookupWords.add(matchEntry);
      }
    }

    final allSuggestions = <WordEntry>[
      ...normal,
      ...lookupWords.where((newW) =>
          !normal.any((oldW) => oldW.text.toLowerCase() == newW.text.toLowerCase()))
    ].take(14).toList();

    if (myVersion != _suggestionVersion) return;
    suggestions = allSuggestions;
    notifyListeners();
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────

  @override
  void dispose() {
    textController.removeListener(_handleTextChanged);
    textController.dispose();
    super.dispose();
  }
}
