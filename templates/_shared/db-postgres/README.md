# Template — `db-postgres`

Welle-2-Template-Satz fürs DB-Subsystem (Spec [`db-subsystem.md`](../../../docs/architecture/db-subsystem.md) §5 + §6 + §7 + §16-R4 + §16-R5).

## Inhalt

| Datei | Zweck |
|---|---|
| `compose.fragment.yml` | Docker-Compose-Snippet (services `db` + `migrations` + volume `db_data`) — beim Scaffold ans Projekt-`docker-compose.yml` angehängt. |
| `.env.db.example` | Vorlage für die DB-spezifischen env-Variablen (POSTGRES_USER/PASSWORD/DB/PGDATA). |
| `db_scripts/run-migrations.sh` | Migration-Runner: läuft im one-shot `migrations`-Container, applied `db_scripts/<NNN>_*.sql` numerisch, schreibt Marker + Checksum. |
| `db_scripts/000_init_meta.sql` | Erste Migration: legt Marker-Tabelle `_schema_migrations` an (idempotent). |
| `scripts/db-backup.sh` | Ad-hoc-Backup via `docker compose exec db pg_dump -Fc` (custom format, intern komprimiert) → `.dump`. |
| `scripts/db-restore.sh` | Restore eines `.dump`-Files via `pg_restore --clean --if-exists`; verlangt interaktiv den DB-Namen als Bestätigung (`--force` zum Skippen). |

## Verwendung

**Automatisch** beim Scaffold via `/new-project --db postgres` oder `/agent-flow:adopt` mit Detection `db_dialect=postgres` (Spec §10 / §9). Die Wiring-Welle 3 kopiert das Fragment, hängt es an `docker-compose.yml`, legt `db_scripts/` + `scripts/` an und schreibt `profile.db_dialect: postgres`.

**Migration-Workflow:**

```bash
# 1. neue Migration anlegen
$EDITOR db_scripts/001_init.sql
# 2. Compose anwerfen — `migrations`-Service applied alles Neue automatisch
docker compose up -d db
docker compose up migrations  # one-shot; wartet auf db: service_healthy
# 3. App starten
docker compose up -d app
```

**Backup/Restore:**

```bash
./scripts/db-backup.sh                          # → backups/db-<UTC>.dump (pg_dump -Fc)
./scripts/db-backup.sh path/to/custom.dump      # expliziter Pfad
./scripts/db-restore.sh backups/db-<UTC>.dump   # fragt nach DB-Namen zur Bestätigung
./scripts/db-restore.sh backup.dump --force     # skip-confirmation (CI / Smoke)
```

## Konventionen (Spec-Referenz)

- Migrationen forward-only + 3-stellig nullgepaddet (§4).
- Marker-Tabelle `public._schema_migrations(version, applied_at, checksum)` — `checksum` optional, hier aktiv für Drift-Detection (§16-R5).
- Migrationen laufen im separaten `migrations`-Image (`postgres:17-alpine`), NICHT im App-Container (§16-R4).
- Compose-Pflichten: `restart: unless-stopped`, healthcheck (`pg_isready`), benanntes Volume, kein hartkodiertes Passwort (§5).
- Production: Port-Mapping aus `compose.fragment.yml` ENTFERNEN (§15-R7).

Pack-Regeln & RLS-Idiome: siehe [`knowledge/sql.md`](../../../knowledge/sql.md).
