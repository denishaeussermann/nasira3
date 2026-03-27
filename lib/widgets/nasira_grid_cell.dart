import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../nasira_app_state.dart';
import '../nasira_repository.dart';
import '../theme/nasira_colors.dart';
import 'composite_symbol.dart';

/// Universelle Grid3-Stil Zelle — wird in allen Screens verwendet.
///
/// Zeigt ein optionales Symbol (via Engine-Lookup oder direktem Asset-Pfad)
/// und eine Beschriftung. Visuell passend zum Original Grid3 Nasira.
class NasiraGridCell extends StatelessWidget {
  final String? caption;
  final String? symbolWord;
  final String? assetPath;
  final IconData? icon;
  final Color backgroundColor;
  final Color textColor;
  final double fontSize;
  final VoidCallback? onTap;
  final double borderRadius;
  final double? elevation;

  const NasiraGridCell({
    super.key,
    this.caption,
    this.symbolWord,
    this.assetPath,
    this.icon,
    this.backgroundColor = NasiraColors.navGreen,
    this.textColor = Colors.white,
    this.fontSize = 13,
    this.onTap,
    this.borderRadius = 8,
    this.elevation,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(borderRadius),
      elevation: elevation ?? 2,
      child: InkWell(
        borderRadius: BorderRadius.circular(borderRadius),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 6, 4, 4),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_hasVisual) ...[
                Expanded(child: _buildVisual(context)),
                const SizedBox(height: 3),
              ],
              if (caption != null && caption!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Text(
                    caption!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: fontSize,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                      height: 1.15,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  bool get _hasVisual =>
      symbolWord != null || assetPath != null || icon != null;

  Widget _buildVisual(BuildContext context) {
    // Direkter Asset-Pfad
    if (assetPath != null) {
      return Image.asset(
        assetPath!,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => _iconOrEmpty(),
      );
    }

    // Icon
    if (icon != null && symbolWord == null) {
      return Center(child: Icon(icon, color: textColor, size: 36));
    }

    // Engine-Lookup
    if (symbolWord != null) {
      return _SymbolLookup(
        word: symbolWord!,
        fallbackIcon: icon,
        iconColor: textColor,
      );
    }

    return const SizedBox.shrink();
  }

  Widget _iconOrEmpty() {
    if (icon != null) {
      return Center(child: Icon(icon, color: textColor, size: 36));
    }
    return const SizedBox.shrink();
  }
}

/// Interner Widget: Sucht Symbol über Engine, zeigt Bild oder Fallback.
class _SymbolLookup extends StatelessWidget {
  final String word;
  final IconData? fallbackIcon;
  final Color iconColor;

  const _SymbolLookup({
    required this.word,
    this.fallbackIcon,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final state = context.watch<NasiraAppState>();
    return FutureBuilder<NasiraLoadResult>(
      future: state.futureLoad,
      builder: (ctx, snap) {
        if (!snap.hasData) {
          return fallbackIcon != null
              ? Center(child: Icon(fallbackIcon, color: iconColor, size: 36))
              : const SizedBox.shrink();
        }
        final data = snap.data!.data;
        final sym = state.cachedLookup(data, word);
        final path =
            sym != null ? state.assetResolver.resolveForSymbol(sym) : null;
        if (path != null) {
          return Image.asset(
            path,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => CompositeSymbolWidget(
              fallbackText: word,
              size: 40,
            ),
          );
        }
        return CompositeSymbolWidget(fallbackText: word, size: 40);
      },
    );
  }
}
