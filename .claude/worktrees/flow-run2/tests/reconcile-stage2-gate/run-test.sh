#!/usr/bin/env bash
# tests/reconcile-stage2-gate/run-test.sh
#
# Covers (reconcile): AC6
#   AC6 — Harte Vorbedingung: Stufe 2 läuft NUR, wenn To Do/In Progress/Blocked/In Review
#         ALLE leer sind. Ist eine Spalte belegt, wird Stufe 2 übersprungen ("erst Board
#         leerräumen"); Stufe 1 läuft unabhängig davon. Inkl. Review-Lehre S-011: fehlt das
#         Board-Skelett (board.yaml nicht vorhanden), bricht der Check NICHT hart ab
#         (`scripts/board` würde das für schreibende Verben tun, coder/L15) — er meldet die
#         Vorbedingung sauber als "nicht erfüllbar/leer" statt mit Fehler abzubrechen.
#
# Self-Test für `scripts/reconcile-stage2-gate.sh` (Kanban-Vorbedingungs-Check des Reconcile-
# Skills, Stufe 2). Verwendet /tmp-Fixtures + ein eigenes BOARD_DIR — berührt NIEMALS das
# echte board/ des Repos.
#
# Exit: 0 = alle Tests bestanden, 1 = mindestens ein Fehler

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
GATE_SCRIPT="${REPO_ROOT}/scripts/reconcile-stage2-gate.sh"
BOARD_SCRIPT="${REPO_ROOT}/scripts/board"

# Eigene TMPDIR-Variable (reviewer/L05: $TMPDIR nie überschreiben)
TEST_WORK_DIR="$(mktemp -d /tmp/reconcile-stage2-gate-test.XXXXXX)"
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

init_board() {
  # $1 = Board-Verzeichnis -- legt ein leeres, aber initialisiertes Board-Skelett an.
  mkdir -p "$1/features" "$1/stories"
  cat > "$1/board.yaml" <<'EOF'
schema_version: 1
project_slug: test
next_feature_id: 1
next_story_id: 1
EOF
}

write_story() {
  # $1 = Zielpfad, $2 = id, $3 = status
  mkdir -p "$(dirname "$1")"
  cat > "$1" <<EOF
id: $2
parent: F-001
title: Test Story
status: $3
priority: P2
spec: docs/specs/x.md
implements:
- AC1
depends: []
labels: []
size_est: M
dispo_est: null
dispo_act: null
dispo_forecast: null
estimate_note: ''
confidence: low
branch: null
pr: null
blocked_reason: null
created_at: '2026-06-30T00:00:00Z'
updated_at: '2026-06-30T00:00:00Z'
done_at: null
EOF
}

run_gate() {
  # $1 = BOARD_DIR (absolut) -- gibt stdout des Gate-Scripts zurück, prüft Exit==0
  local board_dir="$1"
  local out rc
  set +e
  out="$(BOARD_SCRIPT="$BOARD_SCRIPT" BOARD_DIR="$board_dir" bash "$GATE_SCRIPT" 2>"${TEST_WORK_DIR}/.last_stderr")"
  rc=$?
  set -e
  if [[ "$rc" -ne 0 ]]; then
    echo "GATE-EXIT-FEHLER(${rc})"
    return
  fi
  echo "$out"
}

# ===========================================================================
# Test 1: Board-Skelett fehlt komplett (kein board.yaml) -> "no-board", Exit 0 (kein Absturz)
# ===========================================================================
T1_DIR="${TEST_WORK_DIR}/t1/board"
T1_OUT="$(run_gate "$T1_DIR")"
if [[ "$T1_OUT" == "no-board" ]]; then
  pass "Test 1 (Review-Lehre S-011): fehlendes Board-Skelett -> 'no-board', kein Absturz"
else
  fail "Test 1: erwartet 'no-board', bekam '${T1_OUT}'"
fi

# ===========================================================================
# Test 2: Board initialisiert, alle vier Spalten leer -> "empty"
# ===========================================================================
T2_DIR="${TEST_WORK_DIR}/t2/board"
init_board "$T2_DIR"
T2_OUT="$(run_gate "$T2_DIR")"
if [[ "$T2_OUT" == "empty" ]]; then
  pass "Test 2 (AC6): alle vier Spalten leer -> 'empty'"
else
  fail "Test 2: erwartet 'empty', bekam '${T2_OUT}'"
fi

# ===========================================================================
# Test 3: Story in 'To Do' -> "not-empty"
# ===========================================================================
T3_DIR="${TEST_WORK_DIR}/t3/board"
init_board "$T3_DIR"
write_story "${T3_DIR}/stories/S-001-x.yaml" "S-001" "To Do"
T3_OUT="$(run_gate "$T3_DIR")"
if [[ "$T3_OUT" == "not-empty" ]]; then
  pass "Test 3 (AC6/A1): Story in 'To Do' -> 'not-empty'"
else
  fail "Test 3: erwartet 'not-empty', bekam '${T3_OUT}'"
fi

# ===========================================================================
# Test 4: Story NUR in 'Blocked' (andere Spalten leer) -> "not-empty" (jede Spalte zählt)
# ===========================================================================
T4_DIR="${TEST_WORK_DIR}/t4/board"
init_board "$T4_DIR"
write_story "${T4_DIR}/stories/S-001-x.yaml" "S-001" "Blocked"
T4_OUT="$(run_gate "$T4_DIR")"
if [[ "$T4_OUT" == "not-empty" ]]; then
  pass "Test 4 (AC6): Story nur in 'Blocked' -> 'not-empty'"
else
  fail "Test 4: erwartet 'not-empty', bekam '${T4_OUT}'"
fi

# ===========================================================================
# Test 5: Alle Stories 'Done' (kein Item in den vier aktiven Spalten) -> "empty"
# ===========================================================================
T5_DIR="${TEST_WORK_DIR}/t5/board"
init_board "$T5_DIR"
write_story "${T5_DIR}/stories/S-001-x.yaml" "S-001" "Done"
T5_OUT="$(run_gate "$T5_DIR")"
if [[ "$T5_OUT" == "empty" ]]; then
  pass "Test 5 (AC6): nur 'Done'-Stories -> 'empty' (Done zählt nicht zu den vier aktiven Spalten)"
else
  fail "Test 5: erwartet 'empty', bekam '${T5_OUT}'"
fi

# ===========================================================================
# Zusammenfassung
# ===========================================================================
echo ""
echo "reconcile-stage2-gate: ${PASS} passed, ${FAIL} failed"
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
exit 0
