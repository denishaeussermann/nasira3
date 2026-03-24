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
    final fileName   = json['fileName'] as String;

    // "Nomen & Sonstiges" ist eine Catch-All-Kategorie aus dem Importer.
    // Wir leiten die echte Kategorie aus dem Dateipfad ab:
    //   "Tiere\maus.jpg"    → "Tiere"
    //   "Computer/maus.jpg" → "Computer"
    final String category;
    if (rawCategory.isEmpty || rawCategory == 'Nomen & Sonstiges') {
      final parts = fileName.replaceAll('\\', '/').split('/');
      category = parts.length > 1 ? parts.first : 'Sonstiges';
    } else {
      category = rawCategory;
    }

    return SymbolEntry(
      id: json['id'] as String,
      label: json['label'] as String,
      fileName: fileName,
      category: category,
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
