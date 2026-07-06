# `tests/regression-runner/` — Mechanik-Smoke-Tests des Regressions-Runners

End-to-end-Smoke-Tests für den deterministischen Regressions-Runner (Spec
[`docs/specs/regression-runner.md`](../../docs/specs/regression-runner.md),
Template-Artefakte `templates/_shared/regression/run-regression.sh` +
`templates/_shared/regression/tests-example/regression/verbund/infra-guard.ts`).

Geprüft wird die **Runner-/Guard-Mechanik** — nicht echte Playwright-Browser-
Läufe (kein `npm install`/Netzwerk nötig): `smoke.sh` nutzt einen Stub-`npx`,
der Aufrufe + Umgebung protokolliert statt Browser zu starten; `infra-
leitplanken-smoke.sh` importiert das Guard-Modul direkt per `node` (native
TypeScript-Unterstützung).

## `smoke.sh`

| AC | Was wird verifiziert |
|---|---|
| **AC1** | Der Runner-Quelltext dispatcht keinen Agenten (statischer Check). |
| **AC2/AC3** | `target: local` wird aus der Begleitbeschreibung (`<suite>.md`-Frontmatter) gelesen und auf `http://localhost:<preview_port>` aufgelöst. |
| **AC5** | `target: url` läuft gegen die deklarierte URL, unabhängig vom (ggf. nicht erreichbaren) `local`-Ziel — kein lokales Provisionieren. |
| **AC6** | `local`-Ziel nicht erreichbar → Vorbedingungs-Fehler, **kein** Playwright/Stub-Aufruf; erreichbar → Lauf wird ausgeführt. |
| **AC9** | Ein vorhandenes `scripts/load-env.sh` injiziert ein Secret zur Laufzeit; es wird an den Playwright-Kindprozess vererbt, aber nie aus einer Test-/Datendatei gelesen und nirgends persistiert. |
| Edge-Cases | Fehlendes `target` bzw. fehlendes `url`-Feld bei `target: url` → Fehler statt stillem Default. |

## `infra-leitplanken-smoke.sh`

| AC | Was wird verifiziert |
|---|---|
| **AC7** | Ein konformer `rtest-*`-Name wird akzeptiert; ein Name ohne `rtest-*`-Präfix wird mit `InfraGuardrailError` hart abgelehnt. |
| **AC7 Edge-Case** | Ein `rtest-*`-Name, der mit einem Produktiv-Allowlist-Eintrag kollidiert, wird trotz korrektem Präfix abgelehnt (AC7 hat Vorrang). |
| **AC8** | Das Provision→Poll→Use→Teardown-Muster (try/finally) führt den Teardown auch aus, wenn der "Use"-Schritt eine Exception wirft; der Guard wird sowohl vor Provisionierung als auch vor Teardown aufgerufen. |
| **AC8 Negativ-Beweis** | Scheitert der Guard bereits beim Provisionieren, wird keine Ressource angelegt und kein Teardown ausgelöst. |

## Ausführen

```bash
./smoke.sh
./infra-leitplanken-smoke.sh
```

Exit-Codes: `0` = alle Verträge grün, `1` = mindestens ein Vertrag verletzt
(Details auf stderr/stdout).

## Wann ausführen

- Nach jedem Edit an `templates/_shared/regression/run-regression.sh` → `smoke.sh`.
- Nach jedem Edit an `templates/_shared/regression/playwright.config.ts`
  (`REGRESSION_BASE_URL`-Wiring) → `smoke.sh`.
- Nach jedem Edit an
  `templates/_shared/regression/tests-example/regression/verbund/infra-guard.ts`
  oder `infra.fixture.ts` → `infra-leitplanken-smoke.sh`.

## Was die Tests NICHT prüfen

- **Echte Playwright-Ausführung** (Browser, Reporter-Dateien) — das ist
  Playwright-eigene Verantwortung, nicht Teil der Runner-/Guard-Mechanik.
