---
id: version-endpoint
title: Versions-Endpunkt
status: draft               # bleibt draft, bis /flow die stack-spezifische Umsetzung im Zielprojekt liefert
version: 1
spec_format: use-case-2.0
area: <bereich-id>           # von requirement beim Scaffold-Lauf zu setzen (docs/specs/board-areas.md AC6)
---

# Spec: Versions-Endpunkt  (`version-endpoint`)

> **Schicht 3 von 3.** Testbares **Verhalten + Verträge**, sprach-/paradigma-unabhängig (Intent, keine Idiome/Klassen).
> **Source of Truth** für `coder` (baut daraus), `tester` (testet die Acceptance-Kriterien + Coverage-Gate), `reviewer` (prüft den Diff dagegen — hartes Drift-Gate).
>
> **Fabrik-Herkunft.** Diese Spec ist mit dem Projekt gescaffoldet worden (Fabrik-Standard „Build-Versionierung", `docs/specs/build-version-stamping.md` AC3/AC8). Sie konkretisiert den dort definierten `/version`-Vertrag — die **stack-spezifische Implementierung** (Route, Datei-/ENV-Zugriff) entsteht **projekt-lokal** über `/flow`.

## Zweck

Ein `GET /version`-Endpunkt liefert als Selbstauskunft die tatsächlich laufende Build-Version + Revision — robust gegen das Einfrieren der Anzeige bei einem Container-Recreate (die Quelle ist eine ins Image gebrannte Datei, keine ENV).

## Main Success Scenario

1. Ein Client ruft `GET /version` auf.
2. Die App liest die Version primär aus der ins Image gebrannten Datei `/app/VERSION`.
3. Die App antwortet `200` mit `{"version", "revision", "source"}`.

## Alternative Flows

### A1: Gebrannte Datei fehlt zur Laufzeit
- Die App liest `APP_VERSION` stattdessen aus der ENV.

### A2: Weder Datei noch ENV vorhanden
- Die App antwortet mit `"dev"` als Version — kein Fehler.

## Acceptance-Kriterien

- **AC1** — `GET /version` liest die Version primär aus der ins Image gebrannten Datei `/app/VERSION`, **nicht** aus der ENV (→ [[build-version-stamping]] AC3).
- **AC2** — Fallback-Kette **Datei → ENV `APP_VERSION` → `"dev"`**; fail-soft, **nie 5xx** — auch wenn weder Datei noch ENV vorhanden sind (deckt A1, A2).
- **AC3** — Response-Shape bei Erfolg: `200 { "version": string, "revision": string, "source": "file"|"env"|"dev" }`; `source` spiegelt wider, welche Stufe der Fallback-Kette gegriffen hat.
- **AC4** — Der Endpunkt ist rein lesend, ohne Authentifizierung öffentlich erreichbar (keine sensiblen Daten, keine State-Änderung).

> **Traceability:** Jeder Test trägt das kanonische Trace-Tag `@trace version-endpoint#AC<n>`
> gemäss `knowledge/<lang>.md` → `## Spec-Tagging`. Der `tester` rechnet das Coverage-Gate
> (jede genannte AC ≥ 1 deckender Test). Details: `docs/architecture/traceability-subsystem.md`.

## Verträge

### `/version`-Endpunkt
```
GET /version   →  200  { "version": "<APP_VERSION>", "revision": "<git-sha>", "source": "file|env|dev" }
```
- Quelle: gebrannte Image-Datei `/app/VERSION` — **nicht** ENV.
- Fallback: Datei fehlt → ENV `APP_VERSION` → `"dev"`. **Nie 5xx** (fail-soft).

**Stack-spezifisch zu konkretisieren (via `/flow` im Zielprojekt — nicht Teil des Scaffolds):**
- Die konkrete Route/das Framework-Handler-Pattern.
- Die Herkunft von `revision` (git-SHA), sofern zur Laufzeit verfügbar — sonst best-effort/`"unknown"`.

## Edge-Cases & Fehlerverhalten

- **Lokaler `docker build`/`docker run` ohne Build-Arg** → Datei enthält `"dev"`, `/version` liefert `"dev"` (kein Fehler).
- **Container-Recreate mit übernommener Alt-ENV** → irrelevant, da die Datei-Quelle Vorrang vor der ENV hat.

## NFRs

- **Robustheit:** fail-soft, nie 5xx.
- **Konsistenz:** der Rollout-Abgleich (`agents/cicd.md` Abschnitt D, Schritt 8) liest `.version` aus dieser Response — der Feldname `version` ist bindend, keine Umbenennung.

## Nicht-Ziele

- Das Frontend-Pendant (statisches `version.json` im served-dir, nginx no-cache) — kein Endpunkt nötig, siehe [[build-version-stamping]] AC6.
- Der OCI-Label-Vergleich / die Rollout-Diagnose — cicd-seitig (`agents/cicd.md`, [[build-version-verification]]).

## Abhängigkeiten

- [[build-version-stamping]] — AC3 (Fallback-Kette dieses Endpunkts), AC8 (Scaffold-Herkunft dieser Vorlage).
- `agents/cicd.md` Abschnitt D („Versions-Endpunkt-Hinweis") — erwartet exakt den Feldnamen `version` für den Rollout-Abgleich.
