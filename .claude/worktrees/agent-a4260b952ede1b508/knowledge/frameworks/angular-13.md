---
pack: frameworks/angular-13
pack_version: 1.0
framework_version_range: ">=13.0, <14.0"
pack_date: 2026-05-31
eol: "LTS endete ~Q4 2022 (verify gegen angular.io/guide/releases)"
superseded_by: angular-14
primary_sources:
  - https://angular.io/guide/releases
  - https://angular.io/guide/update-to-version-13
  - https://github.com/angular/angular/releases
  - https://blog.angular.io/
non_sources:
  - dev.to
  - medium.com
  - stackoverflow.com
  - geeksforgeeks.org
---

# Knowledge Pack: angular-13

Angular 13.x (Major-Range `>=13.0, <14.0`). **LTS-EOL erreicht; ausschließlich Maintenance-/Migrations-Modus.** Geladen bei `profile.frameworks` enthält `angular@13`. Regel-IDs: `angular-13/A<NN>` (Sektion A, train) · `angular-13/B<NN>` (Sektion B, retro) · `angular-13/C<NN>` (Sektion C, Floor).

> **⚠️ EOL-Hinweis:** Angular 13 hat das Ende seines LTS-Supports erreicht (verify gegen `angular.io/guide/releases` für das aktuelle Datum). Aktive Migration auf eine supportete Major-Version ist die wichtigste Empfehlung dieses Packs. Verbleibender Use-Case: Bestandsprojekte, die noch nicht migriert sind — der Reviewer flaggt jeden Drift gegen aktuelle Angular-Patterns explizit als Migrations-Hinweis.

## A. Stable API & Deprecations

> Quellen-getrieben (`train`-Land). Schreibt: `agent-flow:train`. Nicht ändern ohne `/train angular@13`-Lauf.

- `angular-13/A01` — **Ivy ist der einzige Renderer (since 13).** ViewEngine ist in 13 vollständig entfernt — Libraries, die nur ViewEngine-kompatibles `metadata.json` ausliefern, lassen sich nicht mehr konsumieren. Bei Migration aus 12: alle Dependencies prüfen, ob sie Ivy-Distribution liefern. [src: https://blog.angular.io/angular-v13-is-now-available-cce66f7bc296, since: 13.0]
- `angular-13/A02` — **TypeScript 4.4+ Pflicht (since 13).** Frühere TS-Versionen werden vom Angular-Compiler nicht mehr akzeptiert. Bei Migration: `tsconfig.json` `compilerOptions.target` und CI-Toolchain prüfen. [src: https://angular.io/guide/update-to-version-13, since: 13.0]
- `angular-13/A03` — **Node.js Mindestversion: 12.20+ / 14.15+ / 16.10+ (verify gegen angular.io/guide/versions für 13.x).** Frühere Node-Versionen werden vom Angular-CLI nicht mehr unterstützt. CI-Toolchain entsprechend pinnen. [src: https://angular.io/guide/versions, since: 13.0 — verify exact node versions]
- `angular-13/A04` — **IE11-Support entfernt (since 13).** `browserslist`-Konfigurationen, die IE11 listen, müssen bereinigt werden — keine differential-loading-Bundles mehr (eigene polyfill-Strategie nicht mehr nötig). [src: https://blog.angular.io/angular-v13-is-now-available-cce66f7bc296, since: 13.0]
- `angular-13/A05` — **Standalone-Components existieren in 13 NICHT** (eingeführt in 14, stabil in 15). Code in 13 MUSS Components in `NgModule`s deklarieren — `@Component({ standalone: true })` kompiliert in 13 nicht. Migration auf 14+ nötig, um den Module-Boilerplate zu entfernen. [src: https://angular.io/guide/standalone-components — Note: this feature requires Angular 14+, since: not-in-13]

## B. Anti-Patterns aus Einsatz

> Felderfahrung (`retro`-Land). Schreibt: `agent-flow:retro` ab ≥2 Projekten × ≥2 Stellen (siehe `docs/architecture/framework-build-subsystem.md` §9 Schutzgitter). Stand initial: leer — füllt sich, wenn Projekte real damit arbeiten.

_(noch keine Einträge; siehe Schutzgitter in der Spec)_

## C. Konventionen (Floor)

> Stabile Konventionen, manuell gepflegt (User-Approval Pflicht für Edits durch `train`/`retro`). Diese Floor-Regeln sind Angular-Major-übergreifend (gelten auch in 14+/15+/16+).

- `angular-13/C01` — **`OnPush`-ChangeDetection für reine Display-Components.** Default-`ChangeDetectionStrategy.Default` führt bei jedem Browser-Event den Change-Detector über den ganzen Component-Tree laufen lassen — bei größeren Apps merkbarer Performance-Hit. Reine Display-Components (Eingabe = `@Input`, keine interne Mutation) sollten `changeDetection: ChangeDetectionStrategy.OnPush` setzen — der CD läuft dann nur bei Input-Wechsel + Async-Pipe-Emission + manuellen `markForCheck()`-Calls.
- `angular-13/C02` — **`async`-Pipe statt manuelles `.subscribe()`.** `obs$ | async` im Template handhabt Subscription + Unsubscription automatisch (auf Component-Destroy). Manuelles `subscribe()` in Component-Klasse ohne `takeUntil(this.destroy$)` oder `takeUntilDestroyed()` (since 16) → Memory-Leak garantiert. Wenn `.subscribe()` zwingend (z.B. Side-Effect), `takeUntil`-Pattern Pflicht.
- `angular-13/C03` — **Feature-Modules per Lazy-Loading.** Top-Level `AppModule` mit allen Routes/Components vollgepackt → Initial-Bundle wird groß, Time-to-Interactive leidet. Stattdessen Feature-Modules in eigene Files, im Router via `loadChildren: () => import('./feature/feature.module').then(m => m.FeatureModule)` lazy-laden.
- `angular-13/C04` — **EOL-Bewusstsein: jeder Neu-Code in 13.x braucht eine Migrations-Begründung.** Angular 13 ist LTS-EOL — neuer Code sollte nicht in 13 entstehen, außer es gibt einen dokumentierten Migrations-Block. Reviewer-Flag bei Neu-Code ohne Migrations-Kommentar = Important.

## Coder-Guidance

- Lies das Pack-Frontmatter (`framework_version_range` + `eol`) — Angular 13 ist LTS-EOL; neuer Code braucht eine Migrations-Begründung (C04).
- KEINE Standalone-Components verwenden (A05 — kompiliert in 13 nicht); alles in `NgModule`s deklarieren.
- TypeScript-Toolchain auf 4.4+ pinnen (A02).
- Node-Toolchain entsprechend Pack-A03 in CI verankern.
- Bei DI: Dependencies via Constructor (Angular-Standard, kein zusätzliches Pattern nötig — keine Field-Injection wie in Java).
- Bei reactive Code: `async`-Pipe im Template bevorzugen; `subscribe()` nur mit `takeUntil(destroy$)`.

## Reviewer-Checklist

- `@Component({ standalone: true })` in 13er-Code → **Critical** (A05 — kompiliert nicht, gehört zu 14+).
- `tsconfig.json` mit `compilerOptions.target` < `es2017` ODER TypeScript-Version < 4.4 → **Important** (A02).
- `browserslist` listet IE11 → **Important** (A04 — keine Wirkung mehr, irreführend).
- Manuelles `.subscribe()` ohne `takeUntil`/Component-OnDestroy-Cleanup → **Important** (C02, Memory-Leak).
- `ChangeDetectionStrategy.Default` bei reiner Display-Component (nur `@Input`, kein interner State) → **Suggestion** (C01, Performance).
- `loadChildren`-Strings in Router-Konfig (alt-Pattern vor 8) statt Lambda-Import-Syntax → **Important** (Modernisierungs-Pflicht in 13).
- Neu-Code in 13.x-Projekt ohne Migrations-Begründungs-Kommentar → **Important** (C04, EOL-Bewusstsein).
- **Migrations-Empfehlung im Review-Output:** bei jedem PR den Hinweis „Angular 13 ist LTS-EOL; Migration auf supportete Major-Version prüfen" als **Suggestion**.

## Test-Approach

- Build via npm/pnpm (siehe `knowledge/build/<build>.md` Test-Approach — `ng build` oder `ng test` werden im Hintergrund vom Build-Tool ausgeführt).
- Unit-Tests mit Karma + Jasmine (Default-Setup in `angular-cli`-generierten Projekten). Bei Migrationsplanung: Jest ist Alternative ab 14+ (`@angular-builders/jest`).
- Component-Tests via `TestBed`-Pattern (`compileComponents()` + `fixture.detectChanges()`).
- E2E-Tests: Protractor ist deprecated und entfernt (in 13 noch tolerierbar mit `@angular-devkit/build-angular` Legacy-Builder, aber Migration auf Cypress/Playwright empfohlen).
- **Bundle-Size-Smoke (EOL-Test):** CI sollte das `dist/`-Bundle nach Build messen — wachsende Bundle-Size bei stehendem Feature-Set ist Migrations-Indikator (Tree-Shaking-Schwächen in älterem Angular-Compiler).
