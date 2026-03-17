import 'dart:convert';
import 'dart:io';

import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

import 'models/models.dart';

class NasiraImportReport {
  final NasiraData data;
  final int excelWordCount;
  final int txtSymbolCount;
  final int mappedCount;
  final int unmappedWordCount;
  final int unusedSymbolCount;
  final int addedWordCount;
  final String exportFolder;
  final String aliasFilePath;

  const NasiraImportReport({
    required this.data,
    required this.excelWordCount,
    required this.txtSymbolCount,
    required this.mappedCount,
    required this.unmappedWordCount,
    required this.unusedSymbolCount,
    required this.addedWordCount,
    required this.exportFolder,
    required this.aliasFilePath,
  });
}

class NasiraImportService {
  Future<NasiraImportReport?> pickAndImport() async {
    final excelResult = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
      allowMultiple: false,
    );

    if (excelResult == null || excelResult.files.single.path == null) {
      return null;
    }

    final txtResult = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt'],
      allowMultiple: false,
    );

    if (txtResult == null || txtResult.files.single.path == null) {
      return null;
    }

    return importFromFiles(
      excelPath: excelResult.files.single.path!,
      txtPath: txtResult.files.single.path!,
    );
  }

  Future<NasiraImportReport> importFromFiles({
    required String excelPath,
    required String txtPath,
  }) async {
    final exportDir = await _getExportDir();
    final aliasFile = await _ensureAliasFile(exportDir);
    final aliasMap = await _loadAliasMap(aliasFile);

    final baseWords = await _readBaseWordsFromExcel(excelPath);
    final rawFileNames = await _readSymbolFileNamesFromTxt(txtPath);
    final symbols = _buildRepresentativeSymbols(rawFileNames, aliasMap);

    final words = <WordEntry>[];
    final mappings = <WordSymbolMapping>[];

    final wordByLookup = <String, WordEntry>{};
    final mappedWordIds = <String>{};
    final mappedSymbolIds = <String>{};
    final mappingKeys = <String>{};

    var wordCounter = 1;

    for (final baseWord in baseWords) {
      final cleaned = _displayWordFromNaturalTerm(baseWord);
      if (cleaned.isEmpty) continue;
      if (_findWordByText(cleaned, wordByLookup) != null) continue;

      final word = WordEntry(
        id: 'w$wordCounter',
        text: cleaned,
        rank: wordCounter,
        nextWords: const [],
      );

      words.add(word);
      _registerWordLookup(wordByLookup, word);
      wordCounter++;
    }

    final baseWordCount = words.length;
    var addedWordCount = 0;

    for (final symbol in symbols) {
      WordEntry? word = _findWordByText(symbol.label, wordByLookup);

      if (word == null && _shouldAutoCreateWordFromSymbol(symbol.label)) {
        final createdWordText = _displayWordFromNaturalTerm(symbol.label);

        word = WordEntry(
          id: 'w$wordCounter',
          text: createdWordText,
          rank: wordCounter,
          nextWords: const [],
        );

        words.add(word);
        _registerWordLookup(wordByLookup, word);
        wordCounter++;
        addedWordCount++;
      }

      if (word == null) continue;

      final mappingKey = '${word.id}|${symbol.id}';
      if (!mappingKeys.add(mappingKey)) continue;

      mappings.add(
        WordSymbolMapping(wordId: word.id, symbolId: symbol.id),
      );

      mappedWordIds.add(word.id);
      mappedSymbolIds.add(symbol.id);
    }

    final mappedCount = mappings.length;
    final unmappedWordCount = words.length - mappedWordIds.length;
    final unusedSymbolCount = symbols.length - mappedSymbolIds.length;

    final data = NasiraData(
      words: words,
      symbols: symbols,
      mappings: mappings,
    );

    await _writeJsonExports(
      exportDir: exportDir,
      words: words,
      symbols: symbols,
      mappings: mappings,
      baseWordCount: baseWordCount,
      addedWordCount: addedWordCount,
      mappedCount: mappedCount,
      unmappedWordCount: unmappedWordCount,
      unusedSymbolCount: unusedSymbolCount,
      aliasFilePath: aliasFile.path,
    );

    return NasiraImportReport(
      data: data,
      excelWordCount: baseWordCount,
      txtSymbolCount: symbols.length,
      mappedCount: mappedCount,
      unmappedWordCount: unmappedWordCount,
      unusedSymbolCount: unusedSymbolCount,
      addedWordCount: addedWordCount,
      exportFolder: exportDir.path,
      aliasFilePath: aliasFile.path,
    );
  }

  Future<Directory> _getExportDir() async {
    final baseDir = await getApplicationDocumentsDirectory();
    final exportDir = Directory(
      '${baseDir.path}${Platform.pathSeparator}nasira_import',
    );
    if (!await exportDir.exists()) {
      await exportDir.create(recursive: true);
    }
    return exportDir;
  }

  Future<File> _ensureAliasFile(Directory exportDir) async {
    final file = File(
      '${exportDir.path}${Platform.pathSeparator}symbol_aliases.json',
    );

    if (!await file.exists()) {
      const starterAliases = {
        'a bis z': 'alphabet',
        'abc': 'alphabet',
        'ct mrt': 'CT MRT',
        'ekg': 'EKG',
        'eeg': 'EEG',
        'mzeb': 'MZEB',
        'spz': 'SPZ',
        'tuete': 'tüte',
        'fragezeichen': 'fragezeichen',
        'ausrufungszeichen': 'ausrufezeichen',
        'doppelpunkt': 'doppelpunkt',
        'komma': 'komma',
        'punkt': 'punkt',
        'schraegstrich': 'schrägstrich',
        'frauenaerztin': 'frauenärztin',
        'hausaerztin': 'hausärztin',
        'zahnaerztin': 'zahnärztin',
      };

      const encoder = JsonEncoder.withIndent('  ');
      await file.writeAsString(encoder.convert(starterAliases));
    }

    return file;
  }

  Future<Map<String, String>> _loadAliasMap(File aliasFile) async {
    try {
      final raw = await aliasFile.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};

      final result = <String, String>{};
      for (final entry in decoded.entries) {
        final value = entry.value.toString().trim();
        if (value.isEmpty) continue;
        for (final key in _buildLookupKeys(entry.key.toString())) {
          if (key.isNotEmpty) result[key] = value;
        }
      }
      return result;
    } catch (_) {
      return {};
    }
  }

  Future<List<String>> _readBaseWordsFromExcel(String excelPath) async {
    final bytes = await File(excelPath).readAsBytes();
    final excel = Excel.decodeBytes(bytes);

    if (excel.tables.isEmpty) {
      throw Exception('Die Excel-Datei enthält kein lesbares Tabellenblatt.');
    }

    final firstSheetName = excel.tables.keys.first;
    final sheet = excel.tables[firstSheetName];

    if (sheet == null) {
      throw Exception('Das erste Tabellenblatt konnte nicht gelesen werden.');
    }

    final result = <String>[];
    for (final row in sheet.rows) {
      if (row.isEmpty) continue;
      final firstCell = _firstMeaningfulCell(row);
      if (firstCell.isEmpty) continue;
      if (_looksLikeHeader(firstCell)) continue;
      result.add(firstCell);
    }
    return result;
  }

  Future<List<String>> _readSymbolFileNamesFromTxt(String txtPath) async {
    final content = utf8.decode(
      await File(txtPath).readAsBytes(),
      allowMalformed: true,
    );

    final lines = const LineSplitter().convert(content);
    final result = <String>[];

    for (final line in lines) {
      final cleaned = line.trim().replaceAll('"', '');
      if (cleaned.isEmpty) continue;
      final lower = cleaned.toLowerCase();
      if (!lower.endsWith('.jpg') &&
          !lower.endsWith('.jpeg') &&
          !lower.endsWith('.png')) {
        continue;
      }
      result.add(cleaned);
    }
    return result;
  }

  List<SymbolEntry> _buildRepresentativeSymbols(
    List<String> rawFileNames,
    Map<String, String> aliasMap,
  ) {
    final grouped = <String, List<String>>{};
    final labelByGroup = <String, String>{};

    for (final fileName in rawFileNames) {
      final rawNaturalTerm = _naturalTermFromFileName(fileName);
      final alias = _resolveAlias(rawNaturalTerm, aliasMap);
      final displayTerm = _displayWordFromNaturalTerm(alias);
      final groupKey = _normalizeForCompare(displayTerm);

      if (groupKey.isEmpty) continue;

      grouped.putIfAbsent(groupKey, () => []).add(fileName);
      labelByGroup.putIfAbsent(groupKey, () => displayTerm);
    }

    final groupKeys = grouped.keys.toList()..sort();
    final symbols = <SymbolEntry>[];
    var symbolCounter = 1;

    for (final groupKey in groupKeys) {
      final candidates = grouped[groupKey]!;
      candidates.sort((a, b) {
        final scoreA = _candidateScore(a);
        final scoreB = _candidateScore(b);
        if (scoreA != scoreB) return scoreA.compareTo(scoreB);
        final lenA = _stripExtension(_fileNameOnly(a)).length;
        final lenB = _stripExtension(_fileNameOnly(b)).length;
        if (lenA != lenB) return lenA.compareTo(lenB);
        return a.toLowerCase().compareTo(b.toLowerCase());
      });

      final chosenFile = candidates.first;
      final label = labelByGroup[groupKey]!;
      final category = _categorize(label);

      symbols.add(
        SymbolEntry(
          id: 's$symbolCounter',
          label: label,
          fileName: chosenFile,
          category: category,
        ),
      );
      symbolCounter++;
    }

    return symbols;
  }

  String _symbolConceptKey(String fileName) {
    var base = _stripExtension(_fileNameOnly(fileName)).trim();
    base = base.replaceFirst(RegExp(r'^_+'), '');
    base = base.replaceFirst(RegExp(r'^\d+_?'), '');

    var previous = '';
    while (base.isNotEmpty && base != previous) {
      previous = base;
      base = _removeTrailingVariants(base);
      base = _removeTrailingDigits(base);
      base = base.replaceAll(RegExp(r'_+'), '_');
      base = base.replaceAll(RegExp(r'^_+|_+$'), '');
    }
    return base.toLowerCase();
  }

  String _naturalTermFromFileName(String fileName) {
    var key = _symbolConceptKey(fileName);
    key = key.replaceAll('_', ' ').trim();
    key = key.replaceAll(RegExp(r'\s+'), ' ');
    return key;
  }

  String _fileNameOnly(String value) {
    final normalized = value.replaceAll('\\', '/');
    if (normalized.contains('/')) return normalized.split('/').last;
    return normalized;
  }

  String _stripExtension(String value) {
    return value.replaceFirst(RegExp(r'\.[^.]+$'), '');
  }

  String _removeTrailingVariants(String value) {
    const suffixes = [
      'allesprachen',
      'farbcodiert',
      'farbkodiert',
      'niederl',
      'schwed',
      'engl',
      'fran',
      'span',
      'grkl',
      'ggr',
      'hdh',
      'sw',
      'dh',
      'gr',
      'kl',
    ];

    var current = value.trim();

    while (current.isNotEmpty) {
      final lower = current.toLowerCase();
      String? matched;

      for (final suffix in suffixes) {
        if (lower.endsWith('_$suffix') || lower.endsWith(suffix)) {
          matched = suffix;
          break;
        }
      }

      if (matched == null) return current;

      final updated = current.replaceFirst(
        RegExp(
          '(?:_${RegExp.escape(matched)}|${RegExp.escape(matched)})\$',
          caseSensitive: false,
        ),
        '',
      );

      final cleaned = updated.replaceAll(RegExp(r'_+$'), '').trim();
      if (cleaned == current) return current;
      current = cleaned;
    }
    return current;
  }

  String _removeTrailingDigits(String value) {
    return value.replaceFirst(RegExp(r'\d+$'), '');
  }

  int _candidateScore(String fileName) {
    final lower = _stripExtension(_fileNameOnly(fileName)).toLowerCase();
    var score = 0;
    if (_hasTrailingVariant(lower, 'allesprachen')) score += 120;
    if (_hasTrailingVariant(lower, 'sw')) score += 90;
    if (_hasTrailingVariant(lower, 'dh')) score += 70;
    if (_hasTrailingVariant(lower, 'hdh')) score += 65;
    if (_hasTrailingVariant(lower, 'ggr')) score += 55;
    if (_hasTrailingVariant(lower, 'grkl')) score += 55;
    if (_hasTrailingVariant(lower, 'gr')) score += 45;
    if (_hasTrailingVariant(lower, 'kl')) score += 45;
    if (_hasTrailingVariant(lower, 'engl')) score += 35;
    if (_hasTrailingVariant(lower, 'schwed')) score += 35;
    if (_hasTrailingVariant(lower, 'niederl')) score += 35;
    if (_hasTrailingVariant(lower, 'span')) score += 35;
    if (_hasTrailingVariant(lower, 'fran')) score += 35;
    if (_hasTrailingVariant(lower, 'farbcodiert')) score += 25;
    if (_hasTrailingVariant(lower, 'farbkodiert')) score += 25;
    if (RegExp(r'\d+$').hasMatch(_removeTrailingVariants(lower))) score += 10;
    return score;
  }

  bool _hasTrailingVariant(String value, String suffix) {
    final lower = value.toLowerCase();
    return lower.endsWith('_$suffix') || lower.endsWith(suffix);
  }

  bool _looksLikeHeader(String firstCell) {
    final normalized = _normalizeForCompare(firstCell);
    return normalized == 'grundwortschatz1000woerter' ||
        normalized == 'grundwortschatz' ||
        normalized == '1000woerter' ||
        normalized == 'wort' ||
        normalized == 'word';
  }

  String _firstMeaningfulCell(List<dynamic> row) {
    for (final cell in row) {
      final text = _cellToString(cell);
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  String _cellToString(dynamic cell) {
    if (cell == null) return '';
    try {
      final value = cell.value;
      if (value == null) return '';
      return value.toString().trim();
    } catch (_) {
      return cell.toString().trim();
    }
  }

  String _normalizeForCompare(String input) {
    var s = input.trim().toLowerCase();
    s = s
        .replaceAll('á', 'a')
        .replaceAll('à', 'a')
        .replaceAll('â', 'a')
        .replaceAll('é', 'e')
        .replaceAll('è', 'e')
        .replaceAll('ê', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ì', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ò', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ù', 'u');
    return NasiraData.strip(s);
  }

  Set<String> _buildLookupKeys(String input) {
    final normalized = _normalizeForCompare(input);
    if (normalized.isEmpty) return {};
    final keys = <String>{normalized};
    final collapsed = normalized.replaceAll(' ', '');
    if (collapsed.isNotEmpty) keys.add(collapsed);
    return keys;
  }

  void _registerWordLookup(
    Map<String, WordEntry> wordByLookup,
    WordEntry word,
  ) {
    for (final key in _buildLookupKeys(word.text)) {
      wordByLookup.putIfAbsent(key, () => word);
    }
  }

  WordEntry? _findWordByText(
    String input,
    Map<String, WordEntry> wordByLookup,
  ) {
    for (final key in _buildLookupKeys(input)) {
      final word = wordByLookup[key];
      if (word != null) return word;
    }
    return null;
  }

  String _resolveAlias(String rawNaturalTerm, Map<String, String> aliasMap) {
    for (final key in _buildLookupKeys(rawNaturalTerm)) {
      final alias = aliasMap[key];
      if (alias != null && alias.trim().isNotEmpty) return alias.trim();
    }
    return rawNaturalTerm;
  }

  String _displayWordFromNaturalTerm(String input) {
    final cleaned = input.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (cleaned.isEmpty) return cleaned;

    const uppercaseWords = {
      'ekg',
      'eeg',
      'ct',
      'mrt',
      'aac',
      'abc',
      'mzeb',
      'spz',
    };

    final parts = cleaned.split(' ');
    final converted = parts.map((part) {
      final lower = part.toLowerCase();
      if (uppercaseWords.contains(lower)) return lower.toUpperCase();
      return lower;
    }).toList();

    return converted.join(' ');
  }

  bool _shouldAutoCreateWordFromSymbol(String term) {
    final normalized = _normalizeForCompare(term);
    if (normalized.isEmpty) return false;

    const ignoredExact = {
      'leer',
      'shift',
      'punkt',
      'komma',
      'doppelpunkt',
      'fragezeichen',
      'ausrufezeichen',
      'schraegstrich',
      'space',
      'alphabet',
    };
    if (ignoredExact.contains(normalized)) return false;

    if (normalized.contains('allesprachen') ||
        normalized.contains('farbcodiert') ||
        normalized.contains('farbkodiert')) {
      return false;
    }

    const shortWords = {
      'ich',
      'du',
      'er',
      'sie',
      'es',
      'wir',
      'ihr',
      'bin',
      'bist',
      'ist',
      'sind',
      'seid',
      'war',
      'hat',
      'hast',
      'hab',
      'kann',
      'will',
      'soll',
      'darf',
      'mag',
      'wann',
      'was',
      'wer',
      'wie',
      'wo',
      'da',
      'und',
      'oder',
      'aber',
      'mit',
      'von',
      'bei',
      'auf',
      'in',
      'der',
      'die',
      'das',
      'den',
      'dem',
      'des',
      'ein',
      'eine',
      'nicht',
      'kein',
      'ja',
      'nein',
      'nun',
      'noch',
    };

    if (_isConcatenationOfShortWords(normalized, shortWords)) return false;

    const concatPrefixes = [
      'ichbin',
      'ichwar',
      'ichkann',
      'ichwill',
      'ichmuss',
      'dubist',
      'duwarst',
      'dukannst',
      'erhat',
      'erist',
      'erwar',
      'siehat',
      'sieist',
      'siewar',
      'wirsind',
      'wirhaben',
      'wirwaren',
      'istbin',
      'istbinbist',
      'wannsind',
      'wannwird',
      'wannkommt',
      'wasmacht',
      'waswill',
      'wasist',
    ];
    for (final prefix in concatPrefixes) {
      if (normalized.startsWith(prefix)) return false;
    }

    const concatSuffixes = ['wirda', 'sinda', 'isda', 'binda'];
    for (final suffix in concatSuffixes) {
      if (normalized.endsWith(suffix)) return false;
    }

    final parts = normalized.split(' ').where((e) => e.isNotEmpty).toList();
    if (parts.isEmpty) return false;
    if (parts.every((p) => p.length == 1)) return false;
    if (parts.length == 1 && parts.first.length == 1) return false;
    if (parts.length >= 2) return true;
    return parts.first.length >= 2;
  }

  bool _isConcatenationOfShortWords(String s, Set<String> words) {
    if (s.length < 4) return false;

    final n = s.length;
    final reachable = List<bool>.filled(n + 1, false);
    reachable[0] = true;
    var matchCount = 0;

    for (int i = 0; i < n; i++) {
      if (!reachable[i]) continue;
      for (final word in words) {
        if (i + word.length <= n && s.substring(i, i + word.length) == word) {
          reachable[i + word.length] = true;
          if (i > 0) matchCount++;
        }
      }
    }

    return reachable[n] && matchCount >= 1;
  }

  String _categorize(String term) {
    final normalized = _normalizeForCompare(term);

    const pronounsAndArticles = {
      'ich',
      'du',
      'er',
      'sie',
      'es',
      'wir',
      'ihr',
      'mich',
      'dich',
      'ihn',
      'uns',
      'euch',
      'mir',
      'dir',
      'ihm',
      'ihnen',
      'mein',
      'dein',
      'sein',
      'unser',
      'euer',
      'meine',
      'deine',
      'seine',
      'ihre',
      'unsere',
      'eure',
      'meinen',
      'deinen',
      'seinen',
      'ihren',
      'unseren',
      'euren',
      'meinem',
      'deinem',
      'seinem',
      'ihrem',
      'unserem',
      'eurem',
      'meiner',
      'deiner',
      'seiner',
      'ihrer',
      'unserer',
      'eurer',
      'der',
      'die',
      'das',
      'den',
      'dem',
      'des',
      'ein',
      'eine',
      'einen',
      'einem',
      'einer',
      'eines',
      'sieeinzahl',
      'siemehrzahl',
    };

    const questionWords = {
      'was',
      'wer',
      'wie',
      'wo',
      'wann',
      'warum',
      'welcher',
      'welche',
      'welches',
      'dies',
      'diese',
      'dieser',
      'dieses',
      'jeder',
      'jede',
      'jedes',
      'alle',
      'alles',
      'manche',
      'manches',
    };

    const smallWords = {
      'ja',
      'nein',
      'bitte',
      'danke',
      'okay',
      'gut',
      'schlecht',
      'genau',
      'vielleicht',
      'sicher',
      'nicht',
      'nie',
      'nichts',
      'niemand',
      'immer',
      'oft',
      'manchmal',
      'selten',
      'schon',
      'noch',
      'wieder',
      'mehr',
      'weniger',
      'hier',
      'da',
      'dort',
      'oben',
      'unten',
      'drinnen',
      'draussen',
      'links',
      'rechts',
      'gerade',
      'so',
      'sehr',
      'zu',
      'auch',
      'und',
      'oder',
      'aber',
      'weil',
      'denn',
      'dass',
      'wenn',
      'als',
      'ob',
      'damit',
      'trotzdem',
      'sonst',
      'in',
      'auf',
      'an',
      'bei',
      'mit',
      'ohne',
      'fuer',
      'gegen',
      'aus',
      'von',
      'nach',
      'vor',
      'hinter',
      'ueber',
      'unter',
      'zwischen',
      'durch',
      'um',
      'bis',
    };

    const commonVerbs = {
      'bin',
      'bist',
      'ist',
      'sind',
      'seid',
      'war',
      'waren',
      'waere',
      'habe',
      'hast',
      'hat',
      'haben',
      'habt',
      'hatte',
      'hatten',
      'kann',
      'kannst',
      'koennen',
      'koennt',
      'konnte',
      'konnten',
      'muss',
      'musst',
      'muessen',
      'muesst',
      'musste',
      'mussten',
      'soll',
      'sollst',
      'sollen',
      'sollt',
      'sollte',
      'sollten',
      'will',
      'willst',
      'wollen',
      'wollt',
      'wollte',
      'wollten',
      'darf',
      'darfst',
      'duerfen',
      'duerft',
      'durfte',
      'durften',
      'moechte',
      'mag',
      'moegen',
      'gehen',
      'komme',
      'kommst',
      'kommt',
      'kommen',
      'ging',
      'gingen',
      'machen',
      'mache',
      'machst',
      'macht',
      'tat',
      'taten',
      'sagen',
      'sage',
      'sagst',
      'sagt',
      'sagte',
      'sagten',
      'sehen',
      'sehe',
      'siehst',
      'sieht',
      'sah',
      'sahen',
      'hoeren',
      'hoere',
      'hoerst',
      'hoert',
      'hoerte',
      'hoerten',
      'sprechen',
      'spreche',
      'sprichst',
      'spricht',
      'sprach',
    };

    const medicalKeywords = {
      'arzt',
      'aerzt',
      'therapie',
      'therapeut',
      'apothe',
      'kranken',
      'medizin',
      'medikament',
      'fieber',
      'schmerz',
      'infektion',
      'virus',
      'corona',
      'ekg',
      'eeg',
      'ct',
      'mrt',
      'autismus',
      'epilepsie',
      'diabetes',
      'dialyse',
      'pflaster',
      'augen',
      'atem',
      'behandlung',
      'pflege',
      'chirurg',
      'ergotherapeut',
      'frauenarzt',
      'frauenaerztin',
    };

    if (pronounsAndArticles.contains(normalized)) return 'Pronomen & Artikel';
    if (questionWords.contains(normalized)) return 'Fragewörter';
    if (smallWords.contains(normalized)) return 'Kleine Wörter';

    for (final keyword in medicalKeywords) {
      if (normalized.contains(keyword)) return 'Gesundheit';
    }

    if (commonVerbs.contains(normalized) || normalized.endsWith('en')) {
      return 'Verben';
    }

    return 'Nomen & Sonstiges';
  }

  Future<void> _writeJsonExports({
    required Directory exportDir,
    required List<WordEntry> words,
    required List<SymbolEntry> symbols,
    required List<WordSymbolMapping> mappings,
    required int baseWordCount,
    required int addedWordCount,
    required int mappedCount,
    required int unmappedWordCount,
    required int unusedSymbolCount,
    required String aliasFilePath,
  }) async {
    const encoder = JsonEncoder.withIndent('  ');

    final wordsJson = words
        .map((w) => {
              'id': w.id,
              'text': w.text,
              'rank': w.rank,
              'nextWords': w.nextWords,
            })
        .toList();

    final symbolsJson = symbols
        .map((s) => {
              'id': s.id,
              'label': s.label,
              'fileName': s.fileName,
              'category': s.category,
            })
        .toList();

    final mappingsJson = mappings
        .map((m) => {'wordId': m.wordId, 'symbolId': m.symbolId})
        .toList();

    final summaryJson = {
      'baseWordCount': baseWordCount,
      'finalWordCount': words.length,
      'symbolCount': symbols.length,
      'mappingCount': mappedCount,
      'unmappedWordCount': unmappedWordCount,
      'unusedSymbolCount': unusedSymbolCount,
      'addedWordCount': addedWordCount,
      'aliasFilePath': aliasFilePath,
    };

    await File('${exportDir.path}${Platform.pathSeparator}words.json')
        .writeAsString(encoder.convert(wordsJson));

    await File('${exportDir.path}${Platform.pathSeparator}symbols.json')
        .writeAsString(encoder.convert(symbolsJson));

    await File('${exportDir.path}${Platform.pathSeparator}mappings.json')
        .writeAsString(encoder.convert(mappingsJson));

    await File('${exportDir.path}${Platform.pathSeparator}import_summary.json')
        .writeAsString(encoder.convert(summaryJson));
  }
}
