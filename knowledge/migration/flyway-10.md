---
pack: migration/flyway-10
pack_version: 1.1
framework_version_range: ">=10.0, <11.0"
pack_date: 2026-06-02
requires:                         # Solver-Constraints (upgrade-subsystem §12); Quelle: A01
  java: ">=17"
primary_sources:
  - https://documentation.red-gate.com/fd
  - https://github.com/flyway/flyway/releases
  - https://documentation.red-gate.com/fd/release-notes-flyway-engine-179732572.html
non_sources:
  - baeldung.com
  - dev.to
  - medium.com
  - stackoverflow.com
---

# Knowledge Pack: flyway-10

Flyway 10.x — Java-Migration-Tool, Current-Major mit **Java 17 als Mindest-Version** (Hauptunterschied zu 9.x). Geladen bei `profile.db_migration_tool: flyway@10`. Regel-IDs: `flyway-10/A<NN>` · `flyway-10/B<NN>` · `flyway-10/C<NN>`.

## A. Stable API & Deprecations

> Quellen-getrieben (`train`-Land).

- `flyway-10/A01` — **Java 17 Mindest-Version (since 10.0).** Flyway-10-Core läuft NICHT mehr unter Java 8/11. Bei Migration aus 9.x: Toolchain auf Java 17+ heben. Quelle: [Flyway 10.0.0 Release Notes — Breaking-Changes](https://documentation.red-gate.com/fd/release-notes-flyway-engine-179732572.html) — verbatim aus den Release-Notes: „Retired Java 8 from use. Java 17 is now required for development".
- `flyway-10/A02` — **Versioned Migrations** unverändert zu 9.x: `V<version>__<description>.sql`.
- `flyway-10/A03` — **Repeatable Migrations** unverändert: `R__<description>.sql`.
- `flyway-10/A04` — **Undo Migrations** weiterhin Enterprise-only.
- `flyway-10/A05` — **Native-Connector-Splits** (since 10.0): einzelne DB-Treiber als separate Module (`flyway-database-postgresql`, `flyway-database-mysql`, etc.). Bei Maven-Setup explizit deklarieren — der Core hat nicht mehr alle Treiber inkludiert. Verify gegen die aktuelle Maven-Coordinates-Tabelle der Release-Notes für deinen Dialekt.

## B. Anti-Patterns aus Einsatz

> Felderfahrung (`retro`-Land).

- `flyway-10/B01` — **Dialekt-Modul-Lücke beim SB2→3-BOM-Bump bleibt unsichtbar bis zum Boot.** Hebt ein Spring-Boot-2→3-Upgrade Flyway transitiv über die BOM von 8/9 auf 10, fügt **OpenRewrite das nach `flyway-10/A05` nun pflichtige `flyway-database-<dialect>`-Modul NICHT hinzu** — der Diff sieht grün aus, kompiliert, und Unit-Tests (insb. mit `spring.flyway.enabled=false`) bleiben grün. Erst der **echte Boot** wirft `Unsupported Database: <engine>`. Zusätzlich ist Flyway 10s Engine-Erkennung **strenger** als 9.x: ein MariaDB-Server hinter `db_dialect=mysql` + MySQL-Connector, den Flyway 8/9 noch stillschweigend tolerierte, wird jetzt abgelehnt — Engine, JDBC-Treiber und `flyway-database-<dialect>`-Modul müssen konsistent zum **real laufenden** Server sein, nicht nur zum konfigurierten Dialekt. **Pflicht:** Bei jedem Upgrade, das Flyway transitiv auf 10 hebt, das Dialekt-Modul explizit ergänzen (A05/C05) UND einen Real-DB-Boot-Smoke gegen die tatsächliche Engine fahren (Querverweis `upgrade-subsystem §17-R1/R2` — Unit-Gate sieht diese Klasse strukturell nicht). [seen-in: 1 Projekt, promoted: 2026-06-03]

## C. Konventionen (Floor)

- `flyway-10/C01` — **Migrations-Pfad: `src/main/resources/db/migration/`** (unverändert zu 9.x).
- `flyway-10/C02` — **Forward-only-Disziplin** (identisch zu 9.x).
- `flyway-10/C03` — **Klare Versions-Nummerierung** (identisch zu 9.x).
- `flyway-10/C04` — **Bei Spring-Boot 3.x**: `spring.flyway.enabled=true` + `spring.jpa.hibernate.ddl-auto=validate`. Spring-Boot 3.x braucht Java 17 ohnehin → kein zusätzlicher Java-Toolchain-Konflikt.
- `flyway-10/C05` — **Native-Connector Dep explizit deklarieren** (`flyway-10/A05`): in `pom.xml` zusätzlich zum `flyway-core` auch `flyway-database-<dialect>` (z.B. `flyway-database-postgresql`) als Dep.

## Coder-Guidance

- Java-Toolchain auf 17+ pinnen (A01).
- Native-Connector-Dep für den Ziel-Dialekt explizit ergänzen (A05/C05).
- Sonst identisch zu flyway-9 (Versioned/Repeatable/Undo).

## Reviewer-Checklist

- Java-Toolchain < 17 + flyway-10-Dep → **Critical** (A01, kompiliert nicht).
- `flyway-core` ohne passenden `flyway-database-<dialect>` Dep → **Important** (A05/C05 — fehlender Treiber, Boot-Fehler).
- Upgrade-Diff hebt Flyway transitiv (BOM) auf 10, aber Dialekt-Modul fehlt im `pom` ODER kein Real-DB-Boot-Smoke gefahren → **Critical** (B01 — grüne Unit-Tests verdecken den `Unsupported Database`-Boot-Fehler; vgl. `upgrade-subsystem §17-R2`).
- `db_dialect`/Connector ≠ real laufende Engine (z.B. `mysql`-Connector gegen MariaDB-Server) → **Critical** (B01 — Flyway 10 erkennt strenger als 9.x).
- In-place-Edit einer committeten `V<n>`-Migration → **Critical** (C02).
- `spring.jpa.hibernate.ddl-auto=update`/`create` UND Flyway aktiv → **Critical** (C04).
- `U<n>`-Undo-Migration in OSS-Edition → **Important** (A04).

## Test-Approach

- **Apply-Befehl (kanonisch, siehe `agents/tester.md` Migration-Apply-Dispatch):** `mvn -B -ntp flyway:migrate` (Maven-Plugin) ODER `flyway migrate` (CLI/Docker `flyway/flyway:10-alpine`).
- **Idempotenz-Test:** zweimaliger Lauf → identischer Schema-History-Count.
- **TestContainers** für DB-Integration (siehe `frameworks/spring-boot-3.md` Test-Approach).
