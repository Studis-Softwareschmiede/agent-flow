#!/usr/bin/env bash
# tests/board-round/runner/run-test.sh
#
# Fixture-Test für scripts/board-round.sh — den deterministischen
# Runden-Zustandsautomaten (Spec docs/specs/flow-deterministic-runner.md
# AC1/AC2/AC5/AC7/AC8/AC9/AC10/AC11, Detailkonzept
# docs/architecture/flow-deterministic-runner.md §2/§4/§5).
#
# Fixture-Technik (Muster tests/board-feature-drain/run-test.sh +
# tests/story-claim-lock/run-test.sh): bare "origin"-Repo + Arbeits-Klon,
# gemockte `claude -p`-Aufrufe via PATH-Fake-Binary (dispatcht auf Basis des
# ROLE-Markers/Prompt-Präfixes im Minimal-Kontrakt), gemockter `gh` (Muster
# tests/board-ship/run-test.sh), gemockter `sleep` (No-Op). Berührt NIEMALS
# echtes GitHub oder Claude.
#
# Covers (flow-deterministic-runner):
#   @trace flow-deterministic-runner#AC1
#   @trace flow-deterministic-runner#AC2
#   @trace flow-deterministic-runner#AC5
#   @trace flow-deterministic-runner#AC7
#   @trace flow-deterministic-runner#AC8
#   @trace flow-deterministic-runner#AC9
#   @trace flow-deterministic-runner#AC10
#   @trace flow-deterministic-runner#AC11
#
#   S-129 (Detailkonzept §7 "Decision-Trace + Audit", AC9/AC10) — additive
#   Decision-Trace-Schreibung (board/runs/round-<story>.trace, JSON-Lines,
#   APPEND-ONLY, gitignored): Test 1d/1e/1f verifizieren Entstehung + Format
#   + die vollständige Happy-Path-Übergangsfolge; Test 8c/8d verifizieren den
#   Eskalations-Fall (Übergang nach JUDGE + judge_called/judge_result im
#   Trace, kein stilles Raten). Kein Verhaltensdelta am Zustandsautomaten
#   selbst (reine Beobachtbarkeit, s. board-round.sh write_trace()).
#
#   Test 1  (AC1/AC2/AC9)  — kompletter Happy-Path: Item-Wahl -> Claim ->
#     coder -> reviewer PASS -> tester PASS -> board-ship.sh -> Done.
#   Test 2  (AC5)           — Review-Gate CHANGES-REQUIRED -> Iterate (N=2)
#     -> danach PASS -> landet.
#   Test 3  (AC5/AC7)       — Schleifenschutz N>3: dieselbe CHANGES-REQUIRED
#     überlebt 3 Iterationen -> Blocked ("Loop-Schutz N=3").
#   Test 4                  — coder meldet SPEC-LÜCKE -> Blocked, kein
#     Review-/Test-Dispatch.
#   Test 5  (AC5)           — Test-Gate FAIL -> Iterate -> danach PASS ->
#     landet.
#   Test 6                  — Test-Gate SKIPPED-NO-DOCKER -> Blocked
#     (Human-Handoff, kein Auto-Merge).
#   Test 7  (AC7/§5.1)      — mehrdeutiger Review-Gate-Text -> Judge-Mock
#     liefert PASS -> Fortsetzung (landet).
#   Test 8  (AC7/§5.1)      — Judge liefert AMBIGUOUS -> Blocked
#     ("Gate-Text uneindeutig — manuelle Klärung nötig"), NIE geraten.
#   Test 9                  — DB-Trigger (Label 'db') aktiviert dba-Dispatch,
#     beide Gates PASS -> landet.
#   Test 10                 — Design-Gate (UI-Projekt + Label 'ui', keine
#     Freigabe) headless -> Blocked VOR jedem coder-Dispatch.
#   Test 11 (Q6a)           — `--all`/`--parent` -> Abgabe an den
#     LLM-Orchestrator (Exit 10), KEIN Dispatch, KEIN Board-Schreibvorgang.
#   Test 12 (AC8/§4.1)      — Flip-Fixer: board-ship.sh liefert Exit != 0,
#     aber der Remote-PR ist MERGED -> Restschritte nachgezogen -> Done.
#   Test 13 (AC11/I2)       — Invariante I2: kein Fremd-Schreiben — nur die
#     eigene Story + .claude/memory.md werden in den Commits dieser Runde
#     verändert, keine andere Story-Datei.
#   Test 14 (I3)            — Invariante I3: kein coder-Dispatch vor
#     bestätigtem Claim-Push (fremd+frischer Claim -> Board leer -> kein
#     einziger `claude`-Aufruf).
#   Test 15 (Critical-3-Fix, AC7, Review-Iteration 2; S-132 Nudge-Retry) —
#     coder-Handoff OHNE den Pflicht-Marker `Review-Handoff: REVIEW
#     REQUIRED` (aber auch ohne SPEC-LÜCKE, nicht leer) beim ERSTEN
#     Dispatch -> GENAU EIN mechanischer Nudge-Redispatch (kein
#     ITER-Increment) -> Marker im Nudge-Handoff vorhanden -> Runde läuft
#     normal weiter (Review/Test) -> Done. Belegt: coder wird genau zweimal
#     dispatcht (Original + Nudge), reviewer erst NACH dem erfolgreichen
#     Nudge.
#   Test 20 (S-132, AC7/AC9/AC11) — Gegenprobe: Pflicht-Marker fehlt AUCH im
#     Nudge-Redispatch (`MOCK_CODER_NO_MARKER_PERSIST`) -> block_round greift
#     UNVERÄNDERT wie vor dem Nudge-Fix (kein zweiter Nudge, kein Loop, kein
#     Raten), reviewer wird NICHT dispatcht, coder wird exakt zweimal
#     dispatcht (Original + der eine Nudge, kein dritter Versuch).
#   Test 16 (Critical-1-Fix, I4/AC8, Review-Iteration 2) — ECHTER `kill
#     -TERM` auf die echte Runner-PID (kein Mock, kein simuliertes Signal):
#     State-Datei liegt am korrekten, ABSOLUTEN Ort mit plausiblem
#     Unterbrechungs-Zustand, der Mock-Agent-Kindprozess (der sich VOR dem
#     Kill nachweislich aufgehängt hatte) ist NACH dem Signal nicht mehr am
#     Leben (kein Waisen-Prozess), der Story-Worktree ist abgebaut, der
#     Claim bleibt unangetastet (In Progress, gleicher claimed_by) UND ein
#     Folge-Lauf nach künstlich veraltetem `claimed_at` reklamiert die
#     Story sauber über den bestehenden Stale-Reclamation-Pfad und bringt
#     sie zu Ende (Done) — die Story bleibt reklamierbar.
#   Test 17 (S-130, Bug-1-Fix, AC8/AC9) — produktiv-realistischer coder, der
#     (wie sein echter Vertrag vorschreibt) NIE committet: der Runner
#     committet den fertigen Worktree-Stand selbst vor jedem Landen-Aufruf
#     (commit_story_changes()) -> board-ship.sh's L6-Guard bricht NICHT mehr
#     ab -> Done, Worktree danach sauber abgebaut, Commit-Betreff trägt die
#     Story-ID.
#   Test 18 (S-130, Bug-2-Fix, AC8/AC9/AC11) — EXAKTE Reproduktion des
#     Datenverlust-Vorfalls vom 2026-07-29: nie-committender coder + Loop-
#     Schutz-N=3-Abbruch (Review-Gate CHANGES-REQUIRED x3) + eine fremde,
#     uncommittete Änderung in REPO_ROOT (simulierte Parallel-Session) löst
#     block_round()s eigenen guard_repo_root_clean()-Treffer aus -> Runner
#     bricht mit Exit != 0 ab -> der EXIT-Trap darf den dirty Story-Worktree
#     NICHT mehr force-entfernen (worktree_is_dirty()-Guard): Worktree
#     existiert weiterhin, die uncommittete Coder-Arbeit ist unverändert
#     vorhanden, Board-Status bleibt 'In Progress' (Guard griff VOR jedem
#     Board-Schreibvorgang) — kein Datenverlust, Story bleibt über das
#     bestehende Stale-Reclamation-Netz erreichbar.
#   Test 19 (S-131, AC9/AC11) — EXAKTE Reproduktion des research-app-
#     Vorfalls vom 2026-07-29: ein Zielprojekt OHNE eigenen
#     .claude/worktrees/-Gitignore-Eintrag (anders als agent-flow selbst) +
#     Loop-Schutz-N=3-Blocked-Ausgang. Vor dem Fix hielt
#     guard_repo_root_clean() den eigenen, gerade angelegten Story-Worktree
#     fälschlich für eine fremde uncommittete Änderung und brach die Runde
#     komplett ab (Exit != 0), statt regulär Blocked zu setzen. Test 19a-c:
#     Pathspec-Exclude greift -> Exit 0, kein Guard-Fehlalarm, Story korrekt
#     Blocked. Test 19d-f (Gegenprobe, Zahnlos-Check): dasselbe verwundbare
#     Zielprojekt, aber mit einer ECHTEN fremden uncommitteten Änderung
#     ausserhalb von .claude/worktrees/ (wie Test 18) -> der Guard MUSS
#     weiterhin blockieren, der Exclude betrifft NUR .claude/worktrees/.
#
# Ehrliche Lücke (Handoff-Pflicht, Owner-Transparenz): NICHT abgedeckt in
# diesem Anlauf sind Claim-Race/Stale-Reclamation als eigenständiges Thema
# (bereits vollständig durch tests/board-round/claim/run-test.sh gedeckt,
# hier nicht dupliziert außer als Beleg in Test 16) sowie der Gate-Parser
# selbst (bereits durch tests/board-round/gate/run-test.sh gedeckt). Ein
# echter SIGKILL (statt SIGTERM) auf die Runner-PID selbst ist per
# Unix-Semantik NICHT durch irgendeinen Trap abfangbar (SIGKILL kann
# grundsätzlich nicht behandelt werden) — dafür gibt es keinen Test, weil
# keine Implementierung das lösen könnte; das Stale-Reclamation-Netz
# (Test 16i/16j) ist die einzig mögliche Absicherung für diesen Fall und
# bleibt unverändert wirksam, da der Claim bei JEDEM Abbruch unangetastet
# bleibt. Dieser Test fokussiert die ZUSAMMENSTECKUNG (Zustandsautomat) —
# nicht die bereits andernorts geprüften Primitive.
#
# Exit: 0 = alle Tests bestanden, 1 = mindestens ein Fehler

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
ROUND_SCRIPT="${REPO_ROOT}/scripts/board-round.sh"
BOARD_SCRIPT="${REPO_ROOT}/scripts/board"

TEST_WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/board-round-runner-test.XXXXXX")"
trap 'rm -rf "$TEST_WORK_DIR"' EXIT

FAIL=0
PASS=0
fail() { echo "FAIL: $*" >&2; FAIL=$(( FAIL + 1 )); }
pass() { echo "PASS: $*"; PASS=$(( PASS + 1 )); }

export GIT_AUTHOR_NAME="test" GIT_AUTHOR_EMAIL="test@test.local"
export GIT_COMMITTER_NAME="test" GIT_COMMITTER_EMAIL="test@test.local"
export BOARD_ROUND_SKIP_GH_AUTH=1
export BOARD_SHIP_SKIP_GH_AUTH=1
export MOCK_HEAD_SHA=AUTO

# metrics-collect.sh (via board-round-finalize.sh) durchsucht sonst das
# echte $HOME/.claude/projects (Muster tests/board-round/finalize/run-test.sh).
FAKE_CLAUDE_CONFIG_DIR="${TEST_WORK_DIR}/fake-claude-config"
mkdir -p "${FAKE_CLAUDE_CONFIG_DIR}/.claude/projects"
export CLAUDE_CONFIG_DIR="$FAKE_CLAUDE_CONFIG_DIR"
export BOARD_ID_RESERVE_SLEEP="${BOARD_ID_RESERVE_SLEEP:-0}"

# ---------------------------------------------------------------------------
# Gemockte Binaries (gemeinsames PATH-Verzeichnis für alle Tests)
# ---------------------------------------------------------------------------
# ECHTEN `sleep`-Pfad VOR der PATH-Umbiegung sichern (Fixture-Bugfix,
# Review-Iteration 3 -- Diagnose eines vermeintlichen Signal-Flakes in
# Test 16): der No-Op-`sleep`-Mock unten ist für board-ship.sh's CI-Poll-
# Schleifen nötig (sonst wartet die Suite real 40x15s), würde aber
# UNBEMERKT auch Test 16s "haengender Agent"-Simulation (`sleep 300` im
# Mock-Coder) auf 0 Sekunden verkuerzen -- der Mock-Prozess beendet sich
# dann fast sofort von selbst (nicht wegen des Signal-Traps!), was
# GELEGENTLICH, je nach Scheduling-Timing, zu einem falschen Testergebnis
# fuehrt (Race zwischen "Marker erschienen" und "Mock-Prozess bereits
# wieder beendet", NICHTS mit der Signal-Handhabung von board-round.sh
# selbst zu tun -- live per 23 sauberen manuellen Wiederholungen mit dem
# ECHTEN `sleep` verifiziert, s. Handoff). Test 16s "haengender" Mock nutzt
# daher explizit REAL_SLEEP_BIN (den echten Pfad), NIE den gemockten
# No-Op -- der Rest der Suite (board-ship.sh-CI-Polling) bleibt beim
# gemockten No-Op-`sleep`.
REAL_SLEEP_BIN="$(command -v sleep)"
export REAL_SLEEP_BIN

MOCK_BIN_DIR="${TEST_WORK_DIR}/mockbin"
mkdir -p "$MOCK_BIN_DIR"

cat > "${MOCK_BIN_DIR}/sleep" <<'MOCKEOF'
#!/usr/bin/env bash
exit 0
MOCKEOF
chmod +x "${MOCK_BIN_DIR}/sleep"

# `timeout` — NUR anlegen, wenn das Host-System KEIN echtes `timeout' hat
# (Stock-macOS ohne Homebrew-coreutils, board-round.sh:run_judge nutzt seit
# Review-Iteration 4 `timeout 60s ...`, analog run_memory_curation/
# board-feature-drain.sh:325 -- bestehendes Repo-Muster, keine neue
# Regression). Existiert ein echtes `timeout`, wird HIER NICHTS angelegt,
# damit das reale Binary (falls vorhanden) unverändert greift -- der Shim
# reicht das Kommando nur durch (kein Testpfad in dieser Suite provoziert
# einen echten Haenger, der eine tatsächliche Deadline bräuchte).
if ! command -v timeout >/dev/null 2>&1; then
  cat > "${MOCK_BIN_DIR}/timeout" <<'MOCKEOF'
#!/usr/bin/env bash
shift
exec "$@"
MOCKEOF
  chmod +x "${MOCK_BIN_DIR}/timeout"
fi

# `gh` — Muster tests/board-ship/run-test.sh: CI immer grün, PR-Zustand aus
# Env gesteuert (MOCK_PR_LIST_STATE=MERGED -> gh pr list --head ... liefert
# "true", Grundlage für den Flip-Fixer-Test UND board-ship.sh's eigene
# Idempotenz-Prüfung).
cat > "${MOCK_BIN_DIR}/gh" <<'MOCKEOF'
#!/usr/bin/env bash
if [[ "$1" == "run" && "$2" == "list" ]]; then
  branch="" jq_expr=""
  for ((i=1; i<=$#; i++)); do
    if [[ "${!i}" == "--branch" ]]; then j=$((i+1)); branch="${!j}"; fi
    if [[ "${!i}" == "--jq" ]]; then j=$((i+1)); jq_expr="${!j}"; fi
  done
  case "$jq_expr" in
    *'NOSHA'*)
      if [[ "${MOCK_HEAD_SHA:-}" == "AUTO" ]]; then
        echo "$(git rev-parse "origin/${branch}" 2>/dev/null)"
      else
        echo "${MOCK_HEAD_SHA:-NOSHA}"
      fi
      exit 0 ;;
    *headSha*)
      if [[ "${MOCK_HEAD_SHA:-}" == "AUTO" ]]; then
        echo "$(git rev-parse "origin/${branch}" 2>/dev/null)"
      else
        echo "${MOCK_HEAD_SHA:-}"
      fi
      exit 0 ;;
    *'.status'*) echo "completed"; exit 0 ;;
    *conclusion*) echo "success"; exit 0 ;;
  esac
  echo ""; exit 0
fi
if [[ "$1" == "pr" && "$2" == "create" ]]; then
  echo "https://github.com/mock/repo/pull/999"
  exit 0
fi
if [[ "$1" == "pr" && "$2" == "merge" ]]; then
  exit "${MOCK_GH_PR_MERGE_EXIT:-0}"
fi
if [[ "$1" == "pr" && "$2" == "view" ]]; then
  case "${MOCK_PR_VIEW_STATE:-}" in
    MERGED) echo "true" ;;
    *) echo "false" ;;
  esac
  exit 0
fi
if [[ "$1" == "pr" && "$2" == "list" ]]; then
  case "${MOCK_PR_LIST_STATE:-}" in
    MERGED) echo "true" ;;
    *) echo "false" ;;
  esac
  exit 0
fi
if [[ "$1" == "api" ]]; then
  if [[ " $* " == *" DELETE "* ]]; then
    exit 0
  fi
fi
exit 0
MOCKEOF
chmod +x "${MOCK_BIN_DIR}/gh"

# `claude` — dispatcht auf Basis des Minimal-Kontrakt-Prompts ($2). Erkennt
# die Rolle über den "ROLE: <rolle>"-Marker bzw. die festen Präfixe
# "JUDGE-GATE-NORMALIZE"/"MEMORY-KURATION" (board-round.sh §5.1/§5.2).
cat > "${MOCK_BIN_DIR}/claude" <<'MOCKEOF'
#!/usr/bin/env bash
set -euo pipefail
PROMPT="$2"

if [[ "$PROMPT" == JUDGE-GATE-NORMALIZE* ]]; then
  echo "${MOCK_JUDGE_TOKEN:-AMBIGUOUS}"
  exit 0
fi

if [[ "$PROMPT" == MEMORY-KURATION* ]]; then
  if [[ "${MOCK_MEMORY_FAIL:-0}" == "1" ]]; then
    exit 1
  fi
  cat <<'MEMEOF'
> Orientierung, nie Wahrheit: dieses Dokument spiegelt den Stand, nicht die Wahrheit.
> Kuratiert von /flow (mock).

## Aktueller Stand
Mock-Session lief durch.

## Letzte Arbeiten
- Mock-Eintrag

## Offene Fäden
(keine)
MEMEOF
  exit 0
fi

ROLE="$(printf '%s' "$PROMPT" | grep -oE 'ROLE: [a-z]+' | head -1 | awk '{print $2}')"
STATE_DIR="$(pwd)/.mock-state"
mkdir -p "$STATE_DIR"
echo "1" >> "${STATE_DIR}/dispatch-count"

pick_seq() {
  local seq_var="$1" state_file="$2"
  local seq="${!seq_var:-}"
  [[ -n "$seq" ]] || { echo ""; return 0; }
  local idx=0
  [[ -f "$state_file" ]] && idx="$(cat "$state_file")"
  IFS=',' read -ra arr <<< "$seq"
  local n="${#arr[@]}"
  local use_idx="$idx"
  [[ "$use_idx" -ge "$n" ]] && use_idx=$(( n - 1 ))
  echo "$(( idx + 1 ))" > "$state_file"
  echo "${arr[$use_idx]}"
}

case "$ROLE" in
  coder)
    IDX_FILE="${STATE_DIR}/coder-idx"
    idx=0; [[ -f "$IDX_FILE" ]] && idx="$(cat "$IDX_FILE")"
    idx=$(( idx + 1 )); echo "$idx" > "$IDX_FILE"

    # S-130-Fixture (Bug-2-Reproduktion): simuliert eine fremde, uncommittete
    # Änderung, die WÄHREND der Runde in REPO_ROOT auftaucht (z.B. eine
    # parallele Session) -- unabhängig vom Story-Worktree selbst, in dem der
    # Coder-Dispatch läuft. Löst später block_round()s eigenen
    # guard_repo_root_clean()-Aufruf aus (exakt der zweite, im Vorfall
    # beobachtete Guard-Treffer, diesmal in REPO_ROOT statt im Ship-Worktree).
    if [[ -n "${MOCK_DIRTY_REPO_ROOT:-}" ]]; then
      echo "stray foreign change (simulierte Parallel-Session)" > "${MOCK_DIRTY_REPO_ROOT}/stray-foreign-change.txt"
    fi

    if [[ "${MOCK_CODER_SPEC_LUECKE:-0}" == "1" && "$idx" == "1" ]]; then
      echo "Done: nichts umgesetzt (Spec-Lücke erkannt)"
      echo "Files: -"
      echo "Spec: SPEC-LÜCKE: strukturelle Lücke -- /requirement nötig"
      echo "Self-Test: n/a"
      exit 0
    fi

    # Critical-3-Fixture (Allow-Listing statt Deny-Listing): liefert einen
    # wohlgeformt aussehenden, aber UNVOLLSTAENDIGEN Output OHNE den
    # Pflicht-Marker "Review-Handoff: REVIEW REQUIRED" -- muss eskalieren,
    # NICHT stillschweigend als "bereit fuer Review" durchgehen.
    #
    # S-132-Fixture: seit dem Nudge-Retry-Fix wird der Marker nach EINEM
    # fehlenden Vorkommen mechanisch nachgefragt (build_nudge_prompt()). Zwei
    # Varianten:
    #  - MOCK_CODER_NO_MARKER=1        -- Marker fehlt NUR beim allerersten
    #    Dispatch (idx==1); der nachfolgende Nudge-Redispatch (idx==2) faellt
    #    durch in den Default-Zweig unten (MIT Marker) -- Nudge hilft, Runde
    #    laeuft normal weiter.
    #  - MOCK_CODER_NO_MARKER_PERSIST=1 -- Marker fehlt bei JEDEM Dispatch
    #    (auch beim Nudge-Redispatch) -- Nudge hilft NICHT, block_round muss
    #    unveraendert greifen (kein zweiter Nudge, kein Loop).
    if [[ "${MOCK_CODER_NO_MARKER_PERSIST:-0}" == "1" ]]; then
      echo "mock coder iteration ${idx} (no marker, persist)" >> mock-impl.txt
      git add -A
      git commit -q -m "mock coder iteration ${idx} (no marker, persist)"
      echo "Done: mock implementation (iter ${idx}, unvollstaendiger Handoff, persist)"
      echo "Files: mock-impl.txt"
      echo "Spec: unveraendert"
      echo "Self-Test: ok"
      exit 0
    fi
    if [[ "${MOCK_CODER_NO_MARKER:-0}" == "1" && "$idx" == "1" ]]; then
      echo "mock coder iteration ${idx} (no marker)" >> mock-impl.txt
      git add -A
      git commit -q -m "mock coder iteration ${idx} (no marker)"
      echo "Done: mock implementation (iter ${idx}, unvollstaendiger Handoff)"
      echo "Files: mock-impl.txt"
      echo "Spec: unveraendert"
      echo "Self-Test: ok"
      exit 0
    fi

    # Critical-1-Fixture (echter SIGTERM-Test): schreibt die eigene PID in
    # eine Marker-Datei und haengt sich dann auf (simuliert einen lange
    # laufenden Agenten-Dispatch) -- wird vom Test gezielt gekillt.
    if [[ "${MOCK_CODER_HANG:-0}" == "1" && "$idx" == "1" && -n "${MOCK_HANG_MARKER:-}" ]]; then
      echo "$$" > "${MOCK_HANG_MARKER}"
      # ECHTES sleep (nicht der No-Op-PATH-Mock) -- s. Kommentar bei
      # REAL_SLEEP_BIN oben, sonst beendet sich dieser Prozess faelschlich
      # sofort statt tatsaechlich zu haengen.
      "${REAL_SLEEP_BIN:-sleep}" 300
      exit 0
    fi

    echo "mock coder iteration ${idx}" >> mock-impl.txt
    if [[ "${MOCK_CODER_DB_FILE:-0}" == "1" ]]; then
      mkdir -p db_scripts
      echo "-- mock migration ${idx}" >> db_scripts/001_mock.sql
    fi

    # S-130-Fixture (Bug-1-Reproduktion, HART, "MOCK_CODER_UNCOMMITTED"): der
    # ECHTE coder-Agent committet NIE (agents/coder.md: "Editiere nur den
    # Worktree, committe NICHT") -- die vorherigen Mock-Zweige oben committen
    # aus Fixture-Bequemlichkeit selbst und verdecken damit Bug 1 (fehlender
    # Commit-Schritt in board-round.sh vor dem Landen). Dieser Zweig bildet
    # den PRODUKTIV-realistischen Vertrag ab: schreibt, committet NICHT.
    if [[ "${MOCK_CODER_UNCOMMITTED:-0}" == "1" ]]; then
      echo "Done: mock implementation (iter ${idx}, uncommitted -- echter coder-Vertrag)"
      echo "Files: mock-impl.txt"
      echo "Spec: unverändert"
      echo "Self-Test: ok"
      echo "Review-Handoff: REVIEW REQUIRED (#1, Iteration ${idx})"
      exit 0
    fi

    git add -A
    git commit -q -m "mock coder iteration ${idx}"

    echo "Done: mock implementation (iter ${idx})"
    echo "Files: mock-impl.txt"
    echo "Spec: unverändert"
    echo "Self-Test: ok"
    echo "Review-Handoff: REVIEW REQUIRED (#1, Iteration ${idx})"
    exit 0
    ;;
  reviewer)
    val="$(pick_seq MOCK_REVIEWER_SEQUENCE "${STATE_DIR}/reviewer-idx")"
    val="${val:-PASS}"
    case "$val" in
      CR)
        cat <<EOF
Review-Gate: CHANGES-REQUIRED

## Critical
mock-impl.txt:1 -- Mock-Befund -- Fix: mach es richtig -- [neu]
## Important
(none)
## Suggestions
(none)
EOF
        ;;
      AMBIGUOUS)
        echo "Der Reviewer ist unsicher -- dieser Text enthaelt gar keine Gate-Zeile."
        ;;
      *)
        cat <<EOF
Review-Gate: PASS

## Critical
(none)
## Important
(none)
## Suggestions
(none)
EOF
        ;;
    esac
    exit 0
    ;;
  dba)
    val="$(pick_seq MOCK_DBA_SEQUENCE "${STATE_DIR}/dba-idx")"
    val="${val:-PASS}"
    if [[ "$val" == "CR" ]]; then
      cat <<EOF
Review-Gate: CHANGES-REQUIRED

## Critical
db_scripts/001_mock.sql:1 -- Mock-DB-Befund -- Fix -- [neu]
## Important
(none)
## Suggestions
(none)
EOF
    else
      cat <<EOF
Review-Gate: PASS

## Critical
(none)
## Important
(none)
## Suggestions
(none)
EOF
    fi
    exit 0
    ;;
  tester)
    val="$(pick_seq MOCK_TESTER_SEQUENCE "${STATE_DIR}/tester-idx")"
    val="${val:-PASS}"
    case "$val" in
      FAIL)
        cat <<EOF
Test-Gate: FAIL
Ran: mock tests
Result: 0 passed, 1 failed
Failures: mock-impl.txt assertion failed
EOF
        ;;
      SKIPPED-NO-DOCKER)
        cat <<EOF
Test-Gate: SKIPPED-NO-DOCKER
Ran: n/a
Result: Docker-Daemon nicht erreichbar
Failures: none
EOF
        ;;
      *)
        cat <<EOF
Test-Gate: PASS
Ran: mock tests
Result: 1 passed, 0 failed
Failures: none
EOF
        ;;
    esac
    exit 0
    ;;
  *)
    echo "[mock-claude] unbekannte/keine ROLE im Prompt: '${ROLE}'" >&2
    exit 1
    ;;
esac
MOCKEOF
chmod +x "${MOCK_BIN_DIR}/claude"

export PATH="${MOCK_BIN_DIR}:${PATH}"

# ---------------------------------------------------------------------------
# Fixture-Aufbau: bare "origin" + Arbeits-Klon mit Board + Profil + Spec.
# ---------------------------------------------------------------------------
setup_fixture() {
  local dir="$1" lang="${2:-md}"
  local origin="${dir}/origin.git"
  local work="${dir}/work"

  git init --bare -q "$origin"
  git init -q "$work"
  (
    cd "$work"
    git remote add origin "$origin"
    mkdir -p board/features board/stories docs/specs .claude/metrics
    cat > board/board.yaml <<'YAML'
schema_version: 1
project_slug: test-proj
next_feature_id: 2
next_story_id: 950
YAML
    cat > board/features/F-001-test.yaml <<'YAML'
id: F-001
title: Test-Feature
goal: Testfeature
status: Active
priority: P1
spec: null
definition_of_done: null
labels: null
depends: null
owner: null
area: null
stories: null
progress: null
created_at: '2026-01-01T00:00:00Z'
updated_at: '2026-01-01T00:00:00Z'
YAML
    cat > docs/specs/test-spec.md <<'MD'
---
id: test-spec
title: Test Spec
status: active
---
# Test Spec
AC1 — Testkriterium eins.
AC2 — Testkriterium zwei.
MD
    cat > .claude/profile.md <<PROFEOF
---
language: ${lang}
domains: []
merge_policy: direct
board: 1
deploy: none
default_branch: main
cost_mode: balanced
---
Test-Profil.
PROFEOF
    cat > .gitignore <<'GITIGNOREEOF'
board/runs/
.claude/worktrees/
.claude/metrics/dispatches.jsonl
.claude/metrics/items.jsonl
.mock-state/
GITIGNOREEOF
    echo "initial" > README.md
    git add -A
    git commit -q -m "initial board setup"
    git branch -M main
    git push -q origin main
  )
  git -C "$origin" symbolic-ref HEAD refs/heads/main
  echo "$work"
}

# setup_fixture_no_worktree_gitignore <dir> [<lang>] — wie setup_fixture(),
# aber die .gitignore des Zielprojekts hat den .claude/worktrees/-Eintrag
# NICHT (S-131, exakte Nachstellung des research-app-Vorfalls vom
# 2026-07-29: anders als agent-flow selbst — und anders als die Standard-
# Fixture oben — hat das Zielprojekt dort keinen passenden
# .gitignore-Eintrag für den vom Runner selbst angelegten Story-Worktree).
setup_fixture_no_worktree_gitignore() {
  local dir="$1" lang="${2:-md}"
  local work
  work="$(setup_fixture "$dir" "$lang")"
  (
    cd "$work"
    grep -v '^\.claude/worktrees/$' .gitignore > .gitignore.tmp
    mv .gitignore.tmp .gitignore
    git add -A
    git commit -q -m "gitignore ohne .claude/worktrees (research-app-Vorfall-Nachstellung)"
    git push -q origin main
  )
  echo "$work"
}

# add_story <work> <id> <labels-yaml> [<extra-yaml-lines>] — legt eine
# To-Do-Story an + committet + pusht.
add_story() {
  local work="$1" sid="$2" labels="$3" extra="${4:-}"
  cat > "${work}/board/stories/${sid}-mock.yaml" <<YAML
id: ${sid}
parent: F-001
title: Mock-Story ${sid}
status: To Do
priority: P2
spec: docs/specs/test-spec.md
implements: [AC1, AC2]
depends: null
labels: ${labels}
claimed_by: null
claimed_at: null
branch: null
size_est: M
dispo_est: null
tok_est: null
pr: null
created_at: '2026-01-01T00:00:00Z'
updated_at: '2026-01-01T00:00:00Z'
done_at: null
${extra}
YAML
  ( cd "$work" && git add -A && git commit -q -m "add ${sid}" && git push -q origin main )
}

now_minus_hours() {
  local hours="$1"
  date -u -v-"${hours}"H +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
    || date -u -d "-${hours} hours" +%Y-%m-%dT%H:%M:%SZ
}

# pid_alive_retry <pid> [<tries>] — Liveness-Check mit kurzem, begrenztem
# Retry (Default 10x100ms = max. 1s). Unter Last (Stability-Wiederholungen
# des Signal-Fixture-Tests, s. Test 16) beobachtet: ein EINZELNER `kill -0`
# kann durch OS-Scheduling-Jitter kurzzeitig fälschlich "tot" melden, obwohl
# der Prozess de facto noch 300s in `sleep` hängt — ein knapper Retry glättet
# dieses reine Timing-Rauschen, ohne die eigentliche Aussage (der Prozess
# lebt / lebt nicht mehr) zu verwässern.
pid_alive_retry() {
  local pid="$1" tries="${2:-10}" i
  for (( i=0; i<tries; i++ )); do
    kill -0 "$pid" 2>/dev/null && return 0
    sleep 0.1
  done
  return 1
}

# run_round <work> [env-assignments...] — führt board-round.sh im "work"-Klon
# aus, gibt kombinierten Output zurück (stdout+stderr), setzt RC.
run_round() {
  local work="$1"; shift
  set +e
  ROUND_OUT="$(cd "$work" && env "$@" bash "$ROUND_SCRIPT" 2>&1)"
  ROUND_RC=$?
  set -e
}

# ===========================================================================
echo ""
echo "--- Test 1 (AC1/AC2/AC9): Happy-Path -- PASS/PASS/PASS -> Done ---"
T1_DIR="${TEST_WORK_DIR}/t1"
T1_WORK="$(setup_fixture "$T1_DIR")"
add_story "$T1_WORK" "S-950" "null"

run_round "$T1_WORK"
if [[ "$ROUND_RC" -eq 0 ]]; then
  pass "Test 1a: board-round.sh Exit 0"
else
  fail "Test 1a: erwartete Exit 0, bekam ${ROUND_RC} -- Output:
${ROUND_OUT}"
fi

T1_STATUS="$(git --git-dir="${T1_DIR}/origin.git" show main:board/stories/S-950-mock.yaml | grep '^status:')"
if [[ "$T1_STATUS" == "status: Done" ]]; then
  pass "Test 1b: S-950 remote 'Done'"
else
  fail "Test 1b: S-950 remote-Status unerwartet: ${T1_STATUS} -- Output:
${ROUND_OUT}"
fi

if [[ ! -d "${T1_WORK}/.claude/worktrees/S-950" ]]; then
  pass "Test 1c: Story-Worktree nach Landung abgebaut (SR1)"
else
  fail "Test 1c: Story-Worktree wurde nicht abgebaut"
fi

# Decision-Trace (S-129, Detailkonzept §7 "Decision-Trace + Audit", AC9/AC10):
# board/runs/round-<story>.trace entsteht, ist JSON-Lines (jede Zeile für
# sich per `python3 json.loads` fehlerfrei parsbar) und enthält für den
# Happy-Path GENAU die erwartete Übergangsfolge aus der Architektur-§2-
# Tabelle (kein DB_REVIEW/JUDGE, da kein DB-Trigger und kein mehrdeutiges
# Gate in diesem Testfall).
T1_TRACE_FILE="${T1_WORK}/board/runs/round-S-950.trace"
if [[ -s "$T1_TRACE_FILE" ]]; then
  pass "Test 1d: Trace-Datei board/runs/round-S-950.trace entstanden"
else
  fail "Test 1d: Trace-Datei fehlt oder leer (${T1_TRACE_FILE})"
fi

T1_TRACE_PARSE_ERR="$(python3 -c '
import json, sys
path = sys.argv[1]
errors = 0
with open(path) as f:
    for i, line in enumerate(f, 1):
        line = line.strip()
        if not line:
            continue
        try:
            json.loads(line)
        except Exception as e:
            errors += 1
            print(f"line {i}: {e}", file=sys.stderr)
sys.exit(1 if errors else 0)
' "$T1_TRACE_FILE" 2>&1)" || true
if [[ -z "$T1_TRACE_PARSE_ERR" ]]; then
  pass "Test 1e: jede Trace-Zeile ist geparst-verifizierbares JSON"
else
  fail "Test 1e: mindestens eine Trace-Zeile ist kein gültiges JSON:
${T1_TRACE_PARSE_ERR}"
fi

T1_TRACE_SEQ="$(python3 -c '
import json
path = "'"$T1_TRACE_FILE"'"
with open(path) as f:
    tos = [json.loads(l)["to"] for l in f if l.strip()]
print(",".join(tos))
' 2>/dev/null)" || true
T1_EXPECTED_SEQ="SELECT,CLAIM,DESIGN_GATE,CODE,REVIEW,TEST,LAND,FINALIZE,EXIT"
if [[ "$T1_TRACE_SEQ" == "$T1_EXPECTED_SEQ" ]]; then
  pass "Test 1f: Trace-Übergangsfolge entspricht dem Happy-Path (${T1_EXPECTED_SEQ})"
else
  fail "Test 1f: unerwartete Trace-Übergangsfolge -- erwartet '${T1_EXPECTED_SEQ}', bekam '${T1_TRACE_SEQ}'"
fi

# ===========================================================================
echo ""
echo "--- Test 2 (AC5): Review-Gate CHANGES-REQUIRED -> Iterate -> PASS -> Done ---"
T2_DIR="${TEST_WORK_DIR}/t2"
T2_WORK="$(setup_fixture "$T2_DIR")"
add_story "$T2_WORK" "S-951" "null"

run_round "$T2_WORK" MOCK_REVIEWER_SEQUENCE=CR,PASS
if [[ "$ROUND_RC" -eq 0 ]]; then
  pass "Test 2a: Exit 0 nach Iterate+PASS"
else
  fail "Test 2a: erwartete Exit 0, bekam ${ROUND_RC} -- Output:
${ROUND_OUT}"
fi
T2_STATUS="$(git --git-dir="${T2_DIR}/origin.git" show main:board/stories/S-951-mock.yaml | grep '^status:')"
if [[ "$T2_STATUS" == "status: Done" ]]; then
  pass "Test 2b: S-951 remote 'Done' nach einer Iteration"
else
  fail "Test 2b: S-951 remote-Status unerwartet: ${T2_STATUS}"
fi
T2_CODER_DISPATCHES="$(printf '%s\n' "$ROUND_OUT" | grep -c 'agent=coder' || true)"
if [[ "$T2_CODER_DISPATCHES" -eq 2 ]]; then
  pass "Test 2c: coder wurde genau zweimal dispatcht (Iterate griff, Metrik-Log belegt es)"
else
  fail "Test 2c: erwartete 2 coder-Dispatches, gezählt ${T2_CODER_DISPATCHES} -- Output:
${ROUND_OUT}"
fi

# ===========================================================================
echo ""
echo "--- Test 3 (AC5/AC7): Schleifenschutz N>3 -> Blocked ---"
T3_DIR="${TEST_WORK_DIR}/t3"
T3_WORK="$(setup_fixture "$T3_DIR")"
add_story "$T3_WORK" "S-952" "null"

run_round "$T3_WORK" MOCK_REVIEWER_SEQUENCE=CR,CR,CR,CR
if [[ "$ROUND_RC" -eq 0 ]]; then
  pass "Test 3a: Exit 0 (Blocked ist ein regulärer Rundenabschluss)"
else
  fail "Test 3a: erwartete Exit 0, bekam ${ROUND_RC} -- Output:
${ROUND_OUT}"
fi
T3_SHOW="$(cd "$T3_WORK" && BOARD_DIR=board "$BOARD_SCRIPT" show S-952)"
if echo "$T3_SHOW" | grep -q '"status": "Blocked"' && echo "$T3_SHOW" | grep -q 'Loop-Schutz N=3'; then
  pass "Test 3b: S-952 Blocked mit 'Loop-Schutz N=3'-Grund"
else
  fail "Test 3b: unerwarteter Board-Zustand: ${T3_SHOW}"
fi

# ===========================================================================
echo ""
echo "--- Test 4: coder meldet SPEC-LÜCKE -> Blocked, kein Review-/Test-Dispatch ---"
T4_DIR="${TEST_WORK_DIR}/t4"
T4_WORK="$(setup_fixture "$T4_DIR")"
add_story "$T4_WORK" "S-953" "null"

run_round "$T4_WORK" MOCK_CODER_SPEC_LUECKE=1
if [[ "$ROUND_RC" -eq 0 ]]; then
  pass "Test 4a: Exit 0"
else
  fail "Test 4a: erwartete Exit 0, bekam ${ROUND_RC} -- Output:
${ROUND_OUT}"
fi
T4_SHOW="$(cd "$T4_WORK" && BOARD_DIR=board "$BOARD_SCRIPT" show S-953)"
if echo "$T4_SHOW" | grep -q '"status": "Blocked"' && echo "$T4_SHOW" | grep -q 'Spec unvollständig'; then
  pass "Test 4b: S-953 Blocked mit 'Spec unvollständig'-Grund"
else
  fail "Test 4b: unerwarteter Board-Zustand: ${T4_SHOW}"
fi

# ===========================================================================
echo ""
echo "--- Test 5 (AC5): Test-Gate FAIL -> Iterate -> PASS -> Done ---"
T5_DIR="${TEST_WORK_DIR}/t5"
T5_WORK="$(setup_fixture "$T5_DIR")"
add_story "$T5_WORK" "S-954" "null"

run_round "$T5_WORK" MOCK_TESTER_SEQUENCE=FAIL,PASS
if [[ "$ROUND_RC" -eq 0 ]]; then
  pass "Test 5a: Exit 0 nach Test-FAIL+Iterate+PASS"
else
  fail "Test 5a: erwartete Exit 0, bekam ${ROUND_RC} -- Output:
${ROUND_OUT}"
fi
T5_STATUS="$(git --git-dir="${T5_DIR}/origin.git" show main:board/stories/S-954-mock.yaml | grep '^status:')"
if [[ "$T5_STATUS" == "status: Done" ]]; then
  pass "Test 5b: S-954 remote 'Done'"
else
  fail "Test 5b: S-954 remote-Status unerwartet: ${T5_STATUS}"
fi

# ===========================================================================
echo ""
echo "--- Test 6: Test-Gate SKIPPED-NO-DOCKER -> Blocked (Human-Handoff) ---"
T6_DIR="${TEST_WORK_DIR}/t6"
T6_WORK="$(setup_fixture "$T6_DIR")"
add_story "$T6_WORK" "S-955" "null"

run_round "$T6_WORK" MOCK_TESTER_SEQUENCE=SKIPPED-NO-DOCKER
if [[ "$ROUND_RC" -eq 0 ]]; then
  pass "Test 6a: Exit 0"
else
  fail "Test 6a: erwartete Exit 0, bekam ${ROUND_RC} -- Output:
${ROUND_OUT}"
fi
T6_SHOW="$(cd "$T6_WORK" && BOARD_DIR=board "$BOARD_SCRIPT" show S-955)"
if echo "$T6_SHOW" | grep -q '"status": "Blocked"' && echo "$T6_SHOW" | grep -q 'Docker-Daemon'; then
  pass "Test 6b: S-955 Blocked mit Docker-Grund, kein Auto-Merge"
else
  fail "Test 6b: unerwarteter Board-Zustand: ${T6_SHOW}"
fi

# ===========================================================================
echo ""
echo "--- Test 7 (AC7/§5.1): mehrdeutiges Review-Gate -> Judge-Mock PASS -> landet ---"
T7_DIR="${TEST_WORK_DIR}/t7"
T7_WORK="$(setup_fixture "$T7_DIR")"
add_story "$T7_WORK" "S-956" "null"

run_round "$T7_WORK" MOCK_REVIEWER_SEQUENCE=AMBIGUOUS MOCK_JUDGE_TOKEN=PASS
if [[ "$ROUND_RC" -eq 0 ]]; then
  pass "Test 7a: Exit 0 nach Judge-Normalisierung"
else
  fail "Test 7a: erwartete Exit 0, bekam ${ROUND_RC} -- Output:
${ROUND_OUT}"
fi
T7_STATUS="$(git --git-dir="${T7_DIR}/origin.git" show main:board/stories/S-956-mock.yaml | grep '^status:')"
if [[ "$T7_STATUS" == "status: Done" ]]; then
  pass "Test 7b: S-956 remote 'Done' -- Judge hat mehrdeutigen Text korrekt normalisiert"
else
  fail "Test 7b: S-956 remote-Status unerwartet: ${T7_STATUS}"
fi

# ===========================================================================
echo ""
echo "--- Test 8 (AC7/§5.1): Judge liefert AMBIGUOUS -> Blocked (nie geraten) ---"
T8_DIR="${TEST_WORK_DIR}/t8"
T8_WORK="$(setup_fixture "$T8_DIR")"
add_story "$T8_WORK" "S-957" "null"

run_round "$T8_WORK" MOCK_REVIEWER_SEQUENCE=AMBIGUOUS MOCK_JUDGE_TOKEN=AMBIGUOUS
if [[ "$ROUND_RC" -eq 0 ]]; then
  pass "Test 8a: Exit 0 (Blocked ist regulärer Abschluss)"
else
  fail "Test 8a: erwartete Exit 0, bekam ${ROUND_RC} -- Output:
${ROUND_OUT}"
fi
T8_SHOW="$(cd "$T8_WORK" && BOARD_DIR=board "$BOARD_SCRIPT" show S-957)"
if echo "$T8_SHOW" | grep -q '"status": "Blocked"' && echo "$T8_SHOW" | grep -q 'Gate-Text uneindeutig'; then
  pass "Test 8b: S-957 Blocked mit 'Gate-Text uneindeutig — manuelle Klärung nötig'"
else
  fail "Test 8b: unerwarteter Board-Zustand: ${T8_SHOW}"
fi

# Decision-Trace (S-129): der Eskalations-Fall MUSS im Trace sichtbar sein --
# eine Zeile mit to=JUDGE (Review-Gate mehrdeutig -> Judge gerufen) und eine
# Zeile mit judge_called=true + judge_result=AMBIGUOUS auf dem Weg zu BLOCK
# (kein stilles Raten, s. AC7).
T8_TRACE_FILE="${T8_WORK}/board/runs/round-S-957.trace"
T8_TRACE_JUDGE_ENTRY="$(python3 -c '
import json
with open("'"$T8_TRACE_FILE"'") as f:
    for l in f:
        e = json.loads(l)
        if e.get("to") == "JUDGE":
            print("found")
            break
' 2>/dev/null)" || true
if [[ "$T8_TRACE_JUDGE_ENTRY" == "found" ]]; then
  pass "Test 8c: Trace enthält einen Übergang nach JUDGE (Gate-Eskalation dokumentiert)"
else
  fail "Test 8c: kein 'to: JUDGE'-Eintrag im Trace gefunden (${T8_TRACE_FILE}):
$(cat "$T8_TRACE_FILE" 2>/dev/null || echo '<fehlt>')"
fi

T8_TRACE_JUDGE_RESULT="$(python3 -c '
import json
with open("'"$T8_TRACE_FILE"'") as f:
    for l in f:
        e = json.loads(l)
        if e.get("judge_called") and e.get("judge_result"):
            print(e["judge_result"])
            break
' 2>/dev/null)" || true
if [[ "$T8_TRACE_JUDGE_RESULT" == "AMBIGUOUS" ]]; then
  pass "Test 8d: Trace belegt judge_called=true mit judge_result=AMBIGUOUS (Eskalations-Ergebnis dokumentiert)"
else
  fail "Test 8d: erwartete judge_result=AMBIGUOUS im Trace, bekam '${T8_TRACE_JUDGE_RESULT}':
$(cat "$T8_TRACE_FILE" 2>/dev/null || echo '<fehlt>')"
fi

# ===========================================================================
echo ""
echo "--- Test 9: DB-Trigger (Label 'db') aktiviert dba-Dispatch, beide Gates PASS -> Done ---"
T9_DIR="${TEST_WORK_DIR}/t9"
T9_WORK="$(setup_fixture "$T9_DIR")"
add_story "$T9_WORK" "S-958" "[db]"

run_round "$T9_WORK" MOCK_CODER_DB_FILE=1
if [[ "$ROUND_RC" -eq 0 ]]; then
  pass "Test 9a: Exit 0"
else
  fail "Test 9a: erwartete Exit 0, bekam ${ROUND_RC} -- Output:
${ROUND_OUT}"
fi
T9_STATUS="$(git --git-dir="${T9_DIR}/origin.git" show main:board/stories/S-958-mock.yaml | grep '^status:')"
if [[ "$T9_STATUS" == "status: Done" ]]; then
  pass "Test 9b: S-958 remote 'Done'"
else
  fail "Test 9b: S-958 remote-Status unerwartet: ${T9_STATUS}"
fi
if [[ -f "${T9_WORK}/.claude/worktrees/S-958/.mock-state/dba-idx" ]] || printf '%s' "$ROUND_OUT" | grep -qi 'dba'; then
  pass "Test 9c: dba wurde tatsächlich dispatcht (DB-Trigger griff)"
else
  fail "Test 9c: kein Beleg für dba-Dispatch -- Output:
${ROUND_OUT}"
fi

# ===========================================================================
echo ""
echo "--- Test 10: Design-Gate (UI-Projekt + Label 'ui', keine Freigabe) headless -> Blocked VOR jedem Dispatch ---"
T10_DIR="${TEST_WORK_DIR}/t10"
T10_WORK="$(setup_fixture "$T10_DIR" "angular")"
add_story "$T10_WORK" "S-959" "[ui]"

run_round "$T10_WORK"
if [[ "$ROUND_RC" -eq 0 ]]; then
  pass "Test 10a: Exit 0"
else
  fail "Test 10a: erwartete Exit 0, bekam ${ROUND_RC} -- Output:
${ROUND_OUT}"
fi
T10_SHOW="$(cd "$T10_WORK" && BOARD_DIR=board "$BOARD_SCRIPT" show S-959)"
if echo "$T10_SHOW" | grep -q '"status": "Blocked"' && echo "$T10_SHOW" | grep -q 'Design-Freigabe ausstehend'; then
  pass "Test 10b: S-959 Blocked mit 'Design-Freigabe ausstehend'"
else
  fail "Test 10b: unerwarteter Board-Zustand: ${T10_SHOW}"
fi
if [[ ! -f "${T10_WORK}/.claude/worktrees/S-959/.mock-state/dispatch-count" ]]; then
  pass "Test 10c: KEIN Agent-Dispatch vor dem Design-Gate-Block (Worktree ohne .mock-state)"
else
  fail "Test 10c: unerwarteter Agent-Dispatch trotz fehlender Design-Freigabe"
fi

# ===========================================================================
echo ""
echo "--- Test 11 (Q6a): --all/--parent -> Abgabe an Orchestrator, kein Dispatch ---"
T11_DIR="${TEST_WORK_DIR}/t11"
T11_WORK="$(setup_fixture "$T11_DIR")"
add_story "$T11_WORK" "S-960" "null"

set +e
T11_OUT_ALL="$(cd "$T11_WORK" && bash "$ROUND_SCRIPT" --all 2>&1)"
T11_RC_ALL=$?
set -e
if [[ "$T11_RC_ALL" -eq 10 ]] && printf '%s' "$T11_OUT_ALL" | grep -q 'ausserhalb Runner-Scope'; then
  pass "Test 11a: '--all' -> Exit 10 + Klartext-Abgabe"
else
  fail "Test 11a: erwartete Exit 10 + Abgabe-Meldung, bekam ${T11_RC_ALL} -- Output:
${T11_OUT_ALL}"
fi

set +e
T11_OUT_PARENT="$(cd "$T11_WORK" && bash "$ROUND_SCRIPT" --parent F-001 2>&1)"
T11_RC_PARENT=$?
set -e
if [[ "$T11_RC_PARENT" -eq 10 ]] && printf '%s' "$T11_OUT_PARENT" | grep -q 'ausserhalb Runner-Scope'; then
  pass "Test 11b: '--parent F-001' -> Exit 10 + Klartext-Abgabe"
else
  fail "Test 11b: erwartete Exit 10 + Abgabe-Meldung, bekam ${T11_RC_PARENT} -- Output:
${T11_OUT_PARENT}"
fi

T11_STATUS="$(git --git-dir="${T11_DIR}/origin.git" show main:board/stories/S-960-mock.yaml | grep '^status:')"
if [[ "$T11_STATUS" == "status: To Do" ]]; then
  pass "Test 11c: S-960 bleibt 'To Do' -- kein Claim, kein Dispatch bei Out-of-Scope-Flags"
else
  fail "Test 11c: S-960 unerwartet verändert: ${T11_STATUS}"
fi

# ===========================================================================
echo ""
echo "--- Test 12 (AC8/§4.1): Flip-Fixer -- board-ship.sh Exit != 0, PR MERGED -> Done nachgezogen ---"
T12_DIR="${TEST_WORK_DIR}/t12"
T12_WORK="$(setup_fixture "$T12_DIR")"
add_story "$T12_WORK" "S-961" "null"

FAKE_SHIP="${T12_DIR}/fake-ship.sh"
cat > "$FAKE_SHIP" <<FAKESHIPEOF
#!/usr/bin/env bash
set -euo pipefail
SID="\$1"
STATE_DIR="${T12_DIR}/fake-ship-state"
mkdir -p "\$STATE_DIR"
CALLS_FILE="\${STATE_DIR}/calls"
n=0; [[ -f "\$CALLS_FILE" ]] && n="\$(cat "\$CALLS_FILE")"
n=\$(( n + 1 )); echo "\$n" > "\$CALLS_FILE"

ORIGIN_URL="\$(git remote get-url origin)"
TMP="\$(mktemp -d)"
git clone -q "\$ORIGIN_URL" "\$TMP"

if [[ "\$n" -eq 1 ]]; then
  ( cd "\$TMP" && git checkout -q -B main origin/main && echo merged >> merged-marker.txt && git add -A && git commit -q -m "\${SID}: merged remote (mock flow/P3)" && git push -q origin HEAD:main )
  rm -rf "\$TMP"
  echo "mock-ship: simulierter Remote-Merge erfolgreich, aber lokaler Board-Flip schlaegt fehl (flow/P3)" >&2
  exit 1
fi

( cd "\$TMP" && git checkout -q -B main origin/main && BOARD_DIR=board BOARD_WRITER=flow "${BOARD_SCRIPT}" set "\$SID" status Done >/dev/null && git add board/ && git commit -q -m "\${SID}: Done (mock flip-fixer restschritt)" && git push -q origin HEAD:main )
rm -rf "\$TMP"
exit 0
FAKESHIPEOF
chmod +x "$FAKE_SHIP"

run_round "$T12_WORK" BOARD_ROUND_SHIP_CMD="$FAKE_SHIP" MOCK_PR_LIST_STATE=MERGED
if [[ "$ROUND_RC" -eq 0 ]]; then
  pass "Test 12a: Exit 0 nach Flip-Fixer-Restschritt"
else
  fail "Test 12a: erwartete Exit 0, bekam ${ROUND_RC} -- Output:
${ROUND_OUT}"
fi
T12_STATUS="$(git --git-dir="${T12_DIR}/origin.git" show main:board/stories/S-961-mock.yaml | grep '^status:')"
if [[ "$T12_STATUS" == "status: Done" ]]; then
  pass "Test 12b: S-961 remote 'Done' -- Flip-Fixer hat den Board-Flip nachgezogen"
else
  fail "Test 12b: S-961 remote-Status unerwartet: ${T12_STATUS}"
fi
if printf '%s' "$ROUND_OUT" | grep -q 'MERGED'; then
  pass "Test 12c: Runner-Log belegt die Remote-PR-MERGED-Prüfung (kein blindes 'nicht gelandet')"
else
  fail "Test 12c: kein Beleg für die Remote-PR-Pruefung im Log -- Output:
${ROUND_OUT}"
fi

# ===========================================================================
echo ""
echo "--- Test 13 (AC11/I2): Invariante I2 -- kein Fremd-Schreiben ---"
T13_DIR="${TEST_WORK_DIR}/t13"
T13_WORK="$(setup_fixture "$T13_DIR")"
add_story "$T13_WORK" "S-962" "null"
add_story "$T13_WORK" "S-963" "null"

T13_BASE_SHA="$(git -C "$T13_WORK" rev-parse HEAD)"
run_round "$T13_WORK"
if [[ "$ROUND_RC" -eq 0 ]]; then
  pass "Test 13a: Exit 0"
else
  fail "Test 13a: erwartete Exit 0, bekam ${ROUND_RC} -- Output:
${ROUND_OUT}"
fi

T13_CHANGED_FILES="$(git --git-dir="${T13_DIR}/origin.git" diff --name-only "$T13_BASE_SHA" main)"
if printf '%s\n' "$T13_CHANGED_FILES" | grep -q 'board/stories/S-963-mock.yaml'; then
  fail "Test 13b: S-963 (fremde Story) wurde verändert -- Invariante I2 verletzt:
${T13_CHANGED_FILES}"
else
  pass "Test 13b: S-963 (fremde, nicht gewählte Story) bleibt unangetastet"
fi
if printf '%s\n' "$T13_CHANGED_FILES" | grep -q 'board/stories/S-962-mock.yaml'; then
  pass "Test 13c: die eigene Story S-962 wurde verändert (erwartet)"
else
  fail "Test 13c: S-962 wurde NICHT verändert, obwohl sie gelandet sein sollte:
${T13_CHANGED_FILES}"
fi

# ===========================================================================
echo ""
echo "--- Test 14 (I3): kein coder-Dispatch vor bestätigtem Claim-Push (fremd+frischer Claim) ---"
T14_DIR="${TEST_WORK_DIR}/t14"
T14_WORK="$(setup_fixture "$T14_DIR")"
add_story "$T14_WORK" "S-964" "null"
(
  cd "$T14_WORK"
  BOARD_DIR=board BOARD_WRITER=flow "$BOARD_SCRIPT" set S-964 status "In Progress" >/dev/null
  BOARD_DIR=board "$BOARD_SCRIPT" set S-964 claimed_by "fremde-frische-session-123" >/dev/null
  BOARD_DIR=board "$BOARD_SCRIPT" set S-964 claimed_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >/dev/null
  BOARD_DIR=board "$BOARD_SCRIPT" set S-964 branch "feat/S-964-fremd" >/dev/null
  git add board/ && git commit -q -m "chore(board): S-964 claim (fremd, frisch)" && git push -q origin main
)

run_round "$T14_WORK"
if [[ "$ROUND_RC" -eq 0 ]]; then
  pass "Test 14a: Exit 0 (Board hat kein eigenes bereites Item -- Leerlauf-Diagnose)"
else
  fail "Test 14a: erwartete Exit 0, bekam ${ROUND_RC} -- Output:
${ROUND_OUT}"
fi
if [[ ! -d "${T14_WORK}/.claude/worktrees/S-964" ]]; then
  pass "Test 14b: kein Story-Worktree fuer S-964 angelegt (kein Dispatch moeglich ohne Worktree)"
else
  fail "Test 14b: unerwarteter Story-Worktree fuer S-964 trotz fremdem, frischem Claim"
fi
T14_STATUS="$(git --git-dir="${T14_DIR}/origin.git" show main:board/stories/S-964-mock.yaml | grep '^status:')"
T14_CLAIMED_BY="$(git --git-dir="${T14_DIR}/origin.git" show main:board/stories/S-964-mock.yaml | grep '^claimed_by:')"
if [[ "$T14_STATUS" == "status: In Progress" ]] && printf '%s' "$T14_CLAIMED_BY" | grep -q 'fremde-frische-session-123'; then
  pass "Test 14c: fremder, frischer Claim von S-964 bleibt unangetastet (kein Fremd-Schreiben)"
else
  fail "Test 14c: S-964 wurde unerwartet veraendert -- status='${T14_STATUS}', claimed_by='${T14_CLAIMED_BY}'"
fi

# ===========================================================================
echo ""
echo "--- Test 15 (Critical-3, AC7; S-132 Nudge-Retry): coder-Handoff ohne Pflicht-Marker beim 1. Dispatch -> genau EIN Nudge-Redispatch -> Marker vorhanden -> Done ---"
T15_DIR="${TEST_WORK_DIR}/t15"
T15_WORK="$(setup_fixture "$T15_DIR")"
add_story "$T15_WORK" "S-965" "null"

run_round "$T15_WORK" MOCK_CODER_NO_MARKER=1
if [[ "$ROUND_RC" -eq 0 ]]; then
  pass "Test 15a: Exit 0"
else
  fail "Test 15a: erwartete Exit 0, bekam ${ROUND_RC} -- Output:
${ROUND_OUT}"
fi
T15_STATUS="$(git --git-dir="${T15_DIR}/origin.git" show main:board/stories/S-965-mock.yaml | grep '^status:')"
if [[ "$T15_STATUS" == "status: Done" ]]; then
  pass "Test 15b: S-965 remote 'Done' -- der eine Nudge-Redispatch hat den fehlenden Marker nachgeliefert"
else
  fail "Test 15b: unerwarteter remote-Status (erwartete Done nach erfolgreichem Nudge): ${T15_STATUS}"
fi
T15_CODER_DISPATCHES="$(printf '%s\n' "$ROUND_OUT" | grep -c 'agent=coder' || true)"
if [[ "$T15_CODER_DISPATCHES" -eq 2 ]]; then
  pass "Test 15c: coder wurde genau zweimal dispatcht (Original ohne Marker + der EINE Nudge-Redispatch)"
else
  fail "Test 15c: erwartete 2 coder-Dispatches, gezählt ${T15_CODER_DISPATCHES} -- Output:
${ROUND_OUT}"
fi
T15_REVIEWER_CALLS="$(printf '%s\n' "$ROUND_OUT" | grep -c 'agent=reviewer' || true)"
if [[ "$T15_REVIEWER_CALLS" -eq 1 ]]; then
  pass "Test 15d: reviewer wurde genau einmal dispatcht (erst NACH dem erfolgreichen Nudge)"
else
  fail "Test 15d: erwartete genau 1 reviewer-Dispatch, gezählt ${T15_REVIEWER_CALLS} -- Output:
${ROUND_OUT}"
fi

# Decision-Trace: der Nudge-Versuch MUSS als eigener, von einer normalen
# Iteration unterscheidbarer Übergang sichtbar sein (CODE -> CODE, "Nudge"
# im Trigger-Text) UND darf den Iterationszähler NICHT erhöht haben
# (iteration bleibt 1 in jeder Nudge-Trace-Zeile — kein Review-Loop-Durchgang).
T15_TRACE_FILE="${T15_WORK}/board/runs/round-S-965.trace"
T15_NUDGE_STATS="$(python3 -c '
import json
count = 0
bad_iter = 0
with open("'"$T15_TRACE_FILE"'") as f:
    for l in f:
        e = json.loads(l)
        if "Nudge" in (e.get("trigger") or ""):
            count += 1
            if e.get("iteration") != 1:
                bad_iter += 1
print(f"{count},{bad_iter}")
' 2>/dev/null)" || true
if [[ "$T15_NUDGE_STATS" == "2,0" ]]; then
  pass "Test 15e: Trace zeigt genau 2 Nudge-bezogene Übergänge (Marker fehlt + Nudge erfolgreich), jeweils ohne ITER-Increment"
else
  fail "Test 15e: unerwartete Nudge-Trace-Statistik (count,bad_iter) -- erwartet '2,0', bekam '${T15_NUDGE_STATS}':
$(cat "$T15_TRACE_FILE" 2>/dev/null || echo '<fehlt>')"
fi

# ===========================================================================
echo ""
echo "--- Test 16 (Critical-1, I4/AC8): echter SIGTERM auf die Runner-PID -- State-Datei korrekt, kein Waisen-Kindprozess, Story sauber reklamierbar ---"
T16_DIR="${TEST_WORK_DIR}/t16"
T16_WORK="$(setup_fixture "$T16_DIR")"
add_story "$T16_WORK" "S-966" "null"

T16_PID_FILE="${T16_DIR}/runner.pid"
T16_HANG_MARKER="${T16_DIR}/hang-child.pid"
T16_RUN_LOG="${T16_DIR}/run.log"
rm -f "$T16_PID_FILE" "$T16_HANG_MARKER" "$T16_RUN_LOG"

(
  cd "$T16_WORK" && env \
    BOARD_ROUND_PID_FILE="$T16_PID_FILE" \
    MOCK_CODER_HANG=1 \
    MOCK_HANG_MARKER="$T16_HANG_MARKER" \
    bash "$ROUND_SCRIPT"
) > "$T16_RUN_LOG" 2>&1 &
T16_BG_JOB=$!

# Bounded Poll (kein fixes sleep) -- auf die Runner-PID-Datei warten.
T16_WAITED=0
while [[ ! -s "$T16_PID_FILE" && "$T16_WAITED" -lt 100 ]]; do
  sleep 0.1
  T16_WAITED=$(( T16_WAITED + 1 ))
done
T16_RUNNER_PID="$(cat "$T16_PID_FILE" 2>/dev/null || true)"

# Bounded Poll auf den haengenden Mock-Kindprozess (beweist: er laeuft
# TATSAECHLICH, bevor wir killen).
T16_WAITED=0
while [[ ! -s "$T16_HANG_MARKER" && "$T16_WAITED" -lt 150 ]]; do
  sleep 0.1
  T16_WAITED=$(( T16_WAITED + 1 ))
done
T16_HANG_PID="$(cat "$T16_HANG_MARKER" 2>/dev/null || true)"

if [[ -n "$T16_RUNNER_PID" ]] && pid_alive_retry "$T16_RUNNER_PID"; then
  pass "Test 16a: Runner-PID (${T16_RUNNER_PID}) ermittelt, Prozess laeuft"
else
  fail "Test 16a: Runner-PID nicht ermittelbar oder Prozess laeuft nicht (PID='${T16_RUNNER_PID}')"
fi
if [[ -n "$T16_HANG_PID" ]] && pid_alive_retry "$T16_HANG_PID"; then
  pass "Test 16b: Mock-Agent-Kindprozess (${T16_HANG_PID}) laeuft VOR dem Kill (echter Hintergrund-Dispatch)"
else
  fail "Test 16b: Mock-Agent-Kindprozess nicht ermittelbar oder laeuft nicht (PID='${T16_HANG_PID}')"
fi

# Echter SIGTERM auf die ECHTE Runner-PID (nicht auf den Bash-Job-Wrapper) --
# exakt das Live-Repro aus dem Review.
kill -TERM "$T16_RUNNER_PID" 2>/dev/null || true

wait "$T16_BG_JOB" 2>/dev/null || true

# Kurzer Nachlauf-Poll: der Kindprozess braucht ggf. einen Moment, um auf
# SIGTERM zu reagieren (bounded, kein festes sleep).
T16_WAITED=0
while kill -0 "$T16_HANG_PID" 2>/dev/null && [[ "$T16_WAITED" -lt 50 ]]; do
  sleep 0.1
  T16_WAITED=$(( T16_WAITED + 1 ))
done

if grep -q 'Signal TERM empfangen' "$T16_RUN_LOG"; then
  pass "Test 16c: Signal-Trap hat gefeuert (Log belegt 'Signal TERM empfangen')"
else
  fail "Test 16c: kein Beleg für den Signal-Trap im Log:
$(cat "$T16_RUN_LOG")"
fi

if ! kill -0 "$T16_HANG_PID" 2>/dev/null; then
  pass "Test 16d: Mock-Agent-Kindprozess (${T16_HANG_PID}) ist NICHT mehr am Leben -- kein Waisen-Prozess"
else
  fail "Test 16d: Mock-Agent-Kindprozess (${T16_HANG_PID}) läuft NACH dem Kill weiter -- Waisen-Prozess (Critical-1-Regression)"
  kill -9 "$T16_HANG_PID" 2>/dev/null || true
fi

T16_STATE_FILE="${T16_WORK}/board/runs/round-S-966.state"
if [[ -f "$T16_STATE_FILE" ]] && grep -q '^story_id: S-966' "$T16_STATE_FILE"; then
  pass "Test 16e: State-Datei liegt am erwarteten, ABSOLUTEN Ort (${T16_STATE_FILE}) mit korrektem story_id"
else
  fail "Test 16e: State-Datei fehlt oder falscher Inhalt am erwarteten Ort (${T16_STATE_FILE}):
$(cat "$T16_STATE_FILE" 2>/dev/null || echo '<fehlt>')"
fi
if [[ -f "$T16_STATE_FILE" ]] && grep -qE '^state: (CODE|CLAIM|SETUP|SELECT)' "$T16_STATE_FILE"; then
  pass "Test 16f: State-Datei zeigt einen plausiblen Unterbrechungs-Zustand"
else
  fail "Test 16f: unerwarteter state-Wert in der State-Datei:
$(cat "$T16_STATE_FILE" 2>/dev/null || echo '<fehlt>')"
fi

if [[ ! -d "${T16_WORK}/.claude/worktrees/S-966" ]]; then
  pass "Test 16g: Story-Worktree wurde abgebaut (EXIT-Trap lief nach dem Signal-Trap)"
else
  fail "Test 16g: Story-Worktree wurde NICHT abgebaut"
fi

T16_ORIG_CLAIMED_BY="$(git --git-dir="${T16_DIR}/origin.git" show main:board/stories/S-966-mock.yaml | grep '^claimed_by:')"
T16_STATUS="$(git --git-dir="${T16_DIR}/origin.git" show main:board/stories/S-966-mock.yaml | grep '^status:')"
if [[ "$T16_STATUS" == "status: In Progress" && -n "$T16_ORIG_CLAIMED_BY" ]]; then
  pass "Test 16h: S-966 bleibt 'In Progress' mit unangetastetem Claim (kein aggressives Zurücksetzen, I4)"
else
  fail "Test 16h: S-966 unerwartet verändert -- status='${T16_STATUS}', claimed_by='${T16_ORIG_CLAIMED_BY}'"
fi

# Reklamierbarkeits-Beweis: claimed_at künstlich veralten lassen (stale
# claim), dann einen frischen, NICHT haengenden Lauf starten -- muss den
# verwaisten Claim ueber den bestehenden Stale-Reclamation-Pfad uebernehmen
# und die Story sauber zu Ende bringen (Done).
(
  cd "$T16_WORK"
  git fetch -q origin main
  git reset -q --hard origin/main
  BOARD_DIR=board "$BOARD_SCRIPT" set S-966 claimed_at "$(now_minus_hours 6)" >/dev/null
  git add board/ && git commit -q -m "chore(board): S-966 claimed_at auf stale zurückdatiert (Testvorbereitung)" && git push -q origin main
)
run_round "$T16_WORK"
if [[ "$ROUND_RC" -eq 0 ]]; then
  pass "Test 16i: Folge-Lauf nach Stale-Reclamation Exit 0"
else
  fail "Test 16i: erwartete Exit 0 im Folge-Lauf, bekam ${ROUND_RC} -- Output:
${ROUND_OUT}"
fi
T16_FINAL_STATUS="$(git --git-dir="${T16_DIR}/origin.git" show main:board/stories/S-966-mock.yaml | grep '^status:')"
if [[ "$T16_FINAL_STATUS" == "status: Done" ]]; then
  pass "Test 16j: S-966 nach Stale-Reclamation + frischem Lauf sauber 'Done' -- Story bleibt reklamierbar"
else
  fail "Test 16j: S-966 nach Reklamation nicht 'Done': ${T16_FINAL_STATUS}"
fi

# ===========================================================================
echo ""
echo "--- Test 17 (S-130, Bug-1-Fix): produktiv-realistischer coder (committet NICHT) -> Runner committet selbst vor dem Landen -> Done ---"
T17_DIR="${TEST_WORK_DIR}/t17"
T17_WORK="$(setup_fixture "$T17_DIR")"
add_story "$T17_WORK" "S-967" "null"

run_round "$T17_WORK" MOCK_CODER_UNCOMMITTED=1
if [[ "$ROUND_RC" -eq 0 ]]; then
  pass "Test 17a: Exit 0 -- board-ship.sh's L6-Guard bricht NICHT ab (Runner hat vor dem Landen committet)"
else
  fail "Test 17a: erwartete Exit 0, bekam ${ROUND_RC} -- Output:
${ROUND_OUT}"
fi
T17_STATUS="$(git --git-dir="${T17_DIR}/origin.git" show main:board/stories/S-967-mock.yaml | grep '^status:')"
if [[ "$T17_STATUS" == "status: Done" ]]; then
  pass "Test 17b: S-967 remote 'Done' trotz nie-committendem coder"
else
  fail "Test 17b: S-967 remote-Status unerwartet: ${T17_STATUS} -- Output:
${ROUND_OUT}"
fi
if [[ ! -d "${T17_WORK}/.claude/worktrees/S-967" ]]; then
  pass "Test 17c: Story-Worktree nach Landung sauber abgebaut (nichts mehr uncommittet)"
else
  fail "Test 17c: Story-Worktree wurde nicht abgebaut"
fi
# git log -1 träfe hier den NACHFOLGENDEN Dispo-Spiegel/Memory-Commit
# (finalize_done() committet nach der Landung noch einmal Board-Meta) --
# die eigentliche Story-Implementierung muss also in der VOLLEN Historie
# gesucht werden, nicht nur im allerletzten Commit.
T17_COMMIT_SUBJECT="$(git --git-dir="${T17_DIR}/origin.git" log --format=%s main | grep -m1 '^S-967:' || true)"
if [[ "$T17_COMMIT_SUBJECT" == S-967:* ]]; then
  pass "Test 17d: gelandeter Story-Commit trägt die erwartete '${T17_COMMIT_SUBJECT}'-Betreffzeile (Story-ID-Präfix, von commit_story_changes() gesetzt)"
else
  fail "Test 17d: kein Commit mit 'S-967:'-Präfix in der main-Historie gefunden -- Output:
${ROUND_OUT}"
fi

# ===========================================================================
echo ""
echo "--- Test 18 (S-130, Bug-2-Fix): EXAKTE Vorfall-Reproduktion -- dirty Story-Worktree + REPO_ROOT-Guard-Treffer waehrend BLOCK -> Worktree NICHT geloescht ---"
T18_DIR="${TEST_WORK_DIR}/t18"
T18_WORK="$(setup_fixture "$T18_DIR")"
add_story "$T18_WORK" "S-968" "null"

# Reproduziert 1:1 den Vorfall vom 2026-07-29: ein coder, der (wie der echte
# Vertrag es vorsieht) NICHT committet, gefolgt von einem Loop-Schutz-N=3-
# Abbruch (Review-Gate CHANGES-REQUIRED dreimal), waehrend WAEHREND der Runde
# eine fremde, uncommittete Aenderung in REPO_ROOT auftaucht (simulierte
# Parallel-Session) -- genau der zweite Guard-Treffer aus dem Vorfallbericht
# ("diesmal im REPO_ROOT, beim Versuch den Board-Meta-Commit zu schreiben").
run_round "$T18_WORK" MOCK_CODER_UNCOMMITTED=1 MOCK_REVIEWER_SEQUENCE=CR,CR,CR,CR "MOCK_DIRTY_REPO_ROOT=${T18_WORK}"

if [[ "$ROUND_RC" -ne 0 ]]; then
  pass "Test 18a: Runner bricht mit Exit != 0 ab (REPO_ROOT-Guard griff waehrend BLOCK, wie im Vorfall beobachtet)"
else
  fail "Test 18a: erwartete Exit != 0 (Guard-Treffer), bekam Exit 0 -- Output:
${ROUND_OUT}"
fi
if printf '%s' "$ROUND_OUT" | grep -q 'uncommittete Änderungen'; then
  pass "Test 18b: Fehlermeldung nennt die uncommitteten Änderungen in REPO_ROOT (Board-Meta-Write-Guard)"
else
  fail "Test 18b: erwartete Guard-Fehlermeldung fehlt -- Output:
${ROUND_OUT}"
fi

T18_STORY_WORKTREE="${T18_WORK}/.claude/worktrees/S-968"
if [[ -d "$T18_STORY_WORKTREE" ]]; then
  pass "Test 18c: Story-Worktree existiert NOCH (Bug-2-Fix -- kein Force-Remove eines dirty Worktrees)"
else
  fail "Test 18c: Story-Worktree wurde entfernt -- GENAU der reproduzierte Datenverlust-Vorfall"
fi

if [[ -f "${T18_STORY_WORKTREE}/mock-impl.txt" ]] && grep -q "mock coder iteration" "${T18_STORY_WORKTREE}/mock-impl.txt"; then
  pass "Test 18d: die (nie committete) Coder-Arbeit (mock-impl.txt) ist noch vorhanden -- kein Datenverlust"
else
  fail "Test 18d: mock-impl.txt fehlt oder leer -- Coder-Arbeit verloren -- Output:
${ROUND_OUT}"
fi

T18_WORKTREE_DIRTY="$(git -C "$T18_STORY_WORKTREE" status --porcelain 2>/dev/null || true)"
if [[ -n "$T18_WORKTREE_DIRTY" ]]; then
  pass "Test 18e: Story-Worktree ist weiterhin uncommittet (nichts wurde heimlich committet oder verworfen)"
else
  fail "Test 18e: Story-Worktree ist ueberraschend sauber -- Zustand entspricht nicht dem erwarteten Vorfall"
fi

if printf '%s' "$ROUND_OUT" | grep -q 'unversicherte Änderungen — NICHT entfernt'; then
  pass "Test 18f: Runner-Log belegt die explizite Rettungs-Warnung (teardown_story_worktree-Guard griff)"
else
  fail "Test 18f: erwartete Rettungs-Warnung fehlt im Log -- Output:
${ROUND_OUT}"
fi

T18_STATUS="$(git --git-dir="${T18_DIR}/origin.git" show main:board/stories/S-968-mock.yaml | grep '^status:')"
if [[ "$T18_STATUS" == "status: In Progress" ]]; then
  pass "Test 18g: S-968 bleibt 'In Progress' (Guard griff VOR jedem Board-Status-Schreibvorgang in block_round) -- Stale-Reclamation-Netz bleibt zustaendig"
else
  fail "Test 18g: unerwarteter remote-Status: ${T18_STATUS}"
fi

# ===========================================================================
echo ""
echo "--- Test 19 (S-131, AC9/AC11): guard_repo_root_clean() schliesst .claude/worktrees/ per Pathspec-Exclude aus -- Fehlalarm-Fix + Gegenprobe ---"

T19_DIR="${TEST_WORK_DIR}/t19"
T19_WORK="$(setup_fixture_no_worktree_gitignore "$T19_DIR")"
add_story "$T19_WORK" "S-971" "null"

# Reproduziert den Vorfall vom 2026-07-29: ein Zielprojekt OHNE eigenen
# .claude/worktrees/-Gitignore-Eintrag (anders als agent-flow selbst) +
# ein Loop-Schutz-N=3-Blocked-Ausgang (block_round() ruft
# guard_repo_root_clean() auf, waehrend der Story-Worktree noch existiert,
# s. board-round.sh:978). VOR dem Fix hielt der Guard den eigenen, gerade
# angelegten Story-Worktree faelschlich fuer eine fremde uncommittete
# Aenderung und brach das Skript komplett ab (Exit != 0), STATT den
# Blocked-Zustand regulaer zu setzen.
run_round "$T19_WORK" MOCK_REVIEWER_SEQUENCE=CR,CR,CR,CR

if [[ "$ROUND_RC" -eq 0 ]]; then
  pass "Test 19a: Exit 0 -- kein Guard-Fehlalarm auf den eigenen Story-Worktree trotz fehlendem .claude/worktrees/-Gitignore-Eintrag im Zielprojekt"
else
  fail "Test 19a: erwartete Exit 0 (regulaerer Blocked-Abschluss), bekam ${ROUND_RC} -- Output:
${ROUND_OUT}"
fi

if ! printf '%s' "$ROUND_OUT" | grep -q 'hat uncommittete Änderungen'; then
  pass "Test 19b: kein REPO_ROOT-Guard-Fehlalarm im Log (Pathspec-Exclude griff)"
else
  fail "Test 19b: unerwarteter Guard-Fehlalarm im Log -- Output:
${ROUND_OUT}"
fi

T19_SHOW="$(cd "$T19_WORK" && BOARD_DIR=board "$BOARD_SCRIPT" show S-971)"
if echo "$T19_SHOW" | grep -q '"status": "Blocked"' && echo "$T19_SHOW" | grep -q 'Loop-Schutz N=3'; then
  pass "Test 19c: S-971 korrekt Blocked mit 'Loop-Schutz N=3'-Grund (nicht durch Guard-Absturz verhindert)"
else
  fail "Test 19c: unerwarteter Board-Zustand: ${T19_SHOW}"
fi

# Gegenprobe (Zahnlos-Check): dasselbe verwundbare Zielprojekt (KEIN
# .claude/worktrees/-Gitignore-Eintrag), aber diesmal MIT einer ECHTEN
# fremden uncommitteten Änderung ausserhalb von .claude/worktrees/
# (simulierte Parallel-Session, wie Test 18) -- der Guard MUSS das
# weiterhin erkennen und blockieren; der Pathspec-Exclude betrifft NUR
# .claude/worktrees/.
T19G_DIR="${TEST_WORK_DIR}/t19-gegenprobe"
T19G_WORK="$(setup_fixture_no_worktree_gitignore "$T19G_DIR")"
add_story "$T19G_WORK" "S-972" "null"

run_round "$T19G_WORK" MOCK_REVIEWER_SEQUENCE=CR,CR,CR,CR "MOCK_DIRTY_REPO_ROOT=${T19G_WORK}"

if [[ "$ROUND_RC" -ne 0 ]]; then
  pass "Test 19d: Guard bleibt scharf -- echte fremde Änderung ausserhalb .claude/worktrees/ blockiert weiterhin (Exit != 0)"
else
  fail "Test 19d: erwartete Exit != 0 (echte fremde Änderung hätte blockieren müssen), bekam Exit 0 -- Output:
${ROUND_OUT}"
fi

if printf '%s' "$ROUND_OUT" | grep -q 'hat uncommittete Änderungen'; then
  pass "Test 19e: Fehlermeldung nennt weiterhin die uncommitteten Änderungen (echte fremde Datei bleibt erkannt)"
else
  fail "Test 19e: erwartete Guard-Fehlermeldung fehlt -- Output:
${ROUND_OUT}"
fi

T19G_STATUS="$(git --git-dir="${T19G_DIR}/origin.git" show main:board/stories/S-972-mock.yaml | grep '^status:')"
if [[ "$T19G_STATUS" == "status: In Progress" ]]; then
  pass "Test 19f: S-972 bleibt 'In Progress' (Guard griff VOR jedem Board-Status-Schreibvorgang, wie Test 18g)"
else
  fail "Test 19f: unerwarteter remote-Status: ${T19G_STATUS}"
fi

# ===========================================================================
echo ""
echo "--- Test 20 (S-132, AC7/AC9/AC11): Pflicht-Marker fehlt AUCH im Nudge-Redispatch -> block_round unveraendert wie vor dem Nudge-Fix ---"
T20_DIR="${TEST_WORK_DIR}/t20"
T20_WORK="$(setup_fixture "$T20_DIR")"
add_story "$T20_WORK" "S-973" "null"

run_round "$T20_WORK" MOCK_CODER_NO_MARKER_PERSIST=1
if [[ "$ROUND_RC" -eq 0 ]]; then
  pass "Test 20a: Exit 0 (Blocked ist regulärer Abschluss)"
else
  fail "Test 20a: erwartete Exit 0, bekam ${ROUND_RC} -- Output:
${ROUND_OUT}"
fi
T20_SHOW="$(cd "$T20_WORK" && BOARD_DIR=board "$BOARD_SCRIPT" show S-973)"
if echo "$T20_SHOW" | grep -q '"status": "Blocked"' && echo "$T20_SHOW" | grep -q "Nudge-Retry"; then
  pass "Test 20b: S-973 Blocked mit Hinweis auf den weiterhin fehlenden Marker nach dem Nudge-Retry"
else
  fail "Test 20b: unerwarteter Board-Zustand (erwartete Blocked mit Nudge-Retry-Hinweis): ${T20_SHOW}"
fi
T20_CODER_DISPATCHES="$(printf '%s\n' "$ROUND_OUT" | grep -c 'agent=coder' || true)"
if [[ "$T20_CODER_DISPATCHES" -eq 2 ]]; then
  pass "Test 20c: coder wurde genau zweimal dispatcht (Original + der EINE Nudge-Redispatch, kein dritter Versuch)"
else
  fail "Test 20c: erwartete genau 2 coder-Dispatches, gezählt ${T20_CODER_DISPATCHES} -- Output:
${ROUND_OUT}"
fi
T20_REVIEWER_CALLS="$(printf '%s\n' "$ROUND_OUT" | grep -c 'agent=reviewer' || true)"
if [[ "$T20_REVIEWER_CALLS" -eq 0 ]]; then
  pass "Test 20d: reviewer wurde NICHT dispatcht (Eskalation erfolgte VOR dem Review-Schritt, auch nach dem Nudge)"
else
  fail "Test 20d: reviewer wurde trotz weiterhin fehlendem Marker dispatcht (${T20_REVIEWER_CALLS}x) -- stilles Weiterlaufen"
fi

# ===========================================================================
echo ""
echo "=============================="
echo "Ergebnis: ${PASS} PASS, ${FAIL} FAIL"
echo "=============================="

if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
exit 0
