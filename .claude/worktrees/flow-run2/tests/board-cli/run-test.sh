#!/usr/bin/env bash
# tests/board-cli/run-test.sh
#
# Self-Test für `board ready` (AC12, F-008 „Autonome Board-Abarbeitung").
# Verwendet /tmp — berührt NIEMALS das echte board/ des Repos.
#
# Testziele:
#   - Alle To-Do-Stories ready → Exit 0, READY-Zeilen (happy path)
#   - Mindestens eine To-Do-Story NOT-READY → Exit 1 (not-ready path)
#   - Jede Regel R2–R5 erzeugt den korrekten NOT-READY-Grund
#   - --quiet unterdrückt (n/a)-Zeilen
#   - Nicht-To-Do-Stories werden als (n/a) übersprungen
#   - Fehlendes Board-Verzeichnis → Exit 0, kein Crash
#
# Exit: 0 = alle Tests bestanden, 1 = mindestens ein Fehler

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
BOARD_SCRIPT="${REPO_ROOT}/scripts/board"

# Eigene TMPDIR-Variable (reviewer/L05: $TMPDIR nie überschreiben)
TEST_WORK_DIR="$(mktemp -d /tmp/board-cli-test.XXXXXX)"

# Cleanup bei Exit
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

# ---------------------------------------------------------------------------
# Hilfsfunktion: minimales Board-Skelett aufbauen
# ---------------------------------------------------------------------------
setup_board() {
  local work_dir="$1"
  local project_slug="${2:-test-proj}"
  mkdir -p "${work_dir}/board/features"
  mkdir -p "${work_dir}/board/stories"
  mkdir -p "${work_dir}/docs/specs"

  # board.yaml
  cat > "${work_dir}/board/board.yaml" <<YAML
schema_version: 1
project_slug: ${project_slug}
next_feature_id: 2
next_story_id: 10
YAML

  # F-001 Feature
  cat > "${work_dir}/board/features/F-001-test.yaml" <<YAML
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
}

# ---------------------------------------------------------------------------
# Hilfsfunktion: Spec-Datei mit aktivem Frontmatter anlegen
# ---------------------------------------------------------------------------
make_active_spec() {
  local path="$1"
  shift  # weitere ACs als $@
  mkdir -p "$(dirname "$path")"
  {
    echo "---"
    echo "id: test-spec"
    echo "title: Test Spec"
    echo "status: active"
    echo "---"
    echo "# Test Spec"
    for ac in "$@"; do
      echo "- **${ac}** — Testanforderung"
    done
  } > "$path"
}

# ---------------------------------------------------------------------------
# Hilfsfunktion: Story-YAML anlegen
# ---------------------------------------------------------------------------
make_story() {
  local work_dir="$1"
  local sid="$2"
  local status="$3"
  local spec="${4:-}"
  local implements="${5:-}"
  local depends="${6:-}"
  local blocked_reason="${7:-}"

  local slug
  slug="$(echo "$sid" | tr '[:upper:]' '[:lower:]')"

  {
    echo "id: ${sid}"
    echo "parent: F-001"
    echo "title: Story ${sid}"
    echo "status: ${status}"
    echo "priority: P2"
    echo "spec: ${spec:-null}"
    if [[ -n "$implements" ]]; then
      echo "implements: [${implements}]"
    else
      echo "implements: null"
    fi
    if [[ -n "$depends" ]]; then
      echo "depends: [${depends}]"
    else
      echo "depends: null"
    fi
    echo "labels: null"
    echo "size_est: null"
    echo "dispo_est: null"
    echo "dispo_act: null"
    echo "dispo_forecast: null"
    echo "estimate_note: null"
    echo "confidence: null"
    echo "branch: null"
    echo "pr: null"
    echo "blocked_reason: ${blocked_reason:-null}"
    echo "created_at: '2026-01-01T00:00:00Z'"
    echo "updated_at: '2026-01-01T00:00:00Z'"
    echo "done_at: null"
  } > "${work_dir}/board/stories/${sid}-${slug}.yaml"
}

# ===========================================================================
# Test 1: Happy Path — alle To-Do-Stories ready
# ===========================================================================
echo ""
echo "--- Test 1: Happy Path — alle To-Do-Stories ready ---"

T1_DIR="${TEST_WORK_DIR}/test1"
setup_board "$T1_DIR"
make_active_spec "${T1_DIR}/docs/specs/test.md" "AC1" "AC2"
make_story "$T1_DIR" "S-001" "To Do" "docs/specs/test.md" "AC1, AC2" "" ""
make_story "$T1_DIR" "S-002" "To Do" "docs/specs/test.md" "AC2" "" ""

T1_EXIT=0
T1_OUTPUT=""
set +e
T1_OUTPUT="$(cd "$T1_DIR" && BOARD_DIR=board bash "$BOARD_SCRIPT" ready 2>&1)"
T1_EXIT=$?
set -e

echo "$T1_OUTPUT"

if [[ $T1_EXIT -eq 0 ]]; then
  pass "Test 1a: Exit 0 (alle ready)"
else
  fail "Test 1a: Exit ${T1_EXIT} (erwartet 0)"
fi

if echo "$T1_OUTPUT" | grep -q "^READY     S-001"; then
  pass "Test 1b: S-001 als READY gemeldet"
else
  fail "Test 1b: S-001 nicht als READY gemeldet"
fi

if echo "$T1_OUTPUT" | grep -q "^READY     S-002"; then
  pass "Test 1c: S-002 als READY gemeldet"
else
  fail "Test 1c: S-002 nicht als READY gemeldet"
fi

if echo "$T1_OUTPUT" | grep -q "Summary: 2/2 To-Do-Stories ready"; then
  pass "Test 1d: Summary korrekt (2/2)"
else
  fail "Test 1d: Summary fehlt oder falsch"
  echo "  Output: $T1_OUTPUT"
fi

# ===========================================================================
# Test 2: Not-Ready Path — eine Story NOT-READY → Exit 1
# ===========================================================================
echo ""
echo "--- Test 2: Not-Ready Path — Exit 1 wenn mindestens eine NOT-READY ---"

T2_DIR="${TEST_WORK_DIR}/test2"
setup_board "$T2_DIR"
make_active_spec "${T2_DIR}/docs/specs/test.md" "AC1"
make_story "$T2_DIR" "S-001" "To Do" "docs/specs/test.md" "AC1" "" ""
# S-002: spec fehlt → NOT-READY
make_story "$T2_DIR" "S-002" "To Do" "" "" "" ""

T2_EXIT=0
T2_OUTPUT=""
set +e
T2_OUTPUT="$(cd "$T2_DIR" && BOARD_DIR=board bash "$BOARD_SCRIPT" ready 2>&1)"
T2_EXIT=$?
set -e

echo "$T2_OUTPUT"

if [[ $T2_EXIT -eq 1 ]]; then
  pass "Test 2a: Exit 1 (mindestens eine NOT-READY)"
else
  fail "Test 2a: Exit ${T2_EXIT} (erwartet 1)"
fi

if echo "$T2_OUTPUT" | grep -q "^READY     S-001"; then
  pass "Test 2b: S-001 als READY gemeldet"
else
  fail "Test 2b: S-001 nicht als READY gemeldet"
fi

if echo "$T2_OUTPUT" | grep -q "^NOT-READY S-002"; then
  pass "Test 2c: S-002 als NOT-READY gemeldet"
else
  fail "Test 2c: S-002 nicht als NOT-READY gemeldet"
fi

# ===========================================================================
# Test 3: R2 — spec nicht gesetzt
# ===========================================================================
echo ""
echo "--- Test 3: R2 — spec nicht gesetzt ---"

T3_DIR="${TEST_WORK_DIR}/test3"
setup_board "$T3_DIR"
make_story "$T3_DIR" "S-001" "To Do" "" "" "" ""

T3_OUTPUT=""
set +e
T3_OUTPUT="$(cd "$T3_DIR" && BOARD_DIR=board bash "$BOARD_SCRIPT" ready 2>&1)"
set -e

if echo "$T3_OUTPUT" | grep -q "R2: spec nicht gesetzt"; then
  pass "Test 3: R2 spec nicht gesetzt — korrekte Fehlermeldung"
else
  fail "Test 3: R2 Fehlermeldung fehlt oder falsch"
  echo "  Output: $T3_OUTPUT"
fi

# ===========================================================================
# Test 4: R2 — spec-Datei fehlt
# ===========================================================================
echo ""
echo "--- Test 4: R2 — spec-Datei fehlt ---"

T4_DIR="${TEST_WORK_DIR}/test4"
setup_board "$T4_DIR"
make_story "$T4_DIR" "S-001" "To Do" "docs/specs/nonexistent.md" "AC1" "" ""

T4_OUTPUT=""
set +e
T4_OUTPUT="$(cd "$T4_DIR" && BOARD_DIR=board bash "$BOARD_SCRIPT" ready 2>&1)"
set -e

if echo "$T4_OUTPUT" | grep -q "R2: spec-Datei fehlt"; then
  pass "Test 4: R2 spec-Datei fehlt — korrekte Fehlermeldung"
else
  fail "Test 4: R2 Fehlermeldung fehlt oder falsch"
  echo "  Output: $T4_OUTPUT"
fi

# ===========================================================================
# Test 5: R2 — spec-Datei hat kein YAML-Frontmatter
# ===========================================================================
echo ""
echo "--- Test 5: R2 — spec hat kein YAML-Frontmatter ---"

T5_DIR="${TEST_WORK_DIR}/test5"
setup_board "$T5_DIR"
mkdir -p "${T5_DIR}/docs/specs"
# Spec ohne Frontmatter
echo "# Kein Frontmatter — nur Text" > "${T5_DIR}/docs/specs/no-fm.md"
echo "- **AC1** — Test" >> "${T5_DIR}/docs/specs/no-fm.md"
make_story "$T5_DIR" "S-001" "To Do" "docs/specs/no-fm.md" "AC1" "" ""

T5_OUTPUT=""
set +e
T5_OUTPUT="$(cd "$T5_DIR" && BOARD_DIR=board bash "$BOARD_SCRIPT" ready 2>&1)"
set -e

if echo "$T5_OUTPUT" | grep -q "R2:"; then
  pass "Test 5: R2 Frontmatter fehlt — Fehler gemeldet"
else
  fail "Test 5: R2 Frontmatter fehlt — kein Fehler gemeldet"
  echo "  Output: $T5_OUTPUT"
fi

# ===========================================================================
# Test 6: R2 — spec-Datei hat status: draft (nicht active)
# ===========================================================================
echo ""
echo "--- Test 6: R2 — spec status: draft ---"

T6_DIR="${TEST_WORK_DIR}/test6"
setup_board "$T6_DIR"
mkdir -p "${T6_DIR}/docs/specs"
cat > "${T6_DIR}/docs/specs/draft-spec.md" <<'MDEOF'
---
id: draft-spec
title: Draft Spec
status: draft
---
# Draft Spec
- **AC1** — Test
MDEOF
make_story "$T6_DIR" "S-001" "To Do" "docs/specs/draft-spec.md" "AC1" "" ""

T6_OUTPUT=""
set +e
T6_OUTPUT="$(cd "$T6_DIR" && BOARD_DIR=board bash "$BOARD_SCRIPT" ready 2>&1)"
set -e

if echo "$T6_OUTPUT" | grep -q "R2:.*status=.*draft"; then
  pass "Test 6: R2 spec status=draft — korrekte Fehlermeldung"
else
  fail "Test 6: R2 spec status=draft — Fehlermeldung fehlt oder falsch"
  echo "  Output: $T6_OUTPUT"
fi

# ===========================================================================
# Test 7: R3 — implements leer
# ===========================================================================
echo ""
echo "--- Test 7: R3 — implements leer ---"

T7_DIR="${TEST_WORK_DIR}/test7"
setup_board "$T7_DIR"
make_active_spec "${T7_DIR}/docs/specs/test.md" "AC1"
make_story "$T7_DIR" "S-001" "To Do" "docs/specs/test.md" "" "" ""

T7_OUTPUT=""
set +e
T7_OUTPUT="$(cd "$T7_DIR" && BOARD_DIR=board bash "$BOARD_SCRIPT" ready 2>&1)"
set -e

if echo "$T7_OUTPUT" | grep -q "R3: implements leer"; then
  pass "Test 7: R3 implements leer — korrekte Fehlermeldung"
else
  fail "Test 7: R3 implements leer — Fehlermeldung fehlt oder falsch"
  echo "  Output: $T7_OUTPUT"
fi

# ===========================================================================
# Test 8: R3 — AC-Nummer nicht in Spec
# ===========================================================================
echo ""
echo "--- Test 8: R3 — AC fehlt in Spec ---"

T8_DIR="${TEST_WORK_DIR}/test8"
setup_board "$T8_DIR"
make_active_spec "${T8_DIR}/docs/specs/test.md" "AC1"
# Story implementiert AC99, das nicht in der Spec ist
make_story "$T8_DIR" "S-001" "To Do" "docs/specs/test.md" "AC99" "" ""

T8_OUTPUT=""
set +e
T8_OUTPUT="$(cd "$T8_DIR" && BOARD_DIR=board bash "$BOARD_SCRIPT" ready 2>&1)"
set -e

if echo "$T8_OUTPUT" | grep -q "R3: AC fehlt in Spec.*AC99"; then
  pass "Test 8: R3 AC99 fehlt in Spec — korrekte Fehlermeldung"
else
  fail "Test 8: R3 AC fehlt in Spec — Fehlermeldung fehlt oder falsch"
  echo "  Output: $T8_OUTPUT"
fi

# ===========================================================================
# Test 9: R4 — depends nicht Done
# ===========================================================================
echo ""
echo "--- Test 9: R4 — depends nicht Done ---"

T9_DIR="${TEST_WORK_DIR}/test9"
setup_board "$T9_DIR"
make_active_spec "${T9_DIR}/docs/specs/test.md" "AC1"
# S-001 ist To Do (nicht Done)
make_story "$T9_DIR" "S-001" "To Do" "docs/specs/test.md" "AC1" "" ""
# S-002 hängt von S-001 ab (das nicht Done ist)
make_story "$T9_DIR" "S-002" "To Do" "docs/specs/test.md" "AC1" "S-001" ""

T9_OUTPUT=""
set +e
T9_OUTPUT="$(cd "$T9_DIR" && BOARD_DIR=board bash "$BOARD_SCRIPT" ready 2>&1)"
set -e

if echo "$T9_OUTPUT" | grep -q "R4: depends nicht Done.*S-001"; then
  pass "Test 9: R4 depends S-001 nicht Done — korrekte Fehlermeldung"
else
  fail "Test 9: R4 depends nicht Done — Fehlermeldung fehlt oder falsch"
  echo "  Output: $T9_OUTPUT"
fi

# S-001 selbst soll READY sein (keine depends)
if echo "$T9_OUTPUT" | grep -q "^READY     S-001"; then
  pass "Test 9b: S-001 ohne depends → READY"
else
  fail "Test 9b: S-001 ohne depends soll READY sein"
  echo "  Output: $T9_OUTPUT"
fi

# ===========================================================================
# Test 10: R4 — depends Done → READY
# ===========================================================================
echo ""
echo "--- Test 10: R4 — depends Done → READY ---"

T10_DIR="${TEST_WORK_DIR}/test10"
setup_board "$T10_DIR"
make_active_spec "${T10_DIR}/docs/specs/test.md" "AC1"
# S-001 ist Done
make_story "$T10_DIR" "S-001" "Done" "docs/specs/test.md" "AC1" "" ""
# S-002 hängt von S-001 ab (Done) → soll READY sein
make_story "$T10_DIR" "S-002" "To Do" "docs/specs/test.md" "AC1" "S-001" ""

T10_EXIT=0
T10_OUTPUT=""
set +e
T10_OUTPUT="$(cd "$T10_DIR" && BOARD_DIR=board bash "$BOARD_SCRIPT" ready 2>&1)"
T10_EXIT=$?
set -e

echo "$T10_OUTPUT"

if [[ $T10_EXIT -eq 0 ]]; then
  pass "Test 10a: Exit 0 (depends Done → alle ready)"
else
  fail "Test 10a: Exit ${T10_EXIT} (erwartet 0)"
fi

if echo "$T10_OUTPUT" | grep -q "^READY     S-002"; then
  pass "Test 10b: S-002 mit Done-depends → READY"
else
  fail "Test 10b: S-002 nicht als READY gemeldet"
  echo "  Output: $T10_OUTPUT"
fi

# S-001 (Done) soll als (n/a) erscheinen
if echo "$T10_OUTPUT" | grep -q "^(n/a)     S-001"; then
  pass "Test 10c: S-001 (Done) → (n/a)"
else
  fail "Test 10c: S-001 (Done) nicht als (n/a)"
  echo "  Output: $T10_OUTPUT"
fi

# ===========================================================================
# Test 11: R5 — blocked_reason gesetzt
# ===========================================================================
echo ""
echo "--- Test 11: R5 — blocked_reason gesetzt ---"

T11_DIR="${TEST_WORK_DIR}/test11"
setup_board "$T11_DIR"
make_active_spec "${T11_DIR}/docs/specs/test.md" "AC1"
make_story "$T11_DIR" "S-001" "To Do" "docs/specs/test.md" "AC1" "" "Warte auf Entscheidung"

T11_OUTPUT=""
set +e
T11_OUTPUT="$(cd "$T11_DIR" && BOARD_DIR=board bash "$BOARD_SCRIPT" ready 2>&1)"
set -e

if echo "$T11_OUTPUT" | grep -q "R5: blocked_reason gesetzt"; then
  pass "Test 11: R5 blocked_reason gesetzt — korrekte Fehlermeldung"
else
  fail "Test 11: R5 blocked_reason gesetzt — Fehlermeldung fehlt oder falsch"
  echo "  Output: $T11_OUTPUT"
fi

# ===========================================================================
# Test 12: --quiet — (n/a)-Zeilen unterdrückt
# ===========================================================================
echo ""
echo "--- Test 12: --quiet unterdrückt (n/a)-Zeilen ---"

T12_DIR="${TEST_WORK_DIR}/test12"
setup_board "$T12_DIR"
make_active_spec "${T12_DIR}/docs/specs/test.md" "AC1"
make_story "$T12_DIR" "S-001" "Done" "docs/specs/test.md" "AC1" "" ""
make_story "$T12_DIR" "S-002" "To Do" "docs/specs/test.md" "AC1" "" ""

T12_OUTPUT=""
set +e
T12_OUTPUT="$(cd "$T12_DIR" && BOARD_DIR=board bash "$BOARD_SCRIPT" ready --quiet 2>&1)"
set -e

if echo "$T12_OUTPUT" | grep -q "^(n/a)"; then
  fail "Test 12a: --quiet hat (n/a)-Zeilen nicht unterdrückt"
  echo "  Output: $T12_OUTPUT"
else
  pass "Test 12a: --quiet unterdrückt (n/a)-Zeilen"
fi

if echo "$T12_OUTPUT" | grep -q "^READY     S-002"; then
  pass "Test 12b: --quiet zeigt READY-Zeilen"
else
  fail "Test 12b: --quiet soll READY-Zeilen zeigen"
  echo "  Output: $T12_OUTPUT"
fi

if echo "$T12_OUTPUT" | grep -q "Summary:"; then
  pass "Test 12c: --quiet zeigt Summary"
else
  fail "Test 12c: --quiet soll Summary zeigen"
  echo "  Output: $T12_OUTPUT"
fi

# ===========================================================================
# Test 13: Fehlendes Board-Verzeichnis → Exit 0, kein Crash
# ===========================================================================
echo ""
echo "--- Test 13: Fehlendes Board-Verzeichnis → Exit 0 ---"

T13_DIR="${TEST_WORK_DIR}/test13"
mkdir -p "$T13_DIR"

T13_EXIT=0
T13_OUTPUT=""
set +e
T13_OUTPUT="$(cd "$T13_DIR" && BOARD_DIR=board bash "$BOARD_SCRIPT" ready 2>&1)"
T13_EXIT=$?
set -e

if [[ $T13_EXIT -eq 0 ]]; then
  pass "Test 13a: Fehlendes Board → Exit 0"
else
  fail "Test 13a: Fehlendes Board → Exit ${T13_EXIT} (erwartet 0)"
fi

# Kein Crash / kein unhandled Error
if echo "$T13_OUTPUT" | grep -qi "traceback\|error\|exception"; then
  fail "Test 13b: Fehlerausgabe bei fehlendem Board"
  echo "  Output: $T13_OUTPUT"
else
  pass "Test 13b: Kein Crash bei fehlendem Board"
fi

# ===========================================================================
# Test 14: Mehrere Regeln verletzt gleichzeitig → alle Gründe gemeldet
# ===========================================================================
echo ""
echo "--- Test 14: Mehrere Regeln verletzt gleichzeitig ---"

T14_DIR="${TEST_WORK_DIR}/test14"
setup_board "$T14_DIR"
# Keine spec, kein implements, blocked_reason gesetzt
make_story "$T14_DIR" "S-001" "To Do" "" "" "" "Technische Schuld"

T14_OUTPUT=""
set +e
T14_OUTPUT="$(cd "$T14_DIR" && BOARD_DIR=board bash "$BOARD_SCRIPT" ready 2>&1)"
set -e

if echo "$T14_OUTPUT" | grep -q "R2:"; then
  pass "Test 14a: R2-Grund bei mehreren Verletzungen gemeldet"
else
  fail "Test 14a: R2-Grund fehlt"
  echo "  Output: $T14_OUTPUT"
fi

if echo "$T14_OUTPUT" | grep -q "R3:"; then
  pass "Test 14b: R3-Grund bei mehreren Verletzungen gemeldet"
else
  fail "Test 14b: R3-Grund fehlt"
  echo "  Output: $T14_OUTPUT"
fi

if echo "$T14_OUTPUT" | grep -q "R5:"; then
  pass "Test 14c: R5-Grund bei mehreren Verletzungen gemeldet"
else
  fail "Test 14c: R5-Grund fehlt"
  echo "  Output: $T14_OUTPUT"
fi

# ===========================================================================
# Test 15: Summary-Ausgabe korrekt
# ===========================================================================
echo ""
echo "--- Test 15: Summary-Ausgabe korrekt ---"

T15_DIR="${TEST_WORK_DIR}/test15"
setup_board "$T15_DIR"
make_active_spec "${T15_DIR}/docs/specs/test.md" "AC1"
make_story "$T15_DIR" "S-001" "To Do" "docs/specs/test.md" "AC1" "" ""   # ready
make_story "$T15_DIR" "S-002" "To Do" "" "" "" ""                         # not-ready (kein spec)
make_story "$T15_DIR" "S-003" "Done" "docs/specs/test.md" "AC1" "" ""    # n/a

T15_OUTPUT=""
set +e
T15_OUTPUT="$(cd "$T15_DIR" && BOARD_DIR=board bash "$BOARD_SCRIPT" ready 2>&1)"
set -e

if echo "$T15_OUTPUT" | grep -q "Summary: 1/2 To-Do-Stories ready"; then
  pass "Test 15: Summary korrekt (1/2)"
else
  fail "Test 15: Summary fehlt oder falsch (erwartet '1/2 To-Do-Stories ready')"
  echo "  Output: $T15_OUTPUT"
fi

# ===========================================================================
# Test 16: Keine To-Do-Stories → Exit 0, Summary-Hinweis
# ===========================================================================
echo ""
echo "--- Test 16: Keine To-Do-Stories → Exit 0, Summary-Hinweis ---"

T16_DIR="${TEST_WORK_DIR}/test16"
setup_board "$T16_DIR"
make_active_spec "${T16_DIR}/docs/specs/test.md" "AC1"
make_story "$T16_DIR" "S-001" "Done" "docs/specs/test.md" "AC1" "" ""
make_story "$T16_DIR" "S-002" "In Progress" "docs/specs/test.md" "AC1" "" ""

T16_EXIT=0
T16_OUTPUT=""
set +e
T16_OUTPUT="$(cd "$T16_DIR" && BOARD_DIR=board bash "$BOARD_SCRIPT" ready 2>&1)"
T16_EXIT=$?
set -e

if [[ $T16_EXIT -eq 0 ]]; then
  pass "Test 16a: Keine To-Do-Stories → Exit 0"
else
  fail "Test 16a: Exit ${T16_EXIT} (erwartet 0)"
fi

if echo "$T16_OUTPUT" | grep -q "Summary: 0 To-Do-Stories"; then
  pass "Test 16b: Summary 0 To-Do-Stories korrekt"
else
  fail "Test 16b: Summary fehlt oder falsch"
  echo "  Output: $T16_OUTPUT"
fi

# ===========================================================================
# Test 17: R3 — implements: AC1 (skalarer Wert, kein Array) → NOT-READY
# ===========================================================================
echo ""
echo "--- Test 17: R3 — implements als Scalar (nicht Liste) → NOT-READY ---"

T17_DIR="${TEST_WORK_DIR}/test17"
setup_board "$T17_DIR"
make_active_spec "${T17_DIR}/docs/specs/test.md" "AC1"

# Story mit skalarem implements: AC1 (YAML-Scalar, kein Array)
cat > "${T17_DIR}/board/stories/S-001-s-001.yaml" <<YAML
id: S-001
parent: F-001
title: Story S-001
status: To Do
priority: P2
spec: docs/specs/test.md
implements: AC1
depends: null
labels: null
size_est: null
dispo_est: null
dispo_act: null
dispo_forecast: null
estimate_note: null
confidence: null
branch: null
pr: null
blocked_reason: null
created_at: '2026-01-01T00:00:00Z'
updated_at: '2026-01-01T00:00:00Z'
done_at: null
YAML

T17_EXIT=0
T17_OUTPUT=""
set +e
T17_OUTPUT="$(cd "$T17_DIR" && BOARD_DIR=board bash "$BOARD_SCRIPT" ready 2>&1)"
T17_EXIT=$?
set -e

echo "$T17_OUTPUT"

if [[ $T17_EXIT -eq 1 ]]; then
  pass "Test 17a: Scalar implements → Exit 1 (NOT-READY)"
else
  fail "Test 17a: Scalar implements → Exit ${T17_EXIT} (erwartet 1)"
fi

if echo "$T17_OUTPUT" | grep -q "^NOT-READY S-001"; then
  pass "Test 17b: Scalar implements → NOT-READY gemeldet"
else
  fail "Test 17b: Scalar implements → NOT-READY fehlt"
  echo "  Output: $T17_OUTPUT"
fi

if echo "$T17_OUTPUT" | grep -q "R3: implements hat ungültigen Typ"; then
  pass "Test 17c: Scalar implements → R3-Grund korrekt"
else
  fail "Test 17c: Scalar implements → R3-Grund fehlt oder falsch"
  echo "  Output: $T17_OUTPUT"
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
