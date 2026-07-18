---
id: vertical-slice-stories
title: Vertikale Feature-Schnitte statt Schicht-Zerlegung (Backend-zuerst abgeschafft)
status: active
version: 1
spec_format: use-case-2.0
area: anforderung-intake
---

# Spec: Vertikale Feature-Schnitte statt Schicht-Zerlegung  (`vertical-slice-stories`)

> **Schicht 3 von 3.** Testbares **Verhalten + Verträge**, sprach-/paradigma-unabhängig.
> **Source of Truth** für `coder` (baut daraus), `tester` (testet die Acceptance-Kriterien + Coverage-Gate), `reviewer` (prüft den Diff dagegen — hartes Drift-Gate).

## Zweck

Stories werden als **durchgängige Feature-Schnitte** geschnitten (sichtbare Oberfläche + Logik + Datenhaltung in einer Story), statt schichtweise (erst alle Backend-Stories, Frontend am Ende). Jede gelieferte Story zeigt damit sichtbaren Nutzen. Die bisherige `/flow`-Ordnungsregel „Backend vor Frontend, Datenschicht vor UI" entfällt.

## Main Success Scenario

1. `requirement` (bzw. `from-notes` Stufe c über ihn) zerlegt eine Anforderung.
2. Jede Story wird **vertikal** geschnitten: sie umfasst alle Schichten, die ihr Feature-Stück braucht — von der Oberfläche bis zur Datenhaltung.
3. `/flow` arbeitet die Stories nach `depends` + Priorität ab; nach jeder Story ist ein sichtbares Stück fertig.

## Alternative Flows

### A1: Feature ohne sichtbaren Anteil
- Reine Infrastruktur-/Migrations-/Backend-Features (kein UI-Anteil vorhanden) werden wie bisher geschnitten — vertikal ist hier trivial erfüllt.

### A2: Vertikale Story würde XL sprengen
- Die Story wird gesplittet — aber in **gekoppelte** Teil-Stories (Frontend-Teil `depends` auf Backend-Teil, gleiche Priorität), damit der sichtbare Teil unmittelbar folgt und nie liegen bleibt.

## Acceptance-Kriterien

- **AC1** — Vertikaler Default: `requirement` zerlegt standardmäßig in vertikale Feature-Schnitte — jede Story liefert den durchgängigen Schnitt (Oberfläche + Logik + Datenhaltung), den ihr Feature-Stück braucht, solange sie in **einen** coder→reviewer→tester-Durchlauf passt. Ein Schnitt entlang technischer Schichten ist **nicht** mehr der Normalfall.
- **AC2** — Begründete Ausnahme + Kopplung: Ein Schicht-Schnitt ist nur zulässig, wenn (a) das Feature keinen sichtbaren Anteil hat *(deckt A1)* oder (b) die vertikale Story die Größenklasse XL sprengen würde. Im Fall (b) wird in gekoppelte Teil-Stories gesplittet: Frontend-Teil `depends` auf Backend-Teil, **gleiche Priorität** — der sichtbare Teil folgt unmittelbar *(deckt A2)*. Die Ausnahme wird im Item-Body in einem Satz begründet.
- **AC3** — /flow-Ordnungsregel ersetzt: Die Konfliktregel in `/flow` §0a-(b) „Reihenfolge nach `depends` + logischer Schichtung (Backend vor Frontend, Datenschicht vor UI)" wird ersetzt durch „Reihenfolge nach `depends` + **feature-weiser Fertigstellung** (Stories desselben Features vor Stories des nächsten)". `depends` bleibt maßgeblich; eine Schicht-Präferenz existiert nicht mehr.
- **AC4** — Doku nachgezogen: `AGENTS.md` (requirement-Zerlegungs-Vertrag) beschreibt den vertikalen Default; in `AGENTS.md` und den Skills verbleibt keine Formulierung, die „Backend zuerst" als Regel vorgibt.
- **AC5** — Bestandsschutz: Bereits angelegte Stories/Boards werden nicht rückwirkend umgeschnitten oder umsortiert; die Regel gilt für neue Zerlegungen.

> **Traceability:** Jeder Test trägt das kanonische Trace-Tag `@trace vertical-slice-stories#AC<n>`
> gemäss `knowledge/<lang>.md` → `## Spec-Tagging`. Details: `docs/architecture/traceability-subsystem.md`.

## Verträge

- **Zerlegungs-Vertrag (`requirement` Schritt 5):** Default vertikal; Ausnahme nur nach AC2 mit Ein-Satz-Begründung im Item-Body.
- **Kopplungs-Vertrag (Split-Fall):** Teil-Stories tragen dieselbe Priorität; der Frontend-Teil `depends` auf den Backend-Teil und referenziert dieselbe Spec.
- **`/flow`-Konfliktregel (§0a-(b)):** `depends` → feature-weise Fertigstellung; keine Schicht-Heuristik.

## Edge-Cases & Fehlerverhalten

- Projekt ganz ohne UI (`language` nicht UI, keine `ui`-Domäne): Verhalten faktisch unverändert.
- Gemeinsames Fundament mehrerer Features (z.B. initiales Schema/Auth): darf als eigene Fundament-Story vorangehen (Fall AC2a), danach vertikal.

## NFRs

- Keine zusätzlichen Laufzeit-Kosten: reine Regel-/Doku-Änderung in Zerlegung und Ordnung, keine neuen Agenten oder Gates.

## Nicht-Ziele

- Kein „Frontend zuerst mit Platzhaltern"-Modus (bewusst nicht gewählt).
- Keine Änderung an der SR1-Parallelisierung, dem Depends-Gate oder der Wellen-Planung ([[parallel-session-plan]]) — nur die Schicht-Heuristik entfällt.

## Abhängigkeiten

- `agents/requirement.md` (Schritt 5), `skills/flow/SKILL.md` (§0a-(b)), `AGENTS.md`.
- [[design-owner-approval]] — vertikale Stories mit UI-Anteil tragen das Label `ui` und fallen damit unter das Design-Freigabe-Gate.
