---
id: metrics-retro-effectiveness
title: Retro-Effektivität messen (Defektrate je Regel-ID, LEARNINGS quantitativ)
status: approved
version: 1
---

# Spec: Retro-Effektivität messen  (`metrics-retro-effectiveness`)

> **Schicht 3 von 3.** Testbares **Verhalten + Verträge**, sprach-/paradigma-unabhängig (Intent, keine Idiome/Klassen).
> **Source of Truth** für `coder` (baut daraus), `tester` (testet die Acceptance-Kriterien), `reviewer` (prüft den Diff dagegen — hartes Drift-Gate).
>
> **Detailkonzept-Bindung.** Das Subsystem ist in `docs/architecture/metrics-subsystem.md` spezifiziert (bindend, §8). Diese Spec beschreibt die **Phase-3-Capability** (der Clou): die `rule_hits` im Ledger ergeben eine Defektrate je Regel-ID, die `LEARNINGS.md`-Status `Measuring → Validated | Reverted` quantitativ macht. Sie setzt das Ledger (`metrics-ledger`) und die retro-Aggregation (`metrics-retro-aggregation`) voraus.

## Zweck

CONCEPT §5a fragt: *„kehrt der adressierte Fehler weiter wieder?"* — bisher qualitativ beantwortet. Weil `reviewer`/`dba` jeden Befund mit Regel-ID taggen und diese `rule_hits` nun im Ledger landen, ist die **Defektrate je Regel-ID** (Treffer pro 100 EP) über die Zeit gratis auswertbar. Damit wird der `LEARNINGS.md`-Lebenszyklus `Measuring → Validated | Reverted` **quantitativ** statt nach Bauchgefühl — und die Gesamt-Effektivität von `retro`/`train` belegbar.

## Kontext / Designnuancen (bindend)

- **Gratis-Datenquelle.** Die `rule_hits` werden bereits von `metrics-ledger` geschrieben; diese Capability wertet sie nur aus (im seltenen retro-Lauf, auf Zahlen, kein Pro-Item-Aufwand).
- **Defektrate = Treffer pro 100 EP.** Normiert auf den Aufwand (EP), nicht auf rohe Item-Zahl — so vergleichbar über unterschiedlich grosse Sprints.
- **Tier-1-Anschluss.** Tier 1 (LEARNINGS-Ledger, Regel-ID-Tagging) bleibt unverändert und ist die Eingangs-Datenquelle; diese Spec fügt die quantitative Auswertung hinzu.
- **Schutzgitter unverändert.** Läuft im retro-Mess-Schritt; Cooldown (G3) + PR+Gate-Mechanik bleiben.

## Verhalten

### V1 — Defektrate je Regel-ID
`retro` berechnet aus den `rule_hits` der Ledger die Defektrate je Regel-ID = `(Σ Treffer der ID) / (Σ EP) × 100` (Treffer pro 100 EP), je definierbarem Zeit-/Item-Fenster.

### V2 — Baseline beim Promoten festhalten
Beim Promoten einer Regel (Status `Measuring`) hält `retro` die **Baseline-Defektrate** der adressierten Regel-ID fest (als Zahl in `LEARNINGS.md` bzw. dem Improvement-Board-Eintrag).

### V3 — Validated/Reverted quantitativ
Nach **N** weiteren Items (N_MIN = 10 Items, Mindest-Stichprobe) misst `retro` die neue Rate: signifikant gesunken (neue Rate < Baseline × 0.5, d.h. > 50% Reduktion) → Status `Validated` **mit Zahl** (z.B. „`coder/R01`: 4.2 → 0.8 Treffer/100 EP über 30 Items"); kein Effekt/schlechter (Rate ≥ Baseline × 0.5) → `Reverted` (`git revert`), die Zahl ist die Begründung. < N_MIN Items seit Promotion → kein Statuswechsel (AC6).

### V4 — Gesamt-Effektivität
`retro` aggregiert die EP-/Defekt-Reduktion über alle `Validated` minus dem Schaden der `Reverted` zu einer Gesamt-Retro-Effektivitäts-Kennzahl (Teil des retro-Mess-Outputs).

### V5 — Tier-1 unverändert + Schutzgitter
Die Auswertung läuft im retro-Mess-Schritt (Modus D, nach Modus C), ohne Tier-1-Verhalten, Cooldown (G3) oder PR+Gate-Mechanik zu verändern. `agents/retro.md` wird um Modus D erweitert.

### V6a — LEARNINGS.md-Format (Präzisierung)
Das erweiterte Status-Feld-Suffix: `Measuring · baseline=<rate>/100EP@N<n>` → `Validated · <baseline> → <new>/100EP über N Items` bzw. `Reverted · <baseline> → <new>/100EP über N Items`. Bestehende Spalten (`ID | Datum | Pack/Skill | Regel | Quelle | PR | Status`) bleiben unverändert. Das Suffix ist rückwärtskompatibel.

### V6b — `baseline.json`-Erweiterung (Präzisierung)
`metrics-aggregate.sh` gibt zusätzlich aus:
- `defect_rates` — Objekt: Regel-ID → `{ hits, ep_total, rate_per_100ep, n_items, window_items }` (AC1)
- `retro_effectiveness` — Kennzahl (Zahl oder null) (AC4)
- `learnings_rules` — Array von `{ rule_id, status, baseline_rate, baseline_n, promoted_after_item, measured_rate, measured_n }` — persistent über Läufe (von retro Modus D befüllt/aktualisiert)

### V6 — Datenmangel-Toleranz
Fehlen `rule_hits` oder ist die Item-Zahl seit Promotion < N, bleibt der Status `Measuring` (keine voreilige Promotion/Revert); kein Abbruch.

## Acceptance-Kriterien

- **AC1** — `retro` berechnet die Defektrate je Regel-ID als Treffer pro 100 EP aus den `rule_hits` der Ledger, je Zeit-/Item-Fenster. *(V1)*
- **AC2** — Beim Promoten (`Measuring`) wird die Baseline-Defektrate der Regel-ID als Zahl festgehalten (LEARNINGS/Board). *(V2)*
- **AC3** — Nach N Items entscheidet die gemessene Rate quantitativ über `Validated` (mit Zahl) bzw. `Reverted` (Zahl als Begründung, `git revert`). *(V3)*
- **AC4** — `retro` aggregiert eine Gesamt-Retro-Effektivitäts-Kennzahl (Σ Reduktion `Validated` − Schaden `Reverted`) als Teil des Mess-Outputs. *(V4)*
- **AC5** — Die Auswertung erweitert `agents/retro.md`, ohne Tier-1-Verhalten, Cooldown (G3) oder PR+Gate-Mechanik zu verändern. *(V5)*
- **AC6** — Fehlende `rule_hits` oder < N Items seit Promotion → Status bleibt `Measuring`; keine voreilige Promotion/Revert; kein Abbruch. *(V6)*

## Nicht-Ziele

- Ledger-Erfassung/EP-Formel (`metrics-ledger`).
- Token-Befüllung (`metrics-token-collect`).
- baseline.json-Aggregation/Kalibrierung (`metrics-retro-aggregation`).
- A-priori-Schätzung/Forecast (`metrics-estimation`).
