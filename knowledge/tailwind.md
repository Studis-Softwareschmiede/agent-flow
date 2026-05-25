# Knowledge Pack: tailwind

Expertise für Tailwind CSS. Domäne bei UI-Projekten mit Tailwind. Regel-IDs: `tailwind/R<NN>`.

## Coder-Guidance
- `tailwind/R01` — Utility-first; wiederkehrende Klassen-Cluster in Komponenten/`@apply` extrahieren.
- `tailwind/R02` — Tokens in `tailwind.config` definieren; keine Arbitrary-Values (`[...]`), wo ein Token existiert.

## Reviewer-Checklist
- Arbitrary-Values statt Token (`w-[317px]`) → **Important** (Token-Disziplin).
- Lange, duplizierte Klassen-Strings ohne Extraktion → **Suggestion**.
- Kontrast/A11y wie im `css`-Pack → **Critical/Important**.

## Test-Approach
- Build (Purge/JIT) ok, keine fehlenden Klassen; visueller Smoke.
