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

**Detection-Heuristik (`/adopt` und `/init`)** — erstes Match in dieser Reihenfolge gewinnt:

| Signal | → `db_dialect` |
|---|---|
| `package.json` deps: `mongoose`, `mongodb` | `mongodb` |
| `package.json` deps: `pg`, `postgres`, `prisma` (mit `provider = "postgresql"`) | `postgres` |
| `package.json` deps: `mysql2`, `mysql`, `prisma` (mit `provider = "mysql"`) | `mysql` |
| `package.json` deps: `better-sqlite3`, `sqlite3` | `sqlite` |
| `pom.xml`/`build.gradle`: `org.postgresql:postgresql` | `postgres` |
| `pom.xml`/`build.gradle`: `mysql:mysql-connector-j`, `org.mariadb.jdbc:mariadb-java-client` | `mysql` |
| `pubspec.yaml`: `postgres`, `supabase_flutter` | `postgres` |
| `pubspec.yaml`: `sqflite`, `drift`, `sembast_sqflite` | `sqlite` |
| Compose-Service `image:` enthält `postgres`, `supabase/postgres`, `timescale` | `postgres` |
| Compose-Service `image:` enthält `mariadb`, `mysql` | `mysql` |
| Compose-Service `image:` enthält `mongo` | `mongodb` |
| File-Endung `*.sqlite`, `*.db` im Repo-Root oder `data/` | `sqlite` |
| Verzeichnis `db_scripts/` mit `*.sql` und `CREATE TABLE` enthält `SERIAL`/`BIGSERIAL`/`uuid_generate_v4` | `postgres` |
| Verzeichnis `db_scripts/` mit `*.sql` und `AUTO_INCREMENT`/`ENGINE=InnoDB` | `mysql` |
| Verzeichnis `db_scripts/` mit `*.js` und `db.createCollection` | `mongodb` |
| sonst | **Frage stellen** (`AskUserQuestion` mit den 5 Enum-Werten) |

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
    001_init.sql              # postgres|mysql|sqlite
    002_<name>.sql
    003_<name>.js             # mongodb (mongosh script)
    run-migrations.sh         # dialekt-spezifischer Wrapper (Welle 2)
```

**Annahme (begründet):** Verzeichnis-Name `db_scripts/` (nicht `migrations/`, nicht `db/migrations/`) — übernommen aus dem Brewing-Projekt (Konsistenz mit existierender Praxis im Umfeld; ein etablierter Begriff schlägt drei plausible Alternativen). Mongo-Dateien sind `.js` (mongosh-syntax); SQL-Dateien sind `.sql` — die Endung trägt den Dialekt nicht, der kommt aus `profile.db_dialect`.

**Nummerierung.** 3-stellig, nullgepaddet, lückenlos, **forward-only**. Eine bereits committete Migration wird **nie editiert** (`coder/R02` für DB-Domäne — wird in den Packs verankert); Korrekturen werden als neue, höhere Nummer angehängt.

**Apply-Tracking — Marker-Tabelle pro Dialekt:**

| Dialekt | Tabelle/Collection | Schema |
|---|---|---|
| postgres | `public._schema_migrations` | `(version text PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT now())` |
| mysql | `_schema_migrations` | `(version VARCHAR(255) PRIMARY KEY, applied_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP)` |
| sqlite | `_schema_migrations` | `(version TEXT PRIMARY KEY, applied_at TEXT NOT NULL DEFAULT (datetime('now')))` |
| mongodb | Collection `_schema_migrations` | Document `{ _id: "<version>", applied_at: ISODate }` |

**Annahme (begründet):** Marker-Name `_schema_migrations` (Unterstrich-Präfix; angelehnt an Rails/Sqitch-Tradition, signalisiert „internes Tooling"). Bewusst nicht der Flyway/Liquibase-Default — wir betreiben einen schlanken eigenen Runner (keine Java-Runtime im Postgres-/JS-Container).

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
    README.md                  # erklärt: kein Service, nur Volume-Mount
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

**SQLite-Sonderfall.** Kein Service. Stattdessen ein **named Volume** im App-Service:

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

**Keine automatischen Edits.** `/adopt` schreibt nur `profile.db_dialect` und Backlog-Items; **keine** Auto-Migration, **kein** Auto-Compose-Patch (Konsistent mit „behebt nichts automatisch", `/adopt` Grenze).

---

## 10. `/new-project`-Erweiterung

**Neuer Flag.** `/new-project <name> [--lang <x>] [--db <dialect>]`.

**Ohne `--db`:** **Eine** zusätzliche Frage (`AskUserQuestion`) nach Stack-Frage und vor Board-Anlage:
> „DB-Dialekt? [postgres|mysql|sqlite|mongodb|none] (none = keine DB)"

**Was passiert je Wert:**

- `none`: `profile.db_dialect: none`. Kein DB-Pack, kein Compose-Fragment, kein `db_scripts/`-Skeleton, kein DBA-Dispatch beim ersten `requirement`-Lauf. `docs/data-model.md` wird **nicht** gescaffolded (bestand-Regel in `new-project` Schritt 4b bleibt — sie hängt heute schon an `domains: [sql]`, künftig an `db_dialect != none`).
- `postgres|mysql|sqlite|mongodb`: Das Fragment aus `templates/_shared/db-<dialect>/compose.fragment.yml` wird ans Projekt-`docker-compose.yml` angehängt. `db_scripts/` wird mit `001_init.sql` (bzw. `.js`) als **leere Vorlage** + dem dialekt-spezifischen `run-migrations.sh` angelegt. `docs/data-model.md` wird gescaffolded. Der `Dockerfile` der Sprache wird um den DB-CLI-Client ergänzt (psql / mariadb-client / sqlite3 / mongosh).

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

Die DB-Subsystem-Erweiterung wird in der Fabrik durch **vier Smoke-Projekte** verifiziert (eines pro Dialekt). Diese leben in `tests/smoke-db/` innerhalb des `agent-flow`-Repos und werden von einem neuen Workflow `tests/smoke-db.yml` (Welle 3) bei jedem PR ausgeführt, der `knowledge/sql*.md`, `knowledge/mongodb.md`, `templates/_shared/db-*` oder `skills/preview/SKILL.md` berührt.

**Smoke-Projekt-Struktur** (gilt für alle 4):

```
tests/smoke-db/<dialect>/
  docker-compose.yml         # App + (für 3 von 4 Dialekten) db
  Dockerfile                 # minimaler curl/echo-Service
  db_scripts/
    001_init.sql|js          # CREATE TABLE foo / createCollection
    run-migrations.sh
  expected.txt               # "ok" — Output des Smoke-SELECTs
```

**Smoke-Verlauf** (ein Skript `tests/smoke-db/run.sh`, vom CI-Job pro Dialekt aufgerufen):

1. `docker compose -p smoke-<dialect> up -d`.
2. Auf DB-Healthcheck warten (außer sqlite).
3. `run-migrations.sh` ausführen → muss exit 0.
4. **Idempotenz-Test:** `run-migrations.sh` ein zweites Mal ausführen → muss exit 0 (Marker filtert).
5. Smoke-Query gegen den DB-Service: ein `SELECT 1` / `db.foo.findOne()` aus einem Throwaway-Client-Container.
6. Output vergleichen mit `expected.txt`.
7. `docker compose -p smoke-<dialect> down -v`.
8. PASS = alle 4 Dialekte grün; ein roter = PR rot.

**Annahme (begründet):** Smoke testet **die Mechanik** (Runner, Marker, Idempotenz, Compose-Fragment), nicht den Pack-Inhalt (Pack-Korrektheit ist `reviewer`-/Mensch-Sache; bei wir testen würden, müssten wir den ganzen `/flow` simulieren — zu schwer für CI).

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
- `templates/_shared/db-sqlite/` (README + Volume-Snippet; keine compose-fragment).
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
- `tests/smoke-db/<dialect>/` + `.github/workflows/smoke-db.yml`.
- **Output:** End-to-end nutzbar.

**Parallelisierbarkeit:**
- Innerhalb Welle 1: alle 4 Packs + DBA-Agent unabhängig.
- Innerhalb Welle 2: alle 4 Fragment-Ordner unabhängig.
- Innerhalb Welle 3: 4 Skill-Edits sind serialisierbar, aber unabhängig voneinander; Smoke-Tests können nach jedem Skill-Edit laufen.

**Cross-Wellen:** Welle 2 darf erst beginnen, wenn Welle 1 (zumindest die jeweils referenzierten Pack-Regeln) gemerged ist. Welle 3 erst, wenn Welle 2 vollständig gemerged ist (Smoke-Tests in Welle 3 brauchen die Templates).

---

## 15. Risiken & offene Fragen

**R1 — Polyglott-Projekte ignoriert.** Eine App, die wirklich Postgres + Mongo gleichzeitig nutzt, passt nicht ins Modell. Mitigations-Pfad: spätere Welle mit `db_dialects: [a, b]`-Liste + Pack-Mehrfach-Laden. Frage: blockiert das jemanden konkret? — User-Entscheid offen.

**R2 — SQLite-Multi-Reader.** SQLite mit mehreren App-Replicas im Compose-Stack ist nicht safe (file-lock-Probleme). `/preview` baut heute genau 1 App-Container → kein Akut-Problem. Wenn das Plugin später Multi-Replica-Previews unterstützt, muss SQLite explizit auf „nur 1 Replica" gepinnt werden. **Frage: erwähnen wir das jetzt im sqlite-Pack als Hard-Limit?**

**R3 — Mongo-Transaktionalität.** Mongo-Migrationen sind nicht atomar (über Statements hinweg). Falls eine Migration auf halbem Weg crasht, bleibt der DB-State zwischen den Versionen. Mitigations: Idempotenz-Pflicht im `mongo/R01` (rerun muss sauber durchgehen). **Frage: brauchen wir ein Lock-Pattern (z.B. Single-Doc-Lock in `_schema_migrations`), um konkurrierende Runner auszuschließen?** — Im Plugin-Kontext (Preview, ein Runner) wahrscheinlich überflüssig.

**R4 — CLI-Clients im App-Image.** Ein `psql`/`mongosh` im Production-Image vergrößert Surface und Image-Größe. Mitigations-Optionen: (a) Multi-Stage-Build mit `migrations-Stage` (CLI nur im Build, nicht im Runtime); (b) Separater `init`-Container nur mit der CLI, der die App-Image-Größe nicht aufbläht. **Empfehlung: (b) ab Welle 2 — ein generisches `migrations`-Image (z.B. `alpine` + dialekt-CLI) statt CLI im App-Image.** Soll ich die Welle-2-Specs entsprechend umstellen? — User-Entscheid offen, default in dieser Spec ist noch (a).

**R5 — `tests/smoke-db.yml` läuft Docker-in-Docker auf GitHub Actions.** Funktioniert (DinD ist Standard), kostet aber Minuten. Bei langer Smoke-Pipeline → Lauf nur auf Pfad-Änderungen filtern (`paths:` in der workflow-Trigger-Config). **Geklärt:** Filter ist Pflicht (in Welle 3 spezifiziert).

**R6 — `domains: [sql]` Backwards-Compat.** Der einzeilige Fallback (`domains: [sql]` ohne `db_dialect` ⇒ `postgres`) muss in `coder`/`reviewer`/`tester`/`dba` konsistent geschrieben sein, sonst zerfällt der Bestand. **Frage:** Eigene Test-Datei dafür? — Ja, ein 5. Smoke-Projekt `tests/smoke-db/legacy-sql-domain/` in Welle 3.

**R7 — Sicherheits-Surface durch DB-Port-Mapping.** Compose-Fragmente mappen DB-Ports nach `localhost:<port>`. In Preview-Mode ist das ok (Dev-Maschine). Wenn das Compose je in Production wandert, ist das ein **Critical** (DB nach außen). **Mitigation:** Welle-2-Fragmente bekommen einen Kommentar „`ports:`-Block für Preview; in Production ENTFERNEN" — und ein `reviewer`-Regel-Eintrag im jeweiligen Pack.

**R8 — Backup-Default-Pfad.** Die Backup-Skripte sind nur Vorlagen, nicht standardmäßig im Projekt-`db_scripts/`. Für Bestandsprojekte aus dem Brewing-Umfeld (wo Backup kritisch ist) könnte das überraschen. Aber: Plugin bleibt minimal, Brewing hat sein eigenes Backup-Setup. **Entscheidung: stays as drafted, Brewing-Pfad nicht koppeln.**
