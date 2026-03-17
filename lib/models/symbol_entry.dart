/// Ein Metacom-Symbol mit Dateipfad und Kategorie.
///
/// Das [label] ist der menschenlesbare Name (z. B. "spielen"),
/// [fileName] der tatsächliche Dateiname im Asset-Ordner
/// (z. B. "Verben/spielen.jpg").
class SymbolEntry {
  final String id;
  final String label;
  final String fileName;
  final String category;

  const SymbolEntry({
    required this.id,
    required this.label,
    required this.fileName,
    this.category = 'Sonstiges',
  });

  /// Asset-Pfad relativ zum Flutter-Projekt.
  String get assetPath => 'assets/metacom/$fileName';

  factory SymbolEntry.fromJson(Map<String, dynamic> json) {
    final rawCategory = (json['category'] as String?)?.trim() ?? '';
    return SymbolEntry(
      id: json['id'] as String,
      label: json['label'] as String,
      fileName: json['fileName'] as String,
      category: rawCategory.isNotEmpty ? rawCategory : 'Sonstiges',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'fileName': fileName,
        'category': category,
      };

  @override
  String toString() =>
      'SymbolEntry(id: "$id", label: "$label", file: "$fileName")';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is SymbolEntry && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
