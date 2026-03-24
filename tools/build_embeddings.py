#!/usr/bin/env python3
"""
Nasira Symbol-Embeddings Builder
=================================
Generiert assets/nasira_embeddings.bin aus allen gemappten Symbol-Wörtern.

Verwendung:
  python tools/build_embeddings.py \
    --fasttext  C:/pfad/zu/cc.de.300.bin \
    --data      C:/Users/denlu/Documents/nasira_import \
    --output    assets/nasira_embeddings.bin

Das Skript liest words.json, symbols.json und mappings.json,
und erstellt für jedes gemappte Wort einen 300-dim fastText-Vektor.

Vorher: 9.018 Einträge (60% der Symbole)
Nachher: ~15.000 Einträge (100% der Symbole)
"""

import argparse
import json
import struct
import unicodedata
from pathlib import Path


def parse_args():
    p = argparse.ArgumentParser(description='Nasira Symbol-Embeddings Builder')
    p.add_argument('--fasttext', required=True,
                   help='Pfad zur fastText-Modelldatei (cc.de.300.bin)')
    p.add_argument('--data',
                   default=r'C:\Users\denlu\Documents\nasira_import',
                   help='Pfad zum Import-Ordner (words.json, symbols.json, mappings.json)')
    p.add_argument('--output',
                   default='assets/nasira_embeddings.bin',
                   help='Ausgabedatei (default: assets/nasira_embeddings.bin)')
    return p.parse_args()


def normalize(text):
    """
    Entspricht TextNormalizer.normalize() in Dart:
    Kleinbuchstaben + Umlaute zu ASCII (ae/oe/ue/ss).
    """
    text = unicodedata.normalize('NFC', text.lower().strip())
    for src, dst in [('ä', 'ae'), ('ö', 'oe'), ('ü', 'ue'), ('ß', 'ss'),
                     ('Ä', 'ae'), ('Ö', 'oe'), ('Ü', 'ue')]:
        text = text.replace(src, dst)
    return text


def strip_extension(filename):
    """'Tiere\\maus.jpg' → 'maus',  'Computer/maus.jpg' → 'maus'"""
    base = filename.replace('\\', '/').split('/')[-1]
    dot  = base.rfind('.')
    return base[:dot] if dot >= 0 else base


def write_binary(output_path, entries):
    """
    Schreibt das Binärformat das EmbeddingService erwartet:
      int32:  Anzahl Einträge
      je Eintrag:
        uint16 + bytes  key   (UTF-8)
        uint16 + bytes  clean (UTF-8)
        300 × float32   Vektor
    """
    out = Path(output_path)
    out.parent.mkdir(parents=True, exist_ok=True)

    with open(out, 'wb') as f:
        f.write(struct.pack('<i', len(entries)))
        for key, clean, vec in entries:
            for s in (key, clean):
                sb = s.encode('utf-8')
                f.write(struct.pack('<H', len(sb)))
                f.write(sb)
            for v in vec:
                f.write(struct.pack('<f', float(v)))

    return out.stat().st_size / 1024 / 1024


def main():
    args = parse_args()
    data_dir = Path(args.data)

    # ── 1. JSON laden ──────────────────────────────────────────────────────
    print('Lade Nasira-Daten ...')
    with open(data_dir / 'words.json',    encoding='utf-8') as f:
        words    = json.load(f)
    with open(data_dir / 'symbols.json',  encoding='utf-8') as f:
        symbols  = json.load(f)
    with open(data_dir / 'mappings.json', encoding='utf-8') as f:
        mappings = json.load(f)

    print(f'  {len(words):,} Wörter  |  {len(symbols):,} Symbole  |  {len(mappings):,} Mappings')

    word_by_id   = {w['id']: w for w in words}
    symbol_by_id = {s['id']: s for s in symbols}

    # ── 2. Schlüssel sammeln ───────────────────────────────────────────────
    # key   → was in _symbolKeys landet (Suchtreffer muss data.searchSymbol() finden)
    # clean → was in _symbolClean landet (Leerzeichen-getrennte Alternative)
    #
    # Zwei Schlüssel pro Mapping:
    #   A) normalize(word.text)         z.B. "computer1"   → _mappedByNormalizedWord
    #   B) normalize(stripExt(fileName)) z.B. "maus"       → _mappedByFileName
    #
    # clean = normalize(symbol.label)   z.B. "computer 1"  → _symbolClean

    seen     = {}   # key (normalisiert) → clean  (dedupliziert)
    originals = {}  # key (normalisiert) → originaler Text (mit Umlauten, für fastText)
    skipped  = 0

    for m in mappings:
        word   = word_by_id.get(m['wordId'])
        symbol = symbol_by_id.get(m['symbolId'])
        if word is None or symbol is None:
            skipped += 1
            continue

        clean = normalize(symbol.get('label', word['text']))

        # Schlüssel A: Worttext (normalisiert als Key, Original für fastText)
        key_a = normalize(word['text'])
        if key_a and key_a not in seen:
            seen[key_a]      = clean
            originals[key_a] = word['text']          # z.B. "müde" statt "muede"

        # Schlüssel B: Dateiname ohne Erweiterung
        key_b    = normalize(strip_extension(symbol['fileName']))
        orig_b   = strip_extension(symbol['fileName'])
        if key_b and key_b not in seen:
            seen[key_b]      = clean
            originals[key_b] = orig_b                # z.B. "müdeFB" statt "muedefb"

    print(f'  {len(seen):,} einzigartige Schlüssel  |  {skipped} Mappings übersprungen')

    # ── 3. FastText laden ──────────────────────────────────────────────────
    print(f'\nLade FastText: {args.fasttext}')
    print('  (ca. 30–60 Sekunden ...)')
    import fasttext  # Import erst hier, damit --help ohne fasttext funktioniert
    ft = fasttext.load_model(args.fasttext)
    print('  OK\n')

    # ── 4. Vektoren extrahieren ────────────────────────────────────────────
    # fastText liefert immer einen Vektor (auch für unbekannte Wörter via Subword).
    print(f'Extrahiere {len(seen):,} Vektoren ...')
    print('  (Abfrage mit Original-Formen inkl. Umlaute für bessere Vektoren)')
    entries = []
    for i, (key, clean) in enumerate(seen.items()):
        # Original-Form verwenden (z.B. "müde" statt "muede") →
        # fastText liefert dann den echten Trainingsvektor, nicht nur Subword-Schätzung.
        original = originals.get(key, key)
        vec = ft.get_word_vector(original)
        entries.append((key, clean, vec))
        if (i + 1) % 2000 == 0:
            print(f'  {i + 1:,} / {len(seen):,}')

    # ── 5. Schreiben ───────────────────────────────────────────────────────
    print(f'\nSchreibe {args.output} ...')
    size_mb = write_binary(args.output, entries)

    print()
    print('=' * 45)
    print('  FERTIG')
    print('=' * 45)
    print(f'  Einträge vorher:  9.018  (60% Coverage)')
    print(f'  Einträge jetzt:   {len(entries):,}  (~100% Coverage)')
    print(f'  Dateigröße:       {size_mb:.1f} MB')
    print()
    print('  Nächster Schritt: App neu starten (flutter run)')
    print('  Der EmbeddingService lädt die neue Datei automatisch.')


if __name__ == '__main__':
    main()
