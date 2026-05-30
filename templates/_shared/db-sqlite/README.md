# `db-sqlite` Template — File-DB pattern (no compose service)

SQLite-Template-Satz für die Softwareschmiede (Spec §5 SQLite-Sonderfall, §16-R4).
SQLite ist **file-based**: kein DB-Server, kein eigener Compose-Service —
nur ein geteiltes Volume und ein einmaliger `migrations`-Container.

---

## WARNUNG — SQLite skaliert NICHT horizontal

> **SQLite skaliert NICHT horizontal: das gesamte File ist Single-Writer
> (Whole-Database-Lock). Zur Laufzeit kann immer nur ein Prozess schreiben —
> die Engine erzwingt einen exklusiven Lock auf Datei-Ebene. Multi-Replica-
> Deployments (z.B. 2+ App-Container, Kubernetes-Pod-Replicas, Load-Balancer
> mit mehreren Backends, docker-compose `scale: N`) verursachen stillen
> Datenverlust oder Korruption, weil mehrere Instanzen das gleiche Volume-File
> gleichzeitig beschreiben.** Wenn das Projekt Multi-Replica braucht →
> **Postgres oder MySQL** stattdessen wählen.

Quelle: [sqlite.org/whentouse.html — „Many concurrent writers"](https://www.sqlite.org/whentouse.html) ·
[sqlite.org/lockingv3.html — Exclusive Lock](https://www.sqlite.org/lockingv3.html)

Pack-Regel `sqlite/R01` (`knowledge/sql-sqlite.md`): Items mit Deployment-Pattern
Multi-Replica und `profile.db_dialect: sqlite` MÜSSEN als **Critical** geflaggt werden.

---

## Wann SQLite passt

- Kleines internes Tool oder CLI mit eingebettetem State.
- Single-User / Single-Tenant App, ein Prozess, niedrige bis mittlere
  Concurrency (viele Reader, wenige Writer → WAL passt).
- Demos, Smoke-Apps, Single-Binary-Distributionen (Spec §1, P1-Dialekt für
  „CLI-Tools, Demos, single-binary Apps").
- Wenn `pg_dump`/Server-Operations Overhead nicht gerechtfertigt sind.

**Nicht** geeignet: Web-App mit horizontaler Skalierung, Multi-Tenant-SaaS
mit Concurrent-Writes, oder alles, was später nach Kubernetes-Replicas
verlangen könnte.

---

## File-Lokation + Volume-Mount-Pattern

- DB-Datei lebt in einem **named Volume** `db_data`, gemountet als
  `/data` in jedem Container, der darauf zugreifen muss.
- Default-Pfad: `DB_PATH=/data/app.db` (siehe `.env.db.example`).
- Sowohl der einmalige `migrations`-Container ALS AUCH der App-Container
  müssen `db_data:/data` mounten + `DB_PATH` als Env setzen. Sonst sieht
  die App keine Daten oder arbeitet auf einer anderen Datei.

App-Compose-Snippet (vom Projekt-Compose zu ergänzen):

```yaml
services:
  app:
    depends_on:
      migrations:
        condition: service_completed_successfully
    environment:
      DB_PATH: ${DB_PATH:-/data/app.db}
    volumes:
      - db_data:/data
```

WAL-Sidecars (`app.db-wal`, `app.db-shm`) liegen automatisch neben der
Hauptdatei im selben Volume — die müssen mitkopiert werden, wenn man das
Volume klont (nicht aber, wenn man via `db-backup.sh` arbeitet, das macht
vorher `wal_checkpoint(TRUNCATE)`).

---

## Migration-Workflow (gleich wie postgres/mysql, Spec §4)

Verzeichnis: `db_scripts/`, 3-stellig nullgepaddet, lückenlos, **forward-only**.

```
db_scripts/
  000_init_meta.sql          # PRAGMAs + _schema_migrations (mitgeliefert)
  001_init.sql               # erstes App-Schema (Projekt-spezifisch)
  002_add_users_table.sql
  …
  run-migrations.sh          # vom Template kopiert
```

Bereits committete Migrationen werden **nie editiert** — Korrekturen kommen
als neue höhere Nummer. Der Runner schreibt einen SHA-256-Checksum in
`_schema_migrations.checksum` (Spec §16-R5) und bricht bei Drift hart ab.

Idempotenz-Pflicht (sqlite/R06):

- `CREATE TABLE IF NOT EXISTS`, `CREATE INDEX IF NOT EXISTS`.
- ALTER ist in SQLite stark eingeschränkt → bei Schema-Änderungen jenseits
  von `ADD COLUMN`/`DROP COLUMN`/`RENAME` den Table-Rebuild-Pattern
  verwenden (sqlite/R05; `knowledge/sql-sqlite.md`).
- `PRAGMA foreign_keys = ON;` (R02) muss zusätzlich im App-Code beim
  Connect gesetzt werden (per-connection, nicht persistent).
- Neue Tabellen mit `STRICT` (R04).

Lauf:

```bash
docker compose up migrations          # one-shot, exited 0 = ok
# danach App starten:
docker compose up -d app
```

Der Runner ist idempotent: zweimal aufrufen → der zweite Lauf wendet
nichts mehr an (Marker filtert).

---

## Backup = File-Copy (mit WAL-Checkpoint!)

```bash
./scripts/db-backup.sh                  # → ./backups/db-YYYYMMDD-HHMMSS.sqlite
./scripts/db-backup.sh /pfad/zum/ziel   # → /pfad/zum/ziel/db-YYYYMMDD-HHMMSS.sqlite
```

Warum nicht nackter `cp`? Im WAL-Modus liegen jüngste Writes in der
`<db>-wal`-Sidecar-Datei. `db-backup.sh` ruft vor dem Copy
`PRAGMA wal_checkpoint(TRUNCATE)` auf → WAL ist nach dem Checkpoint leer,
Hauptdatei ist konsistent. Plain `cp` ohne Checkpoint riskiert Datenverlust
(Reviewer-Checklist `knowledge/sql-sqlite.md`).

Restore:

```bash
./scripts/db-restore.sh ./backups/db-20260530-101500.sqlite
```

Stoppt den App-Container, überschreibt die DB-Datei im Volume, entfernt
verwaiste WAL/SHM-Sidecars, validiert via `PRAGMA integrity_check`,
startet die App neu. Fragt vor dem Apply nach dem Projektnamen zur
Bestätigung (kein silent destroy).

---

## Inhalt dieses Templates

| Datei | Zweck |
|---|---|
| `compose.fragment.yml` | `migrations`-Service (Alpine + sqlite-CLI) + `db_data`-Volume |
| `.env.db.example` | `DB_PATH=/data/app.db` (keine Credentials) |
| `db_scripts/000_init_meta.sql` | PRAGMAs (WAL, FK) + `_schema_migrations` STRICT-Table |
| `db_scripts/run-migrations.sh` | Forward-only Runner mit SHA-256 Drift-Detection |
| `scripts/db-backup.sh` | WAL-Checkpoint + File-Copy auf Host |
| `scripts/db-restore.sh` | App stoppen → Volume überschreiben → integrity_check → starten |
| `README.md` | Diese Datei |

Wiring durch das Plugin (Welle 3): `/new-project --db sqlite` hängt das
Compose-Fragment ans Projekt-`docker-compose.yml`, kopiert `db_scripts/`
+ `scripts/`, und scaffoldet `docs/data-model.md`.

---

## Referenzen

- Spec: `docs/architecture/db-subsystem.md` §5 (SQLite-Sonderfall), §6 (Runner-Pattern),
  §7 (Backup/Restore), §16-R4 (separates migrations-Image), §16-R5 (checksum).
- Knowledge-Pack: `knowledge/sql-sqlite.md` (R01 Multi-Replica-Hard-Stop,
  R02 foreign_keys, R03 WAL, R04 STRICT, R05 ALTER-Einschränkungen,
  R06 Migrations-Konvention).
