import 'package:flutter/foundation.dart';

import '../models/models.dart';
import '../nasira_import_service.dart';
import '../embedding_service.dart';
import 'search_log_service.dart';

class LookupResult {
  final MappedSymbol? symbol;
  final SearchResult searchResult;

  const LookupResult({
    required this.symbol,
    required this.searchResult,
  });

  bool get hasMatch => symbol != null;
}

class SymbolLookupService {
  final SearchLogService? _log;

  SymbolLookupService({SearchLogService? log}) : _log = log;

  /// Synchron (Stufen 1–6), kein Embedding
  LookupResult lookup(NasiraData data, String rawWord, {bool silent = false}) {
    if (rawWord.contains('\\') ||
        rawWord.contains('/') ||
        rawWord.endsWith('.jpg') ||
        rawWord.endsWith('.png') ||
        rawWord.length > 50) {
      return LookupResult(
        symbol: null,
        searchResult: SearchResult.empty(rawWord),
      );
    }
    return _lookupInternal(data, rawWord, silent: silent);
  }

  /// Stufen 1–6 synchron, Stufe 7 (Embedding) NUR als
  /// automatischer Fallback wenn 1–6 versagen. Kein Blockieren!
  /// Der Aufrufer bekommt sofort das Sync-Ergebnis zurück.
  /// Bei Embedding-Treffer wird [onEmbeddingResult] aufgerufen → setState().
  void lookupWithFallback(
    NasiraData data,
    String rawWord, {
    bool silent = false,
    required void Function(LookupResult result) onEmbeddingResult,
  }) {
    if (rawWord.contains('\\') ||
        rawWord.contains('/') ||
        rawWord.endsWith('.jpg') ||
        rawWord.endsWith('.png') ||
        rawWord.length > 50) {
      return;
    }

    // Stufen 1–6 synchron
    final syncResult = _lookupInternal(data, rawWord, silent: silent);

    // Hat 1–6 einen starken Match gefunden? → fertig, kein Embedding nötig.
    // Schwache Fuzzy-Matches (Score < 0.3) blockieren Stufe 7 nicht —
    // damit z.B. "freude" (Fuzzy→"fremde" 0.2) trotzdem ein Embedding bekommt.
    if (syncResult.hasMatch && syncResult.searchResult.score >= 0.3) return;

    // Stufen 1–6 haben NICHTS gefunden → Stufe 7 als stiller Hintergrundjob
    if (rawWord.length >= 4) {
      EmbeddingService.instance.findNearestSymbolAsync(rawWord).then((embHit) {
        if (embHit == null) return;

        final embResult = data.searchSymbol(embHit);
        if (!embResult.hasMatch) return;

        if (embResult.score < 0.3) return;

        final symbol = data.mappedSymbolForWord(embResult.matchedWord) ??
            data.mappedSymbolForWord(embHit);
        if (symbol == null) return;

        final normalized = NasiraData.normalize(rawWord);
        final result = SearchResult(
          query: rawWord,
          normalizedQuery: normalized,
          matchedWord: embResult.matchedWord,
          assetPath: embResult.assetPath,
          matchType: SearchMatchType.prefix,
          score: 0.45,
          debugInfo:
              '[KI] Embedding: "$rawWord" → "$embHit" → "${embResult.matchedWord}"',
        );

        if (!silent) _log?.log(result);

        onEmbeddingResult(LookupResult(symbol: symbol, searchResult: result));
      }).catchError((e) {
        debugPrint('Embedding-Fehler bei "$rawWord": $e');
      });
    }
  }

  /// Asynchron (alt, bleibt für Kompatibilität)
  Future<LookupResult> lookupAsync(
    NasiraData data,
    String rawWord, {
    bool silent = false,
  }) async {
    if (rawWord.contains('\\') ||
        rawWord.contains('/') ||
        rawWord.endsWith('.jpg') ||
        rawWord.endsWith('.png') ||
        rawWord.length > 50) {
      final noMatch = SearchResult.empty(rawWord);
      if (!silent) _log?.log(noMatch);
      return LookupResult(symbol: null, searchResult: noMatch);
    }

    // Stufen 1–7 via _lookupInternal (inkl. Embedding-Fallback)
    return await _lookupInternalAsync(data, rawWord, silent: silent);
  }

  // ── Interne Logik (Stufen 1–6, synchron) ─────────────────────────────
  LookupResult _lookupInternal(NasiraData data, String rawWord,
      {bool silent = false}) {
    final normalized = NasiraData.normalize(rawWord);

    // Stufe 1: Exakte Suche
    final exactResult = data.searchSymbolExact(rawWord);
    if (exactResult.hasMatch) {
      final symbol = data.mappedSymbolForWord(exactResult.matchedWord) ??
          data.mappedSymbolForWord(rawWord);
      if (!silent) _log?.log(exactResult);
      return LookupResult(symbol: symbol, searchResult: exactResult);
    }

    // Stufe 2: Alias-Auflösung
    final alias = _aliases[normalized] ??
        _aliases[NasiraData.strip(rawWord)] ??
        _semanticAliases[normalized] ??
        _semanticAliases[NasiraData.strip(rawWord)];
    if (alias != null) {
      final aliasResult = data.searchSymbol(alias);
      if (aliasResult.hasMatch) {
        final symbol = data.mappedSymbolForWord(aliasResult.matchedWord) ??
            data.mappedSymbolForWord(alias);
        final result = SearchResult(
          query: rawWord,
          normalizedQuery: normalized,
          matchedWord: aliasResult.matchedWord,
          assetPath: aliasResult.assetPath,
          matchType: SearchMatchType.alias,
          score: 0.5,
          debugInfo:
              'Alias: "$rawWord" → "$alias" → "${aliasResult.matchedWord}"',
        );
        if (!silent) _log?.log(result);
        return LookupResult(symbol: symbol, searchResult: result);
      }

      final aliasSymbol = _searchInAllMappings(data, alias);
      if (aliasSymbol != null) {
        final result = SearchResult(
          query: rawWord,
          normalizedQuery: normalized,
          matchedWord: aliasSymbol.word.text,
          assetPath: aliasSymbol.symbol.assetPath,
          matchType: SearchMatchType.alias,
          score: 0.4,
          debugInfo:
              'Alias (Mapping): "$rawWord" → "$alias" → "${aliasSymbol.word.text}"',
        );
        if (!silent) _log?.log(result);
        return LookupResult(symbol: aliasSymbol, searchResult: result);
      }
    }

    // Stufe 3: Partizip-II → Grundform
    final base = NasiraContextService.partizipToBase(rawWord);
    if (base != null) {
      final baseResult = data.searchSymbol(base);
      if (baseResult.hasMatch) {
        final symbol = data.mappedSymbolForWord(base);
        final result = SearchResult(
          query: rawWord,
          normalizedQuery: normalized,
          matchedWord: baseResult.matchedWord,
          assetPath: baseResult.assetPath,
          matchType: SearchMatchType.partizip,
          score: 0.3,
          debugInfo:
              'Partizip: "$rawWord" → "$base" → "${baseResult.matchedWord}"',
        );
        if (!silent) _log?.log(result);
        return LookupResult(symbol: symbol, searchResult: result);
      }

      final baseSymbol = _searchInAllMappings(data, base);
      if (baseSymbol != null) {
        final result = SearchResult(
          query: rawWord,
          normalizedQuery: normalized,
          matchedWord: baseSymbol.word.text,
          assetPath: baseSymbol.symbol.assetPath,
          matchType: SearchMatchType.partizip,
          score: 0.25,
          debugInfo:
              'Partizip (Mapping): "$rawWord" → "$base" → "${baseSymbol.word.text}"',
        );
        if (!silent) _log?.log(result);
        return LookupResult(symbol: baseSymbol, searchResult: result);
      }

      final baseNorm = NasiraData.normalize(base);
      final baseAlias = _aliases[baseNorm] ?? _aliases[NasiraData.strip(base)];
      if (baseAlias != null) {
        final aliasResult = data.searchSymbol(baseAlias);
        if (aliasResult.hasMatch) {
          final symbol = data.mappedSymbolForWord(baseAlias);
          final result = SearchResult(
            query: rawWord,
            normalizedQuery: normalized,
            matchedWord: aliasResult.matchedWord,
            assetPath: aliasResult.assetPath,
            matchType: SearchMatchType.partizip,
            score: 0.25,
            debugInfo:
                'Partizip+Alias: "$rawWord" → "$base" → "$baseAlias" → "${aliasResult.matchedWord}"',
          );
          if (!silent) _log?.log(result);
          return LookupResult(symbol: symbol, searchResult: result);
        }
      }

      final strippedBase = _stripTrennbaresPrefix(base);
      if (strippedBase != null) {
        final stemResult = data.searchSymbol(strippedBase);
        if (stemResult.hasMatch) {
          final symbol = data.mappedSymbolForWord(strippedBase);
          final result = SearchResult(
            query: rawWord,
            normalizedQuery: normalized,
            matchedWord: stemResult.matchedWord,
            assetPath: stemResult.assetPath,
            matchType: SearchMatchType.partizip,
            score: 0.25,
            debugInfo:
                'Partizip (Stamm): "$rawWord" → "$base" → "$strippedBase" → "${stemResult.matchedWord}"',
          );
          if (!silent) _log?.log(result);
          return LookupResult(symbol: symbol, searchResult: result);
        }

        final stemSymbol = _searchInAllMappings(data, strippedBase);
        if (stemSymbol != null) {
          final result = SearchResult(
            query: rawWord,
            normalizedQuery: normalized,
            matchedWord: stemSymbol.word.text,
            assetPath: stemSymbol.symbol.assetPath,
            matchType: SearchMatchType.partizip,
            score: 0.2,
            debugInfo:
                'Partizip (Stamm-Mapping): "$rawWord" → "$base" → "$strippedBase" → "${stemSymbol.word.text}"',
          );
          if (!silent) _log?.log(result);
          return LookupResult(symbol: stemSymbol, searchResult: result);
        }
      }
    }

    // Stufe 4: Flexionsendungen entfernen
    final stemmed = _stripFlexion(normalized);
    if (stemmed != null) {
      final stemResult = data.searchSymbolExact(stemmed);
      if (stemResult.hasMatch) {
        final symbol = data.mappedSymbolForWord(stemmed);
        final result = SearchResult(
          query: rawWord,
          normalizedQuery: normalized,
          matchedWord: stemResult.matchedWord,
          assetPath: stemResult.assetPath,
          matchType: SearchMatchType.stemmed,
          score: 0.35,
          debugInfo:
              'Stemmed: "$rawWord" → "$stemmed" → "${stemResult.matchedWord}"',
        );
        if (!silent) _log?.log(result);
        return LookupResult(symbol: symbol, searchResult: result);
      }

      final stemAlias =
          _aliases[stemmed] ?? _aliases[NasiraData.strip(stemmed)];
      if (stemAlias != null) {
        final aliasResult = data.searchSymbol(stemAlias);
        if (aliasResult.hasMatch) {
          final symbol = data.mappedSymbolForWord(stemAlias);
          final result = SearchResult(
            query: rawWord,
            normalizedQuery: normalized,
            matchedWord: aliasResult.matchedWord,
            assetPath: aliasResult.assetPath,
            matchType: SearchMatchType.stemmed,
            score: 0.3,
            debugInfo:
                'Stemmed+Alias: "$rawWord" → "$stemmed" → "$stemAlias" → "${aliasResult.matchedWord}"',
          );
          if (!silent) _log?.log(result);
          return LookupResult(symbol: symbol, searchResult: result);
        }
      }
    }

    // Stufe 5: Präfix-Fallback
    final prefixResult = data.searchSymbol(rawWord);
    if (prefixResult.hasMatch) {
      final symbol = data.mappedSymbolForWord(prefixResult.matchedWord) ??
          data.mappedSymbolForWord(rawWord);
      if (!silent) _log?.log(prefixResult);
      return LookupResult(symbol: symbol, searchResult: prefixResult);
    }

    // Stufe 6: Smart Auto-Match
    final autoMatch = _smartAutoMatch(data, rawWord, normalized);
    if (autoMatch != null) {
      if (!silent) _log?.log(autoMatch.searchResult);
      return autoMatch;
    }

    // Kein Treffer aus Stufen 1–6
    final emptyResult =
        SearchResult.empty(rawWord, normalizedQuery: normalized);
    if (!silent) _log?.log(emptyResult);
    return LookupResult(symbol: null, searchResult: emptyResult);
  }

  /// Stufen 1–7 asynchron: ruft zuerst _lookupInternal (1–6),
  /// bei Misserfolg dann Stufe 7 (Embedding).
  Future<LookupResult> _lookupInternalAsync(NasiraData data, String rawWord,
      {bool silent = false}) async {
    // Stufen 1–6
    final syncResult = _lookupInternal(data, rawWord, silent: silent);
    if (syncResult.hasMatch) return syncResult;

    // Stufe 7: Embedding
    if (rawWord.length >= 4) {
      try {
        final embHit =
            await EmbeddingService.instance.findNearestSymbolAsync(rawWord);
        if (embHit != null) {
          final embResult = data.searchSymbol(embHit);
          if (embResult.hasMatch) {
            final symbol = data.mappedSymbolForWord(embResult.matchedWord) ??
                data.mappedSymbolForWord(embHit);
            if (symbol != null) {
              final normalized = NasiraData.normalize(rawWord);
              final result = SearchResult(
                query: rawWord,
                normalizedQuery: normalized,
                matchedWord: embResult.matchedWord,
                assetPath: embResult.assetPath,
                matchType: SearchMatchType.prefix,
                score: 0.45,
                debugInfo:
                    '[KI] Embedding: "$rawWord" → "$embHit" → "${embResult.matchedWord}"',
              );
              if (!silent) _log?.log(result);
              return LookupResult(symbol: symbol, searchResult: result);
            }
          }
        }
      } catch (e) {
        debugPrint('Embedding-Fehler bei "$rawWord": $e');
      }
    }

    // Kein Treffer aus Stufen 1–7
    final normalized = NasiraData.normalize(rawWord);
    final noMatch = SearchResult.empty(rawWord, normalizedQuery: normalized);
    if (!silent) _log?.log(noMatch);
    return LookupResult(symbol: null, searchResult: noMatch);
  }

  // ── Hilfsmethoden (unverändert) ───────────────────────────────────────

  bool _isPlausibleMatch(String rawWord, String matchedWord) {
    final input =
        NasiraData.normalize(rawWord).replaceAll(RegExp(r'[^a-z0-9]'), '');
    final match =
        NasiraData.normalize(matchedWord).replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (match.length <= 2) return false;
    if (match.length < input.length * 0.6) return false;
    if (input.length < match.length * 0.5) return false;
    return true;
  }

  MappedSymbol? _searchInAllMappings(NasiraData data, String word) {
    final variants = <String>{
      NasiraData.normalize(word),
      NasiraData.strip(word),
    };
    final allMapped = data.filteredMappedSymbols(category: 'Alle', search: '');
    for (final item in allMapped) {
      final candidate = NasiraData.strip(item.word.text);
      if (candidate.isEmpty) continue;
      if (variants.contains(candidate)) return item;
    }
    return null;
  }

  static String? _stripTrennbaresPrefix(String infinitiv) {
    final normalized = NasiraData.normalize(infinitiv);
    const prefixes = [
      'zurueck',
      'heraus',
      'hinaus',
      'herum',
      'herein',
      'hinein',
      'heran',
      'daran',
      'drauf',
      'raus',
      'rein',
      'fest',
      'nach',
      'heim',
      'dran',
      'auf',
      'aus',
      'ein',
      'los',
      'mit',
      'vor',
      'weg',
      'hin',
      'her',
      'rum',
      'um',
      'an',
      'ab',
      'zu',
    ];
    for (final prefix in prefixes) {
      if (normalized.startsWith(prefix) &&
          normalized.length > prefix.length + 2) {
        return normalized.substring(prefix.length);
      }
    }
    return null;
  }

  static String? _stripFlexion(String normalized) {
    final clean = normalized.replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (clean.length < 4) return null;
    const endings = ['em', 'en', 'er', 'es', 'e'];
    for (final ending in endings) {
      if (clean.endsWith(ending) && clean.length > ending.length + 2) {
        return clean.substring(0, clean.length - ending.length);
      }
    }
    return null;
  }

  LookupResult? _smartAutoMatch(
      NasiraData data, String rawWord, String normalized) {
    final clean = normalized.replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (clean.length < 3) return null;

    final stemmed = _extendedStem(clean);
    for (final stem in stemmed) {
      final result = data.searchSymbolExact(stem);
      if (result.hasMatch) {
        final candidate = _autoResult(data, rawWord, normalized, result,
            'AutoStem: "$rawWord" → "$stem"');
        if (_isPlausibleMatch(rawWord, candidate.searchResult.matchedWord)) {
          return candidate;
        }
      }
      final stemAlias = _aliases[stem];
      if (stemAlias != null) {
        final aliasResult = data.searchSymbol(stemAlias);
        if (aliasResult.hasMatch) {
          final candidate = _autoResult(data, rawWord, normalized, aliasResult,
              'AutoStem+Alias: "$rawWord" → "$stem" → "$stemAlias"');
          if (_isPlausibleMatch(rawWord, candidate.searchResult.matchedWord)) {
            return candidate;
          }
        }
      }
    }

    if (clean.length >= 6) {
      final compResult = _compoundMatch(data, rawWord, normalized, clean);
      if (compResult != null) return compResult;
    }
    if (clean.length >= 5) {
      final subResult = _substringMatch(data, rawWord, normalized, clean);
      if (subResult != null) return subResult;
    }
    if (clean.length >= 4) {
      final reverseResult =
          _reversePrefixMatch(data, rawWord, normalized, clean);
      if (reverseResult != null) return reverseResult;
    }
    if (clean.length >= 5) {
      final fuzzyResult = _fuzzyMatch(data, rawWord, normalized, clean);
      if (fuzzyResult != null) return fuzzyResult;
    }
    if (clean.length >= 5) {
      final fuzzyAliasResult =
          _fuzzyAliasMatch(data, rawWord, normalized, clean);
      if (fuzzyAliasResult != null) return fuzzyAliasResult;
    }

    return null;
  }

  static List<String> _extendedStem(String clean) {
    if (clean.length < 4) return [];
    final candidates = <String>[];
    const suffixes = [
      'ungen',
      'ieren',
      'ender',
      'sten',
      'stem',
      'ster',
      'tet',
      'ten',
      'ter',
      'tes',
      'tem',
      'ung',
      'nis',
      'keit',
      'heit',
      'lich',
      'isch',
      'bar',
      'st',
      'te',
      'et',
      'en',
      'er',
      'es',
      'em',
      't',
      'e',
      's',
      'n',
    ];
    for (final suffix in suffixes) {
      if (clean.endsWith(suffix) && clean.length > suffix.length + 2) {
        final stem = clean.substring(0, clean.length - suffix.length);
        if (stem.length >= 3 && !candidates.contains(stem)) {
          candidates.add(stem);
        }
      }
    }
    return candidates;
  }

  LookupResult? _compoundMatch(
      NasiraData data, String rawWord, String normalized, String clean) {
    const minPart = 4;
    for (int i = minPart; i <= clean.length - minPart; i++) {
      final left = clean.substring(0, i);
      final right = clean.substring(i);
      final rightResult = data.searchSymbolExact(right);
      if (rightResult.hasMatch &&
          _isPlausibleMatch(rawWord, rightResult.matchedWord)) {
        return _autoResult(data, rawWord, normalized, rightResult,
            'Kompositum: "$rawWord" → [$left|$right] → "${rightResult.matchedWord}"');
      }
      final leftResult = data.searchSymbolExact(left);
      if (leftResult.hasMatch &&
          right.length >= 4 &&
          left.length >= 4 &&
          _isPlausibleMatch(rawWord, leftResult.matchedWord)) {
        return _autoResult(data, rawWord, normalized, leftResult,
            'Kompositum (links): "$rawWord" → [$left|$right] → "${leftResult.matchedWord}"');
      }
    }
    return null;
  }

  LookupResult? _substringMatch(
      NasiraData data, String rawWord, String normalized, String clean) {
    MappedSymbol? bestMatch;
    int bestLen = 999;
    for (final m in data.mappedSymbols) {
      final symbolWord = NasiraData.normalize(m.word.text);
      if (symbolWord.startsWith(clean) &&
          symbolWord.length > clean.length &&
          symbolWord.length < bestLen &&
          _isPlausibleMatch(rawWord, m.word.text)) {
        bestMatch = m;
        bestLen = symbolWord.length;
      }
    }
    if (bestMatch == null && clean.length >= 7) {
      for (final m in data.mappedSymbols) {
        final symbolWord = NasiraData.normalize(m.word.text);
        if (symbolWord.contains(clean) &&
            symbolWord.length > clean.length &&
            symbolWord.length < bestLen &&
            _isPlausibleMatch(rawWord, m.word.text)) {
          bestMatch = m;
          bestLen = symbolWord.length;
        }
      }
    }
    if (bestMatch != null) {
      final result = SearchResult(
        query: rawWord,
        normalizedQuery: normalized,
        matchedWord: bestMatch.word.text,
        assetPath: bestMatch.symbol.assetPath,
        matchType: SearchMatchType.prefix,
        score: 0.3,
        debugInfo: 'Substring: "$rawWord" → "${bestMatch.word.text}"',
      );
      return LookupResult(symbol: bestMatch, searchResult: result);
    }
    return null;
  }

  LookupResult? _reversePrefixMatch(
      NasiraData data, String rawWord, String normalized, String clean) {
    MappedSymbol? bestMatch;
    int bestLen = 999;
    for (final m in data.mappedSymbols) {
      final symbolWord = NasiraData.normalize(m.word.text);
      if (symbolWord.startsWith(clean) &&
          symbolWord.length > clean.length &&
          symbolWord.length - clean.length <= 3 &&
          symbolWord.length < bestLen &&
          _isPlausibleMatch(rawWord, m.word.text)) {
        bestMatch = m;
        bestLen = symbolWord.length;
      }
    }
    if (bestMatch != null) {
      final result = SearchResult(
        query: rawWord,
        normalizedQuery: normalized,
        matchedWord: bestMatch.word.text,
        assetPath: bestMatch.symbol.assetPath,
        matchType: SearchMatchType.prefix,
        score: 0.35,
        debugInfo: 'AutoPrefix: "$rawWord" → "${bestMatch.word.text}"',
      );
      return LookupResult(symbol: bestMatch, searchResult: result);
    }
    return null;
  }

  LookupResult? _fuzzyMatch(
      NasiraData data, String rawWord, String normalized, String clean) {
    MappedSymbol? bestMatch;
    int bestDist = 2;
    for (final m in data.mappedSymbols) {
      final symbolWord = NasiraData.normalize(m.word.text);
      if ((symbolWord.length - clean.length).abs() > 2) continue;
      final dist = _levenshtein(clean, symbolWord);
      if (dist < bestDist && _isPlausibleMatch(rawWord, m.word.text)) {
        bestDist = dist;
        bestMatch = m;
        if (dist == 1) break;
      }
    }
    if (bestMatch != null && bestDist <= 1) {
      final result = SearchResult(
        query: rawWord,
        normalizedQuery: normalized,
        matchedWord: bestMatch.word.text,
        assetPath: bestMatch.symbol.assetPath,
        matchType: SearchMatchType.prefix,
        score: 0.2,
        debugInfo: 'Fuzzy ($bestDist): "$rawWord" → "${bestMatch.word.text}"',
      );
      return LookupResult(symbol: bestMatch, searchResult: result);
    }
    return null;
  }

  LookupResult? _fuzzyAliasMatch(
      NasiraData data, String rawWord, String normalized, String clean) {
    String? bestKey;
    String? bestTarget;
    int bestDist = 2;

    for (final entry in _semanticAliases.entries) {
      if ((entry.key.length - clean.length).abs() > 1) continue;
      final dist = _levenshtein(clean, entry.key);
      if (dist < bestDist) {
        bestDist = dist;
        bestKey = entry.key;
        bestTarget = entry.value;
        if (dist == 1) break;
      }
    }

    if (bestDist > 1) {
      for (final entry in _aliases.entries) {
        if ((entry.key.length - clean.length).abs() > 1) continue;
        final dist = _levenshtein(clean, entry.key);
        if (dist < bestDist) {
          bestDist = dist;
          bestKey = entry.key;
          bestTarget = entry.value;
          if (dist == 1) break;
        }
      }
    }

    if (bestTarget != null && bestDist <= 1) {
      final aliasResult = data.searchSymbol(bestTarget);
      if (aliasResult.hasMatch) {
        final symbol = data.mappedSymbolForWord(aliasResult.matchedWord) ??
            data.mappedSymbolForWord(bestTarget);
        final result = SearchResult(
          query: rawWord,
          normalizedQuery: normalized,
          matchedWord: aliasResult.matchedWord,
          assetPath: aliasResult.assetPath,
          matchType: SearchMatchType.alias,
          score: 0.2,
          debugInfo:
              'FuzzyAlias: "$rawWord" ~→ "$bestKey" → "$bestTarget" → "${aliasResult.matchedWord}"',
        );
        return LookupResult(symbol: symbol, searchResult: result);
      }
    }
    return null;
  }

  LookupResult _autoResult(NasiraData data, String rawWord, String normalized,
      SearchResult matchResult, String debug) {
    final symbol = data.mappedSymbolForWord(matchResult.matchedWord);
    final result = SearchResult(
      query: rawWord,
      normalizedQuery: normalized,
      matchedWord: matchResult.matchedWord,
      assetPath: matchResult.assetPath,
      matchType: SearchMatchType.prefix,
      score: 0.3,
      debugInfo: debug,
    );
    return LookupResult(symbol: symbol, searchResult: result);
  }

  static int _levenshtein(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    final la = a.length;
    final lb = b.length;
    if ((la - lb).abs() > 2) return 3;
    var prev = List<int>.generate(lb + 1, (i) => i);
    var curr = List<int>.filled(lb + 1, 0);
    for (int i = 1; i <= la; i++) {
      curr[0] = i;
      for (int j = 1; j <= lb; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        curr[j] = [
          prev[j] + 1,
          curr[j - 1] + 1,
          prev[j - 1] + cost,
        ].reduce((a, b) => a < b ? a : b);
      }
      final tmp = prev;
      prev = curr;
      curr = tmp;
    }
    return prev[lb];
  }

  // ── Semantische Wortgruppen ──────────────────────────────────────────
  static final Map<String, String> _semanticAliases = _buildSemanticAliases();

  static Map<String, String> _buildSemanticAliases() {
    final result = <String, String>{};
    const groups = <String, List<String>>{
      'gasflasche': [
        'helium',
        'wasserstoff',
        'sauerstoff',
        'stickstoff',
        'co2',
        'propan',
        'butan',
        'argon',
        'neon'
      ],
      'erdgas': ['methan', 'biogas'],
      'regen': ['niederschlag', 'schauer', 'regenschauer', 'nass'],
      'sturm': [
        'orkan',
        'hurrikan',
        'taifun',
        'tornado',
        'unwetter',
        'gewitter'
      ],
      'schnee': ['schneeflocke', 'schneesturm', 'wintereinbruch'],
      'sonne': ['sonnenschein', 'sonnig', 'heiter'],
      'traurig': [
        'deprimiert',
        'niedergeschlagen',
        'betruebt',
        'melancholisch',
        'ungluecklich'
      ],
      'froh': [
        'gluecklich',
        'erfreut',
        'heiter',
        'begeistert',
        'euphorisch',
        'zufrieden'
      ],
      'wuetend': [
        'zornig',
        'sauer',
        'aergerlich',
        'rasend',
        'aufgebracht',
        'empoert'
      ],
      'aengstlich': [
        'furchtsam',
        'veraengstigt',
        'beklommen',
        'panisch',
        'besorgt'
      ],
      'muede': ['erschoepft', 'schlaefrig', 'ermattet', 'kaputt', 'ausgelaugt'],
      'essen': ['nahrung', 'mahlzeit', 'speise', 'gericht', 'mahl'],
      'trinken': ['getraenk', 'schluck', 'fluessigkeit'],
      'brot': ['broetchen', 'toast', 'semmel', 'stulle'],
      'obst': ['frucht', 'fruechte'],
      'krank': [
        'erkrankt',
        'unwohl',
        'fieber',
        'erkaeltet',
        'erkaeltung',
        'grippe'
      ],
      'schmerzen': ['schmerz', 'wehtun', 'weh', 'aua', 'wehwehchen'],
      'arzt': ['doktor', 'mediziner', 'hausarzt', 'kinderarzt'],
      'krankenhaus': ['klinik', 'hospital', 'spital', 'notaufnahme'],
      'medikament': ['medizin', 'tablette', 'pille', 'arznei'],
      'auto': ['fahrzeug', 'wagen', 'pkw', 'automobil', 'mondauto'],
      'bus': ['omnibus', 'linienbus', 'schulbus', 'reisebus'],
      'fahrrad': ['rad', 'velo', 'drahtesel'],
      'haus': ['gebaeude', 'wohnung', 'zuhause', 'daheim', 'heim'],
      'schule': ['schulgebaeude', 'bildung', 'unterricht'],
      'kirche': ['gotteshaus', 'kapelle', 'dom', 'kathedrale'],
      'baum': ['baeume', 'gehoelz', 'stamm'],
      'blume': ['bluete', 'pflanze'],
      'wald': ['forst', 'gehoelz', 'dickicht'],
      'berg': ['gebirge', 'huegel', 'gipfel'],
      'meer': ['ozean', 'see', 'gewaesser'],
      'fluss': ['strom', 'bach', 'kanal'],
      'hund1': ['welpe', 'ruede', 'huendin'],
      'katze1': ['kaetzchen', 'mieze', 'stubentiger', 'kater'],
      'vogel': ['piepmatz', 'spatz'],
      'polizei': ['polizist', 'polizistin', 'beamter'],
      'feuerwehr': ['feuerwehrmann', 'feuerwehrfrau', 'loeschen'],
      'sprechen': [
        'reden',
        'erzaehlen',
        'sagen',
        'berichten',
        'mitteilen',
        'quatschen'
      ],
      'telefon': ['handy', 'smartphone', 'mobiltelefon', 'anruf'],
      'lesen': ['buch', 'lektuere'],
      'schreiben': ['verfassen', 'notieren', 'aufschreiben'],
      'rechnen': ['berechnen', 'mathematik', 'mathe'],
      'deutschland': ['bundesrepublik', 'brd'],
      'gesetz': ['recht', 'verordnung', 'vorschrift', 'regel'],
      'geld': ['euro', 'muenzen', 'bargeld', 'waehrung'],
    };
    for (final entry in groups.entries) {
      for (final word in entry.value) {
        result[word] = entry.key;
      }
    }
    return result;
  }

  // ── Alias-Tabelle ─────────────────────────────────────────────────────
  static const Map<String, String> _aliases = {
    // ── Nationalitäten ────────────────────────────────────────────────
    'russe': 'russlandf',
    'russin': 'russlandf',
    'russen': 'russlandf',
    'albaner': 'albanienf',
    'albanerin': 'albanienf',
    'amerikaner': 'amerikaf',
    'amerikanerin': 'amerikaf',
    'usaamerikaner': 'amerikaf',
    'nordamerikaner': 'amerikaf',
    'inder': 'indienf',
    'inderin': 'indienf',
    'indien': 'indienf',
    'grieche': 'griechenlandf',
    'griechin': 'griechenlandf',
    'franzose': 'frankreichf',
    'franzoese': 'frankreichf',
    'italiener': 'italienf',
    'italienerin': 'italienf',
    'spanier': 'spanienf',
    'spanierin': 'spanienf',
    'brite': 'grossbritannienf',
    'englaender': 'grossbritannienf',
    'pole': 'polenf',
    'polin': 'polenf',
    'tscheche': 'tschechienf',
    'oesterreicher': 'oesterreichf',
    'schweizer': 'schweizf',
    'afghane': 'afghanistanf',
    'afghanen': 'afghanistanf',
    'syrer': 'syrien',
    'syrerin': 'syrien',
    'iraker': 'irak',
    'iraqi': 'irak',
    'iraner': 'iran',
    'iranerin': 'iran',
    'tunesier': 'tunesienf',
    'marokkaner': 'marokkof',
    'tuerke': 'tuerkeif',
    'tuerkei': 'tuerkeif',
    // ── Pronomen ──────────────────────────────────────────────────────
    'sie': 'sie_einzahl',
    'ihm': 'ihr',
    'sein': 'sein1',
    'seine': 'mein',
    'seinen': 'mein',
    'seinem': 'mein',
    'seiner': 'mein',
    'seines': 'mein',
    'meine': 'mein',
    'meinen': 'mein',
    'meinem': 'mein',
    'meiner': 'mein',
    'meines': 'mein',
    'deine': 'dein',
    'deinen': 'dein',
    'deinem': 'dein',
    'deiner': 'dein',
    'deines': 'dein',
    'ihre': 'ihr',
    'ihren': 'ihr',
    'ihrem': 'ihr',
    'ihrer': 'ihr',
    'ihres': 'ihr',
    'unsere': 'unser',
    'unseren': 'unser',
    'unserem': 'unser',
    'unserer': 'unser',
    'unseres': 'unser',
    'eure': 'eure',
    'euren': 'eure',
    'eurem': 'eure',
    'eurer': 'eure',
    'eures': 'eure',
    // ── Hilfsverben ───────────────────────────────────────────────────
    'bin': 'sein1',
    'bist': 'sein1',
    'ist': 'sein1',
    'sind': 'sein1',
    'seid': 'sein1',
    'war': 'waren1',
    'waren': 'waren1',
    'waere': 'sein1',
    'hat': 'haben',
    'hast': 'haben',
    'habt': 'haben',
    'hatte': 'haben',
    'hatten': 'haben',
    'kann': 'koennen',
    'kannst': 'koennen',
    'koennt': 'koennen',
    'konnte': 'koennen',
    'konnten': 'koennen',
    'muss': 'muessen',
    'musst': 'muessen',
    'muesst': 'muessen',
    'musste': 'muessen',
    'mussten': 'muessen',
    'soll': 'sollen',
    'sollst': 'sollen',
    'sollt': 'sollen',
    'sollte': 'sollen',
    'sollten': 'sollen',
    'will': 'wollen',
    'willst': 'wollen',
    'wollt': 'wollen',
    'wollte': 'wollen',
    'wollten': 'wollen',
    'darf': 'duerfen',
    'darfst': 'duerfen',
    'duerft': 'duerfen',
    'durfte': 'duerfen',
    'durften': 'duerfen',
    'mag': 'moegen',
    'magst': 'moegen',
    'moegt': 'moegen',
    'moechte': 'moechten',
    'moechtest': 'moechten',
    'mochte': 'moechten',
    // ── Vollverben ────────────────────────────────────────────────────
    'gehe': 'gehen',
    'gehst': 'gehen',
    'geht': 'gehen',
    'ging': 'gehen',
    'gingen': 'gehen',
    'komme': 'ankommen',
    'kommst': 'ankommen',
    'komm': 'ankommen',
    'esse': 'essen1',
    'isst': 'essen1',
    'ass': 'essen1',
    'essen': 'essen1',
    'sage': 'sprechen',
    'sagst': 'sprechen',
    'sagt': 'sprechen',
    'sagte': 'sprechen',
    'sagten': 'sprechen',
    'sagen': 'sprechen',
    'siehst': 'sehen',
    'sieht': 'sehen',
    'sah': 'sehen',
    'sahen': 'sehen',
    'sehe': 'sehen',
    'tat': 'machen',
    'taten': 'machen',
    'tun': 'machen',
    'tu': 'machen',
    'tue': 'machen',
    'tust': 'machen',
    'tut': 'machen',
    'schlafen': 'schlafen1',
    'schlafe': 'schlafen1',
    'schlaefst': 'schlafen1',
    'schlaeft': 'schlafen1',
    'fahren': 'fahren1',
    'fahre': 'fahren1',
    'faehrst': 'fahren1',
    'faehrt': 'fahren1',
    'lesen': 'lesen1',
    'lese': 'lesen1',
    'liest': 'lesen1',
    'helfen': 'helfensw',
    'helfe': 'helfensw',
    'hilfst': 'helfensw',
    'hilft': 'helfensw',
    'werden': 'werden1',
    'werde': 'werden1',
    'wirst': 'werden1',
    'wird': 'werden1',
    'backen': 'kochen',
    'backe': 'kochen',
    'backst': 'kochen',
    'backt': 'kochen',
    'trinke': 'trinken',
    'trinkst': 'trinken',
    'trinkt': 'trinken',
    'spiele': 'spielen',
    'spielst': 'spielen',
    'spielt': 'spielen',
    'mache': 'machen',
    'machst': 'machen',
    'macht': 'machen',
    'habe': 'haben',
    'koche': 'kochen',
    'kochst': 'kochen',
    'kocht': 'kochen',
    'tanze': 'tanzen',
    'tanzt': 'tanzen',
    'singe': 'singen',
    'singst': 'singen',
    'singt': 'singen',
    'lache': 'lachen',
    'lachst': 'lachen',
    'lacht': 'lachen',
    'weine': 'weinen',
    'weinst': 'weinen',
    'weint': 'weinen',
    'denke': 'denken',
    'denkst': 'denken',
    'denkt': 'denken',
    'frage': 'fragen',
    'fragst': 'fragen',
    'fragt': 'fragen',
    'zeige': 'zeigen',
    'zeigst': 'zeigen',
    'zeigt': 'zeigen',
    'schreibe': 'schreiben',
    'schreibst': 'schreiben',
    'schreibt': 'schreiben',
    'weiss': 'wissen',
    'wisst': 'wissen',
    'kenne': 'kennen',
    'kennst': 'kennen',
    'kennt': 'kennen',
    'kaufe': 'kaufen',
    'kaufst': 'kaufen',
    'kauft': 'kaufen',
    'arbeite': 'arbeiten',
    'arbeitest': 'arbeiten',
    'arbeitet': 'arbeiten',
    'hoere': 'hoeren',
    'hoerst': 'hoeren',
    'hoert': 'hoeren',
    'spreche': 'sprechen',
    'sprichst': 'sprechen',
    'spricht': 'sprechen',
    'sprach': 'sprechen',
    'liebe': 'lieben',
    'liebst': 'lieben',
    'liebt': 'lieben',
    'glaube': 'glauben',
    'glaubst': 'glauben',
    'glaubt': 'glauben',
    'antworte': 'antworten',
    'antwortest': 'antworten',
    'antwortet': 'antworten',
    'jage': 'jagen',
    'jagst': 'jagen',
    'jagt': 'jagen',
    // ── Kleine Wörter ─────────────────────────────────────────────────
    'gerne': 'gern',
    'nicht': 'nein',
    'garnicht': 'nein',
    'ueberhaupt': 'nein',
    'nie': 'nein',
    'niemals': 'nein',
    'okay': 'ja',
    'dies': 'diese',
    'jeder': 'jede',
    'jedes': 'jede',
    'alles': 'alle',
    'manches': 'manche',
    'oben': 'oben1',
    'unten': 'unten1',
    'links': 'links1',
    'rechts': 'rechts1',
    'und': 'und1',
    'drinnen': 'drinnen2',
    'viele': 'viel',
    'wenige': 'weniger',
    'jeden': 'jede',
    'vieles': 'viel',
    // ── Konjugationen ─────────────────────────────────────────────────
    'nachdenkt': 'nachdenken',
    'nachdenke': 'nachdenken',
    'nachgedacht': 'nachdenken',
    'bekomme': 'bekommen',
    'bekommst': 'bekommen',
    'bekommt': 'bekommen',
    'bekam': 'bekommen',
    'dachte': 'denken',
    'dachten': 'denken',
    'haette': 'haben',
    'haetten': 'haben',
    'wirkt': 'wirken_bewirken',
    'wirken': 'wirken_bewirken',
    'gibt': 'geben',
    'gibst': 'geben',
    'gab': 'geben',
    'gaben': 'geben',
    'findet': 'finden',
    'fand': 'finden',
    'fanden': 'finden',
    'nimmt': 'nehmen',
    'nimmst': 'nehmen',
    'nahm': 'nehmen',
    'nahmen': 'nehmen',
    'laesst': 'lassen',
    'liess': 'lassen',
    'bringt': 'bringen',
    'bringe': 'bringen',
    'bringst': 'bringen',
    'traegt': 'tragen',
    'merke': 'merken',
    'merkst': 'merken',
    'merkt': 'merken',
    'vermisse': 'vermissen',
    'vermisst': 'vermissen',
    'freue': 'freuen',
    'freust': 'freuen',
    'freut': 'freuen',
    'lerne': 'lernen',
    'lernst': 'lernen',
    'lernt': 'lernen',
    'finde': 'finden',
    'findest': 'finden',
    'entscheidet': 'entscheiden',
    'entscheide': 'entscheiden',
    'entschieden': 'entscheiden',
    'veraendert': 'veraendern',
    'veraendere': 'veraendern',
    // ── Nomen/Sonstiges ───────────────────────────────────────────────
    'mama': 'babymutter',
    'papa': 'babyvater',
    'mutter': 'babymutter',
    'vater': 'babyvater',
    'mutti': 'babymutter',
    'papi': 'babyvater',
    'hause': 'haus',
    'dinge': 'ding',
    'sorgen': 'sorge',
    'einfach': 'einfachleicht',
    'besonders': 'besondersbesondere',
    'bestimmt': 'bestimmtbestimmen',
    'genauso': 'genau',
    'naechsten': 'naechster',
    'naechste': 'naechster',
    'naechstes': 'naechster',
    'naechstem': 'naechster',
    'andere': 'andere_anderer_anderes',
    'anderen': 'andere_anderer_anderes',
    'anderer': 'andere_anderer_anderes',
    'anderes': 'andere_anderer_anderes',
    'anrichten': 'vorbereiten',
    'hinrichten': 'tot',
    'zurichten': 'kaputtmachen',
    'einrichten': 'moebel',
    'abtreiben': 'abtreibung',
    'weiterleiten': 'leiten',
    'schaemen': 'schaemenpruede',
    'scham': 'peinlich',
    'schande': 'peinlich',
    'verlegenheit': 'peinlich',
    'verlegen': 'peinlich',
    'peinlichkeit': 'peinlich',
    'angst': 'aengstlich',
    'panik': 'aengstlich',
    'furcht': 'aengstlich',
    'fuerchten': 'aengstlich',
    'erschrecken': 'aengstlich',
    'mut': 'mutig',
    'tapfer': 'mutig',
    'sehnsucht': 'vermissen',
    'sehnen': 'vermissen',
    'vergnuegt': 'froh',
    'gluecklich': 'froh',
    'froehlich': 'froh',
    'heiter': 'froh',
    'begeistert': 'froh',
    'traurigkeit': 'traurig',
    'deprimiert': 'traurig',
    'wut': 'wuetend',
    'zornig': 'wuetend',
    'langeweile': 'langweilig',
    'oede': 'langweilig',
    'entschuldigen': 'entschuldigung',
    'verzeihung': 'entschuldigung',
    'verzeihen': 'entschuldigung',
    'reden': 'sprechen',
    'quatschen': 'sprechen',
    'unterhalten': 'sprechen',
    'gespraech': 'sprechen',
    'austausch': 'sprechen',
    'gratulieren': 'glueckwunschkarte',
    'glueckwunsch': 'glueckwunschkarte',
    'gratulation': 'glueckwunschkarte',
    'genuegend': 'genug',
    'ausreichend': 'genug',
    'hungrig': 'essen',
    'hunger': 'essen',
    'durstig': 'trinken',
    'erschoepft': 'muede',
    'erkrankung': 'krank',
    'krankheit': 'krank',
    'saemtliche': 'alle',
    'komplett': 'alle',
    'reichlich': 'viel',
    'kaum': 'wenig',
    'kommen': 'ankommen',
    'gekommen': 'ankommen',
    'kommt': 'ankommen',
    'kam': 'ankommen',
    'herkommen': 'ankommen',
    'rueckkehr': 'ankommen',
    'darueber': 'ueber',
    'darauf': 'auf',
    'dazu': 'zu',
    'frei': 'frei_nichtarbeiten',
    'kein': 'keine1',
    'erfahrung': 'lernen',
    'beispiel': 'zeigen',
    'affen': 'affe',
    'kater': 'katze1',
    'teddybaer': 'teddy',
    'hund': 'hund1',
    'katze': 'katze1',
    'hunde': 'hund1',
    'katzen': 'katze1',
    'spazieren': 'spazierengehen',
    'spaziergang': 'spazierengehen',
    'papiermuell': 'muell',
    'bundesrepublik': 'deutschland',
    'ballon': 'luftballon',
    'anblick': 'blicken',
    'faszinierender': 'beeindruckend',
    'faszinierend': 'beeindruckend',
    'lauf': 'laufen',
    'nehme': 'nehmen',
    'letzte': 'letzter',
    'erst': 'erster',
    'voelkerrecht': 'recht',
    'mondauto': 'auto',
    'direk': 'direkt',
    'hilfe': 'helfensw',
    'problem': 'schwer',
    'schwierigkeit': 'schwer',
    'fehler': 'falsch',
    'loesung': 'finden',
    'idee': 'denken',
    'gedanke': 'denken',
    // ── Intensivierungen (wunder-, super-, mega-…) ────────────────────────
    'wunderschoen': 'schoen',
    'wundervoll': 'schoen',
    'wunderbar': 'schoen',
    'superschoen': 'schoen',
    'megaschoen': 'schoen',
    'supergut': 'gut',
    'megagut': 'gut',
    'wundergut': 'gut',
    'superklasse': 'gut',
    'supercool': 'cool',
    'megacool': 'cool',
  };
}
