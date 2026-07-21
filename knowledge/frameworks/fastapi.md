---
pack: frameworks/fastapi
pack_version: 1.0
framework_version_range: ""
pack_date: 2026-07-21
primary_sources:
  - https://fastapi.tiangolo.com/
  - https://fastapi.tiangolo.com/tutorial/
  - https://www.uvicorn.org/
  - https://docs.pydantic.dev/latest/
non_sources: [dev.to, medium.com, stackoverflow.com, geeksforgeeks.org]
requires:                         # Solver-Constraints (upgrade-subsystem §12); Quelle: A01/A06
  pydantic: ">=2.0"
---

# Knowledge Pack: frameworks/fastapi

FastAPI verwendet kein Major-Range-Versionsschema wie Spring Boot (`framework_version_range` daher leer) — Regeln gelten für den aktuellen Stable-Stand. Regel-IDs: `fastapi/A<NN>` (Sektion A, train) · `fastapi/B<NN>` (Sektion B, retro) · `fastapi/C<NN>` (Sektion C, Floor).

## A. Stable API & Deprecations

> Quellen-getrieben (`train`-Land). Schreibt: `agent-flow:train`. Nicht ändern ohne `/train frameworks/fastapi`-Lauf.

- `fastapi/A01` — **Pydantic-v2-`BaseModel` für Request-/Response-Bodies.** Alle Request- und Response-Bodies werden als Pydantic-`BaseModel`-Subklassen deklariert (Type-Hints); FastAPI validiert automatisch und liefert bei Fehlern klare Error-Messages inkl. verschachtelter JSON-Objekte. [src: https://fastapi.tiangolo.com/, https://docs.pydantic.dev/latest/]
- `fastapi/A02` — **Dependency Injection via `Depends()` + `Annotated`.** Pfad-Operationen und Sub-Dependencies deklarieren ihre Abhängigkeiten über `Depends(...)`, typischerweise mit `Annotated[T, Depends(fn)]`. Unterstützt Klassen, Funktionen, Sub-Dependencies und globale Dependencies. [src: https://fastapi.tiangolo.com/tutorial/dependencies/]
- `fastapi/A03` — **`async def` nur bei awaitbaren I/O-Bibliotheken, sonst normales `def`.** Wird eine Pfad-Operation mit normalem `def` statt `async def` deklariert, läuft sie in einem externen Threadpool (verhindert Blockieren des Event-Loops). Faustregel laut Doku: bei Unsicherheit `def` verwenden; `async def` nur wenn die verwendeten Bibliotheken `await` unterstützen. Blockierender (synchroner) Code in `async def` blockiert den Event-Loop. [src: https://fastapi.tiangolo.com/async/]
- `fastapi/A04` — **Dependencies mit `yield` für Ressourcen-Cleanup.** Code vor `yield` läuft vor der Pfad-Operation, Code nach `yield` (typischerweise in `finally`) danach — Standardmuster für DB-Sessions/Datei-Handles/Locks. Exceptions in einer `yield`-Dependency müssen per `try/except` behandelt und, falls nicht in eine `HTTPException` umgewandelt, per `raise` erneut geworfen werden. [src: https://fastapi.tiangolo.com/tutorial/dependencies/dependencies-with-yield/]
- `fastapi/A05` — **Fehler-Handling via `HTTPException` + `@app.exception_handler`.** Erwartete Fehler werden per `raise HTTPException(status_code=..., detail=...)` signalisiert (nie `return`). Für eigene Exception-Typen oder zum Überschreiben der Default-Handler (`RequestValidationError`, Starlette-`HTTPException`) wird `@app.exception_handler(ExcType)` registriert, der eine `JSONResponse`/`PlainTextResponse` zurückgibt. [src: https://fastapi.tiangolo.com/tutorial/handling-errors/]
- `fastapi/A06` — **Konfiguration via `pydantic-settings.BaseSettings`, Secrets nie hartkodiert.** Settings/Secrets/Credentials werden als `BaseSettings`-Subklasse deklariert und aus Umgebungsvariablen (optional `.env` via `SettingsConfigDict(env_file=".env")`) gelesen — case-insensitives Env-Var-Mapping. Explizite Doku-Warnung: sensible Settings (Secret-Keys, DB-Credentials) gehören in Env-Variablen, nicht in den Code. Für Wiederverwendung/Testbarkeit: `Settings`-Objekt über eine `Depends`-Factory (`@lru_cache`) injizieren statt global instanzieren. [src: https://fastapi.tiangolo.com/advanced/settings/]
- `fastapi/A07` — **`response_model` filtert Response-Daten — Pflicht bei sensiblen Feldern.** FastAPI entfernt beim Serialisieren automatisch alle Felder, die nicht im deklarierten `response_model` enthalten sind — auch wenn das zurückgegebene Objekt sie enthält. Doku-Warnung explizit zu Secrets: „Never store the plain password of a user or send it in a response like this, unless you know all the caveats." Muster: getrenntes Input-Model (z.B. `UserIn` mit Secret-Feld) und Output-Model (`UserOut` ohne Secret-Feld). [src: https://fastapi.tiangolo.com/tutorial/response-model/]
- `fastapi/A08` — **Production-Deployment: `fastapi run` bzw. `uvicorn --workers N`, NIE `--reload`.** `fastapi run main.py` ist der von den Docs empfohlene Produktions-Start (bindet `0.0.0.0:8000`); manuell: `uvicorn main:app --host 0.0.0.0 --port <port>`. `--reload` ist explizit nur für lokale Entwicklung gedacht (mehr Ressourcenverbrauch, instabil) und darf nicht in Produktion laufen; `--reload` und `--workers` schließen sich laut Uvicorn-Doku gegenseitig aus. [src: https://fastapi.tiangolo.com/deployment/manually/, https://www.uvicorn.org/deployment/, https://www.uvicorn.org/settings/]
- `fastapi/A09` — **Tests via `fastapi.testclient.TestClient` (httpx-basiert) + pytest.** `TestClient` baut auf Starlette/HTTPX auf und wird synchron aufgerufen (`def test_...`, kein `await`); Auth-Header/Body werden wie im echten Request übergeben, Assertions auf `response.status_code`/`response.json()`. Für Dependency-Mocking in Tests: `app.dependency_overrides[get_settings] = get_settings_override`. [src: https://fastapi.tiangolo.com/tutorial/testing/, https://fastapi.tiangolo.com/advanced/settings/]
- `fastapi/A10` — **`router.routes` ist seit 0.137.0 (2026-06-14) kein flacher `APIRoute`-Array mehr, sondern ein Baum (Breaking Change).** Der Router-Internals-Refactor bewahrt `APIRouter`/`APIRoute`-Instanzen bei `include_router()` (kein Klonen/Kopieren der Routen mehr, damit auch nachträgliches Hinzufügen von Pfad-Operationen zu einem bereits inkludierten Router funktioniert). Eigener Code, der `router.routes`/`app.routes` direkt iteriert (z.B. eigene OpenAPI-Introspektion, Test-/Analyse-Tooling), darf keine flache Liste mehr erwarten — laut Release-Notes gilt `router.routes` als „internal implementation detail, only passed around to the FastAPI functions that need it". Für Introspektions-Use-Cases stattdessen die neue Funktion `iter_route_contexts()` (seit 0.137.2) verwenden. [src: https://fastapi.tiangolo.com/release-notes/#01370-2026-06-14]
- `fastapi/A11` — **`app.frontend()` / `router.frontend()` liefert ein gebautes Frontend (SPA) direkt aus FastAPI aus, seit 0.138.0 (2026-06-20).** Dient dem Ausliefern bereits gebauter statischer Frontend-Dateien (z.B. `npm run build`-Output von Vite/React, Vue, Svelte, Angular, Astro, Solid, TanStack Router) über `app.frontend("/", directory="dist")` — kein Server-Side-Rendering. FastAPI prüft eigene *path operations* zuerst; das Frontend-Fallback greift nur, wenn keine reguläre Route matcht, und Requests mit anderen Methoden als GET/HEAD auf einen reinen Frontend-Fallback-Pfad liefern 404. Dependencies aus App/Router/`include_router()` gelten auch für Frontend-Responses (z.B. Cookie-Auth-Guard vor dem Frontend, seit 0.139.0). [src: https://fastapi.tiangolo.com/tutorial/frontend/, https://fastapi.tiangolo.com/release-notes/#01380-2026-06-20]

## B. Anti-Patterns aus Einsatz

> Felderfahrung (`retro`-Land). Schreibt: `agent-flow:retro` ab ≥2 Projekten × ≥2 Stellen (siehe `docs/architecture/framework-build-subsystem.md` §9 Schutzgitter). Stand initial: leer — füllt sich, wenn Projekte real damit arbeiten.

_(noch keine Einträge; siehe Schutzgitter in der Spec)_

## C. Konventionen (Floor)

> Stabile Konventionen, manuell gepflegt (User-Approval Pflicht für Edits durch `train`/`retro`). Stand initial: leer.

_(noch keine Einträge — Floor wird bei Bedarf mit User-Approval befüllt)_

## Coder-Guidance

- Jeder Endpunkt-Body/Query/Path-Parameter über ein Pydantic-`BaseModel` bzw. typisierte Parameter deklarieren, nie `dict`/`Any` roh entgegennehmen (A01).
- Dependencies über `Depends()`/`Annotated` injizieren statt Objekte global zu instanzieren oder in Endpunkten neu aufzubauen (A02).
- `async def` nur wenn alle im Endpunkt verwendeten I/O-Aufrufe awaitbar sind; bei synchronen/blockierenden Bibliotheken normales `def` verwenden (FastAPI übernimmt Threadpool-Auslagerung automatisch) (A03).
- Ressourcen mit Lebenszyklus (Datei-Handles, externe Verbindungen, Locks) über `yield`-Dependencies mit `try/finally` verwalten, nicht manuell im Endpunkt öffnen/schließen (A04).
- Erwartete Fehler über `raise HTTPException(...)` signalisieren; für wiederkehrende eigene Fehlerklassen einen globalen `@app.exception_handler` registrieren statt Fehlerbehandlung in jedem Endpunkt zu duplizieren (A05).
- Konfiguration (inkl. jedes Secrets/API-/Sponsor-Keys) ausschließlich über eine `pydantic-settings.BaseSettings`-Klasse aus Umgebungsvariablen lesen — Secrets NIE als String-Literal im Code, NIE in Git committen, NIE in eine Response oder Log-Zeile schreiben (A06, A07).
- Endpunkte, die interne Objekte mit sensiblen Feldern zurückgeben, IMMER mit einem eingeschränkten `response_model` absichern (separates Output-Model ohne Secret-Feld) (A07).
- Start-/Deploy-Kommando (Dockerfile `CMD`, Procfile, systemd-Unit) verwendet `fastapi run` oder `uvicorn ... --workers N` — `--reload` ausschließlich in lokalen Dev-Skripten (A08).
- Für dateibasiertes Logging (z.B. eine `log.jsonl` statt einer DB-Tabelle) empfiehlt sich das Standard-`logging`-Modul mit einem Zeilen-JSON-Formatter (kein FastAPI-natives Feature, allgemeine Python-Praxis) — dabei nie den kompletten Request-Body oder Settings-Objekt ungefiltert loggen, da beide Secrets enthalten können (sinngemäß A06/A07).

## Reviewer-Checklist

- Secret/API-Key als String-Literal im Code, in einer `.py`-Datei, in einem Response-Model-Feld ohne Ausschluss oder in einer Log-Ausgabe sichtbar → **Critical** (A06, A07).
- Endpunkt-Parameter ohne Pydantic-Model bzw. ohne Typ-Annotation (roher `dict`/`Any`-Body) → **Critical** (A01, fehlende Input-Validierung).
- `async def`-Endpunkt mit erkennbar blockierendem synchronem Code (z.B. `time.sleep`, synchroner Datei-/Netzwerk-I/O ohne Auslagerung) → **Important** (A03, blockiert Event-Loop).
- Kein globaler Exception-Handler und kein `try/except` um fehleranfälligen Code in einem Endpunkt/einer Dependency (unbehandelte Exception würde als 500 mit Default-Trace durchschlagen) → **Important** (A05).
- `--reload` in einem Produktions-Start-Kommando (Dockerfile/Procfile/CI-Deploy-Skript) → **Important** (A08).
- Objekt mit potenziell sensiblen Feldern wird ohne einschränkendes `response_model` zurückgegeben → **Suggestion**, bei tatsächlich enthaltenem Secret-Feld **Critical** (A07).
- `yield`-Dependency ohne `try/finally` (Ressourcen-Leck bei Exception im Endpunkt) → **Important** (A04).

## Test-Approach

- `fastapi.testclient.TestClient` (httpx-basiert) + pytest; Testfunktionen synchron (`def test_...`), Client-Aufrufe ohne `await` (A09).
- Assertions auf `response.status_code` UND `response.json()`-Body-Shape — Status-Code allein belegt kein Verhalten.
- Dependency-Overrides (`app.dependency_overrides[...] = ...`) zum Mocken von Settings/externen Aufrufen in Tests statt echte Secrets/externe Dienste im Testlauf zu benötigen (A09, A06).
- Bei Fehlerpfaden: mindestens ein Test pro registriertem `@app.exception_handler` und pro `raise HTTPException(...)`-Zweig, der den erwarteten Status-Code + Detail-Body verifiziert.
