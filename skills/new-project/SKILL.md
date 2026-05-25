---
name: new-project
description: Bootstrappt ein Projekt der Softwareschmiede — legt Repo + GitHub-Board an, erkennt/erfragt den Stack, scaffoldet .claude/ (profile, CLAUDE.md, lessons) + Dockerfile + CI aus templates/<lang>. /init adoptiert ein bestehendes Repo. Schreibt KEINEN App-Code.
---

# /new-project <name> [--lang <x>]   ·   /init

Bootstrap, damit die Fabrik an einem Projekt arbeiten kann. cwd = Workspace (`new-project`) bzw. das bestehende Repo (`init`). `GH_TOKEN` muss gesetzt sein.

## Ablauf
1. **Repo**
   - `new-project`: `gh repo create studis-softwareschmiede/<name> --private` + clone.
   - `init`: bestehendes Repo (cwd) nutzen; Remote prüfen.
2. **Stack**
   - `new-project`: aus `--lang` oder genau **1 Frage**.
   - `init`: erkennen — `pubspec.yaml`→flutter · `pom.xml`/`build.gradle`→java · `package.json`→js/angular · `*.html`→html · `*.sql`/`migrations/`→Domäne `sql` — und bestätigen lassen.
3. **Board**: `gh project create` (Org-Ebene), Status-Werte `To Do / In Progress / Blocked / In Review / Done` → Nummer notieren.
4. **`.claude/` scaffolden** (aus `templates/<lang>/`):
   - `profile.md`: `language`, `domains`, `build`/`test`/`lint`/`smoke`, `merge_policy: pr`, `board: <nr>`, `deploy: docker`, `image: ghcr.io/studis-softwareschmiede/<name>`, `registry: ghcr`.
   - `CLAUDE.md`: minimaler Kontext (Template + 1–2 Fragen).
   - `lessons/{coder,reviewer,tester}.md`: leer.
5. **Deploy scaffolden** (aus `templates/<lang>/`):
   - `Dockerfile`.
   - `.github/workflows/build.yml`: on push `main` → Image bauen + Push nach `ghcr.io/studis-softwareschmiede/<name>` via eingebautem `GITHUB_TOKEN` (`permissions: packages: write`).
6. **Branch-Protection** auf `main`: require PR + `reviewer`-Check. (Solo: KEIN Pflicht-Human-Approval — du mergst selbst.)
7. **Initial commit + push.**

## Output
Repo-URL · Board-URL · Profil · Image-Ziel → „bereit für `/requirement`".

## Grenzen
- Kein App-Code.
- `init`: bestehende `.claude/`-Dateien NICHT überschreiben (mergen/fragen) → idempotent.
- Minimal fragen.
