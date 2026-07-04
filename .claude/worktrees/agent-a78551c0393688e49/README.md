# agent-flow — die Softwareschmiede

Wiederverwendbares, selbst-verbesserndes **Coder→Reviewer→Tester-Framework** als Claude-Code-Plugin
(Repo-first). Auf beliebige Projekte beliebiger Sprache ansetzbar. Org: `Studis-Softwareschmiede`.

---

## Install

**1. Plugin installieren** (in Claude Code):

```
/plugin marketplace add Studis-Softwareschmiede/agent-flow
/plugin install agent-flow@agent-flow
/reload-plugins
```

Update später: `/plugin` → *agent-flow* → Update → `/reload-plugins`.

**2. GitHub-Auth einmalig pro Maschine** (die Skills minten den App-Token aus `.env.gpg` via
`scripts/ensure-gh-auth.sh` — kein interaktiver `gh auth login` nötig):

```bash
mkdir -p ~/.config/softwareschmiede && chmod 700 ~/.config/softwareschmiede
# GPG-Passphrase (Bitwarden: studis-softwareschmiede-gpg-passphrase) seeden:
printf '%s' '<passphrase>' > ~/.config/softwareschmiede/gpg.pass
chmod 600 ~/.config/softwareschmiede/gpg.pass
```

Danach stellt jeder Skill seine Auth selbst her. Org-Secret `SONAR_TOKEN` (für optionale Sonar-Analyse)
liegt org-weit in GitHub — nichts lokal zu tun.

> **Namespacing:** Jeder Command ist als `/agent-flow:<name>` aufrufbar. Der bare Kurzname funktioniert
> meist auch — **außer `upgrade`** (`/upgrade` ist ein CLI-Built-in → hier ist `/agent-flow:upgrade` Pflicht).

---

## Commands

Legende „Wo": **Workspace** = beliebiger Ordner · **Repo** = im Ziel-Projekt-Repo ausführen.

### `new-project` / `init` — Projekt bootstrappen · Wo: Workspace (`init`: Repo)
Legt Repo + Board + `.claude/`-/`docs/`-Scaffold + Dockerfile + CI an. Schreibt **keinen** App-Code.
```
/agent-flow:new-project <name> [--lang <x>] [--db <dialect>] [--companions <list>] \
                        [--build <tool>] [--framework <id>@<major>]… [--migration-tool <tool>]
/agent-flow:init        # bestehendes Repo (cwd) adoptieren — selber Pfad ohne Repo-Anlage
```
| Option | Werte |
|---|---|
| `--lang` | `java`·`ts`·`py`·`rust`·`flutter`·`js`·`angular`·`html` … |
| `--db` | `postgres`·`mysql`·`sqlite`·`mongodb`·`none` |
| `--companions` | `redis` (kommagetrennt) |
| `--build` | `maven`·`gradle`·`npm`·`pnpm`·`uv`·`cargo`·`none` |
| `--framework` | `<id>@<major>`, wiederholbar (z.B. `--framework spring-boot@3`) |
| `--migration-tool` | `flyway@10`·`liquibase@4`·`alembic`·`prisma`·`sqflite`·`skeleton` … |

Ohne Flags fragt der Skill interaktiv (je eine gezielte Frage). Repo entsteht als `studis-softwareschmiede/<name>` (public).

### `adopt` — Bestehendes Repo in die Fabrik holen · Wo: Workspace
Klont (fremde Repos → in die Org **forken**), übernimmt per `init`, auditiert, legt Backlog aufs Board, validiert E2E. Behebt nichts automatisch — danach `flow`.
```
/agent-flow:adopt <owner/repo>     # z.B. /agent-flow:adopt alexstuder/climatedataanalyser
/agent-flow:adopt re-validate      # nur den Validate-Step erneut (cwd = adoptiertes Repo)
```

### `requirement` — Vage Anforderung → Spec + Board-Items · Wo: Repo
Verfeinert per Rückfragen, schreibt durable Specs unter `docs/specs/`, legt referenzierende Items (To Do) an. Kein Code.
```
/agent-flow:requirement <freitext der anforderung>
```

### `flow` — Board abarbeiten (Orchestrator) · Wo: Repo
Arbeitet To-Do-Items Punkt für Punkt ab: coder → reviewer ⇄ Loop → (dba) → tester → landen → Done. Einziger Schreiber von Board-Status & git/PR.
```
/agent-flow:flow                   # ganzes Board nach Priorität/Depends-on
/agent-flow:flow <fokus-freitext>  # gezielt, z.B. "nur #35 und #37, #35 zuerst"
```

### `upgrade` — Autonomer Stack-Modernisierer · Wo: Repo · **Namespace Pflicht**
Erkennt Ist-Versionen, recherchiert Ziel-Versionen, löst Cross-Achsen-Kompatibilität (Solver), schreibt UpgradePlan + Board-Leiter, bootstrappt fehlende Packs und arbeitet die Leiter eingaben-frei via `flow` ab → `retro`.
```
/agent-flow:upgrade                # cwd-Repo
/agent-flow:upgrade <owner/repo>   # explizites Ziel-Repo
```
Resume/Abort laufen über den `profile.upgrade`-Block automatisch (erneuter Aufruf nimmt einen offenen Lauf wieder auf).

### `preview` — Produktiv-Image deployen + Test-URL · Wo: Repo (teils repo-frei)
Zieht das ghcr-Image, startet einen Container, smoke-testet, gibt URL. Cleanup lässt Image/Repo/Board unangetastet.
```
/agent-flow:preview up [<app>]     # Mac: http://localhost:<port> · VPS: https://<app>.<domain>
/agent-flow:preview down [<app>]
/agent-flow:preview list           # laufende Previews
/agent-flow:preview available      # deploybare Apps (repo-unabhängig)
```

### `train` — Knowledge-Pack aus dem Web aktualisieren · Wo: Workspace/Repo (öffnet PR gegen agent-flow)
Recherchiert aktuelle Patterns für Sprache/Framework/Build-Tool und aktualisiert den Pack (mit Quellen, PR+Gate).
```
/agent-flow:train <pack-id>
/agent-flow:train --bootstrap <pack-id>   # fehlenden Pack neu anlegen (v.a. von /upgrade genutzt)
```
| pack-id Form | Beispiel |
|---|---|
| `<id>` (Sprache/Build) | `/agent-flow:train flutter` · `/agent-flow:train maven` |
| `<id>@<major>` (Framework) | `/agent-flow:train spring-boot@3` |
| `frameworks/…` · `build/…` · `migration/…` (expliziter Pfad bei Ambiguität) | `/agent-flow:train migration/flyway@10` |

### `retro` — Erfahrung → Pack-Verbesserung (PR+Gate) · Wo: Repo
Destilliert projekt-lokale Lessons **oder** Sonar-Findings in die globalen Packs und öffnet einen PR (nie Direkt-Edit).
```
/agent-flow:retro [--force]               # Lessons (.claude/lessons/*); --force umgeht den Wochen-Cooldown
/agent-flow:retro --sonar [<repo>|all]    # Sonar-Findings ernten (token-frei für public); all = alle adoptierten Repos
```

---

## Architektur (Kurz)

```
agent-flow/
├── agents/      generische Rollen-Agenten: requirement·architekt·dba·designer·coder·reviewer·tester·retro·train·teamLeader
├── knowledge/   Packs (Expertise): java js ts angular html css tailwind flutter sql security architecture
│                + frameworks/ + build/ + quality/sonar.md   — Coder-Guidance / Reviewer-Checklist / Test-Approach
├── templates/   Scaffolding pro Projekt-Typ (Dockerfile + CI + profile) + _shared/ (DB/Companion/Sonar-Fragmente)
├── skills/      Entry-Points (= die Commands oben)
├── scripts/     .env.gpg-/Auth-Mechanik (ensure-gh-auth.sh)
├── CONCEPT.md · AGENTS.md · LEARNINGS.md   Architektur · Agenten-Specs · Self-Improvement-Ledger
```

**Prinzipien:** Rolle ≠ Expertise (generische Agenten + ladbare Packs) · Self-Improvement nur via **PR + Gate**
(`retro`/`train`/`teamLeader` editieren nie direkt main) · Spec-getrieben (durable `docs/` = Source of Truth) ·
Per-Projekt-Zustand lebt im Projekt-Repo, dieses Repo bleibt projekt-neutral.

Details: `CONCEPT.md` · `AGENTS.md`.
