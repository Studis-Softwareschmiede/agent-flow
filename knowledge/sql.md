# Knowledge Pack: sql  (Domäne — Datenbank)

Implementierungs-Expertise für SQL/Migrationen/RLS. Domäne (`profile.domains: [sql]`); vom `coder` geladen, vom `dba` fürs Modell-Design. Regel-IDs: `sql/R<NN>`. (Modell-DESIGN macht `dba`, Migrationen schreibt `coder`.)

## Coder-Guidance
- `sql/R01` — Migrationen forward-only + nummeriert; **idempotent** (`IF NOT EXISTS`, `CREATE OR REPLACE`, `DROP … IF EXISTS`).
- `sql/R02` — **Parametrisierte** Queries (`$1,$2`) — nie Werte/Identifier in SQL-Strings interpolieren.
- `sql/R03` — RLS: Tabelle `ENABLE ROW LEVEL SECURITY` **und** Policy; Tenant-Filter auf `auth.uid()`; Schreib-Policies mit `WITH CHECK`.
- `sql/R04` — `SECURITY DEFINER`-Funktionen: `SET search_path = ''` + Tenant-Filter intern erneut asserten.
- `sql/R05` — Index auf jede FK- und RLS-Filter-Spalte.

## Reviewer-Checklist
- Tabelle ohne RLS/Policy bzw. `USING (true)` auf Tenant-Daten → **Critical**.
- `SECURITY DEFINER` ohne gepinnten `search_path` → **Critical**.
- Werte/Identifier in SQL-String interpoliert → **Critical** (Injection).
- Bereits angewandte Migration editiert / umnummeriert → **Critical**.
- Fehlender Index auf FK/RLS-Spalte → **Important**.

## Test-Approach
- Migration läuft sauber **und** idempotent (zweimal anwenden); RLS-Probe mit zweitem User; Smoke-Query pro Schema.
