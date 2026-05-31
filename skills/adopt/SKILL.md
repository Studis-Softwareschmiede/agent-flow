---
name: adopt
description: Adoptiert ein BESTEHENDES GitHub-Repo in die Fabrik — klont es (fremde Repos werden in die Org geforkt), übernimmt es per init (Stack erkennen, .claude/+docs/ scaffolden, Spec aus Code ableiten, CI/Security ergänzen), auditiert den Bestand gegen den Fabrik-Standard, legt die Funde als priorisiertes Backlog aufs Board und validiert das Skeleton end-to-end via tester-Agent (Cache-Flag profile.adoption_validated_at). Behebt NICHTS automatisch — /flow arbeitet das Backlog ab. Aufruf: /agent-flow:adopt <owner/repo> | /agent-flow:adopt re-validate.
---

# /adopt <owner/repo>   ·   /adopt re-validate

Bringt ein bestehendes Repo auf Fabrik-Standard: **clone/fork → adopt → audit → Backlog → Validate (E2E-Smoke) → (du wählst) → `/flow`**. Es wird **nichts automatisch behoben** — der Audit erzeugt Items, gefixt wird inkrementell per `/flow` + PR durchs Gate. Der **Validate-Step** (§6) prüft das Skeleton end-to-end via `tester`-Agent und schreibt das Cache-Flag `profile.adoption_validated_at` (Spec [`docs/architecture/db-subsystem.md`](../../docs/architecture/db-subsystem.md) §18).

`/adopt re-validate` (Mode ohne `<owner/repo>`): cwd = bereits adoptiertes Repo. Läuft **nur** den Validate-Step (§6) erneut — nützlich nach manuellen Spec-/Template-Updates oder wenn `adoption_validated_at` durch `/flow` invalidiert wurde (Spec §18). Keine Detection, kein Scaffold, kein Audit; springt direkt zu §6.

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
| `pom.xml`/`build.gradle`: `mysql:mysql-connector-j` ODER `mysql:mysql-connector-java` (legacy coords, pre-Mai-2023 — B7-Fix), `org.mariadb.jdbc:mariadb-java-client` | `mysql` | high |
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

## 2b. Companion-Detection (`profile.companions[]` ergänzen)
Spec [`docs/architecture/db-subsystem.md`](../../docs/architecture/db-subsystem.md) §17. Companions = stateful Sidecars **OHNE** Schema-Evolution (Cache/Queue/Sessions/Pub-Sub). Läuft **nach** der DB-Detection (2a), unabhängig vom DB-Pfad — `db_dialect: none` schliesst Companions nicht aus.

**Wichtig (Scope-Lock):** Companions belegen **NICHT** den `db_dialect`-Slot — der bleibt für primäre DBs reserviert. Die Companion-Detection beeinflusst die Polyglott-Trigger-Heuristik (§2 / Spec §16-R1) **nicht**.

**a) Auto-Detection — pro Companion separat** (heute nur `redis` verfügbar; weitere Companions additiv in eigenen PRs):

| Signal (Quelle → Wert) | → Companion |
|---|---|
| `package.json` deps: `redis`, `ioredis`, `bull`, `bullmq`, `connect-redis` | `redis` |
| `requirements.txt`/`pyproject.toml`: `redis`, `celery[redis]`, `rq`, `django-redis` | `redis` |
| `pom.xml`/`build.gradle`: `redis.clients:jedis`, `io.lettuce:lettuce-core`, `org.springframework.data:spring-data-redis` | `redis` |
| `pubspec.yaml` deps: `redis` (Dart-Client) | `redis` |
| Vorhandenes `docker-compose*.yml` Service `image:` enthält `redis` | `redis` |
| Env-Refs (`.env*`, `*.yml`): `REDIS_URL`, `REDIS_HOST`, `REDIS_PORT` | `redis` |
| Kein Treffer | (keiner) |

**b) User-Bestätigung — Pflicht bei Treffer** (AskUserQuestion):
```
Detected companion: redis (evidence: package.json:38 ["ioredis": "^5.4.1"])
Add to profile.companions[]? [Y/n]
```

**c) In `.claude/profile.md` schreiben** (Liste, additiv — bestehende Werte erhalten):
```yaml
companions: [redis]   # auto-detected from <evidence>, confirmed <YYYY-MM-DD>
```

**d) Wenn Companion bestätigt — Compose-Fragment + .env-Vorlage ergänzen, IDEMPOTENT:**
- **Fragment-Quelle:** `${CLAUDE_PLUGIN_ROOT}/templates/_shared/companion-<name>/compose.fragment.yml`.
- **Vorhandenes Projekt-`docker-compose.yml`** ohne Companion-Service (z.B. `services.redis` fehlt): Fragment **anhängen** mit Trennzeile `# --- companion-<name> (added by /adopt, source: templates/_shared/companion-<name>/compose.fragment.yml) ---`.
- **Vorhandenes `docker-compose.yml` MIT Companion-Service**: **nicht überschreiben** — Fragment in separate `docker-compose.<name>.yml` ablegen + Backlog-Item „Companion-Service gegen Fabrik-Standard abgleichen".
- **`.env.<name>.example`** (z.B. `.env.redis.example`) ans Repo-Root kopieren, falls noch nicht vorhanden.
- **KEIN `db_scripts/`-Skeleton, KEIN Migrations-Runner, KEIN Backup-Skript** — Companions haben per Definition keine Schema-Evolution (Spec §17 Scope-Lock).
- **KEIN DBA-Audit-Dispatch** — Companions sind Infra, nicht DB. Audit-Findings (z.B. Companion-Service ohne Healthcheck, hartkodiertes Passwort im Compose) gehen über den normalen `reviewer`-Audit (Schritt 3).

**e) Kein Auto-Fix.** Identisch zu 2a-g: 2b schreibt nur `profile.companions[]`, kopiert nicht-destruktives Skeleton, erzeugt ggf. Backlog-Items. Bestehende Companion-Services im Compose werden **nie** überschrieben.

## 2c. Framework/Build-Detection (`profile.build` + `profile.frameworks[]`)
Heuristik gemäß [`docs/architecture/framework-build-subsystem.md`](../../docs/architecture/framework-build-subsystem.md) §6. Erstes Match je Achse gewinnt; mehrere Frameworks für DIESELBE Sprache lösen den Polyglott-Trigger aus (siehe Schritt 2d). Läuft **nach** der Companion-Detection (2b) und **vor** dem Audit (3), damit `reviewer`/`tester` den richtigen Framework-/Build-Pack laden können (Spec §3 Pack-Auswahl-Regel).

**Aufbau analog 2a:** Build-Tool-Achse zuerst (single-value, Pflicht ab Sprachen mit Build-Tool), Framework-Achse danach (multi-value, optional). User-Bestätigung pro Achse — auch bei `high`-Confidence — analog zur DB-Detection (§2a-c).

**a) Build-Tool-Achse** (`profile.build`, single-value):

| Signal | → setzt | Confidence |
|---|---|---|
| `pom.xml` | `build: maven` | high |
| `build.gradle` / `build.gradle.kts` / `settings.gradle{,.kts}` | `build: gradle` | high |
| `package.json` + `package-lock.json` | `build: npm` | high |
| `pnpm-lock.yaml` | `build: pnpm` | high |
| `pyproject.toml` + `uv.lock` | `build: uv` | high |
| `Cargo.toml` | `build: cargo` | high |
| keine der Signale | `build: none` (Default, **mit User-Bestätigung via AskUserQuestion** — auch `none` bedarf der Bestätigung, weil ein Repo möglicherweise einen externen Build-Mechanismus hat, den die Heuristik nicht sieht) | — |

**b) Framework-Achse** (`profile.frameworks: []`, multi-value, optional):

| Signal | → setzt | Confidence |
|---|---|---|
| `pom.xml` mit `spring-boot-starter-parent` ODER `org.springframework.boot:*` Dep | `frameworks += spring-boot@<major>` | high |
| `build.gradle*` mit `org.springframework.boot` Plugin/Dep | `frameworks += spring-boot@<major>` | high |
| `pom.xml`/`build.gradle*` mit `io.quarkus:*` | `frameworks += quarkus@<major>` | high |
| `package.json` dep `react` | `frameworks += react@<major>` | high |
| `package.json` dep `vue` | `frameworks += vue@<major>` | high |
| `package.json` dep `@angular/core` | `frameworks += angular@<major>` | high |
| `requirements.txt`/`pyproject.toml` mit `django>=` | `frameworks += django@<major>` | high |
| `requirements.txt`/`pyproject.toml` mit `fastapi>=` | `frameworks += fastapi@<major>` | high |
| `requirements.txt`/`pyproject.toml` mit `flask>=` | `frameworks += flask@<major>` | high |

**c) Major-Extraktion.** Aus dem Version-Constraint die niedrigste passende Major-Version nehmen:
- `^18.2.0` → `18` (Caret-Range)
- `~5.1` → `5` (Tilde-Range)
- `>=3.4,<4` → `3` (Untere Grenze)
- `>=2,<4` → `2` UND `[POLYGLOTT-WARN]`-Marker (Spannweite über Majors → User soll Profil schärfen)
- Wildcard `*`/`x` ohne Untergrenze → AskUserQuestion mit „kein Major bestimmt"

**d) User-Bestätigung — Pflicht, auch bei `high`-Confidence** (AskUserQuestion, beide Achsen einzeln):
- **build:** single-select aus Tabellen-Werten + `none`; Voreinstellung = Heuristik-Vorschlag.
- **frameworks:** multi-select aus den Heuristik-Treffern; Skip-Option immer dabei; Voreinstellung = alle vorgeschlagen.

**e) In `.claude/profile.md` schreiben:**
```yaml
build: <wert>           # auto-detected from <evidence>, confirmed <YYYY-MM-DD>
frameworks: [<id>@<major>, …]   # auto-detected from <evidence>, confirmed <YYYY-MM-DD>
```

**f) Pack-Vorhandensein-Check + Backlog-Items** (Standard-Priorität Important):
- **Framework-Pack fehlt:** für jedes gewählte Framework prüfen, ob `${CLAUDE_PLUGIN_ROOT}/knowledge/frameworks/<id>-<major>.md` existiert. Fehlt: Backlog-Item „Pack `<id>@<major>` anlegen (via `/train <id>@<major>` oder manuelle Spec)".
- **Build-Pack fehlt:** analog für `${CLAUDE_PLUGIN_ROOT}/knowledge/build/<build>.md`. Fehlt: Backlog-Item „Pack `build/<build>` anlegen".
- **Polyglott-Eskalation:** siehe Schritt 2d.

**g) Kein Auto-Fix.** Analog 2a-g/2b-e: 2c schreibt nur `profile.build` und `profile.frameworks[]`, erzeugt ggf. Backlog-Items. **Kein** automatischer Pack-Anlage-Lauf, **kein** Auto-Patch von App-Code oder Build-Files.

**Multi-Lang-Erkennung (für `profile.lang` Array-Form, siehe `docs/architecture/framework-build-subsystem.md` §2):** wenn die Heuristik **2+ primäre Sprachen** in EINEM Repo findet — typischerweise via expliziter Multi-Modul-Marker:

| Marker | Multi-Lang-Indikator |
|---|---|
| Maven Multi-Modul (`<packaging>pom</packaging>` + `<modules>` mit Sub-Modulen, die UNTERSCHIEDLICHE Sprachen haben) | ja |
| npm/pnpm `workspaces` mit Sprach-fremden Sub-Packages (z.B. Workspace mit `pom.xml` darin) | ja |
| Repo-Root hat sowohl `pom.xml` (Java) ALS AUCH `package.json` (TS/JS) mit eigenem `src/` | ja |
| Cargo `[workspace]` mit Cross-Sprach-Mitgliedern | ja |

Bei Multi-Lang-Treffer **schreibt `/adopt` `lang: [java, ts]`** (Array-Form) statt einzelner Wert. **AskUserQuestion** bestätigt den Vorschlag (multi-select: alle erkannten Sprachen vorausgewählt). Keine separate Polyglott-Eskalation (Polyglott meint MEHRERE Frameworks pro Sprache — nicht mehrere Sprachen pro Repo; siehe Spec §7).

## 2d. Polyglott-Eskalation (Frameworks)
Wiederverwendung des in Schritt 2a für DB-Dialekte etablierten Mechanismus ([`docs/architecture/db-subsystem.md`](../../docs/architecture/db-subsystem.md) §16-R1 und [`docs/architecture/framework-build-subsystem.md`](../../docs/architecture/framework-build-subsystem.md) §7).

**Trigger.** Detection findet **2+ HIGH-Confidence-Frameworks für DIESELBE Sprache** (z.B. `spring-boot@3` + `quarkus@3` im selben Java-Projekt, oder `vue@3` + `angular@17` im selben TS-Projekt).

**Nicht-Trigger:**
- Polyglott über **verschiedene Sprachen** (Java-Backend + React-Frontend im Mono-Repo) — das ist normal, kein Eskalations-Fall. Die Heuristik gruppiert die Detection nach `profile.lang` — der Trigger feuert nur, wenn die Konfliktmenge innerhalb **einer** Sprach-Bucket liegt (Spec §7).
- **Companions** (Redis, Memcached) zählen NICHT als Framework — sie werden separat in Schritt 2b behandelt.
- **Framework-Familien** (z.B. `spring-boot` + `spring-data` + `spring-security` mit gleichem Prefix) sind **komplementär**, nicht rivalisierend — kein Trigger (Spec §7).

**Aktionen bei Trigger:**

1. `AskUserQuestion` mit den gefundenen Frameworks als Optionen (multi-select erlaubt; Default = alle vorgeschlagen) — der User wählt, welche Frameworks in `profile.frameworks[]` landen.
2. **Auto-Backlog-Issue** im aktuellen Repo (Fork):
   - **Titel:** `⚠ POLYGLOTT-FRAMEWORK-BEDARF: <X> + <Y> in <lang> — Architektur-Entscheidung dokumentieren`
   - **Body:** Welcher Framework ist primär? Migration geplant? Verweis auf [`docs/architecture/framework-build-subsystem.md`](../../docs/architecture/framework-build-subsystem.md) §7 + [`docs/architecture/db-subsystem.md`](../../docs/architecture/db-subsystem.md) §16-R1 (Pattern-Quelle).
   - **Labels:** `polyglott-needed`, `architecture` (Fallback ohne Labels analog 2a a.1).
   - **Priorität:** Important.
3. **Console-Output** (eigene Zeile, deutlich abgesetzt — vor der User-Frage):
   ```
   ============================================================
   ⚠ POLYGLOTT: <N> Frameworks für <lang> detektiert (<liste>)
     — siehe Backlog-Item #<n> für Klärung.
   ============================================================
   ```

**Spec-Verweise:** [`docs/architecture/framework-build-subsystem.md`](../../docs/architecture/framework-build-subsystem.md) §7 (Framework-Polyglott) + [`docs/architecture/db-subsystem.md`](../../docs/architecture/db-subsystem.md) §16-R1 (Pattern-Quelle).

## 2f. Migration-Tool-Detection (`profile.db_migration_tool`)
Spec [`docs/architecture/migration-tool-subsystem.md`](../../docs/architecture/migration-tool-subsystem.md) §6 (Heuristik) + §5 (Default-Mapping) + §8 (Konfliktpunkt mit `db_scripts/`). Läuft **nach** der Framework/Build-Detection (2c) und Polyglott-Eskalation (2d), und **vor** dem Audit (3) — damit `reviewer`/`tester` den richtigen Migration-Pack laden können (Spec §7 Pack-Auswahl-Regel).

**Sonderfall `db_dialect: none`:** Migration-Tool-Detection wird **übersprungen** (kein db_dialect ⇒ keine Migrations). `profile.db_migration_tool` wird nicht geschrieben (bleibt fehlend ⇒ Default `skeleton` per Backwards-Compat §11).

**a) Auto-Detection — erstes Match gewinnt** (Reihenfolge: spezifische Tool-Coordinates vor generischen Verzeichnis-Signalen; Major-Version aus Dep-Version):

| Signal (Quelle → Wert) | → `db_migration_tool` | Confidence |
|---|---|---|
| `pom.xml`/`build.gradle*` dep `org.flywaydb:flyway-core` (Version → Major) | `flyway@<major>` | high |
| `pom.xml`/`build.gradle*` dep `org.liquibase:liquibase-core` (Version → Major) | `liquibase@<major>` | high |
| `package.json` dep `prisma` ODER `@prisma/client` | `prisma` | high |
| `package.json` dep `knex` | `knex` | high |
| `package.json` dep `typeorm` | `typeorm` | high |
| `package.json` dep `sequelize` ODER `sequelize-cli` | `sequelize` | high |
| `requirements.txt`/`pyproject.toml` dep `alembic` | `alembic` | high |
| `requirements.txt`/`pyproject.toml` dep `django` UND Verzeichnis `*/migrations/__init__.py` (Django-Auto-Generated) | `django-migrations` | high |
| `pubspec.yaml` dep `sqflite` | `sqflite` | high |
| Verzeichnis `supabase/migrations/` UND `supabase/config.toml` | `supabase` | high |
| `Cargo.toml` dep `sqlx` UND Verzeichnis `migrations/` mit `*.sql` | `sqlx-cli` | high |
| `Cargo.toml` dep `refinery` | `refinery` | high |
| `migrate`-Binary-Aufrufe in `Makefile`/CI-Scripts ODER Repo enthält `migrate.exe`/`migrate` direkt | `golang-migrate` | medium |
| Verzeichnis `db_scripts/` MIT `run-migrations.sh` UND `[0-9][0-9][0-9]_*.sql`-Dateien UND Marker `_schema_migrations` in den Files | `skeleton` | high |
| Kein Treffer | (kein Eintrag → fallback per §5 Default-Mapping nach `lang`+`db_dialect`, dann User-Bestätigung) | — |

**b) Default-Mapping bei Kein-Treffer** (Spec §5): wenn die Auto-Detection nichts findet UND `db_dialect != none`, schlägt der Skill das Default-Tool gemäß `profile.lang` + `profile.db_dialect` vor:

| `lang` | `db_dialect` | Default-Vorschlag |
|---|---|---|
| `java` | `postgres`/`mysql`/`sqlite` | `flyway@10` (Spring-Standard) |
| `ts`/`js` | `postgres`/`mysql`/`sqlite` | `skeleton` (kein dominantes Tool im Node-Ökosystem) |
| `py` | `postgres`/`mysql`/`sqlite` | `alembic` (SQLAlchemy-Standard; bei Django: `django-migrations`) |
| `flutter` | `sqlite` (mobile) | `sqflite` (in-app) |
| `flutter` | `supabase` | `supabase` |
| `rust` | `postgres`/`mysql`/`sqlite` | `sqlx-cli` |
| `go` | `postgres`/`mysql`/`sqlite` | `golang-migrate` |
| sonst | sonst | `skeleton` |

Für **Multi-Lang-Profile** (`profile.lang: [java, ts]`, PR-K): Default-Mapping greift auf die **erste** gelistete Sprache + den `db_dialect` — der User kann via AskUserQuestion bestätigen/ändern (z.B. wenn das Java-Sub-Modul Flyway nutzt, aber das TS-Sub-Modul Prisma — Tool-Mix ist Anti-Pattern, siehe Spec §13).

**c) User-Bestätigung — Pflicht, auch bei `high`-Confidence** (AskUserQuestion, single-select):
```
Detected db_migration_tool: flyway@10 (confidence: high, evidence: api/pom.xml:42 [org.flywaydb:flyway-core:10.0.0])
Confirm? [Y/n/skeleton/flyway@9/flyway@10/liquibase@4/prisma/alembic/knex/typeorm/sequelize/django-migrations/supabase/golang-migrate/sqlx-cli/refinery/sqflite]
```

**d) Evidence sammeln.** Pfad + Zeilennummer (oder Datei-Pfad) merken — wird in `profile.md` als Kommentar mitgegeben.

**e) In `.claude/profile.md` schreiben:**
```yaml
db_migration_tool: <wert>   # auto-detected from <evidence>, confirmed <YYYY-MM-DD>
```

**f) Konfliktpunkt mit `db_scripts/`-Skeleton** (Spec §8):
- **Wenn `db_migration_tool == skeleton`** (Default oder explizit): `db_scripts/`-Skeleton wird angelegt (siehe Schritt 2a-e — heutiges Verhalten).
- **Wenn `db_migration_tool != skeleton`**: `db_scripts/`-Skeleton wird **NICHT** angelegt (das Tool bringt seine eigene Konvention mit, z.B. Flyway nutzt `src/main/resources/db/migration/`). Stattdessen Backlog-Item „Tool-spezifische Konvention prüfen — siehe `knowledge/migration/<tool>.md`".

**g) Pack-Vorhandensein-Check + Backlog-Items** (Standard-Priorität Important):
- **Migration-Pack fehlt:** wenn `db_migration_tool != skeleton` UND `${CLAUDE_PLUGIN_ROOT}/knowledge/migration/<tool>[-<major>].md` nicht existiert: Backlog-Item „Pack `migration/<tool>` anlegen (via `/train migration/<tool>` oder manuelle Spec)".
- **Tool-Mix erkannt:** wenn die Detection-Heuristik 2+ Tools mit `high`-Confidence findet (z.B. flyway-Dep UND prisma-Dep im selben Repo), Backlog-Item „Tool-Mix erkannt: <X>+<Y> — Anti-Pattern (Spec §13), Architektur-Entscheidung dokumentieren". Im Profil das Tool des dominanten Sub-Moduls eintragen (per AskUserQuestion).
- **Kein Auto-Fix.** Wie der ganze `/adopt`-Pfad: 2f schreibt nur `profile.db_migration_tool`, erzeugt Backlog-Items, fasst Tool-spezifische Verzeichnisse (Flyway-Migrations, Prisma-Schema, etc.) **niemals** an.

## 3. Auditieren (gegen den Fabrik-Standard)
- **Automatik zuerst (objektiv, billig):** `gitleaks detect --source=. --no-git` (Secrets) + Dependency-Audit gemäß Sprache (`npm audit --omit=dev` / `pip-audit` / …) → Funde notieren.
- **`reviewer` im Audit-Modus** (Task — s. `reviewer.md` „Audit-Modus"): prüft den **Bestand** (kein Diff) gegen **Security-Floor** (immer), die Sprach-/Domänen-**Pack-Checklists**, Projekt-Konventionen und die **abgeleitete Spec** → priorisierte Funde (Critical/Important/Suggestions). Bei großen Repos **priorisiert** (Security-Floor überall; Pack-Checks auf repräsentative/heikle Dateien — Auth, Daten-/Netz-Zugriff, Eingänge; Architektur-Auffälligkeiten), NICHT zeilenweise.

## 4. Backlog anlegen
Aus den Funden **Board-Items** (Status To Do), **Critical zuerst**: pro Item ein GitHub-Issue mit **Acceptance** („<Fund> auf Standard `<Regel-ID>`/Prinzip beheben") + Priority; verwandte Funde **clustern** (kein 1-Item-pro-Zeile-Dump). Security-Floor-Verstöße → höchste Priority. Wo sinnvoll auf die abgeleitete Spec/AC verweisen.

## 5. Übergabe (KEIN Auto-Fix)
Report an den User: Repo-/Fork-URL · Board-URL · Funde nach Schwere (#Critical / #Important / #Suggestions) · die abgeleiteten Specs. → „Wähle die Items, die behoben werden sollen, und starte `/agent-flow:flow`." **Stop.**

## 6. Validate — End-to-End-Smoke via `tester`-Agent (Spec §18)
**Letzter Schritt nach Übergabe.** Verifiziert, dass das gerade angelegte Skeleton (Compose-Fragment + `db_scripts/`-Marker + Companion-Fragmente) **mechanisch** funktioniert — DB startet, Marker-Migration appliziert, App-Container erreichbar. Schreibt das Cache-Flag `profile.adoption_validated_at`, das `/preview` (Cache-Hit) und `/flow` (Invalidierung) auswerten.

**Trigger.** Läuft **wenn** `profile.db_dialect != none` ODER `profile.companions[]` nicht leer ist. Sonst (statische App ohne DB/Companion): Validate skip + klar-Output „nichts zu validieren — kein DB-/Companion-Skeleton angelegt".

**Konstante.** `MAX_VALIDATE_RETRIES = 3` (interner Fix-Loop-Cap; Spec §18).

### 6.a `tester`-Dispatch — E2E-Smoke-Auftrag
Orchestrator dispatcht `tester`-Agent (Task) mit dem folgenden Auftrag (cwd = adoptiertes Repo, **nicht** das agent-flow-Repo — der `tester` läuft hier im **Adoption-Validate-Modus**, nicht im DB-Subsystem-Smoke-Modus aus `agents/tester.md`):

```
ADOPTION-VALIDATE für <repo>
profile.db_dialect: <wert>
profile.companions:  <liste>

Schritte:
  1. /preview up   (für das adoptierte Repo, im cwd; nutzt die preview-up-Logik aus skills/preview/SKILL.md)
  2. Verifiziere:  DB-Service (sofern db_dialect ∈ {postgres,mysql,mongodb}) ist healthy
                   (docker inspect Health.Status = healthy)
                   bei sqlite: migrations-Service exit 0
                   Companion-Services (sofern profile.companions nicht leer) sind healthy
  2.5. **Migration-Apply** — gemäß `profile.db_migration_tool` aus der kanonischen Tabelle in `agents/tester.md` Migration-Apply-Dispatch (PR-Q3):
       - skeleton: `bash db_scripts/run-migrations.sh`
       - flyway@9/@10: `mvn -B -ntp flyway:migrate` (im app-Container)
       - liquibase@4: `mvn -B -ntp liquibase:update`
       - prisma: `npx prisma migrate deploy`
       - alembic: `alembic upgrade head`
       - knex: `npx knex migrate:latest`
       - typeorm: `npx typeorm migration:run -d <dataSourcePath>`
       - sequelize: `npx sequelize-cli db:migrate`
       - django-migrations: `python manage.py migrate`
       - supabase: `supabase db push`
       - golang-migrate: `migrate -path migrations -database "$DB_URL" up`
       - sqlx-cli: `sqlx migrate run`
       - sqflite / refinery: (in-app, kein externer Apply — Smoke = App-Boot ohne Migration-Fehler)
       - Fehlend / unbekannt: Fallback auf skeleton-Pfad.
  3. Verifiziere:  Marker-Migration appliziert. **Marker-Tabelle/Collection ist tool-spezifisch:**
                   - **skeleton (Default):** `_schema_migrations` (Tabelle/Collection — Spec `db-subsystem.md` §4)
                   - **flyway@<n>:** `flyway_schema_history` (Tabelle)
                   - **liquibase@<n>:** `databasechangelog` (Tabelle)
                   - **prisma:** `_prisma_migrations` (Tabelle)
                   - **alembic:** `alembic_version` (Tabelle, 1 Zeile mit aktuellem revision)
                   - **knex:** `knex_migrations` + `knex_migrations_lock` (2 Tabellen)
                   - **typeorm:** `typeorm_metadata` (Tabelle) oder das in der DataSource-Config definierte
                   - **sequelize:** `SequelizeMeta` (Tabelle)
                   - **django-migrations:** `django_migrations` (Tabelle)
                   - **supabase:** `supabase_migrations.schema_migrations` (Schema + Tabelle)
                   - **golang-migrate:** `schema_migrations` (Tabelle, mit `version` + `dirty`-Spalten)
                   - **sqlx-cli:** `_sqlx_migrations` (Tabelle)
                   - **sqflite / refinery:** in-app Marker (sqflite: `version` aus Database-Header; refinery: `refinery_schema_history`), getestet via App-Boot statt SQL-Query
                   - Query-Form analog skeleton-Pfad: `SELECT count(*) FROM <marker> → >= 1` bzw. für mongodb `db.<marker>.countDocuments() >= 1`.
  4. Trivial-Query auf marker (Marker-Tabelle aus Schritt 3 wählen — **tool-spezifisch**):

                   **Allgemeines Schema:** `<dialekt-client> -c "SELECT * FROM <marker-tabelle> LIMIT 1"`. Marker-Tabelle pro `profile.db_migration_tool` aus Schritt 3 nehmen.

                   **skeleton (Default — Marker `_schema_migrations`):**
                   - postgres:  psql -c "SELECT version FROM _schema_migrations ORDER BY version LIMIT 1"
                   - mysql:     mariadb -e "SELECT version FROM _schema_migrations ORDER BY version LIMIT 1"
                   - sqlite:    sqlite3 /data/app.sqlite "SELECT version FROM _schema_migrations LIMIT 1"
                   - mongodb:   mongosh --eval 'db._schema_migrations.findOne()'

                   **flyway@<n> (Marker `flyway_schema_history`):** `psql -c "SELECT version FROM flyway_schema_history ORDER BY installed_rank LIMIT 1"` (analog für mysql/mariadb).
                   **liquibase@<n> (Marker `databasechangelog`):** `psql -c "SELECT id FROM databasechangelog LIMIT 1"`.
                   **prisma (Marker `_prisma_migrations`):** `psql -c "SELECT migration_name FROM _prisma_migrations LIMIT 1"`.
                   **alembic (Marker `alembic_version`):** `psql -c "SELECT version_num FROM alembic_version LIMIT 1"`.
                   **knex (Marker `knex_migrations`):** `psql -c "SELECT name FROM knex_migrations LIMIT 1"`.
                   **typeorm (Marker `typeorm_metadata` oder DataSource-config):** `psql -c "SELECT name FROM typeorm_metadata LIMIT 1"` (oder gemäß DataSource).
                   **sequelize (Marker `SequelizeMeta`):** `psql -c 'SELECT name FROM "SequelizeMeta" LIMIT 1'` (case-sensitive, deshalb gequotet).
                   **django-migrations (Marker `django_migrations`):** `psql -c "SELECT app, name FROM django_migrations LIMIT 1"`.
                   **supabase (Marker `supabase_migrations.schema_migrations`):** `psql -c "SELECT version FROM supabase_migrations.schema_migrations LIMIT 1"`.
                   **golang-migrate (Marker `schema_migrations`):** `psql -c "SELECT version, dirty FROM schema_migrations LIMIT 1"`.
                   **sqlx-cli (Marker `_sqlx_migrations`):** `psql -c "SELECT version FROM _sqlx_migrations LIMIT 1"`.

                   **In-app Tools (sqflite / refinery):** Schritt 4 **SKIP** — Marker lebt in-app, kein externer SQL-Query möglich. Smoke = App-Boot ohne Migrations-Fehler (Schritt 2.5 in-app-Variante).
  5. /preview down --keep-data=false   (cleanup, Volume weg)

Output (alle 4 Stufen grün → PASS; sonst FAIL mit Stufe + stdout/stderr):
  Validate-Gate: PASS | FAIL
  Failed-Stage:  <up|health|migration|query|down> | none
  Stderr:        <tail -n 50 der relevanten Logs>
```

### 6.b PASS-Pfad — Cache-Flag schreiben
Bei `Validate-Gate: PASS` schreibt der Orchestrator in `.claude/profile.md` (additiv, bestehende Keys nicht überschreiben):

```yaml
adoption_validated_at: <ISO-Datum, z.B. 2026-05-31T11:42:00Z>
adoption_validated_dialect: <postgres|mysql|sqlite|mongodb>
adoption_validated_companions: [<liste, z.B. redis>]
adoption_validated_migration_tool: <skeleton|flyway@<n>|liquibase@<n>|prisma|alembic|...>   # NEU (PR-Q6)
```

Klar-Output:
```
✓ Adoption validated end-to-end. profile.adoption_validated_at: <date>
  Dialect:         <dialect>
  Companions:      [<liste>]
  Migration-Tool:  <tool>                                          # NEU
  Cache:           /preview up wird E2E-Smoke künftig skippen (cache-hit), solange Dialect+Companions+Migration-Tool unverändert.
```

### 6.c FAIL-Pfad — Coder-Fix-Loop (max. `MAX_VALIDATE_RETRIES = 3`)
Bei `Validate-Gate: FAIL`:

1. **Diagnose-Output zeigen** (an User): `Failed-Stage`, `tester`-Stdout/Stderr (letzte 50 Zeilen). Typische Ursachen:
   - **up-Fehler:** Compose-Syntax kaputt (Fragment-Append-Konflikt) → `docker compose config` zeigen.
   - **health-Fehler:** DB-Image bootet nicht (env fehlt, Permission, Port-Konflikt) → `docker logs <db-container>`.
   - **migration-Fehler:** Skeleton-Migration `000_init_meta.{sql|js}` syntaktisch kaputt für den Dialekt, oder `run-migrations.sh` non-executable → Permission/Pfad prüfen.
   - **query-Fehler:** Marker-Tabelle/Collection nicht angelegt (Migration silent-failed).
2. **Coder dispatchen** (Task) mit den Findings als `FINDINGS: <…>` + `ITERATION: <N>` (1..3). Coder fixt **nur** das Skeleton/Compose/Migrations-Skript, **nicht** Business-Code. **§5-Grenze ("kein Auto-Fix für Bestand") bleibt:** der Coder darf das gerade angelegte Skeleton anpassen, nicht jedoch bestehende `db_scripts/`-Dateien/Compose-Services.
   **Tool-Beschränkung (PR-Q6):** Der Coder darf das gerade angelegte Skeleton (`db_scripts/` bei `skeleton`) UND tool-spezifische Initial-Files (z.B. `application.properties` `spring.flyway.enabled=true` bei flyway@<n>, `prisma/schema.prisma` bei prisma) anpassen — niemals jedoch bestehende, vor-`/adopt` existierende Migrations-Files (Forward-only-Disziplin bleibt). Bei nicht-skeleton-Tools, die keinen Auto-Scaffold-Skeleton erhalten haben (Spec §8): der Coder fragt explizit nach manueller Setup-Anweisung (Backlog-Item statt Auto-Fix).
3. **Re-Validate:** Schritt 6.a erneut.
4. Bleibt es nach `MAX_VALIDATE_RETRIES = 3` rot → **human-handoff:**
   - Klare Fehler-Spec ausgeben (Failed-Stage + alle 3 Iterations-Logs).
   - **Backlog-Issue anlegen:** `gh issue create --title "ADOPT-VALIDATE-FAIL: <Failed-Stage>" --body "<tester-Output + Iterations-Diff>" --label adopt-validate-fail,important`. Bei fehlendem Label-Setup: ohne Labels (vgl. Polyglott-Eskalation §2a, a.1).
   - **`adoption_validated_at` wird NICHT gesetzt** — `/preview up` und `/adopt re-validate` werden den Validate-Schritt beim nächsten Aufruf erneut versuchen (kein silent skip).
5. **Schleifenschutz-Klarstellung:** Die 3 Iterationen sind **Validate-intern**, NICHT identisch mit dem `/flow`-Build-Loop (§3) — Validate ist ein separater Mechanismus, der vor dem ersten `/flow`-Run sicherstellt, dass das Skeleton mechanisch trägt.

### 6.d Re-Validate-Mode (`/adopt re-validate`)
Expliziter Befehl ohne `<owner/repo>`-Argument. cwd = bereits adoptiertes Repo (muss `.claude/profile.md` haben).

- **Auth** wie §0.
- **Sprung direkt zu §6** — keine Detection, kein Scaffold, kein Audit, keine Übergabe-Schritte.
- **Vorbedingung:** `profile.db_dialect != none` ODER `profile.companions[]` nicht leer. ZUSÄTZLICH (PR-Q6): bei `db_migration_tool != skeleton` muss das Tool-spezifische Migrations-Setup existieren (z.B. `src/main/resources/db/migration/V1__init.sql` bei flyway; `prisma/schema.prisma` bei prisma) — sonst klar-Output „kein Migrations-Setup vorhanden, re-validate nicht sinnvoll" + Exit 0. Sonst: klar-Output „nichts zu re-validieren" + Exit 0.
- **Verhalten identisch zu §6.a–c** — bei PASS wird `adoption_validated_at` neu gesetzt (überschreibt alten Wert); bei FAIL läuft der gleiche Coder-Fix-Loop (max 3) + Issue-Erstellung.
- **Use-Cases:**
  - Spec/Template wurde manuell editiert (z.B. Compose-Fragment angepasst).
  - `/flow` hat das Flag invalidiert (Spec §18, `skills/flow/SKILL.md` §5a) und der User will explizit re-validieren statt auf den nächsten `/preview up` zu warten.
  - Nach Plugin-Update (`templates/_shared/db-<dialect>/` neu gepullt).

## Grenzen
- **Behebt nichts automatisch** — erzeugt nur das Backlog; Fix = `/flow` (PR-gated).
- Pusht NUR auf das Org-Repo bzw. den Org-Fork — **nie** ungefragt auf ein fremdes Upstream (Upstream-PR nur auf deinen Wunsch + Approve).
- Idempotent: bestehende `.claude/`-/`docs/`-Dateien nicht überschreiben (mergen/fragen).
- Die **abgeleitete Spec ist Entwurf**, bis du sie bestätigst (sie ist danach die Drift-Gate-Referenz für `/flow`).
- **DB-Detection (Schritt 2a) ist nicht-destruktiv:** schreibt `db_dialect`, hängt Compose-Fragment **nur** an, wenn noch kein db-Service existiert; bestehende `db_scripts/`-Dateien werden **nie** überschrieben — Konflikte landen als Backlog-Item, nicht als Auto-Patch.
- **Companion-Detection (Schritt 2b) ist nicht-destruktiv** und beeinflusst `db_dialect` NICHT: Companions leben in `profile.companions[]` (additive Liste, Scope-Lock §17). Heute verfügbar: `redis`. Kein `db_scripts/`-Skeleton, kein Migrations-Runner, kein Backup-Auto-Scaffold — wer das braucht, gehört ins DB-Subsystem.
- **Validate (Schritt 6) ist kein Auto-Fix für Bestand:** der Coder-Fix-Loop darf nur das gerade angelegte **Skeleton** (000_init_meta, run-migrations.sh, Compose-Fragment-Append, .env.db.example) anpassen — nie bestehende `db_scripts/`-Migrations oder bestehende db-Services im Compose. Loop-Cap fix `MAX_VALIDATE_RETRIES = 3`; danach human-handoff + Backlog-Issue, kein Endlos-Loop. `adoption_validated_at` wird NUR bei PASS gesetzt — ohne Validate-PASS gibt es keinen Cache-Hit in `/preview` (Spec §18).
