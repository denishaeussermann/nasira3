/// Art des Suchtreffers in der Fallback-Kette.
///
/// Die Reihenfolge entspricht der Priorität:
/// [exact] > [normalized] > [fileName] > [stripped] > [prefix] >
/// [alias] > [partizip] > [none].
enum SearchMatchType {
  /// Exakter Treffer auf normalisiertem Text.
  exact,

  /// Treffer nach Unicode-Normalisierung (NFC/NFD, Umlaute).
  normalized,

  /// Treffer über den Dateinamen des Symbols.
  fileName,

  /// Treffer nach Entfernung aller Sonderzeichen.
  stripped,

  /// Präfix-Treffer (Eingabe ist Anfang eines Wortes).
  prefix,

  /// Treffer über Alias-Tabelle (Konjugation, Pronomen-Varianten).
  alias,

  /// Treffer über Partizip-II → Grundform Auflösung.
  partizip,

  /// Treffer nach Entfernung von Flexionsendungen (-e, -er, -es, -en, -em).
  stemmed,

  /// Kein Treffer gefunden.
  none,
}

/// Ergebnis einer Symbolsuche mit Debug-Informationen.
///
/// Enthält die Originaleingabe, die normalisierte Form, den gefundenen
/// Treffer, die Fallback-Stufe und optional eine Debug-Begründung.
class SearchResult {
  final String query;
  final String normalizedQuery;
  final String matchedWord;
  final String assetPath;
  final SearchMatchType matchType;
  final double score;
  final String? debugInfo;
  final DateTime timestamp;

  SearchResult({
    required this.query,
    required this.normalizedQuery,
    required this.matchedWord,
    required this.assetPath,
    required this.matchType,
    required this.score,
    this.debugInfo,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Leeres Ergebnis für eine gescheiterte Suche.
  factory SearchResult.empty(String query, {String normalizedQuery = ''}) {
    return SearchResult(
      query: query,
      normalizedQuery: normalizedQuery.isEmpty ? query : normalizedQuery,
      matchedWord: '',
      assetPath: '',
      matchType: SearchMatchType.none,
      score: 0.0,
      debugInfo: 'Kein Treffer gefunden',
    );
  }

  bool get hasMatch => matchType != SearchMatchType.none;

  /// Einzeiliges Log-Format für Debug-Ausgabe.
  String toLogLine() =>
      '[${matchType.name.toUpperCase().padRight(8)}] '
      '"$query" → '
      '${hasMatch ? '"$matchedWord" (${score.toStringAsFixed(1)})' : '---'}'
      '${debugInfo != null ? '  // $debugInfo' : ''}';

  @override
  String toString() =>
      'SearchResult('
      'query: "$query", '
      'matched: "$matchedWord", '
      'type: ${matchType.name}, '
      'score: ${score.toStringAsFixed(2)}'
      ')';
}
