---
spec_format: use-case-2.0
status: active
---

# Spec: Fabrik lernt aus Orchestrator-Arbeit + Red-Team-Retro-Auslöser

> Retro-Verbesserungen aus der Retro vom 2026-07-21 (Nacht-Implementierungen). Feature: F-034.
> Punkt 1 (Orchestrator-Lessons erreichen die Fabrik) + Punkt 3 (Cross-Repo-Transport für Security-Funde).
> Punkt 2 (Worktree-freundliche Tests) ist die dev-gui-Seite, separat.

## Kontext & Motivation

Die Retro vom 2026-07-21 machte einen **blinden Fleck** sichtbar: Eine ganze Nacht Groß-Feature-Arbeit hinterließ
**keine** promotbaren Lessons, weil (a) sie über general-purpose-Subagenten lief, die keine `.claude/lessons/`
schreiben, und (b) selbst der bestehende **Orchestrator-Lesson-Kanal `.claude/lessons/flow.md`** von `retro`
**nicht geharvestet** wird — `/flow` schreibt dorthin, aber retros Tier-1-Quelle listet nur `{coder,reviewer,tester}.md`.
Orchestrator-Lessons bleiben so in `flow.md` gefangen und werden nie zur Fabrik-Regel verallgemeinert.

Zusätzlich: Ein Red-Team-Lauf in einem Konsum-Repo (z.B. flashrescue) erzeugt bereits **klassifizierte** Lessons
(generisch vs projekt-spezifisch, F-033 Teil C). Damit die **generischen** Härtungen in die zentrale Fabrik
promoten, muss aber jemand `/retro` **in genau diesem Repo** anstoßen — der Auslöser fehlt.

## Akzeptanzkriterien

### Punkt 1 — Orchestrator-Lessons erreichen die Fabrik
- **AC1 — retro harvestet den Orchestrator-Kanal (mechanischer Fix, HART).** `agents/retro.md` nimmt
  `.claude/lessons/flow.md` **verbindlich** in die Tier-1-Quellliste auf (Modus A: „Zuerst lesen" + Vorgehen +
  Provenance-Beispiele) — gleichrangig zu `{coder,reviewer,tester}.md`. Damit werden Orchestrator-Lessons wie die
  Arbeits-Agenten-Lessons geclustert, dedupliziert und (bei G1-Erfüllung) promotet. `flow.md` ist der **kanonische**
  Orchestrator-Lesson-Kanal (keine zweite Datei wie `orchestrator.md`).
- **AC2 — Orchestrator füttert den Kanal (Konvention).** Es wird dokumentiert (in `skills/flow/SKILL.md` und
  `AGENTS.md`), dass **jeder Orchestrator** — `/flow`, der Nachtwächter-Außenlauf **und eine Owner-Session, die
  substanzielle Mehr-Feature-Arbeit koordiniert** — vor Session-/Lauf-Ende die wichtigsten **Session-Lessons** in
  `.claude/lessons/flow.md` prependet (newest-first, mit dem nächsten Board-Commit gelandet). So wird auch
  Groß-Feature-Arbeit sichtbar, nicht nur Klein-Story-Arbeit der Agenten.

### Punkt 3 — Cross-Repo-Transport für generische Security-Funde
- **AC3 — Red-Team-Retro-Auslöser.** `agents/red-team.md` (+ Konzept `docs/architecture/red-team-subsystem.md`):
  Enthält ein Lauf **generische/universelle** Funde (Klassifikation aus F-033 Teil C), **empfiehlt/stößt** der Agent
  nach dem Landen des Red-Team-PRs einen **`/retro`-Lauf im selben Konsum-Repo** an — das ist der Transport, über den
  die generischen Härtungen in die Norm-Lane (via `train`) + die Security-Baseline promoten (retro liest nur das
  cwd-Repo; der Auslöser muss dort laufen). Kein generischer Fund → keine Empfehlung (Proportionalität). Der Vermerk
  gehört in die headless-Ausgabe + den Protokoll-Block, damit auch ein GUI-/Nachtwächter-Konsument den Folge-Schritt kennt.

## Bewusst NICHT

- **Kein erzwungener Auto-Spawn** einer Retro aus dem Red-Team-Lauf heraus (das wäre überraschend/teuer) — der Auslöser
  ist eine **klare Empfehlung + Ausgabe-Vermerk**; die tatsächliche Retro bleibt ein bewusster (ggf. GUI-)Schritt.
- **Kein Aushebeln von G1/Lane-Rechten.** Orchestrator-Lessons durchlaufen dieselben Schutzgitter (G1 ≥2 Projekte ×
  ≥2 Stellen); generische Security-Funde nutzen den bestehenden F-033-Teil-C-Routing-Pfad (retro schlägt vor, train schreibt).
- **Punkt 2 (Worktree-Tests)** ist NICHT Teil dieser Spec (dev-gui-Seite, eigenes Board-Item).
