#!/usr/bin/env bash
# tests/reconcile-stage1-detect/run-test.sh
#
# Covers (reconcile): AC3
#   AC3 — Stufe 1 erkennt jede Spec unter docs/specs/, deren spec_format aelter als ODER
#         abweichend von der aktuellen Vorlagen-Version ist ODER ganz fehlt (Vergleich gegen
#         templates/_docs/specs/_template.md). Inkl. Inline-Kommentar-Robustheit (coder/L25):
#         ein trailing YAML-Kommentar auf der spec_format-Zeile (wie ihn die echte Vorlage
#         selbst traegt) darf KEINEN False-Positive ausloesen.
#
# Self-Test für `scripts/reconcile-stage1-detect.sh` (Stufe-1-Erkennungsschritt des
# Reconcile-Skills). Verwendet /tmp-Fixtures — berührt NIEMALS das echte docs/specs/ des Repos.
#
# Exit: 0 = alle Tests bestanden, 1 = mindestens ein Fehler

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
DETECT_SCRIPT="${REPO_ROOT}/scripts/reconcile-stage1-detect.sh"

# Eigene TMPDIR-Variable (reviewer/L05: $TMPDIR nie überschreiben)
TEST_WORK_DIR="$(mktemp -d /tmp/reconcile-stage1-detect-test.XXXXXX)"
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

write_template() {
  # $1 = Zielpfad; schreibt eine Vorlage, deren spec_format-Zeile (wie im echten Template)
  # einen trailing Inline-Kommentar trägt — Regressionsschutz für coder/L25.
  mkdir -p "$(dirname "$1")"
  cat > "$1" <<'EOF'
---
id: <feature-slug>
title: <Feature-Titel>
status: draft
version: 1
spec_format: use-case-2.0   # aktuelle Standard-Version dieser Vorlage
---

# Spec: <Feature-Titel>
EOF
}

write_spec() {
  # $1 = Zielpfad, $2 = spec_format-Zeile-Inhalt ODER leer-String für "Feld weglassen"
  mkdir -p "$(dirname "$1")"
  {
    echo "---"
    echo "id: foo"
    echo "title: Foo"
    echo "status: draft"
    echo "version: 1"
    if [[ -n "${2:-}" ]]; then
      echo "spec_format: $2"
    fi
    echo "---"
    echo ""
    echo "# Spec: Foo"
  } > "$1"
}

# ===========================================================================
# Test 1: Spec bereits aktuell (== Vorlagenwert) -> erscheint NICHT in der Ausgabe
# ===========================================================================
T1_DIR="${TEST_WORK_DIR}/t1"
write_template "${T1_DIR}/template.md"
write_spec "${T1_DIR}/specs/current.md" "use-case-2.0"

T1_OUT="$(cd "$T1_DIR" && SPECS_DIR="specs" TEMPLATE_PATH="template.md" bash "$DETECT_SCRIPT" 2>/dev/null)"
if [[ -z "$T1_OUT" ]]; then
  pass "Test 1: aktuelle Spec wird NICHT als Drift gemeldet"
else
  fail "Test 1: aktuelle Spec faelschlich gemeldet: ${T1_OUT}"
fi

# ===========================================================================
# Test 2: Spec mit veraltetem spec_format -> "outdated" mit altem + neuem Wert
# ===========================================================================
T2_DIR="${TEST_WORK_DIR}/t2"
write_template "${T2_DIR}/template.md"
write_spec "${T2_DIR}/specs/old.md" "use-case-1.0"

T2_OUT="$(cd "$T2_DIR" && SPECS_DIR="specs" TEMPLATE_PATH="template.md" bash "$DETECT_SCRIPT" 2>/dev/null)"
if echo "$T2_OUT" | grep -qF $'specs/old.md\toutdated\tuse-case-1.0\tuse-case-2.0'; then
  pass "Test 2: veraltete Spec korrekt als 'outdated' mit altem/neuem Wert gemeldet"
else
  fail "Test 2: veraltete Spec nicht (korrekt) gemeldet: ${T2_OUT}"
fi

# ===========================================================================
# Test 3: Spec ohne spec_format-Feld -> "missing"
# ===========================================================================
T3_DIR="${TEST_WORK_DIR}/t3"
write_template "${T3_DIR}/template.md"
write_spec "${T3_DIR}/specs/nofield.md" ""

T3_OUT="$(cd "$T3_DIR" && SPECS_DIR="specs" TEMPLATE_PATH="template.md" bash "$DETECT_SCRIPT" 2>/dev/null)"
if echo "$T3_OUT" | grep -qF $'specs/nofield.md\tmissing\t(none)\tuse-case-2.0'; then
  pass "Test 3: Spec ohne spec_format-Feld korrekt als 'missing' gemeldet"
else
  fail "Test 3: fehlendes Feld nicht (korrekt) gemeldet: ${T3_OUT}"
fi

# ===========================================================================
# Test 4: Spec mit aktuellem Wert + eigenem trailing Inline-Kommentar -> KEIN False-Positive
# (coder/L25 — Hauptzweck dieses Tests)
# ===========================================================================
T4_DIR="${TEST_WORK_DIR}/t4"
write_template "${T4_DIR}/template.md"
write_spec "${T4_DIR}/specs/commented.md" "use-case-2.0   # in Kraft, siehe ADR-007"

T4_OUT="$(cd "$T4_DIR" && SPECS_DIR="specs" TEMPLATE_PATH="template.md" bash "$DETECT_SCRIPT" 2>/dev/null)"
if [[ -z "$T4_OUT" ]]; then
  pass "Test 4 (coder/L25): aktueller Wert MIT trailing Inline-Kommentar wird NICHT als Drift gemeldet"
else
  fail "Test 4 (coder/L25): False-Positive durch ungestrippten Inline-Kommentar: ${T4_OUT}"
fi

# ===========================================================================
# Test 5: leeres SPECS_DIR (keine *.md-Dateien) -> leere Ausgabe, Exit 0
# ===========================================================================
T5_DIR="${TEST_WORK_DIR}/t5"
write_template "${T5_DIR}/template.md"
mkdir -p "${T5_DIR}/specs"

set +e
T5_OUT="$(cd "$T5_DIR" && SPECS_DIR="specs" TEMPLATE_PATH="template.md" bash "$DETECT_SCRIPT" 2>/dev/null)"
T5_EXIT=$?
set -e
if [[ -z "$T5_OUT" && "$T5_EXIT" -eq 0 ]]; then
  pass "Test 5: leeres specs/-Verzeichnis -> leere Ausgabe, Exit 0"
else
  fail "Test 5: erwartet leere Ausgabe + Exit 0, bekam Exit=${T5_EXIT} Out=${T5_OUT}"
fi

# ===========================================================================
# Test 6: fehlendes SPECS_DIR (Verzeichnis existiert nicht) -> leere Ausgabe, Exit 0
# ===========================================================================
T6_DIR="${TEST_WORK_DIR}/t6"
write_template "${T6_DIR}/template.md"

set +e
T6_OUT="$(cd "$T6_DIR" && SPECS_DIR="does-not-exist" TEMPLATE_PATH="template.md" bash "$DETECT_SCRIPT" 2>/dev/null)"
T6_EXIT=$?
set -e
if [[ -z "$T6_OUT" && "$T6_EXIT" -eq 0 ]]; then
  pass "Test 6: fehlendes SPECS_DIR -> leere Ausgabe, Exit 0 (kein Fehler)"
else
  fail "Test 6: erwartet leere Ausgabe + Exit 0, bekam Exit=${T6_EXIT} Out=${T6_OUT}"
fi

# ===========================================================================
# Test 7: Vorlage selbst nicht lesbar / ohne spec_format -> Exit 2 (echte Fehlkonfiguration)
# ===========================================================================
T7_DIR="${TEST_WORK_DIR}/t7"
mkdir -p "${T7_DIR}/specs"
write_spec "${T7_DIR}/specs/x.md" "use-case-2.0"
# kein template.md angelegt -> Vorlage fehlt

set +e
(cd "$T7_DIR" && SPECS_DIR="specs" TEMPLATE_PATH="template.md" bash "$DETECT_SCRIPT" >/dev/null 2>"${TEST_WORK_DIR}/t7_err.log")
T7_EXIT=$?
set -e
if [[ "$T7_EXIT" -eq 2 ]]; then
  pass "Test 7: fehlende Vorlage -> Exit 2 (echte Fehlkonfiguration, kein stiller Erfolg)"
else
  fail "Test 7: erwartet Exit 2 bei fehlender Vorlage, bekam Exit=${T7_EXIT}"
fi

# ===========================================================================
# Test 8: mehrere Specs gemischt (aktuell/veraltet/fehlend) -> nur die Drift-Faelle gelistet
# ===========================================================================
T8_DIR="${TEST_WORK_DIR}/t8"
write_template "${T8_DIR}/template.md"
write_spec "${T8_DIR}/specs/a-current.md" "use-case-2.0"
write_spec "${T8_DIR}/specs/b-outdated.md" "use-case-1.0"
write_spec "${T8_DIR}/specs/c-missing.md" ""

T8_OUT="$(cd "$T8_DIR" && SPECS_DIR="specs" TEMPLATE_PATH="template.md" bash "$DETECT_SCRIPT" 2>/dev/null)"
T8_LINES="$(echo "$T8_OUT" | grep -c . || true)"
if [[ "$T8_LINES" -eq 2 ]] \
   && echo "$T8_OUT" | grep -q "b-outdated.md" \
   && echo "$T8_OUT" | grep -q "c-missing.md" \
   && ! echo "$T8_OUT" | grep -q "a-current.md"; then
  pass "Test 8: gemischter Bestand -> nur die 2 Drift-Faelle gelistet, aktuelle Spec ausgeschlossen"
else
  fail "Test 8: erwartet genau 2 Zeilen (b-outdated, c-missing), bekam: ${T8_OUT}"
fi

# ===========================================================================
# Zusammenfassung
# ===========================================================================
echo ""
echo "reconcile-stage1-detect: ${PASS} passed, ${FAIL} failed"
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
exit 0
