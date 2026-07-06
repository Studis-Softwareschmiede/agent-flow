---
id: regression-playwright-conventions
title: Regressions-Konventionen — Playwright als Fabrik-Standard, Layout, Reporter, gitignore
status: active
version: 1
spec_format: use-case-2.0
area: wissen-packs
---

# Spec: Regressions-Konventionen  (`regression-playwright-conventions`)

> **Schicht 3 von 3.** Testbares **Verhalten + Verträge**, sprach-/paradigma-unabhängig.
> **Source of Truth** für `coder` (baut die Referenz-Template-Artefakte + Doku), `reviewer` (Drift-Gate), `tester` (prüft die AC).
>
> **Detailkonzept-Bindung.** Diese Spec fixiert die **durablen Konventionen** des Regressions-Subsystems: Playwright als das **eine** stack-agnostische Regressions-Framework aller Fabrik-Projekte, das Projekt-Layout, datengetriebene Testfälle, das Fixture-/Teardown-Muster für Infra-Ketten, die Reporter-Konfiguration und die gitignore-Pflicht. Sie ist die gemeinsame Basis, auf die [[regression-define]], [[regression-runner]] und [[regression-scaffolding]] aufsetzen.

## Zweck

Ein **einheitliches, versioniertes** Regressions-Fundament für alle Fabrik-Projekte: dieselbe Framework-Wahl (Playwright), dasselbe Verzeichnis-Layout, dasselbe Reporter-/Artefakt-Regime. Testdefinitionen sind versionierte Repo-Dateien; Läufe/Artefakte gehören **nicht** ins Git. Der eigentliche Knowledge-Pack `knowledge/playwright.md` wird **separat** via `/train --bootstrap` aus Primärquellen (playwright.dev) erzeugt — diese Spec definiert dessen Pflicht-Inhalte und die von Code/Templates materialisierten Konventionen.

## Kontext / Designnuancen (bindend)

- **Leitentscheidung (nicht zur Diskussion):** Playwright ist das **eine** stack-agnostische Regressions-Framework aller Fabrik-Projekte — UI via Browser, API via `request`-Kontext, Infra-Verbund via Fixtures mit garantiertem Teardown.
- **Ausführung ist deterministisch** (kein Agent pro Testlauf) — Agenten kommen nur beim **Definieren** ([[regression-define]]) und beim **Heilen** ([[regression-heal]]) zum Einsatz.
- **Testdefinitionen = versionierte Repo-Dateien**; Läufe/Artefakte (`test-results/`, `playwright-report/`) sind **nicht** versioniert.

## Acceptance-Kriterien

- **AC1** — Die Fabrik legt Playwright als das **eine** stack-agnostische Regressions-Framework verbindlich fest (UI via Browser, API via `request`-Kontext, Infra-Verbund via Fixtures); diese Wahl ist als durable Konvention dokumentiert (Knowledge-Pack-Anforderung + Template-Artefakte), nicht pro Projekt neu entschieden.
- **AC2** — Das Projekt-Layout ist fixiert: pro Bereich eine Suite unter `tests/regression/<bereich>/` (`<bereich>` = Bereichs-`id` aus `board/areas.yaml`) und Verbund-/Infra-Suiten unter `tests/regression/verbund/`. Ein Referenz-Skelett existiert als Template-Artefakt unter `templates/`.
- **AC3** — Datengetriebene Testfälle: die Datentabelle liegt als **JSON neben der Testdatei** (z.B. `<suite>.spec.<ext>` + `<suite>.data.json`); der Test iteriert über die Tabelle. Ein Beispiel ist als Template-Artefakt vorhanden.
- **AC4** — Für Infra-Ketten ist ein Fixture-/Teardown-Muster verbindlich: **provisionieren → pollen → prüfen → abbauen**, wobei der Abbau (Teardown) **garantiert auch im Fehlerpfad** läuft (fixture-scoped, wird auch bei Test-Fehler/Exception ausgeführt). Ein Referenz-Fixture ist als Template-Artefakt vorhanden.
- **AC5** — Die Playwright-Konfiguration aktiviert **CTRF-JSON** und **JUnit** als Reporter (maschinenlesbares Verbund-Ergebnis + CI-Standardformat); die Config liegt als Template-Artefakt vor.
- **AC6** — gitignore-Pflicht: `test-results/` und `playwright-report/` sind ignoriert (Läufe/Artefakte nie im Git); der zugehörige `.gitignore`-Block ist Template-Artefakt. Testdefinitionen selbst bleiben versioniert.

## Verträge

### Verzeichnis-Layout (verbindlich)
```
tests/regression/
  <bereich>/                 # je Bereichs-id aus board/areas.yaml
    <suite>.spec.<ext>       # Playwright-Testdatei
    <suite>.data.json        # datengetriebene Tabelle (neben der Testdatei)
    <suite>.md               # Begleitbeschreibung (target-Header, s. regression-runner)
  verbund/                   # bereichsübergreifende + Infra-Verbund-Suiten
```

### Reporter-Konfiguration (verbindlich)
- CTRF-JSON-Reporter → maschinenlesbares Aggregat (dev-gui/Verbund-Auswertung).
- JUnit-Reporter → CI-Standard.
- Artefakt-Ausgabeordner (`test-results/`, `playwright-report/`) sind gitignored (AC6).

### Knowledge-Pack `knowledge/playwright.md` — Pflicht-Inhalte (via `/train --bootstrap`, Folgeaktion)
Der Pack (separate `/train --bootstrap`-Folgeaktion, **nicht** Teil dieses Requirement-Laufs) muss aus Primärquellen (playwright.dev) mindestens abdecken:
- `## Coder-Guidance` — Layout `tests/regression/<bereich>/` + `verbund/`, datengetriebene Tabellen (JSON neben der Spec), Fixture-/Teardown-Muster (provisionieren→pollen→prüfen→abbauen inkl. Fehlerpfad), Secrets nie in Testdateien (Runtime-Injektion).
- `## Reviewer-Checklist` — CTRF+JUnit-Reporter gesetzt, `.gitignore` deckt `test-results/`+`playwright-report/`, Teardown garantiert (auch Fehlerpfad), keine Secrets in Test-/Datendateien, `rtest-*`-Namensschema für Infra-Ressourcen.
- `## Test-Approach` — deterministische Ausführung, `target`-Modi (local/ephemeral-infra/url), Vorbedingungs-Check bei `local`.

## Edge-Cases & Fehlerverhalten

- **Kein `areas.yaml`** → nur `tests/regression/verbund/` als Basis-Skelett; Bereichs-Suiten entstehen erst mit gepflegten Bereichen ([[regression-scaffolding]]).
- **Sprach-Ökosystem ohne npm** → Playwright wird stack-agnostisch als eigenständiger Runner/Dev-Dependency eingebunden ([[regression-scaffolding]] AC5); das Layout/Reporter-Regime bleibt identisch.

## NFRs

- **Portabilität:** identisches Layout/Reporter-Regime über alle Sprachen (stack-agnostisch).
- **Diff-Freundlichkeit:** Testdefinitionen + Datentabellen sind versionierte, review-bare Textdateien.

## Nicht-Ziele

- Das **Authoring** des Packs `knowledge/playwright.md` selbst — separate `/train --bootstrap`-Folgeaktion (hier nur als Abhängigkeit + Pflicht-Inhalt benannt).
- Der Definier-/Heil-Agent ([[regression-define]] / [[regression-heal]]) und der Runner/Testobjekt-Vertrag ([[regression-runner]]).
- Das Verdrahten in `new-project`/`adopt` ([[regression-scaffolding]]).

## Abhängigkeiten

- **`/train --bootstrap playwright`** — erzeugt `knowledge/playwright.md` aus Primärquellen (Folgeaktion, außerhalb dieses Laufs; Vertrag: [[train-bootstrap-new-pack]]).
- [[regression-runner]] — definiert den `target`-Header, den die Begleitbeschreibung trägt.
- [[board-areas]] — liefert die Bereichs-`id`s für `tests/regression/<bereich>/`.
