#!/usr/bin/env bash
# scripts/board-feature-drain.sh <F-###> [<container-name>]
#
# Feature-Schicht der 3-Ebenen-Orchestrierung (Owner-Konzept 2026-07-06):
#   Board-Ebene (außen, z.B. dev-guis Nachtwächter/dieses Skripts Aufrufer)
#   → Feature-Ebene (DIESES Skript, deterministisch, kein LLM)
#   → Story-Ebene (`claude -p /agent-flow:flow --parent <F-###>`, frischer
#     Kontext je Story — unverändert das bestehende Session-Rotation-Prinzip,
#     nur auf ein einzelnes Feature verengt).
#
# Zweck: Storys eines Features werden nacheinander gebaut und LANDEN JEWEILS
# NUR im Feature-Branch (kein main-Merge, kein Rollout pro Story) — erst wenn
# ALLE Storys terminal sind (Done oder bewusst Verworfen), EIN einziger Merge
# Feature-Branch → main + EIN Rollout (statt N Merges/N Rollouts). Löst genau
# das "10 Storys, 10× Deploy"-Problem, das der Owner am 2026-07-06 ansprach.
#
# Voraussetzung: ≥ 2 Storys unter diesem Feature — sonst kein Bündelungs-
# vorteil, das Skript verweigert sich und verweist auf den normalen /flow-Lauf.
#
# Blockade-Verhalten (Owner-Entscheidung 2026-07-06): Bleibt eine Story
# Blocked, wartet das GANZE Feature — kein Timeout, kein Teil-Deploy der
# bereits fertigen Storys. Das Skript beendet sich dann mit Exit 3 und einer
# klaren Diagnose statt endlos zu pollen — ein äußerer Aufrufer (Board-Ebene)
# entscheidet, wann er es erneut versucht (z.B. nachdem der Owner die
# Blockade gelöst hat).
#
# Exit 0 = Feature komplett gelandet (oder war schon fertig — idempotent).
# Exit 1 = Fehler (siehe Meldung).
# Exit 3 = Feature wartet auf mindestens eine blockierte/nicht-terminale Story.

set -euo pipefail

FEATURE_ID="${1:-}"
APP_NAME="${2:-}"
[[ -n "$FEATURE_ID" ]] || { echo "FEHLER [board-feature-drain]: Verwendung: board-feature-drain.sh <F-###> [<container-name>]" >&2; exit 1; }
[[ "$FEATURE_ID" =~ ^F-[0-9]{3,}$ ]] || { echo "FEHLER [board-feature-drain]: <F-###> im Format F-### erwartet, war '$FEATURE_ID'" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

BOARD_SCRIPT="${SCRIPT_DIR}/board"
SHIP_SCRIPT="${SCRIPT_DIR}/board-ship.sh"
FEATURE_BRANCH="feature/${FEATURE_ID}"

log() { echo "[board-feature-drain] $*"; }
die() { echo "FEHLER [board-feature-drain]: $*" >&2; exit 1; }

DEFAULT_BRANCH="$(grep -m1 '^default_branch:' .claude/profile.md 2>/dev/null | sed 's/default_branch: *//;s/"//g')"
DEFAULT_BRANCH="${DEFAULT_BRANCH:-main}"

story_status() {
  # story_status <S-###> — liest den aktuellen Status direkt aus der YAML
  # (kein 'board show', um ohne zusätzliche CLI-Abhängigkeit auszukommen).
  python3 - "$1" <<'PYEOF'
import sys, glob, yaml
sid = sys.argv[1]
for path in glob.glob("board/stories/*.yaml"):
    try:
        with open(path) as f:
            data = yaml.safe_load(f) or {}
    except Exception:
        continue
    if str(data.get("id", "")).strip() == sid:
        print(str(data.get("status", "")).strip())
        break
PYEOF
}

remaining_nonterminal() {
  # Kommagetrennte Liste "<id>:<status>" aller nicht-terminalen Storys dieses
  # Features (leer = alle Done/Verworfen, Feature fertig).
  python3 - "$FEATURE_ID" <<'PYEOF'
import sys, glob, yaml
fid = sys.argv[1]
out = []
for path in glob.glob("board/stories/*.yaml"):
    try:
        with open(path) as f:
            data = yaml.safe_load(f) or {}
    except Exception:
        continue
    if str(data.get("parent", "")).strip() != fid:
        continue
    status = str(data.get("status", "")).strip()
    if status not in ("Done", "Verworfen"):
        out.append(f"{data.get('id')}:{status}")
print(",".join(out))
PYEOF
}

# --- Kandidaten-Check: mindestens 2 Storys unter diesem Feature? ---
STORY_COUNT="$(python3 - "$FEATURE_ID" <<'PYEOF'
import sys, glob, yaml
fid = sys.argv[1]
count = 0
for path in glob.glob("board/stories/*.yaml"):
    try:
        with open(path) as f:
            data = yaml.safe_load(f) or {}
    except Exception:
        continue
    if str(data.get("parent", "")).strip() == fid:
        count += 1
print(count)
PYEOF
)"
[[ "$STORY_COUNT" -ge 2 ]] || die "Feature ${FEATURE_ID} hat nur ${STORY_COUNT} Story(s) — Bündelung bringt hier keinen Vorteil, Storys einzeln per /flow abarbeiten."

log "Feature ${FEATURE_ID}: ${STORY_COUNT} Storys — Batch-Modus aktiv (Feature-Branch ${FEATURE_BRANCH})."

# --- Feature-Branch sicherstellen (von origin/default_branch abzweigen, falls neu) ---
git fetch origin "$DEFAULT_BRANCH" --quiet
if ! git rev-parse "origin/${FEATURE_BRANCH}" >/dev/null 2>&1; then
  git push origin "origin/${DEFAULT_BRANCH}:refs/heads/${FEATURE_BRANCH}" --quiet
  log "Feature-Branch ${FEATURE_BRANCH} neu angelegt (von origin/${DEFAULT_BRANCH})."
fi

# --- Hauptschleife: eine frische Story-Sitzung nach der anderen ---
for round in $(seq 1 50); do
  NEXT_JSON="$("$BOARD_SCRIPT" next --parent "$FEATURE_ID" 2>/dev/null || true)"

  if [[ -z "$NEXT_JSON" ]]; then
    REMAINING="$(remaining_nonterminal)"
    if [[ -z "$REMAINING" ]]; then
      log "Alle Storys von ${FEATURE_ID} terminal (Done/Verworfen) — Feature komplett, finaler Merge folgt."
      break
    fi
    log "Feature ${FEATURE_ID} wartet — keine Story bereit, aber nicht alle terminal: ${REMAINING}"
    echo "BLOCKIERT: ${REMAINING}"
    exit 3
  fi

  STORY_ID="$(echo "$NEXT_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')"
  STATUS_BEFORE="$(story_status "$STORY_ID")"
  log "Runde ${round}: nächste Story ${STORY_ID} (Status davor: ${STATUS_BEFORE})"

  # Frische Story-Sitzung (Story-Ebene, eigener Kontext) — /flow im Feature-Scope.
  "${BOARD_FEATURE_DRAIN_CLAUDE_CMD:-claude}" -p "/agent-flow:flow --parent ${FEATURE_ID}" --dangerously-skip-permissions || true

  git fetch origin "$FEATURE_BRANCH" --quiet 2>/dev/null || true
  STATUS_AFTER="$(story_status "$STORY_ID")"

  # L7-Prinzip: Fortschritt verifizieren statt Ausführung zu vertrauen. Bleibt
  # dieselbe Story trotz eines vollen /flow-Laufs unverändert "To Do", ist das
  # verdächtig (Endlos-Risiko) — abbrechen statt bis Runde 50 blind weiterzulaufen.
  if [[ "$STATUS_BEFORE" == "To Do" && "$STATUS_AFTER" == "To Do" ]]; then
    die "Runde ${round}: ${STORY_ID} blieb trotz /flow-Lauf auf 'To Do' — Verdacht auf Zwischenfall (kein Fortschritt). Manuell prüfen (git log, Worktrees, uncommittete Dateien), nicht automatisch weiterlaufen."
  fi
done

# --- Finaler Merge: Feature-Branch → main, EINMAL CI-Watch + Rollout ---
if [[ -n "$APP_NAME" ]]; then
  "$SHIP_SCRIPT" --merge-feature "$FEATURE_BRANCH" "$APP_NAME"
else
  "$SHIP_SCRIPT" --merge-feature "$FEATURE_BRANCH"
fi

log "Feature ${FEATURE_ID} vollständig gelandet + deployt."
exit 0
