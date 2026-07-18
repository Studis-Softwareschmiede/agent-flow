#!/usr/bin/env bash
# tests/board-plan-validate/run-test.sh
#
# Mechanisches Smoke-Skript fuer scripts/board-plan-validate.sh (analog
# tests/board-id-reservation) -- die mechanische Wellen-Revalidierung von
# docs/specs/parallel-session-plan.md AC6/AC7. agent-flow ist `language: md`
# (No-Op-Build), daher erfolgt die Abnahme der deterministischen
# Bash/Python-Mechanik hier mechanisch statt via Sprach-Testframework.
#
# Jeder Test traegt das kanonische Trace-Tag @trace parallel-session-plan#AC<n>
# (docs/architecture/traceability-subsystem.md).
#
# Covers (docs/specs/parallel-session-plan.md):
#   AC1  -- Plan-Modus (/flow --plan, EIN LLM-Planungsdurchgang): Doku-Vertrag
#     in skills/flow/SKILL.md §0b -- die eigentliche Wellenbildung ist ein
#     LLM-Analyseschritt (Hot-Spot + depends + Konflikt), kein deterministisches
#     Skript, daher hier NICHT unit-testbar -- per Doku-Inspektion verifiziert.
#   AC2  -- Plan-Artefakt-Schema (board/runs/session-plan.yaml): das Schema
#     selbst ist Vertrag in der Spec + §0b; dieses Skript liest ein
#     schema-konformes Fixture ein (Test 1-6 unten) und belegt damit, dass die
#     Revalidierung das dokumentierte Schema tatsaechlich konsumiert.
#   AC3  -- Konfliktfreiheit je Welle (Hot-Spot/depends/Konflikt-Check): Teil
#     der LLM-Planerstellung (§0b), nicht der Revalidierung -- Doku-Vertrag,
#     hier nicht (unit-)testbar.
#   AC4  -- Ein Schreiber je Story: Doku-Praezisierung in
#     docs/architecture/board-subsystem.md §7 -- kein mechanisches Skript
#     dieser Story implementiert das Schreiben selbst (bestehendes `board set`
#     bleibt unveraendert), daher hier nicht (unit-)testbar.
#   AC5  -- Freie, ausgewiesene Session-Zahl + Begruendung: Teil der
#     LLM-Planausgabe (§0b, rationale-Feld) -- Doku-Vertrag, nicht
#     mechanisch pruefbar ausserhalb der eigentlichen Planerstellung.
#   AC6  -- Mechanische Revalidierung vor jeder Welle (KERN dieses Skripts):
#     Done/Verworfen = erfuellt -> REMOVED (Test 1), nicht-terminale depends
#     (inkl. Blocked-Vorgaenger, deckt A1) -> WAITING (Test 1 + Test 2),
#     terminale depends -> READY (Test 1), leere Wellen-Stories-Liste (Test 5),
#     fehlende depends-Story (Test 6).
#   AC7  -- Landen bleibt seriell: reine Doku-Referenz auf den bestehenden
#     §5-Mechanismus (board-ship.sh) in §0c -- dieses Skript aendert daran
#     nichts und ist nicht der Ort dieser Garantie; nicht (unit-)testbar hier.
#   AC8  -- ID-Reservierungs-Vorbedingung: Doku-Vertrag in §0b (nutzt
#     scripts/board-id-reserve.sh show, bereits durch
#     tests/board-id-reservation abgedeckt) -- nicht Teil dieses Skripts.
#   AC9  -- Konsumenten-Vertrag aeussere Schleife: Schema+Semantik-Vertrag,
#     dev-gui-Implementierung ist Nicht-Ziel dieser Story -- Doku-Inspektion.
#   AC10 -- Kein Plan bei leerem Board: Doku-Vertrag in §0b (kein
#     session-plan.yaml bei 0 To-Do-Stories) -- Teil der Planerstellung, nicht
#     der Revalidierung; nicht (unit-)testbar durch dieses Skript.
#
# Zusaetzlich: Exit-Code-Vertrag von board-plan-validate.sh selbst (Test 3
# -- harter Abbruch bei invalidem Plan, Exit 2; Test 4 -- Aufruffehler,
# Exit 1).
#
# Verwendet lokale /tmp-Board-Fixtures (kein Git-Remote noetig -- die
# Revalidierung liest nur lokale board/-Dateien + die Plan-YAML). Exit:
# 0 = alle Tests bestanden, 1 = mindestens ein Fehler.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
VALIDATE_SCRIPT="${REPO_ROOT}/scripts/board-plan-validate.sh"

TEST_WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/board-plan-validate-test.XXXXXX")"
trap 'rm -rf "$TEST_WORK_DIR"' EXIT

FAIL=0
PASS=0
fail() { echo "FAIL: $*" >&2; FAIL=$((FAIL + 1)); }
pass() { echo "PASS: $*"; PASS=$((PASS + 1)); }

# setup_board <dir> -- legt ein minimales board/ Skelett an (board.yaml +
# stories/) OHNE Git -- die Revalidierung braucht keinen Remote.
setup_board() {
  local dir="$1"
  mkdir -p "${dir}/board/stories"
  cat > "${dir}/board/board.yaml" <<'YAML'
schema_version: 1
project_slug: test
next_feature_id: 1
next_story_id: 1
YAML
}

# write_story <dir> <id> <status> [<dep1,dep2,...>]
write_story() {
  local dir="$1" id="$2" status="$3" deps="${4:-}"
  local depends_yaml="[]"
  if [[ -n "$deps" ]]; then
    depends_yaml="[$(echo "$deps" | sed 's/,/, /g')]"
  fi
  cat > "${dir}/board/stories/${id}.yaml" <<YAML
id: ${id}
title: "Test-Story ${id}"
status: "${status}"
depends: ${depends_yaml}
YAML
}

# write_plan <dir> <wave> <stories-space-separated>
write_plan() {
  local dir="$1" wave="$2" stories="$3"
  local stories_yaml
  stories_yaml="[$(echo "$stories" | sed 's/ /, /g')]"
  cat > "${dir}/plan.yaml" <<YAML
schema_version: 1
generated_at: '2026-07-18T06:00:00Z'
board_ref: test
waves:
  - wave: ${wave}
    parallel: 1
    stories: ${stories_yaml}
    rationale: 'fixture'
YAML
}

# ===========================================================================
# Test 1 -- @trace parallel-session-plan#AC6
# Done/Verworfen = erfuellt (REMOVED), terminale depends -> READY,
# nicht-terminale depends -> WAITING.
# ===========================================================================
echo ""
echo "--- Test 1: AC6 -- Done/Verworfen entfernt, terminale depends READY, offene depends WAITING ---"
T1_DIR="${TEST_WORK_DIR}/test1"
setup_board "$T1_DIR"
write_story "$T1_DIR" "S-201" "To Do"
write_story "$T1_DIR" "S-202" "Done"
write_story "$T1_DIR" "S-203" "Verworfen"
write_story "$T1_DIR" "S-204" "To Do" "S-201"
write_plan "$T1_DIR" 1 "S-201 S-202 S-203 S-204"

T1_EXIT=0
T1_OUT="$(cd "$T1_DIR" && "$VALIDATE_SCRIPT" plan.yaml 1)" || T1_EXIT=$?
if [[ "$T1_EXIT" -eq 0 ]]; then
  pass "Test 1a: Exit 0 bei gueltiger Welle"
else
  fail "Test 1a: erwartete Exit 0, bekam ${T1_EXIT}"
fi
if echo "$T1_OUT" | grep -qF "REMOVED S-202 (Done)"; then
  pass "Test 1b: Done-Story wird als erfuellt entfernt (REMOVED)"
else
  fail "Test 1b: 'REMOVED S-202 (Done)' fehlt in Ausgabe: $T1_OUT"
fi
if echo "$T1_OUT" | grep -qF "REMOVED S-203 (Verworfen)"; then
  pass "Test 1c: Verworfen-Story wird als erfuellt entfernt (REMOVED)"
else
  fail "Test 1c: 'REMOVED S-203 (Verworfen)' fehlt in Ausgabe: $T1_OUT"
fi
if echo "$T1_OUT" | grep -qF "WAITING S-204: wartet auf S-201 (To Do)"; then
  pass "Test 1d: Story mit nicht-terminaler depends wird als WAITING gemeldet"
else
  fail "Test 1d: erwartete WAITING-Zeile fuer S-204 fehlt: $T1_OUT"
fi
if echo "$T1_OUT" | grep -qF "READY: S-201"; then
  pass "Test 1e: Story ohne offene depends landet in READY"
else
  fail "Test 1e: erwartete 'READY: S-201' fehlt: $T1_OUT"
fi

# ===========================================================================
# Test 2 -- @trace parallel-session-plan#AC6 (deckt A1)
# Blocked-Vorgaenger: die geblockte Story selbst wird entfernt (nicht mehr
# To Do), ihre Abhaengige wird uebersprungen und als WAITING gemeldet.
# ===========================================================================
echo ""
echo "--- Test 2: AC6/A1 -- Blocked-Vorgaenger uebersprungen + WAITING-Meldung ---"
T2_DIR="${TEST_WORK_DIR}/test2"
setup_board "$T2_DIR"
write_story "$T2_DIR" "S-301" "Blocked"
write_story "$T2_DIR" "S-302" "To Do" "S-301"
write_plan "$T2_DIR" 1 "S-301 S-302"

T2_OUT="$(cd "$T2_DIR" && "$VALIDATE_SCRIPT" plan.yaml 1)"
if echo "$T2_OUT" | grep -qF "REMOVED S-301 (Blocked)"; then
  pass "Test 2a: die geblockte Story selbst wird entfernt (nicht mehr To Do)"
else
  fail "Test 2a: erwartete 'REMOVED S-301 (Blocked)' fehlt: $T2_OUT"
fi
if echo "$T2_OUT" | grep -qF "WAITING S-302: wartet auf S-301 (Blocked)"; then
  pass "Test 2b: abhaengige Story wird uebersprungen + WAITING mit Grund gemeldet"
else
  fail "Test 2b: erwartete WAITING-Zeile fuer S-302 fehlt: $T2_OUT"
fi
if echo "$T2_OUT" | grep -qF "READY:" && ! echo "$T2_OUT" | grep -qE "READY: .+"; then
  pass "Test 2c: READY ist leer (kein startbarer Kandidat in dieser Welle)"
else
  fail "Test 2c: erwartete leere READY-Zeile: $T2_OUT"
fi

# ===========================================================================
# Test 3 -- @trace parallel-session-plan#AC6
# Grob invalider Plan: eine im Plan referenzierte Story existiert nicht mehr
# -> harter Abbruch (Exit 2), Klartext-Diagnose auf stderr.
# ===========================================================================
echo ""
echo "--- Test 3: AC6 -- Story existiert nicht mehr -> harter Abbruch (Exit 2) ---"
T3_DIR="${TEST_WORK_DIR}/test3"
setup_board "$T3_DIR"
write_story "$T3_DIR" "S-401" "To Do"
write_plan "$T3_DIR" 1 "S-401 S-999"

T3_EXIT=0
T3_ERR="$(cd "$T3_DIR" && "$VALIDATE_SCRIPT" plan.yaml 1 2>&1 >/dev/null)" || T3_EXIT=$?
if [[ "$T3_EXIT" -eq 2 ]]; then
  pass "Test 3a: nicht mehr existierende Story fuehrt zu Exit 2"
else
  fail "Test 3a: erwartete Exit 2, bekam ${T3_EXIT}"
fi
if echo "$T3_ERR" | grep -qi "grob invalider Plan"; then
  pass "Test 3b: Klartext-Diagnose 'grob invalider Plan' auf stderr"
else
  fail "Test 3b: erwartete Diagnose fehlt: $T3_ERR"
fi

# ===========================================================================
# Test 4 -- Aufruf-/Eingabefehler (fehlende Wellen-Nummer im Plan) -> Exit 1.
# ===========================================================================
echo ""
echo "--- Test 4: Wellen-Nummer nicht im Plan vorhanden -> Exit 1 ---"
T4_DIR="${TEST_WORK_DIR}/test4"
setup_board "$T4_DIR"
write_story "$T4_DIR" "S-501" "To Do"
write_plan "$T4_DIR" 1 "S-501"

T4_EXIT=0
(cd "$T4_DIR" && "$VALIDATE_SCRIPT" plan.yaml 2 >/dev/null 2>&1) || T4_EXIT=$?
if [[ "$T4_EXIT" -eq 1 ]]; then
  pass "Test 4: unbekannte Wellen-Nummer fuehrt zu Exit 1 (kein stiller Erfolg)"
else
  fail "Test 4: erwartete Exit 1, bekam ${T4_EXIT}"
fi

# ===========================================================================
# Test 5 -- @trace parallel-session-plan#AC6
# Leere stories-Liste einer Welle -> kein Fehler, nur leere READY-Ausgabe.
# ===========================================================================
echo ""
echo "--- Test 5: leere Wellen-Stories-Liste -> Exit 0, leere READY ---"
T5_DIR="${TEST_WORK_DIR}/test5"
setup_board "$T5_DIR"
cat > "${T5_DIR}/plan.yaml" <<'YAML'
schema_version: 1
generated_at: '2026-07-18T06:00:00Z'
board_ref: test
waves:
  - wave: 1
    parallel: 0
    stories: []
    rationale: 'leer'
YAML
T5_EXIT=0
T5_OUT="$(cd "$T5_DIR" && "$VALIDATE_SCRIPT" plan.yaml 1)" || T5_EXIT=$?
if [[ "$T5_EXIT" -eq 0 ]]; then
  pass "Test 5a: leere Welle fuehrt zu Exit 0 (kein Fehler)"
else
  fail "Test 5a: erwartete Exit 0, bekam ${T5_EXIT}"
fi
if echo "$T5_OUT" | grep -qF "READY:"; then
  pass "Test 5b: READY-Zeile vorhanden (leer)"
else
  fail "Test 5b: erwartete READY-Zeile fehlt: $T5_OUT"
fi

# ===========================================================================
# Test 6 -- @trace parallel-session-plan#AC6
# depends referenziert eine Story, die es gar nicht (mehr) gibt -> gilt als
# nicht erfuellt (WAITING, kein harter Abbruch -- der harte Abbruch gilt nur
# fuer im PLAN selbst gelistete, nicht mehr existierende Stories, Test 3).
# ===========================================================================
echo ""
echo "--- Test 6: fehlende depends-Story -> WAITING (not-found), kein harter Abbruch ---"
T6_DIR="${TEST_WORK_DIR}/test6"
setup_board "$T6_DIR"
write_story "$T6_DIR" "S-601" "To Do" "S-999"
write_plan "$T6_DIR" 1 "S-601"

T6_EXIT=0
T6_OUT="$(cd "$T6_DIR" && "$VALIDATE_SCRIPT" plan.yaml 1)" || T6_EXIT=$?
if [[ "$T6_EXIT" -eq 0 ]]; then
  pass "Test 6a: fehlende depends-Story fuehrt NICHT zum harten Abbruch (nur der Plan selbst ist hart, Test 3)"
else
  fail "Test 6a: erwartete Exit 0, bekam ${T6_EXIT}"
fi
if echo "$T6_OUT" | grep -qF "WAITING S-601: wartet auf S-999 (not-found)"; then
  pass "Test 6b: fehlende depends-Story wird als 'not-found' gemeldet (nicht erfuellt)"
else
  fail "Test 6b: erwartete WAITING-Zeile fehlt: $T6_OUT"
fi

echo ""
echo "=============================="
echo "Ergebnis: ${PASS} PASS, ${FAIL} FAIL"
echo "=============================="
[[ "$FAIL" -eq 0 ]]
