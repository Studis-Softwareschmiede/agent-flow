#!/usr/bin/env bash
# tests/board-round/claim/run-test.sh
#
# Self-Test für scripts/board-claim.sh — Stufe-1-Bündelung der CLAIM-Sequenz
# aus skills/flow/SKILL.md §2 (Spec docs/specs/story-claim-lock.md
# AC1-AC5/AC12/AC13), Runner-Primitiv aus
# docs/specs/flow-deterministic-runner.md AC4 (Detailkonzept
# docs/architecture/flow-deterministic-runner.md §1.3 S2.1-S2.5, §4.3, §8).
#
# Fixture-Technik: bare "origin" Repos + isolierte Klone (Muster
# tests/story-claim-lock/run-test.sh Tests 12/13, tests/board-ship/run-test.sh)
# — echte git-push-Races/-Ablehnungen, kein Mock von git selbst. Berührt
# NIEMALS das echte board/ des Repos.
#
# Covers (flow-deterministic-runner):
#   @trace flow-deterministic-runner#AC4
#   @trace flow-deterministic-runner#AC9
#   @trace flow-deterministic-runner#AC11
#   AC4 — board-claim.sh nutzt für Claim/Claim-Race/Retry ausschliesslich das
#        bestehende Push-basierte story-claim-lock-Protokoll (kein neues
#        Lock-/Race-Protokoll):
#        Test 1 — erfolgreicher Claim: Story-Datei korrekt gesetzt
#          (status/claimed_by/claimed_at/branch), Exit 0.
#        Test 2 — Push-Ablehnung, fremd+frisch (echter Zwei-Klon-Race): kein
#          hängender Rebase-Zustand, Exit 2, eigene Reservierung verworfen,
#          HEAD exakt auf origin/main.
#        Test 3 — Push-Ablehnung durch unbezogenen Commit (Story bleibt
#          "To Do"): Retry mit gleichem Token gelingt, Exit 0, unbezogener
#          Commit bleibt erhalten.
#        Test 4 — Retry-Budget (3 Versuche) erschöpft (pre-receive-Hook lehnt
#          jeden Push permanent ab): sauberer Abbruch, Exit 3, Story bleibt
#          "To Do" — sowohl lokal (reset) als auch remote.
#        Test 5 — S2.3-Kollision (Drei-Klon, Reviewer-Fund Iteration 1
#          CRITICAL): Story bereits "In Progress" mit STALE fremdem Claim
#          (claimed_at 6h alt, > Default stale_claim_hours=4); ein zweiter
#          Klon pusht einen unbezogenen Commit, BEVOR der reklamierende Klon
#          seinen Claim-Push absetzt -> real abgelehnt. Re-Read zeigt den
#          Claim weiterhin als fremd, aber STALE -> MUSS wie eine unbezogene
#          Ablehnung behandelt werden (Retry, gleicher Token), NICHT wie
#          "fremd übernommen" (Exit 2) — deckt story-claim-lock AC3 ("fremd,
#          FRISCH (nicht stale)") + AC7 (stale_claim_hours) + AC8 (S2.3,
#          Stale-Reclamation-Kollision).
#   AC9/AC11 — S-131-Fix, Iteration 2: guard_clean_or_die() schliesst
#        .claude/worktrees/ per Git-Pathspec-Exclude aus der Prüfung aus
#        (dieselbe Fehlerklasse wie board-round.sh guard_repo_root_clean(),
#        s. tests/board-round/runner/run-test.sh Test 19) — kein
#        Verhaltensunterschied ggü. heute für den erhaltenen Sonderfall
#        "liegengebliebener Fremd-Story-Worktree" (AC9), Board-Status wird
#        weiterhin nur bei tatsächlich erfolgreichem/abgelehntem Claim
#        geschrieben (AC11):
#        Test 6 — ein liegengebliebener Story-Worktree einer FRÜHEREN,
#          unterbrochenen Runde für eine ANDERE Story (echter
#          `git worktree add`, teardown_story_worktree() lässt ihn bewusst
#          stehen, wenn er dirty ist, S-130) blockiert einen NEUEN
#          Claim-Versuch für eine dritte Story NICHT mehr (Exit 0, kein
#          Guard-Fehlalarm, Fremd-Worktree bleibt unangetastet). Gegenprobe
#          (Zahnlos-Check): eine ECHTE fremde uncommittete Änderung
#          ausserhalb von .claude/worktrees/ blockiert weiterhin (Exit 1).
#
# Exit: 0 = alle Tests bestanden, 1 = mindestens ein Fehler

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
BOARD_SCRIPT="${REPO_ROOT}/scripts/board"
BOARD_CLAIM_SCRIPT="${REPO_ROOT}/scripts/board-claim.sh"

# Eigene TMPDIR-Variable (reviewer/L05: $TMPDIR nie überschreiben)
TEST_WORK_DIR="$(mktemp -d /tmp/board-claim-test.XXXXXX)"
trap 'rm -rf "$TEST_WORK_DIR"' EXIT

FAIL=0
PASS=0

fail() {
  echo "FAIL: $*" >&2
  FAIL=$(( FAIL + 1 ))
}

pass() {
  echo "PASS: $*"
  PASS=$(( PASS + 1 ))
}

export GIT_AUTHOR_NAME="test" GIT_AUTHOR_EMAIL="test@test.local"
export GIT_COMMITTER_NAME="test" GIT_COMMITTER_EMAIL="test@test.local"

# setup_claim_origin <dir> — bare origin + Seed-Commit mit board-Skelett
# (F-001 + aktive Spec + Story S-001/S-002 status=To Do). Gibt den Pfad zum
# bare-Repo aus. (Muster tests/story-claim-lock/run-test.sh)
setup_claim_origin() {
  local dir="$1"
  local origin="${dir}/origin.git"
  local seed="${dir}/seed"
  git init --bare -q "$origin"
  git init -q "$seed"
  (
    cd "$seed"
    git config user.name test
    git config user.email test@test.local
    git remote add origin "$origin"
    mkdir -p board/features board/stories docs/specs
    cat > board/board.yaml <<'YAML'
schema_version: 1
project_slug: test-proj
next_feature_id: 2
next_story_id: 10
YAML
    cat > board/features/F-001-test.yaml <<'YAML'
id: F-001
title: Test Feature
goal: Testfeature
status: Active
priority: P1
spec: null
definition_of_done: null
labels: null
depends: null
owner: null
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
AC1 — Testkriterium.
MD
    for sid in S-001 S-002; do
      cat > "board/stories/${sid}-x.yaml" <<YAML
id: ${sid}
parent: F-001
title: Board-Claim Test ${sid}
status: To Do
priority: P2
spec: docs/specs/test-spec.md
implements: [AC1]
depends: null
labels: null
claimed_by: null
claimed_at: null
branch: null
created_at: '2026-01-01T00:00:00Z'
updated_at: '2026-01-01T00:00:00Z'
done_at: null
YAML
    done
    git add -A
    git commit -q -m init
    git branch -M main
    git push -q origin main
  )
  # Bare-Repo-HEAD explizit auf refs/heads/main zeigen lassen (sonst leerer
  # Checkout bei nachfolgendem 'git clone' — reproduzierter Fixture-Defekt,
  # s. tests/story-claim-lock/run-test.sh).
  git -C "$origin" symbolic-ref HEAD refs/heads/main
  echo "$origin"
}

# now_minus_hours <n> — ISO-8601-UTC-Zeitstempel n Stunden in der
# Vergangenheit (Muster tests/story-claim-lock/run-test.sh).
now_minus_hours() {
  local hours="$1"
  date -u -v-"${hours}"H +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
    || date -u -d "-${hours} hours" +%Y-%m-%dT%H:%M:%SZ
}

# seed_existing_claim <origin> <scratch_dir> <sid> <token> <claimed_at_iso> —
# schreibt einen bereits bestehenden Claim (ggf. stale) DIREKT nach origin,
# über einen Wegwerf-Klon, BEVOR die eigentlichen Test-Klone angelegt werden
# — simuliert eine Story, die zu Testbeginn schon "In Progress" war.
seed_existing_claim() {
  local origin="$1" scratch="$2" sid="$3" token="$4" claimed_at="$5"
  git clone -q "$origin" "$scratch"
  (
    cd "$scratch"
    git config user.name test
    git config user.email test@test.local
    BOARD_DIR=board BOARD_WRITER=flow bash "$BOARD_SCRIPT" set "$sid" status "In Progress" >/dev/null
    BOARD_DIR=board bash "$BOARD_SCRIPT" set "$sid" claimed_by "$token" >/dev/null
    BOARD_DIR=board bash "$BOARD_SCRIPT" set "$sid" claimed_at "$claimed_at" >/dev/null
    BOARD_DIR=board bash "$BOARD_SCRIPT" set "$sid" branch "feat/${sid}-ghost" >/dev/null
    git add "board/stories/${sid}-x.yaml"
    git commit -q -m "chore(board): ${sid} claim (ghost, seed)"
    git push -q origin HEAD:main
  )
  rm -rf "$scratch"
}

# ===========================================================================
# Test 1 (AC4) — erfolgreicher Claim: Story-Datei korrekt gesetzt
# ===========================================================================
echo ""
echo "--- Test 1 (AC4): erfolgreicher Claim ---"

T1_DIR="${TEST_WORK_DIR}/test1"
T1_ORIGIN="$(setup_claim_origin "$T1_DIR")"
git clone -q "$T1_ORIGIN" "${T1_DIR}/clone_a"
(cd "${T1_DIR}/clone_a" && git config user.name test && git config user.email test@test.local)

T1_EXIT=0
T1_OUT="$(cd "${T1_DIR}/clone_a" && bash "$BOARD_CLAIM_SCRIPT" S-001 2>&1)" || T1_EXIT=$?

if [[ "$T1_EXIT" -eq 0 ]]; then
  pass "Test 1a: board-claim.sh S-001 liefert Exit 0"
else
  fail "Test 1a: erwartete Exit 0, bekam ${T1_EXIT} — Output: $T1_OUT"
fi

T1_SHOW="$(cd "${T1_DIR}/clone_a" && BOARD_DIR=board bash "$BOARD_SCRIPT" show S-001)"
if echo "$T1_SHOW" | grep -q '"status": "In Progress"' \
  && echo "$T1_SHOW" | grep -q '"claimed_by": "' \
  && ! echo "$T1_SHOW" | grep -q '"claimed_by": null' \
  && echo "$T1_SHOW" | grep -q '"branch": "feat/S-001-board-claim-test-s-001"'; then
  pass "Test 1b: Story-Datei korrekt gesetzt (status/claimed_by/branch)"
else
  fail "Test 1b: Story-Felder falsch gesetzt — Output: $T1_SHOW"
fi

T1_REMOTE_STATUS="$(cd "${T1_DIR}/clone_a" && git show origin/main:board/stories/S-001-x.yaml | grep '^status:')"
if [[ "$T1_REMOTE_STATUS" == "status: In Progress" ]]; then
  pass "Test 1c: Claim wurde tatsächlich nach origin/main gepusht"
else
  fail "Test 1c: Claim wurde nicht gepusht — Remote-Status: $T1_REMOTE_STATUS"
fi

T1_STATUS_PORCELAIN="$(cd "${T1_DIR}/clone_a" && git status --porcelain)"
if [[ -z "$T1_STATUS_PORCELAIN" ]]; then
  pass "Test 1d: Working-Tree sauber nach erfolgreichem Claim"
else
  fail "Test 1d: Working-Tree nicht sauber: $T1_STATUS_PORCELAIN"
fi

# ===========================================================================
# Test 2 (AC4) — Push-Ablehnung, fremd+frisch (echter Zwei-Klon-Race)
# ===========================================================================
echo ""
echo "--- Test 2 (AC4): Push-Ablehnung fremd+frisch -> Exit 2, keine hängende Rebase ---"

T2_DIR="${TEST_WORK_DIR}/test2"
T2_ORIGIN="$(setup_claim_origin "$T2_DIR")"
git clone -q "$T2_ORIGIN" "${T2_DIR}/clone_a"
git clone -q "$T2_ORIGIN" "${T2_DIR}/clone_b"
for c in clone_a clone_b; do
  (cd "${T2_DIR}/${c}" && git config user.name test && git config user.email test@test.local)
done

# Klon A claimt zuerst und gewinnt (Fast-Forward).
T2_EXIT_A=0
(cd "${T2_DIR}/clone_a" && bash "$BOARD_CLAIM_SCRIPT" S-001 >/dev/null 2>&1) || T2_EXIT_A=$?
if [[ "$T2_EXIT_A" -eq 0 ]]; then
  pass "Test 2a: Klon A gewinnt den Claim (Exit 0)"
else
  fail "Test 2a: Klon A hätte gewinnen müssen, Exit ${T2_EXIT_A}"
fi

# Klon B (lokaler Stand veraltet, kennt A's Claim noch nicht) versucht S-001
# ebenfalls zu claimen -> real abgelehnt (non-fast-forward).
T2_EXIT_B=0
T2_OUT_B="$(cd "${T2_DIR}/clone_b" && bash "$BOARD_CLAIM_SCRIPT" S-001 2>&1)" || T2_EXIT_B=$?

if [[ "$T2_EXIT_B" -eq 2 ]]; then
  pass "Test 2b: Klon B erkennt fremden, frischen Claim -> Exit 2"
else
  fail "Test 2b: erwartete Exit 2, bekam ${T2_EXIT_B} — Output: $T2_OUT_B"
fi

if [[ ! -d "${T2_DIR}/clone_b/.git/rebase-merge" && ! -d "${T2_DIR}/clone_b/.git/rebase-apply" ]]; then
  pass "Test 2c: kein hängender Rebase-Zustand in Klon B"
else
  fail "Test 2c: Klon B hat einen hängenden Rebase-Zustand — CRITICAL-Regression"
fi

T2_HEAD_B="$(cd "${T2_DIR}/clone_b" && git rev-parse HEAD)"
T2_HEAD_ORIGIN="$(cd "${T2_DIR}/clone_b" && git rev-parse origin/main)"
if [[ "$T2_HEAD_B" == "$T2_HEAD_ORIGIN" ]]; then
  pass "Test 2d: Klon B landet exakt auf origin/main (eigene Reservierung verworfen)"
else
  fail "Test 2d: Klon B's HEAD (${T2_HEAD_B}) weicht von origin/main (${T2_HEAD_ORIGIN}) ab"
fi

T2_STATUS_PORCELAIN="$(cd "${T2_DIR}/clone_b" && git status --porcelain)"
if [[ -z "$T2_STATUS_PORCELAIN" ]]; then
  pass "Test 2e: Working-Tree in Klon B sauber nach der Recovery"
else
  fail "Test 2e: Working-Tree in Klon B nicht sauber: $T2_STATUS_PORCELAIN"
fi

T2_SHOW_EXIT=0
T2_SHOW_OUT="$(cd "${T2_DIR}/clone_b" && BOARD_DIR=board bash "$BOARD_SCRIPT" show S-001 2>&1)" || T2_SHOW_EXIT=$?
if [[ "$T2_SHOW_EXIT" -eq 0 ]] && echo "$T2_SHOW_OUT" | grep -q '"status": "In Progress"'; then
  pass "Test 2f: 'board show S-001' funktioniert in Klon B nach der Recovery ohne Crash"
else
  fail "Test 2f: 'board show S-001' fehlgeschlagen — exit=${T2_SHOW_EXIT}, Output: $T2_SHOW_OUT"
fi

# ===========================================================================
# Test 3 (AC4) — Push-Ablehnung durch unbezogenen Commit -> Retry gelingt
# ===========================================================================
echo ""
echo "--- Test 3 (AC4): Push-Ablehnung durch unbezogenen Commit -> Retry gelingt ---"

T3_DIR="${TEST_WORK_DIR}/test3"
T3_ORIGIN="$(setup_claim_origin "$T3_DIR")"
git clone -q "$T3_ORIGIN" "${T3_DIR}/clone_b"
git clone -q "$T3_ORIGIN" "${T3_DIR}/clone_c"
for c in clone_b clone_c; do
  (cd "${T3_DIR}/${c}" && git config user.name test && git config user.email test@test.local)
done

# Klon C pusht einen unbezogenen Commit (ändert S-002, nicht S-001) BEVOR
# Klon B seinen Claim-Versuch startet -> Klon B's erster Push wird real
# abgelehnt (sein lokaler Stand kennt C's Commit noch nicht).
(
  cd "${T3_DIR}/clone_c"
  BOARD_DIR=board BOARD_WRITER=flow bash "$BOARD_SCRIPT" set S-002 status "Blocked" --reason "unbezogen" >/dev/null
  git add board/stories/S-002-x.yaml
  git commit -q -m "chore(board): S-002 blocked (unbezogen)"
  git push -q origin HEAD:main
)

T3_EXIT=0
T3_OUT="$(cd "${T3_DIR}/clone_b" && bash "$BOARD_CLAIM_SCRIPT" S-001 2>&1)" || T3_EXIT=$?

if [[ "$T3_EXIT" -eq 0 ]]; then
  pass "Test 3a: Retry nach unbezogener Ablehnung gelingt — Exit 0"
else
  fail "Test 3a: erwartete Exit 0 nach Retry, bekam ${T3_EXIT} — Output: $T3_OUT"
fi

if echo "$T3_OUT" | grep -q 'Retry 2/3'; then
  pass "Test 3b: Skript-Log dokumentiert den Retry-Versuch (2/3)"
else
  fail "Test 3b: Retry-Log-Zeile fehlt — Output: $T3_OUT"
fi

T3_SHOW="$(cd "${T3_DIR}/clone_b" && BOARD_DIR=board bash "$BOARD_SCRIPT" show S-001)"
if echo "$T3_SHOW" | grep -q '"status": "In Progress"'; then
  pass "Test 3c: S-001 nach Retry korrekt geclaimt"
else
  fail "Test 3c: S-001 nicht korrekt geclaimt — Output: $T3_SHOW"
fi

T3_S002_STATUS="$(cd "${T3_DIR}/clone_b" && git show origin/main:board/stories/S-002-x.yaml | grep '^status:')"
if [[ "$T3_S002_STATUS" == "status: Blocked" ]]; then
  pass "Test 3d: unbezogener Commit (S-002 Blocked von Klon C) bleibt erhalten"
else
  fail "Test 3d: unbezogener Commit verloren gegangen — S-002-Status: $T3_S002_STATUS"
fi

# ===========================================================================
# Test 4 (AC4) — Retry-Budget (3 Versuche) erschöpft -> sauberer Abbruch
# ===========================================================================
echo ""
echo "--- Test 4 (AC4): Retry-Budget erschöpft -> Exit 3, Story bleibt To Do ---"

T4_DIR="${TEST_WORK_DIR}/test4"
T4_ORIGIN="$(setup_claim_origin "$T4_DIR")"

# pre-receive-Hook: lehnt JEDEN Push permanent ab (deterministische
# Simulation einer dauerhaft belegten default_branch-Senke — kein Timing-
# abhängiger Hintergrund-Race nötig).
cat > "${T4_ORIGIN}/hooks/pre-receive" <<'HOOK'
#!/bin/sh
exit 1
HOOK
chmod +x "${T4_ORIGIN}/hooks/pre-receive"

git clone -q "$T4_ORIGIN" "${T4_DIR}/clone_a"
(cd "${T4_DIR}/clone_a" && git config user.name test && git config user.email test@test.local)

T4_EXIT=0
T4_OUT="$(cd "${T4_DIR}/clone_a" && bash "$BOARD_CLAIM_SCRIPT" S-001 2>&1)" || T4_EXIT=$?

if [[ "$T4_EXIT" -eq 3 ]]; then
  pass "Test 4a: Retry-Budget erschöpft -> Exit 3"
else
  fail "Test 4a: erwartete Exit 3, bekam ${T4_EXIT} — Output: $T4_OUT"
fi

if echo "$T4_OUT" | grep -q '3/3' ; then
  pass "Test 4b: Skript-Log zeigt alle 3 Versuche"
else
  fail "Test 4b: Log zeigt nicht 3 Versuche — Output: $T4_OUT"
fi

T4_LOCAL_STATUS="$(cd "${T4_DIR}/clone_a" && cat board/stories/S-001-x.yaml | grep '^status:')"
if [[ "$T4_LOCAL_STATUS" == "status: To Do" ]]; then
  pass "Test 4c: Story bleibt lokal 'To Do' (kein halb-geclaimter Zwischenstand)"
else
  fail "Test 4c: Story lokal nicht 'To Do' — $T4_LOCAL_STATUS"
fi

T4_REMOTE_STATUS="$(cd "${T4_DIR}/clone_a" && git show origin/main:board/stories/S-001-x.yaml | grep '^status:')"
if [[ "$T4_REMOTE_STATUS" == "status: To Do" ]]; then
  pass "Test 4d: Story bleibt remote 'To Do'"
else
  fail "Test 4d: Story remote nicht 'To Do' — $T4_REMOTE_STATUS"
fi

T4_STATUS_PORCELAIN="$(cd "${T4_DIR}/clone_a" && git status --porcelain)"
if [[ -z "$T4_STATUS_PORCELAIN" ]]; then
  pass "Test 4e: Working-Tree sauber nach dem Abbruch (kein Zwischenstand)"
else
  fail "Test 4e: Working-Tree nicht sauber: $T4_STATUS_PORCELAIN"
fi

if [[ ! -d "${T4_DIR}/clone_a/.git/rebase-merge" && ! -d "${T4_DIR}/clone_a/.git/rebase-apply" ]]; then
  pass "Test 4f: kein hängender Rebase-Zustand"
else
  fail "Test 4f: hängender Rebase-Zustand — CRITICAL-Regression"
fi

# ===========================================================================
# Test 5 (AC4, story-claim-lock AC3/AC7/AC8) — S2.3-Kollision: fremd+STALE
# Claim + unbezogene Push-Ablehnung -> Retry gelingt, NICHT Exit 2
# (Reviewer-Fund Iteration 1 CRITICAL: das Skript unterschied bisher nicht
# zwischen fremd+frisch und fremd+stale und behandelte beides als Exit 2)
# ===========================================================================
echo ""
echo "--- Test 5 (AC4/S2.3): fremd+STALE Claim + unbezogene Ablehnung -> Retry gelingt (kein Exit 2) ---"

T5_DIR="${TEST_WORK_DIR}/test5"
T5_ORIGIN="$(setup_claim_origin "$T5_DIR")"

T5_OLD_TOKEN="ghost-session-dead-111"
seed_existing_claim "$T5_ORIGIN" "${T5_DIR}/seed_stale" "S-001" "$T5_OLD_TOKEN" "$(now_minus_hours 6)"

git clone -q "$T5_ORIGIN" "${T5_DIR}/clone_a"
git clone -q "$T5_ORIGIN" "${T5_DIR}/clone_c"
for c in clone_a clone_c; do
  (cd "${T5_DIR}/${c}" && git config user.name test && git config user.email test@test.local)
done

# Klon C pusht einen unbezogenen Commit (S-002 Blocked), BEVOR Klon A (der
# den stale Ghost-Claim von S-001 reklamieren will) seinen Claim-Push absetzt
# -> Klon A's erster Push wird real abgelehnt (sein lokaler Stand kennt C's
# Commit noch nicht).
(
  cd "${T5_DIR}/clone_c"
  BOARD_DIR=board BOARD_WRITER=flow bash "$BOARD_SCRIPT" set S-002 status "Blocked" --reason "unbezogen" >/dev/null
  git add board/stories/S-002-x.yaml
  git commit -q -m "chore(board): S-002 blocked (unbezogen)"
  git push -q origin HEAD:main
)

T5_EXIT=0
T5_OUT="$(cd "${T5_DIR}/clone_a" && bash "$BOARD_CLAIM_SCRIPT" S-001 2>&1)" || T5_EXIT=$?

if [[ "$T5_EXIT" -eq 0 ]]; then
  pass "Test 5a: Reklamation eines stale fremden Claims trotz unbezogener Ablehnung erfolgreich -> Exit 0 (NICHT Exit 2)"
else
  fail "Test 5a: erwartete Exit 0, bekam ${T5_EXIT} — Output: $T5_OUT"
fi

if echo "$T5_OUT" | grep -q 'STALE Claim' && echo "$T5_OUT" | grep -q 'Retry 2/3'; then
  pass "Test 5b: Skript-Log klassifiziert korrekt als fremd+STALE und retried statt aufzugeben"
else
  fail "Test 5b: erwartetes STALE-Retry-Log fehlt — Output: $T5_OUT"
fi

T5_SHOW="$(cd "${T5_DIR}/clone_a" && BOARD_DIR=board bash "$BOARD_SCRIPT" show S-001)"
if echo "$T5_SHOW" | grep -q '"status": "In Progress"' && ! echo "$T5_SHOW" | grep -q "\"claimed_by\": \"${T5_OLD_TOKEN}\""; then
  pass "Test 5c: S-001 jetzt mit dem eigenen (neuen) Claim, alter Ghost-Claim überschrieben"
else
  fail "Test 5c: S-001 falsch geclaimt — Output: $T5_SHOW"
fi

T5_S002_STATUS="$(cd "${T5_DIR}/clone_a" && git show origin/main:board/stories/S-002-x.yaml | grep '^status:')"
if [[ "$T5_S002_STATUS" == "status: Blocked" ]]; then
  pass "Test 5d: unbezogener Commit (S-002 Blocked von Klon C) bleibt erhalten"
else
  fail "Test 5d: unbezogener Commit verloren gegangen — S-002-Status: $T5_S002_STATUS"
fi

if [[ ! -d "${T5_DIR}/clone_a/.git/rebase-merge" && ! -d "${T5_DIR}/clone_a/.git/rebase-apply" ]]; then
  pass "Test 5e: kein hängender Rebase-Zustand"
else
  fail "Test 5e: hängender Rebase-Zustand — CRITICAL-Regression"
fi

# ===========================================================================
# Test 6 (S-131, AC9/AC11) — liegengebliebener Fremd-Story-Worktree einer
# FRÜHEREN, unterbrochenen Runde darf einen NEUEN Claim-Versuch für eine
# ANDERE Story nicht blockieren (guard_clean_or_die()-Pathspec-Exclude,
# dieselbe Fehlerklasse wie board-round.sh guard_repo_root_clean(), Test 19
# in tests/board-round/runner/run-test.sh).
# ===========================================================================
echo ""
echo "--- Test 6 (S-131, AC9/AC11): liegengebliebener Fremd-Story-Worktree blockiert neuen Claim-Versuch NICHT ---"

T6_DIR="${TEST_WORK_DIR}/test6"
T6_ORIGIN="$(setup_claim_origin "$T6_DIR")"
git clone -q "$T6_ORIGIN" "${T6_DIR}/clone_a"
(cd "${T6_DIR}/clone_a" && git config user.name test && git config user.email test@test.local)

# Simuliert einen liegengebliebenen Story-Worktree einer FRÜHEREN,
# unterbrochenen Runde für eine ANDERE Story (S-001) -- echter
# `git worktree add`, wie board-round.sh es tut, MIT einer uncommitteten
# Änderung darin (genau der Zustand, in dem teardown_story_worktree() ihn
# nach S-130 bewusst NICHT entfernt, weil er dirty ist).
(
  cd "${T6_DIR}/clone_a"
  git worktree add -q -B feat/S-001-ghost .claude/worktrees/S-001 origin/main
  echo "abgebrochene, nie committete Coder-Arbeit" > .claude/worktrees/S-001/mock-impl.txt
)

T6_EXIT=0
T6_OUT="$(cd "${T6_DIR}/clone_a" && bash "$BOARD_CLAIM_SCRIPT" S-002 2>&1)" || T6_EXIT=$?

if [[ "$T6_EXIT" -eq 0 ]]; then
  pass "Test 6a: board-claim.sh S-002 liefert trotz liegengebliebenem Fremd-Story-Worktree Exit 0"
else
  fail "Test 6a: erwartete Exit 0, bekam ${T6_EXIT} — Output: $T6_OUT"
fi

if ! printf '%s' "$T6_OUT" | grep -q 'uncommittete Änderungen'; then
  pass "Test 6b: kein Guard-Fehlalarm im Log (Pathspec-Exclude griff)"
else
  fail "Test 6b: unerwarteter Guard-Fehlalarm im Log — Output: $T6_OUT"
fi

T6_REMOTE_STATUS="$(cd "${T6_DIR}/clone_a" && git show origin/main:board/stories/S-002-x.yaml | grep '^status:')"
if [[ "$T6_REMOTE_STATUS" == "status: In Progress" ]]; then
  pass "Test 6c: S-002 tatsächlich geclaimt (Claim lief trotz Fremd-Worktree durch)"
else
  fail "Test 6c: S-002 remote-Status unerwartet: $T6_REMOTE_STATUS"
fi

if [[ -f "${T6_DIR}/clone_a/.claude/worktrees/S-001/mock-impl.txt" ]]; then
  pass "Test 6d: der liegengebliebene Fremd-Story-Worktree (S-001) ist unangetastet (kein versehentliches Aufräumen durch board-claim.sh)"
else
  fail "Test 6d: der Fremd-Story-Worktree wurde unerwartet verändert/entfernt"
fi

# Gegenprobe (Zahnlos-Check): eine ECHTE fremde uncommittete Änderung
# AUSSERHALB von .claude/worktrees/ muss weiterhin blockiert werden — der
# Pathspec-Exclude betrifft NUR .claude/worktrees/.
echo "echte fremde Änderung (simulierte Parallel-Session)" > "${T6_DIR}/clone_a/real-foreign-change.txt"
T6G_EXIT=0
T6G_OUT="$(cd "${T6_DIR}/clone_a" && bash "$BOARD_CLAIM_SCRIPT" S-001 2>&1)" || T6G_EXIT=$?
rm -f "${T6_DIR}/clone_a/real-foreign-change.txt"

if [[ "$T6G_EXIT" -eq 1 ]]; then
  pass "Test 6e: Guard bleibt scharf — echte fremde Änderung ausserhalb .claude/worktrees/ blockiert weiterhin (Exit 1)"
else
  fail "Test 6e: erwartete Exit 1 (Guard hätte blockieren müssen), bekam ${T6G_EXIT} — Output: $T6G_OUT"
fi

if printf '%s' "$T6G_OUT" | grep -q 'real-foreign-change.txt'; then
  pass "Test 6f: Fehlermeldung nennt die tatsächlich fremde Datei (real-foreign-change.txt)"
else
  fail "Test 6f: erwartete Guard-Fehlermeldung mit real-foreign-change.txt fehlt — Output: $T6G_OUT"
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
