# agent-flow — die Softwareschmiede

Wiederverwendbares, selbst-verbesserndes **Coder→Reviewer→Tester-Framework** als Claude-Code-Plugin
(Repo-first). Auf beliebige Projekte beliebiger Sprache ansetzbar. Org: `Studis-Softwareschmiede`.

## Bash — Setup pro Maschine

```bash
# 1. Repo klonen (in einen Workspace-Ordner)
gh repo clone studis-softwareschmiede/agent-flow

# 2. Agenten + Skills global verfügbar machen (user-level)
ln -s "$PWD/agent-flow/agents"    ~/.claude/agents-agent-flow      # bzw. einzeln symlinken
ln -s "$PWD/agent-flow/skills"    ~/.claude/skills-agent-flow      # (Plugin-Hülle kommt später)

# 3. GitHub-Token nutzbar machen (uniform Mac == VPS)
mkdir -p ~/.config/softwareschmiede && chmod 700 ~/.config/softwareschmiede
#   GPG-Passphrase (Bitwarden: studis-softwareschmiede-gpg-passphrase) → gpg.pass seeden:
#   <passphrase> > ~/.config/softwareschmiede/gpg.pass && chmod 600 ~/.config/softwareschmiede/gpg.pass
source scripts/load-env.sh        # entschlüsselt .env.gpg → export GH_TOKEN
gh auth setup-git                 # git-über-https nutzt GH_TOKEN
```

## Workflow

```
new-project/init   → Repo + Board + .claude/- & docs/-Scaffold + Dockerfile + CI
  → architekt (+ dba bei DB, + designer bei UI)   → Detailkonzept (docs/architecture|data-model|design.md)
  → requirement                                   → durable Specs (docs/specs/) + Board-Items (To Do)
  → /flow                                          → coder → reviewer ⇄ Loop → tester → Done
                                                     (Spec = Source of Truth; hartes Drift-Gate)
```

## Architektur

```
agent-flow/
├── agents/      10 Subagent-Defs (Prozess, generisch):
│                requirement · architekt · dba · designer · coder · reviewer · tester
│                · retro · train · teamLeader
├── knowledge/   Packs (Expertise pro Sprache/Domäne): flutter html css tailwind
│                angular java js sql architecture security  — Coder-Guidance / Reviewer-Checklist / Test-Approach
│                (security = querschnittlich: ⚑ Floor immer aktiv, auch ohne domains)
├── templates/   Scaffolding: pro Projekt-Typ (Dockerfile + CI + profile) + _docs/ (Spec-Doku-Skelette)
├── skills/      Entry-Points: flow · new-project · requirement · preview · retro · train
├── scripts/     .env.gpg-Mechanik (decrypt/encrypt/load)
├── CONCEPT.md   Architektur & Entscheidungen
├── AGENTS.md    detaillierte Agenten-/Skill-Specs
└── LEARNINGS.md Ledger der Self-Improvement-Promotions
```

## Prinzipien (Kurz)

- **Rolle ≠ Expertise:** generische Rollen-Agenten + ladbare Knowledge Packs (Sprache/Domäne).
- **Alles interaktiv** (unter Claude-Abo) — keine headless/Cloud-Ebene.
- **Self-Improvement nur via PR + Gate:** `retro` (Lessons), `train` (Web), `teamLeader` (neue Rollen)
  ändern Skills NIE direkt → Branch → reviewer-Check + Mensch-Approve → merge.
- **Spec-getrieben (§4d):** durable, sprach-neutrale `docs/` (Konzept → Detailkonzept → Spec) =
  Source of Truth; Code ist nachgelagert (ein Sprach-Port baut aus den Specs, nicht aus dem Alt-Code).
- **Per-Projekt-Zustand** liegt im Projekt-Repo (`CLAUDE.md`, `.claude/profile.md`, `.claude/lessons/*`,
  `docs/` (Konzept/Spec), Board) — dieses Repo bleibt projekt-neutral.

Details: `CONCEPT.md` · `AGENTS.md`.
