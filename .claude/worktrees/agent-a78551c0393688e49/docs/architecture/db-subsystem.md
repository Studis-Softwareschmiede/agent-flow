# Architecture — DB-Subsystem (pluggable, multi-dialect)

> **Bindend.** Diese Spec beschreibt **wie** das `agent-flow`-Plugin Datenbanken behandelt: welche Dialekte unterstützt werden, wie Migrationen ablaufen, wie der DBA-Agent darauf reagiert und wie `/adopt`, `/new-project`, `/flow` und `/preview` damit verdrahtet sind. Implementierung erfolgt in drei Wellen (Knowledge → Templates → Wiring; §14). Abweichungen sind Review-Kriterium.

---

## 1. Zweck & Scope

**Zweck.** Bisher kennt das Plugin nur eine SQL-Domäne (`knowledge/sql.md`, Postgres-zentriert). Reale Projekte nutzen unterschiedliche DBs. Diese Spec macht den DB-Aspekt zur **erstklassigen, pluggable** Achse: ein expliziter Dialekt im Profil steuert Knowledge-Pack, Compose-Service, Migrations-Runner, Backup und DBA-Review.

**Unterstützte Dialekte (P1):**

| Dialekt | Engine | Begründung |
|---|---|---|
| `postgres` | PostgreSQL 17 | Default-OLTP, RLS, JSON-fähig; Supabase-Basis (Brewing-Erfahrung) |
| `mysql` | MariaDB 11 LTS | Faktischer FOSS-Pfad in MySQL-Welt (Oracle-frei); deckt MySQL-kompatible Apps |
| `sqlite` | SQLite 3 (file) | Embedded — entscheidend für CLI-Tools, Demos, single-binary Apps |
| `mongodb` | MongoDB 7 CE | Einziger relevanter Doc-Store im OSS-Mainstream (Mongoose-Ökosystem) |
| `none` | — | App ohne DB (statisch, CLI ohne Persistenz) — explizit als „none" deklariert |

**Out of Scope (P1).** Oracle, MSSQL (kommerzielle Tooling-Anforderungen — eigener Wellen-Schub bei Bedarf). Cloud-only-Dienste ohne lokal lauffähiges Image (DynamoDB, Spanner — `/preview up` würde brechen). Spezial-Stores (Cassandra, Redis-as-DB, Neo4j — kein Pack-Mass mass-market-Bedarf; Redis-als-Cache ist kein DB-Subsystem-Thema, sondern Infra-Dependency). Multi-Dialekt pro Projekt — **eine App = ein Dialekt**.

---

## 2. `profile.db_dialect`

Neues Pflichtfeld im `.claude/profile.md`. **Enum**, ohne Default beim Scaffold (muss gesetzt sein):

```
db_dialect: postgres | mysql | sqlite | mongodb | none
```

**Default beim `/new-project` ohne `--db`-Flag:** `none` (eine App ohne DB ist der safe minimal state — der User entscheidet später bewusst).

**Detection-Heuristik (`/adopt` und `/init`)** — erstes Match in dieser Reihenfolge gewinnt. Confidence-Stufen steuern, ob die Detection ohne Rückfrage übernommen werden darf (per Spec: **immer** Rückfrage, auch bei `high` — siehe §9):

| Signal | → `db_dialect` | Confidence |
|---|---|---|
| `package.json` deps: `mongoose`, `mongodb` | `mongodb` | high |
| `package.json` deps: `pg`, `postgres`, `pgvector`; `prisma` (mit `provider = "postgresql"`) | `postgres` | high |
| `package.json` deps: `mysql2`, `mysql`, `mariadb`; `prisma` (mit `provider = "mysql"`) | `mysql` | high |
| `package.json` deps: `better-sqlite3`, `sqlite3` | `sqlite` | high |
| `pubspec.yaml`: `postgres`, `supabase_flutter` | `postgres` | high |
| `pubspec.yaml`: `sqflite`, `drift`, `sembast_sqflite` | `sqlite` | high |
| `pom.xml`/`build.gradle`: `org.postgresql:postgresql` | `postgres` | high |
| `pom.xml`/`build.gradle`: `mysql:mysql-connector-j` ODER `mysql:mysql-connector-java` (legacy coords, pre-Mai-2023; immer noch sehr verbreitet in Bestand — B7-Fix), `org.mariadb.jdbc:mariadb-java-client` | `mysql` | high |
| `pom.xml`/`build.gradle`: `org.mongodb:mongodb-driver-sync`, `org.springframework.data:spring-data-mongodb` | `mongodb` | high |
| `requirements.txt`/`pyproject.toml`: `psycopg`, `psycopg2`, `asyncpg` | `postgres` | high |
| `requirements.txt`/`pyproject.toml`: `pymongo`, `motor` | `mongodb` | high |
| Compose-Service `image:` enthält `postgres`, `supabase/postgres`, `timescale`, `pgvector` | `postgres` | high |
| Compose-Service `image:` enthält `mariadb`, `mysql` | `mysql` | high |
| Compose-Service `image:` enthält `mongo` | `mongodb` | high |
| Compose-Healthcheck-String: `pg_isready` | `postgres` | medium |
| Compose-Healthcheck-String: `mongosh`, `mongo --eval` | `mongodb` | medium |
| Env-Refs (`.env*`, `*.yml`): `SUPABASE_URL`, `PG_*`, `POSTGRES_*`, `DATABASE_URL=postgres://` | `postgres` | medium |
| Env-Refs: `MYSQL_HOST`, `MARIADB_HOST`, `DATABASE_URL=mysql://` | `mysql` | medium |
| Env-Refs: `MONGO_URL`, `MONGODB_URI`, `DATABASE_URL=mongodb://` | `mongodb` | medium |
| File-Endung `*.sqlite`, `*.sqlite3`, `*.db` im Repo-Root oder `data/` | `sqlite` | medium |
| SQLite-CLI in Scripts (`sqlite3 path/to/file`) | `sqlite` | low |
| Verzeichnis `db_scripts/` mit `*.sql` und `CREATE TABLE` enthält `SERIAL`/`BIGSERIAL`/`uuid_generate_v4` | `postgres` | low |
| Verzeichnis `db_scripts/` mit `*.sql` und `AUTO_INCREMENT`/`ENGINE=InnoDB` | `mysql` | low |
| Verzeichnis `db_scripts/` mit `*.js` und `db.createCollection` | `mongodb` | low |
| sonst | **Frage stellen** (`AskUserQuestion` mit den 5 Enum-Werten) | — |

Diese Tabelle ist die **kanonische Signal-Palette** (Single Source of Truth) — `skills/adopt/SKILL.md` Schritt 2a spiegelt sie 1:1 wider und darf sie nicht silently erweitern. Neue Signale (etwa eine weitere Sprach-Toolchain wie Rust/`sqlx` oder Go/`pgx`) werden **zuerst hier** ergänzt; die Skill-Tabelle zieht im selben PR nach. Confidence-Stufen sind nicht-bindend für die Detection-Reihenfolge (die ist durch die Tabellen-Position fixiert), sondern Hinweis für Audit-Trail/Logs (welche Klasse von Signal hat gegriffen).

**Annahme (begründet):** Eine App = ein Dialekt. Polyglott (z.B. Postgres + Mongo) ist im OSS-SMB-Bereich selten; wenn nötig, kommt das in einer späteren Welle als `db_dialects: [postgres, mongodb]` Liste hinzu — explizit out-of-scope für P1, damit die Pack-Auswahl und Compose-Generierung deterministisch bleiben.

---

## 3. Knowledge-Pack-Struktur

**Bestand.** `knowledge/sql.md` (existiert) — bleibt **der Postgres-Pack**. Begründung: Inhalt ist heute schon PG17-spezifisch (`MERGE … RETURNING`, `JSON_TABLE`, Supabase-Hinweis), Umbenennung ist breaking für Bestandsprojekte (`profile.domains: [sql]`). Wir vermeiden die Migration und renamen nicht.

**Neu (Welle 1):**

```
knowledge/
  sql.md          # = Postgres-Pack (bestehend; Header-Kommentar klärt: „dialect = postgres")
  sql-mysql.md    # MySQL/MariaDB
  sql-sqlite.md   # SQLite 3
  mongodb.md      # Mongo (nicht „nosql.md" — Pack-Datei = konkrete Engine, kein Genre)
```

**Pack-Auswahl-Regel** (gilt für `dba`, `coder`, `reviewer`, `tester`):

```
profile.db_dialect = postgres → knowledge/sql.md
                   = mysql    → knowledge/sql-mysql.md
                   = sqlite   → knowledge/sql-sqlite.md
                   = mongodb  → knowledge/mongodb.md
                   = none     → kein DB-Pack laden
```

**Backwards-Compat.** `profile.domains: [sql]` (bestehende Projekte ohne `db_dialect`) wird vom Pack-Loader als `db_dialect=postgres` interpretiert (1 Zeile Fallback). `adopt`/`init` setzt `db_dialect` beim nächsten Lauf explizit.

**Pack-Aufbau** (unverändert pro Pack — `## Coder-Guidance` · `## Reviewer-Checklist` · `## Test-Approach`). Regel-IDs pro Pack-Namespace: `sql/R<NN>` (= postgres, bestehend), `mysql/R<NN>`, `sqlite/R<NN>`, `mongo/R<NN>`. Begründung: stabile IDs für das Observability-Ledger (§5a CONCEPT).

---

## 4. Migrations-Konvention

**Verzeichnis-Layout (alle Dialekte):**

```
<repo>/
  db_scripts/
    000_init_meta.sql         # postgres|mysql|sqlite (mongodb: .js)
    001_<name>.sql            # erste App-Migration (Projekt-spezifisch)
    002_<name>.sql
    003_<name>.js             # weitere Migrationen — mongodb nutzt .js (mongosh script)
    run-migrations.sh         # dialekt-spezifischer Wrapper (Welle 2)
```

**Annahme (begründet):** Verzeichnis-Name `db_scripts/` (nicht `migrations/`, nicht `db/migrations/`) — übernommen aus dem Brewing-Projekt (Konsistenz mit existierender Praxis im Umfeld; ein etablierter Begriff schlägt drei plausible Alternativen). Mongo-Dateien sind `.js` (mongosh-syntax); SQL-Dateien sind `.sql` — die Endung trägt den Dialekt nicht, der kommt aus `profile.db_dialect`.

**Nummerierung.** 3-stellig, nullgepaddet, lückenlos, **forward-only**. Eine bereits committete Migration wird **nie editiert** (`coder/R02` für DB-Domäne — wird in den Packs verankert); Korrekturen werden als neue, höhere Nummer angehängt.

**Apply-Tracking — Marker-Tabelle pro Dialekt:**

| Dialekt | Tabelle/Collection | Schema (Pflicht-Spalten) |
|---|---|---|
| postgres | `public._schema_migrations` | `(version text PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT now())` |
| mysql | `_schema_migrations` | `(version VARCHAR(255) PRIMARY KEY, applied_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP)` |
| sqlite | `_schema_migrations` | `(version TEXT PRIMARY KEY, applied_at TEXT NOT NULL DEFAULT (datetime('now')))` |
| mongodb | Collection `_schema_migrations` | Document `{ _id: "<version>", applied_at: ISODate }` |

**Annahme (begründet):** Marker-Name `_schema_migrations` (Unterstrich-Präfix; angelehnt an Rails/Sqitch-Tradition, signalisiert „internes Tooling"). Bewusst nicht der Flyway/Liquibase-Default — wir betreiben einen schlanken eigenen Runner (keine Java-Runtime im Postgres-/JS-Container).

**Optionale Drift-Detection-Spalte `checksum` (Standard-Empfehlung, Spec-konform auch ohne).** Dialekt-Packs **dürfen** die Marker-Tabelle um eine dritte Spalte erweitern:

| Dialekt | Spalte (optional) |
|---|---|
| postgres | `checksum TEXT NULL` |
| mysql | `checksum VARCHAR(128) NULL` |
| sqlite | `checksum TEXT NULL` |
| mongodb | Feld `checksum: <string \| null>` im Document |

Der Wert ist ein Hash (z.B. SHA-256) des Migration-File-Inhalts, beim Apply vom Runner geschrieben. Nutzen: ein erneuter Run vergleicht den Datei-Hash gegen den gespeicherten Wert und erkennt, wenn eine bereits-applied Migration nachträglich editiert wurde (Spec-Verstoß gegen „forward-only" oben) — der Runner bricht dann mit einer klaren Fehlermeldung ab statt still drüberzugehen. Optional, weil kleine Projekte/Demos den Wert nicht brauchen; die Spalte kostet aber praktisch nichts (ein nullable Text-Feld) und ist Industry-Standard (Liquibase, Flyway, Alembic).

**Spec-Konformität:** Implementierungen, die `checksum` NICHT führen, sind weiterhin Spec-konform. Die Spalte ist `NULL`-erlaubt, ihre Befüllung ist Sache des Migration-Runners (`db_scripts/run-migrations.sh`), nicht des App-Codes. Ein Pack-Loader oder Reviewer **darf nicht** das Fehlen der Spalte als Verstoß werten.

**SQLite-Sonderfall (geklärt):** Marker-Tabelle **funktioniert** — SQLite kann CREATE TABLE und Filter wie jeder SQL-Dialekt. Der Sonderfall ist nicht die Tabelle, sondern dass SQLite **kein Service** ist (eine Datei). Der Runner wird also nicht in einem DB-Container gestartet, sondern im **App-Container** ausgeführt (oder einem one-shot init-Container, der das Volume teilt).

**Idempotenz-Regeln pro Dialekt:**

- **postgres**: `CREATE TABLE IF NOT EXISTS`, `CREATE INDEX IF NOT EXISTS`, `CREATE OR REPLACE FUNCTION`, `DROP … IF EXISTS`. ALTER ist nicht idempotent — Migrationen, die ALTER nutzen, werden über den Marker geschützt (nur einmalig angewendet). Bestehende Regel `sql/R01` bleibt.
- **mysql**: gleiches Muster. `CREATE TABLE IF NOT EXISTS`, `CREATE INDEX` ist **nicht** `IF NOT EXISTS` (MySQL/MariaDB-Sprachsupport bröckelt versions-spezifisch) → Marker-Tabelle ist die alleinige Sicherung gegen Doppel-Apply. Neue Regel `mysql/R01`.
- **sqlite**: `CREATE TABLE IF NOT EXISTS`, `CREATE INDEX IF NOT EXISTS` (beides supported). Keine ALTER-Transaktion (SQLite ALTER ist beschränkt → ggf. table-rebuild-Pattern). Neue Regel `sqlite/R01`.
- **mongodb**: Operationen sind in der Regel idempotent (`createIndex`, `updateMany` mit `upsert`); `createCollection` wirft bei Bestand → Migration muss try/catch oder `db.getCollectionNames().includes(…)`-Guard nutzen. Neue Regel `mongo/R01`.

**Disziplin (alle Dialekte).** Eine Migration läuft entweder ganz oder gar nicht (transaktional, wo der Dialekt es zulässt; Mongo ist multi-statement nicht atomar — Migrationen müssen idempotent **wiederholbar** sein, sodass ein erneuter Lauf nach Teilfehler sauber durchgeht).

---

## 5. Compose-Service-Templates

**Neu (Welle 2):**

```
templates/_shared/
  db-postgres/
    compose.fragment.yml      # zum include in docker-compose.yml
  db-mysql/
    compose.fragment.yml
  db-sqlite/
    README.md                  # erklärt: kein db-Service, nur Volume-Mount + migrations-Sidecar
    compose.fragment.yml      # NUR migrations-Service (one-shot, file-DB) + Volume — KEIN db-Service
  db-mongodb/
    compose.fragment.yml
```

**Annahme (begründet):** Wir liefern **Fragmente** (`compose.fragment.yml`), nicht ganze `docker-compose.yml`s — der App-Stack hat schon einen Compose und wir wollen nur den `db`-Service-Block ergänzen. Die Wiring-Welle (§14) hängt das Fragment beim Scaffold per `cat` ans Projekt-Compose an (kein YAML-Merge-Tool nötig, weil das App-Compose vom Plugin selbst ausgerollt wird → Format bekannt).

**Beispiel — `db-postgres/compose.fragment.yml`:**

```yaml
services:
  db:
    image: postgres:17-alpine
    restart: unless-stopped
    environment:
      POSTGRES_DB: ${DB_NAME:-app}
      POSTGRES_USER: ${DB_USER:-app}
      POSTGRES_PASSWORD: ${DB_PASSWORD:?required}
    volumes:
      - db_data:/var/lib/postgresql/data
      - ./db_scripts:/db_scripts:ro
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${DB_USER:-app} -d ${DB_NAME:-app}"]
      interval: 5s
      timeout: 3s
      retries: 20
    ports:
      - "${DB_PORT:-5432}:5432"
volumes:
  db_data: {}
```

**MySQL-Fragment** — Image `mariadb:11`, Healthcheck `healthcheck.sh --connect`, Port `3306`, Volume `/var/lib/mysql`. **Mongo-Fragment** — Image `mongo:7`, Healthcheck `mongosh --quiet --eval 'db.adminCommand({ ping: 1 }).ok'`, Port `27017`, Volume `/data/db`.

**SQLite-Sonderfall.** Kein **db**-Service (SQLite ist eine Datei, kein Server). Stattdessen ein **named Volume** im App-Service + ein optionaler one-shot **migrations**-Service im selben Fragment (Alpine + sqlite-CLI), der `db_scripts/run-migrations.sh` einmalig vor App-Start ausführt (`depends_on: service_completed_successfully`). Das migrations-Service-Fragment lebt parallel zu den anderen Dialekten in `db-sqlite/compose.fragment.yml` (saubere Trennung App ↔ DB-Admin, §16-R4):

```yaml
services:
  app:
    volumes:
      - db_data:/data
    environment:
      DB_PATH: /data/app.sqlite
volumes:
  db_data: {}
```

`db-sqlite/README.md` dokumentiert genau das.

**Pflicht-Felder in jedem Fragment** (Review-Kriterium): `restart: unless-stopped`, `healthcheck` (sonst kann `/preview` keinen sauberen Wait machen), Volume mit eindeutigem Namen, Port-Mapping über env-Variable (Konflikt-vermeidung bei mehreren Previews, §12). **Keine hartkodierten Passwörter** (`${DB_PASSWORD:?required}` — fehlt die env, bricht compose ab; Security-Floor).

---

## 6. Migration-Runner-Pattern

**Pro Dialekt ein Wrapper-Script `db_scripts/run-migrations.sh`** (Bash, in jedem Sprach-Container verfügbar; ausgenommen Mongo-only Container — dort wird mongosh benutzt). Der Runner ist **idempotent**, läuft beim Container-Start oder per CI-Job, und schreibt **immer** in die Marker-Tabelle.

**Algorithmus (alle Dialekte gleich):**

```
1. Marker-Tabelle/Collection sicherstellen (CREATE IF NOT EXISTS / createCollection-guard).
2. SELECT applied versions FROM _schema_migrations.
3. Für jede Datei in db_scripts/ in lexikographischer Reihenfolge:
   a. Version aus Dateiname (001_, 002_, …) extrahieren.
   b. Schon angewandt? → skip.
   c. Anwenden (psql -f / mysql < / sqlite3 < / mongosh <).
   d. Bei Erfolg: INSERT version, applied_at.
   e. Bei Fehler: Skript abbrechen, exit 1.
```

**Beispiel — `db_scripts/run-migrations.sh` für Postgres:**

```bash
#!/usr/bin/env bash
set -euo pipefail
: "${DB_HOST:?}" "${DB_NAME:?}" "${DB_USER:?}" "${PGPASSWORD:?}"
psql -v ON_ERROR_STOP=1 -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" \
  -c "CREATE TABLE IF NOT EXISTS public._schema_migrations (
        version text PRIMARY KEY,
        applied_at timestamptz NOT NULL DEFAULT now())"
applied=$(psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -tAc \
  "SELECT version FROM public._schema_migrations")
for f in db_scripts/[0-9][0-9][0-9]_*.sql; do
  version="$(basename "$f" .sql | cut -c1-3)"
  grep -qx "$version" <<<"$applied" && continue
  echo "Applying $f"
  psql -v ON_ERROR_STOP=1 -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -f "$f"
  psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" \
    -c "INSERT INTO public._schema_migrations(version) VALUES ('$version')"
done
```

Die Mongo-Variante nutzt `mongosh "$MONGO_URI" --quiet --file "$f"` und eine kleine `applyMigration(version)`-JS-Funktion.

**Wo läuft der Runner?**

- **Lokal/Preview (§12):** `/preview up` startet den DB-Service, **wartet auf Healthcheck**, ruft dann `docker compose run --rm app db_scripts/run-migrations.sh` (one-shot, gleiche Network/Env wie der App-Service). Annahme: jeder App-Container hat den jeweiligen CLI-Client installiert (psql/mysql/sqlite3/mongosh) — die `templates/<lang>/Dockerfile` werden in Welle 2 entsprechend ergänzt **nur wenn** `profile.db_dialect != none`.
- **CI (`build.yml`):** Migrations laufen **nicht** im CI — das CI baut nur das Image. Datenbank-Bootstrap ist Aufgabe des Deploy-Schritts (Preview oder echte VPS-Inbetriebnahme).
- **Produktion:** Aufgabe einer späteren Welle / Out-of-Scope-Pfad. Default-Idee: `run-migrations.sh` als `init`-Container im Compose-Stack (depends_on: db healthy) bevor der App-Container startet.

**Annahme (begründet):** Migrations laufen **nicht** als App-Startup-Hook (kein „run on every boot"). Begründung: race conditions bei mehreren App-Replicas, schwer zu debuggen wenn schief — separates `run-migrations`-Kommando ist explizit und auditierbar.

---

## 7. Backup/Restore-Pattern

**Pro Dialekt ein Skript-Paar** in `templates/_shared/db-<dialect>/`:

```
templates/_shared/db-<dialect>/
  backup.sh       # vorbild für db_scripts/backup.sh im Projekt
  restore.sh
```

| Dialekt | Backup | Restore |
|---|---|---|
| postgres | `pg_dump -Fc -d "$DB_URL" > backup.dump` | `pg_restore --clean --if-exists -d "$DB_URL" backup.dump` |
| mysql | `mysqldump --single-transaction -h "$DB_HOST" -u "$DB_USER" "$DB_NAME" > backup.sql` | `mysql -h "$DB_HOST" -u "$DB_USER" "$DB_NAME" < backup.sql` |
| sqlite | `sqlite3 "$DB_PATH" ".backup '$OUT/app.sqlite'"` (online-safe; nicht plain `cp`) | `cp "$OUT/app.sqlite" "$DB_PATH"` (DB-File ist self-contained) |
| mongodb | `mongodump --uri "$MONGO_URI" --archive --gzip > backup.archive.gz` | `mongorestore --uri "$MONGO_URI" --archive --gzip --drop < backup.archive.gz` |

**Wer ruft auf?** **Manuell** — kein Auto-Backup-Cron im Plugin (Brewing-Erfahrung: Backup-Strategie ist projekt-spezifisch, gehört nicht in den Default-Scaffold). Die Skripte sind **Vorlagen**, die der `coder` bei Bedarf via Board-Item ins Projekt zieht. Auto-Backup ist ein optionaler späterer Wellen-Schritt (separater PR).

**Pflicht (Security-Floor angewandt).** Backup-Skripte schreiben **niemals** Plaintext-Credentials in Repo/Log; sie lesen `$DB_PASSWORD`/`$MONGO_URI` aus der Env. `restore.sh` druckt vor dem Apply ein bestätigendes „Will overwrite DB X — type DB-name to confirm" (interaktiv, kein silent destroy).

---

## 8. DBA-Agent-Erweiterung

**Bestand.** `agents/dba.md` liest heute fix `${CLAUDE_PLUGIN_ROOT}/knowledge/sql.md`.

**Erweiterung (Welle 1, im selben File-Edit wie die Packs).** `dba.md` erhält:

1. **Lese-Pflicht ergänzt:** `profile.db_dialect` zuerst lesen → daraus den **richtigen Pack** wählen (Auswahl-Regel §3). Fallback: `domains: [sql]` ohne `db_dialect` → `postgres`. `db_dialect: none` → DBA-Aufruf ist ein Fehler („Projekt hat keine DB; bitte profile.db_dialect setzen oder `dba` nicht aufrufen").
2. **Vorgehen-Schritt angepasst:** „Datenmodell entwerfen" wird dialekt-spezifisch — bei `mongodb` sind „Entitäten" Collections, „FKs" sind eingebettete Dokumente oder Referenzen, „RLS" ist Mongo-Auth-Rules / `$jsonSchema`-Validator + per-Collection-User. Der Pack liefert die Idiome; `dba.md` macht klar: das Output-Schema von `docs/data-model.md` bleibt **dialekt-neutral** (Entitäten/Beziehungen/Constraints — der `coder` übersetzt es).
3. **Output `docs/data-model.md`** bleibt das einzige Output-Artefakt — keine Migrationen, kein Code (unverändert). Die Doc nennt aber jetzt zwingend `db_dialect: <wert>` im Header, damit der `coder` weiß, was er implementieren soll.
4. **Harte Grenzen** explizit: `dba` greift **nie** auf `db_scripts/` zu (das ist coder-Land). Schreibt nur `docs/data-model.md`.

**Schnittstelle zu coder/reviewer/tester (klargestellt im Pack-Lader):**

- `coder` liest bei `profile.db_dialect != none` zusätzlich zum Sprach-Pack den DB-Pack via §3-Regel.
- `reviewer` lädt denselben DB-Pack — die `Reviewer-Checklist` des Packs wird bei jedem Diff angewendet, der `db_scripts/` oder Datenzugriffscode (Heuristik: import von `pg`/`mongoose`/etc.) berührt.
- `tester` lädt den `Test-Approach`-Abschnitt — typisch: „Migration zweimal anwenden (idempotent) + Smoke-Query gegen jedes Schema/Collection".

---

## 9. `/adopt`-Erweiterung — DB-Detection-Heuristik

**Bestand.** `/adopt` Schritt 2 erkennt heute Sprache und domäne `sql` aus `*.sql`-Files. Das wird ersetzt:

**Neu Schritt 2a — DB-Detection** (vor dem `profile.md`-Schreiben):

1. Heuristik aus §2 anwenden → Vorschlag `db_dialect: <wert>`.
2. User-Bestätigung via `AskUserQuestion` (5 Enum-Werte, vorausgewählt der Vorschlag).
3. Ergebnis in `.claude/profile.md` als `db_dialect: <wert>` schreiben.
4. **Wenn `db_dialect != none`:**
   - **DBA-Audit-Dispatch** — `reviewer` im Audit-Modus erhält zusätzlich den passenden DB-Pack (§3). Findet er existierende `db_scripts/`, prüft er die nummerierung (Lücken? doppelte Versionen?), die Idempotenz-Patterns und Security-Floor (z.B. unparametrisierte Queries im App-Code, gefundene Plaintext-Passwörter in `.env.example`).
   - Pack-Funde landen wie üblich im Backlog (Schritt 4 `/adopt`).
   - **Compose-Fragment fehlt?** → ein Backlog-Item „DB-Service im Compose ergänzen" (Standard-Priorität: Important).
   - **`run-migrations.sh` fehlt?** → Backlog-Item „Migration-Runner einrichten" (Priorität: Important).

**Scaffolding ≠ Auto-Fix (Klarstellung, Amendment 2026-05-31 — PR #35).** `/adopt` darf — analog zur bestehenden Scaffold-Logik für `Dockerfile` / `.github/workflows/build.yml` / `security.yml` / `.github/dependabot.yml` aus Schritt 2 — **additive, nicht-destruktive Skeleton-Files** anlegen, wenn der jeweilige Pfad noch nicht existiert. Das umfasst beim DB-Subsystem konkret:

1. **Compose-Fragment-Include:** Wenn das Projekt-`docker-compose.yml` noch keinen `db`-Service hat (bei sqlite: noch keinen `migrations`-Service), wird das Fragment aus `templates/_shared/db-<dialect>/compose.fragment.yml` angehängt (`cat fragment >> docker-compose.yml`, mit Trennzeilen-Kommentar als Audit-Trail). Bei vorhandenem db-Service: **kein Overwrite** — Fragment landet als separates `docker-compose.db.yml` + Backlog-Item.
2. **`db_scripts/`-Skeleton:** `000_init_meta.{sql|js}` + `run-migrations.sh` aus dem dialekt-spezifischen Template-Ordner, wenn `db_scripts/` fehlt. Bestehende `db_scripts/`-Dateien werden **nie** überschrieben.
3. **`.env.db.example`:** Vorlage für DB-Env-Variablen, wenn noch nicht vorhanden.
4. **DBA-Audit-Dispatch:** Wenn `db_scripts/` mit Inhalt vorliegt (eigener oder gerade kopierter Skeleton), dispatcht `/adopt` den `reviewer` im Audit-Modus mit DB-Pack — Findings landen im Backlog.

**Trennlinie zur „behebt nichts automatisch"-Grenze:** Scaffolding (Compose-Fragment, Skeleton, CI-Workflows) und Auto-Fix (Business-Logik, Bestandscode patchen) sind verschiedene Klassen. `/adopt` scaffoldet weiterhin (wie bisher mit Dockerfile/security.yml/dependabot.yml), behebt aber **keine** Critical-/Important-Findings — diese gehen ausschließlich ins Backlog für `/flow`. Eine bestehende `db_scripts/`-Migration, ein bestehender Runner, ein bestehender db-Service im Compose werden **nie** angefasst — Konflikte → Backlog. Diese Klarstellung folgt dem in §16-R5/R6 etablierten Pattern (Spec-Amendment statt Skill-Rollback, wenn die Skill-Implementierung den besseren Trade-off trägt; vgl. auch §14-Amendment „Graceful Degradation" aus PR #28).

---

## 10. `/new-project`-Erweiterung

**Neuer Flag.** `/new-project <name> [--lang <x>] [--db <dialect>]`.

**Ohne `--db`:** **Eine** zusätzliche Frage (`AskUserQuestion`) nach Stack-Frage und vor Board-Anlage:
> „DB-Dialekt? [postgres|mysql|sqlite|mongodb|none] (none = keine DB)"

**Was passiert je Wert:**

- `none`: `profile.db_dialect: none`. Kein DB-Pack, kein Compose-Fragment, kein `db_scripts/`-Skeleton, kein DBA-Dispatch beim ersten `requirement`-Lauf. `docs/data-model.md` wird **nicht** gescaffolded (bestand-Regel in `new-project` Schritt 4b bleibt — sie hängt heute schon an `domains: [sql]`, künftig an `db_dialect != none`).
- `postgres|mysql|sqlite|mongodb`: Das Fragment aus `templates/_shared/db-<dialect>/compose.fragment.yml` wird ans Projekt-`docker-compose.yml` angehängt. `db_scripts/` wird mit `000_init_meta.sql` (bzw. `.js` für mongodb) als idempotenter Marker-Tabellen-Migration + dem dialekt-spezifischen `run-migrations.sh` angelegt. `docs/data-model.md` wird gescaffolded. Der `Dockerfile` der Sprache wird um den DB-CLI-Client ergänzt (psql / mariadb-client / sqlite3 / mongosh).

**Annahme (begründet):** Genau **eine** zusätzliche Frage (kein Multi-Step-Wizard). Begrenzung „minimal fragen" (vgl. existing `new-project` Grenze) bleibt eingehalten.

---

## 11. `/flow`-Erweiterung

**Trigger für DBA-Reviewer-Dispatch** (zusätzlich zum normalen `reviewer`-Loop) — der DBA muss **als zweiter Reviewer** das Modell-Doc prüfen, wenn ein Item den DB-Layer berührt:

Der Orchestrator dispatcht `dba` (im Review-Modus, nicht Design-Modus) **wenn eines zutrifft**:

1. Board-Item hat **Label `db`** (vom `requirement` gesetzt, wenn die Spec `docs/data-model.md` referenziert).
2. `git diff` (vor dem `reviewer`-Run) berührt eine der Pfade: `db_scripts/`, `docs/data-model.md`, oder Code-Files mit Datenzugriffs-Imports (Heuristik wie in §8).

**Reihenfolge im Loop:** `coder` → `reviewer` (Sprach-Pack-Diff-Review) → wenn DB-Trigger: **`dba` als Zweit-Review** (prüft Modell-Konformität / Datenmodell-Drift gegen `docs/data-model.md`). Beide müssen PASS sagen; bei einem CHANGES-REQUIRED → zurück an coder. Erst dann `tester`.

**Annahme (begründet):** DBA ist **Review-only** im Loop, kein eigener Coder-Schritt (Modell-DESIGN bleibt vor-`/flow`; im Item geht es um Umsetzung). Begründung: hält den Loop schlank, vermeidet Doppelarbeit, und das Drift-Gate für `docs/data-model.md` ist bereits durch CONCEPT §4d gedeckt.

**Annahme (begründet):** Der `dba` braucht für den Review-Modus eine kleine Erweiterung in `agents/dba.md` („Review-Modus: prüft Diff gegen `docs/data-model.md` und Pack-Checklist; gibt `Review-Gate: PASS|CHANGES-REQUIRED`; schreibt keinen Code/Doc"). Diese Erweiterung gehört zu Welle 3.

---

## 12. `/preview`-Erweiterung

**Wenn `profile.db_dialect != none`:** `/preview up` startet vor dem App-Container den DB-Service.

**Ablauf erweitert** (additiv zur bestehenden `up`-Logik in `skills/preview/SKILL.md`):

1. **Compose-DB-Service starten:** `docker compose -p "preview-${app}-${preview_port}" up -d db`. Das `-p`-Projekt-Prefix isoliert mehrere parallele Previews (jedes hat ein eigenes Volume `preview-<app>-<port>_db_data`).
2. **Healthcheck-Wait:** Bis `docker inspect --format '{{.State.Health.Status}}' …` `healthy` ist (Timeout 60s; danach Logs zeigen + scheitern).
3. **Migrations applizieren:** `docker compose -p … run --rm app db_scripts/run-migrations.sh` (nur wenn `db_scripts/run-migrations.sh` existiert; sonst skip + Hinweis loggen).
4. **App-Container starten** wie bisher (`docker run …`), aber mit `--network "preview-${app}-${preview_port}_default"` und Env `DB_HOST=db` / `DB_URL=…`.
5. **Smoke + URL** wie bisher.

**SQLite-Sonderfall.** Kein DB-Service. Schritt 1–2 entfallen. Das DB-Volume `preview-<app>-<port>_db_data` wird beim `docker run` als `-v preview-…_db_data:/data` gemountet (Daten überleben Container-Neustart, sind aber pro Preview isoliert).

**`/preview down`** entfernt zusätzlich:

- `docker compose -p "preview-${app}-${preview_port}" down -v` (DB-Container + Volume).
- Bei `--keep-data`-Flag: `down` ohne `-v` (Volume bleibt für späteres `up`).

**Annahme (begründet):** Volumes sind **pro Preview isoliert** (nicht pro App geteilt). Begründung: man will mehrere PRs gleichzeitig previewen können, ohne dass sie auf demselben DB-State arbeiten — sonst Race-Conditions und Reset zwischen PRs unmöglich. Trade-off: jedes `down` kostet Bootstrap-Zeit beim nächsten `up`; akzeptabel, weil Preview ohnehin „wegwerfbar" ist (CONCEPT §8a).

**Annahme (begründet):** `/preview up <app>` (repo-unabhängig, ohne Profil) **funktioniert ohne DB** — der DB-Dialekt kann nicht aus dem ghcr-Image abgeleitet werden. In diesem Modus startet `/preview` **nur den App-Container**; ist eine DB nötig, muss man im Repo sein (mit Profil + Compose). Hinweis-Output: „Repo-loser Preview unterstützt keine DB; im Repo ausführen für vollen Stack."

---

## 13. Test-Verträge — Selbsttest der Fabrik

Die DB-Subsystem-Erweiterung wird in der Fabrik durch **vier Smoke-Skripte** verifiziert (eines pro Dialekt). Diese leben in `tests/db-subsystem/` innerhalb des `agent-flow`-Repos und werden vom **`tester`-Agent im `/flow`-Loop** ausgeführt, sobald ein PR `templates/_shared/db-*/**` oder die Smoke-Skripte selbst (`tests/db-subsystem/*.sh`) berührt. Pfad-basierte Auswahl (nur der betroffene Dialekt; bei Edits am Runner selbst alle vier) ist im Agent kodifiziert — siehe `agents/tester.md` Abschnitt „DB-Subsystem-Smoke (bei Template-Diffs)". Kein GitHub-Actions-Workflow nötig (keine Actions-Minuten, kein DinD-Overhead, unabhängig von Org-Budget-Politik).

**Smoke-Suite-Struktur** (kanonisch, umgesetzt in PR #36):

```
tests/db-subsystem/
  run-all.sh                 # sequentieller Runner über alle 4 Dialekte, sammelt Exit-Codes
  smoke-postgres.sh          # monolithisches Per-Dialekt-Skript (apply + idempotenz + drift)
  smoke-mysql.sh
  smoke-sqlite.sh
  smoke-mongodb.sh
  README.md                  # lokales Ausführungs-/Voraussetzungs-Doc
```

Jedes `smoke-<dialect>.sh` ist **monolithisch + selbst-validierend** (keine separate `expected.txt`): es scaffoldet eine Wegwerf-Testumgebung in `SMOKE_DIR=$(mktemp -d /tmp/smoke-<dialect>-XXXXXX)` aus den `templates/_shared/db-<dialect>/`-Artefakten, startet den Stack, prüft alle Stufen inline und räumt im `trap` wieder ab.

**Begründung für monolithische Struktur (gegenüber dem ursprünglichen `tests/smoke-db/<dialect>/{run.sh, expected.txt}`-Layout):** Per-Dialekt-Skripte sind übersichtlich, portabel (kein gemeinsamer `run.sh` mit case/switch pro Dialekt), validieren erwartete Outputs inline (kein File-Diff-Roundtrip nötig) und haben in PR #36 echte Drift-Bugs in den Compose-Fragmenten gefunden. Eine separate `expected.txt` würde nur sehr triviale „ok"-Vergleiche kapseln; der Mehrwert rechtfertigt das zusätzliche File-Layout nicht.

**Smoke-Verlauf** (ein Skript `tests/db-subsystem/smoke-<dialect>.sh`, vom `tester`-Agent pro betroffenem Dialekt aufgerufen):

1. `docker compose -p smoke-<dialect> up -d`.
2. Auf DB-Healthcheck warten (außer sqlite).
3. `run-migrations.sh` ausführen → muss exit 0 + Marker in `_schema_migrations` erscheinen.
4. **Idempotenz-Test:** `run-migrations.sh` ein zweites Mal ausführen → muss exit 0, Marker-Count bleibt gleich.
5. **Drift-Test:** Migrations-Datei mutieren (Trailing-Kommentar), Runner ein drittes Mal → muss erkennen + sauber abbrechen oder warnen (Pack-spezifisch).
6. Smoke-Query gegen den DB-Service inline im Skript.
7. `docker compose -p smoke-<dialect> down -v` im `trap`.
8. PASS = alle 4 Dialekte grün; ein roter = PR rot. `run-all.sh` aggregiert "N/4 PASS".

**Annahme (begründet):** Smoke testet **die Mechanik** (Runner, Marker, Idempotenz, Drift-Erkennung, Compose-Fragment), nicht den Pack-Inhalt (Pack-Korrektheit ist `reviewer`-/Mensch-Sache; wenn wir das testen würden, müssten wir den ganzen `/flow` simulieren — zu schwer für CI).

**Aufruf-Wiring (Amendment, 2026-05-31):** Die Smoke-Skripte werden vom **`tester`-Agent** im `/flow`-Loop gefahren — nicht von einem GitHub-Actions-Workflow. Pfad-basierte Auswahl (nur der betroffene Dialekt; bei Edits am Runner selbst alle vier) ist im Agent kodifiziert — siehe `agents/tester.md` Abschnitt „DB-Subsystem-Smoke (bei Template-Diffs)". Der `/flow`-Orchestrator behandelt `Test-Gate: PASS` als harte Vorbedingung für Merge bei Template-Diffs (`skills/flow/SKILL.md` §4). Begründung gegenüber der ursprünglich angedachten `.github/workflows/smoke-db.yml`: lokaler Tester-Run ist schneller (kein DinD-Overhead), kostet keine Actions-Minuten, ist unabhängig von Org-Budget-Politik und integriert sich nativ in die bestehende Coder→Reviewer→Tester-Sequenz.

---

## 14. Migrations-Reihenfolge / Build-Wellen

Drei Wellen mit klaren Abhängigkeiten — die zweite hängt von der ersten, die dritte von beiden:

**Welle 1 — Knowledge** (kann sofort starten, parallelisierbar pro Pack):
- `knowledge/sql.md` Header um „dialect = postgres" + 1-Zeilen-Backcompat-Hinweis ergänzen.
- `knowledge/sql-mysql.md` neu.
- `knowledge/sql-sqlite.md` neu.
- `knowledge/mongodb.md` neu.
- `agents/dba.md` Lese-Pflicht + Vorgehen + Review-Modus ergänzen.
- **Output:** 4 Packs + erweiterter DBA-Agent. **Kein** Wiring, **kein** Template — bestehende Projekte bleiben unverändert (Fallback greift).

**Welle 2 — Templates** (braucht Welle 1, damit Packs Templates referenzieren können):
- `templates/_shared/db-postgres/` (compose-fragment + backup/restore-Skripte).
- `templates/_shared/db-mysql/`.
- `templates/_shared/db-sqlite/` (README + Volume-Snippet + `compose.fragment.yml` mit **NUR** migrations-Service (one-shot Alpine + sqlite-CLI) + `db_data`-Volume — KEIN db-Service, weil SQLite eine Datei ist; das Fragment realisiert §16-R4 (separater migrations-Container, depends_on `service_completed_successfully`) parallel zu den anderen Dialekten).
- `templates/_shared/db-mongodb/`.
- `db_scripts/run-migrations.sh`-Vorlagen pro Dialekt (in den `db-<dialect>/`-Ordnern).
- `templates/<lang>/Dockerfile` um optionale CLI-Clients ergänzen (commented-in/out je nach Wiring).
- **Output:** Templates liegen, sind aber noch von keinem Skill konsumiert. Bestehende Projekte unverändert.

**Welle 3 — Wiring** (braucht Welle 1 + 2):
- `skills/new-project/SKILL.md`: `--db`-Flag, `db_dialect`-Frage, Fragment-Append, `db_scripts/`-Scaffold, Doc-Scaffold-Bedingung umschreiben (`db_dialect != none` statt `domains: [sql]`).
- `skills/adopt/SKILL.md`: Detection-Schritt 2a, DBA-Audit-Dispatch.
- `skills/flow/SKILL.md`: DBA-Review-Dispatch bei Trigger §11.
- `skills/preview/SKILL.md`: DB-Service-Start, Migrations-Apply, Isolations-Compose-Projekt-Namen.
- `templates/<lang>/profile.md`: `db_dialect: <bei Scaffold gesetzt>` Zeile.
- `tests/db-subsystem/smoke-<dialect>.sh` + `tests/db-subsystem/run-all.sh` + `tester`-Agent-Dispatch in `agents/tester.md` + `/flow`-Trigger in `skills/flow/SKILL.md` §4 (siehe §13 für die kanonische Struktur, umgesetzt in PR #36; Wiring auf `tester`-Agent statt GH-Actions umgestellt in PR #41).
- **Output:** End-to-end nutzbar.

**Parallelisierbarkeit:**
- Innerhalb Welle 1: alle 4 Packs + DBA-Agent unabhängig.
- Innerhalb Welle 2: alle 4 Fragment-Ordner unabhängig.
- Innerhalb Welle 3: 4 Skill-Edits sind serialisierbar, aber unabhängig voneinander; Smoke-Tests können nach jedem Skill-Edit laufen.

**Cross-Wellen:** Welle 2 darf erst beginnen, wenn Welle 1 (zumindest die jeweils referenzierten Pack-Regeln) gemerged ist. Welle 3 erst, wenn Welle 2 vollständig gemerged ist (Smoke-Tests in Welle 3 brauchen die Templates).

**Amendment (PR #28-Folge, 2026-05-30) — kontrollierte Wellen-Sprünge erlaubt mit Graceful Degradation.** In der Praxis können einzelne Wellen-3-Items (z.B. ein `agents/`- oder Skill-Edit, das nur eine bestehende Dispatch-Regel schärft) **vorgezogen** werden, **wenn** und **nur wenn** der vorgezogene Code sich gegen fehlende Welle-1-/Welle-2-Artefakte **graceful** verhält. Konkrete Anforderung:

1. Der vorgezogene Code muss explizit prüfen, ob das benötigte Artefakt (Pack, Template, Fragment) auf `main` existiert, und im Fehlfall eine klare Warn-Zeile loggen, statt zu scheitern.
2. Der Build-Loop darf durch ein fehlendes Artefakt **nicht** hängen bleiben (kein `CHANGES-REQUIRED`/Exit-Code-Fehler nur wegen Fehlbestand).
3. Dialekt-übergreifende Pflicht-Checks (§4 Forward-only / §6 Marker / Secrets) müssen weiterhin laufen, sodass das Gate nie ungeprüft auf `PASS` fällt.

Vorbild-Fall: PR #28 (Welle 1) hat den `/flow`-Dispatch aus §11 vorgezogen; der DBA-Agent enthält den Graceful-Degradation-Guard (`agents/dba.md` §3, „Pack fehlt"). Damit ist die Wartungsverträglichkeit gewahrt und die Drift gegenüber §14 ist dokumentiert statt versteckt.

Diese Amendment-Regel ist explizit eng: sie deckt nur Disziplin-/Wiring-Edits ab, **nicht** das Vorziehen von Pack-Inhalten oder Templates (deren Abhängigkeitskette bleibt strikt linear, weil dort kein „graceful Fallback" möglich ist).

---

## 15. Risiken & offene Fragen

**R1 — Polyglott-Projekte ignoriert.** Eine App, die wirklich Postgres + Mongo gleichzeitig nutzt, passt nicht ins Modell. Mitigations-Pfad: spätere Welle mit `db_dialects: [a, b]`-Liste + Pack-Mehrfach-Laden. Frage: blockiert das jemanden konkret? — User-Entscheid offen.

**R2 — SQLite-Multi-Reader.** SQLite mit mehreren App-Replicas im Compose-Stack ist nicht safe (file-lock-Probleme). `/preview` baut heute genau 1 App-Container → kein Akut-Problem. Wenn das Plugin später Multi-Replica-Previews unterstützt, muss SQLite explizit auf „nur 1 Replica" gepinnt werden. **Frage: erwähnen wir das jetzt im sqlite-Pack als Hard-Limit?**

**R3 — Mongo-Transaktionalität.** Mongo-Migrationen sind nicht atomar (über Statements hinweg). Falls eine Migration auf halbem Weg crasht, bleibt der DB-State zwischen den Versionen. Mitigations: Idempotenz-Pflicht im `mongo/R01` (rerun muss sauber durchgehen). **Frage: brauchen wir ein Lock-Pattern (z.B. Single-Doc-Lock in `_schema_migrations`), um konkurrierende Runner auszuschließen?** — Im Plugin-Kontext (Preview, ein Runner) wahrscheinlich überflüssig.

**R4 — CLI-Clients im App-Image.** Ein `psql`/`mongosh` im Production-Image vergrößert Surface und Image-Größe. Mitigations-Optionen: (a) Multi-Stage-Build mit `migrations-Stage` (CLI nur im Build, nicht im Runtime); (b) Separater `init`-Container nur mit der CLI, der die App-Image-Größe nicht aufbläht. **Empfehlung: (b) ab Welle 2 — ein generisches `migrations`-Image (z.B. `alpine` + dialekt-CLI) statt CLI im App-Image.** Soll ich die Welle-2-Specs entsprechend umstellen? — User-Entscheid offen, default in dieser Spec ist noch (a).

**R5 — Smoke-Pipeline-Kosten.** Ursprünglich war ein GitHub-Actions-Workflow `tests/smoke-db.yml` (DinD) geplant. **Aufgelöst (PR #41):** Smoke läuft lokal über den `tester`-Agent — keine Actions-Minuten, kein DinD-Overhead, kein Org-Budget-Risiko. Pfad-basierter Filter (nur betroffener Dialekt; ganze Suite bei Runner-Edits) ist im Agent kodifiziert (`agents/tester.md` + `skills/flow/SKILL.md` §4).

**R6 — `domains: [sql]` Backwards-Compat.** Der einzeilige Fallback (`domains: [sql]` ohne `db_dialect` ⇒ `postgres`) muss in `coder`/`reviewer`/`tester`/`dba` konsistent geschrieben sein, sonst zerfällt der Bestand. **Frage:** Eigener Smoke-Test dafür? — Ja, ein 5. Skript `tests/db-subsystem/smoke-legacy-sql-domain.sh` in Welle 3 (analog zur Per-Dialekt-Struktur aus §13).

**R7 — Sicherheits-Surface durch DB-Port-Mapping.** Compose-Fragmente mappen DB-Ports nach `localhost:<port>`. In Preview-Mode ist das ok (Dev-Maschine). Wenn das Compose je in Production wandert, ist das ein **Critical** (DB nach außen). **Mitigation:** Welle-2-Fragmente bekommen einen Kommentar „`ports:`-Block für Preview; in Production ENTFERNEN" — und ein `reviewer`-Regel-Eintrag im jeweiligen Pack.

**R8 — Backup-Default-Pfad.** Die Backup-Skripte sind nur Vorlagen, nicht standardmäßig im Projekt-`db_scripts/`. Für Bestandsprojekte aus dem Brewing-Umfeld (wo Backup kritisch ist) könnte das überraschen. Aber: Plugin bleibt minimal, Brewing hat sein eigenes Backup-Setup. **Entscheidung: stays as drafted, Brewing-Pfad nicht koppeln.**

---

## §16 — Resolutions (Mensch-Entscheidungen, 2026-05-30)

Die in §15 aufgeworfenen offenen Fragen wurden vom User entschieden — die Wellen 1-3 starten mit diesen Festlegungen:

- **R1 — Polyglott:** **Entschieden: P1 = nur 1 DB pro Projekt.** `profile.db_dialect` bleibt Single-Value-Enum. Companion-Services wie Redis werden außerhalb des DB-Subsystems als Sidecar-Templates geführt. Polyglott (mehrere primäre DBs in einem Projekt) wird in P2 evaluiert, falls echter Bedarf entsteht. **Polyglott-Trigger in `/adopt`** — siehe [`skills/adopt/SKILL.md`](../../skills/adopt/SKILL.md) Schritt 2a (Abschnitt **a.1**): erkennt `/adopt` 2+ primäre Dialekte mit `high`-Confidence im selben Repo, wird ein GitHub-Issue mit Label `polyglott-needed` + `architecture` angelegt; P1 wird mit dem vom User gewählten Dialekt adoptiert. Companions (Redis, Memcached, Elasticsearch, Meilisearch, Typesense) zählen explizit **nicht** als Polyglott — die Heuristik schließt sie aus, sonst wäre jede Postgres+Redis-Standard-Webapp ein false-positive. Edge-Case 2 SQL-Dialekte (typisches Test-/Embedded-Setup wie Postgres+SQLite) wird auf `medium`-Confidence downgegradet — keine automatische Eskalation. Diese Skill-Eskalation ist der **Echt-Bedarfs-Belegmechanismus**, der P2 triggert (sobald 2+ unabhängige Projekte den Issue produzieren).
- **R2 — SQLite-Skalierungsgrenze:** **Entschieden: Ja, prominent dokumentieren.** `knowledge/sql-sqlite.md` erhält eine sichtbare Warn-Sektion zur Single-File-Lock-Limitierung; der DBA-Agent erhält eine Regel (z.B. `sqlite/R0X`), Items mit Multi-Replica-Deployment-Anforderung bei `db_dialect: sqlite` als Critical zu flaggen.
- **R4 — Migration-CLI-Ort:** **Entschieden: Separates `migrations`-Image.** Der DB-Client (psql/mysql/sqlite3/mongo) wird NICHT ins App-Image gebacken. Stattdessen pro Dialekt ein schlankes `migrations`-Image (z.B. `postgres:16-alpine` mit `run-migrations.sh` als ENTRYPOINT), das im Compose als one-shot-Service zwischen DB-Healthy und App-Start läuft. Saubere Trennung App ↔ DB-Admin.
- **R5 — Optionale `checksum`-Spalte in `_schema_migrations` (Amendment, 2026-05-30):** **Entschieden: Spec §4 erlaubt eine optionale dritte Spalte `checksum TEXT NULL` (bzw. dialekt-äquivalent).** Verursacht durch Pack-Diff in PR #24 (Postgres-Pack), das diese Spalte für Drift-Detection einführte und damit gegen die ursprüngliche zwei-spaltige Tabellen-Definition driftete. Spec hatte `checksum` weder eingeführt noch bewusst ausgeschlossen — die saubere Lösung ist „optional dokumentiert", sodass jeder Dialekt-Pack frei wählt. Implementierungen ohne `checksum` bleiben Spec-konform. Detail in §4. Unblockt PR #24 + Folge-Packs.
- **R6 — `/adopt` darf DB-Scaffolding ausführen (Amendment, 2026-05-31 — PR #35-Klärung):** **Entschieden: `/adopt` darf Compose-Fragmente includen + `db_scripts/`-Skeleton (`000_init_meta.{sql|js}` + `run-migrations.sh`) + `.env.db.example` anlegen — analog zur bereits existierenden Scaffold-Logik für `Dockerfile` / `.github/workflows/build.yml` / `security.yml` / `.github/dependabot.yml` aus Schritt 2.** Trennlinie: Scaffolding (additive, nicht-destruktive Skeleton-Files in nicht-existierenden Pfaden) ≠ Auto-Fix (Patch von Bestandscode oder bestehenden Migrationen). Bestehende `db_scripts/`, bestehende db-Services im Compose, bestehende Runner werden **nie** überschrieben — Konflikte landen ausschließlich im Backlog. Detail in §9. Folgt dem Spec-Amendment-Pattern aus §14 (PR #28) und R5 (PR #24): wenn die Skill-Implementierung den besseren Trade-off trägt, wird die Spec nachgezogen statt die Skill zurückgerollt.
- **R7 — §2 ist die kanonische Detection-Signal-Palette (Amendment, 2026-05-31 — PR #35-Klärung):** **Entschieden: §2-Tabelle führt die volle Signal-Palette mit Confidence-Stufen.** Skill `skills/adopt/SKILL.md` Schritt 2a spiegelt §2 1:1 wider — keine silent erweiterten Signale in der Skill. Neue Signal-Quellen (z.B. künftig Rust/`sqlx`, Go/`pgx`) werden zuerst in §2 ergänzt, dann in der Skill nachgezogen (gleicher PR). Verhindert Drift zwischen Spec und Implementierung. Eingeführt, weil PR #35 acht zusätzliche Signale (Python-Deps, Mongo-JVM-Deps, `pgvector`, Healthcheck-Strings, Env-Refs, `*.sqlite3`, `sqlite3`-CLI) in der Skill hatte, die in §2 fehlten.
- **R8 — Smoke-Suite-Struktur (Amendment, 2026-05-31, PR #36):** **Entschieden: monolithische Per-Dialekt-Skripte unter `tests/db-subsystem/smoke-<dialect>.sh` statt `tests/smoke-db/<dialect>/{run.sh, expected.txt}`.** Begründung: Per-Dialekt-Skripte sind übersichtlich, portabel (keine Branches in einem gemeinsamen Runner), validieren erwartete Outputs inline (keine separate `expected.txt` nötig) und haben in PR #36 echte Drift-Bugs in den Compose-Fragmenten zutage gefördert. Aggregation läuft über `tests/db-subsystem/run-all.sh`. Spec §13 + §14 wurden in PR #36 entsprechend amended.

Mit diesen Festlegungen ist die Spec vollständig — Welle 1 kann nach Merge dieses PRs starten.

---

## §17 — Companions (stateful Sidecars OHNE Schema-Evolution)

**Zweck.** Manche Apps brauchen stateful Infra-Dienste, die **keine** App-eigenen Schemas tragen — Cache (Redis), Queue-Broker (Redis/BullMQ, RabbitMQ in P2), Session-Store, Pub-Sub-Fanout. Sie sind weder DB (kein durable Business-Schema, keine Migrationen, kein Backup-Runner) noch reine Code-Dependency (eigener Container, eigenes Volume, eigener Lifecycle). Diese Spec-Sektion definiert sie als eigene Klasse: **Companions**.

**Definition.** Ein **Companion** ist ein stateful Sidecar mit:

- **eigenem Container + Volume** (überlebt App-Restarts),
- **schemalosem oder app-internem State** (Cache-Keys, Queue-Jobs, Session-Tokens — keine durable Business-Entitäten),
- **kein Migrations-Runner** (kein `db_scripts/`, kein `_schema_migrations`-Marker),
- **kein Backup-Skript im Default-Scaffold** (Daten sind ephemer/regenerierbar; wenn Persistenz nötig: AOF/RDB als Container-internes Feature, nicht als Workflow),
- **kein Knowledge-Pack-Eintrag** (kein eigener `coder`/`reviewer`/`tester`-Pack — Pattern leben in Sprach-Packs bzw. im Companion-README).

**`profile.companions[]`-Schema.** Neuer optionaler Slot in `.claude/profile.md`:

```yaml
companions: [redis]   # Liste, additiv; Default beim Scaffold: []
```

**Erlaubte Werte (P1):** `redis`. Weitere Companions (z.B. `memcached`, `rabbitmq`, `nats`) sind **additiv** in eigenen Spec-PRs möglich, aber explizit **out-of-scope dieses PRs**. Jeder neue Companion bringt mit:

1. `templates/_shared/companion-<name>/` mit `compose.fragment.yml`, `README.md`, `.env.<name>.example`, optional `scripts/`.
2. Detection-Signale in §17a (kanonische Tabelle, analog §2 für DBs) — neue Signale werden zuerst hier ergänzt, dann in `skills/adopt/SKILL.md` Schritt 2b nachgezogen (gleicher PR, kein Drift).
3. Wiring-Anpassungen in `skills/new-project/SKILL.md` (Flag-Validierung in 2b) und `skills/adopt/SKILL.md` (Detection-Tabelle in 2b).

**Abgrenzung zum DB-Subsystem.**

| Aspekt | DB (§4–§7) | Companion (§17) |
|---|---|---|
| Profile-Slot | `db_dialect: <single-enum>` | `companions: [<array>]` |
| Schema-Evolution | `db_scripts/<NNN>_*.sql` + Marker | **keine** |
| Migrations-Runner | `run-migrations.sh` (§6) | **keiner** |
| Backup-Runner | `scripts/db-backup.sh` Vorlage (§7) | **keiner im Default** |
| Knowledge-Pack | `knowledge/sql*.md` / `mongodb.md` | **keiner** |
| DBA-Agent-Audit | dispatcht bei `db_dialect != none` | **kein Dispatch** |
| `/preview`-Integration | DB-Service + Healthcheck-Wait + Migrations-Apply (§12) | Companion-Service + Healthcheck-Wait — **kein** Migrations-Schritt |
| Reviewer-Audit | DB-Pack-Checklist + Security-Floor | **nur** Security-Floor + Compose-Pflichten (Healthcheck, named Volume, kein hartkodiertes Passwort) |

**Scope-Lock (verbindlich):**

1. **Companions belegen NICHT den `db_dialect`-Slot.** `db_dialect: postgres` + `companions: [redis]` ist eine valide Kombination — Redis ist hier Cache, Postgres ist die primäre DB.
2. **Companion-Detection beeinflusst die Polyglott-Trigger-Heuristik (§16-R1) NICHT.** `companions: [redis]` zusätzlich zu `db_dialect: postgres` ist **kein** Polyglott-Fall — Polyglott meint ausschließlich mehrere **primäre DBs** (z.B. Postgres + Mongo gleichzeitig).
3. **Wer Redis als primären Datenstore nutzen will** (Event-Sourcing-Backbone, einziges System-of-Record), ist im DB-Subsystem falsch UND im Companion-Pfad falsch — das braucht einen eigenen Spec-PR (out-of-scope P1).

**§17a — Detection-Signal-Palette (kanonisch).** Analog §2: diese Tabelle ist die Single Source of Truth, `skills/adopt/SKILL.md` Schritt 2b spiegelt sie 1:1 wider. Neue Signal-Quellen werden zuerst hier ergänzt.

| Signal | → Companion |
|---|---|
| `package.json` deps: `redis`, `ioredis`, `bull`, `bullmq`, `connect-redis` | `redis` |
| `requirements.txt`/`pyproject.toml`: `redis`, `celery[redis]`, `rq`, `django-redis` | `redis` |
| `pom.xml`/`build.gradle`: `redis.clients:jedis`, `io.lettuce:lettuce-core`, `org.springframework.data:spring-data-redis` | `redis` |
| `pubspec.yaml` deps: `redis` | `redis` |
| Vorhandenes `docker-compose*.yml` Service `image:` enthält `redis` | `redis` |
| Env-Refs (`.env*`, `*.yml`): `REDIS_URL`, `REDIS_HOST`, `REDIS_PORT` | `redis` |

**Wiring-Pfad (Welle 3-äquivalent).** Heute (PR „companion-redis"):

- `templates/_shared/companion-redis/` (4 Files: `compose.fragment.yml`, `.env.redis.example`, `README.md`, `scripts/companion-info.sh`) — bereitgestellt.
- `skills/adopt/SKILL.md` Schritt 2b — Companion-Detection nach DB-Detection, idempotenter Fragment-Append, kein Auto-Fix.
- `skills/new-project/SKILL.md` `--companions <list>`-Flag + 1 optionale Frage (Default: keine) + Schritt 4d (Fragment-Scaffold).
- `agents/dba.md`: **unverändert** — Companions sind nicht DBA-Sache.
- `/preview` (Spec §12): Companions starten als reguläre Compose-Services beim `up`; **keine** Migrations-Apply-Stage. Detail-Wiring in einem Folge-PR (heute out-of-scope).

**Heute (P1) verfügbar:** `redis`. Weitere Companions kommen additiv in eigenen PRs — die Spec-Sektion ist so geschnitten, dass eine neue Engine nur §17a um Signale ergänzt und ein neues `templates/_shared/companion-<name>/`-Bundle hinzukommt; die Skill-Wiring-Schritte sind generisch über `<name>` parametrisiert.

Mit dieser Sektion ist die Companion-Klasse als eigener Vertrag etabliert — sauber abgegrenzt zum DB-Subsystem, additive Erweiterbarkeit, klarer Scope-Lock.

---

## §18 — Adoption-Validate (E2E-Smoke + Cache-Flag)

**Zweck.** Eingeführt mit dem Validate-PR (2026-05-31). Stellt sicher, dass das von `/adopt` bzw. `/new-project` angelegte Skeleton (Compose-Fragment + `db_scripts/`-Marker + Companion-Fragmente) **mechanisch trägt** — DB startet healthy, Marker-Migration appliziert, App-Container erreichbar. Das Ergebnis wird als Cache-Flag in `.claude/profile.md` persistiert, damit Folge-Aufrufe (`/preview up`) den teuren E2E-Smoke skippen können, solange das DB-/Companion-Setup unverändert ist.

**User-Konzept (Original-Vorgabe).** „Beim ersten Adopt einen E2E-Test, wenn fail → Loop, wenn ok → künftig überspringen oder beschleunigen, ggf. invalidieren bei DB-Wechsel."

**`profile.md`-Schema** (drei neue optionale Keys, alle Default leer):

```yaml
adoption_validated_at:         <ISO-8601-Datum oder null>   # leer = noch nie validiert; null = invalidated
adoption_validated_dialect:    <postgres|mysql|sqlite|mongodb>   # was zuletzt validiert wurde
adoption_validated_companions: [<liste>]                    # was zuletzt validiert wurde
```

`adoption_validated_dialect` und `adoption_validated_companions` halten den **Snapshot zum Zeitpunkt des Validate-PASS**. Bei Cache-Check vergleicht `/preview` diese gegen die aktuellen `db_dialect`/`companions` aus dem Profil — ein Unterschied zwingt zum Re-Validate.

**Konstanten.**

| Konstante | Wert | Wirkung |
|---|---|---|
| `MAX_VALIDATE_RETRIES` | `3` | Cap für den Coder-Fix-Loop in `/adopt` §6.c und `/new-project` §8. Danach human-handoff + Backlog-Issue. |

### Wer setzt / liest / invalidiert?

| Skill | Rolle | Pfad |
|---|---|---|
| `/adopt` §6 | **Setzt** (volle Validation mit Coder-Fix-Loop, max 3 Retries) | dispatch `tester` Adoption-Validate → bei PASS Flag schreiben |
| `/adopt re-validate` | **Setzt** (re-Run der vollen Validation, gleicher Loop) | identisch zu §6, ohne vorgelagerten Adopt-Aufwand |
| `/new-project` §8 | **Setzt** (volle Validation analog, post initial-commit) | dispatch `tester` → bei PASS Flag schreiben |
| `/preview up` §0 | **Liest** (Cache-Check) | vergleicht `adoption_validated_dialect`+`_companions` gegen aktuelles Profil |
| `/preview up` §6 | **Setzt** (Mini-Re-Validate, best-effort, kein Coder-Fix-Loop) | bei Cache-Miss und Stack-Up: tester-Mini-Smoke → bei PASS Flag refreshen |
| `/flow` §5a | **Invalidiert** (setzt auf `null`) | bei DB-/Companion-Profile-Diff oder Template-Pfad-Diff nach erfolgreichem Landen |

**Wichtig:** `/flow` **invalidiert nur**, setzt nie auf PASS. Das Setzen-Recht liegt ausschließlich bei `/adopt`/`/new-project` (volle Validation) und `/preview up` Mini-Re-Validate (kürzer, ohne Fix-Loop).

### Cache-Logik in `/preview up` (Cache-Hit vs Cache-Miss vs Invalidierung)

| Zustand | Bedingung | Verhalten |
|---|---|---|
| **Cache-Hit** | `adoption_validated_at` gesetzt UND `adoption_validated_dialect` == aktueller `db_dialect` UND `adoption_validated_companions` == aktuelle `companions` | Schneller preview-up (DB+App hoch, **keine** Trivial-Query / Marker-Verify). Output: `cache-hit: skip E2E re-validate`. |
| **Cache-Miss (Drift)** | Dialect oder Companions seit Validate geändert | Normaler preview-up + Mini-Re-Validate (Schritt 6). Bei PASS: Flag-Refresh. Bei FAIL: Warn, kein Abbruch. |
| **Cache-Miss (nie validiert)** | `adoption_validated_at` leer (z.B. erster `/preview up` nach `/adopt` ohne Validate-PASS) | Wie Drift — Mini-Re-Validate post-up. |
| **Invalidiert** | `adoption_validated_at: null` (von `/flow` §5a gesetzt) | Wie Drift — Mini-Re-Validate post-up. |
| **N/A** | `db_dialect: none` UND `companions: []` | Cache-Check skip — nichts zu validieren. |

### Invalidierungs-Regeln in `/flow` (§5a)

`/flow` setzt `adoption_validated_at: null` nach erfolgreichem Landen eines Items, **wenn** eines davon zutrifft:

1. Item-Diff ändert `profile.db_dialect` oder `profile.companions[]`.
2. Item-Diff berührt `db_scripts/run-migrations.sh`, `db_scripts/000_init_meta.{sql|js}`, oder den `# --- db-<dialect> (…)`-/`# --- companion-<name> (…)`-Bereich im Projekt-`docker-compose.yml` (Source-of-Truth-Marker, vom `/adopt`/`/new-project`-Append gesetzt).
3. Plugin-Update wurde gepullt, das `templates/_shared/db-<dialect>/` oder `templates/_shared/companion-<name>/` ändert (best-effort via Plugin-SHA-Tracking; fehlender Track-Wert = kein Trigger).

`adoption_validated_dialect` und `adoption_validated_companions` werden **nicht** gelöscht — sie bleiben als Audit-Trail erhalten ("was war zuletzt validiert"). Der `/preview`-Cache-Check liest `validated_at == null` als Cache-Miss und triggert Mini-Re-Validate.

### Fix-Loop-Disziplin

- **`/adopt` §6.c und `/new-project` §8:** voller Coder-Fix-Loop mit `MAX_VALIDATE_RETRIES = 3`. Coder darf **nur** das gerade gescaffoldete Skeleton (Marker-Migration, Run-Skript, Compose-Fragment-Append, `.env.db.example`) anpassen — keine Business-Code-Edits, keine Bestand-`db_scripts/`-Patches. Bei FAIL nach 3 Iterationen → human-handoff + GitHub-Issue (`adopt-validate-fail`/`new-project-validate-fail`-Label).
- **`/preview` §6:** Mini-Re-Validate **ohne** Coder-Fix-Loop — bei FAIL nur Warn-Output, preview-up bleibt nutzbar. Begründung: `/preview` ist ein Dev-Loop-Befehl, der nicht durch Verifikation blockieren darf; der schwergewichtige Fix-Pfad lebt in `/adopt re-validate`.
- **`/flow` §5a:** kein Fix-Loop — `/flow` invalidiert nur, dispatcht den `tester` nicht für Adoption-Validate (würde den Build-Loop §3 verzerren).

### Verhältnis zu den anderen Spec-Sektionen

- **§13 (DB-Subsystem-Smoke).** Komplett separates Konstrukt: §13 prüft die **Fabrik-Templates** (Tester-Agent läuft im `agent-flow`-Repo selbst). §18 prüft das **adoptierte/neue Projekt** (Tester-Agent läuft im Projekt-Repo, im Adoption-Validate-Modus). Kein Overlap — die `tester`-Definition (`agents/tester.md`) muss beide Modi unterstützen: bei Aufruf im agent-flow-Repo → DB-Subsystem-Smoke; bei Aufruf in einem Projekt-Repo mit Adoption-Validate-Auftrag → Adoption-Validate.
- **§14 (Build-Wellen).** §18 ist Welle-3-äquivalent (Wiring auf bestehende Templates + Skills + Agent) und folgt der Graceful-Degradation-Regel (§14-Amendment): wenn `tester`-Agent nicht erreichbar oder Adoption-Validate-Modus noch nicht implementiert, läuft `/adopt`/`/new-project` **ohne** Validate (Output „Validate skipped — tester unavailable") statt zu scheitern.
- **§16-R6 (`/adopt` darf scaffolden).** Validate ist die **Mechanik-Verifikation** für das Scaffolding aus R6 — schließt den Kreis: Scaffold → Validate → Cache → optional Re-Validate. Ohne Validate war R6 ein „wir hoffen, das Skeleton funktioniert"; mit §18 ist es „wir wissen, das Skeleton funktioniert".

Mit dieser Sektion ist der Validate-Mechanismus vollständig spezifiziert — additive Erweiterung der bestehenden Skill-Pipeline, kein Breaking Change für Projekte ohne DB/Companions (Validate skip), klare Trennung volle vs Mini-Validation.
