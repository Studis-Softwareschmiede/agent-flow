#!/usr/bin/env bash
# metrics-append-item.sh <story-id> [<size_est> [<ep_est> [<loc> [<files> [<blocked> [<lang> [<cost_mode> [<tok_est>]]]]]]]]
#
# Rollup: liest alle dispatches.jsonl-Zeilen des Items, berechnet ep_act
# und hängt eine Zeile an .claude/metrics/items.jsonl an.
# Wird von /flow beim Done (nach Rollout-Gate PASS) aufgerufen (§2b Touchpoint).
#
# Verträge (Spec metrics-recording-reliability V1/V2; <tok_est> Spec apriori-token-estimate AC4):
#   - <story-id>  : kanonisches String-Format "S-###" (AC2)
#   - <size_est>  : S|M|L|XL (Default "M")
#   - <ep_est>    : float|null (Default null)
#   - <loc>       : int (insertions+deletions aus git diff --shortstat; Default 0)
#   - <files>     : int (geänderte Dateien; Default 0)
#   - <blocked>   : 0|1 (Default 0)
#   - <lang>      : Sprache aus profile.lang (Default "md")
#   - <cost_mode> : aktiver Cost-Mode (Default "balanced")
#   - <tok_est>   : int|null (A-priori-Token-Erwartung aus Story-YAML; Default null; optional
#                   — Alt-Aufrufe ohne diesen 9. Parameter bleiben gültig, AC5)
#
# Append-only, idempotenz-tolerant, || true (K3: kein Loop-Abbruch bei Fehler).
# Kein LLM-Aufruf — reine Bash/jq-Arithmetik (K1, AC6).
# Historische Zeilen werden nie geändert (AC7).
#
# EP-Formel (metrics-subsystem §3):
#   EP = 1
#      + 2*(iters-1) + 1*crit + 0.5*imp + 2*test_fails
#      + round(log10(loc+1)) + 3*blocked

set -euo pipefail

STORY_ID="${1:-}"
SIZE_EST="${2:-M}"
EP_EST_RAW="${3:-null}"
LOC="${4:-0}"
FILES="${5:-0}"
BLOCKED="${6:-0}"
LANG="${7:-md}"
COST_MODE="${8:-balanced}"
TOK_EST_RAW="${9:-null}"

# Pflichtfeld prüfen
if [[ -z "$STORY_ID" ]]; then
  echo "[metrics-append-item] WARN: story-id fehlt — Zeile nicht geschrieben" >&2
  exit 0
fi

# jq-Verfügbarkeit prüfen
if ! command -v jq >/dev/null 2>&1; then
  echo "[metrics-append-item] WARN: jq nicht gefunden — Zeile nicht geschrieben" >&2
  exit 0
fi

# Ledger-Pfad (Spec metrics-repo-anchor AC6): kommt EXPLIZIT aus METRICS_ROOT,
# nie aus dem Skript-Ort. Das Werkzeug lebt im Plugin, die Daten am Board-Repo.
if [[ -z "${METRICS_ROOT:-}" ]]; then
  echo "[metrics-append-item] WARN: METRICS_ROOT nicht gesetzt — Ledger-Pfad unbestimmbar, Zeile nicht geschrieben" >&2
  exit 0
fi
REPO_ROOT="$METRICS_ROOT"
# Plausibilitäts-Gate (AC4): nie in ein Repo ohne dieses Board schreiben
if [[ ! -f "$REPO_ROOT/board/board.yaml" ]]; then
  echo "[metrics-append-item] WARN: METRICS_ROOT ($REPO_ROOT) enthält kein board/board.yaml — Zeile nicht geschrieben" >&2
  exit 0
fi
METRICS_DIR="$REPO_ROOT/.claude/metrics"
DISPATCHES_FILE="$METRICS_DIR/dispatches.jsonl"
ITEMS_FILE="$METRICS_DIR/items.jsonl"

# Verzeichnis anlegen falls nötig
mkdir -p "$METRICS_DIR" 2>/dev/null || true

# Numerik-Guards
[[ "$LOC"     =~ ^[0-9]+$ ]] || LOC=0
[[ "$FILES"   =~ ^[0-9]+$ ]] || FILES=0
[[ "$BLOCKED" =~ ^[01]$   ]] || BLOCKED=0

# size_est-Guard
case "$SIZE_EST" in
  S|M|L|XL) ;;
  *) SIZE_EST="M" ;;
esac

# ep_est: "null" oder leer → JSON null; sonst Zahl
if [[ -z "$EP_EST_RAW" || "$EP_EST_RAW" == "null" ]]; then
  EP_EST_JSON='null'
else
  # Prüfen ob parseable Zahl
  if printf '%s' "$EP_EST_RAW" | jq -e '. | numbers' >/dev/null 2>&1; then
    EP_EST_JSON="$EP_EST_RAW"
  else
    EP_EST_JSON='null'
  fi
fi

# tok_est: "null" oder leer → JSON null; sonst Zahl (apriori-token-estimate AC4)
if [[ -z "$TOK_EST_RAW" || "$TOK_EST_RAW" == "null" ]]; then
  TOK_EST_JSON='null'
else
  if printf '%s' "$TOK_EST_RAW" | jq -e '. | numbers' >/dev/null 2>&1; then
    TOK_EST_JSON="$TOK_EST_RAW"
  else
    TOK_EST_JSON='null'
  fi
fi

# ─── Aggregation aus dispatches.jsonl ────────────────────────────────────────
# Rollup: item == STORY_ID (String-Match, AC2)
ITERS=1
CRIT_SUM=0
IMP_SUM=0
TEST_FAILS=0
RULE_HITS_JSON='[]'
SECS_TOTAL=0

if [[ -f "$DISPATCHES_FILE" ]]; then
  # Aggregat zeilenweise (Spec metrics-recording-reliability V5/AC8): jq -R -s
  # liest die Datei als EINEN String ein, split("\n") + fromjson? // empty
  # parst jede Zeile EINZELN — eine einzelne korrupte Zeile lässt (anders als
  # das vormalige atomare "jq -s") nicht mehr das gesamte Aggregat sterben
  # (das vorher den || DEFAULT-Fallback triggerte und ALLE Rollups lautlos
  # auf iters=1/crit=0/imp=0/secs_total=0 zurücksetzte). split("\n") erzeugt
  # bei trailing newline ein leeres letztes Element — das wird vor fromjson
  # per select(length>0) verworfen, zählt also nicht als "unparsbar".
  # Bekannte Grenze: zwei fälschlich auf einer Zeile konkatenierte JSON-Objekte
  # ohne Trenn-Newline (z.B. defektes Append) parsen NICHT als zwei Zeilen —
  # jq fromjson erwartet genau einen Wert je Zeile und würde eine solche
  # Zeile als Ganzes verwerfen (korrekt als "unparsbar" gezählt, aber ohne
  # Teil-Rettung). Für das reale Korruptions-Muster (abgeschnittener Schreib-
  # vorgang, siehe Befund S-073) ist das nicht relevant; ein Vollparser wäre
  # hier unverhältnismäßig.
  ROLLUP="$(jq -R -s \
    --arg item "$STORY_ID" \
    '
    (split("\n") | map(select(length>0))) as $lines
    | ($lines | map(fromjson? // empty) | map(select(type=="object"))) as $rows
    | {
        skipped:     (($lines | length) - ($rows | length)),
        iters:       ([ $rows[] | select(.item==$item) | .iter   // 0 ] | max // 1),
        crit:        ([ $rows[] | select(.item==$item) | .crit   // 0 ] | add // 0),
        imp:         ([ $rows[] | select(.item==$item) | .imp    // 0 ] | add // 0),
        test_fails:  ([ $rows[] | select(.item==$item and .gate=="FAIL" and .agent=="tester") ] | length),
        rule_hits:   ([ $rows[] | select(.item==$item) | .rule_hits // [] | .[] ] | unique),
        secs_total:  ([ $rows[] | select(.item==$item) | .secs   // 0 ] | add // 0)
      }' \
    "$DISPATCHES_FILE" 2>/dev/null)" || ROLLUP='{}'

  ITERS="$(printf '%s' "$ROLLUP" | jq -r '.iters // 1' 2>/dev/null)" || ITERS=1
  CRIT_SUM="$(printf '%s' "$ROLLUP" | jq -r '.crit // 0' 2>/dev/null)" || CRIT_SUM=0
  IMP_SUM="$(printf '%s' "$ROLLUP" | jq -r '.imp // 0' 2>/dev/null)" || IMP_SUM=0
  TEST_FAILS="$(printf '%s' "$ROLLUP" | jq -r '.test_fails // 0' 2>/dev/null)" || TEST_FAILS=0
  RULE_HITS_JSON="$(printf '%s' "$ROLLUP" | jq -c '.rule_hits // []' 2>/dev/null)" || RULE_HITS_JSON='[]'
  SECS_TOTAL="$(printf '%s' "$ROLLUP" | jq -r '.secs_total // 0' 2>/dev/null)" || SECS_TOTAL=0

  # Sichtbare Warnung bei übersprungenen Zeilen (AC8: K3 — nicht blockierend,
  # aber nicht verschwiegen).
  SKIPPED_COUNT="$(printf '%s' "$ROLLUP" | jq -r '.skipped // 0' 2>/dev/null)" || SKIPPED_COUNT=0
  [[ "$SKIPPED_COUNT" =~ ^[0-9]+$ ]] || SKIPPED_COUNT=0
  if [[ "$SKIPPED_COUNT" -gt 0 ]]; then
    # Datei-weite Eigenschaft, kein item-eigenes Ereignis (Review-Fund
    # Iteration 2): der Zähler läuft über ALLE Zeilen von dispatches.jsonl,
    # bevor nach $STORY_ID gefiltert wird — eine kaputte Zeile eines fremden
    # Items triggert dieselbe Warnung. Wording bewusst ohne Item-Bezug.
    echo "[metrics-append-item] WARN: ${SKIPPED_COUNT} unparsbare Zeile(n) im dispatches.jsonl-Ledger übersprungen (datei-weit, nicht zwingend item-eigen)" >&2
  fi
fi

# Numerik-Sicherung nach Aggregat
[[ "$ITERS"      =~ ^[0-9]+$ ]] || ITERS=1
[[ "$CRIT_SUM"   =~ ^[0-9]+$ ]] || CRIT_SUM=0
[[ "$IMP_SUM"    =~ ^[0-9]+$ ]] || IMP_SUM=0
[[ "$TEST_FAILS" =~ ^[0-9]+$ ]] || TEST_FAILS=0
[[ "$SECS_TOTAL" =~ ^[0-9]+$ ]] || SECS_TOTAL=0

# ─── EP-Formel (metrics-subsystem §3) ─────────────────────────────────────────
# EP = 1 + 2*(iters-1) + 1*crit + 0.5*imp + 2*test_fails
#        + round(log10(loc+1)) + 3*blocked
EP_ACT="$(python3 - "$ITERS" "$CRIT_SUM" "$IMP_SUM" "$TEST_FAILS" "$LOC" "$BLOCKED" 2>/dev/null <<'PYEOF' || echo "1"
import sys, math
iters     = int(sys.argv[1])
crit      = int(sys.argv[2])
imp_val   = int(sys.argv[3])
tfails    = int(sys.argv[4])
loc       = int(sys.argv[5])
blocked   = int(sys.argv[6])

ep = (1
      + 2 * (iters - 1)
      + 1 * crit
      + 0.5 * imp_val
      + 2 * tfails
      + round(math.log10(loc + 1))
      + 3 * blocked)
# Minimum 1
ep = max(1.0, ep)
# Ganzzahl wenn möglich (kein .0)
if ep == int(ep):
    print(int(ep))
else:
    print(ep)
PYEOF
)" || EP_ACT=1

# ─── Zeile schreiben (append-only) ────────────────────────────────────────────
jq -nc \
  --arg     ts         "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg     item       "$STORY_ID" \
  --arg     size_est   "$SIZE_EST" \
  --argjson ep_est     "$EP_EST_JSON" \
  --argjson tok_est    "$TOK_EST_JSON" \
  --argjson ep_act     "$EP_ACT" \
  --argjson iters      "$ITERS" \
  --argjson crit       "$CRIT_SUM" \
  --argjson imp        "$IMP_SUM" \
  --argjson test_fails "$TEST_FAILS" \
  --argjson rule_hits  "$RULE_HITS_JSON" \
  --argjson loc        "$LOC" \
  --argjson files      "$FILES" \
  --argjson secs_total "$SECS_TOTAL" \
  --argjson blocked    "$BLOCKED" \
  --arg     lang       "$LANG" \
  --arg     cost_mode  "$COST_MODE" \
  '{ts:$ts, item:$item, size_est:$size_est, ep_est:$ep_est, tok_est:$tok_est,
    ep_act:$ep_act, iters:$iters, crit:$crit, imp:$imp,
    test_fails:$test_fails, rule_hits:$rule_hits,
    loc:$loc, files:$files, tok_total:null,
    secs_total:$secs_total, blocked:$blocked,
    lang:$lang, cost_mode:$cost_mode}' \
  >> "$ITEMS_FILE" 2>/dev/null || true

echo "[metrics-append-item] OK: ${STORY_ID} ep_act=${EP_ACT} iters=${ITERS} crit=${CRIT_SUM} imp=${IMP_SUM}" >&2
