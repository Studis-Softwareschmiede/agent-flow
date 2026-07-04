# Knowledge Pack: angular

Expertise für Angular. Geladen bei `profile.language: angular`. Regel-IDs: `angular/R<NN>`.

## Coder-Guidance
- `angular/R01` — Subscriptions teardownen (`takeUntilDestroyed` / `async`-Pipe), kein manuelles `subscribe` ohne Cleanup.
- `angular/R02` — Moderne Patterns: Standalone Components + Signals; `OnPush`-Change-Detection wo möglich.
- `angular/R03` — Typed Forms / strikte Typisierung, kein `any`.
- `angular/R04` — Structural Directives `*ngIf`, `*ngFor`, `*ngSwitch` seit Angular v20 (2025-05-28) **deprecated** — stattdessen Built-in Control Flow `@if`, `@for`, `@switch` verwenden (stabil seit v17, schneller, besseres Type-Checking, keine Micro-Imports nötig); Entfernung frühestens v22. Migration: `ng update` bietet automatische Schritt an. Quellen: [Angular v20 Blog](https://blog.angular.dev/announcing-angular-v20-b5c9c06cf301) · [angular/angular Deprecation PR](https://github.com/angular/angular/issues/62147)
- `angular/R05` — Alle Kern-Signal-Primitives seit Angular v20 **stabil**: `signal`, `computed`, `effect`, `linkedSignal`, `toSignal`, `toObservable`, `afterRenderEffect`, `afterEveryRender` (ehemals `afterRender`), `PendingTasks`; signal-based Inputs (`input()`) und View-Queries (`viewChild()`, `contentChild()`) ebenfalls stabil — kein `@Input()`/`@ViewChild()` für neuen Code mehr nötig. Quellen: [Angular v20 Blog](https://blog.angular.dev/announcing-angular-v20-b5c9c06cf301) · [Signals Guide angular.dev](https://angular.dev/guide/signals)
- `angular/R06` — Zoneless Change Detection **stabil seit v20.2** (`provideExperimentalZonelessChangeDetection` in v20 umbenannt zu `provideZonelessChangeDetection`, GA in v20.2); CLI-Flag `--zoneless`; Zone.js-Polyfill aus `angular.json` entfernen. Vorteil: bessere Core Web Vitals, native async/await, kleinere Bundle-Größe. Ab v21 ist Zoneless der Default. Quellen: [provideZonelessChangeDetection API (angular.dev)](https://angular.dev/api/core/provideZonelessChangeDetection) · [Zoneless Guide angular.dev](https://angular.dev/guide/zoneless) · [Angular v20 Blog](https://blog.angular.dev/announcing-angular-v20-b5c9c06cf301)
- `angular/R07` — `resource()` und `httpResource()` **stabil seit v22.0** (`@angular/core` bzw. `@angular/common/http`): Signal-basiertes reaktives Datenfetch-Primitive — ersetzt manuelles `HttpClient.get()` + `subscribe`-Ketten für Read-Operationen. `resource()` nimmt einen reaktiven `request`-Parameter (Signal) + asynchronen `loader`, gibt `ResourceRef<T>` mit `.value()`, `.status()`, `.error()` als Signals zurück; bricht laufende Loads via `AbortSignal` ab bei neuer Request. `httpResource()` ist der HTTP-spezialisierte Wrapper (nutzt HttpClient, unterstützt Interceptors, parst JSON by default; `.text()` / `.blob()` für andere Formate); NUR für Lese-Operationen (GET) — keine Mutationen (automatisches Abbrechen würde Mutations unterbrechen). Quellen: [resource() API (angular.dev)](https://angular.dev/api/core/resource) · [httpResource() API (angular.dev)](https://angular.dev/api/common/http/httpResource) · [Async reactivity with resources Guide](https://angular.dev/guide/signals/resource)
- `angular/R08` — Incremental Hydration **stabil seit v20** (via `withIncrementalHydration()`); seit v22.0 ist Incremental Hydration in `provideClientHydration()` **standardmässig aktiv** — `withIncrementalHydration()` ist seit v22 **deprecated** (Entfernung in v24 geplant). In neuem Code `provideClientHydration()` ohne `withIncrementalHydration()` verwenden; `@defer`-Blöcke mit `hydrate on`-Triggern (`viewport`, `idle`, `interaction`, `hover`, `immediate`, `timer`) ermöglichen granulare Hydration nur bei Bedarf → kleinere Initial-Bundle, bessere Core Web Vitals. Quellen: [withIncrementalHydration API (angular.dev)](https://angular.dev/api/platform-browser/withIncrementalHydration) · [Incremental Hydration Guide (angular.dev)](https://angular.dev/guide/incremental-hydration)
- `angular/R09` — Signal Forms (`@angular/forms/signals`) **stabil seit v22.0**: neues, Signal-natives Forms-API als Nachfolger von Reactive Forms und Template-Driven Forms. Alle Feld-/Status-/Fehler-Werte sind Signals; Integration über `Field`-Direktive + `FormValueControl`-Contract; kein separates `FormGroup`/`FormControl`-Instanziieren mehr nötig. R03 (Typed Forms) bleibt für bestehende Reactive-Forms-Code gültig — Signal Forms für neuen Code bevorzugen sobald v22+ Ziel. Quellen: [FormValueControl API (angular.dev)](https://angular.dev/api/forms/signals/FormValueControl) · [FormCheckboxControl API (angular.dev)](https://angular.dev/api/forms/signals/FormCheckboxControl)

## Reviewer-Checklist
- Manuelles `subscribe` ohne Teardown → **Important** (Memory-Leak).
- `any`-Typen / abgeschaltete Strictness → **Important**.
- Logik in Templates statt in Component/Service → **Suggestion**.
- Hartkodierte URLs/Secrets → **Critical**.
- `*ngIf`/`*ngFor`/`*ngSwitch` in neuem Code → **Important** (deprecated seit v20, R04).

## Test-Approach
- `ng build`; `ng test` (oder Smoke); Lint sauber.

## Spec-Tagging
Trace-Tag je gedecktem Kriterium gemäss `docs/architecture/traceability-subsystem.md`.
- **Idiom (Jasmine/Jest — Unit + Integration):** kanonisches Token im `it()`-Titel: `it('@trace user-login#AC1 — rejects empty password', () => { … })`. Hinweis: `fit`/`fdescribe` sind Jasmine-Fokus-Mechanismen und dienen NICHT als Trace-Mechanismus — nicht für Tags verwenden.
- **Idiom (Playwright/Cypress — e2e):** Token im Test-Titel analog js-Pack: `test('@trace user-login#AC1 — Login-Flow durchläuft', …)`.
- **Extraktions-Rezept:** `grep -RoE` über `*.spec.ts`/`*.e2e.ts`, dann Core-Regex `@trace\s+([a-z0-9][a-z0-9-]*)#((?:AC\d+|BR-\d+)(?:,(?:AC\d+|BR-\d+))*)`.
- **Fallback:** kanonisches Token in der Test-Description; Core-Regex.
