#!/usr/bin/env bash
# scripts/board-claim.sh <story-id>
#
# Bündelt die CLAIM-Sequenz aus `skills/flow/SKILL.md` §2 (Spec
# [`docs/specs/story-claim-lock.md`](../docs/specs/story-claim-lock.md)
# AC1-AC5/AC12/AC13) in EIN deterministisches Skript — Stufe-1-Primitiv des
# Runden-Runners (Spec [`docs/specs/flow-deterministic-runner.md`](../docs/specs/flow-deterministic-runner.md)
# AC4, Detailkonzept `docs/architecture/flow-deterministic-runner.md` §1.3
# S2.1-S2.5, §4.3, §8). KEIN neues Claim-/Race-/Lock-Protokoll — dieses
# Skript kapselt ausschliesslich das bestehende, seit S-120 gehärtete
# Push-basierte Protokoll (kein Verhaltensdelta ggü. SKILL.md §2, nur
# Bündelung + Skript-Form).
#
# K1-Doktrin (analog board-ship.sh — prüfen statt behaupten): jeder
# Zustandsübergang wird über eine echte Git-Prüfung entschieden (Push-Erfolg/
# -Ablehnung, `git show` gegen den frisch gefetchten Remote-Stand), nie
# angenommen. Bei jeder Unklarheit Abbruch statt Raten.
#
# Vorbedingung: läuft im Story-Worktree, HEAD ist der Stand, ab dem der Claim
# gesetzt werden soll (i.d.R. unmittelbar nach `git fetch` + `board next` des
# aufrufenden Runners/Orchestrators). Working-Tree MUSS sauber sein (s.
# guard_clean_or_die) — sonst STOPP vor jeder Schreiboperation.
#
# Rebase-frei (HART, s. story-claim-lock AC2 — empirisch, `.git/rebase-merge`
# reproduziert): bei abgelehntem Push wird NIEMALS `git rebase`/`git merge`
# verwendet. Der Re-Read liest ausschliesslich aus dem gefetchten Remote-
# Objekt (`git show origin/<default_branch>:<story-datei>`), der Working-Tree
# (inkl. des eigenen, noch ungelandeten Claim-Commits) bleibt dabei
# unangetastet. Die Bereinigung ist ein reiner Fast-Forward-`git reset --hard`.
#
# Fremd-Klassifikation (wörtlich nach story-claim-lock AC3/AC7 — "fremd,
# FRISCH (nicht stale)"): Zeigt der Re-Read die Story als `In Progress` mit
# fremdem `claimed_by`, prüft dieses Skript `claimed_at` gegen
# `stale_claim_hours` (`board/board.yaml`, Default 4 — identische Semantik zu
# `scripts/board`s `parse_claimed_at`/Stale-Fallback):
#   - fremd + FRISCH (noch nicht stale) → echte Konkurrenz, Exit 2 (eigene
#     Reservierung verwerfen, Aufrufer wählt das nächste Item).
#   - fremd + STALE (Claim ist längst verwaist) → KEINE echte Konkurrenz.
#     Dieser Fall wird wie eine "unbezogene Ablehnung" behandelt (derselbe
#     Retry-Zweig wie `REMOTE_STATUS = To Do`, gleicher Token) — deckt S2.3
#     (Stale-Reclamation-Kollision, story-claim-lock AC8): reklamiert diese
#     Session gerade einen verwaisten Claim und wird ihr Push durch einen
#     völlig unbezogenen Commit abgelehnt, darf die eigene Reklamation
#     weiterlaufen, statt fälschlich als "fremd übernommen" aufzugeben.
# Kein neuer Verzweigungsfall — beide Prüfungen (frisch/stale) sind bereits
# im story-claim-lock-Protokolltext vorgesehen (AC3/AC7/AC8), hier nur
# nachgetragen (AC4: kein neues Protokoll).
#
# Exit-Codes (kanonisch):
#   0 = Claim erfolgreich — status=In Progress, claimed_by/claimed_at/branch
#       gesetzt, committet + nach origin/<default_branch> gepusht. Der
#       Aufrufer darf jetzt den coder dispatchen.
#   2 = Fremd übernommen — Re-Read zeigt die Story als `In Progress` mit
#       fremdem, FRISCHEM claimed_by (noch nicht stale gemäss
#       stale_claim_hours). Eigene Reservierung verworfen (reset --hard).
#       Aufrufer soll das nächste Item wählen (`board next` erneut). Ein
#       fremder, aber bereits STALE Claim führt NICHT hierher — s.
#       Kopfkommentar "Fremd-Klassifikation" (Retry-Zweig statt Exit 2).
#   3 = Retry-Budget (3 Versuche insgesamt) erschöpft — Story bleibt `To Do`
#       (reset --hard), sauberer Abbruch, kein halb-geclaimter Zwischenstand.
#   1 = Nutzungsfehler / harter Git-Infrastruktur-Fehler / nicht
#       klassifizierbarer Remote-Zustand (Klartext-Meldung, kein Raten).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

BOARD_SCRIPT="${SCRIPT_DIR}/board"

log() { echo "[board-claim] $*"; }
die() { echo "FEHLER [board-claim]: $*" >&2; exit 1; }

# --- L6-Guard: niemals mit uncommitteten Änderungen destruktiv git-operieren
# (identisches Muster zu board-ship.sh guard_clean_or_die) ---
guard_clean_or_die() {
  local dirty
  dirty="$(git status --porcelain)"
  if [[ -n "$dirty" ]]; then
    die "Working-Tree hat uncommittete Änderungen — STOPP vor jedem Claim-Versuch.
Commit oder stash zuerst, dann erneut aufrufen. Betroffene Dateien:
${dirty}"
  fi
}

STORY_ID="${1:-}"
[[ -n "$STORY_ID" ]] || die "Verwendung: board-claim.sh <story-id>"
[[ "$STORY_ID" =~ ^S-[0-9]{3,}$ ]] || die "<story-id> muss Format S-### haben, war '$STORY_ID'"

guard_clean_or_die

DEFAULT_BRANCH="$(grep -m1 '^default_branch:' .claude/profile.md 2>/dev/null | sed 's/default_branch: *//;s/"//g' || true)"
DEFAULT_BRANCH="${DEFAULT_BRANCH:-main}"

STORY_FILE="$(git ls-files "board/stories/${STORY_ID}-*.yaml" | head -1)"
[[ -n "$STORY_FILE" ]] || die "Story-Datei für '${STORY_ID}' nicht im Working-Tree gefunden (board/stories/${STORY_ID}-*.yaml)."

# --- Titel lesen + Slug bilden (identischer Algorithmus zu scripts/board
# slugify(): lowercase, Nicht-Alphanumerisches -> Bindestrich, trim, max 60
# Zeichen, Default 'item') — für die Branch-Konvention feat/<id>-<slug> ---
TITLE="$(BOARD_DIR=board "$BOARD_SCRIPT" show "$STORY_ID" 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin).get("title") or "")')"
SLUG="$(python3 -c "
import re, sys
t = sys.argv[1].lower()
t = re.sub(r'[^a-z0-9]+', '-', t)
t = t.strip('-')
print(t[:60] if t else 'item')
" "$TITLE")"
BRANCH_NAME="feat/${STORY_ID}-${SLUG}"

# --- Opaker Session-Token (AC5, story-claim-lock) — EINMAL je Story-Session,
# kein neues Token je Retry ---
CLAIM_TOKEN="$(hostname)-$$-$(date -u +%s)-${RANDOM}"

# do_claim_attempt — Schritte 2-3 aus SKILL.md §2 (Reservierung setzen,
# committen, sofort pushen). Gibt 0 (Push erfolgreich) oder 1 (abgelehnt)
# zurück.
do_claim_attempt() {
  BOARD_DIR=board BOARD_WRITER=flow "$BOARD_SCRIPT" set "$STORY_ID" status "In Progress" >/dev/null
  BOARD_DIR=board "$BOARD_SCRIPT" set "$STORY_ID" claimed_by "$CLAIM_TOKEN" >/dev/null
  BOARD_DIR=board "$BOARD_SCRIPT" set "$STORY_ID" claimed_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >/dev/null
  BOARD_DIR=board "$BOARD_SCRIPT" set "$STORY_ID" branch "$BRANCH_NAME" >/dev/null

  git add "$STORY_FILE"
  git commit -q -m "chore(board): ${STORY_ID} claim (In Progress)"

  if git push origin HEAD:"$DEFAULT_BRANCH" 2>/dev/null; then
    return 0
  else
    return 1
  fi
}

# re_read_remote — fetcht + liest die Story ausschliesslich aus dem
# gefetchten Remote-Objekt (rebase-frei, Working-Tree unangetastet). Setzt
# REMOTE_STATUS/REMOTE_CLAIMED_BY/REMOTE_CLAIMED_AT.
re_read_remote() {
  git fetch origin "$DEFAULT_BRANCH" --quiet \
    || die "git fetch von 'origin/${DEFAULT_BRANCH}' fehlgeschlagen — Claim-Re-Read nicht möglich."
  REMOTE_STATUS="$(git show "origin/${DEFAULT_BRANCH}:${STORY_FILE}" | python3 -c 'import sys,yaml; print((yaml.safe_load(sys.stdin) or {}).get("status") or "")')"
  REMOTE_CLAIMED_BY="$(git show "origin/${DEFAULT_BRANCH}:${STORY_FILE}" | python3 -c 'import sys,yaml; print((yaml.safe_load(sys.stdin) or {}).get("claimed_by") or "")')"
  REMOTE_CLAIMED_AT="$(git show "origin/${DEFAULT_BRANCH}:${STORY_FILE}" | python3 -c 'import sys,yaml; print((yaml.safe_load(sys.stdin) or {}).get("claimed_at") or "")')"
}

# remote_claim_is_stale <claimed_at> — Exit 0 (true) wenn der Zeitstempel
# aelter ist als stale_claim_hours (board/board.yaml, Default 4 bei
# fehlendem/ungueltigem Feld — identisch zu scripts/board); Exit 1 (false)
# bei frischem ODER fehlendem/unparsebarem Zeitstempel (konservativ: wie
# scripts/board cmd_next behandelt ein nicht lesbarer claimed_at NIE als
# stale, s. dortiges parse_claimed_at()==None -> "kein Kandidat").
remote_claim_is_stale() {
  local claimed_at="$1"
  python3 - "$claimed_at" "board/board.yaml" <<'PYEOF'
import sys, datetime

claimed_at, board_yaml_path = sys.argv[1], sys.argv[2]

STALE_DEFAULT = 4
stale_hours = STALE_DEFAULT
try:
    import yaml
    with open(board_yaml_path) as f:
        board_data = yaml.safe_load(f) or {}
    raw = board_data.get("stale_claim_hours")
    if raw is not None:
        parsed = float(raw)
        if parsed > 0:
            stale_hours = parsed
except Exception:
    pass

if not claimed_at:
    sys.exit(1)

try:
    dt = datetime.datetime.strptime(claimed_at, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=datetime.timezone.utc)
except ValueError:
    sys.exit(1)

now = datetime.datetime.now(datetime.timezone.utc)
age_hours = (now - dt).total_seconds() / 3600.0
sys.exit(0 if age_hours > stale_hours else 1)
PYEOF
}

MAX_ATTEMPTS=3
ATTEMPT=1

while true; do
  if do_claim_attempt; then
    log "Claim für ${STORY_ID} erfolgreich gepusht nach origin/${DEFAULT_BRANCH} (Versuch ${ATTEMPT}/${MAX_ATTEMPTS}, Token ${CLAIM_TOKEN}, Branch ${BRANCH_NAME})."
    exit 0
  fi

  log "Claim-Push für ${STORY_ID} abgelehnt (Versuch ${ATTEMPT}/${MAX_ATTEMPTS}, non-fast-forward) — rebase-freier Re-Read."
  re_read_remote

  IS_FOREIGN=0
  if [[ "$REMOTE_STATUS" == "In Progress" && -n "$REMOTE_CLAIMED_BY" && "$REMOTE_CLAIMED_BY" != "$CLAIM_TOKEN" ]]; then
    IS_FOREIGN=1
  fi

  if [[ "$IS_FOREIGN" -eq 1 ]] && ! remote_claim_is_stale "$REMOTE_CLAIMED_AT"; then
    # Fremd + FRISCH (s. Kopfkommentar "Fremd-Klassifikation", story-claim-lock
    # AC3) — echte Konkurrenz, eigene Reservierung verwerfen, kein Bau,
    # Aufrufer wählt das nächste Item.
    git reset --hard "origin/${DEFAULT_BRANCH}" --quiet
    log "${STORY_ID} ist fremd geclaimt und frisch (claimed_by=${REMOTE_CLAIMED_BY}, claimed_at=${REMOTE_CLAIMED_AT}) — eigene Reservierung verworfen, nächstes Item wählen."
    exit 2
  fi

  if [[ "$REMOTE_STATUS" == "To Do" || "$IS_FOREIGN" -eq 1 ]]; then
    # Entweder weiterhin "To Do" (Ablehnung kam von einem unbezogenen Commit)
    # ODER fremd + STALE (S2.3 — die Ablehnung traf einen längst verwaisten
    # Claim, keine echte Konkurrenz; die eigene Reklamation läuft weiter) —
    # in beiden Fällen: Retry mit gleichem Token.
    git reset --hard "origin/${DEFAULT_BRANCH}" --quiet
    if [[ "$ATTEMPT" -lt "$MAX_ATTEMPTS" ]]; then
      ATTEMPT=$(( ATTEMPT + 1 ))
      if [[ "$IS_FOREIGN" -eq 1 ]]; then
        log "${STORY_ID} zeigt einen fremden, aber STALE Claim (claimed_by=${REMOTE_CLAIMED_BY}, claimed_at=${REMOTE_CLAIMED_AT}) — keine echte Konkurrenz, Retry ${ATTEMPT}/${MAX_ATTEMPTS} mit gleichem Token."
      else
        log "${STORY_ID} weiterhin 'To Do' (unbezogene Ablehnung) — Retry ${ATTEMPT}/${MAX_ATTEMPTS} mit gleichem Token."
      fi
      continue
    else
      log "Retry-Budget (${MAX_ATTEMPTS} Versuche) für ${STORY_ID} erschöpft — sauberer Abbruch, Story bleibt 'To Do'."
      exit 3
    fi
  fi

  die "Re-Read für '${STORY_ID}' lieferte einen nicht klassifizierbaren Remote-Zustand (status='${REMOTE_STATUS}', claimed_by='${REMOTE_CLAIMED_BY}') — kein Raten (K1). Working-Tree/Board unverändert prüfen und manuell klären."
done
