# Projekt-Profil (Vorlage: flutter) — new-project füllt <…> aus
language: flutter
domains: []
build: flutter build web --release
test: flutter test
lint: flutter analyze
smoke: "curl -fsS -o /dev/null -w '%{http_code}' http://localhost:8080/"
merge_policy: pr
board: <PROJECT_NUMMER>
deploy: docker
image: ghcr.io/studis-softwareschmiede/<name>
registry: ghcr
