---
id: spec-format-field
title: spec_format-Versionsstempel im Spec-Frontmatter
status: draft
area: doku-reconcile
version: 1
spec_format: use-case-2.0
---

# Spec: spec_format-Versionsstempel  (`spec-format-field`)

> **Schicht 3 von 3.** Testbares **Verhalten + Verträge**, sprach-/paradigma-unabhängig (Intent, keine Idiome/Klassen).
> **Source of Truth** für `coder` (baut daraus), `tester` (testet die Acceptance-Kriterien + Coverage-Gate), `reviewer` (prüft den Diff dagegen — hartes Drift-Gate).
> **Subsystem-Vertrag (verbindlich):** `docs/architecture/reconcile-subsystem.md` §3 Stufe 1 (Versions-Stempel) + §8 (Begriffsquelle Use-Case 2.0). Diese Spec ist das **Fundament** für das Reconcile-Subsystem (`[[reconcile]]`): ohne Stempel kann Stufe 1 (Form) Form-Drift nicht erkennen.

## Zweck
Jede Spec trägt im Frontmatter einen **Versions-Stempel** `spec_format: <name-version>`, der die offizielle Bezeichnung des angewandten Spec-Standards nennt (aktuell `use-case-2.0`). Damit wird die **Form** einer Spec maschinell vergleichbar gegen die aktuelle Vorlage — die Vorbedingung dafür, dass `/agent-flow:reconcile` Stufe 1 veraltete oder fehlende Spec-Formen erkennen und konvertieren kann. Der `requirement`-Agent stempelt neue Specs künftig automatisch, sodass der Stempel nicht von Hand gepflegt werden muss.

## Acceptance-Kriterien
<!-- Nummeriert, testbar. Board-Items referenzieren diese Nummern. AC-IDs sind stabil. -->

- **AC1** — Die kanonische Vorlage `templates/_docs/specs/_template.md` trägt im Frontmatter das Feld `spec_format:` mit dem aktuellen Standard-Wert `use-case-2.0` und nennt diese Version sichtbar im Kopf/Vorlagen-Kommentar (die Vorlage „nennt im Kopf ihre eigene `spec_format`-Version", Vertrag §3).
- **AC2** — Der Wert ist die **offizielle Methodik-Bezeichnung als `name-version`** (`use-case-2.0`), **kein** hausgemachter interner Zähler. Revisionen folgen der Standard-Nummer (`use-case-2.0` → `use-case-2.1` → …); es wird **keine** eigene Revisions-Achse erfunden (Vertrag §3, §7 „Kein eigener interner Revisions-Zähler").
- **AC3** — Der `requirement`-Agent stempelt **jede neu angelegte Spec** automatisch mit dem aktuellen `spec_format`-Wert der Vorlage. Eine über `requirement` erzeugte Spec trägt nach dem Lauf `spec_format: use-case-2.0` im Frontmatter (ohne manuelle Nacharbeit). *(deckt A1)*
- **AC4** — Der Stempel ist ein YAML-Frontmatter-Schlüssel mit stabilem Namen `spec_format` (kebab-frei, exakt diese Schreibweise) und einem nicht-leeren Wert im Format `<name>-<major>.<minor>`. Ein abweichender Schlüsselname oder ein leerer Wert gilt als „nicht gestempelt".
- **AC5** — Bestehende Specs **ohne** `spec_format` bleiben gültig und werden durch diese Story nicht verändert (rückwärtskompatibel). Eine fehlende oder von der Vorlage abweichende `spec_format`-Angabe ist genau das Signal „veraltete/fehlende Form", das `[[reconcile]]` Stufe 1 erkennt und konvertiert — dort, nicht hier, findet die Umschreibung statt. *(deckt E1)*

> **Traceability:** Jeder Test trägt das kanonische Trace-Tag `@trace spec-format-field#AC<n>`
> gemäss `knowledge/<lang>.md` → `## Spec-Tagging`. Der `tester` rechnet das Coverage-Gate
> (jede genannte AC ≥ 1 deckender Test). Details: `docs/architecture/traceability-subsystem.md`.

## Main Success Scenario
1. `requirement` legt eine neue Spec aus `templates/_docs/specs/_template.md` an.
2. Die Vorlage enthält bereits `spec_format: use-case-2.0` im Frontmatter.
3. `requirement` übernimmt/setzt den aktuellen `spec_format`-Wert in die neue Spec.
4. Die fertige Spec liegt mit korrektem Stempel im Working-Tree.

## Alternative Flows
### A1: requirement-Stempelung
- `requirement` setzt `spec_format` auch dann, wenn die Vorlage zwischenzeitlich auf eine höhere Standard-Nummer gehoben wurde — der Wert wird aus der **aktuellen** Vorlage gelesen, nicht hartkodiert.

### E1: Bestandsspec ohne Stempel
- Eine bereits existierende Spec ohne `spec_format` wird **nicht** rückwirkend von dieser Story gestempelt; ihre Aufholung ist Aufgabe von `[[reconcile]]` Stufe 1.

## Verträge
- **Frontmatter-Feld `spec_format`** (neu): YAML-String, Format `<name>-<major>.<minor>`, aktueller Wert `use-case-2.0`. Position: im Frontmatter-Block neben `id`/`title`/`status`/`version`.
- **Standard-Wert-Quelle:** Die Vorlage `templates/_docs/specs/_template.md` ist die **einzige** Quelle der aktuell gültigen `spec_format`-Version; `requirement` liest sie von dort.
- **Konsument:** `[[reconcile]]` Stufe 1 vergleicht den Stempel jeder Spec gegen die Vorlagen-Version.

## Edge-Cases & Fehlerverhalten
- Spec ohne YAML-Frontmatter → außerhalb des Scopes dieser Story (Frontmatter-Vollständigkeit regelt die Vorlage); für Reconcile zählt sie als „fehlende Form".
- Vorlage und neu erzeugte Spec dürfen nie auseinanderlaufen — `requirement` darf den Wert nicht hartkodieren, sondern aus der Vorlage übernehmen (verhindert Stempel-Drift).

## NFRs
- Die Stempelung ist deterministisch und token-arm (Frontmatter-Setzen, kein zusätzlicher Agent-Call).

## Nicht-Ziele
- **Kein** Rück-Stempeln bestehender Specs (das macht `[[reconcile]]` Stufe 1).
- **Keine** Konvertierung der Spec-Struktur (Form-Umschreibung) — nur das Setzen des Stempels bei Neu-Anlage.
- **Kein** eigener interner Revisions-Zähler.

## Abhängigkeiten
- `[[reconcile]]` — Konsument des Stempels (Stufe 1 Form-Erkennung/Konvertierung).
- Vorlage `templates/_docs/specs/_template.md`; Agent `agents/requirement.md` (Stempel-Stelle).
- Vertrag: `docs/architecture/reconcile-subsystem.md` §3, §8. Konzept-Registrierung: `CONCEPT.md` (Reconcile-Absatz).
