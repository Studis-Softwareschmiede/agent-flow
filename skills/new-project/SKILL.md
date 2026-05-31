---
name: new-project
description: Bootstrappt ein Projekt der Softwareschmiede — legt Repo + GitHub-Board an, erkennt/erfragt den Stack + DB-Dialekt + optionale Companions (Cache/Queue/Sessions), scaffoldet .claude/ (profile, CLAUDE.md, lessons) + Dockerfile + CI + optionales DB-Compose-Fragment + optionale Companion-Fragmente aus ${CLAUDE_PLUGIN_ROOT}/templates/. /init adoptiert ein bestehendes Repo. Schreibt KEINEN App-Code.
---

# /new-project <name> [--lang <x>] [--db <dialect>] [--companions <list>]   ·   /init

Bootstrap, damit die Fabrik an einem Projekt arbeiten kann. cwd = Workspace (`new-project`) bzw. das bestehende Repo (`init`).

**Auth ZUERST (sonst scheitert jeder gh-Schritt):** `bash "$CLAUDE_PLUGIN_ROOT/scripts/ensure-gh-auth.sh"` — das mintet den GitHub-App-Token aus `.env.gpg` und loggt `gh` damit ein. **NICHT `gh auth login --web`** (wir nutzen die App, nicht einen interaktiven Login).

## Ablauf
1. **Repo**
   - `new-project`: `gh repo create studis-softwareschmiede/<name> --public` + clone. (Public: Branch-Protection/PR+Gate im Free-Plan möglich; ghcr-Image ohne Pull-Login.)
   - `init`: bestehendes Repo (cwd) nutzen; Remote prüfen.
2. **Stack**
   - `new-project`: aus `--lang` oder genau **1 Frage**.
   - `init`: erkennen — `pubspec.yaml`→flutter · `pom.xml`/`build.gradle`→java · `package.json`→js/angular · `*.html`→html · `*.sql`/`migrations/`→Domäne `sql` — und bestätigen lassen.
2a. **DB-Auswahl** (Spec [`docs/architecture/db-subsystem.md`](../../docs/architecture/db-subsystem.md) §2 + §10) — `profile.db_dialect` festlegen:
   - `new-project` mit `--db <dialect>`: Wert direkt übernehmen.
   - `new-project` ohne `--db`: genau **1 zusätzliche Frage** (AskUserQuestion, 5 Enum-Werte):
     > „DB-System? [postgres|mysql|sqlite|mongodb|none] (none = keine DB)"
   - `init`: Detection wie in `/adopt` Schritt 2a (Heuristik aus Spec §9) — dort dokumentiert; hier nur Verweis, doppelt-pflegen vermeiden.
   - **Erlaubte Werte (Spec §2 Enum):** `postgres | mysql | sqlite | mongodb | none`. **Default** ohne `--db`-Flag und ohne explizite Antwort: `none` (safe minimal state — bewusste Entscheidung später ist besser als Default mit falscher DB).
   - Bei ungültigem Wert: Frage wiederholen (kein Fallback auf `none` „im Stillen").
2b. **Companion-Auswahl** (Spec [`docs/architecture/db-subsystem.md`](../../docs/architecture/db-subsystem.md) §17) — `profile.companions[]` festlegen. Companions = stateful Sidecars **OHNE** Schema-Evolution (Cache/Queue/Sessions/Pub-Sub). Heute verfügbar: `redis`.
   - `new-project` mit `--companions <list>`: kommagetrennte Liste übernehmen (z.B. `--companions redis`; in P1 nur `redis` gültig — unbekannte Namen → Fehler).
   - `new-project` ohne `--companions` + interaktiv: **1 optionale Frage** (AskUserQuestion):
     > „Companions? [<keine>|redis] (Cache/Queue/Sessions; mehrere kommagetrennt)"
     **Default ohne Antwort: keine** (Companions sind opt-in; weniger Moving-Parts beim Bootstrap).
   - `init`: Detection wie in `/adopt` Schritt 2b — dort dokumentiert; hier nur Verweis.
   - **Erlaubte Werte (P1):** `redis` (additive Liste). **Scope-Lock:** Companions belegen **NICHT** den `db_dialect`-Slot — `companions: [redis]` mit `db_dialect: postgres` ist eine valide Kombination.
3. **Board**: `gh project create` (Org-Ebene), Status-Werte `To Do / In Progress / Blocked / In Review / Done` → Nummer notieren.
4. **`.claude/` scaffolden** (aus `${CLAUDE_PLUGIN_ROOT}/templates/<lang>/`):
   - `profile.md`: `language`, `domains`, `db_dialect: <wert aus Schritt 2a>` (Pflicht, Enum `postgres|mysql|sqlite|mongodb|none`; Spec §2), `companions: [<liste aus Schritt 2b>]` (Liste, default `[]`; Spec §17 — heute nur `redis` gültig), `build`/`test`/`lint`/`smoke`, `merge_policy: pr`, `board: <nr>`, `deploy: docker`, `image: ghcr.io/studis-softwareschmiede/<name-lowercase>` (Docker/ghcr-Repo-Namen sind IMMER kleingeschrieben — Repo `Foo-Bar` → Image `foo-bar`), `registry: ghcr`, `container_port: <EXPOSE aus dem Template-Dockerfile, z.B. 80|8080>` (für `/preview`; `preview_port` wird erst beim ersten `/preview up` vergeben).
   - `CLAUDE.md`: minimaler Kontext (Template + 1–2 Fragen).
   - `lessons/{coder,reviewer,tester}.md`: leer.
4b. **`docs/` scaffolden** (Spec-getriebene Doku, CONCEPT §4d — aus `${CLAUDE_PLUGIN_ROOT}/templates/_docs/`, sprach-neutral):
   - **Immer:** `docs/concept.md`, `docs/architecture.md`, `docs/glossary.md`, `docs/specs/_template.md` (Vorlage — bleibt liegen, `requirement` kopiert sie je Feature).
   - **Bedingt:** `docs/data-model.md` nur wenn `profile.db_dialect != none` (Spec §10; ersetzt die alte `domains: [sql]`-Bedingung — `domains` bleibt als reine Knowledge-Pack-Liste, der DB-Layer wird über `db_dialect` gesteuert); `docs/design.md` nur bei UI (`language` ∈ flutter|angular|html oder Domäne `ui`/`accessibility`).
   - `<App>`-Platzhalter durch den Projektnamen ersetzen; sonst leer lassen (füllen `architekt`/`dba`/`designer`/`requirement`). Diese Docs sind die **durable Source of Truth** (`.claude/` hält nur Prozess-State: profile, lessons).
   - **Nur `/init` — „Spec aus Code ableiten" (einmalig, mensch-validiert):** bestehenden Code lesen und `docs/concept.md` + `docs/architecture.md` + je Capability `docs/specs/<feature>.md` als **Entwurf** (`status: draft`) füllen (bei Bedarf `architekt`/`requirement` via Task dispatchen). Die abgeleiteten Docs dem User zur Durchsicht/Korrektur **vorlegen, bevor sie verbindlich werden** — erst nach OK gelten sie als Source of Truth (dann ist die App portierbar + unter Drift-Gate).
4c. **DB-Subsystem scaffolden** (Spec §10) — nur wenn `profile.db_dialect != none`:
   - **Compose-Fragment anhängen:** `cat ${CLAUDE_PLUGIN_ROOT}/templates/_shared/db-<dialect>/compose.fragment.yml >> docker-compose.yml` (Trennzeile davor: `# --- db-<dialect> (source: templates/_shared/db-<dialect>/compose.fragment.yml) ---`). Bei `db_dialect: sqlite` enthält das Fragment **keinen** db-Service, sondern nur den one-shot `migrations`-Service + `db_data`-Volume (Spec §5 SQLite-Sonderfall, §16-R4).
   - **`db_scripts/`-Skeleton kopieren:**
     - `db_scripts/000_init_meta.sql` (postgres/mysql/sqlite) bzw. `000_init_meta.js` (mongodb) — legt die Marker-Tabelle/Collection `_schema_migrations` an (Spec §4).
     - `db_scripts/run-migrations.sh` aus `templates/_shared/db-<dialect>/db_scripts/run-migrations.sh` (executable, Spec §6).
   - **`.env.db.example`** aus `templates/_shared/db-<dialect>/.env.db.example` ans Repo-Root (Vorlage für `DB_HOST`/`DB_NAME`/`DB_USER`/`DB_PASSWORD` bzw. dialekt-äquivalente; **keine** echten Werte committen).
   - **Backup/Restore-Vorlagen NICHT auto-kopieren** (Spec §7 — projekt-spezifisch). Hinweis im README-DB-Abschnitt: „Vorlagen in `templates/_shared/db-<dialect>/scripts/` — bei Bedarf ins Projekt kopieren."
   - **`README.md` um DB-Abschnitt erweitern** (am Ende anhängen): Verweis auf passendes Pack (§3: `postgres`→`knowledge/sql.md`, `mysql`→`sql-mysql.md`, `sqlite`→`sql-sqlite.md`, `mongodb`→`knowledge/mongodb.md`), Migrations-Workflow (`docker compose up -d db && docker compose up migrations && docker compose up -d app` — bei sqlite ohne `db`-Service), Backup/Restore-Verweis. Bei sqlite zusätzlich die Skalierungs-Warnung (Single-Writer-Lock, kein Multi-Replica — Spec §16-R2, Pack-Regel `sqlite/R01`).
4d. **Companions scaffolden** (Spec §17) — pro Eintrag in `profile.companions`:
   - **Compose-Fragment anhängen:** `cat ${CLAUDE_PLUGIN_ROOT}/templates/_shared/companion-<name>/compose.fragment.yml >> docker-compose.yml` (Trennzeile davor: `# --- companion-<name> (source: templates/_shared/companion-<name>/compose.fragment.yml) ---`).
   - **`.env.<name>.example`** (z.B. `.env.redis.example`) ans Repo-Root kopieren (Vorlage für Connection-Variablen).
   - **KEIN `db_scripts/`, KEIN Migrations-Runner, KEIN Backup-Skript** — Scope-Lock §17 (Companions haben keine Schema-Evolution).
   - **`README.md` um Companion-Abschnitt erweitern** (kurz): Use-Case, Connect-Env (`<NAME>_HOST` / `<NAME>_PORT`), Verweis auf `templates/_shared/companion-<name>/README.md` für Details (Production-Password-Setup etc.).
5. **Deploy scaffolden** (aus `${CLAUDE_PLUGIN_ROOT}/templates/<lang>/`):
   - `Dockerfile`.
   - `.github/workflows/build.yml`: on push `main` → **Secret-Scan-Gate (gitleaks)** dann Image bauen + Push nach `ghcr.io/studis-softwareschmiede/<name>` via eingebautem `GITHUB_TOKEN` (`permissions: packages: write`).
   - **Security-Automatik** (Claude-frei, kontinuierlich aktuell): `.github/workflows/security.yml` (aus `templates/_shared/`, geplanter Secret-History-Scan + Issue bei Fund) und `.github/dependabot.yml` (aus `templates/_shared/`, Dependency-/Action-Vuln-Überwachung). Im `dependabot.yml` das **Sprach-Ökosystem** je `profile.language` aktivieren (npm→js/angular, pub→flutter, maven/gradle→java, keins→html). Dazu **GitHub Dependabot security updates aktivieren** (`gh api -X PUT repos/<org>/<name>/automated-security-fixes`).
6. **Branch-Protection** auf `main` (optional/best-effort): nur *„require a pull request before merging"* (blockiert Direkt-Push). **KEINE** Pflicht-Status-Checks (`reviewer` ist ein Agent, kein GitHub-Check → würde sonst jeden Merge blockieren) und **KEINE** Pflicht-Approvals (solo kann eigenen PR nicht approven). Lehnt die API ab (Plan/Permissions) → **überspringen, nicht abbrechen**. Das eigentliche Gate ist dein manueller Merge nach Review-PASS + Test-PASS.
7. **Initial commit + push.**

## Output
Repo-URL · Board-URL · Profil · Image-Ziel → „bereit für `/requirement`".

## Grenzen
- Kein App-Code.
- `init`: bestehende `.claude/`- **und `docs/`**-Dateien NICHT überschreiben (mergen/fragen) → idempotent.
- Minimal fragen — DB-Auswahl ist **genau eine** zusätzliche Frage (kein Multi-Step-Wizard; Spec §10).
- Genau **ein** Dialekt pro Projekt (`db_dialect` ist Single-Value-Enum, Spec §16-R1) — Polyglott (mehrere primäre DBs) ist P1 explizit out of scope.
- `db_dialect: none` → **kein** Compose-Fragment, **kein** `db_scripts/`-Skeleton, **kein** `docs/data-model.md` — der User entscheidet später bewusst per `/adopt`-Re-Run oder manuellem Profil-Edit.
- Companion-Auswahl ist **optional** (Default `companions: []`); P1 nur `redis` verfügbar. Kein Migrations-/Backup-/Pack-Scaffold für Companions (Scope-Lock Spec §17).
