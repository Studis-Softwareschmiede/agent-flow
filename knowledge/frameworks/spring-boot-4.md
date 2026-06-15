---
pack: frameworks/spring-boot-4
pack_version: 1.2
framework_version_range: ">=4.0, <5.0"
pack_date: 2026-06-15
requires:                         # Solver-Constraints (upgrade-subsystem §12); Quelle: A01/A02
  java: ">=17"
  build: { maven: ">=3.6.3", gradle: ">=8.14" }
compatible_with:                  # Quelle: A03 (Jakarta EE 11) + A04
  migration: { flyway: ">=10", liquibase: ">=4" }
incompatible:                     # Quelle: A03 (Servlet 6.1 — Undertow nicht mehr unterstützt)
  - container=undertow
primary_sources:
  - https://docs.spring.io/spring-boot/reference/
  - https://docs.spring.io/spring-boot/system-requirements.html
  - https://github.com/spring-projects/spring-boot/wiki/Spring-Boot-4.0-Migration-Guide
  - https://github.com/spring-projects/spring-boot/wiki/Spring-Boot-4.1-Release-Notes
  - https://github.com/spring-projects/spring-boot/releases
  - https://docs.spring.io/spring-framework/reference/
  - https://spring.io/blog
non_sources:
  - baeldung.com
  - dev.to
  - medium.com
  - stackoverflow.com
---

# Knowledge Pack: spring-boot-4

Spring-Boot 4.x (Major-Range `>=4.0, <5.0`, GA 2025-11-20; aktuell: 4.1.0 GA 2026-06-10). Geladen bei `profile.frameworks` enthält `spring-boot@4`. Regel-IDs: `spring-boot-4/A<NN>` (Sektion A, train) · `spring-boot-4/B<NN>` (Sektion B, retro) · `spring-boot-4/C<NN>` (Sektion C, Floor).

> **Migrations-Kontext:** Ziel der Migration weg von `spring-boot-3` (siehe `spring-boot-3.md`, dort `superseded_by`). Der Sprung 3 → 4 ist ein **Cut**: Spring Framework 7, Jakarta EE 11 (Servlet 6.1), modularisierte Artefakte, Jackson 3, entfernte 3.x-Deprecations — alter Code MUSS angepasst werden. Hilfsmittel: `spring-boot-properties-migrator` (Config-Property-Renames zur Laufzeit), `org.eclipse.transformer` (Namespace), Migration-Guide als autoritative Schritt-Quelle.

## A. Stable API & Deprecations

> Quellen-getrieben (`train`-Land). Schreibt: `agent-flow:train`. Nicht ändern ohne `/train spring-boot@4`-Lauf.

- `spring-boot-4/A01` — **Java 17 Baseline, Java 25 first-class empfohlen (since 4.0).** SB4 baut ab Java 17 (kompatibel bis Java 26); die jeweils aktuelle LTS wird empfohlen, Java 25 erhält First-Class-Support unter Beibehaltung der Java-17-Kompatibilität. JDK-Mindestversion in `pom.xml`/`build.gradle` deklarieren. [src: https://docs.spring.io/spring-boot/system-requirements.html (Java 17 Minimum, kompatibel bis Java 26) · https://spring.io/blog/2025/11/20/spring-boot-4-0-0-available-now (Java 25 first-class), since: 4.0]
- `spring-boot-4/A02` — **Spring Framework 7 Pflicht (since 4.0).** SB4 setzt zwingend Spring Framework `7.0.7+` voraus (Dependency-Management direkt). Build-Tools: Maven `3.6.3+`, Gradle `8.14+`/`9.x`. [src: https://docs.spring.io/spring-boot/system-requirements.html, since: 4.0]
- `spring-boot-4/A03` — **Jakarta EE 11 / Servlet 6.1 Baseline (since 4.0).** Container: Tomcat 11.0.x, Jetty 12.1.x (Servlet 6.1). **Undertow ist nicht mehr unterstützt** (inkompatibel mit Servlet 6.1) — bei Migration auf Tomcat/Jetty wechseln. GraalVM `25+` für Native-Image, Kotlin `2.2+`. [src: https://docs.spring.io/spring-boot/system-requirements.html (GraalVM 25, Servlet 6.1) · https://github.com/spring-projects/spring-boot/wiki/Spring-Boot-4.0-Migration-Guide (Undertow entfernt, Kotlin 2.2+), since: 4.0]
- `spring-boot-4/A04` — **Modularisierte Artefakte + umbenannte Starter (since 4.0).** Schema: Module `spring-boot-<tech>`, Packages `org.springframework.boot.<tech>`, Starter `spring-boot-starter-<tech>`. Umbenannt: `spring-boot-starter-web` → `spring-boot-starter-webmvc`, `…-web-services` → `…-webservices`, `…-oauth2-*` → `spring-boot-starter-security-oauth2-*`. Neu **explizit erforderlich**: `spring-boot-starter-flyway` / `spring-boot-starter-liquibase` (früher reichte die 3rd-Party-Dependency). [src: https://github.com/spring-projects/spring-boot/wiki/Spring-Boot-4.0-Migration-Guide, since: 4.0]
- `spring-boot-4/A05` — **Jackson 3 als bevorzugte JSON-Library (since 4.0).** Neue Group-ID `tools.jackson`, neue Package-Namen, Klassen-Renames. **Ausnahme:** das Modul `jackson-annotations` behält Group-ID `com.fasterxml.jackson.core` und Package `com.fasterxml.jackson.annotation` (NICHT migrieren). Annotation-Renames: `@JsonComponent` → `@JacksonComponent`, `@JsonMixin` → `@JacksonMixin`; `JsonObjectSerializer` → `ObjectValueSerializer`. Jackson-2-Kompatibilität nur noch über `spring-boot-jackson2` (deprecated). [src: https://github.com/spring-projects/spring-boot/wiki/Spring-Boot-4.0-Migration-Guide, since: 4.0]
- `spring-boot-4/A06` — **3.x-Deprecations entfernt + API-Relocations (Breaking, since 4.0).** Alle in 3.x deprecateten Klassen/Methoden/Properties sind entfernt. Test: `@MockBean`/`@SpyBean` entfernt → `@MockitoBean`/`@MockitoSpyBean`. Package-Moves: `BootstrapRegistry` → `org.springframework.boot.bootstrap`, `EnvironmentPostProcessor` → `org.springframework.boot`. `PropertyMapper.alwaysApplyingWhenNonNull()` entfernt → `always()`. Spock-Integration entfernt (Groovy-5-Inkompatibilität). [src: https://github.com/spring-projects/spring-boot/wiki/Spring-Boot-4.0-Migration-Guide, since: 4.0]
- `spring-boot-4/A07` — **Config-Property-Renames + geänderte Test-Auto-Config (since 4.0).** Properties umbenannt/entfernt (z.B. `spring.data.mongodb` → `spring.mongodb` für Non-Spring-Data, `spring.session.redis` → `spring.session.data.redis`, Jackson unter `spring.jackson.json.read|write`); `spring-boot-properties-migrator` als Laufzeit-Hilfe. **MockMvc wird nicht mehr automatisch von `@SpringBootTest` bereitgestellt** → `@AutoConfigureMockMvc` explizit; `TestRestTemplate` braucht `@AutoConfigureTestRestTemplate`, für den Umstieg auf das neue `RestTestClient` (Ersatz für `TestRestTemplate`) `@AutoConfigureRestTestClient`. Liveness/Readiness-Probes default aktiv; DevTools-LiveReload default aus. [src: https://github.com/spring-projects/spring-boot/wiki/Spring-Boot-4.0-Migration-Guide, since: 4.0]
- `spring-boot-4/A08` — **Neue stabile Capabilities (since 4.0).** Portfolio-weite **JSpecify-Null-Safety**; native **API-Versionierung** für REST-Endpoints (geordnete API-Evolution); ausgebaute **deklarative HTTP Service Clients** (weniger Boilerplate für REST-Konsumenten); vollständig **modularisierte Jars** (kleinere, fokussierte Artefakte). [src: https://spring.io/blog/2025/11/20/spring-boot-4-0-0-available-now, since: 4.0]
- `spring-boot-4/A09` — **Nativer gRPC-Support via dedizierte Starter (since 4.1).** SB 4.1.0 integriert gRPC nativ: `spring-boot-starter-grpc-server` (Netty-backed + Servlet/HTTP2) und `spring-boot-starter-grpc-client` (`@ImportGrpcClients`-Annotation). Proto-Dateien unter `src/main/proto/`; Build via `com.google.protobuf`-Plugin. Test-Unterstützung: `spring-boot-starter-grpc-server-test` / `spring-boot-starter-grpc-client-test`. Kein Drittanbieter-Starter mehr nötig. Observability (Micrometer), SSL-Bundles und Spring Security werden auto-konfiguriert. [src: https://docs.spring.io/spring-boot/reference/io/grpc.html · https://github.com/spring-projects/spring-boot/wiki/Spring-Boot-4.1-Release-Notes, since: 4.1]
- `spring-boot-4/A10` — **4.1 Breaking Changes: Maven-AOT-Skip, Derby-Removal, Layertools-Removal; Spock-Restore (since 4.1).** (a) **Maven:** `-DskipTests` überspringt AOT-Processing **nicht mehr** — stattdessen `mvn ... -Dmaven.test.skip=true` verwenden. (b) **Derby deprecated/entfernt:** `DatabaseDriver.DERBY` + `EmbeddedDatabaseConnection.DERBY` deprecated; Migration zu H2 oder HSQLDB. (c) **Layertools JAR-Modus entfernt** (war in 4.0 deprecated) → auf `tools`-Jar-Modus wechseln. (d) **Spock wiederhergestellt** (in 4.0 wegen Groovy-5-Inkompatibilität entfernt, in 4.1 mit Spock 2.4 + Groovy 5 zurück — A06-Hinweis nur für reine 4.0-Nutzer relevant). [src: https://github.com/spring-projects/spring-boot/wiki/Spring-Boot-4.1-Release-Notes, since: 4.1]
- `spring-boot-4/A11` — **SSRF-Mitigation via `InetAddressFilter` (since 4.1).** Neuer stabiler Schutzmechanismus für beide HTTP-Client-Typen (reaktiv + blockierend): `InetAddressFilter` blockiert ausgehende Requests an konfigurierte Adressen (z.B. interne Metadaten-Endpoints). Konfigurierbar via `spring.http.clients.cookie-handling` (Cookie-Verhalten) bzw. programmatisch per `withCookieHandling()`-Methode auf `TestRestTemplate`/`RestTemplateBuilder`. Aktivierung empfohlen bei Anwendungen, die URLs aus User-Input verarbeiten. [src: https://github.com/spring-projects/spring-boot/wiki/Spring-Boot-4.1-Release-Notes, since: 4.1]

## B. Anti-Patterns aus Einsatz

> Felderfahrung (`retro`-Land). Schreibt: `agent-flow:retro` ab ≥2 Projekten × ≥2 Stellen (siehe `docs/architecture/framework-build-subsystem.md` §9 Schutzgitter). Stand initial: leer — füllt sich, wenn Projekte real damit arbeiten.

_(noch keine Einträge; siehe Schutzgitter in der Spec)_

## C. Konventionen (Floor)

> Stabile Konventionen, manuell gepflegt (User-Approval Pflicht für Edits durch `train`/`retro`). Major-übergreifend stabil (galten schon in 3.x).

- `spring-boot-4/C01` — **Constructor-Injection statt Field-Injection.** `@Autowired` auf privaten Feldern erschwert Tests (kein Mock-Override ohne Reflection), versteckt Pflicht-Dependencies (kein Compile-Check), verhindert `final`. Stattdessen: alle Dependencies im Konstruktor, Felder `private final`, ein einziger Konstruktor (Spring wählt ihn automatisch, kein `@Autowired` nötig).
- `spring-boot-4/C02` — **`@Transactional` auf Methoden, nicht auf Klassen.** Klassen-Level macht jede public Method transaktional — auch unbeabsichtigte. Methoden-Level ist explizit und review-bar. Ausnahme: dedizierte Services mit explizitem Code-Kommentar.
- `spring-boot-4/C03` — **Profile-Aktivierung via `spring.profiles.active`-Env, nicht im Code.** `SpringApplication.setAdditionalProfiles()` verhindert Operations-Override (kein 12-Factor). Profile per Env (`SPRING_PROFILES_ACTIVE=prod`).

## Coder-Guidance

- Lies das Pack-Frontmatter (`framework_version_range`) — Ziel ist Spring Boot 4.x auf Spring Framework 7.
- **Keine `javax.*`-Imports** (Jakarta EE 11, A03); **kein Undertow** (A03).
- **Starter-Namen für 4.x** verwenden (A04): `spring-boot-starter-webmvc` (nicht `-web`), `-webservices`, `spring-boot-starter-security-oauth2-*`; für Flyway/Liquibase die expliziten `spring-boot-starter-flyway`/`-liquibase`.
- **Jackson 3** (A05): neue `tools.jackson`-Group, `@JacksonComponent`/`@JacksonMixin` statt `@JsonComponent`/`@JsonMixin`. Jackson-2-Kompat nur als bewusster, dokumentierter Übergang via `spring-boot-jackson2`.
- **Tests:** `@MockitoBean`/`@MockitoSpyBean` statt `@MockBean`/`@SpyBean` (A06); MockMvc explizit via `@AutoConfigureMockMvc` (A07).
- **DI:** Constructor-Injection (C01); kein `@Autowired` auf Field.
- **Neues Idiom (A08):** deklarative HTTP Service Clients statt manuellem `RestClient`/`RestTemplate`-Boilerplate; API-Versionierung für öffentliche REST-Endpoints; JSpecify-Nullness-Annotationen ernst nehmen.
- **Java 17+ (25 empfohlen, A01):** bei Java 21+ Virtual Threads via `spring.threads.virtual.enabled=true` für I/O-gebundene Endpoints.
- **gRPC (A09, seit 4.1):** Native Starters `spring-boot-starter-grpc-server`/`-client` — kein Drittanbieter-Starter nötig.
- **Maven AOT (A10, seit 4.1):** `-DskipTests` überspringt AOT nicht mehr — `mvn ... -Dmaven.test.skip=true` für Build ohne Tests+AOT.
- **SSRF (A11, seit 4.1):** `InetAddressFilter` konfigurieren bei Anwendungen, die externe URLs aus User-Input auflösen.

## Reviewer-Checklist

- `javax.*`-Import in 4.x-Code → **Critical** (A03, Jakarta EE 11).
- Undertow-Dependency / `spring-boot-starter-undertow` → **Critical** (A03, nicht mehr unterstützt).
- Alte Starter-Namen (`spring-boot-starter-web`, `…-web-services`, `…-oauth2-*`) → **Important** (A04, umbenannt).
- Flyway/Liquibase ohne expliziten `spring-boot-starter-flyway`/`-liquibase` → **Important** (A04).
- `@MockBean`/`@SpyBean` in Tests → **Critical** (A06, entfernt — kompiliert nicht).
- Jackson-2-Annotationen (`@JsonComponent`/`@JsonMixin`) oder `com.fasterxml.jackson`-Group ohne `spring-boot-jackson2`-Begründung → **Important** (A05, Jackson 3 ist Default). **Ausnahme:** `com.fasterxml.jackson.annotation` (aus `jackson-annotations`) bleibt in SB4 korrekt — kein Befund.
- Nutzung in 3.x deprecateter & in 4.0 entfernter APIs (`alwaysApplyingWhenNonNull()`, alte `BootstrapRegistry`/`EnvironmentPostProcessor`-Packages) → **Critical** (A06).
- `@SpringBootTest` erwartet MockMvc ohne `@AutoConfigureMockMvc` → **Important** (A07).
- `@Autowired` auf privatem Feld → **Important** (C01).
- `@Transactional` auf Klassen-Level ohne Begründungs-Kommentar → **Important** (C02).
- `SpringApplication.setAdditionalProfiles()` im Production-Code → **Important** (C03).
- JDK-Mindestversion (17+) / Spring-Framework-7 nicht in `pom.xml`/`build.gradle` deklariert → **Important** (A01/A02).
- Manueller HTTP-Boilerplate statt deklarativem HTTP Service Client bei neuen REST-Konsumenten → **Suggestion** (A08).
- gRPC via Drittanbieter-Starter (yidongnan, LogNet, grpc-ecosystem) statt nativen SB-4.1-Startern bei SB 4.1+ → **Important** (A09, native Starters bevorzugen).
- `mvn ... -DskipTests` in CI/CD-Skripten (bricht AOT-Processing ab 4.1) → **Important** (A10, auf `-Dmaven.test.skip=true` migrieren).
- Derby als EmbeddedDatabase in Tests (`EmbeddedDatabaseConnection.DERBY`) → **Important** (A10, deprecated in 4.1; H2 oder HSQLDB verwenden).
- Anwendung verarbeitet externe URLs aus User-Input ohne `InetAddressFilter` → **Important** (A11, SSRF-Risiko).

## Test-Approach

- Build via Maven (`mvn -B -ntp verify`, ≥3.6.3) oder Gradle (`./gradlew build --no-daemon`, ≥8.14) — siehe `knowledge/build/<build>.md`. **Ab 4.1:** `-DskipTests` überspringt AOT nicht mehr — bei Bedarf `-Dmaven.test.skip=true` (A10).
- Integration-Tests mit `@SpringBootTest` **+ explizit** `@AutoConfigureMockMvc` (A07 — MockMvc nicht mehr implizit) für Controller-Layer.
- Test-Doubles via `@MockitoBean`/`@MockitoSpyBean` (A06).
- Slice-Tests (`@WebMvcTest`, `@DataJpaTest`) für schnellere Feedback-Loops.
- TestContainers für DB-Integration (Postgres/MySQL/Mongo) — kein H2-In-Memory für DB-Verhalten-Tests.
- **Upgrade-Smoke (3→4):** nach Migration Build grün; `spring-boot-properties-migrator` temporär einbinden, um umbenannte/entfernte Config-Properties zur Laufzeit zu erkennen, dann wieder entfernen.
