import 'package:flutter/foundation.dart';

import '../models/models.dart';

/// Protokolliert alle Suchvorgänge für Debugging und Analyse.
///
/// Speichert die letzten [maxEntries] Suchergebnisse im Ringpuffer
/// und gibt jedes Ergebnis über [debugPrint] aus.
class SearchLogService {
  final int maxEntries;
  final List<SearchResult> _log = [];

  SearchLogService({this.maxEntries = 500});

  /// Protokolliert ein Suchergebnis.
  void log(SearchResult result) {
    _log.add(result);
    if (_log.length > maxEntries) {
      _log.removeAt(0);
    }
    debugPrint(result.toLogLine());
  }

  /// Alle protokollierten Ergebnisse (älteste zuerst).
  List<SearchResult> get entries => List.unmodifiable(_log);

  /// Die letzten [count] Einträge (neueste zuerst).
  List<SearchResult> recent({int count = 20}) {
    final start = (_log.length - count).clamp(0, _log.length);
    return _log.sublist(start).reversed.toList();
  }

  /// Nur Fehlschläge (kein Treffer).
  List<SearchResult> get misses => _log.where((r) => !r.hasMatch).toList();

  /// Statistik: Wie oft wurde jede Match-Stufe getroffen?
  Map<SearchMatchType, int> get matchTypeStats {
    final stats = <SearchMatchType, int>{};
    for (final r in _log) {
      stats[r.matchType] = (stats[r.matchType] ?? 0) + 1;
    }
    return stats;
  }

  /// Anzahl aller protokollierten Suchen.
  int get totalCount => _log.length;

  /// Anzahl der Treffer.
  int get hitCount => _log.where((r) => r.hasMatch).length;

  /// Anzahl der Fehlschläge.
  int get missCount => _log.where((r) => !r.hasMatch).length;

  /// Trefferquote als Prozentwert (0.0 – 100.0).
  double get hitRate => _log.isEmpty ? 0.0 : (hitCount / _log.length) * 100.0;

  /// Protokoll leeren.
  void clear() => _log.clear();

  /// Zusammenfassung als mehrzeiliger String.
  String get summary => 'Suchen: $totalCount | '
      'Treffer: $hitCount | '
      'Fehlschläge: $missCount | '
      'Quote: ${hitRate.toStringAsFixed(1)}%';
}
