/// Zentrale Textnormalisierung für Nasira.
///
/// Behandelt das Kernproblem: Umlaute können in zwei Unicode-Formen
/// vorliegen:
///
/// - **NFC** (precomposed): `ö` = ein Zeichen (U+00F6)
/// - **NFD** (decomposed): `ö` = `o` + combining diaeresis (U+0308)
///
/// Wenn ein Wort als NFD gespeichert ist, greift `replaceAll('ö', 'oe')`
/// nicht — das `ö` im Code ist NFC, aber der Text enthält NFD.
/// Ergebnis: "möchte" wird zu "mchte" statt "moechte".
///
/// Diese Klasse löst beide Formen auf, bevor sie ersetzt.
class TextNormalizer {
  /// Combining Diaeresis (U+0308) — das "¨" als eigenständiges Zeichen.
  static const String _combiningDiaeresis = '\u0308';

  /// Alle Combining Diacritical Marks: Unicode-Block U+0300–U+036F.
  static final RegExp _combiningMarks = RegExp(r'[\u0300-\u036F]');

  /// Stufe 1: Lowercase + Umlaute/ß auflösen.
  ///
  /// Behandelt sowohl NFC (ö) als auch NFD (o + ◌̈) korrekt.
  /// Entfernt danach alle verbleibenden Combining Marks.
  ///
  /// Beispiele:
  /// - `"Möchte"` → `"moechte"` (egal ob NFC oder NFD)
  /// - `"Straße"` → `"strasse"`
  /// - `"über"` → `"ueber"`
  static String normalize(String input) {
    var s = input.trim().toLowerCase();

    // 1. NFD-Formen auflösen (Basisbuchstabe + Combining Diaeresis)
    s = s
        .replaceAll('a$_combiningDiaeresis', 'ae')
        .replaceAll('o$_combiningDiaeresis', 'oe')
        .replaceAll('u$_combiningDiaeresis', 'ue');

    // 2. NFC-Formen auflösen (precomposed Umlaute)
    s = s
        .replaceAll('ä', 'ae')
        .replaceAll('ö', 'oe')
        .replaceAll('ü', 'ue')
        .replaceAll('ß', 'ss');

    // 3. Verbleibende Combining Marks entfernen
    //    (z.B. Akzente aus Fremdwörtern: café → cafe)
    s = s.replaceAll(_combiningMarks, '');

    return s;
  }

  /// Stufe 2: Wie [normalize], aber zusätzlich alle Nicht-Buchstaben
  /// und Nicht-Ziffern entfernen.
  ///
  /// Beispiele:
  /// - `"CT / MRT"` → `"ctmrt"`
  /// - `"A bis Z"` → `"abisz"`
  static String strip(String input) {
    return normalize(input).replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  /// Prüft ob ein String NFD-Combining-Marks enthält.
  ///
  /// Nützlich für Debugging: wenn `true`, ist der String nicht
  /// in NFC-Form und würde ohne diese Normalisierung Probleme machen.
  static bool containsDecomposed(String input) {
    return _combiningMarks.hasMatch(input);
  }
}
