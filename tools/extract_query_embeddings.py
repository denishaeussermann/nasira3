import argparse
import struct
import fasttext
from pathlib import Path

def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument('--fasttext', required=True)
    p.add_argument('--output', required=True)
    p.add_argument('--top', type=int, default=50000)
    p.add_argument('--extra', default=None)
    return p.parse_args()

def load_extra_words(path):
    if not path:
        return set()
    with open(path, encoding='utf-8') as f:
        return {line.strip().lower() for line in f if line.strip()}

def main():
    args = parse_args()
    extra = load_extra_words(args.extra)

    print(f'Lade FastText: {args.fasttext}')
    ft = fasttext.load_model(args.fasttext)

    words = ft.get_words()
    print(f'  {len(words)} Woerter im Modell')

    needed = set()
    for w in words[:args.top]:
        needed.add(w.lower())
    needed.update(extra)
    print(f'  Extrahiere {len(needed)} Vektoren ...')

    entries = []
    for i, word in enumerate(needed):
        vec = ft.get_word_vector(word)
        entries.append((word, vec))
        if (i + 1) % 5000 == 0:
            print(f'  {i + 1} verarbeitet ...')

    out = Path(args.output)
    out.parent.mkdir(parents=True, exist_ok=True)

    print(f'Schreibe {len(entries)} Eintraege nach {args.output} ...')
    with open(out, 'wb') as f:
        f.write(struct.pack('<i', len(entries)))
        for word, vec in entries:
            wb = word.encode('utf-8')
            f.write(struct.pack('<H', len(wb)))
            f.write(wb)
            f.write(struct.pack('<H', len(wb)))
            f.write(wb)
            for v in vec:
                f.write(struct.pack('<f', float(v)))

    size_mb = out.stat().st_size / 1024 / 1024
    print(f'Fertig! Dateigroesse: {size_mb:.1f} MB')

if __name__ == '__main__':
    main()
