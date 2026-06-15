#!/usr/bin/env bash
# tests/board-github-export/run-test.sh
#
# Self-Test für board-github-export gegen Mock-Daten.
# Verwendet /tmp — berührt NIEMALS das echte board/ des Repos.
#
# Testziele:
#   - Stories + Features korrekt erzeugt (AC1–AC3)
#   - depends aufgelöst (AC4)
#   - board.yaml Zähler korrekt (AC5)
#   - lint grün (AC6)
#   - Report plausibel (AC7)
#   - Zweiter Lauf bricht ab (AC10)
#   - --force ermöglicht zweiten Lauf
#
# Exit: 0 = alle Tests bestanden, 1 = mindestens ein Fehler

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
EXPORT_SCRIPT="${REPO_ROOT}/scripts/board-github-export"
LINT_SCRIPT="${REPO_ROOT}/scripts/board-lint.sh"

# Eigene TMPDIR-Variable (reviewer/L05: $TMPDIR nie überschreiben)
TEST_WORK_DIR="$(mktemp -d /tmp/board-gh-export-test.XXXXXX)"

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
# Test-Umgebung aufbauen:
# Wir legen ein minimales Repo-Skelett an, damit lint spec-Dateien findet.
# Struktur: TEST_WORK_DIR/
#             docs/specs/test-feature-a.md   (mit AC1, AC2, AC3)
#             docs/specs/test-feature-b.md   (mit AC1, AC2)
#             board/                          (leer zu Beginn)
# ---------------------------------------------------------------------------

TEST_BOARD_DIR="${TEST_WORK_DIR}/board"
mkdir -p "${TEST_WORK_DIR}/docs/specs"

cat > "${TEST_WORK_DIR}/docs/specs/test-feature-a.md" <<'MDEOF'
# Test Feature A Spec
- **AC1** — Erste Anforderung
- **AC2** — Zweite Anforderung
- **AC3** — Dritte Anforderung
MDEOF

cat > "${TEST_WORK_DIR}/docs/specs/test-feature-b.md" <<'MDEOF'
# Test Feature B Spec
- **AC1** — Erste Anforderung
- **AC2** — Zweite Anforderung
MDEOF

# Mock-Fixture für diesen Test.
# Issue 5 ist absichtlich unannotiert (kein Spec:, kein implements:) —
# deckt I1 ab: board-lint darf dafür nur WARN STORY-UNSPEC ausgeben, kein FEHLER.
FIXTURE="${TEST_WORK_DIR}/issues.json"
cat > "$FIXTURE" <<'JSONEOF'
[
  {
    "number": 1,
    "title": "Feature A: Erste Story",
    "body": "Spec: docs/specs/test-feature-a.md\nimplements: AC1, AC2\n",
    "labels": ["backend"],
    "status": "Done",
    "priority": "P1",
    "url": "https://github.com/test/repo/issues/1"
  },
  {
    "number": 2,
    "title": "Feature A: Zweite Story",
    "body": "Spec: docs/specs/test-feature-a.md\nimplements: AC3\ndepends: #1",
    "labels": ["backend"],
    "status": "In Progress",
    "priority": "P2",
    "url": "https://github.com/test/repo/issues/2"
  },
  {
    "number": 3,
    "title": "Feature B: Story",
    "body": "Spec: docs/specs/test-feature-b.md\nimplements: AC1, AC2\ndepends: #2",
    "labels": ["frontend"],
    "status": "To Do",
    "priority": "P1",
    "url": "https://github.com/test/repo/issues/3"
  },
  {
    "number": 4,
    "title": "Label-Cluster Story",
    "body": "Spec: docs/specs/test-feature-b.md\nimplements: AC2\ndepends: #99",
    "labels": ["infra"],
    "status": "Blocked",
    "priority": "P0",
    "url": "https://github.com/test/repo/issues/4"
  },
  {
    "number": 5,
    "title": "Unannotiertes Legacy-Issue",
    "body": "Nur freier Text, kein Spec:-Marker, kein implements:-Marker.",
    "labels": ["backend"],
    "status": "To Do",
    "priority": "P3",
    "url": "https://github.com/test/repo/issues/5"
  }
]
JSONEOF

# ---------------------------------------------------------------------------
# Test 1: Erster Lauf — soll erfolgreich sein mit lint grün
# ---------------------------------------------------------------------------
echo ""
echo "--- Test 1: Erster Export-Lauf ---"

# Wir müssen das Skript aus TEST_WORK_DIR heraus aufrufen,
# damit board-lint.sh die Spec-Dateien relativ zu TEST_WORK_DIR findet
EXPORT_OUTPUT=""
EXPORT_EXIT=0
set +e
EXPORT_OUTPUT="$(
  cd "$TEST_WORK_DIR" && \
  bash "$EXPORT_SCRIPT" \
    --mock-input "$FIXTURE" \
    --board-dir board \
    --project-slug test-repo \
    2>&1
)"
EXPORT_EXIT=$?
set -e

echo "$EXPORT_OUTPUT"

if [[ $EXPORT_EXIT -eq 0 ]]; then
  pass "Test 1a: Export-Lauf Exit 0"
else
  fail "Test 1a: Export-Lauf Exit ${EXPORT_EXIT} (erwartet 0)"
fi

if echo "$EXPORT_OUTPUT" | grep -q "lint:.*GREEN"; then
  pass "Test 1b: Lint grün im Report"
else
  fail "Test 1b: Lint nicht grün im Report"
fi

if echo "$EXPORT_OUTPUT" | grep -q "Export erfolgreich"; then
  pass "Test 1c: Erfolgsmeldung vorhanden"
else
  fail "Test 1c: Erfolgsmeldung fehlt"
fi

# ---------------------------------------------------------------------------
# Test 2: Features korrekt erzeugt (AC1, AC3)
# ---------------------------------------------------------------------------
echo ""
echo "--- Test 2: Features korrekt erzeugt ---"

FEATURE_COUNT="$(find "${TEST_BOARD_DIR}/features" -name "F-*.yaml" 2>/dev/null | wc -l | tr -d ' ')"
# 2 Spec-Gruppen (test-feature-a, test-feature-b) + 1 Label-Cluster (infra)
# Aber Issue 4 hat Spec: docs/specs/test-feature-b.md → keine Label-Gruppe
# Issue 4 fällt in spec-group test-feature-b
# → Erwartet: 2 Features (test-feature-a, test-feature-b)
if [[ $FEATURE_COUNT -ge 2 ]]; then
  pass "Test 2a: ${FEATURE_COUNT} Features erzeugt (>= 2)"
else
  fail "Test 2a: Nur ${FEATURE_COUNT} Features (erwartet >= 2)"
fi

# Feature-Datei vorhanden?
if find "${TEST_BOARD_DIR}/features" -name "F-001-*.yaml" | grep -q .; then
  pass "Test 2b: F-001 Feature-Datei vorhanden"
else
  fail "Test 2b: F-001 Feature-Datei fehlt"
fi

# Feature hat parent/goal/status=Backlog
F001="$(find "${TEST_BOARD_DIR}/features" -name "F-001-*.yaml" | head -1)"
if [[ -n "$F001" ]]; then
  if python3 -c "
import yaml, sys
with open(sys.argv[1]) as f: d = yaml.safe_load(f)
assert d.get('status') == 'Backlog', f'Status ist {d.get(\"status\")}'
assert d.get('goal'), 'goal leer'
assert d.get('created_at'), 'created_at fehlt'
print('OK')
" "$F001" 2>/dev/null | grep -q OK; then
    pass "Test 2c: F-001 hat status=Backlog + goal + created_at"
  else
    fail "Test 2c: F-001 Felder unvollständig"
  fi
fi

# ---------------------------------------------------------------------------
# Test 3: Stories korrekt erzeugt (AC2)
# ---------------------------------------------------------------------------
echo ""
echo "--- Test 3: Stories korrekt erzeugt ---"

STORY_COUNT="$(find "${TEST_BOARD_DIR}/stories" -name "S-*.yaml" 2>/dev/null | wc -l | tr -d ' ')"
if [[ $STORY_COUNT -eq 5 ]]; then
  pass "Test 3a: ${STORY_COUNT} Stories erzeugt (erwartet 5)"
else
  fail "Test 3a: ${STORY_COUNT} Stories (erwartet 5)"
fi

# Story hat github_issue (AC2: Nachvollziehbarkeit)
S001="$(find "${TEST_BOARD_DIR}/stories" -name "S-001-*.yaml" | head -1)"
if [[ -n "$S001" ]]; then
  if python3 -c "
import yaml, sys
with open(sys.argv[1]) as f: d = yaml.safe_load(f)
assert d.get('github_issue'), f'github_issue fehlt'
assert d.get('parent', '').startswith('F-'), f'parent ungültig: {d.get(\"parent\")}'
assert d.get('status') in ['To Do','In Progress','Blocked','In Review','Done'], f'Status ungültig: {d.get(\"status\")}'
print('OK')
" "$S001" 2>/dev/null | grep -q OK; then
    pass "Test 3b: S-001 hat github_issue + gültiges parent + gültigen Status"
  else
    fail "Test 3b: S-001 Felder unvollständig"
    python3 -c "
import yaml, sys
with open(sys.argv[1]) as f: d = yaml.safe_load(f)
print(d)
" "$S001"
  fi
fi

# Story-Status korrekt gemappt
if python3 -c "
import yaml, os, sys
stories_dir = sys.argv[1]
status_map = {}
for fn in os.listdir(stories_dir):
    if not fn.endswith('.yaml'): continue
    with open(os.path.join(stories_dir, fn)) as f:
        d = yaml.safe_load(f)
    issue_n = d.get('github_issue')
    status  = d.get('status')
    status_map[issue_n] = status
# Issue 1 → Done, Issue 2 → In Progress, Issue 3 → To Do, Issue 4 → Blocked, Issue 5 → To Do
assert status_map.get(1) == 'Done',        f'Issue 1 Status: {status_map.get(1)}'
assert status_map.get(2) == 'In Progress', f'Issue 2 Status: {status_map.get(2)}'
assert status_map.get(3) == 'To Do',       f'Issue 3 Status: {status_map.get(3)}'
assert status_map.get(4) == 'Blocked',     f'Issue 4 Status: {status_map.get(4)}'
assert status_map.get(5) == 'To Do',       f'Issue 5 Status: {status_map.get(5)}'
print('OK')
" "${TEST_BOARD_DIR}/stories" 2>/dev/null | grep -q OK; then
  pass "Test 3c: Status-Mapping korrekt (1:1)"
else
  fail "Test 3c: Status-Mapping fehlerhaft"
fi

# ---------------------------------------------------------------------------
# Test 4: depends aufgelöst (AC4)
# ---------------------------------------------------------------------------
echo ""
echo "--- Test 4: depends auflösen ---"

# Issue 2 depends on #1 → S-001 (Issue 1's story)
# Issue 3 depends on #2 → S-002
# Issue 4 depends on #99 → nicht gefunden → verworfen

if python3 -c "
import yaml, os, sys
stories_dir = sys.argv[1]
by_issue = {}
for fn in os.listdir(stories_dir):
    if not fn.endswith('.yaml'): continue
    with open(os.path.join(stories_dir, fn)) as f:
        d = yaml.safe_load(f)
    by_issue[d.get('github_issue')] = d

# Issue 2 soll depends auf Story von Issue 1 zeigen
s2 = by_issue.get(2)
s1 = by_issue.get(1)
assert s2, 'Story für Issue 2 fehlt'
assert s1, 'Story für Issue 1 fehlt'
s1_id = s1['id']
deps2 = s2.get('depends') or []
assert s1_id in deps2, f'Issue 2 depends soll {s1_id} enthalten, hat: {deps2}'

# Issue 4 depends #99 → soll None oder leer sein (verworfen)
s4 = by_issue.get(4)
assert s4, 'Story für Issue 4 fehlt'
deps4 = s4.get('depends') or []
assert len(deps4) == 0, f'Issue 4 soll keine depends haben (verworfen), hat: {deps4}'

print('OK')
" "${TEST_BOARD_DIR}/stories" 2>/dev/null | grep -q OK; then
  pass "Test 4a: depends korrekt aufgelöst (Issue 2→S-001, Issue 4 #99 verworfen)"
else
  fail "Test 4a: depends Auflösung fehlerhaft"
fi

# Report soll verworfenes depends melden
if echo "$EXPORT_OUTPUT" | grep -q "depends #99"; then
  pass "Test 4b: Verworfenes depends (#99) im Report gemeldet"
else
  fail "Test 4b: Verworfenes depends (#99) fehlt im Report"
fi

# ---------------------------------------------------------------------------
# Test 5: board.yaml korrekte Zähler (AC5)
# ---------------------------------------------------------------------------
echo ""
echo "--- Test 5: board.yaml Zähler ---"

if python3 -c "
import yaml, sys
with open(sys.argv[1]) as f: d = yaml.safe_load(f)
assert d.get('schema_version') == 1, f'schema_version={d.get(\"schema_version\")}'
assert d.get('project_slug') == 'test-repo', f'project_slug={d.get(\"project_slug\")}'
# next_feature_id = highest_fid + 1 (mindestens 3: F-001, F-002, ...)
nfid = d.get('next_feature_id')
nsid = d.get('next_story_id')
assert isinstance(nfid, int) and nfid >= 3, f'next_feature_id={nfid}'
assert isinstance(nsid, int) and nsid == 6, f'next_story_id={nsid} (erwartet 6, da 5 Stories)'
print('OK')
" "${TEST_BOARD_DIR}/board.yaml" 2>/dev/null | grep -q OK; then
  pass "Test 5: board.yaml Zähler korrekt (schema_version=1, next_story_id=6)"
else
  fail "Test 5: board.yaml Zähler fehlerhaft"
  python3 -c "import yaml,sys; print(yaml.safe_load(open(sys.argv[1]).read()))" "${TEST_BOARD_DIR}/board.yaml"
fi

# ---------------------------------------------------------------------------
# Test 6: Report plausibel (AC7)
# ---------------------------------------------------------------------------
echo ""
echo "--- Test 6: Report-Inhalt ---"

if echo "$EXPORT_OUTPUT" | grep -q "features:.*stories:"; then
  pass "Test 6a: Report enthält features/stories Zähler"
else
  fail "Test 6a: Report-Zeile 'features: N  stories: M' fehlt"
fi

if echo "$EXPORT_OUTPUT" | grep -q "clusters:"; then
  pass "Test 6b: Report enthält cluster-Übersicht"
else
  fail "Test 6b: Report-Zeile 'clusters:' fehlt"
fi

# ---------------------------------------------------------------------------
# Test 7: AC10 — zweiter Lauf bricht ab
# ---------------------------------------------------------------------------
echo ""
echo "--- Test 7: Idempotenz-Schutz (AC10) ---"

SECOND_EXIT=0
set +e
SECOND_OUTPUT="$(
  cd "$TEST_WORK_DIR" && \
  bash "$EXPORT_SCRIPT" \
    --mock-input "$FIXTURE" \
    --board-dir board \
    --project-slug test-repo \
    2>&1
)"
SECOND_EXIT=$?
set -e

if [[ $SECOND_EXIT -ne 0 ]]; then
  pass "Test 7a: Zweiter Lauf bricht ab (Exit ${SECOND_EXIT})"
else
  fail "Test 7a: Zweiter Lauf bricht NICHT ab (Exit 0 — soll 1 sein)"
fi

if echo "$SECOND_OUTPUT" | grep -qi "duplikat\|bereits\|AC10\|force"; then
  pass "Test 7b: Abbruchmeldung erwähnt Duplizierung oder --force"
else
  fail "Test 7b: Abbruchmeldung ist nicht aussagekräftig"
  echo "  Output: $SECOND_OUTPUT"
fi

# ---------------------------------------------------------------------------
# Test 8: --force ermöglicht zweiten Lauf
# ---------------------------------------------------------------------------
echo ""
echo "--- Test 8: --force erzwingt zweiten Lauf ---"

FORCE_EXIT=0
set +e
FORCE_OUTPUT="$(
  cd "$TEST_WORK_DIR" && \
  bash "$EXPORT_SCRIPT" \
    --mock-input "$FIXTURE" \
    --board-dir board \
    --project-slug test-repo \
    --force \
    2>&1
)"
FORCE_EXIT=$?
set -e

if [[ $FORCE_EXIT -eq 0 ]]; then
  pass "Test 8: --force ermöglicht zweiten Lauf (Exit 0)"
else
  fail "Test 8: --force scheitert (Exit ${FORCE_EXIT})"
  echo "  Output: $FORCE_OUTPUT"
fi

# ---------------------------------------------------------------------------
# Test 9: --dry-run schreibt nichts
# ---------------------------------------------------------------------------
echo ""
echo "--- Test 9: --dry-run schreibt nichts ---"

DRY_WORK_DIR="${TEST_WORK_DIR}/dry-run-test"
mkdir -p "${DRY_WORK_DIR}/docs/specs"
cp "${TEST_WORK_DIR}/docs/specs/"*.md "${DRY_WORK_DIR}/docs/specs/"

DRY_EXIT=0
set +e
DRY_OUTPUT="$(
  cd "$DRY_WORK_DIR" && \
  bash "$EXPORT_SCRIPT" \
    --mock-input "$FIXTURE" \
    --board-dir board \
    --project-slug test-repo \
    --dry-run \
    2>&1
)"
DRY_EXIT=$?
set -e

if [[ $DRY_EXIT -eq 0 ]]; then
  pass "Test 9a: --dry-run Exit 0"
else
  fail "Test 9a: --dry-run Exit ${DRY_EXIT}"
fi

if [[ ! -d "${DRY_WORK_DIR}/board" ]]; then
  pass "Test 9b: --dry-run hat kein board/-Verzeichnis erzeugt"
else
  WRITTEN_COUNT="$(find "${DRY_WORK_DIR}/board" -name "*.yaml" 2>/dev/null | wc -l | tr -d ' ')"
  if [[ $WRITTEN_COUNT -eq 0 ]]; then
    pass "Test 9b: --dry-run hat keine YAML-Dateien geschrieben"
  else
    fail "Test 9b: --dry-run hat ${WRITTEN_COUNT} YAML-Dateien geschrieben (soll 0)"
  fi
fi

# ---------------------------------------------------------------------------
# Test 10: Delegation via 'board export-github'
# ---------------------------------------------------------------------------
echo ""
echo "--- Test 10: Delegation via scripts/board export-github ---"

BOARD_DELEG_WORK_DIR="${TEST_WORK_DIR}/delegation-test"
mkdir -p "${BOARD_DELEG_WORK_DIR}/docs/specs"
cp "${TEST_WORK_DIR}/docs/specs/"*.md "${BOARD_DELEG_WORK_DIR}/docs/specs/"

DELEG_EXIT=0
set +e
DELEG_OUTPUT="$(
  cd "$BOARD_DELEG_WORK_DIR" && \
  BOARD_DIR=board bash "${REPO_ROOT}/scripts/board" export-github \
    --mock-input "$FIXTURE" \
    --project-slug test-repo \
    2>&1
)"
DELEG_EXIT=$?
set -e

if [[ $DELEG_EXIT -eq 0 ]]; then
  pass "Test 10: 'board export-github' Delegation erfolgreich"
else
  fail "Test 10: 'board export-github' Delegation fehlgeschlagen (Exit ${DELEG_EXIT})"
  echo "  Output: $DELEG_OUTPUT"
fi

# ---------------------------------------------------------------------------
# Test 11: I1 — Unannotiertes Issue → WARN STORY-UNSPEC (kein FEHLER, lint Exit 0)
# Deckt den Fix für Issues ohne Spec:/implements:-Marker ab.
# ---------------------------------------------------------------------------
echo ""
echo "--- Test 11: Unannotiertes Issue → WARN, kein FEHLER (I1) ---"

# Eigenes Verzeichnis: nur Issue 5 (unannotiert)
UNANN_WORK_DIR="${TEST_WORK_DIR}/unannotated-test"
mkdir -p "${UNANN_WORK_DIR}/docs/specs"
cp "${TEST_WORK_DIR}/docs/specs/"*.md "${UNANN_WORK_DIR}/docs/specs/"

UNANN_FIXTURE="${TEST_WORK_DIR}/unann-issues.json"
cat > "$UNANN_FIXTURE" <<'JSONEOF'
[
  {
    "number": 10,
    "title": "Annotiertes Issue",
    "body": "Spec: docs/specs/test-feature-a.md\nimplements: AC1\n",
    "labels": ["backend"],
    "status": "To Do",
    "priority": "P2",
    "url": "https://github.com/test/repo/issues/10"
  },
  {
    "number": 11,
    "title": "Unannotiertes Issue ohne Marker",
    "body": "Einfacher Freitext ohne Spec oder implements.",
    "labels": ["backend"],
    "status": "To Do",
    "priority": "P3",
    "url": "https://github.com/test/repo/issues/11"
  }
]
JSONEOF

UNANN_EXIT=0
set +e
UNANN_OUTPUT="$(
  cd "$UNANN_WORK_DIR" && \
  bash "$EXPORT_SCRIPT" \
    --mock-input "$UNANN_FIXTURE" \
    --board-dir board \
    --project-slug unann-test \
    2>&1
)"
UNANN_EXIT=$?
set -e

echo "$UNANN_OUTPUT"

# Export muss Exit 0 liefern (lint ist WARN, kein FEHLER)
if [[ $UNANN_EXIT -eq 0 ]]; then
  pass "Test 11a: Export mit unannotiertem Issue → Exit 0 (lint-grün)"
else
  fail "Test 11a: Export mit unannotiertem Issue scheitert (Exit ${UNANN_EXIT})"
fi

# Lint-Report muss WARN STORY-UNSPEC enthalten
if echo "$UNANN_OUTPUT" | grep -q "lint:.*GREEN"; then
  pass "Test 11b: Lint-Report zeigt GREEN"
else
  fail "Test 11b: Lint-Report zeigt nicht GREEN"
fi

# board-lint direkt prüfen: Exit 0 (nur WARN, kein FEHLER)
LINT_DIRECT_EXIT=0
LINT_DIRECT_OUTPUT=""
set +e
LINT_DIRECT_OUTPUT="$(
  cd "$UNANN_WORK_DIR" && \
  bash "$LINT_SCRIPT" board 2>&1
)"
LINT_DIRECT_EXIT=$?
set -e

if [[ $LINT_DIRECT_EXIT -eq 0 ]]; then
  pass "Test 11c: board-lint Exit 0 bei unannotiertem Issue (kein FEHLER)"
else
  fail "Test 11c: board-lint Exit ${LINT_DIRECT_EXIT} (erwartet 0 — nur WARN erlaubt)"
  echo "  Lint-Ausgabe: $LINT_DIRECT_OUTPUT"
fi

if echo "$LINT_DIRECT_OUTPUT" | grep -q "WARN STORY-UNSPEC"; then
  pass "Test 11d: WARN STORY-UNSPEC in board-lint Ausgabe"
else
  fail "Test 11d: WARN STORY-UNSPEC fehlt in board-lint Ausgabe"
  echo "  Lint-Ausgabe: $LINT_DIRECT_OUTPUT"
fi

# Kein FEHLER FIELD-REQUIRED für spec/implements bei importierten Stories
if echo "$LINT_DIRECT_OUTPUT" | grep -q "FEHLER FIELD-REQUIRED"; then
  fail "Test 11e: FEHLER FIELD-REQUIRED vorhanden (darf nicht sein für importierte Stories)"
  echo "  Lint-Ausgabe: $LINT_DIRECT_OUTPUT"
else
  pass "Test 11e: Kein FEHLER FIELD-REQUIRED für unannotierte importierte Story"
fi

# ---------------------------------------------------------------------------
# Test 12: Bug-1-Regression — echtes gh-Format: top-level "status", kein content.state
# Abdeckung: Done→Done, Blocked→Blocked, To Do→To Do, In Progress→In Progress, In Review→In Review
# Items haben "content" ohne "state"-Feld (wie das echte gh project item-list --format json).
# ---------------------------------------------------------------------------
echo ""
echo "--- Test 12: Bug-1-Regression — top-level status, kein content.state ---"

GH_FORMAT_WORK_DIR="${TEST_WORK_DIR}/gh-format-test"
mkdir -p "${GH_FORMAT_WORK_DIR}/docs/specs"
cp "${TEST_WORK_DIR}/docs/specs/"*.md "${GH_FORMAT_WORK_DIR}/docs/specs/"

# Fixture im echten gh-Ausgabe-Format: top-level "status", content OHNE "state"
GH_FORMAT_FIXTURE="${TEST_WORK_DIR}/gh-format-issues.json"
cat > "$GH_FORMAT_FIXTURE" <<'JSONEOF'
[
  {
    "number": 20,
    "title": "Story Done",
    "body": "Spec: docs/specs/test-feature-a.md\nimplements: AC1\n",
    "labels": ["backend"],
    "status": "Done",
    "priority": "P1",
    "url": "https://github.com/org/repo/issues/20"
  },
  {
    "number": 21,
    "title": "Story Blocked",
    "body": "Spec: docs/specs/test-feature-a.md\nimplements: AC2\n",
    "labels": ["backend"],
    "status": "Blocked",
    "priority": "P0",
    "url": "https://github.com/org/repo/issues/21"
  },
  {
    "number": 22,
    "title": "Story To Do",
    "body": "Spec: docs/specs/test-feature-a.md\nimplements: AC3\n",
    "labels": ["backend"],
    "status": "To Do",
    "priority": "P2",
    "url": "https://github.com/org/repo/issues/22"
  },
  {
    "number": 23,
    "title": "Story In Progress",
    "body": "Spec: docs/specs/test-feature-b.md\nimplements: AC1\n",
    "labels": ["frontend"],
    "status": "In Progress",
    "priority": "P1",
    "url": "https://github.com/org/repo/issues/23"
  },
  {
    "number": 24,
    "title": "Story In Review",
    "body": "Spec: docs/specs/test-feature-b.md\nimplements: AC2\n",
    "labels": ["frontend"],
    "status": "In Review",
    "priority": "P2",
    "url": "https://github.com/org/repo/issues/24"
  }
]
JSONEOF

GH_FORMAT_EXIT=0
set +e
GH_FORMAT_OUTPUT="$(
  cd "$GH_FORMAT_WORK_DIR" && \
  bash "$EXPORT_SCRIPT" \
    --mock-input "$GH_FORMAT_FIXTURE" \
    --board-dir board \
    --project-slug gh-format-test \
    2>&1
)"
GH_FORMAT_EXIT=$?
set -e

echo "$GH_FORMAT_OUTPUT"

if [[ $GH_FORMAT_EXIT -eq 0 ]]; then
  pass "Test 12a: Export mit echtem gh-Format (top-level status) → Exit 0"
else
  fail "Test 12a: Export mit echtem gh-Format fehlgeschlagen (Exit ${GH_FORMAT_EXIT})"
  echo "  Output: $GH_FORMAT_OUTPUT"
fi

# Kernassertion Bug 1: top-level status wird 1:1 gemappt (kein Fallback auf "To Do")
if python3 -c "
import yaml, os, sys
stories_dir = sys.argv[1]
by_issue = {}
for fn in os.listdir(stories_dir):
    if not fn.endswith('.yaml'): continue
    with open(os.path.join(stories_dir, fn)) as f:
        d = yaml.safe_load(f)
    by_issue[d.get('github_issue')] = d.get('status')

# Erwartetes 1:1-Mapping (Bug-1-Regression)
assert by_issue.get(20) == 'Done',        f'Issue 20 (Done): erwartet Done, got {by_issue.get(20)}'
assert by_issue.get(21) == 'Blocked',     f'Issue 21 (Blocked): erwartet Blocked, got {by_issue.get(21)}'
assert by_issue.get(22) == 'To Do',       f'Issue 22 (To Do): erwartet To Do, got {by_issue.get(22)}'
assert by_issue.get(23) == 'In Progress', f'Issue 23 (In Progress): erwartet In Progress, got {by_issue.get(23)}'
assert by_issue.get(24) == 'In Review',   f'Issue 24 (In Review): erwartet In Review, got {by_issue.get(24)}'
print('OK')
" "${GH_FORMAT_WORK_DIR}/board/stories" 2>/dev/null | grep -q OK; then
  pass "Test 12b: Bug-1-Regression: Done→Done, Blocked→Blocked, To Do→To Do, In Progress→In Progress, In Review→In Review (alle 1:1)"
else
  fail "Test 12b: Bug-1-Regression: Status-Mapping fehlerhaft (top-level status nicht korrekt übernommen)"
  python3 -c "
import yaml, os, sys
stories_dir = sys.argv[1]
for fn in sorted(os.listdir(stories_dir)):
    if not fn.endswith('.yaml'): continue
    with open(os.path.join(stories_dir, fn)) as f:
        d = yaml.safe_load(f)
    print(f'  github_issue={d.get(\"github_issue\")} status={d.get(\"status\")}')
" "${GH_FORMAT_WORK_DIR}/board/stories"
fi

# ---------------------------------------------------------------------------
# Ergebnis
# ---------------------------------------------------------------------------
echo ""
echo "=============================="
echo "Ergebnis: ${PASS} PASS, ${FAIL} FAIL"
echo "=============================="

if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
exit 0
