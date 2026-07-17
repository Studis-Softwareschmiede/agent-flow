#!/usr/bin/env bash
# tests/metrics-ledger-parse-robust/run-test.sh
#
# Self-Test für die zeilenweise Rollup-Parse-Robustheit (Spec
# metrics-recording-reliability V5/AC8, Story S-073).
#
# Kern-Befund (verifiziert 2026-07-17, dev-gui-Ledger): ein `jq -s` über alle
# Zeilen von dispatches.jsonl ist ATOMAR — eine einzige unparsbare Zeile lässt
# den gesamten Aufruf mit Exit 5 sterben; der `|| DEFAULT`-Fallback ersetzt
# das still durch Defaults (iters=1/crit=0/imp=0/secs_total=0 bzw.
# tok_total=null). Ab der ersten kaputten Zeile werden damit ALLE Rollups
# lautlos verfälscht. Die Kur: zeilenweise parsen (`jq -R -s
# 'split("\n") | map(fromjson? // empty)'`) statt `jq -s`, plus eine
# sichtbare `>&2`-Warnung mit der Anzahl übersprungener Zeilen (K3: nicht
# blockierend, aber nicht verschwiegen).
#
# Covers (metrics-recording-reliability):
#   AC8 — scripts/metrics-append-item.sh: eine korrupte dispatches.jsonl-Zeile
#     verfälscht NICHT mehr das Rollup der validen Zeilen desselben Items
#     (secs_total/iters/crit/imp bleiben korrekt statt auf Defaults zu
#     fallen); sichtbare stderr-Warnung mit der Anzahl übersprungener Zeilen
#     (Test 1). Regression: kein Fehlalarm ohne korrupte Zeile (Test 2).
#     Edge-Case: nur eine korrupte Zeile, keine valide → Defaults + Warnung,
#     kein Crash (Test 3).
#   AC8 — scripts/metrics-collect.sh (patch_items_tok_total): dieselbe
#     Robustheit für den tok_total-Rollup — eine korrupte Zeile verhindert
#     NICHT mehr das korrekte Aufsummieren der gepatchten tok-Felder valider
#     Zeilen; sichtbare stderr-Warnung (Test 4). Regression: kein Fehlalarm
#     ohne korrupte Zeile (Test 5).
#   AC8 — Review-Fund Iteration 2 (Wording): der skipped-Zähler läuft über
#     ALLE Zeilen der Datei, VOR der Item-Filterung — die Warnung ist eine
#     Datei-Eigenschaft, kein item-eigenes Ereignis. Eine kaputte Zeile eines
#     fremden Items triggert dieselbe Warnung beim Rollup jedes anderen
#     Items; das Wording behauptet das nicht fälschlich item-spezifisch
#     (Test 6).
#   AC8 — Review-Fund Iteration 2 (Typprüfung): eine Zeile mit einem validen
#     JSON-Skalar (kein Objekt, z.B. `42`) besteht `fromjson?`, aber wird
#     zusätzlich per `select(type=="object")` verworfen — zählt als
#     übersprungen statt als stiller Typfehler weiterzulaufen (Test 7).
#
# Verwendet lokale /tmp-Fixtures (eigenes METRICS_ROOT + eigenes
# CLAUDE_CONFIG_DIR mit Fake-Subagent-Transcripts) — berührt niemals das
# echte Board/Ledger dieses Repos.
#
# Exit: 0 = alle Tests bestanden, 1 = mindestens ein Fehler

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
APPEND_ITEM_SCRIPT="${REPO_ROOT}/scripts/metrics-append-item.sh"
COLLECT_SCRIPT="${REPO_ROOT}/scripts/metrics-collect.sh"

TEST_WORK_DIR="$(mktemp -d /tmp/metrics-ledger-parse-robust-test.XXXXXX)"
trap 'rm -rf "$TEST_WORK_DIR"' EXIT

FAIL=0
PASS=0
fail() { echo "FAIL: $*" >&2; FAIL=$((FAIL + 1)); }
pass() { echo "PASS: $*"; PASS=$((PASS + 1)); }

# --- Fixture-Aufbau: METRICS_ROOT mit board/board.yaml + .claude/metrics/ ---
setup_metrics_root() {
  local dir="$1"
  mkdir -p "${dir}/board" "${dir}/.claude/metrics"
  echo "schema_version: 1" > "${dir}/board/board.yaml"
  echo "$dir"
}

# ===========================================================================
# Test 1 — metrics-append-item.sh: korrupte Zeile (Muster aus dem Befund)
# + 3 valide Zeilen desselben Items -> Rollup korrekt, sichtbare Warnung
# ===========================================================================
echo ""
echo "--- Test 1: metrics-append-item.sh — korrupte Zeile vergiftet Rollup NICHT mehr ---"
T1_ROOT="$(setup_metrics_root "${TEST_WORK_DIR}/test1")"
cat > "${T1_ROOT}/.claude/metrics/dispatches.jsonl" <<'EOF'
{"ts":"2026-07-17T10:00:00Z","item":"S-999","seq":1,"agent":"coder","iter":1,"gate":"PASS","secs":100,"crit":0,"imp":0}
{"ts":"2026-07-17T10:00:01Z","item":"S-999","seq":1 coder 1 null 100,"agent":"","iter":null,"gate":null}
{"ts":"2026-07-17T10:05:00Z","item":"S-999","seq":2,"agent":"reviewer","iter":1,"gate":"PASS","secs":50,"crit":1,"imp":2}
{"ts":"2026-07-17T10:10:00Z","item":"S-999","seq":3,"agent":"tester","iter":1,"gate":"PASS","secs":30,"crit":0,"imp":0}
EOF
T1_OUTPUT="$(METRICS_ROOT="$T1_ROOT" bash "$APPEND_ITEM_SCRIPT" S-999 M null 10 2 0 md balanced null 2>&1)"
T1_EXIT=$?
T1_LAST_LINE="$(tail -n1 "${T1_ROOT}/.claude/metrics/items.jsonl" 2>/dev/null)"
T1_SECS="$(printf '%s' "$T1_LAST_LINE" | jq -r '.secs_total // "MISSING"' 2>/dev/null)"
T1_ITERS="$(printf '%s' "$T1_LAST_LINE" | jq -r '.iters // "MISSING"' 2>/dev/null)"
T1_CRIT="$(printf '%s' "$T1_LAST_LINE" | jq -r '.crit // "MISSING"' 2>/dev/null)"
T1_IMP="$(printf '%s' "$T1_LAST_LINE" | jq -r '.imp // "MISSING"' 2>/dev/null)"

if [[ $T1_EXIT -eq 0 ]]; then
  pass "Test 1a: Skript läuft trotz korrupter Zeile fehlerfrei durch (exit 0)"
else
  fail "Test 1a: exit=${T1_EXIT}"
fi
if [[ "$T1_SECS" == "180" ]]; then
  pass "Test 1b: secs_total korrekt aus den 3 validen Zeilen (100+50+30=180), NICHT auf Default 0 gefallen"
else
  fail "Test 1b: secs_total ist '${T1_SECS}', erwartet 180"
fi
if [[ "$T1_ITERS" == "1" && "$T1_CRIT" == "1" && "$T1_IMP" == "2" ]]; then
  pass "Test 1c: iters/crit/imp korrekt aus den validen Zeilen (1/1/2)"
else
  fail "Test 1c: iters=${T1_ITERS} crit=${T1_CRIT} imp=${T1_IMP}, erwartet 1/1/2"
fi
if echo "$T1_OUTPUT" | grep -q "1 unparsbare Zeile(n) im dispatches.jsonl-Ledger übersprungen"; then
  pass "Test 1d: sichtbare stderr-Warnung mit korrekter Anzahl (1) übersprungener Zeilen"
else
  fail "Test 1d: keine (oder falsche) Warnung gefunden"
  echo "  Output: $T1_OUTPUT"
fi

# ===========================================================================
# Test 2 — Regression: OHNE korrupte Zeile keine Warnung, Rollup unverändert
# ===========================================================================
echo ""
echo "--- Test 2: metrics-append-item.sh — Regression: keine Warnung ohne korrupte Zeile ---"
T2_ROOT="$(setup_metrics_root "${TEST_WORK_DIR}/test2")"
cat > "${T2_ROOT}/.claude/metrics/dispatches.jsonl" <<'EOF'
{"ts":"2026-07-17T10:00:00Z","item":"S-998","seq":1,"agent":"coder","iter":1,"gate":"PASS","secs":100,"crit":0,"imp":0}
{"ts":"2026-07-17T10:05:00Z","item":"S-998","seq":2,"agent":"reviewer","iter":1,"gate":"PASS","secs":50,"crit":1,"imp":2}
EOF
T2_OUTPUT="$(METRICS_ROOT="$T2_ROOT" bash "$APPEND_ITEM_SCRIPT" S-998 M null 5 1 0 md balanced null 2>&1)"
T2_LAST_LINE="$(tail -n1 "${T2_ROOT}/.claude/metrics/items.jsonl" 2>/dev/null)"
T2_SECS="$(printf '%s' "$T2_LAST_LINE" | jq -r '.secs_total // "MISSING"' 2>/dev/null)"

if [[ "$T2_SECS" == "150" ]]; then
  pass "Test 2a: secs_total korrekt (100+50=150) ohne jede Korruption"
else
  fail "Test 2a: secs_total ist '${T2_SECS}', erwartet 150"
fi
if echo "$T2_OUTPUT" | grep -q "unparsbare Zeile"; then
  fail "Test 2b: Warnung fälschlich ausgegeben, obwohl keine Zeile korrupt war"
else
  pass "Test 2b: keine Warnung — korrekt, da keine Zeile korrupt war"
fi

# ===========================================================================
# Test 3 — Edge-Case: nur eine korrupte Zeile, keine valide -> Defaults,
# Warnung, kein Crash
# ===========================================================================
echo ""
echo "--- Test 3: metrics-append-item.sh — nur korrupte Zeile(n): Defaults + Warnung, kein Crash ---"
T3_ROOT="$(setup_metrics_root "${TEST_WORK_DIR}/test3")"
printf 'not-json-at-all\n' > "${T3_ROOT}/.claude/metrics/dispatches.jsonl"
T3_OUTPUT="$(METRICS_ROOT="$T3_ROOT" bash "$APPEND_ITEM_SCRIPT" S-997 M null 0 0 0 md balanced null 2>&1)"
T3_EXIT=$?
T3_LAST_LINE="$(tail -n1 "${T3_ROOT}/.claude/metrics/items.jsonl" 2>/dev/null)"
T3_ITERS="$(printf '%s' "$T3_LAST_LINE" | jq -r '.iters // "MISSING"' 2>/dev/null)"

if [[ $T3_EXIT -eq 0 && "$T3_ITERS" == "1" ]]; then
  pass "Test 3a: kein Crash, Default-Rollup (iters=1) bei ausschließlich korrupten Zeilen"
else
  fail "Test 3a: exit=${T3_EXIT} iters=${T3_ITERS}"
fi
if echo "$T3_OUTPUT" | grep -q "1 unparsbare Zeile(n)"; then
  pass "Test 3b: Warnung auch im All-Corrupt-Fall sichtbar"
else
  fail "Test 3b: Warnung fehlt im All-Corrupt-Fall"
  echo "  Output: $T3_OUTPUT"
fi

# ===========================================================================
# Test 4 — metrics-collect.sh: korrupte dispatches.jsonl-Zeile vergiftet den
# tok_total-Rollup NICHT mehr, sichtbare Warnung
# ===========================================================================
echo ""
echo "--- Test 4: metrics-collect.sh — korrupte Zeile vergiftet tok_total-Rollup NICHT mehr ---"
T4_ROOT="$(setup_metrics_root "${TEST_WORK_DIR}/test4")"
T4_CONFIG_DIR="${TEST_WORK_DIR}/test4-claude-home"
mkdir -p "${T4_CONFIG_DIR}/.claude/projects/-fake-proj/session-1/subagents"
cat > "${T4_CONFIG_DIR}/.claude/projects/-fake-proj/session-1/subagents/agent-1.meta.json" <<'EOF'
{"agentType":"agent-flow:coder","description":"coder: S-999 implementieren"}
EOF
cat > "${T4_CONFIG_DIR}/.claude/projects/-fake-proj/session-1/subagents/agent-1.jsonl" <<'EOF'
{"type":"assistant","message":{"usage":{"input_tokens":100,"output_tokens":50,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}
EOF
cat > "${T4_ROOT}/.claude/metrics/dispatches.jsonl" <<'EOF'
{"ts":"2026-07-17T10:00:00Z","item":"S-999","seq":1,"agent":"coder","iter":1,"gate":"PASS","secs":100,"crit":0,"imp":0,"tok":null}
{"ts":"2026-07-17T10:00:01Z","item":"S-999","seq":1 coder 1 null 100,"agent":"","iter":null,"gate":null}
{"ts":"2026-07-17T10:05:00Z","item":"S-999","seq":2,"agent":"reviewer","iter":1,"gate":"PASS","secs":50,"crit":1,"imp":2,"tok":null}
EOF
echo '{"ts":"x","item":"S-999","ep_act":1,"tok_total":null}' > "${T4_ROOT}/.claude/metrics/items.jsonl"

T4_OUTPUT="$(CLAUDE_CONFIG_DIR="$T4_CONFIG_DIR" METRICS_ROOT="$T4_ROOT" bash "$COLLECT_SCRIPT" S-999 2>&1)"
T4_EXIT=$?
T4_TOK_TOTAL="$(tail -n1 "${T4_ROOT}/.claude/metrics/items.jsonl" | jq -r '.tok_total // "MISSING"' 2>/dev/null)"

if [[ $T4_EXIT -eq 0 ]]; then
  pass "Test 4a: metrics-collect.sh läuft trotz korrupter Zeile fehlerfrei durch (exit 0)"
else
  fail "Test 4a: exit=${T4_EXIT}"
fi
if [[ "$T4_TOK_TOTAL" == "150" ]]; then
  pass "Test 4b: tok_total korrekt (100+50=150) aus der gepatchten coder-Zeile, NICHT auf null gefallen"
else
  fail "Test 4b: tok_total ist '${T4_TOK_TOTAL}', erwartet 150"
  echo "  Output: $T4_OUTPUT"
fi
if echo "$T4_OUTPUT" | grep -q "1 unparsbare Zeile(n) im dispatches.jsonl-Ledger übersprungen"; then
  pass "Test 4c: sichtbare stderr-Warnung mit korrekter Anzahl (1) übersprungener Zeilen"
else
  fail "Test 4c: keine (oder falsche) Warnung gefunden"
  echo "  Output: $T4_OUTPUT"
fi

# ===========================================================================
# Test 5 — Regression: OHNE korrupte Zeile keine Warnung, tok_total unverändert
# ===========================================================================
echo ""
echo "--- Test 5: metrics-collect.sh — Regression: keine Warnung ohne korrupte Zeile ---"
T5_ROOT="$(setup_metrics_root "${TEST_WORK_DIR}/test5")"
T5_CONFIG_DIR="${TEST_WORK_DIR}/test5-claude-home"
mkdir -p "${T5_CONFIG_DIR}/.claude/projects/-fake-proj/session-1/subagents"
cat > "${T5_CONFIG_DIR}/.claude/projects/-fake-proj/session-1/subagents/agent-1.meta.json" <<'EOF'
{"agentType":"agent-flow:coder","description":"coder: S-996 implementieren"}
EOF
cat > "${T5_CONFIG_DIR}/.claude/projects/-fake-proj/session-1/subagents/agent-1.jsonl" <<'EOF'
{"type":"assistant","message":{"usage":{"input_tokens":10,"output_tokens":5,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}
EOF
cat > "${T5_ROOT}/.claude/metrics/dispatches.jsonl" <<'EOF'
{"ts":"2026-07-17T10:00:00Z","item":"S-996","seq":1,"agent":"coder","iter":1,"gate":"PASS","secs":20,"crit":0,"imp":0,"tok":null}
EOF
echo '{"ts":"x","item":"S-996","ep_act":1,"tok_total":null}' > "${T5_ROOT}/.claude/metrics/items.jsonl"

T5_OUTPUT="$(CLAUDE_CONFIG_DIR="$T5_CONFIG_DIR" METRICS_ROOT="$T5_ROOT" bash "$COLLECT_SCRIPT" S-996 2>&1)"
T5_TOK_TOTAL="$(tail -n1 "${T5_ROOT}/.claude/metrics/items.jsonl" | jq -r '.tok_total // "MISSING"' 2>/dev/null)"

if [[ "$T5_TOK_TOTAL" == "15" ]]; then
  pass "Test 5a: tok_total korrekt (10+5=15) ohne jede Korruption"
else
  fail "Test 5a: tok_total ist '${T5_TOK_TOTAL}', erwartet 15"
fi
if echo "$T5_OUTPUT" | grep -q "unparsbare Zeile"; then
  fail "Test 5b: Warnung fälschlich ausgegeben, obwohl keine Zeile korrupt war"
else
  pass "Test 5b: keine Warnung — korrekt, da keine Zeile korrupt war"
fi

# ===========================================================================
# Test 6 — Review-Fund Iteration 2 (Wording): eine kaputte Zeile "gehört"
# keinem Item (unparsbar), steht aber neben validen Zeilen eines FREMDEN
# Items (S-993) und des Ziel-Items (S-994). Der skipped-Zähler ist
# datei-weit, nicht item-gefiltert — die Warnung darf das NICHT als
# item-eigenes Ereignis behaupten (kein "... für S-994" mehr). Die
# Ziel-Item-Aggregate müssen trotzdem korrekt bleiben (fremdes Item S-993
# geht nicht mit ein).
# ===========================================================================
echo ""
echo "--- Test 6: metrics-append-item.sh — Warnung ist Datei-Eigenschaft, kein item-eigenes Ereignis (Wording) ---"
T6_ROOT="$(setup_metrics_root "${TEST_WORK_DIR}/test6")"
cat > "${T6_ROOT}/.claude/metrics/dispatches.jsonl" <<'EOF'
{"ts":"2026-07-17T10:00:00Z","item":"S-994","seq":1,"agent":"coder","iter":1,"gate":"PASS","secs":100,"crit":0,"imp":0}
totally-not-json-at-all
{"ts":"2026-07-17T10:05:00Z","item":"S-993","seq":1,"agent":"coder","iter":1,"gate":"PASS","secs":999,"crit":9,"imp":9}
EOF
T6_OUTPUT="$(METRICS_ROOT="$T6_ROOT" bash "$APPEND_ITEM_SCRIPT" S-994 M null 3 1 0 md balanced null 2>&1)"
T6_LAST_LINE="$(tail -n1 "${T6_ROOT}/.claude/metrics/items.jsonl" 2>/dev/null)"
T6_SECS="$(printf '%s' "$T6_LAST_LINE" | jq -r '.secs_total // "MISSING"' 2>/dev/null)"
T6_CRIT="$(printf '%s' "$T6_LAST_LINE" | jq -r '.crit // "MISSING"' 2>/dev/null)"

if [[ "$T6_SECS" == "100" && "$T6_CRIT" == "0" ]]; then
  pass "Test 6a: Ziel-Item-Aggregate (S-994) korrekt — weder von der kaputten Zeile noch vom fremden Item S-993 verfälscht"
else
  fail "Test 6a: secs_total=${T6_SECS} crit=${T6_CRIT}, erwartet 100/0"
fi
if echo "$T6_OUTPUT" | grep -q "1 unparsbare Zeile(n) im dispatches.jsonl-Ledger übersprungen"; then
  pass "Test 6b: Warnung erscheint (skipped-Zähler ist datei-weit, nicht item-gefiltert)"
else
  fail "Test 6b: Warnung fehlt oder falscher Wortlaut"
  echo "  Output: $T6_OUTPUT"
fi
T6_WARN_LINE="$(echo "$T6_OUTPUT" | grep "unparsbare Zeile" || true)"
if echo "$T6_WARN_LINE" | grep -q "S-994"; then
  fail "Test 6c: Warnzeile nennt S-994 — behauptet fälschlich ein item-eigenes Ereignis statt einer Datei-Eigenschaft"
  echo "  Warnzeile: $T6_WARN_LINE"
else
  pass "Test 6c: Warnzeile nennt KEIN Item — Datei-Eigenschaft korrekt kommuniziert, kein item-eigenes Ereignis behauptet"
fi

# ===========================================================================
# Test 7 — Review-Fund Iteration 2 (Typprüfung): eine valide-aber-falsch-
# geformte Zeile (JSON-Skalar `42`, kein Objekt) besteht fromjson?, muss
# aber trotzdem als übersprungen gezählt werden (select(type=="object")) —
# kein stiller Typfehler, kein Crash, echte Objektzeilen bleiben korrekt.
# ===========================================================================
echo ""
echo "--- Test 7: metrics-append-item.sh — valider JSON-Skalar (kein Objekt) wird als übersprungen gezählt ---"
T7_ROOT="$(setup_metrics_root "${TEST_WORK_DIR}/test7")"
cat > "${T7_ROOT}/.claude/metrics/dispatches.jsonl" <<'EOF'
{"ts":"2026-07-17T10:00:00Z","item":"S-995","seq":1,"agent":"coder","iter":1,"gate":"PASS","secs":40,"crit":0,"imp":0}
42
{"ts":"2026-07-17T10:05:00Z","item":"S-995","seq":2,"agent":"reviewer","iter":1,"gate":"PASS","secs":20,"crit":1,"imp":0}
EOF
T7_OUTPUT="$(METRICS_ROOT="$T7_ROOT" bash "$APPEND_ITEM_SCRIPT" S-995 M null 1 1 0 md balanced null 2>&1)"
T7_EXIT=$?
T7_LAST_LINE="$(tail -n1 "${T7_ROOT}/.claude/metrics/items.jsonl" 2>/dev/null)"
T7_SECS="$(printf '%s' "$T7_LAST_LINE" | jq -r '.secs_total // "MISSING"' 2>/dev/null)"

if [[ $T7_EXIT -eq 0 ]]; then
  pass "Test 7a: kein Crash bei validem JSON-Skalar ohne Objekt-Form"
else
  fail "Test 7a: exit=${T7_EXIT}"
fi
if [[ "$T7_SECS" == "60" ]]; then
  pass "Test 7b: Aggregate der echten Objektzeilen korrekt (40+20=60), Skalar-Zeile nicht mit eingerechnet"
else
  fail "Test 7b: secs_total ist '${T7_SECS}', erwartet 60"
fi
if echo "$T7_OUTPUT" | grep -q "1 unparsbare Zeile(n) im dispatches.jsonl-Ledger übersprungen"; then
  pass "Test 7c: Skalar-Zeile wird als übersprungen gezählt (select(type==\"object\") greift)"
else
  fail "Test 7c: Skalar-Zeile wurde nicht als übersprungen gezählt"
  echo "  Output: $T7_OUTPUT"
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
