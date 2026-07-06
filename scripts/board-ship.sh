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

DEFAULT_BRANCH="$(grep -m1 '^default_branch:' .claude/profile.md 2>/dev/null | sed 's/default_branch: *//;s/"//g')"
DEFAULT_BRANCH="${DEFAULT_BRANCH:-main}"

# ============================================================================
# Gemeinsame Bausteine (von Modus ship UND merge-feature genutzt)
# ============================================================================

# CI beobachten (cicd/F06: headSha-Race-Schutz) — bricht bei Fehlschlag ab.
watch_ci_or_die() {
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

# Lokaler Docker-Rollout mit Rollout-Verifikation gegen die tatsächlich
# deployte Revision (nicht nur "pull lief durch" — Registry-Propagations-
# verzögerung wurde am 2026-07-06 beim Deploy real beobachtet).
do_rollout_or_die() {
  local expect_sha="$1"
  local deploy_mode image
  deploy_mode="$(grep -m1 '^deploy:' .claude/profile.md 2>/dev/null | sed 's/deploy: *//;s/"//g')"
  deploy_mode="${deploy_mode:-none}"
  [[ "$deploy_mode" == "docker" ]] || return 0

  image="$(grep -m1 '^image:' .claude/profile.md 2>/dev/null | sed 's/image: *//;s/"//g')"
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
    git checkout "$DEFAULT_BRANCH" --quiet 2>/dev/null || git checkout -b "$DEFAULT_BRANCH" "origin/${DEFAULT_BRANCH}" --quiet
    guard_clean_or_die
    git reset --hard "origin/${DEFAULT_BRANCH}" --quiet
    git merge --no-ff "origin/${MERGE_FEATURE_BRANCH}" -q -m "merge: ${MERGE_FEATURE_BRANCH} (Feature-Batch, alle Storys einzeln geprüft/gelandet)" \
      || die "Merge von '${MERGE_FEATURE_BRANCH}' nach '${DEFAULT_BRANCH}' fehlgeschlagen — Konflikt, manuell auflösen (sollte bei sequenziellem Story-Landing nicht vorkommen)."
    git push origin "$DEFAULT_BRANCH" --quiet
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

  MERGE_POLICY="$(grep -m1 '^merge_policy:' .claude/profile.md 2>/dev/null | sed 's/merge_policy: *//;s/"//g')"
  MERGE_POLICY="${MERGE_POLICY:-pr}"

  if [[ "$MERGE_POLICY" == "direct" ]]; then
    guard_clean_or_die
    git checkout "$SHIP_BRANCH" --quiet 2>/dev/null || git checkout -b "$SHIP_BRANCH" "origin/${SHIP_BRANCH}" --quiet
    git pull --ff-only origin "$SHIP_BRANCH" --quiet || die "lokaler ${SHIP_BRANCH} divergiert von origin — manueller Rebase nötig, kein automatischer reset"
    git merge --ff-only "$BRANCH" --quiet || die "kein Fast-Forward möglich — '${BRANCH}' ist nicht aktuell gegenüber ${SHIP_BRANCH}, manuell rebasen"
    git push origin "$SHIP_BRANCH" --quiet
  else
    COMMIT_TITLE="$(git log -1 --format=%s)"
    PR_OUT="$(gh pr create --base "$SHIP_BRANCH" --head "$BRANCH" --title "${STORY_ID}: ${COMMIT_TITLE}" --body "Automatisch gelandet via board-ship.sh (L3 — deterministischer SHIP-Pfad)." 2>&1)" \
      || die "gh pr create fehlgeschlagen: ${PR_OUT}"
    PR_URL="$(echo "$PR_OUT" | grep -Eo 'https://github\.com/\S+' | tail -1)"
    [[ -n "$PR_URL" ]] || die "konnte PR-URL nicht aus gh-Ausgabe extrahieren: ${PR_OUT}"
    gh pr merge "$BRANCH" --squash --delete-branch --quiet || die "gh pr merge fehlgeschlagen für Branch '${BRANCH}'"
  fi
fi

# --- Schritt 3: Ziel-Branch aktualisieren + CI beobachten ---
git checkout "$SHIP_BRANCH" --quiet 2>/dev/null || git checkout -b "$SHIP_BRANCH" "origin/${SHIP_BRANCH}" --quiet
guard_clean_or_die
git fetch origin "$SHIP_BRANCH" --quiet
git reset --hard "origin/${SHIP_BRANCH}" --quiet   # Ziel-Branch selbst, kein Story-Worktree — keine eigene Arbeit hier gefährdet

REMOTE_HEAD="$(git rev-parse "origin/${SHIP_BRANCH}")"
watch_ci_or_die "$SHIP_BRANCH" "$REMOTE_HEAD"

# --- Schritt 4: lokaler Rollout — NUR beim echten Ziel-Branch (nie bei Feature-Zwischenständen) ---
if [[ "$IS_FEATURE_TARGET" -eq 0 ]]; then
  do_rollout_or_die "$REMOTE_HEAD"
else
  log "Ziel ist Feature-Branch '${SHIP_BRANCH}' — kein Rollout (folgt gebündelt beim finalen Feature-Merge)."
fi

# --- Schritt 5: Board-Flip (wiederverwendet 'board set' — kein eigenes YAML-Gefrickel) ---
guard_clean_or_die   # Ziel-Branch muss VOR dem Board-Flip sauber sein (echte Prüfung, kein Vertrauen)
export BOARD_WRITER=flow
"$BOARD_SCRIPT" set "$STORY_ID" status Done
[[ -n "$PR_URL" ]] && "$BOARD_SCRIPT" set "$STORY_ID" pr "$PR_URL"
"$BOARD_SCRIPT" set "$STORY_ID" branch "$BRANCH"

# --- Schritt 6: Board-Flip committen + pushen (sonst nur lokal, nicht geteilt) ---
if [[ -n "$(git status --porcelain)" ]]; then
  git add board/
  git commit -q -m "chore(board): ${STORY_ID} Done"
  git push origin "$SHIP_BRANCH" --quiet
fi

log "${STORY_ID} erfolgreich gelandet (${SHIP_BRANCH}=$(git rev-parse "origin/${SHIP_BRANCH}"))."
exit 0
