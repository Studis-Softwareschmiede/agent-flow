# Projekt-Profil (Vorlage: angular) — new-project füllt <…> aus
language: angular
domains: [css, tailwind]
frameworks: ["angular@<major>"]   # via /adopt aus package.json gesetzt; siehe docs/architecture/framework-build-subsystem.md §3
build: npm run build              # Freitext (Backwards-Compat) ODER kanonisch: npm | pnpm | uv | maven | gradle | cargo | none
test: "npm test -- --watch=false --browsers=ChromeHeadless"
lint: npm run lint
smoke: "curl -fsS -o /dev/null -w '%{http_code}' http://localhost:8080/"
merge_policy: pr
board: <PROJECT_NUMMER>
deploy: docker
image: ghcr.io/studis-softwareschmiede/<name>
registry: ghcr
