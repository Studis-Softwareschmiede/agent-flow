#!/usr/bin/env bash
# tests/board-feature-drain/run-test.sh
#
# Self-Test für scripts/board-feature-drain.sh (Feature-Schicht der
# 3-Ebenen-Orchestrierung, Owner-Konzept 2026-07-06).
#
# Covers:
#   Schwelle — < 2 Storys: Skript verweigert sich mit klarer Meldung (Test 1).
#   Feature-Branch-Anlage — wird von origin/main abgezweigt, falls neu (Test 2).
#   Story-für-Story-Schleife — jede Runde ruft eine frische "Story-Sitzung"
#     (hier: gemockt via BOARD_FEATURE_DRAIN_CLAUDE_CMD) auf, landet NUR im
#     Feature-Branch, kein main-Merge pro Story (Test 2).
#   Blockade-Verhalten (Owner-Entscheidung 2026-07-06: warten, kein Timeout,
#     kein Teil-Deploy) — Exit 3 + klare Diagnose (Test 3).
#   Finaler Merge — nach der letzten Story EIN Merge Feature-Branch → main
#     + Board zeigt alle Storys Done (Test 2), idempotent bei Wiederholung
#     (Test 4).
#
# Covers (docs/specs/feature-batch-orchestration.md — v2 Run-State):
#   AC9  — Run-State-Anlage & -Aktualisierung: state.yaml entsteht zu
#     Drain-Start und wird bei Phasenwechsel + Runden-/Story-Wechsel
#     aktualisiert; last_error bei Exit != 0 gesetzt (Test 9, Test 11).
#   AC10 — state.yaml-Schema-Vertrag: exakt die vertraglichen Felder mit
#     zulässigen Werten (phase-Enum, progress done/total, ISO-8601, S-###
#     oder null, String oder null) (Test 9).
#   AC11 — board/runs/ ist gitignored: nie in git status als zu committende
#     Änderung, kein Commit von Run-Artefakten (Test 9, Test 10, Test 12).
#   AC12 — Last-Run-Eindampfung nach erfolgreichem finalen Merge: state.yaml
#     kompakt (Endphase, total/total), Zwischen-Arbeitsdateien entfernt;
#     erneuter Drain-Start überschreibt statt anzuhäufen (Test 10). E6
#     (abgebrochener Run OHNE Merge) dampft NICHT ein (Test 11).
#
# Verwendet lokale /tmp-Git-Fixtures (bare "origin" + Arbeits-Klon), einen
# gemockten `gh` (wie tests/board-ship) und einen gemockten "claude"-Aufruf,
# der EINE Story pro Aufruf simuliert (board set Done + Commit + Push in den
# Feature-Branch — genau das, was `/flow --parent` + `board-ship.sh
# --target-branch` in echt tun). Berührt NIEMALS echtes GitHub oder Claude.
#
# Exit: 0 = alle Tests bestanden, 1 = mindestens ein Fehler

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
DRAIN_SCRIPT="${REPO_ROOT}/scripts/board-feature-drain.sh"
BOARD_SCRIPT="${REPO_ROOT}/scripts/board"
SHIP_SCRIPT="${REPO_ROOT}/scripts/board-ship.sh"

TEST_WORK_DIR="$(mktemp -d /tmp/board-feature-drain-test.XXXXXX)"
trap 'rm -rf "$TEST_WORK_DIR"' EXIT

FAIL=0
PASS=0
fail() { echo "FAIL: $*" >&2; FAIL=$((FAIL + 1)); }
pass() { echo "PASS: $*"; PASS=$((PASS + 1)); }

export BOARD_SHIP_SKIP_GH_AUTH=1
export GIT_AUTHOR_NAME="test" GIT_AUTHOR_EMAIL="test@test.local"
export GIT_COMMITTER_NAME="test" GIT_COMMITTER_EMAIL="test@test.local"

# --- Gemockter `gh` — identisch zu tests/board-ship, CI immer grün ---
MOCK_BIN_DIR="${TEST_WORK_DIR}/mockbin"
mkdir -p "$MOCK_BIN_DIR"
cat > "${MOCK_BIN_DIR}/gh" <<'MOCKEOF'
#!/usr/bin/env bash
if [[ "$1" == "run" && "$2" == "list" ]]; then
  branch=""
  for ((i=1; i<=$#; i++)); do
    [[ "${!i}" == "--branch" ]] && { j=$((i+1)); branch="${!j}"; break; }
  done
  for a in "$@"; do
    case "$a" in
      *headSha*) echo "$(git rev-parse "origin/${branch}" 2>/dev/null)"; exit 0 ;;
      *'.status'*) echo "completed"; exit 0 ;;
      *conclusion*) echo "success"; exit 0 ;;
    esac
  done
  echo ""; exit 0
fi
exit 0
MOCKEOF
chmod +x "${MOCK_BIN_DIR}/gh"
export PATH="${MOCK_BIN_DIR}:${PATH}"

# --- Gemockter "claude"-Aufruf: simuliert EINE Story-Sitzung -----------------
# Nimmt "-p" "/agent-flow:flow --parent F-###" entgegen, ermittelt per echtem
# `board next --parent` die nächste bereite Story (dieselbe Queue-Logik wie
# in echt). Erfolgsfall: simuliert coder→reviewer→tester, landet dann über
# das ECHTE, bereits separat getestete board-ship.sh --target-branch (kein
# Nachbau der Merge-Logik im Mock — höhere Testtreue, echte Integration).
# Blockade-Fall: kein Code zu landen (Loop-Schutz griff vor tester-PASS) —
# nur der Board-Status wird direkt in den Feature-Branch committet/gepusht,
# genau wie ein echter Blocked-Ausgang keinen board-ship.sh-Lauf auslöst.
MOCK_CLAUDE="${TEST_WORK_DIR}/mock-claude.sh"
cat > "$MOCK_CLAUDE" <<MOCKCLAUDE
#!/usr/bin/env bash
set -euo pipefail
# Argumente: -p "/agent-flow:flow --parent F-###" --dangerously-skip-permissions
PROMPT="\$2"
FID="\$(echo "\$PROMPT" | grep -oE 'F-[0-9]+')"
NEXT_JSON="\$(bash "$BOARD_SCRIPT" next --parent "\$FID" 2>/dev/null || true)"
[[ -n "\$NEXT_JSON" ]] || { echo "[mock-claude] nichts bereit für \$FID"; exit 0; }
SID="\$(echo "\$NEXT_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')"

git fetch origin "\${BOARD_MOCK_FEATURE_BRANCH}" --quiet
git checkout -B "\${BOARD_MOCK_FEATURE_BRANCH}" "origin/\${BOARD_MOCK_FEATURE_BRANCH}" --quiet

if [[ "\${MOCK_STORY_TO_BLOCK:-}" == "\$SID" ]]; then
  BOARD_WRITER=flow bash "$BOARD_SCRIPT" set "\$SID" status Blocked --reason "Test-Blockade"
  git add board/ && git commit -q -m "chore(board): \$SID Blocked (Test)"
  git push origin "\${BOARD_MOCK_FEATURE_BRANCH}" --quiet
  exit 0
fi

if [[ "\${MOCK_STORY_TO_ORPHAN:-}" == "\$SID" ]] && [[ ! -f "\${MOCK_ORPHAN_MARKER}" ]]; then
  touch "\${MOCK_ORPHAN_MARKER}"
  BOARD_WRITER=flow bash "$BOARD_SCRIPT" set "\$SID" status "In Progress" --reason "Test: simulierte unterbrochene Sitzung"
  git add board/ && git commit -q -m "chore(board): \$SID In Progress (Test-Unterbrechung)"
  git push origin "\${BOARD_MOCK_FEATURE_BRANCH}" --quiet
  exit 0
fi

git checkout -q -b "feat/\${SID}-mock"
echo "story \$SID" >> "story-\${SID}.txt"
git add -A
git commit -q -m "\$SID: simulierte Story-Arbeit"
bash "$SHIP_SCRIPT" "\$SID" --target-branch "\${BOARD_MOCK_FEATURE_BRANCH}"
MOCKCLAUDE
chmod +x "$MOCK_CLAUDE"
export BOARD_FEATURE_DRAIN_CLAUDE_CMD="$MOCK_CLAUDE"

# --- Fixture-Aufbau: bare "origin" + Arbeits-Klon mit Board + Profil ---------
setup_fixture() {
  local dir="$1" n_stories="$2"
  local origin="${dir}/origin.git"
  local work="${dir}/work"

  git init --bare -q "$origin"
  git init -q "$work"
  (
    cd "$work"
    git remote add origin "$origin"
    mkdir -p board/features board/stories docs/specs .claude
    cat > board/board.yaml <<YAML
schema_version: 1
project_slug: test-proj
next_feature_id: 2
next_story_id: 901
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
    for i in $(seq 1 "$n_stories"); do
      sid="S-90${i}"
      cat > "board/stories/${sid}-test.yaml" <<YAML
id: ${sid}
parent: F-001
title: Test-Story ${i}
status: To Do
priority: P2
spec: null
implements: null
depends: null
labels: null
branch: null
pr: null
created_at: '2026-01-01T00:00:00Z'
updated_at: '2026-01-01T00:00:00Z'
done_at: null
YAML
    done
    cat > .claude/profile.md <<'YAML'
---
language: md
merge_policy: direct
deploy: none
default_branch: main
---
Test-Profil.
YAML
    # AC11 (board/runs/ ist gitignored) — echtes Repo-Verhalten in der Fixture
    # nachbilden, sonst meldet guard_clean_or_die() in board-ship.sh das
    # untracked board/runs/<F-###>/state.yaml fälschlich als "dirty".
    cat > .gitignore <<'GITIGNORE'
board/runs/
GITIGNORE
    git add -A
    git commit -q -m "initial board setup"
    git branch -M main
    git push -q origin main
  )
  echo "$work"
}

# ===========================================================================
# Test 1 — Owner-Entscheidung 2026-07-06 (zweite Korrektur): KEINE Mindest-
# anzahl mehr — genau 1 Story läuft genauso durch wie mehrere.
# ===========================================================================
echo ""
echo "--- Test 1: genau 1 Story -> läuft durch (kein Mindest-Schwellen-Check mehr) ---"
T1_WORK="$(setup_fixture "${TEST_WORK_DIR}/test1" 1)"
export BOARD_MOCK_FEATURE_BRANCH="feature/F-001"
T1_MAIN_BEFORE="$(git -C "$T1_WORK" rev-parse origin/main)"
set +e
T1_OUTPUT="$(cd "$T1_WORK" && bash "$DRAIN_SCRIPT" F-001 2>&1)"
T1_EXIT=$?
set -e
if [[ $T1_EXIT -eq 0 ]]; then
  pass "Test 1a: genau 1 Story läuft ohne Fehler durch (exit 0)"
else
  fail "Test 1a: erwartete exit 0, bekam exit=${T1_EXIT}"
  echo "  Output: $T1_OUTPUT"
fi
T1_MAIN_AFTER="$(git -C "$T1_WORK" rev-parse origin/main)"
if [[ "$T1_MAIN_AFTER" != "$T1_MAIN_BEFORE" ]]; then
  pass "Test 1b: origin/main hat einen neuen Commit (der finale Merge der einzelnen Story)"
else
  fail "Test 1b: origin/main unverändert — kein Merge stattgefunden"
fi
T1_STATUS="$(git -C "$T1_WORK" show origin/main:board/stories/S-901-test.yaml 2>/dev/null | grep '^status:' || true)"
if echo "$T1_STATUS" | grep -q "Done"; then
  pass "Test 1c: die einzelne Story ist in main als Done sichtbar"
else
  fail "Test 1c: Story nicht Done (Status: ${T1_STATUS})"
fi

# ===========================================================================
# Test 2 — Happy Path: 3 Storys, alle laufen durch, EIN finaler Merge
# ===========================================================================
echo ""
echo "--- Test 2: 3 Storys komplett -> Feature-Branch angelegt, EIN finaler Merge ---"
T2_WORK="$(setup_fixture "${TEST_WORK_DIR}/test2" 3)"
export BOARD_MOCK_FEATURE_BRANCH="feature/F-001"
T2_MAIN_BEFORE="$(git -C "$T2_WORK" rev-parse origin/main)"
T2_OUTPUT="$(cd "$T2_WORK" && bash "$DRAIN_SCRIPT" F-001 2>&1)"
T2_EXIT=$?

if [[ $T2_EXIT -eq 0 ]]; then
  pass "Test 2a: Happy Path läuft ohne Fehler durch (exit 0)"
else
  fail "Test 2a: exit=${T2_EXIT}"
  echo "  Output: $T2_OUTPUT"
fi
if git -C "$T2_WORK" rev-parse origin/feature/F-001 >/dev/null 2>&1; then
  pass "Test 2b: Feature-Branch wurde angelegt"
else
  fail "Test 2b: Feature-Branch fehlt"
fi
T2_MAIN_AFTER="$(git -C "$T2_WORK" rev-parse origin/main)"
if [[ "$T2_MAIN_AFTER" != "$T2_MAIN_BEFORE" ]]; then
  pass "Test 2c: origin/main hat einen neuen Commit (der EINE finale Merge)"
else
  fail "Test 2c: origin/main unverändert"
fi
T2_DONE_COUNT="$(git -C "$T2_WORK" show origin/main --stat 2>/dev/null | grep -c "story-S-90" || true)"
ALL_DONE=1
for i in 1 2 3; do
  ST="$(cd "$T2_WORK" && git show "origin/main:board/stories/S-90${i}-test.yaml" | grep '^status:')"
  [[ "$ST" == "status: Done" ]] || ALL_DONE=0
done
if [[ "$ALL_DONE" -eq 1 ]]; then
  pass "Test 2d: alle 3 Storys sind in main als Done sichtbar"
else
  fail "Test 2d: nicht alle Storys sind in main Done"
fi

# ===========================================================================
# Test 3 — Blockade: eine Story bleibt Blocked -> Exit 3, kein Teil-Deploy
# ===========================================================================
echo ""
echo "--- Test 3: eine Story Blocked -> Exit 3, kein Merge, kein Teil-Deploy ---"
T3_WORK="$(setup_fixture "${TEST_WORK_DIR}/test3" 3)"
export BOARD_MOCK_FEATURE_BRANCH="feature/F-001"
export MOCK_STORY_TO_BLOCK="S-902"
T3_MAIN_BEFORE="$(git -C "$T3_WORK" rev-parse origin/main)"
set +e
T3_OUTPUT="$(cd "$T3_WORK" && bash "$DRAIN_SCRIPT" F-001 2>&1)"
T3_EXIT=$?
set -e
unset MOCK_STORY_TO_BLOCK

if [[ $T3_EXIT -eq 3 ]] && echo "$T3_OUTPUT" | grep -q "BLOCKIERT: S-902"; then
  pass "Test 3a: Exit 3 mit korrekter Blockade-Diagnose (S-902)"
else
  fail "Test 3a: erwartete Exit 3 mit BLOCKIERT-Meldung, bekam exit=${T3_EXIT}"
  echo "  Output: $T3_OUTPUT"
fi
T3_MAIN_AFTER="$(git -C "$T3_WORK" rev-parse origin/main)"
if [[ "$T3_MAIN_AFTER" == "$T3_MAIN_BEFORE" ]]; then
  pass "Test 3b: origin/main unverändert — kein Teil-Deploy trotz 2 fertiger Storys"
else
  fail "Test 3b: origin/main hat sich verändert, obwohl das Feature blockiert war"
fi

# ===========================================================================
# Test 4 — Idempotenz: erneuter Aufruf nach komplettem Feature ist ein No-Op
# ===========================================================================
echo ""
echo "--- Test 4: erneuter Aufruf nach komplettem Feature ist idempotent ---"
export BOARD_MOCK_FEATURE_BRANCH="feature/F-001"
T4_MAIN_BEFORE="$(git -C "$T2_WORK" rev-parse origin/main)"
T4_OUTPUT="$(cd "$T2_WORK" && bash "$DRAIN_SCRIPT" F-001 2>&1)"
T4_EXIT=$?
T4_MAIN_AFTER="$(git -C "$T2_WORK" rev-parse origin/main)"

if [[ $T4_EXIT -eq 0 ]] && [[ "$T4_MAIN_AFTER" == "$T4_MAIN_BEFORE" ]]; then
  pass "Test 4: wiederholter Aufruf ist idempotent (exit 0, kein neuer Commit)"
else
  fail "Test 4: nicht idempotent (exit=${T4_EXIT}, main geändert=$([ "$T4_MAIN_AFTER" != "$T4_MAIN_BEFORE" ] && echo ja || echo nein))"
  echo "  Output: $T4_OUTPUT"
fi

# ===========================================================================
# Test 5 — Regression 2026-07-06 (Owner-Testlauf F-065, dev-gui): profile.md
# OHNE default_branch-Feld (echte dev-gui-Form) darf nicht zum stillen
# Abbruch fuehren (set -e + pipefail auf grep-ohne-Treffer).
# ===========================================================================
echo ""
echo "--- Test 5: profile.md ohne default_branch-Feld -> kein stiller Abbruch ---"
T5_WORK="$(setup_fixture "${TEST_WORK_DIR}/test5" 2)"
cat > "${T5_WORK}/.claude/profile.md" <<'PLAIN'
language: js
merge_policy: direct
deploy: none
PLAIN
(
  cd "$T5_WORK"
  git add -A && git commit -q -m "profile.md ohne default_branch (Regressionsfixture)"
  git push -q origin main
)
export BOARD_MOCK_FEATURE_BRANCH="feature/F-001"
T5_OUTPUT="$(cd "$T5_WORK" && bash "$DRAIN_SCRIPT" F-001 2>&1)"
T5_EXIT=$?
if [[ $T5_EXIT -eq 0 ]]; then
  pass "Test 5: kein stiller Abbruch trotz fehlendem default_branch-Feld — Fallback auf 'main' griff"
else
  fail "Test 5: Skript brach ab (exit=${T5_EXIT}) statt auf 'main' zurückzufallen"
  echo "  Output: $T5_OUTPUT"
fi

# ===========================================================================
# Test 6 — Regression 2026-07-06 (Owner-Testlauf F-065/S-299): eine Story
# bleibt "In Progress" (liegengeblieben durch eine unterbrochene Sitzung,
# KEINE echte Blockade) -> wird automatisch auf "To Do" zurückgesetzt und
# im selben Lauf sofort erneut versucht, statt fälschlich "BLOCKIERT" zu
# melden.
# ===========================================================================
echo ""
echo "--- Test 6: liegengebliebene 'In Progress'-Story wird automatisch zurückgesetzt und fertig ---"
T6_WORK="$(setup_fixture "${TEST_WORK_DIR}/test6" 3)"
export BOARD_MOCK_FEATURE_BRANCH="feature/F-001"
export MOCK_STORY_TO_ORPHAN="S-902"
export MOCK_ORPHAN_MARKER="${TEST_WORK_DIR}/test6-orphan-marker"
rm -f "$MOCK_ORPHAN_MARKER"
set +e
T6_OUTPUT="$(cd "$T6_WORK" && bash "$DRAIN_SCRIPT" F-001 2>&1)"
T6_EXIT=$?
set -e
unset MOCK_STORY_TO_ORPHAN MOCK_ORPHAN_MARKER

if [[ $T6_EXIT -eq 0 ]] && echo "$T6_OUTPUT" | grep -q "liegengebliebene Story"; then
  pass "Test 6a: liegengebliebene Story wurde erkannt und automatisch zurückgesetzt (kein manueller Eingriff nötig)"
else
  fail "Test 6a: erwartete exit 0 mit Hinweis auf liegengebliebene Story, bekam exit=${T6_EXIT}"
  echo "  Output: $T6_OUTPUT"
fi
if ! echo "$T6_OUTPUT" | grep -q "^BLOCKIERT:"; then
  pass "Test 6b: KEINE fälschliche BLOCKIERT-Meldung (das war genau der Vorfall)"
else
  fail "Test 6b: Feature wurde fälschlich als BLOCKIERT gemeldet, obwohl keine echte Blockade vorlag"
  echo "  Output: $T6_OUTPUT"
fi
T6_MAIN_S902_STATUS="$(git -C "$T6_WORK" show origin/main:board/stories/S-902-test.yaml 2>/dev/null | grep '^status:' || true)"
if echo "$T6_MAIN_S902_STATUS" | grep -q "Done"; then
  pass "Test 6c: S-902 ist trotz der Unterbrechung am Ende korrekt Done"
else
  fail "Test 6c: S-902 ist NICHT Done nach dem automatischen Retry (Status: ${T6_MAIN_S902_STATUS})"
fi

# ===========================================================================
# Test 7 — Regression 2026-07-06 (Owner-Feedback, dritte Runde): eine "To Do"-
# Story, die durch das Depends-Gate blockiert ist (Abhängigkeit in einem
# ANDEREN Feature, noch nicht terminal), muss eine konkrete Erklärung liefern
# statt eines nichtssagenden "BLOCKIERT" — der Button sprang sonst lautlos
# zurück auf "Umsetzen", ohne den Owner zu informieren.
# ===========================================================================
echo ""
echo "--- Test 7: Depends-Gate (Abhängigkeit in anderem Feature) -> konkrete Erklärung statt stillem BLOCKIERT ---"
T7C_WORK="$(setup_fixture "${TEST_WORK_DIR}/test7c" 1)"
(
  cd "$T7C_WORK"
  cat > board/features/F-002-other.yaml <<'YAML'
id: F-002
title: Anderes Feature
goal: Test
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
  cat > board/stories/S-800-dependency.yaml <<'YAML'
id: S-800
parent: F-002
title: Voraussetzung in anderem Feature
status: To Do
priority: P2
spec: null
implements: null
depends: null
labels: null
branch: null
pr: null
created_at: '2026-01-01T00:00:00Z'
updated_at: '2026-01-01T00:00:00Z'
done_at: null
YAML
  python3 -c "
import re
path = 'board/stories/S-901-test.yaml'
with open(path) as f:
    content = f.read()
content = content.replace('depends: null', 'depends:\n- S-800')
with open(path, 'w') as f:
    f.write(content)
"
  git add -A
  git commit -q -m "Test-Fixture: Depends-Gate über Feature-Grenze"
  git push -q origin main
)
set +e
T7C_OUTPUT="$(cd "$T7C_WORK" && bash "$DRAIN_SCRIPT" F-001 2>&1)"
T7C_EXIT=$?
set -e
if [[ $T7C_EXIT -eq 3 ]] && echo "$T7C_OUTPUT" | grep -q "WARTET:.*S-901 wartet auf S-800.*F-002"; then
  pass "Test 7: konkrete Depends-Gate-Erklärung statt stillem BLOCKIERT (nennt S-800 + F-002)"
else
  fail "Test 7: erwartete WARTET-Meldung mit S-800/F-002, bekam exit=${T7C_EXIT}"
  echo "  Output: $T7C_OUTPUT"
fi

# ===========================================================================
# Test 8 — Regression 2026-07-06 (Owner-Testlauf, vierte Runde): eine ANDERE,
# aktive dev-gui-Automatisierung hat im geteilten Arbeitsbaum eine noch nicht
# committete Datei liegen, die mit dem Feature-Branch kollidiert -> `git
# checkout` verweigert zu Recht. Statt eines kryptischen Git-Fehlers muss
# board-feature-drain.sh das erkennen, ein paar Mal erneut versuchen und bei
# fortbestehender Blockade klar (nicht roh) melden.
# ===========================================================================
echo ""
echo "--- Test 8: geteilter Arbeitsbaum durch andere Sitzung blockiert -> klare WARTET-Meldung statt rohem Git-Fehler ---"
T8_WORK="$(setup_fixture "${TEST_WORK_DIR}/test8" 2)"
(
  cd "$T8_WORK"
  git push -q origin "origin/main:refs/heads/feature/F-001"
  git fetch -q origin feature/F-001
  git checkout -q -b feature/F-001-setup "origin/feature/F-001"
  echo "vom-branch-committet" > conflict.txt
  git add conflict.txt
  git commit -q -m "Feature-Branch: conflict.txt committet"
  git push -q origin "feature/F-001-setup:feature/F-001"
  git checkout -q main
  git branch -q -D feature/F-001-setup
  echo "andere-sitzung-unfertig" > conflict.txt
)
export BOARD_FEATURE_DRAIN_SYNC_RETRIES=2
export BOARD_FEATURE_DRAIN_SYNC_SLEEP=0
set +e
T8_OUTPUT="$(cd "$T8_WORK" && bash "$DRAIN_SCRIPT" F-001 2>&1)"
T8_EXIT=$?
set -e
unset BOARD_FEATURE_DRAIN_SYNC_RETRIES BOARD_FEATURE_DRAIN_SYNC_SLEEP
if [[ $T8_EXIT -eq 3 ]] && echo "$T8_OUTPUT" | grep -q "WARTET: Arbeitsverzeichnis wird von einer anderen"; then
  pass "Test 8: klare WARTET-Meldung statt rohem Git-Fehlertext, kein Crash"
else
  fail "Test 8: erwartete klare WARTET-Meldung, bekam exit=${T8_EXIT}"
  echo "  Output: $T8_OUTPUT"
fi
if [[ -f "${T8_WORK}/conflict.txt" ]] && grep -q "andere-sitzung-unfertig" "${T8_WORK}/conflict.txt"; then
  pass "Test 8b: die fremde, unfertige Datei der anderen Sitzung wurde NICHT angetastet"
else
  fail "Test 8b: die fremde Datei wurde verändert/gelöscht — Datenverlust-Risiko"
fi

# ===========================================================================
# Test 9 — AC9/AC10/AC11: Happy Path (2 Storys) erzeugt state.yaml mit dem
# vertraglichen Schema (Endphase rollout, progress total/total, ISO-8601-
# Zeitstempel, current_story null außerhalb story-Phase, last_error null) —
# und board/runs/ erscheint NIE in git status (weder Working-Tree noch
# origin/main nach dem finalen Merge).
# ===========================================================================
echo ""
echo "--- Test 9: state.yaml nach Happy Path entspricht dem AC10-Schema, board/runs/ bleibt gitignored (AC11) ---"
T9_WORK="$(setup_fixture "${TEST_WORK_DIR}/test9" 2)"
export BOARD_MOCK_FEATURE_BRANCH="feature/F-001"
T9_OUTPUT="$(cd "$T9_WORK" && bash "$DRAIN_SCRIPT" F-001 2>&1)"
T9_EXIT=$?
if [[ $T9_EXIT -eq 0 ]]; then
  pass "Test 9a: Happy Path (2 Storys) läuft ohne Fehler durch"
else
  fail "Test 9a: exit=${T9_EXIT}"
  echo "  Output: $T9_OUTPUT"
fi

T9_STATE="${T9_WORK}/board/runs/F-001/state.yaml"
if [[ -f "$T9_STATE" ]]; then
  pass "Test 9b: board/runs/F-001/state.yaml wurde angelegt"
else
  fail "Test 9b: state.yaml fehlt (Pfad: ${T9_STATE})"
fi

T9_SCHEMA_OK="$(python3 - "$T9_STATE" <<'PYEOF'
import sys, yaml, re
with open(sys.argv[1]) as f:
    d = yaml.safe_load(f)
errs = []
if d.get("schema_version") != 1:
    errs.append(f"schema_version={d.get('schema_version')!r} (erwartet 1)")
if d.get("feature_id") != "F-001":
    errs.append(f"feature_id={d.get('feature_id')!r} (erwartet F-001)")
if d.get("phase") not in ("dossier", "story", "merge", "rollout"):
    errs.append(f"phase={d.get('phase')!r} nicht im Enum")
if d.get("phase") != "rollout":
    errs.append(f"phase={d.get('phase')!r} (erwartet 'rollout' nach erfolgreichem Merge)")
prog = d.get("progress") or {}
if not isinstance(prog.get("done"), int) or not isinstance(prog.get("total"), int):
    errs.append(f"progress done/total nicht beide int: {prog!r}")
elif prog.get("done") != prog.get("total"):
    errs.append(f"progress {prog!r} (erwartet done==total nach erfolgreichem Merge)")
if d.get("current_story") is not None:
    errs.append(f"current_story={d.get('current_story')!r} (erwartet null außerhalb story-Phase)")
iso_re = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$")
for field in ("started_at", "updated_at"):
    val = d.get(field)
    if not isinstance(val, str) or not iso_re.match(val):
        errs.append(f"{field}={val!r} ist kein ISO-8601-UTC-Zeitstempel")
if d.get("last_error") is not None:
    errs.append(f"last_error={d.get('last_error')!r} (erwartet null nach Erfolg)")
if errs:
    print("FEHLER: " + "; ".join(errs))
else:
    print("OK")
PYEOF
)"
if [[ "$T9_SCHEMA_OK" == "OK" ]]; then
  pass "Test 9c: state.yaml entspricht exakt dem AC10-Schema (Endphase rollout, done==total, ISO-8601, current_story null, last_error null)"
else
  fail "Test 9c: Schema-Abweichung — ${T9_SCHEMA_OK}"
  cat "$T9_STATE"
fi

T9_STATUS_PORCELAIN="$(cd "$T9_WORK" && git status --porcelain)"
if [[ -z "$T9_STATUS_PORCELAIN" ]]; then
  pass "Test 9d: git status im Working-Tree ist sauber — board/runs/ erscheint nirgends als zu committende Änderung (AC11)"
else
  fail "Test 9d: git status ist NICHT sauber — Run-Artefakt wurde offenbar getrackt: ${T9_STATUS_PORCELAIN}"
fi

if cd "$T9_WORK" && git show origin/main --stat 2>/dev/null | grep -q "board/runs"; then
  fail "Test 9e: der finale Merge-Commit nach main enthält Run-Artefakte (board/runs/) — AC11 verletzt"
else
  pass "Test 9e: der finale Merge-Commit nach main enthält KEINE Run-Artefakte (AC11)"
fi

# ===========================================================================
# Test 10 — AC12: Last-Run-Eindampfung. Nach erfolgreichem finalem Merge
# bleibt state.yaml als kompaktes Protokoll stehen; ein erneuter Drain-Start
# desselben (bereits fertigen) Features überschreibt es mit einem frischen
# Run statt alte Zwischenstände anzuhäufen (kein Wachstum).
# ===========================================================================
echo ""
echo "--- Test 10: Last-Run-Eindampfung nach Merge + erneuter Lauf überschreibt (kein Anhäufen) ---"
T10_RUN_DIR="${T2_WORK}/board/runs/F-001"
if [[ -f "${T10_RUN_DIR}/state.yaml" ]]; then
  pass "Test 10a: state.yaml existiert nach dem Happy-Path-Lauf aus Test 2 (bereits terminaler Merge)"
else
  fail "Test 10a: state.yaml fehlt nach Test 2 — Voraussetzung für Eindampfungs-Check nicht gegeben"
fi
if [[ ! -f "${T10_RUN_DIR}/dossier.md" && ! -f "${T10_RUN_DIR}/notes.md" ]]; then
  pass "Test 10b: keine Zwischen-Arbeitsdateien (dossier.md/notes.md) nach erfolgreichem Merge übrig (Eindampfung)"
else
  fail "Test 10b: dossier.md/notes.md sind nach dem Merge noch vorhanden — keine Eindampfung"
fi

T10_ROUND_BEFORE="$(python3 -c "import yaml; print(yaml.safe_load(open('${T10_RUN_DIR}/state.yaml'))['round'])")"
T10_UPDATED_BEFORE="$(python3 -c "import yaml; print(yaml.safe_load(open('${T10_RUN_DIR}/state.yaml'))['updated_at'])")"

# Test 4 (oben) hat bereits einen zweiten, idempotenten Lauf auf T2_WORK
# ausgeführt — state.yaml muss dabei NEU geschrieben worden sein (frischer
# updated_at/round), nicht additiv gewachsen.
T10_ROUND_AFTER="$(python3 -c "import yaml; print(yaml.safe_load(open('${T10_RUN_DIR}/state.yaml'))['round'])")"
T10_UPDATED_AFTER="$(python3 -c "import yaml; print(yaml.safe_load(open('${T10_RUN_DIR}/state.yaml'))['updated_at'])")"
if [[ "$T10_ROUND_AFTER" -le 1 ]]; then
  pass "Test 10c: erneuter (idempotenter) Drain-Start startet mit frischem round-Zähler (kein Anhäufen über Läufe hinweg)"
else
  fail "Test 10c: round=${T10_ROUND_AFTER} nach erneutem Lauf — deutet auf Anhäufung/Fortsetzung statt frischem Run hin"
fi
T10_STATE_SIZE_LINES="$(wc -l < "${T10_RUN_DIR}/state.yaml")"
if [[ "$T10_STATE_SIZE_LINES" -le 12 ]]; then
  pass "Test 10d: state.yaml bleibt kompakt (${T10_STATE_SIZE_LINES} Zeilen) — kein Wachstum über Läufe hinweg"
else
  fail "Test 10d: state.yaml ist unerwartet groß (${T10_STATE_SIZE_LINES} Zeilen)"
fi

# ===========================================================================
# Test 11 — AC9 last_error + E6: bricht das Feature MIT einer echten Blockade
# ab (Exit 3, kein Merge), MUSS state.yaml last_error mit einer Klartext-
# Zeile setzen — UND darf NICHT eingedampft werden (E6: kein erfolgreicher
# Merge -> Eindampfung greift nicht, Zwischenstände bleiben für Diagnose).
# ===========================================================================
echo ""
echo "--- Test 11: last_error bei Blockade gesetzt (AC9) + KEINE Eindampfung ohne Merge (E6) ---"
T11_WORK="$(setup_fixture "${TEST_WORK_DIR}/test11" 3)"
export BOARD_MOCK_FEATURE_BRANCH="feature/F-001"
export MOCK_STORY_TO_BLOCK="S-902"
set +e
T11_OUTPUT="$(cd "$T11_WORK" && bash "$DRAIN_SCRIPT" F-001 2>&1)"
T11_EXIT=$?
set -e
unset MOCK_STORY_TO_BLOCK

T11_STATE="${T11_WORK}/board/runs/F-001/state.yaml"
if [[ $T11_EXIT -eq 3 && -f "$T11_STATE" ]]; then
  pass "Test 11a: state.yaml existiert trotz (bzw. gerade wegen) der Blockade"
else
  fail "Test 11a: erwartete Exit 3 mit vorhandenem state.yaml, bekam exit=${T11_EXIT}"
fi

T11_LAST_ERROR="$(python3 -c "import yaml; print(yaml.safe_load(open('${T11_STATE}'))['last_error'])" 2>/dev/null || echo "<lesefehler>")"
if [[ -n "$T11_LAST_ERROR" && "$T11_LAST_ERROR" != "None" ]]; then
  pass "Test 11b: last_error ist eine Klartext-Zeile (nicht null) nach Exit != 0 — '${T11_LAST_ERROR}'"
else
  fail "Test 11b: last_error ist null/leer trotz Exit 3 — ${T11_LAST_ERROR}"
fi

T11_PHASE="$(python3 -c "import yaml; print(yaml.safe_load(open('${T11_STATE}'))['phase'])" 2>/dev/null || echo "<lesefehler>")"
if [[ "$T11_PHASE" != "rollout" ]]; then
  pass "Test 11c: phase ist NICHT 'rollout' (E6 — kein erfolgreicher Merge, keine Eindampfung auf Endphase)"
else
  fail "Test 11c: phase ist 'rollout', obwohl das Feature blockiert abgebrochen ist (E6 verletzt)"
fi

# ===========================================================================
# Test 12 — AC11: board/runs/ bleibt auch im Feature-Branch selbst (nicht nur
# main) niemals ein zu committendes Artefakt — der Feature-Drain committet
# während der gesamten Story-Schleife nichts aus board/runs/.
# ===========================================================================
echo ""
echo "--- Test 12: Feature-Branch enthält zu keinem Zeitpunkt Run-Artefakte aus board/runs/ (AC11) ---"
if cd "$T9_WORK" && git log origin/feature/F-001 --name-only 2>/dev/null | grep -q "board/runs"; then
  fail "Test 12: mindestens ein Commit im Feature-Branch enthält board/runs/ — AC11 verletzt"
else
  pass "Test 12: kein Commit im Feature-Branch enthält board/runs/ (AC11)"
fi

# ===========================================================================
# Ergebnis
# ===========================================================================
echo ""
echo "=============================="
echo "Ergebnis: ${PASS} PASS, ${FAIL} FAIL"
echo "=============================="

if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
exit 0
