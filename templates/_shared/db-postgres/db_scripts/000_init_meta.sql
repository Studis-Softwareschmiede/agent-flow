-- 000_init_meta.sql — Erste Migration jedes neuen Postgres-Projekts
--
-- Legt die Marker-Tabelle `_schema_migrations` an. Der Runner
-- (`run-migrations.sh`) ruft diese Anweisung beim Bootstrap zwar selber
-- schon auf — aber wir tracken sie auch hier als reguläre Migration,
-- damit `db_scripts/` allein (z.B. via psql -f) eine vollständige,
-- idempotente Schema-Definition ist.
--
-- Spec §4 (Marker-Tabelle) + §16-R5 (optionale checksum-Spalte).
-- Idempotent: CREATE TABLE IF NOT EXISTS, mehrfacher Aufruf ohne Schaden.

CREATE TABLE IF NOT EXISTS public._schema_migrations (
  version    TEXT        PRIMARY KEY,
  applied_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  checksum   TEXT
);

COMMENT ON TABLE public._schema_migrations IS
  'Migration-Marker (agent-flow db-postgres template). NICHT manuell editieren — vom run-migrations.sh verwaltet.';
