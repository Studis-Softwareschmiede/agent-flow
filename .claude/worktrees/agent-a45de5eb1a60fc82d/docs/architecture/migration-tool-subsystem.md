# Architecture — Migration-Tool-Subsystem (pluggable, 4. Achse)

> **Bindend.** Diese Spec beschreibt **wie** das `agent-flow`-Plugin DB-Schema-Migrations-Tools (Flyway, Liquibase, Prisma, Alembic, …) als erstklassige, pluggable **4. Achse** behandelt — additiv zur Sprach-Achse (`lang`), zur DB-Achse (`db_dialect`) und zur Framework-/Build-Achse (`build` / `frameworks`). Implementierung erfolgt in sieben Wellen (Spec → Schema/Loader → Tester-Dispatch → Adopt/new-project-Detection → Pilot-Packs → DBA/Validate → Polish; §12). Abweichungen sind Review-Kriterium.

---

## 1. Zweck & Scope

**Zweck.** Heute kennt das Plugin genau **einen** Migration-Runner: den hauseigenen `skeleton`-Wrapper `db_scripts/run-migrations.sh` (dokumentiert in `docs/architecture/db-subsystem.md` §4-§6 — `_schema_migrations`-Marker-Tabelle, 3-stellig nummerierte `db_scripts/<NNN>_*.sql`, forward-only, optionale `checksum`-Drift-Detection). Diese Spec erweitert das Plugin um eine **4. Achse `db_migration_tool`**, die die Tool-Wahl pro Projekt explizit macht. Reale Projekte benutzen Industrie-Standards, die das Plugin abbilden muss:

- **Java/Spring**: Flyway (Default) / Liquibase (Alternative).
- **Node**: Prisma Migrate / Knex / TypeORM / Sequelize.
- **Python**: Alembic (SQLAlchemy) / Django-Migrations.
- **Flutter (mobile)**: sqflite (in-app `onUpgrade`).
- **Flutter+Supabase**: Supabase-CLI.
- **Go**: golang-migrate.
- **Rust**: refinery / sqlx-cli.

**Motivation (begründet).**

- **Tool ≠ Dialekt.** Postgres lässt sich mit Flyway, Liquibase, Prisma, Alembic, golang-migrate, sqlx-cli, Supabase-CLI ODER dem Skeleton-Runner verwalten — die Wahl ist orthogonal zum Dialekt. Eine 3-Achsen-Profil-Welt (lang/db/framework) bildet das nicht ab; jedes Adopt eines Flyway-Projekts müsste sonst entweder migrieren oder das Tool unsichtbar in einem Pack mitlaufen lassen.
- **Skeleton ist nicht universell.** Der hauseigene Runner ist bewusst schlank (keine Java-Runtime, kein Liquibase-Changelog-XML, kein Prisma-Migrate-State) und für neue Projekte/Demos optimal. Für Bestand mit Flyway/Liquibase/Prisma würde ein erzwungener Skeleton-Wechsel die Migration-Historie zerstören (oder einen riskanten Konvertierungs-Marathon erfordern). Das Plugin muss Bestand respektieren.
- **Tester/Reviewer/DBA brauchen Tool-Wissen.** Der Smoke-Apply-Befehl (`mvn flyway:migrate` vs. `npx prisma migrate deploy` vs. `bash db_scripts/run-migrations.sh`), die File-Konvention (`V<n>__<name>.sql` bei Flyway, `prisma/migrations/<timestamp>_<name>/migration.sql` bei Prisma) und die Anti-Patterns (z.B. „nie eine bereits applied Flyway-Migration editieren — Checksum bricht") sind tool-spezifisch und müssen in einem dedizierten Knowledge-Pack landen.

**Default bleibt `skeleton`.** Alle bestehenden Projekte (ohne `db_migration_tool` im Profil) verhalten sich unverändert; der Loader interpretiert eine fehlende Zeile als `skeleton` (§11). Neue Projekte bekommen über `/new-project` per Default-Mapping (§5) und User-Bestätigung einen passenden Vorschlag.

**Out of Scope (P1).**

- **Auto-Konvertierung** von einem Tool zum anderen (z.B. Flyway-`V1__init.sql` → Prisma-`migration.sql`). Das ist eine Mensch-Entscheidung mit Migrations-Historie-Risiko und Architektur-Implikationen — Plugin schlägt nichts vor, bietet keine Mass-Migration.
- **Mehrere Tools pro Projekt** (außer `skeleton` + spezifisches Tool als Übergangs-Phase — und davon ist abzuraten; Reviewer flaggt diese Konstellation als Anti-Pattern, §13).
- **Tool-Plugin-Detection** (z.B. Flyway-Java-Migrations, Liquibase-Extensions) — die Packs dokumentieren Standard-Konfigurationen; tieferes Plugin-Wissen ist späterer Wellen-Schub.
- **Cross-Tool-Validierung** (z.B. „die Prisma-Migration und das hand-geschriebene Flyway-SQL ergeben denselben Schema-State") — out-of-scope, bricht §13.

---

## 2. Profil-Erweiterung

Neues Feld im `.claude/profile.md`. Die drei bestehenden Achsen bleiben unverändert; **ein neues Feld** kommt hinzu:

```yaml
db_migration_tool: "skeleton" | "flyway@<major>" | "liquibase@<major>" | "prisma" | "alembic" | "knex" | "typeorm" | "sequelize" | "sqflite" | "supabase" | "golang-migrate" | "refinery" | "sqlx-cli" | "django-migrations"   # NEU, optional
```

**Pflicht-/Optional-Matrix:**

| Feld | Status | Default beim Scaffold |
|---|---|---|
| `db_migration_tool` | Optional (fehlt = `skeleton`) | aus Default-Mapping §5 oder User-Wahl |

**Major-Form (`@<major>`).** Pflicht bei Tools mit Cut. Beispiele:

- **`flyway@9` vs. `flyway@10`** — Flyway 10 hob die Java-Mindestversion auf 17 (Cut). Projekte auf Java 11/17 mit Flyway-9-Migrations bleiben auf 9; Projekte ab Java 17 starten typischerweise auf 10.
- **`liquibase@4`** — derzeit nur ein aktiver Major; `@<major>` Pflicht ab erstem Cut.
- **`prisma`, `alembic`, `knex`, `typeorm`, `sequelize`, `sqflite`, `supabase`, `golang-migrate`, `refinery`, `sqlx-cli`, `django-migrations`** — derzeit kein dokumentierter API-Cut, `@<major>` optional (Major-Optionalitäts-Regel analog `framework-build-subsystem.md` §5). Sobald ein Tool einen Cut bekommt, wird `@<major>` Pflicht (Build-Time-Fehler im Pack-Loader bei Ambiguität).

**Backwards-Compat.** Fehlende `db_migration_tool`-Zeile → Loader interpretiert als `skeleton` (1-Zeilen-Fallback, §11). Keine Migration nötig für Bestand. Beim nächsten `/adopt`-Lauf setzt §6-Heuristik den Wert (häufig `skeleton`, wenn `db_scripts/run-migrations.sh` existiert; sonst aus Default-Mapping §5).

**Abgrenzung zu `db_dialect`.** `db_migration_tool` ist orthogonal: ein Postgres-Projekt kann `skeleton`, `flyway@10`, `prisma`, `alembic` oder `golang-migrate` haben. Die Auswahl ist independent — die Tools sprechen alle SQL gegen denselben Dialekt-Service. Konfliktpunkt nur bei der Datei-Layout-Konvention (§8 — `db_scripts/` vs. tool-eigene Ordner).

---

## 3. Knowledge-Pack-Struktur

Neuer Pack-Ordner `knowledge/migration/`:

```
knowledge/
  migration/
    skeleton.md            # formalisiert unser bestehendes db_scripts/run-migrations.sh-Pattern
    flyway-9.md            # LTS-Range (Java 11/17)
    flyway-10.md           # Current-Range (Java-17-Cut)
    liquibase-4.md         # (on-demand)
    prisma.md              # (on-demand, kein Major-Cut bisher)
    alembic.md             # (on-demand)
    knex.md                # (on-demand)
    typeorm.md             # (on-demand)
    sequelize.md           # (on-demand)
    sqflite.md             # (on-demand)
    supabase.md            # (on-demand)
    golang-migrate.md      # (on-demand)
    refinery.md            # (on-demand)
    sqlx-cli.md            # (on-demand)
    django-migrations.md   # (on-demand)
```

**Pack-Header** (Pflicht-Frontmatter, analog `framework-build-subsystem.md` §3):

```yaml
---
pack: migration/flyway-10
pack_version: 1.0                              # SemVer, intern; bumpe bei jedem Edit (train/retro)
framework_version_range: ">=10.0, <11.0"       # bei Tools mit Cut; sonst entfällt/leer
pack_date: 2026-05-31                          # last_trained-Äquivalent
primary_sources:
  - https://documentation.red-gate.com/fd/
  - https://github.com/flyway/flyway/releases
non_sources: [baeldung.com, dev.to, medium.com]
---
```

**Header-Pflicht für Tools ohne Cut** (z.B. `prisma`, `alembic`): identisch, außer `framework_version_range` (entfällt oder leer). `primary_sources` zeigt auf die offizielle Doku (z.B. `prisma.io/docs`, `alembic.sqlalchemy.org`).

**Header-Pflicht für `skeleton.md`:** identisch, `framework_version_range` entfällt, `primary_sources` zeigt auf die hauseigene Spec (`docs/architecture/db-subsystem.md` §4-§6) — der Skeleton-Runner ist Plugin-intern, keine externe Primärquelle nötig.

**Pack-Versionierung (`pack_version`).** Pflicht-Format `<major>.<minor>` (zwei-stellig) — patch-Level nicht nötig, weil Pack-Patches als neuer commit/PR landen und das `pack_date` der Wahrheits-Marker ist. Identisch zur Framework-Pack-Konvention.

**Regel-IDs pro Pack-Namespace** (analog DB-Subsystem §3 und Framework-Subsystem §3): `flyway/R<NN>`, `liquibase/R<NN>`, `prisma/R<NN>`, `alembic/R<NN>`, `skeleton/R<NN>`. Begründung: stabile IDs für das Observability-Ledger (CONCEPT §5a).

---

## 4. Pack-Sektionen (Drei-Schichten-Aufbau)

Identisch zur Framework-Pack-Konvention (`docs/architecture/framework-build-subsystem.md` §4):

- `## A. Stable API & Deprecations` — von `train` befüllt (externe Wahrheit, Quellen-getrieben). Hier landen Tool-Lifecycle-Aussagen (z.B. „Flyway 10 erfordert Java 17"), Deprecation-Versionen (z.B. „`flyway.locations` ohne Prefix ist seit 9.x deprecated"), Breaking-Changes aus Release-Notes.
- `## B. Anti-Patterns aus Einsatz` — von `retro` befüllt (Felderfahrung, Projekt-getrieben). Hier landen Patterns, die in der Praxis brennen — mit Provenance (Projekt + Datei/PR; `framework-build-subsystem.md` §9-G2).
- `## C. Konventionen (Floor)` — manuell gepflegt. Sowohl `train` als auch `retro` fassen das **nur mit User-Approval** an (PR-Body markiert solche Änderungen explizit).
- `## Coder-Guidance` / `## Reviewer-Checklist` / `## Test-Approach` — Standard-Sektionen wie in Sprach-/Framework-Packs. Beide Agenten dürfen hier ergänzen, sofern die Aussage zu ihrer Schreib-Hoheit passt.

**Konflikt-Frei.** `train` schreibt **nie** in B. `retro` schreibt **nie** in A. Beide schreiben PRs (kein Direct-Push). Reviewer prüft die Schreib-Hoheit als Hard-Check: ein PR von `train`, der Sektion B berührt, ist `CHANGES-REQUIRED`; analog für `retro` in Sektion A. Symmetrisch zu Framework-Packs.

**Sektions-Reihenfolge im Pack-File** (kanonisch, damit Reviewer Diffs leicht zuordnet): A → B → C → Coder-Guidance → Reviewer-Checklist → Test-Approach.

**Verbatim-Wording-Disziplin (Pack-Authoring-Regel, identisch zu `framework-build-subsystem.md` §4 — Lehre aus PR-I).** Bei Aussagen mit **harten Versions- oder Datumsangaben** (z.B. „Flyway 10 erfordert Java 17 ab Release 10.0.0", „Liquibase 4.27 deprecated XYZ") MUSS der Pack-Autor entweder:

1. Ein **wörtliches Zitat + Anchor-Link** aus der Primärquelle im Pack-Regel-Body haben (`[src: URL#anchor — verbatim: „<exaktes Zitat>"]`), ODER
2. Die Aussage **entschärfen** mit `verify`-Marker (z.B. „Java 17 wird ab Flyway 10.x vorausgesetzt — *verify gegen die Release-Note der eingesetzten 10.x-Version*"), ODER
3. Auf das konkrete Datum/die konkrete Version **verzichten** und stattdessen auf die Primärquelle verweisen („siehe `documentation.red-gate.com/fd/` für aktuelle Support-Matrix").

Reviewer prüft das beim Pack-Review als Hard-Check: harte Datums-Behauptung ohne Verbatim/Anchor/verify-Marker → **Important** mit Verweis auf diese Regel.

**Versions-Strategie.** Major-Cut/Minor-Tag-Faustregel aus [`knowledge/_meta/versioning.md`](../../knowledge/_meta/versioning.md) — gilt analog für Migration-Tools. Beispiele:

- **Flyway 9 → 10**: **Cut** (Java-Mindest-Version änderte sich; vgl. Spring-Boot 2→3 mit Java-17-Cut).
- **Flyway 9.x → 9.y**: **Tag** (`[since: 9.x]`-Marker im Pack-Body, kein neuer Pack).
- **Prisma 5 → 6** (Beispiel zukünftig): **Cut** falls Migration-File-Format bricht; sonst Tag.

Beim Cut wird der NEUE Pack durch Kopie + Anpassung erzeugt; der ALTE Pack wird NICHT gelöscht (Bestandsprojekte verlassen sich darauf), bekommt aber im Header einen Endlebenszyklus-Marker (`eol: <datum>` oder `superseded_by: <neuer-pack-id>`). Identisch zur Framework-Pack-Regel (`framework-build-subsystem.md` §5).

---

## 5. Default-Mapping pro `lang + db_dialect`

Wenn `/new-project` ohne `--migration-tool`-Flag aufgerufen wird oder `/adopt` keine Tool-Heuristik trifft (§6), schlägt der Skill folgende Defaults vor (User-Bestätigung Pflicht via `AskUserQuestion`):

| `lang` | `db_dialect` | Default-Vorschlag | Begründung |
|---|---|---|---|
| java | postgres / mysql / sqlite | `flyway@10` | Spring-Standard; Java-17-baseline Stand 2026 |
| ts / js | postgres / mysql / sqlite | `skeleton` | Kein dominantes Tool im Node-Ökosystem — Prisma/Knex/TypeORM/Sequelize konkurrieren; Tool-Wahl ist ORM-Frage, nicht Migration-Frage |
| py | postgres / mysql / sqlite | `alembic` | SQLAlchemy-Standard; bei Django überschreibt §6-Detection → `django-migrations` |
| flutter | sqlite (mobile) | `sqflite` | In-app `onUpgrade`-Hook, kein externes Tool |
| flutter | supabase | `supabase` | Supabase-CLI ist der dokumentierte Pfad |
| rust | postgres / mysql / sqlite | `sqlx-cli` | Standard im sqlx-Ökosystem; refinery als Alternative im Pack erwähnt |
| go | postgres / mysql / sqlite | `golang-migrate` | De-facto-Standard im Go-Ökosystem |
| sonst | sonst | `skeleton` | Sicherer Fallback — Skeleton ist immer anwendbar |

**Mapping ist nur Vorschlag.** User-Bestätigung via `AskUserQuestion` ist Pflicht — analog zur DB-Detection in `db-subsystem.md` §9 („immer Rückfrage, auch bei `high`-Confidence"). Begründung: das Default-Mapping rät gut, aber die Tool-Wahl hat Architektur-Konsequenzen (Migration-Historie, Team-Skill, ORM-Bindung) — Mensch entscheidet, Plugin folgt.

**Sonderfall `db_dialect: none`.** Wenn das Projekt keine DB hat, ist `db_migration_tool` irrelevant — das Feld bleibt leer/fehlt, Loader behandelt es als `skeleton` (no-op, weil §7-Regel den Skeleton-Pfad nicht lädt).

---

## 6. Adopt-Detection-Heuristik

Kanonische Signal-Palette mit Confidence-Stufen. Detection läuft **nach** der DB-Detection (`db-subsystem.md` §9 Schritt 2a) und **vor** dem reviewer-Audit, damit der `reviewer` im Audit-Modus den passenden Migration-Tool-Pack laden kann.

| Signal | → `db_migration_tool` | Confidence |
|---|---|---|
| `pom.xml` / `build.gradle*` dep `org.flywaydb:flyway-core` (Version → Major) | `flyway@<major>` | high |
| `pom.xml` / `build.gradle*` dep `org.liquibase:liquibase-core` (Version → Major) | `liquibase@<major>` | high |
| `package.json` dep `prisma` ODER `@prisma/client` | `prisma` | high |
| `package.json` dep `knex` | `knex` | high |
| `package.json` dep `typeorm` | `typeorm` | high |
| `package.json` dep `sequelize` ODER `sequelize-cli` | `sequelize` | high |
| `requirements.txt` / `pyproject.toml` dep `alembic` | `alembic` | high |
| `requirements.txt` / `pyproject.toml` dep `django` UND Verzeichnis `*/migrations/__init__.py` | `django-migrations` | high |
| `pubspec.yaml` dep `sqflite` | `sqflite` | high |
| Verzeichnis `supabase/migrations/` UND `supabase/config.toml` | `supabase` | high |
| `Cargo.toml` dep `sqlx` UND Verzeichnis `migrations/` mit `*.sql` | `sqlx-cli` | high |
| `Cargo.toml` dep `refinery` | `refinery` | high |
| `go.mod` mit `github.com/golang-migrate/migrate` ODER `migrate`-Binary-Aufruf in CI/Makefile | `golang-migrate` | medium |
| `db_scripts/run-migrations.sh` UND `db_scripts/[0-9][0-9][0-9]_*.sql` UND Marker-Tabelle `_schema_migrations` | `skeleton` | high |
| Kein Treffer | (kein Eintrag → bleibt Default `skeleton` per §11) | — |

**Major-Extraktion** (analog `framework-build-subsystem.md` §6). Aus der Dep-Version den ersten Major nehmen — `org.flywaydb:flyway-core:10.18.0` → `flyway@10`; `org.flywaydb:flyway-core:9.22.3` → `flyway@9`. Tilde/Caret-Ranges (`~10.0`, `^9.22`) folgen derselben Caret-Regel wie Framework-Detection. Spec-Ranges mit Wildcards (`*`, `x`) ohne Untergrenze → AskUserQuestion.

**Confidence-Semantik.** `high` heißt: Signal ist eindeutig — Detection wird vorgeschlagen, User-Bestätigung erfolgt **trotzdem** (analog DB-Subsystem §9 und Framework-Subsystem §6). Confidence-Stufen sind Hinweis für Audit-Trail/Logs.

**Verbatim-Pflicht** (Pack-Schreibe-Regel aus `framework-build-subsystem.md` §4): bei harten Versions-Behauptungen im Pack — `verify`-Marker oder Verbatim-Zitat. Die Detection-Tabelle selbst ist Plugin-intern und nicht von der Verbatim-Pflicht betroffen; die daraus folgenden Pack-Inhalte schon.

**Mehrere Tool-Signale im selben Repo.** Detection nimmt das **erste eindeutige high-Signal**. Mehrere Tools = Anti-Pattern (§13). Reviewer-Audit flaggt diese Konstellation als **Important** (nicht Critical — Bestand könnte legitime Übergangs-Phase sein) und schlägt im Backlog die Migration auf ein Tool vor.

**Skeleton-Erkennung — Heuristik-Schichten.** Das Skeleton-Signal hat 3 Pflicht-Marker (Wrapper-Skript + Migration-File + Marker-Tabelle), damit ein zufälliges `db_scripts/`-Verzeichnis ohne Plugin-Runner nicht als Skeleton missidentifiziert wird. Sind nur 1-2 der Marker da → kein Signal, Default-Mapping §5 greift.

---

## 7. Pack-Auswahl-Regel

Erweitert die Pack-Auswahl aus `db-subsystem.md` §3 + `framework-build-subsystem.md` §3 um die 4. Achse:

```
ALWAYS  für JEDE Sprache in profile.lang: knowledge/<lang>.md (Sprach-Pack; bei Multi-Lang per-File-Dispatch, framework-build-subsystem §3)
IF db_dialect != none      → knowledge/<dialect>-Pack (db-subsystem §3)
IF profile.frameworks      → für jedes f in frameworks: knowledge/frameworks/<f>.md (framework-build-subsystem §3)
IF profile.build != none   → knowledge/build/<profile.build>.md (framework-build-subsystem §3)
IF db_migration_tool != skeleton AND db_migration_tool != null
                           → knowledge/migration/<tool>[-<major>].md   ← NEU
```

**Skeleton-Sonderfall.** Bei `db_migration_tool: skeleton` (oder fehlend) wird **kein** extra Migration-Pack geladen — die Skeleton-Konventionen sind in `db-subsystem.md` §4-§6 spec-immanent dokumentiert (Marker-Tabelle, Nummerierung, forward-only, Runner-Algorithmus, optionaler `checksum`-Drift-Detection). Ein duplikatives `migration/skeleton.md` würde die Spec spiegeln; stattdessen schreiben wir `migration/skeleton.md` als **schlanken Pack** (Pilot in PR-Q5), der primär auf die Spec verweist und nur die Coder-Guidance/Reviewer-Checklist/Test-Approach-Sektionen für tester/reviewer bündelt — der A/B/C-Drei-Schichten-Aufbau bleibt formal erhalten, ist aber knapp gehalten.

**Loader-Verhalten bei No-Match.** Profil sagt `flyway@10`, aber kein Pack mit `framework_version_range` umfasst `10.x` → Loader bricht mit klarer Fehlermeldung ab (`Pack "migration/flyway-10" fehlt; lege ihn an oder korrigiere das Profil.`). **Kein Silent-Fallback** auf einen anderen Major (analog `framework-build-subsystem.md` §5).

**Range-Matching-Semantik.** Der Pack-Loader matcht `db_migration_tool: "<tool>@<major>"` aus dem Profil gegen den `framework_version_range`-Header der Pack-Datei. Match-Regel: der Major aus dem Profil muss in das Range-Intervall fallen. Beispiel: Pack-Range `">=10.0, <11.0"` matcht `flyway@10`. Mehrere Packs mit überlappenden Ranges für denselben `<tool>` sind nicht erlaubt (Build-Time-Fehler im Pack-Loader).

**Major-Optionalität.** Tools ohne dokumentierten Cut (`prisma`, `alembic`, `knex`, etc.) dürfen ohne `@<major>` im Profil stehen. Loader nimmt dann den einzigen vorhandenen Pack-File-Match. Sobald ein Cut entsteht (z.B. `prisma-7.md` neu), wird `@<major>` im Profil Pflicht — sonst Build-Time-Fehler („mehrdeutiger Match: prisma.md ODER prisma-7.md").

---

## 8. Konfliktpunkt mit db-subsystem

Der Skeleton-Runner aus `db-subsystem.md` §4-§6 hat eine harte File-Konvention: `db_scripts/<NNN>_*.sql` + `db_scripts/run-migrations.sh` + Marker-Tabelle `_schema_migrations`. Industrie-Tools haben eigene, inkompatible Konventionen. Die Trennlinie ist **strikt**:

| `db_migration_tool` | Erwarteter Migration-Ordner | Skeleton-`db_scripts/` wird angelegt? | `run-migrations.sh` wird angelegt? |
|---|---|---|---|
| `skeleton` | `db_scripts/` | **ja** (heute Standard, `db-subsystem.md` §10) | **ja** |
| `flyway@9` / `flyway@10` | `src/main/resources/db/migration/` (Flyway-Default; konfigurierbar) | **nein** | **nein** (Tool: `mvn flyway:migrate`) |
| `liquibase@4` | `src/main/resources/db/changelog/` (Liquibase-Default) | **nein** | **nein** (Tool: `mvn liquibase:update`) |
| `prisma` | `prisma/migrations/` (Prisma-Default) | **nein** | **nein** (Tool: `npx prisma migrate deploy`) |
| `knex` | `migrations/` (Knex-Default; konfigurierbar in `knexfile.js`) | **nein** | **nein** (Tool: `npx knex migrate:latest`) |
| `typeorm` | `src/migration/` (TypeORM-Default) | **nein** | **nein** (Tool: `npx typeorm migration:run`) |
| `sequelize` | `migrations/` (Sequelize-Default) | **nein** | **nein** (Tool: `npx sequelize-cli db:migrate`) |
| `alembic` | `alembic/versions/` (Alembic-Default; via `alembic.ini`) | **nein** | **nein** (Tool: `alembic upgrade head`) |
| `django-migrations` | `<app>/migrations/` (pro Django-App) | **nein** | **nein** (Tool: `python manage.py migrate`) |
| `sqflite` | in-app Code (`onCreate` / `onUpgrade` Callback) | **nein** | **nein** (kein externer Apply — in-app) |
| `supabase` | `supabase/migrations/` (Supabase-CLI-Default) | **nein** | **nein** (Tool: `supabase db push`) |
| `golang-migrate` | `migrations/` (Konvention; konfigurierbar) | **nein** | **nein** (Tool: `migrate ... up`) |
| `sqlx-cli` | `migrations/` (sqlx-CLI-Default) | **nein** | **nein** (Tool: `sqlx migrate run`) |
| `refinery` | `migrations/` (Konvention) | **nein** | **nein** (in-app / build.rs) |

**Regel (verbindlich).** Wenn `db_migration_tool != skeleton`, überspringt `/adopt` und `/new-project` den `db_scripts/`-Skeleton-Copy (`db-subsystem.md` §9 Schritt e/2 und `db-subsystem.md` §10 Schritt für `db_dialect != none`). Der Migration-Pack liefert die Tool-spezifische Konvention im Coder-Guidance-Abschnitt (z.B. „Flyway-Files: `V<sequenz>__<beschreibung>.sql` in `src/main/resources/db/migration/`"); der `coder` legt sie beim ersten realen Bedarf an, nicht beim Scaffold.

**`run-migrations.sh`-Skript** wird **nur bei `skeleton`** angelegt. Bei anderen Tools übernimmt das Tool selbst (`mvn flyway:migrate`, `npx prisma migrate deploy`, `alembic upgrade head`, etc.).

**Compose-Fragment bleibt unabhängig.** Der db-Service-Block in `templates/_shared/db-<dialect>/compose.fragment.yml` (`db-subsystem.md` §5) ist für **ALLE** Tools nötig — sie brauchen alle eine laufende DB. Das Compose-Fragment kümmert sich nur um den DB-Service (Image, Healthcheck, Volume, Port); der Migrations-Service-Block im Fragment (one-shot, ruft `db_scripts/run-migrations.sh`) ist **nur bei `skeleton`** sinnvoll und wird bei anderen Tools entweder entfernt oder durch einen Tool-spezifischen Block ersetzt (Detail-Pattern kommt in den jeweiligen Packs in PR-Q5+ on-demand).

**Reviewer-Audit-Regel.** Wenn `db_migration_tool != skeleton` UND `db_scripts/` mit Migrations existiert → `Important` (vermutlich legacy Skeleton-Bestand, der nach Tool-Wechsel zurückblieb — Konfliktquelle). Wenn `db_migration_tool == skeleton` UND Tool-eigener Ordner (`prisma/migrations/`, `src/main/resources/db/migration/`) existiert → `Important` (Anti-Pattern Tool-Mix, §13). Beide landen im Backlog.

---

## 9. Tester-Migration-Apply-Dispatch

Verweis auf `agents/tester.md` Abschnitt „Migration-Apply-Dispatch" (kommt in PR-Q3 — Welle 3 dieses Epics, kanonische Befehls-Tabelle als Single-Source-of-Truth in dieser Spec):

| `db_migration_tool` | Apply-Befehl (Smoke) |
|---|---|
| `skeleton` | `bash db_scripts/run-migrations.sh` (Bestand, `db-subsystem.md` §6) |
| `flyway@9` / `flyway@10` | `mvn -B -ntp flyway:migrate` (Maven-Plugin) ODER `flyway migrate` (CLI/Docker) |
| `liquibase@4` | `mvn -B -ntp liquibase:update` ODER `liquibase update` |
| `prisma` | `npx prisma migrate deploy` |
| `alembic` | `alembic upgrade head` |
| `knex` | `npx knex migrate:latest` |
| `typeorm` | `npx typeorm migration:run` |
| `sequelize` | `npx sequelize-cli db:migrate` |
| `sqflite` | (in-app, kein externer Apply — Smoke = App-Start ohne DB-Fehler im Log) |
| `supabase` | `supabase db push` |
| `golang-migrate` | `migrate -path migrations -database "$DB_URL" up` |
| `sqlx-cli` | `sqlx migrate run` |
| `refinery` | (in-app — analog `sqflite`, Smoke = App-Start ohne DB-Fehler) |
| `django-migrations` | `python manage.py migrate` |

**Flags-Begründung (knapp).**

- `mvn -B -ntp` — batch mode + no transfer progress (CI-clean output; analog `framework-build-subsystem.md` §10).
- `npx <tool>` — keine globale Installation nötig; das Tool wird aus `package.json` resolved.
- `alembic upgrade head` — `head` ist die Spitze des Migration-Branches (nicht eine konkrete Revision).
- `supabase db push` — pusht alle nicht-applied Migrations aus `supabase/migrations/`.

**Exit-Code-Semantik.** Tester wertet ausschließlich den Exit-Code (0 = PASS, ≠0 = FAIL). Tool-spezifische Log-Pattern-Heuristik ist **out-of-scope** (zu fragil, Tool-übergreifend nicht stabil — analog `framework-build-subsystem.md` §10).

**In-App-Tools (`sqflite`, `refinery`).** Kein externer Apply-Befehl — der Migrations-Code läuft beim App-Start. Smoke-Kriterium: App startet ohne DB-Fehler-Log (Heuristik auf Log-Pattern oder Healthcheck nach Start). Detail-Wiring in `agents/tester.md` PR-Q3.

**Skeleton-Sonderfall.** Der Apply-Befehl ist identisch zum Bestand (`db-subsystem.md` §6) — kein Bruch.

---

## 10. DBA-Erweiterung

`agents/dba.md` ist bisher skeleton-zentriert (siehe `db-subsystem.md` §8). Erweiterung (kommt in PR-Q6 — Welle 6 dieses Epics):

1. **Pack-Lade-Pflicht ergänzt.** Bei `db_migration_tool != skeleton` lädt der DBA den Migration-Pack zusätzlich zum DB-Dialekt-Pack. Bei `skeleton` (oder fehlend) wird kein extra Pack geladen — die Skeleton-Konventionen kennt der DBA bereits aus `db-subsystem.md`.
2. **Audit-Modus prüft Tool-spezifische Konventionen.** Beispiele:
   - **Flyway**: Filename-Pattern `V<sequenz>__<beschreibung>.sql`, keine Lücken in Sequenz, keine Edits an applied Files (Checksum bricht).
   - **Prisma**: Keine direkten `.sql`-Edits außerhalb von `prisma/migrations/<timestamp>_<name>/migration.sql` — alle Schema-Änderungen über `schema.prisma` + `npx prisma migrate dev`.
   - **Alembic**: `down_revision`-Kette intakt, keine vergessenen `op.execute(...)`-Inline-SQL.
   - **Sqflite**: `onUpgrade` deckt alle Versionssprünge ab (1→2, 1→3, 2→3).
3. **Output `docs/data-model.md` bleibt tool-agnostisch.** Entitäten/Beziehungen/Constraints — der `coder` übersetzt sie ins Tool. Unverändert zur Bestandsregel (`db-subsystem.md` §8 Punkt 3).
4. **Harte Grenzen** explizit: `dba` greift **nie** auf den Migrations-Ordner zu (egal ob `db_scripts/`, `prisma/migrations/`, `alembic/versions/` …). Schreibt nur `docs/data-model.md` (unverändert zur Bestandsregel `db-subsystem.md` §8 Punkt 4).

---

## 11. Backwards-Compat

Fehlende `db_migration_tool`-Zeile im Profil → Loader behandelt als `skeleton` (1-Zeilen-Fallback). Bestehende Projekte:

1. **Loader-Verhalten unverändert.** Der Skeleton-Pack-Loader läuft heute auch ohne expliziten Eintrag, weil §7-Regel bei `skeleton` (oder fehlend) **nichts** aus `knowledge/migration/` lädt — das Verhalten ist identisch zu „kein Pack geladen".
2. **`db_scripts/`-Layout unverändert.** Bestehende Projekte mit `db_scripts/run-migrations.sh` + Migrations bleiben funktional unverändert. Kein Migration-Lauf, kein File-Rename, kein Runner-Tausch.
3. **Beim nächsten `/adopt`-Lauf** setzt §6-Heuristik den Wert:
   - `db_scripts/run-migrations.sh` + Marker-Tabelle vorhanden → `skeleton` (explizit).
   - Flyway/Liquibase/Prisma/… detected → entsprechendes Tool (User-Bestätigung Pflicht).
   - Kein Treffer → Default-Mapping §5 (User-Bestätigung Pflicht).
4. **Reviewer-Toleranz.** Ein reviewer-Run, der das `db_migration_tool`-Feld noch nicht im Profil findet, darf das **nicht** als `CHANGES-REQUIRED` werten — er muss klar im Review-Output kennzeichnen („Migration-Tool nicht im Profil; Default `skeleton` angenommen; Profil-Migration empfohlen") und sonst fortfahren (analog `framework-build-subsystem.md` §11).
5. **Migration der Bestandsprojekte** ist **opt-in**: `/adopt` führt die Detection beim nächsten Lauf durch — kein automatischer Mass-Update aller Bestandsprojekte.

---

## 12. Build-Wellen (Implementations-Reihenfolge dieses Epics — PR-Q1 bis Q7)

| Welle | PR | Inhalt | Abhängigkeit |
|---|---|---|---|
| 1 (Spec) | **PR-Q1** | Diese Spec (`docs/architecture/migration-tool-subsystem.md`) | — |
| 2 (Schema + Loader) | **PR-Q2** | Profil-Feld `db_migration_tool` in 5 Agent-Defs (`coder`/`reviewer`/`tester`/`dba`/`train`); Pack-Loader-Logik (§7); `/train`-Resolver-Erweiterung um `migration/`-Namespace | PR-Q1 |
| 3 (Tester-Dispatch) | **PR-Q3** | `agents/tester.md` Migration-Apply-Dispatch-Tabelle (§9), kanonische Apply-Befehle, in-app-Sonderfall, Skeleton-Fallback | PR-Q2 |
| 4 (Adopt + new-project Detection) | **PR-Q4** | `skills/adopt/SKILL.md` Schritt 2f Migration-Tool-Detection (§6); `skills/new-project/SKILL.md` `--migration-tool` Flag + Default-Mapping-Frage (§5) | PR-Q2 |
| 5 (Pilot-Packs) | **PR-Q5** | `knowledge/migration/skeleton.md` + `knowledge/migration/flyway-9.md` + `knowledge/migration/flyway-10.md` (3 Files, sequenziell für Review-Klarheit) | PR-Q2 |
| 6 (DBA + Validate) | **PR-Q6** | `agents/dba.md` Tool-aware (§10); `skills/adopt/SKILL.md` §6 Validate-Schritt Apply-Befehl-Update (analog `adopt/validate-e2e-2026-05-31`-Lesson); Cache-Schlüssel-Erweiterung (`profile.adoption_validated_at`-Cluster bekommt `_migration_tool`-Feld) | PR-Q2 + PR-Q5 |
| 7 (Polish) | **PR-Q7** | Reviewer-Findings aus Q2-Q6 zusammenfassen, on-demand-Pack-Anlage (z.B. `prisma.md`, `alembic.md` wenn Bedarf entsteht), Doku-Politur | PR-Q6 |

**Parallelisierbarkeit.** PR-Q3, PR-Q4 und PR-Q5 können parallel zu Q2 laufen, sobald PR-Q2 gemerged ist. PR-Q6 hängt von PR-Q2 (Loader kennt Migration-Packs) und PR-Q5 (mindestens `skeleton.md` + ein Pilot-Pack existiert).

**Innerhalb Welle 5.** Alle 3 Pack-Files sind unabhängig, werden aber **sequenziell** geprüft (für Review-Klarheit — der Reviewer kann pro Pack einen klaren Befund liefern, statt 3 Packs in einem Diff). Reihenfolge im PR-Body: `skeleton.md` → `flyway-9.md` → `flyway-10.md`.

**Graceful Degradation (analog `db-subsystem.md` §14-Amendment und `framework-build-subsystem.md` §12).** Vorgezogene Wellen-Schritte (z.B. ein Skill-Edit vor dem zugehörigen Pack) müssen sich gegen fehlende Pack-Files **graceful** verhalten — klare Warn-Zeile, kein Hard-Fail.

---

## 13. Nicht-Ziele P1

- **Keine Auto-Konvertierung von einem Tool zum anderen.** Flyway → Prisma, Skeleton → Flyway, etc. sind Mensch-Entscheidungen mit Migrations-Historie-Risiko. Das Plugin schlägt nichts vor, bietet keine Mass-Migration, hat keine Konvertierungs-Logik.
- **Kein Tool-Mix in einem Projekt.** `skeleton` + Flyway parallel im selben Projekt ist Anti-Pattern → Reviewer flaggt als `Important` (Backlog-Item: „Tool-Wahl konsolidieren"). Einzige Ausnahme: dokumentierte Übergangs-Phase (z.B. Flyway-Bestand bleibt, neue Migrations via Skeleton während eines schrittweisen Rückbaus) — muss in `docs/data-model.md`-Header explizit deklariert sein.
- **Keine Cross-Tool-Migrations-File-Konvertierung.** Z.B. Flyway-`V1__init.sql` zu Prisma-`migration.sql` umschreiben — out-of-scope, bricht §1 (Auto-Konvertierung).
- **Pack-Inhalt für non-Pilot-Tools** (`liquibase`, `prisma`, `alembic`, `knex`, `typeorm`, `sequelize`, `sqflite`, `supabase`, `golang-migrate`, `sqlx-cli`, `refinery`, `django-migrations`) kommt **on-demand** — wenn ein reales Projekt sie trifft (Lehre aus `framework-build-subsystem.md`-Pilot-Disziplin: Pilot-Packs für Spring-Boot + Maven; weitere Frameworks/Build-Tools on-demand). Pilot in PR-Q5 sind nur `skeleton` + `flyway-9` + `flyway-10` — weil Flyway im Java-Ökosystem dominant ist und einen echten Cut hat (9→10), der die Profil-Major-Form scharf macht.
- **Keine Tool-Plugin-Tiefe.** Flyway-Java-Migrations, Liquibase-Extensions, Prisma-Generators sind in den Packs nur kurz dokumentiert (Verweis auf Tool-Doku); tieferes Plugin-Wissen ist späterer Wellen-Schub.
- **Keine Multi-Tool-Detection im selben PR.** Wenn `/adopt` 2+ Tools detected (Flyway + Prisma im selben Repo), nimmt es das erste high-Signal und flaggt das zweite als Anti-Pattern-Backlog (§6, §13). Kein Polyglott-Trigger wie bei Frameworks (`framework-build-subsystem.md` §7) — Tool-Polyglottie ist immer Anti-Pattern, kein P2-Architektur-Pfad.
- **Keine Auto-Migration der Bestandsprojekte.** `/adopt` setzt das Feld beim nächsten Lauf, aber kein Mass-Update bestehender Profile (analog `framework-build-subsystem.md` §11 Punkt 4).
