---
language: md
domains: []
build: "true"
test: "true"
lint: "true"
merge_policy: direct
board: 5
deploy: none
default_branch: main
cost_mode: balanced
---

# Projekt-Profil — agent-flow (Selbst-Dogfooding)

agent-flow ist das Fabrik-Plugin selbst (Markdown-Agenten/Skills/Knowledge +
Bash-Scripts), **kein deploybares Programm**. Daher:

- `language: md` — kein Sprach-Pack; coder/reviewer arbeiten an Agent-Defs,
  Skills, Knowledge-Packs und `docs/`.
- `build`/`test`/`lint: "true"` — No-Op-Befehle (exit 0). Es gibt keinen
  klassischen Build/Test-Lauf. Mechanische Smokes für Template-/DB-Subsystem
  dispatcht der `tester` selbst (`tests/db-subsystem/*.sh`); reine
  Doku-/Markdown-Diffs → `SKIPPED-DOC-ONLY`.
- `deploy: none` — kein Docker-Rollout; `cicd` landet nur (merge + push).
- `default_branch: main` — der Metrik-Subsystem-Lauf nutzte temporär den
  Integrations-Branch `feat/metrics-subsystem` (paralleler Lauf arbeitete auf
  `main`); nach Abschluss auf `main` zurückgesetzt.
- `board: 5` — Org-Project „agent-flow improvements".
