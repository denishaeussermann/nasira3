#!/usr/bin/env python3
"""
Nasira Vokabular-Builder
========================
Erweitert die words.json mit echten deutschen Frequenzdaten.

Quellen:
  1. Deutsche Wortfrequenzliste (OpenSubtitles, hermitdave/FrequencyWords)
     -> bestimmt den rank jedes Wortes
  2. Oeffentliche deutsche Prosatexte (Gutenberg) mit automatischer
     Spracherkennung -> liefert nextWords-Bigramme

Was passiert:
  - Bestehende handgepflegte Eintraege bleiben erhalten
  - rank wird aus echter Frequenz aktualisiert
  - nextWords wird ergaenzt wo noch leer
  - Neue Alltagswoerter werden hinzugefuegt (bis MAX_NEW_WORDS)
"""

import json
import re
import urllib.request
from collections import Counter, defaultdict
from pathlib import Path

# ── Pfade ─────────────────────────────────────────────────────────────────

ROOT       = Path(__file__).parent.parent
WORDS_FILE = ROOT / "assets" / "data" / "words.json"

# ── Quellen ───────────────────────────────────────────────────────────────

# Deutsche Wortfrequenzliste (OpenSubtitles 2016, ~50.000 Woerter)
# Format: "wort anzahl" pro Zeile
FREQ_LIST_URL = (
    "https://raw.githubusercontent.com/hermitdave/FrequencyWords"
    "/master/content/2016/de/de_50k.txt"
)

# Deutsche Prosatexte fuer Bigramme (mit Sprachpruefung)
PROSE_SOURCES = [
    # Alice im Wunderland (deutsch) - einfache Saetze, ideal fuer AAC
    ("Alice im Wunderland (de)",
     "https://www.gutenberg.org/cache/epub/19778/pg19778.txt"),
    # Kafka - Die Verwandlung - klare Alltagssprache
    ("Kafka - Die Verwandlung (de)",
     "https://www.gutenberg.org/cache/epub/22367/pg22367.txt"),
    # Goethe - Werther - emotionale Alltagssprache
    ("Goethe - Werther (de)",
     "https://www.gutenberg.org/cache/epub/2407/pg2407.txt"),
    # Goethe - Reineke Fuchs - Fabeln, einfache Sprache
    ("Goethe - Reineke Fuchs (de)",
     "https://www.gutenberg.org/cache/epub/2228/pg2228.txt"),
    # Goethe - Faust II - weiteres Vokabular
    ("Goethe - Faust II (de)",
     "https://www.gutenberg.org/cache/epub/2230/pg2230.txt"),
]

# ── Parameter ─────────────────────────────────────────────────────────────

MAX_NEW_WORDS   = 700   # max. neue Woerter hinzufuegen
MAX_RANK        = 3000  # nur Woerter bis Rang 3000 aus der Frequenzliste
MAX_WORD_LEN    = 16    # laengere Woerter meist Komposita
MIN_WORD_LEN    = 2
NEXTWORDS_LIMIT = 5     # max. nextWords pro Wort

# Woerter die nicht in die App sollen
BLOCKLIST = {
    # Gutenberg-Metadaten
    "gutenberg", "project", "ebook", "title", "author", "release",
    "copyright", "chapter", "produced", "encoding", "utf", "http",
    "www", "org", "html",
    # Zu formal / nicht AAC-relevant
    "usw", "bzw", "vgl", "hrsg", "ebd",
}

# ── Download ──────────────────────────────────────────────────────────────

def fetch(label, url):
    print(f"  Lade {label} ...", end=" ", flush=True)
    try:
        req = urllib.request.Request(
            url, headers={"User-Agent": "NasiraBuilder/1.0"}
        )
        with urllib.request.urlopen(req, timeout=20) as r:
            raw = r.read()
        for enc in ("utf-8", "latin-1"):
            try:
                text = raw.decode(enc)
                print(f"ok ({len(text)//1000} KB)")
                return text
            except UnicodeDecodeError:
                continue
    except Exception as e:
        print(f"FEHLER: {e}")
    return ""

# ── Normalisierung ────────────────────────────────────────────────────────

def normalize(word):
    """
    Kleinschreibung + Umlaute zu ASCII (nur fuer interne Keys/Vergleiche).
    'muesst' und 'musst' haben denselben Key -> werden dedupliciert.
    """
    return (
        word.lower()
        .replace("ae", "ae").replace("oe", "oe").replace("ue", "ue")
        .replace("ae", "ae")
        .replace("a\u0308", "ae").replace("o\u0308", "oe")
        .replace("u\u0308", "ue").replace("\u00df", "ss")
        .replace("\u00e4", "ae").replace("\u00f6", "oe")
        .replace("\u00fc", "ue")
        .replace("\u00c4", "ae").replace("\u00d6", "oe")
        .replace("\u00dc", "ue")
    )

def is_usable(word):
    if len(word) < MIN_WORD_LEN or len(word) > MAX_WORD_LEN:
        return False
    nw = normalize(word)
    if nw in BLOCKLIST:
        return False
    if not re.match(r"^[a-z\u00e4\u00f6\u00fc\u00df]+$", word, re.IGNORECASE):
        return False
    return True

def is_german(tokens, threshold=0.03):
    """
    Gibt True zurueck wenn der Text wahrscheinlich Deutsch ist.
    Prueft ob typische deutsche Funktionswoerter haeufig vorkommen.
    """
    total = len(tokens)
    if total < 100:
        return False
    de_markers = {"und", "der", "die", "das", "ist", "ich", "ein", "eine",
                  "nicht", "mit", "sie", "er", "es", "auf", "den", "dem"}
    en_markers = {"the", "of", "and", "to", "in", "that", "is", "was",
                  "for", "on", "are", "with", "his", "they", "at"}
    tok_lower = [t.lower() for t in tokens[:2000]]
    de_count = sum(1 for t in tok_lower if t in de_markers)
    en_count = sum(1 for t in tok_lower if t in en_markers)
    return de_count > en_count and de_count / min(total, 2000) > threshold

# ── Textverarbeitung ──────────────────────────────────────────────────────

def strip_gutenberg(text):
    for marker in ("*** START OF", "***START OF"):
        i = text.find(marker)
        if i != -1:
            text = text[text.find("\n", i) + 1:]
            break
    for marker in ("*** END OF", "***END OF"):
        i = text.find(marker)
        if i != -1:
            text = text[:i]
            break
    return text

def tokenize(text):
    """Gibt Woerter in Originalschreibung zurueck (Kleinbuchstaben)."""
    text = re.sub(r"[^\w\s]", " ", text, flags=re.UNICODE)
    return [t.lower() for t in text.split() if t.isalpha() and len(t) >= 2]

# ── JSON-Daten ────────────────────────────────────────────────────────────

def load_existing():
    if not WORDS_FILE.exists():
        return []
    with open(WORDS_FILE, "r", encoding="utf-8") as f:
        return json.load(f)

def max_id(entries):
    ids = [int(m.group(1))
           for e in entries
           for m in [re.match(r"w(\d+)", e.get("id", ""))]
           if m]
    return max(ids, default=0)

# ── Hauptlogik ────────────────────────────────────────────────────────────

def main():
    print("=" * 50)
    print("  Nasira Vokabular-Builder")
    print("=" * 50)
    print()

    # ── 1. Bestehende Daten ───────────────────────────────────────────────
    existing = load_existing()
    existing_by_norm = {normalize(e["text"]): e for e in existing}
    print(f"Vorhandene Woerter: {len(existing)}")
    print()

    # ── 2. Frequenzliste laden ────────────────────────────────────────────
    print("Frequenzliste:")
    freq_text = fetch("de_50k (OpenSubtitles)", FREQ_LIST_URL)
    if not freq_text:
        print("Frequenzliste konnte nicht geladen werden. Abbruch.")
        return

    # Format: "wort anzahl" pro Zeile
    freq_rank: dict[str, int] = {}   # normalisierter Key -> Rang
    freq_display: dict[str, str] = {}  # normalisierter Key -> Anzeigewort

    rank = 1
    for line in freq_text.splitlines():
        parts = line.strip().split()
        if len(parts) < 2:
            continue
        word = parts[0].lower()
        if not is_usable(word):
            continue
        nw = normalize(word)
        if nw not in freq_rank:
            freq_rank[nw] = rank
            freq_display[nw] = word
            rank += 1
        if rank > MAX_RANK:
            break

    print(f"  {len(freq_rank)} deutsche Woerter geladen (bis Rang {MAX_RANK})")
    print()

    # ── 3. Prosatexte fuer Bigramme ───────────────────────────────────────
    print("Prosatexte fuer Bigramme:")
    bigrams: defaultdict[str, Counter] = defaultdict(Counter)
    norm_to_display: dict[str, str] = dict(freq_display)  # Basis: Frequenzliste

    for label, url in PROSE_SOURCES:
        text = fetch(label, url)
        if not text:
            continue
        text = strip_gutenberg(text)
        tokens = tokenize(text)
        if not is_german(tokens):
            print(f"    (uebersprungen - kein deutscher Text erkannt)")
            continue
        print(f"    -> {len(tokens):,} Tokens, Bigramme werden extrahiert")
        for i in range(len(tokens) - 1):
            a, b = tokens[i], tokens[i + 1]
            na, nb = normalize(a), normalize(b)
            if is_usable(a) and is_usable(b) and na in freq_rank and nb in freq_rank:
                bigrams[na][nb] += 1
                if na not in norm_to_display:
                    norm_to_display[na] = a
                if nb not in norm_to_display:
                    norm_to_display[nb] = b

    print()

    # ── 4. Bestehende Ränge aktualisieren ─────────────────────────────────
    updated          = 0
    next_words_added = 0

    for entry in existing:
        norm = normalize(entry["text"])
        if norm in freq_rank:
            entry["rank"] = freq_rank[norm]
            updated += 1
        if not entry.get("nextWords") and norm in bigrams:
            top = [
                norm_to_display.get(nb, nb)
                for nb, _ in bigrams[norm].most_common(NEXTWORDS_LIMIT)
                if is_usable(nb)
            ]
            if top:
                entry["nextWords"] = top
                next_words_added += 1

    print(f"Aktualisierte Raenge:  {updated}")
    print(f"nextWords ergaenzt:    {next_words_added}")

    # ── 5. Neue Woerter aus Frequenzliste ─────────────────────────────────
    id_counter  = max_id(existing) + 1
    new_entries = []

    for nw, r in sorted(freq_rank.items(), key=lambda x: x[1]):
        if len(new_entries) >= MAX_NEW_WORDS:
            break
        if nw in existing_by_norm:
            continue

        display  = norm_to_display.get(nw, nw)
        top_next = [
            norm_to_display.get(nb, nb)
            for nb, _ in bigrams[nw].most_common(NEXTWORDS_LIMIT)
            if is_usable(nb)
        ]
        new_entries.append({
            "id":        f"w{id_counter}",
            "text":      display,
            "rank":      r,
            "nextWords": top_next,
        })
        existing_by_norm[nw] = new_entries[-1]
        id_counter += 1

    print(f"Neue Woerter:          {len(new_entries)}")
    print()

    # ── 6. Speichern ──────────────────────────────────────────────────────
    all_entries = existing + new_entries
    all_entries.sort(key=lambda e: e["rank"])

    # Sicherstellen dass Raenge 1..N durchlaufend sind
    for i, e in enumerate(all_entries, 1):
        e["rank"] = i

    with open(WORDS_FILE, "w", encoding="utf-8") as f:
        json.dump(all_entries, f, ensure_ascii=False, indent=2)

    print(f"OK  Gespeichert: {WORDS_FILE}")
    print(f"    Gesamtwoerter: {len(all_entries)}")
    print()

    # ── 7. Vorschau ───────────────────────────────────────────────────────
    print("Top-25 Woerter nach Rang:")
    for e in all_entries[:25]:
        nw   = ", ".join(e["nextWords"][:3]) if e["nextWords"] else "-"
        text = e["text"].encode("ascii", "replace").decode()
        print(f"  {e['rank']:>4}.  {text:<18}  -> {nw}")


if __name__ == "__main__":
    main()
