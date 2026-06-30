#!/usr/bin/env bash
# scripts/spec-audit-append.sh — Schreib-Mechanismus für das Reconcile-Logbuch docs/spec-audit.md
#
# Spec: docs/specs/reconcile.md AC10, AC11. Vertrag: docs/architecture/reconcile-subsystem.md §4.
# Aufrufer: /agent-flow:reconcile-Skill (Stufe 1 + Stufe 2 — einziger Schreiber, AC1/AC9).
#
# Pro Lauf EIN Block: Kopf = Datum (`## YYYY-MM-DD`, UTC), darunter je eine Markdown-Bullet-Zeile
# pro berührtem Dokument. Neuester Block steht oben (append-prepend) — direkt unter dem
# statischen Datei-Kopf (Titel + Blockquote aus templates/_docs/spec-audit.md), vor allen
# bisherigen Blöcken. Ohne übergebene Zeilen wird NICHTS geschrieben — kein leerer Block,
# kein Rauschen (AC11/A2/E2).
#
# Usage:
#   scripts/spec-audit-append.sh "<Zeile 1>" ["<Zeile 2>" ...]
#   printf '%s\n' "<Zeile 1>" "<Zeile 2>" | scripts/spec-audit-append.sh -   (Zeilen aus stdin)
#
# Beispiel:
#   scripts/spec-audit-append.sh \
#     "Spec reconcile.md auf use-case-2.0 konvertiert" \
#     "Konzept docs/architecture.md nachgezogen"
#
# Env:
#   SPEC_AUDIT_FILE — Zielpfad (Default: docs/spec-audit.md, relativ zu cwd = Projekt-Root;
#                     analog BOARD_DIR-Konvention in scripts/board).
#
# Idempotenz: existiert die Zieldatei nicht, wird sie aus templates/_docs/spec-audit.md
# angelegt (Fallback: minimaler eingebetteter Kopf, falls die Vorlage nicht erreichbar ist —
# Graceful Degradation analog db-subsystem §14 Amendment).
#
# Requires: bash >= 4.0, python3.
# Exit 0 bei leerer Eingabe (kein Schreiben — gewollt, AC11). Exit ≠ 0 nur bei echtem
# Schreibfehler (Zielverzeichnis nicht beschreibbar o.ä.).

set -euo pipefail

SPEC_AUDIT_FILE="${SPEC_AUDIT_FILE:-docs/spec-audit.md}"

# ─── Zeilen einsammeln ──────────────────────────────────────────────────────
# coder/L26: ein CLI-/stdin-Argument kann interne \n enthalten (z.B. mehrzeiliger
# Freitext). Würde das unverändert in den Block eingebettet, könnte eine darin
# enthaltene Zeile zufällig wie eine Block-Grenze (`## <Datum>`) aussehen und
# beim NÄCHSTEN Lauf als gefälschter Datums-Block fehlinterpretiert werden.
# Fix: interne Newlines (sowie \r) nach dem Trim durch ein Leerzeichen ersetzen,
# damit aus einem Argument IMMER genau eine Logbuch-Zeile wird.
LINES=()
if [[ "${1:-}" == "-" ]]; then
  while IFS= read -r raw_line; do
    trimmed="$(printf '%s' "$raw_line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    sanitized="$(printf '%s' "$trimmed" | tr '\n\r' '  ' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/[[:space:]][[:space:]]*/ /g')"
    [[ -n "$sanitized" ]] && LINES+=("$sanitized")
  done
else
  for raw_line in "$@"; do
    trimmed="$(printf '%s' "$raw_line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    sanitized="$(printf '%s' "$trimmed" | tr '\n\r' '  ' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/[[:space:]][[:space:]]*/ /g')"
    [[ -n "$sanitized" ]] && LINES+=("$sanitized")
  done
fi

if [[ "${#LINES[@]}" -eq 0 ]]; then
  echo "[spec-audit-append] kein berührtes Dokument übergeben — kein Block geschrieben (AC11)" >&2
  exit 0
fi

# ─── Zielverzeichnis + Idempotenz (Datei anlegen falls fehlend) ────────────
TARGET_DIR="$(dirname "$SPEC_AUDIT_FILE")"
mkdir -p "$TARGET_DIR"

if [[ ! -f "$SPEC_AUDIT_FILE" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
  TEMPLATE="${SCRIPT_DIR}/../templates/_docs/spec-audit.md"
  CREATE_TMP="$(mktemp "${TARGET_DIR}/.spec-audit-create.XXXXXX")"
  if [[ -f "$TEMPLATE" ]]; then
    cp "$TEMPLATE" "$CREATE_TMP"
  else
    printf '%s\n\n' "# Spec-Audit-Log" > "$CREATE_TMP"
    echo "[spec-audit-append] WARN: Vorlage templates/_docs/spec-audit.md nicht gefunden — minimaler Kopf verwendet" >&2
  fi
  mv "$CREATE_TMP" "$SPEC_AUDIT_FILE"
fi

# ─── Block bauen (Kopf = Datum, je eine Zeile pro Dokument) ────────────────
DATE_STR="$(date -u +%Y-%m-%d)"
BLOCK_TMP="$(mktemp "${TARGET_DIR}/.spec-audit-block.XXXXXX")"
{
  printf '## %s\n' "$DATE_STR"
  for line in "${LINES[@]}"; do
    printf -- '- %s\n' "$line"
  done
} > "$BLOCK_TMP"

# ─── Block oben einfügen (append-prepend), bisherige Blöcke unverändert ───
WORK_TMP="$(mktemp "${TARGET_DIR}/.spec-audit-append.XXXXXX")"
trap 'rm -f "$BLOCK_TMP" "$WORK_TMP"' EXIT

python3 - "$SPEC_AUDIT_FILE" "$BLOCK_TMP" "$WORK_TMP" <<'PYEOF'
import sys

target_path, block_path, out_path = sys.argv[1], sys.argv[2], sys.argv[3]

with open(block_path, "r", encoding="utf-8") as f:
    block = f.read()

with open(target_path, "r", encoding="utf-8") as f:
    content = f.read()

lines = content.splitlines(keepends=True)
insert_idx = None
for i, line in enumerate(lines):
    if line.startswith("## "):
        insert_idx = i
        break

if insert_idx is None:
    # Kein bisheriger Block — Block ans Ende des (statischen) Kopfs anhängen.
    if content and not content.endswith("\n"):
        content += "\n"
    if content and not content.endswith("\n\n"):
        content += "\n"
    new_content = content + block
else:
    # Neuester Block kommt vor den ersten bisherigen Block (neueste oben).
    new_content = "".join(lines[:insert_idx]) + block + "\n" + "".join(lines[insert_idx:])

with open(out_path, "w", encoding="utf-8") as f:
    f.write(new_content)
PYEOF

mv "$WORK_TMP" "$SPEC_AUDIT_FILE"
# trap räumt BLOCK_TMP (und ggf. das schon verschobene WORK_TMP, dann no-op) beim Exit auf.

echo "[spec-audit-append] OK: ${SPEC_AUDIT_FILE} — Block ${DATE_STR} mit ${#LINES[@]} Zeile(n) oben eingefügt" >&2
