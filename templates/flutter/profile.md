# Projekt-Profil (Vorlage: flutter) — new-project füllt <…> aus
language: flutter
domains: []
frameworks: []                          # optional Array — siehe docs/architecture/framework-build-subsystem.md §3
build: flutter build web --release      # Freitext (Backwards-Compat) — flutter hat keinen kanonischen Build-Pack (Build = Sprach-Toolchain)
test: flutter test
lint: flutter analyze
smoke: "curl -fsS -o /dev/null -w '%{http_code}' http://localhost:8080/"
merge_policy: pr
default_branch: main                    # Base für PR/direct-Push/CI-Watch. /adopt überschreibt ihn beim Fork-Import mit dem echten Default (oft master); flow leitet ihn sonst zur Laufzeit via `gh repo view` ab.
board: <PROJECT_NUMMER>
deploy: docker
image: ghcr.io/studis-softwareschmiede/<name>
registry: ghcr
