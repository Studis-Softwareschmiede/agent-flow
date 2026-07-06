# Template — `regression` (Playwright)

Regressions-Test-Konventionen und Template-Artefakte für das Fabrik-Framework (Spec [`regression-playwright-conventions.md`](../../../docs/specs/regression-playwright-conventions.md)).

Playwright ist das **eine** stack-agnostische Regressions-Framework aller Fabrik-Projekte: UI via Browser, API via `request`-Kontext, Infra-Verbund via Fixtures mit garantiertem Teardown.

## Inhalt

| Datei / Verzeichnis | Zweck |
|---|---|
| `playwright.config.ts` | Zentrale Playwright-Konfiguration: CTRF-JSON + JUnit-Reporter, Browser-Modi, timeouts. |
| `gitignore.snippet` | `.gitignore`-Regeln: `test-results/` + `playwright-report/` ignoriert; Testdefinitionen selbst versioniert. |
| `tests-example/` | Referenz-Skelett-Layout + ausgearbeitete Beispiele (AC2–AC4). |
| `tests-example/regression/` | Root-Verzeichnis für Regressions-Suiten. |
| `tests-example/regression/<bereich>/` | Bereichs-spezifische Suiten (eine pro Bereichs-`id` aus `board/areas.yaml`). |
| `tests-example/regression/verbund/` | Bereichsübergreifende + Infra-Verbund-Suiten. |

## Referenz-Skelett

Das Layout nach dem Scaffold (AC2):

```
tests/regression/
  board/
    example.spec.ts             # Beispiel-Testdatei
    example.data.json           # Datengetriebene Tabelle (neben der Testdatei)
    example.md                  # Begleitbeschreibung (target-Header, s. regression-runner)
  flow-orchestrierung/
    <suite>.spec.ts
    <suite>.data.json
    <suite>.md
  ...                           # weitere Bereiche aus board/areas.yaml
  verbund/
    infra.fixture.ts            # Referenz-Fixture für Infra-Ketten
    <suite>.spec.ts             # bereichsübergreifende Tests
```

Jeder Bereichs-Ordner `tests/regression/<bereich>/` korrespondiert mit der Bereichs-`id` aus `board/areas.yaml`.

## Datengetriebene Testfälle (AC3)

Die Datentabelle liegt als **JSON neben der Testdatei**:

```
tests/regression/board/
  example.spec.ts
  example.data.json
```

Der Test iteriert über die JSON-Tabelle (2D-Array oder Objekt-Liste). Siehe `tests-example/regression/board/example.spec.ts` + `example.data.json`.

## Fixture-/Teardown-Muster (AC4)

Für Infra-Ketten: **provisionieren → pollen → prüfen → abbauen**, wobei der Abbau (Teardown) **garantiert auch im Fehlerpfad** läuft.

Referenz-Fixture: `tests-example/regression/verbund/infra.fixture.ts`

Das Muster nutzt Playwright's `use()`-Pattern mit `afterEach`-Cleanup oder strukturiertem `try`/`finally`:

```typescript
// Provisionieren
const resource = await provision(...);
try {
  // Pollen
  await poll(resource);
  // Prüfen
  expect(resource.status).toBe('ready');
} finally {
  // Abbauen (garantiert, auch bei Fehler)
  await teardown(resource);
}
```

## Reporter-Konfiguration (AC5)

`playwright.config.ts` aktiviert:

- **CTRF-JSON**: `playwright-ctrf-json-reporter` → maschinenlesbares Aggregat (dev-gui/Verbund-Auswertung).
- **JUnit**: `junit` → CI-Standard (GitLab CI, GitHub Actions).
- Ausgabeordner: `test-results/` (JUnit) + `playwright-report/` (HTML).

Beide werden in den `.gitignore`-Regeln ignoriert.

## gitignore-Pflicht (AC6)

```
# test-results/ + playwright-report/ sind Läufe/Artefakte, nicht versioniert
test-results/
playwright-report/
```

Siehe `gitignore.snippet` zum Anhängen an die App-`.gitignore`.

Testdefinitionen selbst (`tests/regression/**/*.spec.ts`, `tests/regression/**/*.data.json`) bleiben **versioniert**.

## Installation & Verwendung

### Voraussetzungen

```bash
npm install --save-dev @playwright/test playwright-ctrf-json-reporter
```

### Layout

Nach dem Scaffold (via `/new-project` oder `/adopt` mit `regression_scaffold: playwright`):

```bash
# Struktur anlegen und Template-Dateien kopieren
mkdir -p tests/regression
cp -r templates/_shared/regression/tests-example/regression/* tests/regression/

# Konfiguration kopieren
cp templates/_shared/regression/playwright.config.ts .
echo "# append to .gitignore:" && cat templates/_shared/regression/gitignore.snippet >> .gitignore
```

### Test-Ausführung

```bash
# Alle Tests
npx playwright test

# Nur ein Bereich
npx playwright test tests/regression/board

# Mit spezifischem Reporter
npx playwright test --reporter=ctrf
npx playwright test --reporter=junit
```

### Artefakte

Läufe/Ergebnisse landen in (gitignored):
- `test-results/` — JUnit-XML
- `playwright-report/` — HTML-Report

Beide sind maschinenlesbar für CI/Aggregation.

## Konventionen (Spec-Referenz)

- **Stack-agnostisch**: identisches Playwright-Layout über alle Sprachen.
- **Deterministisch**: keine Agenten pro Testlauf (nur beim Definieren/Heilen).
- **Versioniert**: Testdefinitionen + Datentabellen in Git; Läufe/Artefakte NICHT.
- **Fixture-Sicherheit**: Teardown garantiert auch im Fehlerpfad (fixture-scoped oder try/finally).
- **Secrets**: NIE in Testdateien hartcodiert — Runtime-Injektion via Umgebung.
- **Ressourcen-Naming**: Infra-Ressourcen für Tests: Präfix `rtest-` (z.B. `rtest-testdb-001`).

## Verweis

Vollständige Spec: [`docs/specs/regression-playwright-conventions.md`](../../../docs/specs/regression-playwright-conventions.md)

Knowledge-Pack (separate `/train --bootstrap`-Folgeaktion): `knowledge/playwright.md`
