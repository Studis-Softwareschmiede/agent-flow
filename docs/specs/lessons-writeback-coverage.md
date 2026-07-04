---
id: lessons-writeback-coverage
title: Lessons-Write-back für alle Loop-Rollen — tester, dba (Review), cicd + requirement, estimator, architekt, designer schreiben Tier-1-Lessons
status: active
area: lernen-retro
version: 2
spec_format: use-case-2.0
---

# Spec: Lessons-Write-back-Abdeckung  (`lessons-writeback-coverage`)

> **Schicht 3 von 3.** Testbares **Verhalten + Verträge**, sprach-/paradigma-unabhängig (Intent, keine Idiome/Klassen).
> **Source of Truth** für `coder` (baut daraus), `tester` (testet die Acceptance-Kriterien + Coverage-Gate), `reviewer` (prüft den Diff dagegen — hartes Drift-Gate).
> **Betrifft die Fabrik selbst** (agent-flow): die Agenten-Definitionen `agents/tester.md`, `agents/dba.md` (nur Review-Modus), `agents/cicd.md` (v1, AC1–AC11) **sowie ab v2 `agents/requirement.md`, `agents/estimator.md`, `agents/architekt.md`, `agents/designer.md`** (AC12–AC22). Kein Konsumenten-Feature.

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

## Erweiterung v2 — vier weitere Rollen (requirement, estimator, architekt, designer)

> **Owner-Entscheidung 2026-07-02 (verbindlich).** Nach der v1-Auslieferung (tester/dba/cicd, AC1–AC11) wird der Scope um vier bisher als „Einmal-/Meta-Rollen" ausgeschlossene Rollen erweitert. Begründung je Rolle unten. **v1-ACs (AC1–AC11) bleiben unverändert** — v2 ergänzt ausschließlich (AC12–AC22). AC11 (Meta-Rollen-Ausschluss) wird für diese vier Rollen durch **AC22** eingeengt (nicht umgeschrieben).

### Warum diese vier jetzt DAZU
- **`requirement`** — läuft **häufig** (jede Anforderungsrunde), nicht einmalig. Belegter systemischer Fehler (headless-Lauf 2026-07-02): der Agent hat ungefragt eine dritte, nicht angeforderte Story samt Änderung zweier bereits ausgelieferter Specs erzeugt — **Scope-Erfindung statt Eskalation** einer entdeckten Inkonsistenz. Genau der wiederkehrende Verfahrensfehler, den eine Lesson festhalten muss (Regel: „entdeckte, nicht angeforderte Verbesserungspotenziale NUR im Handoff/Output vermerken bzw. eskalieren — NIEMALS eigenmächtig als zusätzliches Item + Spec-Änderung umsetzen").
- **`estimator`** — läuft **häufig** (jede L/XL-Story). Belegter Kalibrierungs-Fehler: die A-priori-Grössenschätzung von S-019 selbst wurde als XL eingestuft, weil die Heuristik reine AC-/Datei-Zählung nutzt (11 AC + 3 Dateien → Score 14 → XL), obwohl der reale Aufwand eher L oder darunter liegt — es sind strukturell **identische, kleine Text-Ergänzungen**. Qualitative Lesson: „Score-Heuristik überschätzt bei mehreren strukturell IDENTISCHEN Datei-Ergänzungen — Repetitions-Rabatt erwägen bzw. im `estimate_note` vermerken."
- **`architekt`** / **`designer`** — laufen **selten** (meist einmal pro Projekt). Schwächere, aber vom Owner akzeptierte Begründung: (a) lokaler Lerneffekt greift bei **wiederholter** Architektur-/Design-Arbeit im selben Projekt (grosse Nachträge); (b) das projektübergreifende `retro`-Promotion-Muster (≥2 Projekte × ≥2 Stellen) braucht überhaupt **Rohmaterial** in Form projekt-lokaler Lessons — ohne Schreibpfad kann architektonisches/Design-Lernpotenzial nie in die globalen Packs einfliessen.

### Weiterhin bewusst ausgeschlossen (Präzisierung von AC11)
- **`teamLeader`** — praktisch nie dispatcht, reines Onboarding-Meta; kein iterativer Diff-gegen-Spec-Abgleich.
- **`train`** — schreibt bereits direkt globale Knowledge-Packs per PR; der Umweg über eine projekt-lokale Lesson-Zwischenstufe bringt keinen Mehrwert, da `train` nicht „Diffs gegen eine Spec" im selben Sinn wie die Loop-Rollen beobachtet.

### Write-/Lese-Routung der vier neuen Rollen (fachliche Entscheidung)
- **`requirement`** und **`estimator`** schreiben **ausschließlich** in ihre eigene Self-Lessons-Datei — **kein** Rückschreiben nach `.claude/lessons/coder.md`. Ihre Funde sind **Prozess-/Verfahrens-Disziplin** (Eskalation statt Scope-Erfindung; Schätz-Kalibrierung), nicht coder-umsetzbar. Kein `coder` fasst diese Muster an.
- **`architekt`** schreibt zweigeteilt (analog `reviewer`/`dba`): **coder-umsetzbare**, wiederkehrende **Implementierungs**-relevante Muster → `.claude/lessons/coder.md`; **architektur-eigene** Verfahrens-/Entscheidungs-Lessons → `.claude/lessons/architekt.md`. Begründung fürs Rückschreiben: der `architekt`-Output ist per Definition **Constraint für den `coder`** (`agents/architekt.md` „als Constraint für den coder formuliert"). Entdeckt der `architekt` ein wiederkehrendes Muster, in dem eine seiner Boundaries im Code systematisch verletzt wird, ist die Regel coder-umsetzbar — dieselbe Routing-Logik wie bei `reviewer`/`dba`.
- **`designer`** schreibt **nur** in `.claude/lessons/designer.md` — **kein** Rückschreiben nach `coder.md`. Begründung (Abgrenzung, damit **keine Doppel-Lessons** entstehen): coder-umsetzbare **UI-Konformität** (Kontrast/Fokus/Spacing/Tastatur-Nav) ist bereits durch die **Reviewer-Checklist der UI-Packs** abgedeckt (`agents/designer.md` Hart-Grenze: „kein separater Design-Reviewer — die Prüfung steckt in der Reviewer-Checklist der UI-Packs"). Der `reviewer` routet coder-umsetzbare UI-Funde also ohnehin nach `coder.md`. Anders als beim `dba` (dessen exklusive DB-Checkliste eine **Lücke** in der generischen `reviewer`-Checkliste füllt) existiert für den `designer` **keine solche Lücke** → ein designer-`coder.md`-Schreibpfad wäre reine Doppelung. `designer` hält daher nur **eigene Design-System-/Verfahrens-Lessons** fest (z.B. Token-Skalen-Entscheidungen, die wiederkehrend Reibung erzeugen).

## Acceptance-Kriterien v2 (AC12–AC22)
<!-- Additiv zu AC1–AC11. Board-Items referenzieren diese Nummern. AC-IDs sind stabil. -->

### requirement
- **AC12** — `agents/requirement.md` erhält einen zu `reviewer.md` §7 analogen **Tier-1-Write-back-Schritt** (im „Vorgehen"-Abschnitt, nach dem Board-Eintrag/Schätzblock): systemische, **wiederkehrende Verfahrens-/Prozess-Fehler** (z.B. Scope-Erfindung statt Eskalation, eigenmächtige Änderung bereits ausgelieferter Specs) werden knapp als Regel in `.claude/lessons/requirement.md` ergänzt (projekt-lokal, **newest-first**, anlegen falls nicht vorhanden). Der Schritt nennt die Kern-Regel explizit: entdeckte, **nicht angeforderte** Verbesserungspotenziale ausschließlich im Output/Handoff vermerken/eskalieren — **nie** eigenmächtig als zusätzliches Item + Spec-Änderung umsetzen. **Kein** Write-back nach `.claude/lessons/coder.md` (requirement-Funde sind nicht coder-umsetzbar).
- **AC13** — `agents/requirement.md` liest `.claude/lessons/requirement.md` (**VERBINDLICH falls vorhanden**) im „Zuerst lesen"-Abschnitt — Voraussetzung dafür, dass der Selbst-Lern-Loop greift.

### estimator
- **AC14** — `agents/estimator.md` erhält einen Tier-1-Write-back-Schritt: **qualitative**, wiederkehrende **Verfahrens-/Kalibrierungs-Lessons** (z.B. „Score-Heuristik überschätzt bei mehreren strukturell IDENTISCHEN Datei-Ergänzungen — Repetitions-Rabatt erwägen / im `estimate_note` vermerken") → `.claude/lessons/estimator.md` (projekt-lokal, newest-first, anlegen falls nicht vorhanden). Der Schritt **grenzt explizit ab** gegen die bereits bestehende **numerische** Kalibrierung (`baseline.json.estimator_calibration`, `retro` Modus E, Single-Writer `retro`): diese Self-Lessons-Datei ist **kein Ersatz** für die numerische Kalibrierung, sondern hält **qualitative Verfahrens-Lektionen** fest. **Kein** Write-back nach `.claude/lessons/coder.md`.
- **AC15** — `agents/estimator.md` liest `.claude/lessons/estimator.md` (**VERBINDLICH falls vorhanden**) im „Zuerst lesen"-Abschnitt.

### architekt
- **AC16** — `agents/architekt.md` erhält einen Tier-1-Write-back-Schritt **mit Domänen-Routing**: **coder-umsetzbare**, wiederkehrende **Implementierungs**-relevante Muster (z.B. eine Architektur-Boundary, die im Code systematisch verletzt wird) → `.claude/lessons/coder.md`; **architektur-eigene** Verfahrens-/Entscheidungs-Lessons → `.claude/lessons/architekt.md` (beide projekt-lokal, newest-first, anlegen falls nicht vorhanden). Der Text nennt das coder.md-Routing analog `reviewer.md` §7 (der architekt-Output ist Constraint für den coder).
- **AC17** — `agents/architekt.md` liest `.claude/lessons/architekt.md` (**VERBINDLICH falls vorhanden**) im „Zuerst lesen"-Abschnitt.

### designer
- **AC18** — `agents/designer.md` erhält einen Tier-1-Write-back-Schritt: **eigene** Design-System-/Verfahrens-Lessons (z.B. wiederkehrend reibungsstiftende Token-/Skalen-Entscheidungen) → `.claude/lessons/designer.md` (projekt-lokal, newest-first, anlegen falls nicht vorhanden). Der Schritt schreibt **NICHT** nach `.claude/lessons/coder.md` und macht die **Abgrenzung explizit**: coder-umsetzbare UI-Konformität (Kontrast/Fokus/Spacing/Tastatur-Nav) deckt bereits der `reviewer` über die UI-Pack-Checklist ab (kein Doppel-Lessons-Pfad, keine `dba`-analoge Checklisten-Lücke beim designer). *(Abgrenzung gegen A3)*
- **AC19** — `agents/designer.md` liest `.claude/lessons/designer.md` (**VERBINDLICH falls vorhanden**) im „Zuerst lesen"-Abschnitt.

### Querschnitt v2
- **AC20** — **Self-Lessons bleiben rollen-privat (Fortschreibung von AC9):** `.claude/lessons/{requirement,estimator,architekt,designer}.md` werden **nur** von der je schreibenden Rolle gelesen. Keine andere Agent-Definition erhält durch diese Erweiterung eine Lese-Pflicht auf eine dieser vier Self-Lessons-Dateien. Der rollen-übergreifende Transfer läuft weiterhin ausschließlich über `.claude/lessons/coder.md` (in die von den neuen Rollen nur `architekt` schreibt).
- **AC21** — **Projekt-lokal, nie global (Fortschreibung von AC10):** Alle vier neuen Write-back-Schritte schreiben ausschließlich nach `.claude/lessons/*.md` und **nie** in `${CLAUDE_PLUGIN_ROOT}/knowledge/`-Packs — jede der vier Agent-Definitionen trägt diese Grenze in ihren „Harte Grenzen"-Abschnitt (analog `reviewer.md`). Die Destillation projekt-lokal → global bleibt `retro` (PR+Gate).
- **AC22** — **AC11-Präzisierung (überschreibt AC11 für diese vier Rollen):** Die AC11-Ausschlussliste wird eingeengt. `agents/{requirement,estimator,architekt,designer}.md` sind **nicht länger** ausgeschlossen (durch AC12–AC19 abgedeckt). **Weiterhin ausgeschlossen** (unverändert, kein Write-back/Read): `agents/teamLeader.md` und `agents/train.md` — Begründung im Abschnitt „Weiterhin bewusst ausgeschlossen". AC11 gilt fort, aber seine wirksame Ausschlussmenge ist ab v2 `{teamLeader, train}`.

> **Traceability (v2):** identisch zu v1 — Tests tragen `@trace lessons-writeback-coverage#AC<n>` für AC12–AC22.

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
- Läuft eine Story ohne DB-Layer, wird `dba` nicht dispatcht → keine dba-Lesson; unverändertes Verhalten. Meta-Rollen bleiben ohnehin außen vor (AC11, ab v2 präzisiert durch AC22: nur noch `{teamLeader, train}`).

### A3 (v2): requirement erkennt Scope-Erweiterungspotenzial
- Der `requirement`-Agent entdeckt beim Schneiden eine nicht angeforderte Verbesserung / Inkonsistenz. Statt sie eigenmächtig als zusätzliches Item + Spec-Änderung umzusetzen, vermerkt/eskaliert er sie **nur im Output** und hält den systemischen Auslöser als Regel in `.claude/lessons/requirement.md` fest (AC12). Kein `coder.md`-Eintrag.

### A4 (v2): estimator erkennt Heuristik-Fehlkalibrierung
- Der `estimator` (oder `requirement` bei der A-priori-Heuristik) stellt fest, dass die reine AC-/Datei-Zählung bei strukturell identischen Wiederholungen überschätzt → **qualitative** Lesson nach `.claude/lessons/estimator.md` (AC14). Die **numerische** Bias-Korrektur bleibt getrennt (`retro` Modus E, `baseline.json.estimator_calibration`) — keine Vermischung.

### A5 (v2): designer-Fund ist bereits vom reviewer abgedeckt
- Ein wiederkehrendes UI-Konformitäts-Muster (z.B. zu geringer Kontrast) ist coder-umsetzbar — aber der `reviewer` fängt es bereits über die UI-Pack-Checklist ab und schreibt es nach `coder.md`. Der `designer` schreibt **nicht** dorthin (kein Doppel-Eintrag, AC18); er hält nur seine eigenen Design-System-Entscheidungs-Lessons in `.claude/lessons/designer.md` fest.

### A6 (v2): architekt-Fund ist coder-umsetzbar
- Der `architekt` sieht ein wiederkehrendes Muster, in dem eine Boundary im Code verletzt wird → coder-umsetzbare Regel nach `.claude/lessons/coder.md`; seine eigenen Entscheidungs-/Verfahrens-Lessons nach `.claude/lessons/architekt.md` (AC16).

## Verträge
- **Betroffene Definitionen:** `agents/tester.md` (AC1/AC2/AC10) · `agents/dba.md` Review-Modus (AC3/AC4/AC5/AC10) · `agents/cicd.md` (AC6/AC7/AC8/AC10).
- **Schreib-Menge:** `.claude/lessons/coder.md` (durch `tester`, `dba`), `.claude/lessons/tester.md`, `.claude/lessons/dba.md`, `.claude/lessons/cicd.md` — alle projekt-lokal, newest-first.
- **Lese-Menge (neu/ergänzt):** `tester` liest `coder.md`+`tester.md`; `dba` (Review) liest `dba.md`; `cicd` liest projekt-lokales `cicd.md` zusätzlich zum globalen `knowledge/cicd.md`.
- **Muster-Vorbild:** `agents/reviewer.md` §7 („Tier-1-Write-back") + „Zuerst lesen" Punkte 3/4 + letzte Hart-Grenze („NUR in `.claude/lessons/…` — NIE in globale Packs").
- **Format der Lessons-Einträge:** newest-first, knappe Regel, optional mit `[seen-in: …; promoted: …]`-Marker analog bestehender coder/reviewer-Lessons — Detail, nicht normativ hier.
- **Verträge v2 — Betroffene Definitionen:** `agents/requirement.md` (AC12/AC13/AC21) · `agents/estimator.md` (AC14/AC15/AC21) · `agents/architekt.md` (AC16/AC17/AC21) · `agents/designer.md` (AC18/AC19/AC21). Querschnitt AC20/AC22 spannen über alle vier.
- **Schreib-Menge v2:** `.claude/lessons/requirement.md`, `.claude/lessons/estimator.md`, `.claude/lessons/designer.md` (je rollen-privat, nur Self-Lessons) · `.claude/lessons/architekt.md` (Self-Lessons) **+** `.claude/lessons/coder.md` (nur `architekt`, coder-umsetzbare Funde) — alle projekt-lokal, newest-first.
- **Lese-Menge v2 (neu):** `requirement` liest `requirement.md`; `estimator` liest `estimator.md`; `architekt` liest `architekt.md`; `designer` liest `designer.md` — jeweils nur die eigene Self-Lessons-Datei (AC20). `architekt` liest `coder.md` **nicht** neu vorgeschrieben durch diese Story (nur Schreibpfad).

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
- **Keine** Änderung an Meta-/Einmal-Rollen (AC11) — **ab v2 eingeengt** (AC22): `requirement`/`estimator`/`architekt`/`designer` sind nun einbezogen; ausgeschlossen bleiben nur `teamLeader` und `train`.
- **Kein** Write-back im dba-**Design**-Modus.
- **Kein** designer-Write-back nach `coder.md` (Doppelung zur reviewer-UI-Checklist, AC18).
- **Kein** requirement-/estimator-Write-back nach `coder.md` (Funde nicht coder-umsetzbar, AC12/AC14).
- **Keine** Änderung an `agents/teamLeader.md` / `agents/train.md` (AC22).
- **Kein** Ersatz der numerischen estimator-Kalibrierung (`baseline.json.estimator_calibration`) — die qualitative `estimator.md`-Lessons-Datei ist additiv (AC14).

## Abhängigkeiten
- Muster-Vorbild: `agents/reviewer.md` §7 + „Zuerst lesen" + Hart-Grenzen.
- **Thematisch benachbart (weiche Abhängigkeit, KEIN Hard-Depend):** F-010 / `docs/specs/flow-lessons-landing.md` — dort werden die hier geschriebenen (getrackten) Lessons beim Landen mitgenommen. Ohne F-010 sind die Producer-Lessons in Repos mit getrackten Lessons noch nicht landungssicher; die Producer-Änderung ist davon unabhängig umsetzbar und in agent-flow selbst ohnehin ephemer (E1).
- Konsument der gelandeten Lessons: `agents/retro.md` (Modus A — Destillation der Tier-1-Lessons in globale Packs via PR+Gate).
</content>
</invoke>
