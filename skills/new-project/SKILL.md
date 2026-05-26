---
name: new-project
description: Bootstrappt ein Projekt der Softwareschmiede — legt Repo + GitHub-Board an, erkennt/erfragt den Stack, scaffoldet .claude/ (profile, CLAUDE.md, lessons) + Dockerfile + CI aus ${CLAUDE_PLUGIN_ROOT}/templates/<lang>. /init adoptiert ein bestehendes Repo. Schreibt KEINEN App-Code.
---

# /new-project <name> [--lang <x>]   ·   /init

Bootstrap, damit die Fabrik an einem Projekt arbeiten kann. cwd = Workspace (`new-project`) bzw. das bestehende Repo (`init`).

**Auth ZUERST (sonst scheitert jeder gh-Schritt):** `bash "$CLAUDE_PLUGIN_ROOT/scripts/ensure-gh-auth.sh"` — das mintet den GitHub-App-Token aus `.env.gpg` und loggt `gh` damit ein. **NICHT `gh auth login --web`** (wir nutzen die App, nicht einen interaktiven Login).

## Ablauf
1. **Repo**
   - `new-project`: `gh repo create studis-softwareschmiede/<name> --public` + clone. (Public: Branch-Protection/PR+Gate im Free-Plan möglich; ghcr-Image ohne Pull-Login.)
   - `init`: bestehendes Repo (cwd) nutzen; Remote prüfen.
2. **Stack**
   - `new-project`: aus `--lang` oder genau **1 Frage**.
   - `init`: erkennen — `pubspec.yaml`→flutter · `pom.xml`/`build.gradle`→java · `package.json`→js/angular · `*.html`→html · `*.sql`/`migrations/`→Domäne `sql` — und bestätigen lassen.
3. **Board**: `gh project create` (Org-Ebene), Status-Werte `To Do / In Progress / Blocked / In Review / Done` → Nummer notieren.
4. **`.claude/` scaffolden** (aus `${CLAUDE_PLUGIN_ROOT}/templates/<lang>/`):
   - `profile.md`: `language`, `domains`, `build`/`test`/`lint`/`smoke`, `merge_policy: pr`, `board: <nr>`, `deploy: docker`, `image: ghcr.io/studis-softwareschmiede/<name>`, `registry: ghcr`, `container_port: <EXPOSE aus dem Template-Dockerfile, z.B. 80|8080>` (für `/preview`; `preview_port` wird erst beim ersten `/preview up` vergeben).
   - `CLAUDE.md`: minimaler Kontext (Template + 1–2 Fragen).
   - `lessons/{coder,reviewer,tester}.md`: leer.
5. **Deploy scaffolden** (aus `${CLAUDE_PLUGIN_ROOT}/templates/<lang>/`):
   - `Dockerfile`.
   - `.github/workflows/build.yml`: on push `main` → Image bauen + Push nach `ghcr.io/studis-softwareschmiede/<name>` via eingebautem `GITHUB_TOKEN` (`permissions: packages: write`).
6. **Branch-Protection** auf `main` (optional/best-effort): nur *„require a pull request before merging"* (blockiert Direkt-Push). **KEINE** Pflicht-Status-Checks (`reviewer` ist ein Agent, kein GitHub-Check → würde sonst jeden Merge blockieren) und **KEINE** Pflicht-Approvals (solo kann eigenen PR nicht approven). Lehnt die API ab (Plan/Permissions) → **überspringen, nicht abbrechen**. Das eigentliche Gate ist dein manueller Merge nach Review-PASS + Test-PASS.
7. **Initial commit + push.**

## Output
Repo-URL · Board-URL · Profil · Image-Ziel → „bereit für `/requirement`".

## Grenzen
- Kein App-Code.
- `init`: bestehende `.claude/`-Dateien NICHT überschreiben (mergen/fragen) → idempotent.
- Minimal fragen.
