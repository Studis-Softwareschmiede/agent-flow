---
pack: build/maven
pack_version: 1.0
pack_date: 2026-06-15
primary_sources:
  - https://maven.apache.org/guides/
  - https://maven.apache.org/plugins/
  - https://maven.apache.org/docs/history.html
non_sources:
  - baeldung.com
  - dev.to
  - medium.com
  - stackoverflow.com
---

# Knowledge Pack: maven

Apache Maven (Build-Tool, primär Java/Kotlin/Scala). Geladen bei `profile.build: maven`. Regel-IDs: `maven/A<NN>` · `maven/B<NN>` · `maven/C<NN>`.

## A. Stable API & Deprecations

> Quellen-getrieben (`train`-Land).

- `maven/A01` — **`-ntp` (`--no-transfer-progress`, since 3.6.1)** unterdrückt das Download-Progress-Spam in CI/Logs. Standardflag im Smoke-Befehl `mvn -B -ntp verify`. [src: https://maven.apache.org/docs/3.6.1/release-notes.html, since: 3.6.1]
- `maven/A02` — **`-B` (`--batch-mode`)** unterdrückt interaktive Prompts und ANSI-Farben — Pflicht für CI/Smoke. Kombination `-B -ntp` ist die kanonische CI-Form.
- `maven/A03` — **Reproducible-Builds via `project.build.outputTimestamp` (since 3.6.3).** Setzt deterministischen Timestamp in JAR-Manifest und ZIP-Entries — Voraussetzung für SOURCE_DATE_EPOCH-konforme Reproducible-Builds. [src: https://maven.apache.org/guides/mini/guide-reproducible-builds.html, since: 3.6.3]
- `maven/A04` — **`<maven.compiler.release>` (statt `source`+`target`-Paar) seit `maven-compiler-plugin` 3.6.** `release` aktiviert `--release N` (JDK 9+), was auch Cross-Compile-API-Checks erzwingt — accidental API-Usage jenseits des Targets wird Compile-Fehler. Ab `maven-compiler-plugin` 3.13.0 ist `release` auch auf JDK 8 nutzbar (Plugin wandelt automatisch auf `source`/`target`-Äquivalent um, kein bedingtes Profil nötig). `source`/`target` allein bietet diesen Schutz nicht. [src: https://maven.apache.org/plugins/maven-compiler-plugin/examples/set-compiler-release.html, since: maven-compiler-plugin 3.13.0 (Uniform-JDK8-Support)]
- `maven/A05` — **CI-friendly Versions (`${revision}`) seit Maven 3.5.0: in Maven 3.x `flatten-maven-plugin` mit `resolveCiFriendliesOnly` Pflicht bei `install`/`deploy`.** Ohne das Plugin enthält das ins Repository geschriebene POM wörtlich `${revision}` statt der aufgelösten Version — Konsumenten können das Artefakt nicht auflösen. Maven 4 (POM-Modell 4.1.0) eliminiert diesen Bedarf nativ. [src: https://maven.apache.org/guides/mini/guide-maven-ci-friendly.html, since: 3.5.0]
- `maven/A06` — **`requirePluginVersions`-Regel im Maven Enforcer Plugin** (`maven-enforcer-plugin` ≥ 1.0) fängt unpinnte Plugins (`LATEST`, `RELEASE`, Snapshots, Default-Super-POM-Versionen) im Build ab — Reviewer-Checklist-Befund „Plugin-Version ungepinnt" kann damit automatisiert werden. Standard-Konfiguration prüft `clean`-, `deploy`- und `site`-Phasen. [src: https://maven.apache.org/enforcer/enforcer-rules/requirePluginVersions.html]

## B. Anti-Patterns aus Einsatz

> Felderfahrung (`retro`-Land). Schreibt: `agent-flow:retro` ab ≥2 Projekten × ≥2 Stellen (siehe `docs/architecture/framework-build-subsystem.md` §9 Schutzgitter). Stand initial: leer — füllt sich, wenn Projekte real damit arbeiten.

_(noch keine Einträge; siehe Schutzgitter in der Spec)_

## C. Konventionen (Floor)

> Stabile Konventionen, manuell gepflegt (User-Approval Pflicht für Edits durch `train`/`retro`).

- `maven/C01` — **Maven-Wrapper (`mvnw`) ins Repo committen.** `mvn:wrapper`-Plugin generiert `mvnw`/`mvnw.cmd` + `.mvn/wrapper/`-Konfiguration. CI und neue Entwickler nutzen den exakt gepinnten Maven, kein Globaler-Maven-Mismatch.
- `maven/C02` — **`dependencyManagement` in Parent-POM bei Multi-Module.** Versionen genau einmal definieren, Sub-Module nur `<dependency>` ohne `<version>`. Verhindert Versions-Drift zwischen Modulen.
- `maven/C03` — **`spring-boot-starter-parent` ODER `dependencyManagement`-Import** für Spring-Boot-Projekte, nicht beides. Wenn der Parent-POM des Projekts schon einen anderen `<parent>` braucht: `spring-boot-dependencies`-BOM via `<scope>import</scope>` ins `dependencyManagement` aufnehmen.
- `maven/C04` — **Keine Snapshot-Dependencies in Release-Builds.** `*-SNAPSHOT`-Refs in `pom.xml` machen den Build nicht-reproduzierbar. CI-Gate: `mvn enforcer:enforce` mit `requireReleaseDeps` Regel.

## Coder-Guidance

- Setze `<maven.compiler.release>` (NICHT nur `source`/`target`) — verhindert versehentliche JDK-API-Nutzung neuer als das Target.
- Multi-Module: gemeinsame Versionen in Parent-POM `dependencyManagement`, niemals doppelt in Sub-Modulen (C02).
- Reproducible-Builds: `project.build.outputTimestamp` setzen (A03).

## Reviewer-Checklist

- `mvnw`/`mvnw.cmd` fehlen → **Important** (C01, Reproducibility).
- Sub-Modul listet `<version>` für eine Library, die schon in Parent `dependencyManagement` steht → **Important** (C02, Drift-Risiko).
- `*-SNAPSHOT`-Dep in `pom.xml` eines Release-Branches → **Critical** (C04).
- Plugin-Version ungepinnt (`<plugin>` ohne `<version>`) → **Important** (Build-Reproducibility).
- `mvn`-Befehl in CI/Smoke-Skripts ohne `-B -ntp` → **Suggestion** (A01/A02).

## Test-Approach

- Smoke-Befehl (kanonisch, siehe `agents/tester.md` Build-Tool-Dispatch): `mvn -B -ntp verify`.
- `verify` ruft `test` (Unit) + `integration-test` (Failsafe-Plugin) — vollständige Build-Lifecycle-Validierung.
- Für nur-Unit-Smoke: `mvn -B -ntp test` (schneller, kein Packaging).
- Mit Test-Profilen (z.B. `-Pintegration-tests`): erweitert den Befehl additiv, ersetzt ihn nicht (siehe tester.md Pack-Erweiterungs-Regel).
