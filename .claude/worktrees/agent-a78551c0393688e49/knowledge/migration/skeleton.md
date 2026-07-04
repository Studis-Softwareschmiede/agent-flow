---
pack: migration/skeleton
pack_version: 1.0
pack_date: 2026-05-31
primary_sources:
  - https://github.com/Studis-Softwareschmiede/agent-flow/blob/main/docs/architecture/db-subsystem.md
non_sources: []
---

# Knowledge Pack: migration/skeleton

Der **skeleton**-Pfad ist unser plugin-eigener Migration-Runner — keine externe Library. Geladen bei `profile.db_migration_tool: skeleton` (Default, wenn das Feld fehlt). Regel-IDs: `skeleton/A<NN>` · `skeleton/B<NN>` · `skeleton/C<NN>`.

> **Hinweis:** Skeleton ist die Spec-immanente Default-Mechanik (siehe `docs/architecture/db-subsystem.md` §4-§6). Dieses Pack formalisiert sie als „Migration-Tool" namens `skeleton` — damit der Loader (Spec `migration-tool-subsystem.md` §7) konsistent über alle Tools bleibt. Der eigentliche Apply-Mechanismus ist `bash db_scripts/run-migrations.sh` (dort dokumentiert).

## A. Stable API & Deprecations

> Quellen-getrieben (`train`-Land). Schreibt: `agent-flow:train`.

- `skeleton/A01` — **Marker-Tabelle `_schema_migrations`** (Spec `db-subsystem.md` §4): pro Dialekt eine Marker-Tabelle/Collection mit Pflicht-Spalten `version` (PRIMARY KEY) + `applied_at` (Timestamp). Optionale `checksum`-Spalte für Drift-Detection (Standard-Empfehlung, Spec-konform auch ohne).
- `skeleton/A02` — **Forward-only-Disziplin** (Spec `db-subsystem.md` §4): committete Migrationen werden NIE editiert; Korrekturen als neue, höhere Nummer angehängt. Drift-Check via optionaler `checksum`-Spalte vom Runner geprüft.
- `skeleton/A03` — **Dialekt-spezifische Idempotenz-Patterns** (Spec `db-subsystem.md` §4): `CREATE TABLE IF NOT EXISTS` + `CREATE INDEX IF NOT EXISTS` (Postgres/SQLite) bzw. via Marker-Tabellen-Guard (MySQL/Mongo). Siehe Sprach-Packs `knowledge/sql.md` etc. für Dialekt-Details.

## B. Anti-Patterns aus Einsatz

> Felderfahrung (`retro`-Land). Initial leer.

_(noch keine Einträge; siehe Spec `migration-tool-subsystem.md` §4 + framework-build-subsystem.md §9 Schutzgitter)_

## C. Konventionen (Floor)

- `skeleton/C01` — **Verzeichnis `db_scripts/`** (Spec `db-subsystem.md` §4): kanonischer Pfad für alle skeleton-Migrationen. Andere Tools nutzen ihre eigene Konvention (Flyway: `src/main/resources/db/migration/`, Prisma: `prisma/migrations/`, etc.) — `db_scripts/` ist **reserviert** für skeleton und wird bei `db_migration_tool != skeleton` NICHT angelegt (Spec `migration-tool-subsystem.md` §8).
- `skeleton/C02` — **3-stellige nullgepaddete Versions-Nummerierung** (`001_init.sql`, `002_add_user_table.sql`, ...). Lückenlos. Mongo-Dateien sind `.js` (mongosh-Syntax).
- `skeleton/C03` — **Migrations-Runner-Script `db_scripts/run-migrations.sh`** ist Pflicht und wird vom Plugin-Template (`templates/_shared/db-<dialect>/db_scripts/run-migrations.sh`) gescaffolded.

## Coder-Guidance

- Neue Migration: nächste höhere 3-stellige Nummer wählen, `db_scripts/`-Verzeichnis editieren.
- Niemals committete Migrationen ändern (`skeleton/A02` Forward-only) — Korrektur als neue Datei.
- Idempotenz-Patterns pro Dialekt aus dem Sprach-/DB-Pack (`knowledge/sql.md`, `knowledge/sql-mysql.md`, etc.) ziehen.

## Reviewer-Checklist

- In-place-Edit einer committeten Migration → **Critical** (`skeleton/A02` Forward-only-Verstoß).
- Nicht-lückenlose Nummerierung (Lücken oder Duplikate) → **Important** (`skeleton/C02`).
- `db_scripts/` ohne `run-migrations.sh` → **Important** (`skeleton/C03` — Runner-Script fehlt, Apply-Pfad gebrochen).
- Marker-Tabelle nicht angelegt (Migration läuft, aber kein `_schema_migrations`-Eintrag) → **Critical** (`skeleton/A01` — Drift-Risiko).

## Test-Approach

- **Apply-Befehl (kanonisch, siehe `agents/tester.md` Migration-Apply-Dispatch):** `bash db_scripts/run-migrations.sh` muss exit 0 + Marker in `_schema_migrations` erscheinen (Spec `db-subsystem.md` §13 Smoke-Skripte).
- **Idempotenz-Test:** zweimaliger Lauf → identischer Marker-Count.
- **Drift-Test (falls `checksum`-Spalte):** Datei-Hash gegen gespeicherten Wert vergleichen.
