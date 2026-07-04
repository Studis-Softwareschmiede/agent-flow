---
id: empty-drain-diagnostics
title: Leerer Drain nie stumm — aggregierte NOT-READY-Diagnose
status: active
area: anforderung-intake
version: 1
spec_format: use-case-2.0
---

# Spec: Aggregierte Leerlauf-Diagnose  (`empty-drain-diagnostics`)

> **Schicht 3 von 3.** Testbares **Verhalten + Verträge**, sprach-/paradigma-unabhängig (Intent, keine Idiome/Klassen).
> **Source of Truth** für `coder` (baut daraus), `tester` (testet die Acceptance-Kriterien + Coverage-Gate), `reviewer` (prüft den Diff dagegen — hartes Drift-Gate).

## Zweck
Ergänzendes Sicherheitsnetz zur Spec-Aktivierungs-Lücke (Vorfall 2026-07-02, `.claude/lessons/orchestrator.md` L04): Wenn ein Lauf **keine** abarbeitbaren Items findet — sei es, weil Specs nicht `active` sind, weil `depends` offen sind oder weil Stories `blocked` sind —, soll der Grund **aggregiert und sichtbar** ausgegeben werden statt eines stummen Leerlaufs (autonome Drains endeten bisher still mit „no-drain-target"). Zwei Oberflächen: das **`board`-CLI** (`board ready` gibt einen aggregierten NOT-READY-Block aus, den jeder Konsument — Nachtwächter, dev-gui, `/flow` — sieht) und der **`/flow`-Orchestrator** (surft die Gründe bei leerer Item-Auswahl aktiv an den User). (Owner-Entscheidung 2026-07-02, bindend.)

## Main Success Scenario
1. Ein Board hat To-Do-Stories, aber **keine** ist ready (z.B. alle referenzieren `draft`-Specs).
2. `board ready` gibt wie bisher je Story `READY`/`NOT-READY … — <Grund>` + die Summary-Zeile aus.
3. **Zusätzlich** gibt `board ready` einen **aggregierten Diagnose-Block** aus, der die NOT-READY-Stories nach Grund-Kategorie gruppiert (z.B. „12 Stories warten auf nicht-aktive Specs: …").
4. `/flow` ruft bei leerer Item-Auswahl die Aggregation auf und meldet dem User die Gründe, bevor es still stoppt bzw. zum Abschluss-Deploy übergeht.

## Alternative Flows
### A1: To-Do-Stories vorhanden, keine ready
- `/flow` (bzw. der autonome Drain) findet kein abarbeitbares Item. Statt einer stummen/leeren Abschlussmeldung gibt `/flow` die aggregierten NOT-READY-Gründe explizit als „nichts abarbeitbar — Gründe:" aus.

### E1: Keine To-Do-Stories
- Sind alle Stories terminal (`Done`/`Verworfen`) oder existieren keine → `board ready` gibt wie bisher nur `Summary: 0 To-Do-Stories …` bzw. `Summary: n/n ready` aus, **kein** Aggregat-Block (es gibt nichts zu aggregieren). `/flow` verhält sich wie gewohnt (Abschluss-Deploy / Board leer).

## Acceptance-Kriterien
<!-- Nummeriert, testbar. Board-Items referenzieren diese Nummern. AC-IDs sind stabil. -->

- **AC1** — `board ready` gibt nach den `READY`/`NOT-READY`-Einzelzeilen und **vor bzw. neben** der bestehenden Summary-Zeile einen **aggregierten Block** aus, der die NOT-READY-Stories nach Grund-Kategorie gruppiert (mindestens: „nicht-aktive Spec" (R2 status ≠ active / kein Frontmatter), „fehlende Spec-Datei/kein spec-Feld" (R2), „fehlende AC in Spec" (R3), „offene depends" (R4), „blocked_reason gesetzt" (R5)). Je Kategorie werden die betroffenen Story-IDs deterministisch sortiert genannt. Der Block ist maschinen- und menschenlesbar (stabiles Zeilen-Präfix, z.B. `WAITING <kategorie> (<n>): S-xxx, S-yyy`).
- **AC2** — Die Kategorie „nicht-aktive Spec" (der häufigste Blocker: Spec `draft`/nicht `active`) wird **eigens** ausgewiesen und nennt zusätzlich zu den Story-IDs die betroffenen **Spec-Pfade**, sodass ein Signal wie „12 Stories warten auf nicht-aktive Specs: docs/specs/x.md …" sofort erkennbar ist.
- **AC3** — Der `/flow`-Orchestrator ruft bei **leerer** `board next`-Ausgabe (kein abarbeitbares Item) `board ready` (bzw. dessen Aggregat) auf und gibt die NOT-READY-Gründe dem User aus, **bevor** er zum Abschluss-Deploy (§7) übergeht oder still stoppt. Ein leerer Drain bleibt nie stumm.
- **AC4** — Existieren To-Do-Stories, aber **keine** ist ready (alle NOT-READY): `/flow` meldet die aggregierten Gründe explizit (z.B. „nichts abarbeitbar — Gründe: <Aggregat>") statt einer leeren/stummen Meldung. *(deckt A1)*
- **AC5** — Der Aggregat-Block ist **token-frei/deterministisch** (reines Bash/`python3` im `board`-CLI; `/flow` liest nur die CLI-Klartext-Ausgabe, kein zusätzlicher Agent-Call) und ändert den **Exit-Code-Vertrag** von `board ready` nicht (Exit 0 wenn alle ready/keine To-Do-Items, Exit 1 wenn ≥1 NOT-READY — unverändert). Bei ausschliesslich readyen oder keinen To-Do-Stories erscheint **kein** Aggregat-Block. *(deckt E1)*

> **Traceability:** Jeder Test trägt das kanonische Trace-Tag `@trace empty-drain-diagnostics#AC<n>`
> gemäss `knowledge/<lang>.md` → `## Spec-Tagging`. Der `tester` rechnet das Coverage-Gate
> (jede genannte AC ≥ 1 deckender Test). Details: `docs/architecture/traceability-subsystem.md`.

## Verträge
- **`board ready`-Ausgabe (erweitert):** unverändert je Story `READY S-xxx` / `NOT-READY S-xxx — <Grund>` (`[[board-cli]]` V12/AC12) + `Summary: <n>/<total> …`. **Neu:** ein Aggregat-Block mit stabilem Zeilen-Präfix je Kategorie, z.B.:
  ```
  WAITING spec-not-active (12): S-003, S-004, … — Specs: docs/specs/a.md, docs/specs/b.md
  WAITING depends-open (2): S-010, S-011
  WAITING blocked (1): S-020
  ```
  Kategorien nur ausgeben, wenn ≥ 1 Story betroffen ist. Reihenfolge der Kategorien fest (deterministisch).
- **`board ready` Exit-Code:** unverändert (0 / 1 gemäss `[[board-cli]]` AC12).
- **`/flow`-Verhalten:** bei leerer `board next`-Ausgabe zusätzlicher `board ready`-Aufruf; dessen Aggregat wird dem User gemeldet (Klartext, kein Board-Schreibvorgang).

## Edge-Cases & Fehlerverhalten
- Fehlendes `board.yaml` / Stories-Verzeichnis → `board ready` Exit 0, kein Aggregat (wie E1).
- Eine Story mit mehreren NOT-READY-Gründen erscheint in **jeder** zutreffenden Kategorie (Gründe sind nicht exklusiv) — Doppelnennung über Kategorien ist gewollt (zeigt alle Blocker).
- Kaputte/unlesbare Story-Felder → die Story zählt (wie bisher) als NOT-READY mit konkretem Grund und wird der passenden Kategorie zugeordnet; kein Crash (`[[board-cli]]` „Robustheit").

## NFRs
- Deterministische, sortierte Ausgabe (kein nicht-deterministisches Dict-Iterieren). Token-frei.

## Nicht-Ziele
- **Keine** Änderung der `board ready`-Regeln R1–R5 selbst (die technischen Sicherheitsnetze bleiben unverändert — Owner-Entscheidung 2); nur die **Darstellung** der Gründe wird aggregiert.
- **Kein** neues Gaten von `board next` auf `status: active` (out of scope — `board next` respektiert weiterhin nur `To Do` + terminale `depends`).
- **Kein** automatisches Beheben der Blocker (z.B. Auto-Aktivieren von Specs — das leistet `[[spec-auto-activation]]` an der Quelle).

## Abhängigkeiten
- `[[board-cli]]` — erweitert die `board ready`-Ausgabe (V12/AC12); der Aggregat-Block wird dort mit fortgeschrieben.
- `[[spec-auto-activation]]` — Quell-Fix (verhindert die häufigste Ursache); diese Spec ist das Sicherheitsnetz, falls doch eine draft-Spec-Blockade entsteht.
- `[[spec-status-lifecycle]]` — Definition von `status: active` (R2-Konsument).
- `/flow`-Skill `skills/flow/SKILL.md` (§1 Item-Auswahl / §7 Abschluss). Entscheidungsquelle: Owner 2026-07-02 (Vorfall `.claude/lessons/orchestrator.md` L04).
