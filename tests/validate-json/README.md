# `tests/validate-json/` — Mechanik-Smoke-Test von `scripts/validate-json.py`

Smoke-Test für den JSON-Selbstvalidierungs-Helfer (Spec
[`docs/specs/regression-define.md`](../../docs/specs/regression-define.md) AC13,
Helferdatei `scripts/validate-json.py`), der die per `ergebnis_datei=`
geschriebene Datei nach dem Schreiben gegen einen echten JSON-Parser prüft.

Beweist den PFLICHT-Testfall der Story S-061: ein Ergebnis-Objekt mit
**typografischen** Anführungszeichen in `schritte`/`pruefpunkte` ergibt valides
JSON (`json.load` erfolgreich); ein Wert mit einem **geraden** `"` (der
Escaping-Bug der drei gescheiterten Voranläufe) wird zuverlässig als
ungültiges JSON erkannt statt fälschlich als Exit 0 durchzugehen.

## `smoke.sh`

| Fall | Was wird verifiziert |
|---|---|
| **Fall A (grün)** | Ergebnis-Objekt mit typografischen Anführungszeichen (`„…"`, `‚…'`) in `titel`/`schritte`/`pruefpunkte`/`beispieldaten` → `validate-json.py` liefert Exit 0; `json.load` (Referenzimplementierung) bestätigt die Validität unabhängig. |
| **Fall B (rot)** | Ein Wert enthält ein ungeescaptes gerades `"` mitten im Text (bricht den JSON-String) → `validate-json.py` liefert Exit 3 (`JSONDecodeError`) mit Fehlermeldung auf stderr — kein falsches Exit 0. |
| Zusatz | Fehlende Datei → Exit 2; falsche Argumentzahl → Exit 1. |

Aufruf: `bash tests/validate-json/smoke.sh` (keine Abhängigkeiten außer `python3`).
