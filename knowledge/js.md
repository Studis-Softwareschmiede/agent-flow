# Knowledge Pack: js

Expertise für JavaScript/Node. Geladen bei `profile.language: js`. Regel-IDs: `js/R<NN>`.

## Coder-Guidance
- `js/R01` — `const`/`let`, nie `var`; strikte Vergleiche (`===`).
- `js/R02` — `async/await` mit `try/catch`; keine unbehandelten Promise-Rejections.
- `js/R03` — Eingaben validieren; externe Fetches mit Timeout + Non-2xx-Zweig.
- `js/R04` — `url.parse()` ist in Node.js 24 **application-deprecated** (DEP0169, Stability 0) — warnt nur für eigenen Code, nicht für `node_modules` (siehe Sektion "Node Deprecation Taxonomy" für die vier Typen); stattdessen `new URL(input)` (WHATWG URL API) verwenden — seit Node.js 10+ verfügbar. Quelle: [Node.js Deprecations — DEP0169](https://nodejs.org/api/deprecations.html#dep0169-insecure-urlparse)
- `js/R05` — Globales `fetch`, `Request`, `Response`, `Headers`, `FormData` und `WebStreams` sind seit Node.js 21 **stabil und ohne Flag** eingebaut; das Paket `node-fetch` ist für aktuelle LTS-Versionen (22+) nicht mehr nötig. Quelle: [Node.js 21 Release Announcement](https://nodejs.org/en/blog/announcements/v21-release-announce)
- `js/R06` — `node:test` (built-in Test-Runner) ist seit Node.js 20 **stabil**; `node --test` läuft Dateien parallel, `describe`/`it`/`mock` sind ohne Extra-Abhängigkeiten verfügbar. Reporters und Coverage (`--experimental-test-coverage`) bleiben experimentell. Quelle: [Node.js 20 Release Announcement](https://nodejs.org/en/blog/announcements/v20-release-announce) · [node:test Docs](https://nodejs.org/api/test.html)
- `js/R07` — **Jest in einem Repo mit parallelen git-Worktrees** (z.B. die agent-flow-Worktrees unter `.claude/worktrees/`): die jest-Config MUSS diese Pfade aus **beidem** ausschließen — der Test-Auswahl (`testPathIgnorePatterns`) **und** der Modul-/Haste-Map (`modulePathIgnorePatterns`), je mit `'/\\.claude/worktrees/'`. Sonst nimmt jest die `src/`-Duplikate der Worktrees als *duplicate haste modules* auf und der **geteilte Transform-Cache** transformiert dieselbe Datei mal als CJS, mal als ESM → `SyntaxError: Cannot use import statement outside a module` bzw. `Test suite failed to run` in einer Datei, die niemand geändert hat. `testPathIgnorePatterns` allein maskiert nur das Symptom im Lauf, die Haste-/Cache-Vergiftung bleibt. **Akut-Reparatur** eines bereits vergifteten Caches: `jest --clearCache`.
- `js/R08` — **`Temporal` API ist TC39 Stage 4 (März 2026)** und in Node.js 26 (Mai 2026) ohne Flag aktiviert. `Date` durch `Temporal.ZonedDateTime`, `Temporal.PlainDate` etc. ablösen — die neuen Typen sind unveränderlich und timezone-aware. TypeScript-Typdefinitionen ab TS 6.0 enthalten. In Browsern: Firefox 139+, Chrome 144+ stabil. Quelle: [tc39/proposal-temporal README](https://github.com/tc39/proposal-temporal/blob/main/README.md) · [Node.js 26.0.0 Release](https://nodejs.org/en/blog/release/v26.0.0)
- `js/R09` — **`_stream_*`-Legacy-Module in Node.js 26 entfernt (End-of-Life, Breaking Change).** `_stream_readable`, `_stream_writable`, `_stream_duplex`, `_stream_transform`, `_stream_passthrough`, `_stream_wrap` existieren nicht mehr — direkten Import über `require('_stream_readable')` etc. sofort auf `require('node:stream').Readable` (bzw. `.Writable`, `.Duplex`, …) migrieren. Betrifft jeden Code, der undokumentierte interne Module direkt importiert hat. Quelle: [Node.js 26.0.0 Release](https://nodejs.org/en/blog/release/v26.0.0)
- `js/R10` — **`Map.prototype.getOrInsert(key, value)` und `Map.prototype.getOrInsertComputed(key, fn)` stabil ab Node.js 26** (V8 14.6, Upsert-Proposal). Ersetzt das verbreitete `map.has(k) ? map.get(k) : (map.set(k, v), v)`-Muster. Gilt analog für `WeakMap`. Quelle: [Node.js 26.0.0 Release](https://nodejs.org/en/blog/release/v26.0.0) · [TC39 Upsert Proposal](https://github.com/tc39/proposals/blob/main/finished-proposals.md)

## Reviewer-Checklist
- Unbehandelte async-Fehler / fehlender Timeout bei Fetch → **Important**.
- Secrets/Keys inline statt aus Env → **Critical**.
- String-Interpolation in DB-Queries → **Critical** (siehe `sql`-Pack).
- `url.parse()` verwendet (application-deprecated seit Node.js 24, DEP0169 — warnt nur für eigenen Code, nicht `node_modules`) → **Important**: auf `new URL()` migrieren.
- `node-fetch` als Abhängigkeit auf Node.js 21+ → **Important**: eingebautes `fetch` bevorzugen.
- jest-Repo, das parallele git-Worktrees nutzt, aber `.claude/worktrees/` NICHT aus `testPathIgnorePatterns` **und** `modulePathIgnorePatterns` ausschließt (`js/R07`) → **Important**: fremde Worktree-Modulkopien vergiften Haste-Map und Transform-Cache.
- `new Date()` für komplexe Datums-/Zeitarithmetik auf Node.js 26+ (`js/R08`) → **Important**: `Temporal`-API bevorzugen (unveränderlich, timezone-korrekt, Stage 4).
- `require('_stream_readable')` / `_stream_writable` / `_stream_duplex` etc. direkt importiert (`js/R09`) → **Critical** bei Node.js 26+: Module entfernt; auf `require('node:stream').Readable` migrieren.
- `map.has(k) ? map.get(k) : (map.set(k, v), v)`-Pattern auf Node.js 26+ (`js/R10`) → **Info**: `map.getOrInsert(k, v)` verfügbar.
- Test für einen Cross-Repo-/Cross-Komponenten-Vertrag baut den Fixture als **handgeschriebenen Mock**, der die **Annahme der eigenen (Konsumenten-)Komponente** spiegelt, statt vom **echten Produzenten-Output** abzuleiten (`js/R11`) → **Important**: Solche Tests bestätigen den Bug statt ihn zu fangen (der Mock hat per Konstruktion genau die Form, die der Konsument erwartet). Verlangt einen Fixture aus einer realen Produzenten-Zeile/-Ausgabe **und** mindestens einen Integrations-/Contract-Test Produzent→Konsument.

## Test-Approach
- Lint; Build; Node-Smoke / Unit-Tests.
- Ab Node.js 20: `node:test` als zero-dependency Alternative zu Jest/Mocha prüfen (`node --test **/*.test.js`).
- **`Test suite failed to run` / `Cannot use import statement outside a module` / `duplicate haste module` in einer Datei, die der aktuelle Diff NICHT geändert hat = fast immer Umgebungs-/Cache-Artefakt, KEIN Code-FAIL.** Zuerst `jest --clearCache` + erneut laufen (häufigste Wurzel: Worktree-Interferenz, `js/R07`), bevor ein FAIL gemeldet wird. Bleibt es nach sauberem Cache rot → echter Defekt.
- **Cross-Repo-Vertrag gegen echten Produzenten-Output testen (`js/R11`):** Berührt der Diff eine Naht zwischen zwei Komponenten/Repos (Runner ↔ Agent-Ausgabe, Backend ↔ Ledger-Datei, API-Producer ↔ Consumer), den Fixture aus einer **realen Produzenten-Zeile** ableiten — nie einen Mock erfinden, der die Erwartung des Konsumenten spiegelt. Zusätzlich ein Integrations-/Contract-Test, der echten Produzenten-Output durch den echten Konsumenten-Parser/-Renderer schickt. *Zweimal in dieser Fabrik verbrannt: 2026-07-08 (regression-define: Mock trug `status`-Feld, das das Agent-Format nie liefert → „kein gültiges JSON" fehlgemeldet, ~5h); 2026-07-17 (Story-Detail: Test mockte `tok: 800`, real ist `tok: {in,out,cache}` → `[object Object]` unbemerkt, weil `tok` wochenlang `null` war).*

## Node Deprecation Taxonomy

Node.js unterscheidet **vier offizielle Deprecation-Typen** (stabil über v20 LTS, v22 LTS, v24 Current; Quelle: [nodejs.org/api/deprecations.html](https://nodejs.org/api/deprecations.html)):

| Typ-Name | Definition | Implikation für Code / Reviewer |
|---|---|---|
| **Documentation-only** | Nur in der API-Doku vermerkt; kein Laufzeit-Effekt. Optional via `--pending-deprecation` / `NODE_PENDING_DEPRECATION=1` als Warnung aktivierbar. | Kein unmittelbarer Handlungsbedarf; Reviewer vermerkt als Low-Priority-Hinweis. |
| **Application** _(non-`node_modules` code only)_ | Gibt beim ersten Aufruf im Applikations-Code eine Prozesswarnung auf `stderr` aus; `node_modules` sind ausgenommen. Mit `--throw-deprecation` wird ein Fehler geworfen. | Eigener Code muss migriert werden; Abhängigkeiten können vorerst ignoriert werden. Reviewer → **Important**. |
| **Runtime** _(all code)_ | Wie Application, aber Warnung gilt für _allen_ Code — inklusive `node_modules`. | Auch transitive Abhängigkeiten können warnen; Migration prüfen + ggf. Abhängigkeit upgraden. Reviewer → **Important**. |
| **End-of-Life** | Funktionalität ist entfernt oder wird es bald; die API funktioniert nicht mehr (oder nur noch befristet). | Sofortige Migration erforderlich, bevor auf die betreffende Node-Version upgegraded wird. Reviewer → **Critical**. |

**Merkhilfe Eskalationsstufe:** Documentation-only < Application < Runtime < End-of-Life.

## Spec-Tagging
Trace-Tag je gedecktem Kriterium gemäss `docs/architecture/traceability-subsystem.md`.
- **Idiom (Vitest/Jest/node:test):** kanonisches Token im `it()`/`test()`-Titel (Komma-Liste erlaubt): `it('@trace user-login#AC1,AC3 — rejects empty password', () => { … })`. Vitest zusätzlich filterbar via `-t "@trace user-login#AC1"`.
- **Idiom (Playwright):** Titel-Token wie oben (optional native `{ tag: [...] }`, maßgeblich bleibt das Titel-Token).
- **Extraktions-Rezept:** Test-Titel einsammeln (`vitest list --json`, Jest-AST oder `grep -RoE`), dann Core-Regex `@trace\s+([a-z0-9][a-z0-9-]*)#((?:AC\d+|BR-\d+)(?:,(?:AC\d+|BR-\d+))*)`.
