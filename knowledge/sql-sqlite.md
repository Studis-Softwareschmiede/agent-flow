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

- `sqlite/R07` — **`RETURNING`-Klausel für INSERT/UPDATE/DELETE (stabil seit SQLite 3.35.0, März 2021).** Gibt die Werte geänderter Zeilen zurück, ohne einen separaten `SELECT` zu benötigen — besonders nützlich für auto-generierte `id`- oder `created_at`-Werte nach einem INSERT. Wichtige Einschränkungen: (1) nur auf Top-Level-Statements, **nicht** in Triggern; (2) die Reihenfolge der zurückgegebenen Zeilen ist nicht garantiert; (3) AFTER-Trigger-Änderungen sind im RETURNING-Output nicht sichtbar; (4) funktioniert nicht auf Virtual Tables (bei DELETE/UPDATE). Beispiel: `INSERT INTO posts(title) VALUES('Hi') RETURNING id, created_at;` Quelle: [sqlite.org/lang_returning.html](https://www.sqlite.org/lang_returning.html)

- `sqlite/R08` — **JSON-Operatoren `->` und `->>` (stabil seit SQLite 3.38.0, Februar 2022).** Kurzform für JSON-Extraktion, kompatibel mit MySQL/PostgreSQL. Unterschied: `->` liefert die **JSON-Darstellung** des Werts (z.B. `'"xyz"'` mit Anführungszeichen), `->>` liefert den **SQL-Wert** (z.B. `'xyz'` ohne Anführungszeichen, entspricht `json_extract()`). Rechts-Operand: JSON-Path-String (z.B. `'$.field'`), Objekt-Label (`'field'` → `'$.field'`), oder Array-Index (Integer, seit 3.47.0 auch negativ). Falle: `col -> '$.key'` gibt `NULL` zurück, wenn `col` NULL ist oder `key` nicht existiert — kein Fehler. Quelle: [sqlite.org/json1.html#jptr](https://www.sqlite.org/json1.html#jptr)

- `sqlite/R09` — **ALTER TABLE: NOT NULL-Constraint ohne Table-Rebuild seit SQLite 3.53.0 (April 2026) änderbar.** Neuer Syntax: `ALTER TABLE t ALTER col SET NOT NULL` / `ALTER TABLE t ALTER col DROP NOT NULL`. Ergänzt R05: der Table-Rebuild ist **nur noch nötig** für Typ-Änderungen, DEFAULT-Änderungen, CHECK-Constraints, Umbenennung von Constraints und alle anderen Schema-Änderungen. `SET NOT NULL` ist idempotent (no-op falls bereits gesetzt). Quelle: [sqlite.org/lang_altertable.html#alter_table_alter_column](https://www.sqlite.org/lang_altertable.html#alter_table_alter_column) · [sqlite.org/releaselog/3_53_0.html](https://www.sqlite.org/releaselog/3_53_0.html)

- `sqlite/R10` — **WAL-Reset-Data-Race-Bug (Korruptionsrisiko in ALLEN SQLite-Versionen 3.7.0–3.51.2, behoben in 3.51.3, März 2026) — schärft R03.** Ein am 2026-03-03 gefundener Data-Race im Checkpoint-Pfad kann bei **≥2 gleichzeitigen Verbindungen** (separate Threads/Prozesse) auf dieselbe Datei, die gleichzeitig schreiben/checkpointen, dazu führen, dass eine spätere Checkpoint-Runde Transaktionsinhalte überspringt → **Datenkorruption**. Betroffen: „likely present in all version of SQLite from 3.7.0 (2010-07-21) through 3.51.2 (2026-01-09)". Behoben in 3.51.3 (2026-03-13)+; Backports für 3.44.6 und 3.50.7 verfügbar. Da `sqlite/R03` WAL-Modus für gleichzeitige Reader empfiehlt: vor Produktiv-Einsatz mit **mehreren schreibenden Verbindungen** die tatsächlich gebundene SQLite-Library-Version des Sprach-Treibers verifizieren (z.B. Python `sqlite3.sqlite_version`, nicht die System-CLI) — muss ≥ 3.51.3 sein bzw. einen der genannten Backports nutzen. Quelle: [sqlite.org/wal.html#the_wal_reset_bug](https://www.sqlite.org/wal.html#the_wal_reset_bug) — „The bug is likely present in all version of SQLite from 3.7.0 (2010-07-21) through 3.51.2 (2026-01-09). It is fixed in version 3.51.3 (2026-03-13) and later."

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
- Schema-Änderung via nicht-unterstütztem ALTER (z.B. `ALTER COLUMN` für Typ-/DEFAULT-Änderung) → **Critical** (`sqlite/R05`). Ausnahme ab SQLite ≥ 3.53.0: `ALTER COLUMN SET/DROP NOT NULL` ist unterstützt (`sqlite/R09`).
- Bereits angewandte Migration editiert / umnummeriert → **Critical** (Spec §4, `sqlite/R06`).
- `PRAGMA journal_mode = WAL;` fehlt und die App hat mehr als einen gleichzeitigen Reader → **Important** (`sqlite/R03`).
- Index auf FK-Spalte fehlt → **Important** (kein Auto-Index auf FKs in SQLite).
- Backup via `cp` auf laufende DB (statt `sqlite3 .backup` oder WAL-Checkpoint) → **Important** (Datenverlust bei gleichzeitigem Write möglich).
- `->` / `->>` verwechselt: `->` liefert JSON-Darstellung (mit Anführungszeichen bei Strings), `->>` liefert SQL-Wert → **Important** (Typ-Fehler in Verarbeitung, `sqlite/R08`).
- `ALTER COLUMN SET NOT NULL` auf SQLite < 3.53.0 → `sqlite/R05` Table-Rebuild-Pattern verwenden; auf ≥ 3.53.0 neue Syntax nutzbar (`sqlite/R09`).
- WAL-Modus (`sqlite/R03`) + mehrere schreibende Verbindungen ohne verifizierte Treiber-SQLite-Version ≥ 3.51.3 (bzw. Backport 3.44.6/3.50.7) → **Important** (WAL-Reset-Korruptionsrisiko, `sqlite/R10`).

---

## Test-Approach

- Migration läuft sauber **und** idempotent (zweimal anwenden, Marker filtert Doppel-Apply).
- Smoke-Query (`SELECT 1 FROM users LIMIT 1`) gegen appliziertes Schema.
- `PRAGMA foreign_keys;` → muss `1` zurückgeben (Verbindungssetup prüfen).
- `PRAGMA journal_mode;` → muss `wal` zurückgeben.
- Bei Multi-Writer-Setups (WAL): gebundene SQLite-Library-Version des Treibers gegen ≥ 3.51.3 prüfen (`sqlite/R10`).
- Table-Rebuild-Migrationen: Zeilencount vor und nach dem Rebuild vergleichen (kein Datenverlust).

## Spec-Tagging
Trace-Tag je gedecktem Kriterium gemäss `docs/architecture/traceability-subsystem.md`.
- **Kontext:** SQLite wird fast ausschliesslich via **App-Layer** getestet (TS/JS: `better-sqlite3`, `@databases/sqlite`; Java: JDBC/sqlite-jdbc). Kein SQL-nativer TAP-Runner üblich. Der Trace-Tag sitzt im App-Layer-Test; In-Memory-DB (`:memory:`) empfohlen für schnelle Unit-Tests.
- **Idiom (App-Layer, TS/JS/Java):** Token im `it()`/`test()`-Titel (Vitest/Jest/node:test) oder JUnit-`@Tag`: `it('@trace schema-migration#AC1 — FK-Constraint verhindert Waise', …)`.
- **Extraktions-Rezept:** Core-Regex `@trace\s+([a-z0-9][a-z0-9-]*)#((?:AC\d+|BR-\d+)(?:,(?:AC\d+|BR-\d+))*)` über App-Test-Titel (`grep -RoE` / `vitest list --json`).
- **Fallback:** kanonisches Token in der Test-Description; Core-Regex.
