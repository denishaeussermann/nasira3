import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

// ── SavedDocument ─────────────────────────────────────────────────────────────

class SavedDocument {
  final String text;
  final DateTime timestamp;

  const SavedDocument({required this.text, required this.timestamp});

  factory SavedDocument.fromJson(Map<String, dynamic> json) => SavedDocument(
        text: json['text'] as String? ?? '',
        timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ??
            DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'text': text,
        'timestamp': timestamp.toIso8601String(),
      };

  /// Erste ~40 Zeichen für die Listenvorschau.
  String get preview {
    final t = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    return t.length <= 40 ? t : '${t.substring(0, 40)}…';
  }

  /// Uhrzeit im Format HH:MM.
  String get timeLabel {
    final h = timestamp.hour.toString().padLeft(2, '0');
    final m = timestamp.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

// ── DocumentService ───────────────────────────────────────────────────────────

/// Verwaltet gespeicherte Dokumente als JSON-Datei im App-Dokumentenverzeichnis.
///
/// Datei: `nasira_documents.json`
/// Format: `[ { "text": "...", "timestamp": "..." }, ... ]`
///
/// Neueste Dokumente stehen zuerst. Maximal 50 Einträge.
class DocumentService extends ChangeNotifier {
  static const _fileName = 'nasira_documents.json';
  static const _maxDocuments = 50;

  List<SavedDocument> _documents = [];
  bool _loaded = false;

  List<SavedDocument> get documents => List.unmodifiable(_documents);

  // ── Datei-Zugriff ─────────────────────────────────────────────────────────

  Future<File> _getFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  // ── Laden ─────────────────────────────────────────────────────────────────

  Future<void> load() async {
    if (_loaded) return;
    try {
      final file = await _getFile();
      if (!await file.exists()) {
        _loaded = true;
        notifyListeners();
        return;
      }
      final raw = await file.readAsString();
      final list = jsonDecode(raw) as List<dynamic>;
      _documents = list
          .map((e) => SavedDocument.fromJson(e as Map<String, dynamic>))
          .toList();
      _loaded = true;
    } catch (_) {
      _loaded = true;
    }
    notifyListeners();
  }

  // ── Speichern ─────────────────────────────────────────────────────────────

  Future<void> _save() async {
    final file = await _getFile();
    await file.writeAsString(
        jsonEncode(_documents.map((d) => d.toJson()).toList()));
  }

  // ── Mutations ─────────────────────────────────────────────────────────────

  /// Fügt ein neues Dokument vorne ein (neueste zuerst). Max. 50 Einträge.
  Future<void> saveDocument(String text) async {
    await load();
    final doc = SavedDocument(text: text, timestamp: DateTime.now());
    _documents.insert(0, doc);
    if (_documents.length > _maxDocuments) {
      _documents = _documents.sublist(0, _maxDocuments);
    }
    await _save();
    notifyListeners();
  }

  Future<void> deleteDocument(int index) async {
    await load();
    if (index < 0 || index >= _documents.length) return;
    _documents.removeAt(index);
    await _save();
    notifyListeners();
  }

  Future<void> deleteAll() async {
    _documents = [];
    await _save();
    notifyListeners();
  }
}
