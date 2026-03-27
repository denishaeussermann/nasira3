import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/custom_sentence.dart';

/// Verwaltet benutzerdefinierte Sätze als JSON-Datei im App-Dokumentenverzeichnis.
///
/// Datei: `nasira_custom_sentences.json`
/// Format: `{ "pin": "1234", "sentences": [...] }`
class CustomSentencesService {
  static const _fileName = 'nasira_custom_sentences.json';
  static const _defaultPin = '1234';

  List<CustomSentence> _sentences = [];
  String _pin = _defaultPin;
  bool _loaded = false;

  List<CustomSentence> get sentences => List.unmodifiable(_sentences);
  String get pin => _pin;

  // ── Datei-Zugriff ────────────────────────────────────────────────────────────

  Future<File> _getFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  // ── Laden ────────────────────────────────────────────────────────────────────

  Future<void> load() async {
    if (_loaded) return;
    try {
      final file = await _getFile();
      if (!await file.exists()) {
        _loaded = true;
        return;
      }
      final raw = await file.readAsString();
      final json = jsonDecode(raw) as Map<String, dynamic>;
      _pin = (json['pin'] as String?) ?? _defaultPin;
      final list = (json['sentences'] as List<dynamic>?) ?? [];
      _sentences = list
          .map((e) => CustomSentence.fromJson(e as Map<String, dynamic>))
          .toList();
      _loaded = true;
    } catch (_) {
      _loaded = true;
    }
  }

  // ── Speichern ────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    final file = await _getFile();
    final json = {
      'pin': _pin,
      'sentences': _sentences.map((s) => s.toJson()).toList(),
    };
    await file.writeAsString(jsonEncode(json));
  }

  // ── Mutations ────────────────────────────────────────────────────────────────

  Future<void> add(CustomSentence sentence) async {
    await load();
    _sentences.add(sentence);
    await _save();
  }

  Future<void> delete(String id) async {
    await load();
    _sentences.removeWhere((s) => s.id == id);
    await _save();
  }

  Future<void> updatePin(String newPin) async {
    await load();
    _pin = newPin;
    await _save();
  }

  bool checkPin(String input) => input == _pin;

  /// Alle Sätze für ein bestimmtes Modul ('brief', 'tagebuch') + 'alle'.
  List<CustomSentence> forModule(String module) {
    return _sentences
        .where((s) => s.moduleTarget == module || s.moduleTarget == 'alle')
        .toList();
  }
}
