---
id: project-memory
title: Projekt-Memory — kuratierter Stand des Projekts (.claude/memory.md)
status: active
version: 1
spec_format: use-case-2.0
area: flow-orchestrierung
---

# Spec: Projekt-Memory  (`project-memory`)

> **Schicht 3 von 3.** Testbares **Verhalten + Verträge**, sprach-/paradigma-unabhängig (Intent, keine Idiome/Klassen).
> **Source of Truth** für `coder` (baut daraus), `tester` (testet die Acceptance-Kriterien + Coverage-Gate), `reviewer` (prüft den Diff dagegen — hartes Drift-Gate).

## Zweck
Jedes Projekt führt eine **kuratierte, kurze Standort-Datei** `.claude/memory.md`: was zuletzt gebaut wurde, wo das Projekt gerade steht, was offen ist — in einfachen, akkuraten Sätzen. Beim Wiedereinstieg (neue `/flow`-Session, Session-Rotation = frischer Kontext pro Story) liefert sie das Gedächtnis über vorangegangene Arbeiten, das Board-Status-Enums und Specs nicht transportieren. Owner-Entscheid 2026-07-18: der Orchestrator (`/flow`) **sichtet und aktualisiert** das Memory am Ende jedes Laufs — Veraltetes wird **gelöscht**, nicht angehängt (kuratieren statt protokollieren).

## Main Success Scenario
1. `/flow` startet in einem Projekt-Repo und liest — falls vorhanden — `.claude/memory.md` als Teil seiner Startlektüre; die Kern-Punkte fliessen als Kontext in die Dispatches (coder/reviewer) ein.
2. Die Story wird regulär abgearbeitet (coder → reviewer ⇄ Loop → tester → cicd ship).
3. Als **letzter Schritt der Session** (nach Landung bzw. nach Blocked-Setzung) sichtet `/flow` das Memory und schreibt es neu: aktueller Stand, letzte Arbeiten, offene Fäden — Erledigtes/Veraltetes fliegt raus, der Größen-Deckel wird eingehalten.
4. Das aktualisierte Memory wird über den bestehenden **Session-Ende-Board-Meta-Commit** persistiert — denselben Commit, mit dem `/flow` nach der Landung ohnehin Board-Meta-Felder schreibt (Dispo-Spiegel) — **nicht** den Landungs-Commit selbst (der liegt zeitlich vor der Kuration, s. AC6) — und steht der nächsten Session zur Verfügung.

## Alternative Flows
### A1: Story endet Blocked
- Auch bei Blocked wird das Memory aktualisiert — gerade dann: 1–2 Sätze, woran es hängt und was der nächste sinnvolle Schritt wäre. Persistenz über denselben Meta-Datei-Pfad wie der Blocked-Board-Status.

### A2: Memory fehlt (Bestandsprojekt)
- Existiert `.claude/memory.md` nicht, startet `/flow` ohne Memory-Kontext (kein Fehler) und legt die Datei am Session-Ende erstmalig an.

### E1: Memory widerspricht Board/Spec
- Bei Widerspruch gelten **Board und Specs** — das Memory ist Orientierung, nie Source of Truth. `/flow` korrigiert den veralteten Memory-Inhalt im Kurations-Schritt; kein Agent leitet aus dem Memory Anforderungen oder Gates ab.

## Acceptance-Kriterien

- **AC1** — Datei-Vertrag: `.claude/memory.md` im Projekt-Repo (versioniert, getrackt) mit genau drei Abschnitten: `## Aktueller Stand` (max. 10 Zeilen Prosa), `## Letzte Arbeiten` (rollierend, max. 10 Einträge à 1–2 Sätze, neueste zuerst), `## Offene Fäden` (optional, max. 5 Einträge). Gesamt-Deckel: **max. 60 Zeilen** Inhalt.
- **AC2** — Lesen beim Start: `/flow` liest `.claude/memory.md` (falls vorhanden) in seiner Startphase und reicht die relevanten Punkte als Kontext an die Story-Dispatches weiter (Lese-Pflicht in `skills/flow/SKILL.md`; fehlende Datei = kein Fehler). *(deckt A2)*
- **AC3** — Kuratieren am Session-Ende (HART): als letzter Schritt jeder `/flow`-Session (nach bestätigter Landung ODER nach Blocked-Setzung) wird das Memory **neu geschrieben**: neuer Stand rein, Erledigtes/Veraltetes/nicht mehr Benötigtes **gelöscht** — reines Anhängen ohne Sichtung verletzt diese Spec. *(deckt A1)*
- **AC4** — Deckel wird durchgesetzt: überschreitet die kuratierte Fassung die Limits aus AC1, wird zusammengefasst/gekürzt statt überschritten (ältere „Letzte Arbeiten"-Einträge fliegen zuerst).
- **AC5** — Orientierung, nie Wahrheit: `skills/flow/SKILL.md` (und die Memory-Sektion selbst via Kopfzeilen-Hinweis in der Datei) stellen klar: bei Widerspruch gelten Board/Specs; das Memory erzeugt keine Gates, keine Acceptance-Kriterien, keinen Spec-Ersatz. *(deckt E1)*
- **AC6** — Persistenz über den Session-Ende-Board-Meta-Commit (HART, präzisiert 2026-07-18): die Kuration läuft **nach** der Landung (letzter Schritt der Session, s. Main Success Scenario Schritt 3/4) — `.claude/memory.md` fährt deshalb **nicht** im eigentlichen Landungs-Commit von `cicd`/`board-ship.sh` mit (das wäre zeitlich unmöglich: die Kuration verarbeitet erst dessen Ergebnis). Stattdessen nutzt die Persistenz denselben, bereits etablierten Session-Ende-Commit-Pfad, den `/flow` nach jeder Landung für Board-Meta-Felder ohnehin fährt (Dispo-Spiegel, `skills/flow/SKILL.md` §2b): `.claude/memory.md` fährt in **diesem** Commit mit (z. B. `chore(board): <story-id> dispo mirror + memory`). Im Blocked-Fall nutzt es denselben Commit wie `board set … status Blocked …`. „Kein eigener, zweiter Commit-Mechanismus" heisst konkret: **kein neuer**, von diesem Session-Ende-Board-Meta-Commit **getrennter** Mechanismus (insbesondere **kein** eigenständiger `chore(memory): …`-Commit als Regelfall) — der Board-Meta-Commit ist der eine Weg. `.claude/memory.md` ist **nicht** Teil des `cicd`-Lessons-Floors ([[flow-lessons-landing]] AC1–AC3): jener deckt ausschliesslich `.claude/lessons/*.md` ab, die bereits **vor** der Landung im Story-Worktree entstehen — memory.md entsteht strukturell erst danach. **Ausnahme (selten):** liegt ein `.claude/memory.md`-Delta ausnahmsweise bereits **vor** der Landung im Story-Worktree vor, fährt es wie die Lessons über den `cicd`-Floor A0 mit (Defense-in-Depth) — das bleibt der Ausnahmefall, nicht der Regelweg.
- **AC7** — Bootstrap: `new-project`/`init` legen eine leere `.claude/memory.md` (Abschnitts-Gerüst + Kopfzeilen-Hinweis) aus der Vorlage an; `init`/`adopt` überschreiben eine bestehende Datei NICHT (idempotent, analog bestehender Scaffold-Regel).
- **AC8** — Schreiber-Disziplin: einziger Schreiber ist der `/flow`-Orchestrator (Kurations-Schritt). coder/reviewer/tester lesen ggf., schreiben aber nie ins Memory (Lessons bleiben deren Write-back-Kanal).

> **Traceability:** Jeder Test trägt das kanonische Trace-Tag `@trace project-memory#AC<n>`
> gemäss `knowledge/<lang>.md` → `## Spec-Tagging`. Der `tester` rechnet das Coverage-Gate
> (jede genannte AC ≥ 1 deckender Test). Details: `docs/architecture/traceability-subsystem.md`.
> Da es sich um Skill-/Template-/Vertrags-Text handelt (`language: md`), erfolgt die Abnahme
> als Doku-Inspektion; das Vorlagen-Scaffolding (AC7) wird über die bestehenden
> Template-Smokes belegt.

## Verträge

### `.claude/memory.md` (kanonisches Gerüst — Vorlage in `templates/_shared/`)
```markdown
> Orientierung, nie Wahrheit: bei Widerspruch gelten Board + docs/specs/.
> Kuratiert von /flow am Ende jeder Session. Max. 60 Zeilen.

## Aktueller Stand
<max. 10 Zeilen: wo steht das Projekt gerade, in Alltagssprache>

## Letzte Arbeiten
- <S-### / Kurzbeschreibung, 1–2 Sätze — neueste zuerst, max. 10 Einträge>

## Offene Fäden
- <max. 5 Einträge: bekannte Stolpersteine, aufgeschobene Entscheidungen>
```

| Artefakt | Garantie |
|---|---|
| `.claude/memory.md` | Kuratierter Projekt-Stand. Single-Writer = `/flow`. Deckel 60 Zeilen. Getrackt + landet mit jeder Session (über den Session-Ende-Board-Meta-Commit, AC6). |
| `skills/flow/SKILL.md` | Start-Lektüre (AC2) + Kurations-Schritt als letzter Session-Schritt (AC3/AC4) + „Orientierung, nie Wahrheit" (AC5) + Session-Ende-Board-Meta-Commit-Persistenz (§2b Dispo-Spiegel bzw. Blocked-Commit, AC6). |
| [[flow-lessons-landing]] / cicd-Floor A0 | **Unverändert:** deckt ausschliesslich `.claude/lessons/*.md` (entstehen vor der Landung im Worktree). `.claude/memory.md` fährt hier nur im Ausnahmefall mit (Delta bereits vor der Landung im Worktree vorhanden, s. AC6) — der Regelweg ist der Session-Ende-Board-Meta-Commit. |
| `templates/_shared/` + `new-project`/`init`/`adopt` | Leeres Gerüst wird gescaffoldet, bestehende Datei nie überschrieben (AC7). |

## Edge-Cases & Fehlerverhalten
- **SR1-Parallel-Batch:** der Kurations-Schritt läuft **einmal** am Batch-Ende (nicht je paralleler Story) — der Orchestrator fasst alle gelandeten/geblockten Storys des Batches zusammen.
- **Memory > Deckel durch Alt-Bestand:** beim ersten Kurations-Lauf auf Deckel-Maß kürzen (kein Fehler).
- **Kurations-Schritt scheitert (IO/git):** kein harter Session-Abbruch (K3-Toleranz), aber sichtbare Meldung — analog Lessons-Landing.

## NFRs
- Token-Ökonomie: das Memory ist bewusst klein (Deckel), damit die Start-Lektüre jeder Session billig bleibt.
- Akkuratheit vor Vollständigkeit: lieber ein Satz weniger als ein veralteter Satz mehr (Kurations-Pflicht AC3).

## Nicht-Ziele
- **Kein** Ersatz für `.claude/lessons/*` (gelernte Regeln), das Board (Status) oder `docs/` (Soll-Verhalten).
- **Keine** Cross-Projekt-Memory und **keine** Fabrik-Memory — strikt pro Projekt-Repo.
- **Keine** dev-gui-Anzeige des Memorys (separates Thema, ggf. eigene dev-gui-Story).
- **Keine** LLM-Zusammenfassung der gesamten Projekt-Historie beim Bootstrap — das Memory wächst ab Einführung organisch.

## Abhängigkeiten
- [[flow-session-rotation]] — der Kurations-Schritt hängt am Session-Ende (eine Story/Batch pro Session).
- [[flow-lessons-landing]] — Persistenz-Muster für `.claude/lessons/*.md` (unverändert; deckt `.claude/memory.md` nur im Ausnahmefall vor der Landung ab, s. AC6).
- `skills/flow/SKILL.md` (§2b Dispo-Spiegel = Regelweg der Persistenz), `agents/cicd.md` (Lessons-Floor A0, Ausnahmefall-Backstop für `.claude/memory.md`), `skills/new-project/SKILL.md`, `skills/adopt/SKILL.md`, `templates/_shared/`.
- Entscheidungsquelle: Owner-Entscheid 2026-07-18 (Dialog-Session, „Orchestrator kuratiert nach Abschluss, Veraltetes löschen").
