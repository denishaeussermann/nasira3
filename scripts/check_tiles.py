"""
check_tiles.py
Prüft alle Brief-Gitter-Kacheln auf fehlende Metacom-Symbole
und gibt Dart-Aliases aus.
"""
import xml.etree.ElementTree as ET
import os
import re

GRIDS  = r'C:\Users\denlu\Documents\Nasira EXPORT\Grids'
ASSETS = r'C:\MeineFlutterApps\nasira3\assets\metacom'

# ── Asset-Index aufbauen ──────────────────────────────────────────────────────
# key = lowercase stem  →  (Category_folder, stem_as_stored)
# Farb-Variante hat Vorrang vor SW-Variante
index = {}
for cat in os.listdir(ASSETS):
    cp = os.path.join(ASSETS, cat)
    if not os.path.isdir(cp):
        continue
    for f in sorted(os.listdir(cp)):
        if not f.endswith('.jpg'):
            continue
        stem = f[:-4]
        k = stem.lower()
        if k not in index or index[k][1].endswith('SW'):
            index[k] = (cat, stem)

print(f"Assets indiziert: {len(index)}\n")

# ── Grids scannen ─────────────────────────────────────────────────────────────
BRIEF_GRIDS = sorted(g for g in os.listdir(GRIDS) if g.lower().startswith('brief'))
issues = []   # (grid, text, xml_stem, xml_cat, best_fallback, fb_cat)

for gdir in BRIEF_GRIDS:
    xf = os.path.join(GRIDS, gdir, 'grid.xml')
    if not os.path.exists(xf):
        continue
    root = ET.parse(xf).getroot()
    wl = root.find('.//WordList')
    if not wl:
        continue

    for item in wl.iter('WordListItem'):
        img = item.find('Image')
        if img is None or not img.text:
            continue
        raw = img.text.strip()
        if '[metacm]' not in raw:
            continue

        # Normalisieren: [metacm]tiere\frosch.emf  →  tiere/frosch
        p = raw.replace('[metacm]', '').replace('\\', '/').lower()
        parts = p.split('/')
        if len(parts) < 2:
            continue
        cat  = parts[0]
        stem = parts[-1].rsplit('.', 1)[0]

        texts = ''.join(r.text or '' for r in item.iter('r')).strip()

        if stem in index:
            continue   # Stem gefunden → OK

        # Fallback suchen
        best = None
        best_cat = None
        candidates = [
            re.sub(r'\d+$', '', stem),               # ohne Zahl am Ende
            re.sub(r'sw$', '', stem),                # ohne SW-Suffix
            stem.replace('_', ''),                   # ohne Unterstriche
            re.sub(r'\d+$', '', stem).replace('_', ''),
        ]
        for c in candidates:
            if not c or c == stem:
                continue
            if c in index:
                # bevorzuge gleiche Kategorie
                if index[c][0].lower().replace('_', '') == cat.replace('_', ''):
                    best = c
                    best_cat = index[c][0]
                    break
        if not best:
            for c in candidates:
                if c and c in index:
                    best = c
                    best_cat = index[c][0]
                    break

        issues.append((gdir[:36], texts[:50], stem, cat, best, best_cat))

# ── Report ausgeben ───────────────────────────────────────────────────────────
print(f"=== FEHLENDE STEMS ({len(issues)} Vorkommen) ===\n")
seen_stems = {}   # stem -> best
for gdir, text, stem, cat, best, bcat in issues:
    if stem not in seen_stems:
        seen_stems[stem] = best
    ok = f"→  {best}" if best else "→  !! KEIN TREFFER !!"
    print(f"  [{gdir:36}]  '{text[:40]:40}'  stem={stem:30}  {ok}")

print(f"\n=== UNIQUE STEMS ({len(seen_stems)}) ===\n")
no_fix = []
for stem, best in sorted(seen_stems.items()):
    if best:
        print(f"  {stem:35}  →  {best}")
    else:
        no_fix.append(stem)
        print(f"  {stem:35}  →  !! KEIN AUTO-FIX !!")

print(f"\n=== DART ALIASES EINFÜGEN ({sum(1 for v in seen_stems.values() if v)}) ===\n")
for stem, best in sorted(seen_stems.items()):
    if best:
        print(f'    "{stem}": "{best}",')

if no_fix:
    print(f"\n=== OHNE AUTO-FIX ({len(no_fix)}) — manuell prüfen ===")
    for s in no_fix:
        print(f"  {s}")
