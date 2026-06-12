---
id: metrics-estimation
title: A-priori-Schätzung + Soll-Ist-Abrechnung (Forecast-Fehler)
status: approved
version: 1
---

# Spec: A-priori-Schätzung + Soll-Ist  (`metrics-estimation`)

> **Schicht 3 von 3.** Testbares **Verhalten + Verträge**, sprach-/paradigma-unabhängig (Intent, keine Idiome/Klassen).
> **Source of Truth** für `coder` (baut daraus), `tester` (testet die Acceptance-Kriterien), `reviewer` (prüft den Diff dagegen — hartes Drift-Gate).
>
> **Detailkonzept-Bindung.** Das Subsystem ist in `docs/architecture/metrics-subsystem.md` spezifiziert (bindend, §6). Diese Spec beschreibt die **Phase-2-Capability**: beim Item-Eintritt eine Grössenklasse heuristisch ableiten, daraus `ep_est` prognostizieren und beim Done gegen `ep_act` abrechnen. Sie setzt das Ledger (`metrics-ledger`) und eine `baseline.json` (`metrics-retro-aggregation`) voraus.

## Zweck

Ziel des Subsystems ist Vorhersagbarkeit: Soll vs. Ist gegenüberstellen. Diese Capability leitet beim Item-Eintritt eine A-priori-Grössenklasse **rein heuristisch** ab (token-sparsam, LLM nur bei L/XL als 1-Satz-Korrektur), mappt sie über `baseline.json` auf einen erwarteten Aufwand `ep_est`, und macht den **Forecast-Fehler** zur eigenen Systemmetrik (Prognosegüte, soll mit Datenmenge sinken).

## Kontext / Designnuancen (bindend)

- **Heuristik zuerst, LLM nur bei L/XL.** S/M laufen rein heuristisch (0 LLM-Token); nur gross eingestufte Items bekommen eine 1-Satz-Schätzkorrektur (bewusst entschieden, token-sparsam).
- **Baseline als Mapping-Quelle.** `size_est` → `ep_est` läuft über `baseline.json.medians`; ohne passenden Schnitt gröbere Aggregation, zuletzt globaler Median; ohne jede Baseline → `ep_est = null` (erwartet, bis genug Historie da ist).
- **Soll-Ist in einer Zeile.** `ep_est` und `ep_act` stehen in derselben `items.jsonl`-Zeile (das Feld existiert bereits aus `metrics-ledger`, hier wird es echt befüllt).

## Verhalten

### V1 — Grössenklasse heuristisch (token-frei)
Beim Item-Eintritt leitet `/flow` `S` | `M` | `L` | `XL` ab aus: (a) #Acceptance-Kriterien der referenzierten Spec, (b) Labels (`db`, `security`, `ui` gewichten hoch), (c) #genannter Komponenten/Dateien im Item-Body. Die Schwellen sind deterministisch fixiert: **Score = n_ac + n_comp + label_bump** (label_bump: +1 je Label `db`/`security`/`ui`, max +3). Mapping: Score 0–3 → `S`, 4–7 → `M`, 8–12 → `L`, ≥ 13 → `XL`. S/M/L/XL ist token-frei bestimmbar.

### V2 — LLM-Korrektur nur bei L/XL
Wird ein Item heuristisch als `L` oder `XL` eingestuft, holt `/flow` eine **1-Satz**-Plausibilitätskorrektur per LLM (token-sparsam) und passt `size_est` ggf. an. `S`/`M` laufen ohne LLM.

### V3 — Mapping size_est → ep_est
`size_est` mappt über `baseline.json.medians[<lang>|<cost_mode>|<size>]` auf `ep_est` (+ erwartete `iters`/`crit` zur Information). Fehlt der Schnitt → gröbere Aggregation, zuletzt globaler Median. Existiert keine `baseline.json` → `ep_est = null`.

### V4 — Soll-Ist in items.jsonl
Beim Done schreibt `/flow` `ep_est` neben `ep_act` in dieselbe `items.jsonl`-Zeile (Felder aus `metrics-ledger` jetzt echt befüllt statt `null`/Default).

### V5 — Forecast-Fehler als Systemmetrik
Der Forecast-Fehler `|ep_est − ep_act| / ep_act` wird je Item berechnet; sein gleitender Mittelwert wird als `baseline.json.forecast_mae` von `retro` mitgeführt (Prognosegüte-Tracker, soll mit Datenmenge sinken). `ep_est = null` (keine Baseline) zählt nicht in den Fehler.

### V6 — Token-/Loop-Schonung
Die Schätzung blockiert nie den Loop; bei fehlender Baseline oder unklarer Heuristik fällt `ep_est` sauber auf `null` (subsystem §10 K3). Die einzige LLM-Ausgabe ist die optionale 1-Satz-L/XL-Korrektur.

## Acceptance-Kriterien

- **AC1** — `/flow` leitet beim Item-Eintritt `size_est` ∈ {S,M,L,XL} deterministisch aus #AC + Labels (`db`/`security`/`ui`) + #Komponenten ab; Schwellen sind fixiert (Score = n_ac + n_comp + label_bump: 0–3→S, 4–7→M, 8–12→L, ≥13→XL); S/M/L/XL token-frei. *(V1)*
- **AC2** — Nur für `L`/`XL` wird eine 1-Satz-LLM-Korrektur geholt; `S`/`M` laufen ohne LLM. *(V2)*
- **AC3** — `ep_est` wird über `baseline.json.medians[<lang>|<cost_mode>|<size>]` gemappt; fehlender Schnitt → gröbere Aggregation → globaler Median; keine Baseline → `ep_est = null`. *(V3)*
- **AC4** — Beim Done steht `ep_est` neben `ep_act` in derselben `items.jsonl`-Zeile. *(V4)*
- **AC5** — Der Forecast-Fehler `|ep_est − ep_act| / ep_act` wird je Item berechnet und als gleitender `forecast_mae` in `baseline.json` mitgeführt; `null`-Schätzungen zählen nicht. *(V5)*
- **AC6** — Die Schätzung blockiert nie den Loop; fehlende Baseline/unklare Heuristik → `ep_est = null`; einzige LLM-Ausgabe ist die L/XL-1-Satz-Korrektur. *(V6, K3)*

## Nicht-Ziele

- Ledger-Schema/EP-Formel (`metrics-ledger`).
- Token-Befüllung (`metrics-token-collect`).
- baseline.json-Aggregation/Kalibrierung (`metrics-retro-aggregation`).
- Defektraten/LEARNINGS-Lebenszyklus (`metrics-retro-effectiveness`).
