# Knowledge Pack: js

Expertise für JavaScript/Node. Geladen bei `profile.language: js`. Regel-IDs: `js/R<NN>`.

## Coder-Guidance
- `js/R01` — `const`/`let`, nie `var`; strikte Vergleiche (`===`).
- `js/R02` — `async/await` mit `try/catch`; keine unbehandelten Promise-Rejections.
- `js/R03` — Eingaben validieren; externe Fetches mit Timeout + Non-2xx-Zweig.
- `js/R04` — `url.parse()` ist in Node.js 24 **application-deprecated** (DEP0169, Stability 0) — warnt nur für eigenen Code, nicht für `node_modules` (siehe Sektion "Node Deprecation Taxonomy" für die vier Typen); stattdessen `new URL(input)` (WHATWG URL API) verwenden — seit Node.js 10+ verfügbar. Quelle: [Node.js Deprecations — DEP0169](https://nodejs.org/api/deprecations.html#dep0169-insecure-urlparse)
- `js/R05` — Globales `fetch`, `Request`, `Response`, `Headers`, `FormData` und `WebStreams` sind seit Node.js 21 **stabil und ohne Flag** eingebaut; das Paket `node-fetch` ist für aktuelle LTS-Versionen (22+) nicht mehr nötig. Quelle: [Node.js 21 Release Announcement](https://nodejs.org/en/blog/announcements/v21-release-announce)
- `js/R06` — `node:test` (built-in Test-Runner) ist seit Node.js 20 **stabil**; `node --test` läuft Dateien parallel, `describe`/`it`/`mock` sind ohne Extra-Abhängigkeiten verfügbar. Reporters und Coverage (`--experimental-test-coverage`) bleiben experimentell. Quelle: [Node.js 20 Release Announcement](https://nodejs.org/en/blog/announcements/v20-release-announce) · [node:test Docs](https://nodejs.org/api/test.html)

## Reviewer-Checklist
- Unbehandelte async-Fehler / fehlender Timeout bei Fetch → **Important**.
- Secrets/Keys inline statt aus Env → **Critical**.
- String-Interpolation in DB-Queries → **Critical** (siehe `sql`-Pack).
- `url.parse()` verwendet (application-deprecated seit Node.js 24, DEP0169 — warnt nur für eigenen Code, nicht `node_modules`) → **Important**: auf `new URL()` migrieren.
- `node-fetch` als Abhängigkeit auf Node.js 21+ → **Important**: eingebautes `fetch` bevorzugen.

## Test-Approach
- Lint; Build; Node-Smoke / Unit-Tests.
- Ab Node.js 20: `node:test` als zero-dependency Alternative zu Jest/Mocha prüfen (`node --test **/*.test.js`).

## Node Deprecation Taxonomy

Node.js unterscheidet **vier offizielle Deprecation-Typen** (stabil über v20 LTS, v22 LTS, v24 Current; Quelle: [nodejs.org/api/deprecations.html](https://nodejs.org/api/deprecations.html)):

| Typ-Name | Definition | Implikation für Code / Reviewer |
|---|---|---|
| **Documentation-only** | Nur in der API-Doku vermerkt; kein Laufzeit-Effekt. Optional via `--pending-deprecation` / `NODE_PENDING_DEPRECATION=1` als Warnung aktivierbar. | Kein unmittelbarer Handlungsbedarf; Reviewer vermerkt als Low-Priority-Hinweis. |
| **Application** _(non-`node_modules` code only)_ | Gibt beim ersten Aufruf im Applikations-Code eine Prozesswarnung auf `stderr` aus; `node_modules` sind ausgenommen. Mit `--throw-deprecation` wird ein Fehler geworfen. | Eigener Code muss migriert werden; Abhängigkeiten können vorerst ignoriert werden. Reviewer → **Important**. |
| **Runtime** _(all code)_ | Wie Application, aber Warnung gilt für _allen_ Code — inklusive `node_modules`. | Auch transitive Abhängigkeiten können warnen; Migration prüfen + ggf. Abhängigkeit upgraden. Reviewer → **Important**. |
| **End-of-Life** | Funktionalität ist entfernt oder wird es bald; die API funktioniert nicht mehr (oder nur noch befristet). | Sofortige Migration erforderlich, bevor auf die betreffende Node-Version upgegraded wird. Reviewer → **Critical**. |

**Merkhilfe Eskalationsstufe:** Documentation-only < Application < Runtime < End-of-Life.
