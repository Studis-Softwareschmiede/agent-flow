#!/usr/bin/env bash
# scripts/reconcile-stage2-gate.sh — Kanban-Vorbedingungs-Check (hart) fuer Reconcile Stufe 2
#
# Spec: docs/specs/reconcile.md AC6. Vertrag: docs/architecture/reconcile-subsystem.md §3 (Stufe 2)
#       + Verträge ("Kanban-Abfrage (Stufe-2-Gate)").
# Aufrufer: skills/reconcile/SKILL.md (Stufe 2, VOR jedem Audit-Dispatch).
#
# Prueft per `scripts/board list`, ob die vier aktiven Spalten (To Do, In Progress, Blocked,
# In Review) ALLE leer sind. Reine Lese-/Report-Operation — KEIN Schreiben, KEIN hartes
# Fehler-Exit bei fehlendem Board (Review-Lehre S-011: `scripts/board` bricht bei FEHLENDEM
# Board-Skelett fuer manche Verben hart ab — coder/L15 verlangt fuer LESENDE Pruefungen
# graceful Handling statt Absturz; dieses Script faengt den `board list`-Fehlerfall fuer den
# Fall "Board nicht initialisiert" ab und meldet ihn als eigenes Ergebnis statt zu crashen).
#
# Ausgabe (stdout), GENAU EIN Token:
#   empty      — alle vier Spalten leer        -> Vorbedingung erfuellt, Stufe 2 darf laufen
#   not-empty  — mind. eine Spalte belegt       -> Stufe 2 wird uebersprungen (AC6/A1)
#   no-board   — Board-Skelett fehlt (board.yaml nicht vorhanden) -> Vorbedingung nicht
#                pruefbar; Stufe 2 wird konservativ uebersprungen (NFR „Vorsicht" —
#                kein impliziter Inhalts-Abgleich, wenn nicht einmal feststeht, ob etwas offen ist)
#
# stderr: je eine Zeile pro Spalte mit Item-Anzahl (informativ) bzw. die Board-Fehlermeldung
# im no-board-Fall. NICHT maschinenlesbar — nur stdout-Token ist der Vertrag.
#
# Env:
#   BOARD_SCRIPT — Pfad zu scripts/board (Default: gleiches Verzeichnis wie dieses Script)
#   BOARD_DIR    — an scripts/board durchgereicht (Default dort: "board"); v.a. fuer Tests.
#
# Exit 0 IMMER fuer die drei oben genannten Ergebnisse (reine Lese-/Report-Operation —
# fehlendes Board ist ein erwarteter Fall, kein Script-Abbruch, analog coder/L15).
# Exit 2 NUR bei echtem Aufrufproblem (board-Skript nicht gefunden, oder `board list`
# schlaegt mit einem ANDEREN Fehler als „Board nicht initialisiert" fehl).
#
# Requires: bash >= 4.0, python3 (transitiv ueber scripts/board).

set -uo pipefail
# bewusst KEIN -e: ein non-zero Exit von `scripts/board list` (z.B. fehlendes Board) ist ein
# erwarteter, abzufangender Fall — kein Script-Abbruch (siehe Kopf-Kommentar).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
BOARD_SCRIPT="${BOARD_SCRIPT:-${SCRIPT_DIR}/board}"

if [[ ! -f "$BOARD_SCRIPT" ]]; then
  echo "FEHLER: board-Skript '${BOARD_SCRIPT}' nicht gefunden" >&2
  exit 2
fi

ERR_TMP="$(mktemp /tmp/reconcile-stage2-gate-err.XXXXXX)"
trap 'rm -f "$ERR_TMP"' EXIT

COLUMNS=("To Do" "In Progress" "Blocked" "In Review")
TOTAL=0
BOARD_MISSING=0

for col in "${COLUMNS[@]}"; do
  out="$(bash "$BOARD_SCRIPT" list --type story --status "$col" 2>"$ERR_TMP")"
  rc=$?
  err="$(cat "$ERR_TMP" 2>/dev/null || true)"
  : > "$ERR_TMP"

  if [[ $rc -ne 0 ]]; then
    if printf '%s' "$err" | grep -q "Board nicht initialisiert"; then
      BOARD_MISSING=1
      echo "Spalte '${col}': Board nicht initialisiert — ${err}" >&2
      break
    fi
    echo "FEHLER: 'board list --status ${col}' schlug unerwartet fehl: ${err}" >&2
    exit 2
  fi

  count="$(printf '%s' "$out" | python3 -c 'import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    data = []
print(len(data) if isinstance(data, list) else 0)' 2>/dev/null || echo 0)"
  echo "Spalte '${col}': ${count} Item(s)" >&2
  TOTAL=$(( TOTAL + count ))
done

if [[ "$BOARD_MISSING" -eq 1 ]]; then
  echo "no-board"
  exit 0
fi

if [[ "$TOTAL" -eq 0 ]]; then
  echo "empty"
else
  echo "not-empty"
fi
exit 0
