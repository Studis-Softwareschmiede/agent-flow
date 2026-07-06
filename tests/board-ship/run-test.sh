#!/usr/bin/env bash
# tests/board-ship/run-test.sh
#
# Self-Test für scripts/board-ship.sh (L3 — deterministischer SHIP-Pfad,
# Owner-Auftrag 2026-07-06 nach dem S-047-Datenverlust-Vorfall).
#
# Covers:
#   L6-Guard — Working-Tree mit uncommitteten Änderungen: STOPP VOR jedem
#     git fetch/pull/reset, kein Datenverlust möglich (Test 1).
#   L3/echte Merge-Prüfung — bereits gemergter Commit wird per merge-base
#     erkannt (keine Behauptung übernommen), kein zweiter Merge-Versuch,
#     idempotent bei wiederholtem Aufruf (Test 2, Test 5).
#   Happy Path — merge_policy=direct, CI grün → Board-Flip auf Done mit
#     korrektem branch-Feld (Test 3).
#   CI-Gate — CI-Fehlschlag verhindert Board-Flip, Story bleibt NICHT Done
#     (Test 4).
#
# Verwendet lokale /tmp-Git-Fixtures (bare "origin" + Arbeits-Klon) und einen
# gemockten `gh` in PATH — berührt NIEMALS echtes GitHub oder das echte
# board/ des Repos.
#
# Exit: 0 = alle Tests bestanden, 1 = mindestens ein Fehler

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SHIP_SCRIPT="${REPO_ROOT}/scripts/board-ship.sh"
BOARD_SCRIPT="${REPO_ROOT}/scripts/board"

TEST_WORK_DIR="$(mktemp -d /tmp/board-ship-test.XXXXXX)"
trap 'rm -rf "$TEST_WORK_DIR"' EXIT

FAIL=0
PASS=0
fail() { echo "FAIL: $*" >&2; FAIL=$((FAIL + 1)); }
pass() { echo "PASS: $*"; PASS=$((PASS + 1)); }

export BOARD_SHIP_SKIP_GH_AUTH=1
export GIT_AUTHOR_NAME="test" GIT_AUTHOR_EMAIL="test@test.local"
export GIT_COMMITTER_NAME="test" GIT_COMMITTER_EMAIL="test@test.local"

# --- Gemockter `gh` — antwortet aus Env-Variablen, berührt nie echtes GitHub ---
MOCK_BIN_DIR="${TEST_WORK_DIR}/mockbin"
mkdir -p "$MOCK_BIN_DIR"
cat > "${MOCK_BIN_DIR}/gh" <<'MOCKEOF'
#!/usr/bin/env bash
if [[ "$1" == "run" && "$2" == "list" ]]; then
  for a in "$@"; do
    case "$a" in
      *headSha*) echo "${MOCK_HEAD_SHA:-}"; exit 0 ;;
      *'.status'*) echo "${MOCK_CI_STATUS:-completed}"; exit 0 ;;
      *conclusion*) echo "${MOCK_CI_CONCLUSION:-success}"; exit 0 ;;
    esac
  done
  echo ""
  exit 0
fi
if [[ "$1" == "pr" && "$2" == "create" ]]; then
  echo "https://github.com/mock/repo/pull/999"
  exit 0
fi
if [[ "$1" == "pr" && "$2" == "merge" ]]; then
  exit 0
fi
exit 0
MOCKEOF
chmod +x "${MOCK_BIN_DIR}/gh"
export PATH="${MOCK_BIN_DIR}:${PATH}"

# --- Fixture-Aufbau: bare "origin" + Arbeits-Klon mit Board + Profil ---
setup_fixture() {
  local dir="$1"
  local origin="${dir}/origin.git"
  local work="${dir}/work"

  git init --bare -q "$origin"

  git init -q "$work"
  (
    cd "$work"
    git remote add origin "$origin"
    mkdir -p board/features board/stories docs/specs .claude
    cat > board/board.yaml <<'YAML'
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
    cat > board/stories/S-900-test.yaml <<'YAML'
id: S-900
parent: F-001
title: Test-Story
status: In Review
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
# Test 1 — L6-Guard: uncommittete Änderungen STOPPEN vor jedem git-Zugriff
# ===========================================================================
echo ""
echo "--- Test 1: L6-Guard — uncommittete Änderungen brechen VOR git fetch/reset ab ---"
T1_WORK="$(setup_fixture "${TEST_WORK_DIR}/test1")"
(
  cd "$T1_WORK"
  git checkout -q -b feat/S-900-test
  echo "dirty" >> README-dirty.md
)
T1_REMOTE_BEFORE="$(git -C "$T1_WORK" rev-parse origin/main)"
set +e
T1_OUTPUT="$(cd "$T1_WORK" && bash "$SHIP_SCRIPT" S-900 2>&1)"
T1_EXIT=$?
set -e
T1_REMOTE_AFTER="$(git -C "$T1_WORK" rev-parse origin/main)"

if [[ $T1_EXIT -ne 0 ]] && echo "$T1_OUTPUT" | grep -q "uncommittete Änderungen"; then
  pass "Test 1a: Script bricht mit klarer Guard-Meldung ab bei dirty Working-Tree"
else
  fail "Test 1a: kein Guard-Abbruch erkannt (exit=$T1_EXIT)"
  echo "  Output: $T1_OUTPUT"
fi
if [[ "$T1_REMOTE_BEFORE" == "$T1_REMOTE_AFTER" ]]; then
  pass "Test 1b: origin/main unverändert — kein Datenzugriff vor dem Guard-Abbruch"
else
  fail "Test 1b: origin/main hat sich trotz Guard-Abbruch verändert!"
fi

# ===========================================================================
# Test 2 — echte Merge-Prüfung: bereits gemergter Commit wird per merge-base
# erkannt (Kern-Fix des S-047-Vorfalls: keine Behauptung, echte Prüfung)
# ===========================================================================
echo ""
echo "--- Test 2: bereits gemergter Commit wird per merge-base erkannt (kein zweiter Merge) ---"
T2_WORK="$(setup_fixture "${TEST_WORK_DIR}/test2")"
(
  cd "$T2_WORK"
  git checkout -q -b feat/S-900-test
  echo "feature" > feature.txt
  git add -A
  git commit -q -m "S-900: feature work"
  git checkout -q main
  git merge -q --no-ff feat/S-900-test -m "merge S-900"
  git push -q origin main
  git checkout -q feat/S-900-test   # zurück auf den (bereits gemergten) Story-Branch
)
export MOCK_HEAD_SHA MOCK_CI_STATUS="completed" MOCK_CI_CONCLUSION="success"
MOCK_HEAD_SHA="$(git -C "$T2_WORK" rev-parse origin/main)"
T2_OUTPUT="$(cd "$T2_WORK" && bash "$SHIP_SCRIPT" S-900 2>&1)"
T2_EXIT=$?

if [[ $T2_EXIT -eq 0 ]] && echo "$T2_OUTPUT" | grep -q "bereits gemergt"; then
  pass "Test 2a: bereits gemergter Commit korrekt per merge-base erkannt"
else
  fail "Test 2a: 'bereits gemergt' nicht erkannt (exit=$T2_EXIT)"
  echo "  Output: $T2_OUTPUT"
fi
T2_STATUS="$(grep '^status:' "$T2_WORK/board/stories/S-900-test.yaml" | head -1)"
if [[ "$T2_STATUS" == "status: Done" ]]; then
  pass "Test 2b: Board trotzdem korrekt auf Done geflippt (CI-Check + Board-Flip laufen weiter)"
else
  fail "Test 2b: Board nicht auf Done (${T2_STATUS})"
fi

# ===========================================================================
# Test 3 — Happy Path: merge_policy=direct, CI gruen -> Board-Flip auf Done
# ===========================================================================
echo ""
echo "--- Test 3: Happy Path — direct-Merge, CI gruen, Board-Flip + branch-Feld ---"
T3_WORK="$(setup_fixture "${TEST_WORK_DIR}/test3")"
(
  cd "$T3_WORK"
  git checkout -q -b feat/S-900-test
  echo "feature" > feature.txt
  git add -A
  git commit -q -m "S-900: feature work"
)
export MOCK_HEAD_SHA MOCK_CI_STATUS="completed" MOCK_CI_CONCLUSION="success"
T3_OUTPUT="$(cd "$T3_WORK" && MOCK_HEAD_SHA="$(git rev-parse HEAD)" bash "$SHIP_SCRIPT" S-900 2>&1)"
T3_EXIT=$?

if [[ $T3_EXIT -eq 0 ]]; then
  pass "Test 3a: Happy Path läuft ohne Fehler durch (exit 0)"
else
  fail "Test 3a: exit=${T3_EXIT}"
  echo "  Output: $T3_OUTPUT"
fi
T3_STATUS="$(grep '^status:' "$T3_WORK/board/stories/S-900-test.yaml" | head -1)"
T3_BRANCH="$(grep '^branch:' "$T3_WORK/board/stories/S-900-test.yaml" | head -1)"
if [[ "$T3_STATUS" == "status: Done" ]]; then
  pass "Test 3b: Board auf Done geflippt"
else
  fail "Test 3b: Board-Status ist '${T3_STATUS}', erwartet 'status: Done'"
fi
if [[ "$T3_BRANCH" == "branch: feat/S-900-test" ]]; then
  pass "Test 3c: branch-Feld korrekt gesetzt"
else
  fail "Test 3c: branch-Feld ist '${T3_BRANCH}'"
fi
T3_ORIGIN_LOG="$(git -C "$T3_WORK" log origin/main --oneline | grep -c "feature work" || true)"
if [[ "$T3_ORIGIN_LOG" -ge 1 ]]; then
  pass "Test 3d: Story-Commit ist tatsächlich auf origin/main gelandet"
else
  fail "Test 3d: Story-Commit fehlt auf origin/main"
fi

# ===========================================================================
# Test 4 — CI-Fehlschlag verhindert Board-Flip (kein Rollout auf rotem CI)
# ===========================================================================
echo ""
echo "--- Test 4: CI-Fehlschlag -> kein Board-Flip, Story bleibt NICHT Done ---"
T4_WORK="$(setup_fixture "${TEST_WORK_DIR}/test4")"
(
  cd "$T4_WORK"
  git checkout -q -b feat/S-900-test
  echo "feature" > feature.txt
  git add -A
  git commit -q -m "S-900: feature work"
)
export MOCK_CI_STATUS="completed" MOCK_CI_CONCLUSION="failure"
set +e
T4_OUTPUT="$(cd "$T4_WORK" && MOCK_HEAD_SHA="$(git rev-parse HEAD)" bash "$SHIP_SCRIPT" S-900 2>&1)"
T4_EXIT=$?
set -e

if [[ $T4_EXIT -ne 0 ]] && echo "$T4_OUTPUT" | grep -q "CI nicht erfolgreich"; then
  pass "Test 4a: CI-Fehlschlag korrekt erkannt und gemeldet"
else
  fail "Test 4a: CI-Fehlschlag nicht erkannt (exit=${T4_EXIT})"
  echo "  Output: $T4_OUTPUT"
fi
T4_STATUS="$(grep '^status:' "$T4_WORK/board/stories/S-900-test.yaml" | head -1)"
if [[ "$T4_STATUS" == "status: In Review" ]]; then
  pass "Test 4b: Board-Status unverändert (kein Flip auf Done bei rotem CI)"
else
  fail "Test 4b: Board-Status ist '${T4_STATUS}', erwartet unverändert 'status: In Review'"
fi

# ===========================================================================
# Test 5 — Idempotenz: zweiter Aufruf nach erfolgreichem Ship ist ein No-Op
# ===========================================================================
echo ""
echo "--- Test 5: zweiter Ship-Aufruf nach erfolgreichem Ship ist idempotent ---"
export MOCK_CI_STATUS="completed" MOCK_CI_CONCLUSION="success"
git -C "$T3_WORK" checkout -q feat/S-900-test   # zurück auf den Story-Branch (Test 3 endete auf main)
set +e
T5_OUTPUT="$(cd "$T3_WORK" && MOCK_HEAD_SHA="$(git rev-parse origin/main)" bash "$SHIP_SCRIPT" S-900 2>&1)"
T5_EXIT=$?
set -e
if [[ $T5_EXIT -eq 0 ]] && echo "$T5_OUTPUT" | grep -q "bereits gemergt"; then
  pass "Test 5: wiederholter Aufruf erkennt 'bereits gemergt', kein Fehler, kein Doppel-Merge"
else
  fail "Test 5: wiederholter Aufruf nicht idempotent (exit=${T5_EXIT})"
  echo "  Output: $T5_OUTPUT"
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
