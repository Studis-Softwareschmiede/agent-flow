#!/usr/bin/env bash
# tests/reconcile-doc-layout/run-test.sh
#
# Covers (reconcile): AC8
#   AC8 — Code ist maßgebend: Stufe 2 zieht fehlende Doku automatisch nach. Dieser Test deckt
#         den mechanisch testbaren Teil von coder/L27 (.claude/lessons/coder.md) ab: die
#         Layout-Erkennung im "Dokument fehlt komplett"-Schreibpfad (skills/reconcile/SKILL.md
#         §2c.2) MUSS deterministisch dasselbe Muster wählen, das der Lese-/Vergleichspfad
#         (§2b) bereits gegen das Projekt erkennt — kanonische Einzeldatei vs. bereits
#         etabliertes Mehrdatei-/Root-Muster (wie agent-flow selbst: Root-CONCEPT.md +
#         docs/architecture/*.md). Der LLM-getriebene Gesamt-Nachzug (reviewer-Audit-Dispatch +
#         echtes Doc-Write) selbst ist NICHT unit-testbar — siehe Handoff-Hinweis
#         "post-merge supervised dry-run empfohlen".
#
# Self-Test für `scripts/reconcile-doc-layout.sh`. Verwendet /tmp-Fixtures — berührt NIEMALS
# das echte Repo.
#
# Exit: 0 = alle Tests bestanden, 1 = mindestens ein Fehler

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
LAYOUT_SCRIPT="${REPO_ROOT}/scripts/reconcile-doc-layout.sh"

# Eigene TMPDIR-Variable (reviewer/L05: $TMPDIR nie überschreiben)
TEST_WORK_DIR="$(mktemp -d /tmp/reconcile-doc-layout-test.XXXXXX)"
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

run_layout() {
  # $1 = doctype, $2 = fixture-root -> stdout
  bash "$LAYOUT_SCRIPT" "$1" "$2"
}

# ===========================================================================
# Test 1: architecture — Mehrdatei-Muster (docs/architecture/*.md vorhanden, wie dieses Repo)
# ===========================================================================
T1_DIR="${TEST_WORK_DIR}/t1"
mkdir -p "${T1_DIR}/docs/architecture"
cat > "${T1_DIR}/docs/architecture/foo-subsystem.md" <<'EOF'
# Foo
EOF
T1_OUT="$(run_layout architecture "$T1_DIR")"
if [[ "$T1_OUT" == "multi" ]]; then
  pass "Test 1 (coder/L27): docs/architecture/*.md vorhanden -> 'multi'"
else
  fail "Test 1: erwartet 'multi', bekam '${T1_OUT}'"
fi

# ===========================================================================
# Test 2: architecture — kein docs/architecture/-Verzeichnis -> kanonische Einzeldatei
# ===========================================================================
T2_DIR="${TEST_WORK_DIR}/t2"
mkdir -p "${T2_DIR}/docs"
T2_OUT="$(run_layout architecture "$T2_DIR")"
if [[ "$T2_OUT" == "single" ]]; then
  pass "Test 2 (coder/L27): kein docs/architecture/ -> 'single'"
else
  fail "Test 2: erwartet 'single', bekam '${T2_OUT}'"
fi

# ===========================================================================
# Test 3: architecture — docs/architecture/ existiert, aber leer (keine *.md) -> 'single'
# ===========================================================================
T3_DIR="${TEST_WORK_DIR}/t3"
mkdir -p "${T3_DIR}/docs/architecture"
T3_OUT="$(run_layout architecture "$T3_DIR")"
if [[ "$T3_OUT" == "single" ]]; then
  pass "Test 3 (coder/L27): docs/architecture/ ohne *.md -> 'single' (kein leeres Verzeichnis als Muster werten)"
else
  fail "Test 3: erwartet 'single', bekam '${T3_OUT}'"
fi

# ===========================================================================
# Test 4: concept — Root-CONCEPT.md vorhanden (wie dieses Repo) -> 'root'
# ===========================================================================
T4_DIR="${TEST_WORK_DIR}/t4"
mkdir -p "${T4_DIR}"
printf '# Concept\n' > "${T4_DIR}/CONCEPT.md"
T4_OUT="$(run_layout concept "$T4_DIR")"
if [[ "$T4_OUT" == "root" ]]; then
  pass "Test 4 (coder/L27): Root-CONCEPT.md vorhanden -> 'root'"
else
  fail "Test 4: erwartet 'root', bekam '${T4_OUT}'"
fi

# ===========================================================================
# Test 5: concept — kein Root-CONCEPT.md -> kanonisch docs/concept.md
# ===========================================================================
T5_DIR="${TEST_WORK_DIR}/t5"
mkdir -p "${T5_DIR}/docs"
T5_OUT="$(run_layout concept "$T5_DIR")"
if [[ "$T5_OUT" == "canonical" ]]; then
  pass "Test 5 (coder/L27): kein Root-CONCEPT.md -> 'canonical'"
else
  fail "Test 5: erwartet 'canonical', bekam '${T5_OUT}'"
fi

# ===========================================================================
# Test 6: ungültiger doctype -> Exit 2, keine Fachfall-Ausgabe
# ===========================================================================
set +e
T6_OUT="$(bash "$LAYOUT_SCRIPT" bogus "${TEST_WORK_DIR}/t5" 2>/dev/null)"
T6_RC=$?
set -e
if [[ "$T6_RC" -eq 2 ]]; then
  pass "Test 6: ungültiger doctype -> Exit 2"
else
  fail "Test 6: erwartet Exit 2, bekam ${T6_RC} (stdout: '${T6_OUT}')"
fi

# ===========================================================================
# Test 7: gegen das echte agent-flow-Repo -> 'multi' (architecture) + 'root' (concept)
#         (verifiziert die Selbst-Referenz aus coder/L27 direkt: dieses Repo IST das
#         Beispiel der Lehre)
# ===========================================================================
T7_ARCH_OUT="$(run_layout architecture "$REPO_ROOT")"
T7_CONCEPT_OUT="$(run_layout concept "$REPO_ROOT")"
if [[ "$T7_ARCH_OUT" == "multi" && "$T7_CONCEPT_OUT" == "root" ]]; then
  pass "Test 7 (coder/L27 Selbst-Referenz): agent-flow-Repo -> architecture='multi', concept='root'"
else
  fail "Test 7: erwartet architecture='multi'/concept='root', bekam architecture='${T7_ARCH_OUT}'/concept='${T7_CONCEPT_OUT}'"
fi

# ===========================================================================
# Zusammenfassung
# ===========================================================================
echo ""
echo "reconcile-doc-layout: ${PASS} passed, ${FAIL} failed"
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
exit 0
