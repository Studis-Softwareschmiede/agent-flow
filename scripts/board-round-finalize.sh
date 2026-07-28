#!/usr/bin/env bash
# scripts/board-round-finalize.sh <story-id> <base-sha> [<size-est> [<ep-est> [<blocked> [<lang> [<cost-mode> [<tok-est>]]]]]]
#
# Stufe-1-Abschluss-Primitiv (docs/architecture/flow-deterministic-runner.md
# §6.1/§8, S2.4/S5.7/S7.2) — bündelt die FINALIZE-Nacharbeit, die heute in
# skills/flow/SKILL.md §2b ("Beim Done"/"Token-Nachtrag"/"Dispo-Spiegel"),
# §5 ("ID-Block-Freigabe, Solo-Pfad") und §7a ("Board-Status-Ausgabe") als
# mehrere Einzelschritte beschrieben sind, in EIN deterministisches Skript —
# analog zu scripts/board-ship.sh (kein neues Verhalten, nur weniger
# Werkzeug-Aufrufe pro Runde).
#
# WICHTIG (Scope-Grenze): Dieses Skript läuft NACH erfolgreichem
# `board-ship.sh`-Landen (Story-Status bereits `Done`). Es ist NICHT für den
# Board-Status-Flip selbst zuständig (macht board-ship.sh) und committet/
# pusht NICHTS — die hier per `board set` geschriebenen Dispo-Spiegel-Felder
# bleiben bewusst uncommitted im Working-Tree stehen (SKILL.md §2b: "Commit
# zurückgehalten bis Session-Ende", zusammen mit der Memory-Kuration). Bei
# Blocked-Ausgängen (kein Landen) wird dieses Skript NICHT aufgerufen.
#
# K3-Doktrin (Metrik-Subsystem, unverändert): ein Metrik-/Cleanup-Fehler
# blockiert nie die Runde, wird aber sichtbar gemeldet (kein stilles
# Verschlucken). Board-Status wird von diesem Skript nirgends geschrieben,
# ausser den Dispo-Spiegel-Feldern (nicht-status Story-Felder, kein
# Single-Writer-Konflikt, board/AC9 betrifft nur `status`).
#
# Reihenfolge (verbindlich, wie im Item-Auftrag beschrieben):
#   1. Metrik-Item-Append   (metrics-append-item.sh, inkl. shortstat)
#   2. Token-Nachtrag       (metrics-collect.sh, out-of-band, || true)
#   3. Dispo-Spiegel        (board set dispo_act/tok/dispo_forecast, Join
#                            gegen die soeben geschriebene items.jsonl-Zeile
#                            -- läuft NACH dem Token-Nachtrag, damit `tok`
#                            nicht mehr `null` ist, wenn metrics-collect.sh
#                            das Ledger patchen konnte)
#   4. ID-Block-Freigabe    (board-id-reserve.sh release, nicht-fatal)
#   5. Board-Status-Ausgabe (board next + board ready --quiet, Klartext)
#
# Argumente:
#   <story-id>   Pflicht, kanonisches Format S-### (AC2 metrics-recording-reliability)
#   <base-sha>   Pflicht, SHA/Ref bei Item-Eintritt (für git diff --shortstat)
#   <size-est>   optional, Default "M"
#   <ep-est>     optional, Default "null" (float|null)
#   <blocked>    optional, Default "0" (0|1)
#   <lang>       optional, Default "md" (profile.lang)
#   <cost-mode>  optional, Default "balanced"
#   <tok-est>    optional, Default "null" (int|null)
#
# Env:
#   METRICS_ROOT  optional -- Ledger-Wurzel (Spec metrics-repo-anchor AC2).
#                 Fehlt die Variable, wird sie auf den Repo-Toplevel dieses
#                 Aufrufs defaultet (identisch zu der Etablierung, die /flow
#                 in SKILL.md §0 ohnehin vornimmt -- kein neuer Pfad, kein
#                 ${CLAUDE_PLUGIN_ROOT}-basierter Ledger-Pfad, AC6).
#
# Exit 0 immer (K3) -- ausser bei fehlenden/falsch formatierten Pflicht-
# argumenten (Usage-Fehler, kein Metrik-/Cleanup-Fehler).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

BOARD_SCRIPT="${SCRIPT_DIR}/board"

log() { echo "[board-round-finalize] $*" >&2; }
die() { echo "FEHLER [board-round-finalize]: $*" >&2; exit 1; }

STORY_ID="${1:-}"
BASE_SHA="${2:-}"
SIZE_EST="${3:-M}"
EP_EST="${4:-null}"
BLOCKED="${5:-0}"
LANG="${6:-md}"
COST_MODE="${7:-balanced}"
TOK_EST="${8:-null}"

[[ -n "$STORY_ID" ]] || die "Verwendung: board-round-finalize.sh <story-id> <base-sha> [<size-est> [<ep-est> [<blocked> [<lang> [<cost-mode> [<tok-est>]]]]]]"
[[ "$STORY_ID" =~ ^S-[0-9]{3,}$ ]] || die "<story-id> muss Format S-### haben, war '$STORY_ID'"
[[ -n "$BASE_SHA" ]] || die "<base-sha> fehlt"

# metrics-repo-anchor AC2/AC6: kein neuer Pfad -- nur die bereits in §0
# etablierte Wurzel defaulten, falls der Aufrufer sie nicht durchgereicht hat.
export METRICS_ROOT="${METRICS_ROOT:-$REPO_ROOT}"

# ============================================================================
# Schritt 1 — Metrik-Item-Append (SKILL.md §2b "Beim Done")
# ============================================================================
SHORTSTAT="$(git diff --shortstat "$BASE_SHA" HEAD 2>/dev/null)" || SHORTSTAT=""
LOC=$(printf '%s' "$SHORTSTAT" | grep -oE '[0-9]+ insertion' | grep -oE '[0-9]+' || echo 0)
LOC=$(( LOC + $(printf '%s' "$SHORTSTAT" | grep -oE '[0-9]+ deletion' | grep -oE '[0-9]+' || echo 0) ))
FILES=$(printf '%s' "$SHORTSTAT" | grep -oE '[0-9]+ file' | grep -oE '[0-9]+' || echo 0)

bash "${SCRIPT_DIR}/metrics-append-item.sh" \
  "$STORY_ID" "$SIZE_EST" "$EP_EST" "$LOC" "$FILES" \
  "$BLOCKED" "$LANG" "$COST_MODE" "$TOK_EST" >&2 || true

# ============================================================================
# Schritt 2 — Token-Nachtrag (SKILL.md §2b "Token-Nachtrag", out-of-band)
# ============================================================================
bash "${SCRIPT_DIR}/metrics-collect.sh" "$STORY_ID" >&2 || true

# ============================================================================
# Schritt 3 — Dispo-Spiegel in Story-YAML (SKILL.md §2b, Join gegen die
# soeben geschriebene items.jsonl-Zeile -- alle Schreibungen || true, K3)
# ============================================================================
ITEMS_FILE="${METRICS_ROOT}/.claude/metrics/items.jsonl"
if [[ -f "$ITEMS_FILE" ]] && command -v jq >/dev/null 2>&1; then
  LAST_ITEM_LINE="$(grep "\"item\":\"${STORY_ID}\"" "$ITEMS_FILE" 2>/dev/null | tail -1 || true)"
  if [[ -n "$LAST_ITEM_LINE" ]]; then
    EP_ACT_JOIN="$(printf '%s' "$LAST_ITEM_LINE" | jq -r '.ep_act // "null"' 2>/dev/null || echo null)"
    TOK_TOTAL_JOIN="$(printf '%s' "$LAST_ITEM_LINE" | jq -r '.tok_total // "null"' 2>/dev/null || echo null)"
    EP_EST_JOIN="$(printf '%s' "$LAST_ITEM_LINE" | jq -r '.ep_est // "null"' 2>/dev/null || echo null)"

    "$BOARD_SCRIPT" set "$STORY_ID" dispo_act "$EP_ACT_JOIN" >/dev/null 2>&1 || true
    "$BOARD_SCRIPT" set "$STORY_ID" tok "$TOK_TOTAL_JOIN" >/dev/null 2>&1 || true

    if [[ "$EP_EST_JOIN" != "null" && "$EP_ACT_JOIN" != "null" && "$EP_ACT_JOIN" != "0" ]]; then
      DISPO_FORECAST="$(python3 -c "
import sys
try:
    ep_est = float(sys.argv[1]); ep_act = float(sys.argv[2])
    print(round((ep_est - ep_act) / ep_act, 4))
except Exception:
    print('null')
" "$EP_EST_JOIN" "$EP_ACT_JOIN" 2>/dev/null || echo null)"
      if [[ "$DISPO_FORECAST" != "null" ]]; then
        "$BOARD_SCRIPT" set "$STORY_ID" dispo_forecast "$DISPO_FORECAST" >/dev/null 2>&1 || true
      fi
    fi
  else
    log "HINWEIS: keine items.jsonl-Zeile für ${STORY_ID} gefunden — Dispo-Spiegel übersprungen (Metrik-Append in Schritt 1 fehlgeschlagen?)."
  fi
else
  log "HINWEIS: items.jsonl oder jq nicht verfügbar — Dispo-Spiegel übersprungen (nicht fatal, K3)."
fi

# ============================================================================
# Schritt 4 — ID-Block-Freigabe, Solo-Pfad (SKILL.md §5, id-block-reservation
# AC9/AC10) -- nicht-fatal, Story ist bereits erfolgreich gelandet.
# ============================================================================
if ! "${SCRIPT_DIR}/board-id-reserve.sh" release "$STORY_ID" >/dev/null 2>/dev/null; then
  echo "⚠ ID-Reservierungs-Freigabe für ${STORY_ID} fehlgeschlagen (nicht fatal — Ledger bleibt mit aktivem Eintrag stehen)." >&2
fi

# ============================================================================
# Schritt 5 — Board-Status-Ausgabe (SKILL.md §7a) -- reine Diagnose, kein
# Board-Schreibvorgang. Der Aufrufer/Runner zeigt den zurückgegebenen Text an.
# ============================================================================
NEXT_JSON="$("$BOARD_SCRIPT" next 2>/dev/null)" || NEXT_JSON=""
READY_OUTPUT="$("$BOARD_SCRIPT" ready --quiet 2>/dev/null)" || true

NEXT_ID=""
if [[ -n "$NEXT_JSON" ]] && command -v jq >/dev/null 2>&1; then
  NEXT_ID="$(printf '%s' "$NEXT_JSON" | jq -r '.id // empty' 2>/dev/null || true)"
fi

if [[ -n "$NEXT_ID" ]]; then
  READY_COUNT="$(printf '%s\n' "$READY_OUTPUT" | grep -oE '^Summary: [0-9]+' | grep -oE '[0-9]+' | head -1 || true)"
  [[ "$READY_COUNT" =~ ^[0-9]+$ ]] || READY_COUNT=0
  echo "Board nicht leer — noch ${READY_COUNT} abarbeitbare(s) Item(s), nächster Lauf nimmt voraussichtlich ${NEXT_ID}."
else
  WAITING_LINES="$(printf '%s\n' "$READY_OUTPUT" | grep '^WAITING ' || true)"
  if [[ -n "$WAITING_LINES" ]]; then
    echo "nichts abarbeitbar — Gründe:"
    printf '%s\n' "$WAITING_LINES"
  else
    echo "Board leer — keine abarbeitbaren Items."
  fi
fi

exit 0
