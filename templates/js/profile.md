# Projekt-Profil (Vorlage: js) — new-project füllt <…> aus
language: js
domains: []
frameworks: []          # optional Array, z.B. ["react@18"] — siehe docs/architecture/framework-build-subsystem.md §3
build: "npm ci"         # Freitext (Backwards-Compat) ODER kanonisch: npm | pnpm | uv | maven | gradle | cargo | none — kanonisch aktiviert build-Pack-Loader
test: "npm test"
lint: "npm run lint"
smoke: "curl -fsS -o /dev/null -w '%{http_code}' http://localhost:8080/"
merge_policy: pr
cost_mode: balanced     # Token-Hebel je Lauf überschreibbar (/flow --cost …): low-cost | balanced | max-quality — siehe knowledge/model-tiers.md
default_branch: main    # Base für PR/direct-Push/CI-Watch. /adopt überschreibt ihn beim Fork-Import mit dem echten Default (oft master); flow leitet ihn sonst zur Laufzeit via `gh repo view` ab.
board: file
# obsidian_source: <absoluter-ordnerpfad>  # optional/additiv — verknüpfter Obsidian-Notiz-Ordner für /agent-flow:from-notes. Precedence: Ordner-Argument > dieses Feld; fehlt beides -> Abbruch. Siehe docs/specs/obsidian-ingest.md AC1-AC3.
deploy: docker
image: ghcr.io/studis-softwareschmiede/<name>
registry: ghcr

# Static Analysis (optional — siehe knowledge/quality/sonar.md). edition: none|sonarcloud|sonarqube-ce
# Auto-Wahl: public-Repo -> sonarcloud · private-Repo -> sonarqube-ce oder none.
# Token NIE hier — als GitHub-Org-Secret SONAR_TOKEN. Kein Setup -> edition: none (nichts bricht).
sonar:
  edition: none
  organization: ""        # SonarCloud-Org (nur sonarcloud)
  project_key: ""         # z.B. <Org>_<repo>
  host_url: ""            # sonarcloud: https://sonarcloud.io · ce: https://<instanz>
