---
id: design-owner-approval
title: Design-Freigabe durch den Owner VOR dem Bauen (UI-Stories)
status: active
version: 1
spec_format: use-case-2.0
area: rollen-agenten
---

# Spec: Design-Freigabe durch den Owner VOR dem Bauen  (`design-owner-approval`)

> **Schicht 3 von 3.** Testbares **Verhalten + Verträge**, sprach-/paradigma-unabhängig.
> **Source of Truth** für `coder` (baut daraus), `tester` (testet die Acceptance-Kriterien + Coverage-Gate), `reviewer` (prüft den Diff dagegen — hartes Drift-Gate).

## Zweck

Der Owner entscheidet über das Erscheinungsbild (Platzierung, Farben, Dichte, Stil), **bevor** gebaut wird — nicht erst nach der Auslieferung. Der `designer` legt dem Owner einen Vorschlag in Alltagssprache vor; erst nach expliziter Freigabe wird `docs/design.md` bindend und UI-Stories werden gebaut. Zusätzlich schließt die Spec die Lücke, dass der Obsidian-Weg (`from-notes`) den `designer` bisher gar nicht einbindet.

## Main Success Scenario

1. Ein UI-Vorhaben erreicht die Fabrik (via `requirement`, `from-notes` Stufe b oder `/flow` vor der ersten UI-Story).
2. Der `designer` wird im **Vorschlags-Modus** dispatcht: er entwirft/aktualisiert `docs/design.md` als **Entwurf** (`owner_approved: null`).
3. Der `designer` legt dem Owner **eine** gebündelte Vorlage vor: Zusammenfassung des Vorschlags in Alltagssprache + alle offenen Gestaltungsfragen mit konkreten Optionen.
4. Der Owner beantwortet die Vorlage; der `designer` arbeitet die Antworten ein.
5. Der Owner gibt frei → der `designer` stempelt `owner_approved: <ISO-Zeitstempel>` ins Frontmatter von `docs/design.md`.
6. `/flow` baut die UI-Stories; `coder`/`reviewer` behandeln das freigegebene `design.md` wie bisher als bindend.

## Alternative Flows

### A1: Headless-Lauf (Owner nicht erreichbar)
- `/flow` trifft auf eine UI-Story ohne freigegebenes `design.md` → Story wird **Blocked** mit Grund „Design-Freigabe ausstehend", die Session endet regulär. Es wird **nie** ohne Freigabe gebaut oder eine Freigabe angenommen.

### A2: Nicht-UI-Projekt / Story ohne UI-Anteil
- Kein Gate, kein designer-Dispatch — Verhalten unverändert.

### E1: Owner lehnt ab / wünscht Änderungen
- Der `designer` arbeitet das Feedback ein und legt erneut vor (Loop bis Freigabe). Kein Teil-Bau auf Basis eines nicht freigegebenen Entwurfs.

## Acceptance-Kriterien

- **AC1** — Vorschlags-Modus: Der `designer` legt `docs/design.md` zunächst als **Entwurf** an bzw. schreibt es fort (`owner_approved: null` im Frontmatter) und erstellt eine Owner-Vorlage: Zusammenfassung in **Alltagssprache** (kein Token-/Fachjargon) + alle offenen Gestaltungsfragen (u.a. Farbrichtung, Dichte/Weißraum, Platzierung zentraler Elemente, Stilrichtung) als **genau EIN** gebündelter Katalog mit konkreten Optionen je Frage. Terminal-Pfad: `AskUserQuestion` (ein Prompt); dev-gui-Pfad: dasselbe JSON-Katalog-Format wie `board/fragenkatalog.schema.json` mit `stage:"design"`, `id`-Muster `design-<n>`.
- **AC2** — Freigabe-Stempel: **Erst nach** expliziter Owner-Freigabe setzt der `designer` `owner_approved: <ISO-Zeitstempel>`. Bis dahin ist `design.md` **nicht bindend** und UI-Stories werden nicht gebaut (AC6). Ablehnung/Änderungswünsche → einarbeiten, erneut vorlegen *(deckt E1)*.
- **AC3** — from-notes-Lücke geschlossen: `from-notes` Stufe b dispatcht bei **UI-Projekten** (`language` ∈ flutter|angular|html **oder** Domäne `ui`/`accessibility` — dieselbe Erkennung wie `new-project`) den `designer` im Vorschlags-Modus. Dessen Design-Fragen fahren im Stufe-b-Fragenkatalog mit (der Grundsatz „genau EIN Katalog pro Stufe" bleibt gewahrt).
- **AC4** — requirement-Einbindung: `requirement` dispatcht bei Anforderungen mit sichtbarem UI-Anteil den `designer` im Vorschlags-Modus (konkretisiert das bisherige formlose „Visual → designer") **und** vergibt an jede Story mit sichtbarem UI-Anteil das Label `ui` — die deterministische Grundlage des Gates (AC6).
- **AC5** — Erst-Design: In einem UI-Projekt ohne freigegebenes `design.md` schiebt `/flow` **interaktiv** vor der ersten UI-Story den designer-Freigabe-Lauf (AC1/AC2) ein und fährt nach Freigabe normal fort.
- **AC6** — Bau-Gate: `/flow` dispatcht den `coder` für eine Story mit Label `ui` **nur**, wenn `docs/design.md` existiert **und** `owner_approved` gesetzt ist. Headless: Story → **Blocked** („Design-Freigabe ausstehend"), regulärer Session-Abschluss *(deckt A1)*.
- **AC7** — Re-Freigabe: Ändert ein designer-Lauf ein bereits freigegebenes `design.md` **wesentlich** (Design-Tokens, Komponenten-Patterns, Platzierungs-/Layout-Muster), setzt er `owner_approved` auf `null` zurück und legt erneut vor. Redaktioneller Feinschliff ohne sichtbare Auswirkung erhält den Stempel.
- **AC8** — Bestandsschutz: Nicht-UI-Projekte und Stories ohne Label `ui` bleiben unberührt — kein Gate, kein designer-Zwang *(deckt A2)*.

> **Traceability:** Jeder Test trägt das kanonische Trace-Tag `@trace design-owner-approval#AC<n>`
> gemäss `knowledge/<lang>.md` → `## Spec-Tagging`. Details: `docs/architecture/traceability-subsystem.md`.

## Verträge

- **`docs/design.md`-Frontmatter (neu):** `owner_approved: null | <ISO-8601-Zeitstempel>`. Einziger Schreiber des Stempels ist der `designer` (nach Owner-Freigabe bzw. Rücksetzung nach AC7). Fehlt das Frontmatter ganz (Bestands-`design.md`), gilt die Datei als **nicht freigegeben**.
- **Design-Katalog:** Format `board/fragenkatalog.schema.json`, `stage:"design"`, `id`-Muster `design-<n>`; Validierung über den bestehenden Gate-Validator (`scripts/obsidian-fragenkatalog-validate.sh`) — kein neuer Katalog-Mechanismus.
- **UI-Projekt-Erkennung:** identisch zu `new-project` (`language` ∈ flutter|angular|html oder Domäne `ui`/`accessibility`) — keine zweite Definition.
- **Gate-Signal:** das Story-Label `ui` (vergeben durch `requirement`, AC4). `/flow` wertet ausschließlich dieses Label + den `owner_approved`-Stempel aus — keine inhaltliche Diff-/Spec-Analyse im Gate.

## Edge-Cases & Fehlerverhalten

- Bestands-Projekte mit `design.md` **ohne** Frontmatter: gelten als nicht freigegeben → beim nächsten UI-Bau greift AC5/AC6 (einmalige Nachfreigabe, dann Ruhe).
- Owner bricht die Vorlage ab / antwortet nicht (interaktiv): kein Stempel, kein Bau — Zustand bleibt Entwurf.
- `designer`-Lauf ohne offene Gestaltungsfragen (alles aus Vorgaben ableitbar): die Vorlage besteht nur aus der Zusammenfassung + einer Freigabe-Frage — das Freigabe-Erfordernis (AC2) entfällt **nie**.

## NFRs

- Rauscharmut: **eine** gebündelte Vorlage pro designer-Lauf — keine verstreuten Einzelfragen.
- Die Owner-Vorlage ist in Alltagssprache (CLAUDE.md-Kommunikationsvertrag), Optionen konkret benannt (z.B. „Navigation links als Seitenleiste" vs. „oben als Menüband").

## Nicht-Ziele

- Keine Abnahme **nach** dem Bauen (Screenshot-/Preview-Gate) — bewusst nicht Teil dieser Spec.
- Kein separater Design-Reviewer; Konformitäts-Prüfung bleibt bei der Reviewer-Checklist der UI-Packs.
- Keine rückwirkende Freigabe-Pflicht für bereits gebaute, ausgelieferte UI.

## Abhängigkeiten

- `board/fragenkatalog.schema.json` + `scripts/obsidian-fragenkatalog-validate.sh` (wiederverwendetes Katalog-Gate).
- [[obsidian-ingest]] (Stufe-b-Katalog, AC3) · `agents/designer.md`, `agents/requirement.md`, `skills/from-notes/SKILL.md`, `skills/flow/SKILL.md`.
