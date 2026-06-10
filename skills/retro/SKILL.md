---
name: retro
description: Startet den retro-Agenten — destilliert projekt-lokale Lessons (Tier 1) ODER Sonar-Findings (--sonar) in Verbesserungen der globalen Knowledge Packs / Skills und öffnet dafür einen PR (PR+Gate). Im Projekt-Repo ausführen. Aufruf: /retro [--force] | /retro --sonar [<repo>|all].
---

# /retro [--cost <mode>] [--force] | /retro [--cost <mode>] --sonar [<repo>|all]

**Cost-Mode auflösen:** Präzedenz `--cost`-Argument > `profile.cost_mode` > `balanced` (Kurzformen `low`/`max`/`front` normalisieren; `front`→`frontier`). Beim Task-Dispatch den `model`-Parameter aus `${CLAUDE_PLUGIN_ROOT}/knowledge/model-tiers.md` (Rolle `retro`) mitgeben; bei `balanced` **keinen** Override (Frontmatter `opus` gilt). Das `--cost`-Token NICHT als `--force`/`--sonar`-Argument fehldeuten — vorher herausparsen.

Starte den **retro**-Agenten (Task-Tool). Zwei Evidenz-Quellen:

- **Modus A — Lessons (Default, `/retro [--force]`):** liest `.claude/lessons/*` im aktuellen Projekt-Repo, clustert das Verallgemeinerbare, dedupliziert gegen die `knowledge/`-Packs und öffnet einen **PR** gegen `agent-flow`.
- **Modus B — Sonar-Harvest (②, `/retro --sonar [<repo>|all]`):** zieht die statischen Analyse-Findings (SonarCloud/SonarQube, faceted nach Rule, token-frei für public) eines Repos (`<repo>`/cwd) oder aller adoptierten Repos (`all`), triagiert sie (a Pack-Regel / b Reviewer-Checklist / c Skip) und promotet die generalisierbaren, wiederkehrenden Muster als Pack-Regeln — damit künftige Repos diese Fehlerklassen seltener machen. **Maturity-Gate:** Repos ohne abgeschlossene Analyse / < 20 Findings werden übersprungen. Details: `agents/retro.md` → *Sonar-Harvest-Modus* (H1–H4).

**4 Schutzgitter** (Spec: `docs/architecture/framework-build-subsystem.md` §9, HART):

1. **Frequenz-Schwelle:** Promotion nur bei ≥2 Projekten × ≥2 Stellen. Ein-Projekt-Patterns bleiben lokal.
2. **Provenance im PR-Body:** jede Regel listet die Quell-Lessons namentlich (Projekt + Datei/Zeile oder PR-Nummer).
3. **Cooldown:** max. 1× pro Woche pro Repo (gespeichert in `.claude/lessons/.retro-last-run`). `--force` umgeht den Cooldown bewusst und manuell. Im Sonar-Modus gilt **G1-Sonar** statt G1: ≥2 Repos ODER ≥5× in 1 Repo + generische Built-in-Rule + User-getriggert (`agents/retro.md` H3).
4. **Reviewer-Gate:** retro-PR durchläuft den normalen reviewer-Loop. Kein Auto-Merge, kein Bypass.

**Sektions-Disziplin bei Framework-/Build-Packs:** retro schreibt NUR in `## B. Anti-Patterns aus Einsatz` (Sektion A ist train-Hoheit; Sektion C nur mit explizitem User-Approval).

**Cross-Pack-Bündelung:** alle Promotions für denselben Pack = ein PR; verschiedene Packs = separate PRs.

Danach: PR-Link an den User. **Merge erst nach `reviewer`-Check + deinem Approve** (Gate §5) — NIE automatisch.
