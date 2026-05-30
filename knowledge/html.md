# Knowledge Pack: html

Expertise für statisches HTML5. Geladen bei `profile.language: html`. Regel-IDs: `html/R<NN>`.

## Coder-Guidance
- `html/R01` — Semantisches HTML5 (`header/nav/main/section/footer`), keine `div`-Suppe.
- `html/R02` — Keine Inline-Styles; CSS in Dateien (siehe `css`-Pack).
- `html/R03` — Assets bündeln, **kein** externes CDN (offline-first, CORS).
- `html/R04` — `popover`-Attribut (WHATWG-Spec) für native Overlays/Tooltips/Dropdowns statt custom JS-Lösungen: `popover="auto"` = Light-Dismiss + schließt andere Auto-Popovers; `popover="manual"` = nur per `hidePopover()` oder explizitem Button schließbar. Baseline Newly Available seit 27. Jan 2025. — [WHATWG HTML Spec §6.12](https://html.spec.whatwg.org/multipage/popover.html) · [web.dev Popover Baseline](https://web.dev/blog/popover-baseline)
- `html/R05` — `inert`-Attribut (Boolean, global) macht einen Teilbaum vollständig nicht-interaktiv und entfernt ihn aus dem Accessibility-Tree; kein eigenes visuelles Feedback — CSS muss `[inert]`-Bereiche klar als inaktiv kennzeichnen. Baseline Widely Available seit Okt 2025. — [WHATWG HTML Spec §interaction/inert](https://html.spec.whatwg.org/dev/interaction.html) · [MDN inert](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Global_attributes/inert)

## Reviewer-Checklist
- Externes CDN für Fonts/Libs → **Critical** (offline-first verletzt).
- Nicht-semantisches Markup / fehlende Landmarks → **Important**.
- `img` ohne `alt`, Form-Felder ohne `label` → **Important** (A11y).
- WCAG 2.2 neue Kriterien (4 AA + 1 A, seit Okt 2023): Neue Pflicht-Kriterien gegenüber 2.1 prüfen — `html/R06`: **Level A:** **3.2.6** Consistent Help (Hilfe-Mechanismus auf gleichem Platz über Seiten hinweg). **Level AA:** **2.4.11** Focus Not Obscured (Fokus mindestens teilweise sichtbar), **2.5.7** Dragging Movements (Drag-Aktionen brauchen Pointer-Alternative), **2.5.8** Target Size Minimum (Interaktionsziele ≥ 24 × 24 CSS-px oder ausreichend Abstand), **3.3.8** Accessible Authentication (kein Cognitive-Function-Test beim Login ohne Alternative). Außerdem entfernt: **4.1.1 Parsing** (war WCAG 2.1, ist in 2.2 obsolet). → [W3C WCAG 2.2 – What's New](https://www.w3.org/WAI/standards-guidelines/wcag/new-in-22/) · [W3C TR/WCAG22](https://www.w3.org/TR/WCAG22/)

## Test-Approach
- Markup validiert (keine offenen Tags); Seite lädt; A11y-Basis (Landmarks, alt, Tab-Reihenfolge).
- WCAG 2.2 AA: Fokus-Indikator sichtbar (2.4.11), Touch-Targets ≥ 24 px (2.5.8), Login ohne reinen Cognitive-Test (3.3.8).
