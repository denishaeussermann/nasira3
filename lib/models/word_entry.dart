/// Ein Wort im Nasira-Grundwortschatz.
///
/// Jeder Eintrag hat eine eindeutige [id], den Anzeigetext [text],
/// einen [rank] (1 = häufigstes Wort) und optionale [nextWords]
/// für kontextbasierte Folgewort-Vorschläge.
class WordEntry {
  final String id;
  final String text;
  final int rank;
  final List<String> nextWords;

  const WordEntry({
    required this.id,
    required this.text,
    required this.rank,
    this.nextWords = const [],
  });

  /// Synthetischer Eintrag für Wörter, die nicht in der Wortliste stehen
  /// (z. B. Partizip-II-Formen wie "gespielt").
  factory WordEntry.synthetic(String text) {
    return WordEntry(
      id: 'synthetic_${text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '')}',
      text: text,
      rank: 9999,
    );
  }

  factory WordEntry.fromJson(Map<String, dynamic> json) {
    return WordEntry(
      id: json['id'] as String,
      text: json['text'] as String,
      rank: json['rank'] as int,
      nextWords: (json['nextWords'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'rank': rank,
        'nextWords': nextWords,
      };

  bool get isSynthetic => id.startsWith('synthetic_');

  @override
  String toString() => 'WordEntry(id: "$id", text: "$text", rank: $rank)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is WordEntry && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
