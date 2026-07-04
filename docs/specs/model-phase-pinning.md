---
id: model-phase-pinning
title: Phasen-Pinning der Design-Rollen auf die Qualitäts-Modellstufe
status: active
area: flow-orchestrierung
version: 1
spec_format: use-case-2.0
---

# Spec: Phasen-Pinning der Design-Rollen auf die Qualitäts-Modellstufe  (`model-phase-pinning`)

> **Schicht 3 von 3.** Testbares **Verhalten + Verträge**, sprach-/paradigma-unabhängig (Intent, keine Idiome/Klassen).
> **Source of Truth** für `coder` (baut daraus), `tester` (testet die Acceptance-Kriterien + Coverage-Gate), `reviewer` (prüft den Diff dagegen — hartes Drift-Gate).

## Zweck
Owner-Entscheidung 2026-07-02 (Token-Analyse, Vorfall Session-Limit): **Qualität wird vorne investiert, wo Fehler sich vervielfachen** — Konzept-/Spec-Erfassung, Architektur und Design-Vorgaben laufen IMMER auf der Qualitäts-Modellstufe (`opus`), unabhängig vom aktiven Cost-Mode des Laufs. Die Umsetzungs-Rollen (coder/tester/cicd, reviewer als Gate) folgen weiterhin dem Cost-Mode. Damit wird `--cost balanced` zum sparsamen Standard für Drains, ohne die Design-Qualität zu senken.

## Kontext (bindend)
Die Tier-Matrix (`knowledge/model-tiers.md`, Rolle × Modus) ist die eine Wahrheit für Modell-Overrides; im Modus `balanced` gilt das Agent-Frontmatter (kein Override). `requirement` und `architekt` stehen bereits in allen Nicht-frontier-Modi auf `opus`-Niveau (Frontmatter `opus`). Die **Design-Rollen-Menge** dieser Spec ist: `requirement`, `architekt`, `designer`, `dba` (nur Design-Modus Datenmodell-Entwurf). `estimator`, `retro`, `train` sind KEINE Design-Rollen im Sinne dieser Spec.

## Acceptance-Kriterien

- **AC1** — `knowledge/model-tiers.md`: Die Zeilen der Design-Rollen führen in den Spalten `low-cost`, `balanced` und `max-quality` durchgängig `opus`: `requirement` und `architekt` auch in `low-cost` (bisher `sonnet`); `designer` in `low-cost`, `balanced` und `max-quality` (bisher `haiku`/`sonnet`/`opus`). Die `frontier`-Spalte bleibt unverändert (Opt-in-Semantik D1).
- **AC2** — `agents/designer.md` Frontmatter `model:` steht auf `opus` (Konsistenz zur `balanced`-Spalte == Frontmatter-Lesart der Matrix).
- **AC3** — `dba` Design-Modus: Der Dispatch des dba im **Design-Modus** (Datenmodell-Entwurf, `docs/data-model.md`) erhält in JEDEM Cost-Mode einen `model: opus`-Override; der **Review-Modus** (Zweit-Review bei DB-Items) folgt unverändert der Matrix-Zeile `dba`. Die Stelle, die den Design-Modus-Dispatch beschreibt (Skill/Agent-Doku), dokumentiert das explizit.
- **AC4** — `knowledge/model-tiers.md` erklärt das Phasen-Prinzip in einem kurzen Abschnitt („Design-Rollen sind gepinnt — Owner-Entscheidung 2026-07-02, Begründung: Upstream-Fehler multiplizieren sich downstream") inklusive der abschließenden Design-Rollen-Menge.
- **AC5** — `skills/flow/SKILL.md` (Cost-Mode-Abschnitt §0) verweist darauf, dass Design-Rollen-Pinning Vorrang vor der Modus-Spalte hat (ein Satz + Verweis auf die Matrix-Doku; keine neue Auflösungslogik im Skill nötig, sofern die Matrix-Werte selbst das Pinning abbilden).

## Verträge
- **Design-Rollen-Menge (abschließend):** `{ requirement, architekt, designer, dba(Design-Modus) }`.
- **Pinning-Stufe:** `opus` (= `max-quality`-Niveau). `frontier` bleibt als bewusstes Opt-in davon unberührt.
- **Matrix bleibt die eine Wahrheit:** Kein Skill hartkodiert Modellnamen an Dispatch-Stellen; das Pinning materialisiert sich in den Matrix-Zellen + Agent-Frontmatter.

## Edge-Cases & Fehlerverhalten
- **E1:** Lauf mit `--cost low-cost` → Design-Rollen-Dispatches erhalten dennoch `opus` (Matrix-Zelle), Umsetzungs-Rollen die `low-cost`-Werte. Kein Fehler, kein Hinweis nötig.
- **E2:** `dba` wird im Review-Modus bei `--cost low-cost` dispatcht → `sonnet`/Matrix-Wert, NICHT `opus` (Modus-Unterscheidung greift).

## NFRs
- Reine Doku-/Matrix-/Frontmatter-Änderung; keine neue Laufzeit-Logik außer der dba-Design-Modus-Regel an der bestehenden Dispatch-Stelle.

## Nicht-Ziele
- Keine Änderung der `frontier`-Semantik (D1 bleibt).
- Kein Pinning für `estimator`, `retro`, `train`, `teamLeader`.
- Keine per-Story-Modellwahl (bleibt Cost-Mode + Matrix).

## Abhängigkeiten
- `[[model-tier-curator]]` (Matrix-Pflege durch /train model-tiers — der Curator darf das Pinning nicht wegkuratieren; Hinweis-Satz in AC4 deckt das ab).
