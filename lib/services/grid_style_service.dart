import 'package:flutter/material.dart';

/// Ein Named Style aus styles.xml — beschreibt Farben + Form einer Zelle.
class GridStyleEntry {
  final String key;
  final String name;
  final Color backgroundColor;
  final Color fontColor;
  /// Null = abgerundet (Standard), 'oval', 'pill'.
  final String? shape;

  const GridStyleEntry({
    required this.key,
    required this.name,
    required this.backgroundColor,
    required this.fontColor,
    this.shape,
  });
}

/// Alle relevanten Named Styles aus Settings0/Styles/styles.xml.
/// Farben als RRGGBBAA → Flutter Color(0xAARRGGBB).
abstract final class GridStyleService {
  static const List<GridStyleEntry> styles = [
    // ── Satzteile / Brief ────────────────────────────────────────────────────
    GridStyleEntry(
      key: 'Action cell 2',
      name: 'Satzteile Navigation',
      backgroundColor: Color(0xFF5D8057),
      fontColor: Color(0xFFFFFFFF),
    ),
    GridStyleEntry(
      key: 'Einkaufen 1',
      name: 'Satzteile hell',
      backgroundColor: Color(0xFF91B38A),
      fontColor: Color(0xFFFFFFFF),
    ),
    GridStyleEntry(
      key: 'style 6',
      name: 'Satzteile dunkel',
      backgroundColor: Color(0xFF2E4529),
      fontColor: Color(0xFFFFFFFF),
    ),
    GridStyleEntry(
      key: 'style 17',
      name: 'Weitere Wörter',
      backgroundColor: Color(0xFFE6F2E3),
      fontColor: Color(0xFF5D8057),
    ),
    GridStyleEntry(
      key: 'style 18',
      name: 'Satzteile invertiert',
      backgroundColor: Color(0xFFFFFFFF),
      fontColor: Color(0xFF5D8057),
    ),
    GridStyleEntry(
      key: 'Auto content cell 3',
      name: 'Wortliste',
      backgroundColor: Color(0xFFFFFFFF),
      fontColor: Color(0xFF000000),
    ),
    GridStyleEntry(
      key: 'Aktionsfeld 2',
      name: 'Brief Satzanfang',
      backgroundColor: Color(0xFFC4302B),
      fontColor: Color(0xFFFFFFFF),
    ),
    GridStyleEntry(
      key: 'Aktionsfeld 3',
      name: 'Brief Frage',
      backgroundColor: Color(0xFF3B5936),
      fontColor: Color(0xFFFFFFFF),
    ),
    GridStyleEntry(
      key: 'Aktionsfeld 4',
      name: 'Neutral',
      backgroundColor: Color(0xFFBFBBAC),
      fontColor: Color(0xFF000000),
    ),
    GridStyleEntry(
      key: 'style 4',
      name: 'Brief Hauptthema',
      backgroundColor: Color(0xFF91B38A),
      fontColor: Color(0xFFFFFFFF),
      shape: 'pill',
    ),
    GridStyleEntry(
      key: 'style 49',
      name: 'Brief Unterthema',
      backgroundColor: Color(0xFFBFDBB8),
      fontColor: Color(0xFFFFFFFF),
      shape: 'pill',
    ),
    GridStyleEntry(
      key: 'style 52',
      name: 'Satzanfang Vergangenheit',
      backgroundColor: Color(0xFFC97F7E),
      fontColor: Color(0xFFFFFFFF),
    ),
    GridStyleEntry(
      key: 'style 53',
      name: 'Frage Vergangenheit',
      backgroundColor: Color(0xFFACC2A8),
      fontColor: Color(0xFFFFFFFF),
    ),
    GridStyleEntry(
      key: 'style 54',
      name: 'Neutral Vergangenheit',
      backgroundColor: Color(0xFFE0DED7),
      fontColor: Color(0xFF000000),
    ),
    GridStyleEntry(
      key: 'style 19',
      name: 'Satzteile hell – groß',
      backgroundColor: Color(0xFF91B38A),
      fontColor: Color(0xFFFFFFFF),
    ),

    // ── Freies Schreiben ─────────────────────────────────────────────────────
    GridStyleEntry(
      key: 'style 31',
      name: 'FS Navigation',
      backgroundColor: Color(0xFF5E80C4),
      fontColor: Color(0xFFFFFFFF),
    ),
    GridStyleEntry(
      key: 'Freies Schreiben 2',
      name: 'FS Weitere Wörter',
      backgroundColor: Color(0xFFDAF2FB),
      fontColor: Color(0xFF5E80C4),
    ),
    GridStyleEntry(
      key: 'style 15',
      name: 'FS invertiert',
      backgroundColor: Color(0xFFFFFFFF),
      fontColor: Color(0xFF263580),
    ),

    // ── Datei / Navigation ───────────────────────────────────────────────────
    GridStyleEntry(
      key: 'style 7',
      name: 'Datei Navigation',
      backgroundColor: Color(0xFF807C72),
      fontColor: Color(0xFFFFFFFF),
      shape: 'oval',
    ),
    GridStyleEntry(
      key: 'style 27',
      name: 'Datei Dokumentenliste',
      backgroundColor: Color(0xFF807C72),
      fontColor: Color(0xFFFFFFFF),
    ),
    GridStyleEntry(
      key: 'style 28',
      name: 'Datei invertiert',
      backgroundColor: Color(0xFFFFFFFF),
      fontColor: Color(0xFF807C72),
    ),

    // ── Allgemein ────────────────────────────────────────────────────────────
    GridStyleEntry(
      key: 'Default',
      name: 'Standard (weiß)',
      backgroundColor: Color(0xFFFFFFFF),
      fontColor: Color(0xFF000000),
    ),
    GridStyleEntry(
      key: 'style 9',
      name: 'Neutral dunkel',
      backgroundColor: Color(0xFF8C8C8C),
      fontColor: Color(0xFF000000),
    ),
    GridStyleEntry(
      key: 'Setuptasten',
      name: 'Telegram dunkel',
      backgroundColor: Color(0xFF00BDA3),
      fontColor: Color(0xFFFFFFFF),
      shape: 'oval',
    ),

    // ── Tagebuch-Wochentage ──────────────────────────────────────────────────
    GridStyleEntry(
      key: 'LSS 1',
      name: 'Wochentage orange',
      backgroundColor: Color(0xFFFFA537),
      fontColor: Color(0xFF000000),
    ),
    GridStyleEntry(
      key: 'LSS 2',
      name: 'Wochentage rot',
      backgroundColor: Color(0xFFFF3737),
      fontColor: Color(0xFF000000),
    ),

    // ── Messenger ────────────────────────────────────────────────────────────
    GridStyleEntry(
      key: 'style 38',
      name: 'WhatsApp Navigation',
      backgroundColor: Color(0xFF00BCA2),
      fontColor: Color(0xFFFFFFFF),
    ),
    GridStyleEntry(
      key: 'style 36',
      name: 'Telegram Navigation',
      backgroundColor: Color(0xFFC0A24A),
      fontColor: Color(0xFFFFFFFF),
    ),
  ];
}
