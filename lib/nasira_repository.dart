import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

import 'models/models.dart';

class NasiraLoadResult {
  final NasiraData data;
  final bool usingImportedData;
  final bool importedDataAvailable;
  final String sourceLabel;
  final String importFolderPath;

  const NasiraLoadResult({
    required this.data,
    required this.usingImportedData,
    required this.importedDataAvailable,
    required this.sourceLabel,
    required this.importFolderPath,
  });
}

class NasiraRepository {
  static const String _importFolderName = 'nasira_import';
  static const String _settingsFileName = 'app_state.json';

  Future<NasiraLoadResult> loadPreferred() async {
    final importDir = await _getImportDir();
    final importedAvailable = await hasImportedData();
    final preferImported = await _readPreferredSourceImported();

    if (preferImported && importedAvailable) {
      final data = await _loadImportedData();
      return NasiraLoadResult(
        data: data,
        usingImportedData: true,
        importedDataAvailable: true,
        sourceLabel: 'Importierte Arbeitsdaten',
        importFolderPath: importDir.path,
      );
    }

    final data = await _loadBundledData();
    return NasiraLoadResult(
      data: data,
      usingImportedData: false,
      importedDataAvailable: importedAvailable,
      sourceLabel: 'Eingebaute Testdaten',
      importFolderPath: importDir.path,
    );
  }

  Future<NasiraLoadResult> loadBundled() async {
    final importDir = await _getImportDir();
    final importedAvailable = await hasImportedData();
    final data = await _loadBundledData();

    return NasiraLoadResult(
      data: data,
      usingImportedData: false,
      importedDataAvailable: importedAvailable,
      sourceLabel: 'Eingebaute Testdaten',
      importFolderPath: importDir.path,
    );
  }

  Future<NasiraLoadResult> loadImported() async {
    final importDir = await _getImportDir();
    final importedAvailable = await hasImportedData();

    if (!importedAvailable) {
      final bundled = await _loadBundledData();
      return NasiraLoadResult(
        data: bundled,
        usingImportedData: false,
        importedDataAvailable: false,
        sourceLabel: 'Eingebaute Testdaten',
        importFolderPath: importDir.path,
      );
    }

    final data = await _loadImportedData();
    return NasiraLoadResult(
      data: data,
      usingImportedData: true,
      importedDataAvailable: true,
      sourceLabel: 'Importierte Arbeitsdaten',
      importFolderPath: importDir.path,
    );
  }

  Future<bool> hasImportedData() async {
    final dir = await _getImportDir();

    final wordsFile = File('${dir.path}${Platform.pathSeparator}words.json');
    final symbolsFile = File('${dir.path}${Platform.pathSeparator}symbols.json');
    final mappingsFile = File('${dir.path}${Platform.pathSeparator}mappings.json');

    return wordsFile.existsSync() &&
        symbolsFile.existsSync() &&
        mappingsFile.existsSync();
  }

  Future<void> setPreferredSourceImported(bool value) async {
    final file = await _getSettingsFile();

    const encoder = JsonEncoder.withIndent('  ');
    final json = {
      'preferredSource': value ? 'imported' : 'bundled',
    };

    await file.writeAsString(encoder.convert(json));
  }

  Future<bool> _readPreferredSourceImported() async {
    try {
      final file = await _getSettingsFile();

      if (!await file.exists()) {
        return true;
      }

      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);

      if (decoded is Map && decoded['preferredSource'] == 'bundled') {
        return false;
      }

      return true;
    } catch (_) {
      return true;
    }
  }

  Future<File> _getSettingsFile() async {
    final dir = await _getImportDir();

    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    return File('${dir.path}${Platform.pathSeparator}$_settingsFileName');
  }

  Future<Directory> _getImportDir() async {
    final documentsDir = await getApplicationDocumentsDirectory();
    return Directory(
      '${documentsDir.path}${Platform.pathSeparator}$_importFolderName',
    );
  }

  Future<NasiraData> _loadBundledData() async {
    final wordsRaw = await rootBundle.loadString('assets/data/words.json');
    final symbolsRaw = await rootBundle.loadString('assets/data/symbols.json');
    final mappingsRaw = await rootBundle.loadString('assets/data/mappings.json');

    return _decodeData(
      wordsRaw: wordsRaw,
      symbolsRaw: symbolsRaw,
      mappingsRaw: mappingsRaw,
    );
  }

  Future<NasiraData> _loadImportedData() async {
    final dir = await _getImportDir();

    final wordsFile = File('${dir.path}${Platform.pathSeparator}words.json');
    final symbolsFile = File('${dir.path}${Platform.pathSeparator}symbols.json');
    final mappingsFile = File('${dir.path}${Platform.pathSeparator}mappings.json');

    if (!await wordsFile.exists() ||
        !await symbolsFile.exists() ||
        !await mappingsFile.exists()) {
      throw Exception('Importierte JSON-Dateien wurden nicht gefunden.');
    }

    final wordsRaw = await wordsFile.readAsString();
    final symbolsRaw = await symbolsFile.readAsString();
    final mappingsRaw = await mappingsFile.readAsString();

    return _decodeData(
      wordsRaw: wordsRaw,
      symbolsRaw: symbolsRaw,
      mappingsRaw: mappingsRaw,
    );
  }

  NasiraData _decodeData({
    required String wordsRaw,
    required String symbolsRaw,
    required String mappingsRaw,
  }) {
    final wordsJson = jsonDecode(wordsRaw) as List<dynamic>;
    final symbolsJson = jsonDecode(symbolsRaw) as List<dynamic>;
    final mappingsJson = jsonDecode(mappingsRaw) as List<dynamic>;

    final words = wordsJson
        .map((e) => WordEntry.fromJson(e as Map<String, dynamic>))
        .toList();

    final symbols = symbolsJson
        .map((e) => SymbolEntry.fromJson(e as Map<String, dynamic>))
        .toList();

    final mappings = mappingsJson
        .map((e) => WordSymbolMapping.fromJson(e as Map<String, dynamic>))
        .toList();

    words.sort((a, b) => a.rank.compareTo(b.rank));

    return NasiraData(
      words: words,
      symbols: symbols,
      mappings: mappings,
    );
  }
}
