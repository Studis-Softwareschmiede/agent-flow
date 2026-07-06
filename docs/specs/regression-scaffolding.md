---
id: regression-scaffolding
title: Regressions-Scaffolding — new-project/adopt legen das Playwright-Grundgerüst an
status: active
version: 1
spec_format: use-case-2.0
area: vorlagen-scaffolding
---

# Spec: Regressions-Scaffolding  (`regression-scaffolding`)

> **Schicht 3 von 3.** Testbares **Verhalten + Verträge** des Scaffolding-Schritts.
> **Source of Truth** für `coder` (verdrahtet `new-project`/`init`/`adopt`), `reviewer` (Idempotenz + Drift-Gate), `tester` (prüft die AC).
>
> **Detailkonzept-Bindung.** Diese Spec verankert das Regressions-Grundgerüst im Projekt-Bootstrap: `new-project` (Neuanlage) und `init`/`adopt` (Adoption) legen die Playwright-Struktur, Reporter-Konfiguration, `.gitignore` und leere Bereichs-Suiten gemäß [[regression-playwright-conventions]] an.

## Zweck

Jedes Fabrik-Projekt startet mit einem funktionsfähigen Regressions-Grundgerüst — ohne Handarbeit. Der Bootstrap kopiert die Referenz-Template-Artefakte, fügt Playwright als Dev-Dependency hinzu und generiert je Bereich (`board/areas.yaml`) eine leere Suite, sodass [[regression-define]] direkt anschließen kann.

## Kontext / Designnuancen (bindend)

- **Konventions-Bindung:** das Grundgerüst folgt [[regression-playwright-conventions]] (Layout, CTRF+JUnit-Reporter, `.gitignore`).
- **Idempotenz:** `init`/`adopt` überschreiben bestehende Regressions-Dateien nicht (mergen/überspringen) — analog zum bestehenden `new-project`/`init`-Prinzip.
- **Stack-agnostisch:** Playwright wird unabhängig von der Projektsprache eingebunden.

## Main Success Scenario

1. `new-project <name>` läuft (Bootstrap).
2. Es legt das Playwright-Grundgerüst an: Dev-Dependency, `tests/regression/`-Baum, Playwright-Config mit CTRF+JUnit-Reportern, `.gitignore`-Einträge.
3. Es generiert je Bereich aus `board/areas.yaml` eine leere Suite `tests/regression/<bereich>/` + `tests/regression/verbund/`.
4. Das Projekt ist „bereit für `regression-define`".

## Alternative Flows

### A1: Adoption bestehender Repos (`init`/`adopt`)
- `init`/`adopt` legen dasselbe Grundgerüst **idempotent** an: bestehende Regressions-Dateien werden nicht überschrieben (mergen/überspringen).

### A2: kein/leeres `areas.yaml`
- Fehlt `board/areas.yaml` oder ist es leer → nur `tests/regression/verbund/` wird angelegt; Bereichs-Suiten entstehen später, sobald Bereiche gepflegt sind.

## Acceptance-Kriterien

- **AC1** — `new-project` scaffoldet das Regressions-Grundgerüst: **Playwright-Dev-Dependency**, `tests/regression/`-Verzeichnisbaum, **Playwright-Config mit CTRF+JUnit-Reportern**, `.gitignore`-Einträge (`test-results/`, `playwright-report/`) — gemäß [[regression-playwright-conventions]].
- **AC2** — Es werden **leere Bereichs-Suiten** je Eintrag in `board/areas.yaml` generiert (`tests/regression/<bereich>/` je Bereichs-`id`) plus `tests/regression/verbund/` (deckt A2: ohne `areas.yaml` nur `verbund/`).
- **AC3** — `init`/`adopt` legen dasselbe Grundgerüst **idempotent** für ein bestehendes Repo an und überschreiben vorhandene Regressions-Dateien **nicht** (mergen/überspringen) (deckt A1).
- **AC4** — Das gescaffoldete Setup folgt [[regression-playwright-conventions]] (Layout, Reporter, `.gitignore`), indem es die Referenz-Template-Artefakte kopiert (keine divergente Zweit-Definition).
- **AC5** — Das Scaffolding ist **stack-agnostisch**: Playwright wird unabhängig von der Projektsprache als Dev-Dependency/eigenständiger Runner eingebunden (Layout/Reporter-Regime identisch über alle Sprachen).

## Verträge

### Gescaffoldete Artefakte (aus `templates/`)
```
tests/regression/<bereich>/     # je Bereichs-id aus board/areas.yaml (leer)
tests/regression/verbund/       # immer
playwright.config.<ext>         # CTRF + JUnit Reporter
.gitignore                      # + test-results/  + playwright-report/
<Playwright-Dev-Dependency>     # via Paketmanager / eigenständiger Runner
```

## Edge-Cases & Fehlerverhalten

- **Bestehende `playwright.config`/`tests/regression/`** (bei `init`/`adopt`) → nicht überschreiben; vorhandenen Stand behalten, nur Fehlendes ergänzen (AC3-Idempotenz).
- **`.gitignore` existiert bereits** → die Einträge werden ergänzt, nicht dupliziert.

## NFRs

- **Idempotenz:** wiederholtes `init`/`adopt` ändert nichts an bereits korrektem Grundgerüst.
- **Portabilität:** identisches Grundgerüst über alle Sprachen.

## Nicht-Ziele

- Das Befüllen der Suiten mit Testfällen ([[regression-define]]).
- Ausführung + Leitplanken ([[regression-runner]]).
- Das Authoring von `knowledge/playwright.md` (`/train --bootstrap`-Folgeaktion).

## Abhängigkeiten

- [[regression-playwright-conventions]] — liefert die zu kopierenden Referenz-Template-Artefakte (Config, `.gitignore`-Block, Layout-Skelett).
- [[board-areas]] — liefert die Bereichs-`id`s für die leeren Bereichs-Suiten.
- `new-project`/`init`/`adopt` — die Bootstrap-Skills, in die dieser Schritt eingebaut wird.
