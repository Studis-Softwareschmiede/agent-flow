#!/usr/bin/env bash
# scripts/board-ship.sh <story-id>
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
# Vorbedingung: läuft im Story-Worktree, auf dem Story-Branch, HEAD ist der
# fertige, geprüfte (tester-PASS) Commit. Vom Orchestrator (/flow) NACH
# tester-PASS aufgerufen — ersetzt den bisherigen cicd-Task-Dispatch für den
# SHIP-Trigger. cicd bleibt für rollback/ci-fix/version-stamp zuständig (mehr
# Urteilsvermögen nötig, kein rein mechanischer Pfad).
#
# Exit 0 = erfolgreich gelandet (oder bereits gelandet, verifiziert). Exit 1 =
# Abbruch mit klarer Fehlermeldung — Board bleibt unverändert, kein Rollout.

set -euo pipefail

STORY_ID="${1:-}"
APP_NAME="${2:-}"
[[ -n "$STORY_ID" ]] || { echo "FEHLER [board-ship]: Verwendung: board-ship.sh <story-id> [<container-name>]" >&2; exit 1; }
[[ "$STORY_ID" =~ ^S-[0-9]{3,}$ ]] || { echo "FEHLER [board-ship]: <story-id> muss Format S-### haben, war '$STORY_ID'" >&2; exit 1; }
# <container-name> optional — analog zum bisherigen cicd-Vertrag ("APP: <app-name>
# (optional; sonst aus .claude/profile.md)"). Wird NIE geraten (K1) — fehlt er bei
# deploy=docker und lässt sich nicht eindeutig bestimmen, bricht Schritt 4 ab.

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

# --- Schritt 0: Ausgangszustand merken ---
LOCAL_HEAD="$(git rev-parse HEAD)"
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
[[ "$BRANCH" != "main" && "$BRANCH" != "HEAD" ]] || die "auf '$BRANCH' — erwarte einen Story-Branch, nicht main/detached HEAD"

guard_clean_or_die

DEFAULT_BRANCH="$(grep -m1 '^default_branch:' .claude/profile.md 2>/dev/null | sed 's/default_branch: *//;s/"//g')"
DEFAULT_BRANCH="${DEFAULT_BRANCH:-main}"

# --- Schritt 1: bereits gemergt? ECHTE Prüfung (merge-base), keine Behauptung übernehmen ---
ensure_gh_auth
git fetch origin "$DEFAULT_BRANCH" --quiet

ALREADY_MERGED=0
if git merge-base --is-ancestor "$LOCAL_HEAD" "origin/${DEFAULT_BRANCH}" 2>/dev/null; then
  ALREADY_MERGED=1
  log "bereits gemergt — ${LOCAL_HEAD} ist nachweislich Vorfahre von origin/${DEFAULT_BRANCH} (merge-base-Check, keine Behauptung übernommen)."
  log "kein erneuter Merge nötig — fahre direkt mit CI-Check/Rollout/Board-Flip fort."
fi

# --- Schritt 2: mergen (nur falls noch nicht gemergt) ---
PR_URL=""
if [[ "$ALREADY_MERGED" -eq 0 ]]; then
  guard_clean_or_die   # erneut — seit Schritt 0 ist Zeit vergangen
  git push origin "HEAD:${BRANCH}" --quiet

  MERGE_POLICY="$(grep -m1 '^merge_policy:' .claude/profile.md 2>/dev/null | sed 's/merge_policy: *//;s/"//g')"
  MERGE_POLICY="${MERGE_POLICY:-pr}"

  if [[ "$MERGE_POLICY" == "direct" ]]; then
    guard_clean_or_die
    git checkout "$DEFAULT_BRANCH" --quiet
    git pull --ff-only origin "$DEFAULT_BRANCH" --quiet || die "lokaler ${DEFAULT_BRANCH} divergiert von origin — manueller Rebase nötig, kein automatischer reset"
    git merge --ff-only "$BRANCH" --quiet || die "kein Fast-Forward möglich — '${BRANCH}' ist nicht aktuell gegenüber ${DEFAULT_BRANCH}, manuell rebasen"
    git push origin "$DEFAULT_BRANCH" --quiet
  else
    COMMIT_TITLE="$(git log -1 --format=%s)"
    PR_OUT="$(gh pr create --head "$BRANCH" --title "${STORY_ID}: ${COMMIT_TITLE}" --body "Automatisch gelandet via board-ship.sh (L3 — deterministischer SHIP-Pfad)." 2>&1)" \
      || die "gh pr create fehlgeschlagen: ${PR_OUT}"
    PR_URL="$(echo "$PR_OUT" | grep -Eo 'https://github\.com/\S+' | tail -1)"
    [[ -n "$PR_URL" ]] || die "konnte PR-URL nicht aus gh-Ausgabe extrahieren: ${PR_OUT}"
    gh pr merge "$BRANCH" --squash --delete-branch --quiet || die "gh pr merge fehlgeschlagen für Branch '${BRANCH}'"
  fi
fi

# --- Schritt 3: main aktualisieren + CI beobachten (cicd/F06: headSha-Race-Schutz) ---
git checkout "$DEFAULT_BRANCH" --quiet 2>/dev/null || true
guard_clean_or_die
git fetch origin "$DEFAULT_BRANCH" --quiet
git reset --hard "origin/${DEFAULT_BRANCH}" --quiet   # main selbst, kein Story-Worktree — keine eigene Arbeit hier gefährdet

REMOTE_HEAD="$(git rev-parse "origin/${DEFAULT_BRANCH}")"
RUN_CONCLUSION=""
for _ in $(seq 1 40); do
  RUN_SHA="$(gh run list --branch "$DEFAULT_BRANCH" --limit 1 --json headSha --jq '.[0].headSha' 2>/dev/null || echo "")"
  RUN_STATUS="$(gh run list --branch "$DEFAULT_BRANCH" --limit 1 --json status --jq '.[0].status' 2>/dev/null || echo "")"
  if [[ "$RUN_SHA" == "$REMOTE_HEAD" ]]; then
    if [[ "$RUN_STATUS" == "completed" ]]; then
      RUN_CONCLUSION="$(gh run list --branch "$DEFAULT_BRANCH" --limit 1 --json conclusion --jq '.[0].conclusion' 2>/dev/null || echo "")"
      break
    fi
  else
    ensure_gh_auth
  fi
  sleep 15
done

if [[ "$RUN_CONCLUSION" != "success" ]]; then
  die "CI nicht erfolgreich für ${REMOTE_HEAD} (conclusion='${RUN_CONCLUSION:-timeout/unbekannt}') — KEIN Rollout, Board bleibt unverändert (In Review). Manuell prüfen: gh run list --branch ${DEFAULT_BRANCH}"
fi
log "CI grün für ${REMOTE_HEAD}."

# --- Schritt 4: lokaler Rollout (nur falls profile.deploy == docker) ---
DEPLOY_MODE="$(grep -m1 '^deploy:' .claude/profile.md 2>/dev/null | sed 's/deploy: *//;s/"//g')"
DEPLOY_MODE="${DEPLOY_MODE:-none}"

if [[ "$DEPLOY_MODE" == "docker" ]]; then
  IMAGE="$(grep -m1 '^image:' .claude/profile.md 2>/dev/null | sed 's/image: *//;s/"//g')"
  [[ -n "$IMAGE" ]] || die "profile.deploy=docker aber kein 'image'-Feld in .claude/profile.md"

  if [[ -z "$APP_NAME" ]]; then
    # Eindeutigkeits-Gate (K1 — nie raten): genau EIN laufender Container mit
    # diesem Image → eindeutig, sonst STOPP (kein automatischer Rollout).
    MATCHES="$(docker ps --filter "ancestor=${IMAGE}" --format '{{.Names}}' 2>/dev/null | sort -u)"
    MATCH_COUNT="$(echo "$MATCHES" | grep -c . || true)"
    if [[ "$MATCH_COUNT" -eq 1 ]]; then
      APP_NAME="$MATCHES"
    else
      die "Container-Name nicht eindeutig bestimmbar (${MATCH_COUNT} Treffer für Image '${IMAGE}') — als 2. Argument explizit übergeben: board-ship.sh ${STORY_ID} <container-name>"
    fi
  fi

  docker pull "${IMAGE}:latest" --quiet || die "docker pull fehlgeschlagen für ${IMAGE}:latest"

  DEPLOYED_REV=""
  for _ in $(seq 1 20); do
    docker compose up -d --force-recreate "$APP_NAME" >/dev/null 2>&1 || docker restart "$APP_NAME" >/dev/null 2>&1 || true
    sleep 3
    DEPLOYED_REV="$(docker inspect "$APP_NAME" --format '{{index .Config.Labels "org.opencontainers.image.revision"}}' 2>/dev/null || echo "")"
    [[ "$DEPLOYED_REV" == "$REMOTE_HEAD" ]] && break
    docker pull "${IMAGE}:latest" --quiet || true   # Registry-Propagationsverzögerung (2026-07-06 beobachtet) — erneut ziehen
    sleep 10
  done

  if [[ "$DEPLOYED_REV" != "$REMOTE_HEAD" ]]; then
    die "Rollout-Verifikation fehlgeschlagen — deployte Revision '${DEPLOYED_REV:-leer}' ≠ erwartet '${REMOTE_HEAD}' nach 20 Versuchen. KEIN Board-Flip auf Done — manuell prüfen."
  fi
  log "Rollout verifiziert — deployte Revision entspricht ${REMOTE_HEAD}."
  docker image prune -f >/dev/null 2>&1 || true
fi

# --- Schritt 5: Board-Flip (wiederverwendet 'board set' — kein eigenes YAML-Gefrickel) ---
guard_clean_or_die   # main muss VOR dem Board-Flip sauber sein (echte Prüfung, kein Vertrauen)
export BOARD_WRITER=flow
"$BOARD_SCRIPT" set "$STORY_ID" status Done
[[ -n "$PR_URL" ]] && "$BOARD_SCRIPT" set "$STORY_ID" pr "$PR_URL"
"$BOARD_SCRIPT" set "$STORY_ID" branch "$BRANCH"

# --- Schritt 6: Board-Flip committen + pushen (sonst nur lokal, nicht geteilt) ---
if [[ -n "$(git status --porcelain)" ]]; then
  git add board/
  git commit -q -m "chore(board): ${STORY_ID} Done"
  git push origin "$DEFAULT_BRANCH" --quiet
fi

log "${STORY_ID} erfolgreich gelandet (main=$(git rev-parse origin/${DEFAULT_BRANCH}))."
exit 0
