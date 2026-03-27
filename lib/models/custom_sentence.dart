/// Ein benutzerdefinierter Satz mit optionalen Symbol-Inhaltswörtern,
/// der im Setup vom Einrichtenden erstellt werden kann.
class CustomSentence {
  final String id;
  final String sentence;
  final String? contentWord1;
  final String? contentWord2;

  /// Zielmodul: 'brief', 'tagebuch' oder 'alle'
  final String moduleTarget;

  const CustomSentence({
    required this.id,
    required this.sentence,
    this.contentWord1,
    this.contentWord2,
    this.moduleTarget = 'alle',
  });

  factory CustomSentence.fromJson(Map<String, dynamic> json) {
    return CustomSentence(
      id: json['id'] as String,
      sentence: json['sentence'] as String,
      contentWord1: json['contentWord1'] as String?,
      contentWord2: json['contentWord2'] as String?,
      moduleTarget: (json['moduleTarget'] as String?) ?? 'alle',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sentence': sentence,
      if (contentWord1 != null) 'contentWord1': contentWord1,
      if (contentWord2 != null) 'contentWord2': contentWord2,
      'moduleTarget': moduleTarget,
    };
  }

  CustomSentence copyWith({
    String? id,
    String? sentence,
    String? contentWord1,
    String? contentWord2,
    String? moduleTarget,
  }) {
    return CustomSentence(
      id: id ?? this.id,
      sentence: sentence ?? this.sentence,
      contentWord1: contentWord1 ?? this.contentWord1,
      contentWord2: contentWord2 ?? this.contentWord2,
      moduleTarget: moduleTarget ?? this.moduleTarget,
    );
  }
}
