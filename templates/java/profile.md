# Projekt-Profil (Vorlage: java) — new-project füllt <…> aus
language: java
domains: []
frameworks: []                              # optional, z.B. ["spring-boot@3"] — siehe docs/architecture/framework-build-subsystem.md §3
build: "mvn -q -DskipTests package"         # Freitext (Backwards-Compat) ODER kanonisch: maven | gradle — kanonisch aktiviert build-Pack-Loader (knowledge/build/maven.md)
test: "mvn -q test"
lint: "mvn -q -DskipTests verify"
smoke: "curl -fsS -o /dev/null -w '%{http_code}' http://localhost:8080/actuator/health || true"
merge_policy: pr
cost_mode: balanced                         # Token-Hebel je Lauf überschreibbar (/flow --cost …): low-cost | balanced | max-quality — siehe knowledge/model-tiers.md
default_branch: main                        # Base für PR/direct-Push/CI-Watch. /adopt überschreibt ihn beim Fork-Import mit dem echten Default (oft master); flow leitet ihn sonst zur Laufzeit via `gh repo view` ab.
board: <PROJECT_NUMMER>
deploy: docker
image: ghcr.io/studis-softwareschmiede/<name>
registry: ghcr
container_runtime: none                      # optional (JVM/Servlet-Stacks): tomcat | jetty | undertow | none — von /adopt aus Deps gesetzt; vom /upgrade-Solver für Runtime-Ausschlüsse genutzt (z.B. Servlet 6.1 ⇒ kein undertow). Spec: docs/architecture/upgrade-subsystem.md §13
# upgrade: { … }                             # transienter /upgrade-Fortschrittsblock (run_id/targets/status/timeout_hours) — wird zur Laufzeit gesetzt, nicht scaffolden. Spec §13

# Static Analysis (optional — siehe knowledge/quality/sonar.md). edition: none|sonarcloud|sonarqube-ce
# Auto-Wahl: public-Repo -> sonarcloud · private-Repo -> sonarqube-ce oder none.
# Token NIE hier — als GitHub-Org-Secret SONAR_TOKEN. Kein Setup -> edition: none (nichts bricht).
sonar:
  edition: none
  organization: ""        # SonarCloud-Org (nur sonarcloud)
  project_key: ""         # z.B. <Org>_<repo>
  host_url: ""            # sonarcloud: https://sonarcloud.io · ce: https://<instanz>
