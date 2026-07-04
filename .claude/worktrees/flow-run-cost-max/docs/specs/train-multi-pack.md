---
id: train-multi-pack
title: Mehr-Pack-Train mit parallelem Agenten-Fan-out (`/train <pack-a> <pack-b> …`)
status: draft
version: 1
---

# Spec: Mehr-Pack-Train mit parallelem Fan-out  (`train-multi-pack`)

> **Schicht 3 von 3.** Testbares **Verhalten + Verträge**, sprach-/paradigma-unabhängig (Intent, keine Idiome/Klassen).
> **Source of Truth** für `coder` (baut daraus), `tester` (testet die ACs), `reviewer` (Drift-Gate).

## Zweck

`/train` aktualisiert heute **genau einen** Knowledge-Pack pro Lauf. Diese Spec erweitert die `train`-Skill so, dass sie **mehrere Pack-IDs** in **einem** Aufruf entgegennimmt und **pro Pack einen `train`-Agenten parallel** startet (Fan-out über das Task-Tool, mehrere Dispatches in einer Runde). Jeder Agent durchläuft den **unveränderten** Einzel-Pack-Ablauf und liefert **seinen eigenen PR** (ein PR pro Pack, wie heute).

**Motivation:** Die GUI-Seite (`dev-gui`, Spec [[team-train-trigger]]) bietet eine Mehrfachauswahl von Knowledge-Bereichen mit einem „Parallel"-Modus an. „Parallel" bedeutet dort **parallele Agenten in der einen Claude-Session** — was genau diesen Mehr-Pack-Aufruf voraussetzt. Diese Spec ist die agent-flow-seitige Fundamentarbeit dazu; die GUI ist die separate Folge-Aufgabe.

## Kontext / Designentscheidungen (bindend)

- **Additiv & rückwärtskompatibel.** Ein einzelner Pack-ID-Aufruf verhält sich **bitgenau wie heute** (gleicher Resolver, gleicher Single-Agent-Dispatch, gleiches Stopp-Verhalten bei Ambiguität). Mehr-Pack ist die neue, zusätzliche Form.
- **Fan-out = ein Agent pro Pack, parallel.** Die Skill löst jede Pack-ID einzeln auf und dispatcht **pro aufgelöstem Pack genau einen `train`-Agenten** — alle Dispatches in **einer** Task-Runde (echte Parallelität innerhalb der Session). Es gibt **keinen** „Sammel-Agenten", der mehrere Packs nacheinander abarbeitet.
- **Ein PR pro Pack.** Jeder Agent arbeitet auf seinem eigenen Branch `train/<pack-id>` und öffnet seinen eigenen PR — unverändert zum Einzel-Lauf. Kein paketübergreifender Merge, keine Sammel-PRs. Damit bleibt das Gate (`reviewer`-Check + Mensch-Approve) pro Pack feinkörnig.
- **Kostenmodus einmal aufgelöst, an alle weitergereicht.** Der Cost-Mode (`--cost` > `profile.cost_mode` > `balanced`) wird **einmal** aufgelöst und als `model`-Override an **jeden** der parallelen Agenten mitgegeben (gleiche Mechanik wie heute, Quelle `knowledge/model-tiers.md`, Rolle `train`).
- **Fehler-Isolation statt Alles-oder-Nichts.** Eine nicht auflösbare/ambige Pack-ID in einer Mehr-Pack-Liste **bricht nicht den ganzen Lauf ab**: sie wird übersprungen und am Ende klar berichtet; die übrigen, eindeutig auflösbaren Packs werden dispatcht. *(Beim Einzel-Aufruf bleibt das heutige harte Stopp-Verhalten mit Optionsliste erhalten — siehe Nicht-Ziele/Edge-Cases.)*
- **Sondermodi bleiben Einzel-Pack.** `model-tiers`, `--bootstrap` sind **nicht** mit der Mehr-Pack-Form kombinierbar (sie haben Sonder-Semantik/Schreibziele). Mehr-Pack gilt nur für reguläre Sprach-/Framework-/Build-/Migration-Packs.
- **Dedup.** Doppelt genannte Pack-IDs werden vor dem Dispatch dedupliziert (ein Agent pro eindeutigem Pack).

## Verhalten

### V1 — Aufruf-Form
`/train [--cost <mode>] <pack-id> [<pack-id> …]` — ein oder mehrere durch Leerzeichen getrennte Pack-IDs. Die `--cost`-/`--force`-Token werden wie heute vor der Pack-ID-Auflösung herausparst; alles Übrige sind Pack-IDs.

### V2 — Pro-Pack-Auflösung
Jede Pack-ID wird **einzeln** über den bestehenden Resolver aufgelöst (`framework-build-subsystem.md §8`: `<id>`, `<id>@<major>`, `frameworks/<id>`, `build/<id>`, `migration/<id>`). Ergebnis je Eintrag: aufgelöst → Pack-Pfad; oder unauflösbar/ambig → als Fehler vermerkt.

### V3 — Paralleler Fan-out
Für jeden **aufgelösten** Pack wird **ein** `train`-Agent über das Task-Tool gestartet; alle Dispatches erfolgen **in einer Runde parallel**. Jeder Agent bekommt seinen Pack + den aufgelösten Cost-Mode-`model`-Override. Jeder Agent führt den **regulären** Einzel-Pack-Ablauf aus (Pack lesen → Web-Recherche aus Primärquellen → max. 3 Regeln → Branch `train/<pack-id>` → PR).

### V4 — Ergebnis-Zusammenfassung
Nach Abschluss aller Agenten liefert die Skill eine **Sammel-Übersicht**: je Pack der Status (PR geöffnet + Link · keine Änderung · Fehler) sowie eine separate Liste der **übersprungenen** (unauflösbaren/ambigen) Pack-IDs mit Grund.

### V5 — Rückwärtskompatibler Einzel-Aufruf
Bei genau **einer** Pack-ID ist das Verhalten unverändert zu heute — inkl. hartem Stopp + Optionsliste bei Ambiguität (kein „Skip & weiter", da es nichts Weiteres gibt).

## Acceptance-Kriterien

- **AC1** — `/train` akzeptiert mehrere durch Leerzeichen getrennte Pack-IDs; `--cost`/`--force` werden korrekt vor der Auflösung herausgeparst und gehören nie zur Pack-ID. *(V1)*
- **AC2** — Jede Pack-ID wird einzeln über den bestehenden Resolver aufgelöst; das Resolver-Verhalten je Einzel-ID ist identisch zum heutigen Einzel-Lauf. *(V2)*
- **AC3** — Für n aufgelöste Packs werden n `train`-Agenten in **einer** parallelen Task-Runde gestartet (ein Agent pro Pack, kein sequentieller Sammel-Agent). *(V3)*
- **AC4** — Jeder Agent öffnet seinen eigenen PR auf Branch `train/<pack-id>`; es gibt keinen paketübergreifenden Sammel-PR/-Merge. *(V3)*
- **AC5** — Der Cost-Mode wird einmal aufgelöst (Präzedenz `--cost` > `profile.cost_mode` > `balanced`) und als `model`-Override an **jeden** Agenten weitergereicht. *(V3, Kontext)*
- **AC6** — Eine unauflösbare/ambige Pack-ID in einer **Mehr-Pack**-Liste bricht den Lauf nicht ab: sie wird übersprungen und in der Zusammenfassung mit Grund gelistet; die übrigen Packs werden dispatcht. *(V2, V4)*
- **AC7** — Bei genau **einer** Pack-ID ist das Verhalten bitgenau wie heute, inkl. hartem Stopp + Optionsliste bei Ambiguität. *(V5)*
- **AC8** — Doppelte Pack-IDs werden vor dem Dispatch dedupliziert (ein Agent je eindeutigem Pack). *(Kontext)*
- **AC9** — Sondermodi (`model-tiers`, `--bootstrap`) werden mit Mehr-Pack-Listen **abgelehnt** (klare Fehlermeldung), nicht still gemischt. *(Kontext)*
- **AC10** — Die Skill liefert am Ende eine Sammel-Übersicht je Pack (PR-Link · keine Änderung · Fehler) + Liste übersprungener IDs. *(V4)*

## Verträge

- **Eingabe:** `/train [--cost <mode>] <pack-id> [<pack-id> …]` (Skill `skills/train/SKILL.md`).
- **Dispatch:** pro aufgelöstem Pack ein Task-Tool-Aufruf des `train`-Agenten (`agents/train.md`) mit `{ pack, model-override }`; alle Aufrufe einer Runde.
- **Ausgabe je Agent:** unverändert — PR gegen `Studis-Softwareschmiede/agent-flow`, Branch `train/<pack-id>`, `LEARNINGS.md`-Zeile (`Proposed`).
- **Ausgabe der Skill:** Sammel-Übersicht (Pack → Status/PR-Link; übersprungene IDs + Grund).

## Edge-Cases & Fehlerverhalten

- **Alle IDs unauflösbar** → kein Dispatch; Zusammenfassung listet alle als übersprungen (kein Crash).
- **Eine von vielen ambig** → diese überspringen + berichten; Rest läuft (AC6).
- **Einzel-ID ambig** → harter Stopp + Optionsliste (AC7, heutiges Verhalten).
- **`model-tiers`/`--bootstrap` mit ≥2 IDs** → Ablehnung mit Hinweis (AC9).
- **Doppelte ID** → einmal dispatcht (AC8).
- **Gate unverändert:** jeder PR braucht `reviewer`-Check + Mensch-Approve; kein Auto-/Self-Merge.

## NFRs

- **Token-/Kontingent-Bewusstsein:** Mehr-Pack-Läufe vervielfachen den Aufwand (n parallele Agenten). Der Cost-Mode greift pro Agent; eine sehr lange Pack-Liste ist bewusst Owner-Entscheidung (die GUI fasst sie in einer Bestätigung zusammen, [[team-train-trigger]] V4).
- **Quellen-Disziplin unverändert:** jeder Agent respektiert `primary_sources`/`non_sources`, max. 3 Regeln/Lauf, Sektion-A-Beschränkung bei Framework-/Build-Packs.

## Nicht-Ziele

- **Paket-übergreifender Sammel-PR/-Merge** — bewusst nicht (ein PR pro Pack bleibt).
- **Mehr-Pack für Sondermodi** (`model-tiers`, `--bootstrap`).
- **Mehrere Claude-Sessions / Session-Pool** — die Parallelität ist reiner Task-Fan-out **innerhalb** der Session.
- **Änderung des Resolvers oder des Einzel-Pack-Ablaufs** (Recherche, Regel-Promotion, Gate bleiben unverändert).
- **GUI-Anteil** — separat in [[team-train-trigger]] (dev-gui).

## Abhängigkeiten

- **agent-flow:** `skills/train/SKILL.md` (Mehr-Pack-Parsing + Fan-out-Dispatch), `agents/train.md` (Agent bleibt Einzel-Pack — keine Änderung am Agenten selbst nötig), Pack-ID-Resolver (`docs/architecture/framework-build-subsystem.md §8`), `knowledge/model-tiers.md` (Cost-Override).
- **dev-gui:** [[team-train-trigger]] (konsumiert diese Form über den „Parallel"-Modus).
