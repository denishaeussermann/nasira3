# Nasira – Änderungsprotokoll 23. März 2026

## Übersicht

Zwei lange Sessions. Themen: Kontext-bewusstes Ranking, Evaluation-Suite, Bugfixes aus App-Logs.

---

## 1. Kontext-bewusstes Ranking (Step 4 + Step 6)

**Problem:** Wenn der Nutzer „mau" tippt nach dem Wort „computer", erschien „Maus (Tier)" vor „Mausklick". Der Kontext „Computer" wurde ignoriert.

**Lösung:**
- `_contextAwarePrefixSearch()` in `suggestion_engine.dart` neu eingeführt (Step 4)
- `_reRankByContext()` für Step 6 (nextWordSuggestions) eingeführt
- Score-Formel: `0.5 × contextSim + 0.2 × rankScore + catBonus`
- `catBonus = 0.3` wenn Kategorie des Kandidaten zur Kontext-Kategorie passt
- Kontext-Vektor = Durchschnitt der letzten 5 abgeschlossenen Token (fastText)

---

## 2. Kategorie-Ableitung aus Dateiname

**Problem:** ~7.000 Symbole hatten `category = "Nomen & Sonstiges"` (Import-Catch-All). Dadurch funktionierte der Kategorie-Bonus nicht.

**Lösung in `SymbolEntry.fromJson()`:**
```dart
if (rawCategory.isEmpty || rawCategory == 'Nomen & Sonstiges') {
  // Kategorie aus Pfad ableiten: "Tiere\maus.jpg" → "Tiere"
  final parts = fileName.replaceAll('\\', '/').split('/');
  category = parts.length > 1 ? parts.first : 'Sonstiges';
}
```

---

## 3. `categoryForWordFuzzy()` + Bugfix `mappedSymbolForWord()`

**Problem:** `categoryForWord("computer")` → null, weil nur `"computer1"` in den Daten existiert.

**Lösung:**
- `categoryForWordFuzzy()` in `NasiraData` hinzugefügt: direkter Lookup, Fallback über `mappedSymbolForWord()`
- Bug in `mappedSymbolForWord()` behoben: suchte nach Original-Wort statt nach `result.matchedWord`
- `wordsInSameCategory()` nutzt jetzt `categoryForWordFuzzy()`

---

## 4. Zahlensuffix beim Einfügen entfernen

**Problem:** Klick auf Vorschlag „computer" fügte „computer1" in den Text ein.

**Lösung in `_insertWord()` (`nasira_home_page.dart`):**
```dart
final insertText = word.text.replaceAll(RegExp(r'(?<=[a-zA-ZäöüÄÖÜß])\d+$'), '');
```

---

## 5. Evaluation-Suite

**Neu erstellt:** `test/engine_eval_test.dart`

Läuft ohne App-Start:
```
flutter test test/engine_eval_test.dart --reporter=expanded
```

Testgruppen:
1. Kontext-Präfix (computer→mausklick, schule, tiere)
2. Drei-Zeichen-Präfix (Erreichbarkeit)
3. Kurze Wörter (es, er, in)
4. Step-6 Kontext-Reranking (nach Leerzeichen)
5. Kategorie-Coverage-Report (alle Kategorien, automatisch)
6. Embedding-Diagnose (Cosine-Scores)

Lädt Daten von `C:\Users\denlu\Documents\nasira_import\`, Fallback auf bundled.

---

## 6. Funktionswörter in Step 5 + Step 6 überspringen

**Problem:** Nach „sie essen gern " zeigte Step 5 andere `Kleine_Worte`-Vorschläge statt Lebensmittel. „gern" bestimmte die Kontext-Kategorie.

**Lösung:**
```dart
static const Set<String> _functionWordCategories = {
  'Kleine_Worte', 'Pronomen', 'Fragewörter', 'Konjunktionen',
};
```

- **Step 5:** Sucht jetzt rückwärts nach dem letzten *Inhaltswort* (überspringt Funktionswörter)
- **Step 6 Kategorie-Pool:** Nur Inhaltswort-Token für `wordsInSameCategory()`
- **`_reRankByContext()`:** `contextCategory` sucht über 5 Token (statt 3), überspringt Funktionswörter
- **`_contextAwarePrefixSearch()`:** gleiche Änderung

---

## 7. Doppelte `[NONE]`-Log-Einträge

**Problem:** Pro Wort-Lookup erschienen zwei `[NONE]`-Einträge im Log.

**Ursache:** `_cachedLookup()` rief erst `lookup()` auf (loggt `[NONE]`), dann `lookupWithFallback()` (lief dieselben Stufen nochmal durch → loggt erneut `[NONE]`).

**Lösung in `nasira_home_page.dart`:**
```dart
_symbolLookup.lookupWithFallback(data, cacheKey, silent: true, ...);
//  ↑ silent:true — Stufen 1–6 bereits von lookup() geloggt
```

---

## 8. `[SUGGEST]`-Spam im Log

**Problem:** Hunderte identische `[SUGGEST]`-Zeilen für denselben Text.

**Ursache:** `TextEditingController.addListener` feuert auch bei Cursor-Bewegungen (nicht nur bei Textänderungen). Android-Tastatur sendet zudem viele Composing-Events.

**Lösung in `_handleTextChanged()`:**
```dart
final currentText = _textController.text;
if (currentText == _lastHandledText) return;
_lastHandledText = currentText;
```

---

## 9. Neue Aliases

In `_aliases` (`symbol_lookup_service.dart`) hinzugefügt:

| Eingabe | → Symbol |
|---------|----------|
| `tu`, `tue`, `tust`, `tut` | `machen` |
| `wunderschoen` | `schoen` |
| `wundervoll`, `wunderbar` | `schoen` |
| `superschoen`, `megaschoen` | `schoen` |
| `supergut`, `megagut`, `wundergut` | `gut` |
| `superklasse` | `gut` |
| `supercool`, `megacool` | `cool` |

---

## Geänderte Dateien

| Datei | Was |
|-------|-----|
| `lib/services/suggestion_engine.dart` | Steps 4–6 Kontext-Ranking, Funktionswort-Filterung |
| `lib/services/symbol_lookup_service.dart` | Neue Aliases (tu/tue, wunderschön, …) |
| `lib/models/symbol_entry.dart` | Kategorie aus Dateiname ableiten |
| `lib/models/nasira_data.dart` | `categoryForWordFuzzy()`, Bugfix `mappedSymbolForWord()` |
| `lib/nasira_home_page.dart` | Zahlensuffix-Fix, silent-Fix, SUGGEST-Spam-Fix |
| `test/engine_eval_test.dart` | Neue Evaluation-Suite (neu erstellt) |
