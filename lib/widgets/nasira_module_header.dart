import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../nasira_app_state.dart';
import 'nasira_text_workspace.dart';

// ── NasiraModuleHeader ────────────────────────────────────────────────────────
//
// Einheitliche Kopfzeile für alle 4 Module (Brief, Tagebuch, Einkaufen,
// Freies Schreiben):
//
//  ┌──────┬──────────────────────────────┬──────────┐
//  │ Home │                              │ Wort lös.│
//  ├──────┤  Text-Workspace (scrollbar)  ├──────────┤
//  │ Back │                              │ Drucken  │
//  └──────┴──────────────────────────────┴──────────┘
//
// Wort löschen: Kurz → letztes Wort löschen.
//               Lang  → Bestätigungs-Dialog „Alles löschen?" (3 s Auto-Close).
//
// onForward: Falls gesetzt, ersetzt „Drucken" durch einen Vorwärts-Pfeil
//            (wird im Brief-Modul genutzt).

class NasiraModuleHeader extends StatefulWidget {
  final TextEditingController controller;
  final Color accentColor;

  /// Wird auf den Zurück-Button gelegt.
  /// null → Navigator.pop(context).
  final VoidCallback? onBack;

  /// Wird auf den vorderen rechten Slot gelegt (Brief-Modul: nächster Schritt).
  /// null → Drucken-Platzhalter.
  final VoidCallback? onForward;

  /// Falls gesetzt: drittes Recht-Button (Hamburger ≡) für Seiteneditor.
  final VoidCallback? onMenu;

  /// Wenn true, wird der Vorwärts-Pfeil als Oval (Ellipse) dargestellt —
  /// signalisiert „Zurück zum Inhalts-Hub" statt sequentiellem Vorwärts.
  final bool isForwardOval;

  /// FocusNode für USB-Tastatureingabe (FreiesSchreiben).
  final FocusNode? focusNode;
  final bool readOnly;
  final bool autofocus;

  const NasiraModuleHeader({
    super.key,
    required this.controller,
    required this.accentColor,
    this.onBack,
    this.onForward,
    this.onMenu,
    this.isForwardOval = false,
    this.focusNode,
    this.readOnly = true,
    this.autofocus = false,
  });

  @override
  State<NasiraModuleHeader> createState() => _NasiraModuleHeaderState();
}

class _NasiraModuleHeaderState extends State<NasiraModuleHeader> {

  // ── Alles-löschen mit Bestätigung ─────────────────────────────────────────

  Future<void> _confirmClearAll() async {
    Timer? timer;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        timer = Timer(const Duration(seconds: 3), () {
          if (ctx.mounted) Navigator.pop(ctx, false);
        });
        return AlertDialog(
          title: const Text('Alles löschen?'),
          content: const Text(
            'Soll der gesamte Text wirklich gelöscht werden?\n'
            '(Dialog schließt sich automatisch nach 3 Sekunden.)',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Nein'),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Ja, löschen'),
            ),
          ],
        );
      },
    );

    timer?.cancel();
    if ((confirmed ?? false) && mounted) {
      context.read<NasiraAppState>().clearText();
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final color  = widget.accentColor;
    final onBack = widget.onBack ?? () => Navigator.pop(context);

    return SizedBox(
      height: 180,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Links: Home + Zurück ─────────────────────────────────────────
          SizedBox(
            width: 80,
            child: Column(
              children: [
                Expanded(
                  child: _ModuleButton(
                    icon: Icons.home_rounded,
                    color: color,
                    onTap: () =>
                        Navigator.of(context).popUntil((r) => r.isFirst),
                  ),
                ),
                const SizedBox(height: 2),
                Expanded(
                  child: _ModuleButton(
                    icon: Icons.arrow_back_rounded,
                    color: color,
                    onTap: onBack,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 2),

          // ── Mitte: Text-Workspace ────────────────────────────────────────
          Expanded(
            child: NasiraTextWorkspace(
              controller: widget.controller,
              focusNode: widget.focusNode,
              readOnly: widget.readOnly,
              autofocus: widget.autofocus,
              minHeight: 0,
              maxHeight: double.infinity,
            ),
          ),

          const SizedBox(width: 2),

          // ── Rechts: Wort löschen + Vorwärts/Drucken + ggf. Menü ────────
          SizedBox(
            width: 80,
            child: Column(
              children: [
                Expanded(
                  child: _ModuleButton(
                    icon: Icons.backspace_outlined,
                    color: color,
                    onTap: () => context.read<NasiraAppState>().deleteLastWord(),
                    onLongPress: _confirmClearAll,
                  ),
                ),
                if (widget.onMenu != null) ...[
                  const SizedBox(height: 2),
                  Expanded(
                    child: _ModuleButton(
                      icon: Icons.menu_rounded,
                      color: color,
                      onTap: widget.onMenu,
                    ),
                  ),
                ],
                const SizedBox(height: 2),
                Expanded(
                  child: widget.onForward != null
                      ? _ModuleButton(
                          icon: Icons.arrow_forward_rounded,
                          color: color,
                          isOval: widget.isForwardOval,
                          onTap: widget.onForward,
                        )
                      : _ModuleButton(
                          icon: Icons.print_rounded,
                          label: 'Drucken',
                          color: color,
                          onTap: () => ScaffoldMessenger.of(context)
                              .showSnackBar(const SnackBar(
                            content: Text('Druckfunktion nicht verfügbar'),
                            duration: Duration(seconds: 2),
                          )),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Hilfs-Widget: einzelne Schaltfläche ───────────────────────────────────────

class _ModuleButton extends StatelessWidget {
  final IconData icon;
  final String? label;
  final Color color;
  final bool isOval;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const _ModuleButton({
    required this.icon,
    required this.color,
    this.label,
    this.isOval = false,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final radius = isOval ? BorderRadius.circular(1000) : null;
    return Material(
      color: color,
      borderRadius: radius,
      clipBehavior: isOval ? Clip.antiAlias : Clip.none,
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        onLongPress: onLongPress,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 28),
            if (label != null) ...[
              const SizedBox(height: 4),
              Text(
                label!,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
