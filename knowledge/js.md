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

## Node Deprecation Taxonomy

Node.js unterscheidet **vier offizielle Deprecation-Typen** (stabil über v20 LTS, v22 LTS, v24 Current; Quelle: [nodejs.org/api/deprecations.html](https://nodejs.org/api/deprecations.html)):

| Typ-Name | Definition | Implikation für Code / Reviewer |
|---|---|---|
| **Documentation-only** | Nur in der API-Doku vermerkt; kein Laufzeit-Effekt. Optional via `--pending-deprecation` / `NODE_PENDING_DEPRECATION=1` als Warnung aktivierbar. | Kein unmittelbarer Handlungsbedarf; Reviewer vermerkt als Low-Priority-Hinweis. |
| **Application** _(non-`node_modules` code only)_ | Gibt beim ersten Aufruf im Applikations-Code eine Prozesswarnung auf `stderr` aus; `node_modules` sind ausgenommen. Mit `--throw-deprecation` wird ein Fehler geworfen. | Eigener Code muss migriert werden; Abhängigkeiten können vorerst ignoriert werden. Reviewer → **Important**. |
| **Runtime** _(all code)_ | Wie Application, aber Warnung gilt für _allen_ Code — inklusive `node_modules`. | Auch transitive Abhängigkeiten können warnen; Migration prüfen + ggf. Abhängigkeit upgraden. Reviewer → **Important**. |
| **End-of-Life** | Funktionalität ist entfernt oder wird es bald; die API funktioniert nicht mehr (oder nur noch befristet). | Sofortige Migration erforderlich, bevor auf die betreffende Node-Version upgegraded wird. Reviewer → **Critical**. |

**Merkhilfe Eskalationsstufe:** Documentation-only < Application < Runtime < End-of-Life.
