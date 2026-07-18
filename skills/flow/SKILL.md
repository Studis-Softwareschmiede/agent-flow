---
name: flow
description: Orchestriert die Softwareschmiede — liest das Projekt-Board und arbeitet EIN To-Do-Item (bzw. einen SR1-Parallel-Batch) ab (coder → reviewer ⇄ Loop → tester → cicd ship → Done), dann endet die Session (Default, auch headless — Kontext-Wachstum vermeiden; äußere Schleifen wie dev-gui ProjectDrain/Nachtwächter rotieren). `--all` (interaktives Opt-in) behält das bisherige Bis-Board-leer-Verhalten. `--plan` (Spec `docs/specs/parallel-session-plan.md`) erstellt statt eines Item-Build-Loops einmalig einen persistierten Wellen-Plan (`board/runs/session-plan.yaml`) für parallele äußere Sessions, dann endet der Aufruf. Einziger Schreiber von Board-Status. Git-Abschluss-Operationen (merge+push) delegiert /flow an cicd als ausführenden Abschluss-Arm. Im Ziel-Projekt-Repo ausführen.
---

# /flow [--cost <mode>] [--all] [--parent <F-###>] [--plan] — Board abarbeiten (Orchestrator)

Du bist der **Orchestrator** (Haupt-Session). Du dispatchst die Agenten via Task-Tool und bist der **einzige Schreiber** von Board-Status. Git/PR-Operationen im Abschluss werden an `cicd` als ausführenden Arm delegiert (s. §5). cwd = Ziel-Projekt-Repo.

**Feature-Scope (`--parent <F-###>`, seit 2026-07-06 — Feature-Batch-Skript `scripts/board-feature-drain.sh`).** Optionales Argument, beschränkt DIESEN Lauf auf Storys eines einzelnen Features: **jeder** `board next`/`board ready`-Aufruf in diesem Skript (§0a, §1, §7a) bekommt zusätzlich `--parent <F-###>` angehängt — dieselbe Queue-Logik (Priority, Depends-Gate), nur auf das Feature beschränkt. Ohne `--parent`: Verhalten unverändert board-weit. **Landen (§5) ändert sich:** Ist `--parent <F-###>` aktiv, ruft §5 `scripts/board-ship.sh <story-id> [<container>] --target-branch feature/<F-###>` auf (statt ohne `--target-branch`) — die Story landet damit im Feature-Branch, nicht in `main`; kein Rollout für diese Einzel-Story (das übernimmt `board-feature-drain.sh` gebündelt am Feature-Ende via `board-ship.sh --merge-feature feature/<F-###>`, s. dessen eigene Doku). **Dossier-Injektion (AC14, Spec `feature-batch-orchestration.md`):** ist `--parent <F-###>` aktiv, liest `/flow` zu Story-Start `board/runs/<F-###>/dossier.md` (falls vorhanden — vom Drain einmalig in Phase `dossier` erzeugt, s. `board-feature-drain.sh`) und stellt dessen Inhalt dem Kontext beim coder/reviewer/tester-Dispatch (§3/§4) voran. Fehlt die Datei → keine Injektion, kein Fehler. **Handoff-Notiz lesen (AC16):** zusätzlich zum Dossier liest `/flow` bei aktivem `--parent <F-###>` zu Story-Start `board/runs/<F-###>/notes.md` (falls vorhanden) und stellt auch deren Inhalt dem Kontext voran (s. §3). Fehlt die Datei (typischerweise die erste Story des Features) → kein Fehler, einfach kein Voranstellen (E5). **Handoff-Notiz schreiben (AC15):** am Ende der Story-Session hängt `/flow` bei aktivem `--parent <F-###>` **3–5 Zeilen** an `board/runs/<F-###>/notes.md` an — was gebaut wurde + was die nächste Story wissen muss (append-only, s. §5). **Ohne `--parent` erfolgt niemals eine Injektion, kein Lesen/Schreiben von `notes.md`** (unverändertes board-weites Verhalten, vgl. AC8).

**ID-Block-Reservierung (`docs/specs/id-block-reservation.md` AC9/AC10 — Board-weite Parität).** Führt eine Story dieses Laufs eine neue namespaced ID (`BR-###`/`ADR-###`/`C-###`) ein, gilt derselbe Ledger-Mechanismus wie im `--parent`-Feature-Batch (dort reserviert `board-feature-drain.sh` proaktiv bei Batch-Start, s. dessen Doku) — nur reserviert der `coder` in einem board-weiten Einzellauf (ohne `--parent`) **lazy, innerhalb seiner eigenen Session** über `scripts/board-id-reserve.sh reserve <namespace> <story-id>` (Scope-Schlüssel = eigene `S-###`), **bevor** er die ID vergibt (s. `agents/coder.md` 3a). Führt die Story keine neue namespaced ID ein: keine Reservierung, kein Ledger-Diff (unverändertes Verhalten). **Freigabe (AC10):** da der Solo-Pfad kein Batch-Ende kennt, gibt `/flow` die Reservierung **je Story** nach erfolgreichem Landen frei (s. §5, „ID-Block-Freigabe (Solo-Pfad)") — sonst bliebe sie dauerhaft `active`.

**Cost-Mode (Token-Hebel).** Jeder Agent-Dispatch dieses Laufs erhält einen **`model`-Override** gemäß dem aktiven Cost-Modus (in §0 aufgelöst). Aufruf optional mit `--cost <low-cost|balanced|max-quality|frontier>` (Kurz: `low`/`max`/`front`; `frontier` = opt-in, nie Default). Im Modus `balanced` wird **kein** Override gesetzt (Agent-Frontmatter gilt). Matrix + Auflösungsregeln: `${CLAUDE_PLUGIN_ROOT}/knowledge/model-tiers.md`. **Design-Rollen-Pinning hat Vorrang vor der Modus-Spalte:** `requirement`/`architekt`/`designer`/`dba`(Design-Modus) laufen unabhängig vom Cost-Mode auf `opus` (Details + Begründung: `knowledge/model-tiers.md` „Design-Rollen-Pinning").

## 0. Setup
- **`METRICS_ROOT` verankern (zuerst, vor jedem weiteren Schritt — Spec [`docs/specs/metrics-repo-anchor.md`](../../docs/specs/metrics-repo-anchor.md) AC1):** **genau einmal**, im Start-Arbeitsverzeichnis, **vor jedem Verzeichniswechsel und vor jeder Worktree-Erstellung**, ermitteln: `METRICS_ROOT="$(git rev-parse --show-toplevel)"`. Als unveränderliche, **absolute** Session-Variable für den gesamten Lauf merken — kein erneutes `rev-parse` später, auch nicht nachdem `/flow` (oder ein dispatchter coder) in einen Story-Worktree wechselt. **Plausibilitäts-Gate (AC4):** vor dem allerersten Metrik-Write prüfen, ob `${METRICS_ROOT}/board/board.yaml` existiert. Fehlt die Datei → die Metrik-Erfassung für diesen gesamten Lauf mit **einem** Hinweis überspringen (`⚠ METRICS_ROOT (<pfad>) enthält kein board/board.yaml — Metrik-Erfassung diese Session übersprungen.`, K3: Messen blockiert nie den Loop) — es wird **nie** in ein Repo ohne dieses Board geschrieben. **Edge-Case E1:** wird `/flow` selbst innerhalb eines Worktrees gestartet (paralleler Sessions-Sonderfall), liefert `rev-parse --show-toplevel` den Worktree-Pfad als `METRICS_ROOT` — das Gate findet dort `board/board.yaml` (der Worktree spiegelt das Repo), Schreiben ist akzeptiert; die Zeilen landen beim Landen der Story nicht automatisch auf `main` (Metriken „gehören" zu Hauptordner-Läufen — Drain/Nachtwächter erfüllen das im Regelfall).
- `.claude/profile.md` lesen → Board-Referenz, `merge_policy` (`pr`|`direct`), Build/Test-Befehle, **`default_branch`**, **`cost_mode`** (Default `balanced`).
- **Orchestrator-Lessons lesen (einmal, zu Beginn):** existiert `.claude/lessons/flow.md` im Projekt-Repo, diese Datei lesen und ihre Regeln für den gesamten Lauf befolgen — der Tier-1-Kanal für Orchestrator-Ebene (Landen/Konsolidieren/Recovery/Dispatch-Ökonomie), analog zu den coder/reviewer/tester-Lessons, die die Arbeits-Agenten über ihre Verträge lesen. Fehlt die Datei → kein Fehler, weiter. Der Orchestrator prependet eigene neue Lessons dorthin (newest-first) und landet sie mit dem nächsten Board-Commit. *[seen-in: ki-investment 2026-07-14 — Orchestrator-Lessons (Resume-Kosten 381k Token, Feature-Konsolidierung) existierten persistent in flow.md, wurden aber von keinem frischen /flow-Lauf gelesen, weil kein Vertrag darauf zeigte; promoted: 2026-07-14]*
- **Projekt-Memory lesen (einmal, zu Beginn — Spec [`docs/specs/project-memory.md`](../../docs/specs/project-memory.md) AC2):** existiert `.claude/memory.md` im Projekt-Repo, sie lesen und ihre Kern-Punkte (`## Aktueller Stand` + relevante `## Offene Fäden`) als kurzen Kontext für die Story-Dispatches dieses Laufs merken (s. §3, „Projekt-Memory-Kontext"). Fehlt die Datei → kein Fehler, kein Memory-Kontext diese Session (deckt A2) — sie entsteht ggf. erstmalig im Kurations-Schritt am Session-Ende (§7). **Orientierung, nie Wahrheit (AC5):** widerspricht der Memory-Inhalt dem Board oder einer Spec, gelten **Board und Specs** — das Memory erzeugt kein Gate, kein Acceptance-Kriterium, keinen Spec-Ersatz; ein etwaiger Widerspruch wird im Kurations-Schritt (§7) korrigiert, nicht im laufenden Build-Loop verwendet.
- **Cost-Mode auflösen** (einmal, merken — gilt für ALLE Dispatches dieses Laufs): Präzedenz `--cost`-Argument > `profile.cost_mode` > `balanced`. Kurzformen normalisieren (`low`→`low-cost`, `max`/`high`→`max-quality`, `front`→`frontier`). Unbekannter Wert → `balanced` + einzeiliger Hinweis (**nie** auf `frontier` raten — opt-in). **Beim Task-Dispatch jedes Agenten** (coder/reviewer/dba/tester in §3–§4 sowie **cicd** beim SHIP-Dispatch in §5) den `model`-Parameter aus `${CLAUDE_PLUGIN_ROOT}/knowledge/model-tiers.md` (Zeile = Rolle, Spalte = Modus) mitgeben; bei `balanced` **keinen** `model`-Parameter setzen (Frontmatter gilt). Einmal zu Beginn ausgeben: „⚙ Cost-Mode: <mode>".
- **Arbeits-Repo Fork-sicher auflösen** (einmal, merken): Das Arbeits-Repo ist **`origin`**. ⚠️ `gh repo view` **ohne Argument** liefert bei einem Fork das **Upstream-Parent** (gh bevorzugt den `upstream`-Remote) — deshalb IMMER die origin-URL explizit übergeben:
  - `repo="$(gh repo view "$(git remote get-url origin)" --json nameWithOwner -q .nameWithOwner)"`
  - Fehlt `profile.default_branch` (Alt-Repo): `default_branch="$(gh repo view "$(git remote get-url origin)" --json defaultBranchRef -q .defaultBranchRef.name)"` (NICHT `main` annehmen — adoptierte Forks haben oft `master`).
- **Auth herstellen:** `bash "$CLAUDE_PLUGIN_ROOT/scripts/ensure-gh-auth.sh"` (mintet App-Token aus `.env.gpg`, loggt `gh` ein). **NICHT `gh auth login --web`.**
- **Security-Frische (einmaliger Nudge):** `last_trained:` aus `${CLAUDE_PLUGIN_ROOT}/knowledge/security.md` lesen; ist es **> 90 Tage** her → einmal ausgeben: „🔒 security-Pack ist <N> Tage alt — `/train security` erwägen." (nur Hinweis, blockiert nicht).
- **Session-Rotation auflösen** (einmal, zu Beginn — Spec [`docs/specs/flow-session-rotation.md`](../../docs/specs/flow-session-rotation.md) AC3): **Default (ohne `--all`, auch headless):** die Session endet nach dem vollständigen Abschluss GENAU EINER Story bzw. eines SR1-Parallel-Batches (Details §6/§7) — kein automatisches Aufnehmen eines weiteren Items im selben Lauf. **`--all`** (interaktives Opt-in, gedacht für Sessions, in denen der Owner bewusst zusieht; Headless-Aufrufer wie dev-gui `ProjectDrain`/Nachtwächter verwenden es NICHT): behält das bisherige Verhalten (Schleife bis Board leer oder User stoppt). Rationale: Ø Cache-Read wuchs in einer 13-Story-Session von 82k auf 298k Token (Faktor 3,6, Messung 2026-07-02) — Rotation hält das Kontext-Wachstum über ein Board linear statt quadratisch; die äußere Schleife übernimmt die Rotation, `/flow` selbst startet keine Folge-Session.

## 0a. Vorab-Plan (vor dem ersten Item)

Bevor `/flow` mit der Item-Abarbeitung beginnt, liest es alle **bereiten** Stories des Backlogs (`board next --all` oder äquivalent) und erstellt einmalig einen **Abarbeitungsplan**. Der Plan ist eine kurzgefasste Ausgabe (kein Agent-Dispatch, kein LLM-Overhead), die folgende drei Punkte abdeckt:

### (a) Hot-Spot-Datei-Analyse
Für jede Story: welche zentralen Dateien berührt sie (aus Spec-Lektüre + `implements`-ACs)? Taucht eine Datei bei ≥ 2 Stories auf → **Hot-Spot**. Hot-Spot-Stories werden **serialisiert** (nicht parallel dispatcht). Typische Hot-Spots: `AppShell`, Router-Registrierung, `server.js`, `index.ts`-Re-Exporte, `viewRegistry`. (Nachhaltige Kur: Auto-Discovery statt manuelles Wiring — s. `flow/P1` in §3.)

### (b) Konflikt-/„heben-sich-auf"-Check
Widersprechen sich Stories? (Eine baut um, was die andere voraussetzt; eine legt Felder an, die eine andere löscht.) → Reihenfolge nach `depends` + logischer Schichtung (Backend vor Frontend, Datenschicht vor UI).

### (c) depends-Reihenfolge (topologisch)
`board next` respektiert `depends` bereits; `/flow` visualisiert trotzdem die Reihenfolge explizit, damit Parallelisierungs-Gruppen sichtbar sind. Eine Story startet erst, wenn ihre `depends` **terminal** sind — terminale Menge `{Done, Verworfen}` (eine verworfene Vorbedingung erfüllt das Depends-Gate ebenso wie eine erledigte; Spec `docs/specs/story-status-verworfen.md` AC3).

**Ergebnis des Plans:** Eine kurze Ausgabe im Format:

```
Abarbeitungsplan:
  Gruppe 1 (seriell — Hot-Spot: <Datei>): S-### → S-###
  Gruppe 2 (parallel): S-###  ‖  S-###
  Gruppe 3 (seriell — depends): S-###
  Landen: immer seriell (main = eine Senke; Rebase zwischen PRs)
```

Dieser Plan wird dem User ausgegeben und steuert die Dispatch-Reihenfolge in §3.

**Verhältnis zum Plan-Modus (`--plan`, §0b):** Dieser Abschnitt (§0a) plant **innerhalb** einer laufenden Session über die **bereiten** Stories (SR1, Innen-Parallelität). §0b hebt dieselbe dreiteilige Analyse (Hot-Spot/Konflikt/depends) eine Ebene höher: über **alle** To-Do-Stories (bereit + wartend), als **persistiertes Artefakt** für **mehrere unabhängige** `/flow`-Sessions der äußeren Schleife. §0a bleibt unverändert der Normalfall eines einzelnen `/flow`-Laufs.

---

## 0b. Plan-Modus (`/flow --plan` — Spec [`docs/specs/parallel-session-plan.md`](../../docs/specs/parallel-session-plan.md) AC1–AC5/AC8–AC10)

Wird `/flow` mit `--plan` aufgerufen, ersetzt dieser Abschnitt den normalen Item-Build-Loop (§1–§7) für **diesen** Aufruf vollständig — der Plan-Modus baut **kein** Item, er erstellt und persistiert nur den Wellen-Plan für die äußere Schleife (dev-gui Nachtwächter/ProjectDrain). Setup (§0) läuft unverändert davor, soweit für den Plan-Schritt benötigt (Board-Referenz aus `.claude/profile.md`).

**Genau EIN LLM-Planungsdurchgang (AC1).** Die folgenden Schritte 1–4 laufen als **eine** zusammenhängende Analyse dieser Session (kein Agent-Dispatch, kein zusätzlicher LLM-Call pro Story) — danach ist alles Weitere (Revalidierung vor jeder Welle, §0c) rein mechanisch.

1. **Alle To-Do-Stories lesen** (bereite UND wartende — nicht nur `board next`): `board list --type story --status "To Do"` liefert alle Kandidaten inkl. `depends`, `labels`, `spec`, `implements`, `parent`. **Feature-Batches:** jedes Feature mit ≥ 1 To-Do-Story zählt planerisch als **eine** Session — Stories desselben Features werden nie auf mehrere parallele Wellen verteilt (Edge-Case der Spec; keine Schwelle, `docs/specs/feature-batch-orchestration.md` v2 AC1).
2. **Hot-Spot-Datei-Analyse** (§0a-(a), hier über ALLE To-Do-Stories statt nur die bereiten): für jede Story die referenzierte Spec (`docs/specs/<feature>.md`) + `implements`-ACs lesen, zentrale berührte Dateien ableiten. Taucht eine Datei bei ≥ 2 Stories auf → **Hot-Spot**; diese Stories werden **nie** gemeinsam in derselben Welle parallel eingeplant (AC3, HART).
3. **Konflikt-/„heben-sich-auf"-Check** (§0a-(b)): inhaltlich widersprechende Stories (eine baut um, was eine andere voraussetzt) werden serialisiert — nie gemeinsame Welle.
4. **depends-Topologie** (§0a-(c)): eine Story startet erst in einer Welle, deren `depends` bereits in einer früheren Welle stehen (oder bereits terminal sind, `{Done, Verworfen}`). Direkte UND transitive `depends`-Beziehungen verhindern gemeinsame Wellen-Zugehörigkeit (AC3).

**Wellen bilden.** Welle 1 = alle Stories ohne offene `depends` und ohne gemeinsamen Hot-Spot/Konflikt untereinander; Welle 2 = Stories, deren `depends` ausschließlich in Welle 1 stehen (oder bereits terminal sind), usw. — bis alle To-Do-Stories eingeplant sind. `parallel` je Welle = Anzahl der Stories dieser Welle (**keine** konfigurierte Obergrenze — Owner-Entscheid, AC5); jede Gruppierung bekommt eine kurze `rationale` (welche Stories warum parallel/seriell laufen, AC5 — Owner-Sichtbarkeit).

**ID-Reservierungs-Vorbedingung (AC8, HART — kein Downgrade).** Bevor eine Welle mit **mehr als einer** Session geplant wird, deren Stories neue namespaced IDs (`BR`/`ADR`/`C`) einführen könnten (Heuristik: Spec-Abschnitt „Verträge" der jeweiligen Story-Spec erwähnt einen dieser Namespaces): prüfen, ob der Reservierungs-Mechanismus funktionsfähig ist — `scripts/board-id-reserve.sh show <erste-story-id-der-welle>` (reine Lese-Operation, kein Ledger-Diff) muss ohne harten Fehler laufen. Schlägt das fehl (Skript fehlt, kein Git-Remote erreichbar) → diese Welle mit ID-Vergabe-Risiko startet **NICHT** — Abbruch der Wellen-Ausführung mit Klartext-Diagnose (analog `id-block-reservation` AC11: „harter Abbruch statt Blind-Vergabe"; auch eine einzelne Session würde ohne funktionierende Reservierung blind vergeben und verstiesse gegen `id-block-reservation` AC9/A2 — „Board-weite `/flow`-Parität: reserviert, bevor er die ID vergibt"). **Kein** Downgrade auf `parallel: 1` als Ersatz für die fehlende Reservierung. Wellen **ohne** ID-Vergabe-Risiko (keine der Stories führt eine neue namespaced ID ein) sind von diesem Gate unberührt und laufen parallel wie geplant (AC8 gilt nur für Wellen mit Risiko). Ist die Reservierung funktionsfähig, bleibt die risikobehaftete Welle parallel — die eigentliche Reservierung passiert weiterhin lazy je Story-Session (§3a, unverändert, bestehender Solo-Pfad-Mechanismus aus [[id-block-reservation]]).

**Kein Plan bei leerem Board (AC10, deckt E1).** Liefert `board list --type story --status "To Do"` **keine** Story → **kein** `session-plan.yaml` schreiben; stattdessen die bestehende Leerlauf-Diagnose (`board ready`, [[empty-drain-diagnostics]]) unverändert ausgeben. Der Plan-Modus endet danach — kein Item-Build-Loop, kein §7.

**Plan-Artefakt schreiben (AC2).** `board/runs/session-plan.yaml` (gitignored, ephemer — analog `board/runs/<F-###>/`) im Schema:
```yaml
schema_version: 1
generated_at: '2026-07-18T06:00:00Z'   # ISO-8601 UTC, date -u +%Y-%m-%dT%H:%M:%SZ
board_ref: agent-flow                   # project_slug aus board/board.yaml
waves:
  - wave: 1
    parallel: 3
    stories: [S-101, S-103, S-107]
    rationale: 'disjunkte Dateien, keine depends untereinander'
  - wave: 2
    parallel: 1
    stories: [S-104]
    rationale: 'depends auf S-101; Hot-Spot skills/flow/SKILL.md mit S-103 → seriell'
```
Zusätzlich menschenlesbar ausgeben (analog dem bestehenden §0a-Format):
```
Wellen-Plan (board/runs/session-plan.yaml):
  Welle 1 (parallel: 3): S-101 ‖ S-103 ‖ S-107 — disjunkte Dateien, keine depends
  Welle 2 (parallel: 1): S-104 — depends auf S-101; Hot-Spot mit S-103
  Landen: immer seriell (main = eine Senke)
```

Danach endet der `--plan`-Aufruf (kein Item-Build-Loop, kein Landen). Die äußere Schleife (dev-gui Nachtwächter/ProjectDrain) liest `session-plan.yaml` und startet je Welle die geplanten `/flow`-Sessions parallel — Konsumenten-Vertrag: eine Story je Session, Wellen strikt nacheinander, Revalidierung vor jedem Wellen-Start (§0c) (AC9). Fehlt die Plan-Datei bei einem Konsumenten-Aufruf, bleibt dessen bisheriges serielle Verhalten unverändert (AC9 — die dev-gui-seitige Umsetzung ist eine separate Story im dev-gui-Repo, hier nur der Datei-Vertrag).

**Ein Schreiber je Story (AC4).** Der Plan garantiert, dass keine Story in mehr als einer Welle/Session gleichzeitig eingeplant ist (Konsequenz aus Schritt „Wellen bilden" oben — jede Story erscheint in genau einer `stories`-Liste). Die Board-Schreibregel bleibt **je Story genau ein schreibender `/flow`-Orchestrator**: parallele Sessions derselben Welle schreiben ausschließlich `board set` für die **eigene** zugeteilte Story-YAML + ihre **eigenen** Metrik-Zeilen (§2b) — nie für eine Story, die eine andere Session dieser Welle bearbeitet (Präzisierung in `docs/architecture/board-subsystem.md` §7).

## 0c. Mechanische Revalidierung vor jeder Welle (`/flow --plan`-Konsument, AC6/AC7 — kein LLM)

Vor dem Start jeder Welle (durch die äußere Schleife) wird der Plan **mechanisch** gegen den aktuellen Board-Ist-Stand geprüft: `scripts/board-plan-validate.sh board/runs/session-plan.yaml <wave-nummer>`. Reines Bash/Python, **kein** LLM-Lauf (AC6):
- Story nicht mehr `To Do` (`Done`/`Verworfen` = erfüllt; andere Nicht-To-Do-Status bereits anderweitig behandelt) → aus der Welle entfernt (`REMOVED <id> (<status>)`).
- `depends` nicht terminal (Blocked-Vorgänger o. Ä.) → Story dieser Welle übersprungen, `WAITING <story>: wartet auf <dep> (<status>)` gemeldet (deckt A1 — eine während einer Welle geblockte Story stoppt nur ihren Abhängigkeits-Ast, nicht die ganze Abarbeitung).
- Story-ID aus dem Plan referenziert **keine** existierende Story mehr (`board show` liefert „nicht gefunden") → grob invalider Plan; das Skript bricht mit Exit 2 + Klartext-Diagnose ab — die äußere Schleife bricht den Drain ab, statt still weiterzulaufen (Edge-Case „Plan veraltet").
- Sonst → `READY: S-### S-### …` (die tatsächlich zu startenden Sessions dieser Welle).

Die äußere Schleife startet ausschließlich die in `READY` gelisteten Stories als parallele `/flow`-Sessions (eine Story je Session, Session-Rotation unverändert, [[flow-session-rotation]]).

**Landen bleibt seriell (AC7).** Der Plan-Mechanismus erzwingt keine parallelen Merges — jede Story landet über den bestehenden §5-Mechanismus (`scripts/board-ship.sh`, first-come, seriell, Rebase vor jedem Merge). Der Plan dokumentiert keine Land-Reihenfolge vorab.

---

## 1. Nächstes Item wählen
- `board next` → die nächste bereite Story als JSON (`id`, `spec`, `implements`, `parent`, `labels`, `priority`); Queue-Logik (Priority, Depends-Gate) lebt in der CLI.
- Aus dem JSON die **Spec-Referenz** lesen: `spec: docs/specs/<feature>.md` + `implements: [AC…]` — die reichst du an coder/reviewer/tester durch (Source of Truth, nicht der Story-Titel).
- **Leere Ausgabe → nie stumm (Spec [`docs/specs/empty-drain-diagnostics.md`](../../docs/specs/empty-drain-diagnostics.md) AC3/AC4):** statt sofort zu stoppen oder direkt zu §7 überzugehen, zuerst `board ready` aufrufen (Klartext, kein Agent-Dispatch, kein Board-Schreibvorgang — token-frei) und dessen Ausgabe auf `WAITING <kategorie> (<n>): …`-Zeilen (Aggregat-Block) prüfen:
  - **≥1 `WAITING …`-Zeile vorhanden** (A1 — es gibt To-Do-Stories, aber keine ist ready): dem User explizit melden: `nichts abarbeitbar — Gründe:` gefolgt von den `WAITING …`-Zeilen im Klartext (AC4).
  - **Keine `WAITING …`-Zeile** (E1 — keine To-Do-Stories oder alle bereits ready, nur die `Summary:`-Zeile): kein Aggregat zu melden, Verhalten unverändert.
  - In beiden Fällen danach weiter zu **7. Abschluss-Deploy** (AC3 — der Diagnose-Schritt ersetzt den Übergang nicht, er geht ihm nur voraus).

> **Terminale Status — `Done` und `Verworfen` (Spec `docs/specs/story-status-verworfen.md` AC6).** Die terminale Menge ist `{Done, Verworfen}`. Stories mit Status `Verworfen` (bewusst nicht mehr umgesetzt — Scope gestrichen/überholt) sind **terminal** und werden vom `/flow`-Loop **nie** als offenes To-Do aufgegriffen — das folgt bereits aus `board next` (Kandidaten sind ausschließlich `To Do`, `Verworfen` ist ausgeschlossen; AC4). Für Fortschritts-/Rollup-Zwecke zählt `Verworfen` wie `Done` als **abgeschlossen/nicht-aktiv**, aber **nie als erfolgreich**: `done_at` und der `done/total`-Zähler bleiben ausschließlich `Done` vorbehalten (`board rollup` weist Verworfenes separat aus, AC5). **Kein `/flow`-Statusübergang erzeugt `Verworfen`** — das ist eine bewusste Owner-/GUI-Entscheidung (kein Loop-Ausgang; Single-Writer `BOARD_WRITER=flow` bleibt unverändert).

### 1a. A-priori-Grössenklasse + `ep_est` (Spec `metrics-estimation` AC1–AC3/AC8/AC10, §2b)

> **Konsument zuerst (v2, AC8/V8):** `/flow` liest die bei Story-Anlage von **requirement** geschriebenen Schätzfelder (`size_est`, `dispo_est`, `confidence`, `estimate_note`, `tok_est`) aus der Story-YAML. Sind die Felder vorhanden → **übernehmen, nicht überschreiben** (kein erneuter estimator-Dispatch, keine Neuberechnung). Fehlen die Felder (Alt-Story / manuell angelegtes Item ohne Schätzfelder) → **Fallback**: `/flow` führt die §1a-Heuristik selbst durch (Rückwärtskompatibilität, AC10). Fehler → `size_est = "M"`, `ep_est = null`, kein Loop-Abbruch (K3).

**Schritt A — Felder aus Story-YAML lesen (Konsument-Pfad, AC8):**

Lese die Story-YAML (`board/stories/<story-id>.yaml`) und prüfe, ob `size_est` gesetzt ist (nicht `null`, nicht leer):

- **`size_est` gesetzt:** übernehme `size_est`, `dispo_est` und `tok_est` unverändert als Session-Variablen (`tok_est` fehlt bei Alt-Stories vor `apriori-token-estimate` → Session-Variable bleibt `null`, kein Fehler, AC5). Schritt B und C entfallen vollständig — requirement hat bereits geschätzt. Weiter mit §2 (In Progress).
- **`size_est` fehlt oder ist `null`:** → **Fallback-Pfad** (Alt-Story / manuell angelegtes Item). Führe Schritt A-Fallback, B und C aus.

**Schritt A-Fallback — Heuristik (token-frei, deterministisch; nur wenn `size_est` fehlt):**

Zähle aus Item-Body + referenzierter Spec (`docs/specs/<feature>.md`):
- `n_ac` = #Acceptance-Kriterien (Zeilen die mit `- **AC` beginnen oder AC-Nummerierung tragen)
- `n_comp` = #genannter Komponenten/Dateien (grobe Zählung: Pfade, Agenten, Scripts im Item-Body)
- `label_bump` = +1 für jedes der Labels `db`, `security`, `ui` am Board-Item (max +3)

**Roher Score:** `score = n_ac + n_comp + label_bump`

**Mapping Score → Grössenklasse** (Schwellen fixiert, Spec `metrics-estimation` AC1):

| Score | `size_est` |
|---|---|
| 0–3   | `S` |
| 4–7   | `M` |
| 8–12  | `L` |
| ≥ 13  | `XL` |

**Schritt B — estimator-Dispatch nur bei L/XL (Fallback-Pfad; AC1, nur wenn `size_est` aus Story-YAML fehlte):**

Wurde `size_est` als `L` oder `XL` eingestuft — oder wurde `--estimate` explizit übergeben — dispatche den **`estimator`-Agenten** (Task). `S`/`M` überspringen diesen Schritt vollständig (keine LLM-Runde).

**Übergabe an estimator** (via Task-Tool, `agents/estimator.md`):
```
STORY: <story-id>           # z.B. S-023
SIZE_EST: <L|XL>
SPEC: docs/specs/<feature>.md (AC<…>)
COST_MODE: <aktiver Cost-Mode>
```
Der estimator liest selbst die Story-YAML, die Spec, `knowledge/reference-stories.md`,
`baseline.json` und `items.jsonl` (Few-shot-Retrieval S1). Er gibt zurück:
```json
{ "dispo_est": <float|null>, "tok_est": <int|null>,
  "confidence": "high|medium|low", "estimate_note": "<1-2 Sätze>",
  "split_suggestion": null|{ "into": <n>, "rationale": "<text>" } }
```

**Empfang und Sofort-Persistenz** (fehlerresistent, blockiert nie den Loop) — dies ist zugleich die **estimator-Übernahme-Stelle** für `tok_est` (Spec `apriori-token-estimate` AC3):

1. Parse das JSON-Objekt aus dem estimator-Output. Schlägt das Parsen fehl → `dispo_est_from_estimator = null`, `tok_est_from_estimator = null`, `estimate_note_from_estimator = "estimator-Dispatch fehlgeschlagen"`, `confidence_from_estimator = "low"`.
2. Speichere `dispo_est_from_estimator` (float|null) und `tok_est_from_estimator` (int|null) als Session-Variablen (für Schritt C unten). **Präzedenz (AC3, Verträge `apriori-token-estimate`): der estimator-Wert für `tok_est` hat Vorrang vor jedem requirement-Baseline-Lookup** — läuft der estimator (L/XL), wird sein `tok_est` unverändert übernommen und übersteuert einen etwaigen älteren Baseline-Lookup-Wert (die eigentliche Baseline-Lookup-Berechnung findet für L/XL ohnehin nicht statt, s. `agents/requirement.md` Schritt B2, der denselben Skip aus Symmetriegründen anwendet).
3. Persistiere sofort via `board set` (alle mit `|| true` — fehlende Story-YAML oder CLI-Fehler blockieren nie):
```bash
board set <story-id> dispo_est "$dispo_est_from_estimator"        || true
board set <story-id> tok_est   "$tok_est_from_estimator"          || true
board set <story-id> estimate_note "$estimate_note_from_estimator" || true
board set <story-id> confidence "$confidence_from_estimator"       || true
```
4. Liegt eine `split_suggestion` vor (nicht null): gib sie in der laufenden Session als informativen Hinweis aus (ändere das Board **nicht** — rein beratend, AC6).
5. *(Metrik: §2b-Touchpoint — T0 vor Dispatch setzen; nach Handoff `scripts/metrics-append-dispatch.sh` aufrufen: Agent-Rolle `estimator`, `gate: null`.)*

**Schritt C — Mapping size_est → ep_est (AC3; Fallback-Pfad; nur wenn `size_est` aus Story-YAML fehlte):**

**Bei `L`/`XL`** (estimator wurde dispatcht): `ep_est = dispo_est_from_estimator` (direkt übernehmen, kann `null` sein — erwarteter Zustand bei Cold-Start oder Fehlerpfad). **Schritt C-Lookup unten entfällt** für L/XL (estimator ersetzt die Heuristik-Tabelle).

**Bei `S`/`M`** (kein estimator): Lese `${METRICS_ROOT}/.claude/metrics/baseline.json` (falls vorhanden — Spec [`docs/specs/metrics-repo-anchor.md`](../../docs/specs/metrics-repo-anchor.md) AC2, `${METRICS_ROOT}` aus §0, kein relativer Pfad). Lookup-Reihenfolge:

1. Exakter Schnitt: `medians["<lang>|<cost_mode>|<size_est>"]` → `ep_est = medians[key].ep`
2. Fehlt exakter Schnitt: aggregiere alle Einträge mit passendem `<lang>|<cost_mode>` unabhängig von Size → Median der `.ep`-Werte dieser Gruppe.
3. Fehlt auch das: globaler Median aller `.ep`-Werte in `medians` → `ep_est`.
4. Keine `baseline.json` vorhanden oder alle `.ep`-Werte `null`/leer → `ep_est = null` (erwarteter Zustand bis genug Historie).

Wenn `medians[key].n` < 3: Schnitt vorhanden aber dünn — trotzdem verwenden (kein spezieller Fallback), aber intern notieren (kein User-Output nötig).

**Session-Variablen nach §1a** (beide Pfade, für §2b-Done):

`ep_est` (und `size_est`) als Session-Variable merken → beim Done in `items.jsonl` eintragen (§2b unten).
- **Konsument-Pfad (size_est vorhanden):** `ep_est` = `dispo_est` aus Story-YAML (für L/XL) resp. kein erneuter Lookup (Wert aus requirement bereits korrekt); für S/M direkt `dispo_est` aus Story-YAML als `ep_est` verwenden.
- **Fallback-Pfad:** `ep_est` aus Schritt C wie oben.

`tok_est` als eigene Session-Variable merken (Spec `apriori-token-estimate` AC4) → beim Done in `items.jsonl` eintragen (§2b unten).
- **Konsument-Pfad (size_est vorhanden):** `tok_est` = `tok_est` aus der Story-YAML (Schritt A, von requirement geschrieben — bzw. `null` bei Alt-Story ohne das Feld, AC5).
- **Fallback-Pfad:** `tok_est` = `tok_est_from_estimator` (L/XL, Schritt B) bzw. `null` (S/M — kein Baseline-Lookup für `tok_est` im Fallback-Pfad implementiert; optionales Feld, `null` ist erwartet, kein Fehler).

## 2. In Progress
- `board set <story-id> status "In Progress"` — setzt die Story auf In Progress.
- `board set <story-id> branch "feat/<story-id>-<slug>"` — setzt den Branch-Namen in der Story-YAML (AC7). Branch-Konvention: `feat/` + Story-ID + kurzer Slug aus dem Titel.

## 2a. Secret-Sync-Gate (Spec [`docs/architecture/secrets-subsystem.md`](../../docs/architecture/secrets-subsystem.md) §9)

Das Secret-Sync-Gate ist **Teil des regulären `reviewer`-Laufs** (Abschnitt 6a in `agents/reviewer.md`) — kein separater Agent-Dispatch. Der Reviewer prüft im normalen Build-Loop, ob der Diff env-Variablen einführt ohne `.env.example`/`.env.gpg` nachzuziehen. Keine Änderung am Dispatch-Ablauf nötig.

## 2b. Metrik-Erfassung — Ledger-Touchpoints (Spec [`docs/architecture/metrics-subsystem.md`](../../docs/architecture/metrics-subsystem.md) §2–§4, [`docs/specs/metrics-recording-reliability.md`](../../docs/specs/metrics-recording-reliability.md))

> **Einziger Schreiber:** Nur `/flow` schreibt `${METRICS_ROOT}/.claude/metrics/dispatches.jsonl` + `items.jsonl` — kein anderer Agent berührt diese Dateien (K2). Erfassung ist deterministische Arithmetik, **~0 zusätzliche LLM-Token**. Ein Metrik-Fehler blockiert nie den Loop und verändert kein Gate (K3) — aber er wird **sichtbar gemeldet** (Hinweis mit Ursache), nie stumm verschluckt. K3 rechtfertigt Nicht-Blockieren, nicht Unsichtbarkeit (Vorfall: `tok` blieb 2026-07-02..-07-17 über 345 Dispatches null, ohne einen einzigen Hinweis).

### Ledger-Verzeichnis
Alle Ledger leben **ausschließlich** unter `${METRICS_ROOT}/.claude/metrics/` (Spec [`docs/specs/metrics-repo-anchor.md`](../../docs/specs/metrics-repo-anchor.md) AC2 — `${METRICS_ROOT}` aus §0, kein relativer Pfad, kein erneutes `rev-parse`, kein `${CLAUDE_PLUGIN_ROOT}`-basierter Pfad). Bei Bedarf `${METRICS_ROOT}/.claude/metrics/` anlegen (falls nicht vorhanden). Schreiben **ausschließlich append-only** (`>>` / `jq -c . >> datei`). Historische Zeilen werden nie gelöscht oder umgeschrieben (Ausnahme: späterer `tok`-Patch durch `metrics-token-collect`).

### Vor jedem Agent-Dispatch (coder / reviewer / dba / tester / cicd / estimator)
```bash
T0=$(date -u +%s)
SEQ=$(( SEQ + 1 ))   # laufende Dispatch-Nummer innerhalb des Items, ab 1
```
Diesen Wert für den nachfolgenden Dispatch-Schlusspunkt merken; `SEQ` zu Beginn jedes Items auf 0 initialisieren.

### Nach jedem Agent-Dispatch — eine Zeile nach `dispatches.jsonl`

Aus dem Klartext-Handoff deterministisch zählen (**kein** zweiter LLM-Lauf):

| Feld | Quelle |
|---|---|
| `ts` | `date -u +%Y-%m-%dT%H:%M:%SZ` |
| `item` | **String** `S-###` — kanonische Board-ID (AC2, V2: identisch zur File-Board-ID, keine int-Konvertierung) |
| `seq` | laufende Dispatch-Nummer **innerhalb** des Items (ab 1 hochzählen) |
| `agent` | `coder` \| `reviewer` \| `dba` \| `tester` \| `cicd` \| `estimator` |
| `iter` | N aus `Review-Handoff … (Iteration N)`; bei nicht-Loop-Rollen die zugehörige Iteration |
| `gate` | `PASS` \| `CHANGES-REQUIRED` \| `FAIL` \| `SKIPPED-*` \| `null` (rollen-abhängig) |
| `crit` | #Einträge unter `## Critical` (nur reviewer/dba; sonst 0) |
| `imp` | #Einträge unter `## Important` (nur reviewer/dba; sonst 0) |
| `rule_hits` | Regel-ID-Tags aus den Befunden (z.B. `["coder/R01"]`); keine Tags → `[]` |
| `secs` | `$(date -u +%s) − T0` |
| `tok` | `null` (Phase 0; Befüllung durch `metrics-token-collect`) |
| `cost_mode` | aktiver Cost-Mode dieses Laufs |

Fehlender / nicht parsbarer Marker → Feld `null` / `0` / `[]`, **nie raten**. Zeile wegschreiben, auch wenn einzelne Felder `null` sind.

**Aufruf (benannter Touchpoint, V1):**
```bash
# Nach jedem Dispatch — Beispiel coder, Iteration 1:
METRICS_ROOT="$METRICS_ROOT" METRIC_CRIT=0 METRIC_IMP=0 METRIC_RULE_HITS='[]' \
bash "${CLAUDE_PLUGIN_ROOT}/scripts/metrics-append-dispatch.sh" \
  "$STORY_ID" "coder" "$SEQ" "$ITER" "null" "$(($(date -u +%s) - T0))" "$COST_MODE" >&2 || true
```
Für **reviewer/dba/tester** stattdessen den echten Gate-Wert übergeben (z.B. `"PASS"`, `"CHANGES-REQUIRED"`, `"FAIL"`, `"SKIPPED-*"`) und `METRIC_CRIT`/`METRIC_IMP`/`METRIC_RULE_HITS` aus dem Handoff befüllen.
Das `|| true` stellt sicher, dass ein Skript-Fehler den Loop nicht abbricht (K3, AC3).

`STORY_ID` = kanonische Story-ID als String `S-###` (z.B. `"S-014"`, nicht `14`). **Werkzeug-Pfad: das Skript liegt im Plugin und wird über `${CLAUDE_PLUGIN_ROOT}/scripts/…` aufgerufen** (Spec `metrics-repo-anchor` AC6). Der **Ledger-Pfad** kommt getrennt davon aus der Env-Variable `METRICS_ROOT` (in §0 ermittelt) — das Skript schreibt ausschließlich nach `${METRICS_ROOT}/.claude/metrics/` und prüft vorher `${METRICS_ROOT}/board/board.yaml` (AC4). Fehlt `METRICS_ROOT`, schreibt es nichts und meldet das sichtbar. So ist die Erfassung unabhängig davon, ob eine Skript-Kopie im Projekt liegt (AC6: Projekte halten keine Kopien) — das war die Ursache, dass 6 von 8 Projekten nie etwas aufzeichneten.

### Beim Done (Item → `Done`, nach Rollout-Gate: PASS) — eine Zeile nach `items.jsonl`

1. **`loc`/`files`** aus `git diff --shortstat` des Item-Diffs gegen `$default_branch`-Stand bei Item-Eintritt: `loc` = insertions + deletions, `files` = #geänderte Dateien.
2. **`blocked`** = 1 wenn das Item zwischenzeitlich den Status `NEEDS-HUMAN`, ungelöste `depends` oder manuellen Eingriff hatte, sonst 0.
3. **Schätzfelder:** `size_est` + `ep_est` aus §1a Session-Variable (Konsument-Pfad: aus Story-YAML; Fallback: §1a-Heuristik). War §1a nicht ausführbar oder ergab keinen Wert → `size_est = "M"`, `ep_est = null` (K3). `tok_est` aus §1a Session-Variable, null-sicher (Spec `apriori-token-estimate` AC4 — Konsument-Pfad: aus Story-YAML; Fallback: §1a wie oben; kein Wert → `null`). `tok_total` = `null` (Phase 0, Befüllung durch `metrics-token-collect`).
4. Das Skript `metrics-append-item.sh` übernimmt Rollup (Aggregation aller dispatch-Zeilen), EP-Berechnung und den Append.

Felder der `items.jsonl`-Zeile (subsystem §2.2):

| Feld | Wert |
|---|---|
| `ts` | Done-Zeitstempel (ISO-8601 UTC) |
| `item` | **String** `S-###` — kanonische Board-ID (AC2, V2: kein int-Präfix-Strip) |
| `size_est` | aus §1a Session-Variable — Konsument-Pfad: aus Story-YAML (von requirement geschrieben); Fallback-Pfad: §1a-Heuristik; Default `"M"` |
| `ep_est` | aus §1a Session-Variable — Konsument-Pfad: `dispo_est` aus Story-YAML; Fallback S/M: Baseline-Lookup, L/XL: `dispo_est` vom estimator; `null` wenn kein Wert |
| `tok_est` | aus §1a Session-Variable — Konsument-Pfad: `tok_est` aus Story-YAML (von requirement geschrieben); Fallback L/XL: `tok_est` vom estimator, S/M: `null` (kein Lookup implementiert); `null` wenn kein Wert (Spec `apriori-token-estimate` AC4) |
| `ep_act` | EP nach EP-Formel (§3 subsystem); `metrics-append-item.sh` berechnet intern |
| `iters` | max `iter` der Dispatches |
| `crit` | Σ `crit` |
| `imp` | Σ `imp` |
| `test_fails` | #`Test-Gate: FAIL` |
| `rule_hits` | Vereinigung aller Regel-IDs |
| `loc` | insertions + deletions (shortstat) |
| `files` | #geänderte Dateien (shortstat) |
| `tok_total` | `null` (Phase 0) |
| `secs_total` | Σ `secs` |
| `blocked` | 0 \| 1 |
| `lang` | `profile.lang` (`language:`-Wert aus `.claude/profile.md`) |
| `cost_mode` | aktiver Cost-Mode |

**Aufruf (benannter Touchpoint, V1):**
```bash
# Shortstat für loc/files
SHORTSTAT="$(git diff --shortstat "$BASE_SHA" HEAD 2>/dev/null)" || SHORTSTAT=""
LOC=$(printf '%s' "$SHORTSTAT" | grep -oE '[0-9]+ insertion' | grep -oE '[0-9]+' || echo 0)
LOC=$(( LOC + $(printf '%s' "$SHORTSTAT" | grep -oE '[0-9]+ deletion' | grep -oE '[0-9]+' || echo 0) ))
FILES=$(printf '%s' "$SHORTSTAT" | grep -oE '[0-9]+ file' | grep -oE '[0-9]+' || echo 0)

METRICS_ROOT="$METRICS_ROOT" bash "${CLAUDE_PLUGIN_ROOT}/scripts/metrics-append-item.sh" \
  "$STORY_ID" "${SIZE_EST:-M}" "${EP_EST:-null}" "$LOC" "$FILES" \
  "${BLOCKED:-0}" "${LANG:-md}" "${COST_MODE:-balanced}" "${TOK_EST:-null}" >&2 || true
```
Das `|| true` stellt sicher, dass ein Skript-Fehler den Loop nicht abbricht (K3, AC3). Auch hier: **Werkzeug über `${CLAUDE_PLUGIN_ROOT}/scripts/…`, Ledger-Pfad via `METRICS_ROOT`-Env** (AC6, s.o.). `${TOK_EST:-null}` = die in §1a gemerkte `tok_est`-Session-Variable (9. Positionsparameter, optional — Alt-Aufrufe ohne diesen Parameter bleiben gültig, das Skript defaultet auf `null`, AC5).

### Self-Check beim Done (V4, AC5)

Nach dem `metrics-append-item.sh`-Aufruf prüfen, ob die Zeile tatsächlich geschrieben wurde und ob `tok_total` nach dem Token-Nachtrag befüllt ist:

```bash
# Prüfe ob items.jsonl-Zeile für STORY_ID existiert
if grep -q "\"item\":\"${STORY_ID}\"" "${METRICS_ROOT}/.claude/metrics/items.jsonl" 2>/dev/null; then ITEMS_LINE=1; else ITEMS_LINE=0; fi
if [[ "$ITEMS_LINE" -eq 0 ]]; then
  echo "HINWEIS: Metrik für ${STORY_ID} nicht erfasst — items.jsonl-Zeile fehlt. Ledger unvollständig." >&2
fi

# Prüfe ob tok_total befüllt ist (nach metrics-collect.sh)
if [[ "$ITEMS_LINE" -gt 0 ]]; then
  TOK_VAL="$(grep "\"item\":\"${STORY_ID}\"" "${METRICS_ROOT}/.claude/metrics/items.jsonl" 2>/dev/null | tail -1 | jq -r '.tok_total // "null"' 2>/dev/null || echo "null")"
  if [[ "$TOK_VAL" == "null" ]]; then
    echo "HINWEIS: tok_total für ${STORY_ID} nicht befüllt — Token-Pfad nicht auflösbar (Transcripts nicht gefunden oder CLAUDE_CONFIG_DIR falsch). EP-Metriken bleiben valide." >&2
  fi
fi
```
Diese Prüfung verändert kein Gate (K4, AC5) — sie ist nur informativ.

### Dispo-Spiegel in Story-YAML (AC6 — nach items.jsonl-Rollup)

Nach dem Append der `items.jsonl`-Zeile spiegelt `/flow` die Dispo-Ist-Werte per ID-Join in die Story-YAML zurück. Die Ledger bleiben Source of Truth; die Story-Felder sind die lesbare Sicht (board-subsystem §4.4).

**Join:** Lies `ep_act` + `tok_total` + `ep_est` aus der soeben geschriebenen `items.jsonl`-Zeile (Story-ID = `item`-Feld, String-Match `"S-###"`).

**Setze via `board set`** (drei Aufrufe, alle mit `|| true` — fehlender Join blockiert nie):
```bash
board set <story-id> dispo_act "$ep_act" || true
board set <story-id> tok "$tok_total" || true   # null → Feld bleibt null in Story-YAML
```
`dispo_forecast` nur setzen, wenn `ep_est` **nicht** `null` ist:
```bash
# dispo_forecast = (ep_est - ep_act) / ep_act  (positiv = Überschätzung, negativ = Unterschätzung)
[[ -n "$ep_est" && "$ep_est" != "null" && "$ep_act" != "0" ]] && \
  board set <story-id> dispo_forecast "$(echo "scale=4; ($ep_est - $ep_act) / $ep_act" | bc)" || true
```

Schlägt ein `board set`-Aufruf fehl → Story-Feld bleibt `null`, kein Abbruch (K3). **Kein erneuter LLM-Aufruf.**

**Commit zurückgehalten bis Session-Ende (Spec [`docs/specs/project-memory.md`](../../docs/specs/project-memory.md) AC6).** Die obigen `board set`-Schreibungen ändern die Story-YAML im Working-Tree, werden aber **noch nicht** committet/gepusht — das geschieht gebündelt als der eine Session-Ende-Board-Meta-Commit in §7 (**„Projekt-Memory kuratieren"**), zusammen mit der kuratierten `.claude/memory.md`. So existiert für den Landen-Fall **ein** Commit für Board-Meta-Felder + Memory, kein separater Zweit-Commit nur fürs Memory.

### Token-Nachtrag (out-of-band, Spec `metrics-token-collect` V4 / subsystem §4 Schritt 4)

Nach dem Append der `items.jsonl`-Zeile (`tok_total` initial `null`) sofort:

```bash
METRICS_ROOT="$METRICS_ROOT" bash "${CLAUDE_PLUGIN_ROOT}/scripts/metrics-collect.sh" "$STORY_ID" >&2 || true
```

Das Script parst die Subagent-Transcript-JSONL, summiert echte Token je Dispatch
und patcht die `tok`-Felder der betroffenen `dispatches.jsonl`-Zeilen + `tok_total`
der `items.jsonl`-Zeile (nur `null`-Felder, bestehende Werte bleiben). Matching erfolgt
über den String `S-###` im `item`-Feld (AC2 von `metrics-token-collect`). Schlägt das Script fehl oder findet es
keine Transcripts → Felder bleiben `null`, **kein Abbruch**, das Item bleibt `Done`
(K3/K4, AC3/AC4 von `metrics-token-collect`). **Werkzeug über `${CLAUDE_PLUGIN_ROOT}/scripts/metrics-collect.sh`,
Ledger-Pfad via `METRICS_ROOT`-Env** (Spec `metrics-repo-anchor` AC6); das Item-Matching in den
Subagent-Transcripts läuft über `S-<nr>` in der `description`, nie über `#<nr>` (Spec
`metrics-token-collect` V2).

**Pfad-Auflösung (AC4, V3 von `metrics-token-collect`):** `metrics-collect.sh` liest Subagent-Transcripts aus
`$CLAUDE_CONFIG_DIR/.claude/projects/<escaped-cwd>/…` (falls `CLAUDE_CONFIG_DIR` gesetzt)
bzw. `$HOME/.claude/projects/<escaped-cwd>/…`. Im GUI-/Container-Kontext muss
`CLAUDE_CONFIG_DIR` auf das korrekte Basis-Verzeichnis zeigen (z.B. `/home/user`).
Fehlt die Variable und greift `$HOME` nicht → `tok` bleibt `null`, kein Crash (K3/K4).

**`<escaped-cwd>` — beide Fälle Hauptordner/Worktree (Spec `metrics-repo-anchor` AC3):**
`<escaped-cwd>` ist der Pfad-Slug des tatsächlichen **Sitzungs-cwd der laufenden
`/flow`-Session selbst** (nicht der Ledger-Pfad, nicht der cwd eines einzelnen
dispatchten coder/reviewer) — Claude organisiert Transcripts pro Top-Level-Session
unter deren eigenem Arbeitsverzeichnis, unabhängig davon, in welchem Story-Worktree
ein dispatchter coder gearbeitet hat.
- **Fall A (Normalfall — `/flow` im Hauptordner gestartet):** `<escaped-cwd>` =
  escaped(`${METRICS_ROOT}`) — Ledger-Pfad und Transcript-Slug fallen zusammen.
- **Fall B (E1 — `/flow` selbst in einem Worktree gestartet):** `<escaped-cwd>` =
  escaped(Worktree-Pfad); da `rev-parse --show-toplevel` in diesem Sonderfall
  ebenfalls den Worktree als `METRICS_ROOT` liefert (§0, E1), fallen auch hier
  Ledger-Pfad und Transcript-Slug zusammen — beide zeigen auf den Worktree.
Der Slug wird in keinem der beiden Fälle manuell konstruiert oder erraten — er
ergibt sich aus dem tatsächlichen Prozess-cwd der `/flow`-Session zur Laufzeit.

### Datei-Hygiene (Spec V11 / subsystem §11)
- `dispatches.jsonl` + `items.jsonl`: gitignored (`.gitignore`).
- `baseline.json`: committet (von `retro` gepflegt, analog `LEARNINGS.md`).
- Kein Secret, keine Diff-Inhalte, keine Befund-Prosa im Ledger (K6).

## 3. Build-Loop (max. 3 Iterationen, N = 1..3)

> **Dossier-Injektion bei `--parent <F-###>` (AC14).** Bevor der erste coder-Dispatch dieses Items erfolgt: ist dieser Lauf mit `--parent <F-###>` gestartet, `board/runs/<F-###>/dossier.md` lesen (falls vorhanden) und dessen Inhalt als vorangestellten Kontext-Abschnitt jedem coder-/reviewer-/tester-Dispatch dieses Items voranstellen (z. B. `FEATURE-DOSSIER: <inhalt>` vor `TASK #<n>`). Fehlt die Datei → einfach kein Voranstellen, kein Fehler. Ohne `--parent` (board-weiter Lauf): dieser Schritt entfällt vollständig, keine Injektion.
>
> **Handoff-Notiz-Injektion bei `--parent <F-###>` (AC16).** Im selben Zug (vor dem ersten coder-Dispatch dieses Items) zusätzlich `board/runs/<F-###>/notes.md` lesen (falls vorhanden) und deren Inhalt ebenfalls als vorangestellten Kontext-Abschnitt voranstellen (z. B. `FEATURE-NOTES: <inhalt>` neben `FEATURE-DOSSIER:` vor `TASK #<n>`) — was frühere Storys desselben Features für die Folge-Storys hinterlassen haben. Fehlt die Datei (typischerweise bei der ersten Story des Features, E5) → einfach kein Voranstellen, kein Fehler. Ohne `--parent` (board-weiter Lauf): dieser Schritt entfällt vollständig, kein Lesen.

> **Projekt-Memory-Kontext (Spec [`docs/specs/project-memory.md`](../../docs/specs/project-memory.md) AC2/AC5).** Wurde in §0 ein `.claude/memory.md` gelesen, stellt `/flow` dessen Kern-Punkte (`## Aktueller Stand` + relevante `## Offene Fäden`) als kurzen, vorangestellten Kontext-Abschnitt (z. B. `PROJECT-MEMORY: <inhalt>`) jedem coder-/reviewer-Dispatch **dieses** Items voran — analog zu `FEATURE-DOSSIER`/`FEATURE-NOTES` oben. **Orientierung, nie Wahrheit (E1):** bei Widerspruch zwischen Memory und Board/Spec gelten Board/Spec; kein Agent leitet aus dem Memory-Kontext Anforderungen, Acceptance-Kriterien oder Gates ab — er dient nur der Einordnung („woran wurde zuletzt gearbeitet"). Fehlt die Datei → kein Voranstellen, kein Fehler.

> **Parallele Worktrees — Frische + Hot-Spot-Warnung (flow/P1).** Beim Dispatch von mehreren coder-Tasks parallel oder in schneller Folge: (a) **Worktree-Frische:** weise jeden coder an, `git fetch origin && git reset --hard origin/<default_branch>` auszuführen und das Vorhandensein erwarteter Vorgänger-Artefakte zu verifizieren, bevor er implementiert (`coder/R03`). (b) **Hot-Spot-Files:** wenn mehrere parallele Items dieselben zentralen Wiring-Dateien berühren (z. B. `server.js`-Router-Registrierung, `App.jsx`/`AppShell.jsx`-Route-/View-Map, `index.ts`-Re-Exporte), serialisiere die betreffenden Items ODER vereinbare ein append-only/Block-Konvention für diese Dateien und plane frühe Rebase-Punkte ein. (c) **Strukturelle Dauer-Kur — Hot-Spot eliminieren statt umfahren:** ein zentrales manuelles Wiring-Register (Router-Liste, View-Switch/Map, Re-Export-Sammeldatei), das wiederholt Konflikt-Brennpunkt ist, sollte durch **Konventions-/Auto-Discovery** ersetzt werden — der Loader entdeckt neue Einträge per Dateisystem-Konvention (z. B. `src/routers/*.js` mit `create(deps)`-Export, datengetriebenes `viewRegistry.js`), sodass ein neues Item nur eine **neue Datei** hinzufügt und die geteilte Sammeldatei gar nicht mehr anfasst. Das ist die nachhaltigste Form der Konflikt-Vermeidung bei Dauer-Parallelarbeit (Serialisierung/append-only sind nur Umgehungen). Migrationshinweis: bei der Umstellung ALLE bestehenden Einträge übernehmen — auch direkte Inline-Handler (`app.get`/`app.post` direkt in `server.js`), nicht nur die per `app.use(router)` montierten — sonst entfällt still ein Endpunkt. Unkontrollierte parallele Edits an Hot-Spot-Files erzeugen wiederkehrende Merge-Konflikte. *[seen-in: dev-gui-cloudflare Items #107–#111 (server.js-Router-Overlap, DeployOrchestrator-Duplikat — Problem + Serialisierung) + dev-gui Items #207/#208 (Router-Auto-Registry `src/routerLoader.js`/`src/routers/*.js` + Frontend-View-Registry `client/src/viewRegistry.js` — strukturelle Kur, ~30-Einträge-Hot-Spots eliminiert); promoted: 2026-06-09, geschärft: 2026-06-14]*

1. **coder** (Task): `TASK #<n>` · `SPEC: docs/specs/<feature>.md (AC<…>)` · `ITERATION: N` · bei N>1 die offenen `FINDINGS`. Story-Kontext: der coder liest via `board show <story-id>` (statt Issue-Body). Er editiert nur den Working-Tree (Code + ggf. kleine Spec-Präzisierung). *(Metrik: §2b-Touchpoint — T0 vor Dispatch merken; nach Handoff `metrics-append-dispatch.sh` aufrufen.)*
2. **reviewer** (Task): `git diff` + die **Spec** (`docs/specs/<feature>.md`, AC<…>). Story-Kontext: der reviewer liest via `board show <story-id>` (statt Issue-Body). *(Metrik: §2b-Touchpoint — T0 vor Dispatch merken; nach Handoff `metrics-append-dispatch.sh` aufrufen.)* Lies sein `Review-Gate`:
   - `CHANGES-REQUIRED` → Critical+Important als `FINDINGS` merken, N++ → zurück zu 3.1.
   - `PASS` → **DB-Trigger prüfen** (siehe 3.2a). Triggert er → weiter zu 3.2a; sonst → weiter zu 4.
2a. **DBA-Zweit-Review (nur bei DB-Trigger)** — Trigger gilt, wenn **eines** zutrifft (Architektur-Spec §11):
    - Board-Item hat Label `db`, ODER
    - `git diff` berührt `db_scripts/`, `docs/data-model.md`, ODER Datenzugriffscode (Heuristik: Imports von `pg`/`postgres`/`mysql2`/`mariadb`/`better-sqlite3`/`sqlite3`/`mongoose`/`mongodb`/`prisma`/`drizzle`/`supabase`).

    Dann zusätzlich **dba** (Task, Review-Modus): `git diff` + Spec + Item-Label. *(Metrik: §2b-Touchpoint — T0 vor Dispatch merken; nach Handoff `metrics-append-dispatch.sh` aufrufen.)* Lies sein `Review-Gate`:
    - `CHANGES-REQUIRED` → Critical+Important als `FINDINGS` an coder zurück, N++ → 3.1.
    - `PASS` → **beide Gates PASS** → weiter zu 4 (Tester). Pflicht: **beide** Reviews müssen PASS sagen, bevor `tester` läuft.
- **SPEC-LÜCKE:** meldet der coder eine strukturelle/Scope-Lücke (oder der reviewer/dba verweist auf `requirement`) → `board set <id> status Blocked --reason "Spec unvollständig — /requirement nötig"`, dem User melden. Nicht im Loop raten. Blocked-Ausgang (AC4): ohne `--all` weiter zu §7 (Session-Ende nach diesem Item, kein Weiterziehen).
- **Schleifenschutz:** überlebt derselbe Befund N=3 → `board set <id> status Blocked --reason "Loop-Schutz N=3 — gleicher Befund überlebt 3 Iterationen"`, melde es dem User. **Ohne `--all`:** Session-Ende — weiter zu §7 (E1/AC4), kein Weiterziehen zum nächsten Item. **Mit `--all`:** frage, ob mit den restlichen Items weiter; bei Zustimmung zurück zu 1.

## 4. Test-Gate
- **tester** (Task): Working-Tree + die **Spec** (AC<…>). Story-Kontext: der tester liest via `board show <story-id>` (statt Issue-Body). *(Metrik: §2b-Touchpoint — T0 vor Dispatch merken; nach Handoff `metrics-append-dispatch.sh` aufrufen.)* Lies `Test-Gate`:
  - `FAIL` → als Befund zurück an coder (zählt zum Schleifenschutz) → 3.1.
  - `PASS` → weiter zu 5.
  - `SKIPPED-NO-DOCKER` → **human-handoff** (kein Auto-Merge): `board set <id> status Blocked --reason "DB-Subsystem-Smoke konnte nicht laufen — Docker-Daemon fehlt; bitte lokal mit Docker oder via Remote-Host wiederholen"`, dem User melden, **nicht** zu 5. weitergehen. Wir wissen sonst nicht, ob die Template-Änderung mechanisch funktioniert. Blocked-Ausgang (AC4): weiter zu §7 (Session-Ende nach diesem Item).
  - `SKIPPED-DOC-ONLY` → äquivalent zu PASS für den Gate-Zweck (Diff ist reine Doku in `tests/db-subsystem/`, kein mechanischer Effekt) → weiter zu 5. Im Normalfall greift der Pfad-Filter in §4 unten schon und der `tester` wird gar nicht dispatcht; dieser Branch ist Defense-in-Depth, falls der `tester` doch lief.

**Template-Diff = hartes Test-Gate.** Wenn `git diff --name-only` (gegen `main`) im `agent-flow`-Repo Pfade unter `templates/_shared/db-*/**`, `templates/_shared/companion-*/**` oder `tests/db-subsystem/*.sh` (nur die Smoke-Skripte selbst, **nicht** README/Docs in dem Ordner) berührt, ist `Test-Gate: PASS` **Pflicht-Vorbedingung** für Schritt 5 — kein Bypass, auch nicht im `direct`-merge-Modus. Reine Doku-Edits (z.B. `tests/db-subsystem/README.md`) triggern das Gate **nicht** — der `tester` hat keinen Smoke für sowas und würde nur einen No-Op zurückgeben (siehe Pfad-Tabelle in `agents/tester.md`). Der `tester`-Agent dispatcht die zugehörigen Smoke-Skripte selbst (Auswahl-Regel siehe `agents/tester.md` → „DB-Subsystem-Smoke (bei Template-Diffs)"). Die früher angedachte CI-Variante (`.github/workflows/smoke-db.yml`) entfällt damit — lokaler Tester-Run ist schneller, kostet keine Actions-Minuten und scheitert nicht an leeren Org-Budgets.

## 5. Landen — deterministisches Skript statt Agent-Dispatch (L3, seit 2026-07-06)

Nach `tester`-PASS: `scripts/board-ship.sh <story-id> [<container-name>]` **direkt per Bash ausführen** (kein Task-Dispatch mehr für den SHIP-Pfad) — **läuft dieser `/flow`-Aufruf mit `--parent <F-###>` (s. Feature-Scope oben), zusätzlich `--target-branch feature/<F-###>` anhängen.** Das Skript übernimmt git-Operationen (Merge + Push), CI-Beobachtung (mit `headSha`-Race-Schutz, cicd/F06), lokalen Rollout (pull + recreate, Rollout-Verifikation gegen die tatsächlich deployte Revision — **entfällt bei aktivem `--target-branch`**, s. Skript-Doku) sowie den Board-Flip auf `Done` (via `board set`, committet + gepusht) — **rein mechanisch, kein LLM-Urteil**. Exit 0 = gelandet; Exit ≠0 = Abbruch mit Klartext-Fehlermeldung, Board bleibt unverändert (`In Review`) — dem User melden, Session-Ende nach diesem Item (kein automatischer Retry).

**Warum ein Skript statt eines Agenten (L3, Owner-Auftrag 2026-07-06):** Der SHIP-Schritt ist rein deterministische Arbeit (mergen, pushen, CI-Status abfragen, Rollout, YAML-Feld setzen) — ideale Bedingungen für ein Skript, denn ein Skript **behauptet nichts, es prüft**. Auslöser: Ein `cicd`-Agent behauptete am 2026-07-06 fälschlich, eine Story sei „schon gelandet" (Verwechslung mit einem älteren Commit), führte daraufhin `git pull` aus und löschte damit 9 fertige, ungecommittete Dateien unwiderruflich (S-047-Vorfall). `board-ship.sh` ersetzt dieses Urteil durch eine mechanische Prüfung (`git merge-base --is-ancestor`) und einen Guard, der vor jedem `git fetch/pull/reset` den Working-Tree auf uncommittete Änderungen prüft und bei Funden abbricht statt zu raten (L6-Guard, `tests/board-ship/run-test.sh` deckt beides testfixture-basiert ab). `cicd` als Agent bleibt für `rollback`/`ci-fix`/`version-stamp` zuständig — Trigger, die echtes Urteilsvermögen brauchen (Diagnose einer roten CI, Entscheidung über einen Rollback) und sich nicht rein mechanisch abbilden lassen; siehe `agents/cicd.md`.

- **Post-Rebase-Verifikation (flow/P2):** Nach jeder Rebase- oder Konfliktauflösung — und bevor das Item auf `Done` gesetzt wird — MUSS der volle Test-Run gegen den **finalen main-Stand** bestätigt werden (nicht nur gegen den isolierten Worktree). cicd's CI-Watch (Schritt 3 der ship-Sequenz, `gh run watch` gegen `main`) deckt das im Normalfall ab; bei **lokaler Konfliktauflösung** zusätzlich `profile.build`/`tester` direkt gegen den post-merge `main`-Stand ausführen. Ein Konfliktlöser, der „Tests grün" nur im Worktree-Kontext bestätigt, kann einen main-Stand mit roten Tests hinterlassen (umgeschriebene Tests kommen nicht sauber an / Mismatch Implementierung↔Test). *[seen-in: dev-gui-cloudflare Rebase nach Items #109/#110 (3 rote Tests auf main nach Konfliktauflösung); promoted: 2026-06-09]*

**SHIP-TRIGGER:**
```
SHIP-TRIGGER: #<n> tester-PASS — bitte landen, CI beobachten, lokal ausrollen
BRANCH: item-<n>-<slug>
MERGE_POLICY: <aus profile.merge_policy>
IMAGE: <profile.image>:latest
```

**Repo-versionierte Meta-Dateien fahren IMMER mit (Belt, Spec [`docs/specs/flow-lessons-landing.md`](../../docs/specs/flow-lessons-landing.md) AC3).** Der SHIP-TRIGGER instruiert cicd **nicht mehr**, „nur" die konkreten Implementierungs-/Test-Dateien zu landen. Jede im Story-Worktree geänderte, **getrackte** `.claude/lessons/*.md` fährt **immer** mit der Landung mit — auch wenn sie in der Dateiliste nicht namentlich auftaucht. Das ist der Gürtel zum Enforcement-Floor in `cicd` (Abschnitt A0/AC1/AC2, Hosenträger): coder/reviewer/tester prependen ihre Lessons in den Worktree, und ohne dieses Mitlanden gingen sie beim Worktree-Teardown (SR1) spurlos verloren. Die Garantie hängt **nicht** am Gedächtnis des Orchestrators — der Floor liegt in cicd; diese Zeile ist der explizite Belt.

**Was cicd dabei tut (Abschnitt A in `agents/cicd.md`):**
- **Getrackte `.claude/lessons/*.md`-Deltas im selben Commit/PR** — Enforcement-Floor (A0), immer mitgelandet; cicd meldet `Lessons: <n> Datei(en) gelandet | keine` (AC8). Konflikt am Datei-Anfang → additive newest-first-Union (A1a/AC5), kein Eintrag verloren/dupliziert. Gitignored (wie agent-flow selbst) → kein Zwangs-Add, kein Fehler (AC6).
- **Code UND etwaige `docs/specs/`-Deltas im selben Commit/PR** — zusammen oder gar nicht (Drift-Gate-Prinzip, CONCEPT §4d).
- **`direct`-Policy:** merge + push auf `$default_branch`.
- **`pr`-Policy:** Branch pushen + PR öffnen (Fork-sicher: `gh pr create --repo "$repo" --base "$default_branch"` — `$repo` via origin-URL aufgelöst). cicd erstellt den PR, merged ihn NICHT selbst → Orchestrator/User mergt; anschliessend Rollout via `/cicd rollout` oder weiter-getriggertem `ship`.
  - **Sonar:** Beim Fabrik-Default (monatlich + manuell) kein per-PR-`sonar.yml`-Run → **kein Warten**. Opt-in-Blockgate: s. Abschnitt in der alten §5-Logik (unverändert).
- **CI-Watch:** `gh run watch` bis Abschluss. Rot → Rollout unterbleibt, `Rollout-Gate: FAIL`.
- **Lokaler Rollout:** `docker pull` + `docker rm -f` + `docker run`.
- **Disk-Hygiene:** `docker image prune -f` (Pflicht).
- Commit-Message endet mit der `Co-Authored-By`-Zeile (von cicd ausgeführt).

**Orchestrator nach cicd-Rückgabe:**
- `Rollout-Gate: PASS` → `board set <id> status Done` (+ PR/Commit verlinkt) + Test-URL melden. *(Metrik: §2b-Touchpoint „Beim Done" — `metrics-append-item.sh` aufrufen + Self-Check + Token-Nachtrag via `metrics-collect.sh`.)*
- `Rollout-Gate: FAIL` → melden + `board set <id> status Blocked --reason "CI rot oder Smoke fehlgeschlagen"`, User fragen.
- `Rollout-Gate: NEEDS-HUMAN` → `board set <id> status Blocked --reason "Manueller Eingriff nötig"`, User vorlegen.

Bei `pr`-Policy und ausstehemdem Merge: `board set <id> status "In Review"` (Orchestrator wartet auf Merge-Signal, dann Done). Zusätzlich: `board set <id> pr "<pr-url>"` — setzt die PR-URL in der Story-YAML (AC7); cicd liefert die URL in seiner Rückgabe.

**Handoff-Notiz schreiben (AC15, nur bei aktivem `--parent <F-###>`).** Nach `Rollout-Gate: PASS` (Story erfolgreich gelandet, s.o.) hängt `/flow` **3–5 Zeilen** an `board/runs/<F-###>/notes.md` an — append-only, bestehende Notizen bleiben unverändert erhalten (`mkdir -p board/runs/<F-###>/` falls der Ordner noch fehlt, dann `>>`). Inhalt: was diese Story gebaut hat + was die nächste Story desselben Features wissen muss (z. B. „neue Schnittstelle X statt Y nutzen", geänderte Annahmen, Fallstricke). Kurzer Klartext-Block, kein Agent-Dispatch — der Orchestrator formuliert die Zeilen selbst aus dem bereits vorliegenden Handoff von coder/reviewer/tester dieses Items (kein zusätzlicher LLM-Aufruf). Ohne `--parent` (board-weiter Lauf): dieser Schritt entfällt vollständig, keine Notiz.

**ID-Block-Freigabe (Solo-Pfad, `docs/specs/id-block-reservation.md` AC9/AC10, nur OHNE `--parent`).** Läuft dieser `/flow`-Aufruf board-weit (kein `--parent <F-###>`), ruft `/flow` nach `Rollout-Gate: PASS` **immer** `scripts/board-id-reserve.sh release <story-id>` auf (Scope-Schlüssel = die eigene `S-###`) — analog zur Freigabe am Feature-Ende in `board-feature-drain.sh` (dort nach dem finalen Merge). Idempotent/gefahrlos, auch wenn die Story in §3a **keine** neue namespaced ID eingeführt und daher nie reserviert hat (`release` liefert dann ein leeres `[]` zurück, kein Fehler). Ein Fehlschlag ist **nicht fatal** — die Story ist bereits erfolgreich gelandet; ein Ledger-Cleanup-Fehler macht das nicht rückgängig (Klartext-Hinweis, kein Blockieren):
```bash
scripts/board-id-reserve.sh release "$STORY_ID" >/dev/null \
  || echo "⚠ ID-Reservierungs-Freigabe für ${STORY_ID} fehlgeschlagen (nicht fatal — Ledger bleibt mit aktivem Eintrag stehen)." >&2
```
Ohne diesen Schritt bliebe jede Solo-Reservierung (§3a-Vertrag oben) dauerhaft `active` und würde nie freigegeben — im Gegensatz zum `--parent`-Feature-Pfad, den `board-feature-drain.sh` am Batch-Ende freigibt. Mit `--parent <F-###>` (Feature-Batch-Lauf): dieser Schritt entfällt hier vollständig — die Freigabe erfolgt gebündelt am Feature-Ende durch `board-feature-drain.sh` (s. dessen Doku), nicht je Story.

## 5a. Validate-Flag-Invalidierung (Spec [`docs/architecture/db-subsystem.md`](../../docs/architecture/db-subsystem.md) §18)
**Nach erfolgreichem Landen** prüfen, ob der gerade gelandete Diff den Validate-Cache invalidiert:

**Trigger.** Eines davon trifft zu:
1. Item-Diff ändert `profile.db_dialect` oder `profile.companions[]` (`yq` vor/nach vergleichen).
2. Item-Diff berührt Pfade, die das **gepullte** Template-Snapshot ersetzen würden: `db_scripts/run-migrations.sh`, `db_scripts/000_init_meta.{sql|js}`, `docker-compose.yml` Diff-Lines innerhalb der `# --- db-<dialect> (…)`- oder `# --- companion-<name> (…)`-Sektion.
3. Plugin-Update wurde gepullt: `git -C "$CLAUDE_PLUGIN_ROOT" log -1 --format=%H templates/_shared/db-<dialect>/` ≠ der in `.claude/profile.md` notierten `adoption_validated_plugin_sha` (falls dort getrackt — best-effort, fehlender Wert = kein Trigger).

**Aktion bei Trigger.**
- `adoption_validated_at: null` in `.claude/profile.md` setzen (Key bleibt — explizites null statt löschen, damit der "wurde mal validiert"-Audit-Trail nicht verloren geht; `/preview` Cache-Check liest `validated_at: null` und fällt auf `CACHE_HIT=false`).
- `adoption_validated_dialect` und `adoption_validated_companions` **unverändert lassen** (Audit-Trail: was war zuletzt validiert).
- **Diesen Profile-Edit als Folge-Commit** auf demselben Branch/PR landen (`chore: invalidate adoption_validated_at (db-setup changed)`) — vor dem `gh pr create` aus §5 oder als amend, falls schon committed.
- Klar-Output:
  ```
  ⚠ DB-Setup geändert (item #<n>) — adoption_validated invalidated.
    Re-validation läuft beim nächsten /preview up (mini, best-effort)
    oder explizit via /adopt re-validate.
  ```

**Kein Trigger.** Items, die nur App-Code/Doku ändern (kein DB-/Companion-Profile-Diff, kein Template-Pfad), lassen das Flag unangetastet — Cache bleibt valide.

## 6. Nächstes (Spec [`docs/specs/flow-session-rotation.md`](../../docs/specs/flow-session-rotation.md) AC1/AC3/AC4)

- **Default (ohne `--all`, auch headless):** Nach dem vollständigen Abschluss GENAU EINER Story (Done geschrieben + gelandet + Worktree abgebaut) bzw. eines SR1-Parallel-Batches (alle Storys des Batches gelandet oder einzeln geblockt, s. SR1 unten) endet diese Runde — weiter zu §7 (Abschluss). Kein automatisches Aufnehmen eines weiteren Items im selben Lauf. Rationale: Ø Cache-Read wuchs in einer 13-Story-Session von 82k auf 298k Token (Faktor 3,6, Messung 2026-07-02) — Rotation hält das Kontext-Wachstum über ein Board linear statt quadratisch; die äußere Schleife (dev-gui `ProjectDrain`, Nachtwächter) übernimmt die Rotation.
- **Blocked-Ausgang (E1, AC4):** Endet das gewählte Item/Batch in Blocked (Loop-Schutz, SPEC-LÜCKE, `SKIPPED-NO-DOCKER`, Rollout-Gate FAIL/NEEDS-HUMAN), endet die Runde ebenso mit der bestehenden Blocked-Meldung — weiter zu §7, kein Weiterziehen zum nächsten Item.
- **Mit `--all` (interaktives Opt-in, A1):** Zurück zu 1, bis das Board leer ist oder der User stoppt (bisheriges Verhalten). Bei Blocked: User fragen, ob mit den restlichen Items weiter; bei Zustimmung zurück zu 1.

## 7. Abschluss (Spec [`docs/specs/flow-session-rotation.md`](../../docs/specs/flow-session-rotation.md) AC2)

Erreicht **nach jeder Runde**: Default (ohne `--all`) nach genau einem Item/Batch aus §6; mit `--all` erst wenn das Board leer ist oder der User stoppt.

### Projekt-Memory kuratieren (Spec [`docs/specs/project-memory.md`](../../docs/specs/project-memory.md) AC3–AC6, letzter Schritt jeder Session)

**Trigger (AC3, HART):** genau einmal, als erster Schritt dieses Abschlusses — unabhängig davon, ob das Item/der Batch **gelandet** ist (`Rollout-Gate: PASS` bzw. gemergter PR) oder **Blocked** endete (SPEC-LÜCKE, Loop-Schutz, `SKIPPED-NO-DOCKER`, Rollout-Gate FAIL/NEEDS-HUMAN). **SR1-Parallel-Batch:** dieser Schritt läuft **einmal am Batch-Ende**, nicht je paralleler Story — `/flow` fasst alle gelandeten/geblockten Storys des Batches in einer Kurations-Runde zusammen.

**Kuratieren (AC3/AC4, HART — neu schreiben, nicht anhängen):**
1. Ausgangsbasis: das in §0 gelesene `.claude/memory.md` (falls vorhanden); fehlt die Datei (Bestandsprojekt ohne Memory, A2), das leere Gerüst aus `templates/_shared/memory.md` als Startpunkt.
2. `## Aktueller Stand` (max. 10 Zeilen Prosa) auf den Stand **nach** dieser Runde bringen — Alltagssprache, was gerade läuft/ansteht.
3. `## Letzte Arbeiten` (rollierend, max. 10 Einträge, neueste zuerst): einen neuen Eintrag für diese Story/diesen Batch voranstellen (`<S-### / 1–2 Sätze>`); erledigte/überholte/nicht mehr relevante ältere Einträge **löschen**, nicht nur anhängen — reines Anhängen ohne Sichtung verletzt AC3.
4. `## Offene Fäden` (optional, max. 5 Einträge): bekannte Stolpersteine/aufgeschobene Entscheidungen. Bei **Blocked**-Ausgang hier 1–2 Sätze ergänzen, woran es hängt + was der nächste sinnvolle Schritt wäre (A1).
5. **Deckel durchsetzen (AC4):** Gesamt-Datei ≤ 60 Zeilen. Überschreitet die kuratierte Fassung das Limit → zusammenfassen/kürzen statt überschreiten; ältere „Letzte Arbeiten"-Einträge fliegen zuerst.
6. **Kopfzeilen-Hinweis unverändert beibehalten (AC5):** die ersten zwei Zeilen (`> Orientierung, nie Wahrheit: …` / `> Kuratiert von /flow …`) sind Teil des Gerüsts und werden beim Kuratieren nie entfernt.

**Persistenz (AC6 — Session-Ende-Board-Meta-Commit, kein eigener zweiter Commit-Mechanismus):** `.claude/memory.md` fährt **nicht** im Landungs-Commit von `cicd`/`board-ship.sh` mit (§5) — die Landung ist zu diesem Zeitpunkt bereits abgeschlossen, die Kuration läuft erst danach (s. Main-Success-Scenario-Schritt 3/4 der Spec). Stattdessen nutzt `.claude/memory.md` denselben, bereits vorgesehenen Session-Ende-Commit für Board-Meta-Felder:

- **Landen-Fall:** die Dispo-Spiegel-Felder aus §2b liegen zu diesem Zeitpunkt noch **uncommittet** im Working-Tree vor (s. dortigen Hinweis „Commit zurückgehalten bis Session-Ende"). `.claude/memory.md` staged in denselben `git add` wie die geänderten Story-YAML-Dateien und committet/pusht direkt auf dem frischen `origin/<default_branch>`-Stand in **einem** Commit (`chore(board): <story-id oder Batch> dispo mirror + memory`). Kein separater `chore(memory): …`-Commit. Fehlt aus irgendeinem Grund ein Dispo-Spiegel-Delta (z. B. Metrik-Erfassung diese Session übersprungen, `METRICS_ROOT`-Gate in §0), committet `.claude/memory.md` als minimaler eigener Board-Meta-Commit nach demselben Namensmuster (`chore(board): <story-id oder Batch> memory`) — bleibt der einzige Fallback, kein dauerhaft paralleler Mechanismus.
- **Blocked-Fall:** die `.claude/memory.md`-Änderung wird **im selben Commit** geführt wie der `board set … status Blocked …`-Schreibvorgang (kein zusätzlicher Commit) — analog zum etablierten `board: <story-id> Blocked (<grund>)`-Commit-Muster.

`.claude/memory.md` ist **kein** Teil des `cicd`-Lessons-Floors (Spec [[flow-lessons-landing]] AC1–AC3, `agents/cicd.md` Abschnitt A0): jener deckt ausschliesslich `.claude/lessons/*.md`, die bereits **vor** der Landung im Story-Worktree entstehen. Memory entsteht strukturell erst danach und geht deshalb den eigenen, oben beschriebenen Weg — außer im dokumentierten Ausnahmefall (`agents/cicd.md` A0), dass ein Memory-Delta ausnahmsweise schon vor der Landung im Worktree vorliegt.

**Fehlerfall (K3):** Scheitert das Kuratieren (IO/git) → **kein** Session-Abbruch, aber eine sichtbare Meldung (analog Lessons-Landing) — der zuvor gesetzte Done-/Blocked-Status der Story bleibt davon unberührt.

**Orientierung, nie Wahrheit (AC5, deckt E1):** Widerspricht das gelesene Memory dem Board/der Spec, gelten Board/Spec — dieser Kurations-Schritt korrigiert den veralteten Memory-Inhalt; kein Agent leitet aus dem Memory Anforderungen oder Gates ab.

### 7a. Board-Status-Ausgabe (AC2)
Vor dem Stoppen `board next` (Klartext, token-frei, kein Agent-Dispatch) UND `board ready --quiet` erneut aufrufen, um den verbleibenden Board-Zustand zu bestimmen:
- **Liefert `board next` ein Item:** melden — `Board nicht leer — noch <n> abarbeitbare(s) Item(s), nächster Lauf nimmt voraussichtlich <id>.` (`<n>` = Anzahl bereiter Items aus `board ready --quiet`, `<id>` = das von `board next` gelieferte Item). Exit-Code bleibt 0 (Erfolgs-Ende, kein Abbruch — s. Spec [`docs/specs/flow-session-rotation.md`](../../docs/specs/flow-session-rotation.md) „Verträge").
- **Liefert es nichts (Board leer):** unverändert die Leerlauf-Diagnose aus §1 (`board ready` + WAITING-Aggregat, Spec [`docs/specs/empty-drain-diagnostics.md`](../../docs/specs/empty-drain-diagnostics.md)).

### 7b. Deploy — wenn Rollout aufgeschoben wurde

Hinweis: Wenn §5 den cicd-`ship`-Modus ausführt (Standard, `profile.deploy == docker`), sind CI-Watch + Rollout + Prune bereits in der ship-Sequenz enthalten. Dieser Unterabschnitt ist dann nur eine abschliessende Zusammenfassung. Er gilt für Konfigurationen, in denen §5 keinen automatischen Rollout auslöst (z.B. `deploy != docker`) oder wenn der Rollout aufgeschoben wurde.

Nur wenn diesem Lauf mindestens ein Item gelandet ist **und** `profile.deploy == docker` **und** kein Rollout in §5 bereits stattgefunden hat:

**cicd-`ship` wurde in §5 bereits ausgeführt (Standard):** Rollout-Gate-Ergebnis aus §5 übernehmen; hier nur Test-URL melden und stoppen.

**Rollout in §5 aufgeschoben (Ausnahme):**
1. **`cicd`-Agent** (Task) dispatchen:
   ```
   SHIP-TRIGGER: bitte landen (falls noch nicht), CI beobachten, lokal ausrollen
   BRANCH: <aktueller Stand>
   MERGE_POLICY: <aus profile>
   IMAGE: <profile.image>:latest
   ```
   Lies `Rollout-Gate`:
   - `PASS` → **Test-URL** aus cicd-Output melden (inkl. Version + Prune-Ergebnis).
   - `FAIL` → melden + überspringen (Hinweis auf `/cicd ship`), Flow NICHT scheitern lassen.
   - `NEEDS-HUMAN` → melden, User vorlegen.
2. **Dev-Preview-Variante** (Mac-Loop, kein produktiver Rollout gewünscht, `DEPLOY_ROLE=local`): die `up`-Logik aus dem **`preview`-Skill** ausführen (`docker pull "${image}:latest"` → `docker run … -p <preview_port>:<container_port>` → Smoke) → **Test-URL** melden. Prune: `docker image prune -f` danach trotzdem ausführen.
   - **Faustregel:** `DEPLOY_ROLE=vps` → cicd-`ship`; `local` ohne expliziten Rollout-Wunsch → preview-Skill + manuelles prune.
3. **Best-effort:** CI rot/Timeout oder Pull `denied` → melden + überspringen, Flow NICHT scheitern lassen (Hinweis auf `/cicd ship` bzw. `/preview up`).

Dann stoppen mit Zusammenfassung (gelandete Items + Test-URL + Version + 7a-Board-Status).

## Strategie-Regeln

### SR1 — Parallel-Abarbeitung (AC2)
- Stories mit **disjunkten** Dateien (kein gemeinsamer Hot-Spot aus §0a) laufen **parallel** in isolierten git-Worktrees (ein coder je Worktree, `coder/R03`).
- Stories mit **geteilten Hot-Spot-Dateien** laufen **seriell** — Reihenfolge aus §0a-Plan.
- **Landen ist immer seriell:** `main` ist die eine Senke; zwischen zwei PRs wird jeweils ein Rebase auf den aktuellen `main`-Stand durchgeführt (Post-Rebase-Verifikation: s. `flow/P2` in §5).
- **Worktree-Teardown erst NACH bestätigter Landung (Reihenfolge-Garantie, Spec [`docs/specs/flow-lessons-landing.md`](../../docs/specs/flow-lessons-landing.md) AC7):** Ein isolierter Story-Worktree (`.claude/worktrees/<story-id>`) wird erst per `git worktree remove --force` entfernt, **nachdem** cicd die Landung bestätigt hat (`Rollout-Gate: PASS` bei `direct`, bzw. gemergter PR bei `pr`). Da cicd die getrackten `.claude/lessons/*.md`-Deltas als Teil des Landungs-Commits/PR führt (Enforcement-Floor A0, AC1/AC4) und der Teardown der Landung **nachgelagert** ist, kann `git worktree remove --force` keine noch nicht committete Lessons-Änderung mehr verschlucken. Kein Teardown vor bestätigter Landung — sonst geht das Lessons-Delta verloren, bevor es committet ist.
- **Test-Isolation:** parallele Worktrees müssen aus Test-Auswahl UND Modul-Auflösung ausgeschlossen sein (jest: `testPathIgnorePatterns` + `modulePathIgnorePatterns` für `.claude/worktrees/`) — sonst Cache-Vergiftung oder rote Tests auf `main`. Details: §3 `flow/P1`.

### SR2 — Feature-Branch-Strategie (AC3)
- **Schwelle ≥ 3 Stories pro Feature:** einen Feature-Branch `feature/<F-###>` anlegen. Alle Stories des Features landen dort (je Story ein PR in den Feature-Branch); am Ende **ein** Merge des Feature-Branches in `main`. Vorteil: zusammenhängendes Review/CI je Feature, weniger `main`-Churn.
- **< 3 Stories:** je Story ein PR direkt in `main` (einfacher, heute Standardpraxis).
- Die Schwelle gilt pro Feature (nicht über Features hinweg); gemischte Features auf demselben Board können unterschiedliche Strategien fahren.

### SR3 — Abarbeitungs-Hygiene (AC4)
- **board-Status persistent:** `board set … Done` muss via PR in `main` landen — **gebündelt** mit dem Story-Code-PR (gleicher Commit/PR). Lose `board set`-Aufrufe ohne Landing gehen bei `reset` verloren.
- **Image-Build/Deploy gebündelt am Feature-Ende:** CI-Run + `docker recreate` sind teuer; nicht pro Story auslösen, sondern einmalig am Feature-Ende (oder bei `deploy: docker` via §5 `cicd`-Ship nach dem letzten Story-PR des Features).
- **Cross-Repo-Markierung:** Stories, deren Code in einem anderen Repo lebt (z. B. agent-flow-Logik vs. dev-gui-Anzeige), klar im Board markieren (Label oder `spec`-Verweis auf das Subsystem-Repo). Spec liegt beim Subsystem; Tracking auf dem Board.
- **Review-Gate bei Parallelität nicht überspringen:** parallele coder übersehen eher sicherheitsrelevante Details (Erfahrung: Path-Traversal-Befund in parallelem Lauf). Gerade bei Parallel-Dispatches adversarial reviewen — kein PASS ohne vollständigen Reviewer-Durchlauf (§3).

---

## Grenzen
- NUR der Orchestrator schreibt Board-Status; cicd führt die git-Abschluss-Operationen (merge+push) und den Rollout im Auftrag des Orchestrators aus (Delegation via SHIP-TRIGGER).
- Bei Unklarheit oder `Blocked`: dem User vorlegen, nicht raten.
- **Rote Tests NIE als „pre-existing/fremd/nicht mein Scope" abtun ohne Ursachenverifikation.** Ein `Test suite failed to run` / Loader-Parse-Fehler in einer Datei, die kein Item dieses Laufs geändert hat, ist meist ein **Umgebungs-Artefakt** (vergifteter Test-Cache, Haste-Map-Duplikate aus den parallelen Worktrees) — kein fremder Code-Bug. Erst Cache leeren + erneut laufen (`knowledge/js.md` `js/R07`; tester §2a), dann werten. Ein gelandeter „grüner" Lauf darf nie auf einem **maskierten** Symptom beruhen (z.B. den verschmutzten Pfad nur aus der Test-*Auswahl* ausschließen, aber die Wurzel — Modul-/Cache-Vergiftung — stehen lassen).
- **Worktree-Parallelität sauber halten:** Bei isolierten Worktrees (§3-Parallelfälle) sicherstellen, dass der Test-Runner die Worktree-Verzeichnisse aus **Test-Auswahl UND Modul-Auflösung** ignoriert (jest: `testPathIgnorePatterns` + `modulePathIgnorePatterns` für `.claude/worktrees/`). Sonst zieht ein Lauf fremde, teils rote Tests anderer Branches mit und/oder vergiftet den geteilten Cache. Wer Parallel-Worktrees anlegt, verantwortet auch deren Test-Isolation — ein dadurch verursachter roter `main` ist nicht „fremd".
- **Validate-Flag (§5a) nur invalidieren, nicht setzen:** das Setzen von `adoption_validated_at` lebt ausschließlich in `/adopt` §6 (volle Validation mit Coder-Fix-Loop) und `/preview` §6 (Mini-Re-Validate). `/flow` invalidiert nur — kein eigenes Dispatch des `tester` für Adoption-Validate (würde den Build-Loop §3 verzerren).
