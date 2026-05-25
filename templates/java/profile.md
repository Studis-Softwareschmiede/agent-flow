# Projekt-Profil (Vorlage: java) — new-project füllt <…> aus
language: java
domains: []
build: "mvn -q -DskipTests package"
test: "mvn -q test"
lint: "mvn -q -DskipTests verify"
smoke: "curl -fsS -o /dev/null -w '%{http_code}' http://localhost:8080/actuator/health || true"
merge_policy: pr
board: <PROJECT_NUMMER>
deploy: docker
image: ghcr.io/studis-softwareschmiede/<name>
registry: ghcr
