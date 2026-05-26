# Projekt-Profil (Vorlage: html) — new-project füllt <…> aus
language: html
domains: [css]
build: "true"          # statisch, kein Build
test: "true"           # Smoke = Seite lädt
lint: "true"
smoke: "curl -fsS -o /dev/null -w '%{http_code}' http://localhost:8080/"
merge_policy: pr
board: <PROJECT_NUMMER>
deploy: docker
image: ghcr.io/studis-softwareschmiede/<name>
registry: ghcr
container_port: 80    # Port im Container (nginx); /preview mappt host:container
# preview_port: <wird von /preview up vergeben (erste freie ab 8080) und hier eingetragen>
