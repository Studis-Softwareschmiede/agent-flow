# Knowledge Pack: PostgreSQL  (Domäne — Datenbank, dialect = postgres)

Implementierungs-Expertise für PostgreSQL/Migrationen/RLS. **Dieser Pack gilt für PostgreSQL (inkl. Supabase). Für MySQL/MariaDB siehe `knowledge/sql-mysql.md`, für SQLite siehe `knowledge/sql-sqlite.md`.** Domäne (`profile.domains: [sql]` oder `profile.db_dialect: postgres`); vom `coder` geladen, vom `dba` fürs Modell-Design. Regel-IDs: `sql/R<NN>`. (Modell-DESIGN macht `dba`, Migrationen schreibt `coder`.)

Backwards-Compat: `profile.domains: [sql]` ohne `db_dialect` wird als `db_dialect: postgres` interpretiert (Spec §3).

## Coder-Guidance

### SQL/PostgreSQL-Regeln
- `sql/R01` — Migrationen forward-only + nummeriert; **idempotent** (`CREATE TABLE IF NOT EXISTS`, `CREATE INDEX IF NOT EXISTS`, `CREATE OR REPLACE FUNCTION`, `DROP … IF EXISTS`). `ALTER TABLE` ist nicht idempotent — wird durch Marker-Tabelle geschützt (nur einmalig appliziert). Quelle: [PostgreSQL IF NOT EXISTS](https://www.postgresql.org/docs/current/sql-createtable.html)
- `sql/R02` — **Parametrisierte** Queries (`$1,$2`) — nie Werte/Identifier in SQL-Strings interpolieren.
- `sql/R03` — RLS: Tabelle `ENABLE ROW LEVEL SECURITY` **und** Policy; Tenant-Filter auf `auth.uid()`; Schreib-Policies mit `WITH CHECK`.
- `sql/R04` — `SECURITY DEFINER`-Funktionen: `SET search_path = ''` + Tenant-Filter intern erneut asserten.
- `sql/R05` — Index auf jede FK- und RLS-Filter-Spalte.
- `sql/R06` — **PostgreSQL 17 (stable seit Sep 2024)**: `MERGE` unterstützt jetzt `RETURNING` (mit `merge_action()` → `'INSERT'|'UPDATE'|'DELETE'`) und die neue Klausel `WHEN NOT MATCHED BY SOURCE` für Zeilen, die nur im Target existieren. `merge_action()` ist ausschließlich in `RETURNING`-Listen von `MERGE` erlaubt. Quelle: [PG17 Release Notes](https://www.postgresql.org/docs/17/release-17.html) · [MERGE Docs](https://www.postgresql.org/docs/17/sql-merge.html) · [merge_action()](https://www.postgresql.org/docs/17/functions-merge-support.html)
- `sql/R07` — **PostgreSQL 17 (stable seit Sep 2024)**: `JSON_TABLE()` wandelt JSON in eine relationale Ergebnismenge um (verwendbar in `FROM`). Zusätzlich: SQL/JSON-Constructor-Funktionen (`JSON()`, `JSON_SCALAR()`, `JSON_SERIALIZE()`) und Query-Funktionen (`JSON_EXISTS()`, `JSON_VALUE()`, `JSON_QUERY()`) sind jetzt Teil des SQL-Standards in PG17 — ersetzen viele manuelle `jsonb`-Ausdrücke. Quelle: [PG17 Release Notes](https://www.postgresql.org/docs/17/release-17.html)
- `sql/R08` — **Supabase Breaking Change (Default ab 30. Mai 2026)**: Neue Tabellen im `public`-Schema werden **nicht mehr automatisch** der Data API (PostgREST/GraphQL) exponiert. Jede Tabelle braucht explizite `GRANT SELECT/INSERT/UPDATE/DELETE ON ... TO anon, authenticated`. Migrations, die neue Tabellen anlegen, müssen diese Grants enthalten; sonst sind die Tabellen per API unsichtbar. Bestehende Tabellen behalten ihre Grants; ab Oktober 2026 gilt das für alle Projekte. Quelle: [Supabase Changelog #45329](https://supabase.com/changelog/45329-breaking-change-tables-not-exposed-to-data-and-graphql-api-automatically)
- `sql/R09` — **PostgreSQL 18 (stable seit Sep 2025)**: `uuidv7()` generiert timestamp-geordnete UUIDs (RFC 9562 Version 7) — natürlich sortierbar, bessere Index-Lokalität als `gen_random_uuid()`. Für neue Tabellen `DEFAULT uuidv7()` statt `DEFAULT gen_random_uuid()` bevorzugen; `gen_random_uuid()` bleibt weiterhin verfügbar (=`uuidv4()`). Quelle: [PG18 Release Notes](https://www.postgresql.org/docs/18/release-18.html) · [uuidv7() Docs](https://www.postgresql.org/docs/18/functions-uuid.html)
- `sql/R10` — **PostgreSQL 18 (stable seit Sep 2025)**: `RETURNING` in `UPDATE`/`DELETE`/`MERGE` unterstützt jetzt explizit `OLD.*` und `NEW.*` — kein Before/After-Subquery-Workaround mehr nötig. `INSERT … RETURNING NEW.*`, `UPDATE … RETURNING OLD.name, NEW.name`, `DELETE … RETURNING OLD.*`. Die Aliase `old`/`new` sind case-insensitiv und können umbenannt werden. Quelle: [PG18 Release Notes](https://www.postgresql.org/docs/18/release-18.html) · [RETURNING Docs](https://www.postgresql.org/docs/18/dml-returning.html)
- `sql/R11` — **PostgreSQL 18 (stable seit Sep 2025) — Deprecation**: MD5-Passwort-Authentifizierung ist deprecated. `CREATE ROLE`/`ALTER ROLE` mit MD5-Passwort geben jetzt Warnungen aus (kontrollierbar via `md5_password_warnings = off`); Entfernung in einer künftigen Major-Version angekündigt. Übergang: SCRAM-SHA-256 (`scram-sha-256` in `pg_hba.conf`, `password_encryption = scram-sha-256`). Quelle: [PG18 Release Notes](https://www.postgresql.org/docs/18/release-18.html) · [Password Authentication Docs](https://www.postgresql.org/docs/18/auth-password.html)

### Migrations-Konvention (Spec §4)

**Verzeichnis-Layout:**
```
<repo>/
  db_scripts/
    001_init.sql          # 3-stellig, nullgepaddet, lückenlos
    002_<name>.sql
    run-migrations.sh     # dialekt-spezifischer Runner (Spec §6)
```

**Marker-Tabelle** (`public._schema_migrations`) — wird vom Runner angelegt, nie manuell editieren:
```sql
CREATE TABLE IF NOT EXISTS public._schema_migrations (
  version    TEXT        PRIMARY KEY,
  applied_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  checksum   TEXT                              -- optional, für Drift-Detection
);
```
Quelle: [PostgreSQL CREATE TABLE](https://www.postgresql.org/docs/current/sql-createtable.html) · [Supabase Migrations Guide](https://supabase.com/docs/guides/database/migrations)

**Regeln:**
- Forward-only, idempotent. Keine Migrations rückwärts laufen lassen — Korrekturen als neue höhere Nummer: `005_revert_004.sql`.
- Apply-Order: numerisch (lexikographisch über `[0-9][0-9][0-9]_*.sql`) — alle ungeapplyzten Versionen werden in einer Transaktion appliziert.
- Eine bereits committete Migration wird **nie editiert** (Marker-Tabelle schützt gegen Doppel-Apply; Editieren erzeugt Drift).

**Beispiel-Migration mit RLS-Policy** (kompakt):
```sql
-- 002_items_rls.sql
CREATE TABLE IF NOT EXISTS public.items (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID NOT NULL REFERENCES auth.users(id),
  name       TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.items ENABLE ROW LEVEL SECURITY;

CREATE POLICY items_owner ON public.items
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

CREATE INDEX IF NOT EXISTS items_user_id_idx ON public.items(user_id);
```

**Migrations-Image (Spec §16-R4):** Migrationen laufen **nicht** im App-Container. Stattdessen ein schlanker one-shot Sidecar (z.B. `postgres:16-alpine` mit `run-migrations.sh` als Entrypoint), der im Compose zwischen DB-Healthy und App-Start läuft. Das App-Image bleibt schlank — kein `psql`-Client einbacken.

## Reviewer-Checklist
- Tabelle ohne RLS/Policy bzw. `USING (true)` auf Tenant-Daten → **Critical**.
- `SECURITY DEFINER` ohne gepinnten `search_path` → **Critical**.
- Werte/Identifier in SQL-String interpoliert → **Critical** (Injection).
- Bereits angewandte Migration editiert / umnummeriert → **Critical**.
- Fehlender Index auf FK/RLS-Spalte → **Important**.
- Neue Tabelle in `public`-Schema ohne explizite `GRANT`-Zeilen (Supabase-Projekte ab Mai 2026) → **Important** (`sql/R08`).
- `run-migrations.sh` läuft im App-Container statt separatem Migrations-Sidecar → **Important** (Spec §16-R4).
- Migration-Nummerierung lückenhaft oder doppelt → **Important**.
- MD5-Passwort in `CREATE ROLE`/`ALTER ROLE` (PG 18+) → **Important** (`sql/R11`); SCRAM-SHA-256 verwenden.

## Test-Approach
- Migration läuft sauber **und** idempotent (zweimal anwenden, zweiter Lauf exit 0); RLS-Probe mit zweitem User; Smoke-Query pro Schema.

## Spec-Tagging
Trace-Tag je gedecktem Kriterium gemäss `docs/architecture/traceability-subsystem.md`.
- **Kontext:** DB-seitige Logik (RLS-Policies, Migrations, Functions) wird entweder via **pgTAP** (SQL-native) oder — häufiger — via **App-Layer-Tests** (TS/Java gegen echte/Container-DB) geprüft. Der Trace-Tag sitzt dort, wo der Test physisch liegt.
- **Idiom (pgTAP — SQL-native):** Token als drittes Argument (Testname) in pgTAP-Funktionen: `SELECT ok(…, '@trace rls-policy#AC1 — Tenant sieht nur eigene Rows');`. Extraktion: `grep -RoE` über `*.sql`-Testdateien + Core-Regex.
- **Idiom (App-Layer, TS/Java):** Token im `it()`/`test()`-Titel (Vitest/Jest) oder JUnit-`@Tag` wie im ts-/java-Pack — DB-Verbindung via `pg`-Driver, JPA oder Testcontainers; Token bleibt im App-Test.
- **Extraktions-Rezept:** Core-Regex `@trace\s+([a-z0-9][a-z0-9-]*)#((?:AC\d+|BR-\d+)(?:,(?:AC\d+|BR-\d+))*)` — über pgTAP-SQL-Dateien (`grep`) oder App-Test-Titel (je nach gewähltem Idiom).
- **Fallback:** kanonisches Token in pgTAP-Testname oder App-Test-Description; Core-Regex.
