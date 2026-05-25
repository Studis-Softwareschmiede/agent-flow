# Knowledge Pack: js

Expertise für JavaScript/Node. Geladen bei `profile.language: js`. Regel-IDs: `js/R<NN>`.

## Coder-Guidance
- `js/R01` — `const`/`let`, nie `var`; strikte Vergleiche (`===`).
- `js/R02` — `async/await` mit `try/catch`; keine unbehandelten Promise-Rejections.
- `js/R03` — Eingaben validieren; externe Fetches mit Timeout + Non-2xx-Zweig.

## Reviewer-Checklist
- Unbehandelte async-Fehler / fehlender Timeout bei Fetch → **Important**.
- Secrets/Keys inline statt aus Env → **Critical**.
- String-Interpolation in DB-Queries → **Critical** (siehe `sql`-Pack).

## Test-Approach
- Lint; Build; Node-Smoke / Unit-Tests.
