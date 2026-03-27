import 'package:flutter/material.dart';
import '../theme/nasira_colors.dart';

/// Navigationsleiste im Grid3-Stil — einheitlich in allen Screens.
///
/// Zeigt Home, Zurück, Vorwärts, Wort-Löschen und optional weitere Aktionen
/// in den Originalfarben (Oliv-Grün oder Taupe).
class NasiraNavBar extends StatelessWidget {
  final VoidCallback? onHome;
  final VoidCallback? onBack;
  final VoidCallback? onForward;
  final VoidCallback? onDeleteWord;
  final VoidCallback? onClear;
  final bool showHome;
  final bool showBack;
  final bool showForward;
  final bool showDeleteWord;
  final bool showClear;
  final Color backgroundColor;
  final List<Widget> extraActions;

  const NasiraNavBar({
    super.key,
    this.onHome,
    this.onBack,
    this.onForward,
    this.onDeleteWord,
    this.onClear,
    this.showHome = true,
    this.showBack = false,
    this.showForward = false,
    this.showDeleteWord = true,
    this.showClear = false,
    this.backgroundColor = NasiraColors.navGreen,
    this.extraActions = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      color: backgroundColor,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          if (showHome)
            _NavButton(
              icon: Icons.home_rounded,
              tooltip: 'Startseite',
              onTap: onHome ?? () => Navigator.of(context).popUntil((r) => r.isFirst),
            ),
          if (showBack)
            _NavButton(
              icon: Icons.arrow_back_rounded,
              tooltip: 'Zurück',
              onTap: onBack,
            ),
          const Spacer(),
          ...extraActions,
          if (showDeleteWord)
            _NavButton(
              icon: Icons.backspace_outlined,
              tooltip: 'Wort löschen',
              onTap: onDeleteWord,
            ),
          if (showClear)
            _NavButton(
              icon: Icons.clear_rounded,
              tooltip: 'Text löschen',
              onTap: onClear,
            ),
          if (showForward)
            _NavButton(
              icon: Icons.arrow_forward_rounded,
              tooltip: 'Weiter',
              onTap: onForward,
            ),
        ],
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  const _NavButton({
    required this.icon,
    required this.tooltip,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: IconButton(
        icon: Icon(icon, color: Colors.white, size: 26),
        tooltip: tooltip,
        onPressed: onTap,
      ),
    );
  }
}
