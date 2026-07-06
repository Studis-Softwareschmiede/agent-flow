#!/usr/bin/env bash
# tests/board-area-ops/run-test.sh
#
# Covers (board-area-ops): AC1, AC2, AC3, AC4, AC5
#   AC1 — `board area list` gibt board/areas.yaml als sortiertes JSON-Array
#         (id, name, description, order) aus; fehlt areas.yaml -> []
#         Exit 0 (Tests 1-2).
#   AC2 — `board area merge <a> <b> <ziel>` ist vollautomatisch: areas.yaml
#         wird angepasst (a/b entfernen, ziel behalten/anlegen), alle
#         area-Etiketten (Feature-area, Spec-area-Frontmatter,
#         Ideen-Inbox-Eintraege) von a/b auf ziel umgeschrieben; idempotent;
#         verschiebt keine Dateien/aendert keine Spec-IDs; unbekannter
#         Bereich -> kein Schreiben, Exit != 0 (Tests 3-8).
#   AC3 — `board archive-done-stories` verschiebt alle Stories mit status=Done
#         nach board/stories/archive/, aktualisiert betroffene Feature-Rollups,
#         anderer Status bleibt unangetastet, idempotent (Tests 9-13).
#   AC4 — `board area split <a> <a1> <a2>` ist assistiert: listet Specs/
#         Features(+Storys informativ)/Ideen-Inbox-Eintraege von <a> mit
#         Ziel-Vorschlag + Konfidenz; eindeutige Faelle werden direkt
#         umgeschrieben, unklare landen als Fragenkatalog
#         ({stage,id,frage,quelle,optionen}, stage="split"); verschiebt keine
#         Dateien/aendert keine Spec-IDs; unbekannter Quell-Bereich -> kein
#         Schreiben, Exit != 0 (Tests 15-19).
#   AC5 — atomares Schreiben (kein halber Zustand bei Fehler); ungueltige
#         Eingabe -> NICHTS geschrieben, Exit != 0 (Test 6 — unbekannter
#         Bereich; Test 14 — neuer <ziel>-Slug verletzt Kebab-Case-Pattern
#         aus board/areas.schema.json; Tests 15/16 — split-Analoga; split-
#         Heuristik ist token-frei/deterministisch — Tests 17-19).
#
# Self-Test fuer die `board area list`/`board area merge`/`board area split`-
# Erweiterung von `scripts/board` (docs/specs/board-area-ops.md). Verwendet
# /tmp-Fixtures — beruehrt NIEMALS das echte board/ des Repos.
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

# --- Split-spezifische Fixture-Helfer (Titel/Goal frei waehlbar fuer die Heuristik) ---

make_feature_titled() {
  local work_dir="$1" fid="$2" area="$3" title="$4" goal="$5"
  local slug
  slug="$(echo "$fid" | tr '[:upper:]' '[:lower:]')"
  cat > "${work_dir}/board/features/${fid}-${slug}.yaml" <<YAML
id: ${fid}
title: ${title}
goal: ${goal}
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

make_story_for() {
  local work_dir="$1" sid="$2" parent="$3" title="$4"
  local slug
  slug="$(echo "$sid" | tr '[:upper:]' '[:lower:]')"
  cat > "${work_dir}/board/stories/${sid}-${slug}.yaml" <<YAML
id: ${sid}
parent: ${parent}
title: ${title}
status: To Do
priority: P2
YAML
}

make_spec_titled() {
  local path="$1" id="$2" title="$3" area="$4"
  mkdir -p "$(dirname "$path")"
  {
    echo "---"
    echo "id: ${id}"
    echo "title: ${title}"
    echo "status: active"
    echo "area: ${area}"
    echo "---"
    echo "# ${title}"
  } > "$path"
}

make_ideas_inbox_titled() {
  local path="$1" heading="$2" area="$3"
  cat > "$path" <<MD
### ${heading}

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
# Test 2: AC1 — areas.yaml vorhanden -> JSON-Array sortiert nach order
# ===========================================================================
echo ""
echo "--- Test 2: AC1 — areas.yaml -> sortiertes JSON-Array (id,name,description,order) ---"

T2_DIR="${TEST_WORK_DIR}/test2"
setup_board "$T2_DIR"
make_areas_yaml "$T2_DIR" \
  "- id: flow-orchestrierung" \
  "  name: Flow-Orchestrierung" \
  "  description: Flow-Skill." \
  "  order: 2" \
  "- id: board" \
  "  name: Board" \
  "  description: Schema und CLI." \
  "  order: 1"

T2_OUTPUT="$(cd "$T2_DIR" && BOARD_DIR=board bash "$BOARD_SCRIPT" area list)"
T2_EXPECTED='[{"id": "board", "name": "Board", "description": "Schema und CLI.", "order": 1}, {"id": "flow-orchestrierung", "name": "Flow-Orchestrierung", "description": "Flow-Skill.", "order": 2}]'

if [[ "$T2_OUTPUT" == "$T2_EXPECTED" ]]; then
  pass "Test 2: JSON-Array korrekt sortiert nach order (AC1)"
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
  "  name: Alpha" \
  "  description: Alpha-Bereich." \
  "  order: 1" \
  "- id: beta" \
  "  name: Beta" \
  "  description: Beta-Bereich." \
  "  order: 2"
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

if echo "$T3_AREAS" | grep -A2 "id: gamma" | grep -q "name: Alpha"; then
  pass "Test 3c: neues ziel erbt name von <a> (Spec-Praezisierung)"
else
  fail "Test 3c: name-Vererbung falsch"
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
  "  name: Board" \
  "  description: Schema und CLI." \
  "  order: 1" \
  "- id: wegwerf" \
  "  name: Wegwerf" \
  "  description: Wird eingegliedert." \
  "  order: 2"
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
  "  name: Board" \
  "  description: Schema und CLI." \
  "  order: 1"
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
  "  name: Alpha" \
  "  description: Alpha-Bereich." \
  "  order: 1" \
  "- id: beta" \
  "  name: Beta" \
  "  description: Beta-Bereich." \
  "  order: 2"
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
  "  name: Alpha" \
  "  description: Alpha-Bereich." \
  "  order: 1" \
  "- id: beta" \
  "  name: Beta" \
  "  description: Beta-Bereich." \
  "  order: 2" \
  "- id: unbeteiligt" \
  "  name: Unbeteiligt" \
  "  description: Bleibt unberuehrt." \
  "  order: 3"
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
# Test 9: AC3 — archive-done-stories verschiebt Done-Stories nach archive/
# ===========================================================================
echo ""
echo "--- Test 9: AC3 — Done-Stories werden nach archive/ verschoben ---"

T9_DIR="${TEST_WORK_DIR}/test9"
setup_board "$T9_DIR"
make_areas_yaml "$T9_DIR" \
  "- id: board" \
  "  name: Board" \
  "  description: Schema und CLI." \
  "  order: 1"
make_feature "$T9_DIR" "F-001" "board"
make_story_for "$T9_DIR" "S-001" "F-001" "Done Story"
make_story_for "$T9_DIR" "S-002" "F-001" "Active Story"

# Setze S-001 auf Done, S-002 auf Active
sed -i.bak 's/status: To Do/status: Done/' "$T9_DIR/board/stories/S-001-s-001.yaml"
sed -i.bak 's/status: To Do/status: In Progress/' "$T9_DIR/board/stories/S-002-s-002.yaml"

T9_OUT="$(cd "$T9_DIR" && BOARD_DIR=board bash "$BOARD_SCRIPT" archive-done-stories)"

if echo "$T9_OUT" | grep -q "S-001"; then
  pass "Test 9a: archivierte Story-ID wird ausgegeben (AC3)"
else
  fail "Test 9a: S-001 nicht in Ausgabe (Output: $T9_OUT)"
fi

if [[ -f "$T9_DIR/board/stories/archive/S-001-s-001.yaml" ]]; then
  pass "Test 9b: Done-Story wurde nach archive/ verschoben (AC3)"
else
  fail "Test 9b: S-001 nicht in archive/"
fi

if [[ -f "$T9_DIR/board/stories/S-002-s-002.yaml" ]]; then
  pass "Test 9c: In-Progress-Story bleibt im aktiven Board (AC3)"
else
  fail "Test 9c: S-002 wurde faelschlich verschoben"
fi

if ! echo "$T9_OUT" | grep -q "S-002"; then
  pass "Test 9d: nicht-Done-Story wird nicht archiviert (AC3)"
else
  fail "Test 9d: S-002 in Ausgabe (sollte nicht archiviert werden)"
fi

# ===========================================================================
# Test 10: AC3/AC5 — Feature-Rollup wird nach Archivierung aktualisiert
# ===========================================================================
echo ""
echo "--- Test 10: AC3 — Feature-Rollup wird aktualisiert nach Archivierung ---"

T10_DIR="${TEST_WORK_DIR}/test10"
setup_board "$T10_DIR"
make_areas_yaml "$T10_DIR" \
  "- id: board" \
  "  name: Board" \
  "  description: Schema und CLI." \
  "  order: 1"
make_feature "$T10_DIR" "F-001" "board"
make_story_for "$T10_DIR" "S-010" "F-001" "Story eins"
make_story_for "$T10_DIR" "S-011" "F-001" "Story zwei"

# Beide Stories auf Done setzen
sed -i.bak 's/status: To Do/status: Done/' "$T10_DIR/board/stories/S-010-s-010.yaml"
sed -i.bak 's/status: To Do/status: Done/' "$T10_DIR/board/stories/S-011-s-011.yaml"

# Archivieren und Output erfassen
T10_OUTPUT="$(cd "$T10_DIR" && BOARD_DIR=board bash "$BOARD_SCRIPT" archive-done-stories)"

# (a) EXAKTER Output-Check: nur S-010 und S-011, sortiert, keine Extrahzeilen
T10_EXPECTED=$'S-010\nS-011'
if [[ "$T10_OUTPUT" == "$T10_EXPECTED" ]]; then
  pass "Test 10a: archive-done-stories Output exakt: Liste nur archivierter Story-IDs (AC3)"
else
  fail "Test 10a: Output weicht ab (erwartet: '$T10_EXPECTED', erhalten: '$T10_OUTPUT')"
fi

# (b) Feature-Rollup aktualisiert: stories und progress im Feature sollten sich geaendert haben
T10_AFTER="$(cat "$T10_DIR/board/features/F-001-f-001.yaml")"

# Prüfe stories-Feld: sollte jetzt null/leer sein (da alle Done und archiviert)
if echo "$T10_AFTER" | grep -q "stories: null" || echo "$T10_AFTER" | grep -q "stories: \[\]"; then
  pass "Test 10b: Feature stories-Feld nach Archivierung auf null/[] gesetzt (Rollup-Update)"
else
  fail "Test 10b: Feature stories-Feld nicht aktualisiert"
  echo "$T10_AFTER"
fi

# Prüfe progress-Feld: sollte sich ebenfalls aktualisiert haben (0/0 done, null, oder {})
if echo "$T10_AFTER" | grep -q "progress:" && echo "$T10_AFTER" | grep -qE "progress:\s*null|progress:\s*0/0|progress:\s*{}"; then
  pass "Test 10c: Feature progress-Feld nach Rollup aktualisiert (AC3)"
else
  fail "Test 10c: Feature progress-Feld nicht korrekt aktualisiert"
  echo "$T10_AFTER"
fi

if [[ -f "$T10_DIR/board/features/F-001-f-001.yaml" ]]; then
  pass "Test 10d: Feature-Datei bleibt bestehen nach Archivierung (AC3)"
else
  fail "Test 10d: Feature-Datei wurde faelschlich geloescht"
fi

# ===========================================================================
# Test 11: AC3 — archive-done-stories ist idempotent
# ===========================================================================
echo ""
echo "--- Test 11: AC3 — zweiter Aufruf ist idempotent (leere Ausgabe) ---"

T11_DIR="${TEST_WORK_DIR}/test11"
setup_board "$T11_DIR"
make_areas_yaml "$T11_DIR" \
  "- id: board" \
  "  name: Board" \
  "  description: Schema und CLI." \
  "  order: 1"
make_feature "$T11_DIR" "F-001" "board"
make_story_for "$T11_DIR" "S-100" "F-001" "Done Story"

sed -i.bak 's/status: To Do/status: Done/' "$T11_DIR/board/stories/S-100-s-100.yaml"

# Erster Aufruf
T11_OUT1="$(cd "$T11_DIR" && BOARD_DIR=board bash "$BOARD_SCRIPT" archive-done-stories)"

if echo "$T11_OUT1" | grep -q "S-100"; then
  pass "Test 11a: erstes Archivieren gibt Story-ID aus"
else
  fail "Test 11a: S-100 nicht in erstem Aufruf"
fi

# Zweiter Aufruf (idempotent)
T11_OUT2="$(cd "$T11_DIR" && BOARD_DIR=board bash "$BOARD_SCRIPT" archive-done-stories)"

if [[ -z "$T11_OUT2" ]] || [[ "$T11_OUT2" =~ ^[[:space:]]*$ ]]; then
  pass "Test 11b: zweiter Aufruf gibt leere Ausgabe (idempotent, AC3)"
else
  fail "Test 11b: zweiter Aufruf nicht leer (Output: '$T11_OUT2')"
fi

# ===========================================================================
# Test 12: AC3 — keine Done-Stories -> leere Ausgabe, Exit 0
# ===========================================================================
echo ""
echo "--- Test 12: AC3 — keine Done-Stories -> leere Ausgabe, Exit 0 ---"

T12_DIR="${TEST_WORK_DIR}/test12"
setup_board "$T12_DIR"
make_areas_yaml "$T12_DIR" \
  "- id: board" \
  "  name: Board" \
  "  description: Schema und CLI." \
  "  order: 1"
make_feature "$T12_DIR" "F-001" "board"
make_story_for "$T12_DIR" "S-200" "F-001" "To Do Story"
# Status ist bereits To Do

T12_EXIT=0
T12_OUT=""
set +e
T12_OUT="$(cd "$T12_DIR" && BOARD_DIR=board bash "$BOARD_SCRIPT" archive-done-stories)"
T12_EXIT=$?
set -e

if [[ $T12_EXIT -eq 0 ]]; then
  pass "Test 12a: Exit 0 wenn keine Done-Stories (AC3)"
else
  fail "Test 12a: Exit ${T12_EXIT} (erwartet 0)"
fi

if [[ -z "$T12_OUT" ]] || [[ "$T12_OUT" =~ ^[[:space:]]*$ ]]; then
  pass "Test 12b: leere Ausgabe wenn keine Done-Stories (AC3)"
else
  fail "Test 12b: Output nicht leer (${T12_OUT})"
fi

# ===========================================================================
# Test 13: AC3 — list/next/rollup ignorieren archivierte Stories
# ===========================================================================
echo ""
echo "--- Test 13: AC3 — list/next ignorieren archivierte Stories ---"

T13_DIR="${TEST_WORK_DIR}/test13"
setup_board "$T13_DIR"
make_areas_yaml "$T13_DIR" \
  "- id: board" \
  "  name: Board" \
  "  description: Schema und CLI." \
  "  order: 1"
make_feature "$T13_DIR" "F-001" "board"
make_story_for "$T13_DIR" "S-300" "F-001" "Story wird archiviert"

sed -i.bak 's/status: To Do/status: Done/' "$T13_DIR/board/stories/S-300-s-300.yaml"

# Archivieren
(cd "$T13_DIR" && BOARD_DIR=board bash "$BOARD_SCRIPT" archive-done-stories >/dev/null)

# next sollte die archivierte Story nicht auflisten
T13_NEXT="$(cd "$T13_DIR" && BOARD_DIR=board bash "$BOARD_SCRIPT" next 2>/dev/null || echo '')"

if ! echo "$T13_NEXT" | grep -q "S-300"; then
  pass "Test 13: archivierte Story wird von 'next' ignoriert (AC3)"
else
  fail "Test 13: archivierte Story noch in 'next' (Output: $T13_NEXT)"
fi

# ===========================================================================
# Test 14: AC5 — neuer <ziel>-Slug verletzt Kebab-Case-Pattern -> Fehler, kein Schreiben
# ===========================================================================
echo ""
echo "--- Test 14: AC5 — ungueltiger <ziel>-Slug (kein kebab-case) -> Fehler, kein Schreiben ---"

T9_DIR="${TEST_WORK_DIR}/test9"
setup_board "$T9_DIR"
make_areas_yaml "$T9_DIR" \
  "- id: alpha" \
  "  name: Alpha" \
  "  description: Alpha-Bereich." \
  "  order: 1" \
  "- id: beta" \
  "  name: Beta" \
  "  description: Beta-Bereich." \
  "  order: 2"
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
# Test 10: AC4/AC5 — split mit <a1>==<a2> ist ungueltige Eingabe -> Fehler, kein Schreiben
# ===========================================================================
echo ""
echo "--- Test 15: AC4/AC5 — split <a1>==<a2> -> Fehler, kein Schreiben ---"

T10_DIR="${TEST_WORK_DIR}/test10"
setup_board "$T10_DIR"
make_areas_yaml "$T10_DIR" \
  "- id: alpha" \
  "  name: Alpha" \
  "  description: Alpha-Bereich." \
  "  order: 1"
make_feature "$T10_DIR" "F-001" "alpha"

T10_AREAS_BEFORE="$(cat "$T10_DIR/board/areas.yaml")"
T10_F1_BEFORE="$(cat "$T10_DIR/board/features/F-001-f-001.yaml")"

T10_EXIT=0
set +e
T10_OUTPUT="$(cd "$T10_DIR" && BOARD_DIR=board bash "$BOARD_SCRIPT" area split alpha vorne vorne 2>&1)"
T10_EXIT=$?
set -e

if [[ $T10_EXIT -ne 0 ]]; then
  pass "Test 10a: Exit != 0 bei <a1>==<a2> (AC5)"
else
  fail "Test 10a: Exit 0 (erwartet != 0), Output: ${T10_OUTPUT}"
fi

T10_AREAS_AFTER="$(cat "$T10_DIR/board/areas.yaml")"
T10_F1_AFTER="$(cat "$T10_DIR/board/features/F-001-f-001.yaml")"
if [[ "$T10_AREAS_BEFORE" == "$T10_AREAS_AFTER" && "$T10_F1_BEFORE" == "$T10_F1_AFTER" ]]; then
  pass "Test 10b: nichts geschrieben bei <a1>==<a2> (AC5, atomar)"
else
  fail "Test 10b: Dateien trotz ungueltiger Eingabe veraendert"
fi

# ===========================================================================
# Test 11: AC4/E1 — split mit unbekanntem Quell-Bereich -> Fehler, kein Schreiben
# ===========================================================================
echo ""
echo "--- Test 16: AC4/E1 — split unbekannter Quell-Bereich -> Fehler, kein Schreiben ---"

T11_DIR="${TEST_WORK_DIR}/test11"
setup_board "$T11_DIR"
make_areas_yaml "$T11_DIR" \
  "- id: alpha" \
  "  name: Alpha" \
  "  description: Alpha-Bereich." \
  "  order: 1"

T11_AREAS_BEFORE="$(cat "$T11_DIR/board/areas.yaml")"

T11_EXIT=0
set +e
T11_OUTPUT="$(cd "$T11_DIR" && BOARD_DIR=board bash "$BOARD_SCRIPT" area split nirgendwo vorne hinten 2>&1)"
T11_EXIT=$?
set -e

if [[ $T11_EXIT -ne 0 ]]; then
  pass "Test 11a: Exit != 0 bei unbekanntem Quell-Bereich (E1)"
else
  fail "Test 11a: Exit 0 (erwartet != 0), Output: ${T11_OUTPUT}"
fi

T11_AREAS_AFTER="$(cat "$T11_DIR/board/areas.yaml")"
if [[ "$T11_AREAS_BEFORE" == "$T11_AREAS_AFTER" ]]; then
  pass "Test 11b: areas.yaml unveraendert bei unbekanntem Quell-Bereich (AC5, atomar)"
else
  fail "Test 11b: areas.yaml trotz unbekanntem Quell-Bereich veraendert"
fi

# ===========================================================================
# Test 12: AC4/A1 — alle Artefakte eindeutig -> leerer Fragenkatalog, direkte
# Zuordnung (Feature/Spec/Idee), Quell-Bereich entfernt, Storys informativ
# ===========================================================================
echo ""
echo "--- Test 17: AC4/A1 — alles eindeutig -> [] Fragenkatalog, direkte Zuordnung ---"

T12_DIR="${TEST_WORK_DIR}/test12"
setup_board "$T12_DIR"
make_areas_yaml "$T12_DIR" \
  "- id: alpha" \
  "  name: Alpha" \
  "  description: Alpha-Bereich mit Frontend und Backend." \
  "  order: 1"
make_feature_titled "$T12_DIR" "F-001" "alpha" "Frontend Dashboard" "Frontend-Testfeature"
make_feature_titled "$T12_DIR" "F-002" "alpha" "Backend Api Service" "Backend-Testfeature"
make_story_for "$T12_DIR" "S-010" "F-001" "Dashboard Redesign"
make_spec_titled "${T12_DIR}/docs/specs/frontend-widgets.md" "frontend-widgets" "Frontend Widgets" "alpha"
make_ideas_inbox_titled "${T12_DIR}/docs/ideas-inbox.md" "Backend Cronjob Idee" "alpha"

T12_OUT="$(cd "$T12_DIR" && BOARD_DIR=board bash "$BOARD_SCRIPT" area split alpha frontend backend)"

T12_KATALOG="$(echo "$T12_OUT" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["fragenkatalog"]))')"
if [[ "$T12_KATALOG" == "0" ]]; then
  pass "Test 12a: leerer Fragenkatalog, wenn alle Artefakte eindeutig (A1)"
else
  fail "Test 12a: Fragenkatalog nicht leer (${T12_KATALOG} Eintraege)"
  echo "$T12_OUT"
fi

T12_ENTFERNT="$(echo "$T12_OUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["quell_bereich_entfernt"])')"
if [[ "$T12_ENTFERNT" == "True" ]]; then
  pass "Test 12b: quell_bereich_entfernt=true, wenn alles zugeordnet ist"
else
  fail "Test 12b: quell_bereich_entfernt=${T12_ENTFERNT} (erwartet True)"
fi

T12_AREAS="$(cat "$T12_DIR/board/areas.yaml")"
if echo "$T12_AREAS" | grep -q "id: frontend" && echo "$T12_AREAS" | grep -q "id: backend" && ! echo "$T12_AREAS" | grep -q "id: alpha"; then
  pass "Test 12c: areas.yaml enthaelt frontend/backend, alpha entfernt"
else
  fail "Test 12c: areas.yaml falsch"
  echo "$T12_AREAS"
fi

T12_F1_AREA="$(grep '^area:' "$T12_DIR/board/features/F-001-f-001.yaml")"
T12_F2_AREA="$(grep '^area:' "$T12_DIR/board/features/F-002-f-002.yaml")"
if [[ "$T12_F1_AREA" == "area: frontend" && "$T12_F2_AREA" == "area: backend" ]]; then
  pass "Test 12d: Feature-area-Etiketten korrekt auf frontend/backend umgeschrieben (AC4)"
else
  fail "Test 12d: Feature-area falsch (F-001: ${T12_F1_AREA}, F-002: ${T12_F2_AREA})"
fi

T12_SPEC_AREA="$(grep '^area:' "${T12_DIR}/docs/specs/frontend-widgets.md")"
if [[ "$T12_SPEC_AREA" == "area: frontend" ]]; then
  pass "Test 12e: Spec-area-Frontmatter korrekt auf frontend umgeschrieben (AC4)"
else
  fail "Test 12e: Spec-area falsch (${T12_SPEC_AREA})"
fi

T12_IDEA_AREA="$(grep '^- area:' "${T12_DIR}/docs/ideas-inbox.md")"
if [[ "$T12_IDEA_AREA" == "- area: backend" ]]; then
  pass "Test 12f: Ideen-Inbox-area korrekt auf backend umgeschrieben (AC4)"
else
  fail "Test 12f: Ideen-Inbox-area falsch (${T12_IDEA_AREA})"
fi

# Story traegt kein eigenes area-Feld: Datei bleibt inhaltlich unveraendert,
# folgt aber informativ der Feature-Entscheidung im Report (Spec-Praezisierung).
T12_STORY_FILE="$(cat "$T12_DIR/board/stories/S-010-s-010.yaml")"
if ! echo "$T12_STORY_FILE" | grep -q "^area:"; then
  pass "Test 12g: Story-Datei bleibt ohne eigenes area-Feld (kein Reparenting, Nicht-Ziel)"
else
  fail "Test 12g: Story-Datei wurde unerwartet um ein area-Feld ergaenzt"
fi

T12_STORY_ROW="$(echo "$T12_OUT" | python3 -c '
import json, sys
data = json.load(sys.stdin)
rows = [r for r in data["zuordnungen"] if r["typ"] == "story" and r["id"] == "S-010"]
print(rows[0]["ziel_vorschlag"] if rows else "MISSING")
')"
if [[ "$T12_STORY_ROW" == "frontend" ]]; then
  pass "Test 12h: Story erscheint im Report informativ mit dem Ziel ihres Eltern-Features (AC4)"
else
  fail "Test 12h: Story-Report-Zeile falsch (${T12_STORY_ROW}, erwartet 'frontend')"
fi

# ===========================================================================
# Test 18: AC4 — unklarer Fall landet als Fragenkatalog; Quell-Bereich bleibt bestehen
# ===========================================================================
echo ""
echo "--- Test 18: AC4 — unklarer Fall -> Fragenkatalog, Quell-Bereich bleibt bestehen ---"

T13_DIR="${TEST_WORK_DIR}/test13"
setup_board "$T13_DIR"
make_areas_yaml "$T13_DIR" \
  "- id: alpha" \
  "  name: Alpha" \
  "  description: Alpha-Bereich mit Frontend und Backend." \
  "  order: 1"
make_feature_titled "$T13_DIR" "F-001" "alpha" "Frontend Dashboard" "Frontend-Testfeature"
make_spec_titled "${T13_DIR}/docs/specs/mystery-spec.md" "mystery-spec" "Voellig Unklare Anforderung" "alpha"

T13_OUT="$(cd "$T13_DIR" && BOARD_DIR=board bash "$BOARD_SCRIPT" area split alpha frontend backend)"

T13_KATALOG_LEN="$(echo "$T13_OUT" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["fragenkatalog"]))')"
if [[ "$T13_KATALOG_LEN" == "1" ]]; then
  pass "Test 13a: unklares Artefakt landet im Fragenkatalog (1 Eintrag)"
else
  fail "Test 13a: Fragenkatalog hat ${T13_KATALOG_LEN} Eintraege (erwartet 1)"
  echo "$T13_OUT"
fi

T13_FRAGE_JSON="$(echo "$T13_OUT" | python3 -c 'import json,sys; print(json.dumps(json.load(sys.stdin)["fragenkatalog"][0]))')"
T13_STAGE="$(echo "$T13_FRAGE_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin)["stage"])')"
T13_ID="$(echo "$T13_FRAGE_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')"
T13_OPTIONEN="$(echo "$T13_FRAGE_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin)["optionen"])')"

if [[ "$T13_STAGE" == "split" ]]; then
  pass "Test 13b: Fragenkatalog-Eintrag traegt stage='split' (Schema-Erweiterung)"
else
  fail "Test 13b: stage='${T13_STAGE}' (erwartet 'split')"
fi

if [[ "$T13_ID" =~ ^split-[0-9]+$ ]]; then
  pass "Test 13c: Fragenkatalog-id folgt Muster split-<n> (AC9-Vertrag)"
else
  fail "Test 13c: id='${T13_ID}' verletzt Muster split-<n>"
fi

if [[ "$T13_OPTIONEN" == "['frontend', 'backend']" ]]; then
  pass "Test 13d: optionen listet <a1>/<a2>"
else
  fail "Test 13d: optionen='${T13_OPTIONEN}' (erwartet ['frontend', 'backend'])"
fi

T13_SPEC_AREA="$(grep '^area:' "${T13_DIR}/docs/specs/mystery-spec.md")"
if [[ "$T13_SPEC_AREA" == "area: alpha" ]]; then
  pass "Test 13e: unklare Spec bleibt bei area=alpha (keine Zuordnung ohne Klaerung)"
else
  fail "Test 13e: unklare Spec wurde veraendert (${T13_SPEC_AREA})"
fi

T13_AREAS="$(cat "$T13_DIR/board/areas.yaml")"
if echo "$T13_AREAS" | grep -q "id: alpha"; then
  pass "Test 13f: Quell-Bereich 'alpha' bleibt bestehen, solange offene Fragen (E2)"
else
  fail "Test 13f: 'alpha' faelschlich entfernt trotz offener Frage"
  echo "$T13_AREAS"
fi

# frontend (eindeutig zugeordnetes Feature) wird trotzdem schon angelegt/geschrieben.
T13_F1_AREA="$(grep '^area:' "$T13_DIR/board/features/F-001-f-001.yaml")"
if [[ "$T13_F1_AREA" == "area: frontend" ]]; then
  pass "Test 13g: eindeutiges Feature wird trotz offener Frage bei anderem Artefakt direkt zugeordnet"
else
  fail "Test 13g: Feature-area falsch (${T13_F1_AREA})"
fi

# ===========================================================================
# Test 19: AC4/E2 — neue Ziel-Bereiche werden mit Platzhalter + naechster order angelegt
# ===========================================================================
echo ""
echo "--- Test 19: AC4/E2 — neue Ziel-Bereiche in areas.yaml (Platzhalter, order) ---"

T14_DIR="${TEST_WORK_DIR}/test14"
setup_board "$T14_DIR"
make_areas_yaml "$T14_DIR" \
  "- id: alpha" \
  "  name: Alpha" \
  "  description: Alpha-Bereich." \
  "  order: 5"
make_feature_titled "$T14_DIR" "F-001" "alpha" "Frontend Dashboard" "Frontend-Testfeature"

(cd "$T14_DIR" && BOARD_DIR=board bash "$BOARD_SCRIPT" area split alpha frontend backend >/dev/null)

T14_AREAS="$(cat "$T14_DIR/board/areas.yaml")"
if echo "$T14_AREAS" | grep -A3 "id: frontend" | grep -q "order: 6"; then
  pass "Test 14a: neuer Ziel-Bereich 'frontend' erhaelt naechste order (6)"
else
  fail "Test 14a: order falsch"
  echo "$T14_AREAS"
fi

if echo "$T14_AREAS" | grep -A3 "id: backend" | grep -q "order: 7"; then
  pass "Test 14b: neuer Ziel-Bereich 'backend' erhaelt naechste order (7)"
else
  fail "Test 14b: order falsch"
  echo "$T14_AREAS"
fi

if echo "$T14_AREAS" | grep -q "TODO: Beschreibung nach Split von ''alpha'' ergaenzen."; then
  pass "Test 14c: neue Ziel-Bereiche erhalten Platzhalter-description (E2)"
else
  fail "Test 14c: Platzhalter-description fehlt"
  echo "$T14_AREAS"
fi

# ===========================================================================
# Test 20: AC5 — split-Heuristik ist deterministisch (zweiter identischer
# Aufruf auf denselben Ausgangszustand liefert dasselbe Ergebnis)
# ===========================================================================
echo ""
echo "--- Test 20: AC5 — split-Heuristik ist deterministisch ---"

T15_DIR_A="${TEST_WORK_DIR}/test15a"
T15_DIR_B="${TEST_WORK_DIR}/test15b"
for T15_DIR in "$T15_DIR_A" "$T15_DIR_B"; do
  setup_board "$T15_DIR"
  make_areas_yaml "$T15_DIR" \
    "- id: alpha" \
    "  name: Alpha" \
    "  description: Alpha-Bereich mit Frontend und Backend." \
    "  order: 1"
  make_feature_titled "$T15_DIR" "F-001" "alpha" "Frontend Dashboard" "Frontend-Testfeature"
  make_feature_titled "$T15_DIR" "F-002" "alpha" "Backend Api Service" "Backend-Testfeature"
done

T15_OUT_A="$(cd "$T15_DIR_A" && BOARD_DIR=board bash "$BOARD_SCRIPT" area split alpha frontend backend)"
T15_OUT_B="$(cd "$T15_DIR_B" && BOARD_DIR=board bash "$BOARD_SCRIPT" area split alpha frontend backend)"

if [[ "$T15_OUT_A" == "$T15_OUT_B" ]]; then
  pass "Test 15: split-Heuristik ist deterministisch (identischer Ausgangszustand -> identisches Ergebnis, AC5)"
else
  fail "Test 15: split-Ergebnis weicht bei identischem Ausgangszustand ab"
  echo "A: $T15_OUT_A"
  echo "B: $T15_OUT_B"
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
