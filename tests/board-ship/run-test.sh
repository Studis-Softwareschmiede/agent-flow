#!/usr/bin/env bash
# tests/board-ship/run-test.sh
#
# Self-Test für scripts/board-ship.sh (L3 — deterministischer SHIP-Pfad,
# Owner-Auftrag 2026-07-06 nach dem S-047-Datenverlust-Vorfall).
#
# Covers:
#   L6-Guard — Working-Tree mit uncommitteten Änderungen: STOPP VOR jedem
#     git fetch/pull/reset, kein Datenverlust möglich (Test 1).
#   L3/echte Merge-Prüfung — bereits gemergter Commit wird per merge-base
#     erkannt (keine Behauptung übernommen), kein zweiter Merge-Versuch,
#     idempotent bei wiederholtem Aufruf (Test 2, Test 5).
#   Happy Path — merge_policy=direct, CI grün → Board-Flip auf Done mit
#     korrektem branch-Feld (Test 3).
#   CI-Gate — CI-Fehlschlag verhindert Board-Flip, Story bleibt NICHT Done
#     (Test 4).
#   Covers (board-ship-environment-guards): AC1 Skip auf Nicht-default_branch
#     ohne eigenen Run (Test 9a); AC2 default_branch bleibt IMMER scharf, mit
#     eigenem Run (Test 9b) und ohne jeden Run (Test 9c); AC3 Fail-safe bei
#     fremder headSha auf main (Test 9d) UND — Review-Fund Iteration 4 — auf
#     einem Nicht-default_branch mit persistierender fremder headSha über
#     mehrere Grace-Fenster-Iterationen, ohne das Fenster vorzeitig zu beenden
#     (Test 9e); Fail-safe bei einer echten gh-Abfrage-Störung im
#     Beobachtungsfenster (MOCK_GH_RUN_LIST_FAIL, coder/L03) — eskaliert
#     scharf statt zu skippen (Test 9f); AC5 BOARD_SHIP_CI_GRACE_SECS steuert
#     nur die Dauer (Test 9a via kleinem Grace-Wert, Test 9e via größerem
#     Grace-Wert für mehrere Iterationen, kein Effekt auf AC2-Pfade). AC4
#     (Repo ganz ohne Workflows) bleibt wie in v1 ungemockt/unverändert
#     (gh-api-Fallback der Test-Mocks liefert nie total_count==0) — kein
#     dedizierter Test, deckt sich mit AC6-Vorgabe (nur a-d gefordert).
#   Covers (board-ship-pr-merge-worktree-safe, S-122): AC1 PR-Merge OHNE
#     '--delete-branch'/lokalen Checkout, 'main' im zweiten Worktree belegt
#     bleibt unberührt (Test 12, statischer Beleg Test 16); AC2(a) nicht-null
#     Merge-Exit wird am Remote-PR-Zustand festgemacht statt sofort zu 'die'n
#     (Test 14a Erfolg via MERGED, Test 14b echter Fehlschlag/E1, Test 14c
#     'gh pr view' selbst gescheitert/E2 fail-safe K1); AC2(b) squash-
#     tauglicher Idempotenz-Zusatz-Check über PR-Status statt nur merge-base
#     (Test 13, deckt A2, kein zweiter PR); AC3 Board-Flip/Nacharbeit im
#     vorhandenen Temp-Detached-Worktree-Mechanismus auch im PR-Pfad, auch
#     bei belegtem 'main' (Test 12c, Test 14a-2 — Skript stirbt nie NACH
#     Merge-Erfolg); AC4 Remote-Branch-Löschung via API, nicht-fatal bei
#     Fehlschlag (Test 15); AC5 s.o. (Tests 12/13/14); AC6 direct-/
#     --target-branch-Pfad unverändert — implizit über alle unveränderten
#     Bestandstests (Test 1-11), die weiterhin grün bleiben.
#   Covers (board-ship-environment-guards, S-070): AC7 kein Checkout des
#     Ziel-Branches — belegt über einen ECHTEN zweiten Worktree, der 'main'
#     hält (Test 11a); AC8 FF-Push-Landung + Non-FF-Klartext-Abbruch ohne
#     Force/Reset (Test 11a happy path, Test 11b Non-FF); AC9 Board-Flip im
#     temporären detached Worktree, zuverlässiger Cleanup ohne Rest in 'git
#     worktree list' (Test 11a-6); AC11 L6-Guard unverändert (implizit über
#     alle Tests, die weiterhin scharf auf dirty Working-Tree reagieren,
#     Test 1); AC12 kein Force-Push/kein reset --hard auf ausgecheckten
#     Branch (Test 11b belegt sichtbaren statt stillen Non-FF-Abbruch). AC10
#     (Modus C worktree-tauglich) deckt Test 7 weiterhin ab (--merge-feature
#     landet unverändert korrekt, jetzt über denselben detached-Worktree-
#     Mechanismus wie AC9 statt über einen Checkout im aufrufenden Worktree).
#
# Verwendet lokale /tmp-Git-Fixtures (bare "origin" + Arbeits-Klon) und einen
# gemockten `gh` (+ No-Op `sleep`) in PATH — berührt NIEMALS echtes GitHub
# oder das echte board/ des Repos.
#
# Exit: 0 = alle Tests bestanden, 1 = mindestens ein Fehler

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SHIP_SCRIPT="${REPO_ROOT}/scripts/board-ship.sh"
BOARD_SCRIPT="${REPO_ROOT}/scripts/board"

TEST_WORK_DIR="$(mktemp -d /tmp/board-ship-test.XXXXXX)"
trap 'rm -rf "$TEST_WORK_DIR"' EXIT

FAIL=0
PASS=0
fail() { echo "FAIL: $*" >&2; FAIL=$((FAIL + 1)); }
pass() { echo "PASS: $*"; PASS=$((PASS + 1)); }

export BOARD_SHIP_SKIP_GH_AUTH=1
export GIT_AUTHOR_NAME="test" GIT_AUTHOR_EMAIL="test@test.local"
export GIT_COMMITTER_NAME="test" GIT_COMMITTER_EMAIL="test@test.local"

# --- Gemockter `gh` — antwortet aus Env-Variablen, berührt nie echtes GitHub ---
# MOCK_HEAD_SHA unset/leer simuliert "gh hat sauber geantwortet, aber (noch)
# kein Run vorhanden" (board-ship.sh v2 fragt dafür '.[0].headSha // "NOSHA"'
# ab — der Mock spiegelt das: NOSHA-Query -> "NOSHA", klassische Query (ohne
# Fallback) -> leere Zeile, wie es echtes `gh`+jq bei leerem Array/Fehler tut).
# MOCK_GH_RUN_LIST_FAIL=1 simuliert eine echte gh-Abfrage-Störung (Netz/Auth/
# Rate-Limit): 'gh run list' liefert nichts und beendet sich mit Exit 1.
MOCK_BIN_DIR="${TEST_WORK_DIR}/mockbin"
mkdir -p "$MOCK_BIN_DIR"
cat > "${MOCK_BIN_DIR}/gh" <<'MOCKEOF'
#!/usr/bin/env bash
if [[ "$1" == "run" && "$2" == "list" ]]; then
  if [[ "${MOCK_GH_RUN_LIST_FAIL:-0}" == "1" ]]; then
    echo "mock: gh run list fehlgeschlagen (simulierte Netz-/Auth-Störung)" >&2
    exit 1
  fi
  # --branch- UND --jq-Wert gezielt extrahieren (NICHT blind über alle
  # Argumente scannen: '--json headSha' enthält selbst die Teilzeichenkette
  # "headSha" und würde einen naiven Scan bereits VOR dem eigentlichen
  # --jq-Ausdruck fälschlich matchen lassen).
  branch="" jq_expr=""
  for ((i=1; i<=$#; i++)); do
    if [[ "${!i}" == "--branch" ]]; then j=$((i+1)); branch="${!j}"; fi
    if [[ "${!i}" == "--jq" ]]; then j=$((i+1)); jq_expr="${!j}"; fi
  done
  case "$jq_expr" in
    *'NOSHA'*)
      # '.[0].headSha // "NOSHA"' — v2-Beobachtungsfenster-Query (AC1/AC3):
      # kein MOCK_HEAD_SHA gesetzt -> "gh sauber, aber kein Run" -> "NOSHA".
      if [[ "${MOCK_HEAD_SHA:-}" == "AUTO" ]]; then
        echo "$(git rev-parse "origin/${branch}" 2>/dev/null)"
      elif [[ -n "${MOCK_HEAD_SHA:-}" ]]; then
        echo "${MOCK_HEAD_SHA}"
      else
        echo "NOSHA"
      fi
      exit 0 ;;
    *headSha*)
      # Klassische Query (ohne Fallback, unverändert seit v1) — nötig für
      # --merge-feature (MOCK_HEAD_SHA=AUTO -> dynamisch aus origin/<branch>
      # auflösen, da 'git merge --no-ff' eine im Voraus unbekannte SHA
      # erzeugt statt eines Fast-Forward auf eine bekannte SHA).
      if [[ "${MOCK_HEAD_SHA:-}" == "AUTO" ]]; then
        echo "$(git rev-parse "origin/${branch}" 2>/dev/null)"
      else
        echo "${MOCK_HEAD_SHA:-}"
      fi
      exit 0 ;;
    *'.status'*) echo "${MOCK_CI_STATUS:-completed}"; exit 0 ;;
    *conclusion*) echo "${MOCK_CI_CONCLUSION:-success}"; exit 0 ;;
  esac
  echo ""
  exit 0
fi
if [[ "$1" == "pr" && "$2" == "create" ]]; then
  if [[ "${MOCK_GH_PR_CREATE_FORBID:-0}" == "1" ]]; then
    echo "mock: gh pr create haette hier NICHT aufgerufen werden duerfen (Idempotenz-Test, S-122 AC5b)" >&2
    exit 1
  fi
  echo "https://github.com/mock/repo/pull/999"
  exit 0
fi
if [[ "$1" == "pr" && "$2" == "merge" ]]; then
  # S-122 AC1/AC2: 'gh pr merge <sel> --squash' OHNE '--delete-branch'. Der
  # Mock simuliert bei Bedarf den GitHub-seitigen Merge (Ziel-Branch bekommt
  # den Story-Commit) UND meldet den vom Test gewünschten Exit-Code separat
  # davon — genau das bildet den Defekt-2-Fall nach (Remote-Merge ok, aber
  # der CLI-Aufruf selbst meldet trotzdem einen Fehler).
  if [[ -n "${MOCK_GH_MERGE_SOURCE_BRANCH:-}" && -n "${MOCK_GH_MERGE_TARGET_BRANCH:-}" ]]; then
    git fetch origin "${MOCK_GH_MERGE_SOURCE_BRANCH}" -q 2>/dev/null || true
    git push -q origin "origin/${MOCK_GH_MERGE_SOURCE_BRANCH}:${MOCK_GH_MERGE_TARGET_BRANCH}" 2>/dev/null || true
  fi
  exit "${MOCK_GH_PR_MERGE_EXIT:-0}"
fi
if [[ "$1" == "pr" && "$2" == "view" ]]; then
  # S-122 AC2(a): 'gh pr view <sel> --json state,mergedAt --jq ...'
  if [[ "${MOCK_GH_PR_VIEW_FAIL:-0}" == "1" ]]; then
    echo "mock: gh pr view fehlgeschlagen (simulierte Netz-/Auth-Störung)" >&2
    exit 1
  fi
  case "${MOCK_PR_VIEW_STATE:-}" in
    MERGED) echo "true" ;;
    *) echo "false" ;;
  esac
  exit 0
fi
if [[ "$1" == "pr" && "$2" == "list" ]]; then
  # S-122 AC2(b): 'gh pr list --head <branch> --state all --json ... --jq ...'
  if [[ "${MOCK_GH_PR_LIST_FAIL:-0}" == "1" ]]; then
    echo "mock: gh pr list fehlgeschlagen (simulierte Netz-/Auth-Störung)" >&2
    exit 1
  fi
  case "${MOCK_PR_LIST_STATE:-}" in
    MERGED) echo "true" ;;
    *) echo "false" ;;
  esac
  exit 0
fi
if [[ "$1" == "api" ]]; then
  # S-122 AC4: 'gh api -X DELETE repos/<owner>/<repo>/git/refs/heads/<branch>'.
  # Alle anderen 'gh api'-Aufrufe (z.B. die bestehende actions/workflows-
  # Abfrage des CI-Watch) sind hier NICHT gemeint und fallen unverändert auf
  # den Catch-all am Skriptende durch (leere Ausgabe, Exit 0).
  if [[ " $* " == *" DELETE "* ]]; then
    if [[ "${MOCK_GH_API_DELETE_FAIL:-0}" == "1" ]]; then
      echo "mock: gh api DELETE fehlgeschlagen (simuliert, nicht-fatal laut AC4)" >&2
      exit 1
    fi
    exit 0
  fi
fi
exit 0
MOCKEOF
chmod +x "${MOCK_BIN_DIR}/gh"

# --- Gemockter `sleep` — No-Op, damit der klassische 40x15s-Scharf-Watch und
# das Beobachtungsfenster in Tests nicht real warten (Suite bleibt schnell,
# ohne am Skript selbst irgendeine neue Zeitsteuerung/einen neuen
# Env-Schalter einzuführen — reine Testinfrastruktur, board-ship.sh bleibt
# unverändert bei den zwei dokumentierten Env-Variablen).
cat > "${MOCK_BIN_DIR}/sleep" <<'MOCKEOF'
#!/usr/bin/env bash
exit 0
MOCKEOF
chmod +x "${MOCK_BIN_DIR}/sleep"

export PATH="${MOCK_BIN_DIR}:${PATH}"

# --- Fixture-Aufbau: bare "origin" + Arbeits-Klon mit Board + Profil ---
setup_fixture() {
  local dir="$1"
  local origin="${dir}/origin.git"
  local work="${dir}/work"

  git init --bare -q "$origin"

  git init -q "$work"
  (
    cd "$work"
    git remote add origin "$origin"
    mkdir -p board/features board/stories docs/specs .claude
    # HINWEIS (v2): board-ship.sh liest/parst .github/workflows/* in KEINER
    # Form mehr (Owner-Entscheid 2026-07-17) — die Trigger-Frage wird
    # ausschließlich empirisch über gemockte 'gh run list'-Antworten
    # beantwortet (MOCK_HEAD_SHA/MOCK_CI_STATUS/MOCK_CI_CONCLUSION). Die
    # Fixture braucht deshalb keine echten Workflow-Dateien mehr.
    cat > board/board.yaml <<'YAML'
schema_version: 1
project_slug: test-proj
next_feature_id: 2
next_story_id: 901
YAML
    cat > board/features/F-001-test.yaml <<'YAML'
id: F-001
title: Test-Feature
goal: Testfeature
status: Active
priority: P1
spec: null
definition_of_done: null
labels: null
depends: null
owner: null
area: null
stories: null
progress: null
created_at: '2026-01-01T00:00:00Z'
updated_at: '2026-01-01T00:00:00Z'
YAML
    cat > board/stories/S-900-test.yaml <<'YAML'
id: S-900
parent: F-001
title: Test-Story
status: In Review
priority: P2
spec: null
implements: null
depends: null
labels: null
branch: null
pr: null
created_at: '2026-01-01T00:00:00Z'
updated_at: '2026-01-01T00:00:00Z'
done_at: null
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
    git add -A
    git commit -q -m "initial board setup"
    git branch -M main
    git push -q origin main
  )
  echo "$work"
}

# Schaltet eine bereits per setup_fixture angelegte Arbeitskopie von
# 'merge_policy: direct' (Fixture-Default) auf 'merge_policy: pr' um und
# committet/pusht die Änderung nach origin/main — für die S-122-Tests
# (AC1-AC5), die den PR-Merge-Pfad (gh pr create/merge statt FF-Push)
# gezielt exerzieren.
set_pr_policy() {
  local work="$1"
  sed -i.bak 's/merge_policy: direct/merge_policy: pr/' "${work}/.claude/profile.md"
  rm -f "${work}/.claude/profile.md.bak"
  (cd "$work" && git add -A && git commit -q -m "profile: merge_policy pr (S-122-Test)" && git push -q origin main)
}

# ===========================================================================
# Test 1 — L6-Guard: uncommittete Änderungen STOPPEN vor jedem git-Zugriff
# ===========================================================================
echo ""
echo "--- Test 1: L6-Guard — uncommittete Änderungen brechen VOR git fetch/reset ab ---"
T1_WORK="$(setup_fixture "${TEST_WORK_DIR}/test1")"
(
  cd "$T1_WORK"
  git checkout -q -b feat/S-900-test
  echo "dirty" >> README-dirty.md
)
T1_REMOTE_BEFORE="$(git -C "$T1_WORK" rev-parse origin/main)"
set +e
T1_OUTPUT="$(cd "$T1_WORK" && bash "$SHIP_SCRIPT" S-900 2>&1)"
T1_EXIT=$?
set -e
T1_REMOTE_AFTER="$(git -C "$T1_WORK" rev-parse origin/main)"

if [[ $T1_EXIT -ne 0 ]] && echo "$T1_OUTPUT" | grep -q "uncommittete Änderungen"; then
  pass "Test 1a: Script bricht mit klarer Guard-Meldung ab bei dirty Working-Tree"
else
  fail "Test 1a: kein Guard-Abbruch erkannt (exit=$T1_EXIT)"
  echo "  Output: $T1_OUTPUT"
fi
if [[ "$T1_REMOTE_BEFORE" == "$T1_REMOTE_AFTER" ]]; then
  pass "Test 1b: origin/main unverändert — kein Datenzugriff vor dem Guard-Abbruch"
else
  fail "Test 1b: origin/main hat sich trotz Guard-Abbruch verändert!"
fi

# ===========================================================================
# Test 2 — echte Merge-Prüfung: bereits gemergter Commit wird per merge-base
# erkannt (Kern-Fix des S-047-Vorfalls: keine Behauptung, echte Prüfung)
# ===========================================================================
echo ""
echo "--- Test 2: bereits gemergter Commit wird per merge-base erkannt (kein zweiter Merge) ---"
T2_WORK="$(setup_fixture "${TEST_WORK_DIR}/test2")"
(
  cd "$T2_WORK"
  git checkout -q -b feat/S-900-test
  echo "feature" > feature.txt
  git add -A
  git commit -q -m "S-900: feature work"
  git checkout -q main
  git merge -q --no-ff feat/S-900-test -m "merge S-900"
  git push -q origin main
  git checkout -q feat/S-900-test   # zurück auf den (bereits gemergten) Story-Branch
)
export MOCK_HEAD_SHA MOCK_CI_STATUS="completed" MOCK_CI_CONCLUSION="success"
MOCK_HEAD_SHA="$(git -C "$T2_WORK" rev-parse origin/main)"
T2_OUTPUT="$(cd "$T2_WORK" && bash "$SHIP_SCRIPT" S-900 2>&1)"
T2_EXIT=$?

if [[ $T2_EXIT -eq 0 ]] && echo "$T2_OUTPUT" | grep -q "bereits gemergt"; then
  pass "Test 2a: bereits gemergter Commit korrekt per merge-base erkannt"
else
  fail "Test 2a: 'bereits gemergt' nicht erkannt (exit=$T2_EXIT)"
  echo "  Output: $T2_OUTPUT"
fi
# AC9 (S-070): der Board-Flip landet seit dem worktree-tauglichen Landen in
# einem temporären, detached Worktree und pusht nach origin — NICHT mehr in
# der lokalen Arbeitskopie von $T2_WORK. Assertion daher gegen origin/main.
T2_STATUS="$(git -C "$T2_WORK" show origin/main:board/stories/S-900-test.yaml 2>/dev/null | grep '^status:' || true)"
if [[ "$T2_STATUS" == "status: Done" ]]; then
  pass "Test 2b: Board trotzdem korrekt auf Done geflippt (CI-Check + Board-Flip laufen weiter, im origin/main-Stand)"
else
  fail "Test 2b: Board nicht auf Done (${T2_STATUS})"
fi

# ===========================================================================
# Test 3 — Happy Path: merge_policy=direct, CI gruen -> Board-Flip auf Done
# ===========================================================================
echo ""
echo "--- Test 3: Happy Path — direct-Merge, CI gruen, Board-Flip + branch-Feld ---"
T3_WORK="$(setup_fixture "${TEST_WORK_DIR}/test3")"
(
  cd "$T3_WORK"
  git checkout -q -b feat/S-900-test
  echo "feature" > feature.txt
  git add -A
  git commit -q -m "S-900: feature work"
)
export MOCK_HEAD_SHA MOCK_CI_STATUS="completed" MOCK_CI_CONCLUSION="success"
T3_OUTPUT="$(cd "$T3_WORK" && MOCK_HEAD_SHA="$(git rev-parse HEAD)" bash "$SHIP_SCRIPT" S-900 2>&1)"
T3_EXIT=$?

if [[ $T3_EXIT -eq 0 ]]; then
  pass "Test 3a: Happy Path läuft ohne Fehler durch (exit 0)"
else
  fail "Test 3a: exit=${T3_EXIT}"
  echo "  Output: $T3_OUTPUT"
fi
# AC9 (S-070): Board-Flip landet im temporären, detached Worktree + Push
# nach origin — NICHT mehr lokal in $T3_WORK. Assertion daher gegen
# origin/main (statt der lokalen Datei).
T3_STATUS="$(git -C "$T3_WORK" show origin/main:board/stories/S-900-test.yaml 2>/dev/null | grep '^status:' || true)"
T3_BRANCH="$(git -C "$T3_WORK" show origin/main:board/stories/S-900-test.yaml 2>/dev/null | grep '^branch:' || true)"
if [[ "$T3_STATUS" == "status: Done" ]]; then
  pass "Test 3b: Board auf Done geflippt (im origin/main-Stand)"
else
  fail "Test 3b: Board-Status in origin/main ist '${T3_STATUS}', erwartet 'status: Done'"
fi
if [[ "$T3_BRANCH" == "branch: feat/S-900-test" ]]; then
  pass "Test 3c: branch-Feld korrekt gesetzt (im origin/main-Stand)"
else
  fail "Test 3c: branch-Feld in origin/main ist '${T3_BRANCH}'"
fi
T3_ORIGIN_LOG="$(git -C "$T3_WORK" log origin/main --oneline | grep -c "feature work" || true)"
if [[ "$T3_ORIGIN_LOG" -ge 1 ]]; then
  pass "Test 3d: Story-Commit ist tatsächlich auf origin/main gelandet"
else
  fail "Test 3d: Story-Commit fehlt auf origin/main"
fi
# AC7 (S-070): der aufrufende Worktree bleibt unverändert auf dem
# Story-Branch — kein Checkout des Ziel-Branches, kein lokaler Board-Flip.
T3_LOCAL_BRANCH_AFTER="$(git -C "$T3_WORK" rev-parse --abbrev-ref HEAD)"
if [[ "$T3_LOCAL_BRANCH_AFTER" == "feat/S-900-test" ]]; then
  pass "Test 3e: aufrufender Worktree steht nach dem Lauf unverändert auf dem Story-Branch (AC7)"
else
  fail "Test 3e: aufrufender Worktree steht auf '${T3_LOCAL_BRANCH_AFTER}', erwartet unverändert 'feat/S-900-test'"
fi
T3_LOCAL_STATUS_FILE="$(grep '^status:' "$T3_WORK/board/stories/S-900-test.yaml" | head -1)"
if [[ "$T3_LOCAL_STATUS_FILE" == "status: In Review" ]]; then
  pass "Test 3f: lokale Board-Datei im Story-Worktree unverändert — Flip geschah im detached Worktree, nicht lokal (AC9)"
else
  fail "Test 3f: lokale Board-Datei im Story-Worktree wurde verändert ('${T3_LOCAL_STATUS_FILE}') — Flip hätte nicht lokal stattfinden dürfen"
fi

# ===========================================================================
# Test 4 — CI-Fehlschlag verhindert Board-Flip (kein Rollout auf rotem CI)
# ===========================================================================
echo ""
echo "--- Test 4: CI-Fehlschlag -> kein Board-Flip, Story bleibt NICHT Done ---"
T4_WORK="$(setup_fixture "${TEST_WORK_DIR}/test4")"
(
  cd "$T4_WORK"
  git checkout -q -b feat/S-900-test
  echo "feature" > feature.txt
  git add -A
  git commit -q -m "S-900: feature work"
)
export MOCK_CI_STATUS="completed" MOCK_CI_CONCLUSION="failure"
set +e
T4_OUTPUT="$(cd "$T4_WORK" && MOCK_HEAD_SHA="$(git rev-parse HEAD)" bash "$SHIP_SCRIPT" S-900 2>&1)"
T4_EXIT=$?
set -e

if [[ $T4_EXIT -ne 0 ]] && echo "$T4_OUTPUT" | grep -q "CI nicht erfolgreich"; then
  pass "Test 4a: CI-Fehlschlag korrekt erkannt und gemeldet"
else
  fail "Test 4a: CI-Fehlschlag nicht erkannt (exit=${T4_EXIT})"
  echo "  Output: $T4_OUTPUT"
fi
T4_STATUS="$(grep '^status:' "$T4_WORK/board/stories/S-900-test.yaml" | head -1)"
if [[ "$T4_STATUS" == "status: In Review" ]]; then
  pass "Test 4b: Board-Status unverändert (kein Flip auf Done bei rotem CI)"
else
  fail "Test 4b: Board-Status ist '${T4_STATUS}', erwartet unverändert 'status: In Review'"
fi

# ===========================================================================
# Test 5 — Idempotenz: zweiter Aufruf nach erfolgreichem Ship ist ein No-Op
# ===========================================================================
echo ""
echo "--- Test 5: zweiter Ship-Aufruf nach erfolgreichem Ship ist idempotent ---"
export MOCK_CI_STATUS="completed" MOCK_CI_CONCLUSION="success"
git -C "$T3_WORK" checkout -q feat/S-900-test   # No-Op seit AC7 (S-070): Test 3 endet bereits auf dem Story-Branch, kein Checkout des Ziel-Branches mehr
set +e
T5_OUTPUT="$(cd "$T3_WORK" && MOCK_HEAD_SHA="$(git rev-parse origin/main)" bash "$SHIP_SCRIPT" S-900 2>&1)"
T5_EXIT=$?
set -e
if [[ $T5_EXIT -eq 0 ]] && echo "$T5_OUTPUT" | grep -q "bereits gemergt"; then
  pass "Test 5: wiederholter Aufruf erkennt 'bereits gemergt', kein Fehler, kein Doppel-Merge"
else
  fail "Test 5: wiederholter Aufruf nicht idempotent (exit=${T5_EXIT})"
  echo "  Output: $T5_OUTPUT"
fi

# ===========================================================================
# Test 6 — Modus B: --target-branch — Story landet im Feature-Branch, main
# bleibt unberührt, kein Rollout (Owner-Konzept 2026-07-06, Feature-Batching)
# ===========================================================================
echo ""
echo "--- Test 6: --target-branch — Story landet im Feature-Branch, main unberührt, kein Rollout ---"
T6_WORK="$(setup_fixture "${TEST_WORK_DIR}/test6")"
(
  cd "$T6_WORK"
  git checkout -q -b feat/S-900-test
  echo "feature" > feature.txt
  git add -A
  git commit -q -m "S-900: feature work"
)
export MOCK_CI_STATUS="completed" MOCK_CI_CONCLUSION="success"
T6_MAIN_BEFORE="$(git -C "$T6_WORK" rev-parse origin/main)"
set +e
T6_OUTPUT="$(cd "$T6_WORK" && MOCK_HEAD_SHA="$(git rev-parse HEAD)" bash "$SHIP_SCRIPT" S-900 --target-branch "feature/F-900" 2>&1)"
T6_EXIT=$?
set -e

if [[ $T6_EXIT -eq 0 ]]; then
  pass "Test 6a: Ship in Feature-Branch läuft ohne Fehler durch"
else
  fail "Test 6a: exit=${T6_EXIT}"
  echo "  Output: $T6_OUTPUT"
fi
T6_MAIN_AFTER="$(git -C "$T6_WORK" rev-parse origin/main)"
if [[ "$T6_MAIN_BEFORE" == "$T6_MAIN_AFTER" ]]; then
  pass "Test 6b: origin/main unverändert — Story landete NICHT direkt in main"
else
  fail "Test 6b: origin/main hat sich verändert, obwohl Ziel der Feature-Branch war"
fi
T6_FEATURE_LOG="$(git -C "$T6_WORK" log "origin/feature/F-900" --oneline 2>/dev/null | grep -c "feature work" || true)"
if [[ "$T6_FEATURE_LOG" -ge 1 ]]; then
  pass "Test 6c: Story-Commit ist tatsächlich in origin/feature/F-900 gelandet"
else
  fail "Test 6c: Story-Commit fehlt im Feature-Branch"
fi
T6_STATUS="$(git -C "$T6_WORK" show "origin/feature/F-900:board/stories/S-900-test.yaml" | grep '^status:')"
if [[ "$T6_STATUS" == "status: Done" ]]; then
  pass "Test 6d: Board-Flip auf Done ist im Feature-Branch committet"
else
  fail "Test 6d: Board-Status im Feature-Branch ist '${T6_STATUS}'"
fi

# ===========================================================================
# Test 7 — Modus C: --merge-feature — kompletter Feature-Branch nach main,
# CI-Watch + Rollout, idempotent bei wiederholtem Aufruf
# ===========================================================================
echo ""
echo "--- Test 7: --merge-feature — Feature-Branch komplett nach main, idempotent ---"
export MOCK_CI_STATUS="completed" MOCK_CI_CONCLUSION="success"
T7_MAIN_HEAD_BEFORE="$(git -C "$T6_WORK" rev-parse origin/main)"
T7_OUTPUT="$(cd "$T6_WORK" && MOCK_HEAD_SHA="AUTO" bash "$SHIP_SCRIPT" --merge-feature "feature/F-900" 2>&1)"
T7_EXIT=$?

if [[ $T7_EXIT -eq 0 ]]; then
  pass "Test 7a: --merge-feature läuft ohne Fehler durch"
else
  fail "Test 7a: exit=${T7_EXIT}"
  echo "  Output: $T7_OUTPUT"
fi
T7_MAIN_HEAD_AFTER="$(git -C "$T6_WORK" rev-parse origin/main)"
if [[ "$T7_MAIN_HEAD_AFTER" != "$T7_MAIN_HEAD_BEFORE" ]]; then
  pass "Test 7b: origin/main hat einen neuen Commit (der Feature-Merge)"
else
  fail "Test 7b: origin/main unverändert — Merge hat nicht stattgefunden"
fi
T7_MAIN_HAS_STORY="$(git -C "$T6_WORK" log origin/main --oneline | grep -c "feature work" || true)"
if [[ "$T7_MAIN_HAS_STORY" -ge 1 ]]; then
  pass "Test 7c: Story-Commit aus dem Feature-Branch ist jetzt in main enthalten"
else
  fail "Test 7c: Story-Commit fehlt in main nach dem Feature-Merge"
fi

# Idempotenz: zweiter Aufruf, Feature-Branch ist jetzt bereits in main enthalten
T7B_OUTPUT="$(cd "$T6_WORK" && MOCK_HEAD_SHA="AUTO" bash "$SHIP_SCRIPT" --merge-feature "feature/F-900" 2>&1)"
T7B_EXIT=$?
if [[ $T7B_EXIT -eq 0 ]] && echo "$T7B_OUTPUT" | grep -q "bereits vollständig"; then
  pass "Test 7d: wiederholter --merge-feature-Aufruf erkennt 'bereits enthalten', kein Doppel-Merge"
else
  fail "Test 7d: wiederholter Aufruf nicht idempotent (exit=${T7B_EXIT})"
  echo "  Output: $T7B_OUTPUT"
fi

# ===========================================================================
# Test 8 — Regression 2026-07-06 (Owner-Testlauf F-065): profile.md OHNE
# default_branch-Feld (echte dev-gui-Form, kein YAML-Frontmatter) darf das
# Skript NICHT wortlos abbrechen (set -e + pipefail auf grep-ohne-Treffer) —
# der ":-main"-Fallback muss tatsächlich greifen.
# ===========================================================================
echo ""
echo "--- Test 8: profile.md ohne default_branch-Feld -> Fallback auf 'main' greift, kein stiller Abbruch ---"
T8_WORK="$(setup_fixture "${TEST_WORK_DIR}/test8")"
cat > "${T8_WORK}/.claude/profile.md" <<'PLAIN'
language: js
merge_policy: direct
deploy: none
PLAIN
(
  cd "$T8_WORK"
  git add -A && git commit -q -m "profile.md ohne default_branch (Regressionsfixture)"
  git push -q origin main
  git checkout -q -b feat/S-900-test
  echo "feature" > feature.txt
  git add -A
  git commit -q -m "S-900: feature work"
)
export MOCK_CI_STATUS="completed" MOCK_CI_CONCLUSION="success"
T8_OUTPUT="$(cd "$T8_WORK" && MOCK_HEAD_SHA="$(git rev-parse HEAD)" bash "$SHIP_SCRIPT" S-900 2>&1)"
T8_EXIT=$?
if [[ $T8_EXIT -eq 0 ]]; then
  pass "Test 8: kein stiller Abbruch trotz fehlendem default_branch-Feld — Fallback auf 'main' griff"
else
  fail "Test 8: Skript brach ab (exit=${T8_EXIT}) statt auf 'main' zurückzufallen"
  echo "  Output: $T8_OUTPUT"
fi

# ===========================================================================
# Test 9 — AC1-AC6 v2 (board-ship-environment-guards, Ansatzwechsel
# 2026-07-17): CI-Trigger-Feststellung EMPIRISCH (nachsehen, ob ein Run mit
# der eigenen SHA erscheint) statt aus .github/workflows/* hergeleitet. Die
# YAML-Anker-/Alias-Regressionsfixtures des verworfenen Parser-Ansatzes
# (vormals Test 10) entfallen ersatzlos — sie sicherten eine Lösung ab, die
# es nicht mehr gibt (v2-Spec, AC6-Traceability-Hinweis).
#   (a) Skip auf Feature-Branch: kein Run mit eigener SHA -> Exit 0, Skip-
#       Logzeile, Board im Feature-Branch auf Done (AC1, AC6a).
#   (b) main bleibt scharf bei rotem CI: Run mit eigener SHA, conclusion=
#       failure -> die, kein Flip (AC2, AC6b).
#   (c) main bleibt scharf OHNE Run: kein Run mit eigener SHA -> KEIN Skip
#       (default_branch), Timeout-die, kein Flip (AC2/E2, AC6c).
#   (d) Race-Schutz: Run mit FREMDER headSha + conclusion=failure -> weder
#       als eigener Run ausgewertet noch als "kein Run" verbucht, auf main
#       folgt der Timeout-die, kein Flip (AC3, AC6d).
# BOARD_SHIP_CI_GRACE_SECS wird klein gesetzt (Spec-Vorgabe AC6-Präambel);
# `sleep` ist zusätzlich global gemockt (No-Op) — betrifft nur die Test-
# Laufzeit, board-ship.sh bleibt bei den zwei dokumentierten Env-Variablen.
# ===========================================================================
echo ""
echo "--- Test 9: AC1-AC6 v2 — empirische CI-Trigger-Feststellung (Beobachtungsfenster) ---"

export BOARD_SHIP_CI_GRACE_SECS=3
unset MOCK_HEAD_SHA

# --- (a) Skip auf Feature-Branch: kein Run mit eigener SHA ---
T9A_WORK="$(setup_fixture "${TEST_WORK_DIR}/test9a")"
(
  cd "$T9A_WORK"
  git checkout -q -b feat/S-900-test
  echo "feature" > feature.txt
  git add -A
  git commit -q -m "S-900: feature work"
)
T9A_START=$(date +%s)
T9A_OUTPUT="$(cd "$T9A_WORK" && MOCK_HEAD_SHA="" bash "$SHIP_SCRIPT" S-900 --target-branch "feature/F-900" 2>&1)"
T9A_EXIT=$?
T9A_END=$(date +%s)
T9A_DURATION=$((T9A_END - T9A_START))

if [[ $T9A_EXIT -eq 0 ]]; then
  pass "Test 9a-1: Ship auf Feature-Branch ohne eigenen Run läuft durch (exit 0)"
else
  fail "Test 9a-1: exit=${T9A_EXIT}"
  echo "  Output: $T9A_OUTPUT"
fi
if echo "$T9A_OUTPUT" | grep -q "kein CI-Run für .* innerhalb .*s erschienen"; then
  pass "Test 9a-2: Skip-Logzeile vorhanden (Beobachtungsfenster abgelaufen, kein Treffer)"
else
  fail "Test 9a-2: Skip-Logzeile fehlt"
  echo "  Output: $T9A_OUTPUT"
fi
if [[ "$T9A_DURATION" -lt 30 ]]; then
  pass "Test 9a-3: kein 40x15s-Timeout — Laufzeit ${T9A_DURATION}s (<30s)"
else
  fail "Test 9a-3: Laufzeit ${T9A_DURATION}s — Warteschleife wurde offenbar nicht übersprungen"
fi
T9A_STATUS="$(git -C "$T9A_WORK" show "origin/feature/F-900:board/stories/S-900-test.yaml" 2>/dev/null | grep '^status:' || true)"
if [[ "$T9A_STATUS" == "status: Done" ]]; then
  pass "Test 9a-4: Board im Feature-Branch auf Done (Skip blockiert Board-Flip nicht)"
else
  fail "Test 9a-4: Board-Status im Feature-Branch ist '${T9A_STATUS}'"
fi

# --- (b) main bleibt scharf bei rotem CI (eigener Run vorhanden) ---
T9B_WORK="$(setup_fixture "${TEST_WORK_DIR}/test9b")"
(
  cd "$T9B_WORK"
  git checkout -q -b feat/S-900-test
  echo "feature" > feature.txt
  git add -A
  git commit -q -m "S-900: feature work"
)
export MOCK_CI_STATUS="completed" MOCK_CI_CONCLUSION="failure"
set +e
T9B_OUTPUT="$(cd "$T9B_WORK" && MOCK_HEAD_SHA="$(git rev-parse HEAD)" bash "$SHIP_SCRIPT" S-900 2>&1)"
T9B_EXIT=$?
set -e
if [[ $T9B_EXIT -ne 0 ]] && echo "$T9B_OUTPUT" | grep -q "CI nicht erfolgreich"; then
  pass "Test 9b: main bleibt scharf — roter CI (eigener Run) wird erkannt, Skript stirbt (AC2)"
else
  fail "Test 9b: main-CI-Fehlschlag nicht erkannt (exit=${T9B_EXIT})"
  echo "  Output: $T9B_OUTPUT"
fi
T9B_STATUS="$(grep '^status:' "$T9B_WORK/board/stories/S-900-test.yaml" | head -1)"
if [[ "$T9B_STATUS" == "status: In Review" ]]; then
  pass "Test 9b-2: Board-Status unverändert bei rotem CI auf main (kein Flip)"
else
  fail "Test 9b-2: Board-Status ist '${T9B_STATUS}', erwartet unverändert 'status: In Review'"
fi

# --- (c) main bleibt scharf OHNE Run — KEIN Skip, Timeout-die (AC2/E2) ---
T9C_WORK="$(setup_fixture "${TEST_WORK_DIR}/test9c")"
(
  cd "$T9C_WORK"
  git checkout -q -b feat/S-900-test
  echo "feature" > feature.txt
  git add -A
  git commit -q -m "S-900: feature work"
)
export MOCK_CI_STATUS="completed" MOCK_CI_CONCLUSION="success"
set +e
T9C_OUTPUT="$(cd "$T9C_WORK" && MOCK_HEAD_SHA="" bash "$SHIP_SCRIPT" S-900 2>&1)"
T9C_EXIT=$?
set -e
if [[ $T9C_EXIT -ne 0 ]] && echo "$T9C_OUTPUT" | grep -q "CI nicht erfolgreich" && echo "$T9C_OUTPUT" | grep -q "timeout/unbekannt"; then
  pass "Test 9c: main bleibt scharf OHNE Run — kein Skip, Timeout-die (AC2/E2)"
else
  fail "Test 9c: main wurde trotz fehlendem Run übersprungen oder falsch behandelt (exit=${T9C_EXIT})"
  echo "  Output: $T9C_OUTPUT"
fi
if echo "$T9C_OUTPUT" | grep -q "kein CI-Run für .* innerhalb .*s erschienen"; then
  fail "Test 9c-2: main hat fälschlich die Skip-Logzeile des Beobachtungsfensters ausgegeben — default_branch darf NIE überspringen"
else
  pass "Test 9c-2: keine Skip-Logzeile auf main — Beobachtungsfenster wird auf default_branch nicht angewendet"
fi
T9C_STATUS="$(grep '^status:' "$T9C_WORK/board/stories/S-900-test.yaml" | head -1)"
if [[ "$T9C_STATUS" == "status: In Review" ]]; then
  pass "Test 9c-3: Board-Status unverändert (kein Flip trotz fehlendem Run auf main)"
else
  fail "Test 9c-3: Board-Status ist '${T9C_STATUS}', erwartet unverändert 'status: In Review'"
fi

# --- (d) Race-Schutz: fremde headSha + conclusion=failure -> weder eigener
#         Run noch "kein Run", auf main folgt Timeout-die (AC3) ---
T9D_WORK="$(setup_fixture "${TEST_WORK_DIR}/test9d")"
(
  cd "$T9D_WORK"
  git checkout -q -b feat/S-900-test
  echo "feature" > feature.txt
  git add -A
  git commit -q -m "S-900: feature work"
)
export MOCK_CI_STATUS="completed" MOCK_CI_CONCLUSION="failure"
set +e
T9D_OUTPUT="$(cd "$T9D_WORK" && MOCK_HEAD_SHA="0000000000000000000000000000000000dead" bash "$SHIP_SCRIPT" S-900 2>&1)"
T9D_EXIT=$?
set -e
if [[ $T9D_EXIT -ne 0 ]] && echo "$T9D_OUTPUT" | grep -q "CI nicht erfolgreich" && echo "$T9D_OUTPUT" | grep -q "timeout/unbekannt"; then
  pass "Test 9d: fremde headSha wird weder als eigener Run noch als 'kein Run' verbucht — Timeout-die auf main (AC3)"
else
  fail "Test 9d: fremde headSha wurde falsch behandelt (exit=${T9D_EXIT})"
  echo "  Output: $T9D_OUTPUT"
fi
T9D_STATUS="$(grep '^status:' "$T9D_WORK/board/stories/S-900-test.yaml" | head -1)"
if [[ "$T9D_STATUS" == "status: In Review" ]]; then
  pass "Test 9d-2: Board-Status unverändert (kein Flip)"
else
  fail "Test 9d-2: Board-Status ist '${T9D_STATUS}', erwartet unverändert 'status: In Review'"
fi

# --- (e) Grace-Window-Race auf einem NICHT-default_branch (Review-Fund
#         Iteration 4): Test 9d lief nur auf 'main' und traf damit den alten
#         Scharf-Loop, nicht die neue Grace-Schleife. Hier: persistierende
#         FREMDE headSha über mehrere Fenster-Iterationen (Grace=12s,
#         Poll=5s -> 3 Abfragen) auf feature/F-900 — die eigene SHA erscheint
#         nie. Belegt: eine fremde headSha wird weder als eigener Run
#         gewertet noch beendet das Fenster vorzeitig; nach vollständigem
#         Ablauf wird korrekt geskippt (Board Done) (AC1/AC3). ---
T9E_WORK="$(setup_fixture "${TEST_WORK_DIR}/test9e")"
(
  cd "$T9E_WORK"
  git checkout -q -b feat/S-900-test
  echo "feature" > feature.txt
  git add -A
  git commit -q -m "S-900: feature work"
)
T9E_OUTPUT="$(cd "$T9E_WORK" && BOARD_SHIP_CI_GRACE_SECS=12 MOCK_HEAD_SHA="0000000000000000000000000000000000dead" bash "$SHIP_SCRIPT" S-900 --target-branch "feature/F-900" 2>&1)"
T9E_EXIT=$?
if [[ $T9E_EXIT -eq 0 ]]; then
  pass "Test 9e-1: Grace-Window mit persistierender fremder headSha läuft vollständig durch, dann Skip (exit 0)"
else
  fail "Test 9e-1: exit=${T9E_EXIT}"
  echo "  Output: $T9E_OUTPUT"
fi
if echo "$T9E_OUTPUT" | grep -q "kein CI-Run für .* innerhalb .*s erschienen"; then
  pass "Test 9e-2: Skip-Logzeile nach vollständig durchlaufenem Fenster vorhanden"
else
  fail "Test 9e-2: Skip-Logzeile fehlt"
  echo "  Output: $T9E_OUTPUT"
fi
if echo "$T9E_OUTPUT" | grep -q "nicht durchgehend fehlerfrei"; then
  fail "Test 9e-3: fremde headSha wurde fälschlich als Query-Fehler gewertet (had_query_failure) statt nur ignoriert"
else
  pass "Test 9e-3: fremde headSha wurde NICHT als Query-Fehler gewertet — Fenster lief regulär zu Ende"
fi
T9E_STATUS="$(git -C "$T9E_WORK" show "origin/feature/F-900:board/stories/S-900-test.yaml" 2>/dev/null | grep '^status:' || true)"
if [[ "$T9E_STATUS" == "status: Done" ]]; then
  pass "Test 9e-4: Board im Feature-Branch auf Done (fremde headSha blockiert Skip/Board-Flip nicht)"
else
  fail "Test 9e-4: Board-Status im Feature-Branch ist '${T9E_STATUS}'"
fi

# --- (f) gh-Störung im Beobachtungsfenster eskaliert scharf statt zu
#         skippen (Review-Fund Iteration 4, coder/L03: MOCK_GH_RUN_LIST_FAIL
#         existierte als Seam, wurde aber von keinem Test aktiviert).
#         Nicht-default_branch, MOCK_GH_RUN_LIST_FAIL=1 -> jede
#         gh-Abfrage im Fenster schlägt fehl -> NIE als "kein Run"/Skip
#         werten (AC3, K1) -> klassischer Scharf-Watch übernimmt, der
#         (mit ebenfalls fehlschlagenden Abfragen) regulär in den
#         Timeout-die läuft, kein Flip. ---
T9F_WORK="$(setup_fixture "${TEST_WORK_DIR}/test9f")"
(
  cd "$T9F_WORK"
  git checkout -q -b feat/S-900-test
  echo "feature" > feature.txt
  git add -A
  git commit -q -m "S-900: feature work"
)
set +e
T9F_OUTPUT="$(cd "$T9F_WORK" && MOCK_GH_RUN_LIST_FAIL=1 bash "$SHIP_SCRIPT" S-900 --target-branch "feature/F-900" 2>&1)"
T9F_EXIT=$?
set -e
if [[ $T9F_EXIT -ne 0 ]] && echo "$T9F_OUTPUT" | grep -q "nicht durchgehend fehlerfrei" && echo "$T9F_OUTPUT" | grep -q "CI nicht erfolgreich" && echo "$T9F_OUTPUT" | grep -q "timeout/unbekannt"; then
  pass "Test 9f: gh-Störung im Fenster eskaliert scharf statt zu skippen — Exit 1, kein Board-Flip (AC3, K1, coder/L03)"
else
  fail "Test 9f: gh-Störung wurde nicht korrekt eskaliert (exit=${T9F_EXIT})"
  echo "  Output: $T9F_OUTPUT"
fi
if echo "$T9F_OUTPUT" | grep -q "kein CI-Run für .* innerhalb .*s erschienen"; then
  fail "Test 9f-2: trotz gh-Störung wurde fälschlich die Skip-Logzeile ausgegeben"
else
  pass "Test 9f-2: keine Skip-Logzeile trotz gh-Störung — Eskalation griff wie vorgesehen"
fi
T9F_STATUS="$(grep '^status:' "$T9F_WORK/board/stories/S-900-test.yaml" | head -1)"
if [[ "$T9F_STATUS" == "status: In Review" ]]; then
  pass "Test 9f-3: Board-Status unverändert (kein Flip trotz Beobachtungsfenster)"
else
  fail "Test 9f-3: Board-Status ist '${T9F_STATUS}', erwartet unverändert 'status: In Review'"
fi

unset BOARD_SHIP_CI_GRACE_SECS
unset MOCK_HEAD_SHA

# ===========================================================================
# Test 11 — AC7-AC13 (board-ship-environment-guards, S-070): worktree-
# taugliches Landen. flow/L07 (dev-gui S-358): board-ship.sh Modus A machte
# 'git checkout <ship-branch>' im aufrufenden Worktree — hielt ein ZWEITER
# Worktree denselben Branch (der Normalfall bei CLAUDE.md-Worktree-Pflicht),
# starb das Skript an 'fatal: a branch named ... already exists', obwohl der
# Story-Commit längst gepusht war. Board blieb 'In Progress'.
#   (a) Zweiter Worktree hält 'main' — Ship aus dem Story-Worktree (Modus A,
#       merge_policy: direct) landet trotzdem: Exit 0, Story-Commit +
#       Board-Flip auf origin/main, zweiter Worktree unverändert (HEAD +
#       Working-Tree unberührt), kein Rest in 'git worktree list' (AC7-AC9,
#       AC13a).
#   (b) Non-FF-Fall: origin/main hat einen fremden Commit, der nicht im
#       Story-Branch enthalten ist -> Exit 1, Klartext-Diagnose, kein Push,
#       kein Force, origin/main unverändert, Board NICHT Done (AC8/E1,
#       AC13b).
# ===========================================================================
echo ""
echo "--- Test 11: AC7-AC13 — worktree-taugliches Landen (kein checkout des Ziel-Branches) ---"

# --- (a) Zweiter Worktree hält main; Ship aus Story-Worktree landet ---
T11A_WORK="$(setup_fixture "${TEST_WORK_DIR}/test11a")"
T11A_SECOND_WORKTREE="${TEST_WORK_DIR}/test11a/second-worktree"
(
  cd "$T11A_WORK"
  git checkout -q -b feat/S-900-test        # 'main' in $T11A_WORK freigeben
  git worktree add -q "$T11A_SECOND_WORKTREE" main
  echo "feature" > feature.txt
  git add -A
  git commit -q -m "S-900: feature work"
)
T11A_SECOND_HEAD_BEFORE="$(git -C "$T11A_SECOND_WORKTREE" rev-parse HEAD)"
T11A_SECOND_STATUS_BEFORE="$(git -C "$T11A_SECOND_WORKTREE" status --porcelain)"

export MOCK_CI_STATUS="completed" MOCK_CI_CONCLUSION="success"
T11A_OUTPUT="$(cd "$T11A_WORK" && MOCK_HEAD_SHA="$(git rev-parse HEAD)" bash "$SHIP_SCRIPT" S-900 2>&1)"
T11A_EXIT=$?

if [[ $T11A_EXIT -eq 0 ]]; then
  pass "Test 11a-1: Ship aus Story-Worktree landet trotz zweitem Worktree auf 'main' (exit 0, kein 'already exists')"
else
  fail "Test 11a-1: exit=${T11A_EXIT} — vermutlich 'fatal: a branch named ... already exists' (flow/L07-Regression)"
  echo "  Output: $T11A_OUTPUT"
fi
if echo "$T11A_OUTPUT" | grep -qi "already exists"; then
  fail "Test 11a-1b: Ausgabe enthält 'already exists' — Checkout-Konflikt trotzdem aufgetreten"
else
  pass "Test 11a-1b: keine 'already exists'-Fehlermeldung"
fi
T11A_ORIGIN_LOG="$(git -C "$T11A_WORK" log origin/main --oneline 2>/dev/null | grep -c "feature work" || true)"
if [[ "$T11A_ORIGIN_LOG" -ge 1 ]]; then
  pass "Test 11a-2: Story-Commit ist tatsächlich auf origin/main gelandet"
else
  fail "Test 11a-2: Story-Commit fehlt auf origin/main"
fi
T11A_STATUS="$(git -C "$T11A_WORK" show origin/main:board/stories/S-900-test.yaml 2>/dev/null | grep '^status:' || true)"
if [[ "$T11A_STATUS" == "status: Done" ]]; then
  pass "Test 11a-3: Board-Flip auf Done ist im origin/main-Stand enthalten"
else
  fail "Test 11a-3: Board-Status in origin/main ist '${T11A_STATUS}'"
fi
T11A_SECOND_HEAD_AFTER="$(git -C "$T11A_SECOND_WORKTREE" rev-parse HEAD)"
T11A_SECOND_STATUS_AFTER="$(git -C "$T11A_SECOND_WORKTREE" status --porcelain)"
if [[ "$T11A_SECOND_HEAD_AFTER" == "$T11A_SECOND_HEAD_BEFORE" ]]; then
  pass "Test 11a-4: zweiter Worktree (main) unverändert — HEAD identisch"
else
  fail "Test 11a-4: zweiter Worktree HEAD hat sich verändert (${T11A_SECOND_HEAD_BEFORE} -> ${T11A_SECOND_HEAD_AFTER})"
fi
if [[ "$T11A_SECOND_STATUS_AFTER" == "$T11A_SECOND_STATUS_BEFORE" ]]; then
  pass "Test 11a-5: zweiter Worktree Working-Tree unverändert (kein Datei-Diff)"
else
  fail "Test 11a-5: zweiter Worktree Working-Tree hat sich verändert"
fi
T11A_WORKTREE_LIST_LEAK="$(git -C "$T11A_WORK" worktree list | grep -c "board-ship-land" || true)"
if [[ "$T11A_WORKTREE_LIST_LEAK" -eq 0 ]]; then
  pass "Test 11a-6: kein verwaister temporärer Landing-Worktree in 'git worktree list' (AC9-Cleanup)"
else
  fail "Test 11a-6: verwaister temporärer Worktree gefunden"
  git -C "$T11A_WORK" worktree list
fi

# --- (b) Non-FF-Fall: origin/main hat einen fremden Commit -> Exit 1, kein Push, kein Flip ---
T11B_WORK="$(setup_fixture "${TEST_WORK_DIR}/test11b")"
(
  cd "$T11B_WORK"
  git checkout -q -b feat/S-900-test
  echo "feature" > feature.txt
  git add -A
  git commit -q -m "S-900: feature work"
)
# Fremder Commit landet auf origin/main, NACHDEM der Story-Branch abgezweigt
# wurde. Der bare "origin.git" hat kein aktualisiertes HEAD-Symref (git init
# --bare zeigt per Default auf 'master') — explizit auf 'main' auschecken
# statt uns auf den Default-Checkout beim Klonen zu verlassen.
T11B_FOREIGN_CLONE="${TEST_WORK_DIR}/test11b/foreign-clone"
git clone -q "${TEST_WORK_DIR}/test11b/origin.git" "$T11B_FOREIGN_CLONE" 2>/dev/null
(
  cd "$T11B_FOREIGN_CLONE"
  git checkout -q main
  echo "foreign" > foreign.txt
  git add -A
  git commit -q -m "fremder Commit — jemand anders war schneller"
  git push -q origin main
)
T11B_ORIGIN_MAIN_BEFORE="$(git -C "$T11B_WORK" ls-remote origin main | cut -f1)"

export MOCK_CI_STATUS="completed" MOCK_CI_CONCLUSION="success"
set +e
T11B_OUTPUT="$(cd "$T11B_WORK" && MOCK_HEAD_SHA="$(git rev-parse HEAD)" bash "$SHIP_SCRIPT" S-900 2>&1)"
T11B_EXIT=$?
set -e
if [[ $T11B_EXIT -ne 0 ]] && echo "$T11B_OUTPUT" | grep -qi "kein Fast-Forward"; then
  pass "Test 11b-1: Non-FF-Fall korrekt erkannt — sichtbarer Abbruch (Exit 1), Klartext-Diagnose (E1)"
else
  fail "Test 11b-1: Non-FF-Fall nicht korrekt behandelt (exit=${T11B_EXIT})"
  echo "  Output: $T11B_OUTPUT"
fi
T11B_ORIGIN_MAIN_AFTER="$(git -C "$T11B_WORK" ls-remote origin main | cut -f1)"
if [[ "$T11B_ORIGIN_MAIN_AFTER" == "$T11B_ORIGIN_MAIN_BEFORE" ]]; then
  pass "Test 11b-2: origin/main unverändert (kein Push, kein Force)"
else
  fail "Test 11b-2: origin/main hat sich verändert trotz Non-FF-Abbruch"
fi
T11B_STATUS="$(grep '^status:' "$T11B_WORK/board/stories/S-900-test.yaml" | head -1)"
if [[ "$T11B_STATUS" == "status: In Review" ]]; then
  pass "Test 11b-3: Board-Status unverändert (kein Flip)"
else
  fail "Test 11b-3: Board-Status ist '${T11B_STATUS}', erwartet unverändert 'status: In Review'"
fi

# ===========================================================================
# Test 12 — S-122 AC1/AC5(a): merge_policy=pr, 'main' in einem zweiten
# Worktree belegt. Merge erfolgt GitHub-seitig OHNE '--delete-branch' (kein
# lokaler Checkout/Branch-Wechsel) — der Mock simuliert den Remote-Merge
# (Ziel-Branch bekommt den Story-Commit). Exit 0, Story-Commit + Board-Flip
# auf origin/main, zweiter Worktree unverändert (@trace
# board-ship-pr-merge-worktree-safe#AC1, #AC5a).
# ===========================================================================
echo ""
echo "--- Test 12: AC1/AC5(a) — PR-Policy, 'main' im zweiten Worktree belegt, Remote-Merge ohne lokale Nebenwirkung ---"
T12_WORK="$(setup_fixture "${TEST_WORK_DIR}/test12")"
set_pr_policy "$T12_WORK"
T12_SECOND_WORKTREE="${TEST_WORK_DIR}/test12/second-worktree"
(
  cd "$T12_WORK"
  git checkout -q -b feat/S-900-test
  git worktree add -q "$T12_SECOND_WORKTREE" main
  echo "feature" > feature.txt
  git add -A
  git commit -q -m "S-900: feature work"
)
T12_SECOND_HEAD_BEFORE="$(git -C "$T12_SECOND_WORKTREE" rev-parse HEAD)"
T12_SECOND_STATUS_BEFORE="$(git -C "$T12_SECOND_WORKTREE" status --porcelain)"

export MOCK_CI_STATUS="completed" MOCK_CI_CONCLUSION="success"
export MOCK_GH_MERGE_SOURCE_BRANCH="feat/S-900-test" MOCK_GH_MERGE_TARGET_BRANCH="main"
T12_OUTPUT="$(cd "$T12_WORK" && MOCK_HEAD_SHA="AUTO" bash "$SHIP_SCRIPT" S-900 2>&1)"
T12_EXIT=$?
unset MOCK_GH_MERGE_SOURCE_BRANCH MOCK_GH_MERGE_TARGET_BRANCH

if [[ $T12_EXIT -eq 0 ]]; then
  pass "Test 12a: PR-Merge aus dem Story-Worktree landet trotz zweitem Worktree auf 'main' (exit 0)"
else
  fail "Test 12a: exit=${T12_EXIT}"
  echo "  Output: $T12_OUTPUT"
fi
T12_ORIGIN_LOG="$(git -C "$T12_WORK" log origin/main --oneline 2>/dev/null | grep -c "feature work" || true)"
if [[ "$T12_ORIGIN_LOG" -ge 1 ]]; then
  pass "Test 12b: Story-Commit ist tatsächlich auf origin/main gelandet"
else
  fail "Test 12b: Story-Commit fehlt auf origin/main"
fi
T12_STATUS="$(git -C "$T12_WORK" show origin/main:board/stories/S-900-test.yaml 2>/dev/null | grep '^status:' || true)"
if [[ "$T12_STATUS" == "status: Done" ]]; then
  pass "Test 12c: Board-Flip auf Done ist im origin/main-Stand enthalten (AC3 — Nacharbeit lief trotz belegtem 'main')"
else
  fail "Test 12c: Board-Status in origin/main ist '${T12_STATUS}'"
fi
T12_SECOND_HEAD_AFTER="$(git -C "$T12_SECOND_WORKTREE" rev-parse HEAD)"
T12_SECOND_STATUS_AFTER="$(git -C "$T12_SECOND_WORKTREE" status --porcelain)"
if [[ "$T12_SECOND_HEAD_AFTER" == "$T12_SECOND_HEAD_BEFORE" && "$T12_SECOND_STATUS_AFTER" == "$T12_SECOND_STATUS_BEFORE" ]]; then
  pass "Test 12d: zweiter Worktree (main) unverändert — HEAD + Working-Tree unberührt (AC1)"
else
  fail "Test 12d: zweiter Worktree wurde durch den PR-Merge verändert"
fi
T12_LOCAL_BRANCH_AFTER="$(git -C "$T12_WORK" rev-parse --abbrev-ref HEAD)"
if [[ "$T12_LOCAL_BRANCH_AFTER" == "feat/S-900-test" ]]; then
  pass "Test 12e: aufrufender Worktree steht nach dem PR-Merge unverändert auf dem Story-Branch (AC1)"
else
  fail "Test 12e: aufrufender Worktree steht auf '${T12_LOCAL_BRANCH_AFTER}', erwartet 'feat/S-900-test'"
fi

# ===========================================================================
# Test 13 — S-122 AC2(b)/AC5(b): Squash-Re-Run. Der Story-Commit ist NICHT
# Vorfahre von origin/main (Squash erzeugt einen neuen Commit) — der
# PR-Status (gh pr list --head <branch> --state all, MERGED) erkennt die
# Landung trotzdem. Exit 0, KEIN zweiter PR (MOCK_GH_PR_CREATE_FORBID würde
# das Skript sonst sterben lassen), Board-Flip läuft idempotent (deckt A2).
# ===========================================================================
echo ""
echo "--- Test 13: AC2(b)/AC5(b) — Squash-Re-Run, PR bereits MERGED, kein zweiter PR ---"
T13_WORK="$(setup_fixture "${TEST_WORK_DIR}/test13")"
set_pr_policy "$T13_WORK"
(
  cd "$T13_WORK"
  git checkout -q -b feat/S-900-test
  echo "feature" > feature.txt
  git add -A
  git commit -q -m "S-900: feature work"
)
# Simuliert einen bereits per Squash gelandeten PR: origin/main bekommt über
# einen unabhängigen Klon einen FREMDEN Commit (repräsentiert den
# Squash-Commit von GitHub) — der lokale Story-Commit ist danach KEIN
# Vorfahre mehr von origin/main, der merge-base-Check trifft also nicht.
T13_FOREIGN="${TEST_WORK_DIR}/test13/foreign-clone"
git clone -q "${TEST_WORK_DIR}/test13/origin.git" "$T13_FOREIGN" 2>/dev/null
(
  cd "$T13_FOREIGN"
  git checkout -q main
  echo "feature" > feature.txt
  git add -A
  git commit -q -m "S-900: feature work (squash, simuliert)"
  git push -q origin main
)
T13_SQUASH_SHA="$(git -C "$T13_FOREIGN" rev-parse HEAD)"

export MOCK_PR_LIST_STATE="MERGED" MOCK_GH_PR_CREATE_FORBID=1
export MOCK_CI_STATUS="completed" MOCK_CI_CONCLUSION="success"
T13_OUTPUT="$(cd "$T13_WORK" && MOCK_HEAD_SHA="$T13_SQUASH_SHA" bash "$SHIP_SCRIPT" S-900 2>&1)"
T13_EXIT=$?
unset MOCK_PR_LIST_STATE MOCK_GH_PR_CREATE_FORBID

if [[ $T13_EXIT -eq 0 ]] && echo "$T13_OUTPUT" | grep -q "squash-tauglicher PR-Status-Check"; then
  pass "Test 13a: Squash-Re-Run korrekt über PR-Status erkannt (kein merge-base-Treffer nötig)"
else
  fail "Test 13a: Squash-Re-Run nicht erkannt (exit=${T13_EXIT})"
  echo "  Output: $T13_OUTPUT"
fi
if echo "$T13_OUTPUT" | grep -qi "gh pr create haette hier NICHT aufgerufen werden"; then
  fail "Test 13b: ein zweiter PR wurde angelegt — Idempotenz verletzt"
else
  pass "Test 13b: kein zweiter PR angelegt (Idempotenz gewahrt, deckt A2)"
fi
T13_STATUS="$(git -C "$T13_WORK" show origin/main:board/stories/S-900-test.yaml 2>/dev/null | grep '^status:' || true)"
if [[ "$T13_STATUS" == "status: Done" ]]; then
  pass "Test 13c: Board-Flip lief trotzdem idempotent weiter (Done im origin/main-Stand)"
else
  fail "Test 13c: Board-Status in origin/main ist '${T13_STATUS}'"
fi

# ===========================================================================
# Test 14 — S-122 AC2(a)/AC5(c): Merge-Aufruf meldet nicht-null Exit (z.B.
# lokaler Aufräum-Schritt scheitert), Remote-PR-Zustand entscheidet.
#   (c1) 'gh pr view' liefert state=MERGED -> Exit 0, Board-Flip (deckt A1).
#   (c2) 'gh pr view' liefert NICHT MERGED -> Exit 1, kein Board-Flip (E1).
# ===========================================================================
echo ""
echo "--- Test 14: AC2(a)/AC5(c) — Merge-Exit != 0, Remote-PR-Zustand entscheidet ---"

# --- (c1) Remote-Zustand MERGED trotz Fehler-Exit -> Erfolg ---
T14A_WORK="$(setup_fixture "${TEST_WORK_DIR}/test14a")"
set_pr_policy "$T14A_WORK"
(
  cd "$T14A_WORK"
  git checkout -q -b feat/S-900-test
  echo "feature" > feature.txt
  git add -A
  git commit -q -m "S-900: feature work"
)
export MOCK_CI_STATUS="completed" MOCK_CI_CONCLUSION="success"
export MOCK_GH_PR_MERGE_EXIT=1 MOCK_PR_VIEW_STATE="MERGED"
export MOCK_GH_MERGE_SOURCE_BRANCH="feat/S-900-test" MOCK_GH_MERGE_TARGET_BRANCH="main"
T14A_OUTPUT="$(cd "$T14A_WORK" && MOCK_HEAD_SHA="AUTO" bash "$SHIP_SCRIPT" S-900 2>&1)"
T14A_EXIT=$?
unset MOCK_GH_PR_MERGE_EXIT MOCK_PR_VIEW_STATE MOCK_GH_MERGE_SOURCE_BRANCH MOCK_GH_MERGE_TARGET_BRANCH

if [[ $T14A_EXIT -eq 0 ]] && echo "$T14A_OUTPUT" | grep -q "werte als Erfolg"; then
  pass "Test 14a-1: nicht-null Merge-Exit, aber Remote-Zustand MERGED -> als Erfolg gewertet (A1, Defekt 2 geschlossen)"
else
  fail "Test 14a-1: exit=${T14A_EXIT}"
  echo "  Output: $T14A_OUTPUT"
fi
T14A_STATUS="$(git -C "$T14A_WORK" show origin/main:board/stories/S-900-test.yaml 2>/dev/null | grep '^status:' || true)"
if [[ "$T14A_STATUS" == "status: Done" ]]; then
  pass "Test 14a-2: Board-Flip fand trotz Merge-Exit != 0 statt (AC3 — Skript stirbt nie NACH Erfolg)"
else
  fail "Test 14a-2: Board-Status in origin/main ist '${T14A_STATUS}'"
fi

# --- (c2) Remote-Zustand NICHT MERGED -> echter Fehlschlag, Exit 1, kein Flip ---
T14B_WORK="$(setup_fixture "${TEST_WORK_DIR}/test14b")"
set_pr_policy "$T14B_WORK"
(
  cd "$T14B_WORK"
  git checkout -q -b feat/S-900-test
  echo "feature" > feature.txt
  git add -A
  git commit -q -m "S-900: feature work"
)
export MOCK_CI_STATUS="completed" MOCK_CI_CONCLUSION="success"
export MOCK_GH_PR_MERGE_EXIT=1 MOCK_PR_VIEW_STATE="OPEN"
set +e
T14B_OUTPUT="$(cd "$T14B_WORK" && MOCK_HEAD_SHA="$(git rev-parse HEAD)" bash "$SHIP_SCRIPT" S-900 2>&1)"
T14B_EXIT=$?
set -e
unset MOCK_GH_PR_MERGE_EXIT MOCK_PR_VIEW_STATE

if [[ $T14B_EXIT -ne 0 ]] && echo "$T14B_OUTPUT" | grep -q "echter Fehlschlag"; then
  pass "Test 14b-1: Remote-Zustand NICHT MERGED -> echter Fehlschlag erkannt, Exit 1 (E1)"
else
  fail "Test 14b-1: exit=${T14B_EXIT}"
  echo "  Output: $T14B_OUTPUT"
fi
T14B_STATUS="$(grep '^status:' "$T14B_WORK/board/stories/S-900-test.yaml" | head -1)"
if [[ "$T14B_STATUS" == "status: In Review" ]]; then
  pass "Test 14b-2: Board-Status unverändert (kein Flip nach echtem Fehlschlag)"
else
  fail "Test 14b-2: Board-Status ist '${T14B_STATUS}', erwartet unverändert 'status: In Review'"
fi

# --- (c3) 'gh pr view' selbst gescheitert (E2, K1 fail-safe) -> Exit 1, kein Flip ---
T14C_WORK="$(setup_fixture "${TEST_WORK_DIR}/test14c")"
set_pr_policy "$T14C_WORK"
(
  cd "$T14C_WORK"
  git checkout -q -b feat/S-900-test
  echo "feature" > feature.txt
  git add -A
  git commit -q -m "S-900: feature work"
)
export MOCK_CI_STATUS="completed" MOCK_CI_CONCLUSION="success"
export MOCK_GH_PR_MERGE_EXIT=1 MOCK_GH_PR_VIEW_FAIL=1
set +e
T14C_OUTPUT="$(cd "$T14C_WORK" && MOCK_HEAD_SHA="$(git rev-parse HEAD)" bash "$SHIP_SCRIPT" S-900 2>&1)"
T14C_EXIT=$?
set -e
unset MOCK_GH_PR_MERGE_EXIT MOCK_GH_PR_VIEW_FAIL

if [[ $T14C_EXIT -ne 0 ]] && echo "$T14C_OUTPUT" | grep -q "fail-safe"; then
  pass "Test 14c-1: 'gh pr view' selbst gescheitert -> fail-safe Abbruch statt Erfolg angenommen (E2, K1)"
else
  fail "Test 14c-1: exit=${T14C_EXIT}"
  echo "  Output: $T14C_OUTPUT"
fi
T14C_STATUS="$(grep '^status:' "$T14C_WORK/board/stories/S-900-test.yaml" | head -1)"
if [[ "$T14C_STATUS" == "status: In Review" ]]; then
  pass "Test 14c-2: Board-Status unverändert (kein Flip bei unklarem Remote-Zustand)"
else
  fail "Test 14c-2: Board-Status ist '${T14C_STATUS}', erwartet unverändert 'status: In Review'"
fi

# ===========================================================================
# Test 15 — S-122 AC4: Remote-Branch-Löschung via API, nicht-fatal bei
# Fehlschlag (Board-Flip findet trotzdem statt).
# ===========================================================================
echo ""
echo "--- Test 15: AC4 — Remote-Branch-Löschung nicht-fatal bei Fehlschlag ---"
T15_WORK="$(setup_fixture "${TEST_WORK_DIR}/test15")"
set_pr_policy "$T15_WORK"
(
  cd "$T15_WORK"
  git checkout -q -b feat/S-900-test
  echo "feature" > feature.txt
  git add -A
  git commit -q -m "S-900: feature work"
)
export MOCK_CI_STATUS="completed" MOCK_CI_CONCLUSION="success"
export MOCK_GH_API_DELETE_FAIL=1
export MOCK_GH_MERGE_SOURCE_BRANCH="feat/S-900-test" MOCK_GH_MERGE_TARGET_BRANCH="main"
T15_OUTPUT="$(cd "$T15_WORK" && MOCK_HEAD_SHA="AUTO" bash "$SHIP_SCRIPT" S-900 2>&1)"
T15_EXIT=$?
unset MOCK_GH_API_DELETE_FAIL MOCK_GH_MERGE_SOURCE_BRANCH MOCK_GH_MERGE_TARGET_BRANCH

if [[ $T15_EXIT -eq 0 ]] && echo "$T15_OUTPUT" | grep -q "nicht-fatal"; then
  pass "Test 15a: Branch-Löschung fehlgeschlagen, aber Lauf bricht NICHT ab (Exit 0, AC4)"
else
  fail "Test 15a: exit=${T15_EXIT}"
  echo "  Output: $T15_OUTPUT"
fi
T15_STATUS="$(git -C "$T15_WORK" show origin/main:board/stories/S-900-test.yaml 2>/dev/null | grep '^status:' || true)"
if [[ "$T15_STATUS" == "status: Done" ]]; then
  pass "Test 15b: Board-Flip fand trotz gescheiterter Branch-Löschung statt"
else
  fail "Test 15b: Board-Status in origin/main ist '${T15_STATUS}'"
fi

# ===========================================================================
# Test 16 — S-122 AC1/Verträge: kein Pfad führt 'gh pr merge ... --delete-branch'
# mehr aus (statischer Beleg, keine Behauptung).
# ===========================================================================
echo ""
echo "--- Test 16: AC1 — kein '--delete-branch' mehr im Skript ---"
# Nur ausführbare Zeilen zählen — die AC1-Begründungskommentare erwähnen
# '--delete-branch' bewusst (Kontext, warum das Flag entfernt wurde).
if grep -v '^[[:space:]]*#' "$SHIP_SCRIPT" | grep -q -- "--delete-branch"; then
  fail "Test 16: '--delete-branch' noch in einer ausführbaren Zeile gefunden — AC1 verletzt"
else
  pass "Test 16: '--delete-branch' nicht mehr in einer ausführbaren Zeile vorhanden"
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
