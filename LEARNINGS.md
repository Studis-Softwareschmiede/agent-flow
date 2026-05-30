# LEARNINGS — Self-Improvement-Ledger

Eine Zeile pro Promotion (von `retro`/`train`/`teamLeader`, via PR). Status:
`Proposed → Merged → Measuring → Validated | Reverted`. Spiegelt das Improvement-Board.

| ID | Datum | Pack/Skill | Regel | Quelle | PR | Status |
|----|-------|------------|-------|--------|----|--------|
| `coder/R01` | 2026-05-26 | `agents/coder.md` | Kein Gold-Plating über die Spec hinaus — strikt nur die genannten AC; als Nicht-Ziel Gelistetes nicht bauen; fehlt etwas → SPEC-LÜCKE statt eigenmächtig ergänzen | sandbox-3 `.claude/lessons/coder.md` #1 (wiederkehrendes Spec-Drift-Muster) | retro/coder-no-gold-plating | Proposed |
| `css/R04` | 2026-05-26 | `knowledge/css.md` | `@container` (Size Container Queries) für komponenten-bezogene Responsiveness statt globaler `@media`; braucht `container-type` am Vorfahren — seit Aug 2025 Baseline „Widely available" | [web.dev Baseline digest Aug 2025](https://web.dev/blog/baseline-digest-aug-2025) · [MDN Container Queries](https://developer.mozilla.org/en-US/docs/Web/CSS/CSS_Container_Queries) | train/css | Proposed |
| `css/R05` | 2026-05-26 | `knowledge/css.md` | `light-dark()` für Light/Dark-Farben in einer Deklaration; erfordert `color-scheme: light dark` — Baseline „Newly available" seit Mai 2024 | [MDN light-dark()](https://developer.mozilla.org/en-US/docs/Web/CSS/color_value/light-dark) | train/css | Proposed |
| `css/R06` | 2026-05-26 | `knowledge/css.md` | `:has()` ist nicht forgiving → ganzer Selektor-Block fällt aus, wenn nicht unterstützt; in `:is()`/`:where()` kapseln — Baseline „Newly available" seit Dez 2023 | [MDN :has()](https://developer.mozilla.org/en-US/docs/Web/CSS/:has) | train/css | Proposed |
| `js/R04` | 2026-05-30 | `knowledge/js.md` | `url.parse()` ist in Node.js 24 runtime-deprecated (DEP0169); `new URL()` (WHATWG URL API) verwenden | [Node.js url.parse Docs](https://nodejs.org/api/url.html) | train/knowledge/js-20260530-142009 | Proposed |
| `js/R05` | 2026-05-30 | `knowledge/js.md` | Globales `fetch`, `Request`, `Response`, `Headers`, `FormData`, `WebStreams` seit Node.js 21 stabil+unflagged; `node-fetch` auf LTS 22+ nicht mehr nötig | [Node.js 21 Announcement](https://nodejs.org/en/blog/announcements/v21-release-announce) | train/knowledge/js-20260530-142009 | Proposed |
| `js/R06` | 2026-05-30 | `knowledge/js.md` | `node:test` built-in Test-Runner seit Node.js 20 stabil; `node --test` parallel, `describe`/`it`/`mock` ohne Abhängigkeiten | [Node.js 20 Announcement](https://nodejs.org/en/blog/announcements/v20-release-announce) | train/knowledge/js-20260530-142009 | Proposed |
