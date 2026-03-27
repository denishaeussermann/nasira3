import 'dart:math' as math;
import 'dart:typed_data';

import '../embedding_service.dart';
import '../models/models.dart';
import '../nasira_import_service.dart';

/// Berechnet Wortvorschläge basierend auf dem aktuellen Textinhalt.
///
/// Prioritäten:
/// 1. Satzfortsetzung (Muster wie "ich möchte" → essen, trinken...)
/// 2. Redewendungen/Satzmuster (NasiraContextService)
/// 3. Kontext-Muster (Hilfsverb → Partizip, Modalverb → Infinitiv)
/// 4. Präfix-Suche auf aktuellem Token
/// 5. Kategorie-Vorschläge (nach "werkzeug" → hammer, säge...)
/// 6. nextWordSuggestions nach letztem abgeschlossenem Wort
/// 7. Initiale Vorschläge (häufigste Wörter)
class SuggestionEngine {
  static const int defaultLimit = 14;

  // Gecachte normalisierte Wort-Suche: normText → WordEntry.
  // Wird lazily aus NasiraData aufgebaut, damit die Embedding-Expansion
  // in O(1) auf WordEntry-Instanzen zugreifen kann.
  Map<String, WordEntry>? _wordIndex;
  Map<String, WordEntry> _getWordIndex(NasiraData data) {
    return _wordIndex ??= {
      for (final w in data.words) NasiraData.normalize(w.text): w,
    };
  }

  /// Kategorien, die als Funktionswörter gelten.
  /// Werden bei der Kontext-Kategorie-Erkennung übersprungen,
  /// damit z.B. "gern" nach "essen" nicht die Kategorie bestimmt.
  static const Set<String> _functionWordCategories = {
    'Kleine_Worte',
    'Pronomen',
    'Fragewörter',
    'Konjunktionen',
  };

  /// Prüft ob ein Wort ein Dateipfad oder ungültig ist.
  static bool _isValidWord(WordEntry w) {
    final t = w.text;
    return !t.contains('\\') &&
        !t.contains('/') &&
        !t.endsWith('.jpg') &&
        !t.endsWith('.png') &&
        t.length <= 50;
  }

  /// Gibt die Kategorie eines Wortes zurück — zuerst aus NasiraData,
  /// dann aus dem Symbol-Cache (enthält Stufe-7-Ergebnisse).
  static String? _categoryFor(
    String word,
    NasiraData data,
    Map<String, MappedSymbol?>? cache,
  ) {
    final direct = data.categoryForWordFuzzy(word);
    if (direct != null) return direct;
    if (cache == null) return null;
    final key = word.toLowerCase().trim().replaceAll(RegExp(r'[^\wäöüß]'), '');
    return cache[key]?.symbol.category;
  }

  /// Berechnet Vorschläge für den aktuellen Text.
  ///
  /// [symbolCache] — optionaler Symbol-Cache aus der UI (enthält
  /// bereits berechnete Stufe-7-Ergebnisse für bereits gesehene Wörter).
  List<WordEntry> computeSuggestions(
    NasiraData data,
    String text, {
    Map<String, MappedSymbol?>? symbolCache,
  }) {
    if (text.trim().isEmpty) {
      return _filtered(data.initialSuggestions(limit: defaultLimit + 10));
    }

    final endsWithWhitespace = RegExp(r'\s$').hasMatch(text);
    final tokens = _tokenize(text);

    if (tokens.isEmpty) {
      return _filtered(data.initialSuggestions(limit: defaultLimit + 10));
    }

    final completedTokens =
        endsWithWhitespace ? tokens : tokens.sublist(0, tokens.length - 1);
    final currentPartial = endsWithWhitespace ? '' : tokens.last;

    // ── Schritt 1: Satzfortsetzung (Pattern-basiert) ──────────────
    if (endsWithWhitespace && completedTokens.isNotEmpty) {
      final continuation = _sentenceContinuation(data, completedTokens);
      if (continuation.isNotEmpty) return continuation;
    }

    // ── Schritt 2: Redewendungen prüfen ───────────────────────────
    final phraseWords =
        NasiraContextService.phraseCompletions(completedTokens);
    if (phraseWords.isNotEmpty) {
      final results = _wordsFromStrings(data, phraseWords, currentPartial);
      if (results.isNotEmpty) return _filtered(results);
    }

    // ── Schritt 3: Kontext-Muster prüfen ──────────────────────────
    final contextWords = NasiraContextService.contextSuggestions(
      completedTokens,
      currentPartial,
    );
    if (contextWords.isNotEmpty) {
      final results = _wordsFromStrings(data, contextWords, currentPartial);
      if (results.isNotEmpty) return _filtered(results);
    }

    // ── Schritt 4: Kontextbewusste Präfix-Suche ───────────────────
    if (!endsWithWhitespace && currentPartial.isNotEmpty) {
      final prefixResults = _contextAwarePrefixSearch(
          data, currentPartial, completedTokens, symbolCache);
      if (prefixResults.isNotEmpty) return prefixResults;
    }

    // ── Schritt 5+6: nextWord + Kategorie + Embedding-Expansion ──
    // Die drei Quellen werden kombiniert und dann per Embedding re-ranked,
    // damit z.B. nach "auto" nicht nur andere Fahrzeuge, sondern auch
    // semantisch verwandte Wörter wie "fahren", "straße", "parken" erscheinen.
    if (endsWithWhitespace && completedTokens.isNotEmpty) {
      final pool = <WordEntry>{};

      // A) nextWord nach letztem Token
      data
          .nextWordSuggestions(completedTokens.last, limit: defaultLimit + 10)
          .where(_isValidWord)
          .forEach(pool.add);

      // B) Kategorie-Pool aus den letzten 3 Inhaltswort-Tokens
      int contentAdded = 0;
      for (final token in completedTokens.reversed) {
        if (contentAdded >= 3) break;
        final cat = _categoryFor(token, data, symbolCache);
        if (cat == null || cat == 'Sonstiges' || _functionWordCategories.contains(cat)) {
          continue;
        }
        data.wordsInSameCategory(token, limit: 30)
            .where(_isValidWord)
            .forEach(pool.add);
        contentAdded++;
      }

      // C) Embedding-Expansion: semantisch ähnliche Wörter aus dem
      // gesamten Vokabular (kategorie-übergreifend, gecached).
      try {
        final emb = EmbeddingService.instance;
        final lastNorm = NasiraData.normalize(completedTokens.last);
        final index = _getWordIndex(data);
        for (final key in emb.topKNeighbors(lastNorm)) {
          final w = index[key];
          if (w != null && _isValidWord(w)) pool.add(w);
        }
      } catch (_) {}

      if (pool.isNotEmpty) {
        return _reRankByContext(pool.toList(), completedTokens, data, symbolCache);
      }
    }

    return _filtered(data.initialSuggestions(limit: defaultLimit + 10));
  }

  // ── Satzfortsetzung ─────────────────────────────────────────────────

  List<WordEntry> _sentenceContinuation(
      NasiraData data, List<String> completedTokens) {
    final last = NasiraData.normalize(completedTokens.last);
    final lastTwo = completedTokens.length >= 2
        ? '${NasiraData.normalize(completedTokens[completedTokens.length - 2])} $last'
        : '';
    final lastThree = completedTokens.length >= 3
        ? '${NasiraData.normalize(completedTokens[completedTokens.length - 3])} $lastTwo'
        : '';

    List<String>? suggestions;
    suggestions = _continuationPatterns3[lastThree];
    suggestions ??= _continuationPatterns2[lastTwo];
    suggestions ??= _continuationPatterns1[last];

    if (suggestions == null || suggestions.isEmpty) return [];

    return _filtered(_wordsFromStrings(data, suggestions, ''));
  }

  // ── Kontextbewusstes Re-Ranking ─────────────────────────────────────

  List<WordEntry> _reRankByContext(
    List<WordEntry> candidates,
    List<String> completedTokens,
    NasiraData data,
    Map<String, MappedSymbol?>? symbolCache,
  ) {
    if (completedTokens.isEmpty) return candidates.take(defaultLimit).toList();

    EmbeddingService? emb;
    try { emb = EmbeddingService.instance; } catch (_) {}
    if (emb == null) return candidates.take(defaultLimit).toList();

    final contextVecs = completedTokens.reversed
        .take(5)
        .map((t) => emb!.vecFor(NasiraData.normalize(t)))
        .whereType<Float32List>()
        .toList();
    if (contextVecs.isEmpty) return candidates.take(defaultLimit).toList();
    final contextVec = _avgVec(contextVecs);

    final contextCategory = completedTokens.reversed
        .take(5)
        .map((t) => _categoryFor(t, data, symbolCache))
        .firstWhere(
          (c) =>
              c != null &&
              c != 'Sonstiges' &&
              !_functionWordCategories.contains(c),
          orElse: () => null,
        );

    final scored = candidates.map((w) {
      final wVec = emb!.vecFor(NasiraData.normalize(w.text));
      final contextSim =
          wVec != null ? _cosine(contextVec, wVec).clamp(0.0, 1.0) : 0.0;
      final rankScore = 1.0 / (1.0 + math.log(w.rank.clamp(1, 1000000).toDouble()));
      final wordCat   = _categoryFor(w.text, data, symbolCache);
      final catBonus  = (contextCategory != null && wordCat == contextCategory) ? 0.3 : 0.0;
      return (w, 0.5 * contextSim + 0.2 * rankScore + catBonus);
    }).toList()
      ..sort((a, b) => b.$2.compareTo(a.$2));

    return scored.map((s) => s.$1).take(defaultLimit).toList();
  }

  // ── Kontextbewusste Präfix-Suche ────────────────────────────────────

  List<WordEntry> _contextAwarePrefixSearch(
    NasiraData data,
    String partial,
    List<String> completedTokens,
    Map<String, MappedSymbol?>? symbolCache,
  ) {
    final candidates = data
        .searchByPrefix(partial, limit: 60)
        .where(_isValidWord)
        .toList();
    if (candidates.isEmpty) return [];

    // Ohne Kontext: reine Rank-Reihenfolge
    if (completedTokens.isEmpty) return candidates.take(defaultLimit).toList();

    EmbeddingService? emb;
    try { emb = EmbeddingService.instance; } catch (_) {}
    if (emb == null) return candidates.take(defaultLimit).toList();

    // Kontextvektor = Durchschnitt der letzten 5 abgeschlossenen Tokens
    final contextVecs = completedTokens.reversed
        .take(5)
        .map((t) => emb!.vecFor(NasiraData.normalize(t)))
        .whereType<Float32List>()
        .toList();
    if (contextVecs.isEmpty) return candidates.take(defaultLimit).toList();
    final contextVec = _avgVec(contextVecs);

    // Kontext-Kategorie: erste Inhaltswort-Kategorie der letzten 5 Tokens
    // (Funktionswörter wie Kleine_Worte, Pronomen werden übersprungen)
    final contextCategory = completedTokens.reversed
        .take(5)
        .map((t) => _categoryFor(t, data, symbolCache))
        .firstWhere(
          (c) =>
              c != null &&
              c != 'Sonstiges' &&
              !_functionWordCategories.contains(c),
          orElse: () => null,
        );

    // Score = Kontext-Ähnlichkeit + Frequenz-Rank + Kategorie-Bonus
    final scored = candidates.map((w) {
      final wVec = emb!.vecFor(NasiraData.normalize(w.text));
      final contextSim =
          wVec != null ? _cosine(contextVec, wVec).clamp(0.0, 1.0) : 0.0;
      final rankScore = 1.0 / (1.0 + math.log(w.rank.clamp(1, 1000000).toDouble()));
      final wordCat   = _categoryFor(w.text, data, symbolCache);
      final catBonus  = (contextCategory != null && wordCat == contextCategory) ? 0.3 : 0.0;
      return (w, 0.5 * contextSim + 0.2 * rankScore + catBonus);
    }).toList()
      ..sort((a, b) => b.$2.compareTo(a.$2));

    return scored.map((s) => s.$1).take(defaultLimit).toList();
  }

  static Float32List _avgVec(List<Float32List> vecs) {
    final result = Float32List(300);
    for (final v in vecs) {
      for (int i = 0; i < 300; i++) { result[i] += v[i]; }
    }
    final n = vecs.length.toDouble();
    for (int i = 0; i < 300; i++) { result[i] /= n; }
    return result;
  }

  static double _cosine(Float32List a, Float32List b) {
    double dot = 0, na = 0, nb = 0;
    for (int i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      na += a[i] * a[i];
      nb += b[i] * b[i];
    }
    if (na == 0 || nb == 0) return 0;
    return dot / math.sqrt(na * nb);
  }

  // ── Hilfsmethoden ───────────────────────────────────────────────────

  List<WordEntry> _filtered(List<WordEntry> input) {
    return input.where(_isValidWord).take(defaultLimit).toList();
  }

  List<String> _tokenize(String text) {
    return text
        .trim()
        .split(RegExp(r'\s+'))
        .where((e) => e.trim().isNotEmpty)
        .toList();
  }

  List<WordEntry> _wordsFromStrings(
    NasiraData data,
    List<String> wordStrings,
    String currentPartial,
  ) {
    final result = <WordEntry>[];
    final partialNorm = NasiraData.normalize(currentPartial);

    for (final word in wordStrings) {
      final wordNorm = NasiraData.normalize(word);

      if (partialNorm.isNotEmpty && !wordNorm.startsWith(partialNorm)) {
        continue;
      }

      final existing = data.words
          .where((w) => NasiraData.normalize(w.text) == wordNorm)
          .firstOrNull;

      if (existing != null) {
        result.add(existing);
      } else {
        result.add(WordEntry.synthetic(word));
      }
    }

    return result;
  }

  // ── Satz-Fortsetzungsmuster ─────────────────────────────────────────

  static const _continuationPatterns3 = <String, List<String>>{
    'ich moechte gerne': ['essen', 'trinken', 'spielen', 'schlafen', 'gehen', 'haben', 'machen'],
    'ich will nicht': ['essen', 'trinken', 'schlafen', 'gehen', 'arbeiten', 'warten'],
    'ich bin sehr': ['muede', 'hungrig', 'traurig', 'froh', 'gluecklich', 'krank', 'wuetend'],
    'ich habe keine': ['angst', 'lust', 'zeit', 'ahnung', 'kraft'],
    'ich habe grosse': ['angst', 'freude', 'lust', 'hunger', 'schmerzen'],
    'das ist sehr': ['gut', 'schlecht', 'schoen', 'toll', 'wichtig', 'schwer', 'einfach', 'lustig'],
    'es ist sehr': ['gut', 'schlecht', 'schoen', 'kalt', 'warm', 'laut', 'still', 'dunkel'],
    'er ist sehr': ['nett', 'lustig', 'stark', 'muede', 'krank', 'traurig', 'froh'],
    'sie ist sehr': ['nett', 'lustig', 'stark', 'muede', 'krank', 'traurig', 'froh', 'schoen'],
    'wir gehen in': ['die', 'den', 'das', 'schule', 'haus', 'garten', 'wald'],
    'ich gehe in': ['die', 'den', 'das', 'schule', 'haus', 'kueche', 'bad'],
    'wie geht es': ['dir', 'euch', 'ihnen', 'ihm', 'ihr'],
    'es tut mir': ['leid', 'weh'],
    'kannst du mir': ['helfen', 'bitte', 'sagen', 'zeigen', 'geben'],
    'ich brauche ein': ['glas', 'brot', 'buch', 'bild', 'taschentuch'],
    'ich brauche eine': ['pause', 'frage', 'antwort', 'hilfe'],
  };

  static const _continuationPatterns2 = <String, List<String>>{
    'ich moechte': ['essen', 'trinken', 'spielen', 'schlafen', 'gehen', 'haben', 'bitte', 'nach'],
    'ich will': ['essen', 'trinken', 'spielen', 'schlafen', 'gehen', 'haben', 'nicht', 'nach'],
    'ich kann': ['nicht', 'das', 'gut', 'schlafen', 'essen', 'laufen', 'schwimmen'],
    'ich muss': ['essen', 'trinken', 'schlafen', 'gehen', 'arbeiten', 'lernen', 'auf'],
    'ich soll': ['essen', 'trinken', 'schlafen', 'gehen', 'lernen', 'helfen', 'warten'],
    'ich darf': ['nicht', 'das', 'essen', 'spielen', 'gehen', 'raus'],
    'ich bin': ['muede', 'hungrig', 'traurig', 'froh', 'krank', 'hier', 'fertig', 'da'],
    'ich habe': ['hunger', 'durst', 'angst', 'schmerzen', 'keine', 'ein', 'eine'],
    'ich gehe': ['nach', 'in', 'zum', 'zur', 'raus', 'schlafen', 'einkaufen', 'heim'],
    'ich brauche': ['hilfe', 'wasser', 'essen', 'ruhe', 'zeit', 'ein', 'eine'],
    'ich mag': ['das', 'dich', 'nicht', 'essen', 'tiere', 'musik'],
    'ich finde': ['das', 'gut', 'schlecht', 'toll', 'schoen', 'lustig'],
    'ich weiss': ['nicht', 'es', 'das', 'schon'],
    'ich denke': ['ja', 'nein', 'nicht', 'schon', 'dass'],
    'ich glaube': ['ja', 'nein', 'nicht', 'das', 'schon'],
    'ich fuehle': ['mich', 'gut', 'schlecht'],
    'ich vermisse': ['dich', 'euch', 'mama', 'papa', 'mein'],
    'ich liebe': ['dich', 'euch', 'mama', 'papa', 'tiere', 'essen'],
    'du bist': ['nett', 'lieb', 'toll', 'gut', 'lustig', 'doof', 'mein'],
    'du kannst': ['das', 'gut', 'nicht', 'mir', 'helfen', 'gehen'],
    'du musst': ['essen', 'trinken', 'schlafen', 'gehen', 'lernen', 'aufpassen'],
    'du sollst': ['nicht', 'essen', 'trinken', 'aufpassen', 'zuhoeren'],
    'er ist': ['nett', 'lustig', 'muede', 'krank', 'hier', 'da', 'weg', 'gross'],
    'sie ist': ['nett', 'lustig', 'muede', 'krank', 'hier', 'da', 'schoen', 'gross'],
    'er hat': ['hunger', 'durst', 'angst', 'schmerzen', 'keine', 'ein', 'das'],
    'sie hat': ['hunger', 'durst', 'angst', 'schmerzen', 'keine', 'ein', 'das'],
    'wir gehen': ['nach', 'in', 'zum', 'zur', 'raus', 'einkaufen', 'spielen', 'heim'],
    'wir koennen': ['das', 'nicht', 'spielen', 'essen', 'gehen', 'zusammen'],
    'wir muessen': ['gehen', 'essen', 'schlafen', 'lernen', 'warten', 'los'],
    'wir sind': ['hier', 'da', 'fertig', 'muede', 'hungrig', 'froh', 'zusammen'],
    'wir haben': ['hunger', 'durst', 'angst', 'zeit', 'keine', 'ein'],
    'wir machen': ['das', 'essen', 'sport', 'musik', 'hausaufgaben', 'zusammen'],
    'das ist': ['gut', 'schlecht', 'schoen', 'toll', 'richtig', 'falsch', 'lustig', 'mein'],
    'das war': ['gut', 'schlecht', 'schoen', 'toll', 'lustig', 'richtig'],
    'es ist': ['gut', 'schlecht', 'kalt', 'warm', 'laut', 'still', 'zeit', 'fertig'],
    'es gibt': ['essen', 'trinken', 'ein', 'eine', 'viel', 'nichts', 'heute'],
    'wo ist': ['das', 'mein', 'die', 'der', 'mama', 'papa', 'toilette'],
    'wo sind': ['die', 'meine', 'wir', 'alle'],
    'was ist': ['das', 'los', 'passiert', 'denn'],
    'was machst': ['du'],
    'was machen': ['wir'],
    'wie geht': ['es'],
    'wie heisst': ['du', 'das', 'er', 'sie'],
    'darf ich': ['das', 'essen', 'trinken', 'spielen', 'gehen', 'raus', 'bitte'],
    'kann ich': ['das', 'haben', 'bitte', 'helfen', 'mitmachen', 'gehen'],
    'muss ich': ['das', 'jetzt', 'noch', 'wirklich'],
    'gibt es': ['essen', 'trinken', 'noch', 'etwas', 'hier', 'heute'],
    'ich esse': ['gerne', 'nicht', 'brot', 'obst', 'fleisch', 'suppe'],
    'ich trinke': ['wasser', 'saft', 'milch', 'tee', 'gerne', 'nicht'],
    'ich spiele': ['gerne', 'nicht', 'mit', 'draussen', 'drinnen', 'fussball'],
    'mir geht': ['es'],
    'mir ist': ['kalt', 'warm', 'schlecht', 'langweilig', 'gut'],
    'es tut': ['mir', 'weh'],
    'tut mir': ['leid', 'weh'],
    'bitte nicht': ['schlagen', 'schreien', 'weinen', 'aergern'],
  };

  static const _continuationPatterns1 = <String, List<String>>{
    'ich': ['bin', 'habe', 'will', 'moechte', 'kann', 'muss', 'gehe', 'brauche', 'mag'],
    'du': ['bist', 'hast', 'willst', 'kannst', 'musst', 'gehst', 'magst'],
    'er': ['ist', 'hat', 'will', 'kann', 'muss', 'geht', 'macht'],
    'sie': ['ist', 'hat', 'will', 'kann', 'muss', 'geht', 'macht', 'sind'],
    'es': ['ist', 'hat', 'gibt', 'geht', 'tut', 'war', 'regnet'],
    'wir': ['gehen', 'haben', 'sind', 'wollen', 'koennen', 'muessen', 'machen', 'spielen'],
    'ihr': ['seid', 'habt', 'wollt', 'koennt', 'muesst', 'geht', 'macht'],
    'der': ['hund', 'mann', 'junge', 'ball', 'tag', 'baum', 'bus', 'arzt'],
    'die': ['katze', 'frau', 'schule', 'mutter', 'blume', 'sonne', 'kinder'],
    'das': ['ist', 'haus', 'kind', 'buch', 'auto', 'essen', 'wasser', 'tier'],
    'ein': ['hund', 'mann', 'junge', 'ball', 'buch', 'auto', 'tier', 'problem'],
    'eine': ['katze', 'frau', 'blume', 'frage', 'idee', 'pause'],
    'in': ['der', 'die', 'das', 'den', 'dem', 'schule', 'haus'],
    'auf': ['der', 'die', 'das', 'den', 'dem', 'jeden', 'keinen'],
    'mit': ['mir', 'dir', 'ihm', 'ihr', 'uns', 'dem', 'der'],
    'fuer': ['mich', 'dich', 'uns', 'euch', 'alle', 'den', 'die'],
    'nach': ['hause', 'draussen', 'oben', 'unten', 'links', 'rechts'],
    'zum': ['arzt', 'essen', 'spielen', 'schlafen', 'beispiel'],
    'zur': ['schule', 'arbeit', 'toilette'],
    'und': ['ich', 'du', 'er', 'sie', 'wir', 'dann', 'auch', 'das'],
    'aber': ['ich', 'nicht', 'das', 'es', 'trotzdem', 'auch'],
    'weil': ['ich', 'du', 'er', 'sie', 'es', 'wir', 'das'],
    'wenn': ['ich', 'du', 'er', 'sie', 'es', 'wir', 'man'],
    'dass': ['ich', 'du', 'er', 'sie', 'es', 'wir', 'das'],
    'oder': ['nicht', 'auch', 'so', 'lieber'],
    'wo': ['ist', 'sind', 'bin', 'bist', 'war', 'wohnt'],
    'was': ['ist', 'machst', 'machen', 'willst', 'gibt'],
    'wann': ['gehen', 'kommen', 'essen', 'schlafen', 'ist'],
    'wie': ['geht', 'heisst', 'alt', 'viel', 'lange', 'gross'],
    'warum': ['nicht', 'ist', 'hast', 'bist', 'muss'],
    'wer': ['ist', 'hat', 'will', 'kann', 'bist'],
    'ja': ['bitte', 'genau', 'gerne', 'klar', 'gut', 'richtig', 'danke'],
    'nein': ['danke', 'bitte', 'nicht', 'nie', 'niemals'],
    'bitte': ['nicht', 'helfen', 'essen', 'trinken', 'geben', 'kommen', 'warten'],
    'danke': ['schoen', 'sehr', 'dir', 'euch', 'fuer'],
    'heute': ['gehen', 'machen', 'essen', 'spielen', 'ist', 'war'],
    'morgen': ['gehen', 'machen', 'ist', 'frueh', 'kommen'],
    'jetzt': ['gehen', 'essen', 'spielen', 'schlafen', 'nicht', 'sofort'],
    'hier': ['ist', 'sind', 'bin', 'bleiben', 'spielen'],
    'dort': ['ist', 'sind', 'war', 'gehen', 'bleiben'],
    'nicht': ['mehr', 'gut', 'schoen', 'richtig', 'so', 'jetzt', 'hier'],
    'noch': ['nicht', 'ein', 'eine', 'mehr', 'einmal', 'etwas'],
    'immer': ['noch', 'wieder', 'gut', 'gerne', 'so'],
    'auch': ['nicht', 'gut', 'gerne', 'noch', 'schon', 'so'],
    'so': ['gut', 'schlecht', 'schoen', 'viel', 'gross', 'nicht'],
    'sehr': ['gut', 'schlecht', 'schoen', 'gerne', 'viel', 'gross', 'nett'],
    'ganz': ['gut', 'schlecht', 'schoen', 'toll', 'genau', 'allein'],
    'essen': ['und', 'trinken', 'gehen', 'wir', 'bitte'],
    'trinken': ['und', 'essen', 'gehen', 'wir', 'bitte'],
    'spielen': ['und', 'mit', 'gehen', 'wir', 'draussen'],
    'schlafen': ['gehen', 'und', 'gut', 'schlecht', 'nicht'],
    'gehen': ['wir', 'nach', 'in', 'zum', 'zur', 'raus', 'zusammen'],
    'machen': ['wir', 'das', 'zusammen', 'gut', 'nichts'],
    'helfen': ['mir', 'dir', 'uns', 'bitte', 'beim'],
    'haben': ['wir', 'hunger', 'durst', 'angst', 'zeit', 'keine'],
    'wollen': ['wir', 'gehen', 'essen', 'spielen', 'nicht'],
  };
}
