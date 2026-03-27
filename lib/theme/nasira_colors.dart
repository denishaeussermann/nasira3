import 'package:flutter/material.dart';

/// Exakte Farben aus dem Grid3 Nasira-Export (`styles.xml`).
abstract final class NasiraColors {
  // ── Hintergründe ────────────────────────────────────────────────────────────
  static const startseite       = Color(0xFF171947);   // dunkles Navy
  static const briefBg          = Color(0xFFF9FAFA);   // Off-White
  static const keyboardBg       = Color(0xFF273849);   // dunkles Blaugrau
  static const gridDark         = Color(0xFF0F2045);   // Grid-Hintergrund dunkel

  // ── Navigation & Aktionen ──────────────────────────────────────────────────
  static const navGreen         = Color(0xFF5D8057);   // Oliv-Grün (Satzteile Navigation)
  static const navTaupe         = Color(0xFF807C72);   // Taupe (Datei-Operationen)
  static const navYellow        = Color(0xFFD4A800);   // Gelb (Einstellungen/Exit)

  // ── Module-Kacheln auf der Startseite ─────────────────────────────────────
  static const moduleDarkGreen  = Color(0xFF2E4529);   // "Satzteile dunkel" (style 6)
  static const moduleGreen      = Color(0xFF91B38A);   // "Satzteile hell" (Einkaufen 1)

  // ── Brief ──────────────────────────────────────────────────────────────────
  static const briefTopic       = Color(0xFF91B38A);   // hell-grün (Brief Hauptthema, style 4)
  static const briefTopicDark   = Color(0xFF2E4529);   // dunkel-grün
  static const briefQuestion    = Color(0xFF3B5936);   // dunkel-grün (Brief Frage, Aktionsfeld 3)
  static const briefSentence    = Color(0xFFC4302B);   // Rot (Brief Satzanfang, Aktionsfeld 2)
  static const briefNeutral     = Color(0xFFBFBBAC);   // Beige (Neutral, Aktionsfeld 4)
  static const briefBorder      = Color(0xFF4B6E50);   // Inhaltsübersicht Border

  // ── Freies Schreiben ───────────────────────────────────────────────────────
  static const fsBorder         = Color(0xFF2C82C9);   // TextEditor-Rahmen
  static const fsPrediction     = Color(0xFFDAF2FB);   // Vorhersage-Zellen Hintergrund
  static const fsPredictionText = Color(0xFF5E80C4);   // Vorhersage-Zellen Text
  static const fsPredictionBorder = Color(0xFF5E80C4); // Vorhersage-Rahmen

  // ── Tastatur ───────────────────────────────────────────────────────────────
  static const keyBg            = Color(0xFF3A4F62);   // Tasten-Hintergrund
  static const keyBgDark        = Color(0xFF1E2E3B);   // Spezial-Tasten
  static const keySpecial       = Color(0xFF2D5FA8);   // Space / Enter

  // ── Tagebuch Wochentage ────────────────────────────────────────────────────
  static const tagMontag        = Color(0xFFE6A800);
  static const tagDienstag      = Color(0xFF2E7D32);
  static const tagMittwoch      = Color(0xFF1565C0);
  static const tagDonnerstag    = Color(0xFFC62828);
  static const tagFreitag       = Color(0xFFE65100);
  static const tagSamstag       = Color(0xFF78909C);
  static const tagSonntag       = Color(0xFFAD1457);
  static const tagWochenende    = Color(0xFF00838F);
  static const tagFerien        = Color(0xFF558B2F);

  // ── Messaging ──────────────────────────────────────────────────────────────
  static const telegramDark     = Color(0xFF00BDA3);

  // ── Allgemein ──────────────────────────────────────────────────────────────
  static const textWhite        = Colors.white;
  static const textDark         = Color(0xFF1A1A2E);
  static const cellWhite        = Color(0xFFFFFFFF);
}
