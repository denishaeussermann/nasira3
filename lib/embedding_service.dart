import 'dart:isolate';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class EmbeddingService {
  static EmbeddingService? _instance;
  static EmbeddingService get instance => _instance!;

  final Map<String, Float32List> _symbolKeys;
  final Map<String, Float32List> _symbolClean;
  final Map<String, Float32List> _queryVecs;
  final Map<String, String?> _cache = {};
  final Map<String, List<String>> _neighborCache = {};

  /// Vorberechnete semantische Karte: normalisiertes Eingabewort → Symbol-Key.
  /// Wird von build_semantic_map.py generiert (assets/nasira_semantic_map.bin).
  /// Ermöglicht O(1)-Lookup für Ableitungen und Komposita (z.B. müdigkeit → muede).
  final Map<String, String> _semanticMap;

  EmbeddingService._(
    this._symbolKeys,
    this._symbolClean,
    this._queryVecs,
    this._semanticMap,
  );

  static Future<Map<String, Float32List>> _loadKeys(String asset) async {
    final bytes = await rootBundle.load(asset);
    final buf   = bytes.buffer;
    final bd    = buf.asByteData();
    int offset  = 0;

    int readI32() { final v = bd.getInt32(offset, Endian.little); offset += 4; return v; }
    int readU16() { final v = bd.getUint16(offset, Endian.little); offset += 2; return v; }
    String readStr() {
      final len = readU16();
      final s = String.fromCharCodes(buf.asUint8List(offset, len));
      offset += len;
      return s;
    }
    Float32List readVec() {
      final v = Float32List(300);
      for (int i = 0; i < 300; i++) { v[i] = bd.getFloat32(offset, Endian.little); offset += 4; }
      return v;
    }

    final n = readI32();
    final byKey = <String, Float32List>{};
    for (int i = 0; i < n; i++) {
      final key   = readStr().toLowerCase();
      readStr(); // clean ignorieren
      final vec   = readVec();
      byKey[key]  = vec;
    }
    return byKey;
  }

  /// Lädt die vorberechnete semantische Karte (nasira_semantic_map.bin).
  /// Format: int32 n, dann n × (uint16+bytes word, uint16+bytes symbol_key)
  static Future<Map<String, String>> _loadSemanticMap() async {
    try {
      final bytes  = await rootBundle.load('assets/nasira_semantic_map.bin');
      final buf    = bytes.buffer;
      final bd     = buf.asByteData();
      int offset   = 0;

      int readU16()   { final v = bd.getUint16(offset, Endian.little); offset += 2; return v; }
      String readStr() {
        final len = readU16();
        final s   = String.fromCharCodes(buf.asUint8List(offset, len));
        offset   += len;
        return s;
      }

      final n   = bd.getInt32(offset, Endian.little); offset += 4;
      final map = <String, String>{};
      for (int i = 0; i < n; i++) {
        final word   = readStr();
        final symKey = readStr();
        map[word]    = symKey;
      }
      debugPrint('[EmbeddingService] ${map.length} semantische Mappings geladen');
      return map;
    } catch (e) {
      debugPrint('[EmbeddingService] Semantic Map nicht gefunden – nur Cosine-Fallback aktiv');
      return {};
    }
  }

  static Future<void> init() async {
    // Symbol-Vektoren – zum Vergleichen per Cosine
    final bytes    = await rootBundle.load('assets/nasira_embeddings.bin');
    final buf      = bytes.buffer;
    final bd       = buf.asByteData();
    final fileSize = buf.lengthInBytes;
    debugPrint('[EmbeddingService] ${(fileSize/1024/1024).toStringAsFixed(2)} MiB');

    int offset = 0;
    int readI32() { final v = bd.getInt32(offset, Endian.little); offset += 4; return v; }
    int readU16() { final v = bd.getUint16(offset, Endian.little); offset += 2; return v; }
    String readStr() {
      final len = readU16();
      final s = String.fromCharCodes(buf.asUint8List(offset, len));
      offset += len;
      return s;
    }
    Float32List readVec() {
      final v = Float32List(300);
      for (int i = 0; i < 300; i++) { v[i] = bd.getFloat32(offset, Endian.little); offset += 4; }
      return v;
    }

    final n = readI32();
    if (n < 0 || n > 25000) throw Exception('Ungueltige Eintragsanzahl: $n');

    final symbolKeys  = <String, Float32List>{};
    final symbolClean = <String, Float32List>{};
    for (int i = 0; i < n; i++) {
      final key   = readStr().toLowerCase();
      final clean = readStr().toLowerCase();
      final vec   = readVec();
      symbolKeys[key] = vec;
      for (final w in clean.split(RegExp(r'\s+'))) {
        if (w.isNotEmpty) symbolClean[w] = vec;
      }
    }
    debugPrint('[EmbeddingService] ${symbolKeys.length} Keys geladen');

    // Query-Vektoren – für Kontext-Scoring in SuggestionEngine
    Map<String, Float32List> queryVecs = {};
    try {
      queryVecs = await _loadKeys('assets/nasira_query_embeddings.bin');
      debugPrint('[EmbeddingService] ${queryVecs.length} Query-Vektoren geladen');
    } catch (e) {
      debugPrint('[EmbeddingService] Query-Embeddings nicht gefunden: $e');
    }

    // Semantische Karte – vorberechnete Wort→Symbol-Mappings (offline gebaut)
    final semanticMap = await _loadSemanticMap();

    _instance = EmbeddingService._(symbolKeys, symbolClean, queryVecs, semanticMap);
  }

  // Erst Query-Vecs (für Eingabe), dann Symbol-Vecs, dann null
  Float32List? vecFor(String word) {
    final w = _norm(word);
    return _queryVecs[w] ?? _symbolKeys[w] ?? _symbolClean[w];
  }

  static double _cosine(Float32List a, Float32List b) {
    double dot = 0, na = 0, nb = 0;
    for (int i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      na  += a[i] * a[i];
      nb  += b[i] * b[i];
    }
    if (na == 0 || nb == 0) return 0;
    return dot / math.sqrt(na * nb);
  }

  static String _norm(String word) => word.toLowerCase()
      .replaceAll('ä', 'ae').replaceAll('ö', 'oe').replaceAll('ü', 'ue')
      .replaceAll('ß', 'ss').replaceAll('Ä', 'ae').replaceAll('Ö', 'oe')
      .replaceAll('Ü', 'ue');

  String? findNearestSymbolSync(String word, {double threshold = 0.35}) {
    if (word.length < 4) return null;
    final w = _norm(word);

    // 1. Semantische Karte (O(1), vorberechnet)
    final mapped = _semanticMap[w];
    if (mapped != null) return mapped;

    // 2. Cosine-Suche als Fallback
    if (_cache.containsKey(w)) return _cache[w];
    final vec = vecFor(w);
    if (vec == null) { _cache[w] = null; return null; }

    String? bestKey;
    double  bestSim = threshold;
    for (final entry in _symbolKeys.entries) {
      final sim = _cosine(vec, entry.value);
      if (sim > bestSim) { bestSim = sim; bestKey = entry.key; if (bestSim > 0.92) break; }
    }
    _cache[w] = bestKey;
    return bestKey;
  }

  /// Gibt die [k] semantisch ähnlichsten Symbol-Keys zurück (gecached).
  /// Wird von der SuggestionEngine für Embedding-Expansion genutzt.
  List<String> topKNeighbors(String word, {int k = 20, double threshold = 0.45}) {
    final w = _norm(word);
    if (!_neighborCache.containsKey(w)) {
      final vec = vecFor(w);
      if (vec == null) {
        _neighborCache[w] = [];
      } else {
        final scores = <(String, double)>[];
        for (final entry in _symbolKeys.entries) {
          if (entry.key == w) continue;
          final sim = _cosine(vec, entry.value);
          if (sim > threshold) scores.add((entry.key, sim));
        }
        scores.sort((a, b) => b.$2.compareTo(a.$2));
        _neighborCache[w] = scores.map((e) => e.$1).toList();
      }
    }
    final cached = _neighborCache[w]!;
    return cached.length <= k ? cached : cached.sublist(0, k);
  }

  Future<String?> findNearestSymbolAsync(String word, {double threshold = 0.35}) async {
    if (word.length < 4) return null;
    final w = _norm(word);

    // 1. Semantische Karte (O(1), vorberechnet — keine async nötig)
    final mapped = _semanticMap[w];
    if (mapped != null) {
      debugPrint('[Embedding] "$w" -> "$mapped" (SemanticMap)');
      return mapped;
    }

    // 2. Cosine-Suche als Fallback (für Wörter außerhalb der Karte)
    if (_cache.containsKey(w)) return _cache[w];
    final vec = vecFor(w);
    if (vec == null) { _cache[w] = null; return null; }

    final keys   = _symbolKeys.keys.toList();
    final vecs   = _symbolKeys.values.toList();
    final result = await Isolate.run(() => _searchInIsolate(vec, keys, vecs, threshold));

    _cache[w] = result;
    if (result != null) debugPrint('[Embedding] "$w" -> "$result" (Cosine)');
    return result;
  }

  static String? _searchInIsolate(
    Float32List queryVec,
    List<String> keys,
    List<Float32List> vecs,
    double threshold,
  ) {
    String? bestKey;
    double  bestSim = threshold;
    for (int i = 0; i < keys.length; i++) {
      final sim = _cosine(queryVec, vecs[i]);
      if (sim > bestSim) { bestSim = sim; bestKey = keys[i]; if (bestSim > 0.92) break; }
    }
    return bestKey;
  }
}
