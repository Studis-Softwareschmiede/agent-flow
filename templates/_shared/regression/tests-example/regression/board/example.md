---
title: Board Area Schema
target: local
---

# Board Area Tests

Test-Begleitbeschreibung für die Beispiel-Suite `example.spec.ts`.

## target

Spezialisierung der Test-Ausführung, gelesen vom Regressions-Runner
(`scripts/run-regression.sh`, vgl. [[regression-runner]] AC2/AC3/AC5):

- `target: local` — Test läuft auf lokal-verfügbarem System (Standard für
  Bereichs-Suiten). Der Runner prüft vorab die Erreichbarkeit von
  `http://localhost:<preview_port>` (AC6).
- `target: ephemeral-infra` — Test läuft gegen ephemeral bereitgestellte Infra
  (kein lokaler Erreichbarkeits-Check).
- `target: url` — Test läuft gegen die im Frontmatter angegebene `url:`, ohne
  lokal zu provisionieren (AC5).

Diese Suite deklariert oben `target: local` (Default für Bereichs-Suiten).

## Übersicht

Diese Suite validiert die `board/areas.yaml`-Struktur über die JSON-Datentabelle `example.data.json`. Sie dient als **Referenz-Beispiel** für datengetriebene Testfälle gemäß AC3.

## Testfälle

- **Datengetriebene Iteration**: Jede Zeile aus `example.data.json` wird als eigener Testfall ausgeführt (z.B. `should handle area: board`, `should handle area: flow-orchestrierung`).
- **Schema-Validierung**: Bereich-ID muss kebab-case sein, Beschreibung nicht leer, Sortierungsnummer positiv.
- **Struktur-Check**: Tabelle hat mindestens eine Zeile, alle Felder vorhanden.

## Fehlerbehandlung

Bei ungültiger `example.data.json` (malformed JSON, fehlende Felder) schlägt der Test fehl und gibt im HTML-Report die jeweilige Reihe an, die kaputt ist.

## Verdrahtet mit

- Testdatei: `example.spec.ts`
- Datentabelle: `example.data.json` (JSON neben der Testdatei)
- Reporter: CTRF-JSON + JUnit (wird via `playwright.config.ts` aktiviert)
