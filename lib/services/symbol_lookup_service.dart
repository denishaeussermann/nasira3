import '../models/models.dart';
import '../nasira_import_service.dart';
import 'search_log_service.dart';

/// Ergebnis einer Symbol-Suche: enthält sowohl das aufgelöste Symbol
/// (für die UI-Anzeige) als auch das strukturierte Suchergebnis
/// (für Logging und Debugging).
class LookupResult {
  final MappedSymbol? symbol;
  final SearchResult searchResult;

  const LookupResult({
    required this.symbol,
    required this.searchResult,
  });

  bool get hasMatch => symbol != null;
}

/// Löst Wörter zu Symbolen auf, unter Berücksichtigung von
/// Flexionsformen, Alias-Tabelle und Partizip-II-Erkennung.
///
/// Erweitert die einfache Suche in [NasiraData.searchSymbol] um:
/// - Eine umfangreiche Alias-Map (Konjugationen, Pronomen, kleine Wörter)
/// - Partizip-II → Grundform Auflösung über [NasiraContextService]
/// - Strukturierte Ergebnisse über [LookupResult]
/// - Optionales Logging über [SearchLogService]
class SymbolLookupService {
  final SearchLogService? _log;

  SymbolLookupService({SearchLogService? log}) : _log = log;

  /// Sucht ein Symbol für ein Wort mit allen Fallbacks.
  ///
  /// Gibt ein [LookupResult] zurück mit:
  /// - [LookupResult.symbol]: Das gefundene MappedSymbol (oder null)
  /// - [LookupResult.searchResult]: Strukturiertes Ergebnis mit Debug-Info
  ///
  /// Fallback-Kette:
  /// 1. Direkte Suche über NasiraData.searchSymbol (exact, fileName, stripped, prefix)
  /// 2. Alias-Varianten (Konjugation, Pronomen, etc.)
  /// 3. Partizip-II → Grundform
  LookupResult lookup(NasiraData data, String rawWord, {bool silent = false}) {
    // Guard: Dateipfade und ungültige Eingaben überspringen
    if (rawWord.contains('\\') || rawWord.contains('/') ||
        rawWord.endsWith('.jpg') || rawWord.endsWith('.png') ||
        rawWord.length > 50) {
      return LookupResult(symbol: null, searchResult: SearchResult.empty(rawWord));
    }

    final normalized = NasiraData.normalize(rawWord);

    // Stufe 1: Exakte Suche (Stufen 1–3, OHNE Präfix)
    final exactResult = data.searchSymbolExact(rawWord);
    if (exactResult.hasMatch) {
      final symbol = data.mappedSymbolForWord(exactResult.matchedWord)
          ?? data.mappedSymbolForWord(rawWord);
      if (!silent) _log?.log(exactResult);
      return LookupResult(symbol: symbol, searchResult: exactResult);
    }

    // Stufe 2: Alias-Auflösung (z.B. "möchte" → "moechten")
    final alias = _aliases[normalized]
        ?? _aliases[NasiraData.strip(rawWord)]
        ?? _semanticAliases[normalized]
        ?? _semanticAliases[NasiraData.strip(rawWord)];
    if (alias != null) {
      final aliasResult = data.searchSymbol(alias);
      if (aliasResult.hasMatch) {
        // WICHTIG: Symbol über gematchtes Wort suchen, nicht alias!
        final symbol = data.mappedSymbolForWord(aliasResult.matchedWord)
            ?? data.mappedSymbolForWord(alias);
        final result = SearchResult(
          query: rawWord,
          normalizedQuery: normalized,
          matchedWord: aliasResult.matchedWord,
          assetPath: aliasResult.assetPath,
          matchType: SearchMatchType.alias,
          score: 0.5,
          debugInfo: 'Alias: "$rawWord" → "$alias" → "${aliasResult.matchedWord}"',
        );
        if (!silent) _log?.log(result);
        return LookupResult(symbol: symbol, searchResult: result);
      }

      // Alias gefunden aber kein Symbol → Varianten-Suche über alle Mappings
      final aliasSymbol = _searchInAllMappings(data, alias);
      if (aliasSymbol != null) {
        final result = SearchResult(
          query: rawWord,
          normalizedQuery: normalized,
          matchedWord: aliasSymbol.word.text,
          assetPath: aliasSymbol.symbol.assetPath,
          matchType: SearchMatchType.alias,
          score: 0.4,
          debugInfo: 'Alias (Mapping): "$rawWord" → "$alias" → "${aliasSymbol.word.text}"',
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
          debugInfo: 'Partizip: "$rawWord" → "$base" → "${baseResult.matchedWord}"',
        );
        if (!silent) _log?.log(result);
        return LookupResult(symbol: symbol, searchResult: result);
      }

      // Partizip-Grundform → Varianten-Suche
      final baseSymbol = _searchInAllMappings(data, base);
      if (baseSymbol != null) {
        final result = SearchResult(
          query: rawWord,
          normalizedQuery: normalized,
          matchedWord: baseSymbol.word.text,
          assetPath: baseSymbol.symbol.assetPath,
          matchType: SearchMatchType.partizip,
          score: 0.25,
          debugInfo: 'Partizip (Mapping): "$rawWord" → "$base" → "${baseSymbol.word.text}"',
        );
        if (!silent) _log?.log(result);
        return LookupResult(symbol: baseSymbol, searchResult: result);
      }

      // Stufe 3a: Partizip-Grundform hat einen Alias?
      // z.B. "getan" → "tun" → Alias "tun" → "machen"
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
            debugInfo: 'Partizip+Alias: "$rawWord" → "$base" → "$baseAlias" → "${aliasResult.matchedWord}"',
          );
          if (!silent) _log?.log(result);
          return LookupResult(symbol: symbol, searchResult: result);
        }
      }

      // Stufe 3b: Trennbares Verb → Stamm ohne Präfix
      // z.B. "angeklebt" → "ankleben" (nicht gefunden) → "kleben" (gefunden!)
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
            debugInfo: 'Partizip (Stamm): "$rawWord" → "$base" → "$strippedBase" → "${stemResult.matchedWord}"',
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
            debugInfo: 'Partizip (Stamm-Mapping): "$rawWord" → "$base" → "$strippedBase" → "${stemSymbol.word.text}"',
          );
          if (!silent) _log?.log(result);
          return LookupResult(symbol: stemSymbol, searchResult: result);
        }
      }
    }

    // Stufe 4: Flexionsendungen entfernen (-e, -er, -es, -en, -em)
    // z.B. "normale" → "normal", "schneller" → "schnell", "vieles" → "viel"
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
          debugInfo: 'Stemmed: "$rawWord" → "$stemmed" → "${stemResult.matchedWord}"',
        );
        if (!silent) _log?.log(result);
        return LookupResult(symbol: symbol, searchResult: result);
      }

      // Stemmed + Alias: z.B. "jeden" → strip → "jede" (kein Treffer) → aber alias?
      final stemAlias = _aliases[stemmed] ?? _aliases[NasiraData.strip(stemmed)];
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
            debugInfo: 'Stemmed+Alias: "$rawWord" → "$stemmed" → "$stemAlias" → "${aliasResult.matchedWord}"',
          );
          if (!silent) _log?.log(result);
          return LookupResult(symbol: symbol, searchResult: result);
        }
      }
    }

    // Stufe 5: Präfix-Fallback (volle Suche inkl. Stufe 4)
    final prefixResult = data.searchSymbol(rawWord);
    if (prefixResult.hasMatch) {
      // WICHTIG: Symbol über das gematchte Wort suchen, nicht über rawWord!
      // "möcht" matched "moechte", aber Symbol existiert nur für "moechte"
      final symbol = data.mappedSymbolForWord(prefixResult.matchedWord)
          ?? data.mappedSymbolForWord(rawWord);
      if (!silent) _log?.log(prefixResult);
      return LookupResult(symbol: symbol, searchResult: prefixResult);
    }

    // Stufe 6: Smart Auto-Match (Kompositum, erweitertes Stemming, Fuzzy)
    final autoMatch = _smartAutoMatch(data, rawWord, normalized);
    if (autoMatch != null) {
      if (!silent) _log?.log(autoMatch.searchResult);
      return autoMatch;
    }

    // Kein Treffer
    final noMatch = SearchResult.empty(rawWord, normalizedQuery: normalized);
    if (!silent) _log?.log(noMatch);
    return LookupResult(symbol: null, searchResult: noMatch);
  }

  /// Hilfsmethode: Sucht ein Wort gegen alle Mapping-Einträge.
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

  /// Entfernt ein trennbares Präfix von einem Infinitiv.
  ///
  /// z.B. "ankleben" → "kleben", "wegstellen" → "stellen"
  /// Gibt null zurück wenn kein Präfix erkannt wird.
  static String? _stripTrennbaresPrefix(String infinitiv) {
    final normalized = NasiraData.normalize(infinitiv);
    const prefixes = [
      'zurueck', 'heraus', 'hinaus', 'herum', 'herein',
      'hinein', 'heran', 'daran', 'drauf', 'raus', 'rein',
      'fest', 'nach', 'heim', 'dran',
      'auf', 'aus', 'ein', 'los', 'mit', 'vor', 'weg', 'hin',
      'her', 'rum', 'um',
      'an', 'ab', 'zu',
    ];
    for (final prefix in prefixes) {
      if (normalized.startsWith(prefix) && normalized.length > prefix.length + 2) {
        return normalized.substring(prefix.length);
      }
    }
    return null;
  }

  /// Entfernt deutsche Flexionsendungen von Adjektiven und Nomen.
  ///
  /// Probiert Endungen von lang nach kurz: -em, -en, -er, -es, -e
  /// Gibt die kürzeste sinnvolle Stammform zurück (mind. 3 Zeichen).
  ///
  /// Beispiele:
  ///   "normale"   → "normal"
  ///   "schneller" → "schnell"
  ///   "vieles"    → "viel"
  ///   "nächsten"  → "naechst"
  ///   "kurzer"    → "kurz"
  ///   "Sorgen"    → "sorge" (Nomen-Plural)
  ///   "Dinge"     → "ding"
  static String? _stripFlexion(String normalized) {
    // Erst Satzzeichen entfernen (z.B. "Monaten." → "monaten")
    final clean = normalized.replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (clean.length < 4) return null;

    // Endungen von lang nach kurz probieren
    const endings = ['em', 'en', 'er', 'es', 'e'];
    for (final ending in endings) {
      if (clean.endsWith(ending) && clean.length > ending.length + 2) {
        return clean.substring(0, clean.length - ending.length);
      }
    }
    return null;
  }

  // ══════════════════════════════════════════════════════════════════════
  // STUFE 6: SMART AUTO-MATCH ENGINE
  // ══════════════════════════════════════════════════════════════════════

  /// Versucht automatisch ein Symbol zu finden durch:
  /// 6a: Erweitertes Suffix-Stripping (deutsche Morphologie)
  /// 6b: Kompositum-Zerlegung (Wort in 2 Teile splitten)
  /// 6c: Reverse-Prefix (Symbol-Wort ist Anfang des Inputs)
  /// 6d: Fuzzy-Match (Levenshtein-Distanz ≤ 2)
  LookupResult? _smartAutoMatch(NasiraData data, String rawWord, String normalized) {
    final clean = normalized.replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (clean.length < 3) return null;

    // 6a: Erweitertes Suffix-Stripping
    final stemmed = _extendedStem(clean);
    for (final stem in stemmed) {
      final result = data.searchSymbolExact(stem);
      if (result.hasMatch) {
        return _autoResult(data, rawWord, normalized, result, 'AutoStem: "$rawWord" → "$stem"');
      }
      // Stem → Alias?
      final stemAlias = _aliases[stem];
      if (stemAlias != null) {
        final aliasResult = data.searchSymbol(stemAlias);
        if (aliasResult.hasMatch) {
          return _autoResult(data, rawWord, normalized, aliasResult,
              'AutoStem+Alias: "$rawWord" → "$stem" → "$stemAlias"');
        }
      }
    }

    // 6b: Kompositum-Zerlegung
    if (clean.length >= 6) {
      final compResult = _compoundMatch(data, rawWord, normalized, clean);
      if (compResult != null) return compResult;
    }

    // 6c: Substring-Match – Input ist irgendwo in einem Symbolnamen enthalten
    // z.B. "gas" → "gasflasche", "papier" → "papierkorb"
    if (clean.length >= 3) {
      final subResult = _substringMatch(data, rawWord, normalized, clean);
      if (subResult != null) return subResult;
    }

    // 6d: Reverse-Prefix (Symbol beginnt mit Input)
    if (clean.length >= 4) {
      final reverseResult = _reversePrefixMatch(data, rawWord, normalized, clean);
      if (reverseResult != null) return reverseResult;
    }

    // 6e: Fuzzy-Match (Levenshtein ≤ 1, streng um falsche Treffer zu vermeiden)
    if (clean.length >= 5) {
      final fuzzyResult = _fuzzyMatch(data, rawWord, normalized, clean);
      if (fuzzyResult != null) return fuzzyResult;
    }

    // 6f: Fuzzy-Alias – Tippfehler gegen semantische + manuelle Alias-Keys prüfen
    // z.B. "demprimiert" (Tippfehler) → "deprimiert" → "traurig"
    if (clean.length >= 5) {
      final fuzzyAliasResult = _fuzzyAliasMatch(data, rawWord, normalized, clean);
      if (fuzzyAliasResult != null) return fuzzyAliasResult;
    }

    return null;
  }

  /// Erweitertes deutsches Suffix-Stripping.
  /// Gibt mehrere Kandidaten zurück (von spezifisch zu allgemein).
  static List<String> _extendedStem(String clean) {
    if (clean.length < 4) return [];
    final candidates = <String>[];

    // Lange Endungen zuerst
    const suffixes = [
      // Derivationssuffixe
      'ungen', 'ieren', 'ender', 'ender',
      // Flexion lang
      'sten', 'stem', 'ster',
      'tet', 'ten', 'ter', 'tes', 'tem',
      'ung', 'nis', 'keit', 'heit',
      'lich', 'isch', 'bar',
      // Flexion kurz
      'st', 'te', 'et', 'en', 'er', 'es', 'em',
      't', 'e', 's', 'n',
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

  /// Kompositum-Zerlegung: Splittet ein Wort an jeder Stelle
  /// und prüft ob einer der Teile ein Symbol hat.
  /// Bevorzugt den längeren Teil und den zweiten Teil (Grundwort).
  LookupResult? _compoundMatch(
      NasiraData data, String rawWord, String normalized, String clean) {
    // Versuche Splits von der Mitte nach außen
    final minPart = 3; // Mindestlänge pro Teil
    final candidates = <(String, String, int)>[]; // (teil, matchType, score)

    for (int i = minPart; i <= clean.length - minPart; i++) {
      final left = clean.substring(0, i);
      final right = clean.substring(i);

      // Rechter Teil (Grundwort) hat höhere Priorität
      final rightResult = data.searchSymbolExact(right);
      if (rightResult.hasMatch) {
        return _autoResult(data, rawWord, normalized, rightResult,
            'Kompositum: "$rawWord" → [$left|$right] → "${rightResult.matchedWord}"');
      }

      // Fugen-S entfernen: "bundesrepublik" → "bundes" → "bund" + "republik"
      if (right.length >= minPart) {
        final leftNoFuge = left.endsWith('s') && left.length > minPart
            ? left.substring(0, left.length - 1)
            : null;
        if (leftNoFuge != null) {
          // Prüfe ob rechter Teil matched
          final r2 = data.searchSymbolExact(right);
          if (r2.hasMatch) {
            return _autoResult(data, rawWord, normalized, r2,
                'Kompositum+Fuge: "$rawWord" → [$leftNoFuge+s|$right] → "${r2.matchedWord}"');
          }
        }
      }

      // Linker Teil (Bestimmungswort) hat niedrigere Priorität
      final leftResult = data.searchSymbolExact(left);
      if (leftResult.hasMatch && right.length >= 3) {
        // Nur wenn der linke Teil sinnvoll ist (nicht nur 'a', 'in' etc.)
        if (left.length >= 4) {
          return _autoResult(data, rawWord, normalized, leftResult,
              'Kompositum (links): "$rawWord" → [$left|$right] → "${leftResult.matchedWord}"');
        }
      }
    }

    return null;
  }

  /// Substring-Match: Findet Symbole deren Name das Input-Wort enthält.
  /// z.B. "gas" → "gasflasche", "papier" → "papierkorb"
  /// Bevorzugt: kürzestes Symbol (spezifischster Treffer).
  LookupResult? _substringMatch(
      NasiraData data, String rawWord, String normalized, String clean) {
    MappedSymbol? bestMatch;
    int bestLen = 999;

    for (final m in data.mappedSymbols) {
      final symbolWord = NasiraData.normalize(m.word.text);
      // Input muss am Anfang des Symbolworts stehen (Bestimmungswort)
      // "gas" findet "gasflasche" aber nicht "orgasmus"
      if (symbolWord.startsWith(clean) &&
          symbolWord.length > clean.length &&
          symbolWord.length < bestLen) {
        bestMatch = m;
        bestLen = symbolWord.length;
      }
    }

    // Fallback: Input ist irgendwo enthalten (aber nur bei > 4 Zeichen
    // um falsche Treffer wie "an" in "ananas" zu vermeiden)
    if (bestMatch == null && clean.length >= 4) {
      for (final m in data.mappedSymbols) {
        final symbolWord = NasiraData.normalize(m.word.text);
        if (symbolWord.contains(clean) &&
            symbolWord.length > clean.length &&
            symbolWord.length < bestLen) {
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

  /// Reverse-Prefix: Findet Symbole deren Wort mit dem Input beginnt.
  /// z.B. "möcht" matched "moechte", "direk" matched "direkt"
  LookupResult? _reversePrefixMatch(
      NasiraData data, String rawWord, String normalized, String clean) {
    MappedSymbol? bestMatch;
    int bestLen = 999;

    for (final m in data.mappedSymbols) {
      final symbolWord = NasiraData.normalize(m.word.text);
      // Input ist Anfang des Symbolwortes (max 3 Zeichen kürzer)
      if (symbolWord.startsWith(clean) &&
          symbolWord.length > clean.length &&
          symbolWord.length - clean.length <= 3 &&
          symbolWord.length < bestLen) {
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

  /// Fuzzy-Match: Findet das nächste Symbol per Levenshtein-Distanz.
  /// Nur für Wörter ≥ 5 Zeichen, max Distanz 2.
  LookupResult? _fuzzyMatch(
      NasiraData data, String rawWord, String normalized, String clean) {
    MappedSymbol? bestMatch;
    int bestDist = 2; // max erlaubte Distanz + 1 (streng: nur 1)

    for (final m in data.mappedSymbols) {
      final symbolWord = NasiraData.normalize(m.word.text);
      // Nur ähnlich lange Wörter prüfen (Performance)
      if ((symbolWord.length - clean.length).abs() > 2) continue;

      final dist = _levenshtein(clean, symbolWord);
      if (dist < bestDist) {
        bestDist = dist;
        bestMatch = m;
        if (dist == 1) break; // Perfekt genug
      }
    }

    if (bestMatch != null && bestDist <= 1) {
      final result = SearchResult(
        query: rawWord,
        normalizedQuery: normalized,
        matchedWord: bestMatch.word.text,
        assetPath: bestMatch.symbol.assetPath,
        matchType: SearchMatchType.prefix, // Reuse type, distinct via debugInfo
        score: 0.2,
        debugInfo: 'Fuzzy ($bestDist): "$rawWord" → "${bestMatch.word.text}"',
      );
      return LookupResult(symbol: bestMatch, searchResult: result);
    }
    return null;
  }

  /// Fuzzy-Alias-Match: Findet den nächsten Alias-Key per Levenshtein.
  /// z.B. "demprimiert" (Tippfehler) → "deprimiert" (Alias) → "traurig"
  LookupResult? _fuzzyAliasMatch(
      NasiraData data, String rawWord, String normalized, String clean) {
    String? bestKey;
    String? bestTarget;
    int bestDist = 2;

    // Prüfe gegen alle semantischen Alias-Keys
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

    // Auch gegen manuelle Alias-Keys prüfen
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
        final symbol = data.mappedSymbolForWord(aliasResult.matchedWord)
            ?? data.mappedSymbolForWord(bestTarget);
        final result = SearchResult(
          query: rawWord,
          normalizedQuery: normalized,
          matchedWord: aliasResult.matchedWord,
          assetPath: aliasResult.assetPath,
          matchType: SearchMatchType.alias,
          score: 0.2,
          debugInfo: 'FuzzyAlias: "$rawWord" ~→ "$bestKey" → "$bestTarget" → "${aliasResult.matchedWord}"',
        );
        return LookupResult(symbol: symbol, searchResult: result);
      }
    }
    return null;
  }

  /// Erstellt ein LookupResult für Auto-Match Treffer.
  LookupResult _autoResult(NasiraData data,
      String rawWord, String normalized, SearchResult matchResult, String debug) {
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

  /// Levenshtein-Distanz (optimiert mit Cutoff).
  static int _levenshtein(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;

    final la = a.length;
    final lb = b.length;
    // Cutoff: wenn Längendifferenz > 2, sofort abbrechen
    if ((la - lb).abs() > 2) return 3;

    var prev = List<int>.generate(lb + 1, (i) => i);
    var curr = List<int>.filled(lb + 1, 0);

    for (int i = 1; i <= la; i++) {
      curr[0] = i;
      for (int j = 1; j <= lb; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        curr[j] = [
          prev[j] + 1,      // Löschung
          curr[j - 1] + 1,  // Einfügung
          prev[j - 1] + cost // Ersetzung
        ].reduce((a, b) => a < b ? a : b);
      }
      final tmp = prev;
      prev = curr;
      curr = tmp;
    }
    return prev[lb];
  }

  // ── Semantische Wortgruppen ──────────────────────────────────────────
  //
  // Statt einzelne Aliases zu pflegen, definieren wir Gruppen
  // verwandter Wörter die alle auf dasselbe Symbol zeigen.
  // Die Aliases werden automatisch daraus generiert.

  static final Map<String, String> _semanticAliases = _buildSemanticAliases();

  static Map<String, String> _buildSemanticAliases() {
    final result = <String, String>{};

    // Format: Symbol-Ziel → Liste verwandter Wörter
    const groups = <String, List<String>>{
      // Gase & Chemie
      'gasflasche': ['helium', 'wasserstoff', 'sauerstoff', 'stickstoff', 'co2', 'propan', 'butan', 'argon', 'neon'],
      'erdgas': ['methan', 'biogas'],
      // Wetter
      'regen': ['niederschlag', 'schauer', 'regenschauer', 'nass'],
      'sturm': ['orkan', 'hurrikan', 'taifun', 'tornado', 'unwetter', 'gewitter'],
      'schnee': ['schneeflocke', 'schneesturm', 'wintereinbruch'],
      'sonne': ['sonnenschein', 'sonnig', 'heiter'],
      // Gefühle erweitert
      'traurig': ['deprimiert', 'niedergeschlagen', 'betruebt', 'melancholisch', 'ungluecklich'],
      'froh': ['gluecklich', 'erfreut', 'heiter', 'begeistert', 'euphorisch', 'zufrieden'],
      'wuetend': ['zornig', 'sauer', 'aergerlich', 'rasend', 'aufgebracht', 'empört'],
      'aengstlich': ['furchtsam', 'verängstigt', 'beklommen', 'panisch', 'besorgt'],
      'muede': ['erschoepft', 'schlaefrig', 'ermattet', 'kaputt', 'ausgelaugt'],
      // Essen & Trinken
      'essen': ['nahrung', 'mahlzeit', 'speise', 'gericht', 'mahl'],
      'trinken': ['getraenk', 'schluck', 'fluessigkeit'],
      'brot': ['broetchen', 'toast', 'semmel', 'stulle'],
      'obst': ['frucht', 'fruechte'],
      // Körper & Gesundheit
      'krank': ['erkrankt', 'unwohl', 'fieber', 'erkaeltet', 'erkaeltung', 'grippe'],
      'schmerzen': ['schmerz', 'wehtun', 'weh', 'aua', 'wehwehchen'],
      'arzt': ['doktor', 'mediziner', 'hausarzt', 'kinderarzt'],
      'krankenhaus': ['klinik', 'hospital', 'spital', 'notaufnahme'],
      'medikament': ['medizin', 'tablette', 'pille', 'arznei'],
      // Verkehr
      'auto': ['fahrzeug', 'wagen', 'pkw', 'automobil', 'mondauto'],
      'bus': ['omnibus', 'linienbus', 'schulbus', 'reisebus'],
      'fahrrad': ['rad', 'velo', 'drahtesel'],
      // Gebäude
      'haus': ['gebaeude', 'wohnung', 'zuhause', 'daheim', 'heim'],
      'schule': ['schulgebaeude', 'bildung', 'unterricht'],
      'kirche': ['gotteshaus', 'kapelle', 'dom', 'kathedrale'],
      // Natur
      'baum': ['baeume', 'gehoelz', 'stamm'],
      'blume': ['bluete', 'pflanze'],
      'wald': ['forst', 'gehoelz', 'dickicht'],
      'berg': ['gebirge', 'huegel', 'gipfel'],
      'meer': ['ozean', 'see', 'gewaesser'],
      'fluss': ['strom', 'bach', 'kanal'],
      // Tiere erweitert
      'hund1': ['welpe', 'ruede', 'huendin'],
      'katze1': ['kaetzchen', 'mieze', 'stubentiger', 'kater'],
      'vogel': ['piepmatz', 'spatz'],
      // Berufe
      'polizei': ['polizist', 'polizistin', 'beamter'],
      'feuerwehr': ['feuerwehrmann', 'feuerwehrfrau', 'loeschen'],
      // Kommunikation
      'sprechen': ['reden', 'erzaehlen', 'sagen', 'berichten', 'mitteilen', 'quatschen'],
      'telefon': ['handy', 'smartphone', 'mobiltelefon', 'anruf'],
      // Schule
      'lesen': ['buch', 'lektuere'],
      'schreiben': ['verfassen', 'notieren', 'aufschreiben'],
      'rechnen': ['berechnen', 'mathematik', 'mathe'],
      // Politik / Gesellschaft
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

  static const _aliases = <String, String>{
    // ── Pronomen ──────────────────────────────────────────────────────
    'sie':        'sie_einzahl',
    'ihm':        'ihr',
    'sein':       'sein1',
    'seine':      'mein',
    'seinen':     'mein',
    'seinem':     'mein',
    'seiner':     'mein',
    'seines':     'mein',
    'meine':      'mein',
    'meinen':     'mein',
    'meinem':     'mein',
    'meiner':     'mein',
    'meines':     'mein',
    'deine':      'dein',
    'deinen':     'dein',
    'deinem':     'dein',
    'deiner':     'dein',
    'deines':     'dein',
    'ihre':       'ihr',
    'ihren':      'ihr',
    'ihrem':      'ihr',
    'ihrer':      'ihr',
    'ihres':      'ihr',
    'unsere':     'unser',
    'unseren':    'unser',
    'unserem':    'unser',
    'unserer':    'unser',
    'unseres':    'unser',
    'eure':       'eure',
    'euren':      'eure',
    'eurem':      'eure',
    'eurer':      'eure',
    'eures':      'eure',
    // ── Hilfsverben ───────────────────────────────────────────────────
    'bin':        'ich',
    'bist':       'du',
    'ist':        'sein1',
    'sind':       'sein1',
    'seid':       'sein1',
    'war':        'waren1',
    'waren':      'waren1',
    'waere':      'sein1',
    'hat':        'haben',
    'hast':       'haben',
    'habt':       'haben',
    'hatte':      'haben',
    'hatten':     'haben',
    'kann':       'koennen',
    'kannst':     'koennen',
    'koennt':     'koennen',
    'konnte':     'koennen',
    'konnten':    'koennen',
    'muss':       'muessen',
    'musst':      'muessen',
    'muesst':     'muessen',
    'musste':     'muessen',
    'mussten':    'muessen',
    'soll':       'sollen',
    'sollst':     'sollen',
    'sollt':      'sollen',
    'sollte':     'sollen',
    'sollten':    'sollen',
    'will':       'wollen',
    'willst':     'wollen',
    'wollt':      'wollen',
    'wollte':     'wollen',
    'wollten':    'wollen',
    'darf':       'duerfen',
    'darfst':     'duerfen',
    'duerft':     'duerfen',
    'durfte':     'duerfen',
    'durften':    'duerfen',
    'mag':        'moegen',
    'magst':      'moegen',
    'moegt':      'moegen',
    'moechte':    'moechten',
    'moechtest':  'moechten',
    'mochte':     'moechten',
    // ── Vollverben ────────────────────────────────────────────────────
    'gehe':       'gehen',
    'gehst':      'gehen',
    'geht':       'gehen',
    'ging':       'gehen',
    'gingen':     'gehen',
    'komme':      'ankommen',
    'kommst':     'ankommen',
    'komm':       'ankommen',
    'esse':       'essen1',
    'isst':       'essen1',
    'ass':        'essen1',
    'essen':      'essen1',
    'sage':       'sprechen',
    'sagst':      'sprechen',
    'sagt':       'sprechen',
    'sagte':      'sprechen',
    'sagten':     'sprechen',
    'sagen':      'sprechen',
    'siehst':     'sehen',
    'sieht':      'sehen',
    'sah':        'sehen',
    'sahen':      'sehen',
    'sehe':       'sehen',
    'tat':        'machen',
    'taten':      'machen',
    'tun':        'machen',
    'schlafen':   'schlafen1',
    'schlafe':    'schlafen1',
    'schlaefst':  'schlafen1',
    'schlaeft':   'schlafen1',
    'fahren':     'fahren1',
    'fahre':      'fahren1',
    'faehrst':    'fahren1',
    'faehrt':     'fahren1',
    'lesen':      'lesen1',
    'lese':       'lesen1',
    'liest':      'lesen1',
    'helfen':     'helfensw',
    'helfe':      'helfensw',
    'hilfst':     'helfensw',
    'hilft':      'helfensw',
    'werden':     'werden1',
    'werde':      'werden1',
    'wirst':      'werden1',
    'wird':       'werden1',
    'backen':     'kochen',
    'backe':      'kochen',
    'backst':     'kochen',
    'backt':      'kochen',
    'trinke':     'trinken',
    'trinkst':    'trinken',
    'trinkt':     'trinken',
    'spiele':     'spielen',
    'spielst':    'spielen',
    'spielt':     'spielen',
    'mache':      'machen',
    'machst':     'machen',
    'macht':      'machen',
    'habe':       'haben',
    'koche':      'kochen',
    'kochst':     'kochen',
    'kocht':      'kochen',
    'tanze':      'tanzen',
    'tanzt':      'tanzen',
    'singe':      'singen',
    'singst':     'singen',
    'singt':      'singen',
    'lache':      'lachen',
    'lachst':     'lachen',
    'lacht':      'lachen',
    'weine':      'weinen',
    'weinst':     'weinen',
    'weint':      'weinen',
    'denke':      'denken',
    'denkst':     'denken',
    'denkt':      'denken',
    'frage':      'fragen',
    'fragst':     'fragen',
    'fragt':      'fragen',
    'zeige':      'zeigen',
    'zeigst':     'zeigen',
    'zeigt':      'zeigen',
    'schreibe':   'schreiben',
    'schreibst':  'schreiben',
    'schreibt':   'schreiben',
    'weiss':      'wissen',
    'wisst':      'wissen',
    'kenne':      'kennen',
    'kennst':     'kennen',
    'kennt':      'kennen',
    'kaufe':      'kaufen',
    'kaufst':     'kaufen',
    'kauft':      'kaufen',
    'arbeite':    'arbeiten',
    'arbeitest':  'arbeiten',
    'arbeitet':   'arbeiten',
    'hoere':      'hoeren',
    'hoerst':     'hoeren',
    'hoert':      'hoeren',
    'spreche':    'sprechen',
    'sprichst':   'sprechen',
    'spricht':    'sprechen',
    'sprach':     'sprechen',
    'liebe':      'lieben',
    'liebst':     'lieben',
    'liebt':      'lieben',
    'glaube':     'glauben',
    'glaubst':    'glauben',
    'glaubt':     'glauben',
    'antworte':   'antworten',
    'antwortest': 'antworten',
    'antwortet':  'antworten',
    'jage':       'jagen',
    'jagst':      'jagen',
    'jagt':       'jagen',
    // ── Kleine Wörter ─────────────────────────────────────────────────
    'gerne':      'gern',
    'nicht':      'nein',
    'nie':        'nein',
    'okay':       'ja',
    'dies':       'diese',
    'jeder':      'jede',
    'jedes':      'jede',
    'alles':      'alle',
    'manches':    'manche',
    'oben':       'oben1',
    'unten':      'unten1',
    'links':      'links1',
    'rechts':     'rechts1',
    'und':        'und1',
    'drinnen':    'drinnen2',
    'viele':      'viel',
    'wenige':     'weniger',
    'jeden':      'jede',
    'vieles':     'viel',
    // ── Konjugationen (Ergänzungen) ─────────────────────────────────
    'nachdenkt':  'nachdenken',
    'nachdenke':  'nachdenken',
    'nachgedacht': 'nachdenken',
    'bekomme':    'bekommen',
    'bekommst':   'bekommen',
    'bekommt':    'bekommen',
    'bekam':      'bekommen',
    'dachte':     'denken',
    'dachten':    'denken',
    'haette':     'haben',
    'haetten':    'haben',
    'wirkt':      'wirken_bewirken',
    'wirken':     'wirken_bewirken',
    'gibt':       'geben',
    'gibst':      'geben',
    'gab':        'geben',
    'gaben':      'geben',
    'findet':     'finden',
    'fand':       'finden',
    'fanden':     'finden',
    'nimmt':      'nehmen',
    'nimmst':     'nehmen',
    'nahm':       'nehmen',
    'nahmen':     'nehmen',
    'laesst':     'lassen',
    'liess':      'lassen',
    'bringt':     'bringen',
    'bringe':     'bringen',
    'bringst':    'bringen',
    'traegt':     'tragen',
    'merke':      'merken',
    'merkst':     'merken',
    'merkt':      'merken',
    'vermisse':   'vermissen',
    'vermisst':   'vermissen',
    'freue':      'freuen',
    'freust':     'freuen',
    'freut':      'freuen',
    'lerne':      'lernen',
    'lernst':     'lernen',
    'lernt':      'lernen',
    'finde':      'finden',
    'findest':    'finden',
    'entscheidet': 'entscheiden',
    'entscheide': 'entscheiden',
    'entschieden': 'entscheiden',
    'veraendert': 'veraendern',
    'veraendere': 'veraendern',
    // ── Nomen/Sonstiges ─────────────────────────────────────────────
    'mama':       'babymutter',
    'papa':       'babyvater',
    'mutter':     'babymutter',
    'vater':      'babyvater',
    'mutti':      'babymutter',
    'papi':       'babyvater',
    'hause':      'haus',
    'dinge':      'ding',
    'sorgen':     'sorge',
    'einfach':    'einfachleicht',
    'besonders':  'besondersbesondere',
    'bestimmt':   'bestimmtbestimmen',
    'genauso':    'genau',
    'naechsten':  'naechster',
    'naechste':   'naechster',
    'naechstes':  'naechster',
    'naechstem':  'naechster',
    'andere':     'andere_anderer_anderes',
    'anderen':    'andere_anderer_anderes',
    'anderer':    'andere_anderer_anderes',
    'anderes':    'andere_anderer_anderes',
    // ── Semantische Zuordnungen (Kompositum → passendes Symbol) ─────
    'anrichten':  'vorbereiten',   // Essen anrichten → vorbereiten
    'hinrichten': 'tot',           // hinrichten → tot
    'zurichten':  'kaputtmachen',  // zurichten → kaputtmachen
    'einrichten': 'moebel',        // Wohnung einrichten → Möbel
    'abtreiben':  'abtreibung',    // abtreiben → Abtreibung
    'weiterleiten': 'leiten',      // weiterleiten → leiten
    // ── Fehlende Symbol-Mappings (kein exaktes Symbol vorhanden) ────
    // Emotionen
    'schaemen':   'schaemenpruede', // schämen → schämen/prüde Symbol
    'scham':      'peinlich',
    'schande':    'peinlich',
    'verlegenheit': 'peinlich',
    'verlegen':   'peinlich',
    'peinlichkeit': 'peinlich',
    'angst':      'aengstlich',    // kein "angst" Symbol, aber ängstlich
    'panik':      'aengstlich',
    'furcht':     'aengstlich',
    'fuerchten':  'aengstlich',
    'erschrecken': 'aengstlich',
    'mut':        'mutig',         // kein "mut" Symbol, aber mutig
    'tapfer':     'mutig',
    'sehnsucht':  'vermissen',
    'sehnen':     'vermissen',
    'vergnuegt':  'froh',
    'gluecklich': 'froh',
    'froehlich':  'froh',
    'heiter':     'froh',
    'begeistert': 'froh',
    'traurigkeit': 'traurig',
    'deprimiert': 'traurig',
    'wut':        'wuetend',
    'zornig':     'wuetend',
    'langeweile': 'langweilig',    // kein "langeweile", aber langweilig
    'oede':       'langweilig',
    // Kommunikation
    'entschuldigen': 'entschuldigung', // kein Verb, aber Nomen existiert
    'verzeihung': 'entschuldigung',
    'verzeihen':  'entschuldigung',
    'reden':      'sprechen',
    'quatschen':  'sprechen',
    'unterhalten': 'sprechen',
    'gespraech':  'sprechen',
    'austausch':  'sprechen',
    'gratulieren': 'glueckwunschkarte',
    'glueckwunsch': 'glueckwunschkarte',
    'gratulation': 'glueckwunschkarte',
    // Grundbedürfnisse
    'genuegend':  'genug',
    'ausreichend': 'genug',
    'hungrig':    'essen',           // kein hunger-Symbol vorhanden
    'durstig':    'trinken',
    'erschoepft': 'muede',
    'erkrankung': 'krank',
    'krankheit':  'krank',
    // Mengen
    'saemtliche': 'alle',
    'komplett':   'alle',
    'reichlich':  'viel',
    'kaum':       'wenig',
    // Bewegung / Ort
    'kommen':     'ankommen',      // NICHT kommentar!
    'gekommen':   'ankommen',
    'kommt':      'ankommen',
    'kam':        'ankommen',
    'herkommen':  'ankommen',
    'rueckkehr':  'ankommen',
    'darueber':   'ueber',
    'darauf':     'auf',
    'dazu':       'zu',
    // Falsche Präfix-Matches korrigieren
    'frei':       'frei_nichtarbeiten',  // NICHT freitag!
    'kein':       'keine1',              // NICHT kein→keineahnung
    'erfahrung':  'lernen',
    'beispiel':   'zeigen',
    'affen':      'affe',
    'kater':      'katze1',
    'teddybaer':  'teddy',
    'hund':       'hund1',
    'katze':      'katze1',
    'hunde':      'hund1',
    'katzen':     'katze1',
    'spazieren':  'spazierengehen',
    'spaziergang': 'spazierengehen',
    'papiermuell': 'muell',
    'bundesrepublik': 'deutschland',
    'ballon':     'luftballon',
    'anblick':    'blicken',
    'faszinierender': 'beeindruckend',
    'faszinierend': 'beeindruckend',
    'lauf':       'laufen',
    'nehme':      'nehmen',
    'letzte':     'letzter',
    'erst':       'erster',
    'voelkerrecht': 'recht',
    'mondauto':   'auto',
    'direk':      'direkt',
    // Abstrakt
    'hilfe':      'helfensw',
    'problem':    'schwer',
    'schwierigkeit': 'schwer',
    'fehler':     'falsch',
    'loesung':    'finden',
    'idee':       'denken',
    'gedanke':    'denken',
  };
}
