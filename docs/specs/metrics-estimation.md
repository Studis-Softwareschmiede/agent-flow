---
id: metrics-estimation
title: A-priori-Schätzung + Soll-Ist-Abrechnung (Forecast-Fehler)
status: active
version: 2
---

# Spec: A-priori-Schätzung + Soll-Ist  (`metrics-estimation`)

> **Schicht 3 von 3.** Testbares **Verhalten + Verträge**, sprach-/paradigma-unabhängig (Intent, keine Idiome/Klassen).
> **Source of Truth** für `coder` (baut daraus), `tester` (testet die Acceptance-Kriterien), `reviewer` (prüft den Diff dagegen — hartes Drift-Gate).
>
> **Detailkonzept-Bindung.** Das Subsystem ist in `docs/architecture/metrics-subsystem.md` spezifiziert (bindend, §6). Diese Spec beschreibt die **Phase-2-Capability**: beim Item-Eintritt eine Grössenklasse heuristisch ableiten, daraus `ep_est` prognostizieren und beim Done gegen `ep_act` abrechnen. Sie setzt das Ledger (`metrics-ledger`) und eine `baseline.json` (`metrics-retro-aggregation`) voraus.
>
> **Version 2 — Schätzung zur Planungszeit (F-002).** Ab v2 entsteht die A-priori-Schätzung (`size_est` + `dispo_est`/`ep_est` + `confidence` + `estimate_note`) **beim Anlegen** einer Story durch den **requirement**-Agenten und steht ab Geburt in der Story-YAML — nicht mehr erst zur Ausführungszeit in `/flow` §1a. `/flow` wird dadurch vom **Produzenten** zum **Konsumenten** der Schätzung (V7–V10 unten); die heutige §1a-Heuristik bleibt als **Fallback** für Alt-/manuell angelegte Stories ohne Schätzfelder erhalten. AC1–AC6 (v1) bleiben unverändert gültig — sie beschreiben jetzt die **Heuristik/Mapping-Mechanik selbst**, unabhängig davon, *wer* sie ausführt (requirement bei Anlage **oder** /flow als Fallback). Die **Quellen-Trennung Soll/Ist** wird in v2 explizit gemacht: Soll = Story-YAML (von requirement), Ist = Ledger `items.jsonl` (ausschliesslich von /flow).

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

### V7 — requirement schätzt bei Story-Anlage (Produzent)  *(v2)*
Beim **Anlegen** jeder Story wendet der **requirement**-Agent die size_est-Heuristik aus V1 an (gleiche Eingaben `n_ac`/`n_comp`/`label_bump`, gleiche fixierten Schwellen). Daraus:
- **`L`/`XL`:** requirement dispatcht den `estimator` (Spec [[estimator]] V1/V3) → `dispo_est` (EP) + `confidence` + `estimate_note`.
- **`S`/`M`:** kein estimator (Token-Disziplin); requirement bestimmt `ep_est` per `baseline.json.medians`-Lookup (identische Lookup-Reihenfolge wie V3: exakter Schnitt → gröbere Aggregation → globaler Median → `null`) und setzt daraus `dispo_est`.

requirement schreibt `size_est`, `dispo_est`, `confidence`, `estimate_note` in die Story-YAML (`board/stories/<id>.yaml`) — bei Anlage, vor dem ersten `/flow`-Lauf. requirement schreibt **nie** ins Ledger (`items.jsonl`). Jeder Fehlerpfad fällt sauber zurück (`size_est="M"`, `dispo_est=null`, K3) und blockiert die Story-Anlage nicht.

### V8 — /flow liest die Schätzung (Konsument) + Fallback  *(v2)*
Zum Ausführungszeitpunkt liest `/flow` §1a die bei Anlage gesetzten Felder aus der Story-YAML.
- **Felder vorhanden** (mind. `size_est` gesetzt): `/flow` **übernimmt** sie unverändert und **überschreibt eine vorhandene requirement-Schätzung nicht** (kein erneuter estimator-Dispatch, keine Neuberechnung). `ep_est` für das Ledger wird aus `dispo_est` (L/XL) bzw. dem vorhandenen Story-Wert (S/M) übernommen.
- **Felder fehlen** (Alt-Story / manuell angelegtes Item ohne Schätzfelder): `/flow` fällt auf die **bestehende §1a-Heuristik** (V1–V3) zurück und schätzt selbst — voll rückwärtskompatibel, kein Bruch.

### V9 — Quellen-Trennung Soll/Ist (Single-Writer)  *(v2)*
- **Soll/Schätzung** = Story-YAML (`size_est`, `dispo_est`, `confidence`, `estimate_note`) → einziger Schreiber bei Anlage ist **requirement**; `/flow` liest sie (V8) und schreibt sie nur, wenn sie fehlen (Fallback).
- **Ist** = Ledger `items.jsonl` (`ep_act`, `tok_total`, sowie `ep_est` als Soll-Spiegel der Soll-Ist-Zeile) → ausschliesslich **`/flow`** beim Done (V4 unverändert). requirement berührt das Ledger nie. Das bestehende Single-Writer-Prinzip der Metrik-Ledger ([[metrics-ledger]] / metrics-subsystem K2) bleibt unangetastet.

### V10 — Done unverändert (Ist + Spiegelung)  *(v2)*
Beim Done schreibt `/flow` weiterhin die Ist-Werte ins Ledger (V4) und spiegelt `dispo_act`/`dispo_forecast` in die Story-YAML (board-subsystem §4.4). `dispo_forecast` entsteht erst hier (braucht `ep_act`) — **nicht** bei Anlage. Die requirement-Schätzfelder bleiben dabei als A-priori-Soll erhalten.

> **Verwandt (Repo-übergreifend, nicht in Scope):** Die dev-gui-Story **S-144** zeigt Soll aus der Story-YAML und Ist aus dem Ledger nebeneinander — die GUI-Hälfte derselben Idee. Hier nur als Querverweis genannt, nicht implementiert.

## Acceptance-Kriterien

- **AC1** — `/flow` leitet beim Item-Eintritt `size_est` ∈ {S,M,L,XL} deterministisch aus #AC + Labels (`db`/`security`/`ui`) + #Komponenten ab; Schwellen sind fixiert (Score = n_ac + n_comp + label_bump: 0–3→S, 4–7→M, 8–12→L, ≥13→XL); S/M/L/XL token-frei. *(V1)*
- **AC2** — Nur für `L`/`XL` wird eine 1-Satz-LLM-Korrektur geholt; `S`/`M` laufen ohne LLM. *(V2)*
- **AC3** — `ep_est` wird über `baseline.json.medians[<lang>|<cost_mode>|<size>]` gemappt; fehlender Schnitt → gröbere Aggregation → globaler Median; keine Baseline → `ep_est = null`. *(V3)*
- **AC4** — Beim Done steht `ep_est` neben `ep_act` in derselben `items.jsonl`-Zeile. *(V4)*
- **AC5** — Der Forecast-Fehler `|ep_est − ep_act| / ep_act` wird je Item berechnet und als gleitender `forecast_mae` in `baseline.json` mitgeführt; `null`-Schätzungen zählen nicht. *(V5)*
- **AC6** — Die Schätzung blockiert nie den Loop; fehlende Baseline/unklare Heuristik → `ep_est = null`; einzige LLM-Ausgabe ist die L/XL-1-Satz-Korrektur. *(V6, K3)*

> **Hinweis zu AC1–AC6 (v2):** Diese ACs beschreiben die **Heuristik-/Mapping-Mechanik** (Schwellen, Lookup, L/XL-Sonderweg, Loop-Schonung). Wer sie ausführt, regeln AC7–AC10: ab v2 ist das primär **requirement** bei Story-Anlage (AC7); `/flow` führt sie nur noch im **Fallback** aus (AC8). Wo AC1–AC6 „`/flow`" als Akteur nennen, gilt das ab v2 als „der schätzende Akteur (requirement bei Anlage, /flow als Fallback)".

- **AC7** — Der **requirement**-Agent führt die A-priori-Schätzung **bei Story-Anlage** durch und schreibt `size_est`, `dispo_est`, `confidence`, `estimate_note` in die Story-YAML. Heuristik/Schwellen wie AC1; `L`/`XL` → estimator-Dispatch ([[estimator]]); `S`/`M` → `ep_est`-Lookup über `baseline.json` (Reihenfolge wie AC3), **kein** estimator. Fehlerpfad → `size_est="M"`, `dispo_est=null`, Anlage wird nicht blockiert. *Prüfbar:* eine neu von requirement angelegte Story trägt vor dem ersten `/flow`-Lauf nicht-leere Schätzfelder (bzw. dokumentierten `null`-Fallback); für `S`/`M` wurde **kein** estimator dispatcht. *(V7)*
- **AC8** — `/flow` §1a **liest** die Schätzfelder aus der Story-YAML und übernimmt sie **unverändert**, wenn `size_est` gesetzt ist (kein erneuter estimator-Dispatch, keine Neuberechnung, **kein Überschreiben** einer vorhandenen requirement-Schätzung); **nur** wenn die Felder fehlen, fällt `/flow` auf die §1a-Heuristik (AC1–AC3) zurück. *Prüfbar:* Story mit vorhandenen Feldern → Felder nach `/flow`-§1a identisch; Story ohne Felder → von `/flow` heuristisch gefüllt. *(V8)*
- **AC9** — Quellen-Trennung bleibt erhalten: **Soll** (`size_est`/`dispo_est`/`confidence`/`estimate_note`) lebt in der Story-YAML, **Ist** (`ep_act`/`tok_total`/`ep_est`-Spiegel) im Ledger `items.jsonl`. **requirement schreibt nie ins Ledger**; das Ledger wird ausschliesslich von `/flow` geschrieben (Single-Writer, metrics-subsystem K2). *Prüfbar:* ein requirement-Lauf erzeugt/ändert keine `items.jsonl`-Zeile. *(V9)*
- **AC10** — **Rückwärtskompatibilität:** Alt-Stories und manuell angelegte Items **ohne** Schätzfelder durchlaufen `/flow` unverändert über den Fallback (AC8); `dispo_forecast` entsteht weiterhin erst beim Done (nicht bei Anlage). Kein bestehender Story-/Ledger-Vertrag bricht. *Prüfbar:* eine Story mit `size_est: null` (bzw. fehlendem Feld) läuft fehlerfrei durch `/flow` und bekommt dort Heuristik-Werte. *(V8/V10)*

## Nicht-Ziele

- Ledger-Schema/EP-Formel (`metrics-ledger`).
- Token-Befüllung (`metrics-token-collect`).
- baseline.json-Aggregation/Kalibrierung (`metrics-retro-aggregation`).
- Defektraten/LEARNINGS-Lebenszyklus (`metrics-retro-effectiveness`).
- **(v2)** Änderung der Ledger-Schreibhoheit — die bleibt bei `/flow` (V9/AC9).
- **(v2)** `dispo_forecast` bei Anlage — entsteht erst beim Done (braucht `ep_act`; V10).
- **(v2)** estimator-Dispatch für `S`/`M` (bewusst token-frei; V7/AC7).
- **(v2)** dev-gui-Darstellung Soll/Ist (S-144, anderes Repo; nur Querverweis).
