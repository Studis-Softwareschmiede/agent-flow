-- Marker-Tabelle für den Migration-Runner (Spec §4 + §16-R5).
-- Forward-only — diese Datei NIE editieren, nach dem ersten Apply.
--
-- Konventionen (knowledge/sql-mysql.md):
--   mysql/R01 — ENGINE=InnoDB explizit.
--   mysql/R02 — CHARSET utf8mb4 + COLLATE utf8mb4_unicode_ci explizit.
--
-- Hinweis: run-migrations.sh erstellt die Tabelle ohnehin idempotent (CREATE
-- IF NOT EXISTS) BEVOR es Migrationen iteriert. Diese 000_init_meta.sql ist
-- die nachvollziehbare, im Repo sichtbare Source-of-Truth-Definition — der
-- Runner kann das gleiche Schema mehrfach safe wiederholen.

CREATE TABLE IF NOT EXISTS _schema_migrations (
  version    VARCHAR(255)                                         NOT NULL,
  applied_at DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  checksum   VARCHAR(128),
  PRIMARY KEY (version)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
