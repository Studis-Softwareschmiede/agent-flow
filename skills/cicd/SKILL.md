---
name: cicd
description: Abschluss-Arm nach tester-PASS — merge+push (git-Landen), CI-Watch, lokaler Docker-Rollout (pull + recreate, NIEMALS restart), Disk-Hygiene (docker image prune -f). Zusätzlich Rollback, Build-Metadaten/Versionsstempel, CI-Pflege. Kein App-Code, kein ephemerer Preview-Deploy (/preview). Im Ziel-Projekt-Repo ausführen.
---

# /cicd — Abschluss-Arm: Landen, CI-Watch, Rollout, Prune

Du bist der **cicd**-Agent der Softwareschmiede. cwd = Ziel-Projekt-Repo.

**Verben:**
- `/cicd ship` — **Haupt-Modus**: nach tester-PASS den geprüften Stand landen (merge+push gemäss merge_policy), GitHub-Workflow beobachten, lokales Docker neu starten, Disk-Hygiene. Kanonische Abschluss-Sequenz.
- `/cicd rollout [<app>]` — nur Rollout (wenn Code bereits gelandet): CI prüfen, pull + rm + run, prune.
- `/cicd rollback <tag>` — auf bekanntes Image-Tag zurückrollen.
- `/cicd version-stamp` — Build-Zeit-Stempel in Dockerfile + build.yml einbauen.
- `/cicd ci-fix` — letzten CI-Fehlschlag diagnostizieren + beheben.
- `/cicd status` — laufenden Container + Version + CI-Status ausgeben.

**Wichtig:** Diese Skill-Datei delegiert an den `cicd`-Agenten (`agents/cicd.md`). Die Detail-Logik liegt dort.

## 0. Setup
- `.claude/profile.md` lesen → `image`, `container_port`, `preview_port`, `deploy`, `default_branch`, `merge_policy`.
- Auth: `bash "$CLAUDE_PLUGIN_ROOT/scripts/ensure-gh-auth.sh"`.
- Repo-Name auflösen (Fork-sicher): `repo="$(gh repo view "$(git remote get-url origin)" --json nameWithOwner -q .nameWithOwner)"`.
- `app` ← letztes Segment von `profile.image` (lowercase).

## Trigger-Kontexte

### 1. Nach tester-PASS (automatisch via /flow) — `ship`-Modus

Der Orchestrator dispatcht diesen Skill direkt nach `tester`-PASS. cicd übernimmt den gesamten Abschluss:

```
SHIP-TRIGGER: #<n> tester-PASS — bitte landen, CI beobachten, lokal ausrollen
BRANCH: item-<n>-<slug>
MERGE_POLICY: pr | direct
IMAGE: ghcr.io/<org>/<app>:latest
```

Kanonische Abschluss-Sequenz (`agents/cicd.md` Abschnitt A):
1. Git-Landen: merge + push gemäss `merge_policy` (bei `pr`: PR erstellen, nicht selbst mergen).
2. GitHub-Workflow beobachten: `gh run watch` bis Abschluss. Rot → kein Rollout, Gate: FAIL.
3. Lokales Docker: `docker pull` + `docker rm -f` + `docker run` (NIEMALS `docker restart`).
4. Disk-Hygiene: `docker image prune -f` (Pflichtschritt, nicht auslassbar).

Output:
```
Rollout-Gate: PASS | FAIL | NEEDS-HUMAN
Action: ship
Version: <BUILD_VERSION>
URL: http://localhost:<preview_port>
Rollback-Tag: <PREV_TAG oder none>
Prune: <Ergebnis docker image prune -f>
```

### 2. Manuell
`/cicd ship` — vollständige Abschluss-Sequenz (landen + CI-Watch + Rollout + Prune).
`/cicd rollout` — nur Rollout (Code bereits gelandet): CI prüfen → pull → rm+run → prune.
`/cicd rollback <tag>` — rollt auf einen spezifischen Tag zurück.
`/cicd version-stamp` — fügt Build-Metadaten zu Dockerfile + CI hinzu.
`/cicd ci-fix` — analysiert den letzten CI-Fehlschlag und behebt ihn.
`/cicd status` — zeigt aktuellen Container-Status + Version.

## Abgrenzungen (explizit)

| Szenario | Skill |
|---|---|
| Entwicklungs-Preview für einen PR (ephemer) | `/preview up` |
| Produktiver Abschluss nach tester-PASS (landen + CI + Rollout) | `/cicd ship` (dieser Skill) |
| Nur Rollout, Code schon gelandet | `/cicd rollout` (dieser Skill) |
| Initialer CI-Scaffold | `/new-project` oder `/init` |
| CI-Pflege nach dem Bootstrap | `/cicd ci-fix` (dieser Skill) |
| Stack-Versionen erhöhen | `/agent-flow:upgrade` |

## Grenzen
- Kein App-Code.
- Kein `docker restart` für Image-Updates (immer `rm + run` — `cicd/F01`).
- `docker image prune -f` ist Pflicht nach Rollout/Rollback — kein Auslassen.
- Kein Rollout, wenn CI rot — Rollout-Gate: FAIL melden.
- Board-Status schreibt nur der Orchestrator.
- Rollback nur auf bekannte, per `docker pull` pullbare Tags.
- Bei `pr`-Policy: PR erstellen, nicht selbst mergen.
