import 'package:flutter/services.dart' show AssetManifest, rootBundle;

import '../models/models.dart';

/// Verwaltet den Asset-Index und löst Symbol-Pfade auf.
///
/// Lädt beim Start alle verfügbaren Bild-Assets aus dem AssetManifest
/// und bietet dann schnelle Pfad-Auflösung über Basename-Lookup.
class AssetResolverService {
  final Set<String> _allAssetPaths = <String>{};
  final Map<String, List<String>> _assetPathsByBasename = <String, List<String>>{};
  bool _ready = false;
  int _imageCount = 0;

  bool get isReady => _ready;
  int get imageCount => _imageCount;

  /// Lädt den Asset-Index aus dem Flutter AssetManifest.
  Future<void> loadIndex() async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final assets = manifest.listAssets();

    final allPaths = <String>{};
    final byBasename = <String, List<String>>{};
    var imageCount = 0;

    for (final rawPath in assets) {
      final path = rawPath.replaceAll('\\', '/');
      if (!_isSupportedImage(path)) continue;
      imageCount++;
      allPaths.add(path);
      final base = _basename(path).toLowerCase();
      byBasename.putIfAbsent(base, () => <String>[]).add(path);
    }

    // Sortiere Kandidaten: Metacom-Pfade bevorzugt
    for (final entry in byBasename.entries) {
      entry.value.sort((a, b) {
        final aScore = _pathScore(a);
        final bScore = _pathScore(b);
        if (aScore != bScore) return bScore.compareTo(aScore);
        return a.compareTo(b);
      });
    }

    _allAssetPaths
      ..clear()
      ..addAll(allPaths);
    _assetPathsByBasename
      ..clear()
      ..addAll(byBasename);
    _imageCount = imageCount;
    _ready = true;
  }

  /// Löst einen rohen Pfad (z. B. aus SymbolEntry.assetPath) zu einem
  /// tatsächlich vorhandenen Asset-Pfad auf.
  ///
  /// Probiert mehrere Varianten:
  /// 1. Exakter Pfad
  /// 2. Mit "assets/" Präfix
  /// 3. Mit "assets/metacom/" Präfix
  /// 4. Basename-Lookup (Fallback)
  String? resolve(String? rawPath) {
    if (rawPath == null || rawPath.trim().isEmpty) return null;
    final normalized = _normalizePath(rawPath);

    if (_allAssetPaths.contains(normalized)) return normalized;

    final withAssets = 'assets/$normalized';
    if (_allAssetPaths.contains(withAssets)) return withAssets;

    final withMetacom = 'assets/metacom/$normalized';
    if (_allAssetPaths.contains(withMetacom)) return withMetacom;

    // Fallback: Basename-Lookup
    final base = _basename(normalized).toLowerCase();
    final matches = _assetPathsByBasename[base];
    if (matches == null || matches.isEmpty) return null;
    return matches.first;
  }

  /// Shortcut: löst den Asset-Pfad eines MappedSymbol auf.
  String? resolveForSymbol(MappedSymbol mapped) {
    return resolve(mapped.symbol.assetPath);
  }

  // ── Interna ───────────────────────────────────────────────────────────

  String _normalizePath(String path) {
    var normalized = path.trim().replaceAll('\\', '/');
    while (normalized.startsWith('./')) {
      normalized = normalized.substring(2);
    }
    if (normalized.startsWith('/')) {
      normalized = normalized.substring(1);
    }
    return normalized;
  }

  String _basename(String path) {
    final normalized = path.replaceAll('\\', '/');
    final slash = normalized.lastIndexOf('/');
    if (slash == -1) return normalized;
    return normalized.substring(slash + 1);
  }

  int _pathScore(String path) {
    final lower = path.toLowerCase();
    var score = 0;
    if (lower.contains('/assets/metacom/')) score += 100;
    if (lower.startsWith('assets/metacom/')) score += 100;
    if (lower.contains('/metacom/')) score += 30;
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) score += 10;
    return score;
  }

  bool _isSupportedImage(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.webp');
  }
}
