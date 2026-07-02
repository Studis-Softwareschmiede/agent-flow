---
id: lessons-writeback-coverage
title: Lessons-Write-back für alle Loop-Rollen — tester, dba (Review), cicd schreiben Tier-1-Lessons
status: draft
version: 1
spec_format: use-case-2.0
---

# Spec: Lessons-Write-back-Abdeckung  (`lessons-writeback-coverage`)

> **Schicht 3 von 3.** Testbares **Verhalten + Verträge**, sprach-/paradigma-unabhängig (Intent, keine Idiome/Klassen).
> **Source of Truth** für `coder` (baut daraus), `tester` (testet die Acceptance-Kriterien + Coverage-Gate), `reviewer` (prüft den Diff dagegen — hartes Drift-Gate).
> **Betrifft die Fabrik selbst** (agent-flow): die Agenten-Definitionen `agents/tester.md`, `agents/dba.md` (nur Review-Modus), `agents/cicd.md`. Kein Konsumenten-Feature.

## Zweck
Nur `coder` und `reviewer` haben heute eine explizite Tier-1-Write-back-Instruktion (systemische, wiederkehrende Befunde als Regel in `.claude/lessons/<rolle>.md` festhalten). Die drei anderen Rollen, die regulär im `/flow`-Story-Loop dispatcht werden — `tester`, `dba` (Review-Modus) und `cicd` — **schreiben nie eine Lesson**, obwohl sie strukturell dieselben wiederkehrenden Muster sehen (Test-/Build-/Security-Fallen, DB-dialekt-spezifische Coder-Fehler, Infra-/Deploy-Fallstricke). Diese Spec schließt die Lücke: jede dieser Rollen bekommt einen zu `reviewer.md` §7 analogen Write-back-Schritt und liest die für sie relevanten projekt-lokalen Lessons zu Beginn.

## Kontext / Root Cause (belegt, per `grep -l "lessons" agents/*.md`)
- **Hat** Write-back: `agents/coder.md` (liest `.claude/lessons/coder.md` als VERBINDLICH), `agents/reviewer.md` §7 (schreibt coder-relevante Befunde nach `.claude/lessons/coder.md` + eigene Selbst-Lessons nach `.claude/lessons/reviewer.md`).
- **Fehlt** Write-back (kein Vorkommen von „lessons" in der Datei): `agents/tester.md`, `agents/cicd.md`. Bei `agents/dba.md` ist Write-back sogar **explizit ausgeschlossen** (Zeile 114: „Tier-1-Write-back ist Sache von `reviewer`, nicht von dir; sonst Doppel-Lessons").
- **Abgrenzung zu F-010 (`flow-lessons-landing`):** unterschiedliche Root Cause. F-010 = geschriebene Lessons gehen beim **Landen** des Worktrees verloren (`cicd` trägt die Datei nicht mit). Diese Spec = manche Rollen **schreiben nie** eine Lesson (Producer-Lücke). Beide betreffen dasselbe Subsystem (Lessons), sind aber funktional unabhängig — daher ein **eigenes Feature**, kein Hard-Depend auf F-010 (bewusste Entscheidung, s. Abhängigkeiten). F-010 ist der Landungs-Schritt, diese Spec der Schreib-Schritt.

## Design-Entscheidungen (fachlich begründet, aus dem Story-Auftrag)
- **Ziel 1 — Wohin schreibt jede Rolle?** Vorbild ist `reviewer.md` §7: Befunde werden an die Rolle geroutet, die sie **umsetzen** muss.
  - `tester` und `dba` (Review) schreiben **coder-umsetzbare** wiederkehrende Befunde nach `.claude/lessons/coder.md` **und** ihre **eigenen** Verfahrens-/Review-Lessons nach `.claude/lessons/tester.md` bzw. `.claude/lessons/dba.md`.
  - `dba`s Doppel-Lessons-Gefahr (läuft parallel zum `reviewer` auf demselben Diff) wird **nicht** durch Blanket-Ausschluss gelöst, sondern durch **Domänen-Trennung**: `dba` schreibt ausschließlich Befunde aus seiner **exklusiven DB-Dialekt-/Modell-Checkliste** (disjunkt zur generischen `reviewer`-Checkliste) — genau die DB-spezifischen Coder-Lessons, die der `reviewer` mangels Checkliste nie nach `coder.md` bringen würde. Ohne diese Regel gingen DB-spezifische Coder-Lessons dauerhaft verloren.
  - `cicd` schreibt **nur** in seine eigene `.claude/lessons/cicd.md` (Infra-/Deploy-/CI-Befunde sind nicht coder-umsetzbar — der `coder` fasst weder CI, Docker noch Deploy an). Die Destillation projekt-lokaler `cicd`-Lessons → globaler `${CLAUDE_PLUGIN_ROOT}/knowledge/cicd.md` bleibt `retro`s Aufgabe (PR+Gate) — konsistent mit `reviewer`s Hart-Grenze „NIE in globale Packs".
- **Ziel 2 — Wer liest die neuen Dateien?** Self-Lessons bleiben **rollen-privat** (analog `reviewer.md`s eigener `reviewer.md`, die nur der `reviewer` liest). `.claude/lessons/{tester,dba,cicd}.md` liest **nur** die je schreibende Rolle. **Keine** Lese-Pflicht dieser Dateien für Fremd-Rollen — der rollen-übergreifende Wissenstransfer läuft ausschließlich über die geteilte `.claude/lessons/coder.md` (die `coder`+`reviewer`+`tester`+`dba` ohnehin lesen). Fremd-Lesen der Self-Lessons wäre Token-Overhead ohne Mehrwert (Self-Lessons betreffen die je-eigene Verfahrens-Disziplin einer Rolle). Wichtig: eine Rolle, die eine Self-Lessons-Datei **schreibt**, muss sie zu Beginn auch **lesen** — sonst greift der Selbst-Lern-Loop nicht.
- **Ziel 3 — Neues Feature vs. unter F-010.** Neues Feature (`lessons-writeback-coverage`), da eigenständige Root Cause + eigene Dateimenge (`agents/{tester,dba,cicd}.md` statt `cicd.md`+`skills/flow`). Thematische Nähe zu F-010 wird als weiche Abhängigkeit vermerkt, **kein** Hard-Depend (die Producer-Änderung ist unabhängig umsetzbar).

## Acceptance-Kriterien
<!-- Nummeriert, testbar. Board-Items referenzieren diese Nummern. AC-IDs sind stabil. -->

### tester
- **AC1** — `agents/tester.md` erhält einen zu `reviewer.md` §7 analogen **Tier-1-Write-back-Schritt** (im „Vorgehen"-Abschnitt, nach dem Gate-Setzen): systemische, **wiederkehrende, coder-umsetzbare** Befunde (z.B. wiederkehrendes Build-/Test-/Dependency-/Security-Smoke-Muster) werden knapp als Regel in `.claude/lessons/coder.md` ergänzt (projekt-lokal, **newest-first**); **tester-eigene** Verfahrens-Lessons (Fehl-Diagnosen, Cache-/Umgebungs-Fallen wie in §2a, Smoke-Prozedur) in `.claude/lessons/tester.md` (anlegen falls nicht vorhanden, newest-first).
- **AC2** — `agents/tester.md` liest im „Zuerst lesen"-Abschnitt `.claude/lessons/coder.md` **und** `.claude/lessons/tester.md` (beide **VERBINDLICH falls vorhanden**) — Voraussetzung dafür, dass der Selbst-Lern-Loop wirkt und coder.md-Rückschreibungen nicht dupliziert werden.

### dba (nur Review-Modus)
- **AC3** — `agents/dba.md` erhält **im Review-Modus** (nach dem Gate-Setzen, Schritt 7) einen Tier-1-Write-back-Schritt: **DB-dialekt-/modell-spezifische**, wiederkehrende **coder-umsetzbare** Befunde (z.B. fehlendes Idempotenz-Pattern, Forward-only-Verstoß-Muster, Marker-Tabellen-Mutation) → `.claude/lessons/coder.md`; **dba-eigene** Review-Fehl-Calls / Pack-Fehldeutungen → `.claude/lessons/dba.md` (newest-first, anlegen falls nicht vorhanden). *(deckt A1)*
- **AC4** — Die bisherige **Blanket-Ausnahme** in `agents/dba.md` (Review-Modus-Hart-Grenze „Tier-1-Write-back ist Sache von `reviewer`, nicht von dir; sonst Doppel-Lessons") wird durch eine **domänen-getrennte** Regel ersetzt: `dba` schreibt **ausschließlich** Befunde aus seiner **exklusiven DB-Checkliste** (disjunkt zur generischen `reviewer`-Checkliste). Der Text macht die Nicht-Überlappung mit `reviewer` explizit, sodass keine Doppel-Lessons durch Überlappung entstehen.
- **AC5** — `agents/dba.md` liest `.claude/lessons/dba.md` (**VERBINDLICH falls vorhanden**) zu Beginn des **Review-Modus**. Der **Design-Modus** bleibt **unverändert** (kein Write-back, kein zusätzlicher Read — Einmal-Design-Rolle außerhalb des iterativen Loops). *(deckt A2)*

### cicd
- **AC6** — `agents/cicd.md` erhält einen Tier-1-Write-back-Schritt (im generellen Abschluss der ship-/Abschluss-Sequenz bzw. als eigener „Vorgehen"-Punkt): systemische, wiederkehrende **Infra-/Deploy-/CI-Fallstricke** (z.B. Branch-Protection-Workaround, Docker-Rollout-Eigenheit, gitleaks-False-Positive-Muster, CI-Pipeline-Falle) werden knapp als Regel in `.claude/lessons/cicd.md` ergänzt (projekt-lokal, newest-first, anlegen falls nicht vorhanden).
- **AC7** — `agents/cicd.md` schreibt **NICHT** nach `.claude/lessons/coder.md` (Infra-/Deploy-Befunde sind nicht coder-umsetzbar) und **NIE** in globale `${CLAUDE_PLUGIN_ROOT}/knowledge/cicd.md` (die Destillation projekt-lokal → global macht `retro` via PR+Gate). Der Write-back-Schritt nennt diese Grenze explizit. *(deckt E1)*
- **AC8** — `agents/cicd.md` liest `.claude/lessons/cicd.md` (projekt-lokal, **VERBINDLICH falls vorhanden**) im „Zuerst lesen"-Abschnitt — **zusätzlich** zum bereits gelesenen globalen `${CLAUDE_PLUGIN_ROOT}/knowledge/cicd.md` (das bleibt Lesequelle).

### Querschnitt
- **AC9** — **Self-Lessons bleiben rollen-privat:** `.claude/lessons/{tester,dba,cicd}.md` werden **nur** von der je schreibenden Rolle gelesen. Keine der Agent-Definitionen `agents/coder.md`, `agents/reviewer.md` (noch eine andere Rolle) erhält durch diese Story eine Lese-Pflicht auf eine fremde Self-Lessons-Datei. Der rollen-übergreifende Transfer läuft ausschließlich über `.claude/lessons/coder.md`.
- **AC10** — **Projekt-lokal, nie global:** Alle drei neuen Write-back-Schritte schreiben ausschließlich nach `.claude/lessons/*.md` (projekt-lokal) und **nie** in `${CLAUDE_PLUGIN_ROOT}/knowledge/`-Packs — jede der drei Agent-Definitionen trägt diese Grenze in ihren „Harte Grenzen"-Abschnitt (analog `reviewer.md` letzte Hart-Grenze).
- **AC11** — **Meta-Rollen unangetastet:** `agents/{architekt,designer,estimator,requirement,teamLeader,train}.md` werden **nicht** verändert (Einmal-/Meta-Rollen außerhalb des iterativen coder→reviewer→tester-Loops; kein wiederholter Diff-gegen-Spec-Abgleich, aus dem „systemische wiederkehrende Befunde" entstehen). *(deckt E2)*

> **Traceability:** Jeder Test trägt das kanonische Trace-Tag `@trace lessons-writeback-coverage#AC<n>`
> gemäss `knowledge/<lang>.md` → `## Spec-Tagging`. Der `tester` rechnet das Coverage-Gate
> (jede genannte AC ≥ 1 deckender Test). Details: `docs/architecture/traceability-subsystem.md`.

## Main Success Scenario
1. `/flow` dispatcht `tester` / `dba` (Review) / `cicd` im Story-Loop.
2. Die Rolle liest zu Beginn ihre relevante(n) projekt-lokale(n) Lessons-Datei(en) (AC2/AC5/AC8).
3. Die Rolle erledigt ihre Kernaufgabe (Gate/Landen) unverändert.
4. Erkennt die Rolle einen **systemischen, wiederkehrenden** Befund, ergänzt sie ihn knapp als Regel — coder-umsetzbar → `.claude/lessons/coder.md` (nur `tester`/`dba`), rollen-eigen → `.claude/lessons/<rolle>.md` (AC1/AC3/AC6).
5. Kein systemischer Befund → kein Write-back (kein Rauschen, kein Leer-Eintrag).

## Alternative Flows
### A1: dba findet DB-spezifischen Coder-Fehler, der reviewer nicht sieht
- Ein wiederkehrendes DB-Dialekt-Muster (z.B. fehlendes `CREATE INDEX IF NOT EXISTS`) landet in `.claude/lessons/coder.md`, obwohl der `reviewer` es mangels DB-Checkliste nicht erfasst. Kein Doppel-Eintrag, weil Domänen disjunkt (AC3/AC4).

### A2: dba im Design-Modus
- Design-Modus dispatcht → kein Lessons-Read, kein Write-back (AC5). Reine Einmal-Design-Rolle.

### E1: cicd-Befund ist infra-spezifisch
- Ein Branch-Protection-/Docker-Rollout-Muster landet in `.claude/lessons/cicd.md`, nicht in `coder.md` und nicht im globalen Pack (AC6/AC7).

### E2: Repo ohne betroffene Rolle im Lauf
- Läuft eine Story ohne DB-Layer, wird `dba` nicht dispatcht → keine dba-Lesson; unverändertes Verhalten. Meta-Rollen bleiben ohnehin außen vor (AC11).

## Verträge
- **Betroffene Definitionen:** `agents/tester.md` (AC1/AC2/AC10) · `agents/dba.md` Review-Modus (AC3/AC4/AC5/AC10) · `agents/cicd.md` (AC6/AC7/AC8/AC10).
- **Schreib-Menge:** `.claude/lessons/coder.md` (durch `tester`, `dba`), `.claude/lessons/tester.md`, `.claude/lessons/dba.md`, `.claude/lessons/cicd.md` — alle projekt-lokal, newest-first.
- **Lese-Menge (neu/ergänzt):** `tester` liest `coder.md`+`tester.md`; `dba` (Review) liest `dba.md`; `cicd` liest projekt-lokales `cicd.md` zusätzlich zum globalen `knowledge/cicd.md`.
- **Muster-Vorbild:** `agents/reviewer.md` §7 („Tier-1-Write-back") + „Zuerst lesen" Punkte 3/4 + letzte Hart-Grenze („NUR in `.claude/lessons/…` — NIE in globale Packs").
- **Format der Lessons-Einträge:** newest-first, knappe Regel, optional mit `[seen-in: …; promoted: …]`-Marker analog bestehender coder/reviewer-Lessons — Detail, nicht normativ hier.

## Edge-Cases & Fehlerverhalten
- **E1 (`.claude/lessons/` gitignored):** In agent-flow selbst ist `.claude/lessons/` gitignored (per `git check-ignore` bestätigt) — geschriebene Lessons sind hier flüchtig. Das ist **kein Fehler**; das Persistieren/Landen getrackter Lessons ist Gegenstand von F-010 (`flow-lessons-landing`), **nicht** dieser Spec. Diese Spec deckt ausschließlich den **Schreib-Schritt** (Producer).
- **E2 (kein Befund):** kein Write-back, kein Leer-Eintrag (Main Success Scenario 5).
- **Dogfooding-Testbarkeit:** reine Agent-Def-Diffs (Markdown) ohne Skript → `SKIPPED-DOC-ONLY` (Profil `language: md`); die AC sind über Struktur-/Vorkommens-Assertions gegen `agents/*.md` prüfbar (z.B. „`tester.md` enthält einen Write-back-Schritt nach `.claude/lessons/coder.md`").

## NFRs
- **Kein Token-Overhead im Normalfall:** Write-back nur bei systemischem Befund (nicht pro Lauf). Zusätzliche Lese-Last = kleine projekt-lokale Dateien.
- **Konsistenz mit bestehendem Muster:** Wortlaut/Struktur der neuen Schritte spiegeln `reviewer.md` §7 (kein neues Vokabular, keine neue Mechanik).
- **Kein stiller Wissensverlust:** die drei Rollen sehen die konkretesten wiederkehrenden Test-/DB-/Infra-Muster; deren Verlust (nie geschrieben) ist der zu schließende Defekt.

## Nicht-Ziele
- **Keine** Änderung an `agents/coder.md` / `agents/reviewer.md` (schreiben/lesen bereits korrekt; erhalten insb. **keine** Lese-Pflicht auf fremde Self-Lessons, AC9).
- **Keine** Landungs-/Persistenz-Mechanik für Lessons (das ist F-010 / `flow-lessons-landing`).
- **Keine** globale Pack-Pflege (`${CLAUDE_PLUGIN_ROOT}/knowledge/*.md`) — bleibt `retro` via PR+Gate.
- **Keine** Änderung an Meta-/Einmal-Rollen (AC11).
- **Kein** Write-back im dba-**Design**-Modus.

## Abhängigkeiten
- Muster-Vorbild: `agents/reviewer.md` §7 + „Zuerst lesen" + Hart-Grenzen.
- **Thematisch benachbart (weiche Abhängigkeit, KEIN Hard-Depend):** F-010 / `docs/specs/flow-lessons-landing.md` — dort werden die hier geschriebenen (getrackten) Lessons beim Landen mitgenommen. Ohne F-010 sind die Producer-Lessons in Repos mit getrackten Lessons noch nicht landungssicher; die Producer-Änderung ist davon unabhängig umsetzbar und in agent-flow selbst ohnehin ephemer (E1).
- Konsument der gelandeten Lessons: `agents/retro.md` (Modus A — Destillation der Tier-1-Lessons in globale Packs via PR+Gate).
</content>
</invoke>
