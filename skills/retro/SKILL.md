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

1. **Frequenz-Schwelle:** Promotion nur bei ≥2 Projekten × ≥2 Stellen. Ein-Projekt-Patterns bleiben lokal (bzw. `Proposed`-Wartezimmer in `LEARNINGS.md`). **Eng begrenzte Ausnahme — Owner-Override (Amendment 2026-07-18, KEINE Aufweichung von G1):** ist die „≥2 Projekte"-Schwelle **strukturell unerfüllbar** (einziges Projekt seiner Klasse in der Org), kann `retro` nur promoten, wenn **alle vier** Bedingungen belegt sind — (a) strukturelle Unerfüllbarkeit begründet, (b) ≥4 unabhängige Belegstellen in einem Projekt, (c) datiertes Owner-Approval mit Referenz, (d) standardisierter PR-Body-Abschnitt „Owner-Approved G1-Override" (kanonische Vorlage: `docs/specs/retro-g1-owner-override.md` Abschnitt „Verträge") + `LEARNINGS.md`-Kennzeichnung. Fehlt ≥1 Bedingung, bleibt G1 unverändert hart. Präzedenzfall: `agent-flow#335` (`alembic/B01`). Details: `agents/retro.md` Schritt 2.
2. **Provenance im PR-Body:** jede Regel listet die Quell-Lessons namentlich (Projekt + Datei/Zeile oder PR-Nummer).
3. **Cooldown:** konfigurierbar via optionales Profil-Feld `retro_cooldown_days` (`.claude/profile.md`, Ganzzahl ≥ 0 Tage; fehlend/leer/unparsbar ⇒ Default **1 Tag**; `0` = kein Cooldown, Stempel wird trotzdem geschrieben) pro Repo (gespeichert in `<projekt-repo>/.claude/lessons/.retro-last-run` — kanonischer State-Ort im **geharvesteten Projekt-Repo**, NICHT im agent-flow-PR-Ziel). `--force` umgeht den Cooldown bewusst und manuell, unabhängig vom konfigurierten Wert. Im Sonar-Modus gilt **G1-Sonar** statt G1: ≥2 Repos ODER ≥5× in 1 Repo + generische Built-in-Rule + User-getriggert (`agents/retro.md` H3). **Persistenz-Garantie:** der Stempel wird nach jedem erfolgreichen Lauf nach `origin/<default_branch>` des geharvesteten Projekt-Repos committet+gepusht (über denselben C4-Commit-Pfad wie `baseline.json`), sodass er bei isolierten Läufen (Worktree-Read, `mktemp`-Pack-PR) nicht in einem verworfenen Working-Tree verloren geht. Fehlender/leerer/unparsbarer Stempel → kein Cooldown, Lauf erlaubt. (Spec: `docs/specs/retro-cooldown-configurable.md` + `docs/specs/retro-cooldown-persistence.md`)
4. **Reviewer-Gate:** retro-PR wird nach Erstellung an den `reviewer` dispatcht. `PASS` → **Auto-Merge** (squash, kein Owner-Approve nötig — Owner-Entscheid 2026-07-18, `docs/specs/retro-auto-merge.md`). `CHANGES-REQUIRED` → Fix-Loop (max. 3 Iterationen), danach offen + Meldung. Kein Bypass, kein Direkt-Push.

**Sektions-Disziplin bei Framework-/Build-Packs:** retro schreibt NUR in `## B. Anti-Patterns aus Einsatz` (Sektion A ist train-Hoheit; Sektion C nur mit explizitem User-Approval).

**Cross-Pack-Bündelung:** alle Promotions für denselben Pack = ein PR; verschiedene Packs = separate PRs.

Danach: PR-Link an den User. **Merge automatisch nach `reviewer`-`PASS`** (Gate §5, retro-Ausnahme) — kein Owner-Approve nötig; bei `CHANGES-REQUIRED` bleibt der PR im Fix-Loop bzw. offen (siehe Schutzgitter 4).
