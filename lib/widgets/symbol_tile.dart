import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../nasira_app_state.dart';
import '../nasira_repository.dart';
import 'composite_symbol.dart';

/// Universelle Wort-Kachel mit automatischer Symbol-Suche.
///
/// Zeigt Symbol (Metacom oder farbiges Buchstaben-Tile) + Text.
/// Sucht das Symbol asynchron über [NasiraAppState.cachedLookup].
class SymbolTile extends StatelessWidget {
  final String text;
  final VoidCallback onTap;
  final Color? tileColor;

  const SymbolTile({
    super.key,
    required this.text,
    required this.onTap,
    this.tileColor,
  });

  @override
  Widget build(BuildContext context) {
    final state = context.watch<NasiraAppState>();
    return FutureBuilder<NasiraLoadResult>(
      future: state.futureLoad,
      builder: (context, snap) {
        final sym = snap.hasData ? state.cachedLookup(snap.data!.data, text) : null;
        final path = sym != null ? state.assetResolver.resolveForSymbol(sym) : null;
        final plural = state.isPlural(text);
        return Material(
          color: tileColor ?? Colors.white,
          borderRadius: BorderRadius.circular(12),
          elevation: 2,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 4, 4),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Expanded(
                    child: Center(
                      child: CompositeSymbolWidget(
                        assetPath1: path,
                        isPlural: plural,
                        fallbackText: text,
                        size: 56,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1A1A2E),
                      height: 1.1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
