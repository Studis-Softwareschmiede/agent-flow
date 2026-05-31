---
pack: frameworks/spring-boot-3
pack_version: 1.0
framework_version_range: ">=3.0, <4.0"
pack_date: 2026-05-31
primary_sources:
  - https://docs.spring.io/spring-boot/reference/
  - https://docs.spring.io/spring-boot/docs/3.0.0/reference/htmlsingle/
  - https://github.com/spring-projects/spring-boot/releases
  - https://spring.io/blog
non_sources:
  - baeldung.com
  - dev.to
  - medium.com
  - stackoverflow.com
---

# Knowledge Pack: spring-boot-3

Spring-Boot 3.x (Major-Range `>=3.0, <4.0`). Geladen bei `profile.frameworks` enthält `spring-boot@3`. Regel-IDs: `spring-boot-3/A<NN>` (Sektion A, train) · `spring-boot-3/B<NN>` (Sektion B, retro) · `spring-boot-3/C<NN>` (Sektion C, Floor).

## A. Stable API & Deprecations

> Quellen-getrieben (`train`-Land). Schreibt: `agent-flow:train`. Nicht ändern ohne `/train spring-boot@3`-Lauf.

- `spring-boot-3/A01` — **Jakarta-Namespace Pflicht (since 3.0).** Alle Spring-Boot-3-APIs verwenden `jakarta.*` statt `javax.*`. Bei Migration aus 2.x: Imports automatisch via `org.eclipse.transformer` oder manuell ersetzen. [src: https://github.com/spring-projects/spring-boot/wiki/Spring-Boot-3.0-Release-Notes, since: 3.0]
- `spring-boot-3/A02` — **Java 17 Minimum (since 3.0), Java 21 empfohlen (since 3.2).** Spring-Boot 3.x baut nicht mehr unter Java 11 oder 8. CI-Toolchain entsprechend pinnen. [src: https://github.com/spring-projects/spring-boot/wiki/Spring-Boot-3.0-Release-Notes, since: 3.0]
- `spring-boot-3/A03` — **`@ConfigurationProperties` mit Java Records (since 3.0).** Records werden als immutable Konfigurations-Holder unterstützt; kein Setter-Boilerplate mehr. Beispiel: `@ConfigurationProperties("app") public record AppProps(String host, int port) {}`. [src: https://docs.spring.io/spring-boot/reference/features/external-config.html, since: 3.0]
- `spring-boot-3/A04` — **Virtual Threads opt-in (since 3.2).** `spring.threads.virtual.enabled=true` aktiviert Virtual Threads für Tomcat/Jetty/RestClient/JdbcClient. JDK 21 Pflicht. [src: https://docs.spring.io/spring-boot/reference/features/spring-application.html#features.spring-application.virtual-threads, since: 3.2]
- `spring-boot-3/A05` — **`RestClient` als bevorzugter HTTP-Client (since 3.2).** Synchroner Nachfolger des deprecaten `RestTemplate` (immer noch funktional, aber kein neuer Code mehr). [src: https://docs.spring.io/spring-boot/reference/io/rest-client.html, since: 3.2]

## B. Anti-Patterns aus Einsatz

> Felderfahrung (`retro`-Land). Schreibt: `agent-flow:retro` ab ≥2 Projekten × ≥2 Stellen (siehe `docs/architecture/framework-build-subsystem.md` §9 Schutzgitter). Stand initial: leer — füllt sich, wenn Projekte real damit arbeiten.

_(noch keine Einträge; siehe Schutzgitter in der Spec)_

## C. Konventionen (Floor)

> Stabile Konventionen, manuell gepflegt (User-Approval Pflicht für Edits durch `train`/`retro`).

- `spring-boot-3/C01` — **Constructor-Injection statt Field-Injection.** `@Autowired` auf privaten Feldern ist ein Anti-Pattern: erschwert Testen (kein Mock-Override ohne Reflection), versteckt Pflicht-Dependencies (kein Compile-Check), verhindert `final`. Stattdessen: alle Dependencies im Konstruktor, Felder `private final`, ein einziger Konstruktor (Spring picks automatisch ab 4.3, kein `@Autowired` nötig).
- `spring-boot-3/C02` — **`@Transactional` auf Methoden, nicht auf Klassen.** Klassen-Level-Annotation macht jede public Method transaktional — auch unbeabsichtigte (`hashCode`, `equals`, Getter). Methoden-Level ist explizit und review-bar. Ausnahme: dedicated Services, deren komplette Public-API transaktional sein muss, mit explizitem Code-Kommentar.
- `spring-boot-3/C03` — **Profile-Aktivierung via `spring.profiles.active` Env, nicht via Code.** `SpringApplication.setAdditionalProfiles()` im Code verhindert Override durch Operations (kein 12-Factor). Profile per Env (`SPRING_PROFILES_ACTIVE=prod`).

## Coder-Guidance

- Lies das Pack-Frontmatter (`framework_version_range`) — Code für 3.x darf keine `javax.*`-Imports enthalten (A01).
- Bei DI: Constructor-Injection (C01); kein `@Autowired` auf Field.
- Bei HTTP-Client neu: `RestClient` (A05), kein `RestTemplate`.
- Bei Java 21+ Toolchain: Virtual-Threads aktivieren (A04) für I/O-gebundene Endpoints.

## Reviewer-Checklist

- `javax.*`-Import in 3.x-Code → **Critical** (A01).
- `@Autowired` auf privatem Feld → **Important** (C01).
- `@Transactional` auf Klassen-Level ohne Code-Kommentar-Begründung → **Important** (C02).
- `RestTemplate`-Aufruf in neuem Code → **Suggestion** (A05, Best-Practice).
- `SpringApplication.setAdditionalProfiles()` im Production-Code → **Important** (C03, 12-Factor-Verstoß).
- JDK-Mindestversion (17+) nicht in `pom.xml`/`build.gradle` deklariert → **Important** (A02).

## Test-Approach

- Build via Maven (`mvn -B -ntp verify`) oder Gradle (`./gradlew build --no-daemon`) — siehe `knowledge/build/<build>.md` Test-Approach.
- Integration-Tests mit `@SpringBootTest` + `@AutoConfigureMockMvc` für Controller-Layer.
- Slice-Tests (`@WebMvcTest`, `@DataJpaTest`) für schnellere Feedback-Loops.
- TestContainers für DB-Integration (Postgres/MySQL/Mongo) — kein H2-In-Memory für DB-Verhalten-Tests.
