---
id: reconcile
title: Reconcile — Doku per /agent-flow:reconcile wieder mit der Realität in Deckung bringen
status: draft
version: 2
spec_format: use-case-2.0
---

# Spec: Reconcile  (`reconcile`)

> **Schicht 3 von 3.** Testbares **Verhalten + Verträge**, sprach-/paradigma-unabhängig (Intent, keine Idiome/Klassen).
> **Source of Truth** für `coder` (baut daraus), `tester` (testet die Acceptance-Kriterien + Coverage-Gate), `reviewer` (prüft den Diff dagegen — hartes Drift-Gate).
> **Subsystem-Vertrag (verbindlich, FINAL):** `docs/architecture/reconcile-subsystem.md`. Diese Spec setzt nur den **agent-flow-Teil** des Vertrags um (Skill + Stufe 1 + Stufe 2 + Logbuch). Der **dünne dev-gui-Button** (§2/§5) lebt im separaten `dev-gui`-Repo und ist hier **nur Cross-Repo-Abhängigkeit**, kein Board-Item.

## Zweck
`/agent-flow:reconcile` ist die **rückwärtige Aufholung** der Doku-Drift (Gegenstück zur vorwärtigen Drift-Disziplin in CONCEPT §4d): on-demand bringt es die `docs/` eines Projekts wieder in Deckung mit der Realität. **Stufe 1 (Form)** hebt jede Spec auf die neueste Vorlagen-Version (läuft immer); **Stufe 2 (Inhalt)** gleicht — nur bei leerem Kanban — die Doku gegen den maßgeblichen Code ab. Beide Stufen legen genau **einen Diff** zur Freigabe vor; ein knappes `docs/spec-audit.md` protokolliert die getroffenen Änderungen.

## Main Success Scenario
1. Der Mensch löst `/agent-flow:reconcile` aus (im Projekt-Terminal, angestoßen durch den dev-gui-Button oder direkt).
2. **Stufe 1 (Form)** läuft immer: Specs mit veraltetem/fehlendem `spec_format` werden in die aktuelle Vorlage konvertiert und neu gestempelt.
3. Ist das Kanban leer, läuft **Stufe 2 (Inhalt)**: `reviewer` im Audit-Modus liefert die Inhalts-Drift, die Doku wird automatisch an den Code angeglichen.
4. Der Lauf schreibt **genau einen** Block ins Logbuch `docs/spec-audit.md` — bei Änderungen je eine Zeile pro berührtem Dokument, bei einem Lauf ohne jede Änderung eine kanonische „keine Änderung nötig"-Zeile (AC10–AC12).
5. Das Ergebnis wird als **ein** Diff (PR/Diff je `merge_policy`) zur Freigabe vorgelegt; nichts landet ungesehen.

## Alternative Flows
### A1: Volles Board → Stufe 1 only
- Ist mindestens eine Spalte (To Do · In Progress · Blocked · In Review) **nicht** leer, wird Stufe 2 **übersprungen** mit Hinweis „erst Board leerräumen". Stufe 1 läuft trotzdem.

### A2: Keine Drift gefunden
- Findet der Lauf nichts zu ändern, entsteht **kein** Diff/PR (kein Rauschen im Code-Repo) — aber **trotzdem genau ein** Logbuch-Block mit einer kanonischen „keine Änderung nötig"-Zeile, damit „gelaufen, nichts nötig" von „nie gelaufen" unterscheidbar bleibt (siehe AC12/E2).

### E1: Konvertierung schlägt für eine Spec fehl
- Schlägt die Stufe-1-Umschreibung einer einzelnen Spec fehl, bricht der Gesamtlauf nicht ab; die betroffene Spec bleibt unverändert und wird im Logbuch/Diff-Bericht als nicht-konvertiert vermerkt.

## Acceptance-Kriterien
<!-- Nummeriert, testbar. Board-Items referenzieren diese Nummern. AC-IDs sind stabil. -->

### Skill-Gerüst + Stufe 1 (Form)
- **AC1** — Es existiert der Skill `/agent-flow:reconcile` (`skills/reconcile/SKILL.md`), der Stufe 1 und Stufe 2 orchestriert. Er ist der **einzige Schreiber** der Doc-Änderungen und liefert sie als **genau einen** Diff je Projekt-`merge_policy` (PR bei `pr`, Working-Tree-Diff bei `direct`). Es wird **kein** eigener `reconcile`-Agent angelegt (Vertrag §7: Erkennung = `reviewer`-Audit, Orchestrierung = Skill).
- **AC2** — **Stufe 1 läuft IMMER** — auch bei vollem Board —, weil sie rein doku-intern ist (kein Code-Bezug). Sie wird nie durch die Kanban-Vorbedingung von Stufe 2 blockiert.
- **AC3** — Stufe 1 erkennt jede Spec unter `docs/specs/`, deren `spec_format` **älter als** oder **abweichend von** der aktuellen Vorlagen-Version ist **oder ganz fehlt** (Vergleich gegen `templates/_docs/specs/_template.md` → `[[spec-format-field]]`).
- **AC4** — Erkannte Specs werden **automatisch** in die aktuelle Vorlage umgeschrieben (ein konvertierender Agent restrukturiert Inhalt verlustfrei in die neue Form) und mit der aktuellen `spec_format`-Version **neu gestempelt**. Bereits aktuelle Specs bleiben unangetastet.
- **AC5** — Stufe 1 legt ihr Ergebnis als **ein** Diff zur Freigabe vor (nichts landet ungesehen) **und** protokolliert die konvertierten Specs als Block in `docs/spec-audit.md` (→ AC10/AC11).

### Stufe 2 (Inhalt)
- **AC6** — **Harte Vorbedingung:** Stufe 2 läuft **nur**, wenn die Spalten **To Do · In Progress · Blocked · In Review alle leer** sind. Ist eine davon belegt, wird Stufe 2 **übersprungen** mit dem Hinweis „erst Board leerräumen"; Stufe 1 läuft unabhängig davon. *(deckt A1)* Fehlt das Board-Skelett komplett (kein `board.yaml`, z.B. frisch geclontes/noch nicht initialisiertes Projekt), ist die Vorbedingung **nicht prüfbar**; Stufe 2 wird in diesem Fall ebenfalls (konservativ) **übersprungen** mit dem Hinweis „kein Board-Skelett vorhanden, Vorbedingung nicht prüfbar" — kein impliziter Inhalts-Abgleich, wenn nicht feststeht, ob noch etwas offen ist. Stufe 1 läuft auch hier unabhängig davon. *(deckt E3)*
- **AC7** — Die Inhalts-Drift wird von `reviewer` im **Audit-Modus** abgeleitet (Eingabe = Bestand, **kein** Diff, **kein** Gate — er berichtet nur). Die **Drift-Heuristik ist identisch zum Drift-Gate**: Endpunkte/UI/I-O/Fehler-Statuscodes/Datenfelder/NFR-Limits; **reiner Refactor zählt nicht**. Verglichen wird beobachtbares Code-Verhalten gegen `concept.md` + `architecture.md` + `specs/*.md`.
- **AC8** — **Code ist maßgebend:** die Doku wird **automatisch** an den Code angeglichen, fehlende Docs werden angelegt. Es gibt **kein Einzel-Nachfragen pro Abweichung** (kein per-Drift-Prompt) — der Mensch-Gate ist der finale Diff-Blick, nicht eine Entscheidung je Drift.
- **AC9** — Stufe 2 legt alle Nachzieh-Änderungen als **ein** Diff zur Freigabe vor **und** protokolliert die nachgezogenen Dokumente als Block in `docs/spec-audit.md` (→ AC10/AC11).

### Logbuch `docs/spec-audit.md`
- **AC10** — Pro Lauf wird **genau ein** knapper Block nach `docs/spec-audit.md` geschrieben — **immer, auch bei einem Lauf ohne jede Änderung** (No-Op): Kopf = **Datum**, darunter bei Änderungen **je eine Zeile pro berührtem Dokument** (z.B. „Spec X auf use-case-2.0 konvertiert" / „Konzept Y nachgezogen"). Der **neueste** Block steht **oben**. Die Datei liegt im Ziel-Repo neben `docs/`; existiert sie nicht, wird sie angelegt.
- **AC11** — Der Block enthält **nur** die getroffenen Änderungen (durable Historie): **keine** Tabelle, **keine** Begründung, **keine** Fundstellen, **nicht** die ephemere Roh-Drift-Liste. Ein Block ist **nie zeilenlos**: bei Änderungen trägt er ≥ 1 Dokument-Zeile, bei einem No-Op-Lauf **genau eine** kanonische „keine Änderung nötig"-Zeile (→ AC12). Eine einzelne **Stufe** ohne Änderung trägt keine eigene Zeile bei — die No-Op-Zeile entsteht nur, wenn **weder** Stufe 1 **noch** Stufe 2 etwas geändert haben (Block-Ebene = ganzer Lauf, nicht je Stufe).

### Immer ein Block — auch bei No-Op
- **AC12** — **Jeder** Reconcile-Lauf schreibt **genau einen** Block, auch wenn nichts geändert wurde — so ist „gelaufen, nichts nötig" von „nie gelaufen" unterscheidbar. Umsetzung: hat der Lauf ≥ 1 Änderung, ruft der Skill `scripts/spec-audit-append.sh` mit den Dokument-Zeilen auf (wie bisher, AC10/AC11); hat er **keine**, ruft er es im **expliziten No-Op-Modus** (`--no-op`) auf, der einen validen Block mit **genau einer** kanonischen No-Op-Zeile schreibt (Marker-Präfix „keine Änderung nötig", z.B. „keine Änderung nötig — Doku deckungsgleich mit Vorlage und Code"). Änderungs-Zeilen und `--no-op` **schließen sich gegenseitig aus** (entweder das eine oder das andere, nie beides). **Schutz-Invariante (bestehendes Verhalten bleibt):** ein Aufruf **ohne** Zeilen **und ohne** `--no-op` schreibt weiterhin **nichts** — versehentliche Leer-Aufrufe erzeugen keinen Block; der No-Op-Block entsteht **ausschließlich** durch das explizite Flag. *(deckt A2/E2)*

> **Traceability:** Jeder Test trägt das kanonische Trace-Tag `@trace reconcile#AC<n>`
> gemäss `knowledge/<lang>.md` → `## Spec-Tagging`. Der `tester` rechnet das Coverage-Gate
> (jede genannte AC ≥ 1 deckender Test). Details: `docs/architecture/traceability-subsystem.md`.

## Verträge
- **Skill-Befehl:** `/agent-flow:reconcile` (Arbeitstitel laut Vertrag §2). Auslöser dünn (dev-gui POST `/api/command`), gesamte Logik in agent-flow.
- **Kanban-Abfrage (Stufe-2-Gate):** „leer" = die vier aktiven Spalten (To Do, In Progress, Blocked, In Review) enthalten **null** Items; abgefragt über das File-Board (`scripts/board`).
- **Audit-Schnittstelle:** Dispatch von `reviewer` im Audit-Modus (`agents/reviewer.md` „Audit-Modus") = Repo statt Diff, Output = priorisierter Fund-Report, **kein** Gate.
- **Logbuch-Format:** `docs/spec-audit.md`, Block = Datums-Kopf + **≥ 1 Zeile** (1/Dokument bei Änderung **oder** genau die eine kanonische No-Op-Zeile), neueste oben, append-prepend (oben einfügen). **Schreib-Mechanismus:** `scripts/spec-audit-append.sh <Zeile> [<Zeile> …]` (Lines auch via Stdin `-`) **oder** `scripts/spec-audit-append.sh --no-op` (schreibt einen Block mit der kanonischen No-Op-Zeile). Idempotent (legt die Datei aus `templates/_docs/spec-audit.md` an, falls sie fehlt). **Schutz-Invariante (AC12):** ohne Zeilen **und** ohne `--no-op` wird **nichts** geschrieben (versehentlicher Leer-Aufruf bleibt folgenlos).
- **Doc-Schreiber:** ausschließlich der `/agent-flow:reconcile`-Skill (kein anderer Touchpoint schreibt Reconcile-Änderungen).

## Edge-Cases & Fehlerverhalten
- **E1:** Einzel-Spec-Konvertierung scheitert → Gesamtlauf läuft weiter; betroffene Spec bleibt unverändert, Vermerk im Diff/Bericht.
- **E2:** Lauf ohne jede Drift → **kein** Diff/PR (kein Rauschen im Code-Repo), aber **ein** Logbuch-Block mit kanonischer „keine Änderung nötig"-Zeile (AC12). Jeder Lauf ist im Logbuch belegt; nur der Code-Diff bleibt rauschfrei.
- Offenes Board bei Stufe 2 → Skip mit Hinweis (AC6), niemals stiller Inhalts-Abgleich von Halbfertigem (Vertrag §7).
- **E3:** Board-Skelett fehlt komplett bei Stufe 2 (`board.yaml` nicht vorhanden) → Vorbedingung nicht prüfbar, Stufe 2 wird konservativ übersprungen mit eigenem Hinweis (AC6) — kein Absturz des Gesamtlaufs, Stufe 1 läuft unabhängig weiter.

## NFRs
- **Sicherheit/Vorsicht:** Kein Landen ohne Diff-Freigabe (beide Stufen, Vertrag §7). Kein Inhalts-Abgleich bei offenem Board. Kein per-Drift-Nachfragen.
- Stufe 1 ist jederzeit sicher (rein doku-intern, kein Code-Bezug).
- **Nachvollziehbarkeit:** Jeder Lauf hinterlässt genau eine Spur im Logbuch (auch No-Op) — ein reconcile-Lauf bleibt nie „unsichtbar", „gelaufen ohne Änderung" ist von „nie gelaufen" unterscheidbar (AC12).

## Nicht-Ziele
- **Kein** eigener `reconcile`-Agent (Vertrag §7).
- **Kein** eigener interner Revisions-Zähler (Standard-Nummer `use-case-2.x`, → `[[spec-format-field]]`).
- **Kein** dev-gui-Button in diesem Repo — siehe Cross-Repo-Abhängigkeit unten.
- **Keine** handgepflegte Drift-Liste als Wahrheit (durable ist nur das Logbuch §4).

## Abhängigkeiten
- `[[spec-format-field]]` — **Fundament** (Stufe 1 vergleicht gegen den Stempel; muss zuerst existieren).
- `agents/reviewer.md` (Audit-Modus, Stufe-2-Erkennung) · `agents/requirement.md` bzw. konvertierender Agent (Stufe-1-Umschreibung) · `scripts/board` (Kanban-Vorbedingung) · `skills/reconcile/SKILL.md` (neu).
- **Cross-Repo-Abhängigkeit (SR3 Cross-Repo-Markierung):** Der **Auslöser-Button** im „Spezifikation"-Reiter (Muster wie „Board abarbeiten"/„Änderung erfassen", POST `/api/command` mit `/agent-flow:reconcile`) lebt im **`dev-gui`-Repo** und wird **dort** in einem eigenen Board-Item umgesetzt — **NICHT** in agent-flow. agent-flow stellt nur den Befehl bereit.
- Vertrag: `docs/architecture/reconcile-subsystem.md` (FINAL). Konzept: `CONCEPT.md` (Reconcile-Absatz). CONCEPT §4d (vorwärtige Drift-Disziplin, Gegenstück).
