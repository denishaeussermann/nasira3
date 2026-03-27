import 'package:flutter/material.dart';

// ── Inhaltsworte-Extraktion ────────────────────────────────────────────────────

/// Deutsche Stoppwörter, die bei der Inhaltsworterkennung übersprungen werden.
const _stopwords = {
  'ich', 'du', 'er', 'sie', 'es', 'wir', 'ihr', 'man',
  'mich', 'dich', 'sich', 'uns', 'euch', 'mir', 'dir', 'ihm',
  'bin', 'ist', 'sind', 'war', 'waren', 'hat', 'habe', 'hast', 'hatte',
  'ein', 'eine', 'einer', 'einem', 'einen', 'eines', 'kein', 'keine',
  'der', 'die', 'das', 'dem', 'den', 'des',
  'und', 'oder', 'aber', 'weil', 'wenn', 'dann', 'also', 'doch',
  'auch', 'auf', 'in', 'an', 'für', 'mit', 'von', 'zu', 'bei', 'aus',
  'über', 'unter', 'nach', 'vor', 'wie', 'was', 'wer', 'dass', 'ob',
  'nicht', 'mehr', 'noch', 'schon', 'sehr', 'ganz', 'mal', 'so', 'ja',
  'heute', 'morgen', 'gestern', 'immer', 'bitte', 'danke',
  'wars', 'gibt', 'geht',
};

/// Extrahiert bis zu [max] Inhaltsworte aus einem deutschen Satz.
///
/// Überspringt Stoppwörter und Kurzwörter (< 3 Zeichen).
/// Gibt die Wörter in Originalschreibweise zurück (vor Lower-Case-Prüfung).
List<String> extractContentWords(String sentence, {int max = 2}) {
  final tokens = sentence.split(RegExp(r'\s+'));
  final result = <String>[];
  for (final token in tokens) {
    if (result.length >= max) break;
    final clean = token.replaceAll(RegExp(r'[^\wäöüÄÖÜß]'), '');
    if (clean.length < 3) continue;
    if (_stopwords.contains(clean.toLowerCase())) continue;
    result.add(clean);
  }
  return result;
}

// ── CompositeSymbolWidget ──────────────────────────────────────────────────────

/// Rendert 1–2 Metacom-Symbole in einer Kachel.
///
/// Verhalten:
/// - [assetPath1] == null  → Text-Fallback mit [fallbackText]
/// - [isPlural] == true    → [assetPath1] wird zweimal versetzt übereinander
///                           gerendert (Plural-Doppelrender)
/// - [assetPath2] != null  → beide Symbole nebeneinander (Komposit-Kachel)
class CompositeSymbolWidget extends StatelessWidget {
  final String? assetPath1;
  final String? assetPath2;
  final bool isPlural;
  final String fallbackText;
  final double size;

  const CompositeSymbolWidget({
    super.key,
    this.assetPath1,
    this.assetPath2,
    this.isPlural = false,
    this.fallbackText = '',
    this.size = 44,
  });

  @override
  Widget build(BuildContext context) {
    if (assetPath1 == null) {
      return _fallback(context);
    }

    if (isPlural) {
      return _buildPluralDouble(context, assetPath1!);
    }

    if (assetPath2 != null) {
      return _buildComposite(context, assetPath1!, assetPath2!);
    }

    return _buildSingle(context, assetPath1!);
  }

  // ── Einzel-Symbol ───────────────────────────────────────────────────────────

  Widget _buildSingle(BuildContext context, String path) {
    return Image.asset(
      path,
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => _fallback(context),
    );
  }

  // ── Plural-Doppelrender ─────────────────────────────────────────────────────

  Widget _buildPluralDouble(BuildContext context, String path) {
    final offset = size * 0.28;
    final imgSize = size * 0.78;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          // Hinteres Symbol (links-oben, leicht transparent)
          Positioned(
            left: 0,
            top: 0,
            child: Opacity(
              opacity: 0.75,
              child: Image.asset(
                path,
                width: imgSize,
                height: imgSize,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => _fallback(context),
              ),
            ),
          ),
          // Vorderes Symbol (rechts-unten)
          Positioned(
            left: offset,
            top: offset,
            child: Image.asset(
              path,
              width: imgSize,
              height: imgSize,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => _fallback(context),
            ),
          ),
        ],
      ),
    );
  }

  // ── Komposit: zwei Symbole nebeneinander ────────────────────────────────────

  Widget _buildComposite(
      BuildContext context, String path1, String path2) {
    return SizedBox(
      width: size,
      height: size,
      child: Row(
        children: [
          Expanded(
            child: Image.asset(
              path1,
              height: size,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
          Expanded(
            child: Image.asset(
              path2,
              height: size,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }

  // ── Text-Fallback ───────────────────────────────────────────────────────────

  Widget _fallback(BuildContext context) {
    if (fallbackText.isEmpty) return SizedBox(width: size, height: size);
    final initial = fallbackText.trim().isEmpty ? '?' : fallbackText.trim()[0].toUpperCase();
    // Deterministisch: Farbe aus dem Hash des Texts ableiten
    final hash = fallbackText.codeUnits.fold(0, (a, b) => (a * 31 + b) & 0x7FFFFFFF);
    final hue = (hash % 320).toDouble(); // 0-320, vermeidet Rot für non-stop-Wörter
    final tileColor = HSLColor.fromAHSL(1.0, hue, 0.55, 0.42).toColor();
    return SizedBox(
      width: size,
      height: size,
      child: Container(
        decoration: BoxDecoration(
          color: tileColor,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Text(
            initial,
            style: TextStyle(
              fontSize: size * 0.5,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              height: 1.0,
            ),
          ),
        ),
      ),
    );
  }
}
