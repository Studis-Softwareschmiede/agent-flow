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
    git add -A
    git commit -q -m "initial board setup"
    git branch -M main
    git push -q origin main
  )
  echo "$work"
}

# ===========================================================================
# Test 1 — Schwelle: < 2 Storys verweigert das Skript
# ===========================================================================
echo ""
echo "--- Test 1: < 2 Storys -> Skript verweigert sich ---"
T1_WORK="$(setup_fixture "${TEST_WORK_DIR}/test1" 1)"
set +e
T1_OUTPUT="$(cd "$T1_WORK" && bash "$DRAIN_SCRIPT" F-001 2>&1)"
T1_EXIT=$?
set -e
if [[ $T1_EXIT -ne 0 ]] && echo "$T1_OUTPUT" | grep -q "Bündelung bringt hier keinen Vorteil"; then
  pass "Test 1: verweigert sich klar bei nur 1 Story"
else
  fail "Test 1: kein klarer Abbruch (exit=${T1_EXIT})"
  echo "  Output: $T1_OUTPUT"
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
