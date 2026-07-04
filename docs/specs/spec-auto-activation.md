---
id: spec-auto-activation
title: requirement aktiviert neu angelegte Specs automatisch (draft → active)
status: active
area: anforderung-intake
version: 1
spec_format: use-case-2.0
---

# Spec: Automatische Spec-Aktivierung durch requirement  (`spec-auto-activation`)

> **Schicht 3 von 3.** Testbares **Verhalten + Verträge**, sprach-/paradigma-unabhängig (Intent, keine Idiome/Klassen).
> **Source of Truth** für `coder` (baut daraus), `tester` (testet die Acceptance-Kriterien + Coverage-Gate), `reviewer` (prüft den Diff dagegen — hartes Drift-Gate).

## Zweck
Schliesst die **Spec-Aktivierungs-Lücke** (Vorfall 2026-07-02, `.claude/lessons/orchestrator.md` L04): Der `requirement`-Agent legte neue Specs bisher als `status: draft` an, aber **kein** Prozessschritt hob sie je auf `active`. Dadurch blieben alle referenzierenden Stories in `board ready` dauerhaft **NOT-READY** (R2: „spec status draft, erwartet active"), und autonome Drains (Nachtwächter / Board-Abarbeiten) endeten still mit „no-drain-target". Diese Spec macht die Aktivierung zum **automatischen Bestandteil** der Story-Anlage: sobald `requirement` die referenzierenden Board-Stories anlegt, gilt die neu erzeugte Spec als in Kraft und wird auf `status: active` gestempelt — **kein** manueller Freigabe-Schritt. (Owner-Entscheidung 2026-07-02, bindend.)

## Main Success Scenario
1. `requirement` klärt die Anforderung (Rückfrage-Loop) und legt je betroffener Capability eine neue Spec aus `templates/_docs/specs/_template.md` an.
2. `requirement` zerlegt die Anforderung in TODOs und legt die referenzierenden Board-Stories an (`spec:`-Feld → die neue Spec, `implements:` → deren AC-Nummern).
3. Beim Anlegen der referenzierenden Story setzt `requirement` das Frontmatter-Feld `status:` **jeder in diesem Lauf neu erzeugten, story-referenzierten Spec** auf `active`.
4. Nach dem Lauf trägt jede neu angelegte, von einer Story referenzierte Spec `status: active`; `board ready` wertet die zugehörigen Stories nicht mehr wegen R2 als NOT-READY.

## Alternative Flows
### A1: Offene Rückfragen / konzeptioneller Widerspruch
- Bestehen konzeptionelle Widersprüche oder Lücken, bezieht `requirement` den Owner ausschliesslich über den **bestehenden Rückfragen-Mechanismus** (AskUserQuestion) ein. Sind alle Rückfragen beantwortet — oder gibt es keine —, gilt die Spec als in Kraft und wird `active`. Es gibt **keinen** zusätzlichen, expliziten Freigabe-Schritt.

### E1: Bestehende / bereits ausgelieferte Specs
- `requirement` stempelt **ausschliesslich** in diesem Lauf **neu angelegte** Specs. Eine bereits existierende Spec (`active` oder `superseded`) wird **nicht** eigenmächtig zurück- oder umgestuft; ein reines Fortschreiben (Textänderung ohne Neuanlage) ändert den Status nicht.

## Acceptance-Kriterien
<!-- Nummeriert, testbar. Board-Items referenzieren diese Nummern. AC-IDs sind stabil. -->

- **AC1** — Beim Anlegen der referenzierenden Board-Story(s) setzt `requirement` jede **in demselben Lauf neu angelegte, story-referenzierte** Spec im Frontmatter auf `status: active` (nicht `draft`). Nach dem Lauf trägt jede solche Spec `status: active`.
- **AC2** — Es gibt **keinen** manuellen Freigabe-Schritt: keine von `requirement` erzeugte, story-referenzierte Spec bleibt dauerhaft `draft` und hält damit ihre Stories in `board ready` NOT-READY. Der Owner wird nur über den bestehenden Rückfragen-Mechanismus einbezogen (→ A1); sind alle Rückfragen beantwortet bzw. gibt es keine, wird die Spec `active`.
- **AC3** — Die Vorlage `templates/_docs/specs/_template.md` behält `status: draft` als Default für **von Hand** begonnene Specs (rückwärtskompatibel). Die Aktivierung ist eine bewusste Handlung von `requirement` bei der Story-Anlage, **kein** geänderter Vorlagen-Default — WIP-Specs ausserhalb des `requirement`-Laufs dürfen weiterhin `draft` sein.
- **AC4** — `requirement` stuft **bestehende** Specs nicht eigenmächtig um: eine bereits `active`/`superseded` Spec wird durch einen `requirement`-Lauf, der sie nur fortschreibt (kein Neuanlegen), im `status` **nicht** verändert. Nur **neu angelegte** Specs werden auf `active` gestempelt. *(deckt E1)*
- **AC5** — Die Agent-Definition `agents/requirement.md` (Ablauf Schritt 3) **und** der Handoff-Vertrag `AGENTS.md` §1 (requirement, Ablauf) benennen die Auto-Aktivierung explizit als verbindlichen Schritt: neu angelegte, story-referenzierte Specs werden `status: active` gestempelt (analog zum `spec_format`-Stempel aus `spec-format-field` AC3).

> **Traceability:** Jeder Test trägt das kanonische Trace-Tag `@trace spec-auto-activation#AC<n>`
> gemäss `knowledge/<lang>.md` → `## Spec-Tagging`. Der `tester` rechnet das Coverage-Gate
> (jede genannte AC ≥ 1 deckender Test). Details: `docs/architecture/traceability-subsystem.md`.
> Da es sich um Agent-Definitions-/Vertrags-Text handelt (`language: md`), erfolgt die Abnahme
> als Doku-Inspektion (analog `spec-format-field` AC3, `lessons-writeback-coverage`).

## Verträge
- **Frontmatter-Feld `status`** (bestehend, `spec-status-lifecycle`): Enum `{ draft | active | superseded }`. Diese Spec fügt keinen Wert hinzu; sie legt fest, **wann** `requirement` auf `active` setzt (bei Neu-Anlage story-referenzierter Specs).
- **Stempel-Stelle:** `agents/requirement.md`, Ablauf Schritt 3 (Spec schreiben) bzw. Schritt 5 (Story-Anlage) — der Auto-Aktivierungs-Schritt reiht sich neben den bestehenden `spec_format`-Stempel ein.
- **Konsument:** `board ready` (R2) wertet `status: active` als „Spec ist in Kraft"; die Auto-Aktivierung sorgt dafür, dass frisch angelegte Stories dieses Gate ohne manuellen Zwischenschritt passieren.

## Edge-Cases & Fehlerverhalten
- Spec ohne YAML-Frontmatter / ohne `status`-Schlüssel → ausserhalb des Scopes (Frontmatter-Vollständigkeit regelt die Vorlage); `requirement` legt neue Specs stets aus der Vorlage mit Frontmatter an.
- Legt `requirement` **keine** neue Spec an (z.B. nur Fortschreiben bestehender Specs) → kein Status-Eingriff (AC4).
- Bleibt eine Rückfrage unbeantwortet (Owner bricht ab) → die Spec ist noch nicht in Kraft; `requirement` aktiviert erst, wenn die Story tatsächlich angelegt wird (kein Aktivieren einer Spec ohne referenzierende Story).

## NFRs
- Deterministisch und token-arm: reines Frontmatter-Setzen beim Anlegen, kein zusätzlicher Agent-Call.

## Nicht-Ziele
- **Kein** Rück-/Umstempeln bestehender Specs (das ist Aufgabe von `[[reconcile]]` bzw. bewusster Owner-Entscheidung).
- **Kein** neuer Vorlagen-Default: `_template.md` bleibt `draft` (AC3).
- **Keine** Änderung an den technischen `board ready`-Sicherheitsnetzen (Spec existiert, AC-Nummern vorhanden, depends erfüllt, kein `blocked_reason`) — die bleiben unverändert (Owner-Entscheidung 2). Deren Diagnose-Aggregation lebt in `[[empty-drain-diagnostics]]`.
- **Kein** automatischer `active` → `superseded`-Übergang (bleibt Nicht-Ziel von `spec-status-lifecycle`).

## Abhängigkeiten
- `[[spec-status-lifecycle]]` — Enum-Quelle `{ draft | active | superseded }`; diese Spec präzisiert den `draft → active`-Übergang bei `requirement`-Neu-Anlage (dort AC2 entsprechend ergänzt).
- `[[spec-format-field]]` — paralleler Auto-Stempel-Mechanismus (`spec_format`) an derselben Stelle in `agents/requirement.md`.
- `[[board-cli]]` — Konsument `board ready` (R2, `status: active`).
- `[[empty-drain-diagnostics]]` — komplementäres Sicherheitsnetz (aggregierte NOT-READY-Diagnose), falls doch eine draft-Spec-Blockade auftritt.
- Agent-Def `agents/requirement.md`, Vertrag `AGENTS.md` §1. Entscheidungsquelle: Owner 2026-07-02 (Vorfall `.claude/lessons/orchestrator.md` L04).
