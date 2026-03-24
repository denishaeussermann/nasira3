#!/usr/bin/env python3
"""
Nasira Semantische Karte Builder  v4
=======================================
Erstellt assets/nasira_semantic_map.bin.

Ansatz: Vollständiges fastText-Vokabular + Batch-Cosine via numpy BLAS
  - Kein sequenzieller Neighbor-Search mehr (war langsam, fehleranfällig)
  - numpy @ (matrix multiply) nutzt alle CPU-Kerne via MKL/OpenBLAS
  - ThreadPoolExecutor für parallele Vektor-Extraktion
  - Laufzeit: ~3–8 Minuten  (statt 50 Minuten)
  - Coverage: gesamtes fastText-Vokabular (~200k–500k deutsche Wörter)

Verwendung:
  python tools/build_semantic_map.py \\
    --fasttext   C:/NLP/cc.de.300.bin \\
    --embeddings assets/nasira_embeddings.bin \\
    --output     assets/nasira_semantic_map.bin

Optionale Parameter:
  --min-verify 0.47   Mindest-Cosine-Ähnlichkeit (default: 0.47)
  --workers    8      Parallel-Threads für Vektor-Extraktion (default: 8)
  --chunk      2000   Chunk-Größe für Batch-Cosine (default: 2000)
"""

import argparse
import json
import struct
import unicodedata
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import numpy as np


def parse_args():
    p = argparse.ArgumentParser(description='Nasira Semantische Karte Builder v4')
    p.add_argument('--fasttext',   required=True,
                   help='Pfad zur fastText-Modelldatei (cc.de.300.bin)')
    p.add_argument('--embeddings', default='assets/nasira_embeddings.bin')
    p.add_argument('--data',       default=r'C:\Users\denlu\Documents\nasira_import',
                   help='Nasira-Importordner (words.json) — filtert Dateiname-Schlüssel')
    p.add_argument('--output',     default='assets/nasira_semantic_map.bin')
    p.add_argument('--min-verify', type=float, default=0.47,
                   help='Mindest-Cosine nach Verifikation (default: 0.47)')
    p.add_argument('--workers',    type=int,   default=8,
                   help='Threads für Vektor-Extraktion (default: 8)')
    p.add_argument('--chunk',      type=int,   default=2000,
                   help='Chunk-Größe für numpy-Batch-Cosine (default: 2000)')
    return p.parse_args()


def normalize(text):
    """Identisch zu TextNormalizer.normalize() in Dart."""
    text = unicodedata.normalize('NFC', text.lower().strip())
    for src, dst in [('ä','ae'),('ö','oe'),('ü','ue'),('ß','ss'),
                     ('Ä','ae'),('Ö','oe'),('Ü','ue')]:
        text = text.replace(src, dst)
    return text


def read_symbol_data(path):
    keys, vecs = [], []
    with open(path, 'rb') as f:
        n = struct.unpack('<i', f.read(4))[0]
        for _ in range(n):
            kl  = struct.unpack('<H', f.read(2))[0]
            key = f.read(kl).decode('utf-8')
            cl  = struct.unpack('<H', f.read(2))[0]; f.read(cl)
            vec = struct.unpack('<300f', f.read(1200))
            keys.append(key); vecs.append(list(vec))
    return keys, vecs


def write_semantic_map(path, mapping):
    out = Path(path)
    out.parent.mkdir(parents=True, exist_ok=True)
    with open(out, 'wb') as f:
        f.write(struct.pack('<i', len(mapping)))
        for word, sym_key in mapping.items():
            for s in (word, sym_key):
                sb = s.encode('utf-8')
                f.write(struct.pack('<H', len(sb))); f.write(sb)
    return out.stat().st_size / 1024 / 1024


def is_valid_vocab_word(word):
    """Nur echte Wörter: alphabetisch, 3–25 Zeichen, keine Zahlen/Satzzeichen."""
    return (3 <= len(word) <= 25 and
            all(c.isalpha() or c in 'äöüÄÖÜßéàèùâêîôûëïüœæ' for c in word))


def extract_vectors_parallel(words, ft, workers):
    """
    Extrahiert fastText-Vektoren parallel via ThreadPoolExecutor.
    fastText-C-Extension gibt GIL bei Vektor-Berechnung frei → echter Speedup.
    """
    print(f'  Starte {workers} Threads für {len(words):,} Wörter ...')
    with ThreadPoolExecutor(max_workers=workers) as ex:
        vecs = list(ex.map(ft.get_word_vector, words))
    return np.array(vecs, dtype=np.float32)


def main():
    args = parse_args()

    # ── 1. Symbol-Daten laden ───────────────────────────────────────────
    print('Lade Symbol-Daten ...')
    sym_keys, sym_vecs_list = read_symbol_data(args.embeddings)

    # Nur Wort-abgeleitete Keys behalten (aus words.json), keine Dateinamen-Schlüssel
    # (z.B. "muedefb", "schlafen1" kommen von Dateinamen und haben sinnlose Vektoren)
    data_dir = Path(args.data)
    words_path = data_dir / 'words.json'
    if words_path.exists():
        with open(words_path, encoding='utf-8') as f:
            words_json = json.load(f)
        word_derived_keys = {normalize(w['text']) for w in words_json if w.get('text')}
        before = len(sym_keys)
        filtered = [(k, v) for k, v in zip(sym_keys, sym_vecs_list) if k in word_derived_keys]
        sym_keys      = [k for k, _ in filtered]
        sym_vecs_list = [v for _, v in filtered]
        print(f'  Wort-abgeleitete Keys: {len(sym_keys):,} / {before:,} '
              f'(gefiltert: {before - len(sym_keys):,} Dateinamen-Schlüssel)')
    else:
        print(f'  WARNUNG: words.json nicht gefunden in {data_dir} — alle Keys werden verwendet')

    sym_keys_set = set(sym_keys)

    sym_vecs_np   = np.array(sym_vecs_list, dtype=np.float32)
    sym_norms     = np.linalg.norm(sym_vecs_np, axis=1, keepdims=True)
    sym_norms[sym_norms < 1e-6] = 1.0
    sym_vecs_norm = sym_vecs_np / sym_norms   # L2-normiert für Cosine via Dot
    print(f'  {len(sym_keys):,} Symbole  |  Symbol-Matrix: {sym_vecs_norm.shape}\n')

    # ── 2. FastText laden ───────────────────────────────────────────────
    print(f'Lade FastText: {args.fasttext}')
    print('  (ca. 60 Sekunden ...)')
    import fasttext
    ft = fasttext.load_model(args.fasttext)
    print('  OK\n')

    # ── 3. fastText-Vokabular filtern ───────────────────────────────────
    print('Lade und filtere fastText-Vokabular ...')
    all_words = ft.get_words()
    print(f'  Rohvokabular: {len(all_words):,} Einträge')

    # Normalisierter Key → originales Wort (erstes Vorkommen gewinnt).
    # Original-Form für fastText-Abfrage behalten (Umlaute → bessere Vektoren).
    word_map = {}   # normalized_key → original_form_with_umlauts
    for w in all_words:
        if not is_valid_vocab_word(w):
            continue
        nk = normalize(w)
        if nk not in sym_keys_set and nk not in word_map:
            word_map[nk] = w

    norm_keys  = list(word_map.keys())
    orig_words = [word_map[k] for k in norm_keys]
    print(f'  {len(norm_keys):,} Kandidaten nach Filterung\n')

    # ── 4. Vektoren parallel extrahieren ────────────────────────────────
    print(f'Extrahiere Vektoren ({args.workers} Threads) ...')
    q_vecs_all = extract_vectors_parallel(orig_words, ft, args.workers)

    # L2-Normierung für Cosine
    q_norms = np.linalg.norm(q_vecs_all, axis=1, keepdims=True)
    zero_mask = q_norms.flatten() < 1e-6
    q_norms[q_norms < 1e-6] = 1.0
    q_norm_all = q_vecs_all / q_norms
    print(f'  Fertig. Shape: {q_norm_all.shape}\n')

    # ── 5. Batch-Cosine via numpy BLAS (alle CPU-Kerne) ─────────────────
    total      = len(norm_keys)
    chunk_size = args.chunk
    n_chunks   = (total + chunk_size - 1) // chunk_size
    final_map  = {}

    print(f'Batch-Cosine: {total:,} Wörter × {len(sym_keys):,} Symbole')
    print(f'  Chunks à {chunk_size:,}  ({n_chunks} Chunks)\n')

    for ci, start in enumerate(range(0, total, chunk_size)):
        end        = min(start + chunk_size, total)
        chunk_norm = q_norm_all[start:end]           # (chunk × 300)
        chunk_zero = zero_mask[start:end]

        # numpy @ nutzt MKL/OpenBLAS → alle verfügbaren Kerne
        sims     = chunk_norm @ sym_vecs_norm.T      # (chunk × n_symbols)
        best_idx = np.argmax(sims, axis=1)           # bestes Symbol pro Wort
        best_sim = sims[np.arange(len(chunk_norm)), best_idx]

        for j in range(len(chunk_norm)):
            if chunk_zero[j]:
                continue
            if best_sim[j] >= args.min_verify:
                final_map[norm_keys[start + j]] = sym_keys[best_idx[j]]

        # Fortschritt alle ~50k Wörter
        done = end
        if ci % max(1, 50000 // chunk_size) == 0 or done == total:
            pct = 100 * done / total
            print(f'  {done:>7,} / {total:,}  ({pct:5.1f}%)  →  {len(final_map):,} Mappings')

    print(f'\n  {len(final_map):,} verifizierte Mappings\n')

    # ── 6. Stichproben ──────────────────────────────────────────────────
    print('Stichproben:')
    test_words = [
        'müdigkeit', 'trinkgeld', 'freude', 'fröhlich', 'fröhlichkeit',
        'erschöpft', 'erschöpfung', 'aufregung', 'begeisterung',
        'schmerzhaft', 'hungrig', 'durstig',
        'garnicht', 'niemals', 'weinen', 'lachen', 'ängstlich',
        'traurigkeit', 'einsamkeit', 'stolz',
    ]
    norm_key_idx = {k: i for i, k in enumerate(norm_keys)}
    for w in test_words:
        k = normalize(w)
        if k in sym_keys_set:
            print(f'  {k:25s} → (direktes Symbol — kein Eintrag nötig)')
            continue
        sym = final_map.get(k)
        if sym:
            print(f'  {k:25s} → {sym}')
        else:
            idx = norm_key_idx.get(k)
            if idx is not None:
                sims   = q_norm_all[idx] @ sym_vecs_norm.T
                best_i = int(np.argmax(sims))
                best_s = float(sims[best_i])
                print(f'  {k:25s} → KEIN MATCH  '
                      f'(bestes: {sym_keys[best_i]} @ {best_s:.3f})')
            else:
                print(f'  {k:25s} → (nicht im fastText-Vokabular)')
    print()

    # ── 7. Schreiben ────────────────────────────────────────────────────
    print(f'Schreibe {args.output} ...')
    size_mb = write_semantic_map(args.output, final_map)

    print()
    print('=' * 50)
    print('  FERTIG')
    print('=' * 50)
    print(f'  Kandidaten:  {len(norm_keys):,}')
    print(f'  Mappings:    {len(final_map):,}')
    print(f'  Dateigröße:  {size_mb:.2f} MB')
    print()
    print('  Nächster Schritt: App neu starten (flutter run)')


if __name__ == '__main__':
    main()
