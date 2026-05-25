# Projekt-Profil (Vorlage: js) — new-project füllt <…> aus
language: js
domains: []
build: "npm ci"
test: "npm test"
lint: "npm run lint"
smoke: "curl -fsS -o /dev/null -w '%{http_code}' http://localhost:8080/"
merge_policy: pr
board: <PROJECT_NUMMER>
deploy: docker
image: ghcr.io/studis-softwareschmiede/<name>
registry: ghcr
