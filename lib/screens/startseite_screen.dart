import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../nasira_app_state.dart';
import '../theme/nasira_colors.dart';
import '../widgets/nasira_grid_cell.dart';
import 'freies_schreiben_screen.dart';
import 'brief_screen.dart';
import 'tagebuch_screen.dart';
import 'einkaufen_screen.dart';
import 'setup_screen.dart';
import 'datei_screen.dart';

// ── Startseite ───────────────────────────────────────────────────────────────
//
// Nachbau des Grid3-Originals: 10×6, Hintergrund #171947.
// Zentrale Modul-Kacheln (Tagebuch, Brief, Einkaufen, Freies Schreiben)
// und untere Zeile (Einstellungen, Datei, Messaging).

class StartseiteScreen extends StatefulWidget {
  const StartseiteScreen({super.key});

  @override
  State<StartseiteScreen> createState() => _StartseiteScreenState();
}

class _StartseiteScreenState extends State<StartseiteScreen> {
  Future<void> _openAdminIfPinCorrect() async {
    final state = context.read<NasiraAppState>();
    await state.customSentences.load();
    if (!mounted) return;
    final ok = await showPinDialog(context, state.customSentences);
    if (ok == true && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const SetupScreen()),
      );
    }
  }

  void _push(Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NasiraColors.startseite,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            const gap = 6.0;
            return Padding(
              padding: const EdgeInsets.all(gap),
              child: Column(
                children: [
                  // ── Obere Zeile: Einstellungen + Titel ──────────────────
                  _buildTopRow(gap),
                  const SizedBox(height: gap),

                  // ── Hauptmodule (2 Zeilen) ──────────────────────────────
                  Expanded(
                    flex: 5,
                    child: _buildModuleGrid(gap),
                  ),
                  const SizedBox(height: gap),

                  // ── Untere Zeile: Datei + Messaging ─────────────────────
                  SizedBox(
                    height: 72,
                    child: _buildBottomRow(gap),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // ── Obere Zeile ──────────────────────────────────────────────────────────

  Widget _buildTopRow(double gap) {
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          // Einstellungen (Long-Press für Admin)
          SizedBox(
            width: 44,
            child: Material(
              color: NasiraColors.navTaupe,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onLongPress: _openAdminIfPinCorrect,
                child: const Icon(Icons.settings_outlined,
                    color: Colors.white, size: 22),
              ),
            ),
          ),
          SizedBox(width: gap),
          // Titel
          Expanded(
            child: Center(
              child: GestureDetector(
                onLongPress: _openAdminIfPinCorrect,
                child: const Text(
                  'Nasira',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
            ),
          ),
          SizedBox(width: gap),
          // Datenquelle
          SizedBox(
            width: 44,
            child: FutureBuilder(
              future: context.read<NasiraAppState>().futureLoad,
              builder: (ctx, snap) {
                if (!snap.hasData) return const SizedBox.shrink();
                return Tooltip(
                  message: snap.data!.sourceLabel,
                  child: const Icon(Icons.storage_outlined,
                      color: Colors.white38, size: 18),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── Modul-Grid (2 Zeilen × 3 Spalten) ────────────────────────────────────

  Widget _buildModuleGrid(double gap) {
    return Column(
      children: [
        // Zeile 1: Tagebuch, Brief, Einkaufen
        Expanded(
          child: Row(
            children: [
              _modulCell('Tagebuch', Icons.menu_book_rounded,
                  () => _push(const TagebuchScreen()),
                  flex: 1),
              SizedBox(width: gap),
              _modulCell('Brief', Icons.mail_rounded,
                  () => _push(const BriefScreen()),
                  flex: 1),
              SizedBox(width: gap),
              _modulCell('Einkaufen', Icons.shopping_cart_rounded,
                  () => _push(const EinkaufenScreen()),
                  flex: 1),
            ],
          ),
        ),
        SizedBox(height: gap),
        // Zeile 2: Freies Schreiben (breit, zentriert)
        Expanded(
          child: Row(
            children: [
              const Spacer(flex: 1),
              Expanded(
                flex: 4,
                child: NasiraGridCell(
                  caption: 'Freies Schreiben',
                  icon: Icons.edit_note_rounded,
                  backgroundColor: NasiraColors.moduleDarkGreen,
                  textColor: Colors.white,
                  fontSize: 16,
                  onTap: () => _push(const FreiesSchreibenScreen()),
                ),
              ),
              const Spacer(flex: 1),
            ],
          ),
        ),
      ],
    );
  }

  Widget _modulCell(String label, IconData icon, VoidCallback onTap,
      {int flex = 1}) {
    return Expanded(
      flex: flex,
      child: NasiraGridCell(
        caption: label,
        icon: icon,
        backgroundColor: NasiraColors.moduleDarkGreen,
        textColor: Colors.white,
        fontSize: 14,
        onTap: onTap,
      ),
    );
  }

  // ── Untere Zeile: Datei + Einstellungen ───────────────────────────────────

  Widget _buildBottomRow(double gap) {
    return Row(
      children: [
        // Einstellungen (Long-Press für Admin)
        _smallCell(
          icon: Icons.grid_view_rounded,
          label: 'Raster',
          color: NasiraColors.navTaupe,
          onTap: _openAdminIfPinCorrect,
        ),
        SizedBox(width: gap),
        _smallCell(
          icon: Icons.folder_outlined,
          label: 'Datei',
          color: NasiraColors.navTaupe,
          onTap: () async {
            final state = context.read<NasiraAppState>();
            final text = state.textController.text.trim();
            if (text.isNotEmpty) {
              await state.documentService.saveDocument(text);
            }
            if (!mounted) return;
            Navigator.push(context,
                MaterialPageRoute(builder: (_) => const DateiScreen()));
          },
        ),
        SizedBox(width: gap),
        const Spacer(flex: 2),
        SizedBox(width: gap),
        _smallCell(
          icon: Icons.send_rounded,
          label: 'Telegram',
          color: NasiraColors.telegramDark,
          onTap: () {}, // Messaging-Placeholder
        ),
        SizedBox(width: gap),
        _smallCell(
          icon: Icons.chat_rounded,
          label: 'WhatsApp',
          color: const Color(0xFF25D366),
          onTap: () {},
        ),
      ],
    );
  }

  Widget _smallCell({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: 72,
      child: NasiraGridCell(
        caption: label,
        icon: icon,
        backgroundColor: color,
        textColor: Colors.white,
        fontSize: 9,
        onTap: onTap,
      ),
    );
  }
}
