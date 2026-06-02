# Projekt-Profil (Vorlage: js) — new-project füllt <…> aus
language: js
domains: []
frameworks: []          # optional Array, z.B. ["react@18"] — siehe docs/architecture/framework-build-subsystem.md §3
build: "npm ci"         # Freitext (Backwards-Compat) ODER kanonisch: npm | pnpm | uv | maven | gradle | cargo | none — kanonisch aktiviert build-Pack-Loader
test: "npm test"
lint: "npm run lint"
smoke: "curl -fsS -o /dev/null -w '%{http_code}' http://localhost:8080/"
merge_policy: pr
default_branch: main    # Base für PR/direct-Push/CI-Watch. /adopt überschreibt ihn beim Fork-Import mit dem echten Default (oft master); flow leitet ihn sonst zur Laufzeit via `gh repo view` ab.
board: <PROJECT_NUMMER>
deploy: docker
image: ghcr.io/studis-softwareschmiede/<name>
registry: ghcr
