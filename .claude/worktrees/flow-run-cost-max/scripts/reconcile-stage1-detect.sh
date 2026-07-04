#!/usr/bin/env bash
# scripts/reconcile-stage1-detect.sh — Stufe-1-Erkennung (Form) für /agent-flow:reconcile
#
# Spec: docs/specs/reconcile.md AC3. Vertrag: docs/architecture/reconcile-subsystem.md §3.
# Aufrufer: skills/reconcile/SKILL.md (Stufe 1, Erkennungsschritt — VOR der Konvertierung).
#
# Vergleicht den `spec_format`-Frontmatter-Stempel jeder Spec unter `docs/specs/*.md` gegen
# den Stempel der aktuellen Vorlage (`templates/_docs/specs/_template.md`). Listet jede Spec,
# deren Stempel FEHLT oder vom Vorlagen-Wert ABWEICHT (älter, andere Form) — AC3.
# Reine Erkennung, KEINE Konvertierung (übernimmt der Skill-Schritt danach, AC4) und KEIN
# Schreiben (idempotent, seiteneffektfrei — kann beliebig oft/parallel gelesen werden).
#
# Usage:
#   scripts/reconcile-stage1-detect.sh
#   SPECS_DIR=<dir> TEMPLATE_PATH=<pfad> scripts/reconcile-stage1-detect.sh   (Overrides, v.a. für Tests)
#
# Ausgabe (stdout), eine Zeile pro Spec, die Stufe 1 umstellen muss, TAB-getrennt:
#   <relativer-Pfad><TAB><missing|outdated><TAB><aktueller-Wert-oder-(none)><TAB><ziel-Wert>
# Specs, deren Stempel bereits dem Vorlagen-Wert entspricht, erscheinen NICHT in der Ausgabe.
# Kein Treffer -> leere Ausgabe, Exit 0 (kein Rauschen, analog AC11/E2-Prinzip).
#
# stderr: der aufgelöste Vorlagen-Zielwert als eine Zeile "TEMPLATE_SPEC_FORMAT=<wert>" —
# informativ für den aufrufenden Skill-Schritt, NICHT Teil des maschinenlesbaren stdout.
#
# Env:
#   SPECS_DIR      — Verzeichnis mit den zu prüfenden Specs (Default: docs/specs, relativ zu cwd)
#   TEMPLATE_PATH  — Pfad zur aktuellen Vorlage (Default: templates/_docs/specs/_template.md)
#
# Exit 0 — auch wenn Drift gefunden wird (Erkennung ist kein Gate, nur ein Report).
# Exit 2 NUR wenn die Vorlage selbst nicht lesbar ist oder keinen `spec_format`-Stempel
# trägt (echte Fehlkonfiguration — ohne Vergleichsbasis kann Stufe 1 nicht sicher urteilen).
# Exit 0 bei fehlendem SPECS_DIR (nichts zu prüfen, kein Fehler).
#
# Requires: bash >= 4.0, python3.

set -euo pipefail

SPECS_DIR="${SPECS_DIR:-docs/specs}"
TEMPLATE_PATH="${TEMPLATE_PATH:-templates/_docs/specs/_template.md}"

python3 - "$SPECS_DIR" "$TEMPLATE_PATH" <<'PYEOF'
import re
import sys
import os
import glob

specs_dir, template_path = sys.argv[1], sys.argv[2]

FRONTMATTER_BLOCK = re.compile(r"^---\s*\n(.*?)\n---\s*\n", re.DOTALL)
SPEC_FORMAT_FIELD = re.compile(r"^spec_format:\s*(.*)$", re.MULTILINE)


def read_spec_format(path):
    """Liest den spec_format-Frontmatter-Wert einer Datei.

    Gibt None zurueck, wenn die Datei fehlt, kein Frontmatter-Block am Dateianfang
    steht oder der Schluessel im Block fehlt. Trennt einen trailing YAML-Inline-
    Kommentar ab (coder/L25), bevor der Wert verglichen wird — sonst False-Positive
    bei Werten wie "use-case-2.0   # aktuelle Standard-Version dieser Vorlage".
    """
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            content = f.read()
    except OSError:
        return None
    fm_match = FRONTMATTER_BLOCK.match(content)
    if not fm_match:
        return None
    field_match = SPEC_FORMAT_FIELD.search(fm_match.group(1))
    if not field_match:
        return None
    raw_val = field_match.group(1).split("#", 1)[0].strip()
    return raw_val or None


template_val = read_spec_format(template_path)
if not template_val:
    print(
        f"FEHLER: Vorlage {template_path!r} nicht lesbar oder ohne spec_format-Stempel "
        f"— keine Vergleichsbasis fuer Stufe 1.",
        file=sys.stderr,
    )
    sys.exit(2)

print(f"TEMPLATE_SPEC_FORMAT={template_val}", file=sys.stderr)

if not os.path.isdir(specs_dir):
    sys.exit(0)

for path in sorted(glob.glob(os.path.join(specs_dir, "*.md"))):
    current_val = read_spec_format(path)
    if current_val is None:
        print(f"{path}\tmissing\t(none)\t{template_val}")
    elif current_val != template_val:
        print(f"{path}\toutdated\t{current_val}\t{template_val}")
    # current_val == template_val -> bereits aktuell, keine Ausgabe.
PYEOF
