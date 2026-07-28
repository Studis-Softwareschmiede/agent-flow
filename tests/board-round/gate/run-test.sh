#!/usr/bin/env bash
# tests/board-round/gate/run-test.sh
#
# Self-Test für scripts/parse-gate.sh (Stufe-1-Primitiv, Phase A des
# `flow-deterministic-runner`-Konzepts).
#
# Fixture-basiert (reine Text-Fixtures unter fixtures/, KEIN Git nötig) --
# Stil analog tests/board-cli/run-test.sh.
#
# Covers (flow-deterministic-runner):
#   AC3 -- Review-Gate (reviewer/dba) und Test-Gate (tester) werden
#     mechanisch aus dem Handoff-Text extrahiert, exakt dieselben Tokens
#     wie SKILL.md §3/§4 (Tests 1-9): reviewer PASS/CHANGES-REQUIRED, dba
#     PASS, tester PASS/FAIL/SKIPPED-NO-DOCKER/SKIPPED-DOC-ONLY/
#     SKIPPED-NO-BUILD (5. Token, agents/tester.md:126/142 -- Review-Fund
#     Iteration 1: das ursprüngliche Regex kannte nur 4 Test-Gate-Tokens,
#     Test 9 schliesst die Lücke). Datei-Arg UND stdin-Eingabe beide
#     geprüft (Test 1 Datei, Test 2 stdin).
#   AC7 -- Kein stilles Raten: fehlende Gate-Zeile (Test 11), widersprüchliche
#     Gate-Zeilen (Test 12), unbekanntes Token/Tippfehler (Test 13), Test-
#     Gate-Tippfehler (Test 14), Tippfehler nah an SKIPPED-NO-BUILD (Test
#     15 -- "SKIPPED-NO-BULID" bleibt bewusst mehrdeutig, belegt die
#     Entscheidung für explizite Token-Enumeration statt eines generischen
#     "SKIPPED-[A-Z-]+"-Suffix-Wildcards, s. Kommentar in scripts/parse-
#     gate.sh: ein Wildcard würde genau diesen Tippfehler still durchwinken),
#     Gate-Zeile mitten in Prosa statt am Zeilenanfang (Test 16) -- jeweils
#     Exit 2, kein Token auf stdout. Owner-Entscheid Q7 (Option c, HART):
#     nur Whitespace-Trim + tolerante Leerzeichen um den Doppelpunkt sind
#     erlaubte Normalisierung -- Test 10 belegt das (Whitespace toleriert),
#     Test 13/14/15/16 belegen die Grenze (keine Case-Insensitivität/kein
#     Fuzzy-Match/kein Suffix-Wildcard). Test 17 -- doppelte, aber
#     IDENTISCHE Gate-Zeilen sind kein Widerspruch (Exit 0), nur
#     widersprüchliche Werte sind mehrdeutig (Abgrenzung zu Test 12).
#     Test 18/19 -- Aufruf-/Eingabefehler (unbekannte Rolle, fehlende
#     Datei) liefern Exit 1, nicht 2 (Usage-Fehler != Handoff-
#     Mehrdeutigkeit).
#
# Exit: 0 = alle Tests bestanden, 1 = mindestens ein Fehler

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
PARSE_GATE="${REPO_ROOT}/scripts/parse-gate.sh"
FIXTURES="${SCRIPT_DIR}/fixtures"

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

# check_ok <label> <erwarteter-token> <rolle> <fixture-datei>
check_ok() {
  local label="$1" expected_token="$2" role="$3" fixture="$4"
  local out rc

  set +e
  out="$("$PARSE_GATE" "$role" "${FIXTURES}/${fixture}" 2>/tmp/parse-gate-test-err.$$)"
  rc=$?
  set -e

  if [ "$rc" -ne 0 ]; then
    fail "${label}: erwartete Exit 0, bekam ${rc} ($(cat /tmp/parse-gate-test-err.$$))"
  elif [ "$out" != "$expected_token" ]; then
    fail "${label}: erwartetes stdout '${expected_token}', bekam '${out}'"
  else
    pass "${label}: Exit 0, stdout='${out}'"
  fi
  rm -f /tmp/parse-gate-test-err.$$
}

# check_ok_stdin <label> <erwarteter-token> <rolle> <fixture-datei>
check_ok_stdin() {
  local label="$1" expected_token="$2" role="$3" fixture="$4"
  local out rc

  set +e
  out="$("$PARSE_GATE" "$role" < "${FIXTURES}/${fixture}" 2>/tmp/parse-gate-test-err.$$)"
  rc=$?
  set -e

  if [ "$rc" -ne 0 ]; then
    fail "${label}: erwartete Exit 0, bekam ${rc} ($(cat /tmp/parse-gate-test-err.$$))"
  elif [ "$out" != "$expected_token" ]; then
    fail "${label}: erwartetes stdout '${expected_token}', bekam '${out}'"
  else
    pass "${label}: Exit 0 (stdin), stdout='${out}'"
  fi
  rm -f /tmp/parse-gate-test-err.$$
}

# check_exit <label> <erwarteter-exit-code> <rolle> [<fixture-datei>]
check_exit() {
  local label="$1" expected_rc="$2" role="$3" fixture="${4:-}"
  local out rc

  set +e
  if [ -n "$fixture" ]; then
    out="$("$PARSE_GATE" "$role" "${FIXTURES}/${fixture}" 2>/tmp/parse-gate-test-err.$$)"
  else
    out="$("$PARSE_GATE" "$role" /nonexistent-handoff-fixture.txt 2>/tmp/parse-gate-test-err.$$)"
  fi
  rc=$?
  set -e

  if [ "$rc" -ne "$expected_rc" ]; then
    fail "${label}: erwartete Exit ${expected_rc}, bekam ${rc} (stdout='${out}', stderr='$(cat /tmp/parse-gate-test-err.$$)')"
  elif [ -n "$out" ]; then
    fail "${label}: erwartete leeres stdout bei Exit ${expected_rc}, bekam '${out}'"
  else
    pass "${label}: Exit ${expected_rc}, kein Token auf stdout"
  fi
  rm -f /tmp/parse-gate-test-err.$$
}

# ---------------------------------------------------------------------------
# AC3 -- gültige Tokens je Rolle
# ---------------------------------------------------------------------------
check_ok "Test 1: reviewer PASS (Datei)" "PASS" "reviewer" "review-pass.txt"
check_ok_stdin "Test 2: reviewer PASS (stdin)" "PASS" "reviewer" "review-pass.txt"
check_ok "Test 3: reviewer CHANGES-REQUIRED" "CHANGES-REQUIRED" "reviewer" "review-changes-required.txt"
check_ok "Test 4: dba PASS (dieselbe Token-Menge wie reviewer)" "PASS" "dba" "review-pass.txt"
check_ok "Test 5: tester PASS" "PASS" "tester" "test-pass.txt"
check_ok "Test 6: tester FAIL" "FAIL" "tester" "test-fail.txt"
check_ok "Test 7: tester SKIPPED-NO-DOCKER" "SKIPPED-NO-DOCKER" "tester" "test-skipped-no-docker.txt"
check_ok "Test 8: tester SKIPPED-DOC-ONLY" "SKIPPED-DOC-ONLY" "tester" "test-skipped-doc-only.txt"
check_ok "Test 9: tester SKIPPED-NO-BUILD (5. Token, agents/tester.md:126/142)" "SKIPPED-NO-BUILD" "tester" "test-skipped-no-build.txt"

# ---------------------------------------------------------------------------
# AC7/Q7 -- erlaubte Normalisierung (NUR Whitespace/Trailing um den Doppelpunkt)
# ---------------------------------------------------------------------------
check_ok "Test 10: Whitespace-Variante toleriert (führend/nachfolgend + um ':')" "PASS" "reviewer" "review-pass-whitespace.txt"

# ---------------------------------------------------------------------------
# AC7 -- kein stilles Raten: definierter Exit 2, kein Token auf stdout
# ---------------------------------------------------------------------------
check_exit "Test 11: fehlende Gate-Zeile -> Exit 2" 2 "reviewer" "missing-gate-line.txt"
check_exit "Test 12: widersprüchliche Gate-Zeilen -> Exit 2" 2 "reviewer" "contradictory-gate-lines.txt"
check_exit "Test 13: unbekanntes Token/Tippfehler -> Exit 2" 2 "reviewer" "unknown-token.txt"
check_exit "Test 14: Test-Gate-Tippfehler ('SKIPED-...') -> Exit 2" 2 "tester" "tester-typo-token.txt"
check_exit "Test 15: Tippfehler nah an SKIPPED-NO-BUILD ('SKIPPED-NO-BULID') -> Exit 2 (belegt explizite Enumeration statt Suffix-Wildcard)" 2 "tester" "tester-typo-skipped-no-build.txt"
check_exit "Test 16: Gate-Zeile in Prosa eingebettet (kein Fuzzy-Match) -> Exit 2" 2 "reviewer" "embedded-in-prose.txt"

# ---------------------------------------------------------------------------
# Abgrenzung: doppelte, aber IDENTISCHE Gate-Zeilen sind kein Widerspruch
# ---------------------------------------------------------------------------
check_ok "Test 17: doppelte identische Gate-Zeilen -> Exit 0 (kein Widerspruch)" "PASS" "reviewer" "duplicate-identical-gate-lines.txt"

# ---------------------------------------------------------------------------
# Aufruf-/Eingabefehler (Exit 1, NICHT 2 -- Usage-Fehler != Mehrdeutigkeit)
# ---------------------------------------------------------------------------
set +e
out="$("$PARSE_GATE" "coder" "${FIXTURES}/review-pass.txt" 2>/dev/null)"
rc=$?
set -e
if [ "$rc" -eq 1 ] && [ -z "$out" ]; then
  pass "Test 18: unbekannte Rolle 'coder' -> Exit 1"
else
  fail "Test 18: unbekannte Rolle 'coder' -- erwartete Exit 1, bekam ${rc} (stdout='${out}')"
fi

set +e
out="$("$PARSE_GATE" "reviewer" "${FIXTURES}/does-not-exist.txt" 2>/dev/null)"
rc=$?
set -e
if [ "$rc" -eq 1 ] && [ -z "$out" ]; then
  pass "Test 19: fehlende Handoff-Datei -> Exit 1"
else
  fail "Test 19: fehlende Handoff-Datei -- erwartete Exit 1, bekam ${rc} (stdout='${out}')"
fi

# ---------------------------------------------------------------------------
# Zusammenfassung
# ---------------------------------------------------------------------------
echo ""
echo "=== ${PASS} passed, ${FAIL} failed ==="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
