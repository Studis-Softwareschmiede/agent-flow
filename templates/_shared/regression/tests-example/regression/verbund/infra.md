---
title: Infra-Verbund-Kette (Referenz-Fixture)
target: ephemeral-infra
kosten: gering — simulierte Provisionierung/Polling/Teardown (kein echtes Wegwerf-Ziel im Beispiel)
---

# Infra-Verbund-Tests

Test-Begleitbeschreibung für die Referenz-Suite `infra.spec.ts`.

## target

`target: ephemeral-infra` (vgl. [[regression-runner]] AC2/AC4): die Suite
erzeugt + zerstört ihr eigenes Wegwerf-Ziel selbst über die Fixture
(`infra.fixture.ts`, provisionieren → pollen → prüfen → abbauen, garantierter
Teardown auch im Fehlerpfad — [[regression-playwright-conventions]] AC4). Der
Regressions-Runner (`scripts/run-regression.sh`) führt diese Suite ohne
lokalen Erreichbarkeits-Check und ohne `REGRESSION_BASE_URL` aus — die
Fixture kümmert sich selbst um ihr Ziel.

Ressourcen-Namensschema (`rtest-*`) und Produktiv-Allowlist/garantiertes
Cleanup auf Infra-Leitplanken-Ebene ([[regression-runner]] AC7/AC8) sind über
`infra-guard.ts` (`guardInfraResourceName`) durchgesetzt: die Fixture ruft den
Guard vor JEDER Provisionierung UND vor JEDEM Teardown eines
Ressourcennamens auf — Verstöße (kein `rtest-*`-Präfix, oder Kollision mit der
projekteigenen Produktiv-Allowlist) brechen hart ab.

## Verdrahtet mit

- Testdatei: `infra.spec.ts`
- Fixture: `infra.fixture.ts` (garantierter Teardown via `try`/`finally`)
- Guard: `infra-guard.ts` (`rtest-*`-Namensschema + Produktiv-Allowlist, AC7/AC8)
- Reporter: CTRF-JSON + JUnit (wird via `playwright.config.ts` aktiviert)
