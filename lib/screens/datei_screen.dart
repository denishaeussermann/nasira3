import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../nasira_app_state.dart';
import '../services/services.dart';
import '../theme/nasira_colors.dart';
import '../widgets/nasira_nav_bar.dart';
import '../widgets/nasira_text_workspace.dart';

// ── DateiScreen ───────────────────────────────────────────────────────────────
//
// Dokumentenverwaltung: Sidebar (Docliste) + Hauptbereich (Symbol-Anzeige).
// Aktionen: Neues Dokument, Weiter schreiben, Kopieren, Löschen.

class DateiScreen extends StatefulWidget {
  const DateiScreen({super.key});

  @override
  State<DateiScreen> createState() => _DateiScreenState();
}

class _DateiScreenState extends State<DateiScreen> {
  int? _selectedIndex;
  final TextEditingController _previewController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final docs = context.read<NasiraAppState>().documentService.documents;
      if (docs.isNotEmpty) {
        _selectDoc(0, docs[0]);
      }
    });
  }

  @override
  void dispose() {
    _previewController.dispose();
    super.dispose();
  }

  void _selectDoc(int index, SavedDocument doc) {
    setState(() {
      _selectedIndex = index;
      _previewController.text = doc.text;
    });
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> _neuesDokument(NasiraAppState state) async {
    final text = state.textController.text.trim();
    if (text.isNotEmpty) {
      await state.documentService.saveDocument(text);
      state.clearText();
    }
    if (!mounted) return;
    Navigator.pop(context);
  }

  void _weiterSchreiben(NasiraAppState state, SavedDocument doc) {
    state.textController.text = doc.text;
    Navigator.pop(context);
  }

  void _kopieren(SavedDocument doc) {
    Clipboard.setData(ClipboardData(text: doc.text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Text in Zwischenablage kopiert.'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _loeschen(NasiraAppState state, int index) async {
    await state.documentService.deleteDocument(index);
    final docs = state.documentService.documents;
    if (docs.isEmpty) {
      setState(() {
        _selectedIndex = null;
        _previewController.clear();
      });
    } else {
      final newIndex = index < docs.length ? index : docs.length - 1;
      _selectDoc(newIndex, docs[newIndex]);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Dokument gelöscht.'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _allesLoeschen(NasiraAppState state) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Alle Dokumente löschen?'),
        content:
            const Text('Dieser Vorgang kann nicht rückgängig gemacht werden.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Alle löschen',
                style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await state.documentService.deleteAll();
      setState(() {
        _selectedIndex = null;
        _previewController.clear();
      });
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final state = context.watch<NasiraAppState>();
    final docs = state.documentService.documents;

    return Scaffold(
      backgroundColor: NasiraColors.keyboardBg,
      body: SafeArea(
        child: Column(
          children: [
            // Nav bar
            NasiraNavBar(
              backgroundColor: NasiraColors.navTaupe,
              showBack: true,
              onBack: () => Navigator.pop(context),
            ),

            // Body: Sidebar + Hauptbereich
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Sidebar ─────────────────────────────────────────────
                  SizedBox(
                    width: 200,
                    child: Container(
                      color: const Color(0xFF1A2733),
                      child: Column(
                        children: [
                          // Aktions-Buttons
                          _sidebarButton(
                            icon: Icons.add,
                            label: 'Neues Dokument',
                            onTap: () => _neuesDokument(state),
                          ),
                          if (_selectedIndex != null &&
                              _selectedIndex! < docs.length)
                            _sidebarButton(
                              icon: Icons.edit_outlined,
                              label: 'Weiter schreiben',
                              onTap: () => _weiterSchreiben(
                                  state, docs[_selectedIndex!]),
                            ),
                          const Divider(
                              color: Colors.white24, height: 1),

                          // Dok-Liste
                          Expanded(
                            child: docs.isEmpty
                                ? const Center(
                                    child: Text(
                                      'Keine Dokumente',
                                      style: TextStyle(
                                          color: Colors.white38,
                                          fontSize: 12),
                                    ),
                                  )
                                : ListView.builder(
                                    itemCount: docs.length,
                                    itemBuilder: (ctx, i) =>
                                        _docListTile(docs, i),
                                  ),
                          ),

                          // Alles löschen
                          if (docs.isNotEmpty) ...[
                            const Divider(color: Colors.white24, height: 1),
                            _sidebarButton(
                              icon: Icons.delete_sweep_outlined,
                              label: 'Alles löschen',
                              onTap: () => _allesLoeschen(state),
                              destructive: true,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),

                  // ── Hauptbereich ────────────────────────────────────────
                  Expanded(
                    child: Container(
                      color: const Color(0xFFF0F4F8),
                      child: Column(
                        children: [
                          // Aktions-Buttons oben
                          if (_selectedIndex != null &&
                              _selectedIndex! < docs.length) ...[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                              child: Row(
                                children: [
                                  _actionButton(
                                    icon: Icons.copy_outlined,
                                    label: 'Kopieren',
                                    onTap: () =>
                                        _kopieren(docs[_selectedIndex!]),
                                  ),
                                  const SizedBox(width: 8),
                                  _actionButton(
                                    icon: Icons.delete_outline,
                                    label: 'Löschen',
                                    color: Colors.red.shade700,
                                    onTap: () =>
                                        _loeschen(state, _selectedIndex!),
                                  ),
                                ],
                              ),
                            ),
                          ],

                          // Text-Vorschau mit Symbolen
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: _selectedIndex == null
                                  ? Center(
                                      child: Text(
                                        'Kein Dokument ausgewählt',
                                        style: TextStyle(
                                            color: Colors.grey.shade500,
                                            fontSize: 14),
                                      ),
                                    )
                                  : NasiraTextWorkspace(
                                      controller: _previewController,
                                      minHeight: double.infinity,
                                      maxHeight: double.infinity,
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _docListTile(List<SavedDocument> docs, int i) {
    final doc = docs[i];
    final isSelected = _selectedIndex == i;
    return InkWell(
      onTap: () => _selectDoc(i, doc),
      child: Container(
        color: isSelected
            ? NasiraColors.navGreen.withAlpha(80)
            : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              doc.timeLabel,
              style: const TextStyle(
                  color: Colors.white54, fontSize: 10),
            ),
            const SizedBox(height: 2),
            Text(
              doc.preview,
              style: const TextStyle(
                  color: Colors.white, fontSize: 12),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _sidebarButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool destructive = false,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(icon,
                size: 18,
                color: destructive ? Colors.red.shade300 : Colors.white70),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: destructive ? Colors.red.shade300 : Colors.white,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
  }) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      style: ElevatedButton.styleFrom(
        foregroundColor: Colors.white,
        backgroundColor: color ?? NasiraColors.navGreen,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}
