# Knowledge Pack: angular

Expertise für Angular. Geladen bei `profile.language: angular`. Regel-IDs: `angular/R<NN>`.

## Coder-Guidance
- `angular/R01` — Subscriptions teardownen (`takeUntilDestroyed` / `async`-Pipe), kein manuelles `subscribe` ohne Cleanup.
- `angular/R02` — Moderne Patterns: Standalone Components + Signals; `OnPush`-Change-Detection wo möglich.
- `angular/R03` — Typed Forms / strikte Typisierung, kein `any`.
- `angular/R04` — Structural Directives `*ngIf`, `*ngFor`, `*ngSwitch` seit Angular v20 (2025-05-28) **deprecated** — stattdessen Built-in Control Flow `@if`, `@for`, `@switch` verwenden (stabil seit v17, schneller, besseres Type-Checking, keine Micro-Imports nötig); Entfernung frühestens v22. Migration: `ng update` bietet automatische Schritt an. Quellen: [Angular v20 Blog](https://blog.angular.dev/announcing-angular-v20-b5c9c06cf301) · [angular/angular Deprecation PR](https://github.com/angular/angular/issues/62147)
- `angular/R05` — Alle Kern-Signal-Primitives seit Angular v20 **stabil**: `signal`, `computed`, `effect`, `linkedSignal`, `toSignal`, `toObservable`, `afterRenderEffect`, `afterEveryRender` (ehemals `afterRender`), `PendingTasks`; signal-based Inputs (`input()`) und View-Queries (`viewChild()`, `contentChild()`) ebenfalls stabil — kein `@Input()`/`@ViewChild()` für neuen Code mehr nötig. Quellen: [Angular v20 Blog](https://blog.angular.dev/announcing-angular-v20-b5c9c06cf301) · [Signals Guide angular.dev](https://angular.dev/guide/signals)
- `angular/R06` — Zoneless Change Detection seit Angular v20 in **Developer Preview** (`provideExperimentalZonelessChangeDetection` → `provideZonelessChangeDetection`); CLI-Flag `--zoneless`; Zone.js-Polyfill aus `angular.json` entfernen. Vorteil: bessere Core Web Vitals, native async/await, kleinere Bundle-Größe. Für neue Apps bereits empfohlen. Quelle: [Zoneless Guide angular.dev](https://angular.dev/guide/zoneless) · [Angular v20 Blog](https://blog.angular.dev/announcing-angular-v20-b5c9c06cf301)

## Reviewer-Checklist
- Manuelles `subscribe` ohne Teardown → **Important** (Memory-Leak).
- `any`-Typen / abgeschaltete Strictness → **Important**.
- Logik in Templates statt in Component/Service → **Suggestion**.
- Hartkodierte URLs/Secrets → **Critical**.
- `*ngIf`/`*ngFor`/`*ngSwitch` in neuem Code → **Important** (deprecated seit v20, R04).

## Test-Approach
- `ng build`; `ng test` (oder Smoke); Lint sauber.
