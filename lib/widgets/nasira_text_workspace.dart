import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../nasira_app_state.dart';
import '../nasira_repository.dart';
import '../theme/nasira_colors.dart';
import 'composite_symbol.dart';

// ── NasiraTextWorkspace ────────────────────────────────────────────────────────
//
// Zeigt den zusammengesetzten Text mit Metacom-Symbolen über jedem Wort.
// Scrollbar bei längerem Text.  Mindestens 3 Zeilen (Symbol+Wort) sichtbar.
//
// readOnly: false → unsichtbares TextField für USB-Tastatureingabe eingebettet.

class NasiraTextWorkspace extends StatelessWidget {
  final TextEditingController controller;
  final Color borderColor;
  final double minHeight;
  final double maxHeight;
  final bool readOnly;
  final FocusNode? focusNode;
  final bool autofocus;

  const NasiraTextWorkspace({
    super.key,
    required this.controller,
    this.borderColor = NasiraColors.fsBorder,
    this.minHeight = 160,
    this.maxHeight = 240,
    this.readOnly = true,
    this.focusNode,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    final state = context.watch<NasiraAppState>();
    return Container(
      width: double.infinity,
      constraints: BoxConstraints(minHeight: minHeight, maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: borderColor, width: 2),
      ),
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          // ── USB-Tastatur-Capture: unsichtbares, fokussierbares TextField ──
          if (!readOnly)
            Opacity(
              opacity: 0.0,
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                autofocus: autofocus,
                maxLines: null,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                style: const TextStyle(fontSize: 1, color: Colors.transparent),
                cursorColor: Colors.transparent,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
          // ── Symbol+Text-Anzeige (scrollbar, Tap fokussiert Eingabe) ───────
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: (!readOnly && focusNode != null)
                ? () => focusNode!.requestFocus()
                : null,
            child: _SymbolTextDisplay(controller: controller, state: state),
          ),
        ],
      ),
    );
  }
}

// ── _SymbolTextDisplay ─────────────────────────────────────────────────────────

class _SymbolTextDisplay extends StatelessWidget {
  final TextEditingController controller;
  final NasiraAppState state;

  const _SymbolTextDisplay({
    required this.controller,
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<NasiraLoadResult>(
      future: state.futureLoad,
      builder: (ctx, snap) {
        final NasiraData? data = snap.data?.data;

        return AnimatedBuilder(
          animation: controller,
          builder: (_, __) {
            final text = controller.text.trim();

            if (text.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Text(
                  'Hier entsteht der Text \u2026',
                  style: TextStyle(color: Colors.grey.shade400, fontSize: 15),
                ),
              );
            }

            final tokens =
                text.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();

            return Padding(
              padding: const EdgeInsets.all(8),
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 4,
                  runSpacing: 8,
                  children: tokens
                      .map((token) => _buildToken(token, data))
                      .toList(),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildToken(String token, NasiraData? data) {
    final clean =
        token.replaceAll(RegExp(r'[^\wäöüÄÖÜß]'), '');

    String? path;
    bool plural = false;

    if (data != null && clean.length >= 2) {
      final sym = state.cachedLookup(data, clean);
      path =
          sym != null ? state.assetResolver.resolveForSymbol(sym) : null;
      plural = state.isPlural(clean);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          height: 36,
          width: 44,
          child: CompositeSymbolWidget(
            assetPath1: path,
            isPlural: plural,
            fallbackText: clean.length >= 2 ? clean : '',
            size: 30,
          ),
        ),
        const SizedBox(height: 1),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 54),
          child: Text(
            token,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 10,
              height: 1.1,
              color: NasiraColors.textDark,
            ),
          ),
        ),
      ],
    );
  }
}
