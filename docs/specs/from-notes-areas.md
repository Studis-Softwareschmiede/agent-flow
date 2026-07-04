---
id: from-notes-areas
title: Notiz-Ingest erzeugt die Bereichsliste — areas.yaml-Entwurf mit Owner-Schleife
status: active
version: 1
spec_format: use-case-2.0
area: anforderung-intake
---

# Spec: Notiz-Ingest erzeugt die Bereichsliste  (`from-notes-areas`)

> **Schicht 3 von 3.** Testbares **Verhalten + Verträge**, sprach-/paradigma-unabhängig (Intent, keine Idiome/Klassen).
> **Source of Truth** für `coder` (baut daraus), `tester` (testet die Acceptance-Kriterien + Coverage-Gate), `reviewer` (prüft den Diff dagegen — hartes Drift-Gate).
>
> **Detailkonzept-Bindung.** Diese Spec **erweitert den Obsidian-Ingest-Weg** (`/agent-flow:from-notes`, [[obsidian-ingest]] / [[obsidian-sync]]) um die **Bereichs-Erzeugung** — analog zu `new-project`/`adopt` ([[new-project-board]] AC8), aber mit **Owner-Schleife über das bestehende Fragenkatalog-Gate**. Sie schließt die dritte Requirement-Quelle an die stabile Strukturkarte ([[board-areas]]) an. Bindender Subsystem-Vertrag: `docs/architecture/obsidian-ingest-subsystem.md`. Owner-Klärung 2026-07-03.

## Zweck

Der Notiz-Ingest darf nicht am Board vorbeiarbeiten: wie `new-project`/`adopt` die Start-`board/areas.yaml` aus dem Konzept scaffolden ([[new-project-board]] AC8), muss auch `/agent-flow:from-notes` die Bereichsliste erzeugen — aber weil die Notizen unfertige Gedanken sind, **nicht autonom**, sondern über eine **Owner-Schleife**: die Pipeline leitet einen `areas.yaml`-**Entwurf** aus dem generierten Konzept ab und legt ihn dem Owner über das **bestehende** Fragenkatalog-Gate zum Streichen/Ergänzen/Bestätigen vor. Die Board-Stufe legt Storys **ausschließlich** unter **bestätigte** Bereiche an — kein Item ohne Bereich, keine autonome Bereichs-Erfindung.

## Kontext / Designnuancen (bindend)

- **Analog new-project/adopt, aber mit Owner-Schleife.** Die Ableitung der Bereiche aus dem Konzept folgt dem Feldformat aus [[board-areas]] AC1; anders als der autonome Scaffold-Schritt in [[new-project-board]] AC8 wird der Entwurf **immer** über das Fragenkatalog-Gate dem Owner vorgelegt (Notizen = unfertig).
- **Ein Gate, kein separater Kanal.** Der Bereichs-Entwurf wird **Teil desselben Stufe-a-`needs-answers`-Zyklus** wie die übrigen Ingest-Rückfragen ([[obsidian-ingest]] AC7/AC9) — kein zweiter Katalog, kein eigener Owner-Prompt. Format bleibt `{stage,id,frage,quelle,optionen}` (`board/fragenkatalog.schema.json`).
- **Bestätigte Bereiche sind die einzige Basis der Board-Stufe.** Die Board-Stufe c ([[obsidian-ingest]] AC11c) legt Storys nur unter Bereichs-Features **bestätigter** Bereiche an; sie erfindet **nie** selbst einen Bereich (konsistent zu [[requirement-area-intake]] AC3).
- **Re-Sync respektiert die bestehende `areas.yaml`.** Der `--sync`-Modus ([[obsidian-sync]]) legt **nie** selbst einen Bereich an; erkennt er ein bereichsfremdes Thema, wird es als **Fragenkatalog-Punkt** vorgeschlagen (invertierte Reconcile-Autorität, [[obsidian-sync]] AC3).
- **Rein lesende Notiz-Quelle.** Wie die übrige Pipeline schreibt die Bereichs-Ableitung **nur** `board/areas.yaml` (+ die ohnehin geschriebenen `docs/`/Board-Artefakte), **nie** in den Notiz-Ordner ([[obsidian-ingest]] AC6/AC14).

## Main Success Scenario

1. Ingest-**Stufe a** erzeugt `docs/concept.md` aus dem Notiz-Korpus ([[obsidian-ingest]] AC11a).
2. Aus dem Konzept leitet `from-notes` einen **`areas.yaml`-Entwurf** ab: je Produktbereich `id` (kebab-case), `titel`, `beschreibung` (1 Satz), `reihenfolge` (int, eindeutig) — konform [[board-areas]] AC1.
3. Der Entwurf wird als Teil des **Stufe-a-Fragenkatalogs** vorgelegt: je Bereich zum **Streichen/Ergänzen/Bestätigen**.
4. Nach Beantwortung schreibt `from-notes` `board/areas.yaml` mit **ausschließlich** den bestätigten Bereichen; der Schreibvorgang fährt im **Stufe-a-Commit** mit.
5. **Stufe c** legt die Storys über `requirement` **ausschließlich** unter Bereichs-Features **bestätigter** Bereiche an; jede neue Spec trägt `area: <bereich>`.

## Alternative Flows

### A1: Konzept eindeutig, Entwurf unstrittig
- Ergeben sich aus dem Konzept klare Bereiche ohne offene Frage → der Bereichs-Entwurf erzeugt **keine** zusätzlichen Katalog-Einträge; die Stufe läuft mit dem Entwurf als Default durch (Auto-Durchlauf, [[obsidian-ingest]] AC8).

### A2: Re-Sync findet ein bereichsfremdes Thema
- `--sync` erkennt im aktuellen Notiz-Stand ein Thema, das keinem Bereich in `board/areas.yaml` zugeordnet ist → es wird als **Fragenkatalog-Punkt** (`stage:"sync"`) vorgeschlagen; `from-notes` legt den Bereich **nie** selbst an.

### E1: kein Bereich ableitbar
- Lässt sich aus dem Konzept (noch) kein Bereich ableiten → minimaler Platzhalter-Bereich (analog [[new-project-board]] AC8) im Entwurf bzw. dokumentiert übersprungen; die Board-Stufe verhält sich dann wie ohne Bereichs-Gate ([[requirement-area-intake]] AC1) und vermerkt das im Output.

## Acceptance-Kriterien
<!-- Nummeriert, testbar. Board-Items referenzieren diese Nummern. AC-IDs sind stabil (nicht umnummerieren). -->

- **AC1** — In Ingest-**Stufe a** leitet `from-notes` nach der `docs/concept.md`-Erzeugung einen **`areas.yaml`-Entwurf** aus dem Konzept ab: je Produktbereich `id` (kebab-case, eindeutig), `titel`, `beschreibung` (genau 1 Satz) und `reihenfolge` (int, eindeutig) — konform zum Feldformat aus [[board-areas]] AC1. Lässt sich kein Bereich ableiten, entsteht ein minimaler Platzhalter-Bereich bzw. der Schritt wird dokumentiert übersprungen (*deckt E1*, analog [[new-project-board]] AC8). *(V1)*
- **AC2** — Der Entwurf wird über das **bestehende** Fragenkatalog-Gate (`{stage,id,frage,quelle,optionen}`, `board/fragenkatalog.schema.json`, [[obsidian-ingest]] AC9) als **Teil desselben Stufe-a-`needs-answers`-Zyklus** vorgelegt (`stage:"a"`) — je Bereich zum **Streichen/Ergänzen/Bestätigen**; **kein** separater Kanal, **kein** zweiter Katalog. Ist der Entwurf unstrittig und das Konzept eindeutig → Auto-Durchlauf mit dem Entwurf als Default ([[obsidian-ingest]] AC8, *deckt A1*). *(V2)*
- **AC3** — Erst **nach** Beantwortung/Bestätigung schreibt `from-notes` `board/areas.yaml` mit **ausschließlich** den bestätigten Bereichen (gestrichene entfallen, ergänzte werden aufgenommen); der Schreibvorgang fährt im **Stufe-a-Commit** mit ([[obsidian-ingest]] AC12). Der Notiz-Ordner wird dabei **nie** beschrieben ([[obsidian-ingest]] AC6). *(V3)*
- **AC4** — Die **Board-Stufe c** ([[obsidian-ingest]] AC11c) legt Storys **ausschließlich** unter Bereichs-Features **bestätigter** Bereiche an (Story-`parent` = Bereichs-Feature des zugeordneten Bereichs, neue Spec mit `area: <bereich>` gestempelt) — **kein** Item ohne Bereich, **keine** autonome Bereichs-Erfindung (neue Bereiche entstehen nur über die AC2/AC3-Bestätigung; konsistent zu [[requirement-area-intake]] AC2/AC3). *(V4)*
- **AC5** — Der Re-Sync-Modus (`--sync`, [[obsidian-sync]]) respektiert die **bestehende** `board/areas.yaml`: erkennt er im aktuellen Notiz-Stand ein Thema, das keinem bestehenden Bereich zugeordnet ist, legt er es als **Fragenkatalog-Punkt** (`stage:"sync"`, Richtungs-/Bereichs-Option) vor — und legt **nie** selbst einen neuen Bereich an (invertierte Autorität, [[obsidian-sync]] AC3; [[requirement-area-intake]] AC3). Nur ein expliziter Owner-Entscheid führt zu einem neuen Bereich. *(V5, deckt A2)*

> **Traceability:** Jeder Test trägt das kanonische Trace-Tag `@trace from-notes-areas#AC<n>`
> gemäss `knowledge/<lang>.md` → `## Spec-Tagging`. Der `tester` rechnet das Coverage-Gate
> (jede genannte AC ≥ 1 deckender Test). Details: `docs/architecture/traceability-subsystem.md`.

## Verträge

- **Skill-Befehl:** `/agent-flow:from-notes [<ordnerpfad>]` (Ingest, AC1–AC4) und `/agent-flow:from-notes --sync` (Re-Sync, AC5) — dieselbe Pipeline, additive Bereichs-Erzeugung. Kein neuer Skill.
- **Bereichs-Entwurf (Reader→Gate):** eine Liste von Bereichs-Objekten je `{ id, titel, beschreibung, reihenfolge }` konform [[board-areas]] AC1. Aus dem Konzept abgeleitet, in den Stufe-a-Katalog eingebettet.
- **Fragenkatalog-Einträge (Bereichs-Bestätigung):** `{ stage:"a", id:"a-<n>" (fortlaufender Stufe-a-Zähler, schema-konform zu `^[a-z]+-[0-9]+$`), frage:<Bereich streichen/ergänzen/bestätigen?>, quelle:<Konzept-/Notiz-Fundstelle>, optionen:["bestätigen","streichen","ändern"] }` — wiederverwendetes Format `board/fragenkatalog.schema.json` (AC2). Im `--sync`-Fall `stage:"sync"` (AC5).
- **Schreib-Ziel:** ausschließlich `board/areas.yaml` (+ die von Stufe a/c ohnehin geschriebenen `docs/`/Board-Artefakte). **Nie** in den Notiz-Ordner (AC3, [[obsidian-ingest]] AC6).
- **Wiederverwendete Bausteine:** Notiz-Korpus-Reader + Fragenkatalog-Gate ([[obsidian-ingest]] AC4–AC9), `requirement`-Zerlegung (Stufe c), `board/areas.yaml`-Format + Lint ([[board-areas]]). Kein zweiter Zerlege-/Gate-/Bereichs-Pfad.

## Edge-Cases & Fehlerverhalten

- **Bestehende `board/areas.yaml` bei Re-Ingest** → der Entwurf wird gegen den Bestand abgeglichen; bestätigte Ergänzungen werden aufgenommen, Bestehendes nicht blind überschrieben (Owner-Entscheid, konsistent [[obsidian-sync]] AC3).
- **Owner streicht alle Bereiche** → keine `areas.yaml` bestätigt → Board-Stufe wie ohne Bereichs-Gate ([[requirement-area-intake]] AC1), Vermerk im Output (*deckt E1*).
- **Abgeleiteter Bereich verletzt das Feldformat** (z.B. `id` nicht kebab-case) → wird vor dem Vorlegen normalisiert bzw. als Katalog-Frage geklärt; `board lint` (`AREA-FIELD`, [[board-areas]] AC5) fängt ein Rest-Risiko ab.
- **`--sync` findet kein bereichsfremdes Thema** → kein Bereichs-Katalog-Punkt, keine `areas.yaml`-Änderung (Rauscharmut, [[obsidian-sync]] AC5).

## NFRs

- **Präzision vor Autonomie:** die Bereichsliste entsteht nie still — jeder Bereich ist owner-bestätigt (Notizen = unfertig).
- **Nachvollziehbarkeit:** jeder Katalog-Eintrag trägt die Konzept-/Notiz-Fundstelle als `quelle`.
- **Nicht-destruktiv:** `board/areas.yaml` wird nie blind überschrieben; der Notiz-Ordner nie beschrieben.

## Nicht-Ziele

- Das Bereichs-Datenmodell + Lint selbst ([[board-areas]]).
- Der autonome Scaffold bei `new-project`/`adopt` ([[new-project-board]] AC8) — hier bewusst mit Owner-Schleife.
- Das Requirement-Eingangs-Gate für die getippte Anforderung ([[requirement-area-intake]]) — hier nur referenziert.
- Die Drei-Stufen-Pipeline / der Reader / das Fragenkatalog-Format selbst ([[obsidian-ingest]] / [[obsidian-sync]]) — wiederverwendet, nicht neu definiert.

## Abhängigkeiten

- [[obsidian-ingest]] — Fundament: Drei-Stufen-Pipeline (AC11), Reader (AC4–AC6), Fragenkatalog-Gate (AC7–AC9), Stufen-Commit (AC12), Authoring-only (AC14).
- [[obsidian-sync]] — Re-Sync-Modus (AC5 hier baut auf dessen invertierter Autorität, AC3).
- [[board-areas]] — `board/areas.yaml`-Feldformat + Bereichs-Lint, gegen das der Entwurf erzeugt wird.
- [[new-project-board]] — AC8 (Scaffold-Analogon bei new-project/adopt).
- [[requirement-area-intake]] — Bereichs-Zuordnung + „NIE selbst Bereich anlegen" (AC3), das die Board-Stufe hier spiegelt.
- `skills/from-notes/SKILL.md` — der Skill, in den die Bereichs-Erzeugung eingebaut wird.
- Vertrag: `docs/architecture/obsidian-ingest-subsystem.md`. Kontext: CONCEPT §4a/§4d.
