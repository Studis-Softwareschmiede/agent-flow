# Knowledge Pack: html

Expertise für statisches HTML5. Geladen bei `profile.language: html`. Regel-IDs: `html/R<NN>`.

## Coder-Guidance
- `html/R01` — Semantisches HTML5 (`header/nav/main/section/footer`), keine `div`-Suppe.
- `html/R02` — Keine Inline-Styles; CSS in Dateien (siehe `css`-Pack).
- `html/R03` — Assets bündeln, **kein** externes CDN (offline-first, CORS).
- `html/R04` — `popover`-Attribut (WHATWG-Spec) für native Overlays/Tooltips/Dropdowns statt custom JS-Lösungen: `popover="auto"` = Light-Dismiss + schließt andere Auto-Popovers; `popover="manual"` = nur per `hidePopover()` oder explizitem Button schließbar. Baseline Newly Available seit 27. Jan 2025. — [WHATWG HTML Spec §6.12](https://html.spec.whatwg.org/multipage/popover.html) · [web.dev Popover Baseline](https://web.dev/blog/popover-baseline)
- `html/R05` — `inert`-Attribut (Boolean, global) macht einen Teilbaum vollständig nicht-interaktiv und entfernt ihn aus dem Accessibility-Tree; kein eigenes visuelles Feedback — CSS muss `[inert]`-Bereiche klar als inaktiv kennzeichnen. Baseline Widely Available seit Okt 2025. — [WHATWG HTML Spec §interaction/inert](https://html.spec.whatwg.org/dev/interaction.html) · [MDN inert](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Global_attributes/inert)
- `html/R07` — `<details name="gruppe">` für native Exclusive-Accordions ohne JS: Mehrere `<details>`-Elemente mit gleichem `name`-Wert bilden eine Gruppe — das Öffnen eines Elements schließt alle anderen der Gruppe automatisch. Kein JS-Event-Handling nötig. Baseline Newly Available seit 3. Sep 2024. — [WHATWG HTML Spec §interactive-elements](https://html.spec.whatwg.org/multipage/interactive-elements.html#the-details-element) · [MDN HTMLDetailsElement: name](https://developer.mozilla.org/en-US/docs/Web/API/HTMLDetailsElement/name)
- `html/R08` — Invoker Commands API (`command`/`commandfor` auf `<button>`) für deklaratives Steuern von `<dialog>`- und Popover-Elementen ohne JS: `<button commandfor="my-dialog" command="show-modal">Öffnen</button>` — Built-in-Commands: `show-modal`, `close`, `request-close`, `toggle-popover`, `show-popover`, `hide-popover`; Custom-Commands mit `--`-Präfix möglich. Focus-Management und A11y werden vom Browser übernommen. Baseline Newly Available seit 12. Dez 2025. — [WHATWG HTML Spec §attr-button-command](https://html.spec.whatwg.org/multipage/form-elements.html#attr-button-command) · [MDN Invoker Commands API](https://developer.mozilla.org/en-US/docs/Web/API/Invoker_Commands_API)
- `html/R09` — `<search>`-Element (Grouping-Content) als semantischer Wrapper für Such-/Filter-Formularkontrollen statt `<div role="search">` oder generischem `<form>`: impliziert automatisch die ARIA-Landmark-Rolle `search`, kein manuelles `role="search"` nötig. Ergänzt `html/R01`. Baseline Widely Available seit 13. Apr 2026 (Newly Available bereits seit Okt 2023, jetzt cross-browser gefestigt). — [WHATWG HTML Spec §the-search-element](https://html.spec.whatwg.org/multipage/grouping-content.html#the-search-element) · [MDN `<search>`](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/search)
- `html/R10` — Natives Lazy-Loading via `loading="lazy"` auf `<img>`/`<iframe>` statt JS-/`IntersectionObserver`-Lazy-Load-Libraries (passt zu `html/R03` offline-first, keine externe Lib nötig): Browser verzögert das Laden bis zur Nähe des Viewports; `loading="eager"` (Default) lädt sofort. Kombiniertes Feature „Lazy-loading images and iframes" Baseline Widely Available seit 19. Jun 2026. — [WHATWG HTML Spec §lazy-loading-attributes](https://html.spec.whatwg.org/multipage/urls-and-fetching.html#lazy-loading-attributes) · [MDN `loading` (iframe)](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/iframe#loading)

## Reviewer-Checklist
- Externes CDN für Fonts/Libs → **Critical** (offline-first verletzt).
- Nicht-semantisches Markup / fehlende Landmarks → **Important**.
- `img` ohne `alt`, Form-Felder ohne `label` → **Important** (A11y).
- WCAG 2.2 neue Kriterien (4 AA + 1 A, seit Okt 2023): Neue Pflicht-Kriterien gegenüber 2.1 prüfen — `html/R06`: **Level A:** **3.2.6** Consistent Help (Hilfe-Mechanismus auf gleichem Platz über Seiten hinweg). **Level AA:** **2.4.11** Focus Not Obscured (Fokus mindestens teilweise sichtbar), **2.5.7** Dragging Movements (Drag-Aktionen brauchen Pointer-Alternative), **2.5.8** Target Size Minimum (Interaktionsziele ≥ 24 × 24 CSS-px oder ausreichend Abstand), **3.3.8** Accessible Authentication (kein Cognitive-Function-Test beim Login ohne Alternative). Außerdem entfernt: **4.1.1 Parsing** (war WCAG 2.1, ist in 2.2 obsolet). → [W3C WCAG 2.2 – What's New](https://www.w3.org/WAI/standards-guidelines/wcag/new-in-22/) · [W3C TR/WCAG22](https://www.w3.org/TR/WCAG22/)

## Test-Approach
- Markup validiert (keine offenen Tags); Seite lädt; A11y-Basis (Landmarks, alt, Tab-Reihenfolge).
- WCAG 2.2 AA: Fokus-Indikator sichtbar (2.4.11), Touch-Targets ≥ 24 px (2.5.8), Login ohne reinen Cognitive-Test (3.3.8).

## Spec-Tagging
Trace-Tag je gedecktem Kriterium gemäss `docs/architecture/traceability-subsystem.md`.
- **Kontext:** statische HTML-Projekte testen i.d.R. via Playwright oder besitzen nur Build/Smoke. Bei reinem Smoke greift das Coverage-Gate nur für AC, die als Smoke-Probe formuliert sind.
- **Idiom (Playwright):** kanonisches Titel-Token wie im js-Pack: `test('@trace landing#AC1 — Seite lädt', …)`.
- **Extraktions-Rezept:** wie js-Pack (Core-Regex über Test-Titel).
