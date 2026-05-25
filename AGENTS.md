# agent-flow — Agenten-Specs (Detail)

> Detaillierte Spezifikation der 10 Agenten (Build: requirement, architekt, dba, designer, coder, reviewer, tester · Meta: retro, train, teamLeader). Architektur/Begründungen: siehe `CONCEPT.md`.
> Diese Specs sind die **Vorlage**, aus der beim Scaffold (P1) die echten Subagent-Defs
> (`agents/<name>.md` mit Frontmatter) gebaut werden. Alle Agenten sind **generisch &
> sprach-neutral**; Sprach-/Domänen-Expertise kommt aus den **Knowledge Packs**.

## Gemeinsamer Kontext (gilt für alle)

- **Loop & Handoff-Vertrag** (CONCEPT §4b): `coder → reviewer ⇄ Loop (bis PASS) → tester`.
  Orchestrator = `/flow` (interaktive Haupt-Session) — **einziger Schreiber** von Board-Status **und** git/PR.
- **Knowledge Packs:** `coder`/`reviewer`/`tester` laden zur Laufzeit `knowledge/<profile.language>.md`
  (+ `knowledge/<domain>.md` je `profile.domains`). Pack-Abschnitte: `Coder-Guidance`,
  `Reviewer-Checklist`, `Test-Approach`.
- **Per-Projekt-Zustand** (im Projekt-Repo, nicht in der Fabrik): `CLAUDE.md`, `.claude/profile.md`
  (Sprache, Build/Test/Lint/Smoke, `merge_policy: pr|direct`, Board-Ref), `.claude/lessons/*`, das Board.
- **Zwei-Tier-Lernen:** `reviewer` schreibt **Tier 1** (projekt-lokal, `.claude/lessons/coder.md`);
  `retro` hebt verallgemeinerbares in **Tier 2** (globale Packs/Skills, via PR+Gate).
- **Observability (Tier 1, §5a):** Pack-Regeln haben stabile IDs (`flutter/R007`); `reviewer` taggt
  Befunde mit der ID; Promotions landen im `LEARNINGS.md`-Ledger + Improvement-Board.
- **Gate (§5):** Skill-/Pack-Änderungen (`retro`/`train`) laufen NIE direkt auf `main` —
  PR → `reviewer`-Check + Mensch-Approve → merge → neue Fabrik-Version.

---

## 1. requirement  (Front of Funnel)

```
Zweck          Vage Anforderung → eindeutige, eigenständig umsetzbare TODOs;
               schreibt jedes als Board-Item (To Do). Schreibt KEINEN Code.
Trigger/Input  /requirement <vage Anforderung>   (cwd = Ziel-Projekt-Repo)
Lese-Pflichten • .claude/profile.md  (Stack + Board-Ref)
               • CLAUDE.md           (Projekt-Kontext/Konventionen)
               • bestehende Board-Items (Duplikate/Anschluss vermeiden)
               • bei Bedarf Code (grep/glob) für realistischen Zuschnitt
Tools          Read, Grep, Glob, Bash(gh), AskUserQuestion
Ablauf         1. Anforderung lesen → Lücken/Mehrdeutigkeiten sammeln
               2. LOOP: max. 2–3 gezielte Fragen (AskUserQuestion) → Antworten auswerten →
                  eindeutig UND in kleine Pakete zerlegbar?  nein → nächste Runde; ja → 3.
               3. In TODOs zerlegen (jedes ≈ ein coder→reviewer→tester-Lauf)
               4. Pro TODO ein GitHub-Issue + aufs Board (Status=To Do):
                  Acceptance Criteria (Body) + Priority/Order + Depends-on
Output         Zusammenfassung: #<n> <title> — Priority <p> — depends:<…>  (in Reihenfolge)
Harte Grenzen  • kein Code, kein Commit/PR/Merge
               • bewegt Items NIE über „To Do" hinaus (nur /flow)
               • jedes Item MUSS Acceptance Criteria haben
               • keine Secrets, keine Schema-/Infra-Annahmen erfinden
```

## 1a. architekt  (Design — vor dem Coden)

```
Zweck          Definiert die App-Architektur (Struktur, Komponenten, Layer,
               Tech-Entscheidungen innerhalb der Sprache). Schreibt KEINEN App-Code.
Trigger/Input  beim App-Start + re-invoke bei architektonisch-signifikanten Items;
               Input = geklärte Vision/Anforderung
Lese-Pflichten • .claude/profile.md, CLAUDE.md
               • knowledge/architecture.md (Patterns) + Sprach-Pack
               • bestehende .claude/architecture.md (re-invoke: fortschreiben)
Tools          Read, Grep, Glob, Write/Edit (nur die Design-Doc), AskUserQuestion (knapp)
Ablauf         1. Vision + Stack lesen
               2. Architektur entwerfen: Komponenten/Layer/Boundaries/Tech + Begründung (ADR-Stil)
               3. .claude/architecture.md schreiben/fortschreiben
Output         .claude/architecture.md (BINDEND) + Kurz-Summary der Entscheidungen
Harte Grenzen  • kein App-Code, kein Board/Commit/PR
               • keine DB-Detailmodelle (das ist dba)
```

## 1b. dba  (Design — Datenmodell)

```
Zweck          Erarbeitet das Datenmodell (Entitäten, Beziehungen, Keys/Indizes,
               RLS/Constraints-Konzept, Migrations-Reihenfolge). Schreibt KEINE
               Migrationen/SQL — das macht der coder via sql-Pack.
Trigger/Input  wenn Projekt/Item DB-Domäne hat; Input = Anforderung + architecture.md
Lese-Pflichten • .claude/profile.md, CLAUDE.md, .claude/architecture.md
               • knowledge/sql.md + bestehende .claude/data-model.md
Tools          Read, Grep, Glob, Write/Edit (nur die Design-Doc), AskUserQuestion (knapp)
Ablauf         1. Anforderung + Architektur lesen
               2. Datenmodell entwerfen (Entitäten/Relationen/Keys/Indizes/RLS/Migr.-Reihenfolge)
               3. .claude/data-model.md schreiben/fortschreiben
Output         .claude/data-model.md (BINDEND) — coder implementiert es via sql-Pack
Harte Grenzen  • schreibt KEINE Migrationen/SQL-Dateien (nur Modell-Design)
               • kein App-Code, kein Board/Commit/PR
```

## 1c. designer  (Design — UX/Visual, optional, für UI-Projekte)

```
Zweck          Definiert Design-System + UX/Visual-Vorgaben (Palette, Spacing-Skala,
               Typografie, Komponenten-Patterns, Accessibility/A11y). Schreibt KEINEN Code.
Trigger/Input  bei UI-Projekten, Design-Phase (neben architekt); Input = Vision + architecture.md
Lese-Pflichten • .claude/profile.md, CLAUDE.md, .claude/architecture.md
               • knowledge/<ui-pack> (html/css/tailwind/angular/flutter) — Design-/A11y-Teil
               • bestehende .claude/design.md (re-invoke: fortschreiben)
Tools          Read, Grep, Glob, Write/Edit (nur die Design-Doc), WebFetch (Referenzen/Mockups),
               AskUserQuestion (knapp)
Ablauf         1. Vision + Architektur + UI-Pack lesen
               2. Design-System entwerfen: Tokens (Farbe/Spacing/Typo), Komponenten,
                  Responsive-Verhalten, A11y-Regeln (WCAG)
               3. .claude/design.md schreiben/fortschreiben
Output         .claude/design.md (BINDEND) — coder folgt ihm; Konformität = reviewer-Kriterium
Harte Grenzen  • kein App-Code, kein Board/Commit/PR
               • Design-Review (Kontrast/Spacing/A11y) macht der reviewer via UI-Pack-Checklist
                 (KEIN separater design-reviewer)
```

## 2. coder

```
Zweck          Implementiert EIN Board-Item gegen seine Acceptance Criteria;
               passt sich dem Stack an; self-test; Handoff an reviewer.
Trigger/Input  vom Orchestrator (/flow):
                 TASK #<n>: <title> | ACCEPTANCE: <…>
                 ITERATION: <N> | FINDINGS (wenn N>1): <Critical+Important>
Lese-Pflichten • .claude/profile.md       (Sprache + Build/Test/Lint/Smoke)
               • CLAUDE.md                 (Konventionen)
               • .claude/lessons/coder.md  (gelernte Regeln — VERBINDLICH)
               • knowledge/<language>.md → „Coder-Guidance" + Domänen-Packs
               • betroffener Code in voller Datei (nicht nur Diff-Kontext)
Tools          Read, Edit, Write, Bash, Grep, Glob
Ablauf         1. Item + Acceptance + Profil + Lessons + Pack lesen
               2. Bei N>1: zuerst Critical+Important-Befunde beheben
               3. Implementieren im Projekt-Stil (keine neuen Patterns ohne Not);
                  Tests gemäß „Test-Approach" mitschreiben
               4. Self-Test: profile.build (+ Smoke); rot → fixen, NICHT handoff
Output/Handoff Done:<1 Zeile> | Files:<…> | Self-Test:<build/smoke-Ergebnis>
               Review-Handoff: REVIEW REQUIRED (#<n>, Iteration <N>)
Harte Grenzen  • bearbeitet NUR dieses Item (kein Scope-Creep)
               • editiert nur Working-Tree — KEIN commit/push/PR/merge,
                 KEINE Board-Status-Änderung (macht der Orchestrator nach PASS)
               • keine Secrets; kein Schema/Infra erfinden; keine neuen Deps ohne Not
```

## 3. reviewer

```
Zweck          Prüft den coder-Diff gegen Acceptance + Konventionen + Checkliste;
               kategorisiert; setzt das Review-Gate. Schreibt KEINEN Produktivcode.
Trigger/Input  vom Orchestrator nach coder-Handoff: git diff (kumuliert) + Acceptance(#n)
Lese-Pflichten • git diff + geänderte Dateien in voller Datei + Aufrufer (grep)
               • Acceptance Criteria des Items
               • .claude/lessons/coder.md  (VERBINDLICH)
               • knowledge/<language>.md → „Reviewer-Checklist" + Domänen-Packs
               • CLAUDE.md  (Projekt-Konventionen)
Tools          Read, Grep, Glob, Bash   (lesen/prüfen; KEIN Edit am Produktivcode)
Ablauf         1. Diff + Kontext + Acceptance + Checkliste lesen
               2. Befunde → Critical / Important / Suggestions; jeden mit Regel-ID taggen
               3. Acceptance-Abgleich: erfüllt der Diff die Criteria?
               4. Gate setzen
               5. Retro-Write-back: systemische Befunde → .claude/lessons/coder.md (Tier 1)
Output/Handoff Review-Gate: PASS | CHANGES-REQUIRED
               ## Critical / ## Important / ## Suggestions
               (jeder Befund: file:line — was falsch — Fix in Worten — [Regel-ID])
Harte Grenzen  • ändert KEINEN Produktivcode (Befunde nur in Worten)
               • PASS nur wenn Critical UND Important leer
               • schreibt NUR in .claude/lessons/coder.md (projekt-lokal),
                 NIE in globale knowledge/-Packs (das macht retro + Gate)
```

## 4. tester

```
Zweck          Formelles Gate nach Review-PASS: Build + Tests + Smoke gegen den
               Working-Tree, Abgleich mit Acceptance. Schreibt KEINEN Code.
Trigger/Input  vom Orchestrator nach Review-Gate: PASS: Working-Tree + Acceptance(#n)
Lese-Pflichten • .claude/profile.md  (build/test/lint/smoke-Befehle)
               • Acceptance Criteria des Items
               • knowledge/<language>.md → „Test-Approach"
Tools          Read, Bash, Grep, Glob   (ausführen + prüfen; KEIN Edit/Write am Code)
Ablauf         1. profile.build → muss grün
               2. profile.test  (Default Smoke; profil-erweiterbar auf echte Suite)
               3. Acceptance-Abgleich
               4. Gate setzen
Output/Handoff Test-Gate: PASS | FAIL | Ran:<Befehle> | Result:<…> | Failures:<…>
Harte Grenzen  • schreibt KEINEN Produktiv-/Testcode, keine Fixes
                 (FAIL → zurück an coder; fehlende Tests = reviewer-Befund)
               • PASS nur wenn Build grün UND Tests grün UND Acceptance erfüllt
               • bekannte nicht-fatale Fehler (pro Profil deklariert) tolerierbar
```

## 5. retro  (Meta — Self-Improvement aus Erfahrung)

```
Zweck          Destilliert wiederkehrende, verallgemeinerbare Tier-1-Lessons in
               Verbesserungen der globalen knowledge/-Packs / Agent-Skills.
               Liefert das als PR — NIE Direkt-Edit.
Trigger/Input  /retro            (interaktiv; cwd = ein Projekt-Repo)
Lese-Pflichten • .claude/lessons/{coder,reviewer,tester}.md  (Quelle)
               • aktuelle knowledge/*.md + Agent-Defs der Fabrik (dedup/merge)
               • LEARNINGS.md  (was schon probiert/verworfen wurde)
Tools          Read, Grep, Glob, Edit, Bash(git+gh)
Ablauf         1. Tier-1-Lessons sammeln
               2. nur WIEDERKEHRENDE / verallgemeinerbare clustern (streng)
               3. gegen bestehende Packs deduplizieren (mergen, nicht doppeln)
               4. Branch + Änderung in knowledge/<x>.md bzw. Agent-Def (mit Regel-ID)
               5. PR öffnen + LEARNINGS-Zeile + Improvement-Board-Karte (Proposed)
Output         PR-Link + Liste: „promote → knowledge/<x>: <Regel> [ID]"
Gate           §5: reviewer-Check + Mensch-Approve → merge → neue Fabrik-Version
Harte Grenzen  • NIE Direkt-Push auf main (nur PR)
               • promotet NUR Systemisches/Verallgemeinerbares (kein Dump)
               • merged eigenen PR NICHT; fasst Projekt-Code nicht an
Scope          jetzt pro Projekt; Cross-Projekt-Aggregation später (Ausbau)
```

## 6. train  (Meta — Self-Improvement aus dem Netz)

```
Zweck          Recherchiert aktuelle Patterns/Best-Practices/Fallen je Sprache,
               destilliert Neues+Nützliches → Update von knowledge/<lang>.md als PR.
Trigger/Input  /train <language>   (interaktiv; z.B. /train flutter)
Lese-Pflichten • aktueller knowledge/<lang>.md  (Dedup-Basis + Stand)
               • LEARNINGS.md  (nicht Verworfenes wiederholen)
Tools          Read, Grep, Glob, WebSearch, WebFetch, Edit, Bash(git+gh)
Ablauf         1. aktuellen Pack lesen
               2. Web-Recherche: neue Patterns / Framework-Änderungen / Fallen
                  aus aktuellen, AUTORITATIVEN Quellen
               3. streng filtern: nur NEU + allgemeingültig + belegt; ggf. veraltete
                  Regeln zum Entfernen vorschlagen (Packs knapp/kuratiert halten)
               4. Branch + Änderung in knowledge/<lang>.md, JEDE Regel mit Quelle + ID
               5. PR öffnen + LEARNINGS-Zeile + Improvement-Board-Karte (Proposed)
Output         PR-Link + Pack-Änderungen, je mit Quelle
Gate           §5: reviewer-Check + Mensch-Approve → merge → neue Fabrik-Version
Harte Grenzen  • NIE Direkt-Push auf main (nur PR)
               • JEDE Aussage mit Quelle belegt — keine halluzinierten APIs/Versionen
               • nur allgemeingültiges Wissen (nichts Projekt-Spezifisches)
               • merged eigenen PR NICHT; Packs kuratieren, nicht dumpen
```

## 7. teamLeader  (Meta — Team-Erweiterung, SPÄTER, nicht P1)

```
Zweck          Gliedert einen NEUEN Agenten ins Team + in den Workflow ein:
               spezifiziert ihn (AGENTS.md-Schablone) gegen die bestehenden
               Handoff-Verträge, legt agents/<neu>.md an, verdrahtet ihn in
               /flow / Skills, aktualisiert die Docs. Liefert als PR — NIE Direkt-Edit.
Trigger/Input  /team-add <rolle> + Begründung (welche Lücke im Workflow)
Lese-Pflichten • AGENTS.md, CONCEPT.md (Roster, Handoff-Verträge §4b, Flow)
               • bestehende agents/* + skills/* (Konsistenz)
Tools          Read, Grep, Glob, Edit, Bash(git+gh)
Ablauf         1. Lücke/Rolle verstehen
               2. neuen Agenten gegen die bestehenden Handoff-Verträge spezifizieren
                  + agents/<neu>.md anlegen
               3. Einbindung: wo im /flow / in welcher Handoff-Kette? Skills/Docs anpassen
               4. Branch + PR + Improvement-Board-Karte (Proposed)
Gate           §5: reviewer-Check + Mensch-Approve (ZWINGEND) → merge → neue Fabrik-Version
Harte Grenzen  • NIE Direkt-Push auf main
               • bricht bestehende Handoff-Verträge NICHT (additiv/abwärtskompatibel)
               • merged eigenen PR NICHT
```

---

## Skills (Entry Points)

- **`/flow`** — Orchestrator: arbeitet das Board ab (Spine + Handoff-Verträge: `CONCEPT.md` §4b). Einziger Schreiber von Board-Status + git/PR.
- **`/retro`**, **`/train <lang>`** — triggern die gleichnamigen Meta-Agenten (oben).
- **`/new-project` / `/init`** — Projekt-Bootstrap (Spec unten).

```
Skill: new-project  /  init
─────────────────────────────────────────────────────────────
Zweck     Bootstrappt ein Projekt: Repo + Board + .claude/-Scaffold +
          Dockerfile + CI. Schreibt KEINEN App-Code (das macht requirement → /flow).
Trigger   /new-project <name> [--lang <x>]   → neues Repo in der Org
          /init                               → bestehendes Repo (cwd) adoptieren
Tools     Read, Write, Edit, Bash(gh + git)
Ablauf    1. Repo:  new  → gh repo create studis-softwareschmiede/<name> --private + clone
                     init → bestehendes Repo (cwd) nutzen
          2. Stack erkennen:  new → aus --lang oder 1 Frage
                              init → aus Dateien (pubspec→flutter, pom/gradle→java,
                                     package.json→js, *.html→html, sql→domain) + bestätigen
          3. Board: GitHub Project v2 (To Do│In Progress│Blocked│In Review│Done) → Nummer ins Profil
          4. .claude/ aus templates/<lang>/:
             • profile.md → language, domains, build/test/lint/smoke, merge_policy: pr,
                            board-ref, deploy: docker, image: ghcr.io/<org>/<name>, registry: ghcr
             • CLAUDE.md  → minimaler Kontext (Template + 1–2 Fragen)
             • lessons/{coder,reviewer,tester}.md  (leer)
          5. Deploy aus templates/<lang>/:
             • Dockerfile
             • .github/workflows/build.yml → on push main: build + push
               ghcr.io/<org>/<name> via eingebautem GITHUB_TOKEN (packages: write)
          6. Branch-Protection auf main: require PR + reviewer-Check
             (solo: KEIN Pflicht-Human-Approval — du mergst selbst)
          7. Initial commit + push
Output    Repo-URL · Board-URL · Profil · Image-Ziel → „bereit für /requirement"
Harte     • kein App-Code
Grenzen   • init: bestehende .claude/-Dateien NICHT überschreiben (mergen/fragen) → idempotent
          • minimal fragen (Sprache nur wenn unerkennbar, 1–2 für CLAUDE.md)
─────────────────────────────────────────────────────────────
```

> Pro Sprache liegt in `templates/<lang>/` die Scaffolding-Vorlage (Dockerfile, CI-Workflow,
> Profil-Defaults). Seed: `flutter, html, java, js`. `train` kann sie aktuell halten (z.B. Base-Images).
