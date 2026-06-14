---
id: flow-board-backend
title: /flow auf File-Board — board next/set statt gh + Story-ID-Brücke ins Ledger
status: draft
version: 1
---

# Spec: /flow auf File-Board  (`flow-board-backend`)

> **Schicht 3 von 3.** Testbares **Verhalten + Verträge**, sprach-/paradigma-unabhängig (Intent, keine Idiome/Klassen).
> **Source of Truth** für `coder` (baut daraus), `tester` (testet die Acceptance-Kriterien), `reviewer` (prüft den Diff dagegen — hartes Drift-Gate).
>
> **Detailkonzept-Bindung.** Das Board-Subsystem ist in `docs/architecture/board-subsystem.md` spezifiziert (bindend, §4.4, §5, §7, §8). Diese Spec stellt `/flow` (und mitlesende Agents coder/reviewer/tester) vom GitHub-Backend auf die `board`-CLI ([[board-cli]]) um: `board next` lesen, `board set … status` schreiben — **Logik identisch**, nur das Backend wechselt. Zusätzlich verankert sie die ID-Brücke: die Story-ID `S-###` als `item`-Schlüssel in den Metrik-Ledgern (§4.4).

## Zweck

`/flow` liest die nächste Arbeitseinheit künftig über `board next` statt `gh project item-list` und schreibt Story-Status über `board set <id> status …` statt `gh project item-edit`. Die Story-Übergänge und ihre Auslöser bleiben 1:1 wie heute; es ändert sich nur das Backend. Damit `dispo_est`/`dispo_act` ([[metrics-estimation]], [[estimator]]) eindeutig der Story zugeordnet bleiben, schreibt `/flow` die Story-ID als `item`-Schlüssel in `dispatches.jsonl`/`items.jsonl`.

## Kontext / Designnuancen (bindend)

- **Backend-Tausch, gleiche Logik.** Die Status-Übergänge `To Do → In Progress → In Review → Done` und die Blocked-Auslöser (Spec-Lücke, Loop-Schutz N=3, DB-Smoke-FAIL, Rollout-FAIL) bleiben unverändert (board-subsystem §5, §8). Nur die Lese-/Schreib-Aufrufe wechseln von `gh` auf `board`.
- **`/flow` bleibt einziger Status-Schreiber.** Single-Writer-Regel; `/flow` setzt Story-Status, kein anderer Agent (§7).
- **Lesen über `board next`.** Ersetzt `gh project item-list` (board-subsystem §7, Verweis auf `flow/SKILL.md:22`). Die Queue-Logik selbst lebt in der CLI ([[board-cli]] V6).
- **ID-Brücke (Pflicht).** Bisher = GitHub-Issue-Nummer als `item`. Künftig schreibt `/flow` die **Story-ID `S-###`** als `item`-Schlüssel in `dispatches.jsonl`/`items.jsonl` (board-subsystem §4.4). Die Story-YAML spiegelt `dispo_*`/`tok` per ID-Join; die Ledger bleiben SoT der Ist-Werte.
- **Coder/Reviewer/Tester lesen über `board show`.** Sie lesen Story + Spec via `board show <story>` statt Issue-Body; sie schreiben weiterhin KEINEN Status (§8).
- **Laufzeit-Felder.** `/flow` setzt `branch` (immer) und `pr` (bei pr-Policy) sowie `blocked_reason` bei Blocked über `board set` (§4.2).
- Konservative Annahme: Die Schätzung (`size_est`/`dispo_est`) folgt unverändert [[metrics-estimation]]/[[estimator]]; diese Spec ändert nur, WOHIN `/flow` die Werte schreibt (Story-YAML + Ledger mit Story-ID), nicht WIE geschätzt wird.

## Verhalten

### V1 — nächste Story lesen
`/flow` ruft `board next` (statt `gh project item-list`) und erhält die nächste bereite Story (`id`, `spec`, `implements`, `parent`, `labels`, `priority`). Leere Ausgabe → „nichts zu tun", der Loop endet sauber.

### V2 — Status schreiben über CLI
Jeder Status-Übergang läuft über `board set <story-id> status <wert> [--reason …]` statt `gh project item-edit`. Die Übergänge und Auslöser sind identisch zu heute (board-subsystem §5).

### V3 — Blocked mit Grund
Setzt `/flow` eine Story auf `Blocked` (Spec-Lücke / Loop-Schutz N=3 / DB-Smoke-FAIL / Rollout-FAIL), übergibt es `--reason <grund>`, der nach `blocked_reason` geschrieben wird.

### V4 — Done-Übergang
Beim `Done` setzt `/flow` `board set <story> status Done` (CLI setzt `done_at`) und schreibt — wie heute — die `items.jsonl`-Rollup-Zeile ([[metrics-ledger]] V5).

### V5 — ID-Brücke ins Ledger
`/flow` schreibt die **Story-ID `S-###`** als `item`-Feld in jede `dispatches.jsonl`- und `items.jsonl`-Zeile (statt der GitHub-Issue-Nummer). Alle Metrik-Felder bleiben unverändert; nur der Schlüssel wechselt (board-subsystem §4.4).

### V6 — Story-YAML spiegelt Dispo
Nach dem Done aktualisiert `/flow` die Sicht-Felder der Story-YAML (`dispo_act`, `dispo_forecast`, `tok`) per ID-Join aus dem Ledger über `board set` — SoT der Ist-Werte bleibt das Ledger ([[metrics-ledger]], [[metrics-estimation]]). Schlägt der Join fehl → Story-Felder bleiben `null` (blockiert nie).

### V7 — Laufzeit-Felder
`/flow` setzt `branch` beim Start der Story (`board set <id> branch …`) und `pr` bei aktiver pr-Policy (`board set <id> pr …`).

### V8 — Lese-Agents auf board show
`coder`/`reviewer`/`tester` lesen die Story über `board show <story>` + die referenzierte Spec, statt einen Issue-Body. Sie schreiben weiterhin keinen Status und keine Board-Felder.

### V9 — kein gh im Board-Pfad
Im Board-Lese-/Schreib-Pfad von `/flow` (und der lesenden Agents) gibt es keine `gh project`-Aufrufe mehr. `gh` für Code-Review/PR (cicd) bleibt unberührt.

### V10 — Skill-/Agent-Doku-Anschluss
`skills/flow/SKILL.md` und die Agent-Defs `coder`/`reviewer`/`tester` werden auf die `board`-Verben umgeschrieben (board-subsystem §8); die Status-Logik-Beschreibung bleibt inhaltlich identisch.

## Acceptance-Kriterien

- **AC1** — `/flow` liest die nächste Arbeitseinheit über `board next` (nicht `gh project item-list`); leere Ausgabe → Loop endet sauber als „nichts zu tun". *(V1)*
- **AC2** — Jeder Story-Status-Übergang läuft über `board set <story> status …`; die Übergänge/Auslöser sind identisch zu board-subsystem §5. *(V2)*
- **AC3** — `Blocked` wird mit `--reason` gesetzt und landet in `blocked_reason`. *(V3)*
- **AC4** — Beim Done setzt `/flow` `status Done` über die CLI und schreibt die `items.jsonl`-Rollup-Zeile. *(V4)*
- **AC5** — `/flow` schreibt die Story-ID `S-###` als `item`-Schlüssel in `dispatches.jsonl` und `items.jsonl` (statt Issue-Nummer); alle übrigen Metrik-Felder unverändert. *(V5)*
- **AC6** — Nach dem Done spiegelt `/flow` `dispo_act`/`dispo_forecast`/`tok` per ID-Join aus dem Ledger in die Story-YAML; fehlgeschlagener Join → Felder `null`, kein Block. *(V6)*
- **AC7** — `/flow` setzt `branch` beim Start und `pr` bei pr-Policy über `board set`. *(V7)*
- **AC8** — `coder`/`reviewer`/`tester` lesen die Story über `board show <story>` + Spec und schreiben weiterhin keinen Status/keine Board-Felder. *(V8)*
- **AC9** — Im Board-Pfad von `/flow` und den lesenden Agents gibt es keine `gh project`-Aufrufe mehr; `gh` für PR/Code-Review (cicd) bleibt unberührt. *(V9)*
- **AC10** — `skills/flow/SKILL.md` + `coder`/`reviewer`/`tester`-Defs sind auf die `board`-Verben umgeschrieben; die Status-Logik bleibt inhaltlich identisch. *(V10)*

## Verträge

### `/flow`-Board-Aufrufe (Ersatz-Mapping)
```
gh project item-list   →  board next
gh project item-edit … status   →  board set <id> status <wert> [--reason …]
(Issue-Body lesen)     →  board show <id>   (coder/reviewer/tester)
```

### Ledger-Schlüssel (ID-Brücke, §4.4)
```
dispatches.jsonl: { item: "S-014", … }     # statt item: 123 (Issue-Nr.)
items.jsonl:      { item: "S-014", … }
```

## Edge-Cases & Fehlerverhalten

- **`board next` leer** → kein Item; `/flow` endet ohne Fehler (kein Block).
- **`board set` schlägt fehl** (z.B. ungültiger Wert) → `/flow` behandelt wie heute einen Backend-Fehler; Story-Status bleibt unverändert.
- **Ledger-Join findet keine Story-Zeile** → Sicht-Felder `null`; Loop läuft weiter (board-subsystem §4.4 Reifegrad-Hinweis).
- **Single-Writer-Verletzung** (anderer Agent versucht `set status`) → von der CLI abgelehnt ([[board-cli]] V9); `/flow` ist der einzige legitime Schreiber.

## NFRs

- **Verhaltens-Äquivalenz:** identische Status-Maschine wie heute; nur Backend getauscht (Regressions-Risiko minimal).
- **Token-frei:** `board next`/`set`/`show` deterministisch ohne LLM.
- **Auditierbarkeit:** Status-Änderungen sind git-Diffs der Story-YAML.

## Nicht-Ziele

- Queue-Logik selbst ([[board-cli]] V6).
- Dateiformat ([[board-schema]]).
- Schätz-Mechanik S/M bzw. L/XL ([[metrics-estimation]], [[estimator]]) — hier nur das Schreibziel.
- dev-gui-Aggregation ([[dev-gui-board-aggregator]]).
- Migration aus GitHub ([[board-github-export]]).

## Abhängigkeiten

- [[board-cli]] — die Verben, die `/flow` ruft.
- [[board-schema]] — Story-Felder, die `/flow` setzt/spiegelt.
- [[metrics-ledger]] · [[metrics-estimation]] · [[estimator]] — Ledger + Dispo-Werte, deren Schlüssel auf die Story-ID umgestellt wird.
- `docs/architecture/board-subsystem.md` §4.4, §5, §7, §8 — bindendes Detailkonzept.
