---
pack: frameworks/angular-21
pack_version: 1.1
framework_version_range: ">=21.0, <22.0"
pack_date: 2026-06-02
eol: "v21 aktiv bis ~2026-05-19, danach LTS (verify gegen angular.dev/reference/releases)"
requires:                         # Solver-Constraints (upgrade-subsystem §12); Quelle: A01/A02
  node: "^20.19.0 || ^22.12.0 || ^24.0.0"
  typescript: ">=5.9 <6.0"
primary_sources:
  - https://angular.dev/reference/releases
  - https://angular.dev/reference/versions
  - https://angular.dev/update-guide
  - https://angular.dev/reference/migrations
  - https://angular.dev/guide/testing
  - https://angular.dev/guide/testing/karma
  - https://angular.dev/roadmap
  - https://github.com/angular/angular/releases
  - https://github.com/angular/angular-cli/releases
  - https://blog.angular.dev/
non_sources:
  - dev.to
  - medium.com
  - stackoverflow.com
  - geeksforgeeks.org
---

# Knowledge Pack: angular-21

Angular 21.x (Major-Range `>=21.0, <22.0`). Aktuelle, supportete Major (Release 2025-11-20). Geladen bei `profile.frameworks` enthält `angular@21`. Regel-IDs: `angular-21/A<NN>` (Sektion A, train) · `angular-21/B<NN>` (Sektion B, retro) · `angular-21/C<NN>` (Sektion C, Floor).

> **Migrations-Kontext:** Dieser Pack ist das Ziel der Migration weg von `angular-13` (siehe `angular-13.md`, dort `superseded_by`). Der Sprung 13 → 21 läuft über je eine Major-Stufe via `ng update` (autoritative Schritt-Reihenfolge: `angular.dev/update-guide`, von/auf exakt einstellen) — niemals Majors überspringen. Sektion A unten beschreibt den **Ziel-Zustand 21**; die Modernisierungs-Schematics (A07) heben 13er-Patterns automatisiert auf 21er-Idiom.

## A. Stable API & Deprecations

> Quellen-getrieben (`train`-Land). Schreibt: `agent-flow:train`. Nicht ändern ohne `/train angular@21`-Lauf.

- `angular-21/A01` — **TypeScript 5.9+ Pflicht (since 21).** TS < 5.9 wird vom Angular-Compiler nicht mehr akzeptiert (`>=5.9.0 <6.0.0`). TS 5.9 verschärft Inference/Type-Checking — Generics, Conditional Types und komplexe Inference-Ketten sind die häufigsten Quellen neuer Fehler bei der Migration. [src: https://angular.dev/reference/versions, since: 21.0]
- `angular-21/A02` — **Node.js `^20.19.0 || ^22.12.0 || ^24.0.0` (since 21).** Ältere Node-Versionen lassen das Angular-CLI gar nicht erst starten (`ng serve`/`ng build` brechen vor Ausführung ab). RxJS-Range: `^6.5.3 || ^7.4.0`. CI-Toolchain entsprechend pinnen. [src: https://angular.dev/reference/versions, since: 21.0]
- `angular-21/A03` — **Zoneless als Default; kein ZoneJS-Change-Detection-Scheduler mehr by default (since 21).** Angular liefert per Default keinen ZoneJS-basierten CD-Scheduler — wer zone.js-basierte Change Detection behalten will, MUSS `provideZoneChangeDetection()` explizit in die Bootstrap-Provider aufnehmen. Die Config-Option `ignoreChangesOutsideZone` ist vollständig entfernt. Server-Bootstrap braucht jetzt `BootstrapContext`, das an `bootstrapApplication` übergeben wird. [src: https://github.com/angular/angular/releases/tag/21.0.0, since: 21.0]
- `angular-21/A04` — **Entfernte APIs in 21 (Breaking).** `moduleId` aus Component-Metadata entfernt · Custom-`interpolation`-Konfiguration entfernt (Default-`{{ }}`-Syntax ist die einzige Option) · `UpgradeAdapter` entfernt (Migrationspfad: `upgrade/static`) · `ApplicationConfig`-Export aus `@angular/platform-browser` entfernt. [src: https://github.com/angular/angular/releases/tag/21.0.0, since: 21.0]
- `angular-21/A05` — **Host-Binding-Type-Checking standardmäßig aktiv (since 21).** Bisher verborgene Typfehler in Host-Bindings können beim Build neu auftauchen. Zudem: Signal-Inputs in Custom Elements werden jetzt direkt (nicht als Function-Call) gelesen — analog Decorator-Input-Verhalten. [src: https://github.com/angular/angular/releases/tag/21.0.0, since: 21.0]
- `angular-21/A06` — **Plattform-Support reduziert (since 21).** IE und nicht-Chromium-Edge sind nicht mehr unterstützt. `browserslist`-Konfigurationen entsprechend bereinigen. `HttpResponseBase.statusText` ist deprecated (Entfernung in künftiger Version vorgemerkt). [src: https://github.com/angular/angular/releases/tag/21.0.0, since: 21.0]
- `angular-21/A07` — **Automatisierte Modernisierungs-Migrationen verfügbar (`ng generate @angular/core:<name>`).** Für den 13→21-Sprung relevant: `control-flow` (`*ngIf/*ngFor/*ngSwitch` → `@if/@for/@switch`), `standalone` (NgModule-Components → Standalone), `inject` (Constructor-DI → `inject()`), `signal-inputs`/`outputs`/`signal-queries` (Decorator → Signal-APIs), `cleanup-unused-imports`, `self-closing-tags`, `ngclass-to-class`/`ngstyle-to-style`, `commonmodule-to-standalone-imports`, Lazy-Loaded-Routes. Diese Schematics sind der bevorzugte Weg, alten Code aufs 21er-Idiom zu heben — nicht von Hand umschreiben. [src: https://angular.dev/reference/migrations, since: 21.0]
- `angular-21/A08` — **Vitest ist der stabile Default-Test-Runner für neue Projekte (since 21); Karma bleibt offiziell unterstützt.** Laut `angular.dev/guide/testing`: „This guide covers the default testing setup for new Angular CLI projects, which uses Vitest." Laut `angular.dev/guide/testing/karma`: „While Vitest is the default test runner for new Angular projects, Karma is still a supported and widely used test runner." — Karma ist damit **nicht deprecated**. Die Angular-Roadmap (post-v21) nennt als nächsten Schritt: Karma-zu-Vitest-Migrations-Tool auf stable zu heben. Jest: CLI v21.0.0 erweiterte Jest-Kompatibilität auf v30 (kein Deprecation-Signal). WTR-Status nicht per Primärquelle verifizierbar (keine Erwähnung in `angular.dev`- oder CLI-21-Release-Notes). Empfehlung: Vitest für Neu-Projekte; Karma-Migrationen über offizielles Migrations-Tool. [src: https://angular.dev/guide/testing · https://angular.dev/guide/testing/karma · https://angular.dev/roadmap · https://github.com/angular/angular-cli/releases/tag/21.0.0, since: 21.0]

## B. Anti-Patterns aus Einsatz

> Felderfahrung (`retro`-Land). Schreibt: `agent-flow:retro` ab ≥2 Projekten × ≥2 Stellen (siehe `docs/architecture/framework-build-subsystem.md` §9 Schutzgitter). Stand initial: leer — füllt sich, wenn Projekte real damit arbeiten.

_(noch keine Einträge; siehe Schutzgitter in der Spec)_

## C. Konventionen (Floor)

> Stabile Konventionen, manuell gepflegt (User-Approval Pflicht für Edits durch `train`/`retro`). Diese Floor-Regeln sind Angular-Major-übergreifend stabil.

- `angular-21/C01` — **Standalone-first; keine neuen NgModules.** Standalone-Components/-Directives/-Pipes sind das Default-Idiom. Neuer Code deklariert Abhängigkeiten direkt über `imports: [...]` am Component — kein `@NgModule`-Boilerplate. Bootstrap via `bootstrapApplication(AppComponent, appConfig)`.
- `angular-21/C02` — **Built-in Control Flow im Template.** `@if`/`@for`/`@switch` statt `*ngIf`/`*ngFor`/`*ngSwitch`. Bei `@for` ist `track` Pflicht (Identitäts-Tracking für stabiles DOM-Diffing).
- `angular-21/C03` — **`inject()` statt Constructor-DI** in neuem Code — genauere Typen, bessere Kompatibilität mit Standard-Decorators; erlaubt DI außerhalb des Constructors (z.B. in Functions/Factories).
- `angular-21/C04` — **Signals-first State; `OnPush` für reine Display-Components.** Im (Default-)Zoneless-Betrieb ist signal-basierter State der Default-Weg, Change Detection auszulösen. Reine Display-Components (`@Input`/`input()`, keine interne Mutation) setzen `changeDetection: ChangeDetectionStrategy.OnPush`.
- `angular-21/C05` — **`async`-Pipe oder `takeUntilDestroyed()` statt nacktem `.subscribe()`.** `obs$ | async` im Template handhabt Subscription/Unsubscription automatisch. Wenn `.subscribe()` zwingend (Side-Effect), ist `takeUntilDestroyed()` (since 16) oder `takeUntil(destroy$)` Pflicht — sonst Memory-Leak. Wo möglich `toSignal()` statt manueller Subscription.
- `angular-21/C06` — **Feature-Routes lazy-laden.** Routen via `loadComponent: () => import(...)` / `loadChildren` lazy einbinden, statt alles eager ins Initial-Bundle zu ziehen — Time-to-Interactive.

## Coder-Guidance

- Lies das Pack-Frontmatter (`framework_version_range`) — Ziel ist Angular 21.x.
- **Standalone + Control Flow + `inject()` + Signals** sind das Idiom (C01–C04). Keine NgModules, keine `*ngIf/*ngFor`, keine Constructor-DI in Neu-Code.
- **TypeScript auf 5.9+** und Node-Toolchain gemäß A01/A02 in CI pinnen.
- **Zoneless ist Default (A03):** Nicht implizit auf `NgZone`/zone.js-Verhalten verlassen. Nur wenn ein Legacy-Pfad zone-basierte CD braucht, explizit `provideZoneChangeDetection()` setzen — und im PR begründen.
- Bei Migration aus 13: **erst die `ng update`-Leiter** (je eine Major), **dann** die `@angular/core`-Modernisierungs-Schematics (A07) laufen lassen — nicht von Hand umschreiben.
- Entfernte APIs (A04) und Host-Binding-Type-Checking (A05) sind häufige Build-Brecher beim Upgrade — zuerst dort suchen, wenn der Build nach einem Major-Bump rot ist.
- Tests: Vitest bevorzugen (A08); Karma bleibt unterstützt, Migration über offizielles Tool empfohlen.

## Reviewer-Checklist

- Neues `@NgModule` für Feature-/Component-Organisation in Neu-Code → **Important** (C01 — Standalone-first).
- `*ngIf`/`*ngFor`/`*ngSwitch` in neuen/angefassten Templates → **Important** (C02 — Built-in Control Flow); `@for` ohne `track` → **Important**.
- Constructor-DI in Neu-Code statt `inject()` → **Suggestion** (C03).
- `tsconfig`/`package.json` mit TypeScript < 5.9 → **Critical** (A01 — kompiliert nicht).
- Node-Engine in CI/`package.json` außerhalb `^20.19.0 || ^22.12.0 || ^24.0.0` → **Important** (A02).
- Code/Provider verlassen sich implizit auf zone.js-CD ohne `provideZoneChangeDetection()` → **Critical** (A03 — bricht im Zoneless-Default).
- Nutzung entfernter APIs (`moduleId`, custom `interpolation`, `UpgradeAdapter`, `ApplicationConfig` aus `platform-browser`) → **Critical** (A04).
- Manuelles `.subscribe()` ohne `takeUntilDestroyed()`/`async`-Pipe/Cleanup → **Important** (C05, Memory-Leak).
- `ChangeDetectionStrategy.Default` bei reiner Display-Component → **Suggestion** (C04).
- Eager geladene Feature-Routen statt `loadComponent`/`loadChildren` → **Suggestion** (C06).
- Neue Tests gegen Karma/WTR/Jest statt Vitest → **Suggestion** (A08 — Vitest ist Default; Karma weiterhin offiziell unterstützt; für neue Projekte Vitest bevorzugen).

## Test-Approach

- Build via npm/pnpm (siehe `knowledge/build/<build>.md` Test-Approach — `ng build`/`ng test` laufen im Hintergrund über das Build-Tool).
- **Unit-Tests mit Vitest** (stabiler Default-Runner since 21, A08). Karma bleibt offiziell unterstützt; Migration zu Vitest über das offizielle Tool (`angular.dev/guide/testing/migrating-to-vitest`) empfohlen.
- Component-Tests via `TestBed`-Pattern (`fixture.detectChanges()`); im Zoneless-Default ggf. explizites `await fixture.whenStable()` statt impliziter zone-getriebener Stabilisierung.
- E2E: Cypress/Playwright (Protractor ist seit Jahren entfernt).
- **Upgrade-Smoke (13→21):** Nach jeder `ng update`-Stufe Build + Tests grün; Bundle-Size nach Erreichen von 21 vs. 13-Baseline vergleichen (Zoneless + neuer Builder sollten kleinere Bundles + bessere Core Web Vitals liefern).
