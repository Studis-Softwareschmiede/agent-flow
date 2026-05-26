---
name: requirement
description: Startet den requirement-Agenten — verfeinert eine vage Anforderung per Rückfragen, schreibt durable Specs unter docs/specs/ und legt referenzierende GitHub-Issues aufs Board (To Do). Aufruf: /agent-flow:requirement <vage Anforderung>. Im Ziel-Projekt-Repo ausführen.
---

# /requirement <vage Anforderung>

cwd = Ziel-Projekt-Repo.

1. **Auth herstellen:** `bash "$CLAUDE_PLUGIN_ROOT/scripts/ensure-gh-auth.sh"` (mintet App-Token, loggt `gh` ein). NICHT `gh auth login --web`.
2. Starte den **requirement**-Agenten (Task-Tool) mit der genannten Anforderung. Er liest `.claude/profile.md` (Board-Referenz) + `CLAUDE.md` + `docs/` (concept/architecture/specs), fragt **in Runden à max. 2–3 Fragen** bis die Anforderung eindeutig UND zerlegbar ist, schreibt je Capability eine **durable `docs/specs/<feature>.md`** (nummerierte Acceptance-Kriterien) und legt pro TODO ein **GitHub-Issue + Board-Item (Status: To Do)** an, das auf **Spec + AC-Nummern** zeigt (statt die Kriterien einzubetten).
3. **Specs committen (durable):** der Agent schreibt nur in den Working-Tree. Zeigt `git status --short docs/` Änderungen → committen + pushen:
   ```
   git add docs/ && git commit -m "spec: <kurz> (Items #<…>)
   
   Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>" && git push
   ```
   Specs müssen vor `/flow` auf `main` liegen (der Loop verzweigt pro Item von `main`). Lehnt Branch-Protection den Direkt-Push ab → docs-only-PR öffnen + selbst mergen.

Danach: Zusammenfassung der Specs + angelegten Items an den User → bereit für `/agent-flow:flow`.
