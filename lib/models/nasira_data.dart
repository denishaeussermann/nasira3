import '../core/text_normalizer.dart';
import 'word_entry.dart';
import 'symbol_entry.dart';
import 'word_symbol_mapping.dart';
import 'mapped_symbol.dart';
import 'search_result.dart';

/// Zentraler Datencontainer für Nasira.
///
/// Hält die drei Grundlisten (Wörter, Symbole, Mappings) und baut
/// daraus verschiedene Lookup-Indizes für schnelle Suche auf.
///
/// Die Normalisierungs- und Such-Logik lebt aktuell noch hier,
/// wird aber in Schritt 3 in separate Services extrahiert.
class NasiraData {
  final List<WordEntry> words;
  final List<SymbolEntry> symbols;
  final List<WordSymbolMapping> mappings;

  NasiraData({
    required this.words,
    required this.symbols,
    required this.mappings,
  });

  // ── Lookup-Indizes (lazy) ─────────────────────────────────────────────

  late final Map<String, WordEntry> _wordById = {
    for (final w in words) w.id: w,
  };

  late final Map<String, SymbolEntry> _symbolById = {
    for (final s in symbols) s.id: s,
  };

  late final Map<String, WordEntry> _wordByNormalizedText = {
    for (final w in words) normalize(w.text): w,
  };

  late final List<MappedSymbol> _mappedSymbols = _buildMappedSymbols();

  late final Map<String, MappedSymbol> _mappedByNormalizedWord = {
    for (final m in _mappedSymbols) normalize(m.word.text): m,
  };

  late final Map<String, MappedSymbol> _mappedByFileName = {
    for (final m in _mappedSymbols)
      normalize(_stripExtension(m.symbol.fileName)): m,
  };

  late final Map<String, MappedSymbol> _mappedByStrippedWord = {
    for (final m in _mappedSymbols) strip(m.word.text): m,
  };

  // ── Öffentliche Zugriffe ──────────────────────────────────────────────

  WordEntry? wordById(String id) => _wordById[id];
  SymbolEntry? symbolById(String id) => _symbolById[id];

  List<MappedSymbol> get mappedSymbols => _mappedSymbols;

  List<String> get mappedCategories {
    final set = <String>{};
    for (final m in _mappedSymbols) {
      final cat = m.symbol.category.trim();
      if (cat.isNotEmpty) set.add(cat);
    }
    return set.toList()..sort();
  }

  // ── Normalisierung ────────────────────────────────────────────────────

  /// Stufe 1: Kleinschreibung + Umlaute auflösen (NFC + NFD sicher).
  static String normalize(String input) => TextNormalizer.normalize(input);

  /// Stufe 2: Zusätzlich alle Nicht-Buchstaben/Ziffern entfernen.
  static String strip(String input) => TextNormalizer.strip(input);

  // ── Symbolsuche mit 4-stufiger Fallback-Kette ────────────────────────

  /// Sucht nur exakte Treffer (Stufe 1–3), OHNE Präfix-Fallback.
  ///
  /// Wird vom SymbolLookupService genutzt, um vor der Alias-Prüfung
  /// nur echte Treffer zu finden — Präfix kommt erst danach.
  SearchResult searchSymbolExact(String query) {
    final normalized = normalize(query);

    // Stufe 1: normalisierter Exakt-Treffer
    final exact = _mappedByNormalizedWord[normalized];
    if (exact != null) {
      return _toResult(query, normalized, exact, SearchMatchType.exact, 1.0);
    }

    // Stufe 2: Dateiname-Treffer
    final fileMatch = _mappedByFileName[normalized];
    if (fileMatch != null) {
      return _toResult(
          query, normalized, fileMatch, SearchMatchType.fileName, 0.8);
    }

    // Stufe 3: gestrippter Exakt-Treffer
    final stripped = strip(query);
    final strippedMatch = _mappedByStrippedWord[stripped];
    if (strippedMatch != null) {
      return _toResult(
          query, normalized, strippedMatch, SearchMatchType.stripped, 0.6);
    }

    return SearchResult.empty(query, normalizedQuery: normalized);
  }

  /// Sucht das passende Symbol für ein Wort (alle 4 Stufen).
  ///
  /// Fallback-Kette:
  /// 1. Normalisierter Exakt-Treffer
  /// 2. Dateiname-Treffer
  /// 3. Gestrippter Exakt-Treffer
  /// 4. Präfix-Treffer (ab 4 Zeichen, max. 3 Zeichen länger)
  SearchResult searchSymbol(String query) {
    final normalized = normalize(query);

    // Stufe 1: normalisierter Exakt-Treffer
    final exact = _mappedByNormalizedWord[normalized];
    if (exact != null) {
      return _toResult(query, normalized, exact, SearchMatchType.exact, 1.0);
    }

    // Stufe 2: Dateiname-Treffer
    final fileMatch = _mappedByFileName[normalized];
    if (fileMatch != null) {
      return _toResult(
          query, normalized, fileMatch, SearchMatchType.fileName, 0.8);
    }

    // Stufe 3: gestrippter Exakt-Treffer
    final stripped = strip(query);
    final strippedMatch = _mappedByStrippedWord[stripped];
    if (strippedMatch != null) {
      return _toResult(
          query, normalized, strippedMatch, SearchMatchType.stripped, 0.6);
    }

    // Stufe 4: Präfix-Treffer (ab 4 Zeichen, max. 3 länger)
    if (normalized.length >= 4) {
      MappedSymbol? best;
      int bestLen = 999;

      for (final entry in _mappedByNormalizedWord.entries) {
        if (entry.key.startsWith(normalized) &&
            entry.key.length < bestLen &&
            entry.key.length - normalized.length <= 3) {
          best = entry.value;
          bestLen = entry.key.length;
        }
      }

      if (best != null) {
        return _toResult(
            query, normalized, best, SearchMatchType.prefix, 0.4);
      }
    }

    return SearchResult.empty(query, normalizedQuery: normalized);
  }

  /// Legacy-Kompatibilität: gibt MappedSymbol? zurück.
  MappedSymbol? mappedSymbolForWord(String word) {
    final result = searchSymbol(word);
    if (!result.hasMatch) return null;

    // Treffer aus dem Index zurückgeben
    final normalized = normalize(word);
    return _mappedByNormalizedWord[normalized] ??
        _mappedByFileName[normalized] ??
        _mappedByStrippedWord[strip(word)];
  }

  /// Legacy-Kompatibilität: gibt SymbolEntry? zurück.
  SymbolEntry? symbolForWord(String word) {
    return mappedSymbolForWord(word)?.symbol;
  }

  // ── Vorschlagslogik ───────────────────────────────────────────────────

  List<WordEntry> initialSuggestions({int limit = 14}) {
    final sorted = [...words]..sort((a, b) => a.rank.compareTo(b.rank));
    return sorted.take(limit).toList();
  }

  List<WordEntry> searchByPrefix(String prefix, {int limit = 14}) {
    final normalized = normalize(prefix);
    if (normalized.isEmpty) return initialSuggestions(limit: limit);

    final exactMatches = <WordEntry>[];
    final prefixMatches = <WordEntry>[];

    for (final w in words) {
      final key = normalize(w.text);
      if (key == normalized) {
        exactMatches.add(w);
      } else if (normalized.length >= 3 && key.startsWith(normalized)) {
        prefixMatches.add(w);
      }
    }

    exactMatches.sort((a, b) => a.rank.compareTo(b.rank));
    prefixMatches.sort((a, b) => a.rank.compareTo(b.rank));

    return [...exactMatches, ...prefixMatches].take(limit).toList();
  }

  List<WordEntry> nextWordSuggestions(String previousWord, {int limit = 14}) {
    final entry = _wordByNormalizedText[normalize(previousWord)];
    if (entry == null || entry.nextWords.isEmpty) {
      return initialSuggestions(limit: limit);
    }

    final result = <WordEntry>[];
    for (final next in entry.nextWords) {
      final found = _wordByNormalizedText[normalize(next)];
      if (found != null) result.add(found);
    }

    if (result.isEmpty) return initialSuggestions(limit: limit);

    result.sort((a, b) => a.rank.compareTo(b.rank));
    return result.take(limit).toList();
  }

  // ── Filter ────────────────────────────────────────────────────────────

  /// Kategorie-Index: normalisiertes Wort → Kategorie
  late final Map<String, String> _categoryByWord = {
    for (final m in _mappedSymbols)
      normalize(m.word.text): m.symbol.category,
  };

  /// Gibt die Kategorie eines Wortes zurück (oder null).
  String? categoryForWord(String word) {
    return _categoryByWord[normalize(word)];
  }

  /// Gibt Wörter aus derselben Kategorie zurück.
  ///
  /// Nützlich für Vorschläge: "werkzeug" → hammer, säge, schraubenzieher...
  List<WordEntry> wordsInSameCategory(String word, {int limit = 14}) {
    final category = categoryForWord(word);
    if (category == null) return [];

    final wordNorm = normalize(word);
    final result = <WordEntry>[];

    for (final m in _mappedSymbols) {
      if (m.symbol.category == category && normalize(m.word.text) != wordNorm) {
        result.add(m.word);
      }
    }

    result.sort((a, b) => a.rank.compareTo(b.rank));
    return result.take(limit).toList();
  }

  List<MappedSymbol> filteredMappedSymbols({
    String? category,
    String search = '',
  }) {
    final normalizedSearch = normalize(search);

    return _mappedSymbols.where((item) {
      final categoryOk = category == null ||
          category == 'Alle' ||
          item.symbol.category == category;

      final searchOk = normalizedSearch.isEmpty ||
          normalize(item.word.text).contains(normalizedSearch) ||
          normalize(item.symbol.label).contains(normalizedSearch);

      return categoryOk && searchOk;
    }).toList();
  }

  // ── Interna ───────────────────────────────────────────────────────────

  List<MappedSymbol> _buildMappedSymbols() {
    final result = <MappedSymbol>[];

    for (final mapping in mappings) {
      final word = _wordById[mapping.wordId];
      final symbol = _symbolById[mapping.symbolId];
      if (word != null && symbol != null) {
        result.add(MappedSymbol(word: word, symbol: symbol));
      }
    }

    result.sort((a, b) {
      final catCmp = a.symbol.category.compareTo(b.symbol.category);
      if (catCmp != 0) return catCmp;
      final rankCmp = a.word.rank.compareTo(b.word.rank);
      if (rankCmp != 0) return rankCmp;
      return a.word.text.compareTo(b.word.text);
    });

    return result;
  }

  SearchResult _toResult(
    String query,
    String normalized,
    MappedSymbol mapped,
    SearchMatchType type,
    double score,
  ) {
    return SearchResult(
      query: query,
      normalizedQuery: normalized,
      matchedWord: mapped.word.text,
      assetPath: mapped.symbol.assetPath,
      matchType: type,
      score: score,
      debugInfo: 'Stufe ${type.name}: "${mapped.word.text}" '
          '→ ${mapped.symbol.fileName}',
    );
  }

  static String _stripExtension(String fileName) {
    final slash = fileName.replaceAll('\\', '/').lastIndexOf('/');
    final base = slash >= 0 ? fileName.substring(slash + 1) : fileName;
    final dot = base.lastIndexOf('.');
    return dot >= 0 ? base.substring(0, dot) : base;
  }
}
