#!/usr/bin/env bash
# scripts/obsidian-fragenkatalog-validate.sh — Fragenkatalog-Gate-Validator (Obsidian-Ingest)
#
# Spec: docs/specs/obsidian-ingest.md AC7/AC9 (+ AC8-Auto-Durchlauf).
# Vertrag/Schema: board/fragenkatalog.schema.json; Verortung: docs/architecture/obsidian-ingest-subsystem.md §6.
# Aufrufer (spaeter): die noch nicht existierende Drei-Stufen-Pipeline (S-023) — VOR dem Vorlegen
#   eines Katalogs an den User (dev-gui / AskUserQuestion) und VOR dem Stufen-Commit. Dieser Baustein
#   ist eigenstaendig + wiederverwendbar (Format-Kontrakt + Gate-Invarianten), OHNE Pipeline-Orchestrierung.
#
# Zweck: prueft, ob ein Fragenkatalog (JSON-Liste von Frage-Objekten, gelesen von stdin ODER aus einer
#   Datei per $1) dem bindenden AC9-Vertrag entspricht. Reine Lese-/Report-Operation — schreibt nichts.
#
# Vertrag (AC9, bindende Feldmenge je Frage-Objekt):
#   - stage    (Pflicht) : "a" | "b" | "c" | "sync" | "split" | "design"
#   - id       (Pflicht) : stabile, KATALOG-EINDEUTIGE Frage-ID (Muster <stage>-<n>, z.B. "a-1")
#   - frage    (Pflicht) : nicht-leerer Text
#   - quelle   (Pflicht) : nicht-leere Notiz-/Doku-Fundstelle (Herkunfts-Marker, AC4)
#   - optionen (optional): Liste nicht-leerer Strings, ODER weggelassen/null
#   Keine unbekannten Felder (additionalProperties:false im Schema).
#
# AC8-Regel: ein LEERER Katalog ([]) ist GUELTIG (Stufe klar/widerspruchsfrei -> Auto-Durchlauf).
#   Ein leerer Katalog darf laut AC8 NICHT dem User vorgelegt werden; das Vorlegen entscheidet der
#   Aufrufer anhand des stdout-Tokens (siehe unten), nicht dieser Validator.
#
# Ausgabe (stdout), GENAU EIN Token:
#   empty  — gueltiger LEERER Katalog ([])          -> Auto-Durchlauf (AC8), NICHT vorlegen
#   valid  — gueltiger NICHT-leerer Katalog (>=1)    -> dem User vorlegen (AC7), dann committen
#   (im Fehlerfall wird KEIN Token, sondern Exit 1 + Diagnose auf stderr ausgegeben)
#
# stderr: je Verletzung eine Diagnose-Zeile (nicht maschinenlesbar — nur stdout-Token ist der Vertrag).
#
# Env:
#   SCHEMA_PATH — Pfad zu board/fragenkatalog.schema.json (Default: relativ zu diesem Script).
#                 Nur informativ referenziert; die Validierung selbst ist self-contained (keine
#                 externe jsonschema-Abhaengigkeit — nur python3-stdlib), damit der Baustein ohne
#                 Zusatz-Dependency laeuft (Vertrags-Feldmenge ist unten 1:1 nachgebildet).
#
# Exit:
#   0 — Katalog gueltig (Token "empty" oder "valid" auf stdout)
#   1 — Katalog ungueltig (Vertragsverletzung; Diagnosen auf stderr)
#   2 — Aufrufproblem (Eingabe nicht lesbar / kein valides JSON / kein python3)
#
# Requires: python3 (stdlib), bash.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck disable=SC2034  # SCHEMA_PATH ist Doku-/Kontext-Referenz auf den bindenden Vertrag.
SCHEMA_PATH="${SCHEMA_PATH:-${SCRIPT_DIR}/../board/fragenkatalog.schema.json}"

if ! command -v python3 >/dev/null 2>&1; then
  echo "FEHLER: python3 nicht gefunden — Fragenkatalog-Validierung nicht moeglich." >&2
  exit 2
fi

# Eingabe: aus Datei ($1) oder stdin. Der Python-Teil liest per Heredoc von stdin,
# darum wird der Katalog VOR dem python3-Aufruf in eine Temp-Datei materialisiert
# (sonst kollidiert die Katalog-Eingabe mit dem Heredoc-Skript auf stdin).
INPUT_SRC="${1:--}"
INPUT_TMP="$(mktemp /tmp/obsidian-fragenkatalog-input.XXXXXX)"
trap 'rm -f "$INPUT_TMP"' EXIT

if [[ "$INPUT_SRC" == "-" ]]; then
  cat > "$INPUT_TMP"
else
  if [[ ! -r "$INPUT_SRC" ]]; then
    echo "FEHLER: Eingabe nicht lesbar (${INPUT_SRC})." >&2
    exit 2
  fi
  cat "$INPUT_SRC" > "$INPUT_TMP"
fi

python3 - "$INPUT_TMP" <<'PYEOF'
import json
import re
import sys

src = sys.argv[1]

# --- Eingabe lesen ---
try:
    with open(src, "r", encoding="utf-8") as fh:
        raw = fh.read()
except OSError as exc:
    print(f"FEHLER: Eingabe nicht lesbar ({src}): {exc}", file=sys.stderr)
    sys.exit(2)

try:
    catalog = json.loads(raw)
except json.JSONDecodeError as exc:
    print(f"FEHLER: kein valides JSON: {exc}", file=sys.stderr)
    sys.exit(2)

# --- Struktur: Top-Level MUSS eine Liste sein (AC9-Vertrag: "eine Liste von Frage-Objekten") ---
if not isinstance(catalog, list):
    print("FEHLER: Fragenkatalog muss eine JSON-Liste sein (AC9-Vertrag).", file=sys.stderr)
    sys.exit(1)

# --- AC8: leerer Katalog ist gueltig -> Auto-Durchlauf, NICHT vorlegen ---
if len(catalog) == 0:
    print("empty")
    sys.exit(0)

VALID_STAGES = {"a", "b", "c", "sync", "split", "design"}
REQUIRED = ("stage", "id", "frage", "quelle")
ALLOWED = set(REQUIRED) | {"optionen"}
ID_PATTERN = re.compile(r"^[a-z]+-[0-9]+$")

errors = []
seen_ids = {}  # id -> erster Index (Duplikat-Erkennung, AC9 "katalog-eindeutig")

for idx, item in enumerate(catalog):
    where = f"Eintrag #{idx}"
    if not isinstance(item, dict):
        errors.append(f"{where}: Frage-Objekt muss ein Objekt sein, ist {type(item).__name__}.")
        continue

    # Pflichtfelder vorhanden?
    for field in REQUIRED:
        if field not in item:
            errors.append(f"{where}: Pflichtfeld '{field}' fehlt (AC9).")

    # keine unbekannten Felder (additionalProperties:false)
    for key in item:
        if key not in ALLOWED:
            errors.append(f"{where}: unbekanntes Feld '{key}' (nur {sorted(ALLOWED)} erlaubt).")

    # stage-Enum
    stage = item.get("stage")
    if "stage" in item and stage not in VALID_STAGES:
        errors.append(f"{where}: stage='{stage}' ungueltig (erlaubt: a|b|c|sync|split|design).")

    # id: nicht-leerer String, Muster, katalog-eindeutig
    qid = item.get("id")
    if "id" in item:
        if not isinstance(qid, str) or not qid:
            errors.append(f"{where}: id muss ein nicht-leerer String sein.")
        elif not ID_PATTERN.match(qid):
            errors.append(f"{where}: id='{qid}' verletzt Muster <stage>-<n> (z.B. 'a-1').")
        else:
            if qid in seen_ids:
                errors.append(
                    f"{where}: id='{qid}' ist nicht katalog-eindeutig "
                    f"(bereits in Eintrag #{seen_ids[qid]}) — verletzt AC9."
                )
            else:
                seen_ids[qid] = idx

    # frage: nicht-leerer String
    frage = item.get("frage")
    if "frage" in item and (not isinstance(frage, str) or not frage.strip()):
        errors.append(f"{where}: frage muss ein nicht-leerer Text sein.")

    # quelle: nicht-leerer String (Herkunfts-Marker)
    quelle = item.get("quelle")
    if "quelle" in item and (not isinstance(quelle, str) or not quelle.strip()):
        errors.append(f"{where}: quelle muss eine nicht-leere Notiz-/Doku-Fundstelle sein (AC4).")

    # optionen: optional; wenn vorhanden -> Liste nicht-leerer Strings ODER null
    if "optionen" in item and item["optionen"] is not None:
        opts = item["optionen"]
        if not isinstance(opts, list):
            errors.append(f"{where}: optionen muss eine Liste sein (oder weggelassen/null).")
        else:
            for o_idx, opt in enumerate(opts):
                if not isinstance(opt, str) or not opt.strip():
                    errors.append(f"{where}: optionen[{o_idx}] muss ein nicht-leerer String sein.")

if errors:
    for e in errors:
        print(e, file=sys.stderr)
    print(f"FEHLER: Fragenkatalog verletzt den AC9-Vertrag ({len(errors)} Problem(e)).", file=sys.stderr)
    sys.exit(1)

print("valid")
sys.exit(0)
PYEOF
