# Knowledge Pack: js

Expertise für JavaScript/Node. Geladen bei `profile.language: js`. Regel-IDs: `js/R<NN>`.

## Coder-Guidance
- `js/R01` — `const`/`let`, nie `var`; strikte Vergleiche (`===`).
- `js/R02` — `async/await` mit `try/catch`; keine unbehandelten Promise-Rejections.
- `js/R03` — Eingaben validieren; externe Fetches mit Timeout + Non-2xx-Zweig.
- `js/R04` — `url.parse()` ist in Node.js 24 runtime-deprecated (DEP0169, Stability 0); stattdessen `new URL(input)` (WHATWG URL API) verwenden — seit Node.js 10+ verfügbar. Quelle: [Node.js v24 Docs — url.parse()](https://nodejs.org/api/url.html)
- `js/R05` — Globales `fetch`, `Request`, `Response`, `Headers`, `FormData` und `WebStreams` sind seit Node.js 21 **stabil und ohne Flag** eingebaut; das Paket `node-fetch` ist für aktuelle LTS-Versionen (22+) nicht mehr nötig. Quelle: [Node.js 21 Release Announcement](https://nodejs.org/en/blog/announcements/v21-release-announce)
- `js/R06` — `node:test` (built-in Test-Runner) ist seit Node.js 20 **stabil**; `node --test` läuft Dateien parallel, `describe`/`it`/`mock` sind ohne Extra-Abhängigkeiten verfügbar. Reporters und Coverage (`--experimental-test-coverage`) bleiben experimentell. Quelle: [Node.js 20 Release Announcement](https://nodejs.org/en/blog/announcements/v20-release-announce) · [node:test Docs](https://nodejs.org/api/test.html)

## Reviewer-Checklist
- Unbehandelte async-Fehler / fehlender Timeout bei Fetch → **Important**.
- Secrets/Keys inline statt aus Env → **Critical**.
- String-Interpolation in DB-Queries → **Critical** (siehe `sql`-Pack).
- `url.parse()` verwendet (runtime-deprecated seit Node.js 24) → **Important**: auf `new URL()` migrieren.
- `node-fetch` als Abhängigkeit auf Node.js 21+ → **Important**: eingebautes `fetch` bevorzugen.

## Test-Approach
- Lint; Build; Node-Smoke / Unit-Tests.
- Ab Node.js 20: `node:test` als zero-dependency Alternative zu Jest/Mocha prüfen (`node --test **/*.test.js`).
