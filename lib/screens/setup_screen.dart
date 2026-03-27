import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../nasira_app_state.dart';
import '../nasira_repository.dart';
import '../models/custom_sentence.dart';
import '../services/custom_sentences_service.dart';
import '../widgets/composite_symbol.dart';

// ── PIN-Dialog ────────────────────────────────────────────────────────────────

/// Zeigt den PIN-Eingabe-Dialog. Gibt `true` zurück wenn korrekt, sonst null.
Future<bool?> showPinDialog(BuildContext context, CustomSentencesService svc) {
  final ctrl = TextEditingController();
  String? error;

  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.lock_outline, size: 20),
              SizedBox(width: 8),
              Text('Setup – PIN eingeben'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ctrl,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'PIN',
                  counterText: '',
                  errorText: error,
                ),
                onSubmitted: (_) {
                  if (svc.checkPin(ctrl.text)) {
                    Navigator.pop(ctx, true);
                  } else {
                    setState(() => error = 'Falscher PIN');
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: () {
                if (svc.checkPin(ctrl.text)) {
                  Navigator.pop(ctx, true);
                } else {
                  setState(() => error = 'Falscher PIN');
                }
              },
              child: const Text('Öffnen'),
            ),
          ],
        ),
      );
    },
  );
}

// ── SetupScreen ───────────────────────────────────────────────────────────────

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _pinController = TextEditingController();
  String _pinFeedback = '';

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.read<NasiraAppState>();
    final svc = state.customSentences;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2D3250),
        foregroundColor: Colors.white,
        title: const Row(
          children: [
            Icon(Icons.admin_panel_settings_outlined, size: 20),
            SizedBox(width: 8),
            Text('Setup – Nasira Admin'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openAddDialog(context, svc),
        icon: const Icon(Icons.add),
        label: const Text('Neuer Satz'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── PIN ändern ──────────────────────────────────────────────────────
          _buildSection(
            context,
            title: 'PIN ändern',
            icon: Icons.lock_reset_outlined,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _pinController,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    decoration: const InputDecoration(
                      labelText: 'Neuer PIN',
                      counterText: '',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: () async {
                    final pin = _pinController.text.trim();
                    if (pin.length < 4) {
                      setState(() => _pinFeedback = 'Mindestens 4 Zeichen');
                      return;
                    }
                    await svc.updatePin(pin);
                    _pinController.clear();
                    setState(() => _pinFeedback = 'PIN gespeichert ✓');
                  },
                  child: const Text('Speichern'),
                ),
              ],
            ),
          ),
          if (_pinFeedback.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 4),
              child: Text(_pinFeedback,
                  style: TextStyle(
                      fontSize: 12,
                      color: _pinFeedback.contains('✓')
                          ? Colors.green.shade700
                          : Colors.red.shade700)),
            ),
          const SizedBox(height: 24),

          // ── Eigene Sätze ────────────────────────────────────────────────────
          _buildSection(
            context,
            title: 'Eigene Sätze (${svc.sentences.length})',
            icon: Icons.format_list_bulleted_outlined,
            child: svc.sentences.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'Noch keine eigenen Sätze. Tippe auf + Neuer Satz.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : Column(
                    children: svc.sentences
                        .map((s) => _CustomSentenceRow(
                              sentence: s,
                              onDelete: () async {
                                await svc.delete(s.id);
                                setState(() {});
                              },
                            ))
                        .toList(),
                  ),
          ),
          const SizedBox(height: 80), // FAB-Abstand
        ],
      ),
    );
  }

  Widget _buildSection(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: Colors.indigo),
                const SizedBox(width: 8),
                Text(title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  Future<void> _openAddDialog(
      BuildContext context, CustomSentencesService svc) async {
    final state = context.read<NasiraAppState>();
    await showDialog<void>(
      context: context,
      builder: (ctx) => _AddSatzDialog(
        state: state,
        onSave: (s) async {
          await svc.add(s);
          if (mounted) setState(() {});
        },
      ),
    );
  }
}

// ── Zeile in der Satzliste ────────────────────────────────────────────────────

class _CustomSentenceRow extends StatelessWidget {
  final CustomSentence sentence;
  final VoidCallback onDelete;

  const _CustomSentenceRow({required this.sentence, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    // watch statt read: Widget baut neu wenn Symbole asynchron geladen werden
    final state = context.watch<NasiraAppState>();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          // Komposit-Symbol Vorschau
          FutureBuilder<NasiraLoadResult>(
            future: state.futureLoad,
            builder: (ctx, snap) {
              if (!snap.hasData) return const SizedBox(width: 48, height: 32);
              final data = snap.data!.data;
              final sym1 = sentence.contentWord1 != null
                  ? state.cachedLookup(data, sentence.contentWord1!)
                  : null;
              final sym2 = sentence.contentWord2 != null
                  ? state.cachedLookup(data, sentence.contentWord2!)
                  : null;
              return CompositeSymbolWidget(
                assetPath1: sym1 != null
                    ? state.assetResolver.resolveForSymbol(sym1)
                    : null,
                assetPath2: sym2 != null
                    ? state.assetResolver.resolveForSymbol(sym2)
                    : null,
                fallbackText: sentence.contentWord1 ?? '',
                size: 32,
              );
            },
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(sentence.sentence,
                    style: const TextStyle(fontWeight: FontWeight.w500)),
                Text(
                  '${sentence.moduleTarget} · ${[
                    sentence.contentWord1,
                    sentence.contentWord2
                  ].whereType<String>().join(', ')}',
                  style: TextStyle(
                      fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 20),
            color: Colors.red.shade400,
            tooltip: 'Löschen',
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

// ── Dialog: Neuen Satz erstellen ──────────────────────────────────────────────

class _AddSatzDialog extends StatefulWidget {
  final NasiraAppState state;
  final Future<void> Function(CustomSentence) onSave;

  const _AddSatzDialog({required this.state, required this.onSave});

  @override
  State<_AddSatzDialog> createState() => _AddSatzDialogState();
}

class _AddSatzDialogState extends State<_AddSatzDialog> {
  final _satzCtrl = TextEditingController();
  final _wort1Ctrl = TextEditingController();
  final _wort2Ctrl = TextEditingController();
  String _modul = 'alle';
  bool _saving = false;

  @override
  void dispose() {
    _satzCtrl.dispose();
    _wort1Ctrl.dispose();
    _wort2Ctrl.dispose();
    super.dispose();
  }

  void _autoExtract() {
    final words = extractContentWords(_satzCtrl.text);
    setState(() {
      _wort1Ctrl.text = words.isNotEmpty ? words[0] : '';
      _wort2Ctrl.text = words.length >= 2 ? words[1] : '';
    });
  }

  Future<void> _save() async {
    final satz = _satzCtrl.text.trim();
    if (satz.isEmpty) return;
    setState(() => _saving = true);
    final sentence = CustomSentence(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      sentence: satz,
      contentWord1:
          _wort1Ctrl.text.trim().isEmpty ? null : _wort1Ctrl.text.trim(),
      contentWord2:
          _wort2Ctrl.text.trim().isEmpty ? null : _wort2Ctrl.text.trim(),
      moduleTarget: _modul,
    );
    await widget.onSave(sentence);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Neuen Satz erstellen'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _satzCtrl,
              decoration: const InputDecoration(
                labelText: 'Satz',
                border: OutlineInputBorder(),
                hintText: 'z.B. Ich freue mich auf den Ausflug.',
              ),
              maxLines: 2,
              onChanged: (_) => _autoExtract(),
            ),
            const SizedBox(height: 12),
            const Text('Inhaltswörter für Symbole:',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _wort1Ctrl,
                    decoration: const InputDecoration(
                      labelText: 'Wort 1',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _wort2Ctrl,
                    decoration: const InputDecoration(
                      labelText: 'Wort 2',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _modul,
              decoration: const InputDecoration(
                labelText: 'Modul',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: const [
                DropdownMenuItem(value: 'alle', child: Text('Alle Module')),
                DropdownMenuItem(value: 'brief', child: Text('Brief')),
                DropdownMenuItem(value: 'tagebuch', child: Text('Tagebuch')),
              ],
              onChanged: (v) => setState(() => _modul = v ?? 'alle'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Speichern'),
        ),
      ],
    );
  }
}

