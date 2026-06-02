# Projekt-Profil (Vorlage: java) — new-project füllt <…> aus
language: java
domains: []
frameworks: []                              # optional, z.B. ["spring-boot@3"] — siehe docs/architecture/framework-build-subsystem.md §3
build: "mvn -q -DskipTests package"         # Freitext (Backwards-Compat) ODER kanonisch: maven | gradle — kanonisch aktiviert build-Pack-Loader (knowledge/build/maven.md)
test: "mvn -q test"
lint: "mvn -q -DskipTests verify"
smoke: "curl -fsS -o /dev/null -w '%{http_code}' http://localhost:8080/actuator/health || true"
merge_policy: pr
default_branch: main                        # Base für PR/direct-Push/CI-Watch. /adopt überschreibt ihn beim Fork-Import mit dem echten Default (oft master); flow leitet ihn sonst zur Laufzeit via `gh repo view` ab.
board: <PROJECT_NUMMER>
deploy: docker
image: ghcr.io/studis-softwareschmiede/<name>
registry: ghcr
