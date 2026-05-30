# Knowledge Pack: sql  (Domäne — Datenbank)

Implementierungs-Expertise für SQL/Migrationen/RLS. Domäne (`profile.domains: [sql]`); vom `coder` geladen, vom `dba` fürs Modell-Design. Regel-IDs: `sql/R<NN>`. (Modell-DESIGN macht `dba`, Migrationen schreibt `coder`.)

## Coder-Guidance
- `sql/R01` — Migrationen forward-only + nummeriert; **idempotent** (`IF NOT EXISTS`, `CREATE OR REPLACE`, `DROP … IF EXISTS`).
- `sql/R02` — **Parametrisierte** Queries (`$1,$2`) — nie Werte/Identifier in SQL-Strings interpolieren.
- `sql/R03` — RLS: Tabelle `ENABLE ROW LEVEL SECURITY` **und** Policy; Tenant-Filter auf `auth.uid()`; Schreib-Policies mit `WITH CHECK`.
- `sql/R04` — `SECURITY DEFINER`-Funktionen: `SET search_path = ''` + Tenant-Filter intern erneut asserten.
- `sql/R05` — Index auf jede FK- und RLS-Filter-Spalte.
- `sql/R06` — **PostgreSQL 17 (stable seit Sep 2024)**: `MERGE` unterstützt jetzt `RETURNING` (mit `merge_action()` → `'INSERT'|'UPDATE'|'DELETE'`) und die neue Klausel `WHEN NOT MATCHED BY SOURCE` für Zeilen, die nur im Target existieren. `merge_action()` ist ausschließlich in `RETURNING`-Listen von `MERGE` erlaubt. Quelle: [PG17 Release Notes](https://www.postgresql.org/docs/17/release-17.html) · [MERGE Docs](https://www.postgresql.org/docs/17/sql-merge.html) · [merge_action()](https://www.postgresql.org/docs/17/functions-merge-support.html)
- `sql/R07` — **PostgreSQL 17 (stable seit Sep 2024)**: `JSON_TABLE()` wandelt JSON in eine relationale Ergebnismenge um (verwendbar in `FROM`). Zusätzlich: SQL/JSON-Constructor-Funktionen (`JSON()`, `JSON_SCALAR()`, `JSON_SERIALIZE()`) und Query-Funktionen (`JSON_EXISTS()`, `JSON_VALUE()`, `JSON_QUERY()`) sind jetzt Teil des SQL-Standards in PG17 — ersetzen viele manuelle `jsonb`-Ausdrücke. Quelle: [PG17 Release Notes](https://www.postgresql.org/docs/17/release-17.html)
- `sql/R08` — **Supabase Breaking Change (Default ab 30. Mai 2026)**: Neue Tabellen im `public`-Schema werden **nicht mehr automatisch** der Data API (PostgREST/GraphQL) exponiert. Jede Tabelle braucht explizite `GRANT SELECT/INSERT/UPDATE/DELETE ON ... TO anon, authenticated`. Migrations, die neue Tabellen anlegen, müssen diese Grants enthalten; sonst sind die Tabellen per API unsichtbar. Bestehende Tabellen behalten ihre Grants; ab Oktober 2026 gilt das für alle Projekte. Quelle: [Supabase Changelog #45329](https://supabase.com/changelog/45329-breaking-change-tables-not-exposed-to-data-and-graphql-api-automatically)

## Reviewer-Checklist
- Tabelle ohne RLS/Policy bzw. `USING (true)` auf Tenant-Daten → **Critical**.
- `SECURITY DEFINER` ohne gepinnten `search_path` → **Critical**.
- Werte/Identifier in SQL-String interpoliert → **Critical** (Injection).
- Bereits angewandte Migration editiert / umnummeriert → **Critical**.
- Fehlender Index auf FK/RLS-Spalte → **Important**.
- Neue Tabelle in `public`-Schema ohne explizite `GRANT`-Zeilen (Supabase-Projekte ab Mai 2026) → **Important** (`sql/R08`).

## Test-Approach
- Migration läuft sauber **und** idempotent (zweimal anwenden); RLS-Probe mit zweitem User; Smoke-Query pro Schema.
