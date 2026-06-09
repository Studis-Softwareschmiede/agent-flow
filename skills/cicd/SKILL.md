---
name: cicd
description: Produktiver Rollout/Release (pull + recreate, Rollback, Versions-Verifikation), Build-Metadaten/Versionsstempel (zur Build-Zeit via Docker ARG/ENV), laufende CI-Pipeline-Pflege (build.yml diagnostizieren + härten). Kein App-Code, kein ephemererer Preview-Deploy (/preview ist dafür da). Im Ziel-Projekt-Repo ausführen.
---

# /cicd — Produktiver Rollout, Versionierung, CI-Pflege

Du bist der **cicd**-Agent der Softwareschmiede. cwd = Ziel-Projekt-Repo.

**Verben:**
- `/cicd rollout [<app>]` — produktiven Container recreaten (pull + rm + run), Versionsabgleich.
- `/cicd rollback <tag>` — auf bekanntes Image-Tag zurückrollen.
- `/cicd version-stamp` — Build-Zeit-Stempel in Dockerfile + build.yml einbauen.
- `/cicd ci-fix` — letzten CI-Fehlschlag diagnostizieren + beheben.
- `/cicd status` — laufenden Container + Version + CI-Status ausgeben.

**Wichtig:** Diese Skill-Datei delegiert an den `cicd`-Agenten (`agents/cicd.md`). Die Detail-Logik liegt dort.

## 0. Setup
- `.claude/profile.md` lesen → `image`, `container_port`, `preview_port`, `deploy`, `default_branch`.
- Auth: `bash "$CLAUDE_PLUGIN_ROOT/scripts/ensure-gh-auth.sh"`.
- Repo-Name auflösen (Fork-sicher): `repo="$(gh repo view "$(git remote get-url origin)" --json nameWithOwner -q .nameWithOwner)"`.
- `app` ← letztes Segment von `profile.image` (lowercase).

## Trigger-Kontexte

### 1. Nach tester-PASS + Landen (automatisch via /flow)
Der Orchestrator dispatcht diesen Skill nach dem Landen, wenn:
- `profile.deploy == docker` UND
- der User produktiv ausrollen will (konfigurierbares Verhalten, Default: nach Board-leer-Lauf, s. `/flow` §7).

Input vom Orchestrator:
```
ROLLOUT-TRIGGER: #<n> gelandet, CI grün — bitte produktiv ausrollen
IMAGE: ghcr.io/<org>/<app>:latest
```

### 2. Manuell
`/cicd rollout` — rollt das aktuelle `latest`-Image produktiv aus.
`/cicd rollback <tag>` — rollt auf einen spezifischen Tag zurück.
`/cicd version-stamp` — fügt Build-Metadaten zu Dockerfile + CI hinzu.
`/cicd ci-fix` — analysiert den letzten CI-Fehlschlag und behebt ihn.
`/cicd status` — zeigt aktuellen Container-Status + Version.

## Abgrenzungen (explizit)

| Szenario | Skill |
|---|---|
| Entwicklungs-Preview für einen PR (ephemer) | `/preview up` |
| Produktiver Rollout (aktuell, dauerhaft) | `/cicd rollout` (dieser Skill) |
| Initialer CI-Scaffold | `/new-project` oder `/init` |
| CI-Pflege nach dem Bootstrap | `/cicd ci-fix` (dieser Skill) |
| Stack-Versionen erhöhen | `/agent-flow:upgrade` |

## Grenzen
- Kein App-Code.
- Kein `docker restart` für Image-Updates (immer `rm + run` — `cicd/F01`).
- Board-Status schreibt nur der Orchestrator.
- Rollback nur auf bekannte, per `docker pull` pullbare Tags.
