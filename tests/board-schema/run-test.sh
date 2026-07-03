#!/usr/bin/env bash
# tests/board-schema/run-test.sh
#
# Covers (board-schema): AC12
#   AC12 — Story-YAML kennt das optionale Feld `abgenommen_at` (ISO-8601-UTC |
#         null). `board lint` validiert bei gesetztem Wert NUR das Format
#         (kein Pflichtfeld; fehlend/null -> kein Fehler, Test 1/2); ein
#         gesetzter, format-verletzender Wert -> FEHLER ABGENOMMEN-FORMAT
#         (Test 3). Ein gesetztes `abgenommen_at` bei einer Story mit
#         status != Done ist kein lint-Fehler (Test 4, Edge-Case laut Spec).
#         Die Schreiber-Beschraenkung ("nur dev-gui, kein Agent setzt es")
#         ist ein Prozess-/Organisationsvertrag ohne mechanisch pruefbares
#         Gegenstueck in board-lint.sh; nicht separat testbar.
#
# Self-Test fuer die AC12-Erweiterung von `scripts/board-lint.sh`
# (docs/specs/board-schema.md). Verwendet /tmp-Fixtures — beruehrt NIEMALS
# das echte board/ des Repos.
#
# Exit: 0 = alle Tests bestanden, 1 = mindestens ein Fehler

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
LINT_SCRIPT="${REPO_ROOT}/scripts/board-lint.sh"

# Eigene TMPDIR-Variable (reviewer/L05: $TMPDIR nie ueberschreiben)
TEST_WORK_DIR="$(mktemp -d /tmp/board-schema-test.XXXXXX)"
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
# Hilfsfunktionen
# ---------------------------------------------------------------------------
setup_board() {
  local work_dir="$1"
  mkdir -p "${work_dir}/board/features"
  mkdir -p "${work_dir}/board/stories"
  mkdir -p "${work_dir}/docs/specs"
  cat > "${work_dir}/board/board.yaml" <<YAML
schema_version: 1
project_slug: test-proj
next_feature_id: 2
next_story_id: 10
YAML
  cat > "${work_dir}/board/features/F-001-f-001.yaml" <<YAML
id: F-001
title: Feature F-001
goal: Testfeature
status: Active
priority: P1
created_at: '2026-01-01T00:00:00Z'
updated_at: '2026-01-01T00:00:00Z'
YAML
  cat > "${work_dir}/docs/specs/test-spec.md" <<YAML
---
id: test-spec
title: Test Spec
status: active
---
# Test Spec
AC1 — Testkriterium.
YAML
}

make_story() {
  local work_dir="$1" sid="$2" status="$3" abgenommen_at="$4"
  local slug
  slug="$(echo "$sid" | tr '[:upper:]' '[:lower:]')"
  cat > "${work_dir}/board/stories/${sid}-${slug}.yaml" <<YAML
id: ${sid}
parent: F-001
title: Story ${sid}
status: ${status}
priority: P2
spec: docs/specs/test-spec.md
implements: [AC1]
depends: null
labels: null
created_at: '2026-01-01T00:00:00Z'
updated_at: '2026-01-01T00:00:00Z'
done_at: null
abgenommen_at: ${abgenommen_at}
YAML
}

# ===========================================================================
# Test 1: AC12 — abgenommen_at fehlend/null -> kein Fehler
# ===========================================================================
echo ""
echo "--- Test 1: AC12 — abgenommen_at=null -> kein ABGENOMMEN-FORMAT-Fehler ---"

T1_DIR="${TEST_WORK_DIR}/test1"
setup_board "$T1_DIR"
make_story "$T1_DIR" "S-001" "Done" "null"

T1_OUTPUT="$(bash "$LINT_SCRIPT" "$T1_DIR/board" 2>&1 || true)"
if echo "$T1_OUTPUT" | grep -q "ABGENOMMEN-FORMAT"; then
  fail "Test 1: ABGENOMMEN-FORMAT faelschlich gemeldet bei abgenommen_at=null"
  echo "  Output: $T1_OUTPUT"
else
  pass "Test 1: kein ABGENOMMEN-FORMAT bei abgenommen_at=null (AC12)"
fi

# ===========================================================================
# Test 2: AC12 — abgenommen_at gueltiges ISO-8601-UTC -> kein Fehler
# ===========================================================================
echo ""
echo "--- Test 2: AC12 — gueltiges abgenommen_at -> kein Fehler ---"

T2_DIR="${TEST_WORK_DIR}/test2"
setup_board "$T2_DIR"
make_story "$T2_DIR" "S-001" "Done" "'2026-02-01T12:00:00Z'"

T2_OUTPUT="$(bash "$LINT_SCRIPT" "$T2_DIR/board" 2>&1 || true)"
if echo "$T2_OUTPUT" | grep -q "ABGENOMMEN-FORMAT"; then
  fail "Test 2: ABGENOMMEN-FORMAT faelschlich gemeldet bei gueltigem Zeitstempel"
  echo "  Output: $T2_OUTPUT"
else
  pass "Test 2: kein ABGENOMMEN-FORMAT bei gueltigem ISO-8601-UTC (AC12)"
fi

# ===========================================================================
# Test 3: AC12 — abgenommen_at format-verletzend -> FEHLER ABGENOMMEN-FORMAT
# ===========================================================================
echo ""
echo "--- Test 3: AC12 — abgenommen_at verletzt Format -> FEHLER ABGENOMMEN-FORMAT ---"

T3_DIR="${TEST_WORK_DIR}/test3"
setup_board "$T3_DIR"
make_story "$T3_DIR" "S-001" "Done" "'2026-02-01'"

T3_OUTPUT="$(bash "$LINT_SCRIPT" "$T3_DIR/board" 2>&1 || true)"
if echo "$T3_OUTPUT" | grep -q "FEHLER ABGENOMMEN-FORMAT .*S-001-s-001.yaml abgenommen_at='2026-02-01'"; then
  pass "Test 3: FEHLER ABGENOMMEN-FORMAT bei format-verletzendem Wert gemeldet (AC12)"
else
  fail "Test 3: ABGENOMMEN-FORMAT fehlt oder falsch"
  echo "  Output: $T3_OUTPUT"
fi

T3_EXIT=0
set +e
bash "$LINT_SCRIPT" "$T3_DIR/board" >/dev/null 2>&1
T3_EXIT=$?
set -e
if [[ $T3_EXIT -eq 1 ]]; then
  pass "Test 3b: Exit 1 bei format-verletzendem abgenommen_at"
else
  fail "Test 3b: Exit ${T3_EXIT} (erwartet 1)"
fi

# ===========================================================================
# Test 4: AC12 — abgenommen_at gesetzt bei status != Done -> kein lint-Fehler
# (Edge-Case aus Spec: lint erzwingt die Abnahme-Semantik nicht)
# ===========================================================================
echo ""
echo "--- Test 4: AC12 — abgenommen_at gesetzt trotz status != Done -> kein Fehler ---"

T4_DIR="${TEST_WORK_DIR}/test4"
setup_board "$T4_DIR"
make_story "$T4_DIR" "S-001" "In Progress" "'2026-02-01T12:00:00Z'"

T4_OUTPUT="$(bash "$LINT_SCRIPT" "$T4_DIR/board" 2>&1 || true)"
if echo "$T4_OUTPUT" | grep -q "ABGENOMMEN-FORMAT"; then
  fail "Test 4: ABGENOMMEN-FORMAT faelschlich gemeldet bei status != Done"
  echo "  Output: $T4_OUTPUT"
else
  pass "Test 4: kein lint-Fehler bei abgenommen_at + status != Done (AC12, Edge-Case)"
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
