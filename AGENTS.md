# agent-flow — Agenten-Specs (Detail)

> Detaillierte Spezifikation der 15 Agenten (Build: requirement, architekt, dba, designer, estimator, coder, reviewer, tester · Meta: retro, train, regression-define, regression-heal, cicd, teamLeader, red-team). Architektur/Begründungen: siehe `CONCEPT.md`.
> Diese Specs sind die **Vorlage**, aus der beim Scaffold (P1) die echten Subagent-Defs
> (`agents/<name>.md` mit Frontmatter) gebaut werden. Alle Agenten sind **generisch &
> sprach-neutral**; Sprach-/Domänen-Expertise kommt aus den **Knowledge Packs**.

## Gemeinsamer Kontext (gilt für alle)

- **Loop & Handoff-Vertrag** (CONCEPT §4b): `coder → reviewer ⇄ Loop (bis PASS) → tester → cicd (ship)`.
  Orchestrator = `/flow` (interaktive Haupt-Session) — **einziger Schreiber** von Board-Status. Git/PR-Abschluss-Operationen delegiert `/flow` an `cicd` als ausführenden Abschluss-Arm (Beauftragung via SHIP-TRIGGER); die konzeptuelle Hoheit über den Flow-Ablauf und die Board-Übergänge bleibt beim Orchestrator.
  (`/upgrade` erweitert das additiv: initialer Plan-Commit + Item-Anlage + Profil-Rückschreib am Lauf-Ende —
  `docs/architecture/upgrade-subsystem.md` §3/§7; Item-Status-Übergänge bleiben `/flow`-Hoheit.)
- **Session-Rotation (Default, auch headless, Spec `docs/specs/flow-session-rotation.md`):** `/flow` arbeitet pro Lauf **eine** Story (bzw. einen SR1-Parallel-Batch) ab und beendet die Session danach erfolgreich (Exit 0) — kein automatisches Weiterziehen zum nächsten Item; äußere Schleifen (dev-gui `ProjectDrain`, Nachtwächter) übernehmen die Rotation. Grund: Ø Cache-Read wuchs sonst in einer 13-Story-Session von 82k auf 298k Token (Messung 2026-07-02) — linear statt quadratisch wachsender Kontext über ein Board. `--all` (interaktives Opt-in) behält das bisherige Bis-Board-leer-Verhalten.
- **Knowledge Packs:** `coder`/`reviewer`/`tester` laden zur Laufzeit `knowledge/<profile.language>.md`
  (+ `knowledge/<domain>.md` je `profile.domains`). Pack-Abschnitte: `Coder-Guidance`,
  `Reviewer-Checklist`, `Test-Approach`.
- **Security (querschnittlich, angehoben):** `knowledge/security.md` mit **⚑ Floor**, den `coder` (sicher
  bauen) und `reviewer` (Floor-Befunde = Critical) **IMMER** anwenden — auch ohne `domains:[security]`,
  weil Build/Smoke/AC Sicherheitslücken nicht sehen. Voller Pack bei `domains:[security]`. Automatik:
  CI-**Secret-Scan** (gitleaks, harter Gate vor dem Image, `build.yml`) + `tester`-Security-Smoke
  (Secret-Scan + Dependency-Audit). Security-Anforderungen werden **AC** (→ Drift-Gate). KEIN eigener
  security-reviewer (Pack-Prinzip). Floor ≠ Gold-Plating (`coder/R01`): Hygiene ist Pflicht, fügt aber
  keine user-sichtbaren Features hinzu.
- **Per-Projekt-Zustand** (im Projekt-Repo, nicht in der Fabrik): `CLAUDE.md`, `.claude/profile.md`
  (Sprache, Build/Test/Lint/Smoke, `merge_policy: pr|direct`, `cost_mode: low-cost|balanced|max-quality`, Board-Ref), `.claude/lessons/*`, das Board.
- **Modell-Wahl je Agent (Cost-Mode, Token-Hebel):** das `model:`-**Frontmatter** jedes Agenten ist der **`balanced`-Default**, NICHT eine fixe Zuordnung. Der aktive Cost-Mode (`--cost`-Argument > `profile.cost_mode` > `balanced`) überschreibt es zur Laufzeit per `model`-Override beim Task-Dispatch — `balanced` setzt keinen Override (Frontmatter gilt). Die bindende Rolle×Modus-Matrix + Auflösungs-/Override-Mechanik: `docs/architecture/model-tier-subsystem.md` (Referenz-Tabelle `knowledge/model-tiers.md`). Beim Justieren der Modelle die Matrix pflegen, nicht das Frontmatter.
- **Spec-getriebene Doku (CONCEPT §4d):** durable, sprach-neutrale Source of Truth unter `docs/` —
  `concept.md` → `architecture.md`/`data-model.md`/`design.md` (Detailkonzept) → `specs/<feature>.md`
  (testbare Acceptance-Kriterien AC1…). `requirement` schreibt sie, `coder`/`reviewer`/`tester` konsumieren
  sie; Board-Items referenzieren **Spec + AC-Nummern** (nicht eingebettete Kriterien). **Hartes Drift-Gate:**
  ein Diff, der beobachtbares Verhalten ohne Spec-Delta ändert → reviewer `CHANGES-REQUIRED`; Code + Spec
  landen im selben Commit/PR. `.claude/` hält nur Prozess-State (profile, lessons).
- **Traceability (Spec↔Test):** Jeder Test trägt das kanonische Trace-Tag
  `@trace <spec-slug>#AC<n>[,BR-NNN]` im sprach-idiomatischen Format (`knowledge/<lang>.md` →
  `## Spec-Tagging`). Der `tester` parst die Tags und rechnet das **Coverage-Gate** (jede genannte AC +
  jede referenzierte BR ≥ 1 deckender Test). Geschäftsregeln (`BR-NNN`) leben zentral in
  `architecture.md`/`data-model.md`; Specs referenzieren sie. Map = abgeleitet, nie handgepflegt.
  Source of Truth: `docs/architecture/traceability-subsystem.md`.
- **Zwei-Tier-Lernen:** `reviewer` schreibt **Tier 1** (projekt-lokal, `.claude/lessons/coder.md`);
  `retro` hebt verallgemeinerbares in **Tier 2** (globale Packs/Skills, via PR+Gate). Der `security`-Pack
  bekommt dafür **zwei kollisionsfreie Lanes** (`docs/architecture/red-team-subsystem.md` §5): die **Norm-Lane**
  `security/R<NN>` (Hoheit `train`, externe Standards) und die **Einsatz-Lane** `security/E<NN>` (Hoheit `retro`,
  Erfahrung aus echten Läufen). Der `red-team`-Agent (§10) ist der **Produzent echter Angriffs-Funde** und speist
  Tier 1 (`.claude/lessons/red-team.md`) für die Einsatz-Lane — er schließt damit den Sicherheits-Lernkreis, den
  `train` (Netz → Pack) und `reviewer`→`retro` (Diff → Pack) nur zur Hälfte decken.
- **Orchestrator-Lesson-Kanal (Tier 1, kanonisch):** `.claude/lessons/flow.md` ist der Tier-1-Kanal der
  Orchestrator-Ebene — geschrieben (prepend, newest-first) von `/flow`, dem Nachtwächter-Außenlauf **und** einer
  koordinierenden Owner-Session bei substanzieller Mehr-Feature-Arbeit (auch über general-purpose-Subagenten);
  gelesen zu Lauf-Beginn und **geharvestet von `retro`** gleichrangig zu den coder/reviewer/tester-Lessons.
  So wird auch Groß-Feature-Arbeit für die Retro sichtbar, nicht nur Klein-Story-Arbeit der Agenten.
- **Observability (Tier 1, §5a):** Pack-Regeln haben stabile IDs (`flutter/R007`); `reviewer` taggt
  Befunde mit der ID; Promotions landen im `LEARNINGS.md`-Ledger + Improvement-Board.
- **Gate (§5):** Skill-/Pack-Änderungen (`retro`/`train`) laufen NIE direkt auf `main` —
  PR → `reviewer`-Check + Mensch-Approve → merge → neue Fabrik-Version. **Ausnahme retro (seit
  2026-07-18, `docs/specs/retro-auto-merge.md`):** `reviewer`-`PASS` → **Auto-Merge** (squash), kein
  Mensch-Approve mehr; `CHANGES-REQUIRED` → Fix-Loop (max. 3 Iterationen) → offen + Meldung. `train`/
  `teamLeader` behalten das Gate unverändert.

---

## 1. requirement  (Front of Funnel)

```
Zweck          Vage Anforderung → durable Spec(s) unter docs/specs/ + referenzierende
               Board-Items (To Do). Schreibt KEINEN Code, committet nicht.
Trigger/Input  /requirement <vage Anforderung>   (cwd = Ziel-Projekt-Repo)
Lese-Pflichten • .claude/profile.md  (Stack + Board-Ref)
               • CLAUDE.md           (Projekt-Kontext/Konventionen)
               • docs/concept.md + docs/architecture.md (+ data-model/design) — Vorgaben
               • docs/specs/ (anschließen, nicht duplizieren) + docs/specs/_template.md
               • bestehende Board-Items (Duplikate/Anschluss vermeiden)
Tools          Read, Grep, Glob, Bash(gh), Write, Edit, AskUserQuestion
Ablauf         1. Anforderung lesen → Lücken/Mehrdeutigkeiten sammeln
               2. LOOP: max. 2–3 gezielte Fragen (AskUserQuestion) → eindeutig + zerlegbar?
                  nein → nächste Runde; ja → 3.
               3. Spec schreiben/fortschreiben (durable): docs/specs/<feature>.md aus _template —
                  bei verzweigungsreichem Verhalten optional Main Success Scenario + Alternative Flows
                  (Herleitung), daraus die nummerierten Acceptance-Kriterien (AC1…, **stabile IDs**,
                  jeder Alt-/Fehlerpfad ⇒ eine AC) + Verträge + Edge-Cases.
                  Geschäftsregeln NICHT in der Spec definieren — in architecture.md (Verhalten) bzw.
                  data-model.md (Validierung) als BR-NNN anlegen/fortschreiben und in der AC via (→ BR-NNN)
                  referenzieren. Scope/Struktur → concept.md/architecture.md nachziehen.
               4. In TODOs zerlegen — Default: **vertikaler Feature-Schnitt** (Oberfläche + Logik +
                  Datenhaltung pro Item, solange ≈ ein coder→reviewer→tester-Lauf passt,
                  vertical-slice-stories AC1). Schicht-Schnitt nur als begründete Ausnahme (AC2):
                  kein sichtbarer Anteil, oder vertikal würde XL sprengen → Split in gekoppelte
                  Teil-Stories (Frontend-Teil depends auf Backend-Teil, gleiche Priorität, gleiche
                  Spec) + Ein-Satz-Begründung im Item-Body. Pro TODO ein GitHub-Issue + Board
                  (To Do), Body: Spec-Ref + implements AC<…> + Priority + Depends-on
               5. Spec-Auto-Aktivierung (VERBINDLICH, spec-auto-activation): beim Anlegen der
                  referenzierenden Story jede in DIESEM Lauf neu angelegte Spec im Frontmatter auf
                  status: active stempeln (analog spec_format-Stempel) → Stories passieren board-ready
                  R2 ohne manuellen Freigabe-Schritt. Bestehende active/superseded-Specs NIE umstempeln;
                  ohne referenzierende Story bleibt die Spec draft.
Output         Specs: docs/specs/<…>.md (neu|aktualisiert)
               #<n> <title> — Spec <slug> (AC<…>) — Priority <p> — depends:<…>
Harte Grenzen  • kein Code, kein Commit/PR/Merge (Specs nur in den Working-Tree; commit macht der Skill)
               • bewegt Items NIE über „To Do" hinaus (nur /flow)
               • jedes Item MUSS auf eine Spec + AC-Nummern zeigen
               • Geschäftsregeln leben in architecture.md/data-model.md (BR-NNN), nie dupliziert in Specs
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
               • bestehende docs/architecture.md (re-invoke: fortschreiben)
Tools          Read, Grep, Glob, Write/Edit (nur die Design-Doc), AskUserQuestion (knapp)
Ablauf         1. Vision + Stack lesen
               2. Architektur entwerfen: Komponenten/Layer/Boundaries/Tech + Begründung (ADR-Stil)
               3. docs/architecture.md schreiben/fortschreiben
Output         docs/architecture.md (BINDEND) + Kurz-Summary der Entscheidungen
Harte Grenzen  • kein App-Code, kein Board/Commit/PR
               • keine DB-Detailmodelle (das ist dba)
```

## 1b. dba  (Design — Datenmodell)

```
Zweck          Erarbeitet das Datenmodell (Entitäten, Beziehungen, Keys/Indizes,
               RLS/Constraints-Konzept, Migrations-Reihenfolge). Schreibt KEINE
               Migrationen/SQL — das macht der coder via sql-Pack.
Trigger/Input  wenn Projekt/Item DB-Domäne hat; Input = Anforderung + architecture.md
Lese-Pflichten • .claude/profile.md, CLAUDE.md, docs/architecture.md
               • knowledge/sql.md + bestehende docs/data-model.md
Tools          Read, Grep, Glob, Write/Edit (nur die Design-Doc), AskUserQuestion (knapp)
Ablauf         1. Anforderung + Architektur lesen
               2. Datenmodell entwerfen (Entitäten/Relationen/Keys/Indizes/RLS/Migr.-Reihenfolge)
               3. docs/data-model.md schreiben/fortschreiben
Output         docs/data-model.md (BINDEND) — coder implementiert es via sql-Pack
Harte Grenzen  • schreibt KEINE Migrationen/SQL-Dateien (nur Modell-Design)
               • kein App-Code, kein Board/Commit/PR
```

## 1c. designer  (Design — UX/Visual, optional, für UI-Projekte)

```
Zweck          Definiert Design-System + UX/Visual-Vorgaben (Palette, Spacing-Skala,
               Typografie, Komponenten-Patterns, Accessibility/A11y). Schreibt KEINEN Code.
Trigger/Input  bei UI-Projekten, Design-Phase (neben architekt); Input = Vision + architecture.md
Lese-Pflichten • .claude/profile.md, CLAUDE.md, docs/architecture.md
               • knowledge/<ui-pack> (html/css/tailwind/angular/flutter) — Design-/A11y-Teil
               • bestehende docs/design.md (re-invoke: fortschreiben)
Tools          Read, Grep, Glob, Write/Edit (nur die Design-Doc), WebFetch (Referenzen/Mockups),
               AskUserQuestion (knapp)
Ablauf         1. Vision + Architektur + UI-Pack lesen
               2. Design-System entwerfen: Tokens (Farbe/Spacing/Typo), Komponenten,
                  Responsive-Verhalten, A11y-Regeln (WCAG)
               3. docs/design.md schreiben/fortschreiben
Output         docs/design.md (BINDEND) — coder folgt ihm; Konformität = reviewer-Kriterium
Harte Grenzen  • kein App-Code, kein Board/Commit/PR
               • Design-Review (Kontrast/Spacing/A11y) macht der reviewer via UI-Pack-Checklist
                 (KEIN separater design-reviewer)
```

## 1d. estimator  (Design-Vorstufe — Aufwandsschätzung für L/XL, vor coder)

```
Zweck          Schätzt vorab den Aufwand ("Dispo") einer L/XL-Story — relativ gegen
               Referenz-Stories (kuratierte Anker + ähnlichste abgeschlossene Stories
               als Few-shot); liefert dispo_est (EP) + Token-Erwartung + Begründung +
               ggf. Split-Empfehlung. Schreibt NICHTS ins Board, kein Code, kein Commit.
Trigger/Input  von /flow (Task), nur wenn size_est ∈ {L, XL} (oder --estimate explizit);
               S/M werden rein heuristisch geschätzt, ohne estimator-Dispatch
Lese-Pflichten • .claude/profile.md  (lang + cost_mode)
               • die Story (board/stories/<id>.yaml) + referenzierte Spec docs/specs/<feature>.md
                 (Acceptance-Kriterien = Umfang, Risikotreiber)
               • knowledge/reference-stories.md  (kuratierter Anker-Katalog, scale-aware S/M/L/XL)
               • .claude/metrics/baseline.json  (ep_per_token, medians, estimator_bias, forecast_mae)
               • .claude/metrics/items.jsonl  (Historie für Retrieval ähnlichster Stories)
               • .claude/lessons/estimator.md  (projekt-lokal, VERBINDLICH falls vorhanden)
Tools          Read, Grep, Glob, Bash
Ablauf         1. Fingerprint extrahieren (lang, labels, n_ac, n_comp)
               2. Few-shot-Menge bauen: Anker (S/M/L/XL) + Top-K Retrieval ähnlichster
                  abgeschlossener Stories aus items.jsonl (Ähnlichkeitsfunktion S1)
               3. Relativ schätzen (Vergleich gegen Beispiele, nie eine freie absolute Zahl)
               4. Bias-Korrektur aus baseline.json.estimator_bias anwenden (Schnitt-Kaskade
                  lang|cost_mode|size → lang|cost_mode → lang → kein Schnitt), Cap ±0.50
               5. Ableiten: tok_est, confidence, estimate_note (Anker-Bezug + Haupttreiber)
               6. Cold-Start/Fallback: zu wenig Vergleichsdaten → dispo_est = null,
                  confidence = low, Grund in estimate_note; blockiert nie den Loop
               7. Split-Empfehlung bei XL + hoher Unsicherheit (rein beratend)
               8. Tier-1-Write-back: systemische Verfahrens-/Kalibrierungs-Lesson →
                  .claude/lessons/estimator.md
Output         JSON: dispo_est, tok_est, confidence, estimate_note, split_suggestion
               (an /flow — persistiert die Felder auf der Story)
Harte Grenzen  • schreibt nichts ins Board/YAML/Ledger — /flow persistiert
               • schreibt NICHT baseline.json.estimator_calibration (Single-Writer retro, Modus E)
               • kein Code, kein Commit/PR/Merge
               • ein LLM-Durchgang pro L/XL-Story; relativ gegen Beispiele, nie frei erfunden
               • Tier-1-Write-back NUR nach .claude/lessons/estimator.md — NIE nach
                 .claude/lessons/coder.md, NIE in globale knowledge/-Packs
```

## 2. coder

```
Zweck          Implementiert EIN Board-Item gegen die Spec (AC); passt sich dem Stack
               an; self-test; Handoff an reviewer.
Trigger/Input  vom Orchestrator (/flow):
                 TASK #<n>: <title> | SPEC: docs/specs/<feature>.md (AC<…>)
                 ITERATION: <N> | FINDINGS (wenn N>1): <Critical+Important>
Lese-Pflichten • die Spec docs/specs/<feature>.md  (PRIMÄRE Quelle: Verhalten + AC)
               • .claude/profile.md (Sprache + Build/Test/Lint/Smoke), CLAUDE.md
               • .claude/lessons/coder.md  (gelernte Regeln — VERBINDLICH)
               • knowledge/<language>.md → „Coder-Guidance" + Domänen-Packs
               • docs/architecture.md/data-model.md/design.md (falls vorhanden)
               • betroffener Code in voller Datei (nicht nur Diff-Kontext)
Tools          Read, Edit, Write, Bash, Grep, Glob
Ablauf         1. Spec-Sektion + AC + Vorgaben + Lessons + Pack lesen
               2. Bei N>1: zuerst Critical+Important-Befunde beheben
               3. Vor jedem Neucode-Baustein die Simplicity-Leiter absteigen (coder/R09,
                  Ponytail-Prinzip): AC-Bedarf → Wiederverwendung → Stdlib → Plattform-Feature →
                  installierte Dependency → erst dann Eigencode; kürzt nie an AC/Coverage-Gate/
                  Security-Floor/Detailkonzept/Lessons (docs/specs/coder-simplicity-ladder.md).
               3a. Implementieren im Projekt-Stil; Tests gemäß „Test-Approach" mitschreiben.
                  JEDER Test trägt das Trace-Tag gemäß knowledge/<lang>.md → „## Spec-Tagging"
                  (@trace <spec-slug>#AC<n>[,BR-NNN]) für die AC/BR, die er abdeckt.
               4. Spec-Drift vermeiden: kleine Lücke (Edge-Case/Feld/Statuscode) → Spec in
                  docs/specs/ mitpflegen; strukturell/Scope → als SPEC-LÜCKE melden
               5. Self-Test (targeted): nur vom Diff betroffene Tests + Lint auf geänderten
                  Dateien — nicht die komplette Suite (Tester-Gate exklusiv); rot → fixen, NICHT handoff
Output/Handoff Done:<1 Zeile> | Files:<… inkl. docs/specs falls präzisiert>
               Spec:<unverändert|AC<n> präzisiert|SPEC-LÜCKE:<…>> | Self-Test:<…>
               Review-Handoff: REVIEW REQUIRED (#<n>, Iteration <N>)
Harte Grenzen  • bearbeitet NUR dieses Item (kein Scope-Creep)
               • editiert nur Working-Tree (inkl. kleiner Spec-Präzisierung) — KEIN commit/push/PR/merge,
                 KEINE Board-Status-Änderung (macht der Orchestrator nach PASS)
               • Spec präzisieren = ok; Spec umschreiben (Scope/Architektur) = NICHT → melden
               • keine Secrets; kein Schema/Infra erfinden; keine neuen Deps ohne Not
```

## 3. reviewer

```
Zweck          Prüft den coder-Diff gegen die Spec (AC) + Konventionen + Checkliste;
               hartes Drift-Gate; setzt das Review-Gate. Schreibt KEINEN Produktivcode.
Trigger/Input  vom Orchestrator nach coder-Handoff: git diff (kumuliert) + Spec(#n, AC<…>)
Lese-Pflichten • git diff + geänderte Dateien in voller Datei + Aufrufer (grep)
                 (Diff kann docs/specs/ enthalten — coder darf Lücken präzisieren)
               • die Spec docs/specs/<feature>.md + AC + Detailkonzept-Docs (docs/*.md)
               • .claude/lessons/coder.md  (VERBINDLICH)
               • knowledge/<language>.md → „Reviewer-Checklist" + Domänen-Packs
               • CLAUDE.md  (Projekt-Konventionen)
Tools          Read, Grep, Glob, Bash   (lesen/prüfen; KEIN Edit am Produktivcode)
Ablauf         1. Diff + Kontext + Checkliste lesen
               2. Spec-Konformität: erfüllt der Code die AC? Verträge/Edge-Cases/NFRs?
                  Referenzierte BR-NNN existieren in architecture.md/data-model.md? (sonst Critical)
                  Tragen neue/geänderte Tests Trace-Tags (knowledge/<lang>.md → Spec-Tagging)? (fehlend = Important)
               3. Drift-Gate (HART): Diff ändert/erweitert beobachtbares Verhalten
                  (Endpunkte/UI/I-O/Fehler-Statuscodes/Datenfelder/NFR-Limits) ohne Spec-Delta
                  → Critical „Spec-Drift" → CHANGES-REQUIRED. (Refactor/Typo ohne Verhalten = kein Drift.)
               3a. Simplicity-Leiter-Check (reviewer/R10): Eigenbau, wo Wiederverwendung/Stdlib/
                  Plattform-Feature/installierte Dependency verfügbar war → Important, getaggt
                  coder/R09 (docs/specs/coder-simplicity-ladder.md AC4); kein neues Gate.
               4. Befunde → Critical / Important / Suggestions; jeden mit Regel-ID taggen
               5. Gate setzen
               6. Tier-1-Write-back: systemische Befunde → .claude/lessons/coder.md
Output/Handoff Review-Gate: PASS | CHANGES-REQUIRED
               ## Critical / ## Important / ## Suggestions
               (jeder Befund: file:line — was falsch — Fix in Worten — [Regel-ID])
Harte Grenzen  • ändert KEINEN Produktivcode (Befunde nur in Worten)
               • PASS nur wenn Critical UND Important leer (⇒ AC erfüllt + kein offener Drift)
               • schreibt NUR in .claude/lessons/coder.md (projekt-lokal),
                 NIE in globale knowledge/-Packs (das macht retro + Gate)
```

## 4. tester

```
Zweck          Formelles Gate nach Review-PASS: Build + Tests + Smoke gegen den
               Working-Tree, Abgleich mit den Spec-AC. Schreibt KEINEN Code.
Trigger/Input  vom Orchestrator nach Review-Gate: PASS: Working-Tree + Spec(#n, AC<…>)
Lese-Pflichten • .claude/profile.md  (build/test/lint/smoke-Befehle)
               • die Spec docs/specs/<feature>.md — die genannten AC = Abgleich-Maßstab
               • knowledge/<language>.md → „Test-Approach"
Tools          Read, Bash, Grep, Glob   (ausführen + prüfen; KEIN Edit/Write am Code)
Ablauf         1. profile.build → muss grün
               2. profile.test — VOLLE Suite (Default Smoke; profil-erweiterbar auf echte Suite),
                  NICHT auf vom Diff betroffene Tests begrenzt (einzige Stelle mit Voll-Garantie
                  pro Story; coder-Self-Test ist bewusst nur targeted, s. Abschnitt 2)
               2a. profile.lint — VOLLE Lint über das gesamte Projekt (nicht nur geänderte Dateien)
               3. AC-Abgleich + Coverage-Gate: Trace-Tags via Pack-Rezept (knowledge/<lang>.md →
                  Spec-Tagging) parsen. Jede genannte AC erfüllt UND von ≥1 Test getaggt; jede von diesen
                  AC referenzierte BR-NNN von ≥1 Test gedeckt. Lücke → FAIL (Grund: „TRACE-GAP: <spec>#<crit>").
               4. Gate setzen
Output/Handoff Test-Gate: PASS | FAIL | Ran:<Befehle> | Result:<…> | Failures:<…>
Harte Grenzen  • schreibt KEINEN Produktiv-/Testcode, keine Fixes
                 (FAIL → zurück an coder; fehlende Tests = reviewer-Befund)
               • PASS nur wenn Build grün UND Tests grün UND alle genannten AC erfüllt UND
                 Coverage-Gate grün (keine ungedeckte AC/BR)
               • bekannte nicht-fatale Fehler (pro Profil deklariert) tolerierbar
```

## 5. retro  (Meta — Self-Improvement aus Erfahrung)

```
Zweck          Destilliert wiederkehrende, verallgemeinerbare Tier-1-Lessons in
               Verbesserungen der globalen knowledge/-Packs / Agent-Skills.
               Liefert das als PR — NIE Direkt-Edit.
Trigger/Input  /retro            (interaktiv; cwd = ein Projekt-Repo)
Lese-Pflichten • .claude/lessons/{coder,reviewer,tester,flow}.md  (Quelle; flow.md = Orchestrator-Kanal, gleichrangig)
               • aktuelle knowledge/*.md + Agent-Defs der Fabrik (dedup/merge)
               • LEARNINGS.md  (was schon probiert/verworfen wurde)
Tools          Read, Grep, Glob, Edit, Bash(git+gh)
Ablauf         1. Tier-1-Lessons sammeln
               2. nur WIEDERKEHRENDE / verallgemeinerbare clustern (streng)
               3. gegen bestehende Packs deduplizieren (mergen, nicht doppeln)
               4. Branch + Änderung in knowledge/<x>.md bzw. Agent-Def (mit Regel-ID)
               5. PR öffnen + LEARNINGS-Zeile + Improvement-Board-Karte (Proposed)
Mechanik       NICHT ${CLAUDE_PLUGIN_ROOT} editieren (read-only Cache) → agent-flow-Source
               temp-klonen (gh repo clone), Branch, edit, push, gh pr create. Details: agents/retro.md.
Output         PR-Link + Liste: „promote → knowledge/<x>.md|agents/<role>.md: <Regel> [ID]"
Gate           §5, retro-Ausnahme: reviewer-Check → PASS → Auto-Merge (squash, kein Mensch-Approve);
               CHANGES-REQUIRED → Fix-Loop (max. 3 Iterationen) → offen + Meldung
               (`docs/specs/retro-auto-merge.md`)
Harte Grenzen  • NIE Direkt-Push auf main (nur PR) — auch nicht als Ausweichpfad bei Merge-Fehlschlag
               • promotet NUR Systemisches/Verallgemeinerbares (kein Dump)
               • mergt eigenen PR NUR nach dispatchtem reviewer-PASS; fasst Projekt-Code nicht an
Scope          jetzt pro Projekt; Cross-Projekt-Aggregation später (Ausbau)
```

## 6. train  (Meta — Self-Improvement aus dem Netz)

```
Zweck          Recherchiert aktuelle Patterns/Best-Practices/Fallen je Sprache,
               destilliert Neues+Nützliches → Update von knowledge/<lang>.md als PR.
Trigger/Input  /train <language>   (interaktiv; z.B. /train flutter)
               /train --bootstrap <pack-id> — fehlenden Pack ANLEGEN statt abbrechen
                 (Skelett aus Vorgänger + Sektion A aus Quellen + Solver-Constraints;
                  schreibt bei AGENT_FLOW_KNOWLEDGE_DIR in den Staging-Dir). Primär von
                  /upgrade Phase E. Vertrag: docs/architecture/upgrade-subsystem.md §8.
Lese-Pflichten • aktueller knowledge/<lang>.md  (Dedup-Basis + Stand)
               • LEARNINGS.md  (nicht Verworfenes wiederholen)
Tools          Read, Grep, Glob, WebSearch, WebFetch, Edit, Bash(git+gh)
Ablauf         1. aktuellen Pack lesen
               2. Web-Recherche aus PRIMÄR-/autoritativen Quellen (offizielle Docs,
                  Specs, Release-Notes/Changelogs) — KEINE Einzel-Blogs als Beleg
               3. streng filtern + priorisieren: bevorzugt FAKTISCHE Deltas (Deprecation/
                  neue stabile API/Breaking Change) statt subjektiver „Best-Practice";
                  MAX. 3 Regeln/Lauf; veraltete Regeln zum Entfernen vorschlagen
               4. Branch + Änderung in knowledge/<lang>.md, JEDE Regel mit Quell-Link + ID
               5. PR öffnen + LEARNINGS-Zeile + Improvement-Board-Karte (Proposed)
Mechanik       NICHT ${CLAUDE_PLUGIN_ROOT} editieren (read-only Cache) → agent-flow-Source
               temp-klonen, Branch, edit, push, gh pr create. Details: agents/train.md.
Output         PR-Link + Pack-Änderungen, je mit Quelle
Gate           §5: reviewer-Check + Mensch-Approve → merge → neue Fabrik-Version
Harte Grenzen  • NIE Direkt-Push auf main (nur PR); merged eigenen PR NICHT
               • JEDE Regel mit autoritativer Quelle (Link) belegt — keine halluzinierten
                 APIs/Versionen, keine Blog-Meinung als „Best-Practice"
               • MAX. 3 Regeln/Lauf, im Zweifel weniger; nur allgemeingültiges Wissen
```

## 7a. regression-define  (Meta — Regressionstests aus Specs definieren)

```
Zweck          Liest die Specs eines Bereichs/Verbunds, schlägt in Alltagssprache
               Testfälle für die dev-gui-Redaktionsschleife vor und übersetzt die vom
               Owner redigierte Fassung deterministisch in Playwright-Testdatei +
               Datentabelle + Begleitbeschreibung. Führt keine Testläufe aus, heilt
               nicht. Liefert immer als PR.
Trigger/Input  zwei Modi (modus: vorschlag | uebersetzen):
                 vorschlag:    projekt, bereich|verbund, stichworte[]
                 uebersetzen:  projekt, redigierter_vorschlag (JSON, vom Owner editiert)
Lese-Pflichten • docs/specs/regression-define.md  (primäre Quelle, AC1–AC8)
               • docs/specs/regression-playwright-conventions.md  (Layout/Fixtures)
               • docs/specs/regression-runner.md  (target:-Header-Vertrag, Secret-Injektion)
               • board/areas.yaml  (gültige Bereichs-ids)
               • .claude/profile.md  (merge_policy, default_branch)
               • knowledge/playwright.md → „Coder-Guidance" (fehlt: Graceful Degradation
                 auf templates/_shared/regression/tests-example/)
               • .claude/lessons/regression-define.md  (VERBINDLICH falls vorhanden)
Tools          Read, Grep, Glob, Write, Edit, Bash
Ablauf         Modus vorschlag: 1. Eingabe validieren (genau bereich ODER verbund)
                 2. Quell-Specs bestimmen (Frontmatter area: bzw. Verbund-Spec-Auswahl)
                 3. Testfälle in Alltagssprache ableiten (titel/schritte/pruefpunkte/
                    beispieldaten) + Secret-Vorabprüfung (Platzhalter statt Wert)
                 4. Rückgabeformat ausgeben (keine Datei geschrieben)
               Modus uebersetzen: 1. Owner-Fassung entgegennehmen (maßgebend, 1:1)
                 2. Ziel-Pfad bestimmen (bereich/verbund-Layout)
                 3. je Testfall: Secret-Check (HART, vor jedem Schreiben) → Datentabelle
                    → Testdatei (.spec.ts) → Begleitbeschreibung (target:, quell_specs:)
                 4. Auslieferung: eigener Branch + Commit + Push + PR (nie Direkt-Merge)
                 5. Tier-1-Write-back: systemisches Muster → .claude/lessons/regression-define.md
Output         Modus vorschlag: Rückgabeformat-JSON (projekt/ziel/quell_specs/vorschlag/target_vorschlag)
               Modus uebersetzen: Ziel-Pfade, Secrets ersetzt, Nicht-datengetrieben, PR-Link
Harte Grenzen  • führt KEINE Testläufe aus (das ist regression-runner)
               • heilt NICHT (regression-heal-Scope)
               • baut die dev-gui-Redaktionsoberfläche nicht
               • Secrets erscheinen NIE in erzeugten Dateien (HART) — Platzhalter statt Wert,
                 sonst Testfall ablehnen statt schreiben
               • Auslieferung ausschließlich als PR (HART) — nie Direkt-Merge/-Push
               • schreibt keinen Board-Status, keine Board-Felder
               • Tier-1-Write-back NUR nach .claude/lessons/regression-define.md
```

## 7b. regression-heal  (Meta — Selektor-Drift in Regressionstests heilen)

```
Zweck          Reagiert NUR auf einen bereits vorliegenden roten Regressions-Lauf,
               dessen Fehlschlag als UI-/Selektor-Drift klassifiziert ist (nicht echte
               Verhaltensänderung). Ermittelt via Playwright-Healer-Ansatz (Test Agents,
               Playwright ≥ v1.56) aktualisierte Locator/Selektoren, liefert IMMER als
               PR. Bei unsicherer Klassifikation eskaliert er (Lauf bleibt rot) —
               kein Maskieren echter Regressionen.
Trigger/Input  projekt, lauf (Run-ID/CTRF-Report-Pfad des roten Laufs),
               tests[] (optional — sonst aus dem CTRF-Report abgeleitet)
Lese-Pflichten • docs/specs/regression-heal.md  (primäre Quelle, AC1–AC5)
               • docs/specs/regression-runner.md  (CTRF-Report-Format/-Ort, target:-Modell)
               • docs/specs/regression-playwright-conventions.md  (Layout/Fixture-Muster)
               • .claude/profile.md  (merge_policy, default_branch)
               • knowledge/playwright.md → „Coder-Guidance"+„Reviewer-Checklist" (fehlt:
                 Graceful Degradation auf dokumentierten Healer-Ablauf)
               • .claude/lessons/regression-heal.md  (VERBINDLICH falls vorhanden)
Tools          Read, Grep, Glob, Write, Edit, Bash
Ablauf         1. Eingabe validieren (lauf vorhanden + Report lesbar, sonst kein Heilversuch)
               2. Playwright-Version prüfen (< 1.56 → Vorbedingungs-Lücke melden, nicht heilen)
               3. Fehlgeschlagene Tests aus CTRF-Report ermitteln
               4. Klassifikation je Test: Drift | echte Verhaltensänderung | unsicher
                  (HART — bei Verhaltensänderung/unsicher NICHT heilen, eskalieren)
               5. Reparatur-Diff erzeugen (nur die driftenden Locator-Zeilen)
               6. Diagnose formulieren (1–2 Sätze je geheiltem Test)
               7. Auslieferung: eigener Branch + Commit + Push + PR (nie Direkt-Merge)
               8. Kein Test geheilt → kein PR, nur Eskalations-Output
               9. Tier-1-Write-back: systemisches Muster → .claude/lessons/regression-heal.md
Output         Geheilt: [tests, …] | Eskaliert: [test: grund, …] | PR: <link|keiner+Grund>
Harte Grenzen  • Trigger ausschließlich ein bereits roter Lauf (HART) — kein eigener
                 Testlauf-Dispatch zur Rot-Erkennung
               • heilt NUR Selektor-Drift (HART) — bei Verhaltensänderung/Unsicherheit
                 kein Diff, keine Maskierung, Lauf bleibt rot
               • Auslieferung ausschließlich als PR (HART) — nie Direkt-Merge/-Push
               • kein PR ohne Diff (alle Fehlschläge Verhaltensänderung/unsicher)
               • definiert/übersetzt keine neuen Tests (regression-define-Scope)
               • schreibt keinen Board-Status, keine Board-Felder
               • Tier-1-Write-back NUR nach .claude/lessons/regression-heal.md
```

## 8. cicd  (Abschluss-Arm: Landen, CI-Watch, Rollout, Disk-Hygiene; Versionierung, CI-Pflege)

```
Zweck          Ausführender Abschluss-Arm des /flow-Orchestrators ab tester-PASS:
               (1) git-Landen (merge + push gemäss merge_policy, im Auftrag von /flow),
               (2) GitHub-Workflow beobachten (gh run watch, CI-Watch-Gate),
               (3) lokaler Docker-Rollout (pull + recreate, NIEMALS restart),
               (4) Disk-Hygiene (docker image prune -f, Pflichtschritt).
               Zusätzlich: Rollback auf vorheriges Image/Tag, Build-Zeit-Versionsstempel
               (Dockerfile ARG/ENV + build.yml build-args), Versions-Endpunkt-Verifikation,
               laufende CI-Pipeline-Pflege (build.yml diagnostizieren + härten, gitleaks-Gate).
Trigger/Input  Nach tester-PASS (vom /flow-Orchestrator, SHIP-TRIGGER) ODER manuell:
               /cicd ship              — kanonische Abschluss-Sequenz (merge+push+CI-Watch+Rollout+Prune)
               /cicd rollout [<app>]   — nur Rollout (Code bereits gelandet)
               /cicd rollback <tag>    — auf bekannten Tag zurückrollen
               /cicd version-stamp     — Build-Metadaten in Dockerfile + CI einbauen
               /cicd ci-fix            — CI-Fehlschlag diagnostizieren + beheben
               /cicd status            — Container-Status + Version + CI
Lese-Pflichten • .claude/profile.md   (image, container_port, preview_port, deploy, default_branch, merge_policy)
               • CLAUDE.md            (Konventionen)
               • knowledge/cicd.md    (Patterns/Fallen: F01–F07, P01–P07)
Tools          Read, Bash, Grep, Glob, Edit, Write
Handoff-Kette  tester (PASS) → cicd-ship (merge+push → CI-Watch → Rollout → Prune)
                               → Rollout-Gate: PASS|FAIL|NEEDS-HUMAN + Version + Prune
               → /flow (Abschluss-Summary + Board-Done)
               Eintritt: nach tester-PASS (Vorbedingung erfüllt — cicd vertraut tester-Gate)
               Austritt: Rollout-Gate + Version + Prune-Ergebnis
Abgrenzung     • vs. /preview:        preview = ephemerer Dev-/PR-Container + Tunnel (bleibt unverändert)
                                       cicd    = git-Landen + CI-Watch + produktiver Rollout + Prune
               • vs. tester:          tester endet vor dem produktiven Image (Build+Test+Smoke im Working-Tree)
                                       cicd startet danach und vertraut dem tester-Gate
               • vs. new-project/init: scaffolden build.yml EINMAL beim Bootstrap
                                       cicd übernimmt die laufende PFLEGE danach
               • vs. upgrade:         upgrade = Stack-Versionen bumpen; cicd = CI-Betrieb + Rollout
               • App-Code:            NICHT cicd (das ist coder)
               • Versions-Endpunkt:   cicd meldet die Spec-Lücke; der coder implementiert ihn
Output/Handoff Rollout-Gate: PASS | FAIL | NEEDS-HUMAN
               Action: ship | rollout | rollback | version-stamp | ci-fix
               Version: <BUILD_VERSION>
               URL: <url>
               Rollback-Tag: <tag oder none>
               Prune: <Ergebnis docker image prune -f>
               Changes: <geänderte Dateien bei ci-fix/version-stamp>
Harte Grenzen  • kein App-Code, kein Spec-Drift
               • NIE docker restart für Image-Updates (immer rm + run — cicd/F01)
               • docker image prune -f IMMER nach Rollout/Rollback (cicd/F07)
               • CI-Watch vor Rollout — niemals Rollout bei rotem CI (cicd/F06)
               • gitleaks-Whitelist nur mit Beweis (cicd/F03)
               • merged eigene PRs NICHT (bei pr-Policy: PR erstellen, User mergt)
               • Board-Status schreibt nur der Orchestrator
               • vertraut dem tester-Gate — kein eigener Re-Test
```

## 9. teamLeader  (Meta — Team-Erweiterung, SPÄTER, nicht P1)

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

## 10. red-team  (Meta — autorisiertes Angriffs-Testen, schließt den Sicherheits-Lernkreis)

```
Zweck          Autorisiertes Angriffs-Testen ausschließlich EIGENER, autorisierter Apps
               des Owners (die laufende, deployte App): steuert einen etablierten Scanner
               (Nuclei/OWASP ZAP), triagiert die Funde agentisch (ohne destruktives
               Ausnutzen) und schließt den Sicherheits-Lernkreis über drei Ausgänge —
               Protokoll + Board-Items + Lessons. Der fehlende Produzent echter
               Angriffs-Funde (ergänzt train: Netz→Pack, reviewer→retro: Diff→Pack).
               Schreibt KEINEN App-Code, KEINEN Board-Status; liefert immer als PR.
Trigger/Input  /agent-flow:red-team ziel=<app-slug> [modus=durch-cloudflare|direkt|beide]
               (cwd = Ziel-Projekt-Repo; per-Lauf menschlich autorisiert — kein Auto-Feuern)
Lese-Pflichten • docs/architecture/red-team-subsystem.md  (BINDENDER Rahmen: §2 Grundhaltung,
                 §3 Allowlist, §4 Ablauf, §5 Lernkreis/Lanes, §7 „Bewusst NICHT")
               • docs/specs/red-team-capability.md  (AC1/AC4/AC5/AC6/AC7)
               • knowledge/security.md  (Methodik + Angriffsklassen OWASP Top 10:2025;
                 Norm-Lane security/R<NN> + Einsatz-Lane security/E<NN> als Triage-Leitfaden)
               • .claude/profile.md  (merge_policy, default_branch + VPS-/Deploy-Felder für Allowlist)
               • .claude/lessons/red-team.md  (eigene Verfahrens-Lessons, VERBINDLICH falls vorhanden)
Tools          Read, Grep, Glob, Bash (NUR Scanner-Steuerung + git/PR), Write, Edit
Ablauf         1. Ziel auflösen + Allowlist-Gate (§3, AC3): Laufzeit-Schnittmenge
                  „VPS-Container ∩ Org-Repo", nie Freitext. Außerhalb → sofort STOPP (Default deny)
               2. Pack lesen (Methodik, Angriffsklassen, beide Lanes)
               3. Breiter Scan — self-updating: etablierter Scanner, Vorlagen frisch aus dem
                  offiziellen Feed (tagesaktuelle Ebene lebt NICHT im Pack). Kein eigener Exploit-Code
               4. Triage — agentisch: False-Positive-Filter, Ausnutzbarkeit (belegen, nie ausnutzen),
                  Schweregrad — ohne destruktives Ausnutzen (kein Datenabfluss/Löschung)
               5. Drei Ausgänge: (a) Protokoll — genau EIN Block/Lauf in docs/red-team-audit.md
                  (auch No-Op), „was versucht / hat gegriffen / wurde abgewehrt" + Cloudflare-Differenz;
                  (b) Board-Items — jede bestätigte Lücke als To-Do (für /flow: finden→beheben→erneut testen);
                  (c) Lessons — generalisierbare Muster → .claude/lessons/red-team.md (retro-lesbar,
                  für Einsatz-Lane security/E<NN>)
               6. Freigabe: eigener Branch + PR (nie Self-Merge, nie Direkt-Push)
Handoff-Kette  red-team (Funde) → /flow (behebt Board-Items) · red-team-Lessons → retro
               (destilliert in Einsatz-Lane security/E<NN> des security-Packs, §5 des Rahmens)
Output/Handoff Ziel + Autorisierung | Scan: N Roh → M bestätigt | Protokoll (+1 Block) |
               Board-Items | Lessons | PR-Link (headless: EIN End-JSON, s. SKILL.md)
Harte Grenzen  • Ziel-Allowlist HART (AC3): kein Freitext-Ziel, nur VPS-Container ∩ Org-Repo,
                 außerhalb → sofort STOPP, Default deny
               • Koordination statt Tarnung HART (AC4): keine Detection-Evasion; Cloudflare-
                 Freischaltung ist ein MENSCHLICH bestätigter Schritt, nie still ausgelöst
               • kein destruktives Ausnutzen (Ausnutzbarkeit belegen, nie ausnutzen)
               • Protokoll-Pflicht HART (AC5): genau EIN Block/Lauf, auch bei No-Op
               • Auslieferung ausschließlich als PR (AC7, HART); ohne Remote/Auth committeter
                 lokaler Branch als Fallback — nie stiller Abbruch, nie Direkt-Push
               • Lessons NUR projekt-lokal (.claude/lessons/red-team.md), NIE in globale
                 knowledge/-Packs (Destillation = retro-Hoheit via PR+Gate)
               • kein App-Code, kein Board-Status (legt Items als To Do an — Hoheit /flow)
               • diese Iteration: Vertrag + Gerüst; Live-Scanner-Wiring gegen echte Ziele +
                 Cloudflare-Koordination ist die dev-gui-Kachel-Folge (Rahmen §6)
```

---

## Skills (Entry Points)

- **`/flow [--all]`** — Orchestrator: arbeitet pro Lauf **eine** Story (bzw. einen SR1-Parallel-Batch) ab (Spine + Handoff-Verträge: `CONCEPT.md` §4b), dann endet die Session (Default, auch headless — Kontext-Wachstum vermeiden, äußere Schleife rotiert; Spec `docs/specs/flow-session-rotation.md`). `--all` (interaktives Opt-in) behält das bisherige Bis-Board-leer-Verhalten. Einziger Schreiber von Board-Status + git/PR.
- **`/retro`**, **`/train <lang>`** — triggern die gleichnamigen Meta-Agenten (oben).
- **`/agent-flow:red-team ziel=<app-slug> [modus=durch-cloudflare|direkt|beide]`** — dispatcht den `red-team`-Agenten (oben): autorisiertes Angriffs-Testen einer EIGENEN, autorisierten App (Allowlist „läuft auf eigenem VPS" ∩ „eigenes Org-Repo", konstruktiv erzwungen, Default deny). Reines Dispatch (Muster `reconcile`): parst die Ziel-Kennung, erzwingt das Allowlist-Gate, startet den Agenten. Liefert die drei Ausgänge des Sicherheits-Lernkreises (Protokoll `docs/red-team-audit.md`, Board-Items für `/flow`, `retro`-lesbare Lessons → Einsatz-Lane `security/E<NN>`) als **einen** PR — kein Self-Merge, kein Auto-Feuern; ohne Remote/Auth committeter lokaler Branch als Fallback. Koordination statt Tarnung: die Cloudflare-Freischaltung ist ein menschlich bestätigter Schritt. Headless-konsumierbar (`claude -p`, genau EIN End-JSON). Bindender Rahmen: `docs/architecture/red-team-subsystem.md`.
- **`/new-project` / `/init`** — Projekt-Bootstrap (Spec unten).
- **`/adopt <owner/repo>`** — bestehendes Repo adoptieren + auf Standard heben: clone (fremd → Fork in die Org) → init (Spec aus Code) → **Audit** (reviewer Audit-Modus + gitleaks/dep-audit gegen Security-Floor/Packs/Spec) → Funde als priorisiertes **Backlog** aufs Board → `/flow`. Behebt nichts automatisch; pusht nie ungefragt aufs fremde Upstream.
- **`/cicd`** — Abschluss-Arm nach tester-PASS: git-Landen (merge+push), CI-Watch, lokaler Docker-Rollout, Disk-Hygiene (`docker image prune -f`). Verben: `ship` (kanonischer Modus), `rollout`, `rollback <tag>`, `version-stamp`, `ci-fix`, `status`. Dispatcht den `cicd`-Agenten; vom `/flow`-Orchestrator direkt nach tester-PASS ausgelöst (via SHIP-TRIGGER) oder manuell. **Abgrenzung:** `/preview` ist der ephemere Dev-Preview; `/cicd ship` ist der vollständige produktive Abschluss.
- **`/agent-flow:upgrade [<owner/repo>]`** (namespaced Pflicht — bloßes `/upgrade` ist ein CLI-Built-in [Abo-Upgrade] und erreicht das Skill nicht) — autonomer Stack-Modernisierer: Ist-Versionen erkennen → neueste recherchieren → **Cross-Achsen-Kompatibilität** auflösen (Solver) → **UpgradePlan** als Spec + Board-Leiter → fehlende Knowledge-Packs via `train --bootstrap` schließen → Stufe für Stufe via `/flow` ausführen → testen + Loop → `retro`. Läuft **eingaben-frei** (Overnight) über hermetisches Pack-Loading + Failure-Isolation/Resume. Bindende Spec: `docs/architecture/upgrade-subsystem.md`.

```
Skill: new-project  /  init
─────────────────────────────────────────────────────────────
Zweck     Bootstrappt ein Projekt: Repo + Board + .claude/-Scaffold + docs/-Scaffold +
          Dockerfile + CI. Schreibt KEINEN App-Code (das macht requirement → /flow).
Trigger   /new-project <name> [--lang <x>]   → neues Repo in der Org
          /init                               → bestehendes Repo (cwd) adoptieren
Tools     Read, Write, Edit, Bash(gh + git)
Ablauf    1. Repo:  new  → gh repo create studis-softwareschmiede/<name> --public + clone
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
          4b. docs/ aus templates/_docs/ (Spec-Doku §4d, sprach-neutral):
             • immer: concept.md, architecture.md, glossary.md, specs/_template.md
             • bedingt: data-model.md (sql-Domäne), design.md (UI)
             • /init zusätzlich: „Spec aus Code ableiten" — concept+architecture+specs als
               Entwurf füllen, mensch-validiert, dann committen → App portierbar + unter Drift-Gate
          5. Deploy aus templates/<lang>/:
             • Dockerfile
             • .github/workflows/build.yml → on push main: secret-scan-Gate (gitleaks) +
               build + push ghcr.io/<org>/<name> via eingebautem GITHUB_TOKEN (packages: write)
             • .github/workflows/security.yml (geplanter Secret-History-Scan + Issue) +
               .github/dependabot.yml (Dep-/Action-Vuln-Überwachung; Sprach-Ökosystem je language)
               + Dependabot security-fixes aktivieren (gh api automated-security-fixes)
          6. Branch-Protection auf main (best-effort): nur "require PR before merging";
             KEINE Pflicht-Checks (reviewer=Agent, kein GitHub-Check), KEINE Pflicht-Approvals (solo).
             API-Ablehnung → ueberspringen, nicht abbrechen. Gate = manueller Merge nach PASS.
          7. Initial commit + push
Output    Repo-URL · Board-URL · Profil · Image-Ziel → „bereit für /requirement"
Harte     • kein App-Code
Grenzen   • init: bestehende .claude/- und docs/-Dateien NICHT überschreiben (mergen/fragen) → idempotent
          • minimal fragen (Sprache nur wenn unerkennbar, 1–2 für CLAUDE.md)
─────────────────────────────────────────────────────────────
```

> Pro Sprache liegt in `templates/<lang>/` die Scaffolding-Vorlage (Dockerfile, CI-Workflow,
> Profil-Defaults). Seed: `flutter, html, java, js`. `train` kann sie aktuell halten (z.B. Base-Images).
