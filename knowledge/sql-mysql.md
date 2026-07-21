# MySQL / MariaDB Knowledge Pack — pluggable DB-Subsystem (Spec §3)

> **Dialekt:** `mysql` (`profile.db_dialect: mysql`). Engine target: **MariaDB 11.8 LTS** (preferred FOSS path, supersedes 11.4 as of GA 2025-06-04) and **MySQL 8.0 / 8.4 LTS** (compatible).
> See also: Postgres-Pack → `knowledge/sql.md` | SQLite-Pack → `knowledge/sql-sqlite.md` | other dialects → `knowledge/`.
> Regel-IDs: `mysql/R<NN>`.

---

## Coder-Guidance

- `mysql/R01` — **`ENGINE=InnoDB` explizit** auf jeder neuen Tabelle setzen (`CREATE TABLE … ENGINE=InnoDB`). InnoDB ist zwar der Default in MySQL 8.0 und MariaDB 11, aber `NO_ENGINE_SUBSTITUTION` (Teil des MySQL-8.0-Default-SQL-Mode) erlaubt der Engine still zu substituieren, falls ein anderes Storage-Plugin aktiv ist. Explizite Angabe macht die Absicht dokumenten-sicher und verhindert unerwartete Substitution in Deployments mit abweichender Konfiguration. Quelle: [MySQL 8.0 §16.1 Setting the Storage Engine](https://dev.mysql.com/doc/refman/8.0/en/storage-engine-setting.html) · [MySQL 8.0 §17.1 InnoDB Introduction](https://dev.mysql.com/doc/refman/8.0/en/innodb-introduction.html)

- `mysql/R02` — **`CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci`** explizit auf jeder neuen Tabelle (und bei Bedarf auf Spalten) setzen. `utf8` / `utf8mb3` ist **deprecated seit MySQL 8.0** (alias für 3-Byte-Encoding, das supplementäre Zeichen inkl. Emojis nicht speichern kann) und wird in einem zukünftigen Major-Release entfernt. MySQL 8.0 default-collation `utf8mb4_0900_ai_ci` und MariaDB-11.6+-Default `utf8mb4_uca1400_ai_ci` unterscheiden sich — explizit `utf8mb4_unicode_ci` setzen gewährleistet portables Verhalten über beide Engines. Quelle: [MySQL 8.0 §12.9.1 utf8mb4](https://dev.mysql.com/doc/refman/8.0/en/charset-unicode-utf8mb4.html) · [MySQL 8.0 §12.9.2 utf8mb3 deprecated](https://dev.mysql.com/doc/refman/8.0/en/charset-unicode-utf8mb3.html) · [MariaDB Character Set Overview](https://mariadb.com/docs/server/reference/data-types/string-data-types/character-sets/character-set-and-collation-overview)

- `mysql/R03` — **Primary Keys: `BIGINT UNSIGNED NOT NULL AUTO_INCREMENT`**. `INT` läuft bei ~2,1 Mrd. Rows über; `BIGINT UNSIGNED` trägt ~18,4 × 10¹⁸ Werte. MySQL-spezifisch: `AUTO_INCREMENT`-Attribut (kein `SERIAL`-Alias wie Postgres); Spalte muss indiziert sein (PRIMARY KEY genügt). Quelle: [MySQL 8.0 §5.6.9 Using AUTO_INCREMENT](https://dev.mysql.com/doc/refman/8.0/en/example-auto-increment.html)

- `mysql/R04` — **`updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP`** für automatisch aktualisierte Zeitstempel-Spalten verwenden. Das `ON UPDATE CURRENT_TIMESTAMP`-Attribut ist MySQL/MariaDB-spezifisch (kein Standard-SQL); es aktualisiert die Spalte beim `UPDATE` automatisch auf den aktuellen Server-Zeitstempel — ohne Trigger. Quelle: [MySQL 8.0 §13.2.5 Automatic Initialization and Updating for TIMESTAMP](https://dev.mysql.com/doc/refman/8.0/en/timestamp-initialization.html) · [MariaDB TIMESTAMP Docs](https://mariadb.com/docs/server/reference/data-types/date-and-time-data-types/timestamp)

- `mysql/R05` — **SQL_MODE `STRICT_TRANS_TABLES` nie deaktivieren.** `STRICT_TRANS_TABLES` ist in MySQL 8.0 standardmäßig aktiv und verhindert silent type-coercion (z.B. leere Strings statt NULL, gekürzte Strings). Für MariaDB: prüfe den effektiven Default via `SELECT @@global.sql_mode;` — der Wert ist versionsabhängig und nicht per öffentlichem Curl-Fetch verifizierbar. Migrations oder App-Code dürfen `SET sql_mode = …` nicht nutzen, um Strict Mode zu umgehen — das versteckt Daten-Integritätsprobleme. Quelle: [MySQL 8.0 §7.1.11 Server SQL Modes](https://dev.mysql.com/doc/refman/8.0/en/sql-mode.html)

- `mysql/R06` — **`mysql_native_password` ist in MySQL 8.4 per Default deaktiviert und in MySQL 9.0 vollständig entfernt.** Migriere alle User-Accounts auf `caching_sha2_password` (seit MySQL 8.0 Standard-Default). Timeline: deprecated MySQL 8.0.34 → disabled-by-default MySQL 8.4 (`--mysql-native-password=OFF`; kann temporär mit `--mysql-native-password=ON` re-enabled werden) → **removed MySQL 9.0.0** (kein Re-Enable mehr möglich). Achtung für Connector-Kompatibilität: `caching_sha2_password` verlangt entweder eine TLS-gesicherte Verbindung oder eine unverschlüsselte Verbindung mit RSA-Key-Exchange (`--get-server-public-key` / `--server-public-key-path` client-seitig). MariaDB 11 verwendet weiterhin `mysql_native_password` als Default und ist nicht betroffen. Quelle: [MySQL 8.4 §8.4.1.1 Native Pluggable Authentication](https://dev.mysql.com/doc/refman/8.4/en/native-pluggable-authentication.html) · [MySQL 8.4 §8.4.1.1 Caching SHA-2 Pluggable Authentication](https://dev.mysql.com/doc/refman/8.4/en/caching-sha2-pluggable-authentication.html) · [MySQL 9.0 Release Notes](https://dev.mysql.com/doc/relnotes/mysql/9.0/en/news-9-0-0.html)

- `mysql/R07` — **MariaDB 11.4 LTS (GA Mai 2024): SSL/TLS ist per Default aktiv.** Der Server generiert beim Start automatisch ein selbst-signiertes Zertifikat; ab MariaDB 11.4 erfordert der `mariadb`-Client TLS-Verbindungen + Cert-Verifikation per Default. Praktische Fallen: (a) Docker-Compose-Setups mit `mariadb:11` (≥11.4) müssen Container-interne Verbindungen (z.B. der `migrations`-one-shot-Service) explizit handhaben — entweder mit `--disable-ssl` (intern-vertrauenswürdig) oder indem die Cert-Verifikation deaktiviert wird (`--disable-ssl-verify-server-cert`); (b) Anwendungs-Connectoren (JDBC, mysql2, PyMySQL, usw.) müssen für 11.4+-Ziele entsprechend konfiguriert sein. Alternativ kann der Server-seitig mit `--disable-ssl` gestartet werden (nur für interne/lokale Deployments). Quelle: [MariaDB 11.4 Changes & Improvements](https://mariadb.com/docs/release-notes/community-server/11.4/what-is-mariadb-114) · [MariaDB Securing Connections](https://mariadb.com/docs/server/security/encryption/data-in-transit-encryption/securing-connections-for-client-and-server)

- `mysql/R08` — **MariaDB 11.4: `tx_isolation` und `tx_read_only` sind deprecated** — verwende stattdessen `transaction_isolation` und `transaction_read_only`. In MariaDB 11.4 sind die alten Variablennamen noch als deprecated Aliases vorhanden, werden aber in einem zukünftigen Release entfernt. Betroffen: `my.cnf`-Einträge, Verbindungs-String-Parameter (z.B. JDBC `sessionVariables=transaction_isolation=READ-COMMITTED`) und explizite `SET tx_isolation = …`-Statements in Migrations oder App-Code. Quelle: [Upgrading from MariaDB 10.11 to MariaDB 11.4](https://mariadb.com/docs/server/server-management/install-and-upgrade-mariadb/upgrading/mariadb-community-server-upgrade-paths/upgrading-from-mariadb-10-11-to-mariadb-11-4) · [MariaDB SET TRANSACTION](https://mariadb.com/docs/server/reference/sql-statements/administrative-sql-statements/set-commands/set-transaction)

- `mysql/R09` — **MariaDB 11.8 ist die aktuelle LTS-Version** (GA 2025-06-04, maintained bis Juni 2028) und löst 11.4 als bevorzugtes FOSS-Ziel ab — 11.8 enthält kumulativ alle Änderungen aus 11.5–11.7 (u.a. R08's `transaction_isolation`-Rename ist bereits enthalten). Neue Projekte sollten `mariadb:11.8` statt `mariadb:11.4` als Basis-Image-Tag verwenden; bestehende 11.4-Deployments bleiben bis zu ihrem eigenen EOL unterstützt (kein sofortiger Migrationszwang). Quelle: [MariaDB 11.8 Changes & Improvements](https://mariadb.com/docs/release-notes/community-server/11.8/what-is-mariadb-118) („MariaDB 11.8 is a long-term release, maintained until June 2028")

- `mysql/R10` — **`TIMESTAMP`-Wertebereich ist dialekt-divergent seit MariaDB 11.5.** MariaDB ≥11.5 (64-Bit-Systeme) erweitert den `TIMESTAMP`-Bereich von `2038-01-19 03:14:07 UTC` auf `2106-02-07 06:28:15 UTC`; MySQL (8.0, 8.4, 9.x) sowie MariaDB <11.5 bleiben beim klassischen 32-Bit-Unix-Limit (`2038-01-19`). Portabler Code (beide Engines / ältere MariaDB-Instanzen) darf sich für Daten über 2038 hinaus **nicht** auf `TIMESTAMP` verlassen — `DATETIME` verwenden, wenn das Zieldatum potenziell über 2038 liegt (z.B. langlebige Scheduling-/Ablauf-Spalten) und nicht sichergestellt ist, dass ausschliesslich MariaDB ≥11.5 im Einsatz ist. Quelle: [MariaDB TIMESTAMP](https://mariadb.com/docs/server/reference/data-types/date-and-time-data-types/timestamp) („MariaDB stores values that use the TIMESTAMP data type as the number of seconds since '1970-01-01 00:00:00' (UTC). This means that the TIMESTAMP data type can hold values between '1970-01-01 00:00:01' (UTC) and '2106-02-07 06:28:15 UTC'" für ≥11.5, vs. „…and '2038-01-19 03:14:07' (UTC)" für ältere Versionen)

- `mysql/R11` — **`default_authentication_plugin` ist seit MySQL 8.4.0 vollständig entfernt** (deprecated bereits seit 8.0.27) — verwende stattdessen `authentication_policy`. Server-Configs (`my.cnf`) oder Startup-Skripte mit `default_authentication_plugin=…` starten auf MySQL 8.4+ nicht mehr (Variable existiert nicht mehr, kein stiller Fallback). Zusätzlich hat sich als Teil dieser Entfernung die Syntax von `authentication_policy` geändert. MariaDB ist nicht betroffen (eigene Variable `default_authentication_plugin` bleibt dort bestehen). Quelle: [MySQL 8.4 Reference Manual §1.4 What Is New in MySQL 8.4 since MySQL 8.0](https://dev.mysql.com/doc/refman/8.4/en/mysql-nutshell.html) („The default_authentication_plugin system variable, deprecated in MySQL 8.0.27, is removed as of MySQL 8.4.0. Use authentication_policy instead.")

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
- `CREATE INDEX` hat **kein** `IF NOT EXISTS` in MySQL (keiner Version — nicht in 8.0, nicht in 8.4; verifiziert via `curl https://dev.mysql.com/doc/refman/8.0/en/create-index.html | grep -i "IF NOT EXISTS"` → 0 Treffer). MariaDB dokumentiert `CREATE INDEX IF NOT EXISTS`, eine exakte Einführungsversion ist jedoch nicht per öffentlichem Curl-Fetch aus den MariaDB-Docs verifizierbar. Empfehlung: **Idempotenz für Indexes generell über den Marker steuern** (Marker-Tabelle als einzige Schutzschicht gegen Doppel-Apply) oder per explizitem Check: `SELECT COUNT(*) FROM INFORMATION_SCHEMA.STATISTICS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='...' AND INDEX_NAME='...'` vor dem `CREATE INDEX`.
- `ALTER TABLE` ist nicht idempotent — Migrationen mit `ALTER` ausschließlich per Marker steuern (nicht zweimal anwenden).
- Transaktion um jede Migration wrappen (`START TRANSACTION … COMMIT`); Rollback bei Fehler. DDL in MySQL/MariaDB ist **nicht** automatisch transaktional für metadata — dennoch explizit wrappen, weil DML-Teile der Migration transaktional sind.

**Compose-Service-Referenz** (Spec §5, Welle 2 — das vollständige Compose-Fragment inklusive Runner-Integration kommt in Welle 2):

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
- User-Account mit `mysql_native_password` auf MySQL 8.4+ → **Critical** (`mysql/R06`; Plugin disabled-by-default auf 8.4, removed auf 9.0 — Connector kann nicht mehr verbinden).
- Docker-Compose-Migrations-Service ohne SSL-Konfiguration gegen `mariadb:11` (≥11.4) → **Important** (`mysql/R07`; ab MariaDB 11.4 erfordert der `mariadb`-Client TLS + Cert-Verifikation per Default — interner Container-Connect schlägt ohne `--disable-ssl` oder `--disable-ssl-verify-server-cert` fehl).
- `SET tx_isolation = …` oder `tx_isolation` in `my.cnf`/Verbindungs-String auf MariaDB 11.4+ → **Minor** (`mysql/R08`; Variable deprecated, wird in künftigem Major entfernt — auf `transaction_isolation` migrieren).
- Neues Projekt pinnt `mariadb:11.4` (oder älter) statt `mariadb:11.8` als Basis-Image → **Minor** (`mysql/R09`; 11.8 ist die aktuelle LTS, kein sofortiger Zwang für bestehende Deployments).
- `TIMESTAMP`-Spalte für Daten/Ablaufzeiten, die potenziell über 2038 hinausreichen, ohne Absicherung auf MariaDB ≥11.5 → **Important** (`mysql/R10`; MySQL und ältere MariaDB kappen bei 2038 — `DATETIME` verwenden, wenn Portabilität/ältere Engine nicht ausgeschlossen ist).
- `default_authentication_plugin=…` in `my.cnf`/Startup-Config für ein MySQL-8.4+-Ziel → **Critical** (`mysql/R11`; Variable entfernt, Server startet nicht — auf `authentication_policy` migrieren).

---

## Test-Approach

- Migration läuft sauber **und** idempotent (zweimal anwenden; zweiter Lauf per Marker-Check übersprungen).
- Verify: `SHOW CREATE TABLE <name>` zeigt `ENGINE=InnoDB` + `utf8mb4`.
- Smoke-INSERT mit Emoji (`🍺`) in VARCHAR-Spalte — muss ohne Error gespeichert und identisch zurückgeliefert werden.
- Verify `@@sql_mode` enthält `STRICT_TRANS_TABLES` nach Migration.

## Spec-Tagging
Trace-Tag je gedecktem Kriterium gemäss `docs/architecture/traceability-subsystem.md`.
- **Kontext:** MySQL/MariaDB-Logik wird typischerweise via **App-Layer-Tests** geprüft (TS/Java — kein weit verbreiteter SQL-nativer TAP-Runner für MySQL/MariaDB). Der Trace-Tag sitzt im App-Layer-Test.
- **Idiom (App-Layer, TS/Java):** Token im `it()`/`test()`-Titel (Vitest/Jest) oder JUnit-`@Tag` wie im ts-/java-Pack: `it('@trace user-reg#AC1 — Email-Unique-Constraint wirft Fehler', …)`. DB-Verbindung via `mysql2`-Driver oder JDBC/Testcontainers; Token bleibt im App-Test.
- **Extraktions-Rezept:** Core-Regex `@trace\s+([a-z0-9][a-z0-9-]*)#((?:AC\d+|BR-\d+)(?:,(?:AC\d+|BR-\d+))*)` über App-Test-Titel (`grep -RoE` / `vitest list --json`).
- **Fallback:** kanonisches Token in der Test-Description; Core-Regex.
