---
name: retro
description: Startet den retro-Agenten — destilliert die projekt-lokalen Lessons (Tier 1) in Verbesserungen der globalen Knowledge Packs / Skills und öffnet dafür einen PR (PR+Gate). Im Projekt-Repo ausführen.
---

# /retro

Starte den **retro**-Agenten (Task-Tool) im aktuellen Projekt-Repo. Er liest `.claude/lessons/*`, clustert das Verallgemeinerbare, dedupliziert gegen die bestehenden `knowledge/`-Packs und öffnet einen **PR** gegen das `agent-flow`-Repo (+ `LEARNINGS.md`-Zeile, Improvement-Board-Karte `Proposed`).

Danach: PR-Link an den User. **Merge erst nach `reviewer`-Check + deinem Approve** (Gate §5) — NIE automatisch.
