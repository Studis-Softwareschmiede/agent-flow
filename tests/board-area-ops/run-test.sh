#!/usr/bin/env bash
# tests/board-area-ops/run-test.sh
#
# Covers (board-area-ops): AC1, AC2, AC5
#   AC1 — `board area list` gibt board/areas.yaml als sortiertes JSON-Array
#         (id, titel, beschreibung, reihenfolge) aus; fehlt areas.yaml -> []
#         Exit 0 (Tests 1-2).
#   AC2 — `board area merge <a> <b> <ziel>` ist vollautomatisch: areas.yaml
#         wird angepasst (a/b entfernen, ziel behalten/anlegen), alle
#         area-Etiketten (Feature-area, Spec-area-Frontmatter,
#         Ideen-Inbox-Eintraege) von a/b auf ziel umgeschrieben; idempotent;
#         verschiebt keine Dateien/aendert keine Spec-IDs; unbekannter
#         Bereich -> kein Schreiben, Exit != 0 (Tests 3-8).
#   AC5 — atomares Schreiben (kein halber Zustand bei Fehler); ungueltige
#         Eingabe -> NICHTS geschrieben, Exit != 0 (Test 6 — unbekannter
#         Bereich; Test 9 — neuer <ziel>-Slug verletzt Kebab-Case-Pattern
#         aus board/areas.schema.json).
#
# Self-Test fuer die `board area list`/`board area merge`-Erweiterung von
# `scripts/board` (docs/specs/board-area-ops.md). Verwendet /tmp-Fixtures —
# beruehrt NIEMALS das echte board/ des Repos.
#
# Exit: 0 = alle Tests bestanden, 1 = mindestens ein Fehler

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
BOARD_SCRIPT="${REPO_ROOT}/scripts/board"

# Eigene TMPDIR-Variable (reviewer/L05: $TMPDIR nie ueberschreiben)
TEST_WORK_DIR="$(mktemp -d /tmp/board-area-ops-test.XXXXXX)"
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

make_ideas_inbox() {
  local path="$1" area="$2"
  cat > "$path" <<MD
### Idee eins

- status: Idee
- created_at: 2026-01-01T00:00:00Z
- begruendung: Testeintrag
- area: ${area}

Eine testweise Idee.
MD
}

# ===========================================================================
# Test 1: AC1 — areas.yaml fehlt -> leeres Array, Exit 0
# ===========================================================================
echo ""
echo "--- Test 1: AC1 — areas.yaml fehlt -> [] Exit 0 ---"

T1_DIR="${TEST_WORK_DIR}/test1"
setup_board "$T1_DIR"

T1_EXIT=0
T1_OUTPUT=""
set +e
T1_OUTPUT="$(cd "$T1_DIR" && BOARD_DIR=board bash "$BOARD_SCRIPT" area list)"
T1_EXIT=$?
set -e

if [[ "$T1_OUTPUT" == "[]" ]]; then
  pass "Test 1a: leeres Array bei fehlender areas.yaml (AC1)"
else
  fail "Test 1a: Output '${T1_OUTPUT}' (erwartet '[]')"
fi
if [[ $T1_EXIT -eq 0 ]]; then
  pass "Test 1b: Exit 0 (AC1)"
else
  fail "Test 1b: Exit ${T1_EXIT} (erwartet 0)"
fi

# ===========================================================================
# Test 2: AC1 — areas.yaml vorhanden -> JSON-Array sortiert nach reihenfolge
# ===========================================================================
echo ""
echo "--- Test 2: AC1 — areas.yaml -> sortiertes JSON-Array (id,titel,beschreibung,reihenfolge) ---"

T2_DIR="${TEST_WORK_DIR}/test2"
setup_board "$T2_DIR"
make_areas_yaml "$T2_DIR" \
  "- id: flow-orchestrierung" \
  "  titel: Flow-Orchestrierung" \
  "  beschreibung: Flow-Skill." \
  "  reihenfolge: 2" \
  "- id: board" \
  "  titel: Board" \
  "  beschreibung: Schema und CLI." \
  "  reihenfolge: 1"

T2_OUTPUT="$(cd "$T2_DIR" && BOARD_DIR=board bash "$BOARD_SCRIPT" area list)"
T2_EXPECTED='[{"id": "board", "titel": "Board", "beschreibung": "Schema und CLI.", "reihenfolge": 1}, {"id": "flow-orchestrierung", "titel": "Flow-Orchestrierung", "beschreibung": "Flow-Skill.", "reihenfolge": 2}]'

if [[ "$T2_OUTPUT" == "$T2_EXPECTED" ]]; then
  pass "Test 2: JSON-Array korrekt sortiert nach reihenfolge (AC1)"
else
  fail "Test 2: Output weicht ab"
  echo "  erwartet: $T2_EXPECTED"
  echo "  erhalten: $T2_OUTPUT"
fi

# ===========================================================================
# Test 3: AC2 — merge zweier bestehender Bereiche in neues <ziel>
# ===========================================================================
echo ""
echo "--- Test 3: AC2 — merge a+b -> neues ziel (areas.yaml + Feature + Spec) ---"

T3_DIR="${TEST_WORK_DIR}/test3"
setup_board "$T3_DIR"
make_areas_yaml "$T3_DIR" \
  "- id: alpha" \
  "  titel: Alpha" \
  "  beschreibung: Alpha-Bereich." \
  "  reihenfolge: 1" \
  "- id: beta" \
  "  titel: Beta" \
  "  beschreibung: Beta-Bereich." \
  "  reihenfolge: 2"
make_feature "$T3_DIR" "F-001" "alpha"
make_feature "$T3_DIR" "F-002" "beta"
make_spec "${T3_DIR}/docs/specs/orphan-a.md" "alpha"
make_spec "${T3_DIR}/docs/specs/orphan-b.md" "beta"

T3_OUT="$(cd "$T3_DIR" && BOARD_DIR=board bash "$BOARD_SCRIPT" area merge alpha beta gamma)"

if [[ "$T3_OUT" == "gamma" ]]; then
  pass "Test 3a: merge gibt <ziel> aus"
else
  fail "Test 3a: Output '${T3_OUT}' (erwartet 'gamma')"
fi

T3_AREAS="$(cat "$T3_DIR/board/areas.yaml")"
if echo "$T3_AREAS" | grep -q "id: gamma" && ! echo "$T3_AREAS" | grep -q "id: alpha" && ! echo "$T3_AREAS" | grep -q "id: beta"; then
  pass "Test 3b: areas.yaml enthaelt gamma, nicht mehr alpha/beta (AC2)"
else
  fail "Test 3b: areas.yaml falsch"
  echo "$T3_AREAS"
fi

if echo "$T3_AREAS" | grep -A2 "id: gamma" | grep -q "titel: Alpha"; then
  pass "Test 3c: neues ziel erbt titel von <a> (Spec-Praezisierung)"
else
  fail "Test 3c: titel-Vererbung falsch"
  echo "$T3_AREAS"
fi

T3_F1_AREA="$(grep '^area:' "$T3_DIR/board/features/F-001-f-001.yaml")"
T3_F2_AREA="$(grep '^area:' "$T3_DIR/board/features/F-002-f-002.yaml")"
if [[ "$T3_F1_AREA" == "area: gamma" && "$T3_F2_AREA" == "area: gamma" ]]; then
  pass "Test 3d: Feature-area-Etiketten auf gamma umgeschrieben (AC2)"
else
  fail "Test 3d: Feature-area falsch (F-001: ${T3_F1_AREA}, F-002: ${T3_F2_AREA})"
fi

T3_SPEC_A_AREA="$(grep '^area:' "${T3_DIR}/docs/specs/orphan-a.md")"
T3_SPEC_B_AREA="$(grep '^area:' "${T3_DIR}/docs/specs/orphan-b.md")"
if [[ "$T3_SPEC_A_AREA" == "area: gamma" && "$T3_SPEC_B_AREA" == "area: gamma" ]]; then
  pass "Test 3e: Spec-area-Frontmatter auf gamma umgeschrieben (AC2)"
else
  fail "Test 3e: Spec-area falsch (a: ${T3_SPEC_A_AREA}, b: ${T3_SPEC_B_AREA})"
fi

# Spec-Rumpf (Body) darf unveraendert bleiben — keine Spec-ID-Aenderung.
if grep -q "^id: test-spec$" "${T3_DIR}/docs/specs/orphan-a.md" && grep -q "^# Test Spec$" "${T3_DIR}/docs/specs/orphan-a.md"; then
  pass "Test 3f: Spec-id/Body unveraendert (keine Spec-ID-Aenderung)"
else
  fail "Test 3f: Spec-Body/id veraendert"
fi

# ===========================================================================
# Test 4: AC2 — Idempotenz: zweiter, identischer Aufruf aendert nichts
# ===========================================================================
echo ""
echo "--- Test 4: AC2 — zweiter identischer merge-Aufruf ist idempotent ---"

T4_AREAS_BEFORE="$(cat "$T3_DIR/board/areas.yaml")"
T4_F1_BEFORE="$(cat "$T3_DIR/board/features/F-001-f-001.yaml")"

T4_EXIT=0
set +e
T4_OUT="$(cd "$T3_DIR" && BOARD_DIR=board bash "$BOARD_SCRIPT" area merge alpha beta gamma)"
T4_EXIT=$?
set -e

if [[ $T4_EXIT -eq 0 && "$T4_OUT" == "gamma" ]]; then
  pass "Test 4a: zweiter Aufruf erfolgreich (Exit 0, AC2)"
else
  fail "Test 4a: zweiter Aufruf fehlgeschlagen (Exit ${T4_EXIT}, Output '${T4_OUT}')"
fi

T4_AREAS_AFTER="$(cat "$T3_DIR/board/areas.yaml")"
T4_F1_AFTER="$(cat "$T3_DIR/board/features/F-001-f-001.yaml")"

if [[ "$T4_AREAS_BEFORE" == "$T4_AREAS_AFTER" ]]; then
  pass "Test 4b: areas.yaml unveraendert nach zweitem Aufruf (Idempotenz, AC2)"
else
  fail "Test 4b: areas.yaml hat sich beim zweiten Aufruf veraendert"
fi

if [[ "$T4_F1_BEFORE" == "$T4_F1_AFTER" ]]; then
  pass "Test 4c: Feature-Datei unveraendert nach zweitem Aufruf (Idempotenz, AC2)"
else
  fail "Test 4c: Feature-Datei hat sich beim zweiten Aufruf veraendert"
fi

# ===========================================================================
# Test 5: AC2/Edge-Case — a==ziel (bestehend): b wird eingegliedert, kein Fehler
# ===========================================================================
echo ""
echo "--- Test 5: AC2 — a==ziel (bestehend) -> b eingegliedert, kein Fehler ---"

T5_DIR="${TEST_WORK_DIR}/test5"
setup_board "$T5_DIR"
make_areas_yaml "$T5_DIR" \
  "- id: board" \
  "  titel: Board" \
  "  beschreibung: Schema und CLI." \
  "  reihenfolge: 1" \
  "- id: wegwerf" \
  "  titel: Wegwerf" \
  "  beschreibung: Wird eingegliedert." \
  "  reihenfolge: 2"
make_feature "$T5_DIR" "F-001" "wegwerf"

T5_EXIT=0
set +e
T5_OUT="$(cd "$T5_DIR" && BOARD_DIR=board bash "$BOARD_SCRIPT" area merge board wegwerf board)"
T5_EXIT=$?
set -e

if [[ $T5_EXIT -eq 0 && "$T5_OUT" == "board" ]]; then
  pass "Test 5a: a==ziel -> kein Fehler (Edge-Case)"
else
  fail "Test 5a: Exit ${T5_EXIT}, Output '${T5_OUT}' (erwartet Exit 0, 'board')"
fi

T5_AREAS="$(cat "$T5_DIR/board/areas.yaml")"
if echo "$T5_AREAS" | grep -q "id: board" && ! echo "$T5_AREAS" | grep -q "id: wegwerf"; then
  pass "Test 5b: 'wegwerf' entfernt, 'board' bleibt bestehen"
else
  fail "Test 5b: areas.yaml falsch"
  echo "$T5_AREAS"
fi

T5_F1_AREA="$(grep '^area:' "$T5_DIR/board/features/F-001-f-001.yaml")"
if [[ "$T5_F1_AREA" == "area: board" ]]; then
  pass "Test 5c: Feature-area von 'wegwerf' auf 'board' umgeschrieben"
else
  fail "Test 5c: Feature-area falsch (${T5_F1_AREA})"
fi

# ===========================================================================
# Test 6: AC2/E1/AC5 — unbekannter Bereich (weder a/b/ziel bekannt) -> Fehler, kein Schreiben
# ===========================================================================
echo ""
echo "--- Test 6: AC2/E1/AC5 — unbekannter Bereich -> Fehler, kein Schreiben ---"

T6_DIR="${TEST_WORK_DIR}/test6"
setup_board "$T6_DIR"
make_areas_yaml "$T6_DIR" \
  "- id: board" \
  "  titel: Board" \
  "  beschreibung: Schema und CLI." \
  "  reihenfolge: 1"
make_feature "$T6_DIR" "F-001" "board"

T6_AREAS_BEFORE="$(cat "$T6_DIR/board/areas.yaml")"
T6_F1_BEFORE="$(cat "$T6_DIR/board/features/F-001-f-001.yaml")"

T6_EXIT=0
T6_OUTPUT=""
set +e
T6_OUTPUT="$(cd "$T6_DIR" && BOARD_DIR=board bash "$BOARD_SCRIPT" area merge nirgends niemals nichts 2>&1)"
T6_EXIT=$?
set -e

if [[ $T6_EXIT -ne 0 ]]; then
  pass "Test 6a: Exit != 0 bei unbekanntem Bereich (E1)"
else
  fail "Test 6a: Exit 0 (erwartet != 0)"
fi

T6_AREAS_AFTER="$(cat "$T6_DIR/board/areas.yaml")"
T6_F1_AFTER="$(cat "$T6_DIR/board/features/F-001-f-001.yaml")"

if [[ "$T6_AREAS_BEFORE" == "$T6_AREAS_AFTER" && "$T6_F1_BEFORE" == "$T6_F1_AFTER" ]]; then
  pass "Test 6b: keine Datei veraendert bei ungueltiger Eingabe (AC5, atomar)"
else
  fail "Test 6b: Dateien wurden trotz Fehler veraendert"
fi

# ===========================================================================
# Test 7: AC2 — Ideen-Inbox-Eintraege werden mechanisch umgeschrieben
# ===========================================================================
echo ""
echo "--- Test 7: AC2 — Ideen-Inbox '- area:'-Eintrag wird umgeschrieben ---"

T7_DIR="${TEST_WORK_DIR}/test7"
setup_board "$T7_DIR"
make_areas_yaml "$T7_DIR" \
  "- id: alpha" \
  "  titel: Alpha" \
  "  beschreibung: Alpha-Bereich." \
  "  reihenfolge: 1" \
  "- id: beta" \
  "  titel: Beta" \
  "  beschreibung: Beta-Bereich." \
  "  reihenfolge: 2"
make_ideas_inbox "${T7_DIR}/docs/ideas-inbox.md" "alpha"

(cd "$T7_DIR" && BOARD_DIR=board bash "$BOARD_SCRIPT" area merge alpha beta gamma >/dev/null)

T7_IDEA_AREA="$(grep '^- area:' "${T7_DIR}/docs/ideas-inbox.md")"
if [[ "$T7_IDEA_AREA" == "- area: gamma" ]]; then
  pass "Test 7: Ideen-Inbox-area-Eintrag mechanisch auf gamma umgeschrieben (AC2)"
else
  fail "Test 7: Ideen-Inbox-area falsch (${T7_IDEA_AREA})"
fi

# ===========================================================================
# Test 8: AC2 — merge unbeteiligter Feature bleibt unangetastet
# ===========================================================================
echo ""
echo "--- Test 8: AC2 — Feature mit anderem Bereich bleibt unveraendert ---"

T8_DIR="${TEST_WORK_DIR}/test8"
setup_board "$T8_DIR"
make_areas_yaml "$T8_DIR" \
  "- id: alpha" \
  "  titel: Alpha" \
  "  beschreibung: Alpha-Bereich." \
  "  reihenfolge: 1" \
  "- id: beta" \
  "  titel: Beta" \
  "  beschreibung: Beta-Bereich." \
  "  reihenfolge: 2" \
  "- id: unbeteiligt" \
  "  titel: Unbeteiligt" \
  "  beschreibung: Bleibt unberuehrt." \
  "  reihenfolge: 3"
make_feature "$T8_DIR" "F-001" "alpha"
make_feature "$T8_DIR" "F-002" "unbeteiligt"

(cd "$T8_DIR" && BOARD_DIR=board bash "$BOARD_SCRIPT" area merge alpha beta gamma >/dev/null)

T8_F2_AREA="$(grep '^area:' "$T8_DIR/board/features/F-002-f-002.yaml")"
if [[ "$T8_F2_AREA" == "area: unbeteiligt" ]]; then
  pass "Test 8: unbeteiligtes Feature bleibt unveraendert (kein Kollateralschaden)"
else
  fail "Test 8: unbeteiligtes Feature veraendert (${T8_F2_AREA})"
fi

T8_AREAS="$(cat "$T8_DIR/board/areas.yaml")"
if echo "$T8_AREAS" | grep -q "id: unbeteiligt"; then
  pass "Test 8b: 'unbeteiligt' bleibt in areas.yaml bestehen"
else
  fail "Test 8b: 'unbeteiligt' faelschlich entfernt"
  echo "$T8_AREAS"
fi

# ===========================================================================
# Test 9: AC5 — neuer <ziel>-Slug verletzt Kebab-Case-Pattern -> Fehler, kein Schreiben
# ===========================================================================
echo ""
echo "--- Test 9: AC5 — ungueltiger <ziel>-Slug (kein kebab-case) -> Fehler, kein Schreiben ---"

T9_DIR="${TEST_WORK_DIR}/test9"
setup_board "$T9_DIR"
make_areas_yaml "$T9_DIR" \
  "- id: alpha" \
  "  titel: Alpha" \
  "  beschreibung: Alpha-Bereich." \
  "  reihenfolge: 1" \
  "- id: beta" \
  "  titel: Beta" \
  "  beschreibung: Beta-Bereich." \
  "  reihenfolge: 2"
make_feature "$T9_DIR" "F-001" "alpha"

T9_AREAS_BEFORE="$(cat "$T9_DIR/board/areas.yaml")"
T9_F1_BEFORE="$(cat "$T9_DIR/board/features/F-001-f-001.yaml")"

T9_EXIT=0
T9_OUTPUT=""
set +e
T9_OUTPUT="$(cd "$T9_DIR" && BOARD_DIR=board bash "$BOARD_SCRIPT" area merge alpha beta "My Invalid Ziel" 2>&1)"
T9_EXIT=$?
set -e

if [[ $T9_EXIT -ne 0 ]]; then
  pass "Test 9a: Exit != 0 bei ungueltigem <ziel>-Slug (AC5)"
else
  fail "Test 9a: Exit 0 (erwartet != 0), Output: ${T9_OUTPUT}"
fi

T9_AREAS_AFTER="$(cat "$T9_DIR/board/areas.yaml")"
T9_F1_AFTER="$(cat "$T9_DIR/board/features/F-001-f-001.yaml")"

if [[ "$T9_AREAS_BEFORE" == "$T9_AREAS_AFTER" && "$T9_F1_BEFORE" == "$T9_F1_AFTER" ]]; then
  pass "Test 9b: areas.yaml/Feature unveraendert bei ungueltigem <ziel>-Slug (AC5, atomar)"
else
  fail "Test 9b: Dateien wurden trotz ungueltigem <ziel>-Slug veraendert"
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
