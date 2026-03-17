/// Verknüpfung zwischen einem [WordEntry] und einem [SymbolEntry].
///
/// Entspricht einer Zeile in mappings.json.
class WordSymbolMapping {
  final String wordId;
  final String symbolId;

  const WordSymbolMapping({
    required this.wordId,
    required this.symbolId,
  });

  factory WordSymbolMapping.fromJson(Map<String, dynamic> json) {
    return WordSymbolMapping(
      wordId: json['wordId'] as String,
      symbolId: json['symbolId'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
        'wordId': wordId,
        'symbolId': symbolId,
      };

  @override
  String toString() =>
      'WordSymbolMapping(word: "$wordId", symbol: "$symbolId")';
}
