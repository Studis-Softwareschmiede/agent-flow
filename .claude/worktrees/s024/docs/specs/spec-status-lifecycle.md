---
id: spec-status-lifecycle
title: Spec-Status-Lebenszyklus (draft → active → superseded)
status: active
version: 1
---

# Spec: Spec-Status-Lebenszyklus  (`spec-status-lifecycle`)

> **Schicht 3 von 3.** Testbares **Verhalten + Verträge**, sprach-/paradigma-unabhängig (Intent, keine Idiome/Klassen).
> **Source of Truth** für `coder` (baut daraus), `tester` (testet die Acceptance-Kriterien + Coverage-Gate), `reviewer` (prüft den Diff dagegen — hartes Drift-Gate).

## Zweck
Definiert den verbindlichen Lebenszyklus des Spec-Frontmatter-Felds `status:` als **eine Wahrheit über alle Stellen** (Vorlage, Architektur-Doku, `board-cli`/`board-lint`, dev-gui-Filter): genau **drei** gültige Werte. Beseitigt den historischen Drift-Wert `approved`, der von keinem Producer erzeugt, aber von Hand in einzelne Specs gerutscht ist, und macht die Regel über ein Lint-Gate selbst-korrigierend. (Entscheidung: `CONCEPT.md` §11 „Entschieden (Spec-Status-Lebenszyklus)", commit 32d29e7.)

## Acceptance-Kriterien
<!-- Nummeriert, testbar. Board-Items referenzieren diese Nummern. AC-IDs sind stabil. -->

- **AC1** — Das Frontmatter-Feld `status:` einer Spec kennt **genau drei** gültige Werte: `draft`, `active`, `superseded`. Jeder andere Wert ist ungültig.
- **AC2** — Die Werte tragen feste Bedeutung: `draft` = in Arbeit, gilt noch nicht; `active` = verbindlich/in Kraft; `superseded` = durch eine neuere Spec ersetzt. Der Pfad ist `draft → active → superseded` (eine Spec startet als `draft`, wird `active`, wenn sie in Kraft tritt, und `superseded`, sobald eine neuere Spec sie ablöst).
- **AC3** — `approved` ist **kein** gültiger Status (faktisches Synonym für `active`, historischer Hand-Drift, kein Producer). Nach Umsetzung trägt **keine** Spec im Repo `status: approved`; insbesondere tragen die zuvor betroffenen Specs `metrics-ledger`, `metrics-retro-aggregation`, `metrics-retro-effectiveness`, `frontier-cost-mode`, `metrics-estimation`, `metrics-token-collect` jeweils `status: active`.
- **AC4** — `board-lint.sh` meldet einen Spec-`status:`-Wert außerhalb `{draft, active, superseded}` als **FEHLER** mit der stabilen Regel-ID `SPEC-STATUS-INVALID` (Format `FEHLER SPEC-STATUS-INVALID <datei> status=<wert>`) und Exit-Code ≠ 0. Geprüft wird mindestens jede Spec-Datei, die von einer Story über das `spec:`-Feld referenziert wird und existiert. Eine Spec mit gültigem Status erzeugt keinen `SPEC-STATUS-INVALID`-Befund. *(deckt E1)*
- **AC5** — Vorlage (`templates/_docs/specs/_template.md`) und `docs/architecture/board-subsystem.md` führen genau diese drei Werte **und** benennen `approved` explizit als ungültigen Wert.

> **Traceability:** Jeder Test trägt das kanonische Trace-Tag `@trace spec-status-lifecycle#AC<n>`
> gemäss `knowledge/<lang>.md` → `## Spec-Tagging`. Der `tester` rechnet das Coverage-Gate
> (jede genannte AC ≥ 1 deckender Test). Details: `docs/architecture/traceability-subsystem.md`.

## Verträge
- **Enum `status` (Spec-Frontmatter):** `{ draft | active | superseded }`. Kein Default im Sinne von „leer = gültig" — fehlendes/leeres `status` ist außerhalb des Scopes dieser Spec (Frontmatter-Pflicht regelt die Vorlage).
- **Lint-Befund (board-lint.sh):** Regel-ID `SPEC-STATUS-INVALID`, Ausgabezeile `FEHLER SPEC-STATUS-INVALID <relativer-datei-pfad> status=<wert>`, trägt zum Fehler-Zähler bei (Exit 1). Reiht sich in die bestehende deterministische, sortierte Befund-Ausgabe ein.
- **Konsument `board next` (R2):** wertet unverändert ausschließlich `status: active` als „spec ist in Kraft" — diese Spec stellt sicher, dass es keinen zweiten, gleichbedeutenden Wert (`approved`) mehr gibt.

## Edge-Cases & Fehlerverhalten
- **E1:** Spec mit `status: approved` (oder jedem anderen Fremdwert) → `board-lint.sh` gibt `FEHLER SPEC-STATUS-INVALID …` aus, Exit 1.
- Referenzierte Spec-Datei fehlt → bestehender Befund `SPEC-MISSING` (nicht dieser Spec zugeordnet); keine Doppelmeldung als `SPEC-STATUS-INVALID`.
- Spec ohne YAML-Frontmatter / ohne `status`-Schlüssel → kein `SPEC-STATUS-INVALID` (dieser Check prüft nur einen **vorhandenen** Wert auf Enum-Gültigkeit; Frontmatter-Vollständigkeit ist nicht Gegenstand dieser Spec).

## NFRs
- Lint bleibt deterministisch (stabile, sortierte Ausgabe) und token-frei (reines Bash/python3, kein Agent-Call).

## Nicht-Ziele
- Der **dev-gui-Status-Filter** (Reduktion 4 → 3 Werte) lebt im separaten `dev-gui`-Repo und wird dort nachgezogen — **nicht** Teil dieser Story/dieses Repos.
- Erzwingen eines Frontmatter-`status`-Pflichtfelds (Vorhandensein) — nur die Enum-Gültigkeit eines vorhandenen Werts ist Gegenstand.
- Automatische Status-Übergänge (z.B. `active` → `superseded` beim Anlegen einer Nachfolge-Spec).

## Abhängigkeiten
- `[[board-cli]]` (R2 — Konsument von `status: active`), `[[board-schema]]` (Lint-Regel-IDs + Befund-Format).
- Vorlage `templates/_docs/specs/_template.md`, Architektur-Doku `docs/architecture/board-subsystem.md`.
- Entscheidungsquelle: `CONCEPT.md` §11 „Entschieden (Spec-Status-Lebenszyklus)".
