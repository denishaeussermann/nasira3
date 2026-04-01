import 'package:flutter/material.dart';
import '../theme/nasira_colors.dart';

/// Konsistente Titelleiste für alle Modul-Screens.
///
/// Links:  Hamburger-Menü (öffnet Layout-Editor für die aktuelle Seite).
/// Mitte:  "Nasira" (zentriert).
/// Rechts: Symmetrie-Spacer (gleiche Breite wie Hamburger).
///
/// [onMenuTap] ist `null` → Hamburger wird ausgegraut dargestellt.
class NasiraTitleBar extends StatelessWidget {
  final VoidCallback? onMenuTap;
  final Color backgroundColor;

  const NasiraTitleBar({
    super.key,
    this.onMenuTap,
    this.backgroundColor = NasiraColors.startseite,
  });

  @override
  Widget build(BuildContext context) {
    final active = onMenuTap != null;
    return SizedBox(
      height: 44,
      child: ColoredBox(
        color: backgroundColor,
        child: Row(
          children: [
            // ── Hamburger ────────────────────────────────────────────────
            SizedBox(
              width: 44,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onMenuTap,
                  child: Center(
                    child: Icon(
                      Icons.menu_rounded,
                      color: active ? Colors.white : Colors.white30,
                      size: 22,
                    ),
                  ),
                ),
              ),
            ),
            // ── Titel ────────────────────────────────────────────────────
            const Expanded(
              child: Center(
                child: Text(
                  'Nasira',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
            // ── Symmetrie-Spacer ─────────────────────────────────────────
            const SizedBox(width: 44),
          ],
        ),
      ),
    );
  }
}
