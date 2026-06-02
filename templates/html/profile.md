# Projekt-Profil (Vorlage: html) — new-project füllt <…> aus
language: html
domains: [css]
frameworks: []          # statische Seite — keine Frameworks; siehe docs/architecture/framework-build-subsystem.md §3
build: "true"          # statisch, kein Build (kanonisch wäre: none)
test: "true"           # Smoke = Seite lädt
lint: "true"
smoke: "curl -fsS -o /dev/null -w '%{http_code}' http://localhost:8080/"
merge_policy: pr
default_branch: main    # Base für PR/direct-Push/CI-Watch. /adopt überschreibt ihn beim Fork-Import mit dem echten Default (oft master); flow leitet ihn sonst zur Laufzeit via `gh repo view` ab.
board: <PROJECT_NUMMER>
deploy: docker
image: ghcr.io/studis-softwareschmiede/<name>
registry: ghcr
container_port: 80    # Port im Container (nginx); /preview mappt host:container
# preview_port: <wird von /preview up vergeben (erste freie ab 8080) und hier eingetragen>
