# Knowledge Pack: angular

Expertise für Angular. Geladen bei `profile.language: angular`. Regel-IDs: `angular/R<NN>`.

## Coder-Guidance
- `angular/R01` — Subscriptions teardownen (`takeUntilDestroyed` / `async`-Pipe), kein manuelles `subscribe` ohne Cleanup.
- `angular/R02` — Moderne Patterns: Standalone Components + Signals; `OnPush`-Change-Detection wo möglich.
- `angular/R03` — Typed Forms / strikte Typisierung, kein `any`.

## Reviewer-Checklist
- Manuelles `subscribe` ohne Teardown → **Important** (Memory-Leak).
- `any`-Typen / abgeschaltete Strictness → **Important**.
- Logik in Templates statt in Component/Service → **Suggestion**.
- Hartkodierte URLs/Secrets → **Critical**.

## Test-Approach
- `ng build`; `ng test` (oder Smoke); Lint sauber.
