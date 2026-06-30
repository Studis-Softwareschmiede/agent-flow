---
id: frontier-cost-mode
title: Vierter Cost-Modus `frontier` (opt-in, Modell-Klasse fable)
status: active
version: 1
---

# Spec: Vierter Cost-Modus `frontier`  (`frontier-cost-mode`)

> **Schicht 3 von 3.** Testbares **Verhalten + Verträge**, sprach-/paradigma-unabhängig (Intent, keine Idiome/Klassen).
> **Source of Truth** für `coder` (baut daraus), `tester` (testet die Acceptance-Kriterien), `reviewer` (prüft den Diff dagegen — hartes Drift-Gate).
>
> **Detailkonzept-Bindung.** Das Subsystem ist in `docs/architecture/model-tier-subsystem.md` spezifiziert (bindend). Die maßgebliche Rolle×Modus→Modell-Matrix ist `knowledge/model-tiers.md` (Single Source of Truth). Diese Spec erweitert das bestehende Cost-Mode-Subsystem (Bausteine 1–3, gemergt via #90–#96) um einen **vierten, opt-in Modus `frontier`** und ist die agent-flow-seitige Fundamentarbeit. Die GUI-Seite (dev-gui) ist eine **separate** Folge-Aufgabe (siehe Abhängigkeiten).

## Zweck

Das Cost-Mode-Subsystem kennt heute drei Modi (`low-cost | balanced | max-quality`) über der Modell-Klassen-Ordnung `haiku < sonnet < opus`. Diese Spec führt einen **vierten, explizit opt-in Modus `frontier`** ein, der die neue, autoritativ verifizierte Modell-Klasse **`fable`** (Claude Fable 5, `claude-fable-5`) nutzt. `frontier` steht **oberhalb** von `max-quality` und ist von ihm **getrennt**: `max-quality` bleibt bewusst bei `opus`, weil Opus 4.8 ein Adaptive/Extended-Reasoning-Profil hat, das Fable 5 **nicht** besitzt (kein Extended Thinking; nur Adaptive Thinking always-on). `frontier` ist **nie** Default — der Default bleibt `balanced`.

## Kontext / Designnuancen (bindend)

- **Verifizierte Vorbedingungen (als gegeben).**
  - `fable` ist als `model`-Override im Task-Dispatch von Claude Code **empirisch bestätigt** (Test-Subagent lief als `claude-fable-5`). Der Modus ist also ein echter Subagent-Hebel — die Override-Mechanik trägt eine vierte Modell-Klasse.
  - Fable 5: GA seit 2026-06-09, Pricing $10/$50 MTok (Input/Output), ca. **2× über Opus** ($5/$25). **Kein Extended Thinking; Adaptive Thinking always-on.** Quellen: `platform.claude.com` Models overview + Pricing (bereits als `primary_sources` im Header von `knowledge/model-tiers.md` verankert).
- **Abo, nicht API (dev-gui ADR-001).** Der Cost-Mode ist ein **Token-/Modell-Hebel** gegen das Abo-**Kontingent** (5h-/Wochen-Fenster), kein Dollar-Optimierer. Die $/MTok-Werte fließen nur als **relative Tier-Einordnung** ein (`fable` > `opus`), nie als Dollar-Zielwert.
- **`fable` ohne Extended Thinking.** Für agentisches Coding/Review/Architektur ist Opus 4.8 dank Extended/Adaptive-Reasoning teils stärker; `frontier` ist daher kein pauschales „besser als max-quality", sondern eine **opt-in Frontier-Wahl** für Läufe, in denen die rohe Fable-5-Klasse gewünscht ist. Diese Nuance begründet die gewählte selektive Rollen-Einordnung (V3, Designentscheidung D1).
- **Kein Regress.** Die Erweiterung ist **additiv**: `balanced` bleibt bitgenau das Frontmatter (I1 unangetastet), die drei bestehenden Spalten bleiben unverändert. `frontier` ist eine **neue Spalte**, keine Umverteilung bestehender Werte.

## Verhalten

### V1 — Vierter Modus, neue Klassen-Ordnung
Das Subsystem kennt nach dieser Spec vier Modi: `low-cost | balanced | max-quality | frontier`. Die Modell-**Klassen-Ordnung** wird von `haiku < sonnet < opus` auf **`haiku < sonnet < opus < fable`** erweitert. Die Override-Mechanik-Enum des `model`-Parameters wird von `opus | sonnet | haiku` auf **`opus | sonnet | haiku | fable`** erweitert.

### V2 — `frontier` ist opt-in, NIE Default
Der Default bleibt **`balanced`**. `frontier` wird **ausschließlich** durch explizite Wahl aktiv:
1. **Lauf-Argument** `--cost frontier` (Kurzform `front`) am Skill, oder
2. **Projekt-Default** `cost_mode: frontier` in `.claude/profile.md` (bewusst gesetzt).

Ein unbekannter/fehlender Wert fällt **nie** auf `frontier` zurück, sondern auf `balanced` (mit einzeiligem Hinweis). Die Auflösungs-Präzedenz bleibt unverändert: `--cost`-Argument > `profile.cost_mode` > `balanced`.

### V3 — Rollen-Einordnung der `frontier`-Spalte (Designentscheidung D1)
Die `frontier`-Spalte der Matrix wird **aus der `max-quality`-Spalte abgeleitet**: gewählte Variante **(b) „Selektiv"** — nur die **Top-Reasoning-Rollen** werden auf `fable` gehoben, die übrigen Rollen behalten ihren `max-quality`-Wert (kontingent-schonend, da `fable` 2× teurer ist und kein Extended Thinking hat).

| Rolle | `max-quality` | `frontier` (gewählt: Variante b) |
|---|---|---|
| architekt   | opus   | **fable** |
| requirement | opus   | **fable** |
| reviewer    | opus   | **fable** |
| coder       | opus   | **fable** |
| retro       | opus   | opus |
| teamLeader  | opus   | opus |
| tester      | opus   | opus |
| dba         | opus   | opus |
| designer    | opus   | opus |
| train       | opus   | opus |
| cicd        | sonnet | sonnet |

Diese Einordnung wahrt **I2** (`max-quality ≤ frontier`): jede Rolle ist in `frontier` ≥ ihrem `max-quality`-Wert.

> **Designentscheidung D1 — bestätigt (2026-06-10): Variante (b) „Selektiv".** Nur die Top-Reasoning-Rollen (architekt/requirement/reviewer/coder) laufen auf `fable`; die übrigen behalten ihren `max-quality`-Wert. Begründung: `fable` ist ~2× teurer (Kontingent) + hat kein Extended Thinking ⇒ nicht pauschal über Opus. Verworfene Alternativen: **(a)** opus→fable überall (cicd bleibt sonnet); **(c)** fable überall inkl. tester/cicd (maximaler/teuerster Modus). Eine spätere Umstellung beträfe nur die Zellen der `frontier`-Spalte in `knowledge/model-tiers.md`; V1/V2/V4–V6 und alle AC bleiben gültig.

### V4 — Override-Mechanik (unverändert, vierte Klasse zulässig)
Beim `Task`-Dispatch gilt weiterhin:
```
model = (cost_mode == "balanced") ? <kein Override>          // Frontmatter gilt
                                  : Matrix[rolle][cost_mode]
```
Für `cost_mode == "frontier"` schlägt der Skill die Rolle in der `frontier`-Spalte nach und übergibt den Treffer (`fable | opus | sonnet`) als `model`-Override. Präzedenz unverändert: **Override > Frontmatter > Session-Erbe**. Bei `frontier` wird — wie bei `low-cost`/`max-quality` — **immer** ein Override gesetzt (auch wenn der Treffer zufällig dem Frontmatter entspricht); nur `balanced` setzt keinen.

### V5 — Skill-Normalisierung (`--cost frontier`)
Die Skills `/flow`, `/requirement`, `/retro`, `/train` akzeptieren `frontier` als gültigen `--cost`-Wert. Kurzform `front` → `frontier` (normalisiert), ebenso der Langwert `frontier`. Die bestehenden Normalisierungen (`low`→`low-cost`, `max`/`high`→`max-quality`, `mid`/`std`→`balanced`) bleiben. Das `--cost frontier`/`--cost front`-Token wird wie bisher vor dem Agent-Dispatch aus den Argumenten herausgeparst (nicht als Anforderung/pack-id/`--force`/`--sonar` fehldeuten).

### V6 — Knowledge-Pack & Architektur-Doc nachgezogen
- `knowledge/model-tiers.md` erhält eine vierte Matrix-**Spalte `frontier`** (Werte gemäß V3), die „Drei Modi"-Beschreibung wird zu „Vier Modi", und die Sektion **„Beobachtete neue Modell-Klasse `fable`" wird aufgelöst/aktualisiert**: `fable` ist nun via `frontier` regulär eingebunden (kein offener Scope-Cut mehr). Die Klassen-Ordnung und die `primary_sources` bleiben (fable bereits dort belegt).
- `docs/architecture/model-tier-subsystem.md` wird auf vier Modi erweitert: Klassen-Ordnung `haiku < sonnet < opus < fable`, Invariante I2 → `low-cost ≤ balanced ≤ max-quality ≤ frontier`, Override-Enum `+ fable`, Profil-Enum (§6) `+ frontier`, Auflösungs-/Präzedenz-Logik (Default bleibt `balanced`; `frontier` ist explizit opt-in, nie Default).

## Acceptance-Kriterien

- **AC1** — Das Subsystem kennt vier Modi `low-cost | balanced | max-quality | frontier`; die Modell-Klassen-Ordnung ist `haiku < sonnet < opus < fable` und der `model`-Override-Enum umfasst `opus | sonnet | haiku | fable`. Dokumentiert in `docs/architecture/model-tier-subsystem.md`. *(V1)*
- **AC2** — Der Default bleibt `balanced`; `frontier` wird **nur** durch explizites `--cost frontier`/`--cost front` oder `cost_mode: frontier` aktiv. Ein unbekannter/fehlender Wert fällt auf `balanced` zurück (mit Hinweis), **nie** auf `frontier`. *(V2)*
- **AC3** — `knowledge/model-tiers.md` enthält eine vierte Spalte `frontier`; jede dispatchbare Rolle (I3) hat dort einen Wert. Die Werte entsprechen der in V3 gewählten Variante (Default (b)): architekt/requirement/reviewer/coder = `fable`, retro/teamLeader/tester/dba/designer/train = `opus`, cicd = `sonnet`. *(V3, V6)*
- **AC4** — Invariante **I2** gilt für alle vier Spalten: je Rolle `low-cost ≤ balanced ≤ max-quality ≤ frontier` in der Ordnung `haiku < sonnet < opus < fable` (kein Modus dreht gegen seine Richtung). *(V1, V3)*
- **AC5** — **Kein Regress (I1):** die Spalten `low-cost`, `balanced`, `max-quality` sind unverändert; `balanced` == `model:`-Frontmatter jeder Rolle. Die Erweiterung ist rein additiv (neue Spalte). *(V6)*
- **AC6** — Bei `cost_mode == frontier` setzt jeder Skill-Dispatch einen `model`-Override aus der `frontier`-Spalte (`fable | opus | sonnet`); bei `balanced` weiterhin **keinen**. Präzedenz Override > Frontmatter > Session-Erbe. *(V4)*
- **AC7** — `/flow`, `/requirement`, `/retro`, `/train` akzeptieren und normalisieren `frontier` (und Kurzform `front`) als gültigen `--cost`-Wert; das Token wird vor dem Agent-Dispatch sauber herausgeparst (keine Fehldeutung als Anforderung/pack-id/`--force`/`--sonar`). *(V5)*
- **AC8** — Die Sektion „Beobachtete neue Modell-Klasse `fable`" in `knowledge/model-tiers.md` ist aufgelöst/aktualisiert: `fable` ist als via `frontier` eingebundene reguläre Klasse beschrieben (kein offener Scope-Cut-Hinweis mehr). *(V6)*
- **AC9** — `docs/architecture/model-tier-subsystem.md` ist konsistent erweitert: vier Modi (Tabelle §2), I2 mit vier Spalten (§3), Override-Enum `+ fable` (§5), Profil-Enum `+ frontier` (§6), Auflösung mit „frontier opt-in, nie Default" (§4). *(V6)*

## Verträge

- **Trigger:** `--cost frontier` (Kurz: `--cost front`) an `/flow`, `/requirement`, `/retro`, `/train`; bzw. `cost_mode: frontier` in `.claude/profile.md`.
- **Modell-Klassen-Ordnung:** `haiku < sonnet < opus < fable`.
- **Override-Enum (`model`-Parameter des Task-Tools):** `opus | sonnet | haiku | fable`.
- **Profil-Enum (§6):** `low-cost | balanced | max-quality | frontier` (Default `balanced`; fehlender Key ⇒ `balanced`, Backwards-Compat).
- **Matrix-Single-Source:** `knowledge/model-tiers.md` (vierte Spalte `frontier`). Bindendes Subsystem-Doc: `docs/architecture/model-tier-subsystem.md`.
- **Matrix-Invarianten (bleiben gewahrt):** I1 (`balanced` == Frontmatter), I2 (`low-cost ≤ balanced ≤ max-quality ≤ frontier`), I3 (jede dispatchbare Rolle hat eine Zeile mit Wert in allen vier Spalten).

## Edge-Cases & Fehlerverhalten

- **Unbekannter `--cost`-Wert** (z.B. `--cost fronteer`): Fallback auf `balanced` + einzeiliger Hinweis — **nie** auf `frontier` raten.
- **Kein `--cost`-Argument und kein Profil-Key:** `balanced` (unverändert) — `frontier` wird nie implizit aktiv.
- **`frontier` gesetzt, aber Rolle ohne `frontier`-Zelle:** I3-Verletzung — vom Reviewer als harter Befund zu fangen; jede dispatchbare Rolle muss eine `frontier`-Zelle haben.
- **I2-Konflikt** (eine `frontier`-Zelle wäre niedriger als `max-quality` derselben Rolle): unzulässig — die `frontier`-Spalte ist aus `max-quality` nach oben (oder gleich) abgeleitet.
- **Frontmatter-Drift:** die Erweiterung berührt **keine** Agenten-Frontmatter (I1) — eine Frontmatter-Änderung im Diff ist ein Drift-Befund.

## NFRs

- **Token-/Limit-bewusst:** `frontier` nutzt die teuerste Klasse (`fable`, ~2× opus) und ist daher bewusst opt-in + selektiv (Variante b) eingeordnet — schützt das Abo-Kontingent gegenüber „fable überall".
- **Additiv / regress-frei:** drei bestehende Spalten und alle Frontmatter unverändert (I1).
- **Quellen-Integrität:** `fable`-Fakten (GA-Datum, Pricing-Relation, kein Extended Thinking) stammen aus den verankerten `primary_sources`; keine erfundenen Klassen/IDs.

## Nicht-Ziele

- **dev-gui-Seite** (COST_MODES-Enum 3→4, 4-Wege-Schalter, `--cost`-Validierung, Kosten-Anzeige) — **separate** Folge-Aufgabe im dev-gui-Repo (eigene requirement-Runde, siehe Abhängigkeiten). Hier **nicht** spezifiziert.
- **Umverteilung der bestehenden Spalten** — `low-cost`/`balanced`/`max-quality` bleiben unangetastet.
- **`max-quality` auf `fable` heben** — bewusst getrennt; `max-quality` bleibt `opus` (Extended/Adaptive-Reasoning-Profil).
- **Automatische Modus-Wahl anhand Telemetrie** — out of scope des Subsystems.
- **Künftige Klassen jenseits `fable`** (z.B. mythos) — separat, wenn autoritativ relevant; diese Spec führt nur `frontier`/`fable` ein.

## Abhängigkeiten

- `docs/architecture/model-tier-subsystem.md` — bindendes Detailkonzept (wird hier erweitert).
- `knowledge/model-tiers.md` — Single Source of Truth der Matrix (vierte Spalte; `fable`-Sektion auflösen).
- `skills/{flow,requirement,retro,train}/SKILL.md` — `frontier`-Normalisierung ergänzen.
- `docs/specs/model-tier-curator.md` — Schwester-Spec (der Curator pflegt dieselbe Matrix; I1–I3 konsistent halten).
- **Folge-Item (dev-gui-Repo, separat):** COST_MODES-Enum 3→4 (`+frontier`), `--cost`-Validierung, 3-Wege- → 4-Wege-Schalter, Tests, `flow-trigger.md`/`architecture.md`; PLUS **Kosten-Anzeige** (absolute $/MTok pro Modus mit klarem Abo-Disclaimer „Abo zahlt nicht pro Token — Werte nur theoretisch"). Wird in einer eigenen requirement-Runde im dev-gui-Repo spezifiziert — **nicht** hier.
