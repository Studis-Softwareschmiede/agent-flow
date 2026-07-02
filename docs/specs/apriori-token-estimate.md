---
id: apriori-token-estimate
title: Token-Erwartung bei Story-Anlage (requirement) — Schätzspalte nie leer
status: active
version: 1
spec_format: use-case-2.0
---

# Spec: Token-Erwartung bei Story-Anlage  (`apriori-token-estimate`)

> **Schicht 3 von 3.** Testbares **Verhalten + Verträge**, sprach-/paradigma-unabhängig (Intent, keine Idiome/Klassen).
> **Source of Truth** für `coder` (baut daraus), `tester` (testet die Acceptance-Kriterien + Coverage-Gate), `reviewer` (prüft den Diff dagegen — hartes Drift-Gate).

## Zweck
Die dev-gui-Detailansicht zeigt „Tokens: keine Schätzung", weil nur der estimator (L/XL-Stories ohne Vorab-Schätzung) eine Token-Erwartung liefert — der requirement-Agent schätzt bei der Anlage aber nur `size_est`/`dispo_est` und wird für S/M nie durch den estimator ergänzt. Owner-Ziel (2026-07-02): Die Schätzspalte ist nie systematisch leer; jede angelegte Story trägt eine A-priori-Token-Erwartung aus der Baseline.

## Acceptance-Kriterien

- **AC1** — `agents/requirement.md`: Beim Anlegen jeder Story setzt requirement zusätzlich `tok_est` (erwartete Gesamt-Tokens des Flow-Durchlaufs) aus der Projekt-Baseline: Lookup `medians["<lang>|<cost_mode>|<size_est>"].tok` in `.claude/metrics/baseline.json`; fehlt der exakte Schnitt, Aggregation über `<lang>|<cost_mode>` (Median), fehlt auch das: `tok_est: null` MIT `estimate_note`-Ergänzung „keine Baseline-Tokens".
- **AC2** — Board-Schema (`docs/specs/board-schema.md` + Story-Vorlage/Anlage-Pfad): Das Story-Feld `tok_est` ist als optionales Feld dokumentiert (Typ: Ganzzahl | null; Semantik: erwartete Gesamt-Tokens It-Durchlauf).
- **AC3** — `estimator` (L/XL-Pfad) bleibt unverändert maßgeblich, WENN er läuft: Sein Token-Erwartungswert überschreibt den requirement-A-priori-Wert (Präzedenz estimator > requirement-Baseline-Lookup); das ist an der estimator-Übernahme-Stelle in `skills/flow/SKILL.md` §1a dokumentiert.
- **AC4** — `/flow` „Beim Done" (§2b): Die `items.jsonl`-Zeile übernimmt `tok_est` aus der Story-YAML (Feld `tok_est`, null-sicher) — damit können dev-gui-Detailansicht und Retro-Kalibrierung Soll/Ist der Tokens vergleichen, sobald `tok_total` (Ist) erfasst ist.
- **AC5** — Rückwärtskompatibilität: Bestehende Stories ohne `tok_est` bleiben gültig (Lint meldet nichts; Aggregator/GUI zeigen weiterhin „keine Schätzung").

## Verträge
- **`tok_est`:** Ganzzahl (Tokens) oder null; A-priori-Wert, Herkunft in `estimate_note` einzeilig vermerkt („tok_est aus baseline <key>").
- **Präzedenz:** estimator-Wert > requirement-Baseline-Lookup > null.

## Edge-Cases & Fehlerverhalten
- **E1:** Projekt ohne `baseline.json` (frisches Repo) → `tok_est: null` + Vermerk, kein Fehler.
- **E2:** Baseline vorhanden, aber ohne `tok`-Werte (alle Ist-Tokens null — heutiger Zustand vor `[[metrics-repo-anchor]]`) → wie E1 behandeln.

## NFRs
- Reine Agent-/Skill-/Doku-Textänderung; Lookup ist deterministisch, keine zusätzlichen LLM-Aufrufe.

## Nicht-Ziele
- Keine Ist-Token-Erfassung (das leistet `[[metrics-repo-anchor]]` AC3).
- Keine estimator-Pflicht für S/M-Stories.
- Keine dev-gui-Änderung (die Anzeige liest vorhandene Felder; leere Werte bleiben zulässig).

## Abhängigkeiten
- `[[metrics-repo-anchor]]` (liefert künftig echte `tok_total`-Ist-Werte, aus denen die Baseline `tok`-Mediane lernt — ohne sie bleibt AC1 praktisch bei E2).
- `[[estimator]]`, `[[board-schema]]`.
