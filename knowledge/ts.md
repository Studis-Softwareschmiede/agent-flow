# Knowledge Pack: ts

Expertise für TypeScript. Geladen bei `profile.language: ts`. Regel-IDs: `ts/R<NN>`.

> **Hinweis Multi-Lang (PR-K):** in Mono-Repos mit `language: [java, ts]` (oder ähnlich) lädt der Reviewer diesen Pack via Per-File-Dispatch für `*.ts`/`*.tsx`-Dateien — Floor-Pack (`security.md`) gilt dateiunabhängig. Siehe `docs/architecture/framework-build-subsystem.md` §3.

## Coder-Guidance
- `ts/R01` — **`strict: true` in `tsconfig.json` Pflicht.** Aktiviert alle strict-Flags (`strictNullChecks`, `noImplicitAny`, `strictFunctionTypes`, `alwaysStrict` …). Ohne strict ist TypeScript faktisch nur ein Linter; bei Migration aus Legacy-Code: schrittweise via einzelne strict-Flags, aber Ziel = Voll-strict. Quelle: [TS Handbook — strict](https://www.typescriptlang.org/tsconfig/#strict)
- `ts/R02` — **Kein `any`.** `any` deaktiviert Type-Checking — bei externen/unbekannten Inputs `unknown` + Type-Guards (`typeof`, `instanceof`, Discriminator-Check) verwenden. Wenn `any` zwingend (z.B. JSON.parse-Output kurzzeitig), explizit kommentieren (`// any: external input, validated below`). Quelle: [TS Handbook — any vs unknown](https://www.typescriptlang.org/docs/handbook/2/everyday-types.html#unknown)
- `ts/R03` — **Immutability via `readonly` + `as const`.** Pflicht-Properties als `readonly` deklarieren (Compile-Time-Garantie), Literal-Arrays/-Objekte mit `as const` einfrieren (Tuple-Inferenz + readonly). Verhindert versehentliche Mutation, hilft dem Compiler bei Type-Narrowing. Quelle: [TS Handbook — const assertions](https://www.typescriptlang.org/docs/handbook/release-notes/typescript-3-4.html#const-assertions)
- `ts/R04` — **Discriminated Unions statt Magic-String-Discriminators.** State/Result/Event als Union mit einem `kind`/`type`-Discriminator modellieren — der Compiler narrowt dann pro Case (exhaustive-check via `never`-Default). Kein `if (status === 'loading') { ... } else if (status === 'success') { ... }` mit lose verteilten String-Literalen. Quelle: [TS Handbook — Discriminated Unions](https://www.typescriptlang.org/docs/handbook/2/narrowing.html#discriminated-unions)
- `ts/R05` — **`import type` für Type-only Imports.** Reine Typen via `import type { Foo } from './foo'` importieren — der Import wird beim Compile entfernt, kein Runtime-Side-Effect, besseres Tree-Shaking. `verbatimModuleSyntax: true` in `tsconfig.json` erzwingt das. Quelle: [TS Handbook — Type-Only Imports](https://www.typescriptlang.org/docs/handbook/release-notes/typescript-3-8.html#type-only-imports-and-export)
- `ts/R06` — **Pfad-Aliase via `tsconfig.paths` statt tiefer Relativ-Imports.** `import { x } from '@/lib/foo'` schlägt `import { x } from '../../../lib/foo'` (refactor-stabil, lesbar). Bundler-Konfig muss die Aliase ebenfalls auflösen (vite/webpack/jest/vitest haben das eingebaut, Native-Node braucht `tsconfig-paths` oder Build-Resolve).
- `ts/R07` — **Framework-/Build-Pack laden:** ist `profile.frameworks` oder `profile.build` gesetzt, lade zusätzlich die entsprechenden Packs aus `knowledge/frameworks/` und `knowledge/build/` (siehe `docs/architecture/framework-build-subsystem.md` §3). Framework-spezifische Regeln (Angular/React/Vue) stehen NICHT in diesem TS-Pack, sondern in `frameworks/<id>-<major>.md`.

## Reviewer-Checklist
- `tsconfig.json` ohne `strict: true` (oder ohne alle strict-Flags einzeln) → **Important** (R01).
- `any`-Type im Code ohne Begründungs-Kommentar → **Important** (R02).
- `// @ts-ignore` / `// @ts-expect-error` ohne Begründungs-Kommentar → **Important** (Suppression ohne Audit-Trail).
- Secrets/API-Keys inline statt aus Env → **Critical**.
- String-Interpolation in DB-Queries (siehe `sql`-Packs) → **Critical**.
- Magic-String-Discriminator statt Discriminated Union (mehrere `if`-Vergleiche gegen Literal-Strings) → **Suggestion** (R04).
- Regulärer `import { Foo }` für rein-typische Verwendung (`Foo` taucht nur in Type-Positions auf) → **Suggestion** (R05).
- Tiefe Relativ-Imports (`../../../`) → **Suggestion** (R06, Refactor-Brüchigkeit).
- Unbehandelte Promise-Rejection / fehlender `await` bei async-Funktion → **Important** (TypeScript flaggt das mit `noUncheckedSideEffectImports`/`noImplicitReturns` nicht direkt — Reviewer-Auge nötig).

## Test-Approach
- **Type-Check Pflicht:** `tsc --noEmit` muss grün — kein TS-Code geht durch, wenn der Compiler rot ist.
- **Unit-Tests:** Framework-/Build-Tool-spezifisch — `vitest` (Vite-Projekte), `jest` (Bestand-Setups), `node --test` (Pure-Node ab Node 20). Siehe `knowledge/build/<build>.md` Test-Approach und ggf. Framework-Pack.
- **Lint:** ESLint mit `@typescript-eslint/recommended` als Floor; `eslint-plugin-import` für Import-Ordnung; ggf. Prettier für Formatting (out-of-scope dieses Packs).
