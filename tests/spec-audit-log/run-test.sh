#!/usr/bin/env bash
# tests/spec-audit-log/run-test.sh
#
# Covers (reconcile): AC10, AC11
#   AC10 — Pro Lauf EIN Block (Kopf = Datum, je eine Zeile pro berührtem Dokument),
#          neuester Block oben; Datei wird angelegt falls sie fehlt. Inkl. Newline-
#          Injection-Schutz (coder/L26): ein Argument mit eingebettetem Newline darf
#          KEINEN gefälschten `## <Datum>`-Block erzeugen, der die "neuester-Block-
#          oben"-Insert-Logik beim nächsten Lauf als echte Block-Grenze fehlinterpretiert.
#   AC11 — Block enthält NUR die getroffenen Änderungen (keine Tabelle, keine Begründung,
#          keine Fundstellen); ein Lauf ohne Änderung erzeugt keine Zeile/keinen Block.
#
# Self-Test für `scripts/spec-audit-append.sh` (Schreib-Mechanismus des Reconcile-Logbuchs
# docs/spec-audit.md). Verwendet /tmp — berührt NIEMALS das echte docs/ des Repos.
#
# Exit: 0 = alle Tests bestanden, 1 = mindestens ein Fehler

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
APPEND_SCRIPT="${REPO_ROOT}/scripts/spec-audit-append.sh"

# Eigene TMPDIR-Variable (reviewer/L05: $TMPDIR nie überschreiben)
TEST_WORK_DIR="$(mktemp -d /tmp/spec-audit-log-test.XXXXXX)"
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

# ===========================================================================
# Test 1: Datei fehlt -> wird angelegt (AC10), Kopf-Block trägt Datum + Zeilen
# ===========================================================================
T1_DIR="${TEST_WORK_DIR}/t1"
mkdir -p "${T1_DIR}/docs"

(cd "$T1_DIR" && bash "$APPEND_SCRIPT" \
  "Spec foo.md auf use-case-2.0 konvertiert" \
  "Konzept bar.md nachgezogen") >/dev/null 2>&1

if [[ -f "${T1_DIR}/docs/spec-audit.md" ]]; then
  pass "Test 1a: docs/spec-audit.md wird angelegt, wenn sie fehlt"
else
  fail "Test 1a: docs/spec-audit.md wurde NICHT angelegt"
fi

TODAY="$(date -u +%Y-%m-%d)"
T1_CONTENT="$(cat "${T1_DIR}/docs/spec-audit.md" 2>/dev/null || true)"

if echo "$T1_CONTENT" | grep -q "^## ${TODAY}$"; then
  pass "Test 1b: Block-Kopf = Datum (## ${TODAY})"
else
  fail "Test 1b: Block-Kopf fehlt oder falsches Format"
fi

if echo "$T1_CONTENT" | grep -qF -- "- Spec foo.md auf use-case-2.0 konvertiert" \
   && echo "$T1_CONTENT" | grep -qF -- "- Konzept bar.md nachgezogen"; then
  pass "Test 1c: je eine Zeile pro berührtem Dokument vorhanden"
else
  fail "Test 1c: Dokument-Zeilen fehlen oder falsch formatiert"
fi

# ===========================================================================
# Test 2: zweiter Lauf -> neuer Block steht OBEN, alter Block bleibt erhalten
# ===========================================================================
sleep 1
(cd "$T1_DIR" && bash "$APPEND_SCRIPT" "Spec baz.md auf use-case-2.0 konvertiert") >/dev/null 2>&1

T2_CONTENT="$(cat "${T1_DIR}/docs/spec-audit.md")"
FIRST_BLOCK_LINE="$(echo "$T2_CONTENT" | grep -n "^## " | head -1 | cut -d: -f1)"
BAZ_LINE="$(echo "$T2_CONTENT" | grep -n -- "- Spec baz.md auf use-case-2.0 konvertiert" | head -1 | cut -d: -f1)"
FOO_LINE="$(echo "$T2_CONTENT" | grep -n -- "- Spec foo.md auf use-case-2.0 konvertiert" | head -1 | cut -d: -f1)"

if [[ -n "$BAZ_LINE" && -n "$FOO_LINE" && "$BAZ_LINE" -lt "$FOO_LINE" ]]; then
  pass "Test 2a: neuester Block (baz) steht über dem älteren Block (foo)"
else
  fail "Test 2a: Block-Reihenfolge falsch (neueste nicht oben)"
fi

if echo "$T2_CONTENT" | grep -qF -- "- Konzept bar.md nachgezogen"; then
  pass "Test 2b: alter Block (bar) bleibt nach zweitem Lauf erhalten"
else
  fail "Test 2b: alter Block wurde überschrieben statt erhalten"
fi

BLOCK_COUNT="$(echo "$T2_CONTENT" | grep -c "^## " 2>/dev/null)"; BLOCK_COUNT=${BLOCK_COUNT:-0}
if [[ "$BLOCK_COUNT" -eq 2 ]]; then
  pass "Test 2c: genau 2 Blöcke nach 2 Läufen (AC10 — ein Block pro Lauf)"
else
  fail "Test 2c: erwartet 2 Blöcke, gefunden ${BLOCK_COUNT}"
fi

# ===========================================================================
# Test 3: kein berührtes Dokument -> kein Block, keine Änderung (AC11/E2)
# ===========================================================================
T3_DIR="${TEST_WORK_DIR}/t3"
mkdir -p "${T3_DIR}/docs"
(cd "$T3_DIR" && bash "$APPEND_SCRIPT" "Spec init.md" >/dev/null 2>&1)
BEFORE_HASH="$(shasum "${T3_DIR}/docs/spec-audit.md" | awk '{print $1}')"

(cd "$T3_DIR" && bash "$APPEND_SCRIPT" >/dev/null 2>&1)
AFTER_HASH_NOARGS="$(shasum "${T3_DIR}/docs/spec-audit.md" | awk '{print $1}')"

if [[ "$BEFORE_HASH" == "$AFTER_HASH_NOARGS" ]]; then
  pass "Test 3a: Aufruf ohne Zeilen ändert die Datei nicht"
else
  fail "Test 3a: Aufruf ohne Zeilen hat die Datei verändert"
fi

(cd "$T3_DIR" && bash "$APPEND_SCRIPT" "   " "" >/dev/null 2>&1)
AFTER_HASH_BLANK="$(shasum "${T3_DIR}/docs/spec-audit.md" | awk '{print $1}')"

if [[ "$BEFORE_HASH" == "$AFTER_HASH_BLANK" ]]; then
  pass "Test 3b: Aufruf mit nur Leerzeichen/leeren Zeilen ändert die Datei nicht"
else
  fail "Test 3b: Leerzeilen haben fälschlich einen Block erzeugt"
fi

# ===========================================================================
# Test 4: Block enthält keine Tabelle/Begründung — nur Datums-Kopf + Bullets (AC11)
# ===========================================================================
T4_DIR="${TEST_WORK_DIR}/t4"
mkdir -p "${T4_DIR}/docs"
(cd "$T4_DIR" && bash "$APPEND_SCRIPT" "Spec qux.md auf use-case-2.0 konvertiert" >/dev/null 2>&1)
T4_CONTENT="$(cat "${T4_DIR}/docs/spec-audit.md")"

if echo "$T4_CONTENT" | grep -q '|.*|.*|' ; then
  fail "Test 4: Block enthält eine Markdown-Tabelle (AC11 verletzt)"
else
  pass "Test 4: kein Tabellen-Markup im Block (AC11)"
fi

# ===========================================================================
# Test 5: stdin-Modus ("-") liest Zeilen aus stdin, eine pro Zeile
# ===========================================================================
T5_DIR="${TEST_WORK_DIR}/t5"
mkdir -p "${T5_DIR}/docs"
(cd "$T5_DIR" && printf '%s\n' "Spec a.md konvertiert" "Spec b.md konvertiert" \
  | bash "$APPEND_SCRIPT" - >/dev/null 2>&1)
T5_CONTENT="$(cat "${T5_DIR}/docs/spec-audit.md" 2>/dev/null || true)"

if echo "$T5_CONTENT" | grep -qF -- "- Spec a.md konvertiert" \
   && echo "$T5_CONTENT" | grep -qF -- "- Spec b.md konvertiert"; then
  pass "Test 5: stdin-Modus (-) übernimmt Zeilen korrekt"
else
  fail "Test 5: stdin-Modus hat Zeilen nicht korrekt übernommen"
fi

# ===========================================================================
# Test 6: SPEC_AUDIT_FILE-Override (analog BOARD_DIR-Konvention)
# ===========================================================================
T6_DIR="${TEST_WORK_DIR}/t6"
mkdir -p "${T6_DIR}/custom"
(cd "$T6_DIR" && SPEC_AUDIT_FILE="custom/log.md" bash "$APPEND_SCRIPT" "Spec c.md konvertiert" >/dev/null 2>&1)

if [[ -f "${T6_DIR}/custom/log.md" ]] && ! [[ -f "${T6_DIR}/docs/spec-audit.md" ]]; then
  pass "Test 6: SPEC_AUDIT_FILE-Override schreibt an den angegebenen Pfad"
else
  fail "Test 6: SPEC_AUDIT_FILE-Override wurde nicht respektiert"
fi

# ===========================================================================
# Test 7: Newline-Injection — eingebetteter \n in einer Eingabezeile darf
# KEINEN gefälschten `## <Datum>`-Block vortäuschen (coder/L26)
# ===========================================================================
T7_DIR="${TEST_WORK_DIR}/t7"
mkdir -p "${T7_DIR}/docs"

(cd "$T7_DIR" && bash "$APPEND_SCRIPT" $'Text\n## 2099-01-01\n- Fake') >/dev/null 2>&1
sleep 1
(cd "$T7_DIR" && bash "$APPEND_SCRIPT" "Spec real.md nachgezogen") >/dev/null 2>&1

T7_CONTENT="$(cat "${T7_DIR}/docs/spec-audit.md" 2>/dev/null || true)"
T7_BLOCK_COUNT="$(echo "$T7_CONTENT" | grep -c '^## ' 2>/dev/null)"; T7_BLOCK_COUNT=${T7_BLOCK_COUNT:-0}
T7_REAL_LINE="$(echo "$T7_CONTENT" | grep -n -- "- Spec real.md nachgezogen" | head -1 | cut -d: -f1)"
T7_FIRST_BLOCK_LINE="$(echo "$T7_CONTENT" | grep -n "^## " | head -1 | cut -d: -f1)"

# Logbuch-Invariante bleibt intakt: genau 2 echte Blöcke (Injection-Lauf + Folge-Lauf),
# KEIN gefälschter Fake-Datums-Header (## 2099-01-01), und der echte Folge-Block landet
# weiterhin korrekt oben (neuester-Block-oben-Logik nicht durch Fake-Block ausgehebelt).
if [[ "$T7_BLOCK_COUNT" -eq 2 ]] \
   && ! echo "$T7_CONTENT" | grep -q "^## 2099-01-01$" \
   && [[ -n "$T7_REAL_LINE" && -n "$T7_FIRST_BLOCK_LINE" && "$T7_FIRST_BLOCK_LINE" -lt "$T7_REAL_LINE" ]]; then
  pass "Test 7: eingebetteter Newline erzeugt keinen gefälschten Datums-Block — Logbuch-Invariante intakt"
else
  fail "Test 7: Newline-Injection nicht abgewehrt (Blöcke=${T7_BLOCK_COUNT}, erwartet 2; Fake-Header oder Block-Reihenfolge fehlerhaft)"
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
