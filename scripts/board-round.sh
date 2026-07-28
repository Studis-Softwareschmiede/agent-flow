#!/usr/bin/env bash
# scripts/board-round.sh [--cost <mode>]
#
# Deterministischer Runden-Zustandsautomat für die board-weite
# Standard-Einzelrunde (Spec docs/specs/flow-deterministic-runner.md
# AC1/AC2/AC5/AC7/AC8/AC9/AC10/AC11, Detailkonzept
# docs/architecture/flow-deterministic-runner.md — BINDEND für Zustände/
# Übergänge/Fehlerpfade/Invarianten, §2/§3/§4/§5/§8/§9).
#
# Zustandsautomat (Architektur §2, Klartext-Diagramm dort ist die Quelle):
#   SETUP -> SELECT -> CLAIM -> DESIGN_GATE ->
#   BUILD-LOOP(CODE -> REVIEW -> [DB_REVIEW] -> TEST -> ITERATE) ->
#   LAND -> [RECOVER] -> FINALIZE -> [BLOCK ->] EXIT
#
# Dieses Skript hält KEINEN LLM-Kontext — es ist reines Bash. Es dispatcht
# coder/reviewer/dba/tester als je eigene, headless `claude -p`-Subsessions
# mit Minimal-Kontrakt (§3) und wertet deren Klartext-Handoff MECHANISCH aus
# (parse-gate.sh). Ein leichtes LLM-Urteil (Judge, §5.1) wird NUR bei
# mehrdeutigem Gate-Text gerufen — nie zum Raten, s. AC7/K1.
#
# Wiederverwendete Bausteine (kein Neubau, §8 Skript-Schnitt):
#   scripts/board-claim.sh          — CLAIM-Sequenz (S-125, Phase A)
#   scripts/board-round-finalize.sh — FINALIZE-Mechanik (S-126, Phase A)
#   scripts/parse-gate.sh           — Gate-Token-Parser (S-127, Phase A)
#   scripts/board-ship.sh           — Landen (unverändert, K1)
#   scripts/board (next/ready/set/show) — Item-Wahl, Diagnose, Status
#   scripts/board-id-reserve.sh     — ID-Block-Freigabe (via board-round-finalize.sh)
#   scripts/metrics-append-dispatch.sh — Ledger-Touchpoints je Dispatch
#
# Scope (Owner-Entscheid Q6a, HART): NUR die board-weite Standard-
# Einzelrunde. `--all`/`--parent`/`--plan`/SR1-Parallel/interaktive Design-
# Freigabe sind AUSSERHALB des Scopes — bereits im SETUP-Vorab-Filter
# erkannt und an den LLM-Orchestrator abgegeben (Exit 10 + Klartext).
#
# Test-Seams (analog board-feature-drain.sh / board-ship.sh — Produktions-
# Default bleibt unverändert, wenn die Variable fehlt):
#   BOARD_ROUND_CLAUDE_CMD    — Ersatz-Binary für `claude` (Fixture-Tests)
#   BOARD_ROUND_SKIP_GH_AUTH  — "1" überspringt ensure-gh-auth.sh
#   BOARD_ROUND_SHIP_CMD      — Ersatz-Skript für board-ship.sh (nur für den
#                               Flip-Fixer-Fixture-Test, §4.1 — Default ruft
#                               das echte, unveränderte board-ship.sh, K1)
#   BOARD_ROUND_PID_FILE      — schreibt `$$` dorthin, sobald der Runner
#                               startet (nur für den echten SIGTERM-Fixture-
#                               Test, Critical-1-Fix Iteration 2 — ermittelt
#                               die echte Runner-PID ohne Subshell-/Exec-
#                               Rätselraten)
#
# Invarianten (Architektur §2, Fixture-Test-Pflicht):
#   I1 — aus jedem Zustand ist ein Blocked-/Abbruch-Ausgang erreichbar.
#   I2 — Board-Status wird NUR in CLAIM/BLOCK/LAND(-RECOVER) geschrieben.
#   I3 — kein coder-Dispatch vor bestätigtem Claim-Push.
#   I4 — EXIT-Trap schreibt bei unerwartetem Abbruch einen Runner-Zustand,
#        setzt aber NIE aggressiv den Claim zurück (Stale-Reclamation-Netz
#        aus story-claim-lock übernimmt das beim nächsten Lauf, §4.2).
#        SIGTERM/SIGINT werden zusätzlich EXPLIZIT getrappt und beenden den
#        aktiven Agent-Dispatch-Prozessbaum aktiv, BEVOR der Worktree
#        entfernt wird (Critical-1-Fix, Review-Iteration 2 — sonst überlebt
#        der `claude`-Kindprozess jeden Kill als Waise).
#
# Iteration-2-Review-Fixes (Critical 1-3 + Important 1-2, s. PR-Historie):
#   - ROUND_STATE_FILE ist ABSOLUT (REPO_ROOT-verankert), nie relativ —
#     sonst schreibt ein späterer `cd` in eine andere Datei als der Trap
#     erwartet, und der Worktree-Teardown vernichtet sie sofort wieder.
#   - Kein Cherry-Pick mehr für Board-Meta-Commits (verlor bei echter
#     Nebenläufigkeit ganze Commits, da `.claude/memory.md` IMMER komplett
#     neugeschrieben wird und daher garantiert kollidiert) — stattdessen ein
#     deterministischer Re-Apply-Retry (push_meta_with_retry), der bei
#     Push-Ablehnung frisch fetcht/resettet und denselben Schreibvorgang
#     erneut anwendet (kein Merge, kein Konfliktrisiko, kein Datenverlust).
#   - CODE→REVIEW prüft jetzt den Pflicht-Marker `Review-Handoff: REVIEW
#     REQUIRED` (Allow-Listing) statt nur auf SPEC-LÜCKE/leer zu prüfen
#     (Deny-Listing) — jeder andere/verstümmelte coder-Output eskaliert.
#   - DIAGNOSE (leeres Board) und Claim-Budget-erschöpft laufen jetzt auch
#     durch eine (reduzierte) FINALIZE-Kuration (Memory, kein Item ohne
#     Story), statt direkt zu enden.
#   - block_round() ruft board-round-finalize.sh jetzt mit blocked=1 auf —
#     auch Blocked-Runden landen im Metrik-Ledger.
#
# Exit-Codes:
#   0  = Runde sauber beendet (Done, Blocked, leeres Board, Claim-Budget
#        erschöpft — jeweils per Log-Ausgabe unterscheidbar)
#   10 = ausserhalb Runner-Scope (--all/--parent/--plan) — an den
#        LLM-Orchestrator abgegeben, KEIN Dispatch erfolgt
#   1  = harter Usage-/Infrastruktur-Fehler (Klartext auf stderr)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

BOARD_SCRIPT="${SCRIPT_DIR}/board"
CLAIM_SCRIPT="${SCRIPT_DIR}/board-claim.sh"
FINALIZE_SCRIPT="${SCRIPT_DIR}/board-round-finalize.sh"
PARSE_GATE_SCRIPT="${SCRIPT_DIR}/parse-gate.sh"
SHIP_SCRIPT="${BOARD_ROUND_SHIP_CMD:-${SCRIPT_DIR}/board-ship.sh}"
METRICS_DISPATCH_SCRIPT="${SCRIPT_DIR}/metrics-append-dispatch.sh"

CLAUDE_CMD="${BOARD_ROUND_CLAUDE_CMD:-claude}"

log() { echo "[board-round] $*"; }
die() { echo "FEHLER [board-round]: $*" >&2; exit 1; }

# --- L6-Guard (analog board-ship.sh/board-claim.sh) ---
guard_repo_root_clean() {
  local dirty
  dirty="$(git -C "$REPO_ROOT" status --porcelain)"
  if [[ -n "$dirty" ]]; then
    die "REPO_ROOT (${REPO_ROOT}) hat uncommittete Änderungen — STOPP vor jedem Board-Meta-Schreibvorgang.
${dirty}"
  fi
}

# ============================================================================
# I4 — EXIT-Trap: bei unerwartetem Abbruch (Exit != 0) den Runner-Zustand in
# eine gitignored State-Datei schreiben, NIE aggressiv den Claim zurücksetzen
# (Stale-Reclamation-Netz aus story-claim-lock übernimmt das, §4.2).
# ============================================================================
STORY_ID=""
CUR_STATE="SETUP"
ROUND_STATE_FILE=""
STORY_WORKTREE=""
CURRENT_DISPATCH_PID=""
SIGNAL_RECEIVED=""

write_round_state() {
  [[ -n "$ROUND_STATE_FILE" ]] || return 0
  mkdir -p "$(dirname "$ROUND_STATE_FILE")" 2>/dev/null || return 0
  {
    echo "story_id: ${STORY_ID}"
    echo "state: ${CUR_STATE}"
    echo "updated_at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } > "$ROUND_STATE_FILE" 2>/dev/null || true
}

teardown_story_worktree() {
  [[ -n "$STORY_WORKTREE" ]] || return 0
  git worktree remove --force "$STORY_WORKTREE" >/dev/null 2>&1 || rm -rf "$STORY_WORKTREE" 2>/dev/null || true
  git worktree prune >/dev/null 2>&1 || true
  STORY_WORKTREE=""
}

release_round_state() {
  [[ -n "$ROUND_STATE_FILE" ]] || return 0
  rm -f "$ROUND_STATE_FILE" 2>/dev/null || true
}

# kill_process_tree <pid> <signal> — beendet <pid> UND alle Nachfahren
# (bottom-up, rekursiv über pgrep -P) — robuster als ein einzelnes
# `pkill -P`, das nur DIREKTE Kinder erreicht, falls die Dispatch-Subshell
# NICHT in den `claude`-Prozess exec-optimiert wurde (Bash garantiert das
# nicht) und daher ein Enkel-Prozess (z.B. eine `sleep`/Warteschleife
# innerhalb des Agenten) sonst als Waise überlebt (Critical-1-Fix).
kill_process_tree() {
  local pid="$1" sig="${2:-TERM}"
  local children c
  children="$(pgrep -P "$pid" 2>/dev/null || true)"
  for c in $children; do
    kill_process_tree "$c" "$sig"
  done
  kill -"$sig" "$pid" 2>/dev/null || true
}

on_exit_trap() {
  local ec=$?
  if [[ "$ec" -ne 0 && "$ec" -ne 10 ]]; then
    write_round_state
    log "Runner unerwartet beendet (Exit ${ec}) im Zustand '${CUR_STATE}' — Claim NICHT zurückgesetzt (Stale-Reclamation-Netz greift beim nächsten Lauf, Architektur §4.2). State-Datei: ${ROUND_STATE_FILE:-<keine>}"
  fi
  teardown_story_worktree
}
trap on_exit_trap EXIT

# SIGTERM/SIGINT — Critical-1-Fix (Review-Iteration 2/3): der reine EXIT-Trap
# reagiert NICHT auf ein Signal, das den Runner selbst beendet, ohne dass
# der aktive `claude`-Kindprozess (CODE/REVIEW/DB_REVIEW/TEST-Dispatch)
# jemals ein Signal erhält — er überlebt sonst JEDEN Kill der Runner-PID als
# dauerhafte Waise. Der Signal-Trap beendet AKTIV den getrackten
# Dispatch-Prozessbaum, BEVOR er den Runner-Prozess selbst per `exit`
# beendet (was wiederum den bestehenden EXIT-Trap auslöst — State-Datei-
# Schreiben + Worktree-Teardown bleiben dort zentral, kein Doppel-Code).
#
# SIGNAL_RECEIVED-Flag (Review-Iteration 3, HÄRTUNG): unter Last live
# beobachtet, dass NACH dem Töten des Dispatch-Kindprozesses das durch das
# Signal unterbrochene `wait "$CURRENT_DISPATCH_PID"` in dispatch_agent()
# zurückkehren und den REST von build_loop weiterlaufen lassen kann,
# BEVOR das `exit 143` dieses Traps tatsächlich greift (Bash dokumentiert
# Trap-Dispatch nicht als strikt atomar gegenüber einem gerade zurück-
# kehrenden `wait`) — dispatch_agent() sähe dann einen LEEREN
# DISPATCH_OUT (der Kindprozess wurde ja gerade erst getötet, bevor er
# etwas ausgeben konnte) und build_loop interpretierte das fälschlich als
# "coder-Dispatch lieferte keinen Handoff" -> block_round() lief TEILWEISE
# an (Zustand fälschlich "BLOCK" statt des echten Unterbrechungs-Zustands).
# Das Flag ist ein zweiter, expliziter Prüfpunkt (s. dispatch_agent): sobald
# der Trap gefeuert hat, MUSS jeder Fortsetzungspfad sofort selbst beenden,
# statt sich auf das Trap-eigene `exit` allein zu verlassen.
on_signal_trap() {
  local sig="$1"
  SIGNAL_RECEIVED="$sig"
  log "Signal ${sig} empfangen — beende aktiven Agent-Dispatch-Prozessbaum (PID ${CURRENT_DISPATCH_PID:-<keiner>}) BEVOR der Story-Worktree entfernt wird; Runner-Zustand wird über den EXIT-Trap geschrieben, Claim bleibt unangetastet (I4)."
  if [[ -n "$CURRENT_DISPATCH_PID" ]]; then
    kill_process_tree "$CURRENT_DISPATCH_PID" TERM
  fi
  exit 143
}
trap 'on_signal_trap TERM' TERM
trap 'on_signal_trap INT' INT

# Test-Seam (nur gesetzt im echten SIGTERM-Fixture-Test): Runner-PID sofort
# nach Trap-Registrierung an einen bekannten Ort schreiben, damit der Test
# die ECHTE PID kennt, ohne Subshell-/Exec-Optimierungs-Annahmen treffen zu
# müssen.
if [[ -n "${BOARD_ROUND_PID_FILE:-}" ]]; then
  echo "$$" > "$BOARD_ROUND_PID_FILE" 2>/dev/null || true
fi

# ============================================================================
# SETUP — Vorab-Filter (Q6a, HART): --all/--parent/--plan sind ausserhalb
# des Runner-Scopes -> Abgabe an den LLM-Orchestrator, kein Dispatch.
# ============================================================================
COST_MODE_ARG=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --cost) shift; COST_MODE_ARG="${1:-}" ;;
    --all|--parent|--plan)
      log "ausserhalb Runner-Scope, bitte /agent-flow:flow direkt nutzen (Flag: $1)"
      exit 10
      ;;
    *) die "unbekanntes Argument '$1'" ;;
  esac
  shift
done

normalize_cost_mode() {
  case "$1" in
    low|low-cost) echo "low-cost" ;;
    max|high|max-quality) echo "max-quality" ;;
    mid|std|balanced) echo "balanced" ;;
    front|frontier) echo "frontier" ;;
    *) echo "" ;;
  esac
}

guard_repo_root_clean

METRICS_ROOT="$REPO_ROOT"
export METRICS_ROOT
if [[ ! -f "${METRICS_ROOT}/board/board.yaml" ]]; then
  log "⚠ METRICS_ROOT (${METRICS_ROOT}) enthält kein board/board.yaml — Metrik-Erfassung diese Session übersprungen."
fi

DEFAULT_BRANCH="$(grep -m1 '^default_branch:' .claude/profile.md 2>/dev/null | sed 's/default_branch: *//;s/"//g' || true)"
DEFAULT_BRANCH="${DEFAULT_BRANCH:-main}"

LANG_VAL="$(grep -m1 '^language:' .claude/profile.md 2>/dev/null | sed 's/language: *//;s/"//g' || true)"
LANG_VAL="${LANG_VAL:-md}"

PROFILE_COST_MODE="$(grep -m1 '^cost_mode:' .claude/profile.md 2>/dev/null | sed 's/cost_mode: *//;s/"//g' || true)"
if [[ -n "$COST_MODE_ARG" ]]; then
  COST_MODE="$(normalize_cost_mode "$COST_MODE_ARG")"
elif [[ -n "$PROFILE_COST_MODE" ]]; then
  COST_MODE="$(normalize_cost_mode "$PROFILE_COST_MODE")"
else
  COST_MODE=""
fi
if [[ -z "$COST_MODE" ]]; then
  [[ -n "${COST_MODE_ARG}${PROFILE_COST_MODE}" ]] && log "unbekannter Cost-Mode-Wert — Fallback 'balanced' (nie 'frontier' geraten)."
  COST_MODE="balanced"
fi
log "Cost-Mode: ${COST_MODE}"

if [[ "${BOARD_ROUND_SKIP_GH_AUTH:-0}" != "1" ]]; then
  AUTH_SCRIPT="${SCRIPT_DIR}/ensure-gh-auth.sh"
  [[ -x "$AUTH_SCRIPT" ]] && "$AUTH_SCRIPT" >/dev/null 2>&1 || true
fi

# ============================================================================
# Modell-Auflösung (S0.3, Detailkonzept §1.1) — Matrix
# ${AGENT_FLOW_KNOWLEDGE_DIR:-plugin}/knowledge/model-tiers.md, Spalte = Modus.
# balanced -> KEIN Override (Agent-Frontmatter gilt). Judge (§5.1, Q2a) läuft
# immer auf der günstigsten Stufe, unabhängig vom Cost-Mode.
# ============================================================================
resolve_model() {
  local role="$1"
  local mode="${2:-$COST_MODE}"
  [[ "$mode" == "balanced" ]] && { echo ""; return 0; }
  local pack="${AGENT_FLOW_KNOWLEDGE_DIR:-${SCRIPT_DIR}/../knowledge}/model-tiers.md"
  [[ -f "$pack" ]] || { echo ""; return 0; }
  local fidx
  case "$mode" in
    low-cost) fidx=3 ;;
    max-quality) fidx=5 ;;
    frontier) fidx=6 ;;
    *) echo ""; return 0 ;;
  esac
  local row field
  row="$(grep -E "^\| ${role}[[:space:]]" "$pack" | head -1)"
  [[ -n "$row" ]] || { echo ""; return 0; }
  field="$(printf '%s' "$row" | awk -F'|' -v i="$fidx" '{gsub(/^[ \t]+|[ \t]+$/,"",$i); print $i}')"
  field="$(printf '%s' "$field" | sed -E 's/\*//g')"
  printf '%s' "$field"
}

# ============================================================================
# Metrik-Touchpoints (S2.4, SKILL.md §2b) — deterministische Arithmetik, kein
# LLM-Aufruf. Ein Metrik-Fehler blockiert nie die Runde (K3).
# ============================================================================
SEQ=0
T0=0
metric_before() { T0=$(date -u +%s); SEQ=$(( SEQ + 1 )); }
metric_after() {
  local agent="$1" gate="$2" crit="${3:-0}" imp="${4:-0}"
  local secs=$(( $(date -u +%s) - T0 ))
  METRICS_ROOT="$METRICS_ROOT" METRIC_CRIT="$crit" METRIC_IMP="$imp" METRIC_RULE_HITS='[]' \
    "$METRICS_DISPATCH_SCRIPT" "$STORY_ID" "$agent" "$SEQ" "$ITER" "$gate" "$secs" "$COST_MODE" >&2 || true
}

# ============================================================================
# SELECT + CLAIM (§1/§2, story-claim-lock via board-claim.sh — kein Neubau,
# AC4). I3: kein coder-Dispatch vor bestätigtem Claim-Push.
# ============================================================================
STORY_BRANCH=""
SPEC_PATH=""
IMPLEMENTS_JSON="[]"
LABELS_JSON="[]"
BASE_SHA=""
SIZE_EST="M"
EP_EST="null"
TOK_EST="null"

parse_next_json() {
  local json="$1"
  STORY_ID="$(printf '%s' "$json" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("id") or "")')"
  SPEC_PATH="$(printf '%s' "$json" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("spec") or "")')"
  IMPLEMENTS_JSON="$(printf '%s' "$json" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(json.dumps(d.get("implements") or []))')"
  LABELS_JSON="$(printf '%s' "$json" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(json.dumps(d.get("labels") or []))')"
}

print_empty_diagnosis() {
  local ready_out waiting_lines
  ready_out="$("$BOARD_SCRIPT" ready --quiet 2>/dev/null || true)"
  waiting_lines="$(printf '%s\n' "$ready_out" | grep '^WAITING ' || true)"
  if [[ -n "$waiting_lines" ]]; then
    log "nichts abarbeitbar — Gründe:"
    printf '%s\n' "$waiting_lines" | while IFS= read -r l; do log "$l"; done
  else
    log "Board leer — keine abarbeitbaren Items."
  fi
}

select_and_claim_loop() {
  cd "$REPO_ROOT"
  local attempt=0
  while true; do
    attempt=$(( attempt + 1 ))
    if [[ "$attempt" -gt 20 ]]; then
      log "Zu viele Claim-/Select-Retry-Runden (>20) — Abbruch (I1-Sicherheitsnetz gegen stillen Hang)."
      exit 0
    fi

    CUR_STATE="SELECT"
    STORY_ID=""; ROUND_STATE_FILE=""
    git fetch origin "$DEFAULT_BRANCH" --quiet || die "git fetch von origin/${DEFAULT_BRANCH} fehlgeschlagen."

    local next_json
    next_json="$("$BOARD_SCRIPT" next 2>/dev/null || true)"
    if [[ -z "$next_json" ]]; then
      print_empty_diagnosis
      finalize_empty_or_no_claim "Board leer / nichts abarbeitbar"
      exit 0
    fi

    parse_next_json "$next_json"
    [[ "$STORY_ID" =~ ^S-[0-9]{3,}$ ]] || die "board next lieferte ein nicht klassifizierbares Item-JSON (id='${STORY_ID}')."
    [[ -n "$SPEC_PATH" ]] || die "board next lieferte kein 'spec'-Feld für ${STORY_ID} — kein Dispatch ohne Spec-Referenz."

    # ABSOLUT (Critical-1-Fix) -- ein späteres `cd` (STORY_WORKTREE, Ship-
    # Aufrufe) darf NICHT dazu führen, dass write_round_state() plötzlich in
    # eine andere Datei schreibt als der Trap erwartet.
    ROUND_STATE_FILE="${REPO_ROOT}/board/runs/round-${STORY_ID}.state"
    CUR_STATE="CLAIM"
    write_round_state

    set +e
    "$CLAIM_SCRIPT" "$STORY_ID"
    local claim_rc=$?
    set -e

    case "$claim_rc" in
      0) break ;;
      2) release_round_state; continue ;;
      3)
        log "Claim-Retry-Budget für ${STORY_ID} erschöpft — Story bleibt 'To Do'."
        release_round_state
        finalize_empty_or_no_claim "Claim-Budget für ${STORY_ID} erschöpft"
        exit 0
        ;;
      *) die "board-claim.sh lieferte einen unerwarteten Exit-Code ${claim_rc} für ${STORY_ID}." ;;
    esac
  done

  local show_json
  show_json="$("$BOARD_SCRIPT" show "$STORY_ID" 2>/dev/null)"
  STORY_BRANCH="$(printf '%s' "$show_json" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("branch") or "")')"
  [[ -n "$STORY_BRANCH" ]] || die "Story-Branch für ${STORY_ID} nach Claim nicht ermittelbar."
  SIZE_EST="$(printf '%s' "$show_json" | python3 -c 'import json,sys; d=json.load(sys.stdin); v=d.get("size_est"); print(v if v else "M")')"
  EP_EST="$(printf '%s' "$show_json" | python3 -c 'import json,sys; d=json.load(sys.stdin); v=d.get("dispo_est"); print(v if v is not None else "null")')"
  TOK_EST="$(printf '%s' "$show_json" | python3 -c 'import json,sys; d=json.load(sys.stdin); v=d.get("tok_est"); print(v if v is not None else "null")')"

  STORY_WORKTREE="${REPO_ROOT}/.claude/worktrees/${STORY_ID}"
  if [[ -d "$STORY_WORKTREE" ]]; then
    git worktree remove --force "$STORY_WORKTREE" >/dev/null 2>&1 || rm -rf "$STORY_WORKTREE"
    git worktree prune >/dev/null 2>&1 || true
  fi
  mkdir -p "$(dirname "$STORY_WORKTREE")"
  git fetch origin "$DEFAULT_BRANCH" --quiet
  git worktree add -B "$STORY_BRANCH" "$STORY_WORKTREE" "origin/${DEFAULT_BRANCH}" --quiet \
    || die "Story-Worktree für ${STORY_ID} (${STORY_BRANCH}) konnte nicht angelegt werden."
  BASE_SHA="$(git -C "$STORY_WORKTREE" rev-parse HEAD)"
}

# ============================================================================
# DESIGN_GATE (§2c-Äquivalent) — NUR UI-Projekt UND Label 'ui'; headless
# (Runner hat keinen Owner-Kanal) -> BLOCK bei fehlender Freigabe.
# ============================================================================
is_ui_project() {
  local lang domains
  lang="$(grep -m1 '^language:' .claude/profile.md 2>/dev/null | sed 's/language: *//;s/"//g' || true)"
  domains="$(grep -m1 '^domains:' .claude/profile.md 2>/dev/null || true)"
  case "$lang" in
    flutter|angular|html) return 0 ;;
  esac
  printf '%s' "$domains" | grep -qE '\b(ui|accessibility)\b'
}

story_has_label() {
  local label="$1"
  printf '%s' "$LABELS_JSON" | python3 -c "import json,sys; l=json.load(sys.stdin) or []; sys.exit(0 if '$label' in l else 1)" 2>/dev/null
}

design_gate_check() {
  if ! is_ui_project || ! story_has_label ui; then
    return 0
  fi
  [[ -f docs/design.md ]] || return 1
  local approved
  approved="$(grep -m1 '^owner_approved:' docs/design.md 2>/dev/null | sed 's/owner_approved: *//;s/"//g' || true)"
  [[ -n "$approved" && "$approved" != "null" ]]
}

# ============================================================================
# DB-Trigger (S3.4) — identische Heuristik zu SKILL.md §3.2a/agents/dba.md:
# Label 'db' ODER Diff berührt db_scripts/|docs/data-model.md ODER
# Datenzugriffs-Import-Heuristik.
# ============================================================================
db_trigger_check() {
  if printf '%s' "$LABELS_JSON" | python3 -c 'import json,sys; l=json.load(sys.stdin) or []; sys.exit(0 if "db" in l else 1)' 2>/dev/null; then
    return 0
  fi
  local diff_files
  diff_files="$(git diff --name-only "$BASE_SHA" HEAD 2>/dev/null || true)"
  if printf '%s\n' "$diff_files" | grep -qE '(^|/)db_scripts/|(^|/)docs/data-model\.md$'; then
    return 0
  fi
  if git diff "$BASE_SHA" HEAD 2>/dev/null | grep -E '^\+' | grep -qE '\b(pg|postgres|mysql2|mariadb|better-sqlite3|sqlite3|mongoose|mongodb|prisma|drizzle|supabase)\b'; then
    return 0
  fi
  return 1
}

# ============================================================================
# Minimal-Kontext-Verträge (§3) — Prompt-Aufbau je Rolle.
# ============================================================================
build_spec_line() {
  IMPLEMENTS_JSON="$IMPLEMENTS_JSON" SPEC_PATH="$SPEC_PATH" python3 - <<'PYEOF'
import json, os
impl = json.loads(os.environ.get("IMPLEMENTS_JSON") or "[]")
spec = os.environ.get("SPEC_PATH") or ""
print(f"{spec} ({', '.join(impl)})" if impl else spec)
PYEOF
}

ITER=1
FINDINGS=""

build_prompt() {
  local role="$1"
  local model model_line=""
  model="$(resolve_model "$role")"
  [[ -n "$model" ]] && model_line=$'\n'"MODEL-OVERRIDE: ${model}"
  local spec_line
  spec_line="$(build_spec_line)"
  local extra=""
  case "$role" in
    coder)
      extra=$'\n'"ITERATION: ${ITER}"
      if [[ "$ITER" -gt 1 && -n "$FINDINGS" ]]; then
        extra="${extra}"$'\n'"FINDINGS:"$'\n'"${FINDINGS}"
      fi
      ;;
    dba)
      extra=$'\n'"MODE: review"
      if printf '%s' "$LABELS_JSON" | grep -q '"db"'; then
        extra="${extra}"$'\n'"LABEL: db"
      fi
      ;;
  esac
  cat <<PROMPT
Nutze den agents/${role}.md-Agenten (Rolle: ${role}) exakt wie dort definiert. Lade deinen "Zuerst lesen"-Block selbst (Spec/Profile/Lessons/Packs) — du bekommst hier NUR den Minimal-Kontrakt (Detailkonzept flow-deterministic-runner §3), keinen SKILL.md-Volltext, keinen Gesprächsverlauf.

ROLE: ${role}
STORY: ${STORY_ID}
SPEC: ${spec_line}
BASE_SHA: ${BASE_SHA}${model_line}${extra}
PROMPT
}

# dispatch_agent — Critical-1-Fix (Review-Iteration 3, HART): MUSS als
# eigenständige Anweisung aufgerufen werden -- NIEMALS über
# `var="$(dispatch_agent ...)"`. Bash dokumentiert explizit: "If bash is
# waiting for a command to complete and receives a signal for which a trap
# has been set, the trap will not be executed until the command completes."
# Eine Kommando-Substitution `$(...)` forkt ihrerseits eine Subshell, auf
# die der TOP-LEVEL-Prozess (dessen `trap ... TERM` registriert ist) mit
# einem eigenen, blockierenden `wait` wartet -- das interne
# `wait "$CURRENT_DISPATCH_PID"` innerhalb von dispatch_agent läuft dann in
# dieser NACHGEORDNETEN Subshell, nicht im Top-Level-Prozess, dessen Trap
# beim Empfang von SIGTERM/SIGINT erst NACH Abschluss der gesamten
# Substitution (d.h. potenziell erst nach dem vollen Hänger) feuert -- live
# reproduziert (Review-Iteration 3: 60s/178s Verzögerung, kein Trap-Log,
# kein State-Update, Waisen-Prozess). DESHALB: Rückgabewert über die globale
# Variable DISPATCH_OUT, dispatch_agent als PLAIN STATEMENT aufrufen (kein
# Value-Capture per Substitution um den Funktionsaufruf) -- der Aufrufer
# liest danach $DISPATCH_OUT. Der interne `cat "$out_file"`-Aufruf unten
# bleibt eine (unkritische) Kommando-Substitution, weil er auf eine bereits
# fertig geschriebene, kleine lokale Datei zugreift -- kein blockierender
# Wait, keine Verzögerungsgefahr, anders als der äussere Fall oben.
DISPATCH_OUT=""

dispatch_agent() {
  local role="$1" prompt="$2"
  DISPATCH_OUT=""
  local out_file
  out_file="$(mktemp "${TMPDIR:-/tmp}/board-round-dispatch.XXXXXX")"
  ( cd "$STORY_WORKTREE" && "$CLAUDE_CMD" -p "$prompt" --dangerously-skip-permissions ) >"$out_file" 2>/dev/null &
  CURRENT_DISPATCH_PID=$!
  wait "$CURRENT_DISPATCH_PID" || true
  CURRENT_DISPATCH_PID=""
  # SIGNAL_RECEIVED-Doppel-Check (Review-Iteration 3, s. Kommentar bei
  # on_signal_trap): falls das unterbrochene `wait` zurückkehrte, WEIL wir
  # selbst den Kindprozess im Signal-Trap getötet haben, MUSS hier sofort
  # beendet werden -- der Rückgabewert (leer, da der Kindprozess vor jeder
  # Ausgabe getötet wurde) darf NIEMALS als "coder lieferte leeren Handoff"
  # o.ä. an den Aufrufer durchgereicht werden (das würde fälschlich in den
  # normalen Board-Schreibpfad laufen, statt sauber über den Signal-Pfad zu
  # enden). Kein Verlass darauf, dass das `exit 143` im Trap selbst
  # rechtzeitig vor dieser Fortsetzung greift.
  if [[ -n "$SIGNAL_RECEIVED" ]]; then
    exit 143
  fi
  DISPATCH_OUT="$(cat "$out_file" 2>/dev/null)"
  rm -f "$out_file" 2>/dev/null || true
}

# ============================================================================
# Eskalations-Mechanik (§5.1) — Judge: fixes günstigstes Modell (Q2a),
# unabhängig vom aktiven Cost-Mode. NIE stilles Raten (AC7).
# ============================================================================
run_judge() {
  local role="$1" handoff="$2"
  local allowed
  case "$role" in
    reviewer|dba) allowed="PASS | CHANGES-REQUIRED" ;;
    tester) allowed="PASS | FAIL | SKIPPED-NO-DOCKER | SKIPPED-DOC-ONLY | SKIPPED-NO-BUILD" ;;
    *) printf 'AMBIGUOUS'; return 0 ;;
  esac
  local prompt out token judge_model
  # Q2(a), HART: immer die günstigste Modell-Stufe, UNABHÄNGIG vom aktiven
  # Cost-Mode der Runde -- reuse resolve_model()/model-tiers.md (Konsistenz-
  # Suggestion Review-Iteration 2) statt eines zweiten, unabhängigen
  # "haiku"-Hardcodes; das "low-cost"-Modus-Override ist NUR lokal für diesen
  # Lookup, $COST_MODE selbst bleibt unverändert (resolve_model liest den
  # Modus aus dem optionalen zweiten Parameter, nicht aus der globalen
  # Variable, wenn er übergeben wird).
  judge_model="$(resolve_model tester low-cost)"
  [[ -z "$judge_model" ]] && judge_model="haiku"
  prompt="JUDGE-GATE-NORMALIZE
ROLE: ${role}
Welches Gate-Token trifft im folgenden Handoff-Text zu? Antworte mit GENAU EINEM Wort aus: ${allowed} | AMBIGUOUS. Keine Begründung.

HANDOFF:
${handoff}"
  set +e
  out="$(timeout 60s "$CLAUDE_CMD" -p "$prompt" --model "$judge_model" 2>/dev/null)"
  set -e
  token="$(printf '%s' "$out" | tr -d '\r' | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' | head -1)"
  case "$role" in
    reviewer|dba)
      case "$token" in
        PASS|CHANGES-REQUIRED) printf '%s' "$token"; return 0 ;;
      esac
      ;;
    tester)
      case "$token" in
        PASS|FAIL|SKIPPED-NO-DOCKER|SKIPPED-DOC-ONLY|SKIPPED-NO-BUILD) printf '%s' "$token"; return 0 ;;
      esac
      ;;
  esac
  printf 'AMBIGUOUS'
  return 0
}

# resolve_gate <role> <handoff> — Exit 0 (Token auf stdout) | 2 (weiterhin
# mehrdeutig NACH Judge — Aufrufer MUSS blockieren, nie raten, AC7).
resolve_gate() {
  local role="$1" handoff="$2"
  local token rc
  set +e
  token="$(printf '%s' "$handoff" | "$PARSE_GATE_SCRIPT" "$role" 2>/dev/null)"
  rc=$?
  set -e
  if [[ "$rc" -eq 0 ]]; then
    printf '%s' "$token"
    return 0
  fi
  if [[ "$rc" -eq 2 ]]; then
    local judged
    judged="$(run_judge "$role" "$handoff")"
    if [[ -n "$judged" && "$judged" != "AMBIGUOUS" ]]; then
      printf '%s' "$judged"
      return 0
    fi
    printf ''
    return 2
  fi
  die "parse-gate.sh lieferte einen Usage-Fehler für Rolle '${role}' — Skript-Aufruf prüfen."
}

extract_findings() {
  HANDOFF_TEXT="$1" python3 - <<'PYEOF'
import os
text = os.environ.get("HANDOFF_TEXT", "")
out = []
capture = False
for line in text.splitlines():
    s = line.strip()
    if s.startswith("## Critical") or s.startswith("## Important"):
        capture = True
        out.append(line)
        continue
    if s.startswith("## "):
        capture = False
        continue
    if capture:
        out.append(line)
print("\n".join(out).strip())
PYEOF
}

extract_failures() {
  printf '%s\n' "$1" | awk '/^Failures:/{found=1} found{print}'
}

count_section() {
  HANDOFF_TEXT="$1" SECTION="$2" python3 - <<'PYEOF'
import os
text = os.environ.get("HANDOFF_TEXT", "")
section = os.environ.get("SECTION", "")
capture = False
count = 0
for line in text.splitlines():
    s = line.strip()
    if s.startswith(f"## {section}"):
        capture = True
        continue
    if s.startswith("## ") and capture:
        break
    if capture:
        if not s or s.lower().startswith("(none") or s.lower() == "none":
            continue
        count += 1
print(count)
PYEOF
}

# ============================================================================
# Memory-Kuration (§5.2/§7.1 — S7.1, der einzige garantierte (c)-Call einer
# sonst LLM-freien Standard-Runde, Owner-Entscheid Q3a: pro Runde).
#
# Critical-2-Fix (Review-Iteration 2): schreibt die Datei NICHT mehr direkt
# -- setzt nur MEMORY_CURATION_CONTENT (globale Variable). Der Aufrufer
# schreibt die Datei selbst (initial UND bei jedem Re-Apply-Retry
# identisch, s. push_meta_with_retry) -- so kann ein Push-Konflikt den
# bereits berechneten Kurations-Text verlustfrei erneut anwenden, ohne
# einen zweiten LLM-Aufruf zu brauchen.
# ============================================================================
MEMORY_CURATION_CONTENT=""

run_memory_curation() {
  local story_id="$1" outcome="$2"
  MEMORY_CURATION_CONTENT=""
  local memory_file="${REPO_ROOT}/.claude/memory.md"
  local current
  if [[ -f "$memory_file" ]]; then
    current="$(cat "$memory_file")"
  else
    current="(keine bestehende .claude/memory.md — ggf. templates/_shared/memory.md als Startgerüst verwenden)"
  fi
  local prompt
  prompt="MEMORY-KURATION
Kuratiere .claude/memory.md gemäss docs/specs/project-memory.md AC3-AC6 (max 60 Zeilen; ## Aktueller Stand max 10 Zeilen; ## Letzte Arbeiten rollierend max 10 Einträge, neueste zuerst; ## Offene Fäden optional max 5). Story ${story_id}: ${outcome}.

AKTUELLER INHALT:
${current}

Gib NUR den vollständigen neuen Inhalt von .claude/memory.md aus, sonst nichts."
  local out
  set +e
  out="$(timeout 60s "$CLAUDE_CMD" -p "$prompt" 2>/dev/null)"
  set -e
  if [[ -n "$out" ]]; then
    MEMORY_CURATION_CONTENT="$out"
    return 0
  fi
  log "⚠ Memory-Kuration fehlgeschlagen oder leer (best-effort, K3) — .claude/memory.md unverändert."
  return 1
}

# ============================================================================
# Board-Meta-Commit mit Re-Apply-Retry (Critical-2-Fix, Review-Iteration 2).
#
# VORHER (fehlerhaft): ein Push-Konflikt wurde per `git cherry-pick`
# aufgelöst. Live reproduziert: da `.claude/memory.md` bei JEDEM Aufruf
# komplett neu geschrieben wird, kollidiert ein Cherry-Pick bei echter
# Nebenläufigkeit GARANTIERT an dieser Datei -> `cherry-pick --abort` ->
# der GESAMTE Commit ging verloren, INKLUSIVE der unbeteiligten
# Dispo-Spiegel-Änderung einer anderen Story. Kein Rest auf origin, nur eine
# Warnzeile im Log -- stiller, echter Datenverlust.
#
# JETZT: kein Merge/Diff-Replay mehr. Bei Push-Ablehnung wird (rebase-frei,
# exakt das gehärtete Re-Read-Muster aus board-claim.sh/story-claim-lock)
# frisch gefetcht + hart resettet, und der Aufrufer wendet über die
# übergebene Reapply-Funktion DENSELBEN deterministischen Schreibvorgang
# erneut an (kein Diff, kein Konfliktpotential) -- dann wird neu committet
# und erneut gepusht. Kein neues Lock-/Race-Protokoll (AC4): dasselbe
# Re-Read/Re-Apply-Prinzip wie beim Claim, nur auf Board-Meta angewandt.
# ============================================================================

# stage_board_meta — fügt board/ IMMER hinzu; .claude/memory.md NUR wenn sie
# existiert. Ein einzelner `git add board/ .claude/memory.md`-Aufruf würde
# bei fehlender memory.md ("did not match any files") GAR NICHTS stagen,
# auch nicht die tatsächlich vorhandenen board/-Änderungen (git-add-Gotcha:
# ein ungültiger Pfad in derselben Invocation lässt die gesamte Operation
# fehlschlagen) — deshalb getrennte Aufrufe.
stage_board_meta() {
  git add board/ 2>/dev/null || true
  [[ -f .claude/memory.md ]] && { git add .claude/memory.md 2>/dev/null || true; }
  return 0
}

# push_meta_with_retry <commit-msg> <reapply-fn> — <reapply-fn> ist eine
# bereits definierte Shell-Funktion (per Namen übergeben), die NACH einem
# frischen `reset --hard origin/...` den gewünschten Board-Meta-Zustand
# deterministisch neu schreibt (z.B. `board set ... Blocked --reason ...` +
# `.claude/memory.md` aus einer bereits berechneten Variable neu befüllen).
# Kein Verlust bei Kollision: im schlimmsten Fall mehrere Retries, nie ein
# verworfener Commit.
push_meta_with_retry() {
  local commit_msg="$1" reapply_fn="$2"
  local attempt=1 max=5
  while true; do
    stage_board_meta
    if git diff --cached --quiet; then
      return 0
    fi
    git commit -q -m "$commit_msg"
    if git push origin HEAD:"$DEFAULT_BRANCH" --quiet 2>/dev/null; then
      return 0
    fi
    [[ "$attempt" -ge "$max" ]] && return 1
    git fetch origin "$DEFAULT_BRANCH" --quiet || return 1
    git reset --hard "origin/${DEFAULT_BRANCH}" --quiet || return 1
    "$reapply_fn"
    attempt=$(( attempt + 1 ))
  done
}

# ============================================================================
# BLOCK — I2: Board-Status wird HIER geschrieben (BOARD_WRITER=flow), sonst
# nirgends ausserhalb CLAIM/LAND-RECOVER.
#
# Important-2-Fix (Review-Iteration 2): auch Blocked-Runden fahren
# board-round-finalize.sh MIT blocked=1 — vorher fehlte JEDE Blocked-Runde
# (SPEC-LÜCKE, Loop-Schutz, Design-Gate, SKIPPED-NO-DOCKER, Judge-AMBIGUOUS,
# NEEDS-HUMAN) im Metrik-Ledger, obwohl das Skript den Parameter dafür
# bereits mitbringt. shortstat braucht den ECHTEN Story-Diff (lebt im
# Story-Worktree, nicht in REPO_ROOT) — deshalb VOR dem Worktree-Teardown
# ausgeführt; die resultierenden Dispo-Spiegel-Werte werden danach in
# REPO_ROOT (die einzige committete/gepushte Kopie) übernommen.
# ============================================================================
block_round() {
  local reason="$1"
  CUR_STATE="BLOCK"
  write_round_state

  local dispo_act_val="null" tok_val="null" dispo_forecast_val="null"
  if [[ -n "$STORY_WORKTREE" && -d "$STORY_WORKTREE" ]]; then
    ( cd "$STORY_WORKTREE" && METRICS_ROOT="$METRICS_ROOT" "$FINALIZE_SCRIPT" "$STORY_ID" "$BASE_SHA" "$SIZE_EST" "$EP_EST" 1 "$LANG_VAL" "$COST_MODE" "$TOK_EST" >&2 ) || true
    local show_json
    show_json="$(cd "$STORY_WORKTREE" && "$BOARD_SCRIPT" show "$STORY_ID" 2>/dev/null)" || show_json=""
    if [[ -n "$show_json" ]]; then
      dispo_act_val="$(printf '%s' "$show_json" | python3 -c 'import json,sys
d=json.load(sys.stdin); v=d.get("dispo_act"); print(v if v is not None else "null")' 2>/dev/null || echo "null")"
      tok_val="$(printf '%s' "$show_json" | python3 -c 'import json,sys
d=json.load(sys.stdin); v=d.get("tok"); print(v if v is not None else "null")' 2>/dev/null || echo "null")"
      dispo_forecast_val="$(printf '%s' "$show_json" | python3 -c 'import json,sys
d=json.load(sys.stdin); v=d.get("dispo_forecast"); print(v if v is not None else "null")' 2>/dev/null || echo "null")"
    fi
  fi

  cd "$REPO_ROOT"
  guard_repo_root_clean

  # Deterministischer, idempotenter Schreibvorgang -- initial UND als
  # Re-Apply-Callback bei Push-Konflikt identisch (Critical-2-Fix).
  _block_apply_fields() {
    BOARD_WRITER=flow "$BOARD_SCRIPT" set "$STORY_ID" status Blocked --reason "$reason"
    if [[ "$dispo_act_val" != "null" ]]; then
      "$BOARD_SCRIPT" set "$STORY_ID" dispo_act "$dispo_act_val" >/dev/null 2>&1 || true
    fi
    if [[ "$tok_val" != "null" ]]; then
      "$BOARD_SCRIPT" set "$STORY_ID" tok "$tok_val" >/dev/null 2>&1 || true
    fi
    if [[ "$dispo_forecast_val" != "null" ]]; then
      "$BOARD_SCRIPT" set "$STORY_ID" dispo_forecast "$dispo_forecast_val" >/dev/null 2>&1 || true
    fi
    return 0
  }
  _block_apply_fields

  run_memory_curation "$STORY_ID" "Blocked: ${reason}" || true
  [[ -n "$MEMORY_CURATION_CONTENT" ]] && printf '%s\n' "$MEMORY_CURATION_CONTENT" > .claude/memory.md

  _block_reapply() {
    _block_apply_fields
    [[ -n "$MEMORY_CURATION_CONTENT" ]] && printf '%s\n' "$MEMORY_CURATION_CONTENT" > .claude/memory.md
    return 0
  }

  push_meta_with_retry "chore(board): ${STORY_ID} Blocked (${reason})" _block_reapply \
    || log "⚠ Push des Blocked-Status für ${STORY_ID} fehlgeschlagen — bitte manuell erneut versuchen."

  release_round_state
  teardown_story_worktree
  log "Runde beendet: ${STORY_ID} Blocked — ${reason}"
  exit 0
}

# ============================================================================
# FINALIZE (Done-Pfad) — board-round-finalize.sh (S-126) + Memory-Kuration +
# gebündelter Session-Ende-Commit (SKILL.md §7-Muster).
# ============================================================================
finalize_done() {
  teardown_story_worktree
  cd "$REPO_ROOT"
  CUR_STATE="FINALIZE"
  write_round_state
  guard_repo_root_clean
  git fetch origin "$DEFAULT_BRANCH" --quiet || true
  git reset --hard "origin/${DEFAULT_BRANCH}" --quiet || true

  local finalize_out
  finalize_out="$(METRICS_ROOT="$METRICS_ROOT" "$FINALIZE_SCRIPT" "$STORY_ID" "$BASE_SHA" "$SIZE_EST" "$EP_EST" 0 "$LANG_VAL" "$COST_MODE" "$TOK_EST" 2>&1)" || true
  printf '%s\n' "$finalize_out" | while IFS= read -r line; do log "$line"; done

  # Dispo-Spiegel-Werte EINMALIG erfassen (Important-Fix, Review-Iteration
  # 3): FINALIZE_SCRIPT läuft ab hier NIE wieder für diese Story -- ein
  # erneuter Aufruf im Reapply-Callback würde metrics-append-item.sh ein
  # zweites Mal ausführen und eine doppelte items.jsonl-Zeile erzeugen
  # (stiller Überzählungs-Fehler unter Last). Der Reapply-Callback wendet
  # bei Push-Konflikt nur die BEREITS BERECHNETEN Feldwerte erneut an
  # (direkter, deterministischer `board set`, kein zweiter Metrik-Append) --
  # exakt das bereits gehärtete Muster aus block_round()/_block_reapply.
  local show_json dispo_act_val="null" tok_val="null" dispo_forecast_val="null"
  show_json="$("$BOARD_SCRIPT" show "$STORY_ID" 2>/dev/null)" || show_json=""
  if [[ -n "$show_json" ]]; then
    dispo_act_val="$(printf '%s' "$show_json" | python3 -c 'import json,sys
d=json.load(sys.stdin); v=d.get("dispo_act"); print(v if v is not None else "null")' 2>/dev/null || echo "null")"
    tok_val="$(printf '%s' "$show_json" | python3 -c 'import json,sys
d=json.load(sys.stdin); v=d.get("tok"); print(v if v is not None else "null")' 2>/dev/null || echo "null")"
    dispo_forecast_val="$(printf '%s' "$show_json" | python3 -c 'import json,sys
d=json.load(sys.stdin); v=d.get("dispo_forecast"); print(v if v is not None else "null")' 2>/dev/null || echo "null")"
  fi

  run_memory_curation "$STORY_ID" "Done" || true
  [[ -n "$MEMORY_CURATION_CONTENT" ]] && printf '%s\n' "$MEMORY_CURATION_CONTENT" > .claude/memory.md

  _finalize_apply_fields() {
    if [[ "$dispo_act_val" != "null" ]]; then
      "$BOARD_SCRIPT" set "$STORY_ID" dispo_act "$dispo_act_val" >/dev/null 2>&1 || true
    fi
    if [[ "$tok_val" != "null" ]]; then
      "$BOARD_SCRIPT" set "$STORY_ID" tok "$tok_val" >/dev/null 2>&1 || true
    fi
    if [[ "$dispo_forecast_val" != "null" ]]; then
      "$BOARD_SCRIPT" set "$STORY_ID" dispo_forecast "$dispo_forecast_val" >/dev/null 2>&1 || true
    fi
    return 0
  }

  _finalize_reapply() {
    _finalize_apply_fields
    [[ -n "$MEMORY_CURATION_CONTENT" ]] && printf '%s\n' "$MEMORY_CURATION_CONTENT" > .claude/memory.md
    return 0
  }

  push_meta_with_retry "chore(board): ${STORY_ID} dispo mirror + memory" _finalize_reapply \
    || log "⚠ Push des Dispo-Spiegels/Memory für ${STORY_ID} fehlgeschlagen (nicht fatal, Story bleibt Done)."

  release_round_state
  log "Runde beendet: ${STORY_ID} Done."
  exit 0
}

# ============================================================================
# FINALIZE (leerer Board- bzw. Claim-Budget-erschöpft-Pfad) — Important-1-Fix
# (Review-Iteration 2): die Übergangstabelle verlangt "DIAGNOSE -> FINALIZE"
# und "CLAIM -> FINALIZE" auch ohne Story-Landung. Ohne Story-ID ergibt ein
# Metrik-Item-Append keinen Sinn (board-round-finalize.sh braucht zwingend
# <story-id>+<base-sha>) — die reduzierte Finalize-Kuration hier deckt genau
# den EINEN garantierten (c)-Call ab (Memory, Q3a "pro Runde").
# ============================================================================
finalize_empty_or_no_claim() {
  local outcome="$1"
  cd "$REPO_ROOT"
  guard_repo_root_clean
  run_memory_curation "-" "$outcome" || true
  if [[ -n "$MEMORY_CURATION_CONTENT" ]]; then
    printf '%s\n' "$MEMORY_CURATION_CONTENT" > .claude/memory.md
    _diag_reapply() {
      [[ -n "$MEMORY_CURATION_CONTENT" ]] && printf '%s\n' "$MEMORY_CURATION_CONTENT" > .claude/memory.md
      return 0
    }
    push_meta_with_retry "chore(board): memory (${outcome})" _diag_reapply \
      || log "⚠ Push der Memory-Kuration fehlgeschlagen (nicht fatal)."
  fi
}

# ============================================================================
# LAND + RECOVER (§4.1 Flip-Fixer, AC8) — board-ship.sh Exit != 0 heisst NIE
# automatisch "nicht gelandet"; erst Remote-PR-Status prüfen.
# ============================================================================
iterate_or_block() {
  local reason="$1"
  ITER=$(( ITER + 1 ))
  if [[ "$ITER" -gt 3 ]]; then
    block_round "Loop-Schutz N=3 — gleicher Befund überlebt 3 Iterationen"
  fi
}

land_and_finalize() {
  CUR_STATE="LAND"
  write_round_state
  set +e
  ( cd "$STORY_WORKTREE" && "$SHIP_SCRIPT" "$STORY_ID" )
  local ship_rc=$?
  set -e

  if [[ "$ship_rc" -eq 0 ]]; then
    finalize_done
    return
  fi

  CUR_STATE="RECOVER"
  write_round_state
  log "board-ship.sh endete mit Exit ${ship_rc} — prüfe Remote-PR-Status (Flip-Fixer §4.1) statt 'nicht gelandet' anzunehmen."
  local merged
  merged="$(gh pr list --head "$STORY_BRANCH" --state all --json state,mergedAt --jq '(.[0].state=="MERGED") or (.[0].mergedAt != null)' 2>/dev/null || echo "")"

  if [[ "$merged" == "true" ]]; then
    log "Remote-PR für '${STORY_BRANCH}' ist MERGED — ziehe Restschritte nach (erneuter, idempotenter board-ship.sh-Aufruf)."
    set +e
    ( cd "$STORY_WORKTREE" && "$SHIP_SCRIPT" "$STORY_ID" )
    local retry_rc=$?
    set -e
    if [[ "$retry_rc" -eq 0 ]]; then
      finalize_done
      return
    fi
    block_round "NEEDS-HUMAN — Landung laut Remote-PR MERGED, aber Restschritte (Board-Flip) schlagen wiederholt fehl (Exit ${retry_rc})"
  else
    block_round "NEEDS-HUMAN — Landen fehlgeschlagen (Exit ${ship_rc}), Remote-PR-Status ist nicht MERGED oder nicht ermittelbar"
  fi
}

# ============================================================================
# BUILD-LOOP (§3, max. N=3) — CODE -> REVIEW -> [DB_REVIEW] -> TEST -> ITERATE
# ============================================================================
build_loop() {
  cd "$STORY_WORKTREE"
  while true; do
    CUR_STATE="CODE"
    write_round_state
    local coder_prompt coder_out
    coder_prompt="$(build_prompt coder)"
    metric_before
    dispatch_agent coder "$coder_prompt"
    coder_out="$DISPATCH_OUT"
    metric_after coder "null" 0 0

    if [[ -z "$coder_out" ]]; then
      block_round "coder-Dispatch lieferte keinen Handoff (Iteration ${ITER}) — Abbruch, manuelle Prüfung nötig"
    fi
    if printf '%s' "$coder_out" | grep -q 'SPEC-LÜCKE'; then
      block_round "Spec unvollständig — /requirement nötig"
    fi
    # Critical-3-Fix (Review-Iteration 2, AC7): Allow-Listing statt
    # Deny-Listing. Vorher galt JEDER Output, der weder leer war noch
    # SPEC-LÜCKE enthielt, stillschweigend als "bereit für Review" — ein
    # unvollständiger/verstümmelter/falsch formatierter coder-Output ohne
    # den Pflicht-Marker wurde nie erkannt (stilles Raten). Jetzt wird der
    # Pflicht-Marker `Review-Handoff: REVIEW REQUIRED` (Architektur §2/§3)
    # explizit verlangt — fehlt er, eskaliert der Runner statt weiterzulaufen.
    if ! printf '%s' "$coder_out" | grep -qE '^Review-Handoff: REVIEW REQUIRED'; then
      block_round "coder-Handoff uneindeutig — kein 'Review-Handoff: REVIEW REQUIRED'-Marker gefunden (Iteration ${ITER})"
    fi

    CUR_STATE="REVIEW"
    write_round_state
    local reviewer_prompt reviewer_out review_gate review_rc
    reviewer_prompt="$(build_prompt reviewer)"
    metric_before
    dispatch_agent reviewer "$reviewer_prompt"
    reviewer_out="$DISPATCH_OUT"
    set +e
    review_gate="$(resolve_gate reviewer "$reviewer_out")"
    review_rc=$?
    set -e
    metric_after reviewer "${review_gate:-AMBIGUOUS}" "$(count_section "$reviewer_out" Critical)" "$(count_section "$reviewer_out" Important)"

    if [[ "$review_rc" -eq 2 ]]; then
      block_round "Gate-Text uneindeutig — manuelle Klärung nötig"
    fi

    if [[ "$review_gate" == "CHANGES-REQUIRED" ]]; then
      FINDINGS="$(extract_findings "$reviewer_out")"
      iterate_or_block "reviewer CHANGES-REQUIRED"
      continue
    fi

    # review_gate == PASS ab hier
    if db_trigger_check; then
      CUR_STATE="DB_REVIEW"
      write_round_state
      local dba_prompt dba_out dba_gate dba_rc
      dba_prompt="$(build_prompt dba)"
      metric_before
      dispatch_agent dba "$dba_prompt"
      dba_out="$DISPATCH_OUT"
      set +e
      dba_gate="$(resolve_gate dba "$dba_out")"
      dba_rc=$?
      set -e
      metric_after dba "${dba_gate:-AMBIGUOUS}" "$(count_section "$dba_out" Critical)" "$(count_section "$dba_out" Important)"

      if [[ "$dba_rc" -eq 2 ]]; then
        block_round "Gate-Text uneindeutig — manuelle Klärung nötig"
      fi
      if [[ "$dba_gate" == "CHANGES-REQUIRED" ]]; then
        FINDINGS="$(extract_findings "$dba_out")"
        iterate_or_block "dba CHANGES-REQUIRED"
        continue
      fi
    fi

    CUR_STATE="TEST"
    write_round_state
    local tester_prompt tester_out test_gate test_rc
    tester_prompt="$(build_prompt tester)"
    metric_before
    dispatch_agent tester "$tester_prompt"
    tester_out="$DISPATCH_OUT"
    set +e
    test_gate="$(resolve_gate tester "$tester_out")"
    test_rc=$?
    set -e
    metric_after tester "${test_gate:-AMBIGUOUS}" 0 0

    if [[ "$test_rc" -eq 2 ]]; then
      block_round "Gate-Text uneindeutig — manuelle Klärung nötig"
    fi

    case "$test_gate" in
      PASS|SKIPPED-DOC-ONLY)
        break
        ;;
      SKIPPED-NO-DOCKER)
        block_round "DB-Subsystem-Smoke konnte nicht laufen — Docker-Daemon fehlt; bitte lokal mit Docker oder via Remote-Host wiederholen"
        ;;
      FAIL)
        FINDINGS="$(extract_failures "$tester_out")"
        iterate_or_block "tester FAIL"
        continue
        ;;
      *)
        block_round "Unbekanntes Test-Gate-Ergebnis (${test_gate})"
        ;;
    esac
  done
}

# ============================================================================
# Main
# ============================================================================
main() {
  select_and_claim_loop

  cd "$STORY_WORKTREE"
  CUR_STATE="DESIGN_GATE"
  write_round_state
  if ! design_gate_check; then
    block_round "Design-Freigabe ausstehend"
  fi

  build_loop
  land_and_finalize
}

main "$@"
