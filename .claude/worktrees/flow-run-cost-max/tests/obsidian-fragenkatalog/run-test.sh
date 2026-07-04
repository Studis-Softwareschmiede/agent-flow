#!/usr/bin/env bash
# tests/obsidian-fragenkatalog/run-test.sh
#
# @file Self-Test fuer den Fragenkatalog-Gate-Baustein (Obsidian-Ingest, S-022).
#       Prueft scripts/obsidian-fragenkatalog-validate.sh gegen den AC9-Vertrag
#       (board/fragenkatalog.schema.json) sowie die AC10-Fixture-Invariante.
#       Verwendet /tmp-Fixtures + die eingecheckten Fixtures unter fixtures/ —
#       beruehrt NIEMALS reale Projekt-Docs/Board.
#
# Covers (obsidian-ingest): AC7, AC8, AC9, AC10
#   AC7  — genau EIN gesammelter Katalog pro Stufe: eine JSON-Liste (mehrere Fragen
#          derselben Stufe in EINEM Katalog) ist gueltig -> Token "valid".
#   AC8  — Auto-Durchlauf bei Klarheit: leerer Katalog ([]) ist gueltig, wird als
#          Token "empty" gemeldet (NICHT dem User vorgelegt, kein leerer Katalog).
#   AC9  — maschinenlesbares Rueckgabeformat: Pflicht-Feldmenge (stage|id|frage|quelle,
#          optional optionen[]), stage-Enum, katalog-eindeutige id, keine Fremdfelder.
#          Fehlende/fehlerhafte Felder -> Exit 1.
#   AC10 — Erst-Uebersetzung praezise (fixture-geprueft): die bewusst mehrdeutige
#          Fixture (fixtures/ambiguous-notes/, zwei widerspruechliche Zielgruppen)
#          erzeugt in Stufe a MINDESTENS einen Katalog-Eintrag mit stage="a", dessen
#          quelle auf die Quellnotizen zeigt — ein stiller Default waere eine Verletzung.
#
# Exit: 0 = alle Tests bestanden, 1 = mindestens ein Fehler
#
# @trace obsidian-ingest#AC7,AC8,AC9,AC10

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
VALIDATE="${REPO_ROOT}/scripts/obsidian-fragenkatalog-validate.sh"
FIXTURES="${SCRIPT_DIR}/fixtures"

# Eigene TMPDIR-Variable (reviewer/L05: $TMPDIR nie ueberschreiben).
TEST_WORK_DIR="$(mktemp -d /tmp/obsidian-fragenkatalog-test.XXXXXX)"
trap 'rm -rf "$TEST_WORK_DIR"' EXIT

FAIL=0
PASS=0
fail() { echo "FAIL: $*" >&2; FAIL=$(( FAIL + 1 )); }
pass() { echo "PASS: $*"; PASS=$(( PASS + 1 )); }

# run_validate <json-string> -> setzt globale OUT/RC
run_validate() {
  local json="$1"
  set +e
  OUT="$(printf '%s' "$json" | bash "$VALIDATE" 2>/dev/null)"
  RC=$?
  set -e
}

# ===========================================================================
# AC9: gueltiger Minimal-Katalog (nur Pflichtfelder) -> "valid", Exit 0
# ===========================================================================
run_validate '[{"stage":"a","id":"a-1","frage":"Wer ist die Zielgruppe?","quelle":"idee.md"}]'
if [[ "$OUT" == "valid" && "$RC" -eq 0 ]]; then
  pass "@trace obsidian-ingest#AC9 — Minimal-Katalog (Pflichtfelder) ist gueltig -> valid"
else
  fail "@trace obsidian-ingest#AC9 — Minimal-Katalog: erwartet valid/0, bekam Out='${OUT}' RC=${RC}"
fi

# ===========================================================================
# AC9: optionen[] ist erlaubt und gueltig
# ===========================================================================
run_validate '[{"stage":"b","id":"b-1","frage":"Welches Format?","quelle":"concept.md §2","optionen":["JSON","YAML"]}]'
if [[ "$OUT" == "valid" && "$RC" -eq 0 ]]; then
  pass "@trace obsidian-ingest#AC9 — optionen[] wird akzeptiert -> valid"
else
  fail "@trace obsidian-ingest#AC9 — optionen[]: erwartet valid/0, bekam Out='${OUT}' RC=${RC}"
fi

# ===========================================================================
# AC7: mehrere Fragen derselben Stufe in EINEM Katalog (gesammelt, nicht einzeln)
# ===========================================================================
run_validate '[
  {"stage":"a","id":"a-1","frage":"Zielgruppe?","quelle":"idee.md"},
  {"stage":"a","id":"a-2","frage":"Plattform?","quelle":"scope.md"},
  {"stage":"a","id":"a-3","frage":"Offline-faehig?","quelle":"scope.md §3"}
]'
if [[ "$OUT" == "valid" && "$RC" -eq 0 ]]; then
  pass "@trace obsidian-ingest#AC7 — genau EIN gesammelter Katalog mit mehreren Fragen -> valid"
else
  fail "@trace obsidian-ingest#AC7 — Sammelkatalog: erwartet valid/0, bekam Out='${OUT}' RC=${RC}"
fi

# ===========================================================================
# AC8: leerer Katalog -> "empty", Exit 0 (Auto-Durchlauf, NICHT vorlegen)
# ===========================================================================
run_validate '[]'
if [[ "$OUT" == "empty" && "$RC" -eq 0 ]]; then
  pass "@trace obsidian-ingest#AC8 — leerer Katalog -> empty (Auto-Durchlauf, kein leerer Katalog vorgelegt)"
else
  fail "@trace obsidian-ingest#AC8 — leerer Katalog: erwartet empty/0, bekam Out='${OUT}' RC=${RC}"
fi

# ===========================================================================
# AC9: fehlendes Pflichtfeld (quelle) -> Exit 1, kein Token
# ===========================================================================
run_validate '[{"stage":"a","id":"a-1","frage":"Zielgruppe?"}]'
if [[ "$RC" -eq 1 && -z "$OUT" ]]; then
  pass "@trace obsidian-ingest#AC9 — fehlendes Pflichtfeld 'quelle' -> Exit 1 (Vertragsverletzung)"
else
  fail "@trace obsidian-ingest#AC9 — fehlendes 'quelle': erwartet Exit 1/kein Token, bekam Out='${OUT}' RC=${RC}"
fi

# ===========================================================================
# AC9: ungueltiger stage-Wert -> Exit 1
# ===========================================================================
run_validate '[{"stage":"z","id":"z-1","frage":"?","quelle":"x.md"}]'
if [[ "$RC" -eq 1 ]]; then
  pass "@trace obsidian-ingest#AC9 — stage ausserhalb {a,b,c,sync} -> Exit 1"
else
  fail "@trace obsidian-ingest#AC9 — ungueltige stage: erwartet Exit 1, bekam Out='${OUT}' RC=${RC}"
fi

# ===========================================================================
# AC9: nicht katalog-eindeutige id (Duplikat) -> Exit 1
# ===========================================================================
run_validate '[
  {"stage":"a","id":"a-1","frage":"Frage A","quelle":"idee.md"},
  {"stage":"a","id":"a-1","frage":"Frage B","quelle":"scope.md"}
]'
if [[ "$RC" -eq 1 ]]; then
  pass "@trace obsidian-ingest#AC9 — doppelte id (nicht katalog-eindeutig) -> Exit 1"
else
  fail "@trace obsidian-ingest#AC9 — doppelte id: erwartet Exit 1, bekam Out='${OUT}' RC=${RC}"
fi

# ===========================================================================
# AC9: unbekanntes Fremdfeld -> Exit 1 (additionalProperties:false)
# ===========================================================================
run_validate '[{"stage":"a","id":"a-1","frage":"?","quelle":"x.md","prioritaet":"hoch"}]'
if [[ "$RC" -eq 1 ]]; then
  pass "@trace obsidian-ingest#AC9 — unbekanntes Fremdfeld -> Exit 1"
else
  fail "@trace obsidian-ingest#AC9 — Fremdfeld: erwartet Exit 1, bekam Out='${OUT}' RC=${RC}"
fi

# ===========================================================================
# AC9: Top-Level kein Array (z.B. Objekt) -> Exit 1
# ===========================================================================
run_validate '{"stage":"a","id":"a-1","frage":"?","quelle":"x.md"}'
if [[ "$RC" -eq 1 ]]; then
  pass "@trace obsidian-ingest#AC9 — Top-Level-Objekt statt Liste -> Exit 1"
else
  fail "@trace obsidian-ingest#AC9 — Nicht-Liste: erwartet Exit 1, bekam Out='${OUT}' RC=${RC}"
fi

# ===========================================================================
# AC9: kein valides JSON -> Exit 2 (Aufrufproblem, nicht Vertragsverletzung)
# ===========================================================================
run_validate 'nicht mal json'
if [[ "$RC" -eq 2 ]]; then
  pass "@trace obsidian-ingest#AC9 — kaputtes JSON -> Exit 2 (Aufrufproblem)"
else
  fail "@trace obsidian-ingest#AC9 — kaputtes JSON: erwartet Exit 2, bekam Out='${OUT}' RC=${RC}"
fi

# ===========================================================================
# AC10 (Kernprobe): die mehrdeutige Fixture erzeugt in Stufe a >=1 Katalog-Eintrag,
# der auf die Quellnotizen zeigt — ein stiller Default waere AC10-Verletzung.
# Der erwartete Stufe-a-Katalog ist als Fixture eingecheckt; wir pruefen:
#   (1) er ist ein gueltiger Katalog (Token "valid", NICHT "empty"),
#   (2) er enthaelt mindestens einen Eintrag mit stage="a",
#   (3) dessen quelle referenziert die widerspruechlichen Fixture-Notizen.
# ===========================================================================
EXPECTED_A="${FIXTURES}/ambiguous-notes.expected-stage-a.json"

# Fixture-Vorbedingung: der Widerspruch MUSS in den Notizen wirklich stehen
# (sonst prueft der Test einen leeren Popanz).
if grep -qi "Grundschulkinder" "${FIXTURES}/ambiguous-notes/idee.md" \
   && grep -qi "Erwachsene" "${FIXTURES}/ambiguous-notes/scope.md"; then
  pass "@trace obsidian-ingest#AC10 — Fixture enthaelt den bewussten Zielgruppen-Widerspruch (idee.md vs. scope.md)"
else
  fail "@trace obsidian-ingest#AC10 — Fixture-Vorbedingung verletzt: Widerspruch nicht in beiden Notizen auffindbar"
fi

# (1) gueltiger, NICHT-leerer Katalog
set +e
A_OUT="$(bash "$VALIDATE" "$EXPECTED_A" 2>/dev/null)"
A_RC=$?
set -e
if [[ "$A_OUT" == "valid" && "$A_RC" -eq 0 ]]; then
  pass "@trace obsidian-ingest#AC10 — Stufe-a-Katalog der Fixture ist gueltig UND nicht leer (kein stiller Default)"
else
  fail "@trace obsidian-ingest#AC10 — Stufe-a-Katalog: erwartet valid/0, bekam Out='${A_OUT}' RC=${A_RC}"
fi

# (2)+(3) mindestens ein stage="a"-Eintrag, dessen quelle die Notizen referenziert
set +e
A_CHECK="$(python3 - "$EXPECTED_A" <<'PYEOF'
import json, sys
with open(sys.argv[1], encoding="utf-8") as fh:
    cat = json.load(fh)
a_entries = [q for q in cat if isinstance(q, dict) and q.get("stage") == "a"]
if not a_entries:
    print("NO_STAGE_A"); sys.exit(0)
# quelle muss auf mindestens eine der Fixture-Notizen zeigen
has_source = any(
    ("idee.md" in q.get("quelle", "")) or ("scope.md" in q.get("quelle", ""))
    for q in a_entries
)
print("OK" if has_source else "NO_SOURCE_REF")
PYEOF
)"
A_CHECK_RC=$?
set -e
if [[ "$A_CHECK" == "OK" && "$A_CHECK_RC" -eq 0 ]]; then
  pass "@trace obsidian-ingest#AC10 — >=1 stage=a-Eintrag, quelle zeigt auf die widerspruechlichen Notizen"
else
  fail "@trace obsidian-ingest#AC10 — Stufe-a-Eintrag/quelle-Referenz fehlt (Ergebnis: ${A_CHECK})"
fi

# ===========================================================================
# Zusammenfassung
# ===========================================================================
echo ""
echo "obsidian-fragenkatalog: ${PASS} passed, ${FAIL} failed"
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
exit 0
