---
name: train
description: Startet den train-Agenten — recherchiert im Netz aktuelle Patterns für eine Sprache, ein Framework oder ein Build-Tool und öffnet einen PR, der den entsprechenden Pack aktualisiert (mit Quellen, PR+Gate). Aufruf: /train <pack-id>.
---

# /train <pack-id>

Starte den **train**-Agenten (Task-Tool) für eine **Sprache**, ein **Framework** oder ein **Build-Tool**. Pack-ID-Resolver (analog `docs/architecture/framework-build-subsystem.md` §8):

| pack-id Form | Resolver | Beispiel |
|---|---|---|
| `<id>` | erst `knowledge/<id>.md`, sonst eindeutiges Match in `knowledge/frameworks/` oder `knowledge/build/` | `/train flutter`, `/train maven` |
| `<id>@<major>` | `knowledge/frameworks/<id>-<major>.md` | `/train spring-boot@3` |
| `frameworks/<id>`, `build/<id>` ODER `migration/<id>` | expliziter Pfad-Präfix; löst Ambiguität auf | `/train frameworks/redis@7`, `/train migration/flyway@10` |

**Ambiguität:** Ist `<id>` in 2+ Ordnern vorhanden, **STOPPT** der Agent mit einer Optionsliste — kein Default. Erzwingt explizit-präzise ID (z.B. `frameworks/redis@7`).

**`--bootstrap` (fehlenden Pack anlegen):** `/train --bootstrap <pack-id>` bricht bei einem **fehlenden** Pack NICHT ab, sondern legt ihn an (Skelett aus dem Vorgänger bei Cut + Sektion A aus Primärquellen + Solver-Constraints). Primär von `/upgrade` (Phase E) genutzt; bei gesetztem `AGENT_FLOW_KNOWLEDGE_DIR` schreibt er zusätzlich in den hermetischen Staging-Dir des Laufs. Vertrag: `docs/architecture/upgrade-subsystem.md` §8 + `agents/train.md` Abschnitt „Bootstrap-Modus".

Er liest den vom Resolver bestimmten Pack, recherchiert aus **Primär-/autoritativen Quellen** (offizielle Docs/Specs/Release-Notes — keine Einzel-Blogs; bei Framework-/Build-Packs **strikt** nach `primary_sources`/`non_sources` aus dem Pack-Header), priorisiert **faktische Deltas** (Deprecations/neue stabile APIs/Breaking Changes), promotet **max. 3 Regeln/Lauf** und öffnet einen **PR**.

**Bei Framework-/Build-Packs schreibt der train-Agent ausschließlich in Sektion `## A. Stable API & Deprecations`** (Sektion B ist retro-Hoheit; Sektion C nur mit User-Approval). Verstoß = harter Gate-Fail beim Reviewer.

**Merge erst nach `reviewer`-Check + deinem Approve** (Gate §5).
