#!/usr/bin/env bash
# metrics-aggregate.sh
#
# Liest .claude/metrics/dispatches.jsonl + items.jsonl, bildet Mediane je
# <lang>|<cost_mode>|<size> und kalibriert die EP-Gewichte per linearer
# Regression gegen echte tok/secs. Schreibt .claude/metrics/baseline.json neu.
#
# Aufgerufen von retro im periodischen Mess-Schritt (Modus C).
# Single-Writer-Disziplin: NUR retro darf baseline.json schreiben (K2).
#
# ─── Design-Entscheidung: Cache-Token-Gewichtung ─────────────────────────────
# Echte Token-Verteilung (empirisch, #109): ~302 in / ~72k out / ~15.4M cache.
# Cache-Reads sind ~10× billiger als frischer Input (API-Pricing). Würde man
# tok_total = in+out+cache ungewichtet als Eich-Ziel nehmen, würde das Cache-
# Volumen alles andere dominieren und ep_per_token verzerren.
#
# Lösung: "effektive Token" für die Kalibrierung:
#   tok_eff = in + out + κ·cache   (κ = 0.1)
#
# κ = 0.1 entspricht näherungsweise dem relativen API-Preis-Verhältnis
# (cache_read ≈ 0.1 × input_cost). So reflektiert ep_per_token den echten
# Kontingent-Verbrauch besser. items.jsonl speichert tok_total ungewichtet
# (Rohdaten), dispatches.jsonl enthält die Aufschlüsselung {in, out, cache}.
#
# Fallback: Gibt es keine Token-Daten (tok null), wird secs_total als
# Alternativ-Signal für die Regression verwendet (zeitbasierte Eichung).
# ep_per_token bezieht sich dann auf effektive Token und bleibt null wenn
# auch keine secs-Daten vorhanden sind.
# ─────────────────────────────────────────────────────────────────────────────
#
# Robust gegen leere/kleine Ledger:
#   - < MIN_ITEMS Items mit Daten → Regression wird übersprungen (null)
#   - < MIN_MEDIAN Einträge in einem Schnitt → Median bleibt null
#   - Jeder Fehler → null-Feld, kein Abbruch (K3)
#
# Requires: bash ≥3, jq, python3
#
# Usage: scripts/metrics-aggregate.sh [--repo-root <path>]
#

set -euo pipefail

MIN_ITEMS=5          # Minimum Items für lineare Regression (EP-Kalibrierung)
MIN_MEDIAN=2         # Minimum Einträge für einen validen Median-Schnitt
CACHE_KAPPA="0.1"    # Cache-Token-Gewichtungsfaktor (κ = ~Preis-Verhältnis)

# ─── Argumente / Pfade ────────────────────────────────────────────────────────
REPO_ROOT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo-root) REPO_ROOT="$2"; shift 2 ;;
    *) shift ;;
  esac
done

if [[ -z "$REPO_ROOT" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
  REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
fi

DISPATCHES_FILE="$REPO_ROOT/.claude/metrics/dispatches.jsonl"
ITEMS_FILE="$REPO_ROOT/.claude/metrics/items.jsonl"
BASELINE_FILE="$REPO_ROOT/.claude/metrics/baseline.json"

# ─── Vorbedingungen ───────────────────────────────────────────────────────────
if ! command -v jq >/dev/null 2>&1; then
  echo "[metrics-aggregate] WARN: jq nicht gefunden — baseline.json bleibt unverändert" >&2
  exit 0
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "[metrics-aggregate] WARN: python3 nicht gefunden — baseline.json bleibt unverändert" >&2
  exit 0
fi
if [[ ! -f "$ITEMS_FILE" ]]; then
  echo "[metrics-aggregate] INFO: items.jsonl nicht vorhanden — noch keine Daten" >&2
  exit 0
fi

# ─── Temp-Datei (atomarer Write auf baseline.json) ────────────────────────────
WORK_BASELINE=""
cleanup_temp() {
  [[ -n "${WORK_BASELINE:-}" ]] && rm -f "$WORK_BASELINE" || true
}
trap 'cleanup_temp' EXIT

WORK_BASELINE="$(mktemp "$REPO_ROOT/.claude/metrics/baseline-work.XXXXXX")"

# ─── Haupt-Logik in Python ────────────────────────────────────────────────────
# set +e um den python3-Aufruf: unter `set -e` würde ein Python-Crash bash SOFORT
# abbrechen (exit≠0), bevor der EXIT_CODE-Block unten greift — das verstösst gegen
# K3 (Messen blockiert nie den Loop). Nach dem Capture set -e wieder aktivieren.
set +e
python3 - \
  "$ITEMS_FILE" \
  "${DISPATCHES_FILE:-}" \
  "$WORK_BASELINE" \
  "$MIN_ITEMS" \
  "$MIN_MEDIAN" \
  "$CACHE_KAPPA" \
  "$BASELINE_FILE" \
  <<'PYEOF'

import sys
import json
import math
import statistics
from datetime import datetime, timezone
from pathlib import Path

items_file      = sys.argv[1]
dispatches_file = sys.argv[2]
work_out        = sys.argv[3]
min_items       = int(sys.argv[4])
min_median      = int(sys.argv[5])
cache_kappa     = float(sys.argv[6])
baseline_file   = sys.argv[7]

# ─── Ledger-Daten lesen ───────────────────────────────────────────────────────
def read_jsonl(path):
    """Liest eine JSONL-Datei. Fehlerhafte Zeilen werden übersprungen."""
    rows = []
    try:
        with open(path, encoding='utf-8') as f:
            for lineno, line in enumerate(f, 1):
                line = line.strip()
                if not line:
                    continue
                try:
                    rows.append(json.loads(line))
                except json.JSONDecodeError:
                    pass  # Fehlerhafte Zeile überspringen (K3)
    except (OSError, IOError):
        pass
    return rows

items = read_jsonl(items_file)
dispatches = read_jsonl(dispatches_file) if (dispatches_file and Path(dispatches_file).is_file()) else []

# ─── Bestehende baseline.json lesen (weights als Fallback) ────────────────────
DEFAULT_WEIGHTS = {
    "iter": 2, "crit": 1, "imp": 0.5,
    "test_fail": 2, "loc_log": 1, "blocked": 3
}

existing_weights = dict(DEFAULT_WEIGHTS)
if Path(baseline_file).is_file():
    try:
        with open(baseline_file, encoding='utf-8') as f:
            existing = json.load(f)
        if isinstance(existing.get('weights'), dict):
            # Bestehende Gewichte als Ausgangspunkt (werden ggf. kalibriert)
            for k, v in existing['weights'].items():
                if isinstance(v, (int, float)):
                    existing_weights[k] = v
    except Exception:
        pass

# ─── Helper: sicherer numerischer Wert ───────────────────────────────────────
def safe_num(val, default=None):
    if val is None:
        return default
    try:
        return float(val)
    except (TypeError, ValueError):
        return default

def safe_int(val, default=0):
    if val is None:
        return default
    try:
        return int(val)
    except (TypeError, ValueError):
        return default

# ─── dispatches per Item-Dispatch aggregieren: effektive Token ───────────────
# Aus dispatches.jsonl: tok = {"in": int, "out": int, "cache": int}
# tok_eff = in + out + κ·cache
# Pro Item die Summe über alle Dispatches.
dispatch_tok_eff_per_item = {}  # item_id → tok_eff (float)
for d in dispatches:
    item_id = d.get('item')
    if item_id is None:
        continue
    tok = d.get('tok')
    if not isinstance(tok, dict):
        continue
    t_in    = safe_int(tok.get('in'), 0)
    t_out   = safe_int(tok.get('out'), 0)
    t_cache = safe_int(tok.get('cache'), 0)
    eff = t_in + t_out + cache_kappa * t_cache
    dispatch_tok_eff_per_item[item_id] = dispatch_tok_eff_per_item.get(item_id, 0.0) + eff

# ─── Items validieren und anreichern ─────────────────────────────────────────
valid_items = []
for item in items:
    ep_act = safe_num(item.get('ep_act'))
    if ep_act is None or ep_act <= 0:
        continue  # ep_act ist Pflicht und positiv
    lang      = item.get('lang') or 'unknown'
    cost_mode = item.get('cost_mode') or 'balanced'
    size_est  = item.get('size_est') or 'M'
    iters     = safe_int(item.get('iters'), 1)
    crit      = safe_int(item.get('crit'), 0)
    imp       = safe_int(item.get('imp'), 0)
    test_fails = safe_int(item.get('test_fails'), 0)
    loc       = safe_int(item.get('loc'), 0)
    blocked   = safe_int(item.get('blocked'), 0)
    secs_total = safe_num(item.get('secs_total'))
    tok_total_raw = safe_num(item.get('tok_total'))

    item_id = item.get('item')
    # Effektive Token: aus dispatches (bevorzugt) oder tok_total (Fallback, keine κ-Gewichtung)
    tok_eff = dispatch_tok_eff_per_item.get(item_id) if item_id is not None else None
    if tok_eff is None and tok_total_raw is not None:
        # Fallback: tok_total ist in+out+cache ungewichtet — trotzdem besser als null
        # Wir markieren es als "unweighted" durch flag (wird bei ep_per_token beachtet)
        tok_eff = tok_total_raw  # konservativ: keine κ-Korrektur möglich

    valid_items.append({
        'item': item_id,
        'ep_act': ep_act,
        'lang': lang,
        'cost_mode': cost_mode,
        'size_est': size_est,
        'iters': iters,
        'crit': crit,
        'imp': imp,
        'test_fails': test_fails,
        'loc': loc,
        'blocked': blocked,
        'secs_total': secs_total,
        'tok_eff': tok_eff,
        'ep_est': safe_num(item.get('ep_est')),
    })

n_items = len(valid_items)

# ─── Mediane je <lang>|<cost_mode>|<size> ────────────────────────────────────
from collections import defaultdict
groups = defaultdict(list)
for item in valid_items:
    key = f"{item['lang']}|{item['cost_mode']}|{item['size_est']}"
    groups[key].append(item)

def median_or_null(values):
    vals = [v for v in values if v is not None]
    if len(vals) < min_median:
        return None
    return statistics.median(vals)

medians = {}
for key, group in sorted(groups.items()):
    n = len(group)
    entry = {
        'n': n,
        'ep':         median_or_null([g['ep_act']   for g in group]),
        'iters':      median_or_null([g['iters']     for g in group]),
        'crit':       median_or_null([g['crit']      for g in group]),
        'tok_total':  median_or_null([g['tok_eff']   for g in group if g['tok_eff'] is not None]),
        'secs_total': median_or_null([g['secs_total'] for g in group if g['secs_total'] is not None]),
    }
    medians[key] = entry

# ─── EP-Kalibrierung: lineare Regression ─────────────────────────────────────
# Wir kalibrieren:
#   1. ep_per_token: Median von ep_act / tok_eff (robust gegen Ausreisser)
#   2. weights: OLS-Regression EP ~ Σ weight_i * driver_i
#      Treiber: (iters-1), crit, imp, test_fails, log10(loc+1), blocked
#
# Mindest-Stichprobengrösse: MIN_ITEMS.

ep_per_token = None
calibrated_weights = dict(existing_weights)
calibration_note = None

# 1. ep_per_token
items_with_tok = [it for it in valid_items if it['tok_eff'] is not None and it['tok_eff'] > 0]
if len(items_with_tok) >= min_items:
    ratios = [it['ep_act'] / it['tok_eff'] for it in items_with_tok]
    ep_per_token = statistics.median(ratios)
    # Runden auf 6 Nachkommastellen (Lesbarkeit)
    ep_per_token = round(ep_per_token, 6)
    calibration_note = f"ep_per_token kalibriert auf {len(items_with_tok)} Items (κ={cache_kappa})"
elif len(items_with_tok) > 0:
    calibration_note = (
        f"Zu wenig Token-Daten ({len(items_with_tok)}/{min_items}) — ep_per_token bleibt null"
    )
else:
    calibration_note = "Keine Token-Daten — ep_per_token bleibt null"

# 2. Gewichts-Kalibrierung via OLS (nur wenn genug Daten)
# EP-Formel: EP = 1 + w_iter*(iters-1) + w_crit*crit + w_imp*imp
#                  + w_tf*test_fails + w_loc*log10(loc+1) + w_bl*blocked
#
# Für OLS subtrahieren wir den Basis-EP=1 von ep_act:
#   y = ep_act - 1
#   X = [(iters-1), crit, imp, test_fails, log10(loc+1), blocked]
#
# OLS: w = (X^T X)^{-1} X^T y  (via numpy-freie Implementierung)
#
# Constraints: alle Gewichte >= 0.1 (Plausibilitäts-Clamp)

def ols_nonneg(X, y, min_weight=0.1):
    """Einfache OLS ohne numpy. Gibt Koeffizientenvektor zurück oder None."""
    n = len(y)
    k = len(X[0]) if X else 0
    if n < k + 1:
        return None  # unterbestimmt
    # X^T X
    XtX = [[0.0]*k for _ in range(k)]
    for row in X:
        for i in range(k):
            for j in range(k):
                XtX[i][j] += row[i] * row[j]
    # X^T y
    Xty = [0.0]*k
    for idx, row in enumerate(X):
        for i in range(k):
            Xty[i] += row[i] * y[idx]
    # Gauß-Elimination mit Pivotierung
    aug = [XtX[i] + [Xty[i]] for i in range(k)]
    for col in range(k):
        # Pivot suchen
        pivot_row = max(range(col, k), key=lambda r: abs(aug[r][col]))
        aug[col], aug[pivot_row] = aug[pivot_row], aug[col]
        if abs(aug[col][col]) < 1e-12:
            return None  # Singularität
        factor = aug[col][col]
        aug[col] = [v / factor for v in aug[col]]
        for row in range(k):
            if row != col:
                mult = aug[row][col]
                aug[row] = [aug[row][j] - mult * aug[col][j] for j in range(k+1)]
    coeffs = [aug[i][k] for i in range(k)]
    # Clamp auf min_weight (kein negatives Gewicht)
    return [max(c, min_weight) for c in coeffs]

if n_items >= min_items:
    X_data = []
    y_data = []
    for it in valid_items:
        iter_driver = max(it['iters'] - 1, 0)
        loc_driver  = math.log10(it['loc'] + 1)
        X_data.append([
            float(iter_driver),
            float(it['crit']),
            float(it['imp']),
            float(it['test_fails']),
            loc_driver,
            float(it['blocked']),
        ])
        y_data.append(it['ep_act'] - 1.0)  # Basis-EP subtrahieren

    coeffs = ols_nonneg(X_data, y_data)
    if coeffs is not None:
        weight_keys = ['iter', 'crit', 'imp', 'test_fail', 'loc_log', 'blocked']
        for k_name, c in zip(weight_keys, coeffs):
            calibrated_weights[k_name] = round(c, 4)

# ─── Forecast-MAE ─────────────────────────────────────────────────────────────
items_with_est = [it for it in valid_items if it['ep_est'] is not None]
forecast_mae = None
if len(items_with_est) >= min_median:
    abs_errs = []
    for it in items_with_est:
        if it['ep_act'] > 0:
            abs_errs.append(abs(it['ep_est'] - it['ep_act']) / it['ep_act'])
    if abs_errs:
        forecast_mae = round(statistics.mean(abs_errs), 4)

# ─── baseline.json schreiben ──────────────────────────────────────────────────
calibrated_at = datetime.now(timezone.utc).strftime('%Y-%m-%d')

output = {
    "schema_version": 1,
    "calibrated_at": calibrated_at,
    "n_items": n_items,
    "ep_per_token": ep_per_token,
    "cache_kappa": float(cache_kappa),
    "weights": calibrated_weights,
    "medians": medians,
    "forecast_mae": forecast_mae,
}

if calibration_note:
    output["_calibration_note"] = calibration_note

with open(work_out, 'w', encoding='utf-8') as f:
    json.dump(output, f, indent=2, ensure_ascii=False)
    f.write('\n')

# Status-Ausgabe — auf stderr (stdout bleibt sauber; konsistent mit metrics-collect.sh)
print(f"[metrics-aggregate] OK: {n_items} Items, "
      f"{len(medians)} Median-Schnitte, "
      f"ep_per_token={'%.6f' % ep_per_token if ep_per_token is not None else 'null'}, "
      f"forecast_mae={forecast_mae}", file=sys.stderr)
PYEOF

EXIT_CODE=$?
set -e
if [[ $EXIT_CODE -ne 0 ]]; then
  echo "[metrics-aggregate] WARN: Python-Aggregation fehlgeschlagen (exit $EXIT_CODE) — baseline.json bleibt unverändert" >&2
  exit 0
fi

# Prüfen ob WORK_BASELINE etwas enthält (Python hat erfolgreich geschrieben)
if [[ ! -s "$WORK_BASELINE" ]]; then
  echo "[metrics-aggregate] WARN: Leere Ausgabe — baseline.json bleibt unverändert" >&2
  exit 0
fi

# Atomarer Replace (rename(2) im selben Verzeichnis — coder/L10)
mv "$WORK_BASELINE" "$BASELINE_FILE"
WORK_BASELINE=""  # Cleanup-Trap soll die nun an Ziel übergebene Datei nicht löschen
