# `db-mysql` — Template-Set für `profile.db_dialect: mysql`

> **Welle 2** des DB-Subsystems (siehe `docs/architecture/db-subsystem.md` §5–§7).
> Geliefert wird ein Compose-Fragment, der Migration-Runner und Backup/Restore-Skripte.
> Knowledge-Pack (Coder/Reviewer/Tester-Idiome) lebt in [`knowledge/sql-mysql.md`](../../../knowledge/sql-mysql.md).

---

## Engine: warum MariaDB statt MySQL

| Aspekt | Entscheid |
|---|---|
| Image | `mariadb:11` (LTS) |
| Wire-Protokoll | 100% kompatibel zu MySQL-Clients (`mariadb` ≡ `mysql`, `mariadb-dump` ≡ `mysqldump`, JDBC/ODBC interchangeable) |
| Lizenz | GPLv2 — kein Oracle-Lizenz-Risiko, keine OCI-Tracking-Klauseln |
| Drift | Knowledge-Pack `knowledge/sql-mysql.md` deckt beide explizit ab (Regeln `mysql/R01`–`R05` gelten für MySQL 8.0/8.4 LTS und MariaDB 11 LTS) |

Wer zwingend Oracle-MySQL braucht: das Fragment funktioniert mit `image: mysql:8.4` 1:1, nur der Healthcheck-Befehl wechselt von `healthcheck.sh --connect --innodb_initialized` auf `mysqladmin ping`. **Pin auf eine konkrete Version (`8.4`), nie floating `mysql:8`** — der Major-Tag driftet (8.0→8.4) und kann die Engine-Erkennung neuerer Migrationstools brechen.

> **Dialekt↔Engine↔Treiber↔Migrationstool-Modul müssen konsistent sein.** Die Wire-Protokoll-Kompatibilität (Zeile oben) verleitet zur Annahme „JDBC/Treiber sind interchangeable" — das gilt **nicht durchgängig** für moderne Migrationstools. Flyway 10 z.B. erkennt MariaDB vs. MySQL strenger als 9.x und lehnt einen MySQL-Connector gegen einen MariaDB-Server ab (Detail: `knowledge/migration/flyway-10.md §B/B01`). Wenn `profile.db_dialect: mysql` real gegen die hier deployte **MariaDB** läuft, muss das **bewusst & konsistent** sein: passender JDBC-Treiber UND passendes `flyway-database-<dialect>`-Modul zur **tatsächlich laufenden** Engine. Querverweis Runtime-Verify-Pflicht: `docs/architecture/upgrade-subsystem.md §17`.

---

## Inhalt

```
templates/_shared/db-mysql/
  README.md
  compose.fragment.yml         # services.db + services.migrations + named-volume
  .env.db.example              # Credential-Vorlage (cp → .env.db, NIE committen)
  db_scripts/
    000_init_meta.sql          # _schema_migrations (Marker-Tabelle)
    run-migrations.sh          # Idempotenter Runner (Spec §6 mysql-Dialekt)
  scripts/
    db-backup.sh               # mariadb-dump --single-transaction --quick > backup.sql
    db-restore.sh              # docker compose exec db mariadb < backup.sql
```

---

## Quickstart

```bash
# 1. Compose-Fragment ans Projekt-docker-compose.yml hängen
cat templates/_shared/db-mysql/compose.fragment.yml >> docker-compose.yml

# 2. Migrations-Skripte ins Projekt-Repo kopieren
mkdir -p db_scripts scripts
cp templates/_shared/db-mysql/db_scripts/000_init_meta.sql db_scripts/
cp templates/_shared/db-mysql/db_scripts/run-migrations.sh db_scripts/
cp templates/_shared/db-mysql/scripts/db-backup.sh         scripts/
cp templates/_shared/db-mysql/scripts/db-restore.sh        scripts/
cp templates/_shared/db-mysql/.env.db.example              .env.db.example

# 3. Lokale .env.db erstellen (Plaintext, gitignored!)
cp .env.db.example .env.db
$EDITOR .env.db    # MARIADB_PASSWORD + MARIADB_ROOT_PASSWORD echte Werte setzen

# 4. .gitignore ergänzen
printf '\n.env.db\nbackups/\n' >> .gitignore

# 5. Stack hochfahren — Migrations laufen automatisch (depends_on: db healthy)
docker compose up -d db
docker compose run --rm migrations

# 6. App-Migrations hinzufügen — Beispiel:
cat > db_scripts/001_create_users.sql <<'SQL'
CREATE TABLE IF NOT EXISTS users (
  id         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  email      VARCHAR(320)    NOT NULL,
  created_at TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_users_email (email)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
SQL
docker compose run --rm migrations
```

---

## Migration-Runner

`db_scripts/run-migrations.sh` (Spec §6 + `knowledge/sql-mysql.md`):

1. Wartet bis zu 60 s auf den DB-Service (`mariadb-admin ping`).
2. Stellt `_schema_migrations` sicher (`CREATE TABLE IF NOT EXISTS`, Schema gemäß §4 mysql-Dialekt + optionale `checksum`-Spalte gemäß §16-R5).
3. Iteriert `db_scripts/[0-9][0-9][0-9]_*.sql` in lexikographischer (= numerischer) Reihenfolge.
4. Pro Datei:
   - SHA-256 berechnen.
   - Bereits angewandt? → wenn gespeicherter Checksum ≠ aktueller → **Drift-Abort** (Forward-only-Verletzung, Spec §4). Sonst skip.
   - Sonst: `BEGIN; <sql>; INSERT INTO _schema_migrations …; COMMIT;` als ein Batch.
5. Klare Logs (`[migrations] Applying NNN_name (sha256=abcd…)`).

**Wichtig — MariaDB-DDL ist meist nicht-transaktional.** Statements wie `CREATE TABLE`, `ALTER TABLE`, `DROP` triggern ein implizites `COMMIT` und können nicht zurückgerollt werden. Der `BEGIN/COMMIT`-Wrap wird trotzdem geschrieben, weil:

- DML-Anteile (`INSERT`, `UPDATE`, `DELETE`) bleiben transaktional.
- Der Marker-`INSERT` läuft im selben Statement-Batch.
- Bei reinen DDL-Migrationen ist der Wrap effektiv ein No-op — die Marker-Tabelle bleibt **die einzige verlässliche Schutzschicht** gegen Doppel-Apply (`mysql/R01`-Idempotenz-Regel).

**Konsequenz für Migration-Autoren.** DDL und DML in derselben Migration mischen ist riskant: kracht das DML nach einem DDL, ist das Schema bereits geändert. Empfehlung: DDL und DML in getrennte, aufeinanderfolgende Migrationsdateien aufteilen.

---

## Backup / Restore

| Skript | Was | Ausgabe |
|---|---|---|
| `scripts/db-backup.sh` | `mariadb-dump --single-transaction --quick --routines --triggers > backup.sql` | `backups/db-YYYYMMDD-HHMMSS.sql` |
| `scripts/db-restore.sh <file>` | `docker compose exec -T db mariadb < backup.sql` mit Empty-DB-Check + interaktiver Bestätigung (oder `--force`) | restored in `$MARIADB_DATABASE` |

Beide Skripte:

- lesen Credentials aus den `MARIADB_*`-Env-Variablen (kein hartkodiertes Passwort),
- verwenden `--defaults-extra-file` oder `MYSQL_PWD`-Env — **niemals** Plaintext in `argv` (sichtbar im Prozess-Listing),
- `db-restore.sh` druckt **vor** dem Apply eine Warnung und verlangt die DB-Name als Bestätigung (Spec §7 Security-Floor), `--force` umgeht den Prompt für scripted Restores.

**Format:** Plain SQL gemäss Spec §7 verbatim (`mysqldump … > backup.sql` / `mysql … < backup.sql`).
Kein automatischer gzip-Wrapper — getrennte Verantwortlichkeit von dump und compression.
Für Archivierung lokal manuell `gzip backups/*.sql` aufrufen; vor dem Restore entsprechend `gunzip backups/db-*.sql.gz`.

---

## Konventionen (Reviewer-Pflicht)

Aus `knowledge/sql-mysql.md`:

- `mysql/R01` — `ENGINE=InnoDB` explizit auf jeder neuen Tabelle.
- `mysql/R02` — `CHARSET utf8mb4 COLLATE utf8mb4_unicode_ci` explizit.
- `mysql/R03` — Primary Keys als `BIGINT UNSIGNED NOT NULL AUTO_INCREMENT`.
- `mysql/R04` — `updated_at` über `ON UPDATE CURRENT_TIMESTAMP`, nicht Trigger.
- `mysql/R05` — `SET sql_mode = …` in Migrationen verboten (verdeckt Daten-Integritätsprobleme).

Bezüglich Migrations:

- **Forward-only.** Eine committete `NNN_*.sql` wird NIE editiert; der Runner erkennt Drift via SHA-256 und bricht ab.
- `CREATE INDEX IF NOT EXISTS` ist in MySQL **nicht** verfügbar (MariaDB schon, versions-abhängig) → die Marker-Tabelle ist die alleinige Schutzschicht.
- **Dialekt-Konsistenz (Critical).** `db_dialect`/JDBC-Treiber/Migrationstool-Dialekt-Modul müssen zur **real laufenden** Engine passen (`mysql`-Connector gegen MariaDB-Server ist bei Flyway 10 ein Boot-Fehler, nicht nur ein Warning). DB-Image auf konkrete Version pinnen, nie floating Major-Tag.
- `DATETIME` ohne Timezone (MySQL/MariaDB können kein `TIMESTAMPTZ`) — Server-`time_zone` global auf `+00:00` setzen, App stellt um.

---

## Production-Hinweise (Spec §15-R7)

- `ports:` im `compose.fragment.yml` ist NUR für Preview/Dev. In Production **entfernen** — DB darf nicht direkt nach außen mappen, nur intern erreichbar.
- `.env.db` enthält Plaintext-Credentials → niemals committen. Production-Stack injiziert per `sops`, `.env.gpg`, Docker-Secrets oder K8s-Secret.
- Backup-Auto-Run ist **nicht** Teil dieses Template-Sets (Spec §7). Cron + Off-Site-Storage sind projektspezifisch.
