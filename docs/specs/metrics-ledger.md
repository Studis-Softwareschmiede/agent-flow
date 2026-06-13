---
id: metrics-ledger
title: Metrik-Ledger + Erfassung in /flow (Phase 0, Fundament)
status: approved
version: 1
---

# Spec: Metrik-Ledger + Erfassung in /flow  (`metrics-ledger`)

> **Schicht 3 von 3.** Testbares **Verhalten + Verträge**, sprach-/paradigma-unabhängig (Intent, keine Idiome/Klassen).
> **Source of Truth** für `coder` (baut daraus), `tester` (testet die Acceptance-Kriterien), `reviewer` (prüft den Diff dagegen — hartes Drift-Gate).
>
> **Detailkonzept-Bindung.** Das Subsystem ist in `docs/architecture/metrics-subsystem.md` spezifiziert (bindend). Diese Spec beschreibt die **Phase-0-Fundament-Capability**: das Datenmodell der zwei JSONL-Ledger, die EP-Formel und die deterministischen Erfassungs-Touchpoints in `/flow`. Token-Erfassung (out-of-band) ist eine **separate** Capability (`metrics-token-collect`); Schätzung/Aggregation/Effektivität sind spätere Phasen.

## Zweck

`/flow` ist einziger Orchestrator + einziger Board-Schreiber und liest die Handoff-Marker ohnehin im Klartext. Diese Spec macht `/flow` zusätzlich zum **einzigen Metrik-Schreiber**: pro Agent-Dispatch eine Zeile, pro Board-Item beim Done eine Rollup-Zeile — deterministische Arithmetik, **~0 zusätzliche LLM-Token**. Sie legt das EP-Maß (Aufwands-Münze) und die Felder fest, auf denen alle späteren Phasen aufbauen.

## Kontext / Designnuancen (bindend)

- **Single-Writer, append-only.** Nur `/flow` schreibt `.claude/metrics/dispatches.jsonl` + `items.jsonl`. Kein anderer Agent berührt `.claude/metrics/` (subsystem §10 K2).
- **Messen blockiert nie den Loop.** Jeder fehlende/unparsebare Marker fällt auf `null`/`0`; ein Metrik-Fehler darf kein Item aufhalten und kein Gate verändern (subsystem §10 K3).
- **Token-frei.** EP wird ohne `tok` berechnet; `tok` ist hier immer `null` (Befüllung liefert `metrics-token-collect`).
- **Marker existieren bereits.** `Review-Handoff … (Iteration N)`, `Review-Gate: PASS|CHANGES-REQUIRED` + `## Critical`/`## Important`, `Test-Gate: PASS|FAIL`, `Rollout-Gate`, Regel-ID-Tags des reviewers — keine neuen Agent-Outputs nötig, nur Zählen.

## Verhalten

### V1 — Ledger-Verzeichnis + Append-only
`/flow` legt bei Bedarf `.claude/metrics/` an und schreibt **ausschließlich anhängend** in `dispatches.jsonl` und `items.jsonl` (je eine JSON-Zeile pro Append). Historische Zeilen werden nie gelöscht oder umgeschrieben (Ausnahme: der `null`→Wert-Patch des Token-Felds durch `metrics-token-collect`).

### V2 — Dispatch-Zeile (pro Agent-Dispatch)
Nach **jedem** Task-Dispatch (coder/reviewer/dba/tester/cicd) appendet `/flow` eine Zeile nach `dispatches.jsonl` mit den Feldern aus subsystem §2.1: `ts, item, seq, agent, iter, gate, crit, imp, rule_hits[], secs, tok (=null), cost_mode`. `seq` zählt innerhalb des Items aufsteigend ab 1.

### V3 — Marker-Zählung (deterministisch)
Die Felder werden aus dem Klartext-Handoff des Dispatches gezählt, kein zweiter LLM-Lauf: `gate` = das jeweilige `*-Gate`; `iter` = N aus `Review-Handoff … (Iteration N)`; `crit`/`imp` = Anzahl Einträge unter `## Critical` / `## Important`; `rule_hits` = die vom reviewer/dba vergebenen Regel-ID-Tags (leer → `[]`). Fehlt ein Marker → das Feld `null`/`0`/`[]` (nie raten).

### V4 — Wall-Clock je Dispatch
`/flow` umklammert jeden Dispatch mit `T0=$(date -u +%s)` (vorher) und `secs = $(date -u +%s) − T0` (nachher) und trägt `secs` in die Dispatch-Zeile. Kein zusätzlicher LLM-Aufwand.

### V5 — Item-Rollup-Zeile (beim Done)
Wenn `/flow` ein Item auf `Done` setzt (nach `Rollout-Gate: PASS`), appendet es **eine** Zeile nach `items.jsonl` mit den Feldern aus subsystem §2.2: `ts, item, size_est, ep_est, ep_act, iters, crit, imp, test_fails, rule_hits[], loc, files, tok_total (=null), secs_total, blocked, lang, cost_mode`. `iters` = max der `iter`-Werte; `crit`/`imp`/`test_fails` = Summen über die Dispatches des Items; `rule_hits` = Vereinigung; `secs_total` = Σ `secs`.

### V6 — Diff-Grösse beim Done
`loc` und `files` stammen aus `git diff --shortstat` des Item-Diffs gegen den `default_branch`-Stand bei Item-Eintritt (`loc` = insertions + deletions, `files` = #geänderte Dateien).

### V7 — EP-Formel (Aufwands-Münze)
`ep_act` wird nach der festen Formel aus subsystem §3 berechnet:
`EP = 1 + 2·(iters−1) + 1·crit + 0.5·imp + 2·test_fails + round(log10(loc+1)) + 3·blocked`.
Sind kalibrierte Gewichte (`baseline.json.weights`) vorhanden, haben diese Vorrang vor den Startgewichten; existiert keine `baseline.json` → Startgewichte.

### V8 — Blocked-Flag
`blocked` = 1, wenn das Item zwischenzeitlich blockiert war (`NEEDS-HUMAN`, ungelöste `depends`, manueller Eingriff), sonst 0.

### V9 — ep_est-Platzhalter in Phase 0
In Phase 0 (ohne Schätz-Capability) schreibt `/flow` `size_est` best-effort (oder `"M"` als neutraler Default) und `ep_est = null`. Die echte Schätzung liefert `metrics-estimation` (spätere Phase) — das Feld existiert hier bereits im Schema, bleibt aber `null`.

### V10 — CONCEPT §5a-Anschluss
Der Tier-2-Absatz in `CONCEPT.md` §5a wird so fortgeschrieben, dass er auf `docs/architecture/metrics-subsystem.md` als Source of Truth für Tier 2 verlinkt; Tier-1-Verhalten bleibt unverändert.

### V11 — Datei-Hygiene
`.claude/metrics/dispatches.jsonl` + `items.jsonl` werden gitignored (lokale, pro-Lauf wachsende Mess-Ledger). `.claude/metrics/baseline.json` bleibt committet (von späterer Phase gepflegt). Keine Secrets, keine Diff-Inhalte, keine Befund-Prosa im Ledger.

## Acceptance-Kriterien

- **AC1** — `/flow` legt `.claude/metrics/` bei Bedarf an und schreibt `dispatches.jsonl` + `items.jsonl` ausschliesslich append-only; keine historische Zeile wird gelöscht/umgeschrieben (Ausnahme: späterer Token-Patch). *(V1)*
- **AC2** — Nach jedem Agent-Dispatch wird genau eine `dispatches.jsonl`-Zeile mit allen Feldern aus subsystem §2.1 angehängt; `seq` zählt pro Item ab 1. *(V2)*
- **AC3** — `gate`, `iter`, `crit`, `imp`, `rule_hits` werden deterministisch aus dem Klartext-Handoff gezählt (kein zweiter LLM-Lauf); fehlender Marker → `null`/`0`/`[]`, nie geraten. *(V3)*
- **AC4** — Jeder Dispatch ist mit `date -u +%s` umklammert; `secs` = Differenz, in die Dispatch-Zeile geschrieben. *(V4)*
- **AC5** — Beim Setzen eines Items auf `Done` wird genau eine `items.jsonl`-Rollup-Zeile mit allen Feldern aus subsystem §2.2 angehängt; `iters`/`crit`/`imp`/`test_fails`/`rule_hits`/`secs_total` korrekt aus den Dispatch-Zeilen aggregiert. *(V5)*
- **AC6** — `loc`/`files` stammen aus `git diff --shortstat` gegen den `default_branch`-Stand bei Item-Eintritt (`loc` = insertions+deletions). *(V6)*
- **AC7** — `ep_act` entspricht bitgenau der EP-Formel aus subsystem §3; kalibrierte `baseline.json.weights` haben Vorrang, sonst Startgewichte. *(V7)*
- **AC8** — `blocked` = 1 bei NEEDS-HUMAN/ungelöster depends/manuellem Eingriff, sonst 0; wirkt entsprechend in der EP-Formel. *(V8)*
- **AC9** — In Phase 0 schreibt `/flow` `tok`/`tok_total`/`ep_est` als `null` und `size_est` best-effort (Default `"M"`); kein Metrik-Schritt blockiert den Loop oder verändert ein Gate. *(V9, K3)*
- **AC10** — Der Tier-2-Absatz in `CONCEPT.md` §5a verlinkt auf `docs/architecture/metrics-subsystem.md`; Tier-1-Verhalten unverändert. *(V10)*
- **AC11** — `dispatches.jsonl` + `items.jsonl` sind gitignored, `baseline.json` ist committet; das Ledger enthält keine Secrets/Diff-Inhalte/Befund-Prosa. *(V11, K6)*
- **AC12** — Nur `/flow` schreibt die beiden Ledger (Single-Writer); kein anderer Agent-Def referenziert `.claude/metrics/`-Schreibzugriff. *(K2)*

## Nicht-Ziele

- Echte Token-Befüllung (`metrics-token-collect`).
- A-priori-Schätzung/Forecast (`metrics-estimation`).
- `baseline.json`-Aggregation/Kalibrierung (`metrics-retro-aggregation`).
- Defektraten/LEARNINGS-Lebenszyklus (`metrics-retro-effectiveness`).
- Echtzeit-Dashboard oder eigener Render-Pfad.
