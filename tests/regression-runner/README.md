# `tests/regression-runner/` — Mechanik-Smoke-Test des Regressions-Runners

End-to-end-Smoke-Test für den deterministischen Regressions-Runner (Spec
[`docs/specs/regression-runner.md`](../../docs/specs/regression-runner.md),
Template-Artefakt `templates/_shared/regression/run-regression.sh`).

Geprüft wird die **Runner-Mechanik** — nicht echte Playwright-Browser-Läufe
(kein `npm install`/Netzwerk nötig): ein Stub-`npx` protokolliert Aufrufe +
Umgebung statt Browser zu starten.

| AC | Was wird verifiziert |
|---|---|
| **AC1** | Der Runner-Quelltext dispatcht keinen Agenten (statischer Check). |
| **AC2/AC3** | `target: local` wird aus der Begleitbeschreibung (`<suite>.md`-Frontmatter) gelesen und auf `http://localhost:<preview_port>` aufgelöst. |
| **AC5** | `target: url` läuft gegen die deklarierte URL, unabhängig vom (ggf. nicht erreichbaren) `local`-Ziel — kein lokales Provisionieren. |
| **AC6** | `local`-Ziel nicht erreichbar → Vorbedingungs-Fehler, **kein** Playwright/Stub-Aufruf; erreichbar → Lauf wird ausgeführt. |
| **AC9** | Ein vorhandenes `scripts/load-env.sh` injiziert ein Secret zur Laufzeit; es wird an den Playwright-Kindprozess vererbt, aber nie aus einer Test-/Datendatei gelesen und nirgends persistiert. |
| Edge-Cases | Fehlendes `target` bzw. fehlendes `url`-Feld bei `target: url` → Fehler statt stillem Default. |

## Ausführen

```bash
./smoke.sh
```

Exit-Codes: `0` = alle Verträge grün, `1` = mindestens ein Vertrag verletzt
(Details auf stderr/stdout).

## Wann ausführen

- Nach jedem Edit an `templates/_shared/regression/run-regression.sh`.
- Nach jedem Edit an `templates/_shared/regression/playwright.config.ts`
  (`REGRESSION_BASE_URL`-Wiring).

## Was der Test NICHT prüft

- **AC4/AC7/AC8** (ephemeral-infra-Provisionierung, `rtest-*`-Namensschema,
  Produktiv-Allowlist, garantiertes Cleanup) — separate Story
  (`docs/specs/regression-runner.md`, S-051).
- **Echte Playwright-Ausführung** (Browser, Reporter-Dateien) — das ist
  Playwright-eigene Verantwortung, nicht Teil der Runner-Mechanik.
