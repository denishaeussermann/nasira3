// ignore_for_file: avoid_print
// ignore_for_file: dangling_library_doc_comments
/// ════════════════════════════════════════════════════════════════════════════
/// NASIRA ENGINE EVALUATION SUITE
/// ════════════════════════════════════════════════════════════════════════════
///
/// Läuft ohne Gerät / Emulator:
///   flutter test test/engine_eval_test.dart --reporter=expanded
///
/// Was getestet wird:
///   1. Kontext-Präfix   (computer → mausklick vor maus)
///   2. 3-Zeichen-Präfix (Basis-Erreichbarkeit)
///   3. Kurze Wörter     (es, er, in in Satzleiste + Symbol)
///   4. Step-6 Reranking (nach Leerzeichen kontextbewusst)
///   5. Kategorie-Coverage (auto: jedes Symbol via 3-Zeichen-Präfix?)
///   6. Embedding-Diagnose (Cosinus-Scores für Debug)
///
/// ════════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nasira3/embedding_service.dart';
import 'package:nasira3/models/models.dart';
import 'package:nasira3/services/suggestion_engine.dart';

// ── Globale Testdaten ─────────────────────────────────────────────────────────

late NasiraData _data;
late SuggestionEngine _engine;

// ── Hilfsfunktionen ──────────────────────────────────────────────────────────

NasiraData _decodeData(String wordsRaw, String symbolsRaw, String mappingsRaw) {
  final words = (jsonDecode(wordsRaw) as List)
      .map((e) => WordEntry.fromJson(e as Map<String, dynamic>))
      .toList();
  final symbols = (jsonDecode(symbolsRaw) as List)
      .map((e) => SymbolEntry.fromJson(e as Map<String, dynamic>))
      .toList();
  final mappings = (jsonDecode(mappingsRaw) as List)
      .map((e) => WordSymbolMapping.fromJson(e as Map<String, dynamic>))
      .toList();
  words.sort((a, b) => a.rank.compareTo(b.rank));
  return NasiraData(words: words, symbols: symbols, mappings: mappings);
}

Future<NasiraData> _loadData() async {
  // 1. Importierte Daten versuchen (vollständiges Metacom-Vokabular)
  final home = Platform.environment['USERPROFILE'] ??
      Platform.environment['HOME'] ?? '';
  final sep  = Platform.pathSeparator;
  final importPath = '$home${sep}Documents${sep}nasira_import';
  final importDir  = Directory(importPath);

  if (importDir.existsSync()) {
    final wf = File('$importPath${sep}words.json');
    final sf = File('$importPath${sep}symbols.json');
    final mf = File('$importPath${sep}mappings.json');
    if (wf.existsSync() && sf.existsSync() && mf.existsSync()) {
      print('  Quelle: importierte Daten ($importPath)');
      return _decodeData(
        await wf.readAsString(),
        await sf.readAsString(),
        await mf.readAsString(),
      );
    }
  }

  // 2. Fallback: Bundle-Daten (nur 9 Symbole — Tests eingeschränkt!)
  print('  ⚠ Importpfad "$importPath" nicht gefunden');
  print('  ⚠ Fallback auf Bundle-Daten (nur Minimal-Symbole)');
  final wordsRaw    = await rootBundle.loadString('assets/data/words.json');
  final symbolsRaw  = await rootBundle.loadString('assets/data/symbols.json');
  final mappingsRaw = await rootBundle.loadString('assets/data/mappings.json');
  return _decodeData(wordsRaw, symbolsRaw, mappingsRaw);
}

/// 1-basierter Rang eines Worts in der Liste (0 = nicht gefunden).
int _rankOf(List<WordEntry> suggestions, String word) {
  final norm = NasiraData.normalize(word);
  for (int i = 0; i < suggestions.length; i++) {
    if (NasiraData.normalize(suggestions[i].text) == norm) return i + 1;
  }
  return 0;
}

String _fmt(List<WordEntry> words, {int max = 12}) {
  final items = words.take(max).map((w) => w.text).toList();
  if (words.length > max) items.add('…');
  return '[${items.join(', ')}]';
}

String _bar(int hits, int total, {int width = 20}) {
  if (total == 0) return '─' * width;
  final filled = (hits / total * width).round().clamp(0, width);
  return '█' * filled + '░' * (width - filled);
}

List<WordEntry> _suggest(String text, {bool verbose = true}) {
  final result = _engine.computeSuggestions(_data, text);
  if (verbose) {
    final ctx = text.length > 50 ? '…${text.substring(text.length - 50)}' : text;
    print('  suggest("$ctx") → ${_fmt(result)}');
  }
  return result;
}

double _cosine(Float32List a, Float32List b) {
  double dot = 0, na = 0, nb = 0;
  for (int i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    na  += a[i] * a[i];
    nb  += b[i] * b[i];
  }
  if (na == 0 || nb == 0) return 0;
  return dot / math.sqrt(na * nb);
}

Float32List _avgVec(List<Float32List> vecs) {
  final result = Float32List(300);
  for (final v in vecs) {
    for (int i = 0; i < 300; i++) { result[i] += v[i]; }
  }
  final n = vecs.length.toDouble();
  for (int i = 0; i < 300; i++) { result[i] /= n; }
  return result;
}

// ════════════════════════════════════════════════════════════════════════════
// TESTS
// ════════════════════════════════════════════════════════════════════════════

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    print('\n${'═' * 70}');
    print('  NASIRA ENGINE EVALUATION');
    print('${'═' * 70}\n');

    _data = await _loadData();
    print('  Wörter: ${_data.words.length} | '
        'Symbole: ${_data.symbols.length} | '
        'Mappings: ${_data.mappings.length}');

    await EmbeddingService.init();
    print('  Embeddings bereit.\n');

    _engine = SuggestionEngine();
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 1. KONTEXT-PRÄFIX
  // ─────────────────────────────────────────────────────────────────────────
  group('1. Kontext-Präfix', () {
    test('computer → mausklick VOR maus(Tier) bei Präfix "mau"', () {
      print('\n[1a] Computer-Kontext + Präfix "mau"');
      final s = _suggest('computer mau');
      final rKlick = _rankOf(s, 'mausklick');
      final rMaus  = _rankOf(s, 'maus');
      print('     mausklick rank=$rKlick  maus(Tier) rank=$rMaus');

      expect(rKlick, greaterThan(0),
          reason: 'mausklick muss in Vorschlägen erscheinen');
      if (rMaus > 0) {
        expect(rKlick, lessThan(rMaus),
            reason: 'Im Computer-Kontext soll mausklick vor maus(Tier) ranken');
      }
    });

    test('computer → mauspfeil in Top-5 bei Präfix "mausp"', () {
      print('\n[1b] Präfix "mausp"');
      final s = _suggest('computer mausp');
      final r = _rankOf(s, 'mauspfeil');
      print('     mauspfeil rank=$r');
      expect(r, greaterThan(0));
      expect(r, lessThanOrEqualTo(5));
    });

    test('tiere-Kontext → maulwurf erscheint bei "mau"', () {
      print('\n[1c] Tiere-Kontext + Präfix "mau"');
      final s = _suggest('hund katze vogel mau');
      final rWurf  = _rankOf(s, 'maulwurf');
      final rMaus  = _rankOf(s, 'maus');
      final rMauer = _rankOf(s, 'mauer');
      print('     maulwurf=$rWurf  maus=$rMaus  mauer=$rMauer');
      // Nur beobachten, kein harter Fail
    });

    test('schule-Kontext → schulrelevante "st"-Wörter erscheinen', () {
      print('\n[1d] Schule-Kontext + Präfix "st"');
      final s = _suggest('schule buch tafel st');
      print('     Ergebnis: ${_fmt(s)}');
      final r = _rankOf(s, 'stift');
      print('     stift rank=$r');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 2. DREI-ZEICHEN-PRÄFIX
  // ─────────────────────────────────────────────────────────────────────────
  group('2. Drei-Zeichen-Präfix (kein Kontext)', () {
    test('Basis-Erreichbarkeit: häufige Wörter in Top-5', () {
      print('\n[2] Drei-Zeichen-Präfix ohne Kontext:');
      final cases = <String, String>{
        'com': 'computer1',
        'mau': 'maus',
        'hun': 'hund',
        'kat': 'katze',
        'ess': 'essen',
        'tri': 'trinken',
        'buc': 'buch',
        'aut': 'auto',
        'han': 'hand',
        'sch': 'schule',
        'tie': 'tier',
        'vog': 'vogel',
      };
      int hits = 0;
      for (final e in cases.entries) {
        final s = _suggest(e.key, verbose: false);
        final rank = _rankOf(s, e.value);
        final ok = rank > 0 && rank <= 5;
        if (ok) hits++;
        final mark = ok ? '✓' : (rank > 0 ? '~(rank=$rank)' : '✗');
        print('    "${e.key}" → ${e.value}: $mark');
      }
      print('    Ergebnis: $hits/${cases.length} in Top-5');
      expect(hits, greaterThanOrEqualTo(cases.length ~/ 2));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 3. KURZE WÖRTER
  // ─────────────────────────────────────────────────────────────────────────
  group('3. Kurze Wörter', () {
    test('"es", "er", "in" in Satzleiste (>= 2 Zeichen)', () {
      print('\n[3a] Satzleiste-Filter');
      const text = 'ich bin es er in der schule';
      final tokens = text.trim()
          .split(RegExp(r'\s+'))
          .where((t) => t.length >= 2)
          .toList();
      print('    Tokens: $tokens');
      for (final w in ['es', 'er', 'in']) {
        expect(tokens, contains(w), reason: '"$w" soll in Satzleiste erscheinen');
        print('    "$w" ✓');
      }
    });

    test('"es" hat Symbol-Mapping', () {
      print('\n[3b] "es" → Symbol');
      final result = _data.searchSymbol('es');
      print('    hasMatch=${result.hasMatch}  '
          'word="${result.matchedWord}"  '
          'path="${result.assetPath}"');
      expect(result.hasMatch, isTrue,
          reason: '"es" soll auf ein Symbol mappen (Baby)');
    });

    test('Kurze Wörter in words.json vorhanden', () {
      print('\n[3c] Kurze Wörter in Datenbasis:');
      for (final word in ['es', 'er', 'in', 'an', 'zu', 'da', 'so', 'ab']) {
        final found = _data.words.any(
            (w) => NasiraData.normalize(w.text) == NasiraData.normalize(word));
        print('    "$word": ${found ? "✓" : "✗ (fehlt in words.json!)"}');
      }
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 4. STEP-6 KONTEXT-RERANKING (nach Leerzeichen)
  // ─────────────────────────────────────────────────────────────────────────
  group('4. Step-6 Kontext-Reranking', () {
    test('nach "computer maus " → Computer-Wörter bevorzugt', () {
      print('\n[4a] Step-6 nach "computer maus "');
      final s = _suggest('computer maus ');

      final computerWords = ['mausklick', 'mauspfeil', 'tastatur',
          'computerspiel', 'computerhandy', 'drucker', 'bildschirm'];
      final genericWords  = ['einige', 'las', 'gebe', 'frage', 'weiß'];

      int compHits = 0;
      print('    Computer-Wörter:');
      for (final w in computerWords) {
        final r = _rankOf(s, w);
        if (r > 0) { compHits++; print('      $w: rank $r ✓'); }
        else        { print('      $w: nicht in Top-${SuggestionEngine.defaultLimit}'); }
      }
      print('    Generische Wörter (sollten hinten sein):');
      for (final w in genericWords) {
        final r = _rankOf(s, w);
        if (r > 0) print('      $w: rank $r ⚠');
      }
      print('    Computer-Wörter gefunden: $compHits/${computerWords.length}');
    });

    test('nach "hund katze " → Tier-Wörter in Vorschlägen', () {
      print('\n[4b] Step-6 nach "hund katze "');
      final s = _suggest('hund katze ');
      final tierWords = ['vogel', 'fisch', 'pferd', 'maus', 'hase', 'esel'];
      int hits = 0;
      for (final w in tierWords) {
        final r = _rankOf(s, w);
        if (r > 0) { hits++; print('    $w: rank $r ✓'); }
      }
      print('    Tier-Wörter in Top-${SuggestionEngine.defaultLimit}: $hits/${tierWords.length}');
    });

    test('nach "essen trinken " → Lebensmittel in Vorschlägen', () {
      print('\n[4c] Step-6 nach "essen trinken "');
      final s = _suggest('essen trinken ');
      final foodWords = ['brot', 'wasser', 'milch', 'obst', 'suppe', 'saft'];
      int hits = 0;
      for (final w in foodWords) {
        final r = _rankOf(s, w);
        if (r > 0) { hits++; print('    $w: rank $r ✓'); }
      }
      print('    Lebensmittel in Top-${SuggestionEngine.defaultLimit}: $hits/${foodWords.length}');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 5. KATEGORIE-COVERAGE (auto-generiert)
  // ─────────────────────────────────────────────────────────────────────────
  group('5. Kategorie-Coverage', () {
    test('Jedes Symbol via 3-Zeichen-Präfix erreichbar (Report)', () {
      print('\n${'─' * 70}');
      print('  KATEGORIE-COVERAGE REPORT (3-Zeichen-Präfix → Top-20)');
      print('─' * 70);

      final categories = _data.mappedCategories;
      final catResults  = <String, (int, int)>{};

      for (final cat in categories) {
        final mapped = _data.filteredMappedSymbols(category: cat);
        int hits = 0;

        for (final item in mapped) {
          final norm = NasiraData.normalize(item.word.text);
          if (norm.length < 3) {
            // Kurze Wörter: exakte Suche
            final found = _data.words
                .any((w) => NasiraData.normalize(w.text) == norm);
            if (found) hits++;
            continue;
          }
          final prefix = norm.substring(0, 3);
          final suggestions = _data.searchByPrefix(prefix, limit: 20);
          if (suggestions.any((w) => NasiraData.normalize(w.text) == norm)) {
            hits++;
          }
        }

        catResults[cat] = (hits, mapped.length);
      }

      int totalHits = 0, totalItems = 0;
      for (final cat in categories) {
        final (hits, total) = catResults[cat]!;
        totalHits  += hits;
        totalItems += total;
        final pct  = total == 0 ? 0 : (hits * 100 ~/ total);
        final bar  = _bar(hits, total, width: 18);
        final mark = pct >= 90 ? '✓' : (pct >= 70 ? '~' : '✗');
        print('  $mark $bar ${pct.toString().padLeft(3)}%'
            '  ${cat.padRight(32)} ($hits/$total)');
      }

      print('─' * 70);
      final totalPct = totalItems == 0 ? 0 : (totalHits * 100 ~/ totalItems);
      print('  GESAMT ${_bar(totalHits, totalItems, width: 18)} '
          '${totalPct.toString().padLeft(3)}%  '
          '($totalHits/$totalItems)\n');

      expect(totalPct, greaterThanOrEqualTo(70),
          reason: 'Mind. 70% aller Symbole via 3-Zeichen-Präfix erreichbar');
    });

    test('Fehlende Wörter pro Kategorie (< 90% Coverage)', () {
      print('\n${'─' * 70}');
      print('  FEHLENDE WÖRTER (Kategorien mit < 90% Coverage)');
      print('─' * 70);

      for (final cat in _data.mappedCategories) {
        final mapped  = _data.filteredMappedSymbols(category: cat);
        final missing = <String>[];

        for (final item in mapped) {
          final norm = NasiraData.normalize(item.word.text);
          if (norm.length < 3) continue;
          final prefix      = norm.substring(0, 3);
          final suggestions = _data.searchByPrefix(prefix, limit: 20);
          if (!suggestions.any((w) => NasiraData.normalize(w.text) == norm)) {
            missing.add(item.word.text);
          }
        }

        if (missing.isEmpty) continue;
        final total = mapped.length;
        final pct   = ((total - missing.length) * 100 ~/ total);
        if (pct < 90) {
          final show = missing.take(8).join(', ');
          final more = missing.length > 8 ? ' + ${missing.length - 8} mehr' : '';
          print('  [$cat] $pct%: $show$more');
        }
      }
      print('');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 6. EMBEDDING-DIAGNOSE
  // ─────────────────────────────────────────────────────────────────────────
  group('6. Embedding-Diagnose', () {
    test('Cosinus-Ähnlichkeit: "computer" ↔ mau*-Kandidaten', () {
      print('\n[6a] Cosinus: "computer" ↔ Kandidaten');
      final emb = EmbeddingService.instance;
      final cVec = emb.vecFor('computer');
      if (cVec == null) { print('  ⚠ Kein Vektor für "computer"'); return; }

      final candidates = [
        'maus', 'mausklick', 'mauspfeil', 'mausklickrechts',
        'maulwurf', 'mauer', 'maurer', 'maul', 'tastatur', 'bildschirm',
      ];
      _printScores(emb, cVec, candidates);

      print('\n  → Für gutes Ranking muss cosine(computer, mausklick) '
          '> cosine(computer, maus)');
      final simKlick = emb.vecFor('mausklick');
      final simMaus  = emb.vecFor('maus');
      if (simKlick != null && simMaus != null) {
        final diff = _cosine(cVec, simKlick) - _cosine(cVec, simMaus);
        print('  Differenz (mausklick - maus): '
            '${diff >= 0 ? "+" : ""}${diff.toStringAsFixed(4)} '
            '${diff >= 0 ? "✓" : "✗ → Gewicht erhöhen nötig"}');
      }
    });

    test('Kontextvektor "computer + maus" → ähnlichste Kandidaten', () {
      print('\n[6b] Avg-Vektor "computer"+"maus" ↔ Kandidaten');
      final emb = EmbeddingService.instance;
      final v1  = emb.vecFor('computer');
      final v2  = emb.vecFor('maus');
      if (v1 == null || v2 == null) { print('  ⚠ Vektoren fehlen'); return; }

      final avgVec    = _avgVec([v1, v2]);
      final candidates = [
        'mausklick', 'mauspfeil', 'tastatur', 'computerspiel',
        'maus', 'maulwurf', 'hund', 'katze', 'bildschirm', 'drucker',
      ];
      _printScores(emb, avgVec, candidates);
    });

    test('Ranking-Formel Analyse: warum kommt maus vor mausklick?', () {
      print('\n[6c] Score-Analyse (40% cosine + 60% rank)');
      final emb     = EmbeddingService.instance;
      final cVec    = emb.vecFor('computer');
      if (cVec == null) { print('  ⚠ Kein Vektor'); return; }

      final candidates = ['maus', 'mausklick', 'mauspfeil', 'mauer', 'maulwurf'];
      print('  ${"Wort".padRight(20)} rank  rankScore  cosSim    total');
      print('  ${"─" * 62}');
      for (final word in candidates) {
        final entry = _data.words.firstWhere(
          (w) => NasiraData.normalize(w.text) == NasiraData.normalize(word),
          orElse: () => WordEntry(id: '', text: word, rank: 99999),
        );
        final vec       = emb.vecFor(NasiraData.normalize(word));
        final cosSim    = vec != null ? _cosine(cVec, vec).clamp(0.0, 1.0) : 0.0;
        final rankScore = 1.0 / (1.0 + math.log(entry.rank.clamp(1, 1000000).toDouble()));
        final total     = 0.4 * cosSim + 0.6 * rankScore;
        print('  ${word.padRight(20)}'
            ' ${entry.rank.toString().padLeft(5)}'
            '  ${rankScore.toStringAsFixed(4).padLeft(9)}'
            '  ${cosSim.toStringAsFixed(4).padLeft(7)}'
            '  ${total.toStringAsFixed(4).padLeft(7)}');
      }
      print('');
      print('  → Wenn "maus" immer noch vorne ist, Cosinus-Gewicht von 40%');
      print('    auf 60% oder 70% erhöhen in _contextAwarePrefixSearch()');
    });
  });
}

// ── Hilfsmethode: Scores ausgeben ─────────────────────────────────────────────

void _printScores(EmbeddingService emb, Float32List refVec, List<String> words) {
  final scores = <String, double>{};
  for (final word in words) {
    final vec = emb.vecFor(word);
    if (vec != null) scores[word] = _cosine(refVec, vec);
  }
  final sorted = scores.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  for (final e in sorted) {
    final bar = _bar((e.value.clamp(0.0, 1.0) * 20).round(), 20);
    print('    ${e.key.padRight(22)} $bar  ${e.value.toStringAsFixed(4)}');
  }
}
