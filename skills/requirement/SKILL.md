---
name: requirement
description: Startet den requirement-Agenten — verfeinert eine vage Anforderung per Rückfragen in eigenständige TODOs und schreibt sie als GitHub-Issues aufs Projekt-Board (To Do). Aufruf: /agent-flow:requirement <vage Anforderung>. Im Ziel-Projekt-Repo ausführen.
---

# /requirement <vage Anforderung>

cwd = Ziel-Projekt-Repo.

1. **Auth herstellen:** `bash "$CLAUDE_PLUGIN_ROOT/scripts/ensure-gh-auth.sh"` (mintet App-Token, loggt `gh` ein). NICHT `gh auth login --web`.
2. Starte den **requirement**-Agenten (Task-Tool) mit der genannten Anforderung. Er liest `.claude/profile.md` (Board-Referenz) + `CLAUDE.md` + ggf. Design-Docs, fragt **in Runden à max. 2–3 Fragen** bis die Anforderung eindeutig UND in kleine Pakete zerlegbar ist, und legt pro TODO ein **GitHub-Issue + Board-Item (Status: To Do)** an — mit Acceptance Criteria, Priority und ggf. Depends-on.

Danach: Zusammenfassung der angelegten Items an den User → bereit für `/agent-flow:flow`.
