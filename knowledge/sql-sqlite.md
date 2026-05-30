# Knowledge Pack: sql-sqlite  (Dialekt — SQLite 3, File-DB)

Implementierungs-Expertise für SQLite-Migrationen und -Zugriff. Dialekt (`profile.db_dialect: sqlite`); vom `coder` geladen, vom `dba` fürs Modell-Design. Regel-IDs: `sqlite/R<NN>`. (Modell-DESIGN macht `dba`, Migrationen schreibt `coder`.)

---

## WARNUNG: SQLite skaliert NICHT horizontal

> **SQLite skaliert NICHT horizontal: das gesamte File ist Single-Writer (Whole-Database-Lock). Zur Laufzeit kann immer nur ein Prozess schreiben — die Engine erzwingt einen exklusiven Lock auf Datei-Ebene. Multi-Replica-Deployments (z.B. 2+ App-Container, Kubernetes-Pod-Replicas, Load-Balancer mit mehreren Backends, docker-compose `scale: N`) verursachen stillen Datenverlust oder Korruption, weil mehrere Instanzen das gleiche Volume-File gleichzeitig beschreiben.** Wenn das Projekt Multi-Replica braucht → **Postgres oder MySQL** stattdessen wählen.

Quelle: [sqlite.org/whentouse.html — „Many concurrent writers"](https://www.sqlite.org/whentouse.html) · [sqlite.org/lockingv3.html — Exclusive Lock](https://www.sqlite.org/lockingv3.html)

### Harte DBA-Regel `sqlite/R01`

Items mit Deployment-Pattern Multi-Replica (Compose `scale:`, Kubernetes `replicas:`, Load-Balancer mit mehreren Backends) und `profile.db_dialect: sqlite` **MÜSSEN** als **Critical** geflaggt werden. Keine Ausnahme.

---

## Coder-Guidance

- `sqlite/R02` — **`PRAGMA foreign_keys = ON;`** am Verbindungsaufbau explizit setzen. Foreign-Key-Constraints sind in SQLite **historisch OFF by default** und müssen pro Datenbankverbindung aktiviert werden — dies überrascht Entwickler, die von Postgres/MySQL kommen. Ohne dieses PRAGMA werden FK-Verletzungen stillschweigend ignoriert. Quelle: [sqlite.org/foreignkeys.html#fk_enable](https://www.sqlite.org/foreignkeys.html#fk_enable)

- `sqlite/R03` — **`PRAGMA journal_mode = WAL;`** für gleichzeitige Reads. Der Default-Modus (`DELETE`) lässt Reads und Writes nicht gleichzeitig laufen. WAL (Write-Ahead Logging, stabil seit SQLite 3.7.0, Juli 2010) erlaubt beliebig viele gleichzeitige Reader neben einem Writer: „Reading and writing can proceed concurrently." WAL-Modus ist **persistent** — einmal gesetzt bleibt er über Verbindungsneustarts erhalten. Quelle: [sqlite.org/wal.html](https://www.sqlite.org/wal.html)

- `sqlite/R04` — **Type Affinity vs. STRICT Tables.** SQLite hat dynamische Typen (Type Affinity): `INTEGER`-Spalten speichern auch Texte ohne Fehler. Strikte Typprüfung erfordert das **`STRICT`-Keyword** am Ende der `CREATE TABLE`-Anweisung (stabil seit SQLite 3.37.0, November 2021). Erlaubte Datentypen in STRICT-Tables: `INT`, `INTEGER`, `REAL`, `TEXT`, `BLOB`, `ANY`. Ohne `STRICT` können Typ-Fehler zur Laufzeit unbemerkt bleiben. Quelle: [sqlite.org/stricttables.html](https://www.sqlite.org/stricttables.html)

- `sqlite/R05` — **ALTER TABLE ist stark eingeschränkt — Schema-Änderungen oft via Table-Rebuild.** SQLite unterstützt nur: `RENAME TABLE`, `RENAME COLUMN`, `ADD COLUMN`, `DROP COLUMN`. Es gibt kein `ALTER COLUMN` (Typ ändern, NOT NULL hinzufügen, Default ändern), kein `ADD CONSTRAINT`, kein `DROP CONSTRAINT`. Schema-Änderungen, die über diese Operationen hinausgehen, erfordern den klassischen **Table-Rebuild**:
  1. Neue Tabelle mit gewünschtem Schema anlegen (`CREATE TABLE new_t ...`).
  2. Daten kopieren (`INSERT INTO new_t SELECT ... FROM old_t`).
  3. Alte Tabelle löschen (`DROP TABLE old_t`).
  4. Neue Tabelle umbenennen (`ALTER TABLE new_t RENAME TO old_t`).
  Dieser Rebuild muss in einer Transaktion erfolgen. Quelle: [sqlite.org/lang_altertable.html](https://www.sqlite.org/lang_altertable.html)

- `sqlite/R06` — **Migrations-Konvention (Spec §4).**
  - Verzeichnis: `db_scripts/<NNN>_name.sql` (3-stellig, nullgepaddet, lückenlos, forward-only).
  - Marker-Tabelle: `_schema_migrations(version TEXT PRIMARY KEY, applied_at TEXT NOT NULL DEFAULT (datetime('now')), checksum TEXT)` — funktioniert nativ in SQLite.
  - Idempotenz: `CREATE TABLE IF NOT EXISTS`, `CREATE INDEX IF NOT EXISTS`.
  - **Kein Compose-DB-Service** (Spec §5): DB-File liegt in Container-Volume (`/data/app.sqlite`), Migrations werden via separatem schlanken `sqlite3`-Image als one-shot-Container appliziert (Spec §16-R4), der das Volume teilt.
  - `PRAGMA foreign_keys = ON;` und `PRAGMA journal_mode = WAL;` gehören in `001_init.sql` (erste Migration) — werden einmalig gesetzt und sind dann persistent.

---

## Beispiel-Migration (`db_scripts/001_init.sql`)

```sql
-- WAL-Modus aktivieren (persistent nach erstem Setzen)
PRAGMA journal_mode = WAL;

-- FK-Enforcement für diese Verbindung aktivieren
PRAGMA foreign_keys = ON;

-- Migrations-Marker-Tabelle
CREATE TABLE IF NOT EXISTS _schema_migrations (
  version     TEXT    NOT NULL PRIMARY KEY,
  applied_at  TEXT    NOT NULL DEFAULT (datetime('now')),
  checksum    TEXT
);

-- Anwendungs-Tabellen (STRICT erzwingt Typ-Korrektheit)
CREATE TABLE IF NOT EXISTS users (
  id         INTEGER NOT NULL PRIMARY KEY,
  email      TEXT    NOT NULL UNIQUE,
  created_at TEXT    NOT NULL DEFAULT (datetime('now'))
) STRICT;

CREATE TABLE IF NOT EXISTS posts (
  id         INTEGER NOT NULL PRIMARY KEY,
  user_id    INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  title      TEXT    NOT NULL,
  body       TEXT,
  created_at TEXT    NOT NULL DEFAULT (datetime('now'))
) STRICT;

CREATE INDEX IF NOT EXISTS idx_posts_user_id ON posts(user_id);
```

---

## Reviewer-Checklist

- `profile.db_dialect: sqlite` + Deployment-Pattern mit `scale:`, `replicas:` oder mehreren App-Backends → **Critical** (`sqlite/R01` — Multi-Replica-Hard-Stop).
- Verbindungsaufbau ohne `PRAGMA foreign_keys = ON;` → **Critical** (FK-Constraints werden ignoriert, `sqlite/R02`).
- Neue Tabellen ohne `STRICT` in neuem Code (SQLite ≥ 3.37.0) → **Important** (unerwartete Typ-Koersion, `sqlite/R04`).
- Schema-Änderung via nicht-unterstütztem ALTER (z.B. `ALTER COLUMN`) → **Critical** (wird ohne Fehlermeldung ignoriert oder bricht ab, `sqlite/R05`).
- Bereits angewandte Migration editiert / umnummeriert → **Critical** (Spec §4, `sqlite/R06`).
- `PRAGMA journal_mode = WAL;` fehlt und die App hat mehr als einen gleichzeitigen Reader → **Important** (`sqlite/R03`).
- Index auf FK-Spalte fehlt → **Important** (kein Auto-Index auf FKs in SQLite).
- Backup via `cp` auf laufende DB (statt `sqlite3 .backup` oder WAL-Checkpoint) → **Important** (Datenverlust bei gleichzeitigem Write möglich).

---

## Test-Approach

- Migration läuft sauber **und** idempotent (zweimal anwenden, Marker filtert Doppel-Apply).
- Smoke-Query (`SELECT 1 FROM users LIMIT 1`) gegen appliziertes Schema.
- `PRAGMA foreign_keys;` → muss `1` zurückgeben (Verbindungssetup prüfen).
- `PRAGMA journal_mode;` → muss `wal` zurückgeben.
- Table-Rebuild-Migrationen: Zeilencount vor und nach dem Rebuild vergleichen (kein Datenverlust).
