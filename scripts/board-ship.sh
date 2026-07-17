#!/usr/bin/env bash
# scripts/board-ship.sh <story-id> [<container-name>] [--target-branch <branch>]
# scripts/board-ship.sh --merge-feature <branch> [<container-name>]
#
# Deterministischer Ersatz für den cicd-Agenten-SHIP-Pfad (L3, Owner-Auftrag
# 2026-07-06 — Reaktion auf den S-047-Vorfall vom selben Tag).
#
# Vorfall, den dieses Script verhindert: Ein cicd-Agent behauptete "schon
# gelandet" (verwechselte den Story-Commit mit einem älteren Spec+Board-Commit),
# führte daraufhin `git pull` aus und löschte damit 9 fertige, ungecommittete
# Dateien unwiderruflich. Ein LLM-Agent trifft hier ein Urteil ("ist das schon
# gelandet?") — dieses Script ersetzt das Urteil durch eine mechanische Prüfung
# (`git merge-base --is-ancestor`) und bricht bei jeder Unklarheit ab, statt zu
# raten (K1: kein Bypass, kein Silent-Fix — Rest-Fälle eskalieren an den Owner/
# Orchestrator statt zum cicd-Agenten zurückzufallen).
#
# L6-Guard (Kern dieses Scripts): niemals git fetch+reset/pull auf einem
# Working-Tree mit uncommitteten Änderungen ausführen, ohne vorher explizit zu
# prüfen und abzubrechen. Dieses Script verlässt sich NIE auf eine Behauptung
# über den Merge-Status — es prüft immer den echten Zustand nach (guard_clean,
# merge-base-Check).
#
# Drei Modi (Owner-Konzept 2026-07-06 — Feature-Batch-Bündelung, board-feature-drain.sh):
#   A) board-ship.sh <story-id> [<container>]
#      Normalfall: Story landet in profile.default_branch (main). Voller
#      Pfad: Merge, CI-Watch, Rollout, Board-Flip. Unverändert seit L3.
#   B) board-ship.sh <story-id> [<container>] --target-branch <branch>
#      Story landet im übergebenen Branch (z.B. feature/F-042) statt main.
#      CI-Watch läuft (Sicherheit — Konflikte fallen sofort auf), Rollout
#      entfällt (Feature-Branch deployt nie einzeln), Board-Flip committet
#      in <branch>.
#   C) board-ship.sh --merge-feature <branch> [<container>]
#      Der finale, EINMALIGE Merge eines kompletten Feature-Branches nach
#      profile.default_branch — nach der letzten Story eines Features.
#      Merge (normal, nicht Squash — Einzel-Story-Commits bleiben sichtbar),
#      CI-Watch, Rollout. KEIN Board-Flip (alle Storys sind bereits einzeln
#      in Modus B geflippt worden — hier gibt es nichts mehr zu setzen).
#
# Vorbedingung Modus A/B: läuft im Story-Worktree, auf dem Story-Branch, HEAD
# ist der fertige, geprüfte (tester-PASS) Commit. Vom Orchestrator (/flow)
# NACH tester-PASS aufgerufen. Vorbedingung Modus C: <branch> existiert remote
# und enthält mindestens einen Commit, der nicht in profile.default_branch ist.
#
# Exit 0 = erfolgreich gelandet (oder bereits gelandet, verifiziert). Exit 1 =
# Abbruch mit klarer Fehlermeldung — Board bleibt unverändert, kein Rollout.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

BOARD_SCRIPT="${SCRIPT_DIR}/board"

log() { echo "[board-ship] $*"; }
die() { echo "FEHLER [board-ship]: $*" >&2; exit 1; }

# --- L6-Guard: niemals mit uncommitteten Änderungen destruktiv git-operieren ---
guard_clean_or_die() {
  local dirty
  dirty="$(git status --porcelain)"
  if [[ -n "$dirty" ]]; then
    die "Working-Tree hat uncommittete Änderungen — STOPP vor jedem git fetch/pull/reset.
Commit oder stash zuerst, dann erneut aufrufen. Betroffene Dateien:
${dirty}"
  fi
}

ensure_gh_auth() {
  [[ "${BOARD_SHIP_SKIP_GH_AUTH:-0}" == "1" ]] && return 0   # Test-Seam (tests/board-ship)
  local script
  script="$(ls -dt "${HOME}/.claude/plugins/cache/agent-flow/agent-flow"/*/ 2>/dev/null | head -1)scripts/ensure-gh-auth.sh"
  [[ -x "$script" ]] && "$script" >/dev/null 2>&1 || true
}

# --- Argumente parsen (drei Modi, s. Kopfkommentar) ---
MODE="ship"          # ship | merge-feature
STORY_ID=""
APP_NAME=""
TARGET_BRANCH=""
MERGE_FEATURE_BRANCH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --merge-feature) MODE="merge-feature"; shift; MERGE_FEATURE_BRANCH="${1:-}" ;;
    --target-branch) shift; TARGET_BRANCH="${1:-}" ;;
    *)
      if [[ -z "$STORY_ID" && "$MODE" == "ship" ]]; then STORY_ID="$1";
      elif [[ -z "$APP_NAME" ]]; then APP_NAME="$1";
      else die "unerwartetes Argument '$1'"; fi
      ;;
  esac
  shift
done

DEFAULT_BRANCH="$(grep -m1 '^default_branch:' .claude/profile.md 2>/dev/null | sed 's/default_branch: *//;s/"//g' || true)"
DEFAULT_BRANCH="${DEFAULT_BRANCH:-main}"

# ============================================================================
# Gemeinsame Bausteine (von Modus ship UND merge-feature genutzt)
# ============================================================================

# ---------------------------------------------------------------------------
# CI-Trigger-Feststellung: EMPIRISCH (nachsehen, ob ein Run erscheint) statt
# hergeleitet (board-ship-environment-guards v2, Owner-Entscheid 2026-07-17).
# v1 versuchte herzuleiten, ob ein Push nach <branch> triggert, indem es
# .github/workflows/* mit einem Eigenbau-Bash-Parser las. Zwei Review-
# Iterationen fanden je einen kritischen Fail-open-Fall (Anker auf
# 'branches:', dann auf 'on:' selbst — coder/L01, coder/L02): "Bash kann
# YAML nicht", jeder Flicken deckte nur den gemeldeten Fall, die Fehlerklasse
# blieb offen. v2 liest/parst .github/workflows/* in KEINER Form (kein
# grep/sed/awk, kein YAML-Parser) — die Trigger-Frage wird ausschließlich aus
# beobachteten `gh run list`-Ergebnissen beantwortet.
# ---------------------------------------------------------------------------

# Der unveränderte, klassische Scharf-Watch (v1-Verhalten, unverändert):
# wartet bis zu 40x15s auf 'completed' für die eigene SHA, dann 'die' bei
# conclusion != success. Wird für default_branch IMMER verwendet (AC2) sowie
# für Nicht-default_branch, sobald im Beobachtungsfenster ein eigener Run
# erschien oder die Fensterbeobachtung selbst unsicher war (AC3, K1).
watch_ci_scharf_loop() {
  local branch="$1" expect_sha="$2"
  local run_conclusion="" run_sha="" run_status=""
  for _ in $(seq 1 40); do
    run_sha="$(gh run list --branch "$branch" --limit 1 --json headSha --jq '.[0].headSha' 2>/dev/null || echo "")"
    run_status="$(gh run list --branch "$branch" --limit 1 --json status --jq '.[0].status' 2>/dev/null || echo "")"
    if [[ "$run_sha" == "$expect_sha" ]]; then
      if [[ "$run_status" == "completed" ]]; then
        run_conclusion="$(gh run list --branch "$branch" --limit 1 --json conclusion --jq '.[0].conclusion' 2>/dev/null || echo "")"
        break
      fi
    else
      ensure_gh_auth
    fi
    sleep 15
  done
  if [[ "$run_conclusion" != "success" ]]; then
    die "CI nicht erfolgreich für ${expect_sha} auf '${branch}' (conclusion='${run_conclusion:-timeout/unbekannt}') — KEIN Rollout. Manuell prüfen: gh run list --branch ${branch}"
  fi
  log "CI grün für ${expect_sha} auf '${branch}'."
}

# CI beobachten (cicd/F06: headSha-Race-Schutz) — bricht bei Fehlschlag ab.
# AC4: Repos ganz ohne Workflows -> sofortiger Skip, auch auf default_branch,
# ohne Wartezeit (API-Tatsache über das Repo, keine Herleitung aus
# Definitionen). AC2: auf default_branch NIE überspringen — dort immer der
# klassische Scharf-Watch, unabhängig vom Beobachtungsfenster. Auf jedem
# anderen Branch: bis zu <grace> Sekunden (AC5, BOARD_SHIP_CI_GRACE_SECS,
# Default 90) empirisch beobachten, ob ein Run für die EIGENE SHA erscheint
# (AC1, Zuordnung ausschließlich über headSha-Vergleich). Erscheint einer ->
# klassischer Scharf-Watch. Bleibt das Fenster fehlerfrei ohne Treffer ->
# Skip (deckt A1). Trat im Fenster irgendeine fehlgeschlagene/leere
# gh-Abfrage auf -> NIE als "kein Trigger" werten (AC3, K1) -> ebenfalls
# klassischer Scharf-Watch.
watch_ci_or_die() {
  local branch="$1" expect_sha="$2"

  local workflow_count
  workflow_count="$(gh api "repos/$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)/actions/workflows" --jq '.total_count' 2>/dev/null || echo "")"
  if [[ "$workflow_count" == "0" ]]; then
    log "keine Actions-Workflows im Repo konfiguriert — CI-Watch entfällt strukturell für '${branch}'."
    return 0
  fi

  if [[ "$branch" == "$DEFAULT_BRANCH" ]]; then
    watch_ci_scharf_loop "$branch" "$expect_sha"
    return 0
  fi

  # Beobachtungsfenster nur auf Nicht-default_branch (AC1/AC2/AC3/AC5).
  local grace_secs="${BOARD_SHIP_CI_GRACE_SECS:-}"
  if ! [[ "$grace_secs" =~ ^[1-9][0-9]*$ ]]; then
    grace_secs=90   # fehlend/nicht-numerisch/negativ/0 -> Default (AC5: Fehlkonfiguration darf nie sofort skippen)
  fi
  local poll_interval=5
  [[ "$poll_interval" -gt "$grace_secs" ]] && poll_interval="$grace_secs"

  local elapsed=0 own_run_found=0 had_query_failure=0 run_sha=""
  while [[ "$elapsed" -lt "$grace_secs" ]]; do
    # '// "NOSHA"' macht "gh hat sauber geantwortet, aber (noch) kein Run
    # vorhanden" (leeres Array, jq: .[0] -> null -> Fallback "NOSHA") explizit
    # von einer echten Abfrage-Störung unterscheidbar: eine fehlgeschlagene/
    # abgebrochene gh-Abfrage (Netz/Auth/Rate-Limit) liefert eine LEERE
    # Zeichenkette, niemals "NOSHA" — genau das trennt AC1 ("kein Run") von
    # AC3 ("Abfrage war nicht fehlerfrei, also NIE als 'kein Trigger' werten").
    run_sha="$(gh run list --branch "$branch" --limit 1 --json headSha --jq '.[0].headSha // "NOSHA"' 2>/dev/null || echo "")"
    if [[ -z "$run_sha" ]]; then
      had_query_failure=1
      ensure_gh_auth
    elif [[ "$run_sha" == "$expect_sha" ]]; then
      own_run_found=1
      break
    else
      # "NOSHA" (noch kein Run) oder ein fremder Run (anderer Commit) — beides
      # ist kein Treffer, aber auch kein Fehlersignal; das Fenster läuft
      # unverändert weiter (AC1/AC3).
      ensure_gh_auth
    fi
    sleep "$poll_interval"
    elapsed=$((elapsed + poll_interval))
  done

  if [[ "$own_run_found" -eq 1 ]]; then
    log "CI-Run für ${expect_sha} auf '${branch}' erschienen — beobachte scharf bis zur Conclusion."
    watch_ci_scharf_loop "$branch" "$expect_sha"
    return 0
  fi

  if [[ "$had_query_failure" -eq 1 ]]; then
    log "Trigger-Beobachtung für '${branch}' im Fenster nicht durchgehend fehlerfrei (gh-Abfrage leer/fehlgeschlagen) — CI-Watch läuft sicherheitshalber scharf (K1)."
    watch_ci_scharf_loop "$branch" "$expect_sha"
    return 0
  fi

  log "kein CI-Run für ${expect_sha} auf '${branch}' innerhalb ${grace_secs}s erschienen — kein Trigger, CI-Watch entfällt."
  return 0
}

# Lokaler Docker-Rollout mit Rollout-Verifikation gegen die tatsächlich
# deployte Revision (nicht nur "pull lief durch" — Registry-Propagations-
# verzögerung wurde am 2026-07-06 beim Deploy real beobachtet).
do_rollout_or_die() {
  local expect_sha="$1"
  local deploy_mode image
  deploy_mode="$(grep -m1 '^deploy:' .claude/profile.md 2>/dev/null | sed 's/deploy: *//;s/"//g' || true)"
  deploy_mode="${deploy_mode:-none}"
  [[ "$deploy_mode" == "docker" ]] || return 0

  image="$(grep -m1 '^image:' .claude/profile.md 2>/dev/null | sed 's/image: *//;s/"//g' || true)"
  [[ -n "$image" ]] || die "profile.deploy=docker aber kein 'image'-Feld in .claude/profile.md"

  if [[ -z "$APP_NAME" ]]; then
    # Eindeutigkeits-Gate (K1 — nie raten): genau EIN laufender Container mit
    # diesem Image → eindeutig, sonst STOPP (kein automatischer Rollout).
    local matches match_count
    matches="$(docker ps --filter "ancestor=${image}" --format '{{.Names}}' 2>/dev/null | sort -u)"
    match_count="$(echo "$matches" | grep -c . || true)"
    if [[ "$match_count" -eq 1 ]]; then
      APP_NAME="$matches"
    else
      die "Container-Name nicht eindeutig bestimmbar (${match_count} Treffer für Image '${image}') — als Argument explizit übergeben."
    fi
  fi

  docker pull "${image}:latest" --quiet || die "docker pull fehlgeschlagen für ${image}:latest"

  local deployed_rev=""
  for _ in $(seq 1 20); do
    docker compose up -d --force-recreate "$APP_NAME" >/dev/null 2>&1 || docker restart "$APP_NAME" >/dev/null 2>&1 || true
    sleep 3
    deployed_rev="$(docker inspect "$APP_NAME" --format '{{index .Config.Labels "org.opencontainers.image.revision"}}' 2>/dev/null || echo "")"
    [[ "$deployed_rev" == "$expect_sha" ]] && break
    docker pull "${image}:latest" --quiet || true   # Registry-Propagationsverzögerung (2026-07-06 beobachtet) — erneut ziehen
    sleep 10
  done

  if [[ "$deployed_rev" != "$expect_sha" ]]; then
    die "Rollout-Verifikation fehlgeschlagen — deployte Revision '${deployed_rev:-leer}' ≠ erwartet '${expect_sha}' nach 20 Versuchen. Manuell prüfen."
  fi
  log "Rollout verifiziert — deployte Revision entspricht ${expect_sha}."
  docker image prune -f >/dev/null 2>&1 || true
}

# ---------------------------------------------------------------------------
# Temporärer, detached Worktree für git-Operationen auf einem Branch, der im
# aufrufenden Worktree bereits ausgecheckt sein könnte (AC7/AC9/AC10,
# flow/L07 — dev-gui S-358). Git verbietet denselben Branch gleichzeitig in
# zwei Worktrees; statt den Ziel-Branch im aufrufenden Worktree auszuchecken
# (der S-358-Defekt), arbeitet dieses Skript auf einem eigenen, kurzlebigen,
# DETACHED Worktree auf origin/<branch> und landet per
# 'git push origin HEAD:<branch>'. Der temporäre Worktree wird auf JEDEM
# Ausgang entfernt (Erfolg, Fehler, Abbruch) — EXIT-Trap als Sicherheitsnetz
# PLUS expliziter Aufruf direkt nach Gebrauch; kein Fallback auf 'checkout'
# bei Fehlschlag (E7 — das wäre genau der Defekt, den diese Spec beseitigt).
# ---------------------------------------------------------------------------
TEMP_LAND_WORKTREE=""

cleanup_temp_land_worktree() {
  if [[ -n "$TEMP_LAND_WORKTREE" ]]; then
    git worktree remove --force "$TEMP_LAND_WORKTREE" >/dev/null 2>&1 \
      || rm -rf "$TEMP_LAND_WORKTREE" 2>/dev/null || true
    git worktree prune >/dev/null 2>&1 || true
    TEMP_LAND_WORKTREE=""
  fi
}
trap cleanup_temp_land_worktree EXIT

# Legt einen temporären, detached Worktree auf origin/<branch> an und gibt
# dessen Pfad auf stdout aus. WICHTIG: läuft der Aufrufer über Kommando-
# substitution ("$(create_temp_land_worktree ...)"), MUSS er danach selbst
# TEMP_LAND_WORKTREE="<Rückgabewert>" setzen — diese Funktion selbst läuft
# dabei in einer Subshell, eigene Zuweisungen an TEMP_LAND_WORKTREE gingen
# beim Verlassen der Subshell verloren (Bash-Semantik).
create_temp_land_worktree() {
  local branch="$1"
  git worktree prune >/dev/null 2>&1 || true   # nicht-destruktiv, entfernt nur verwaiste Metadaten (E7)
  local path
  path="$(mktemp -u -d "${TMPDIR:-/tmp}/board-ship-land.XXXXXX")"
  git worktree add --detach --quiet "$path" "origin/${branch}" \
    || die "temporärer Worktree für '${branch}' konnte nicht angelegt werden (Pfad belegt? Rest eines abgebrochenen Laufs? 'git worktree prune' half nicht) — kein Fallback auf 'checkout'."
  echo "$path"
}

# ============================================================================
# Modus C — kompletten Feature-Branch nach profile.default_branch mergen
# ============================================================================
if [[ "$MODE" == "merge-feature" ]]; then
  [[ -n "$MERGE_FEATURE_BRANCH" ]] || die "Verwendung: board-ship.sh --merge-feature <branch> [<container-name>]"
  guard_clean_or_die
  ensure_gh_auth
  git fetch origin "$MERGE_FEATURE_BRANCH" "$DEFAULT_BRANCH" --quiet \
    || die "Fetch von '${MERGE_FEATURE_BRANCH}'/'${DEFAULT_BRANCH}' fehlgeschlagen — existiert der Feature-Branch remote?"

  if git merge-base --is-ancestor "origin/${MERGE_FEATURE_BRANCH}" "origin/${DEFAULT_BRANCH}" 2>/dev/null; then
    log "Feature-Branch '${MERGE_FEATURE_BRANCH}' ist bereits vollständig in '${DEFAULT_BRANCH}' enthalten — nichts zu mergen."
  else
    # AC10: finaler Feature-Merge OHNE checkout/reset --hard des default_branch
    # im aufrufenden Worktree — der Merge-Commit entsteht in einem temporären,
    # detached Worktree auf origin/<default_branch> (AC9-Mechanismus).
    guard_clean_or_die
    MERGE_LAND_WORKTREE="$(create_temp_land_worktree "$DEFAULT_BRANCH")"
    TEMP_LAND_WORKTREE="$MERGE_LAND_WORKTREE"

    git -C "$MERGE_LAND_WORKTREE" merge --no-ff "origin/${MERGE_FEATURE_BRANCH}" -q -m "merge: ${MERGE_FEATURE_BRANCH} (Feature-Batch, alle Storys einzeln geprüft/gelandet)" \
      || die "Merge von '${MERGE_FEATURE_BRANCH}' nach '${DEFAULT_BRANCH}' fehlgeschlagen — Konflikt, manuell auflösen (sollte bei sequenziellem Story-Landing nicht vorkommen)."
    git -C "$MERGE_LAND_WORKTREE" push origin "HEAD:${DEFAULT_BRANCH}" --quiet \
      || die "Push des Feature-Merges nach '${DEFAULT_BRANCH}' fehlgeschlagen (Non-Fast-Forward?) — origin/${DEFAULT_BRANCH} unverändert, kein Force, manuell prüfen."

    cleanup_temp_land_worktree
  fi

  REMOTE_HEAD="$(git rev-parse "origin/${DEFAULT_BRANCH}")"
  watch_ci_or_die "$DEFAULT_BRANCH" "$REMOTE_HEAD"
  do_rollout_or_die "$REMOTE_HEAD"

  log "Feature-Branch '${MERGE_FEATURE_BRANCH}' erfolgreich nach '${DEFAULT_BRANCH}' gelandet (${REMOTE_HEAD})."
  exit 0
fi

# ============================================================================
# Modus A/B — einzelne Story landen (Ziel: profile.default_branch oder --target-branch)
# ============================================================================
[[ -n "$STORY_ID" ]] || die "Verwendung: board-ship.sh <story-id> [<container-name>] [--target-branch <branch>]"
[[ "$STORY_ID" =~ ^S-[0-9]{3,}$ ]] || die "<story-id> muss Format S-### haben, war '$STORY_ID'"

SHIP_BRANCH="${TARGET_BRANCH:-$DEFAULT_BRANCH}"
IS_FEATURE_TARGET=0
[[ -n "$TARGET_BRANCH" ]] && IS_FEATURE_TARGET=1

# --- Schritt 0: Ausgangszustand merken ---
LOCAL_HEAD="$(git rev-parse HEAD)"
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
[[ "$BRANCH" != "main" && "$BRANCH" != "HEAD" && "$BRANCH" != "$SHIP_BRANCH" ]] || die "auf '$BRANCH' — erwarte einen eigenen Story-Branch, nicht das Ziel selbst"

guard_clean_or_die

# --- Schritt 1: bereits gemergt? ECHTE Prüfung (merge-base), keine Behauptung übernehmen ---
ensure_gh_auth
git fetch origin "$SHIP_BRANCH" --quiet 2>/dev/null || git fetch origin "$DEFAULT_BRANCH" --quiet   # Feature-Branch existiert evtl. noch nicht remote

ALREADY_MERGED=0
if git rev-parse "origin/${SHIP_BRANCH}" >/dev/null 2>&1 && git merge-base --is-ancestor "$LOCAL_HEAD" "origin/${SHIP_BRANCH}" 2>/dev/null; then
  ALREADY_MERGED=1
  log "bereits gemergt — ${LOCAL_HEAD} ist nachweislich Vorfahre von origin/${SHIP_BRANCH} (merge-base-Check, keine Behauptung übernommen)."
  log "kein erneuter Merge nötig — fahre direkt mit CI-Check/Board-Flip fort."
fi

# --- Schritt 2: mergen (nur falls noch nicht gemergt) ---
PR_URL=""
if [[ "$ALREADY_MERGED" -eq 0 ]]; then
  guard_clean_or_die   # erneut — seit Schritt 0 ist Zeit vergangen
  git push origin "HEAD:${BRANCH}" --quiet

  if [[ "$IS_FEATURE_TARGET" -eq 1 ]] && ! git rev-parse "origin/${SHIP_BRANCH}" >/dev/null 2>&1; then
    # Feature-Branch existiert remote noch nicht — von origin/default_branch abzweigen (board-feature-drain.sh legt ihn i.d.R. schon an; Defense-in-Depth).
    git push origin "origin/${DEFAULT_BRANCH}:refs/heads/${SHIP_BRANCH}" --quiet \
      || die "Feature-Branch '${SHIP_BRANCH}' existiert nicht und konnte nicht angelegt werden."
  fi

  MERGE_POLICY="$(grep -m1 '^merge_policy:' .claude/profile.md 2>/dev/null | sed 's/merge_policy: *//;s/"//g' || true)"
  MERGE_POLICY="${MERGE_POLICY:-pr}"

  if [[ "$MERGE_POLICY" == "direct" ]]; then
    # AC8: Landen per FF-Push, OHNE Checkout des Ziel-Branches im aufrufenden
    # Worktree (AC7) — mechanische FF-Prüfung statt 'checkout + pull + merge
    # --ff-only'. HEAD ist hier weiterhin der Story-Branch '$BRANCH'.
    guard_clean_or_die
    git fetch origin "$SHIP_BRANCH" --quiet || die "Fetch von '${SHIP_BRANCH}' fehlgeschlagen."
    BEHIND_COUNT="$(git rev-list --count "HEAD..origin/${SHIP_BRANCH}" 2>/dev/null || echo "")"
    [[ "$BEHIND_COUNT" =~ ^[0-9]+$ ]] || die "Fast-Forward-Prüfung gegen 'origin/${SHIP_BRANCH}' mechanisch nicht auswertbar — Abbruch, kein Push."
    [[ "$BEHIND_COUNT" == "0" ]] || die "kein Fast-Forward möglich — ${BEHIND_COUNT} Commit(s) Rückstand gegenüber origin/${SHIP_BRANCH} — manuell rebasen. origin/${SHIP_BRANCH} unverändert, Board unverändert."
    git push origin "HEAD:${SHIP_BRANCH}" --quiet \
      || die "Push nach '${SHIP_BRANCH}' fehlgeschlagen (Non-Fast-Forward?) — origin/${SHIP_BRANCH} unverändert, kein Force, manuell prüfen."
  else
    COMMIT_TITLE="$(git log -1 --format=%s)"
    PR_OUT="$(gh pr create --base "$SHIP_BRANCH" --head "$BRANCH" --title "${STORY_ID}: ${COMMIT_TITLE}" --body "Automatisch gelandet via board-ship.sh (L3 — deterministischer SHIP-Pfad)." 2>&1)" \
      || die "gh pr create fehlgeschlagen: ${PR_OUT}"
    PR_URL="$(echo "$PR_OUT" | grep -Eo 'https://github\.com/\S+' | tail -1)"
    [[ -n "$PR_URL" ]] || die "konnte PR-URL nicht aus gh-Ausgabe extrahieren: ${PR_OUT}"
    gh pr merge "$BRANCH" --squash --delete-branch >/dev/null || die "gh pr merge fehlgeschlagen für Branch '${BRANCH}'"
  fi
fi

# --- Schritt 3: Ziel-Branch-SHA ermitteln + CI beobachten (AC7: kein
# Checkout des Ziel-Branches — 'origin/<ship-branch>' wird rein lesend
# abgefragt, der aufrufende Worktree bleibt auf dem Story-Branch) ---
guard_clean_or_die
git fetch origin "$SHIP_BRANCH" --quiet || die "Fetch von '${SHIP_BRANCH}' fehlgeschlagen."

REMOTE_HEAD="$(git rev-parse "origin/${SHIP_BRANCH}")"
watch_ci_or_die "$SHIP_BRANCH" "$REMOTE_HEAD"

# --- Schritt 4: lokaler Rollout — NUR beim echten Ziel-Branch (nie bei Feature-Zwischenständen) ---
if [[ "$IS_FEATURE_TARGET" -eq 0 ]]; then
  do_rollout_or_die "$REMOTE_HEAD"
else
  log "Ziel ist Feature-Branch '${SHIP_BRANCH}' — kein Rollout (folgt gebündelt beim finalen Feature-Merge)."
fi

# --- Schritt 5/6: Board-Flip im temporären, detached Worktree auf
# origin/<ship-branch> (AC9) — betrifft AUCH merge_policy: pr (agent-flow
# selbst): der aufrufende Worktree bleibt unverändert auf dem Story-Branch,
# der Ziel-Branch wird hier NIE ausgecheckt. 'board set' operiert über die
# BOARD_DIR-Env-Var direkt auf dem temporären Worktree — kein 'cd' im
# laufenden Skript nötig (vermeidet Subshell-/Trap-Verwicklungen). ---
guard_clean_or_die   # aufrufender Worktree muss VOR dem Worktree-Anlegen sauber sein (echte Prüfung, kein Vertrauen)
git fetch origin "$SHIP_BRANCH" --quiet || die "Fetch von '${SHIP_BRANCH}' vor dem Board-Flip fehlgeschlagen."

LAND_WORKTREE="$(create_temp_land_worktree "$SHIP_BRANCH")"
TEMP_LAND_WORKTREE="$LAND_WORKTREE"

BOARD_DIR="${LAND_WORKTREE}/board" BOARD_WRITER=flow "$BOARD_SCRIPT" set "$STORY_ID" status Done
if [[ -n "$PR_URL" ]]; then
  BOARD_DIR="${LAND_WORKTREE}/board" BOARD_WRITER=flow "$BOARD_SCRIPT" set "$STORY_ID" pr "$PR_URL"
fi
BOARD_DIR="${LAND_WORKTREE}/board" BOARD_WRITER=flow "$BOARD_SCRIPT" set "$STORY_ID" branch "$BRANCH"

if [[ -n "$(git -C "$LAND_WORKTREE" status --porcelain)" ]]; then
  git -C "$LAND_WORKTREE" add board/
  git -C "$LAND_WORKTREE" commit -q -m "chore(board): ${STORY_ID} Done"
  git -C "$LAND_WORKTREE" push origin "HEAD:${SHIP_BRANCH}" --quiet \
    || die "Push des Board-Flips nach '${SHIP_BRANCH}' fehlgeschlagen — origin/${SHIP_BRANCH} inzwischen weitergelaufen? Story-Commit ist gelandet, Flip nicht — erneuter, idempotenter Aufruf holt ihn nach."
fi

cleanup_temp_land_worktree

log "${STORY_ID} erfolgreich gelandet (${SHIP_BRANCH}=$(git rev-parse "origin/${SHIP_BRANCH}"))."
exit 0
