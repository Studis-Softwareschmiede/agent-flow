---
name: new-project
description: Bootstrappt ein Projekt der Softwareschmiede — legt Repo + board/-Skelett (File-Board) an, erkennt/erfragt den Stack + DB-Dialekt + optionale Companions (Cache/Queue/Sessions) + Build-Tool + optionale Frameworks, scaffoldet .claude/ (profile, CLAUDE.md, lessons, memory) + Dockerfile + CI + optionales DB-Compose-Fragment + optionale Companion-Fragmente + das Playwright-Regressions-Grundgerüst (tests/regression/, Config, .gitignore, Dev-Dependency) aus ${CLAUDE_PLUGIN_ROOT}/templates/. /init adoptiert ein bestehendes Repo. Schreibt KEINEN App-Code.
---

# /new-project <name> [--lang <x>] [--db <dialect>] [--companions <list>] [--build <build>] [--framework <id>@<major>]… [--migration-tool <tool>]   ·   /init

Bootstrap, damit die Fabrik an einem Projekt arbeiten kann. cwd = Workspace (`new-project`) bzw. das bestehende Repo (`init`).

**Auth ZUERST (sonst scheitert jeder gh-Schritt):** `bash "$CLAUDE_PLUGIN_ROOT/scripts/ensure-gh-auth.sh"` — das mintet den GitHub-App-Token aus `.env.gpg` und loggt `gh` damit ein. **NICHT `gh auth login --web`** (wir nutzen die App, nicht einen interaktiven Login).

## Ablauf
1. **Repo**
   - `new-project`: `gh repo create studis-softwareschmiede/<name> --public` + clone. (Public: Branch-Protection/PR+Gate im Free-Plan möglich; ghcr-Image ohne Pull-Login.)
   - `init`: bestehendes Repo (cwd) nutzen; Remote prüfen.
2. **Stack**
   - `new-project`: aus `--lang` oder genau **1 Frage**.
   - `init`: erkennen — `pubspec.yaml`→flutter · `pom.xml`/`build.gradle`→java · `package.json`→js/angular · `*.html`→html · `*.sql`/`migrations/`→Domäne `sql` — und bestätigen lassen.
2a. **DB-Auswahl** (Spec [`docs/architecture/db-subsystem.md`](../../docs/architecture/db-subsystem.md) §2 + §10) — `profile.db_dialect` festlegen:
   - `new-project` mit `--db <dialect>`: Wert direkt übernehmen.
   - `new-project` ohne `--db`: genau **1 zusätzliche Frage** (AskUserQuestion, 5 Enum-Werte):
     > „DB-System? [postgres|mysql|sqlite|mongodb|none] (none = keine DB)"
   - `init`: Detection wie in `/adopt` Schritt 2a (Heuristik aus Spec §9) — dort dokumentiert; hier nur Verweis, doppelt-pflegen vermeiden.
   - **Erlaubte Werte (Spec §2 Enum):** `postgres | mysql | sqlite | mongodb | none`. **Default** ohne `--db`-Flag und ohne explizite Antwort: `none` (safe minimal state — bewusste Entscheidung später ist besser als Default mit falscher DB).
   - Bei ungültigem Wert: Frage wiederholen (kein Fallback auf `none` „im Stillen").
2b. **Companion-Auswahl** (Spec [`docs/architecture/db-subsystem.md`](../../docs/architecture/db-subsystem.md) §17) — `profile.companions[]` festlegen. Companions = stateful Sidecars **OHNE** Schema-Evolution (Cache/Queue/Sessions/Pub-Sub). Heute verfügbar: `redis`.
   - `new-project` mit `--companions <list>`: kommagetrennte Liste übernehmen (z.B. `--companions redis`; in P1 nur `redis` gültig — unbekannte Namen → Fehler).
   - `new-project` ohne `--companions` + interaktiv: **1 optionale Frage** (AskUserQuestion):
     > „Companions? [<keine>|redis] (Cache/Queue/Sessions; mehrere kommagetrennt)"
     **Default ohne Antwort: keine** (Companions sind opt-in; weniger Moving-Parts beim Bootstrap).
   - `init`: Detection wie in `/adopt` Schritt 2b — dort dokumentiert; hier nur Verweis.
   - **Erlaubte Werte (P1):** `redis` (additive Liste). **Scope-Lock:** Companions belegen **NICHT** den `db_dialect`-Slot — `companions: [redis]` mit `db_dialect: postgres` ist eine valide Kombination.
2c. **Build-Tool-Auswahl** (Spec [`docs/architecture/framework-build-subsystem.md`](../../docs/architecture/framework-build-subsystem.md) §6 + §10) — `profile.build` festlegen (single-value, Pflicht ab Sprachen mit Build-Tool; `none` für Bash/statisch).
   - `new-project` mit `--build <build>`: kanonischer Wert aus `framework-build-subsystem.md §10` (`maven|gradle|npm|pnpm|uv|cargo|none`). Default: aus `--lang` ableiten (java→`maven`, ts→`npm`, py→`uv`, rust→`cargo`); kein Default → `none`.
   - `new-project` ohne `--build` + interaktiv: genau **1 zusätzliche Frage** (AskUserQuestion, single-select):
     > „Build-Tool? [maven|gradle|npm|pnpm|uv|cargo|none]"
     Voreinstellung = der lang-abgeleitete Default oben.
   - `init`: Detection wie in `/adopt` Schritt 2c — dort dokumentiert; hier nur Verweis, doppelt-pflegen vermeiden.
   - **Erlaubte Werte (Spec §10 Build-Tool-Tabelle):** `maven | gradle | npm | pnpm | uv | cargo | none`. Bei ungültigem Wert: Frage wiederholen (kein Silent-Fallback auf `none`).
2d. **Framework-Auswahl** (Spec [`docs/architecture/framework-build-subsystem.md`](../../docs/architecture/framework-build-subsystem.md) §6) — `profile.frameworks[]` festlegen (multi-value, optional, Default `[]`).
   - `new-project` mit `--framework <id>@<major>`: **wiederholbar**. Beispiel: `--framework spring-boot@3 --framework spring-data@3`. Default: keiner (leeres Array).
   - `new-project` ohne `--framework` + interaktiv: **1 optionale Frage** (AskUserQuestion, multi-select aus passender Liste pro Sprache; Skip-Option immer dabei):
     > „Framework(s)? (optional, mehrfach)"
     Vorschlags-Liste pro `lang`:
     - **java/kotlin:** `[spring-boot@3, quarkus@3]`
     - **ts/js:** `[react@18, react@19, vue@3, angular@17]`
     - **py:** `[django@5, fastapi, flask]` — django mit `@5` (Cut bei 4→5 erfolgt); `fastapi`/`flask` ohne `@<major>` (noch nie ein Cut, Spec §5 Major-Optionalität).
     - **rust:** (keine Vorschläge in P1 — Skip oder Freitext)
     **Default ohne Antwort: keine** (Framework-Auswahl ist opt-in; weniger Moving-Parts beim Bootstrap).
   - `init`: Detection wie in `/adopt` Schritt 2c — dort dokumentiert; hier nur Verweis.
   - **Polyglott-Erinnerung:** Mehrere rivalisierende Frameworks für **dieselbe Sprache** (z.B. `spring-boot@3` + `quarkus@3`) sind ein Polyglott-Fall — analog Spec §7. `/new-project` warnt explizit, der User entscheidet (Mono-Repo mit gemischten Stacks ist ungewöhnlich, aber zulässig).
2e. **Migration-Tool-Auswahl** (Spec [`docs/architecture/migration-tool-subsystem.md`](../../docs/architecture/migration-tool-subsystem.md) §2 + §5) — `profile.db_migration_tool` festlegen (single-value, optional; Default ableitbar aus `--lang` + `--db`). **Entfällt komplett bei `db_dialect: none`** (kein DB ⇒ kein Migration-Tool nötig).
   - `new-project` mit `--migration-tool <tool>`: kanonischer Wert aus Spec §2 (`skeleton|flyway@9|flyway@10|liquibase@4|prisma|alembic|knex|typeorm|sequelize|django-migrations|supabase|golang-migrate|sqlx-cli|refinery|sqflite`). Default: aus `--lang` + `--db` via §5 Default-Mapping abgeleitet; explizit `skeleton` wenn `--db none` ODER kein Default greift.
   - `new-project` ohne `--migration-tool` + interaktiv (nur wenn `db_dialect != none`): genau **1 zusätzliche Frage** (AskUserQuestion, single-select):
     > „Migration-Tool? [skeleton|flyway@10|prisma|alembic|...]"
     Voreinstellung = Vorschlag aus Spec §5 Default-Mapping basierend auf `--lang` + `--db` (java+sql→`flyway@10`, py+sql→`alembic`, flutter+sqlite→`sqflite`, flutter+supabase→`supabase`, rust+sql→`sqlx-cli`, go+sql→`golang-migrate`, sonst→`skeleton`). Skip-Option (`skeleton`) ist immer dabei.
   - `init`: Detection wie in `/adopt` Schritt 2f — dort dokumentiert; hier nur Verweis, doppelt-pflegen vermeiden.
   - **Erlaubte Werte (Spec §2 Enum):** siehe oben. Bei ungültigem Wert: Frage wiederholen (kein Silent-Fallback).
   - **Bei `db_dialect: none`:** Frage entfällt komplett — `db_migration_tool` wird nicht gesetzt (Loader interpretiert fehlend = `skeleton`, no-op, weil bei `db_dialect: none` kein Migration-Pfad geladen wird; Spec §5 Sonderfall + §11).
3. **Board-Skelett anlegen** (board-subsystem §8; Spec `docs/specs/new-project-board.md`):
   - Prüfen ob `board/` bereits existiert — falls ja: Meldung „Board existiert bereits" + keine Änderung (idempotent, Spec Edge-Case).
   - Falls kein Init-Verb in der `board`-CLI vorhanden: minimales `board/board.yaml` direkt schreiben (strikt nach [[board-schema]] V1):
     ```yaml
     schema_version: 1
     project_slug: <projektname-kebab-case>   # aus <name> normalisiert: Kleinbuchstaben, Sonderzeichen→Bindestrich
     next_feature_id: 1
     next_story_id: 1
     ```
   - `board/features/.gitkeep` + `board/stories/.gitkeep` anlegen (damit leere Ordner committet werden).
   - Kein `gh project create`, keine Netzwerkabhängigkeit, keine PAT-Anforderung.
4. **`.claude/` scaffolden** (aus `${CLAUDE_PLUGIN_ROOT}/templates/<lang>/`):
   - `profile.md`: `language`, `domains`, `db_dialect: <wert aus Schritt 2a>` (Pflicht, Enum `postgres|mysql|sqlite|mongodb|none`; Spec §2), `companions: [<liste aus Schritt 2b>]` (Liste, default `[]`; Spec §17 — heute nur `redis` gültig), `build: <wert aus Schritt 2c>` (Pflicht ab Sprachen mit Build-Tool, Enum `maven|gradle|npm|pnpm|uv|cargo|none`; Spec framework-build-subsystem §2 + §10), `frameworks: [<liste aus Schritt 2d>]` (Liste, default `[]`, Form `<id>@<major>`; Spec §2), `db_migration_tool: <wert aus Schritt 2e>` (optional, Enum aus migration-tool-subsystem §2 — `skeleton|flyway@9|flyway@10|liquibase@4|prisma|alembic|knex|typeorm|sequelize|django-migrations|supabase|golang-migrate|sqlx-cli|refinery|sqflite`; **bei `db_dialect: none` weggelassen**; Loader interpretiert fehlend = `skeleton`, Spec §11 Backwards-Compat), `test`/`lint`/`smoke`, `merge_policy: pr`, `cost_mode: balanced` (Token-Hebel, Default `balanced`; je Lauf via `/flow --cost …` überschreibbar — Enum `low-cost|balanced|max-quality`, Matrix `knowledge/model-tiers.md`), `board: file`, `deploy: docker`, `image: ghcr.io/studis-softwareschmiede/<name-lowercase>` (Docker/ghcr-Repo-Namen sind IMMER kleingeschrieben — Repo `Foo-Bar` → Image `foo-bar`), `registry: ghcr`, `container_port: <EXPOSE aus dem Template-Dockerfile, z.B. 80|8080>` (für `/preview`; `preview_port` wird erst beim ersten `/preview up` vergeben).
   - **Pack-Vorhandensein-Check** (nach Profile-Schreiben, vor Step 5): für jedes gewählte Framework + Build-Tool prüfen, ob der Pack unter `${CLAUDE_PLUGIN_ROOT}/knowledge/frameworks/<id>-<major>.md` bzw. `${CLAUDE_PLUGIN_ROOT}/knowledge/build/<build>.md` existiert. Fehlt: **⚠ Konsolen-Warnung** ausgeben + **Backlog-Item** anlegen („Pack `<id>` anlegen (via `/train <id>`)"). Kein Hard-Fail — Loader verhält sich graceful (Spec §11 + §12 Graceful-Degradation). **Migration-Pack analog:** wenn `db_migration_tool != skeleton`, prüfen ob `${CLAUDE_PLUGIN_ROOT}/knowledge/migration/<tool>[-<major>].md` existiert. Fehlt: Backlog-Item „Pack `migration/<tool>` anlegen (via `/train migration/<tool>` oder manuelle Spec)" (Spec migration-tool-subsystem §6 + §12 Graceful-Degradation).
   - `CLAUDE.md`: minimaler Kontext (Template + 1–2 Fragen). **Pflicht-Blöcke:** den Abschnitt „Kommunikation mit dem Owner" aus `${CLAUDE_PLUGIN_ROOT}/templates/_shared/owner-communication.md` unverändert übernehmen (Stil-Regel für die Owner-Session: kurz, wenig Jargon, 3-Schichten-Antwort, Steuerwörter `kurz`/`erklär`/`technisch`) sowie den Abschnitt „Parallelbetrieb: mehrere Cloud-Sessions" aus `${CLAUDE_PLUGIN_ROOT}/templates/_shared/parallel-sessions.md` unverändert übernehmen (Pflicht-Worktree-Isolation bei parallelen Sessions im selben Repo). Rest projekt-spezifisch.
   - `lessons/{coder,reviewer,tester}.md`: leer.
   - **`.claude/memory.md` scaffolden (Spec [`docs/specs/project-memory.md`](../../docs/specs/project-memory.md) AC7):** existiert die Datei noch nicht, `templates/_shared/memory.md` (leeres Gerüst — Kopfzeilen-Hinweis + drei Abschnitte) unverändert dorthin kopieren. Existiert sie bereits → **nicht überschreiben** (idempotent, gilt auch bei erneutem `new-project`-Lauf oder beim `/init`-Pfad von `/adopt`, s. dessen Schritt 2).
4b. **`docs/` scaffolden** (Spec-getriebene Doku, CONCEPT §4d — aus `${CLAUDE_PLUGIN_ROOT}/templates/_docs/`, sprach-neutral):
   - **Immer:** `docs/concept.md`, `docs/architecture.md`, `docs/glossary.md`, `docs/specs/_template.md` (Vorlage — bleibt liegen, `requirement` kopiert sie je Feature).
   - **Bedingt:** `docs/data-model.md` nur wenn `profile.db_dialect != none` (Spec §10; ersetzt die alte `domains: [sql]`-Bedingung — `domains` bleibt als reine Knowledge-Pack-Liste, der DB-Layer wird über `db_dialect` gesteuert); `docs/design.md` nur bei UI (`language` ∈ flutter|angular|html oder Domäne `ui`/`accessibility`).
   - `<App>`-Platzhalter durch den Projektnamen ersetzen; sonst leer lassen (füllen `architekt`/`dba`/`designer`/`requirement`). Diese Docs sind die **durable Source of Truth** (`.claude/` hält nur Prozess-State: profile, lessons).
   - **Nur `/init` — „Spec aus Code ableiten" (einmalig, mensch-validiert):** bestehenden Code lesen und `docs/concept.md` + `docs/architecture.md` + je Capability `docs/specs/<feature>.md` als **Entwurf** (`status: draft`) füllen (bei Bedarf `architekt`/`requirement` via Task dispatchen). Die abgeleiteten Docs dem User zur Durchsicht/Korrektur **vorlegen, bevor sie verbindlich werden** — erst nach OK gelten sie als Source of Truth (dann ist die App portierbar + unter Drift-Gate).
4c. **DB-Subsystem scaffolden** (Spec §10) — nur wenn `profile.db_dialect != none`:
   - **Compose-Fragment anhängen:** `cat ${CLAUDE_PLUGIN_ROOT}/templates/_shared/db-<dialect>/compose.fragment.yml >> docker-compose.yml` (Trennzeile davor: `# --- db-<dialect> (source: templates/_shared/db-<dialect>/compose.fragment.yml) ---`). Bei `db_dialect: sqlite` enthält das Fragment **keinen** db-Service, sondern nur den one-shot `migrations`-Service + `db_data`-Volume (Spec §5 SQLite-Sonderfall, §16-R4). Compose-Fragment für den **DB-Service** wird **unabhängig vom Migration-Tool** angehängt (alle Tools brauchen eine laufende DB; migration-tool-subsystem.md §8).
   - **Tool-Gating für `db_scripts/`-Skeleton + Migrations-Runner** (Spec migration-tool-subsystem §8 — strikte Trennlinie):
     - **`db_migration_tool: skeleton`** (Default oder explizit): `db_scripts/`-Skeleton + `run-migrations.sh` werden angelegt (siehe nächster Spiegelstrich — heutiges Verhalten).
     - **`db_migration_tool: flyway@9|flyway@10`**: KEIN `db_scripts/`, KEIN `run-migrations.sh`. Stattdessen Backlog-Item „Flyway-Konfiguration einrichten (`src/main/resources/db/migration/V1__init.sql` + `application.properties` mit `spring.flyway.enabled=true`)" — Initial-Migration kann per `/flow` aus dem Backlog gezogen werden.
     - **`db_migration_tool: prisma`**: KEIN `db_scripts/`. Backlog-Item „Prisma-Setup (`npx prisma init` + Schema in `prisma/schema.prisma`)".
     - **`db_migration_tool: liquibase@4|alembic|knex|typeorm|sequelize|django-migrations|supabase|golang-migrate|sqlx-cli|refinery|sqflite`**: KEIN `db_scripts/`. Backlog-Item „Tool-spezifisches Setup gemäß `knowledge/migration/<tool>.md` einrichten" (Tool-eigene Konvention; siehe Spec §8-Tabelle für die jeweilige Default-Verzeichnis-Konvention).
     - **Migrations-Service-Block im Compose-Fragment** (one-shot, ruft `db_scripts/run-migrations.sh`): **nur bei `skeleton`** sinnvoll. Bei anderen Tools entweder weglassen oder durch tool-spezifischen Block ersetzen (Detail-Pattern in den jeweiligen Migration-Packs PR-Q5+ on-demand).
   - **`db_scripts/`-Skeleton kopieren** (nur bei `db_migration_tool: skeleton`):
     - `db_scripts/000_init_meta.sql` (postgres/mysql/sqlite) bzw. `000_init_meta.js` (mongodb) — legt die Marker-Tabelle/Collection `_schema_migrations` an (Spec §4).
     - `db_scripts/run-migrations.sh` aus `templates/_shared/db-<dialect>/db_scripts/run-migrations.sh` (executable, Spec §6).
   - **`.env.db.example`** aus `templates/_shared/db-<dialect>/.env.db.example` ans Repo-Root (Vorlage für `DB_HOST`/`DB_NAME`/`DB_USER`/`DB_PASSWORD` bzw. dialekt-äquivalente; **keine** echten Werte committen). **Tool-unabhängig** (auch Flyway/Prisma/… brauchen DB-Connection-Vars).
   - **Backup/Restore-Vorlagen NICHT auto-kopieren** (Spec §7 — projekt-spezifisch). Hinweis im README-DB-Abschnitt: „Vorlagen in `templates/_shared/db-<dialect>/scripts/` — bei Bedarf ins Projekt kopieren."
   - **`README.md` um DB-Abschnitt erweitern** (am Ende anhängen): Verweis auf passendes Pack (§3: `postgres`→`knowledge/sql.md`, `mysql`→`sql-mysql.md`, `sqlite`→`sql-sqlite.md`, `mongodb`→`knowledge/mongodb.md`) + bei `db_migration_tool != skeleton` zusätzlich Verweis auf `knowledge/migration/<tool>.md`, Migrations-Workflow (bei `skeleton`: `docker compose up -d db && docker compose up migrations && docker compose up -d app` — bei sqlite ohne `db`-Service; bei anderen Tools: Tool-spezifischer Apply-Befehl gemäß migration-tool-subsystem §9, z.B. `mvn flyway:migrate` / `npx prisma migrate deploy` / `alembic upgrade head`), Backup/Restore-Verweis. Bei sqlite zusätzlich die Skalierungs-Warnung (Single-Writer-Lock, kein Multi-Replica — Spec §16-R2, Pack-Regel `sqlite/R01`).
4d. **Companions scaffolden** (Spec §17) — pro Eintrag in `profile.companions`:
   - **Compose-Fragment anhängen:** `cat ${CLAUDE_PLUGIN_ROOT}/templates/_shared/companion-<name>/compose.fragment.yml >> docker-compose.yml` (Trennzeile davor: `# --- companion-<name> (source: templates/_shared/companion-<name>/compose.fragment.yml) ---`).
   - **`.env.<name>.example`** (z.B. `.env.redis.example`) ans Repo-Root kopieren (Vorlage für Connection-Variablen).
   - **KEIN `db_scripts/`, KEIN Migrations-Runner, KEIN Backup-Skript** — Scope-Lock §17 (Companions haben keine Schema-Evolution).
   - **`README.md` um Companion-Abschnitt erweitern** (kurz): Use-Case, Connect-Env (`<NAME>_HOST` / `<NAME>_PORT`), Verweis auf `templates/_shared/companion-<name>/README.md` für Details (Production-Password-Setup etc.).
4e. **Secrets-Subsystem scaffolden** (Spec [`docs/architecture/secrets-subsystem.md`](../../docs/architecture/secrets-subsystem.md) §10) — **immer** (keine Opt-in-Frage, jede App bekommt es):
   1. **Script-Set kopieren:** `${CLAUDE_PLUGIN_ROOT}/templates/_shared/secrets/{_lib.sh,encrypt-env.sh,decrypt-env.sh,load-env.sh}` → `scripts/` (encrypt/decrypt/load-env: `chmod +x`; `_lib.sh` ohne `+x` — nur via `source`).
   2. **`.env.example` kopieren** ans Repo-Root (Vorlage, committed).
   3. **`.gitignore` ergänzen** um `${CLAUDE_PLUGIN_ROOT}/templates/_shared/secrets/gitignore.snippet` (idempotent — nicht doppelt anhängen, prüfen ob Block bereits vorhanden).
   4. **`.gitleaks.toml` kopieren** ans Repo-Root (§6 Allowlist-Scaffold).
   5. **Initiales `.env.gpg` anlegen + committen (GE4):**
      - Aus `.env.example` (Platzhalter, keine echten Werte) per `bash scripts/encrypt-env.sh` ein initiales `.env.gpg` erzeugen — **vorausgesetzt die Passphrase-Kette (§3) ist auf dem Scaffold-Host auflösbar** (d.h. `resolve_pass_file` gibt einen Pfad zurück ODER `$GPG_PASSPHRASE` gesetzt).
      - **Passphrasen-Quelle (Regelweg, GE1):** Jede App bekommt eine **eigene** Passphrase (Bitwarden-Item `env.gpg-passphrase-<app>`), **provisioniert von dev-gui** — dev-gui ist der einzige Bitwarden-vertraute Knoten der Fabrik ([[per-app-gpg-passphrase-provisioning]], dev-gui-Repo) und reicht die erzeugte Passphrase diesem Scaffold **ausschließlich als temporäre `0600`-Datei** über `$GPG_PASS_FILE` durch (nie über Argv, nie dauerhaft). `/new-project` selbst spricht **nie** mit Bitwarden — es liest nur die von `$GPG_PASS_FILE` referenzierte Datei.
      - **Passphrase nicht auflösbar** (non-interaktiv, kein `$GPG_PASS_FILE`, kein `$GPG_PASSPHRASE` — z.B. Lauf außerhalb eines dev-gui-Kontexts, **Fallback**: bisheriges interaktives Verfahren): kein Hard-Fail — Backlog-Item anlegen „Initiales `.env.gpg` erzeugen (`bash scripts/encrypt-env.sh`, sobald Passphrase provisioniert ist — Spec §10 GE4)" + Konsolen-Warnung ausgeben. Das übrige Scaffold (Scripts, `.gitignore`, `.gitleaks.toml`, `.env.example`) liegt trotzdem.
   6. **README um Secrets-Abschnitt erweitern** (am Ende anhängen): Verweis auf `docs/architecture/secrets-subsystem.md`, `.env`/`.env.gpg`-Modell, Workflow (`bash scripts/decrypt-env.sh` lokal → `.env` editieren → `bash scripts/encrypt-env.sh` → `.env.gpg` + `.env.example` committen).

4f. **Regressions-Grundgerüst scaffolden** (Spec [`docs/specs/regression-scaffolding.md`](../../docs/specs/regression-scaffolding.md), Konventionen [`docs/specs/regression-playwright-conventions.md`](../../docs/specs/regression-playwright-conventions.md)) — **immer** (stack-agnostisch, keine Opt-in-Frage; Playwright ist der eine Fabrik-Standard über alle Sprachen):
   1. **`playwright.config.ts` kopieren** (idempotent — nur anlegen, falls noch nicht vorhanden): `cp ${CLAUDE_PLUGIN_ROOT}/templates/_shared/regression/playwright.config.ts .` — Referenz-Template-Artefakt, keine divergente Zweit-Definition (AC4); aktiviert CTRF-JSON + JUnit-Reporter (AC1).
   2. **Playwright-Dev-Dependency** (`@playwright/test` + `playwright-ctrf-json-reporter`, AC1/AC5):
      - Existiert bereits ein Root-`package.json` (js/angular): als `devDependencies` **ergänzen** (bestehende Einträge/Deps nicht überschreiben).
      - Existiert **kein** `package.json` (Normalfall bei `new-project` — noch kein App-Code; ebenso jede nicht-npm-Sprache: java/flutter/html): ein **eigenständiges, minimales** `package.json` anlegen, das ausschließlich Playwright als Dev-Runner trägt (AC5 „eigenständiger Runner", stack-agnostisch):
        ```json
        {
          "name": "<projektname-kebab-case>-regression",
          "private": true,
          "devDependencies": {
            "@playwright/test": "latest",
            "playwright-ctrf-json-reporter": "latest"
          }
        }
        ```
   3. **`tests/regression/`-Baum anlegen** (AC2 — leere Bereichs-Suiten; deckt A2 „kein/leeres `areas.yaml`"):
      - **Immer:** `mkdir -p tests/regression/verbund` + `.gitkeep` (nur falls der Ordner noch nicht existiert).
      - **Je Eintrag in `board/areas.yaml`** (Bereichs-`id`, sofern die Datei existiert und mindestens einen Eintrag hat): `mkdir -p tests/regression/<id>` + `.gitkeep` — **leere** Suite, kein Testinhalt (Befüllen ist [[regression-define]], explizites Nicht-Ziel dieser Story).
      - **Fehlt `board/areas.yaml` oder ist sie leer:** nur `tests/regression/verbund/` entsteht (A2) — Bereichs-Suiten folgen, sobald Bereiche gepflegt sind.
   4. **`.gitignore` ergänzen** (idempotent — prüfen ob `test-results/` bereits vorhanden ist, sonst `cat ${CLAUDE_PLUGIN_ROOT}/templates/_shared/regression/gitignore.snippet >> .gitignore`, AC1).
   5. **Kein Runner-Wiring:** `scripts/run-regression.sh` (Ausführung, [[regression-runner]]) ist explizites Nicht-Ziel dieses Schritts (Spec regression-scaffolding.md Nicht-Ziele) — bleibt als Template-Artefakt unter `templates/_shared/regression/`.

5. **Deploy scaffolden** (aus `${CLAUDE_PLUGIN_ROOT}/templates/<lang>/`):
   - `Dockerfile`.
   - **Nur bei `profile.language` = `html`/`flutter`/`angular`:** `nginx.conf` (Sibling-Datei desselben Template-Ordners) — das Dockerfile kopiert sie explizit (`COPY nginx.conf /etc/nginx/conf.d/default.conf`); ohne diese Kopie bricht `docker build` mit „file not found" (Build-Versionierung, `docs/specs/build-version-stamping.md` AC6/AC7).
   - `.github/workflows/build.yml`: on push `main` → **Secret-Scan-Gate (gitleaks)** dann Image bauen + Push nach `ghcr.io/studis-softwareschmiede/<name>` via eingebautem `GITHUB_TOKEN` (`permissions: packages: write`).
   - **Security-Automatik** (Claude-frei, kontinuierlich aktuell): `.github/workflows/security.yml` (aus `templates/_shared/`, geplanter Secret-History-Scan + Issue bei Fund) und `.github/dependabot.yml` (aus `templates/_shared/`, Dependency-/Action-Vuln-Überwachung). Im `dependabot.yml` das **Sprach-Ökosystem** je `profile.language` aktivieren (npm→js/angular, pub→flutter, maven/gradle→java, keins→html). Dazu **GitHub Dependabot security updates aktivieren** (`gh api -X PUT repos/<org>/<name>/automated-security-fixes`).
   - **Static Analysis (optional — `knowledge/quality/sonar.md`):** Edition nach Repo-Sichtbarkeit wählen (AskUserQuestion): `gh repo view --json visibility` → **public → `sonarcloud`**, **private → `sonarqube-ce` oder `none`**. Default `none` → überspringen, nichts bricht. Bei `!= none`: `profile.sonar`-Block setzen (`edition`/`organization`/`project_key`=`<Org>_<repo>`/`host_url`), `templates/_shared/sonar.yml` → `.github/workflows/sonar.yml` (Platzhalter `__APP_JAVA_VERSION__`/`__SONAR_*__` ersetzen; **Java: Scanner-Step auf Java 17** ≠ App-JDK, Pack §3; **Trigger** = `schedule` monatlich + `workflow_dispatch`, kein push/PR (Pack §1a, SonarCloud wie CE); **Nicht-Java:** sonar-scanner CLI statt Maven-Plugin). Token NIE ins Repo → **Org-Secret `SONAR_TOKEN`** (manueller Schritt für den User).
5b. **Test-Runner-Isolation scaffolden (JS/Angular mit jest)** — bei `profile.language: js` (bzw. `angular`) UND jest als Test-Runner (Default-Annahme für npm/pnpm-Projekte ohne explizit anderen Runner): `cp ${CLAUDE_PLUGIN_ROOT}/templates/js/jest.config.js ./jest.config.js`. Die Vorlage trägt die **Pflicht-Worktree-Ignores** (`knowledge/js.md` `js/R07`: `testPathIgnorePatterns` + `modulePathIgnorePatterns` für `.claude/worktrees/`) — ohne sie vergiften parallele Worktrees (`/flow` §3) Haste-Map + Transform-Cache, und Tests scheitern später mit „Test suite failed to run". Der `coder` erweitert die Config projekt-spezifisch (babel/JSX/TS, moduleNameMapper, coverage), darf die zwei Ignore-Zeilen aber NICHT entfernen. **Nutzt das Projekt `vitest`/`node:test` statt jest**, die Datei NICHT kopieren — stattdessen die Worktree-Ignores sinngemäß in dessen Config (`vitest.config` `test.exclude` / `--test`-Glob ohne `.claude/`) übertragen und das als Backlog-Item vermerken.
6. **Branch-Protection** auf `main` (optional/best-effort): nur *„require a pull request before merging"* (blockiert Direkt-Push). **KEINE** Pflicht-Status-Checks (`reviewer` ist ein Agent, kein GitHub-Check → würde sonst jeden Merge blockieren) und **KEINE** Pflicht-Approvals (solo kann eigenen PR nicht approven). Lehnt die API ab (Plan/Permissions) → **überspringen, nicht abbrechen**. Das eigentliche Gate ist dein manueller Merge nach Review-PASS + Test-PASS.
7. **Initial commit + push.**

8. **Validate** (Spec [`docs/architecture/db-subsystem.md`](../../docs/architecture/db-subsystem.md) §18) — **wenn** `profile.db_dialect != none` ODER `profile.companions[]` nicht leer:
   - Analoger E2E-Smoke-Step wie `/adopt` §6 — der Orchestrator dispatcht den `tester`-Agent (Adoption-Validate-Modus) mit dem Auftrag `/preview up` → DB/Companion healthy → Marker-Migration appliziert (`SELECT count(*) FROM _schema_migrations` ≥ 1 / Mongo-Äquivalent) → Trivial-Query → `/preview down --keep-data=false`. Das Image-Build läuft via CI (Schritt 5 hat `build.yml` gescaffolded) **bevor** Validate den ghcr-Pull triggert — Validate wartet best-effort auf den ersten `build.yml`-Run (`gh run watch` mit kurzem Timeout). Pull-`denied` (Image noch nicht gebaut/published) → Validate skip + Output „CI nicht fertig — Validate beim nächsten `/preview up` nachholen" (kein FAIL, kein Issue).
   - **Konstante:** `MAX_VALIDATE_RETRIES = 3` (identisch zu `/adopt` §6).
   - **PASS:** in `.claude/profile.md` ergänzen:
     ```yaml
     adoption_validated_at: <ISO-Datum>
     adoption_validated_dialect: <postgres|mysql|sqlite|mongodb>
     adoption_validated_companions: [<liste>]
     ```
     Klar-Output: `✓ New-project validated end-to-end. profile.adoption_validated_at: <date>`. Validate-Ergänzung läuft als **zweiter Commit** auf demselben Branch (`chore: validate scaffold end-to-end`) — der Initial-Commit aus Schritt 7 bleibt unverändert (Audit-Trail).
   - **FAIL:** identischer Coder-Fix-Loop wie `/adopt` §6.c. Coder darf **nur** das gerade gescaffoldete Skeleton/Compose-Fragment/Migration anpassen — kein Business-Code. Bleibt nach 3 Iterationen FAIL → human-handoff + `gh issue create --title "NEW-PROJECT-VALIDATE-FAIL: <stage>" --label adopt-validate-fail,important`. `adoption_validated_at` wird **NICHT** gesetzt (später `/preview up` versucht erneut).
   - **Wenn `db_dialect: none` UND `companions: []`:** Validate skip + Output „nichts zu validieren — kein DB-/Companion-Skeleton angelegt" (statische App). Konsistent mit `/adopt` §6.

## Output
Repo-URL · Board-Pfad (`board/`) · Profil · Image-Ziel · (sofern Schritt 8 lief) Validate-Status → „bereit für `/requirement`".

## Grenzen
- Kein App-Code.
- `init`: bestehende `.claude/`- **und `docs/`**-Dateien NICHT überschreiben (mergen/fragen) → idempotent.
- Minimal fragen — DB-Auswahl ist **genau eine** zusätzliche Frage (kein Multi-Step-Wizard; Spec §10).
- Genau **ein** Dialekt pro Projekt (`db_dialect` ist Single-Value-Enum, Spec §16-R1) — Polyglott (mehrere primäre DBs) ist P1 explizit out of scope.
- `db_dialect: none` → **kein** Compose-Fragment, **kein** `db_scripts/`-Skeleton, **kein** `docs/data-model.md` — der User entscheidet später bewusst per `/adopt`-Re-Run oder manuellem Profil-Edit.
- Companion-Auswahl ist **optional** (Default `companions: []`); P1 nur `redis` verfügbar. Kein Migrations-/Backup-/Pack-Scaffold für Companions (Scope-Lock Spec §17).
- **Migration-Tool-Auswahl (Schritt 2e) ist single-value, optional, Default aus Spec §5 Mapping;** entfällt bei `db_dialect: none`. `db_scripts/`-Skeleton wird **nur bei `db_migration_tool: skeleton`** gescaffolded (Spec migration-tool-subsystem §8); bei anderen Tools landet die Tool-spezifische Konvention (Flyway-`src/main/resources/db/migration/`, Prisma-`prisma/migrations/`, …) als Backlog-Item, nicht als Auto-Scaffold. Kein Tool-Mix in einem Projekt — Spec §13.
- **Regressions-Scaffolding (Schritt 4f) ist immer aktiv** (stack-agnostisch, Spec `docs/specs/regression-scaffolding.md`) und idempotent — bestehende `playwright.config.ts`/`tests/regression/**`-Dateien werden nie überschrieben. Befüllen der Suiten ([[regression-define]]) und das Runner-Wiring ([[regression-runner]], `scripts/run-regression.sh`) sind explizite Nicht-Ziele dieses Schritts.
- **Validate (Schritt 8) ist kein Auto-Fix für Bestand:** Coder-Fix-Loop darf nur Skeleton/Compose-Fragment/Marker-Migration anpassen. Loop-Cap fix `MAX_VALIDATE_RETRIES = 3`; danach human-handoff, kein Endlos-Loop. `adoption_validated_at` wird NUR bei PASS gesetzt (Spec §18).
