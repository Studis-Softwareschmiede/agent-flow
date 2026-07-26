#!/usr/bin/env bash
# tests/story-claim-lock/run-test.sh
#
# Self-Test für die mechanischen Anteile von docs/specs/story-claim-lock.md.
# Verwendet /tmp-Fixtures — berührt NIEMALS das echte board/ des Repos.
#
# Traceability (Spec-Fussnote "Da agent-flow `language: md` ist, erfolgt die
# Abnahme der Skill-/Doku-Anteile als Doku-Inspektion; Schema-, `board next`/
# `board ready`- und Reclamation-Logik werden über ein Smoke-Skript belegt"):
#
# Covers (story-claim-lock) — mechanisch (scripts/board):
#   @trace story-claim-lock#AC6
#   @trace story-claim-lock#AC7
#   @trace story-claim-lock#AC8
#   @trace story-claim-lock#AC9
#   @trace story-claim-lock#AC10
#   AC6  — `board next` liefert eine frisch geclaimte "In Progress"-Story NIE
#         als Kandidaten (weder als Primär- noch als Fallback-Treffer)
#         (Tests 1, 2)
#   AC7  — `stale_claim_hours` aus board.yaml (Default 4 wenn Feld fehlt/
#         ungueltig; Override wird respektiert) (Tests 2, 3, 4)
#   AC8  — Stale-Reclamation-Fallback: `board next` liefert eine stale
#         "In Progress"-Story NUR wenn keine bereite To-Do-Story existiert,
#         markiert mit "reclaimable": true; eine bereite To-Do-Story hat
#         IMMER Vorrang (nachrangig) (Tests 2, 3, 5)
#   AC9  — `board ready` weist stale-geclaimte "In Progress"-Stories als
#         eigene RECLAIMABLE-Kategorie aus, unabhängig von --quiet; eine
#         frische "In Progress"-Story bleibt (n/a) (Tests 6, 7)
#   AC10 — Schema (board/story.schema.json) kennt `claimed_by`/`claimed_at`;
#         `board set <id> claimed_by|claimed_at <wert>` schreibt + `board show`
#         liest sie zurück; bestehende Stories ohne die Felder bleiben lesbar
#         (Tests 8, 9, 10)
#
# Covers (story-claim-lock) — ECHTE Zwei-Klon-Nebenläufigkeit (Bare-Repo-
# Fixture, Muster tests/board-id-reservation/run-test.sh Test 7; reproduziert
# das Reviewer-Iteration-1-CRITICAL: zwei konkurrierende Claims schreiben
# dieselbe Story-YAML komplett neu, ein `git rebase`/`git merge` hätte hier
# einen hängenden Konflikt hinterlassen — daher rebase-frei via
# `git fetch` + `git show origin/<branch>:<pfad>` + `git reset --hard`):
#   @trace story-claim-lock#AC1
#   @trace story-claim-lock#AC2
#   @trace story-claim-lock#AC3
#   @trace story-claim-lock#AC4
#   AC1/AC2/AC3 — zwei echte Klone claimen dieselbe Story; der Verlierer-Push
#         wird real abgelehnt, die dokumentierte rebase-freie Recovery läuft
#         als literale Befehlsfolge (kein Mock) — verifiziert: kein hängender
#         Rebase-Zustand (`.git/rebase-merge` existiert nie), `board show`
#         funktioniert danach ohne Crash, Verlierer landet exakt auf
#         `origin/<branch>` (Test 12).
#   AC4  — Ablehnung durch unbezogenen Commit (dritter Klon) → Re-Read liefert
#         weiterhin `To Do` → Retry (reset + kompletter Claim-Vorgang neu)
#         landet erfolgreich (Test 13).
#
# Covers (story-claim-lock) — Doku-Inspektion (skills/flow/SKILL.md, kein
# Agent-Dispatch nötig — agent-flow ist `language: md`):
#   @trace story-claim-lock#AC1
#   @trace story-claim-lock#AC2
#   @trace story-claim-lock#AC3
#   @trace story-claim-lock#AC4
#   @trace story-claim-lock#AC5
#   @trace story-claim-lock#AC11
#   @trace story-claim-lock#AC12
#   @trace story-claim-lock#AC13
#   AC1/AC2/AC3/AC4/AC5/AC11/AC12/AC13 — Claim-Protokoll-Text vorhanden
#   (Test 11)
#
# Exit: 0 = alle Tests bestanden, 1 = mindestens ein Fehler

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
BOARD_SCRIPT="${REPO_ROOT}/scripts/board"
SKILL_FILE="${REPO_ROOT}/skills/flow/SKILL.md"
SCHEMA_FILE="${REPO_ROOT}/board/story.schema.json"

# Eigene TMPDIR-Variable (reviewer/L05: $TMPDIR nie überschreiben)
TEST_WORK_DIR="$(mktemp -d /tmp/story-claim-lock-test.XXXXXX)"
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

# now_minus_hours <n> — ISO-8601-UTC-Zeitstempel n Stunden in der Vergangenheit
now_minus_hours() {
  local hours="$1"
  date -u -v-"${hours}"H +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
    || date -u -d "-${hours} hours" +%Y-%m-%dT%H:%M:%SZ
}

now_ts() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

setup_board() {
  local work_dir="$1"
  local stale_claim_hours="${2:-}"
  mkdir -p "${work_dir}/board/features"
  mkdir -p "${work_dir}/board/stories"
  mkdir -p "${work_dir}/docs/specs"

  {
    echo "schema_version: 1"
    echo "project_slug: test-proj"
    echo "next_feature_id: 2"
    echo "next_story_id: 10"
    if [[ -n "$stale_claim_hours" ]]; then
      echo "stale_claim_hours: ${stale_claim_hours}"
    fi
  } > "${work_dir}/board/board.yaml"

  cat > "${work_dir}/board/features/F-001-test.yaml" <<'YAML'
id: F-001
title: Test Feature
goal: Testfeature
status: Active
priority: P1
spec: null
definition_of_done: null
labels: null
depends: null
owner: null
stories: null
progress: null
created_at: '2026-01-01T00:00:00Z'
updated_at: '2026-01-01T00:00:00Z'
YAML

  cat > "${work_dir}/docs/specs/test-spec.md" <<'MD'
---
id: test-spec
title: Test Spec
status: active
---
# Test Spec
AC1 — Testkriterium.
MD
}

# make_story <work_dir> <sid> <status> [claimed_by] [claimed_at]
make_story() {
  local work_dir="$1" sid="$2" status="$3" claimed_by="${4:-null}" claimed_at="${5:-null}"
  local slug
  slug="$(echo "$sid" | tr '[:upper:]' '[:lower:]')"

  local claimed_by_yaml claimed_at_yaml
  if [[ "$claimed_by" == "null" ]]; then claimed_by_yaml="null"; else claimed_by_yaml="'${claimed_by}'"; fi
  if [[ "$claimed_at" == "null" ]]; then claimed_at_yaml="null"; else claimed_at_yaml="'${claimed_at}'"; fi

  cat > "${work_dir}/board/stories/${sid}-${slug}.yaml" <<YAML
id: ${sid}
parent: F-001
title: Story ${sid}
status: ${status}
priority: P2
spec: docs/specs/test-spec.md
implements: [AC1]
depends: null
labels: null
claimed_by: ${claimed_by_yaml}
claimed_at: ${claimed_at_yaml}
created_at: '2026-01-01T00:00:00Z'
updated_at: '2026-01-01T00:00:00Z'
done_at: null
YAML
}

board_next() {
  local work_dir="$1"; shift
  (cd "$work_dir" && BOARD_DIR=board bash "$BOARD_SCRIPT" next "$@")
}

board_ready() {
  local work_dir="$1"; shift
  (cd "$work_dir" && BOARD_DIR=board bash "$BOARD_SCRIPT" ready "$@")
}

# ===========================================================================
# Test 1 (AC6) — nur eine frisch geclaimte "In Progress"-Story, kein To-Do
#   -> board next liefert NICHTS (kein Kandidat, weder primär noch reclaimable)
# ===========================================================================
echo ""
echo "--- Test 1 (AC6): frisch geclaimte In-Progress-Story wird NIE zurückgegeben ---"

T1_DIR="${TEST_WORK_DIR}/test1"
setup_board "$T1_DIR"
make_story "$T1_DIR" "S-001" "In Progress" "sess-fresh" "$(now_ts)"

T1_OUT="$(board_next "$T1_DIR")"
if [[ -z "$T1_OUT" ]]; then
  pass "Test 1: leere Ausgabe bei ausschliesslich frischem In-Progress-Claim (AC6)"
else
  fail "Test 1: erwartete leere Ausgabe, bekam: $T1_OUT"
fi

# ===========================================================================
# Test 2 (AC6/AC7/AC8) — Default stale_claim_hours=4 (kein Feld in board.yaml):
#   3h alter Claim -> noch NICHT stale -> leere Ausgabe
#   5h alter Claim -> stale -> reclaimable:true
# ===========================================================================
echo ""
echo "--- Test 2 (AC6/AC7/AC8): Default-Schwelle 4h ---"

T2_DIR="${TEST_WORK_DIR}/test2"
setup_board "$T2_DIR"
make_story "$T2_DIR" "S-001" "In Progress" "sess-3h" "$(now_minus_hours 3)"

T2A_OUT="$(board_next "$T2_DIR")"
if [[ -z "$T2A_OUT" ]]; then
  pass "Test 2a: 3h alter Claim (< Default 4h) noch nicht reclaimable (AC7)"
else
  fail "Test 2a: erwartete leere Ausgabe bei 3h altem Claim, bekam: $T2A_OUT"
fi

rm -f "${T2_DIR}/board/stories/S-001-s-001.yaml"
make_story "$T2_DIR" "S-002" "In Progress" "sess-5h" "$(now_minus_hours 5)"

T2B_OUT="$(board_next "$T2_DIR")"
if echo "$T2B_OUT" | grep -q '"id": "S-002"' && echo "$T2B_OUT" | grep -q '"reclaimable": true'; then
  pass "Test 2b: 5h alter Claim (> Default 4h) reclaimable:true (AC7/AC8)"
else
  fail "Test 2b: erwartete S-002 reclaimable:true, bekam: $T2B_OUT"
fi

# ===========================================================================
# Test 3 (AC7) — stale_claim_hours-Override in board.yaml wird respektiert
# ===========================================================================
echo ""
echo "--- Test 3 (AC7): stale_claim_hours-Override (1h) ---"

T3_DIR="${TEST_WORK_DIR}/test3"
setup_board "$T3_DIR" "1"
make_story "$T3_DIR" "S-001" "In Progress" "sess-old" "$(now_minus_hours 2)"

T3_OUT="$(board_next "$T3_DIR")"
if echo "$T3_OUT" | grep -q '"id": "S-001"' && echo "$T3_OUT" | grep -q '"reclaimable": true'; then
  pass "Test 3: 2h alter Claim bei stale_claim_hours=1 -> reclaimable:true (AC7)"
else
  fail "Test 3: erwartete S-001 reclaimable:true, bekam: $T3_OUT"
fi

# ===========================================================================
# Test 4 (AC7) — ungueltiger stale_claim_hours-Wert -> Default 4 greift
# ===========================================================================
echo ""
echo "--- Test 4 (AC7): ungueltiger stale_claim_hours-Wert -> Default 4 ---"

T4_DIR="${TEST_WORK_DIR}/test4"
setup_board "$T4_DIR" "not-a-number"
make_story "$T4_DIR" "S-001" "In Progress" "sess-3h" "$(now_minus_hours 3)"

T4_OUT="$(board_next "$T4_DIR")"
if [[ -z "$T4_OUT" ]]; then
  pass "Test 4: ungueltiger stale_claim_hours-Wert -> Default 4 greift (3h < 4h, kein Kandidat) (AC7)"
else
  fail "Test 4: erwartete leere Ausgabe (Default 4 sollte greifen), bekam: $T4_OUT"
fi

# ===========================================================================
# Test 5 (AC8) — bereite To-Do-Story hat Vorrang vor reclaimable Story
# ===========================================================================
echo ""
echo "--- Test 5 (AC8): To-Do-Kandidat nachrangig gegenüber stale Reclamation ---"

T5_DIR="${TEST_WORK_DIR}/test5"
setup_board "$T5_DIR"
make_story "$T5_DIR" "S-001" "To Do"
make_story "$T5_DIR" "S-002" "In Progress" "sess-dead" "$(now_minus_hours 10)"

T5_OUT="$(board_next "$T5_DIR")"
if echo "$T5_OUT" | grep -q '"id": "S-001"' && echo "$T5_OUT" | grep -q '"reclaimable": false'; then
  pass "Test 5: bereite To-Do-Story S-001 hat Vorrang vor reclaimable S-002 (AC8)"
else
  fail "Test 5: erwartete S-001 (reclaimable:false), bekam: $T5_OUT"
fi

# ===========================================================================
# Test 6 (AC9) — 'board ready' weist RECLAIMABLE-Kategorie aus
# ===========================================================================
echo ""
echo "--- Test 6 (AC9): 'board ready' RECLAIMABLE-Zeile bei stale Claim ---"

T6_DIR="${TEST_WORK_DIR}/test6"
setup_board "$T6_DIR"
make_story "$T6_DIR" "S-001" "In Progress" "sess-dead" "$(now_minus_hours 6)"

T6_OUT="$(board_ready "$T6_DIR" || true)"
if echo "$T6_OUT" | grep -qE '^RECLAIMABLE S-001: In Progress seit .*, Claim stale \(> 4h\)$'; then
  pass "Test 6: RECLAIMABLE-Zeile im erwarteten Format (AC9)"
else
  fail "Test 6: RECLAIMABLE-Zeile fehlt oder falsches Format"
  echo "  Output: $T6_OUT"
fi

# ===========================================================================
# Test 7 (AC9) — frische In-Progress-Story bleibt (n/a), keine RECLAIMABLE-
#   Zeile; --quiet unterdrückt (n/a), aber NICHT die RECLAIMABLE-Zeile
# ===========================================================================
echo ""
echo "--- Test 7 (AC9): frischer Claim -> (n/a); RECLAIMABLE ueberlebt --quiet ---"

T7_DIR="${TEST_WORK_DIR}/test7"
setup_board "$T7_DIR"
make_story "$T7_DIR" "S-001" "In Progress" "sess-fresh" "$(now_ts)"
make_story "$T7_DIR" "S-002" "In Progress" "sess-dead" "$(now_minus_hours 6)"

T7_OUT="$(board_ready "$T7_DIR" || true)"
if echo "$T7_OUT" | grep -q '(n/a)     S-001' && ! echo "$T7_OUT" | grep -q 'RECLAIMABLE S-001'; then
  pass "Test 7a: frischer Claim S-001 bleibt (n/a), keine RECLAIMABLE-Zeile (AC6/AC9)"
else
  fail "Test 7a: S-001 sollte (n/a) sein, kein RECLAIMABLE"
  echo "  Output: $T7_OUT"
fi

T7Q_OUT="$(board_ready "$T7_DIR" --quiet || true)"
if echo "$T7Q_OUT" | grep -q 'RECLAIMABLE S-002' && ! echo "$T7Q_OUT" | grep -q '(n/a)     S-001'; then
  pass "Test 7b: --quiet unterdrückt (n/a), RECLAIMABLE-Zeile bleibt sichtbar (AC9)"
else
  fail "Test 7b: --quiet-Verhalten falsch"
  echo "  Output: $T7Q_OUT"
fi

# ===========================================================================
# Test 8 (AC10) — Schema kennt claimed_by/claimed_at
# ===========================================================================
echo ""
echo "--- Test 8 (AC10): board/story.schema.json kennt claimed_by/claimed_at ---"

if python3 -c "
import json
with open('${SCHEMA_FILE}') as f:
    schema = json.load(f)
props = schema.get('properties', {})
assert 'claimed_by' in props, 'claimed_by fehlt'
assert 'claimed_at' in props, 'claimed_at fehlt'
assert 'string' in props['claimed_by']['type'] and 'null' in props['claimed_by']['type']
assert 'string' in props['claimed_at']['type'] and 'null' in props['claimed_at']['type']
required = schema.get('required', [])
assert 'claimed_by' not in required and 'claimed_at' not in required, 'sollten optional sein'
"; then
  pass "Test 8: Schema deklariert claimed_by/claimed_at als optionale string|null-Felder (AC10)"
else
  fail "Test 8: Schema-Check fehlgeschlagen"
fi

# ===========================================================================
# Test 9 (AC10) — 'board set' schreibt claimed_by/claimed_at, 'board show' liest zurück
# ===========================================================================
echo ""
echo "--- Test 9 (AC10): 'board set'/'board show' Roundtrip für claimed_by/claimed_at ---"

T9_DIR="${TEST_WORK_DIR}/test9"
setup_board "$T9_DIR"
make_story "$T9_DIR" "S-001" "To Do"

(cd "$T9_DIR" && BOARD_DIR=board BOARD_WRITER=flow bash "$BOARD_SCRIPT" set S-001 status "In Progress" >/dev/null)
(cd "$T9_DIR" && BOARD_DIR=board bash "$BOARD_SCRIPT" set S-001 claimed_by "host-123-42" >/dev/null)
(cd "$T9_DIR" && BOARD_DIR=board bash "$BOARD_SCRIPT" set S-001 claimed_at "2026-07-26T10:00:00Z" >/dev/null)

T9_SHOW="$(cd "$T9_DIR" && BOARD_DIR=board bash "$BOARD_SCRIPT" show S-001)"
if echo "$T9_SHOW" | grep -q '"claimed_by": "host-123-42"' && echo "$T9_SHOW" | grep -q '"claimed_at": "2026-07-26T10:00:00Z"'; then
  pass "Test 9: claimed_by/claimed_at über 'board set' geschrieben + über 'board show' korrekt gelesen (AC10)"
else
  fail "Test 9: Roundtrip fehlgeschlagen"
  echo "  Output: $T9_SHOW"
fi

# ===========================================================================
# Test 10 (AC10) — Story-YAML OHNE claimed_by/claimed_at bleibt lesbar
#   (Rückwärtskompatibilität — Default null, kein Nachtragen erzwungen)
# ===========================================================================
echo ""
echo "--- Test 10 (AC10): Alt-Story ohne claimed_by/claimed_at bleibt funktionsfähig ---"

T10_DIR="${TEST_WORK_DIR}/test10"
setup_board "$T10_DIR"
mkdir -p "${T10_DIR}/board/stories"
cat > "${T10_DIR}/board/stories/S-001-alt.yaml" <<'YAML'
id: S-001
parent: F-001
title: Alt-Story ohne Claim-Felder
status: To Do
priority: P2
spec: docs/specs/test-spec.md
implements: [AC1]
depends: null
labels: null
created_at: '2026-01-01T00:00:00Z'
updated_at: '2026-01-01T00:00:00Z'
done_at: null
YAML

T10_OUT="$(board_next "$T10_DIR")"
if echo "$T10_OUT" | grep -q '"id": "S-001"'; then
  pass "Test 10: Alt-Story ohne claimed_by/claimed_at wird von 'board next' weiterhin gefunden (AC10)"
else
  fail "Test 10: Alt-Story nicht gefunden — Output: $T10_OUT"
fi

# ===========================================================================
# Test 11 (Doku-Inspektion AC1/AC2/AC3/AC4/AC5/AC11/AC12/AC13) —
#   skills/flow/SKILL.md §1/§2 enthält das Claim-Protokoll
# ===========================================================================
echo ""
echo "--- Test 11: Doku-Inspektion skills/flow/SKILL.md (AC1-5/AC11-13) ---"

check_skill_contains() {
  local desc="$1" pattern="$2"
  if grep -qF "$pattern" "$SKILL_FILE"; then
    pass "Test 11: SKILL.md enthält '${desc}'"
  else
    fail "Test 11: SKILL.md fehlt '${desc}' (erwartetes Muster: ${pattern})"
  fi
}

check_skill_contains "Fetch vor board next (AC1)" 'board next` aufgerufen wird'
check_skill_contains "Claim vor coder-Dispatch (AC1)" 'startet, bevor der Claim-Push bestätigt ist'
check_skill_contains "sofortiges Committen+Pushen (AC1/AC2)" 'kein Zurückhalten bis Session-Ende'
check_skill_contains "Push-Ablehnung rebase-frei (AC2)" 'REBASE-FREI (AC2, HART)'
check_skill_contains "Re-Read via git show statt Working-Tree-Merge (AC2)" 'git show "origin/$default_branch:$STORY_FILE"'
check_skill_contains "Grund für rebase-frei dokumentiert (AC2, empirisch)" 'hängenden Rebase-Zustand'
check_skill_contains "Verlierer verwirft + board next erneut (AC3)" 'zurück zu **1. Nächstes Item wählen** (AC3)'
check_skill_contains "Retry-Budget 3 Versuche (AC4)" '3 Versuche insgesamt** (Retry-Budget, AC4)'
check_skill_contains "opaker Session-Token (AC5)" 'Opaken Session-Token erzeugen (AC5'
check_skill_contains "kein Dienst/Lock-Server (AC11)" 'kein Lock-Server, kein Daemon'
check_skill_contains "kein Fremd-Schreiben ausser Reclamation (AC12)" '**Kein Fremd-Schreiben (AC12).**'
check_skill_contains "sauberer Abbruch bei erschöpftem Budget (AC13)" 'Retry-Budget erschöpft** (AC13'

# ===========================================================================
# Zwei-Klon-Race-Fixture (Muster tests/board-id-reservation/run-test.sh Test 7)
# — bare "origin" + mehrere unabhängige Arbeits-Klone. Führt die in SKILL.md
# §2 dokumentierten Claim-/Recovery-Befehle als LITERALE Befehlsfolge aus
# (kein Mock) — belegt, dass die rebase-freie Recovery empirisch funktioniert.
# ===========================================================================

export GIT_AUTHOR_NAME="test" GIT_AUTHOR_EMAIL="test@test.local"
export GIT_COMMITTER_NAME="test" GIT_COMMITTER_EMAIL="test@test.local"

# setup_claim_origin <dir> — bare origin + Seed-Commit mit board-Skelett
# (F-001 + aktive Spec + Story S-001/S-002 status=To Do). Gibt den Pfad zum
# bare-Repo aus.
setup_claim_origin() {
  local dir="$1"
  local origin="${dir}/origin.git"
  local seed="${dir}/seed"
  git init --bare -q "$origin"
  git init -q "$seed"
  (
    cd "$seed"
    git config user.name test
    git config user.email test@test.local
    git remote add origin "$origin"
    mkdir -p board/features board/stories docs/specs
    cat > board/board.yaml <<'YAML'
schema_version: 1
project_slug: test-proj
next_feature_id: 2
next_story_id: 10
YAML
    cat > board/features/F-001-test.yaml <<'YAML'
id: F-001
title: Test Feature
goal: Testfeature
status: Active
priority: P1
spec: null
definition_of_done: null
labels: null
depends: null
owner: null
stories: null
progress: null
created_at: '2026-01-01T00:00:00Z'
updated_at: '2026-01-01T00:00:00Z'
YAML
    cat > docs/specs/test-spec.md <<'MD'
---
id: test-spec
title: Test Spec
status: active
---
# Test Spec
AC1 — Testkriterium.
MD
    for sid in S-001 S-002; do
      cat > "board/stories/${sid}-x.yaml" <<YAML
id: ${sid}
parent: F-001
title: Story ${sid}
status: To Do
priority: P2
spec: docs/specs/test-spec.md
implements: [AC1]
depends: null
labels: null
claimed_by: null
claimed_at: null
created_at: '2026-01-01T00:00:00Z'
updated_at: '2026-01-01T00:00:00Z'
done_at: null
YAML
    done
    git add -A
    git commit -q -m init
    git branch -M main
    git push -q origin main
  )
  # Bare-Repo-HEAD explizit auf refs/heads/main zeigen lassen — ein frisches
  # `git init --bare` defaultet HEAD auf refs/heads/master (unabhängig vom
  # tatsächlich gepushten Branch); ohne diesen Fix checkt jeder nachfolgende
  # `git clone` eine LEERE Working-Tree aus ("remote HEAD refers to
  # nonexistent ref"), obwohl alle Refs korrekt vorhanden sind.
  git -C "$origin" symbolic-ref HEAD refs/heads/main
  echo "$origin"
}

# do_claim <clone_dir> <sid> <token> — führt die SKILL.md-§2-Claim-Schritte
# 1-3 literal aus (Token setzen, Reservierung, Commit, Push). Gibt "0" (Push
# erfolgreich) oder "1" (Push abgelehnt) auf stdout aus.
do_claim() {
  local clone_dir="$1" sid="$2" token="$3"
  (
    cd "$clone_dir"
    BOARD_DIR=board BOARD_WRITER=flow bash "$BOARD_SCRIPT" set "$sid" status "In Progress" >/dev/null
    BOARD_DIR=board bash "$BOARD_SCRIPT" set "$sid" claimed_by "$token" >/dev/null
    BOARD_DIR=board bash "$BOARD_SCRIPT" set "$sid" claimed_at "$(now_ts)" >/dev/null
    BOARD_DIR=board bash "$BOARD_SCRIPT" set "$sid" branch "feat/${sid}-x" >/dev/null
    git add "board/stories/${sid}-x.yaml"
    git commit -q -m "chore(board): ${sid} claim (In Progress)"
    if git push -q origin HEAD:main 2>/dev/null; then
      echo "0"
    else
      echo "1"
    fi
  )
}

# ===========================================================================
# Test 12 (AC1/AC2/AC3, empirisch) — zwei Klone claimen S-001 SEQUENTIELL
# (A zuerst, dann B — B sieht den bereits gelandeten Claim von A nicht lokal,
# bevor B selbst committet+pusht, exakt wie im echten Race: Push-Reihenfolge
# entscheidet, nicht Lese-Reihenfolge) -> B's Push wird real abgelehnt ->
# die dokumentierte rebase-freie Recovery läuft literal.
# ===========================================================================
echo ""
echo "--- Test 12 (AC1/AC2/AC3, empirisch): Zwei-Klon-Race auf S-001, rebase-freie Recovery ---"

T12_DIR="${TEST_WORK_DIR}/test12"
T12_ORIGIN="$(setup_claim_origin "$T12_DIR")"
git clone -q "$T12_ORIGIN" "${T12_DIR}/clone_a"
git clone -q "$T12_ORIGIN" "${T12_DIR}/clone_b"
for c in clone_a clone_b; do
  (cd "${T12_DIR}/${c}" && git config user.name test && git config user.email test@test.local)
done

T12_TOKEN_A="host-a-1111-42"
T12_TOKEN_B="host-b-2222-99"

# A committet+pusht zuerst — muss gewinnen (Fast-Forward).
T12_RESULT_A="$(do_claim "${T12_DIR}/clone_a" "S-001" "$T12_TOKEN_A")"
if [[ "$T12_RESULT_A" == "0" ]]; then
  pass "Test 12a: Klon A gewinnt den Claim-Push für S-001 (Fast-Forward)"
else
  fail "Test 12a: Klon A hätte den Push gewinnen müssen, Ergebnis: $T12_RESULT_A"
fi

# B committet+pusht auf seinem (jetzt veralteten) lokalen Stand -> REAL abgelehnt.
T12_RESULT_B="$(do_claim "${T12_DIR}/clone_b" "S-001" "$T12_TOKEN_B")"
if [[ "$T12_RESULT_B" == "1" ]]; then
  pass "Test 12b: Klon B's Push wird real abgelehnt (non-fast-forward, echter Konflikt)"
else
  fail "Test 12b: Klon B's Push hätte abgelehnt werden müssen, Ergebnis: $T12_RESULT_B"
fi

# --- Rebase-freie Recovery in clone_b (SKILL.md §2, literal) ---
(
  cd "${T12_DIR}/clone_b"
  git fetch origin main --quiet
  STORY_FILE="$(git ls-files 'board/stories/S-001-*.yaml' | head -1)"
  REMOTE_STATUS="$(git show "origin/main:$STORY_FILE" | python3 -c 'import sys,yaml; print((yaml.safe_load(sys.stdin) or {}).get("status") or "")')"
  REMOTE_CLAIMED_BY="$(git show "origin/main:$STORY_FILE" | python3 -c 'import sys,yaml; print((yaml.safe_load(sys.stdin) or {}).get("claimed_by") or "")')"
  echo "$REMOTE_STATUS" > "${T12_DIR}/remote_status.txt"
  echo "$REMOTE_CLAIMED_BY" > "${T12_DIR}/remote_claimed_by.txt"
)
T12_REMOTE_STATUS="$(cat "${T12_DIR}/remote_status.txt")"
T12_REMOTE_CLAIMED_BY="$(cat "${T12_DIR}/remote_claimed_by.txt")"

if [[ "$T12_REMOTE_STATUS" == "In Progress" && "$T12_REMOTE_CLAIMED_BY" == "$T12_TOKEN_A" ]]; then
  pass "Test 12c: Re-Read via 'git show origin/main:<pfad>' liefert korrekt den fremden, frischen Claim (A) — Working-Tree unangetastet (AC2)"
else
  fail "Test 12c: Re-Read falsch — status='${T12_REMOTE_STATUS}' claimed_by='${T12_REMOTE_CLAIMED_BY}' (erwartet 'In Progress'/'${T12_TOKEN_A}')"
fi

# Kein hängender Rebase-Zustand — es wurde nie rebased.
if [[ ! -d "${T12_DIR}/clone_b/.git/rebase-merge" && ! -d "${T12_DIR}/clone_b/.git/rebase-apply" ]]; then
  pass "Test 12d: kein hängender Rebase-Zustand in Klon B (.git/rebase-merge|rebase-apply existiert nicht)"
else
  fail "Test 12d: Klon B hat einen hängenden Rebase-Zustand — CRITICAL-Regression"
fi

# Verlierer verwirft die eigene Reservierung (AC3) — reiner Fast-Forward-Reset.
(cd "${T12_DIR}/clone_b" && git reset --hard origin/main --quiet)

T12_HEAD_B="$(cd "${T12_DIR}/clone_b" && git rev-parse HEAD)"
T12_HEAD_ORIGIN="$(cd "${T12_DIR}/clone_b" && git rev-parse origin/main)"
if [[ "$T12_HEAD_B" == "$T12_HEAD_ORIGIN" ]]; then
  pass "Test 12e: Klon B landet exakt auf origin/main (eigener Claim-Commit vollständig verworfen, AC3)"
else
  fail "Test 12e: Klon B's HEAD (${T12_HEAD_B}) weicht von origin/main (${T12_HEAD_ORIGIN}) ab"
fi

T12_STATUS_PORCELAIN="$(cd "${T12_DIR}/clone_b" && git status --porcelain)"
if [[ -z "$T12_STATUS_PORCELAIN" ]]; then
  pass "Test 12f: Working-Tree in Klon B ist sauber nach der Recovery (keine Konfliktmarker, keine offenen Änderungen)"
else
  fail "Test 12f: Working-Tree in Klon B ist NICHT sauber: $T12_STATUS_PORCELAIN"
fi

T12_SHOW_OUT=""
T12_SHOW_EXIT=0
T12_SHOW_OUT="$(cd "${T12_DIR}/clone_b" && BOARD_DIR=board bash "$BOARD_SCRIPT" show S-001 2>&1)" || T12_SHOW_EXIT=$?
if [[ "$T12_SHOW_EXIT" -eq 0 ]] && echo "$T12_SHOW_OUT" | grep -q "\"claimed_by\": \"${T12_TOKEN_A}\""; then
  pass "Test 12g: 'board show S-001' funktioniert in Klon B nach der Recovery ohne Crash und zeigt A's Claim"
else
  fail "Test 12g: 'board show S-001' schlägt fehl oder zeigt falschen Claim — exit=${T12_SHOW_EXIT}, Output: $T12_SHOW_OUT"
fi

# ===========================================================================
# Test 13 (AC4, empirisch) — Push abgelehnt durch UNBEZOGENEN Commit (dritter
# Klon ändert S-002 nicht, sondern eine andere Datei) -> Re-Read liefert
# weiterhin "To Do" -> Retry (reset + kompletter Claim-Vorgang neu) gelingt.
# ===========================================================================
echo ""
echo "--- Test 13 (AC4, empirisch): Push abgelehnt durch unbezogenen Commit -> Retry gelingt ---"

T13_DIR="${TEST_WORK_DIR}/test13"
T13_ORIGIN="$(setup_claim_origin "$T13_DIR")"
git clone -q "$T13_ORIGIN" "${T13_DIR}/clone_b"
git clone -q "$T13_ORIGIN" "${T13_DIR}/clone_c"
for c in clone_b clone_c; do
  (cd "${T13_DIR}/${c}" && git config user.name test && git config user.email test@test.local)
done

# clone_b bereitet den Claim für S-002 lokal vor, pusht aber noch NICHT
# (simuliert: zwischen Vorbereitung und Push landet ein unbezogener Commit).
(
  cd "${T13_DIR}/clone_b"
  BOARD_DIR=board BOARD_WRITER=flow bash "$BOARD_SCRIPT" set S-002 status "In Progress" >/dev/null
  BOARD_DIR=board bash "$BOARD_SCRIPT" set S-002 claimed_by "host-b-claim" >/dev/null
  BOARD_DIR=board bash "$BOARD_SCRIPT" set S-002 claimed_at "$(now_ts)" >/dev/null
  BOARD_DIR=board bash "$BOARD_SCRIPT" set S-002 branch "feat/S-002-x" >/dev/null
  git add board/stories/S-002-x.yaml
  git commit -q -m "chore(board): S-002 claim (In Progress)"
)

# clone_c pusht einen UNBEZOGENEN Commit (aendert S-001, nicht S-002).
(
  cd "${T13_DIR}/clone_c"
  BOARD_DIR=board BOARD_WRITER=flow bash "$BOARD_SCRIPT" set S-001 status "Blocked" --reason "unbezogen" >/dev/null
  git add board/stories/S-001-x.yaml
  git commit -q -m "chore(board): S-001 blocked (unbezogen)"
  git push -q origin HEAD:main
)

# clone_b pusht jetzt -> abgelehnt (unbezogener Commit dazwischen).
T13_PUSH_RESULT=0
(cd "${T13_DIR}/clone_b" && git push -q origin HEAD:main 2>/dev/null) || T13_PUSH_RESULT=1
if [[ "$T13_PUSH_RESULT" -eq 1 ]]; then
  pass "Test 13a: Klon B's Push wird real abgelehnt (unbezogener Commit von Klon C dazwischen)"
else
  fail "Test 13a: Klon B's Push hätte abgelehnt werden müssen"
fi

# Rebase-freie Recovery: fetch + Re-Read via git show -> weiterhin "To Do".
(
  cd "${T13_DIR}/clone_b"
  git fetch origin main --quiet
  STORY_FILE="$(git ls-files 'board/stories/S-002-*.yaml' | head -1)"
  git show "origin/main:$STORY_FILE" | python3 -c 'import sys,yaml; print((yaml.safe_load(sys.stdin) or {}).get("status") or "")' \
    > "${T13_DIR}/remote_status.txt"
)
T13_REMOTE_STATUS="$(cat "${T13_DIR}/remote_status.txt")"
if [[ "$T13_REMOTE_STATUS" == "To Do" ]]; then
  pass "Test 13b: Re-Read zeigt S-002 weiterhin 'To Do' (Ablehnung war unbezogen, AC4)"
else
  fail "Test 13b: erwartete status='To Do', bekam '${T13_REMOTE_STATUS}'"
fi

# Retry: reset + kompletten Claim-Vorgang neu (gleiches Token).
(cd "${T13_DIR}/clone_b" && git reset --hard origin/main --quiet)
T13_RETRY_RESULT="$(do_claim "${T13_DIR}/clone_b" "S-002" "host-b-claim")"
if [[ "$T13_RETRY_RESULT" == "0" ]]; then
  pass "Test 13c: Retry nach unbezogener Ablehnung gelingt — Claim-Push landet (AC4)"
else
  fail "Test 13c: Retry hätte gelingen müssen, Ergebnis: $T13_RETRY_RESULT"
fi

T13_SHOW_EXIT=0
T13_SHOW_OUT="$(cd "${T13_DIR}/clone_b" && BOARD_DIR=board bash "$BOARD_SCRIPT" show S-002 2>&1)" || T13_SHOW_EXIT=$?
if [[ "$T13_SHOW_EXIT" -eq 0 ]] && echo "$T13_SHOW_OUT" | grep -q '"claimed_by": "host-b-claim"'; then
  pass "Test 13d: 'board show S-002' funktioniert nach erfolgreichem Retry, zeigt den eigenen Claim"
else
  fail "Test 13d: 'board show S-002' fehlgeschlagen oder falscher Claim — exit=${T13_SHOW_EXIT}, Output: $T13_SHOW_OUT"
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
