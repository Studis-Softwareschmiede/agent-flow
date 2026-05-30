# Knowledge Pack: tailwind

Expertise für Tailwind CSS. Domäne bei UI-Projekten mit Tailwind. Regel-IDs: `tailwind/R<NN>`.

## Coder-Guidance
- `tailwind/R01` — Utility-first; wiederkehrende Klassen-Cluster in Komponenten/`@apply` extrahieren.
- `tailwind/R02` — **[v4 Update]** Tokens in `@theme { --color-...: ...; }` im CSS definieren (v4: CSS-first config); `tailwind.config.js` wird in v4 **nicht mehr automatisch erkannt** — nur noch via explizitem `@config`-Directive nutzbar oder vollständig durch CSS-Konfiguration ersetzen. Keine Arbitrary-Values (`[...]`), wo ein Token existiert. — Quelle: [Tailwind v4 Upgrade Guide](https://tailwindcss.com/docs/upgrade-guide) · [v4 Blog](https://tailwindcss.com/blog/tailwindcss-v4) · stabil seit 22. Jan 2025
- `tailwind/R03` — **(v4 Deprecations)** Die `*-opacity-*`-Utilities (`bg-opacity-*`, `text-opacity-*`, `border-opacity-*`, `ring-opacity-*`, `divide-opacity-*`, `placeholder-opacity-*`) sind in v4 entfernt — Slash-Opacity-Syntax verwenden: `bg-black/50`, `text-white/75`. `flex-shrink-*`, `flex-grow-*` und `overflow-ellipsis` sind in v4 als rückwärtskompatible Aliases erhalten (beta.1 PR #15069), aber deprecated — in neuem Code `shrink-*`/`grow-*`/`text-ellipsis` verwenden; das Upgrade-Tool migriert automatisch. — Quelle: [Tailwind v4 Upgrade Guide — Removed Utilities](https://tailwindcss.com/docs/upgrade-guide) · [CHANGELOG beta.1 PR #15069](https://github.com/tailwindlabs/tailwindcss/pull/15069)
- `tailwind/R04` — **(v4 Breaking Change)** Mehrere Utility-Klassen wurden in v4 umbenannt/verschoben; direkte Ersetzungen: `shadow` → `shadow-sm`, `shadow-sm` → `shadow-xs`; `outline-none` → `outline-hidden`; `ring` → `ring-3`; `blur` → `blur-sm`, `blur-sm` → `blur-xs`; `rounded` → `rounded-sm`, `rounded-sm` → `rounded-xs`; `bg-gradient-*` → `bg-linear-*`. Der `!important`-Modifier: v4 empfiehlt Suffix-Syntax (`flex!`), Präfix-Syntax (`!flex`) ist weiterhin gültig aber deprecated — das Upgrade-Tool migriert auf Suffix. — Quelle: [Tailwind v4 Upgrade Guide — Renamed Utilities & Important Modifier](https://tailwindcss.com/docs/upgrade-guide)

## Reviewer-Checklist
- Arbitrary-Values statt Token (`w-[317px]`) → **Important** (Token-Disziplin).
- Lange, duplizierte Klassen-Strings ohne Extraktion → **Suggestion**.
- Kontrast/A11y wie im `css`-Pack → **Critical/Important**.
- `bg-opacity-*` / `text-opacity-*` / `*-opacity-*` im v4-Projekt → **Critical** (Klassen wurden entfernt; Slash-Syntax verwenden).
- `flex-grow-*` / `flex-shrink-*` / `overflow-ellipsis` im v4-Projekt → **Important** (deprecated Aliases, funktionieren noch; auf `grow-*`/`shrink-*`/`text-ellipsis` migrieren).
- `tailwind.config.js` ohne `@config`-Directive in v4-Projekt → **Important** (wird stillschweigend ignoriert).
- `outline-none`, `ring`, `shadow`, `blur`, `rounded` ohne Suffix in v4-Projekt → **Important** (Semantik hat sich verschoben; gegen Upgrade Guide prüfen).

## Test-Approach
- Build (Purge/JIT) ok, keine fehlenden Klassen; visueller Smoke.
- Bei v3→v4-Migration: automatisches Upgrade-Tool (`npx @tailwindcss/upgrade`) ausführen und Output auf umbenannte/entfernte Klassen prüfen.
