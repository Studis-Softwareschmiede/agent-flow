#!/usr/bin/env bash
# smoke.sh — Mechanik-Smoke-Test für scripts/validate-json.py.
#
# Covers (regression-define): AC13
#
# Beweist den PFLICHT-Testfall aus der Story S-061 ("ein Vorschlag mit
# Anführungszeichen in schritte/pruefpunkte muss valide JSON in der
# ergebnis_datei ergeben, json.load erfolgreich"):
#   - Fall A (grün): eine Ergebnis-Objekt-Datei, deren Textwerte (schritte,
#     pruefpunkte) ausschließlich TYPOGRAFISCHE Anführungszeichen enthalten
#     (deutsche „…" / ‚…'), ist valides JSON — validate-json.py liefert
#     Exit-Code 0.
#   - Fall B (rot, Regressionsschutz): eine Datei, die ein GERADES `"`
#     innerhalb eines Textwerts enthält (bricht den umschließenden
#     JSON-String — genau der Bug der drei gescheiterten Voranläufe dieser
#     Story), ist KEIN valides JSON — validate-json.py liefert einen
#     Fehler-Exit-Code (≠ 0) auf stderr, statt fälschlich Exit 0 zu melden.
#   - Zusatz: fehlende Datei -> Exit 2 (nicht 0/3), falsche Argumentzahl -> Exit 1.
#
# Voraussetzungen: bash, python3 (nur der zu testende Helfer selbst).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
VALIDATOR="$REPO_ROOT/scripts/validate-json.py"

SMOKE_DIR="$(mktemp -d "/tmp/smoke-validate-json-XXXXXX")"

cleanup() {
  local rc=$?
  rm -rf "$SMOKE_DIR"
  exit "$rc"
}
trap cleanup EXIT INT TERM

log()  { printf '[smoke-validate-json] %s\n' "$*"; }
fail() { printf '[smoke-validate-json] FAIL: %s\n' "$*" >&2; exit 1; }

[[ -f "$VALIDATOR" ]] || fail "Validator-Skript nicht gefunden: $VALIDATOR"

log "SMOKE_DIR=$SMOKE_DIR"

# ---- Fall A (grün): typografische Anführungszeichen im Wert -> valides JSON
log "Fall A: typografische Anführungszeichen in schritte/pruefpunkte -> valides JSON"
GOOD_FILE="$SMOKE_DIR/gut.json"
# Bewusst per Write-Äquivalent (hier: Heredoc mit AUSSCHLIESSLICH statischem,
# in diesem Testskript fest verdrahtetem Text — kein dynamisch interpolierter
# Agenten-Output) angelegt; der zu prüfende Mechanismus ist validate-json.py
# selbst, nicht der Schreibweg der Skill-Session.
cat >"$GOOD_FILE" <<'JSON'
{
  "projekt": "beispiel-repo",
  "ziel": { "typ": "bereich", "id": "regression-define" },
  "quell_specs": ["docs/specs/regression-define.md"],
  "vorschlag": [
    {
      "titel": "Owner redigiert einen Vorschlag mit „Sonderzeichen“",
      "schritte": [
        "Der Owner öffnet die Redaktionsschleife und liest den Hinweis „bitte prüfen“.",
        "Er ergänzt eine Notiz mit ‚Rückfrage: Format okay?‘ im Feld."
      ],
      "pruefpunkte": [
        "Die gespeicherte Fassung enthält weiterhin den Text „bitte prüfen“ unverändert."
      ],
      "beispieldaten": [ { "notiz": "‚Rückfrage: Format okay?‘" } ]
    }
  ],
  "target_vorschlag": "local",
  "hinweise": []
}
JSON

set +e
out_good="$(python3 "$VALIDATOR" "$GOOD_FILE" 2>&1)"
rc_good=$?
set -e
[[ "$rc_good" -eq 0 ]] || fail "Fall A sollte Exit 0 liefern, bekam $rc_good: $out_good"
python3 -c "import json,sys; json.load(open(sys.argv[1], encoding='utf-8'))" "$GOOD_FILE" \
  || fail "Fall A: json.load (Referenzimplementierung) schlug fehl — Testdatei selbst ungueltig"
log "Fall A ok — Exit 0, json.load erfolgreich"

# ---- Fall B (rot): gerades " innerhalb eines Werts bricht den JSON-String ---
log "Fall B: gerades \" innerhalb eines Werts -> validate-json.py erkennt den Fehler"
BAD_FILE="$SMOKE_DIR/kaputt.json"
# Absichtlich ein *ungeescaptes* gerades Anführungszeichen mitten im Wert, wie
# es beim Von-Hand-Zusammensetzen von JSON-Text in einem Shell-String entsteht
# (Bash-Quoting-Kollision, Ursache der drei gescheiterten Voranläufe).
cat >"$BAD_FILE" <<'JSON'
{
  "titel": "Test mit "kaputtem" geradem Anführungszeichen im Wert",
  "schritte": ["Schritt 1"],
  "pruefpunkte": ["Ergebnis 1"]
}
JSON

set +e
out_bad="$(python3 "$VALIDATOR" "$BAD_FILE" 2>&1)"
rc_bad=$?
set -e
[[ "$rc_bad" -ne 0 ]] || fail "Fall B haette einen Fehler-Exit-Code liefern muessen, bekam 0"
[[ "$rc_bad" -eq 3 ]] || fail "Fall B: erwarteter Exit-Code 3 (JSONDecodeError), bekam $rc_bad: $out_bad"
echo "$out_bad" | grep -qi "kein valides JSON" || fail "Fall B: erwartete Fehlermeldung fehlt: $out_bad"
log "Fall B ok — Exit $rc_bad, Fehlermeldung vorhanden (kein falsches Exit 0)"

# ---- Zusatz: fehlende Datei -> Exit 2 --------------------------------------
log "Zusatz: nicht existierende Datei -> Exit 2"
set +e
out_missing="$(python3 "$VALIDATOR" "$SMOKE_DIR/existiert-nicht.json" 2>&1)"
rc_missing=$?
set -e
[[ "$rc_missing" -eq 2 ]] || fail "erwarteter Exit-Code 2 bei fehlender Datei, bekam $rc_missing: $out_missing"
log "Zusatz ok — Exit 2 bei fehlender Datei"

# ---- Zusatz: falsche Argumentzahl -> Exit 1 --------------------------------
log "Zusatz: falsche Argumentzahl -> Exit 1"
set +e
out_argc="$(python3 "$VALIDATOR" 2>&1)"
rc_argc=$?
set -e
[[ "$rc_argc" -eq 1 ]] || fail "erwarteter Exit-Code 1 bei fehlendem Argument, bekam $rc_argc: $out_argc"
log "Zusatz ok — Exit 1 bei fehlender Argumentzahl"

log "ALL VERTRAEGE PASS"
echo "PASS"
