---
name: retro
description: Startet den retro-Agenten — destilliert die projekt-lokalen Lessons (Tier 1) in Verbesserungen der globalen Knowledge Packs / Skills und öffnet dafür einen PR (PR+Gate). Im Projekt-Repo ausführen. Aufruf: /retro [--force].
---

# /retro [--force]

Starte den **retro**-Agenten (Task-Tool) im aktuellen Projekt-Repo. Er liest `.claude/lessons/*`, clustert das Verallgemeinerbare, dedupliziert gegen die bestehenden `knowledge/`-Packs und öffnet einen **PR** gegen das `agent-flow`-Repo.

**4 Schutzgitter** (Spec: `docs/architecture/framework-build-subsystem.md` §9, HART):

1. **Frequenz-Schwelle:** Promotion nur bei ≥2 Projekten × ≥2 Stellen. Ein-Projekt-Patterns bleiben lokal.
2. **Provenance im PR-Body:** jede Regel listet die Quell-Lessons namentlich (Projekt + Datei/Zeile oder PR-Nummer).
3. **Cooldown:** max. 1× pro Woche pro Repo (gespeichert in `.claude/lessons/.retro-last-run`). `--force` umgeht den Cooldown bewusst und manuell.
4. **Reviewer-Gate:** retro-PR durchläuft den normalen reviewer-Loop. Kein Auto-Merge, kein Bypass.

**Sektions-Disziplin bei Framework-/Build-Packs:** retro schreibt NUR in `## B. Anti-Patterns aus Einsatz` (Sektion A ist train-Hoheit; Sektion C nur mit explizitem User-Approval).

**Cross-Pack-Bündelung:** alle Promotions für denselben Pack = ein PR; verschiedene Packs = separate PRs.

Danach: PR-Link an den User. **Merge erst nach `reviewer`-Check + deinem Approve** (Gate §5) — NIE automatisch.
