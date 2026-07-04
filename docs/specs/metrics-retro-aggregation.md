---
id: metrics-retro-aggregation
title: retro — Ledger-Aggregation + EP-Kalibrierung (baseline.json)
status: active
area: metriken-schaetzung
version: 1
---

# Spec: retro-Aggregation + EP-Kalibrierung  (`metrics-retro-aggregation`)

> **Schicht 3 von 3.** Testbares **Verhalten + Verträge**, sprach-/paradigma-unabhängig (Intent, keine Idiome/Klassen).
> **Source of Truth** für `coder` (baut daraus), `tester` (testet die Acceptance-Kriterien), `reviewer` (prüft den Diff dagegen — hartes Drift-Gate).
>
> **Detailkonzept-Bindung.** Das Subsystem ist in `docs/architecture/metrics-subsystem.md` spezifiziert (bindend, §7). Diese Spec beschreibt die **Phase-1-Capability**: `retro` aggregiert die beiden Ledger periodisch zu `baseline.json` und eicht die EP-Gewichte gegen echte Token/Zeit. Sie setzt das Ledger (`metrics-ledger`) und idealerweise echte Token (`metrics-token-collect`) voraus.

## Zweck

`retro` läuft ohnehin selten (~1×/Woche, Cooldown-Gitter G3) — der richtige Ort für die teurere Analyse **auf Zahlen statt Code**. Zusätzlich zum Lessons-Destillieren bekommt `retro` eine **Mess-Aufgabe**: aus den Ledgern Mediane je Grösse×Sprache×cost_mode bilden und die EP-Gewichte gegen die echten `tok_total`/`secs_total` kalibrieren. Damit wird EP von einer festen Startschätzung zur **real geeichten Proxy-Münze** — billig im Alltag, real nachgezogen.

## Kontext / Designnuancen (bindend)

- **Der richtige Ort.** Die teurere Zahlen-Analyse gehört in den seltenen retro-Lauf, nicht in den Pro-Item-Loop (subsystem §10 K1).
- **Deterministischer Rechenschritt.** Aggregation + lineare Regression sind Bash/jq/Rechnung — kein zusätzlicher LLM-Reasoning-Block über den ohnehin laufenden retro hinaus.
- **Schutzgitter respektieren.** Cooldown (G3, 1×/Woche/Repo via `.retro-last-run`), PR+Gate-Mechanik des retro bleiben unverändert.
- **Append-only-Geist.** Die Ledger werden nur **gelesen**; `baseline.json` wird neu geschrieben (committetes Aggregat, analog `LEARNINGS.md`), die historischen Ledger-Werte bleibt unangetastet.

## Verhalten

### V1 — Ledger-Aggregation
Im retro-Lauf liest `retro` `dispatches.jsonl` + `items.jsonl` und bildet Mediane je Schnitt `<lang>|<cost_mode>|<size>`: `ep`, `iters`, `crit`, `tok_total`, `secs_total` (subsystem §2.3).

### V2 — baseline.json schreiben
`retro` schreibt `.claude/metrics/baseline.json` mit der Struktur aus subsystem §2.3: `schema_version` (1), `calibrated_at`, `n_items`, `ep_per_token`, `cache_kappa`, `weights`, `medians` (Schlüssel `<lang>|<cost_mode>|<size>`, je mit Sample-Count `n`), `forecast_mae`. Die Datei wird committet (Teil des regulären retro-Outputs/PR).

### V3 — EP-Kalibrierung (lineare Regression)
`retro` eicht die EP-Gewichte gegen die echten Token/`secs_total` per linearer Regression: `ep_per_token` (1 EP ≈ X **effektive** Token) wird bestimmt; einzelne `weights` (`iter`/`crit`/`imp`/`test_fail`/`loc_log`/`blocked`) ggf. nachjustiert. Die kalibrierten `weights` landen in `baseline.json.weights`.

**Cache-Token-Gewichtung (Design-Entscheidung, bindend):** Cache-Reads sind ~10× billiger als frischer Input (empirisch belegt: #109 zeigte ~15.4M Cache- vs. ~302 Input-Token je Dispatch). Würde man ungewichtetes `tok_total` (in+out+cache) als Eich-Ziel nehmen, dominiert das Cache-Volumen alles andere und verzerrt `ep_per_token`. Die Kalibrierung verwendet daher **effektive Token**: `tok_eff = in + out + κ·cache` mit κ = 0.1 (approximiert das Preis-Verhältnis). Der κ-Wert wird als `cache_kappa` in `baseline.json` dokumentiert.

### V4 — Vorrang der kalibrierten Gewichte
Sind kalibrierte `weights` in `baseline.json` vorhanden, haben sie in `/flow` Vorrang vor den Startgewichten der EP-Formel (subsystem §3) — ohne erneuten Code-Eingriff in `/flow` (es liest `baseline.json.weights`, falls vorhanden).

### V5 — Token-Mangel-Toleranz
Existieren noch keine (oder zu wenige) echte `tok_total` (Token-Pfad nicht verfügbar), überspringt `retro` die Regression sauber: `ep_per_token` bleibt `null`/leer und die `weights` bleiben die Startgewichte. Mediane werden trotzdem (ohne Token-Schnitt) gebildet. Kein Abbruch.

### V6 — Schutzgitter unverändert
Die Mess-Aggregation respektiert Cooldown (G3) und die PR+Gate-Mechanik des retro; sie fügt keinen Bypass und keinen zweiten State-Ort hinzu. `agents/retro.md` wird um diese Mess-Aufgabe erweitert (zusätzlich zum Lessons-Destillieren), ohne die bestehenden Modi/Gitter zu verändern.

## Acceptance-Kriterien

- **AC1** — `retro` liest beide Ledger und bildet Mediane je `<lang>|<cost_mode>|<size>` (`ep`, `iters`, `crit`, `tok_total`, `secs_total`). *(V1)*
- **AC2** — `retro` schreibt `.claude/metrics/baseline.json` mit der Struktur aus subsystem §2.3 (committet, Teil des retro-Outputs/PR). *(V2)*
- **AC3** — Die EP-Gewichte werden per linearer Regression gegen echte `tok_total`/`secs_total` geeicht; `ep_per_token` + ggf. nachjustierte `weights` landen in `baseline.json`. *(V3)*
- **AC4** — Sind kalibrierte `weights` vorhanden, nutzt `/flow` sie mit Vorrang vor den Startgewichten (über `baseline.json.weights`, kein Code-Eingriff). *(V4)*
- **AC5** — Fehlen echte Token, überspringt `retro` die Regression sauber (`ep_per_token` leer, Startgewichte bleiben); Mediane werden trotzdem gebildet; kein Abbruch. *(V5)*
- **AC6** — `agents/retro.md` wird um die Mess-Aufgabe erweitert, ohne Cooldown (G3), PR+Gate-Mechanik oder bestehende Modi zu verändern; kein zweiter State-Ort. *(V6)*

## Nicht-Ziele

- Ledger-Erfassung in `/flow` (`metrics-ledger`).
- Token-Befüllung (`metrics-token-collect`).
- A-priori-Schätzung/Forecast-Fehler (`metrics-estimation`).
- Defektraten/LEARNINGS-Lebenszyklus (`metrics-retro-effectiveness`).
