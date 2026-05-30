# MySQL / MariaDB Knowledge Pack — pluggable DB-Subsystem (Spec §3)

> **Dialekt:** `mysql` (`profile.db_dialect: mysql`). Engine target: **MariaDB 11 LTS** (preferred FOSS path) and **MySQL 8.0 / 8.4 LTS** (compatible).
> See also: Postgres-Pack → `knowledge/sql.md` | MongoDB-Pack → `knowledge/mongodb.md`.
> Regel-IDs: `mysql/R<NN>`.

---

## Coder-Guidance

- `mysql/R01` — **`ENGINE=InnoDB` explizit** auf jeder neuen Tabelle setzen (`CREATE TABLE … ENGINE=InnoDB`). InnoDB ist zwar der Default in MySQL 8.0 und MariaDB 11, aber `NO_ENGINE_SUBSTITUTION` (Teil des MySQL-8.0-Default-SQL-Mode) erlaubt der Engine still zu substituieren, falls ein anderes Storage-Plugin aktiv ist. Explizite Angabe macht die Absicht dokumenten-sicher und verhindert unerwartete Substitution in Deployments mit abweichender Konfiguration. Quelle: [MySQL 8.0 §16.1 Setting the Storage Engine](https://dev.mysql.com/doc/refman/8.0/en/storage-engine-setting.html) · [MySQL 8.0 §17.1 InnoDB Introduction](https://dev.mysql.com/doc/refman/8.0/en/innodb-introduction.html)

- `mysql/R02` — **`CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci`** explizit auf jeder neuen Tabelle (und bei Bedarf auf Spalten) setzen. `utf8` / `utf8mb3` ist **deprecated seit MySQL 8.0** (alias für 3-Byte-Encoding, das supplementäre Zeichen inkl. Emojis nicht speichern kann) und wird in einem zukünftigen Major-Release entfernt. MySQL 8.0 default-collation `utf8mb4_0900_ai_ci` und MariaDB-11.6+-Default `utf8mb4_uca1400_ai_ci` unterscheiden sich — explizit `utf8mb4_unicode_ci` setzen gewährleistet portables Verhalten über beide Engines. Quelle: [MySQL 8.0 §12.9.1 utf8mb4](https://dev.mysql.com/doc/refman/8.0/en/charset-unicode-utf8mb4.html) · [MySQL 8.0 §12.9.2 utf8mb3 deprecated](https://dev.mysql.com/doc/refman/8.0/en/charset-unicode-utf8mb3.html) · [MariaDB Character Set Overview](https://mariadb.com/docs/server/reference/data-types/string-data-types/character-sets/character-set-and-collation-overview)

- `mysql/R03` — **Primary Keys: `BIGINT UNSIGNED NOT NULL AUTO_INCREMENT`**. `INT` läuft bei ~2,1 Mrd. Rows über; `BIGINT UNSIGNED` trägt ~18,4 × 10¹⁸ Werte. MySQL-spezifisch: `AUTO_INCREMENT`-Attribut (kein `SERIAL`-Alias wie Postgres); Spalte muss indiziert sein (PRIMARY KEY genügt). Quelle: [MySQL 8.0 §5.6.9 Using AUTO_INCREMENT](https://dev.mysql.com/doc/refman//8.0/en/example-auto-increment.html)

- `mysql/R04` — **`updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP`** für automatisch aktualisierte Zeitstempel-Spalten verwenden. Das `ON UPDATE CURRENT_TIMESTAMP`-Attribut ist MySQL/MariaDB-spezifisch (kein Standard-SQL); es aktualisiert die Spalte beim `UPDATE` automatisch auf den aktuellen Server-Zeitstempel — ohne Trigger. Quelle: [MySQL 8.0 §13.2.5 Automatic Initialization and Updating for TIMESTAMP](https://dev.mysql.com/doc/refman/8.0/en/timestamp-initialization.html) · [MariaDB TIMESTAMP Docs](https://mariadb.com/docs/server/reference/data-types/date-and-time-data-types/timestamp)

- `mysql/R05` — **SQL_MODE `STRICT_TRANS_TABLES` nie deaktivieren.** `STRICT_TRANS_TABLES` ist in MySQL 8.0 und MariaDB standardmäßig aktiv und verhindert silent type-coercion (z.B. leere Strings statt NULL, gekürzte Strings). Migrations oder App-Code dürfen `SET sql_mode = …` nicht nutzen, um Strict Mode zu umgehen — das versteckt Daten-Integritätsprobleme. Quelle: [MySQL 8.0 §7.1.11 Server SQL Modes](https://dev.mysql.com/doc/refman/8.0/en/sql-mode.html)

---

## Migrations-Konvention

**Layout** (identisch zu Postgres-Pack, Spec §4):

```
<repo>/
  db_scripts/
    001_init.sql
    002_<name>.sql
    run-migrations.sh   # Welle-2-Runner
```

**Nummerierung:** 3-stellig, nullgepaddet, lückenlos, **forward-only**. Committete Migrationen werden nie editiert — Korrekturen kommen als neue, höhere Nummer.

**Marker-Tabelle** (Spec §4, mysql-Dialekt):

```sql
CREATE TABLE IF NOT EXISTS _schema_migrations (
  version     VARCHAR(255)                        NOT NULL,
  applied_at  DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  checksum    VARCHAR(64),
  PRIMARY KEY (version)
) ENGINE=InnoDB CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
```

> Hinweis: `DATETIME` statt `TIMESTAMPTZ` (kein Timezone-Typ in MySQL/MariaDB). Server-Timezone konsistent setzen (`time_zone = '+00:00'` in `my.cnf`).

**Idempotenz-Regeln (mysql-Dialekt, Spec §4):**

- `CREATE TABLE IF NOT EXISTS` — supported.
- `CREATE INDEX` hat **kein** `IF NOT EXISTS` in MySQL < 8.0.29 / MariaDB < 10.1.4. Ab MySQL 8.0.29+ und MariaDB 10.1.4+ ist `CREATE INDEX IF NOT EXISTS` verfügbar — prüfen, welche Engine-Version deployt ist; alternativ den Marker als alleinige Schutz gegen Doppel-Apply einsetzen.
- `ALTER TABLE` ist nicht idempotent — Migrationen mit `ALTER` ausschließlich per Marker steuern (nicht zweimal anwenden).
- Transaktion um jede Migration wrappen (`START TRANSACTION … COMMIT`); Rollback bei Fehler. DDL in MySQL/MariaDB ist **nicht** automatisch transaktional für metadata — dennoch explizit wrappen, weil DML-Teile der Migration transaktional sind.

**Compose-Service-Referenz** (Spec §5, Welle 2):

```yaml
services:
  db:
    image: mariadb:11
    restart: unless-stopped
    environment:
      MARIADB_DATABASE: ${DB_NAME:-app}
      MARIADB_USER: ${DB_USER:-app}
      MARIADB_PASSWORD: ${DB_PASSWORD:?required}
      MARIADB_ROOT_PASSWORD: ${DB_ROOT_PASSWORD:?required}
    volumes:
      - db_data:/var/lib/mysql
      - ./db_scripts:/db_scripts:ro
    healthcheck:
      test: ["CMD", "healthcheck.sh", "--connect"]
      interval: 5s
      timeout: 3s
      retries: 20
    ports:
      - "${DB_PORT:-3306}:3306"
volumes:
  db_data: {}
```

---

## Beispiel-Migration

```sql
-- db_scripts/001_init.sql
-- Forward-only. Apply via Marker-Tabelle (_schema_migrations).

START TRANSACTION;

CREATE TABLE IF NOT EXISTS _schema_migrations (
  version     VARCHAR(255) NOT NULL,
  applied_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  checksum    VARCHAR(64),
  PRIMARY KEY (version)
) ENGINE=InnoDB CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS users (
  id         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  email      VARCHAR(320)    NOT NULL,
  created_at TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP
                                       ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_users_email (email)
) ENGINE=InnoDB CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS posts (
  id         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id    BIGINT UNSIGNED NOT NULL,
  title      VARCHAR(255)    NOT NULL,
  body       TEXT,
  created_at TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP
                                       ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  CONSTRAINT fk_posts_user FOREIGN KEY (user_id)
    REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- Index auf FK-Spalte (Reviewer-Checklist R05-analog)
CREATE INDEX idx_posts_user_id ON posts (user_id);

INSERT IGNORE INTO _schema_migrations (version, checksum)
  VALUES ('001_init', SHA2('001_init', 256));

COMMIT;
```

---

## Reviewer-Checklist

- `ENGINE=InnoDB` fehlt auf neuer Tabelle → **Important** (`mysql/R01`).
- `utf8` / `utf8mb3` statt `utf8mb4` auf Tabelle oder Spalte → **Important** (`mysql/R02`; 3-Byte-Encoding, Emojis scheitern silently).
- Primary Key als `INT` ohne `UNSIGNED` oder als `SERIAL`-Alias → **Important** (`mysql/R03`; `SERIAL` = `BIGINT UNSIGNED AUTO_INCREMENT` in MariaDB, aber nicht in MySQL — explizit ausschreiben).
- `updated_at` mit Trigger statt `ON UPDATE CURRENT_TIMESTAMP` (unnötige Komplexität) → **Minor**.
- `SET sql_mode = …` in Migration entfernt `STRICT_TRANS_TABLES` → **Critical** (`mysql/R05`; verdeckt Daten-Integritätsprobleme).
- Bereits committete Migration editiert oder umnummeriert → **Critical**.
- `ALTER TABLE` in Migration ohne Marker-Schutz (könnte doppelt angewendet werden) → **Critical**.
- Fehlender Index auf FK-Spalte → **Important**.
- `DATETIME`-Spalten ohne explizite Timezone-Strategie in Server-Konfiguration → **Important** (MySQL/MariaDB speichert `DATETIME` ohne TZ; Deployments mit unterschiedlichem `time_zone` liefern inkonsistente Werte).

---

## Test-Approach

- Migration läuft sauber **und** idempotent (zweimal anwenden; zweiter Lauf per Marker-Check übersprungen).
- Verify: `SHOW CREATE TABLE <name>` zeigt `ENGINE=InnoDB` + `utf8mb4`.
- Smoke-INSERT mit Emoji (`🍺`) in VARCHAR-Spalte — muss ohne Error gespeichert und identisch zurückgeliefert werden.
- Verify `@@sql_mode` enthält `STRICT_TRANS_TABLES` nach Migration.
