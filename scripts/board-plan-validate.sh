#!/usr/bin/env bash
# scripts/board-plan-validate.sh <session-plan.yaml> <wave-number>
#
# Mechanische Revalidierung einer Welle des Wellen-Plans (Spec
# docs/specs/parallel-session-plan.md AC6/AC7, §0c von skills/flow/SKILL.md)
# -- rein deterministisches Bash/Python, KEIN LLM-Lauf. Wird von der aeusseren
# Schleife (dev-gui Nachtwaechter/ProjectDrain) VOR jedem Wellen-Start
# aufgerufen, um den zu Plan-Zeit erstellten Wellen-Plan gegen den
# tatsaechlichen Board-Ist-Stand zu pruefen (der Plan kann inzwischen
# veraltet sein -- Board von Hand geaendert, eine Story wurde parallel
# geblockt, usw.).
#
# Regeln je Story der angegebenen Welle:
#   - Story-ID aus dem Plan referenziert KEINE existierende Story mehr
#     (`board show` liefert "nicht gefunden") -> grob invalider Plan,
#     HARTER ABBRUCH (Exit 2) mit Klartext-Diagnose (Edge-Case "Plan
#     veraltet", Spec-Abschnitt "Edge-Cases & Fehlerverhalten").
#   - Story-Status NICHT MEHR "To Do" (Done/Verworfen = erfuellt; jeder
#     andere Nicht-To-Do-Status wurde bereits anderweitig behandelt, z.B.
#     In Progress aus einer unterbrochenen Session) -> aus der Welle
#     entfernt (REMOVED <id> (<status>)).
#   - Story-Status "To Do", aber mindestens ein `depends`-Eintrag ist NICHT
#     terminal (Menge {Done, Verworfen}) -> Story dieser Welle uebersprungen,
#     WAITING <story>: wartet auf <dep> (<status>) gemeldet (deckt A1 --
#     eine waehrend einer Welle geblockte Story stoppt nur ihren
#     Abhaengigkeits-Ast, nicht die ganze Abarbeitung).
#   - Sonst -> READY (tatsaechlich zu startende Session dieser Welle).
#
# Nutzt `board show <id>` als einzige Quelle der Wahrheit (SSOT, keine
# eigene YAML-Parser-Kopie der Story-Felder -- coder/L-Lesson S-063/S-064).
#
# Ausgabe (stdout, Klartext, stabile Zeilen-Praefixe):
#   READY: S-101 S-103
#   WAITING S-104: wartet auf S-101 (In Progress)
#   REMOVED S-105 (Done)
#
# Exit 0 = Welle mechanisch verarbeitet (auch wenn 0 Stories in READY landen
#          -- eine leere Welle ist kein Fehler, nur eine leere Ausbeute).
# Exit 1 = Aufruf-/Eingabefehler (fehlende Argumente, Plan-Datei fehlt,
#          Wellen-Nummer nicht im Plan).
# Exit 2 = grob invalider Plan (referenzierte Story existiert nicht mehr) --
#          die aeussere Schleife bricht den Drain ab statt still
#          weiterzulaufen.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOARD_SCRIPT="${SCRIPT_DIR}/board"

die() {
  echo "FEHLER [board-plan-validate]: $*" >&2
  exit 1
}
die_invalid_plan() {
  echo "FEHLER [board-plan-validate]: grob invalider Plan -- $*" >&2
  exit 2
}

PLAN_FILE="${1:-}"
WAVE_NUM="${2:-}"
[[ -n "$PLAN_FILE" && -n "$WAVE_NUM" ]] || die "Verwendung: board-plan-validate.sh <session-plan.yaml> <wave-nummer>"
[[ -f "$PLAN_FILE" ]] || die "Plan-Datei nicht gefunden: ${PLAN_FILE}"
[[ "$WAVE_NUM" =~ ^[0-9]+$ ]] || die "Wellen-Nummer muss numerisch sein, war '${WAVE_NUM}'"
[[ -x "$BOARD_SCRIPT" ]] || die "board-CLI nicht ausfuehrbar: ${BOARD_SCRIPT}"

# Terminale Status (board-Konvention, s. skills/flow/SKILL.md "Terminale Status")
TERMINAL_STATUSES="Done Verworfen"
is_terminal() {
  local status="$1"
  [[ " $TERMINAL_STATUSES " == *" ${status} "* ]]
}

# Story-IDs der angegebenen Welle aus dem Plan extrahieren (Python/PyYAML --
# gleiche Bibliothek wie scripts/board selbst, keine neue Abhaengigkeit).
STORY_IDS_RAW="$(python3 - "$PLAN_FILE" "$WAVE_NUM" <<'PYEOF'
import sys, yaml
plan_file, wave_num = sys.argv[1], int(sys.argv[2])
with open(plan_file) as f:
    plan = yaml.safe_load(f) or {}
waves = plan.get("waves") or []
match = [w for w in waves if int(w.get("wave", -1)) == wave_num]
if not match:
    sys.exit(3)
stories = match[0].get("stories") or []
print("\n".join(str(s) for s in stories))
PYEOF
)" || {
  rc=$?
  if [[ "$rc" -eq 3 ]]; then
    die "Welle ${WAVE_NUM} ist im Plan ${PLAN_FILE} nicht vorhanden"
  fi
  die "Plan-Datei ${PLAN_FILE} konnte nicht gelesen werden (kaputtes YAML?)"
}

if [[ -z "$STORY_IDS_RAW" ]]; then
  # Leere stories-Liste in dieser Welle -- kein Fehler, nur nichts zu tun.
  echo "READY:"
  exit 0
fi

READY_IDS=()
WAITING_LINES=()
REMOVED_LINES=()

while IFS= read -r story_id; do
  [[ -n "$story_id" ]] || continue

  SHOW_OUT=""
  if ! SHOW_OUT="$("$BOARD_SCRIPT" show "$story_id" 2>/dev/null)"; then
    die_invalid_plan "Story '${story_id}' aus Welle ${WAVE_NUM} existiert nicht mehr (board show liefert 'nicht gefunden')"
  fi

  STATUS="$(printf '%s' "$SHOW_OUT" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("status") or "")')"

  if [[ "$STATUS" != "To Do" ]]; then
    REMOVED_LINES+=("REMOVED ${story_id} (${STATUS})")
    continue
  fi

  # depends terminal? erster nicht-terminaler dep entscheidet die WAITING-Meldung.
  BLOCKING_DEP=""
  BLOCKING_DEP_STATUS=""
  DEPS_RAW="$(printf '%s' "$SHOW_OUT" | python3 -c '
import json, sys
data = json.load(sys.stdin)
deps = data.get("depends") or []
if not isinstance(deps, list):
    deps = [deps]
print("\n".join(str(d) for d in deps if str(d).strip()))
')"
  if [[ -n "$DEPS_RAW" ]]; then
    while IFS= read -r dep_id; do
      [[ -n "$dep_id" ]] || continue
      DEP_SHOW_OUT=""
      if ! DEP_SHOW_OUT="$("$BOARD_SCRIPT" show "$dep_id" 2>/dev/null)"; then
        BLOCKING_DEP="$dep_id"
        BLOCKING_DEP_STATUS="not-found"
        break
      fi
      DEP_STATUS="$(printf '%s' "$DEP_SHOW_OUT" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("status") or "")')"
      if ! is_terminal "$DEP_STATUS"; then
        BLOCKING_DEP="$dep_id"
        BLOCKING_DEP_STATUS="$DEP_STATUS"
        break
      fi
    done <<< "$DEPS_RAW"
  fi

  if [[ -n "$BLOCKING_DEP" ]]; then
    WAITING_LINES+=("WAITING ${story_id}: wartet auf ${BLOCKING_DEP} (${BLOCKING_DEP_STATUS})")
  else
    READY_IDS+=("$story_id")
  fi
done <<< "$STORY_IDS_RAW"

for line in "${REMOVED_LINES[@]+"${REMOVED_LINES[@]}"}"; do
  echo "$line"
done
for line in "${WAITING_LINES[@]+"${WAITING_LINES[@]}"}"; do
  echo "$line"
done
if [[ "${#READY_IDS[@]}" -gt 0 ]]; then
  echo "READY: ${READY_IDS[*]}"
else
  echo "READY:"
fi

exit 0
