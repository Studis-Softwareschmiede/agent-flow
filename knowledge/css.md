# Knowledge Pack: css

Expertise für modernes CSS. Geladen als Domäne bei UI-Projekten. Regel-IDs: `css/R<NN>`.

## Coder-Guidance
- `css/R01` — Design-Tokens als Custom Properties (`--color-…`, `--space-…`); keine Magic-Werte.
- `css/R02` — Mobile-first: `@media (min-width: …)` progressiv.
- `css/R03` — Persistente Animationen unter `@media (prefers-reduced-motion: reduce)` abschalten.
- `css/R04` — Für **komponenten-bezogene** Responsiveness `@container` (Size Container Queries) statt globaler `@media`-Breakpoints nutzen — die Komponente reagiert auf ihren Container, nicht auf den Viewport. Eltern brauchen `container-type: inline-size` (oder `container`). Seit **August 2025 Baseline „Widely available"** (newly available seit Feb 2023), also produktionsreif ohne Polyfill. Quelle: [web.dev — Baseline digest Aug 2025](https://web.dev/blog/baseline-digest-aug-2025) · [MDN — CSS container queries](https://developer.mozilla.org/en-US/docs/Web/CSS/CSS_Container_Queries).
- `css/R05` — Light/Dark-Farben mit `light-dark(<light>, <dark>)` in **einer** Deklaration statt doppelter `prefers-color-scheme`-Blöcke. **Voraussetzung:** `color-scheme: light dark` (i. d. R. auf `:root`) — ohne das greift `light-dark()` nicht. Baseline „Newly available" seit **Mai 2024**. Quelle: [MDN — `light-dark()`](https://developer.mozilla.org/en-US/docs/Web/CSS/color_value/light-dark).
- `css/R06` — `:has()` ist **nicht forgiving**: Wird `:has()` (oder ein Argument darin) nicht unterstützt, fällt der **gesamte** Selektor-Block aus. Für graceful degradation in `:is()`/`:where()` kapseln (z. B. `:where(h1:has(+ h2))`). Baseline „Newly available" seit **Dez 2023**. Quelle: [MDN — `:has()`](https://developer.mozilla.org/en-US/docs/Web/CSS/:has).
- `css/R07` — Natives CSS Nesting (ohne Build-Step, ohne Sass) ist Baseline „Newly available" seit **2023-12-11**, erwartet „Widely available" ab **2026-06-11**. Wichtigste Falle: `&` ist bei Pseudo-Klassen/Pseudo-Elementen und Compound-Selektoren **zwingend** (`.card { &:hover {} }` korrekt); bei Nachfahren-Selektoren optional (`.card { .title {} }` = `.card .title`). Kein String-Concatenation à la Sass (`.block { &__element {} }` ist **ungültig** — erzeugt keinen Typ-Selektor). Quelle: [MDN — CSS nesting](https://developer.mozilla.org/en-US/docs/Web/CSS/CSS_nesting) · [web-features-explorer — nesting](https://web-platform-dx.github.io/web-features-explorer/features/nesting/).
- `css/R08` — `color-mix(in <colorspace>, <color1> [pct], <color2> [pct])` mischt zwei Farben in einem gewählten Farbraum (z. B. `oklab` für perceptuell gleichmässige Resultate, `srgb` für klasssisches Alpha-Blending). Baseline **„Widely available" seit 2025-11-09** — produktionsreif ohne Fallback. Ersetzt preprocessor-Tints/-Shades durch reines CSS (`color-mix(in oklab, var(--color-primary) 80%, white)`). Quelle: [MDN — `color-mix()`](https://developer.mozilla.org/en-US/docs/Web/CSS/color_value/color-mix) · [web-features-explorer — color-mix](https://web-platform-dx.github.io/web-features-explorer/features/color-mix/).
- `css/R09` — `@starting-style` definiert den **Ausgangs-Zustand** für CSS-Transitions beim ersten Render eines Elements (Entry-Transition) oder wenn `display` von `none` wechselt. Ohne `@starting-style` werden Transitions beim ersten Paint **nicht ausgelöst**. Baseline „Newly available" seit **2024-08-06** (~86 % globale Abdeckung); als Progressive Enhancement einsetzbar (ältere Browser überspringen die Eintritts-Animation, Layout bleibt korrekt). Spezifität-Falle: `@starting-style`-Block **nach** dem Haupt-Ruleset platzieren, da gleiche Spezifität gilt und sonst die Haupt-Styles überschreiben. Quelle: [MDN — `@starting-style`](https://developer.mozilla.org/en-US/docs/Web/CSS/@starting-style) · [web-features-explorer — starting-style](https://web-platform-dx.github.io/web-features-explorer/features/starting-style/).

## Reviewer-Checklist
- Werte außerhalb der Spacing-/Token-Skala → **Important**.
- Kontrast < WCAG (Body 4.5:1 / Large 3:1) — **berechnen**, nicht schätzen → **Critical**.
- Animationen ohne `prefers-reduced-motion`-Berücksichtigung → **Important**.
- `@container`-Query ohne `container-type`/`container` auf einem Vorfahren → Query ist wirkungslos → **Important** (`css/R04`).
- `light-dark()` verwendet, aber kein `color-scheme: light dark` gesetzt → Funktion greift nicht → **Important** (`css/R05`).
- `:has()` außerhalb von `:is()`/`:where()` in einem Selektor, der auch unsupporteten Browsern dienen muss → kompletter Block-Ausfall → **Important** (`css/R06`).
- Sass-style `&__element`-Concatenation in nativem CSS → ungültig (kein Type-Selektor-Prefix) → **Important** (`css/R07`).
- `color-mix()` mit `srgb` statt `oklab`/`oklch` für Tints/Shades → perceptuell ungleichmässige Ergebnisse — `oklab` bevorzugen → **Minor** (`css/R08`).
- `@starting-style`-Block vor dem Haupt-Ruleset → gleiche Spezifität, Haupt-Styles gewinnen, Entry-Transition fehlt → **Important** (`css/R09`).

## Test-Approach
- Visueller Smoke; Kontrast der geänderten Farbpaare berechnet.
- Container-Queries: Komponente isoliert in schmalem/breitem Container rendern (nicht nur Viewport resizen) und Layout-Wechsel verifizieren.
- `light-dark()`: in beiden `color-scheme`-Modi (Light/Dark) prüfen.
- CSS Nesting: in DevTools CSSOM verifizieren dass Selektoren korrekt aufgelöst werden (Compound-Selektoren mit `&`).
- `@starting-style`: Element aus DOM entfernen und wieder einfügen (oder `display: none` → sichtbar) — Entry-Transition muss ausgelöst werden.
