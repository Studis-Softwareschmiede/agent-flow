---
name: adopt
description: Adoptiert ein BESTEHENDES GitHub-Repo in die Fabrik — klont es (fremde Repos werden in die Org geforkt), übernimmt es per init (Stack erkennen, .claude/+docs/ scaffolden, Spec aus Code ableiten, CI/Security ergänzen), auditiert den Bestand gegen den Fabrik-Standard und legt die Funde als priorisiertes Backlog aufs Board. Behebt NICHTS automatisch — /flow arbeitet das Backlog ab. Aufruf: /agent-flow:adopt <owner/repo>.
---

# /adopt <owner/repo>

Bringt ein bestehendes Repo auf Fabrik-Standard: **clone/fork → adopt → audit → Backlog → (du wählst) → `/flow`**. Es wird **nichts automatisch behoben** — der Audit erzeugt Items, gefixt wird inkrementell per `/flow` + PR durchs Gate.

## 0. Auth
`bash "$CLAUDE_PLUGIN_ROOT/scripts/ensure-gh-auth.sh"`.

## 1. Beschaffen (clone / fork)
- **Org-eigen** (`<owner>` = `studis-softwareschmiede`): `gh repo clone studis-softwareschmiede/<repo>` → cwd = Klon. App hat Schreibrecht → Branch/PR direkt.
- **Fremd** (anderer Owner → kein Schreibrecht): **in die Org forken + klonen** — `gh repo fork <owner>/<repo> --org studis-softwareschmiede --clone --remote` (Original bleibt als `upstream`). Gearbeitet wird am **Org-Fork** (App-schreibbar); PRs gehen an den Fork; ein Upstream-PR ist optional und braucht deinen Approve.
  - **Issues am Fork einschalten** (Pflicht): GitHub liefert Forks mit **deaktivierten Issues** → direkt `gh repo edit studis-softwareschmiede/<repo> --enable-issues`. **Ohne das scheitert das Backlog** (Schritt 4, `gh issue create`). Issues/Board entstehen am **Fork**, nie am Upstream.

## 2. Adoptieren (= `init`-Pfad des `new-project`-Skills, idempotent)
Im Klon den **`/init`-Ablauf** ausführen — bestehende Dateien NICHT überschreiben:
- **Stack erkennen** (pubspec→flutter · pom/gradle→java · package.json→js/angular · `*.html`→html · `*.sql`→sql-Domäne) → bestätigen → `.claude/profile.md` (+ leere `lessons/`). **`profile.image` = `ghcr.io/studis-softwareschmiede/<repo-lowercase>`** — Fork-Repos haben oft Großbuchstaben (z.B. `Spoon-Knife`), das Docker-Image ist aber `spoon-knife` (Docker erlaubt keine Großbuchstaben).
- **`docs/` scaffolden + Spec aus Code ableiten:** concept/architecture/specs als **Entwurf** — dem User zur Durchsicht vorlegen, **verbindlich erst nach OK**.
- Fehlende `Dockerfile` / `.github/workflows/build.yml` / `security.yml` / `.github/dependabot.yml` aus `${CLAUDE_PLUGIN_ROOT}/templates/` ergänzen (Sprach-Ökosystem im dependabot.yml setzen).
- **Board** anlegen (`gh project create`) → Nummer ins Profil.

## 2a. DB-Detection (`profile.db_dialect` erstmalig setzen)
Spec [`docs/architecture/db-subsystem.md`](../../docs/architecture/db-subsystem.md) §2 + §9. Läuft **nach** dem Stack-Erkennen und **vor** dem Audit, damit der `reviewer` den richtigen DB-Pack (§3) laden kann.

**a) Auto-Detection — erstes Match gewinnt** (Reihenfolge bewusst: spezifische Engine-Deps vor generischen Compose-/File-Signalen):

| Signal (Quelle → Wert) | → `db_dialect` | Confidence |
|---|---|---|
| `package.json` deps: `mongoose`, `mongodb` | `mongodb` | high |
| `package.json` deps: `pg`, `postgres`, `pgvector`; `prisma` mit `provider = "postgresql"` | `postgres` | high |
| `package.json` deps: `mysql2`, `mysql`, `mariadb`; `prisma` mit `provider = "mysql"` | `mysql` | high |
| `package.json` deps: `better-sqlite3`, `sqlite3` | `sqlite` | high |
| `pubspec.yaml` deps: `postgres`, `supabase_flutter` | `postgres` | high |
| `pubspec.yaml` deps: `sqflite`, `drift`, `sembast_sqflite` | `sqlite` | high |
| `pom.xml`/`build.gradle`: `org.postgresql:postgresql` | `postgres` | high |
| `pom.xml`/`build.gradle`: `mysql:mysql-connector-j`, `org.mariadb.jdbc:mariadb-java-client` | `mysql` | high |
| `pom.xml`/`build.gradle`: `org.mongodb:mongodb-driver-sync`, `org.springframework.data:spring-data-mongodb` | `mongodb` | high |
| `requirements.txt`/`pyproject.toml`: `psycopg`, `psycopg2`, `asyncpg` | `postgres` | high |
| `requirements.txt`/`pyproject.toml`: `pymongo`, `motor` | `mongodb` | high |
| Vorhandenes `docker-compose*.yml` Service `image:` enthält `postgres`, `supabase/postgres`, `timescale`, `pgvector` | `postgres` | high |
| Vorhandenes `docker-compose*.yml` Service `image:` enthält `mariadb`, `mysql` | `mysql` | high |
| Vorhandenes `docker-compose*.yml` Service `image:` enthält `mongo` | `mongodb` | high |
| Compose-Healthcheck-String: `pg_isready` | `postgres` | medium |
| Compose-Healthcheck-String: `mongosh`, `mongo --eval` | `mongodb` | medium |
| Env-Refs (`.env*`, `*.yml`): `SUPABASE_URL`, `PG_*`, `POSTGRES_*`, `DATABASE_URL=postgres://` | `postgres` | medium |
| Env-Refs: `MYSQL_HOST`, `MARIADB_HOST`, `DATABASE_URL=mysql://` | `mysql` | medium |
| Env-Refs: `MONGO_URL`, `MONGODB_URI`, `DATABASE_URL=mongodb://` | `mongodb` | medium |
| Files `*.sqlite`, `*.sqlite3`, `*.db` im Repo-Root oder `data/` | `sqlite` | medium |
| SQLite-CLI in Scripts (`sqlite3 path/to/file`) | `sqlite` | low |
| `db_scripts/*.sql` enthält `SERIAL`/`BIGSERIAL`/`uuid_generate_v4` | `postgres` | low |
| `db_scripts/*.sql` enthält `AUTO_INCREMENT`/`ENGINE=InnoDB` | `mysql` | low |
| `db_scripts/*.js` enthält `db.createCollection` | `mongodb` | low |
| Kein Treffer | `none` (Vorschlag) | low |

**a.1) Polyglott-Trigger — Eskalation bei 2+ primären DB-Dialekten (Spec §16-R1).** Spec hält `profile.db_dialect` als **Single-Value-Enum** (P1, Polyglott vertagt auf P2). Trotzdem muss `/adopt` Polyglott-Repos **erkennen** und sichtbar **eskalieren**, damit die P2-Erweiterung vom realen Bedarf getrieben wird statt vergessen zu werden.

**Definition Primär-Store vs. Companion.** Die Polyglott-Heuristik zählt **nur primäre Datastores** (`postgres`, `mysql`, `sqlite`, `mongodb` — die Enum-Werte aus §2). **Companions** sind Cache-/Search-/Index-Schichten, die **nie** als primärer Store eingesetzt werden und in der Detection-Heuristik gar nicht erst auftauchen:

| Companion-Klasse | Beispiel-Signale | Rolle |
|---|---|---|
| Cache | `redis`, `memcached` | flüchtiger Key-Value |
| Search/Index | `elasticsearch`, `meilisearch`, `typesense` | sekundärer Index über den primären Store |

Companions werden **nicht** als `db_dialect`-Kandidaten gewertet (Postgres + Redis ist die Standard-Web-App, **nicht** Polyglott) — sie werden in `.claude/profile.md` separat als `companions: [redis, …]` getrackt (additive Liste, keine Behandlungs-Pflicht in P1). Die Detection-Tabelle in §2 listet bewusst keine Companion-Signale; sollte das künftig nachgezogen werden (z.B. `package.json` deps: `ioredis` → `companions: [redis]`), gehört das in einen separaten Pfad und **nicht** in die Dialekt-Spalte.

**Trigger-Bedingung.** Polyglott-Eskalation **nur**, wenn die Detection in Schritt **a)** im selben Repo **2 oder mehr verschiedene primäre Dialekte mit `high`-Confidence** trifft (z.B. `postgres` aus `package.json: pg` UND `mongodb` aus `package.json: mongoose`). Treffer in `medium`/`low` reichen **nicht**, weil dort die false-positive-Rate zu hoch ist (z.B. env-ref ohne aktive Nutzung).

**Edge-Case 2 SQL-Dialekte (typisches Test-Setup, kein echtes Polyglott).** Wenn die 2 high-Treffer beide SQL-Dialekte sind (`postgres` + `sqlite`, `mysql` + `sqlite`, oder selten `postgres` + `mysql`), ist das meist ein App+Test-Setup (Production-Postgres, In-Memory-SQLite für Tests) — **nicht** echtes Polyglott. In dem Fall: die Polyglott-Eskalation **downgraden** auf `medium`-Confidence, sichtbarer Log-Hinweis („Likely test-/embedded-DB combo, not true polyglott — confirm with user"), kein Auto-Issue. Echtes Polyglott (cross-paradigm) ist erst `postgres|mysql|sqlite` × `mongodb`.

**Bei echtem Polyglott — 3-Schritt-Eskalation:**

1. **User wählt trotzdem EINEN Dialekt für P1.** Die AskUserQuestion in Schritt **c)** bleibt 1-aus-5; vor der Frage explizit anzeigen, welche Dialekte mit welcher Evidence erkannt wurden, damit der User informiert wählt. `profile.db_dialect` bleibt Single-Value (Spec §2 + §16-R1).
2. **Automatisch GitHub-Issue im aktuellen Repo (Fork) anlegen.** Vor `gh issue create` sicherstellen, dass Issues am Fork aktiviert sind (vgl. Schritt 1 — Forks haben Issues default-off):
   - **Titel:** `⚠ POLYGLOTT-BEDARF: <X> + <Y> primär — P2-Architektur-Erweiterung nötig` (X/Y alphabetisch sortiert für Idempotenz)
   - **Body:**
     ```
     ## Polyglott-Erkennung in /adopt

     Repo nutzt **2 oder mehr primäre DB-Dialekte** gleichzeitig:

     - **<X>** (high-Confidence) — Evidence: <Pfad:Zeile + Signal>
     - **<Y>** (high-Confidence) — Evidence: <Pfad:Zeile + Signal>

     ## Konsequenz für P1
     `/adopt` hat `<gewählter Dialekt>` als `profile.db_dialect` gesetzt (Single-Value, Spec §2).
     **<anderer Dialekt>-Integration ist in der aktuellen Fabrik nicht abgedeckt** —
     der DB-Pack, das Compose-Fragment und der Migration-Runner für <anderer Dialekt>
     werden NICHT ausgerollt; die Datenzugriffs-Schicht im App-Code wird vom `reviewer`
     ausschließlich gegen den `<gewählter>`-Pack geprüft.

     ## P2-Trigger
     Siehe `docs/architecture/db-subsystem.md` §16-R1 — Polyglott-Support
     (`db_dialects: [a, b]` Liste + Pack-Mehrfach-Laden + multi-Compose-Fragmente)
     ist explizit auf P2 vertagt; **dieses Issue ist die Eskalation, die den P2-Bedarf belegt**.
     Sobald 2+ unabhängige Projekte diesen Issue produzieren, ist P2 zu starten.

     ## Companions ausgeschlossen
     Redis/Memcached/Elasticsearch & Co. zählen NICHT als Polyglott (sind Cache/Index,
     keine primären Stores). Dieses Issue ist **nur** dann gerechtfertigt, wenn beide
     erkannten Dialekte echte Datastores sind.
     ```
   - **Labels:** `polyglott-needed`, `architecture` (bei Bedarf vorher mit `gh label create` anlegen — fehlende Labels dürfen Issue-Erstellung **nicht** blockieren; Fallback: ohne Labels anlegen + Hinweis loggen).
3. **Console-Output beim Adopt-Lauf** (eigene Zeile, deutlich abgesetzt — **nicht** in einer Loglinie zwischen Dutzend Detection-Zeilen verstecken):
   ```
   ============================================================
   ⚠ Polyglott detected: this repo uses <X> + <Y>.
     Adopted <chosen> for P1. Issue #<N> created for polyglott support.
   ============================================================
   ```
   Erscheint **zusätzlich** zum normalen Detection-Output und wird am Ende des `/adopt`-Reports (Schritt 5) wiederholt, damit der User es im Final-Report nicht übersieht.

**Nicht-Pflicht / Out-of-Scope für die Polyglott-Eskalation.** Es wird **nichts** für den nicht-gewählten Dialekt gescaffolded (kein zweites Compose-Fragment, kein zweites `db_scripts/`, kein zweiter Pack-Reviewer-Lauf). Wer den zweiten Dialekt produktiv betreiben will, muss heute manuell außerhalb der Fabrik nachziehen und auf P2 warten — genau das macht die Eskalation sichtbar.

**b) Evidence sammeln.** Für den höchsten Hit Pfad + Zeilennummer (oder Datei-Pfad bei File-Signalen) merken — die Evidence wird der User-Frage UND der `profile.md` als Kommentar mitgegeben („Audit-Trail"). Bei Polyglott (a.1): Evidence für **alle** high-Treffer separat sammeln (für den Issue-Body).

**c) User-Bestätigung — Pflicht, auch bei `high`-Confidence** (AskUserQuestion, 5 Enum-Werte vorselektiert):
```
Detected db_dialect: postgres (confidence: high, evidence: package.json:42 ["pg": "^8.13.0"])
Confirm? [Y/n/postgres/mysql/sqlite/mongodb/none]
```
Begründung: Detection-Heuristiken haben Edge-Cases (z.B. ein altes `pg` als Transitive Dep ohne aktive DB-Nutzung) — der User entscheidet final.

**d) In `.claude/profile.md` schreiben:**
```yaml
db_dialect: <wert>   # auto-detected from <evidence>, confirmed <YYYY-MM-DD>
```

**e) Wenn `db_dialect != none` — Compose-Fragment + Skeleton ergänzen, IDEMPOTENT:**
- **Fragment-Quelle:** `${CLAUDE_PLUGIN_ROOT}/templates/_shared/db-<dialect>/compose.fragment.yml`.
- **Vorhandenes Projekt-`docker-compose.yml`** ohne DB-Service (`services.db` fehlt, bei sqlite: `services.migrations` fehlt): Fragment **anhängen** (`cat fragment >> docker-compose.yml`) — sauber, weil das Fragment selbst nur die neuen Service-/Volume-Blöcke enthält. Vor dem Append eine Trennzeile `# --- db-<dialect> (added by /adopt, source: templates/_shared/db-<dialect>/compose.fragment.yml) ---` einfügen.
- **Vorhandenes `docker-compose.yml` MIT db-Service**: **nicht überschreiben** — stattdessen Fragment als separate Datei `docker-compose.db.yml` ablegen + READMEs/Backlog-Item „Compose-DB-Service gegen Fabrik-Standard abgleichen" anlegen (Mensch entscheidet beim Merge).
- **`db_scripts/`-Skeleton kopieren, falls Verzeichnis fehlt:**
  - `db_scripts/000_init_meta.sql` (postgres/mysql/sqlite) bzw. `000_init_meta.js` (mongodb) aus `templates/_shared/db-<dialect>/db_scripts/`.
  - `db_scripts/run-migrations.sh` aus demselben Ordner (ausführbar; `chmod +x`).
- **`.env.db.example`** aus dem Template ans Repo-Root kopieren (falls noch nicht vorhanden) — als Vorlage für die DB-spezifischen env-Variablen.
- **`scripts/db-backup.sh` + `db-restore.sh`** sind Vorlagen, **NICHT** automatisch kopieren (Brewing-Erfahrung: Backup-Strategie ist projekt-spezifisch, §7) → stattdessen Backlog-Item „Backup/Restore aus `templates/_shared/db-<dialect>/scripts/` ziehen, wenn benötigt".

**f) Wenn `db_dialect != none` — DBA-Audit dispatchen** (Spec §9, Audit-Modus):
- Der `reviewer` lädt im Audit-Modus zusätzlich zum Sprach-Pack den passenden DB-Pack (§3-Auswahl: `postgres`→`knowledge/sql.md`, `mysql`→`sql-mysql.md`, `sqlite`→`sql-sqlite.md`, `mongodb`→`mongodb.md`).
- Prüft bei vorhandenem `db_scripts/`: **Nummerierungs-Lücken** (`001`, `002`, … lückenlos?), **doppelte Versionen**, **Idempotenz-Patterns** (`CREATE TABLE IF NOT EXISTS` etc. pro Dialekt, §4), **Forward-only-Disziplin** (keine in-place-Edits committeter Migrationen — git-log-basiert), **Security-Floor** (unparametrisierte Queries, Plaintext-Credentials in `.env.example` / SQL-Files / Code).
- Prüft Compose-Konformität (Fragment-Pflichten §5): `restart: unless-stopped`, healthcheck vorhanden, benanntes Volume, Port-Mapping über env-Variable, **keine hartkodierten Passwörter**.
- Findings als priorisierte Backlog-Items (Schritt 4) — Security-Floor-Verstöße → Critical, fehlende Idempotenz → Important, Style-Drift → Suggestions.
- **Existiert nach Skeleton-Kopie immer noch kein `db_scripts/run-migrations.sh`** (Skeleton-Copy wurde übersprungen, weil ein bestehender, abweichend benannter oder strukturierter Runner gefunden wurde) → Backlog „Bestehenden Migration-Runner gegen Fabrik-Pattern angleichen (§6)".
- **Fehlt das Compose-Fragment** und konnte nicht angehängt werden (Konflikt mit bestehendem db-Service) → Backlog „DB-Service im Compose gegen `templates/_shared/db-<dialect>/compose.fragment.yml` abgleichen" (Priority: Important).

**g) Kein Auto-Fix.** Wie der ganze `/adopt`-Pfad: 2a schreibt nur `profile.db_dialect`, kopiert idempotent **Skeleton**-Dateien (die per Definition nichts überschreiben) und erzeugt Backlog-Items. **Keine** automatische Migrations-Ausführung, **kein** Auto-Patch von App-Code.

## 3. Auditieren (gegen den Fabrik-Standard)
- **Automatik zuerst (objektiv, billig):** `gitleaks detect --source=. --no-git` (Secrets) + Dependency-Audit gemäß Sprache (`npm audit --omit=dev` / `pip-audit` / …) → Funde notieren.
- **`reviewer` im Audit-Modus** (Task — s. `reviewer.md` „Audit-Modus"): prüft den **Bestand** (kein Diff) gegen **Security-Floor** (immer), die Sprach-/Domänen-**Pack-Checklists**, Projekt-Konventionen und die **abgeleitete Spec** → priorisierte Funde (Critical/Important/Suggestions). Bei großen Repos **priorisiert** (Security-Floor überall; Pack-Checks auf repräsentative/heikle Dateien — Auth, Daten-/Netz-Zugriff, Eingänge; Architektur-Auffälligkeiten), NICHT zeilenweise.

## 4. Backlog anlegen
Aus den Funden **Board-Items** (Status To Do), **Critical zuerst**: pro Item ein GitHub-Issue mit **Acceptance** („<Fund> auf Standard `<Regel-ID>`/Prinzip beheben") + Priority; verwandte Funde **clustern** (kein 1-Item-pro-Zeile-Dump). Security-Floor-Verstöße → höchste Priority. Wo sinnvoll auf die abgeleitete Spec/AC verweisen.

## 5. Übergabe (KEIN Auto-Fix)
Report an den User: Repo-/Fork-URL · Board-URL · Funde nach Schwere (#Critical / #Important / #Suggestions) · die abgeleiteten Specs. → „Wähle die Items, die behoben werden sollen, und starte `/agent-flow:flow`." **Stop.**

## Grenzen
- **Behebt nichts automatisch** — erzeugt nur das Backlog; Fix = `/flow` (PR-gated).
- Pusht NUR auf das Org-Repo bzw. den Org-Fork — **nie** ungefragt auf ein fremdes Upstream (Upstream-PR nur auf deinen Wunsch + Approve).
- Idempotent: bestehende `.claude/`-/`docs/`-Dateien nicht überschreiben (mergen/fragen).
- Die **abgeleitete Spec ist Entwurf**, bis du sie bestätigst (sie ist danach die Drift-Gate-Referenz für `/flow`).
- **DB-Detection (Schritt 2a) ist nicht-destruktiv:** schreibt `db_dialect`, hängt Compose-Fragment **nur** an, wenn noch kein db-Service existiert; bestehende `db_scripts/`-Dateien werden **nie** überschrieben — Konflikte landen als Backlog-Item, nicht als Auto-Patch.
