---
pack: frameworks/spring-boot-2
pack_version: 1.0
framework_version_range: ">=2.0, <3.0"
pack_date: 2026-07-21
eol: 2023-11-18 (OSS — kommerzieller Support via VMware Tanzu bis 2026-08-25)
superseded_by: spring-boot-3
primary_sources:
  - https://docs.spring.io/spring-boot/docs/2.7.x/reference/htmlsingle/
  - https://github.com/spring-projects/spring-boot/wiki/Spring-Boot-2.7-Release-Notes
  - https://github.com/spring-projects/spring-boot/releases
  - https://spring.io/projects/spring-boot/#support
non_sources:
  - baeldung.com
  - dev.to
  - medium.com
  - stackoverflow.com
---

# Knowledge Pack: spring-boot-2

Spring-Boot 2.x (Major-Range `>=2.0, <3.0`). **EOL für OSS seit 2023-11-18; ausschließlich Maintenance-/Migrations-Modus.** Geladen bei `profile.frameworks` enthält `spring-boot@2`. Regel-IDs: `spring-boot-2/A<NN>` (Sektion A, train) · `spring-boot-2/B<NN>` (Sektion B, retro) · `spring-boot-2/C<NN>` (Sektion C, Floor).

> **⚠️ EOL-Hinweis:** Spring-Boot 2.x erhält seit 2023-11-18 KEINE OSS-Security-Patches mehr. Aktive Migration auf 3.x ist die wichtigste Empfehlung dieses Packs (siehe `knowledge/frameworks/spring-boot-3.md`). Verbleibender Use-Case: Bestandsprojekte, die noch nicht migriert sind — der Reviewer flaggt jeden Drift gegen 3.x-Patterns explizit als Migrations-Hinweis.

## A. Stable API & Deprecations

> Quellen-getrieben (`train`-Land). Schreibt: `agent-flow:train`. Nicht ändern ohne `/train spring-boot@2`-Lauf.

- `spring-boot-2/A01` — **`javax.*`-Namespace Pflicht.** Alle Spring-Boot-2-APIs verwenden `javax.*` (NICHT `jakarta.*`). Bei Migration auf 3.x: Imports automatisch via `org.eclipse.transformer` oder manuell ersetzen. [src: https://github.com/spring-projects/spring-boot/wiki/Spring-Boot-3.0-Release-Notes, since: 2.0]
- `spring-boot-2/A02` — **Java 8 oder 11 Minimum (since 2.0).** Spring-Boot 2.x baut unter Java 8/11; Java 17 wird in späteren 2.x-Releases (verify gegen die jeweilige Release-Note der eingesetzten 2.x-Version) ebenfalls unterstützt, ist aber nicht erforderlich. Bei Migration auf 3.x wird Java 17 Minimum. [src: https://github.com/spring-projects/spring-boot/wiki/Spring-Boot-2.7-Release-Notes, since: 2.0]
- `spring-boot-2/A03` — **`RestTemplate` als Standard-HTTP-Client.** Synchroner Client (NICHT `@Deprecated` in 2.x, aber laut Spring-Doku in Maintenance-Mode). `WebClient` (reactive) ist die Alternative für asynchrone Calls. `RestClient` (in 3.2 neu) existiert in 2.x NICHT. [src: https://docs.spring.io/spring-boot/docs/2.7.x/reference/htmlsingle/#io.rest-client, since: 2.0]
- `spring-boot-2/A04` — **Spring-Boot 2.7 ist die letzte 2.x-Version.** Danach kommt nur Spring-Boot 3.0 — kein 2.8. OSS-Support für 2.7 ist beendet; kommerzieller Support (Tanzu Spring Runtime) läuft noch — **die genauen Datumsangaben bitte aus der Support-Seite live verifizieren** (Support-Pläne werden gelegentlich aktualisiert). [src: https://spring.io/projects/spring-boot/#support — verify date]
- `spring-boot-2/A05` — **Kein Virtual-Threads-Support.** Spring-Boot 2.x kennt keine `spring.threads.virtual.enabled`-Property (since 3.2 in 3.x). Virtual Threads sind 2.x prinzipiell nicht zugänglich (Tomcat 9 in 2.x ist nicht Virtual-Thread-aware). Migration auf 3.x nötig, um Java-21-Skalierungs-Pattern zu nutzen. [src: https://docs.spring.io/spring-boot/docs/2.7.x/reference/htmlsingle/, since: 2.0]
- `spring-boot-2/A06` — **Java 21 als Runtime kompatibel (ohne Virtual Threads, siehe A05).** Laut System-Requirements-Sektion der Referenz-Doku: „Spring Boot 2.7.18 requires Java 8 and is compatible up to and including Java 21." D.h. ein 2.7.18-Projekt darf auf JDK 21 laufen (reine Runtime-Kompatibilität), OHNE dass dadurch Java-21-Features wie Virtual Threads oder Pattern-Matching-for-switch produktiv nutzbar würden (A05) — Framework-API bleibt auf Java-8/11-Sprachniveau ausgelegt. [src: https://docs.spring.io/spring-boot/docs/2.7.x/reference/htmlsingle/#getting-started.system-requirements, since: 2.7.18]
- `spring-boot-2/A07` — **`spring.factories`-Auto-Configuration seit 2.7 deprecated — Migration zu `AutoConfiguration.imports`.** Die Registrierung von Auto-Configurations über den `org.springframework.boot.autoconfigure.EnableAutoConfiguration`-Key in `META-INF/spring.factories` ist seit 2.7 deprecated (aus Kompatibilitätsgründen weiterhin honoriert). Neuer Ort: `META-INF/spring/org.springframework.boot.autoconfigure.AutoConfiguration.imports` — pro Zeile ein vollqualifizierter Klassenname (kein CSV-Format), Klassen mit `@AutoConfiguration` statt reinem `@Configuration` annotieren. Beide Dateien dürfen parallel existieren (Einträge werden dedupliziert) — Übergangsstrategie für Libraries, die mehrere Spring-Boot-Versionen unterstützen müssen. [src: https://github.com/spring-projects/spring-boot/wiki/Spring-Boot-2.7-Release-Notes, since: 2.7.0]

## B. Anti-Patterns aus Einsatz

> Felderfahrung (`retro`-Land). Schreibt: `agent-flow:retro` ab ≥2 Projekten × ≥2 Stellen (siehe `docs/architecture/framework-build-subsystem.md` §9 Schutzgitter). Stand initial: leer — füllt sich, wenn Projekte real damit arbeiten.

_(noch keine Einträge; siehe Schutzgitter in der Spec)_

## C. Konventionen (Floor)

> Stabile Konventionen, manuell gepflegt (User-Approval Pflicht für Edits durch `train`/`retro`). Identisch zu `spring-boot-3/C01-C03` — gleiche DI-/Tx-/Profile-Pattern in beiden Majors.

- `spring-boot-2/C01` — **Constructor-Injection statt Field-Injection.** `@Autowired` auf privaten Feldern ist ein Anti-Pattern: erschwert Testen (kein Mock-Override ohne Reflection), versteckt Pflicht-Dependencies (kein Compile-Check), verhindert `final`. Stattdessen: alle Dependencies im Konstruktor, Felder `private final`, ein einziger Konstruktor (Spring picks automatisch ab 4.3, kein `@Autowired` nötig).
- `spring-boot-2/C02` — **`@Transactional` auf Methoden, nicht auf Klassen.** Klassen-Level-Annotation macht jede public Method transaktional — auch unbeabsichtigte (`hashCode`, `equals`, Getter). Methoden-Level ist explizit und review-bar. Ausnahme: dedicated Services, deren komplette Public-API transaktional sein muss, mit explizitem Code-Kommentar.
- `spring-boot-2/C03` — **Profile-Aktivierung via `spring.profiles.active` Env, nicht via Code.** `SpringApplication.setAdditionalProfiles()` im Code verhindert Override durch Operations (kein 12-Factor). Profile per Env (`SPRING_PROFILES_ACTIVE=prod`).
- `spring-boot-2/C04` — **EOL-Bewusstsein: jeder Neu-Code in 2.x braucht eine Migrations-Begründung.** Spring-Boot 2.x ist OSS-EOL — neuer Code sollte nicht in 2.x entstehen, außer es gibt einen dokumentierten Migrations-Block (z.B. „Dependency-Library X migriert erst in Q3 nach jakarta-Namespace"). Reviewer-Flag bei Neu-Code ohne Migrations-Kommentar = Important.

## Coder-Guidance

- Lies das Pack-Frontmatter (`framework_version_range` + `eol`) — Spring-Boot 2.x ist OSS-EOL; neuer Code braucht eine Migrations-Begründung (C04).
- `javax.*`-Imports verwenden, NICHT `jakarta.*` (A01).
- Bei DI: Constructor-Injection (C01); kein `@Autowired` auf Field.
- Bei neuem HTTP-Code: `WebClient` (asynchron) oder `RestTemplate` (synchron — Maintenance-Mode). KEIN `RestClient` (existiert erst in 3.2+).
- Bei Java 17 Toolchain: keine Java-21-Features (Virtual Threads / Pattern-Matching for switch) — die laufen erst in 3.x produktiv.

## Reviewer-Checklist

- `jakarta.*`-Import in 2.x-Code → **Critical** (A01, falsches Namespace; jakarta lebt erst in 3.x).
- `@Autowired` auf privatem Feld → **Important** (C01).
- `@Transactional` auf Klassen-Level ohne Code-Kommentar-Begründung → **Important** (C02).
- `SpringApplication.setAdditionalProfiles()` im Production-Code → **Important** (C03, 12-Factor-Verstoß).
- `RestClient`-Import (kompiliert in 2.x nicht) → **Critical** (A03; gehört zu 3.2+).
- JDK-Mindestversion (8 oder 11) nicht in `pom.xml`/`build.gradle` deklariert → **Important** (A02).
- Neu-Code in 2.x-Projekt ohne Migrations-Begründungs-Kommentar → **Important** (C04, EOL-Bewusstsein).
- **Migrations-Empfehlung im Review-Output:** bei jedem PR den Hinweis „Spring-Boot 2.x ist OSS-EOL; Migration auf 3.x prüfen" als **Suggestion**.

## Test-Approach

- Build via Maven (`mvn -B -ntp verify`) oder Gradle (`./gradlew build --no-daemon`) — siehe `knowledge/build/<build>.md` Test-Approach.
- Integration-Tests mit `@SpringBootTest` + `@AutoConfigureMockMvc` für Controller-Layer.
- Slice-Tests (`@WebMvcTest`, `@DataJpaTest`, `@JsonTest`) für schnellere Feedback-Loops.
- TestContainers für DB-Integration (Postgres/MySQL/Mongo) — H2-In-Memory ist in 2.x noch verbreiteter, aber für DB-Verhalten-Tests trotzdem TestContainers nutzen.
- **EOL-Test:** CI sollte einmal pro Sprint die Dependency-Liste gegen `spring-boot-dependencies:3.x` BOM vergleichen, um die Migrations-Distanz zu tracken.
