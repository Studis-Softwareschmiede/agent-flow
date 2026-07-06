#!/usr/bin/env bash
# tests/board-areas/run-test.sh
#
# Covers (board-areas): AC3, AC4, AC5
#   AC3 — Bereichs-Feature-Permanenz: `board rollup` setzt ein Feature mit gesetztem
#         `area` NIE automatisch auf Done/Archived, auch wenn alle Kind-Storys terminal
#         (Done/Verworfen) sind; `progress` wird weiter berechnet, `status` bleibt
#         unveraendert (Tests 1a/1b).
#   AC4 — Archiv-Semantik-Invariante: die ausfuehrende Mechanik (`board archive-done-
#         stories`) ist [[board-area-ops]] (S-038, nicht dieser Scope). Hier nur ab-
#         gesichert: das Bereichs-Feature wird durch `board rollup` NIE archiviert
#         (mitabgedeckt durch Test 1a/1b — Archived ist wie Done ein Zielstatus, den
#         rollup nie automatisch setzt; kein separater Test noetig, da rollup keinen
#         Feature-status-Schreibpfad hat, unabhaengig vom Zielwert).
#   AC5 — `board lint` prueft je Feature-`area` und je Spec-`area`-Frontmatter, dass der
#         Wert in board/areas.yaml existiert (AREA-UNKNOWN, Tests 2-5); ein malformtes
#         areas.yaml (fehlende Pflichtfelder, id nicht kebab-case, doppelte id/
#         order) -> AREA-FIELD (Tests 6-9); fehlt areas.yaml und referenziert
#         kein Item eine area -> keine Bereichs-Fehler (Test 10); order als
#         unhashbarer Typ (YAML-Liste statt int) -> AREA-FIELD statt uncaught
#         TypeError/exit 0 (Test 11, Review-Fund Iteration 1).
#
# Self-Test fuer die Bereichs-Erweiterung von `scripts/board rollup` und
# `scripts/board-lint.sh` (docs/specs/board-areas.md). Verwendet /tmp-Fixtures —
# beruehrt NIEMALS das echte board/ des Repos.
#
# Exit: 0 = alle Tests bestanden, 1 = mindestens ein Fehler

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
BOARD_SCRIPT="${REPO_ROOT}/scripts/board"
LINT_SCRIPT="${REPO_ROOT}/scripts/board-lint.sh"

# Eigene TMPDIR-Variable (reviewer/L05: $TMPDIR nie ueberschreiben)
TEST_WORK_DIR="$(mktemp -d /tmp/board-areas-test.XXXXXX)"
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
}

make_feature() {
  local work_dir="$1" fid="$2" area="${3:-null}"
  local slug
  slug="$(echo "$fid" | tr '[:upper:]' '[:lower:]')"
  cat > "${work_dir}/board/features/${fid}-${slug}.yaml" <<YAML
id: ${fid}
title: Feature ${fid}
goal: Testfeature
status: Active
priority: P1
spec: null
definition_of_done: null
labels: null
depends: null
owner: null
area: ${area}
stories: null
progress: null
created_at: '2026-01-01T00:00:00Z'
updated_at: '2026-01-01T00:00:00Z'
YAML
}

make_story() {
  local work_dir="$1" sid="$2" parent="$3" status="$4"
  local slug
  slug="$(echo "$sid" | tr '[:upper:]' '[:lower:]')"
  cat > "${work_dir}/board/stories/${sid}-${slug}.yaml" <<YAML
id: ${sid}
parent: ${parent}
title: Story ${sid}
status: ${status}
priority: P2
spec: null
implements: null
depends: null
labels: null
created_at: '2026-01-01T00:00:00Z'
updated_at: '2026-01-01T00:00:00Z'
done_at: null
YAML
}

make_areas_yaml() {
  local work_dir="$1"
  shift
  {
    for entry in "$@"; do
      echo "$entry"
    done
  } > "${work_dir}/board/areas.yaml"
}

make_spec() {
  local path="$1" area="${2:-}"
  mkdir -p "$(dirname "$path")"
  {
    echo "---"
    echo "id: test-spec"
    echo "title: Test Spec"
    echo "status: active"
    if [[ -n "$area" ]]; then
      echo "area: ${area}"
    fi
    echo "---"
    echo "# Test Spec"
  } > "$path"
}

# ===========================================================================
# Test 1: AC3/AC4 — Bereichs-Feature-Permanenz (rollup setzt status nie)
# ===========================================================================
echo ""
echo "--- Test 1: AC3/AC4 — rollup laesst status eines Bereichs-Features unveraendert ---"

T1_DIR="${TEST_WORK_DIR}/test1"
setup_board "$T1_DIR"
make_feature "$T1_DIR" "F-001" "board"
make_story "$T1_DIR" "S-001" "F-001" "Done"
make_story "$T1_DIR" "S-002" "F-001" "Verworfen"

(cd "$T1_DIR" && BOARD_DIR=board bash "$BOARD_SCRIPT" rollup F-001 >/dev/null)

T1_STATUS="$(grep '^status:' "$T1_DIR/board/features/F-001-f-001.yaml" | head -1)"
if [[ "$T1_STATUS" == "status: Active" ]]; then
  pass "Test 1a: Bereichs-Feature bleibt Active, obwohl alle Kind-Storys terminal sind (AC3)"
else
  fail "Test 1a: status wurde veraendert (${T1_STATUS}, erwartet 'status: Active') (AC3)"
fi

T1_PROGRESS="$(grep '^progress:' "$T1_DIR/board/features/F-001-f-001.yaml" | head -1)"
if [[ "$T1_PROGRESS" == "progress: 1/2 done · 1 verworfen" ]]; then
  pass "Test 1b: progress wird trotz Permanenz weiter berechnet (AC3)"
else
  fail "Test 1b: progress falsch (${T1_PROGRESS}) (AC3)"
fi

# ===========================================================================
# Test 2: AC5 — Feature-area unbekannt (kein areas.yaml) -> AREA-UNKNOWN
# ===========================================================================
echo ""
echo "--- Test 2: AC5 — Feature-area ohne areas.yaml -> AREA-UNKNOWN ---"

T2_DIR="${TEST_WORK_DIR}/test2"
setup_board "$T2_DIR"
make_feature "$T2_DIR" "F-001" "irgendein-bereich"

T2_OUTPUT="$(bash "$LINT_SCRIPT" "$T2_DIR/board" 2>&1 || true)"
if echo "$T2_OUTPUT" | grep -q "FEHLER AREA-UNKNOWN board/features/F-001-f-001.yaml irgendein-bereich"; then
  pass "Test 2: AREA-UNKNOWN bei fehlendem areas.yaml + Feature-area gemeldet (AC5, E2)"
else
  fail "Test 2: AREA-UNKNOWN fehlt oder falsch"
  echo "  Output: $T2_OUTPUT"
fi

# ===========================================================================
# Test 3: AC5 — Feature-area existiert nicht in areas.yaml -> AREA-UNKNOWN
# ===========================================================================
echo ""
echo "--- Test 3: AC5 — Feature-area verwaist (areas.yaml vorhanden) -> AREA-UNKNOWN ---"

T3_DIR="${TEST_WORK_DIR}/test3"
setup_board "$T3_DIR"
make_areas_yaml "$T3_DIR" \
  "- id: board" \
  "  name: Board" \
  "  description: Schema und CLI." \
  "  order: 1"
make_feature "$T3_DIR" "F-001" "nicht-vorhanden"

T3_OUTPUT="$(bash "$LINT_SCRIPT" "$T3_DIR/board" 2>&1 || true)"
if echo "$T3_OUTPUT" | grep -q "FEHLER AREA-UNKNOWN board/features/F-001-f-001.yaml nicht-vorhanden"; then
  pass "Test 3: AREA-UNKNOWN bei verwaister Feature-area gemeldet (AC5, E1)"
else
  fail "Test 3: AREA-UNKNOWN fehlt oder falsch"
  echo "  Output: $T3_OUTPUT"
fi

# ===========================================================================
# Test 4: AC5 — Feature-area existiert -> kein AREA-UNKNOWN
# ===========================================================================
echo ""
echo "--- Test 4: AC5 — gueltige Feature-area -> kein AREA-UNKNOWN ---"

T4_DIR="${TEST_WORK_DIR}/test4"
setup_board "$T4_DIR"
make_areas_yaml "$T4_DIR" \
  "- id: board" \
  "  name: Board" \
  "  description: Schema und CLI." \
  "  order: 1"
make_feature "$T4_DIR" "F-001" "board"

T4_OUTPUT="$(bash "$LINT_SCRIPT" "$T4_DIR/board" 2>&1 || true)"
if echo "$T4_OUTPUT" | grep -q "AREA-UNKNOWN"; then
  fail "Test 4: AREA-UNKNOWN faelschlich gemeldet bei gueltiger area"
  echo "  Output: $T4_OUTPUT"
else
  pass "Test 4: keine AREA-UNKNOWN-Meldung bei gueltiger Feature-area (AC5)"
fi

# ===========================================================================
# Test 5: AC5 — Spec-area-Frontmatter verwaist -> AREA-UNKNOWN
# ===========================================================================
echo ""
echo "--- Test 5: AC5 — Spec-area-Frontmatter verwaist -> AREA-UNKNOWN ---"

T5_DIR="${TEST_WORK_DIR}/test5"
setup_board "$T5_DIR"
make_areas_yaml "$T5_DIR" \
  "- id: board" \
  "  name: Board" \
  "  description: Schema und CLI." \
  "  order: 1"
make_spec "${T5_DIR}/docs/specs/orphan.md" "nicht-vorhanden"

T5_OUTPUT="$(bash "$LINT_SCRIPT" "$T5_DIR/board" 2>&1 || true)"
if echo "$T5_OUTPUT" | grep -q "FEHLER AREA-UNKNOWN docs/specs/orphan.md nicht-vorhanden"; then
  pass "Test 5: AREA-UNKNOWN bei verwaister Spec-area gemeldet (AC5)"
else
  fail "Test 5: AREA-UNKNOWN fehlt oder falsch"
  echo "  Output: $T5_OUTPUT"
fi

# ===========================================================================
# Test 6: AC5 — areas.yaml: fehlendes Pflichtfeld -> AREA-FIELD
# ===========================================================================
echo ""
echo "--- Test 6: AC5 — fehlendes Pflichtfeld in areas.yaml -> AREA-FIELD ---"

T6_DIR="${TEST_WORK_DIR}/test6"
setup_board "$T6_DIR"
make_areas_yaml "$T6_DIR" \
  "- id: board" \
  "  name: Board" \
  "  order: 1"

T6_OUTPUT="$(bash "$LINT_SCRIPT" "$T6_DIR/board" 2>&1 || true)"
if echo "$T6_OUTPUT" | grep -q "FEHLER AREA-FIELD board/areas.yaml Eintrag 1: Pflichtfeld 'description' fehlt"; then
  pass "Test 6: AREA-FIELD bei fehlendem Pflichtfeld gemeldet (AC5)"
else
  fail "Test 6: AREA-FIELD fehlt oder falsch"
  echo "  Output: $T6_OUTPUT"
fi

# ===========================================================================
# Test 7: AC5 — areas.yaml: id nicht kebab-case -> AREA-FIELD
# ===========================================================================
echo ""
echo "--- Test 7: AC5 — id nicht kebab-case -> AREA-FIELD ---"

T7_DIR="${TEST_WORK_DIR}/test7"
setup_board "$T7_DIR"
make_areas_yaml "$T7_DIR" \
  "- id: Board Bereich" \
  "  name: Board" \
  "  description: Schema und CLI." \
  "  order: 1"

T7_OUTPUT="$(bash "$LINT_SCRIPT" "$T7_DIR/board" 2>&1 || true)"
if echo "$T7_OUTPUT" | grep -q "FEHLER AREA-FIELD board/areas.yaml Eintrag 1: id='Board Bereich' nicht kebab-case"; then
  pass "Test 7: AREA-FIELD bei nicht-kebab-case id gemeldet (AC5)"
else
  fail "Test 7: AREA-FIELD fehlt oder falsch"
  echo "  Output: $T7_OUTPUT"
fi

# ===========================================================================
# Test 8: AC5 — areas.yaml: doppelte id -> AREA-FIELD
# ===========================================================================
echo ""
echo "--- Test 8: AC5 — doppelte id -> AREA-FIELD ---"

T8_DIR="${TEST_WORK_DIR}/test8"
setup_board "$T8_DIR"
make_areas_yaml "$T8_DIR" \
  "- id: board" \
  "  name: Board" \
  "  description: Schema und CLI." \
  "  order: 1" \
  "- id: board" \
  "  name: Board zwei" \
  "  description: Zweiter Eintrag." \
  "  order: 2"

T8_OUTPUT="$(bash "$LINT_SCRIPT" "$T8_DIR/board" 2>&1 || true)"
if echo "$T8_OUTPUT" | grep -q "FEHLER AREA-FIELD board/areas.yaml Eintrag 2: doppelte id='board'"; then
  pass "Test 8: AREA-FIELD bei doppelter id gemeldet (AC5)"
else
  fail "Test 8: AREA-FIELD fehlt oder falsch"
  echo "  Output: $T8_OUTPUT"
fi

# ===========================================================================
# Test 9: AC5 — areas.yaml: doppelte order -> AREA-FIELD
# ===========================================================================
echo ""
echo "--- Test 9: AC5 — doppelte order -> AREA-FIELD ---"

T9_DIR="${TEST_WORK_DIR}/test9"
setup_board "$T9_DIR"
make_areas_yaml "$T9_DIR" \
  "- id: board" \
  "  name: Board" \
  "  description: Schema und CLI." \
  "  order: 1" \
  "- id: flow" \
  "  name: Flow" \
  "  description: Orchestrierung." \
  "  order: 1"

T9_OUTPUT="$(bash "$LINT_SCRIPT" "$T9_DIR/board" 2>&1 || true)"
if echo "$T9_OUTPUT" | grep -q "FEHLER AREA-FIELD board/areas.yaml Eintrag 2: doppelte order=1"; then
  pass "Test 9: AREA-FIELD bei doppelter order gemeldet (AC5)"
else
  fail "Test 9: AREA-FIELD fehlt oder falsch"
  echo "  Output: $T9_OUTPUT"
fi

# ===========================================================================
# Test 10: AC5/E2 — areas.yaml fehlt, kein Item referenziert area -> keine Fehler
# ===========================================================================
echo ""
echo "--- Test 10: AC5/E2 — areas.yaml fehlt, keine area-Referenz -> keine Bereichs-Fehler ---"

T10_DIR="${TEST_WORK_DIR}/test10"
setup_board "$T10_DIR"
make_feature "$T10_DIR" "F-001" "null"

T10_EXIT=0
T10_OUTPUT=""
set +e
T10_OUTPUT="$(bash "$LINT_SCRIPT" "$T10_DIR/board" 2>&1)"
T10_EXIT=$?
set -e

if echo "$T10_OUTPUT" | grep -q "AREA-"; then
  fail "Test 10: Bereichs-Fehler gemeldet, obwohl areas.yaml fehlt und kein Item area referenziert"
  echo "  Output: $T10_OUTPUT"
else
  pass "Test 10: keine Bereichs-Fehler bei fehlendem areas.yaml ohne area-Referenz (AC5, E2)"
fi

if [[ $T10_EXIT -eq 0 ]]; then
  pass "Test 10b: Exit 0 (Board sonst valide)"
else
  fail "Test 10b: Exit ${T10_EXIT} (erwartet 0)"
  echo "  Output: $T10_OUTPUT"
fi

# ===========================================================================
# Test 11: AC5 — areas.yaml: order unhashbar (YAML-Liste) -> AREA-FIELD, kein Crash
# ===========================================================================
echo ""
echo "--- Test 11: AC5 — order als YAML-Liste (unhashbar) -> AREA-FIELD statt Crash ---"

T11_DIR="${TEST_WORK_DIR}/test11"
setup_board "$T11_DIR"
make_areas_yaml "$T11_DIR" \
  "- id: board" \
  "  name: Board" \
  "  description: Test." \
  "  order:" \
  "    - 1" \
  "    - 2"

T11_EXIT=0
T11_OUTPUT=""
set +e
T11_OUTPUT="$(bash "$LINT_SCRIPT" "$T11_DIR/board" 2>&1)"
T11_EXIT=$?
set -e

if echo "$T11_OUTPUT" | grep -qF "FEHLER AREA-FIELD board/areas.yaml Eintrag 1: order=[1, 2] kein int"; then
  pass "Test 11a: AREA-FIELD bei unhashbarer order gemeldet statt stillem Crash (AC5)"
else
  fail "Test 11a: AREA-FIELD fehlt oder falsch (kein TypeError-Schutz?)"
  echo "  Output: $T11_OUTPUT"
fi

if [[ $T11_EXIT -eq 1 ]]; then
  pass "Test 11b: Exit 1 bei malformtem areas.yaml (kein stilles Exit 0)"
else
  fail "Test 11b: Exit ${T11_EXIT} (erwartet 1)"
  echo "  Output: $T11_OUTPUT"
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
