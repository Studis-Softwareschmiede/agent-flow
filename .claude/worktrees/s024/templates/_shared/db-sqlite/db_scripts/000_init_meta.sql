-- 000_init_meta.sql — SQLite connection PRAGMAs + migration-marker table.
-- Wird vom Runner als erste Migration appliziert.
--
-- WICHTIG: PRAGMAs dürfen NICHT innerhalb einer Transaktion stehen
-- (sqlite ignoriert / verweigert sie dort). Daher KEIN BEGIN/COMMIT in dieser
-- Datei. Der Runner (run-migrations.sh) wendet die Datei daher ohne
-- äußere Transaktion an.
--
-- Bezug: knowledge/sql-sqlite.md R02 (foreign_keys), R03 (WAL), R04 (STRICT),
-- R06 (Marker-Tabelle); Spec §4 + §16-R5 (optionale checksum-Spalte).

-- WAL-Journal-Modus aktivieren — persistent nach erstem Setzen.
-- Erlaubt gleichzeitige Reader neben einem Writer (sqlite/R03).
PRAGMA journal_mode = WAL;

-- Foreign-Key-Enforcement — per-connection, nicht persistent. Der App-Code
-- MUSS dieses PRAGMA beim Connection-Setup ebenfalls setzen (sqlite/R02).
PRAGMA foreign_keys = ON;

-- Marker-Tabelle für angewandte Migrationen (Spec §4).
-- STRICT erzwingt Typ-Korrektheit (sqlite/R04, ab SQLite 3.37.0 / 2021-11).
-- checksum ist optional/NULL-erlaubt (Spec §16-R5) — der Runner schreibt
-- SHA-256 des Migration-Files für Drift-Detection.
CREATE TABLE IF NOT EXISTS _schema_migrations (
  version    TEXT NOT NULL PRIMARY KEY,
  applied_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  checksum   TEXT
) STRICT;
