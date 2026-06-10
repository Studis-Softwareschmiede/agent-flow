---
name: train
description: Startet den train-Agenten — recherchiert im Netz aktuelle Patterns für eine Sprache, ein Framework oder ein Build-Tool und öffnet einen PR, der den entsprechenden Pack aktualisiert (mit Quellen, PR+Gate). Sondermodus /train model-tiers kuratiert die Modell-Klassen-/Cost-Matrix gegen die Anthropic-Modell-Quellen. Aufruf: /train <pack-id>.
---

# /train [--cost <mode>] [--force] <pack-id>

**Cost-Mode auflösen:** Präzedenz `--cost`-Argument > `profile.cost_mode` > `balanced` (Kurzformen `low`/`max`/`front` normalisieren; `front`→`frontier`). Beim Task-Dispatch den `model`-Parameter aus `${CLAUDE_PLUGIN_ROOT}/knowledge/model-tiers.md` (Rolle `train`) mitgeben; bei `balanced` **keinen** Override (Frontmatter `sonnet` gilt). Das `--cost`-Token gehört NICHT zur pack-id — vor dem Resolver entfernen. Ebenso gehört das `--force`-Token (Sondermodus `model-tiers`, umgeht den Cooldown) NICHT zur pack-id — vor dem Resolver herausparsen und an den Agenten durchreichen.

Starte den **train**-Agenten (Task-Tool) für eine **Sprache**, ein **Framework** oder ein **Build-Tool**. Pack-ID-Resolver (analog `docs/architecture/framework-build-subsystem.md` §8):

| pack-id Form | Resolver | Beispiel |
|---|---|---|
| `model-tiers` | **Sondermodus (Vorrang):** → `knowledge/model-tiers.md`; Modell-Klassen-/Cost-Matrix-Kuration statt Sprach-/Framework-Wissen | `/train model-tiers`, `/train model-tiers --force` |
| `<id>` | erst `knowledge/<id>.md`, sonst eindeutiges Match in `knowledge/frameworks/` oder `knowledge/build/` | `/train flutter`, `/train maven` |
| `<id>@<major>` | `knowledge/frameworks/<id>-<major>.md` | `/train spring-boot@3` |
| `frameworks/<id>`, `build/<id>` ODER `migration/<id>` | expliziter Pfad-Präfix; löst Ambiguität auf | `/train frameworks/redis@7`, `/train migration/flyway@10` |

**Ambiguität:** Ist `<id>` in 2+ Ordnern vorhanden, **STOPPT** der Agent mit einer Optionsliste — kein Default. Erzwingt explizit-präzise ID (z.B. `frameworks/redis@7`).

**`model-tiers` (Sondermodus — Modell-Klassen-/Cost-Matrix kuratieren):** `/train model-tiers [--force]` hält die Matrix `knowledge/model-tiers.md` (Rolle × `low-cost|balanced|max-quality|frontier` → Modell-Klasse) gegen die **Anthropic-Modell-Primärquellen** (Models overview, Model-Deprecations, Pricing — als `primary_sources` im Pack-Header) aktuell. Greift **nur** bei Klassen-/Tier-Änderungen (neue Klasse/Tier, Deprecation/Umbenennung, Tier-Rebalancing) — **nicht** bei neuen Punktversionen. Setzt bei jedem Lauf `last_curated:` (Frischesignal + Cooldown-State), läuft **monatlich + manuell** (Cooldown, `--force` umgeht), liefert via PR+Gate (kein Auto-/Self-Merge). Bindende Spec: `docs/specs/model-tier-curator.md`; Mechanik: `agents/train.md` Abschnitt „Model-Tiers-Modus".

**`--bootstrap` (fehlenden Pack anlegen):** `/train --bootstrap <pack-id>` bricht bei einem **fehlenden** Pack NICHT ab, sondern legt ihn an (Skelett aus dem Vorgänger bei Cut + Sektion A aus Primärquellen + Solver-Constraints). Primär von `/upgrade` (Phase E) genutzt; bei gesetztem `AGENT_FLOW_KNOWLEDGE_DIR` schreibt er zusätzlich in den hermetischen Staging-Dir des Laufs. Vertrag: `docs/architecture/upgrade-subsystem.md` §8 + `agents/train.md` Abschnitt „Bootstrap-Modus".

Er liest den vom Resolver bestimmten Pack, recherchiert aus **Primär-/autoritativen Quellen** (offizielle Docs/Specs/Release-Notes — keine Einzel-Blogs; bei Framework-/Build-Packs **strikt** nach `primary_sources`/`non_sources` aus dem Pack-Header), priorisiert **faktische Deltas** (Deprecations/neue stabile APIs/Breaking Changes), promotet **max. 3 Regeln/Lauf** und öffnet einen **PR**.

**Bei Framework-/Build-Packs schreibt der train-Agent ausschließlich in Sektion `## A. Stable API & Deprecations`** (Sektion B ist retro-Hoheit; Sektion C nur mit User-Approval). Verstoß = harter Gate-Fail beim Reviewer.

**Merge erst nach `reviewer`-Check + deinem Approve** (Gate §5).
