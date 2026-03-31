#!/usr/bin/env python3
"""
bake_overrides.py
─────────────────────────────────────────────────────────────────────────────
Liest nasira_grid_overrides.json und schreibt Layout- und Größen-Änderungen
direkt in die Grid3-XML-Dateien zurück ("bake in").

Was wird eingebaut:
  ✓  layout   — X/Y/ColumnSpan/RowSpan der Zellen
  ✓  gridSize — Anzahl der Spalten/Zeilen (ColumnDefinition/RowDefinition)
  ✗  cells    — Caption/Symbol-Änderungen (zu tief verschachtelt; Report + manuell)
  ✗  wordList — Wortlisten (sinnvollerweise immer Runtime-Override)

Ablauf:
  1. Backup der XML-Dateien anlegen
  2. XML patchen
  3. layout + gridSize aus der JSON entfernen (cells/wordList bleiben erhalten)
  4. Report ausgeben

Verwendung:
  python bake_overrides.py [--dry-run]   (--dry-run: nur Report, kein Schreiben)
"""

import json
import xml.etree.ElementTree as ET
import os
import sys
import copy
import shutil
from pathlib import Path
from datetime import datetime

# ── Konfiguration ──────────────────────────────────────────────────────────────

OVERRIDES_FILE = Path(r'C:\Users\denlu\Documents\nasira_grid_overrides.json')
GRIDS_PATH     = Path(r'C:\Users\denlu\Documents\Nasira EXPORT\Grids')
BACKUP_ROOT    = Path(r'C:\Users\denlu\Documents\nasira_xml_backups')

# ── Hilfsfunktionen ────────────────────────────────────────────────────────────

def load_overrides():
    if not OVERRIDES_FILE.exists():
        print(f'[ERROR] Overrides-Datei nicht gefunden: {OVERRIDES_FILE}')
        sys.exit(1)
    with open(OVERRIDES_FILE, encoding='utf-8') as f:
        return json.load(f)


def save_overrides(data):
    with open(OVERRIDES_FILE, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=2)


def load_xml(xml_path):
    """Parst eine XML-Datei und gibt (tree, root, original_declaration) zurück."""
    raw = xml_path.read_text(encoding='utf-8', errors='replace')
    # Deklaration extrahieren (für spätere Wiederherstellung)
    decl = ''
    if raw.startswith('<?xml'):
        decl = raw[:raw.index('?>') + 2]
    tree = ET.parse(xml_path)
    return tree, tree.getroot(), decl


def write_xml(xml_path, tree, original_decl):
    """Schreibt den Tree zurück. ElementTree-Formatierung ist für Grid3 ausreichend."""
    ET.indent(tree, space='  ')  # Python 3.9+
    buf = ET.tostring(tree.getroot(), encoding='unicode')
    content = (original_decl + '\n' + buf) if original_decl else buf
    xml_path.write_text(content, encoding='utf-8')


def copy_definition_template(defs_el, tag):
    """Kopiert das letzte vorhandene Element als Vorlage für neue Definitionen."""
    existing = defs_el.findall(tag)
    if existing:
        return copy.deepcopy(existing[-1])
    return ET.Element(tag)


# ── Patch-Funktionen ───────────────────────────────────────────────────────────

def patch_grid_size(root, grid_size, report):
    """Passt ColumnDefinitions und RowDefinitions an."""
    changed = False

    new_cols = grid_size.get('columns')
    new_rows = grid_size.get('rows')

    col_defs = root.find('ColumnDefinitions')
    if col_defs is not None and new_cols is not None:
        current = col_defs.findall('ColumnDefinition')
        n = len(current)
        if n != new_cols:
            report.append(f'  Spalten: {n} → {new_cols}')
            while len(col_defs.findall('ColumnDefinition')) < new_cols:
                col_defs.append(copy_definition_template(col_defs, 'ColumnDefinition'))
            while len(col_defs.findall('ColumnDefinition')) > new_cols:
                last = col_defs.findall('ColumnDefinition')[-1]
                col_defs.remove(last)
            changed = True

    row_defs = root.find('RowDefinitions')
    if row_defs is not None and new_rows is not None:
        current = row_defs.findall('RowDefinition')
        n = len(current)
        if n != new_rows:
            report.append(f'  Zeilen: {n} → {new_rows}')
            while len(row_defs.findall('RowDefinition')) < new_rows:
                row_defs.append(copy_definition_template(row_defs, 'RowDefinition'))
            while len(row_defs.findall('RowDefinition')) > new_rows:
                last = row_defs.findall('RowDefinition')[-1]
                row_defs.remove(last)
            changed = True

    return changed


def patch_layout(root, layout_overrides, report):
    """Verschiebt/verändert Zellen gemäß Layout-Overrides."""
    changed = False
    cells_el = root.find('Cells')
    if cells_el is None:
        report.append('  [WARN] Kein <Cells>-Element gefunden')
        return False

    for raw_key, new_pos in layout_overrides.items():
        raw_x, raw_y = map(int, raw_key.split(','))
        new_x  = new_pos['x']
        new_y  = new_pos['y']
        new_cs = new_pos.get('colSpan', 1)
        new_rs = new_pos.get('rowSpan', 1)

        found = False
        for cell_el in cells_el.findall('Cell'):
            cx = int(cell_el.get('X', 0))
            cy = int(cell_el.get('Y', 0))
            if cx == raw_x and cy == raw_y:
                old_cs = int(cell_el.get('ColumnSpan', 1))
                old_rs = int(cell_el.get('RowSpan', 1))
                cell_el.set('X',          str(new_x))
                cell_el.set('Y',          str(new_y))
                cell_el.set('ColumnSpan', str(new_cs))
                cell_el.set('RowSpan',    str(new_rs))
                pos_str = (
                    f'({raw_x},{raw_y}) → ({new_x},{new_y})'
                    + (f'  cs {old_cs}→{new_cs}' if old_cs != new_cs else '')
                    + (f'  rs {old_rs}→{new_rs}' if old_rs != new_rs else '')
                )
                report.append(f'  Zelle {pos_str}')
                changed = True
                found = True
                break

        if not found:
            report.append(f'  [WARN] Zelle ({raw_x},{raw_y}) nicht in XML gefunden — übersprungen')

    return changed


# ── Hauptprogramm ──────────────────────────────────────────────────────────────

def main():
    dry_run = '--dry-run' in sys.argv
    if dry_run:
        print('=== DRY-RUN (keine Dateien werden verändert) ===\n')

    overrides = load_overrides()
    if not overrides:
        print('Keine Overrides vorhanden. Fertig.')
        return

    timestamp    = datetime.now().strftime('%Y%m%d_%H%M%S')
    backup_dir   = BACKUP_ROOT / timestamp
    new_overrides = {}
    applied_count = 0

    # Report-Puffer
    manual_report = []  # content/wordList-Overrides die manuell einzupflegen sind

    for page_name, page_data in overrides.items():
        has_layout   = bool(page_data.get('layout'))
        has_size     = bool(page_data.get('gridSize'))
        has_cells    = bool(page_data.get('cells'))
        has_wordlist = bool(page_data.get('wordList'))

        print(f'\n── {page_name} ──')

        if has_cells:
            manual_report.append((page_name, 'cells', page_data['cells']))
            print(f'  ⚠  {len(page_data["cells"])} Caption/Symbol-Override(s) → manuell (siehe Report)')

        if has_wordlist:
            print(f'  ℹ  wordList-Override bleibt erhalten (Runtime-Schicht)')

        if not has_layout and not has_size:
            print('  ─  Kein Layout/Größen-Override → nichts zu tun')
            # Behalte cells/wordList im JSON, entferne layout/gridSize (ohnehin nicht vorhanden)
            remaining = {k: v for k, v in page_data.items() if k not in ('layout', 'gridSize')}
            if remaining:
                new_overrides[page_name] = remaining
            continue

        xml_path = GRIDS_PATH / page_name / 'grid.xml'
        if not xml_path.exists():
            print(f'  [ERROR] XML nicht gefunden: {xml_path}')
            new_overrides[page_name] = page_data  # alles behalten
            continue

        report_lines = []

        if dry_run:
            # Nur simulieren — XML lesen aber nicht schreiben
            tree, root, decl = load_xml(xml_path)
            if has_size:
                patch_grid_size(root, page_data['gridSize'], report_lines)
            if has_layout:
                patch_layout(root, page_data['layout'], report_lines)
            for line in report_lines:
                print(line)
            print('  → (dry-run: nicht gespeichert)')
            continue

        # Backup anlegen
        backup_page = backup_dir / page_name
        backup_page.mkdir(parents=True, exist_ok=True)
        shutil.copy2(xml_path, backup_page / 'grid.xml')

        # XML laden, patchen, speichern
        tree, root, decl = load_xml(xml_path)
        changed = False
        if has_size:
            changed |= patch_grid_size(root, page_data['gridSize'], report_lines)
        if has_layout:
            changed |= patch_layout(root, page_data['layout'], report_lines)

        for line in report_lines:
            print(line)

        if changed:
            write_xml(xml_path, tree, decl)
            print(f'  ✓ XML gespeichert (Backup: {backup_page})')
            applied_count += 1
        else:
            print('  ─ Keine Änderungen notwendig')

        # Layout/gridSize aus JSON entfernen; cells/wordList behalten
        remaining = {k: v for k, v in page_data.items() if k not in ('layout', 'gridSize')}
        if remaining:
            new_overrides[page_name] = remaining

    # Overrides-JSON aktualisieren
    if not dry_run:
        save_overrides(new_overrides)
        print(f'\n✓ nasira_grid_overrides.json aktualisiert ({applied_count} Seite(n) eingebaut)')
        if backup_dir.exists():
            print(f'  Backups: {backup_dir}')

    # ── Manueller Report ──────────────────────────────────────────────────────
    if manual_report:
        print('\n' + '='*60)
        print('MANUELL EINZUPFLEGENDE ÄNDERUNGEN (Caption / Symbol):')
        print('='*60)
        for page, kind, data in manual_report:
            print(f'\nSeite: {page}')
            for cell_key, cell_data in data.items():
                x, y = cell_key.split(',')
                print(f'  Zelle ({x},{y}):')
                for field, value in cell_data.items():
                    print(f'    {field}: {value!r}')
        print('\n→ Diese Werte müssen in den entsprechenden grid.xml-Dateien')
        print('  unter <CaptionAndImage><Caption> bzw. <Image> eingetragen werden.')
        print('  Am einfachsten: Report an Claude übergeben → direkt patchen lassen.')

    if not manual_report and applied_count == 0 and not dry_run:
        print('\n✓ Alles eingebaut, keine manuellen Schritte nötig.')


if __name__ == '__main__':
    main()
