#!/usr/bin/env bash
# tests/board-round/finalize/run-test.sh
#
# Fixture-basiertes Smoke-Skript für scripts/board-round-finalize.sh
# (docs/architecture/flow-deterministic-runner.md §6.1/§8, Stufe-1-
# Abschluss-Primitiv). agent-flow ist `language: md` (No-Op-Build) — die
# Abnahme der deterministischen Bash/Python-Mechanik erfolgt daher hier
# mechanisch, analog tests/board-ship/run-test.sh und
# tests/board-id-reservation/run-test.sh.
#
# @trace flow-deterministic-runner#AC11 — Single-Writer bleibt: dieses
#   Skript schreibt NIRGENDS den Story-`status` (nur Dispo-Spiegel-Felder,
#   die kein Single-Writer-Feld sind, board-cli-Spec AC9) und committet/
#   pusht nichts selbst — Board-Status-Flip bleibt exklusiv bei
#   board-ship.sh (Test 6).
#
# Covers (Funktionsumfang laut Item-Auftrag, kein eigenes AC-Set — reine
# Bündelung bestehender, bereits andernorts spezifizierter Mechanik):
#   Test 1 — Metrik-Item-Append inkl. shortstat-Berechnung (SKILL.md §2b
#     "Beim Done"): items.jsonl-Zeile mit korrektem loc/files/size_est/
#     cost_mode/lang wird geschrieben.
#   Test 2 — Dispo-Spiegel (SKILL.md §2b "Dispo-Spiegel"): dispo_act/tok/
#     dispo_forecast landen korrekt in der Story-YAML, per Join gegen die
#     soeben geschriebene items.jsonl-Zeile.
#   Test 3 — ID-Block-Freigabe (SKILL.md §5, id-block-reservation AC9/AC10):
#     eine aktive Reservierung wird bei Landen freigegeben (status=released).
#   Test 4 — ID-Block-Freigabe ohne aktive Reservierung ist ein No-Op, kein
#     Fehlschlag (SKILL.md §5: "liefert dann ein leeres [] zurück").
#   Test 5 — Board-Status-Ausgabe (SKILL.md §7a), alle drei Fälle:
#     5a "Board nicht leer" (ready Item vorhanden), 5b "Board leer" (keine
#     To-Do-Stories), 5c "nichts abarbeitbar" (WAITING-Aggregat, leere
#     board-next-Ausgabe trotz vorhandener To-Do-Story).
#   Test 6 — Single-Writer-Invariante (AC11): Story-`status` bleibt vom
#     Skript unangetastet.
#   Test 7 — Usage-Fehler (fehlende Pflichtargumente / falsches ID-Format)
#     brechen sauber mit Exit ≠0 ab, ohne Seiteneffekt.
#   Test 8 — K3 (Metrik-Fehler blockiert nie): METRICS_ROOT zeigt auf ein
#     Verzeichnis ohne board/board.yaml — Skript läuft trotzdem bis zum Ende
#     durch (ID-Release + Board-Status-Ausgabe unbeeinträchtigt), Exit 0.
#
# Verwendet lokale /tmp-Git-Fixtures (bare "origin" + Arbeits-Klon) — berührt
# nie echtes GitHub. Exit: 0 = alle Tests bestanden, 1 = mindestens ein Fehler.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
FINALIZE_SCRIPT="${REPO_ROOT}/scripts/board-round-finalize.sh"
RESERVE_SCRIPT="${REPO_ROOT}/scripts/board-id-reserve.sh"

TEST_WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/board-round-finalize-test.XXXXXX")"
trap 'rm -rf "$TEST_WORK_DIR"' EXIT

FAIL=0
PASS=0
fail() { echo "FAIL: $*" >&2; FAIL=$((FAIL + 1)); }
pass() { echo "PASS: $*"; PASS=$((PASS + 1)); }

export GIT_AUTHOR_NAME="test" GIT_AUTHOR_EMAIL="test@test.local"
export GIT_COMMITTER_NAME="test" GIT_COMMITTER_EMAIL="test@test.local"
export BOARD_ID_RESERVE_SLEEP="${BOARD_ID_RESERVE_SLEEP:-0}"

# metrics-collect.sh sucht Subagent-Transcripts unter
# ${CLAUDE_CONFIG_DIR}/.claude/projects (Vorrang) bzw. $HOME/.claude/projects
# (Fallback, AC4/V3). OHNE eine existierende, aber LEERE
# ${CLAUDE_CONFIG_DIR}/.claude/projects fällt das Skript auf das ECHTE
# $HOME/.claude/projects zurück und durchsucht damit die realen, potenziell
# sehr grossen Transcript-Verzeichnisse dieser Maschine (beobachtet: Hänger/
# Minuten-lange Laufzeit). Eine leere, aber EXISTIERENDE Projects-Dir hält den
# Fallback-Zweig hermetisch (kein echtes Transcript gefunden -> tok bleibt
# null, K3-Verhalten unverändert, nur ohne den echten Scan).
FAKE_CLAUDE_CONFIG_DIR="${TEST_WORK_DIR}/fake-claude-config"
mkdir -p "${FAKE_CLAUDE_CONFIG_DIR}/.claude/projects"
export CLAUDE_CONFIG_DIR="$FAKE_CLAUDE_CONFIG_DIR"

DOCS_SPEC_CONTENT='---
id: fake-spec
status: active
---

# Spec

## Acceptance-Kriterien
- **AC1** — Testkriterium eins.
- **AC2** — Testkriterium zwei.
'

# setup_fixture <dir> — bare "origin" + Arbeits-Klon mit Board + Profil.
# S-901 (target, bereits Done, wie nach board-ship.sh-Landen) ist immer
# vorhanden; zusätzliche Stories übergibt der jeweilige Test per Callback.
setup_fixture() {
  local dir="$1"
  local origin="${dir}/origin.git"
  local work="${dir}/work"

  git init --bare -q "$origin"
  git init -q "$work"
  (
    cd "$work"
    git remote add origin "$origin"
    mkdir -p board/features board/stories docs/specs .claude/metrics
    cat > board/board.yaml <<'YAML'
schema_version: 1
project_slug: test-proj
next_feature_id: 2
next_story_id: 902
YAML
    cat > docs/specs/fake-spec.md <<SPECEOF
${DOCS_SPEC_CONTENT}
SPECEOF
    cat > board/stories/S-901-target.yaml <<'YAML'
id: S-901
parent: null
title: Target-Story (bereits gelandet)
status: Done
priority: P2
spec: docs/specs/fake-spec.md
implements:
- AC1
depends: null
labels: null
size_est: M
dispo_act: null
dispo_forecast: null
branch: feat/S-901-target
pr: null
created_at: '2026-01-01T00:00:00Z'
updated_at: '2026-01-01T00:00:00Z'
done_at: '2026-01-01T00:05:00Z'
YAML
    cat > .claude/profile.md <<'YAML'
---
language: md
merge_policy: direct
deploy: none
default_branch: main
---
Test-Profil.
YAML
    echo "initial" > README.md
    git add -A
    git commit -q -m "initial board setup"
    git branch -M main
    git push -q origin main
  )
  echo "$work"
}

# add_ready_story <work> — S-902, To Do, ready (gültige Spec, gültige AC).
add_ready_story() {
  local work="$1"
  cat > "${work}/board/stories/S-902-ready.yaml" <<'YAML'
id: S-902
parent: null
title: Ready-Story
status: To Do
priority: P2
spec: docs/specs/fake-spec.md
implements:
- AC2
depends: null
labels: null
branch: null
pr: null
created_at: '2026-01-01T00:00:00Z'
updated_at: '2026-01-01T00:00:00Z'
done_at: null
YAML
  ( cd "$work" && git add -A && git commit -q -m "add S-902 ready" && git push -q origin main )
}

# add_not_ready_story <work> — S-903, To Do, aber depends auf nicht
# existente Story -> WAITING depends-open, nie "ready".
add_not_ready_story() {
  local work="$1"
  cat > "${work}/board/stories/S-903-notready.yaml" <<'YAML'
id: S-903
parent: null
title: Not-Ready-Story
status: To Do
priority: P2
spec: docs/specs/fake-spec.md
implements:
- AC2
depends: S-999
labels: null
branch: null
pr: null
created_at: '2026-01-01T00:00:00Z'
updated_at: '2026-01-01T00:00:00Z'
done_at: null
YAML
  ( cd "$work" && git add -A && git commit -q -m "add S-903 not-ready" && git push -q origin main )
}

# ===========================================================================
# Test 1/2 — Metrik-Item-Append + Dispo-Spiegel (Happy Path)
# ===========================================================================
echo ""
echo "--- Test 1/2: Metrik-Item-Append (inkl. shortstat) + Dispo-Spiegel ---"
T12_WORK="$(setup_fixture "${TEST_WORK_DIR}/test12")"
T12_BASE_SHA="$(git -C "$T12_WORK" rev-parse HEAD)"
(
  cd "$T12_WORK"
  echo "line1" >> impl.txt
  echo "line2" >> impl.txt
  git add -A
  git commit -q -m "S-901 implementation diff"
)

set +e
T12_OUTPUT="$(cd "$T12_WORK" && METRICS_ROOT="$T12_WORK" bash "$FINALIZE_SCRIPT" S-901 "$T12_BASE_SHA" M 3.0 0 md balanced 100 2>&1)"
T12_EXIT=$?
set -e

if [[ $T12_EXIT -eq 0 ]]; then
  pass "Test 1a: Skript beendet mit Exit 0"
else
  fail "Test 1a: unerwarteter Exit ${T12_EXIT}
${T12_OUTPUT}"
fi

T12_ITEMS_FILE="${T12_WORK}/.claude/metrics/items.jsonl"
if [[ -f "$T12_ITEMS_FILE" ]] && grep -q '"item":"S-901"' "$T12_ITEMS_FILE"; then
  pass "Test 1b: items.jsonl enthält eine Zeile für S-901"
else
  fail "Test 1b: keine items.jsonl-Zeile für S-901 gefunden"
fi

T12_LAST_LINE="$(grep '"item":"S-901"' "$T12_ITEMS_FILE" | tail -1)"
T12_LOC="$(printf '%s' "$T12_LAST_LINE" | jq -r '.loc')"
T12_FILES="$(printf '%s' "$T12_LAST_LINE" | jq -r '.files')"
T12_SIZE="$(printf '%s' "$T12_LAST_LINE" | jq -r '.size_est')"
T12_LANG="$(printf '%s' "$T12_LAST_LINE" | jq -r '.lang')"
T12_COST_MODE="$(printf '%s' "$T12_LAST_LINE" | jq -r '.cost_mode')"
T12_TOK_EST="$(printf '%s' "$T12_LAST_LINE" | jq -r '.tok_est')"
if [[ "$T12_LOC" == "2" && "$T12_FILES" == "1" && "$T12_SIZE" == "M" && "$T12_LANG" == "md" && "$T12_COST_MODE" == "balanced" && "$T12_TOK_EST" == "100" ]]; then
  pass "Test 1c: shortstat/size_est/lang/cost_mode/tok_est korrekt aus Argumenten übernommen (loc=2, files=1)"
else
  fail "Test 1c: unerwartete items.jsonl-Felder: loc=${T12_LOC} files=${T12_FILES} size=${T12_SIZE} lang=${T12_LANG} cost_mode=${T12_COST_MODE} tok_est=${T12_TOK_EST}"
fi

T12_EP_ACT="$(printf '%s' "$T12_LAST_LINE" | jq -r '.ep_act')"
T12_STORY_YAML="${T12_WORK}/board/stories/S-901-target.yaml"
T12_DISPO_ACT="$(python3 -c "import yaml; print(yaml.safe_load(open('${T12_STORY_YAML}'))['dispo_act'])")"
if [[ "$T12_DISPO_ACT" == "$T12_EP_ACT" ]]; then
  pass "Test 2a: dispo_act in Story-YAML entspricht ep_act aus items.jsonl (Join korrekt, ${T12_EP_ACT})"
else
  fail "Test 2a: dispo_act (${T12_DISPO_ACT}) != ep_act (${T12_EP_ACT})"
fi

T12_TOK="$(python3 -c "import yaml; d=yaml.safe_load(open('${T12_STORY_YAML}')); print(d.get('tok'))")"
if [[ "$T12_TOK" == "None" ]]; then
  pass "Test 2b: tok-Feld in Story-YAML gesetzt (null, da keine echten Transcripts — erwartetes K3-Verhalten)"
else
  fail "Test 2b: unerwarteter tok-Wert in Story-YAML: ${T12_TOK}"
fi

# ep_est=3.0 wurde übergeben -> dispo_forecast muss berechnet + gesetzt sein
# (ep_act != 0, ep_est != null -> Formel greift, SKILL.md §2b).
T12_DISPO_FORECAST="$(python3 -c "import yaml; d=yaml.safe_load(open('${T12_STORY_YAML}')); print(d.get('dispo_forecast'))")"
T12_EXPECTED_FORECAST="$(python3 -c "print(round((3.0 - ${T12_EP_ACT}) / ${T12_EP_ACT}, 4))")"
if [[ "$T12_DISPO_FORECAST" == "$T12_EXPECTED_FORECAST" ]]; then
  pass "Test 2c: dispo_forecast korrekt berechnet (${T12_DISPO_FORECAST})"
else
  fail "Test 2c: dispo_forecast=${T12_DISPO_FORECAST}, erwartet ${T12_EXPECTED_FORECAST}"
fi

# ===========================================================================
# Test 3 — ID-Block-Freigabe: aktive Reservierung wird released
# ===========================================================================
echo ""
echo "--- Test 3: ID-Block-Freigabe — aktive Reservierung wird bei Landen released ---"
T3_WORK="$(setup_fixture "${TEST_WORK_DIR}/test3")"
T3_BASE_SHA="$(git -C "$T3_WORK" rev-parse HEAD)"
( cd "$T3_WORK" && "$RESERVE_SCRIPT" reserve BR S-901 >/dev/null )
T3_SHOW_BEFORE="$(cd "$T3_WORK" && "$RESERVE_SCRIPT" show S-901)"
if echo "$T3_SHOW_BEFORE" | jq -e '.[0].status == "active"' >/dev/null 2>&1; then
  pass "Test 3a: Vorbedingung — Reservierung ist aktiv vor dem Finalize-Lauf"
else
  fail "Test 3a: Vorbedingung fehlgeschlagen — Reservierung nicht aktiv: ${T3_SHOW_BEFORE}"
fi

( cd "$T3_WORK" && METRICS_ROOT="$T3_WORK" bash "$FINALIZE_SCRIPT" S-901 "$T3_BASE_SHA" >/dev/null 2>&1 )
T3_SHOW_AFTER="$(cd "$T3_WORK" && "$RESERVE_SCRIPT" show S-901)"
if echo "$T3_SHOW_AFTER" | jq -e '.[0].status == "released"' >/dev/null 2>&1; then
  pass "Test 3b: Reservierung für S-901 ist nach Finalize released"
else
  fail "Test 3b: Reservierung nicht released: ${T3_SHOW_AFTER}"
fi

# ===========================================================================
# Test 4 — ID-Block-Freigabe ohne aktive Reservierung: No-Op, kein Fehlschlag
# ===========================================================================
echo ""
echo "--- Test 4: ID-Block-Freigabe ohne aktive Reservierung ist ein No-Op ---"
T4_WORK="$(setup_fixture "${TEST_WORK_DIR}/test4")"
T4_BASE_SHA="$(git -C "$T4_WORK" rev-parse HEAD)"
set +e
T4_OUTPUT="$(cd "$T4_WORK" && METRICS_ROOT="$T4_WORK" bash "$FINALIZE_SCRIPT" S-901 "$T4_BASE_SHA" 2>&1)"
T4_EXIT=$?
set -e
if [[ $T4_EXIT -eq 0 ]]; then
  pass "Test 4: Finalize ohne aktive Reservierung endet trotzdem mit Exit 0 (kein Fehlschlag)"
else
  fail "Test 4: unerwarteter Exit ${T4_EXIT} ohne aktive Reservierung:
${T4_OUTPUT}"
fi

# ===========================================================================
# Test 5 — Board-Status-Ausgabe (§7a), alle drei Fälle
# ===========================================================================
echo ""
echo "--- Test 5a: Board-Status — 'Board nicht leer' (ready Item vorhanden) ---"
T5A_WORK="$(setup_fixture "${TEST_WORK_DIR}/test5a")"
add_ready_story "$T5A_WORK"
T5A_BASE_SHA="$(git -C "$T5A_WORK" rev-parse HEAD~1)"
T5A_OUTPUT="$(cd "$T5A_WORK" && METRICS_ROOT="$T5A_WORK" bash "$FINALIZE_SCRIPT" S-901 "$T5A_BASE_SHA" 2>&1)"
if echo "$T5A_OUTPUT" | grep -qE '^Board nicht leer — noch 1 abarbeitbare\(s\) Item\(s\), nächster Lauf nimmt voraussichtlich S-902\.$'; then
  pass "Test 5a: korrekte 'Board nicht leer'-Meldung mit Item-Zahl + nächster ID"
else
  fail "Test 5a: unerwartete Board-Status-Ausgabe:
${T5A_OUTPUT}"
fi

echo ""
echo "--- Test 5b: Board-Status — 'Board leer' (keine To-Do-Stories) ---"
T5B_WORK="$(setup_fixture "${TEST_WORK_DIR}/test5b")"
T5B_BASE_SHA="$(git -C "$T5B_WORK" rev-parse HEAD)"
T5B_OUTPUT="$(cd "$T5B_WORK" && METRICS_ROOT="$T5B_WORK" bash "$FINALIZE_SCRIPT" S-901 "$T5B_BASE_SHA" 2>&1)"
if echo "$T5B_OUTPUT" | grep -qE '^Board leer — keine abarbeitbaren Items\.$'; then
  pass "Test 5b: korrekte 'Board leer'-Meldung ohne To-Do-Stories"
else
  fail "Test 5b: unerwartete Board-Status-Ausgabe:
${T5B_OUTPUT}"
fi

echo ""
echo "--- Test 5c: Board-Status — 'nichts abarbeitbar' (WAITING-Aggregat) ---"
T5C_WORK="$(setup_fixture "${TEST_WORK_DIR}/test5c")"
add_not_ready_story "$T5C_WORK"
T5C_BASE_SHA="$(git -C "$T5C_WORK" rev-parse HEAD~1)"
T5C_OUTPUT="$(cd "$T5C_WORK" && METRICS_ROOT="$T5C_WORK" bash "$FINALIZE_SCRIPT" S-901 "$T5C_BASE_SHA" 2>&1)"
if echo "$T5C_OUTPUT" | grep -q '^nichts abarbeitbar — Gründe:$' && echo "$T5C_OUTPUT" | grep -q '^WAITING depends-open'; then
  pass "Test 5c: korrekte Leerlauf-Diagnose mit WAITING-Aggregat (depends-open)"
else
  fail "Test 5c: unerwartete Board-Status-Ausgabe:
${T5C_OUTPUT}"
fi

# ===========================================================================
# Test 6 — Single-Writer-Invariante (AC11): status bleibt unangetastet
# ===========================================================================
echo ""
echo "--- Test 6: AC11 — Story-status bleibt vom Skript unangetastet ---"
T6_WORK="$(setup_fixture "${TEST_WORK_DIR}/test6")"
T6_BASE_SHA="$(git -C "$T6_WORK" rev-parse HEAD)"
T6_STATUS_BEFORE="$(python3 -c "import yaml; print(yaml.safe_load(open('${T6_WORK}/board/stories/S-901-target.yaml'))['status'])")"
( cd "$T6_WORK" && METRICS_ROOT="$T6_WORK" bash "$FINALIZE_SCRIPT" S-901 "$T6_BASE_SHA" >/dev/null 2>&1 )
T6_STATUS_AFTER="$(python3 -c "import yaml; print(yaml.safe_load(open('${T6_WORK}/board/stories/S-901-target.yaml'))['status'])")"
if [[ "$T6_STATUS_BEFORE" == "Done" && "$T6_STATUS_AFTER" == "Done" ]]; then
  pass "Test 6: status blieb 'Done' — kein Board-Status-Flip durch dieses Skript"
else
  fail "Test 6: status veränderte sich unerwartet (vorher=${T6_STATUS_BEFORE}, nachher=${T6_STATUS_AFTER})"
fi
if grep -q 'BOARD_WRITER=flow' "$FINALIZE_SCRIPT" 2>/dev/null; then
  fail "Test 6b: Skript referenziert BOARD_WRITER — deutet auf einen (unerwarteten) Status-Schreibversuch hin"
else
  pass "Test 6b: kein BOARD_WRITER-Bezug im Skript (kein Status-Schreibversuch geplant)"
fi

# ===========================================================================
# Test 7 — Usage-Fehler: fehlende Pflichtargumente / falsches ID-Format
# ===========================================================================
echo ""
echo "--- Test 7: Usage-Fehler brechen sauber ab ---"
T7_WORK="$(setup_fixture "${TEST_WORK_DIR}/test7")"

set +e
bash "$FINALIZE_SCRIPT" >/dev/null 2>&1
T7A_EXIT=$?
set -e
if [[ $T7A_EXIT -ne 0 ]]; then
  pass "Test 7a: kein Argument -> Exit ≠0"
else
  fail "Test 7a: erwartete Exit ≠0 ohne Argumente, war 0"
fi

set +e
bash "$FINALIZE_SCRIPT" S-901 >/dev/null 2>&1
T7B_EXIT=$?
set -e
if [[ $T7B_EXIT -ne 0 ]]; then
  pass "Test 7b: fehlendes <base-sha> -> Exit ≠0"
else
  fail "Test 7b: erwartete Exit ≠0 ohne <base-sha>, war 0"
fi

set +e
bash "$FINALIZE_SCRIPT" "901" "HEAD" >/dev/null 2>&1
T7C_EXIT=$?
set -e
if [[ $T7C_EXIT -ne 0 ]]; then
  pass "Test 7c: falsches ID-Format ('901' statt 'S-901') -> Exit ≠0"
else
  fail "Test 7c: erwartete Exit ≠0 bei falschem ID-Format, war 0"
fi

# ===========================================================================
# Test 8 — K3: Metrik-Fehler (METRICS_ROOT ohne board.yaml) blockiert nie
# ===========================================================================
echo ""
echo "--- Test 8: K3 — ungültiges METRICS_ROOT blockiert die Runde nicht ---"
T8_WORK="$(setup_fixture "${TEST_WORK_DIR}/test8")"
add_ready_story "$T8_WORK"
T8_BASE_SHA="$(git -C "$T8_WORK" rev-parse HEAD~1)"
T8_BOGUS_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/board-round-finalize-bogus.XXXXXX")"
set +e
T8_OUTPUT="$(cd "$T8_WORK" && METRICS_ROOT="$T8_BOGUS_ROOT" bash "$FINALIZE_SCRIPT" S-901 "$T8_BASE_SHA" 2>&1)"
T8_EXIT=$?
set -e
rm -rf "$T8_BOGUS_ROOT"

if [[ $T8_EXIT -eq 0 ]]; then
  pass "Test 8a: Exit 0 trotz METRICS_ROOT ohne board/board.yaml"
else
  fail "Test 8a: unerwarteter Exit ${T8_EXIT}:
${T8_OUTPUT}"
fi
if echo "$T8_OUTPUT" | grep -qE '^Board nicht leer — noch 1 abarbeitbare\(s\) Item\(s\), nächster Lauf nimmt voraussichtlich S-902\.$'; then
  pass "Test 8b: Board-Status-Ausgabe (Schritt 5) läuft trotz Metrik-Fehlschlag unbeeinträchtigt weiter"
else
  fail "Test 8b: Board-Status-Ausgabe fehlt/falsch trotz K3-Erwartung:
${T8_OUTPUT}"
fi

# ===========================================================================
echo ""
echo "=== Ergebnis: ${PASS} passed, ${FAIL} failed ==="
[[ $FAIL -eq 0 ]]
