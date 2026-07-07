---
id: self-documentation
title: Selbst-Dokumentations-Pflicht — CONCEPT/AGENTS wachsen mit der Fabrik mit
status: active
area: doku-reconcile
version: 1
spec_format: use-case-2.0
---

# Spec: Selbst-Dokumentations-Pflicht  (`self-documentation`)

> **Schicht 3 von 3.** Testbares **Verhalten + Verträge**, sprach-/paradigma-unabhängig (Intent, keine Idiome/Klassen).
> **Source of Truth** für `coder` (baut daraus), `tester` (testet die Acceptance-Kriterien + Coverage-Gate), `reviewer` (prüft den Diff dagegen — hartes Drift-Gate).
> **Konzept-Herkunft:** `(← C-001)` — CONCEPT.md §11 „Entschieden (Selbst-Dokumentations-Pflicht, 07.07.2026)", entstanden aus Ideennotiz `IDEA-001` (`Agent Flow – Architektur.md`, §Gap zum Konzept, 30.06.2026).

## Zweck
`CONCEPT.md` und `AGENTS.md` sind die Selbstbeschreibung der Fabrik — sie sind dem Repo-Ist-Stand hinterhergewachsen (Befund 30.06.2026: `estimator`-Agent nirgends dokumentiert, 5 `knowledge/`-Unterordner fehlen in §4c), weil kein aktiver Agent sie nachpflegt. Diese Spec verankert zwei minimale Pflichten: der `train`-Bootstrap zieht bei einer **neuen Pack-Kategorie** `CONCEPT.md` §4c im selben PR nach, und der Agenten-Roster in `AGENTS.md` wird vollständig (einmaliger Nachzug + Vollständigkeit als prüfbarer Zustand). Ein neuer periodischer Drift-Scan ist bewusst **kein** Teil dieser Spec — die rückwärtige Aufholung leistet `/agent-flow:reconcile`.

## Acceptance-Kriterien

- **AC1** — Legt `train --bootstrap <pack-id>` einen Pack in einer **neuen Kategorie** an (ein `knowledge/`-Unterordner, den es vorher nicht gab), enthält derselbe PR zusätzlich das Nachziehen von `CONCEPT.md` §4c (Pack-/Verzeichnisliste um die neue Kategorie ergänzt). Pack-Anlage ohne CONCEPT-Delta ist in diesem Fall unvollständig (reviewer-Kriterium).
- **AC2** — Bootstrap/Update eines Packs in einer **bestehenden** Kategorie erzeugt **kein** CONCEPT-Delta (Rauscharmut: §4c listet Kategorien/Struktur, nicht jede einzelne Pack-Datei).
- **AC3** — Läuft der Bootstrap im **Staging-Modus** (`AGENT_FLOW_KNOWLEDGE_DIR` gesetzt, z.B. `/upgrade` Phase E — kein PR-Kontext), entfällt der CONCEPT-Sync; stattdessen weist der `train`-Output explizit auf den ausstehenden §4c-Nachzug hin (kein stiller Verlust der Pflicht).
- **AC4** — Der Agenten-Roster in `AGENTS.md` führt **jeden** produktiven Agenten unter `agents/*.md` mit eigenem Spec-Abschnitt: konkret wird `estimator` nachdokumentiert (Zweck, Trigger/Input, Lese-Pflichten, Tools, Output, harte Grenzen — dieselbe Schablone wie die übrigen Agenten) und die Roster-Zählung/Kopfzeile korrigiert (inkl. `cicd`, das einen Abschnitt hat, aber in der Kopfzeile fehlt).
- **AC5** — Die Vollständigkeit aus AC4 ist mechanisch prüfbar: jede Datei `agents/<name>.md` hat einen zugehörigen `## …<name>`-Abschnitt in `AGENTS.md` (Abgleich Dateiliste ↔ Überschriften; Abweichung = Befund).

## Verträge
- **`train`-Verhalten (AC1–AC3):** Erweiterung des bestehenden `train --bootstrap`-Vertrags (`docs/architecture/upgrade-subsystem.md` §8, `agents/train.md`): „neue Kategorie" = der Ziel-Pfad `knowledge/<kategorie>/<pack>.md` enthält einen Verzeichnisanteil, der vor dem Lauf nicht existierte. Der CONCEPT-Nachzug ist Teil desselben Branch/PR (kein separater PR).
- **Roster-Abgleich (AC4/AC5):** Quelle = Dateiliste `agents/*.md`; Ziel = `AGENTS.md`-Abschnitte. Der Abgleich ist abgeleitet, nie handgepflegt (gleiche Philosophie wie Traceability-Map).

## Edge-Cases & Fehlerverhalten
- Kategorie-Erkennung bei verschachtelten Pfaden: maßgeblich ist der **erste** neue Verzeichnisanteil unter `knowledge/`.
- Ein Pack direkt unter `knowledge/` (ohne Unterordner) ist **keine** neue Kategorie (AC2 greift).
- `AGENTS.md`-Abschnitte für bewusst inaktive Agenten (`teamLeader`, „SPÄTER") bleiben gültig — Inaktivität ist dokumentierter Zustand, kein Roster-Fehler.

## NFRs
- Rauscharmut: keine CONCEPT-Deltas ohne strukturelle Änderung (AC2).
- Nachvollziehbarkeit: der §4c-Nachzug nennt im PR-Body die auslösende neue Kategorie.

## Nicht-Ziele
- **Kein** neuer periodischer Drift-Scan (leistet `/agent-flow:reconcile` Stufe 1/2, bei Obsidian-Anbindung Stufe 3).
- **Keine** Aktivierung des `teamLeader` (bleibt „SPÄTER, nicht P1" — bewusst aus dem Umfang genommen, Fragenkatalog a-2 vom 07.07.2026).
- **Keine** Pflicht, jede einzelne Pack-Datei in CONCEPT.md zu listen (nur Kategorien/Struktur).

## Abhängigkeiten
- `agents/train.md` + `docs/architecture/upgrade-subsystem.md` §8 (Bootstrap-Vertrag, wird um AC1–AC3 erweitert).
- `AGENTS.md` (Roster, AC4/AC5) · `CONCEPT.md` §4c (Ziel des Nachzugs).
- Verwandt: `[[train-bootstrap-new-pack]]` (bestehender Bootstrap-Vertrag), `[[reconcile]]` (rückwärtige Aufholung, Abgrenzung).
