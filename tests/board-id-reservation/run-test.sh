#!/usr/bin/env bash
# tests/board-id-reservation/run-test.sh
#
# Mechanisches Smoke-Skript für scripts/board-id-reserve.sh (analog
# tests/board-cli/tests/board-feature-drain) — die Ledger-/Reservierungs-
# Mechanik von docs/specs/id-block-reservation.md. agent-flow ist
# `language: md` (No-Op-Build), daher erfolgt die Abnahme der deterministischen
# Bash/Python-Mechanik hier mechanisch statt via Sprach-Testframework.
#
# Jeder Test trägt das kanonische Trace-Tag @trace id-block-reservation#AC<n>
# (docs/architecture/traceability-subsystem.md).
#
# Covers (docs/specs/id-block-reservation.md):
#   AC1  — Reservierung bei Batch-Start: genau ein zusammenhängender Block
#     der konfigurierbaren Default-Grösse je Namespace, Ledger legt sich bei
#     Erstlauf aus dem Schema an (Test 1); Bestand-Seed respektiert bei der
#     Block-Berechnung (Test 9, Edge-Case "historisch vergebene IDs").
#   AC2  — Atomarität gegen default_branch + Push-Konflikt-Retry (A1):
#     mechanisch belegt durch den echten Push-Race in Test 7 (zwei parallele
#     Prozesse gegen dieselbe origin) UND den endgültigen Fehlschlag in
#     Test 8 (AC11).
#   AC3  — Disjunkte Blöcke bei Nebenläufigkeit: sequentiell (Test 3) UND
#     ECHT nebenläufig (Test 7 — zwei Hintergrundprozesse, kein Mock).
#   AC4  — Vergabe nur innerhalb des Blocks: `consume` lehnt eine Nummer
#     ausserhalb des reservierten Bereichs hart ab, ohne Ledger-Mutation
#     (Test 5). Der Reviewer-Gate-Teil von AC4 (`reviewer/id-out-of-block`)
#     ist Doku-Vertrag in agents/reviewer.md — hier nicht (unit-)testbar,
#     mechanisch nur die `consume`-Grenzprüfung.
#   AC5  — Block-Nachreservierung bei Erschöpfung: `extend` legt IMMER einen
#     weiteren, disjunkten Block an (Test 4).
#   AC6  — Kollisionsfreie Konsolidierung: zwei "Batches" konsumieren
#     unabhängig voneinander IDs aus ihren eigenen Blöcken — keine der
#     tatsächlich vergebenen Nummern kollidiert (Test 10, End-to-End-Analogon
#     zum BR-132-Vorfall).
#   AC7  — Idempotenz: ein zweiter `reserve`-Aufruf für dieselbe (namespace,
#     id) legt KEINEN zweiten Block an (Test 2).
#   AC8  — Ledger-Schema & -Persistenz: schema_version/namespaces-Struktur
#     exakt wie in der Spec (Test 1); board/id-reservations.yaml ist NICHT
#     gitignored (Test 1d).
#   AC9  — Board-weite /flow-Parität: derselbe Mechanismus (reserve/consume/
#     release) funktioniert unverändert, wenn der Scope-Schlüssel eine
#     Story-ID (S-###) statt einer Feature-ID (F-###) ist (Test 11).
#   AC10 — Freigabe/High-Water-Mark: `release` markiert `released`, behält
#     high_water; ungenutzte (namespace nie berührt ODER Tail nach
#     high_water) Bereiche sind für spätere `reserve`-Aufrufe wiederverwendbar
#     (Test 6).
#   AC11 — Harter Abbruch statt Blind-Vergabe: endgültiger Push-Fehlschlag
#     (alle Retries verbraucht) → Exit ≠ 0 mit Klartext-Diagnose, KEIN
#     Ledger-Diff auf origin (Test 8).
#
# Verwendet lokale /tmp-Git-Fixtures (bare "origin" + Arbeits-Klon) — berührt
# nie echtes GitHub. Exit: 0 = alle Tests bestanden, 1 = mindestens ein Fehler.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RESERVE_SCRIPT="${REPO_ROOT}/scripts/board-id-reserve.sh"

TEST_WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/board-id-reservation-test.XXXXXX")"
trap 'rm -rf "$TEST_WORK_DIR"' EXIT

FAIL=0
PASS=0
fail() { echo "FAIL: $*" >&2; FAIL=$((FAIL + 1)); }
pass() { echo "PASS: $*"; PASS=$((PASS + 1)); }

export GIT_AUTHOR_NAME="test" GIT_AUTHOR_EMAIL="test@test.local"
export GIT_COMMITTER_NAME="test" GIT_COMMITTER_EMAIL="test@test.local"
# Schnelle Retries im Test — keine echte Nebenläufigkeits-Latenz nötig.
export BOARD_ID_RESERVE_SLEEP="${BOARD_ID_RESERVE_SLEEP:-0}"

# setup_fixture <dir> — bare "origin" + Arbeits-Klon mit .claude/profile.md
# (default_branch: main), OHNE vorhandenes board/id-reservations.yaml
# (Erstlauf-Fall, AC1/AC8).
setup_fixture() {
  local dir="$1"
  local origin="${dir}/origin.git"
  local work="${dir}/work"
  git init --bare -q "$origin"
  git init -q "$work"
  (
    cd "$work"
    git remote add origin "$origin"
    mkdir -p .claude board
    cat > .claude/profile.md <<'YAML'
---
language: md
default_branch: main
---
Test-Profil.
YAML
    git add -A
    git commit -q -m "initial"
    git branch -M main
    git push -q origin main
  )
  echo "$work"
}

# ===========================================================================
# Test 1 — @trace id-block-reservation#AC1 @trace id-block-reservation#AC8
# Erstlauf: kein board/id-reservations.yaml vorhanden -> reserve legt das
# Ledger aus dem Schema an, erster Block ist 1..block_size (Default 10).
# ===========================================================================
echo ""
echo "--- Test 1: AC1/AC8 — Erstlauf legt Ledger aus dem Schema an, erster Block 1-10 ---"
T1_WORK="$(setup_fixture "${TEST_WORK_DIR}/test1")"
T1_OUT="$(cd "$T1_WORK" && "$RESERVE_SCRIPT" reserve BR F-001)"
if echo "$T1_OUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d=={"namespace":"BR","feature_id":"F-001","range_start":1,"range_end":10,"status":"active","reserved_at":d["reserved_at"],"high_water":None}, d' 2>/dev/null; then
  pass "Test 1a: reserve liefert Block 1-10, status active, high_water null"
else
  fail "Test 1a: unerwartetes reserve-Ergebnis: $T1_OUT"
fi
T1_LEDGER="$(cd "$T1_WORK" && git fetch origin main -q && git show origin/main:board/id-reservations.yaml)"
if echo "$T1_LEDGER" | grep -q "^schema_version: 1" && echo "$T1_LEDGER" | grep -q "block_size: 10"; then
  pass "Test 1b: Ledger folgt dem Schema (schema_version, block_size)"
else
  fail "Test 1b: Ledger-Schema unerwartet:
$T1_LEDGER"
fi
if [[ -f "${T1_WORK}/.gitignore" ]] && grep -q "board/id-reservations.yaml" "${T1_WORK}/.gitignore" 2>/dev/null; then
  fail "Test 1d: board/id-reservations.yaml ist gitignored — AC8 verlangt COMMITTET"
else
  pass "Test 1d: board/id-reservations.yaml ist NICHT gitignored (AC8 — committet auf default_branch)"
fi

# ===========================================================================
# Test 2 — @trace id-block-reservation#AC7
# Idempotenz: ein zweiter reserve-Aufruf für dieselbe (namespace, id) liefert
# denselben Block zurück, OHNE einen zweiten Eintrag anzulegen.
# ===========================================================================
echo ""
echo "--- Test 2: AC7 — erneuter reserve-Aufruf ist idempotent (kein zweiter Block) ---"
T2_OUT="$(cd "$T1_WORK" && "$RESERVE_SCRIPT" reserve BR F-001)"
if [[ "$T2_OUT" == "$T1_OUT" ]]; then
  pass "Test 2a: zweiter reserve-Aufruf liefert identisches Ergebnis"
else
  fail "Test 2a: reserve nicht idempotent — 1: $T1_OUT / 2: $T2_OUT"
fi
T2_COUNT="$(cd "$T1_WORK" && git fetch origin main -q && git show origin/main:board/id-reservations.yaml | grep -c "feature_id: F-001")"
if [[ "$T2_COUNT" -eq 1 ]]; then
  pass "Test 2b: genau EIN Ledger-Eintrag für F-001/BR (kein Ledger-Wachstum)"
else
  fail "Test 2b: erwartete 1 Eintrag für F-001/BR, gefunden: ${T2_COUNT}"
fi

# ===========================================================================
# Test 3 — @trace id-block-reservation#AC3
# Ein zweites Feature reserviert denselben Namespace -> disjunkter Block
# (kein geteilter Wert mit F-001s aktivem 1-10-Block).
# ===========================================================================
echo ""
echo "--- Test 3: AC3 — zweites Feature bekommt disjunkten Block (11-20) ---"
T3_OUT="$(cd "$T1_WORK" && "$RESERVE_SCRIPT" reserve BR F-002)"
T3_START="$(echo "$T3_OUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["range_start"])')"
T3_END="$(echo "$T3_OUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["range_end"])')"
if [[ "$T3_START" -eq 11 && "$T3_END" -eq 20 ]]; then
  pass "Test 3: F-002/BR bekommt disjunkten Block 11-20 (hinter F-001s aktivem 1-10)"
else
  fail "Test 3: erwartete Block 11-20, bekam ${T3_START}-${T3_END}"
fi

# ===========================================================================
# Test 4 — @trace id-block-reservation#AC5
# Block-Erschöpfung: extend legt IMMER einen weiteren, disjunkten Block für
# dieselbe (namespace, id)-Kombination an (kein Wiederverwenden des
# bestehenden aktiven Blocks, kein stiller Überlauf in fremden Bereich).
# ===========================================================================
echo ""
echo "--- Test 4: AC5 — extend legt zusätzlichen, disjunkten Block an (Block-Erschöpfung) ---"
T4_OUT="$(cd "$T1_WORK" && "$RESERVE_SCRIPT" extend BR F-001)"
T4_START="$(echo "$T4_OUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["range_start"])')"
T4_END="$(echo "$T4_OUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["range_end"])')"
if [[ "$T4_START" -eq 21 && "$T4_END" -eq 30 ]]; then
  pass "Test 4a: extend legt Block 21-30 an (hinter F-002s 11-20)"
else
  fail "Test 4a: erwartete Block 21-30, bekam ${T4_START}-${T4_END}"
fi
T4_COUNT="$(cd "$T1_WORK" && git fetch origin main -q && git show origin/main:board/id-reservations.yaml | grep -c "feature_id: F-001")"
if [[ "$T4_COUNT" -eq 2 ]]; then
  pass "Test 4b: F-001/BR hat jetzt 2 Reservierungs-Einträge (1-10 UND 21-30)"
else
  fail "Test 4b: erwartete 2 Einträge für F-001/BR, gefunden: ${T4_COUNT}"
fi

# ===========================================================================
# Test 5 — @trace id-block-reservation#AC4
# consume lehnt eine Nummer ausserhalb des reservierten Blocks hart ab (kein
# Ledger-Diff), akzeptiert eine gültige Nummer und aktualisiert high_water.
# ===========================================================================
echo ""
echo "--- Test 5: AC4 — consume verweigert Nummer ausserhalb des Blocks, akzeptiert gültige ---"
T5_LEDGER_BEFORE="$(cd "$T1_WORK" && git fetch origin main -q && git show origin/main:board/id-reservations.yaml)"
if (cd "$T1_WORK" && "$RESERVE_SCRIPT" consume BR F-001 999 >/dev/null 2>"${TEST_WORK_DIR}/t5.err"); then
  fail "Test 5a: consume mit id-number ausserhalb des Blocks hätte fehlschlagen müssen"
else
  pass "Test 5a: consume mit BR-999 (ausserhalb [1,10] UND [21,30]) schlägt fehl wie erwartet"
fi
T5_LEDGER_AFTER="$(cd "$T1_WORK" && git fetch origin main -q && git show origin/main:board/id-reservations.yaml)"
if [[ "$T5_LEDGER_BEFORE" == "$T5_LEDGER_AFTER" ]]; then
  pass "Test 5b: kein Ledger-Diff nach abgelehntem consume-Versuch"
else
  fail "Test 5b: Ledger hat sich trotz abgelehntem consume verändert"
fi
T5_OUT="$(cd "$T1_WORK" && "$RESERVE_SCRIPT" consume BR F-001 5)"
T5_HW="$(echo "$T5_OUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["high_water"])')"
if [[ "$T5_HW" == "5" ]]; then
  pass "Test 5c: consume mit gültiger Nummer (5, innerhalb [1,10]) aktualisiert high_water"
else
  fail "Test 5c: erwartete high_water=5, bekam ${T5_HW}"
fi

# ===========================================================================
# Test 6 — @trace id-block-reservation#AC10
# release markiert status=released, behält high_water. Ein NIE berührter
# Namespace (high_water null) wird komplett wiederverwendbar; der genutzte
# Teil eines teil-konsumierten Blocks bleibt dauerhaft blockiert, nur der
# ungenutzte Tail wird für spätere reserve-Aufrufe frei.
# ===========================================================================
echo ""
echo "--- Test 6: AC10 — release: high_water bleibt, ungenutzter Rest wiederverwendbar ---"
T6_REL="$(cd "$T1_WORK" && "$RESERVE_SCRIPT" release F-001)"
if echo "$T6_REL" | python3 -c '
import json, sys
entries = json.load(sys.stdin)
assert len(entries) == 2, entries
by_range = {(e["range_start"], e["range_end"]): e for e in entries}
assert by_range[(1, 10)]["status"] == "released" and by_range[(1, 10)]["high_water"] == 5, entries
assert by_range[(21, 30)]["status"] == "released" and by_range[(21, 30)]["high_water"] is None, entries
' 2>"${TEST_WORK_DIR}/t6.err"; then
  pass "Test 6a: release setzt beide F-001/BR-Reservierungen auf released, high_water bleibt stehen"
else
  fail "Test 6a: unerwarteter release-Output: $T6_REL ($(cat "${TEST_WORK_DIR}/t6.err"))"
fi
# F-001s freigegebener 21-30-Block wurde NIE konsumiert (high_water null) ->
# komplett wiederverwendbar; F-001s freigegebener 1-10-Block ist bis 5
# konsumiert -> nur 6-10 wäre frei, reicht für einen Blocksize-10-Request
# nicht -> next-free muss NACH F-002s aktivem 11-20-Block, in F-001s
# wiederverwendbarem 21-30 landen (first-fit).
T6_OUT="$(cd "$T1_WORK" && "$RESERVE_SCRIPT" reserve BR F-003)"
T6_START="$(echo "$T6_OUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["range_start"])')"
T6_END="$(echo "$T6_OUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["range_end"])')"
if [[ "$T6_START" -eq 21 && "$T6_END" -eq 30 ]]; then
  pass "Test 6b: neue Reservierung reused den komplett freigegebenen 21-30-Bereich (first-fit)"
else
  fail "Test 6b: erwartete Wiederverwendung von 21-30, bekam ${T6_START}-${T6_END}"
fi

# ===========================================================================
# Test 7 — @trace id-block-reservation#AC2 @trace id-block-reservation#AC3
# ECHTE Nebenläufigkeit (A1): zwei unabhängige Prozesse (zwei separate
# Arbeits-Klone derselben origin) reservieren GLEICHZEITIG denselben
# Namespace für unterschiedliche Features. Mindestens einer muss auf einen
# Push-Konflikt treffen und neu berechnen — das Ergebnis MUSS trotzdem
# disjunkt sein.
# ===========================================================================
echo ""
echo "--- Test 7: AC2/AC3 — echte Nebenläufigkeit: zwei parallele reserve-Aufrufe bleiben disjunkt ---"
T7_DIR="${TEST_WORK_DIR}/test7"
T7_ORIGIN="${T7_DIR}/origin.git"
mkdir -p "$T7_DIR"
git init --bare -q "$T7_ORIGIN"
# Gemeinsame Ausgangsbasis EINMAL zentral erzeugen+pushen (analog
# setup_fixture()) — verhindert, dass clone_a/clone_b sequentiell je einen
# EIGENEN init-Commit gegen dieselbe leere origin pushen (Race zwischen
# SHA-Kollision und Non-Fast-Forward-Reject, coder/L49).
T7_SEED="${T7_DIR}/seed"
git clone -q "$T7_ORIGIN" "$T7_SEED"
(
  cd "$T7_SEED"
  git config user.name test
  git config user.email test@test.local
  mkdir -p .claude
  cat > .claude/profile.md <<'YAML'
---
language: md
default_branch: main
---
YAML
  git add -A
  git commit -q -m init
  git branch -M main
  git push -q origin main
)
git clone -q "$T7_ORIGIN" "${T7_DIR}/clone_a"
git clone -q "$T7_ORIGIN" "${T7_DIR}/clone_b"
for c in clone_a clone_b; do
  (
    cd "${T7_DIR}/${c}"
    git config user.name test
    git config user.email test@test.local
  )
done
(cd "${T7_DIR}/clone_a" && "$RESERVE_SCRIPT" reserve C F-PARA-A > "${T7_DIR}/out_a.json" 2>"${T7_DIR}/err_a.log") &
T7_PID_A=$!
(cd "${T7_DIR}/clone_b" && "$RESERVE_SCRIPT" reserve C F-PARA-B > "${T7_DIR}/out_b.json" 2>"${T7_DIR}/err_b.log") &
T7_PID_B=$!
T7_EXIT_A=0; T7_EXIT_B=0
wait "$T7_PID_A" || T7_EXIT_A=$?
wait "$T7_PID_B" || T7_EXIT_B=$?
if [[ "$T7_EXIT_A" -eq 0 && "$T7_EXIT_B" -eq 0 ]]; then
  pass "Test 7a: beide parallelen reserve-Aufrufe laufen erfolgreich durch (kein Deadlock/Datenverlust)"
else
  fail "Test 7a: mindestens ein paralleler reserve-Aufruf ist fehlgeschlagen (A=${T7_EXIT_A}, B=${T7_EXIT_B})"
fi
T7_START_A="$(python3 -c 'import json; print(json.load(open("'"${T7_DIR}"'/out_a.json"))["range_start"])' 2>/dev/null || echo "")"
T7_END_A="$(python3 -c 'import json; print(json.load(open("'"${T7_DIR}"'/out_a.json"))["range_end"])' 2>/dev/null || echo "")"
T7_START_B="$(python3 -c 'import json; print(json.load(open("'"${T7_DIR}"'/out_b.json"))["range_start"])' 2>/dev/null || echo "")"
T7_END_B="$(python3 -c 'import json; print(json.load(open("'"${T7_DIR}"'/out_b.json"))["range_end"])' 2>/dev/null || echo "")"
if [[ -n "$T7_START_A" && -n "$T7_START_B" ]] && (( T7_END_A < T7_START_B || T7_END_B < T7_START_A )); then
  pass "Test 7b: beide Blöcke sind disjunkt (A=${T7_START_A}-${T7_END_A}, B=${T7_START_B}-${T7_END_B})"
else
  fail "Test 7b: Blöcke überlappen oder fehlen — A=${T7_START_A}-${T7_END_A}, B=${T7_START_B}-${T7_END_B}"
fi
if grep -q "Push-Konflikt" "${T7_DIR}/err_a.log" "${T7_DIR}/err_b.log" 2>/dev/null; then
  pass "Test 7c: mindestens ein Prozess traf tatsächlich auf einen Push-Konflikt (echte Race, kein Zufallstreffer)"
else
  fail "Test 7c: kein Push-Konflikt geloggt — Nebenläufigkeits-Szenario evtl. nicht tatsächlich geracet"
fi

# ===========================================================================
# Test 8 — @trace id-block-reservation#AC11 @trace id-block-reservation#AC2
# Endgültiger Push-Fehlschlag (pre-receive-Hook lehnt JEDEN Push ab): nach
# den konfigurierten Retries bricht das Skript mit Exit != 0 und
# Klartext-Diagnose ab. Der Ledger auf origin bleibt UNVERÄNDERT (kein
# Blind-Vergabe-Risiko, AC11).
# ===========================================================================
echo ""
echo "--- Test 8: AC11 — endgültiger Push-Fehlschlag -> harter Abbruch, Ledger unverändert ---"
T8_WORK="$(setup_fixture "${TEST_WORK_DIR}/test8")"
T8_ORIGIN="${TEST_WORK_DIR}/test8/origin.git"
mkdir -p "${T8_ORIGIN}/hooks"
cat > "${T8_ORIGIN}/hooks/pre-receive" <<'HOOK'
#!/bin/sh
echo "rejected: read-only test origin"
exit 1
HOOK
chmod +x "${T8_ORIGIN}/hooks/pre-receive"
T8_LEDGER_BEFORE="$(cd "$T8_WORK" && git show origin/main:board/id-reservations.yaml 2>/dev/null || echo "(fehlt)")"
T8_EXIT=0
( cd "$T8_WORK" && BOARD_ID_RESERVE_RETRIES=3 "$RESERVE_SCRIPT" reserve BR F-777 >/dev/null 2>"${TEST_WORK_DIR}/t8.err" ) || T8_EXIT=$?
if [[ "$T8_EXIT" -ne 0 ]]; then
  pass "Test 8a: reserve bricht mit Exit != 0 ab (kein Blind-Vergabe-Risiko)"
else
  fail "Test 8a: reserve hätte trotz permanentem Push-Reject fehlschlagen müssen"
fi
if grep -q "endgültig fehlgeschlagen" "${TEST_WORK_DIR}/t8.err"; then
  pass "Test 8b: Klartext-Diagnose ('endgültig fehlgeschlagen') auf stderr"
else
  fail "Test 8b: erwartete Klartext-Diagnose fehlt: $(cat "${TEST_WORK_DIR}/t8.err")"
fi
rm -f "${T8_ORIGIN}/hooks/pre-receive"
T8_LEDGER_AFTER="$(cd "$T8_WORK" && git fetch origin main -q && git show origin/main:board/id-reservations.yaml 2>/dev/null || echo "(fehlt)")"
if [[ "$T8_LEDGER_BEFORE" == "$T8_LEDGER_AFTER" ]]; then
  pass "Test 8c: Ledger auf origin ist nach dem endgültigen Fehlschlag UNVERÄNDERT"
else
  fail "Test 8c: Ledger hat sich trotz endgültigem Push-Fehlschlag verändert"
fi

# ===========================================================================
# Test 9 — @trace id-block-reservation#AC1
# Edge-Case "historisch vergebene IDs unterhalb des ersten Blocks": seed legt
# eine permanente Bestand-Reservierung an, die künftige Block-Berechnungen
# respektieren (kein Re-Use bestehender IDs unterhalb des Bestands).
# ===========================================================================
echo ""
echo "--- Test 9: AC1 (Edge-Case) — seed respektiert historischen Bestand bei der Block-Berechnung ---"
T9_WORK="$(setup_fixture "${TEST_WORK_DIR}/test9")"
(cd "$T9_WORK" && "$RESERVE_SCRIPT" seed ADR 50 >/dev/null)
T9_OUT="$(cd "$T9_WORK" && "$RESERVE_SCRIPT" reserve ADR F-900)"
T9_START="$(echo "$T9_OUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["range_start"])')"
if [[ "$T9_START" -eq 51 ]]; then
  pass "Test 9: neue Reservierung startet bei 51 (hinter dem geseedeten Bestand bis 50)"
else
  fail "Test 9: erwartete range_start=51, bekam ${T9_START}"
fi

# ===========================================================================
# Test 10 — @trace id-block-reservation#AC6
# Kollisionsfreie Konsolidierung: zwei "Feature-Batches" (F-101/F-102)
# reservieren + konsumieren unabhängig voneinander IDs aus ihren eigenen
# Blöcken -- keine der TATSÄCHLICH vergebenen Nummern kollidiert (End-to-
# End-Analogon zum BR-132-Vorfall, 2026-07-13 ki-investment).
# ===========================================================================
echo ""
echo "--- Test 10: AC6 — zwei Batches konsumieren unabhängig, keine kollidierenden IDs ---"
T10_WORK="$(setup_fixture "${TEST_WORK_DIR}/test10")"
(cd "$T10_WORK" && "$RESERVE_SCRIPT" reserve BR F-101 >/dev/null)
(cd "$T10_WORK" && "$RESERVE_SCRIPT" reserve BR F-102 >/dev/null)
(cd "$T10_WORK" && "$RESERVE_SCRIPT" consume BR F-101 3 >/dev/null)
(cd "$T10_WORK" && "$RESERVE_SCRIPT" consume BR F-101 4 >/dev/null)
(cd "$T10_WORK" && "$RESERVE_SCRIPT" consume BR F-102 12 >/dev/null)
T10_SHOW_101="$(cd "$T10_WORK" && "$RESERVE_SCRIPT" show F-101)"
T10_SHOW_102="$(cd "$T10_WORK" && "$RESERVE_SCRIPT" show F-102)"
if python3 -c "
import json
a = json.loads('''$T10_SHOW_101''')[0]
b = json.loads('''$T10_SHOW_102''')[0]
a_range = set(range(a['range_start'], a['range_end'] + 1))
b_range = set(range(b['range_start'], b['range_end'] + 1))
assert not (a_range & b_range), (a, b)
"; then
  pass "Test 10: F-101 (BR-3, BR-4) und F-102 (BR-12) liegen in disjunkten Blöcken — keine Kollision"
else
  fail "Test 10: Blöcke von F-101/F-102 überlappen — Kollisionsrisiko wie im BR-132-Vorfall"
fi

# ===========================================================================
# Test 11 — @trace id-block-reservation#AC9
# Board-weite /flow-Parität: derselbe Mechanismus funktioniert unverändert,
# wenn der Scope-Schlüssel eine Story-ID (S-###, board-weiter Einzellauf
# ohne --parent) statt einer Feature-ID (F-###) ist.
# ===========================================================================
echo ""
echo "--- Test 11: AC9 — derselbe Mechanismus mit Story-ID (S-###) statt Feature-ID ---"
T11_WORK="$(setup_fixture "${TEST_WORK_DIR}/test11")"
T11_OUT="$(cd "$T11_WORK" && "$RESERVE_SCRIPT" reserve BR S-063)"
T11_START="$(echo "$T11_OUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["range_start"])')"
(cd "$T11_WORK" && "$RESERVE_SCRIPT" consume BR S-063 3 >/dev/null)
T11_REL="$(cd "$T11_WORK" && "$RESERVE_SCRIPT" release S-063)"
if [[ "$T11_START" -eq 1 ]] && echo "$T11_REL" | python3 -c 'import json,sys; e=json.load(sys.stdin)[0]; assert e["status"]=="released" and e["high_water"]==3, e'; then
  pass "Test 11: reserve/consume/release funktionieren identisch mit einer S-###-Scope-ID (AC9-Parität)"
else
  fail "Test 11: unerwartetes Verhalten mit S-###-Scope-ID — reserve=${T11_OUT} release=${T11_REL}"
fi

echo ""
echo "=============================="
echo "Ergebnis: ${PASS} PASS, ${FAIL} FAIL"
echo "=============================="
[[ "$FAIL" -eq 0 ]]
