---
pack: migration/alembic
pack_version: 1.0
framework_version_range: ""
pack_date: 2026-07-12
primary_sources:
  - https://alembic.sqlalchemy.org/en/latest/tutorial.html
  - https://alembic.sqlalchemy.org/en/latest/autogenerate.html
  - https://alembic.sqlalchemy.org/en/latest/cookbook.html
non_sources: [dev.to, medium.com, stackoverflow.com, geeksforgeeks.org, baeldung.com]
---

# Knowledge Pack: alembic

Alembic — das SQLAlchemy-Migrationstool für Python. Geladen bei `profile.db_migration_tool: alembic` (Default-Vorschlag für `lang: py` + relationale DB, außer bei Django-Projekten, dort `django-migrations` — `migration-tool-subsystem.md` §5). Kein Major-Cut bisher dokumentiert, daher entfällt `framework_version_range`. Regel-IDs: `alembic/A<NN>` · `alembic/B<NN>` · `alembic/C<NN>`.

## A. Stable API & Deprecations

> Quellen-getrieben (`train`-Land). Schreibt: `agent-flow:train`. Nicht ändern ohne `/train migration/alembic`-Lauf.

- `alembic/A01` — **Environment-Setup & Pflicht-Key.** `alembic init <directory>` legt die Migrationsumgebung an (u.a. `alembic.ini`, `env.py`, `versions/`). `script_location` ist der einzige in jedem Fall verpflichtende Konfig-Key — verbatim: „This is the only key required by Alembic in all cases." Quelle: [Tutorial — Editing the .ini File](https://alembic.sqlalchemy.org/en/latest/tutorial.html#editing-the-ini-file).
- `alembic/A02` — **`pyproject.toml`-Konfiguration als Alternative zu `alembic.ini` (since 1.16.0).** Verbatim: „Changed in version 1.16.0: A new pyproject template has been added." Ergänzt `alembic.ini`, ersetzt es nicht zwingend. Quelle: [Tutorial — Using pyproject.toml for configuration](https://alembic.sqlalchemy.org/en/latest/tutorial.html#using-pyproject-toml-for-configuration).
- `alembic/A03` — **Revision-Script-Struktur.** Jede Migration in `versions/` trägt `revision`, `down_revision` (Elternrevision; `None` = erste Datei), `branch_labels`, `depends_on` sowie `upgrade()`/`downgrade()`. Datei-Namensschema per `file_template` konfigurierbar (Default `%(rev)s_%(slug)s`). Quelle: [Tutorial — Create a Migration Script](https://alembic.sqlalchemy.org/en/latest/tutorial.html#create-a-migration-script).
- `alembic/A04` — **Apply-/Rollback-Kommandos.** `alembic upgrade head` (bis Spitze), `alembic upgrade +N` / `alembic downgrade -N` (relativ), `alembic downgrade base` (vollständiger Rollback). Status: `alembic current`, `alembic history --verbose`. Quelle: [Tutorial — Running our First Migration](https://alembic.sqlalchemy.org/en/latest/tutorial.html#running-our-first-migration) + [Relative Migration Identifiers](https://alembic.sqlalchemy.org/en/latest/tutorial.html#relative-migration-identifiers) + [Downgrading](https://alembic.sqlalchemy.org/en/latest/tutorial.html#downgrading).
- `alembic/A05` — **Splicing/Branch-Merge ist möglich, aber manuell heikel.** Verbatim: „it is theoretically possible to 'splice' version files in between others, allowing migration sequences from different branches to be merged, albeit carefully by hand." Quelle: [Tutorial](https://alembic.sqlalchemy.org/en/latest/tutorial.html#tutorial).
- `alembic/A06` — **Autogenerate erkennt zuverlässig:** Tabellen-Add/Remove, Spalten-Add/Remove, Nullable-Änderungen, einfache Index-/explizit benannte Unique-Constraint-Änderungen, einfache FK-Constraint-Änderungen. Optional (konfigurationsabhängig): Spaltentyp-Änderungen (`compare_type`) und Server-Default-Änderungen (`compare_server_default`). Quelle: [Autogenerate — What does Autogenerate detect](https://alembic.sqlalchemy.org/en/latest/autogenerate.html#what-does-autogenerate-detect-and-what-does-it-not-detect).
- `alembic/A07` — **`compare_type`-Default ist seit 1.12.0 `True`.** Verbatim: „Changed in version 1.12.0: The default value of EnvironmentContext.configure.compare_type has been changed to True." Vorher musste es explizit aktiviert werden. Quelle: [Autogenerate — Comparing Types](https://alembic.sqlalchemy.org/en/latest/autogenerate.html#comparing-types).
- `alembic/A08` — **Autogenerate erkennt NICHT:** Tabellen-/Spalten-Umbenennungen (erscheinen als Add/Drop-Paar, keine Rename-Erkennung), anonym benannte Constraints, Spezial-Typen wie `Enum` auf Backends ohne native Unterstützung, sowie (aktuell noch) freistehende Constraints (`PRIMARY KEY`/`EXCLUDE`/`CHECK`) und Sequence-Add/Remove. Verbatim zur Grund-Warnung: „autogenerate is not intended to be perfect. It is always necessary to manually review and correct the candidate migrations that autogenerate produces." Quelle: [Autogenerate — What does Autogenerate detect](https://alembic.sqlalchemy.org/en/latest/autogenerate.html#what-does-autogenerate-detect-and-what-does-it-not-detect).
- `alembic/A09` — **`alembic check` (since 1.9.0)** vergleicht Modelle gegen den DB-Stand und meldet fehlende Autogenerate-Operationen — geeignet als CI-Gate gegen unautogenerate Model-Drift. Verbatim: „Added in version 1.9.0." Quelle: [Autogenerate — Running Alembic Check to test for new upgrade operations](https://alembic.sqlalchemy.org/en/latest/autogenerate.html#running-alembic-check-to-test-for-new-upgrade-operations).
- `alembic/A10` — **`alembic current --check-heads` (since 1.17.1)** prüft, ob die DB auf dem/den Head-Revisionen steht (Exit-Code-Signal), vormals nur als Hand-Rezept dokumentiert. Verbatim: „Changed in version 1.17.1: This recipe is now part of the alembic current command using the command.current.check_heads parameter, available from the command line as --check-heads." Quelle: [Cookbook — Test current database revision is at head(s)](https://alembic.sqlalchemy.org/en/latest/cookbook.html#test-current-database-revision-is-at-head-s).
- `alembic/A11` — **Mehrere benannte Environments in einer `alembic.ini`** via `[abschnittsname]`-Sections + `alembic --name <abschnitt> ...`, um unabhängige Versionshistorien (z.B. pro Schema) im selben Repo zu pflegen. Quelle: [Cookbook — Run Multiple Alembic Environments from one .ini file](https://alembic.sqlalchemy.org/en/latest/cookbook.html#run-multiple-alembic-environments-from-one-ini-file).
- `alembic/A12` — **Schema-Level-Multi-Tenancy ist nicht nativ eingebaut**, wird über wiederholte Alembic-Läufe pro Ziel-DB/Schema erreicht (z.B. Postgres `SET search_path`, MySQL/MariaDB `USE <db>`); üblicher Aufruf `alembic -x tenant=<schema> upgrade head`. Verbatim: „Alembic does not currently have explicit multi-tenant support; typically, the approach must involve running Alembic multiple times against different database URLs." Quelle: [Cookbook — Rudimental Schema-Level Multi Tenancy](https://alembic.sqlalchemy.org/en/latest/cookbook.html#rudimental-schema-level-multi-tenancy-for-postgresql-mysql-other-databases).
- `alembic/A13` — **Leere Autogenerate-Revisionen unterdrücken** via `process_revision_directives`-Hook in `env.py` (entfernt die `MigrationScript`-Direktive, wenn `upgrade_ops.is_empty()`). Quelle: [Cookbook — Don't Generate Empty Migrations with Autogenerate](https://alembic.sqlalchemy.org/en/latest/cookbook.html#don-t-generate-empty-migrations-with-autogenerate).
- `alembic/A14` — **Für Daten-Migrationen gibt es keine Alembic-eigene Best-Practice-Norm** — Schema- und Daten-Migration sind bewusst getrennt gehalten (Downgrade von Datenlöschungen ist oft nicht sauber umkehrbar). Verbatim: „The solution needs to be designed specifically for each individual application and migration. There are no general rules and the following text is only a recommendation based on experience." Empfohlene Grundmuster: kleine Datenmengen via `op.bulk_insert()` inline, größere/komplexere über ein separates Migrations-Skript, oder Online-Migration mit Anwendungslogik. Quelle: [Cookbook — Data Migrations - General Techniques](https://alembic.sqlalchemy.org/en/latest/cookbook.html#data-migrations-general-techniques).

## B. Anti-Patterns aus Einsatz

> Felderfahrung (`retro`-Land). Schreibt: `agent-flow:retro`.

- `alembic/B01` — **SQLite-only-Unit-Tests sind für DB-Engine-spezifisches Verhalten (Constraint-Trigger, FK-Aktionen, Advisory-Locks, Nebenläufigkeit, NUMERIC-Rundung) beweislos — mindestens EIN Test je solchem Verhaltens-Feature MUSS gegen echtes Postgres (temporärer Container) laufen.** In jedem Projekt mit SQLite-basierten Unit-Tests und Postgres-Produktion verdeckt der SQLite-Stand-in eine ganze Klasse von Postgres-only-Semantiken, die grün durch die Suite laufen und erst unter der echten Engine (oder in Produktion) brechen:
  - **(a) Deferred Constraint-Trigger blockiert `ALTER TABLE`.** Ein bestehender `CONSTRAINT TRIGGER … DEFERRABLE INITIALLY DEFERRED` lässt in derselben Transaktion kein `ALTER TABLE` (PK-Tausch, `SET NOT NULL`, Spalten-Add/Drop) mehr zu, sobald zuvor ein `INSERT`/`UPDATE`/`DELETE` auf derselben Tabelle den Trigger „armiert" hat (`cannot ALTER TABLE … because it has pending trigger events`) — auch wenn der Trigger noch nicht gefeuert ist. Migrations-Muster: Trigger+Funktion **vor** dem Backfill-DML droppen, das DDL fahren, den Trigger **erst nach** dem letzten `ALTER TABLE` neu anlegen. SQLite kennt keine deferred Constraint-Trigger → in Unit-Tests unsichtbar.
  - **(b) Neue FK ohne `ON DELETE`-Klausel bricht bestehende bulk-`DELETE`/`rebuild`-Funktionen.** Eine FK auf eine mutierbare Tabelle mit Default `NO ACTION` lässt jedes `DELETE` der referenzierten Zeilen fehlschlagen, sobald referenzierende Zeilen existieren — auch wenn die `rebuild`-Funktion im aktuellen Diff gar nicht angefasst wurde. Bei jeder neuen FK auf eine Tabelle mit (künftigen) bulk-`DELETE`/`rebuild`-Pfaden explizit `ON DELETE CASCADE` setzen ODER die `rebuild`-Funktion um Vorab-Löschen der abhängigen Zeilen ergänzen. Fällt in SQLite-Tests nur auf, wenn `PRAGMA foreign_keys=ON` in **den betroffenen** Fixtures aktiv ist (Default OFF) — und die Test-Datei die reale `rebuild`-Funktion tatsächlich aufruft.
  - **(c) `RETURN NULL`-Dedupe-Trigger ist ORM-unsicher UND race-unsicher.** Ein BEFORE-INSERT-Trigger, der Duplikate per `RETURN NULL` verschluckt, bricht mit SQLAlchemy-ORM (das per `expire_on_commit` abgelaufene Objekt wirft beim nächsten Attribut-Zugriff `ObjectDeletedError`, weil keine Zeile existiert) und schützt unter READ COMMITTED nicht gegen echte Nebenläufigkeit (zwei parallel offene Tx sehen die jeweils andere uncommittete Zeile nicht → beide Inserts laufen durch). Für echten Duplikatschutz: Unique-Constraint + `ON CONFLICT`-Behandlung im App-Layer, oder ein Trigger, der eine **fangbare Exception** wirft (kein stilles `RETURN NULL`).
  - **(d) Read-then-Write-Dedupe ohne Advisory-Lock/Unique-Constraint dupliziert unter Nebenläufigkeit** (empirisch: zwei Threads, `threading.Barrier` → 2 Zeilen statt 1). Advisory-Locks in der **Zwei-Key-Form** `pg_advisory_xact_lock(hashtext('<domäne>'), hashtext(<fachlicher_schlüssel>))` verwenden, damit verschiedene Module nicht den vollen 32-Bit-Hash-Raum teilen und sich cross-domänisch serialisieren.
  - **(e) `NUMERIC(p,s)` rundet in Postgres still beim Insert, in SQLite nicht** — ein nicht terminierender `Decimal` (z. B. ein Ø-Mittelungswert bei Nachkauf) landet unter SQLite ungerundet, unter Postgres gerundet → Test/Prod-Divergenz. Geld-/Ratenwerte am Schreib-Call-Site explizit quantisieren.

  Kern-Gebot: SQLite-only-Grün ist für Trigger-/FK-/Lock-/Concurrency-/NUMERIC-Verhalten **kein Beleg**. Verwandt mit `upgrade-subsystem §17` (grüne Unit-Tests ≠ funktionierendes Upgrade sobald DB-Engine berührt) + `reviewer/R06` (Mock-grün ≠ realer Vertrag). `[seen-in: 1 Projekt (ki-investment, org-weit einziges Postgres-Projekt) / 6 unabhängige Vorfälle — Owner-Approved G1-Override 2026-07-14; promoted: 2026-07-14]`

## C. Konventionen (Floor)

> Manuell gepflegt. Änderungen nur mit User-Approval. Initial-Grundgerüst (kein Vorgänger zum Erben, No-Predecessor-Bootstrap) — abgeleitet aus den Primärquellen (A03/A04), keine erfundenen Projekt-Konventionen.

- `alembic/C01` — **Migrations-Pfad: `alembic/versions/`** (bzw. der in `script_location` konfigurierte Ort). Kanonischer Default aus `alembic init`.
- `alembic/C02` — **Forward-only im Regelbetrieb:** committete Revisionen werden nicht editiert; Korrekturen als neue Revision mit passendem `down_revision`-Kettenglied (A03).
- `alembic/C03` — **Jede Autogenerate-Revision wird vor dem Commit manuell durchgesehen** (A08 — Autogenerate ist explizit nicht auf Perfektion ausgelegt; Rename-Fälle und freistehende Constraints erfordern Hand-Korrektur).

## Coder-Guidance

- Neue Migration bevorzugt via `alembic revision --autogenerate -m "<beschreibung>"`, danach die generierte Datei vollständig durchsehen (A08/C03) — insbesondere Tabellen-/Spalten-Umbenennungen (kommen als Add/Drop) und Daten-Migrationen (A14) von Hand ergänzen.
- Spaltentyp-Änderungen verlassen sich seit 1.12.0 per Default auf `compare_type=True` (A07) — bei False-Positives `compare_type` projektspezifisch per Callable verfeinern statt global abschalten.
- Rollback-Pfad (`downgrade()`) immer mitpflegen, auch wenn er in der Praxis selten läuft — Alembic erwartet die Kette für `alembic downgrade`.
- Bei Multi-Tenant-Setups: kein eingebautes Tenant-Konzept (A12) — Tenant-Parameter explizit über `-x`-Flag und `env.py`-Hook durchreichen, nicht stillschweigend annehmen.

## Reviewer-Checklist

- Autogenerate-Revision ohne sichtbare manuelle Durchsicht/Anpassung bei Rename-verdächtigen Diffs (Drop+Create desselben Spalten-/Tabellen-Shapes mit anderem Namen) → **Important** (A08/C03 — Autogenerate erkennt keine Umbenennungen).
- `down_revision`-Kette gebrochen oder mehrere Heads ohne Merge-Revision → **Critical** (A03/A05 — `alembic upgrade head` schlägt fehl oder wählt einen unerwarteten Head).
- In-place-Edit einer bereits applied/committeten Revision-Datei → **Critical** (C02 Forward-only-Verstoß).
- Daten-Migration direkt in einer Schema-Revision ohne bewusste Strategie-Entscheidung (A14) → **Important** — nachfragen, ob kleine Inline-Daten, separates Skript oder Online-Migration beabsichtigt ist.
- `compare_type`/`compare_server_default` global auf `False` gesetzt ohne Begründung → **Important** (A07 — verschenkt seit 1.12.0 Default-Schutz gegen übersehene Typ-Drifts).

## Test-Approach

- **Apply-Befehl (kanonisch, siehe `agents/tester.md` Migration-Apply-Dispatch, `migration-tool-subsystem.md` §9):** `alembic upgrade head` — Exit-Code 0 = PASS.
- **Head-Konsistenz-Check:** `alembic current --check-heads` (A10, seit 1.17.1) — non-zero Exit, wenn die DB nicht auf dem/den Head(s) steht.
- **Model-Drift-Gate (CI-geeignet):** `alembic check` (A09, seit 1.9.0) — non-zero Exit, wenn das SQLAlchemy-Modell Änderungen enthält, die noch keine Revision haben.
- **Idempotenz-Test:** zweimaliger `alembic upgrade head`-Lauf → zweiter Lauf no-op (kein Fehler, `alembic current` unverändert).
