---
pack: migration/flyway-9
pack_version: 1.1
framework_version_range: ">=9.0, <10.0"
pack_date: 2026-07-21
eol: "EOL/Maintenance — verify aktuelle Lifecycle-Page (documentation.red-gate.com/fd)"
superseded_by: flyway-10
requires:                         # Solver-Constraints (upgrade-subsystem §12); Quelle: A01
  java: ">=8"
primary_sources:
  - https://documentation.red-gate.com/fd
  - https://github.com/flyway/flyway/releases
  - https://documentation.red-gate.com/fd/release-notes-and-older-versions-fd-179732882.html
non_sources:
  - baeldung.com
  - dev.to
  - medium.com
  - stackoverflow.com
---

# Knowledge Pack: flyway-9

Flyway 9.x — Java-Migration-Tool. Geladen bei `profile.db_migration_tool: flyway@9`. Regel-IDs: `flyway-9/A<NN>` · `flyway-9/B<NN>` · `flyway-9/C<NN>`.

> **⚠️ Maintenance-Hinweis:** Flyway 9.x ist nicht mehr die aktive Major-Version — verify gegen `documentation.red-gate.com/fd` für die aktuelle Maintenance-Phase. Neue Projekte sollten direkt `flyway@10` nutzen. Dieses Pack bleibt für Bestandsprojekte, die noch nicht auf 10 migriert haben.

## A. Stable API & Deprecations

> Quellen-getrieben (`train`-Land).

- `flyway-9/A01` — **Java 8 oder höher.** Flyway 9.x läuft unter Java 8+ — Java 17 ist NICHT erforderlich (das ist der Hauptunterschied zu Flyway 10). Bei Migration auf 10: Java 17 wird Pflicht. [src: https://documentation.red-gate.com/fd/release-notes-and-older-versions-fd-179732882.html — verify exact min-java for 9.0]
- `flyway-9/A02` — **Versioned Migrations**: `V<version>__<description>.sql` (z.B. `V1__init.sql`, `V1.2__add_user_table.sql`). Reihenfolge wird über `<version>` aufgelöst (alphanumerisch). `_<description>` ist Mensch-lesbar, ignoriert für Reihenfolge.
- `flyway-9/A03` — **Repeatable Migrations**: `R__<description>.sql` (R-Präfix) werden bei JEDEM Lauf re-applied, wenn die Datei-Checksum sich geändert hat. Nutzbar für Views, Stored Procedures, Seed-Daten — alles wo `CREATE OR REPLACE` Sinn macht.
- `flyway-9/A04` — **Undo Migrations** (Enterprise-only seit 9.0): `U<version>__<description>.sql` als Rollback. **OSS-Edition unterstützt das NICHT** — wer Undo braucht, nutzt Liquibase-OSS oder Flyway-Enterprise.
- `flyway-9/A05` — **`flyway_schema_history`-Tabelle** ist die Marker-Tabelle (NICHT `_schema_migrations` wie bei skeleton). Schema: `installed_rank`, `version`, `description`, `type`, `script`, `checksum`, `installed_by`, `installed_on`, `execution_time`, `success`. Spalten sind nicht direkt user-editierbar; Repair via `flyway repair`.
- `flyway-9/A06` — **`clean` ist seit 9.0 standardmässig DEAKTIVIERT** (Breaking Change ggü. 8.x, Sicherheits-Default gegen versehentliches Prod-Data-Loss). Wortlaut der Quelle: „When you upgrade to Version 9, to carry on using `clean` … you'll need to set `-cleanDisabled` to 'false'." Wer `flyway clean` (CLI/Maven/Gradle) unter 9.x nutzen will, MUSS explizit `-cleanDisabled=false` setzen — ohne diesen Parameter schlägt der Aufruf fehl. [src: https://documentation.red-gate.com/fd/july-2022-version-9-is-coming-what-developers-need-to-know-212140919.html]
- `flyway-9/A07` — **Community-Edition-DB-Versions-Untergrenze seit 9.0**: H2 1.4, Oracle 12.2, MariaDB 10.2 und HSQLDB 2.4 sind aus dem Community-Support herausgefallen (Wortlaut der Quelle: „This year the following database versions have turned 5 🎂: H2 version 1.4, Oracle 12.2, MariaDB 10.2, HSQLDB 2.4"). Projekte, die eine dieser (oder älteren) DB-Versionen brauchen, benötigen entweder eine neuere DB-Version oder Flyway Teams/Enterprise. [src: https://documentation.red-gate.com/fd/july-2022-version-9-is-coming-what-developers-need-to-know-212140919.html]

## B. Anti-Patterns aus Einsatz

> Felderfahrung (`retro`-Land). Initial leer.

_(noch keine Einträge)_

## C. Konventionen (Floor)

- `flyway-9/C01` — **Migrations-Pfad: `src/main/resources/db/migration/`** (Spring-Boot-Default, Maven/Gradle-Standard). NICHT `db_scripts/` — das ist skeleton-Land.
- `flyway-9/C02` — **Niemals committete Migrationen ändern** (Forward-only-Disziplin). Korrekturen via neue Migration mit höherer Version. Bei accidentaler Checksum-Drift: `flyway repair` als letzter Notnagel, NICHT als Routine.
- `flyway-9/C03` — **Klare Versions-Nummerierung**: monotone integer (`V1`, `V2`, `V3`) ODER semantische dezimal-getrennt (`V1.0`, `V1.1`, `V2.0`) — innerhalb eines Projekts EINE Konvention durchziehen.
- `flyway-9/C04` — **Bei Spring-Boot**: `spring.flyway.enabled=true` (Default), `spring.jpa.hibernate.ddl-auto=validate` (NIE `update` oder `create` — sonst läuft JPA dem Flyway hinterher).

## Coder-Guidance

- Neue Migration: nächste freie Versions-Nummer wählen, `V<n>__<beschreibung>.sql` in `src/main/resources/db/migration/` anlegen.
- Niemals existierende Versioned Migration editieren — bei Korrektur neue höhere Version.
- Repeatable-Migrations (`R__`) nur für idempotente Statements (Views, Stored Procedures).
- Bei Spring-Boot: `application.properties` mit `spring.flyway.enabled=true` + `spring.jpa.hibernate.ddl-auto=validate`.

## Reviewer-Checklist

- In-place-Edit einer committeten `V<n>`-Migration → **Critical** (`flyway-9/C02` — Drift-Risiko, Checksum-Fehlschlag bei nächstem Lauf).
- `R__`-Migration mit nicht-idempotenten Statements (z.B. `INSERT` ohne `ON CONFLICT`) → **Important** (`flyway-9/A03` — Repeatable-Migration läuft mehrfach).
- `spring.jpa.hibernate.ddl-auto=update`/`create` UND Flyway aktiv → **Critical** (`flyway-9/C04` — Doppel-Schema-Management).
- Migrations-Datei NICHT in `src/main/resources/db/migration/` → **Important** (`flyway-9/C01` — Konvention-Bruch, Flyway findet sie nicht).
- `U<n>`-Undo-Migration in OSS-Edition → **Important** (`flyway-9/A04` — funktioniert nicht ohne Enterprise-License).
- **Migrations-Empfehlung:** bei jedem PR den Hinweis „Flyway 9.x ist Maintenance — Migration auf 10 prüfen (Java 17 Mindest-Version)" als **Suggestion**.

## Test-Approach

- **Apply-Befehl** (kanonisch, siehe `agents/tester.md` Migration-Apply-Dispatch): `mvn -B -ntp flyway:migrate` (Maven-Plugin) ODER `flyway migrate` (CLI/Docker `flyway/flyway:9-alpine`).
- **Idempotenz-Test:** zweimaliger `flyway:migrate`-Lauf → identischer `flyway_schema_history`-Count.
- **Repair-Pfad-Test:** bei Test-Setup-Drift `flyway:repair` (NIE in Production-CI automatisch).
- **TestContainers** für DB-Integration (Postgres/MySQL) — siehe `frameworks/spring-boot-<major>.md` Test-Approach.
