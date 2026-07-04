---
id: flow-session-rotation
title: /flow Session-Rotation — eine gelandete Story (bzw. ein SR1-Batch) pro Session
status: active
area: flow-orchestrierung
version: 1
spec_format: use-case-2.0
---

# Spec: /flow Session-Rotation  (`flow-session-rotation`)

> **Schicht 3 von 3.** Testbares **Verhalten + Verträge**, sprach-/paradigma-unabhängig (Intent, keine Idiome/Klassen).
> **Source of Truth** für `coder` (baut daraus), `tester` (testet die Acceptance-Kriterien + Coverage-Gate), `reviewer` (prüft den Diff dagegen — hartes Drift-Gate).

## Zweck
Owner-Entscheidung 2026-07-02 (Token-Analyse): Eine `/flow`-Session, die viele Storys nacheinander abarbeitet, schleppt einen linear wachsenden Kontext mit — gemessen am 2026-07-02: Ø Cache-Read pro Schritt wuchs innerhalb einer 13-Story-Session von 82k auf 298k Tokens (Faktor 3,6). `/flow` beendet deshalb die Session nach **einer gelandeten Story** (bzw. einem parallelen SR1-Batch) und überlässt die Rotation der ohnehin vorhandenen äußeren Schleife (dev-gui `ProjectDrain`-Runden, Nachtwächter, Drain-Wrapper). Cache-Reads wachsen damit über ein Board linear statt quadratisch; die Neustart-Kosten (Cache-Neuaufbau) sind demgegenüber vernachlässigbar (Messung 2026-07-02: 12,9 Mio. Cache-Neu vs. 667 Mio. Cache-Read).

## Main Success Scenario
1. `/flow` startet, liest Board, wählt gemäß §1 das nächste Item (bzw. ein paralleles SR1-Batch disjunkter Items).
2. Build-Loop → Review-Gate → Test-Gate → Landen (cicd) → Status Done, Worktree(s) abgebaut — unverändert wie bisher.
3. **NEU:** Statt „zurück zu 1" endet die Session mit der Abschluss-Ausgabe. Sind weitere abarbeitbare Items vorhanden, nennt die Ausgabe das nächste („Board nicht leer — nächster Lauf nimmt voraussichtlich S-xxx"); der Exit-Code bleibt 0.

## Alternative Flows
### A1: `--all` (interaktives Opt-in)
- `/flow --all` behält das bisherige Verhalten (Schleife bis Board leer oder User stoppt). Gedacht für interaktive Sessions, in denen der Owner bewusst zusieht. Headless-Aufrufer (Drain/Nachtwächter) verwenden es NICHT.

### A2: SR1-Parallel-Batch
- Wählt §1 mehrere disjunkte Storys für parallele Worktrees (SR1), zählt das gesamte Batch als „eine Runde": Die Session endet erst, nachdem ALLE Storys des Batches gelandet (oder einzeln geblockt) sind — die Parallelisierung bleibt unangetastet.

### E1: Item wird Blocked statt Done
- Endet ein Item im Loop-Schutz/Blocked, endet die Session ebenso nach diesem Item (kein Weiterziehen zum nächsten) — die äußere Schleife entscheidet über den nächsten Lauf.

## Acceptance-Kriterien

- **AC1** — `skills/flow/SKILL.md` §6 (Loop-Regel): Nach dem vollständigen Abschluss GENAU EINER Story (Done geschrieben + gelandet + Worktree abgebaut) bzw. eines SR1-Batches endet die Session. Kein automatisches Aufnehmen eines weiteren Items im selben Lauf. *(deckt Main 3, A2)*
- **AC2** — Die Abschluss-Ausgabe nennt bei nicht-leerem Board die Anzahl verbleibender abarbeitbarer Items und das voraussichtlich nächste Item; bei leerem Board gilt unverändert die Leerlauf-Diagnose aus `[[empty-drain-diagnostics]]`. *(deckt Main 3)*
- **AC3** — `/flow --all` (dokumentiertes Opt-in in SKILL.md-Frontmatter-`description` + §0): bisheriges Bis-Board-leer-Verhalten. Ohne `--all` gilt Session-Rotation als Default — auch headless. *(deckt A1)*
- **AC4** — Blocked-Ausgang: Endet das gewählte Item/Batch in Blocked, endet die Session nach diesem Item mit der bestehenden Blocked-Meldung; kein Weiterziehen. *(deckt E1)*
- **AC5** — Doku-Nachzug: `AGENTS.md` (Orchestrierungs-Vertrag) und die Stelle(n) in SKILL.md, die „bis das Board leer ist" formulieren, sind konsistent auf die neue Semantik umgestellt; die Begründung (Kontext-Wachstum, Messung 2026-07-02) ist als Ein-Satz-Rationale verankert.

## Verträge
- **Exit-Semantik:** Session-Ende nach einer Runde ist ein ERFOLGS-Ende (Exit 0), kein Abbruch. Die äußere Schleife (ProjectDrain-Runden, Wrapper) erkennt Fortschritt über Board-Statusänderung — unverändert.
- **Keine neue Infrastruktur:** Die Rotation nutzt ausschließlich vorhandene äußere Schleifen; `/flow` selbst startet keine Folge-Session.

## Edge-Cases & Fehlerverhalten
- Board leer beim Start → unverändert Leerlauf-Diagnose (`[[empty-drain-diagnostics]]`), Exit wie bisher.
- Story landet, aber Board-Flip schlägt fehl → bestehende Fehlerpfade unverändert; Session endet nach dem Item.

## NFRs
- Reine Skill-/Doku-Änderung (Markdown); keine Skript-/Code-Änderungen.

## Nicht-Ziele
- Kein Kontext-Kompaktierungs-Feature (Auto-Compact bleibt unberührtes Sicherheitsnetz).
- Keine Änderung an ProjectDrain/NightWatch (dev-gui) — deren Runden-Logik funktioniert unverändert und profitiert automatisch.
- Keine Änderung der Item-Auswahl-Reihenfolge (§1).

## Abhängigkeiten
- `[[empty-drain-diagnostics]]` (Leerlauf-Diagnose, S-028/S-029 — gelandet).
- Konsumenten: dev-gui `ProjectDrain`/`NightWatchScheduler` (verhaltenskompatibel, keine Anpassung nötig).
