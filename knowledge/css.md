# Knowledge Pack: css

Expertise für modernes CSS. Geladen als Domäne bei UI-Projekten. Regel-IDs: `css/R<NN>`.

## Coder-Guidance
- `css/R01` — Design-Tokens als Custom Properties (`--color-…`, `--space-…`); keine Magic-Werte.
- `css/R02` — Mobile-first: `@media (min-width: …)` progressiv.
- `css/R03` — Persistente Animationen unter `@media (prefers-reduced-motion: reduce)` abschalten.
- `css/R04` — Für **komponenten-bezogene** Responsiveness `@container` (Size Container Queries) statt globaler `@media`-Breakpoints nutzen — die Komponente reagiert auf ihren Container, nicht auf den Viewport. Eltern brauchen `container-type: inline-size` (oder `container`). Seit **August 2025 Baseline „Widely available"** (newly available seit Feb 2023), also produktionsreif ohne Polyfill. Quelle: [web.dev — Baseline digest Aug 2025](https://web.dev/blog/baseline-digest-aug-2025) · [MDN — CSS container queries](https://developer.mozilla.org/en-US/docs/Web/CSS/CSS_Container_Queries).
- `css/R05` — Light/Dark-Farben mit `light-dark(<light>, <dark>)` in **einer** Deklaration statt doppelter `prefers-color-scheme`-Blöcke. **Voraussetzung:** `color-scheme: light dark` (i. d. R. auf `:root`) — ohne das greift `light-dark()` nicht. Baseline „Newly available" seit **Mai 2024**. Quelle: [MDN — `light-dark()`](https://developer.mozilla.org/en-US/docs/Web/CSS/color_value/light-dark).
- `css/R06` — `:has()` ist **nicht forgiving**: Wird `:has()` (oder ein Argument darin) nicht unterstützt, fällt der **gesamte** Selektor-Block aus. Für graceful degradation in `:is()`/`:where()` kapseln (z. B. `:where(h1:has(+ h2))`). Baseline „Newly available" seit **Dez 2023**. Quelle: [MDN — `:has()`](https://developer.mozilla.org/en-US/docs/Web/CSS/:has).

## Reviewer-Checklist
- Werte außerhalb der Spacing-/Token-Skala → **Important**.
- Kontrast < WCAG (Body 4.5:1 / Large 3:1) — **berechnen**, nicht schätzen → **Critical**.
- Animationen ohne `prefers-reduced-motion`-Berücksichtigung → **Important**.
- `@container`-Query ohne `container-type`/`container` auf einem Vorfahren → Query ist wirkungslos → **Important** (`css/R04`).
- `light-dark()` verwendet, aber kein `color-scheme: light dark` gesetzt → Funktion greift nicht → **Important** (`css/R05`).
- `:has()` außerhalb von `:is()`/`:where()` in einem Selektor, der auch unsupporteten Browsern dienen muss → kompletter Block-Ausfall → **Important** (`css/R06`).

## Test-Approach
- Visueller Smoke; Kontrast der geänderten Farbpaare berechnet.
- Container-Queries: Komponente isoliert in schmalem/breitem Container rendern (nicht nur Viewport resizen) und Layout-Wechsel verifizieren.
- `light-dark()`: in beiden `color-scheme`-Modi (Light/Dark) prüfen.
