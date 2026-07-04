# Knowledge Pack: tailwind

Expertise für Tailwind CSS. Domäne bei UI-Projekten mit Tailwind. Regel-IDs: `tailwind/R<NN>`.

## Coder-Guidance
- `tailwind/R01` — Utility-first; wiederkehrende Klassen-Cluster in Komponenten/`@apply` extrahieren.
- `tailwind/R02` — **[v4 Update]** Tokens in `@theme { --color-...: ...; }` im CSS definieren (v4: CSS-first config); `tailwind.config.js` wird in v4 **nicht mehr automatisch erkannt** — nur noch via explizitem `@config`-Directive nutzbar oder vollständig durch CSS-Konfiguration ersetzen. Keine Arbitrary-Values (`[...]`), wo ein Token existiert. — Quelle: [Tailwind v4 Upgrade Guide](https://tailwindcss.com/docs/upgrade-guide) · [v4 Blog](https://tailwindcss.com/blog/tailwindcss-v4) · stabil seit 22. Jan 2025
- `tailwind/R03` — **(v4 Deprecations)** Die `*-opacity-*`-Utilities (`bg-opacity-*`, `text-opacity-*`, `border-opacity-*`, `ring-opacity-*`, `divide-opacity-*`, `placeholder-opacity-*`) sind in v4 entfernt — Slash-Opacity-Syntax verwenden: `bg-black/50`, `text-white/75`. `flex-shrink-*`, `flex-grow-*` und `overflow-ellipsis` sind in v4 als rückwärtskompatible Aliases erhalten (beta.1 PR #15069), aber deprecated — in neuem Code `shrink-*`/`grow-*`/`text-ellipsis` verwenden; das Upgrade-Tool migriert automatisch. — Quelle: [Tailwind v4 Upgrade Guide — Removed Utilities](https://tailwindcss.com/docs/upgrade-guide) · [CHANGELOG beta.1 PR #15069](https://github.com/tailwindlabs/tailwindcss/pull/15069)
- `tailwind/R04` — **(v4 Breaking Change)** Mehrere Utility-Klassen wurden in v4 umbenannt/verschoben; direkte Ersetzungen: `shadow` → `shadow-sm`, `shadow-sm` → `shadow-xs`; `outline-none` → `outline-hidden`; `ring` → `ring-3`; `blur` → `blur-sm`, `blur-sm` → `blur-xs`; `rounded` → `rounded-sm`, `rounded-sm` → `rounded-xs`; `bg-gradient-*` → `bg-linear-*`. Der `!important`-Modifier: v4 empfiehlt Suffix-Syntax (`flex!`), Präfix-Syntax (`!flex`) ist weiterhin gültig aber deprecated — das Upgrade-Tool migriert auf Suffix. — Quelle: [Tailwind v4 Upgrade Guide — Renamed Utilities & Important Modifier](https://tailwindcss.com/docs/upgrade-guide)
- `tailwind/R05` — **(v4.1 stabil)** `text-shadow-{2xs,xs,sm,md,lg}`-Utilities sind seit v4.1 eingebaut (kein Plugin nötig); Farbe via `text-shadow-<color>` und Opacity via `/`-Modifier (`text-shadow-lg/50`). Vorher war Text-Schatten nur über Third-Party-Plugin (`@tailwindcss/typography` oder `tailwindcss-textshadow`) möglich. — Quelle: [Tailwind CSS v4.1 Blog](https://tailwindcss.com/blog/tailwindcss-v4-1) · stabil seit v4.1 (April 2025)
- `tailwind/R06` — **(v4.1 Deprecation)** `bg-{left,right}-{top,bottom}`-Utilities (z.B. `bg-left-top`, `bg-right-bottom`) sind in v4.1 deprecated; kanonische Reihenfolge ist jetzt `bg-{top,bottom}-{left,right}` (z.B. `bg-top-left`, `bg-bottom-right`). Analog: `object-{left,right}-{top,bottom}` → `object-{top,bottom}-{left,right}`. — Quelle: [Tailwind CSS CHANGELOG v4.1.0](https://github.com/tailwindlabs/tailwindcss/blob/main/CHANGELOG.md) · stabil seit v4.1 (April 2025)
- `tailwind/R07` — **(v4.2 Deprecation)** `start-*`/`end-*`-Utilities (z.B. `start-0`, `end-4`) sind in v4.2 deprecated zugunsten von `inset-s-*`/`inset-e-*` (z.B. `inset-s-0`, `inset-e-4`), damit die API konsistent mit `inset-bs-*`/`inset-be-*` ist. Beide Formen funktionieren noch; das Upgrade-Tool migriert automatisch. — Quelle: [Tailwind CSS v4.3 Blog (inkl. v4.2-Änderungen)](https://tailwindcss.com/blog/tailwindcss-v4-3) · deprecation eingeführt in v4.2 (2025)

## Reviewer-Checklist
- Arbitrary-Values statt Token (`w-[317px]`) → **Important** (Token-Disziplin).
- Lange, duplizierte Klassen-Strings ohne Extraktion → **Suggestion**.
- Kontrast/A11y wie im `css`-Pack → **Critical/Important**.
- `bg-opacity-*` / `text-opacity-*` / `*-opacity-*` im v4-Projekt → **Critical** (Klassen wurden entfernt; Slash-Syntax verwenden).
- `flex-grow-*` / `flex-shrink-*` / `overflow-ellipsis` im v4-Projekt → **Important** (deprecated Aliases, funktionieren noch; auf `grow-*`/`shrink-*`/`text-ellipsis` migrieren).
- `tailwind.config.js` ohne `@config`-Directive in v4-Projekt → **Important** (wird stillschweigend ignoriert).
- `outline-none`, `ring`, `shadow`, `blur`, `rounded` ohne Suffix in v4-Projekt → **Important** (Semantik hat sich verschoben; gegen Upgrade Guide prüfen).
- `text-shadow`-Plugin eines Drittanbieters in v4.1+-Projekt → **Suggestion** (v4.1 liefert `text-shadow-*` eingebaut; Plugin entfernen, R05).
- `bg-left-top`, `bg-right-top`, `bg-left-bottom`, `bg-right-bottom` in v4.1+-Projekt → **Important** (deprecated; `bg-top-left`, `bg-top-right` etc. verwenden, R06).
- `start-*`/`end-*`-Utilities (z.B. `start-0`, `end-4`) in v4.2+-Projekt → **Important** (deprecated; `inset-s-*`/`inset-e-*` verwenden, R07).

## Test-Approach
- Build (Purge/JIT) ok, keine fehlenden Klassen; visueller Smoke.
- Bei v3→v4-Migration: automatisches Upgrade-Tool (`npx @tailwindcss/upgrade`) ausführen und Output auf umbenannte/entfernte Klassen prüfen.
