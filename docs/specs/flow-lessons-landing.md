---
id: flow-lessons-landing
title: Lessons überleben das Worktree-Landen — cicd trägt .claude/lessons/*.md IMMER mit
status: draft
version: 1
spec_format: use-case-2.0
---

# Spec: Lessons überleben das Worktree-Landen  (`flow-lessons-landing`)

> **Schicht 3 von 3.** Testbares **Verhalten + Verträge**, sprach-/paradigma-unabhängig (Intent, keine Idiome/Klassen).
> **Source of Truth** für `coder` (baut daraus), `tester` (testet die Acceptance-Kriterien + Coverage-Gate), `reviewer` (prüft den Diff dagegen — hartes Drift-Gate).
> **Betrifft die Fabrik selbst** (agent-flow): das Verhalten der `/flow`-Pipeline (`skills/flow/SKILL.md`) + des Abschluss-Arms (`agents/cicd.md`). Kein Konsumenten-Feature.

## Zweck
Lessons, die coder/reviewer/tester **innerhalb eines isolierten Story-Worktrees** in `.claude/lessons/<rolle>.md` schreiben, gehen beim Landen der Story verloren, weil der Abschluss-Arm (`cicd`) nur die konkret genannten Implementierungs-/Test-Dateien committet und der Worktree danach per `git worktree remove --force` gelöscht wird. Diese Spec macht `.claude/lessons/*.md` zu **immer-mitzunehmenden Meta-Dateien jeder Landung** — analog zum bereits isolations-festen retro-Cooldown-Stempel (`.retro-last-run`) — und stellt sicher, dass **parallele** Landungen einander nicht überschreiben (additiver, newest-first Merge statt Datei-Kopie).

## Kontext / Root Cause (belegt, nicht vermutet)
- In Konsumenten-Repos (z.B. `dev-gui`) sind `.claude/lessons/{coder,reviewer,tester}.md` **git-versioniert** (`git ls-files` bestätigt); `.claude/worktrees/` ist gitignored.
- Bei paralleler Story-Abarbeitung (SR1 in `skills/flow`) läuft jede Story in einem eigenen Worktree (`.claude/worktrees/<story-id>`, eigener Branch). `git worktree add` checkt die **getrackte** Lessons-Datei in den Worktree aus; ein Agent prependet dort eine neue Lesson (newest-first) in den Working-Tree.
- `cicd` wurde je Dispatch instruiert, **nur** die konkreten Story-Dateien zu landen; die Lessons-Datei stand nie auf dieser Liste → nie committet → nie gemergt → beim `git worktree remove --force` spurlos verloren. **Beleg:** dev-gui S-225, reviewer-Handoff: „Coder-Lesson festgehalten in `<worktree>/.claude/lessons/coder.md`" — geschrieben, aber nie gelandet.
- Es ist ein **strukturelles Landungs-Problem**, kein Schreib-Fehler der Agenten (coder/reviewer schreiben nachweislich korrekt, `agents/reviewer.md` §7 „Tier-1-Write-back").

## Main Success Scenario
1. `/flow` arbeitet eine Story in einem isolierten Worktree ab; ein Agent prependet eine Lesson in `.claude/lessons/<rolle>.md` (Working-Tree des Worktrees).
2. Nach `tester`-PASS dispatcht `/flow` `cicd` zum Landen (§5).
3. `cicd` bezieht **jede geänderte, getrackte** `.claude/lessons/*.md` in denselben Commit/PR ein — **auch wenn** die Story-Dateiliste sie nicht nennt.
4. Die Lessons-Änderung fährt durch die normale Merge-/Rebase-Maschinerie; ein bereits gelandeter Lessons-Zuwachs einer parallelen Story bleibt erhalten (additiver, newest-first Merge — keine überschreibende Datei-Kopie).
5. Erst nach bestätigter Landung wird der Worktree entfernt. Die Lesson steht auf `<default_branch>`; ein späterer `/retro`-Lauf findet sie.

## Alternative Flows
### A1: Keine Lessons-Änderung in diesem Worktree
- Kein `.claude/lessons/*.md` im Worktree geändert → kein zusätzlicher Datei-Anteil, Landung verläuft unverändert. Kein Fehler, kein Leer-Commit.

### A2: Parallele Landung — konkurrierender newest-first-Prepend
- Zwei Stories prependen zeitnah je eine Lesson in dieselbe `.claude/lessons/<rolle>.md`. Story A landet zuerst; Story B rebaset/merged danach. Der oben-am-Anfang-Konflikt wird **additiv** aufgelöst: beide Blöcke bleiben erhalten, newest-first nach Datums-Kopf, kein Eintrag geht verloren oder wird dupliziert.

### E1: Projekt ignoriert Lessons bewusst (`.claude/lessons/` gitignored)
- Ist `.claude/lessons/` im Ziel-Repo gitignored (bewusste Ephemer-Entscheidung, z.B. agent-flow-eigenes Repo, `.gitignore`), werden Lessons **nicht** zwangs-hinzugefügt (kein `git add -f`). Kein Fehler — dieses Projekt hat Lessons bewusst flüchtig gewählt.

## Acceptance-Kriterien
<!-- Nummeriert, testbar. Board-Items referenzieren diese Nummern. AC-IDs sind stabil. -->

### Immer-mitnehmen (Enforcement-Floor in cicd)
- **AC1** — **Jede** Landung durch `cicd` (`ship`, beide Policies `direct` **und** `pr`) bezieht **jede im Story-Worktree geänderte, getrackte** `.claude/lessons/*.md` in denselben Commit/PR ein — **auch dann**, wenn die Story-Dateiliste (SHIP-TRIGGER bzw. Dispatch-Instruktion) sie **nicht** namentlich nennt. `cicd` behandelt getrackte `.claude/lessons/*.md` als **immer-Teil-der-Landung**-Meta-Dateien (analog zum retro-Cooldown-Stempel).
- **AC2** — Diese Regel ist eine **generische `cicd`-Regel** (in `agents/cicd.md` verankert), **unabhängig** von der konkreten Story und **unabhängig** von `merge_policy`. Sie setzt **nicht** voraus, dass der Orchestrator die Lessons-Pfade explizit aufzählt — der Enforcement-Floor liegt in `cicd` (Defense-in-Depth gegen eine vergessene Dateiliste).

### Belt (Orchestrator-Seite in skills/flow)
- **AC3** — `skills/flow/SKILL.md` (§5 Landen / SHIP-Handoff) instruiert `cicd` **nicht mehr**, „nur" die konkreten Implementierungs-/Test-Dateien zu landen. Der Abschnitt hält explizit fest, dass **repo-versionierte Meta-Dateien** (`.claude/lessons/*.md`) **immer** mit der Landung fahren. Das ist der Gürtel zu AC1/AC2 (Hosenträger); die Garantie hängt nicht am Gedächtnis des Orchestrators.

### Kein Überschreiben — additiver Merge (parallele Landungen)
- **AC4** — **Kein Datenverlust bei parallelen Landungen:** Landet eine Story, deren Worktree eine Lessons-Datei geändert hat, dürfen Einträge, die eine **zwischenzeitlich gelandete** (aber noch nicht integrierte) Parallel-Story hinzugefügt hat, **nicht** verloren gehen. Die Lessons-Änderung wird als **Commit auf dem Story-Branch** geführt und fährt durch die normale Merge-/Rebase-Maschinerie. Eine **überschreibende Datei-Kopie** des Worktree-Standes auf `<default_branch>` ist **verboten** (sie würde bereits gelandete Fremd-Lessons klobbern).
- **AC5** — **Newest-first-Union bei Konflikt:** Erzeugt das Landen (Rebase/Merge) einen Konflikt in einer `.claude/lessons/*.md` (typisch bei konkurrierenden Prepends am Datei-Anfang), löst `cicd` ihn **additiv** auf: **beide** Blöcke bleiben erhalten, geordnet **newest-first** nach dem Datums-Kopf jedes Eintrags, **kein** Eintrag wird verworfen **oder** dupliziert. *(deckt A2)*

### Guards & Sichtbarkeit
- **AC6** — **Nur getrackte Dateien, kein Zwangs-Add:** Es werden ausschließlich Dateien mitgenommen, die in git **getrackt** sind. Ist `.claude/lessons/` im Ziel-Repo **gitignored** (bewusste Ephemer-Entscheidung), fügt `cicd` sie **nicht** per `git add -f` hinzu und meldet keinen Fehler. *(deckt E1)*
- **AC7** — **Reihenfolge-Garantie vor Teardown:** Der Worktree wird erst **nach** bestätigter Landung entfernt. Da `cicd` die Lessons-Delta als Teil des Landungs-Commits/PR führt (AC1/AC4) und die Teardown-Stufe der Landung nachgelagert ist, kann `git worktree remove --force` keine noch nicht committete Lessons-Änderung mehr verschlucken.
- **AC8** — **Sichtbarkeit im Handoff:** `cicd` meldet in seinem `/flow`-Handoff, ob Lessons-Deltas gelandet wurden (Zeile `Lessons: <n> Datei(en) gelandet` bzw. `Lessons: keine`). Macht die Regel beobachtbar und schützt vor stiller Regression (Drift-Gate-Anker für den reviewer).

> **Traceability:** Jeder Test trägt das kanonische Trace-Tag `@trace flow-lessons-landing#AC<n>`
> gemäss `knowledge/<lang>.md` → `## Spec-Tagging`. Der `tester` rechnet das Coverage-Gate
> (jede genannte AC ≥ 1 deckender Test). Details: `docs/architecture/traceability-subsystem.md`.

## Verträge
- **Betroffene Definitionen:** `agents/cicd.md` (Enforcement-Floor, AC1/AC2/AC5/AC6/AC8) · `skills/flow/SKILL.md` §5 (Belt, AC3; SR1-Teardown-Reihenfolge, AC7).
- **Immer-mitnehmen-Menge:** `.claude/lessons/*.md` (getrackt). Der bestehende `.claude/lessons/.retro-last-run`-Stempel bleibt wie gehabt (eigener Persistenz-Pfad in `agents/retro.md` 3a) — diese Spec erweitert das gleiche Prinzip auf die `*.md`-Lessons.
- **Merge-Mechanik (AC4/AC5):** Lessons-Änderungen als Commit auf dem Story-Branch führen; Landung via bestehender `cicd`-Merge-/Rebase-Sequenz. Konfliktauflösung in `.claude/lessons/*.md` = additive Union, newest-first nach Datums-Kopf. Eine optionale Helfer-Mechanik (z.B. `scripts/lessons-merge.sh` als deterministischer Union-Merger) ist zulässig, aber Implementierungs-Detail — der Vertrag ist das **Verhalten** (kein Eintrag verloren/dupliziert), nicht das Skript.
- **Erkennungs-Heuristik „getrackt":** `git ls-files --error-unmatch <pfad>` bzw. `git check-ignore` — nur getrackte, nicht-ignorierte Pfade werden einbezogen (AC6).

## Edge-Cases & Fehlerverhalten
- **E1:** `.claude/lessons/` gitignored → kein Zwangs-Add, kein Fehler (AC6).
- **E2:** Story-Worktree hat **keine** Lessons-Änderung → kein zusätzlicher Datei-Anteil, kein Leer-Commit (A1).
- **E3:** Merge-Konflikt am Datei-Anfang durch konkurrierende Prepends → additive Union, kein Verlust/Dupe (AC5).
- **Dogfooding-Testbarkeit:** Da agent-flow sein **eigenes** `.claude/lessons/` gitignored, kann ein mechanischer Test in agent-flow selbst die getrackte-Lessons-Landung nicht 1:1 nachstellen; ein Smoke muss ein **Konsumenten-Szenario** simulieren (temp-Repo mit getrackter `.claude/lessons/coder.md`, zwei Branches mit konkurrierenden Prepends) — vgl. `tests/`-Muster. Reine Doku-/Agent-Def-Diffs ohne Skript → `SKIPPED-DOC-ONLY` (Profil `language: md`).

## NFRs
- **Robustheit / kein stiller Datenverlust:** Der Kern-NFR — eine geschriebene Lesson darf nie still verloren gehen, weder durch eine kuratierte Dateiliste (AC1/AC3) noch durch eine überschreibende Parallel-Landung (AC4/AC5) noch durch Worktree-Teardown (AC7).
- **Nachvollziehbarkeit:** Jede Landung macht sichtbar, ob Lessons mitfuhren (AC8).
- **Kein Token-Overhead:** Die Regel ist deterministische git-Mechanik im bestehenden `cicd`-Lauf — kein zusätzlicher Agent-Dispatch, kein LLM-Overhead.

## Nicht-Ziele
- **Keine** Änderung an `agents/coder.md`, `agents/reviewer.md`, `agents/tester.md`: Diese schreiben ihre Lessons bereits **korrekt** in `.claude/lessons/<rolle>.md` (belegt: `agents/reviewer.md` §7 „Tier-1-Write-back"; coder liest/nutzt sie als VERBINDLICH; dev-gui-S-225-Handoff-Beleg). Der Defekt liegt **ausschließlich** im **Landungs-Schritt** (`cicd` trägt die Datei nicht mit), **nicht** im **Schreib-Schritt**. Diese Klarstellung verhindert, dass spätere Reviews fälschlich in den Rollen-Defs nach dem Fix suchen. *(Beobachtungs-Nebenbefund, außerhalb dieser Story: in `agents/tester.md` ist aktuell keine explizite Lesson-Write-back-Instruktion auffindbar, obwohl eine `tester.md`-Lessons-Datei existiert — separat zu klären, nicht Teil dieses Fixes.)*
- **Kein** Ändern des retro-Cooldown-Stempel-Pfads (`.retro-last-run`) — der bleibt unverändert (eigener Persistenz-Pfad in `agents/retro.md`).
- **Keine** Migration/Wiederherstellung der in der Nacht 2026-07-01→02 bereits verlorenen Lessons — nur Prävention ab jetzt.

## Abhängigkeiten
- `agents/cicd.md` (Abschluss-Arm — Ort des Enforcement-Floors) · `skills/flow/SKILL.md` §5 + SR1 (Orchestrator-Belt + Worktree-Teardown-Reihenfolge).
- Prinzip-Vorbild: `agents/retro.md` 3a + `docs/specs/retro-cooldown-persistence.md` (isolations-fester Persistenz-Pfad für `.claude/lessons/.retro-last-run`).
- Konsument der gelandeten Lessons: `agents/retro.md` (Modus A — Destillation der Tier-1-Lessons) + `docs/specs/metrics-retro-effectiveness.md`.
