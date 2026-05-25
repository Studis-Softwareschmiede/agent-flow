# Knowledge Pack: css

Expertise für modernes CSS. Geladen als Domäne bei UI-Projekten. Regel-IDs: `css/R<NN>`.

## Coder-Guidance
- `css/R01` — Design-Tokens als Custom Properties (`--color-…`, `--space-…`); keine Magic-Werte.
- `css/R02` — Mobile-first: `@media (min-width: …)` progressiv.
- `css/R03` — Persistente Animationen unter `@media (prefers-reduced-motion: reduce)` abschalten.

## Reviewer-Checklist
- Werte außerhalb der Spacing-/Token-Skala → **Important**.
- Kontrast < WCAG (Body 4.5:1 / Large 3:1) — **berechnen**, nicht schätzen → **Critical**.
- Animationen ohne `prefers-reduced-motion`-Berücksichtigung → **Important**.

## Test-Approach
- Visueller Smoke; Kontrast der geänderten Farbpaare berechnet.
