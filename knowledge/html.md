# Knowledge Pack: html

Expertise für statisches HTML5. Geladen bei `profile.language: html`. Regel-IDs: `html/R<NN>`.

## Coder-Guidance
- `html/R01` — Semantisches HTML5 (`header/nav/main/section/footer`), keine `div`-Suppe.
- `html/R02` — Keine Inline-Styles; CSS in Dateien (siehe `css`-Pack).
- `html/R03` — Assets bündeln, **kein** externes CDN (offline-first, CORS).

## Reviewer-Checklist
- Externes CDN für Fonts/Libs → **Critical** (offline-first verletzt).
- Nicht-semantisches Markup / fehlende Landmarks → **Important**.
- `img` ohne `alt`, Form-Felder ohne `label` → **Important** (A11y).

## Test-Approach
- Markup validiert (keine offenen Tags); Seite lädt; A11y-Basis (Landmarks, alt, Tab-Reihenfolge).
