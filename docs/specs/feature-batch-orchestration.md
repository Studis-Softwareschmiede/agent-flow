---
id: feature-batch-orchestration
title: Feature-Batch-Orchestrierung — eine Merge/ein Deploy pro Feature statt pro Story
status: active
version: 1
spec_format: use-case-2.0
---

# Spec: Feature-Batch-Orchestrierung (`feature-batch-orchestration`)

> **Schicht 3 von 3.** Testbares **Verhalten + Verträge**.

## Zweck

Ohne Bündelung landet und deployt jede Story eines Features einzeln — bei
einem Feature mit 10 Storys: 10 Merges, 10 CI-Läufe, 10 Docker-Rollouts
(Owner-Beobachtung 2026-07-06). Diese Spec führt eine dritte, **rein
deterministische** Orchestrierungs-Ebene zwischen der äußeren Board-Schleife
(dev-gui `ProjectDrain`/Nachtwächter) und der Story-Ebene (`/flow`) ein:
`scripts/board-feature-drain.sh` arbeitet alle Storys eines Features
nacheinander ab, jede landet nur in einem gemeinsamen Feature-Branch, und
erst nach der letzten Story passiert **ein einziger** Merge nach `main` +
**ein einziges** Rollout.

## Verhalten

1. `board-feature-drain.sh <F-###> [<container-name>]` prüft zuerst, ob das
   Feature **mindestens 2** Kind-Storys hat. Bei weniger verweigert es sich
   mit klarer Meldung (kein Bündelungsvorteil bei 0–1 Storys) — der normale
   `/flow`-Lauf bleibt der richtige Weg.
2. Existiert `feature/<F-###>` noch nicht remote, wird er von
   `origin/<default_branch>` abgezweigt.
3. Schleife: `board next --parent <F-###>` liefert die nächste bereite Story
   (dieselbe Priority-/Depends-Gate-Logik wie board-weit, nur auf das
   Feature beschränkt). Für jede gefundene Story wird eine **frische**
   `claude -p /agent-flow:flow --parent <F-###>`-Sitzung gestartet (eigener,
   kleiner Kontext — Session-Rotation-Prinzip aus `flow-session-rotation.md`
   bleibt unverändert, nur auf Feature-Scope verengt).
4. Ist `--parent <F-###>` aktiv, ruft `/flow` in seinem SHIP-Schritt
   `board-ship.sh <story-id> [<container>] --target-branch feature/<F-###>`
   auf: die Story landet im Feature-Branch, **kein** Rollout für diese
   Einzel-Story, CI (Lint/Test) läuft dort dennoch mit (Sicherheit —
   Konflikte zwischen Storys fallen sofort auf, nicht erst am Feature-Ende).
5. Nach jeder Runde: sind alle Kind-Storys terminal (Done/Verworfen) →
   Schleifenende, weiter zu 6. Ist keine Story mehr "bereit", aber mindestens
   eine nicht-terminal (typischerweise Blocked) → **Exit 3** mit
   Klartext-Diagnose ("BLOCKIERT: <id>:<status>, …") — das GANZE Feature
   wartet, kein Timeout, kein Teil-Deploy der bereits fertigen Storys
   (Owner-Entscheidung 2026-07-06).
6. `board-ship.sh --merge-feature feature/<F-###> [<container>]`: **ein**
   Merge (nicht Squash — die einzelnen Story-Commits bleiben sichtbar) nach
   `<default_branch>`, **eine** CI-Beobachtung, **ein** Rollout mit
   Rollout-Verifikation gegen die tatsächlich deployte Image-Revision. Kein
   Board-Flip nötig — alle Storys wurden bereits einzeln in Schritt 4
   geflippt (im Feature-Branch committet, wandert mit dem Merge nach `main`).

## Acceptance-Kriterien

- **AC1** — Schwelle: `board-feature-drain.sh` mit < 2 Kind-Storys bricht mit
  einer Meldung ab, die auf den normalen `/flow`-Lauf verweist, ohne
  irgendeinen Branch anzulegen oder Git-Zustand zu verändern.
- **AC2** — Feature-Branch-Anlage: existiert `feature/<F-###>` remote noch
  nicht, wird er von `origin/<default_branch>` abgezweigt; existiert er
  bereits, wird er unverändert weiterverwendet (idempotent).
- **AC3** — Pro Story: `board next --parent <F-###>` liefert dieselbe
  Priority-/Depends-Gate-Sortierung wie `board next` board-weit, nur gefiltert
  auf `parent == <F-###>`. Story landet via `board-ship.sh --target-branch`
  im Feature-Branch — `origin/<default_branch>` bleibt dabei unverändert.
- **AC4** — Blockade: bleibt eine Story nicht-terminal ohne bereit zu sein
  (Blocked o.ä.), endet `board-feature-drain.sh` mit Exit 3 und einer Zeile
  `BLOCKIERT: <id>:<status>[,…]` — `origin/<default_branch>` bleibt
  unverändert (kein Teil-Deploy der bereits fertigen Storys).
- **AC5** — Fortschritts-Verifikation (L7-Prinzip): bleibt dieselbe Story
  nach einem vollen `/flow`-Lauf unverändert `To Do`, bricht das Skript mit
  einer Verdachtsmeldung ab, statt bis zur Obergrenze (50 Runden) blind
  weiterzulaufen.
- **AC6** — Finaler Merge: sind alle Kind-Storys terminal, macht
  `board-ship.sh --merge-feature` **genau einen** Merge-Commit nach
  `<default_branch>` (normaler Merge, nicht Squash), beobachtet CI genau
  einmal, rollt genau einmal aus (nur bei `profile.deploy == docker`).
- **AC7** — Idempotenz: ein erneuter Aufruf von `board-feature-drain.sh`
  nach vollständig gelandetem Feature erkennt "bereits vollständig enthalten"
  und erzeugt **keinen** neuen Commit, **keinen** erneuten Rollout.
- **AC8** — `/flow --parent <F-###>` (ohne dieses Skript direkt aufgerufen)
  bleibt board-weit kompatibel: ohne `--parent` unverändertes Verhalten
  (`board next`/`board ready` ungefiltert, Landen direkt nach
  `<default_branch>`).

## Verträge

- **Board-CLI-Erweiterung:** `board next [--parent <F-###>]` und
  `board ready [--quiet] [--parent <F-###>]` — additive, optionale Filter;
  ohne das Flag identisches Verhalten zu vorher (Rückwärtskompatibilität,
  s. `tests/board-cli` Test 24c).
- **`board-ship.sh`-Erweiterung (drei Modi, s. Skript-Kopfkommentar):**
  Modus A (Story → `default_branch`, unverändert seit L3), Modus B
  (Story → `--target-branch <branch>`, kein Rollout), Modus C
  (`--merge-feature <branch>` → `default_branch`, kein Board-Flip).
- **Kein neuer LLM-Agent:** Die Feature-Ebene ist ein reines Bash/Python-
  Skript (`board-feature-drain.sh`) — dieselbe Begründung wie bei L3
  (`board-ship.sh`): die Auswahl-/Schleifen-/Merge-Logik ist rein mechanisch,
  kein Urteilsvermögen nötig.

## Abhängigkeiten

- [[board-areas]] (Depends-Gate, Priority-Sortierung von `board next`)
- Ersetzt/erweitert den `L3`-SHIP-Pfad aus dem 2026-07-06-Vorfall (S-047,
  `git pull`-Datenverlust) — dieselbe `guard_clean_or_die`-Absicherung gilt
  in allen drei Modi.

## Edge-Cases

- **E1 — Feature mit genau 1 Story:** kein Bündelungsvorteil, Skript
  verweigert sich (AC1). Owner-Entscheidung 2026-07-06: Schwelle ist
  "immer ab 2 Storys", nicht die ältere SR2-Schwelle von 3.
- **E2 — Story-Konflikt zwischen zwei Feature-Storys:** fällt beim
  CI-Lauf auf dem Feature-Branch auf (Modus B beobachtet CI, s. Verhalten
  Schritt 4) — nicht erst beim finalen Merge nach `main`.
- **E3 — Feature-Branch existiert bereits mit fremdem Inhalt** (z.B. von
  einer vorherigen, abgebrochenen Bündelung): wird unverändert
  weiterverwendet (AC2) — kein automatisches Löschen/Zurücksetzen (L6-Guard-
  Prinzip: nie destruktiv ohne explizite Prüfung).
