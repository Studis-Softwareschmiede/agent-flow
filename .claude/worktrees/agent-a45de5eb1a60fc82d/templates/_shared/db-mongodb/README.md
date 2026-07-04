# db-mongodb — Compose-Fragment + Migration-Runner + Backup/Restore

Welle-2-Template für `profile.db_dialect: mongodb` (Spec
[`docs/architecture/db-subsystem.md`](../../../docs/architecture/db-subsystem.md) §5 + §6 + §7 + §16-R4).

## Inhalt

```
db-mongodb/
  compose.fragment.yml         # db + migrations Service-Blöcke (mongo:7)
  .env.db.example              # Vorlage für MONGO_INITDB_ROOT_* + MONGO_DB/HOST/PORT
  db_scripts/
    000_init_meta.js           # Marker-Collection _schema_migrations
    run-migrations.sh          # bash-Runner (mongosh-basiert)
  scripts/
    db-backup.sh               # mongodump --archive --gzip Wrapper
    db-restore.sh              # mongorestore --archive --gzip --drop Wrapper
```

## Wann wird das verwendet?

`/new-project` (mit `--db mongodb`) und `/adopt` (wenn die Detection-Heuristik
mongodb erkennt; Spec §2) hängen `compose.fragment.yml` ans Projekt-
`docker-compose.yml` und scaffolden `db_scripts/` aus den Vorlagen hier.
Der Wiring-Schritt selbst kommt in Welle 3 — die Templates liegen bereit,
werden aktuell aber noch von keinem Skill konsumiert.

## Wichtige Unterschiede zu den SQL-Dialekten

- **Migrations sind JavaScript, nicht SQL.** Datei-Endung `.js`, Inhalt =
  mongosh-Syntax (`db.createCollection(...)`, `db.x.createIndex(...)`).
  Der Runner ruft pro Datei `mongosh --file <datei>` auf.
- **Marker = Collection, nicht Tabelle.** `_schema_migrations` ist eine
  normale Collection; das Marker-Document hat die Form
  `{ _id: "<version>", applied_at: ISODate, checksum: "<sha256>" }`
  (Spec §4 + §16-R5 optional). `000_init_meta.js` legt sie idempotent
  via `getCollectionNames().includes('_schema_migrations')`-Guard an.
- **Idempotenz ist Pflicht, nicht Empfehlung.** Mongo-Migrationen sind
  **nicht atomar** über Statements hinweg (kein DDL-Rollback wie SQL).
  Bricht eine Migration auf halbem Weg, bleibt der State zwischen den
  Versionen — der Rerun muss sauber durchgehen. Konkrete Idiome stehen
  in [`knowledge/mongodb.md`](../../../knowledge/mongodb.md), insbesondere:
  - `mongo/R01` — `$jsonSchema`-Validator auf jeder App-Collection;
    `validationLevel: 'strict'`, `validationAction: 'error'`.
  - `mongo/R02` — Indexes als Code (in Migrationen), Compound-Reihenfolge
    nach **ESR-Regel** (Equality → Sort → Range).
  - `createCollection` mit `getCollectionNames().includes(...)`-Guard
    oder try/catch — wirft sonst bei Bestand.
  - `insertOne`/`insertMany` in Migrationen **nie** ohne Guard — Seed-
    Daten via `replaceOne({_id: ...}, doc, {upsert: true})`.

## mongosh-Sicherheit (keine Service-User-Credentials in db_scripts)

- Migrationen verwenden **keine** eingebetteten Credentials. Der Runner
  baut die Connection-URI aus `MONGO_INITDB_ROOT_*` + `MONGO_HOST`/`PORT`
  und reicht sie als ersten `mongosh`-Argument durch; in den `.js`-
  Dateien selbst stehen nur Schema/Index/Validator-Definitionen — kein
  `db.createUser()` mit Plaintext-Passwort.
- Wenn ein Projekt **Service-User pro App** anlegen will (z.B. read-only
  für Reporting), gehört das in eine eigene Migration; das Passwort wird
  aus `process.env`/`getEnv()` gezogen, nicht hardkodiert. (mongosh
  unterstützt seit 1.5 `process.env.X` und `--eval` mit shell-substitution.)
- `MONGO_INITDB_ROOT_*` wirkt nur beim **allerersten** Container-Start
  (initdb-Phase, mongo:7-Image-Konvention). Spätere Passwort-Wechsel
  müssen via `db.changeUserPassword()` in admin-DB erfolgen.

## Backup-Strategie (mongodump archive format)

```
./scripts/db-backup.sh                                  # default: ./backups/db-<UTC>.archive.gz
./scripts/db-backup.sh /tmp/foo.archive.gz              # expliziter Pfad
./scripts/db-restore.sh ./backups/db-...archive.gz      # interaktive Bestätigung
FORCE=1 ./scripts/db-restore.sh ./backups/db-...archive.gz   # CI/Skript-Modus
```

- **`--archive --gzip`** statt Verzeichnis-Dump: single-file, streambar
  über `docker compose exec` stdout, kleiner, restore-symmetrisch.
- **`mongorestore --drop`** löscht jede Collection vor dem Restore, um
  einen sauberen Zustand zu garantieren. Daher die Pflicht-Bestätigung
  (DB-Name typen) wenn die Ziel-DB nicht-leer ist (Spec §7: „kein silent
  destroy").
- Auto-Backup-Cron ist **nicht** im Default-Scaffold (Spec §7 Brewing-
  Erfahrung: Backup-Strategie ist projekt-spezifisch). Die Skripte sind
  manuelle Vorlagen.

## Verweise

- Architektur-Spec: [`docs/architecture/db-subsystem.md`](../../../docs/architecture/db-subsystem.md)
  — insbesondere §4 (Migrations-Konvention), §5 (Compose), §6 (Runner),
  §7 (Backup), §16-R4 (separates migrations-Image), §16-R5 (checksum).
- Knowledge-Pack: [`knowledge/mongodb.md`](../../../knowledge/mongodb.md)
  — `$jsonSchema`-Validation (`mongo/R01`), ESR-Indexes (`mongo/R02`),
  Aggregation statt App-side-Joins (`mongo/R03`), Connection-Pool
  (`mongo/R04`), Multi-Doc-Transaktionen nur für echte Atomizität
  (`mongo/R05`), Beispiel-Migration mit Validator + ESR-Index.
- DBA-Agent: [`agents/dba.md`](../../../agents/dba.md) — dialekt-switch +
  Review-Modus.
