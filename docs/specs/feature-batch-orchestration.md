---
id: feature-batch-orchestration
title: Feature-Batch-Orchestrierung — eine Merge/ein Deploy pro Feature statt pro Story
status: active
version: 2
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
   Feature **mindestens 1** Kind-Story hat. Nur `0` Storys ist ein echter
   Fehlerfall (kein Ziel zum Abarbeiten). **Ist-Verhalten seit Commit #295**
   (Owner-Entscheidung 2026-07-06, zweite Korrektur — angeglichen an das
   Skript): die frühere 2er-Schwelle (und die noch ältere SR2-Schwelle von 3)
   ist ersatzlos entfernt — der Bündel-Weg gilt für 1 Story genauso wie für 30,
   kein Sonderfall.
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

### v2 — Kontext-Vererbung & Orchestrator-Sichtbarkeit (Feature-Batch v2)

Grundsatz unverändert: Board- und Feature-Ebene bleiben **rein
deterministisch** (kein lebender LLM-Kontext — Lehre aus dem cicd-Vorfall
S-047), LLM nur auf Story-Ebene und für die **eine** einmalige
Dossier-Erzeugung. Bewusst **verworfen** (nicht Teil dieser Spec): lebende
LLM-Orchestratoren, parallele Features, Feature-PRs.

7. **Feature-Kontext-Dossier (einmalig, klein):** Zu Beginn eines
   Feature-Drains — **bevor** die erste Story-Session startet (Phase
   `dossier`) — erzeugt **genau eine** einmalige, kleine
   `claude -p`-Session `board/runs/<F-###>/dossier.md`. Inhalt: Feature-Ziel,
   betroffene Specs + AC-Nummern, Abhängigkeiten und sinnvolle Reihenfolge der
   Storys, Architektur-Hinweise, bekannte Fallen. Das Dossier wird **einmal**
   pro Feature-Drain erzeugt (nicht pro Story) und existiert danach nur noch
   lesend. Schlägt die Erzeugung fehl, läuft der Drain ohne Dossier weiter
   (best-effort, nie blockierend) — die Story-Sessions arbeiten dann wie in v1.
8. **Dossier-Injektion:** Jede Story-Session bekommt das Dossier beim Start
   injiziert: `/flow` liest bei **aktivem `--parent <F-###>`** die Datei
   `board/runs/<F-###>/dossier.md` (falls vorhanden) und stellt sie ihrem
   Kontext voran, statt dass jede Story den Gesamtkontext neu zusammensucht.
   Ohne `--parent` (board-weiter Lauf): keine Injektion, Verhalten wie v1.
9. **Handoff-Notizen (Aufwärts-Meldung Story→Feature als Datei):** Am **Ende**
   jeder Story-Session hängt `/flow` (bei aktivem `--parent`) **3–5 Zeilen** an
   `board/runs/<F-###>/notes.md` an: was gebaut wurde, was die nächste Story
   wissen muss (z.B. „neue Schnittstelle X statt Y nutzen"). Spätere Storys
   desselben Features lesen `notes.md` beim **Start** mit (zusätzlich zum
   Dossier). Das ist die Weitergabe als **Datei**, nicht als lebender Kontext.
10. **Run-State fürs Cockpit (`state.yaml`):** Der Feature-Drain schreibt und
    aktualisiert bei **jedem** Phasenwechsel `board/runs/<F-###>/state.yaml`
    (Schema s. Verträge — bindender Vertrag, u.a. für dev-gui). Phasen:
    `dossier` → `story` → `merge` → `rollout`. Felder: aktuelle Story-ID,
    Fortschritt (`done`/`total`), Runde, Startzeit, letzter Fehler.
    `board/runs/` ist **gitignored** (ephemer, kein Commit von Run-Artefakten).
    dev-gui liest die Dateien über den Workspace-Mount und zeigt sie live an
    (SSE) — **das ist NICHT Teil dieses Repos** (dev-gui bekommt eigene
    Storys); hier zählt nur, dass das `state.yaml`-Schema präzise und
    verbindlich ist.
11. **Last-Run-Eindampfung:** Nach **erfolgreichem** finalen Merge (Schritt 6)
    wird der Run-Ordner `board/runs/<F-###>/` zu einem **kompakten
    Last-Run-Protokoll** eingedampft: `state.yaml` mit Endphase (`rollout`
    abgeschlossen), Fortschritt `total/total`, Endzeit — die
    Zwischen-Arbeitsdateien (laufende dossier-/notes-Rohstände, die für einen
    späteren Lauf keinen Wert mehr haben) werden auf das Protokoll reduziert.
    Da `board/runs/` gitignored ist, betrifft das nur den Working-Tree/Mount,
    nie die Git-Historie.

## Acceptance-Kriterien

- **AC1** — Schwelle: `board-feature-drain.sh` mit **0** Kind-Storys bricht mit
  einer klaren Meldung ab (`Feature … hat keine Storys.`), ohne irgendeinen
  Branch anzulegen oder Git-Zustand zu verändern. Ab **1** Story läuft der
  Batch-Modus. **Angeglichen an das Ist-Verhalten des Skripts** (Commit #295):
  die frühere „< 2"-Schwelle ist entfernt — 1 Story ist kein Sonderfall mehr,
  sondern der reguläre (dann triviale) Bündel-Weg. Die ältere Formulierung
  „verweist auf den normalen `/flow`-Lauf" gilt damit nicht mehr.
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

<!-- v2 — Kontext-Vererbung & Orchestrator-Sichtbarkeit (neu angehängt, AC1–AC8 unverändert) -->

- **AC9** — Run-State-Anlage & -Aktualisierung: `board-feature-drain.sh` legt
  zu Drain-Start `board/runs/<F-###>/state.yaml` an und aktualisiert es bei
  **jedem** Phasenwechsel (`dossier` → `story` → `merge` → `rollout`) sowie bei
  jedem Runden-/Story-Wechsel (Feld `current_story`, `progress`, `round`,
  `updated_at`). Tritt ein Fehler/Exit ≠ 0 auf, wird `last_error` mit einer
  Klartext-Zeile gesetzt, bevor das Skript endet.
- **AC10** — `state.yaml`-Schema-Vertrag: die geschriebene Datei enthält **exakt**
  die in den Verträgen definierten Felder mit den zulässigen Werten
  (`phase ∈ {dossier, story, merge, rollout}`; `progress` als `done`/`total`
  Ganzzahlen; ISO-8601-Zeitstempel; `current_story` ist `S-###` oder `null`;
  `last_error` ist String oder `null`). Das Schema ist der **bindende Vertrag**
  für dev-gui — Feldnamen/Enums werden nicht ohne Spec-Änderung verändert.
- **AC11** — `board/runs/` ist **gitignored**: weder `state.yaml`, `dossier.md`,
  `notes.md` noch das Last-Run-Protokoll erscheinen jemals in `git status`
  als zu committende Änderung; der Feature-Drain committet **keine**
  Run-Artefakte (weder in den Feature-Branch noch nach `<default_branch>`).
- **AC12** — Last-Run-Eindampfung: nach dem erfolgreichen finalen Merge
  (AC6) wird `board/runs/<F-###>/` auf ein kompaktes Last-Run-Protokoll
  reduziert (`state.yaml` mit abgeschlossener Endphase, `progress = total/total`,
  Endzeit). Ein erneuter Drain-Start desselben Features überschreibt das
  Protokoll mit einem frischen Run (kein Anhäufen alter Rohstände).
- **AC13** — Dossier-Erzeugung (einmalig): zu Drain-Start (Phase `dossier`,
  **vor** der ersten Story-Session) erzeugt **genau eine** `claude -p`-Session
  `board/runs/<F-###>/dossier.md` mit Feature-Ziel, betroffenen Specs +
  AC-Nummern, Story-Reihenfolge/Abhängigkeiten, Architektur-Hinweisen und
  bekannten Fallen. Wird das Dossier pro Drain **nur einmal** erzeugt (nicht
  pro Story); ein Fehlschlag ist best-effort und **blockiert den Drain nicht**.
- **AC14** — Dossier-Injektion: bei aktivem `--parent <F-###>` liest `/flow`
  zu Story-Start `board/runs/<F-###>/dossier.md` (falls vorhanden) und stellt
  es dem Kontext voran. Ohne `--parent` erfolgt **keine** Injektion
  (board-weites Verhalten unverändert, vgl. AC8).
- **AC15** — Handoff-Notiz schreiben: am Ende jeder Story-Session hängt `/flow`
  (bei aktivem `--parent`) **3–5 Zeilen** an `board/runs/<F-###>/notes.md` an
  (angehängt, bestehende Notizen bleiben erhalten) — was gebaut wurde + was die
  nächste Story wissen muss.
- **AC16** — Handoff-Notiz lesen: spätere Story-Sessions desselben Features
  lesen bei aktivem `--parent` zu Story-Start `board/runs/<F-###>/notes.md`
  mit (zusätzlich zum Dossier aus AC14). Fehlt die Datei (erste Story), ist das
  kein Fehler.

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
  kein Urteilsvermögen nötig. **Ausnahme (v2):** die **eine** einmalige
  Dossier-Erzeugung ist eine kurze `claude -p`-Session — sie ist
  best-effort/nicht-blockierend und ändert nichts an der Determinismus-Garantie
  der Auswahl-/Merge-Logik (das Dossier ist reiner Lese-Kontext, kein
  Steuersignal für die Schleife).

### `state.yaml`-Schema (v2 — bindender Vertrag, u.a. für dev-gui)

Pfad: `board/runs/<F-###>/state.yaml` (gitignored, ephemer). Der
Feature-Drain ist **alleiniger Schreiber**; dev-gui liest nur. Feldnamen und
Enum-Werte sind verbindlich — Änderungen nur über eine Spec-Fortschreibung.

```yaml
schema_version: 1            # int — Schema-Version dieses Vertrags
feature_id: F-025            # F-### — Feature, das dieser Run abarbeitet
phase: story                 # enum: dossier | story | merge | rollout
current_story: S-057         # S-### der gerade laufenden Story, oder null
progress:                    # Fortschritt done/total (Ganzzahlen)
  done: 2
  total: 3
round: 3                     # int — aktuelle Schleifen-Runde (1..50)
started_at: '2026-07-07T09:00:00Z'   # ISO-8601 — Drain-Startzeit
updated_at: '2026-07-07T09:42:00Z'   # ISO-8601 — letzte Aktualisierung
last_error: null             # String (Klartext-Diagnose) oder null
```

- **`phase`** durchläuft `dossier` (einmalige Dossier-Erzeugung) → `story`
  (Story-Sessions in der Schleife) → `merge` (finaler Feature→default-Merge) →
  `rollout` (einmaliges Rollout, nur bei `profile.deploy == docker`).
- **`progress.done`/`.total`**: `total` = Anzahl Kind-Storys; `done` = Anzahl
  terminaler (Done/Verworfen) Kind-Storys. Nach erfolgreicher Eindampfung gilt
  `done == total`.
- **`current_story`**: `null` außerhalb der `story`-Phase.
- **`last_error`**: bei Exit 3 (Blockade/Wartet) bzw. Exit 1 (Fehler) die
  entsprechende Klartext-Zeile; sonst `null`.

### Run-Artefakte (v2)

- `board/runs/<F-###>/dossier.md` — einmaliger, kleiner Feature-Kontext
  (nur-lesend nach Erzeugung; AC13/AC14).
- `board/runs/<F-###>/notes.md` — angehängte Handoff-Notizen Story→Feature
  (append-only innerhalb eines Runs; AC15/AC16).
- **`.gitignore`**: `board/runs/` ist ignoriert (AC11) — keine Run-Artefakte
  in der Git-Historie.

## Abhängigkeiten

- [[board-areas]] (Depends-Gate, Priority-Sortierung von `board next`)
- Ersetzt/erweitert den `L3`-SHIP-Pfad aus dem 2026-07-06-Vorfall (S-047,
  `git pull`-Datenverlust) — dieselbe `guard_clean_or_die`-Absicherung gilt
  in allen drei Modi.

## Edge-Cases

- **E1 — Feature mit genau 1 Story:** **kein** Sonderfall mehr (Ist-Verhalten
  seit Commit #295) — der Batch-Modus läuft normal durch (ein Feature-Branch,
  eine Story-Session, ein finaler Merge/Rollout). Nur `0` Storys wird
  verweigert (AC1). Die frühere „ab 2 Storys"- bzw. SR2-„ab 3"-Schwelle ist
  ersatzlos entfernt (Owner-Entscheidung 2026-07-06, zweite Korrektur).
- **E2 — Story-Konflikt zwischen zwei Feature-Storys:** fällt beim
  CI-Lauf auf dem Feature-Branch auf (Modus B beobachtet CI, s. Verhalten
  Schritt 4) — nicht erst beim finalen Merge nach `main`.
- **E3 — Feature-Branch existiert bereits mit fremdem Inhalt** (z.B. von
  einer vorherigen, abgebrochenen Bündelung): wird unverändert
  weiterverwendet (AC2) — kein automatisches Löschen/Zurücksetzen (L6-Guard-
  Prinzip: nie destruktiv ohne explizite Prüfung).
- **E4 — Dossier-Erzeugung schlägt fehl** (z.B. `claude -p`-Timeout, kein
  Token): der Drain läuft ohne `dossier.md` weiter (best-effort, AC13); die
  Story-Sessions arbeiten dann wie in v1 (kein Kontext-Prefix). `last_error`
  in `state.yaml` darf den Fehlgrund vermerken, blockiert aber nicht.
- **E5 — `notes.md` fehlt bei der ersten Story:** kein Fehler (AC16) — die
  erste Story hat naturgemäß keine Vorgänger-Notiz; sie **schreibt** ihre
  eigene Notiz für die Folgestorys (AC15).
- **E6 — Abgebrochener Run (kein erfolgreicher Merge):** `board/runs/<F-###>/`
  wird **nicht** eingedampft (AC12 greift nur nach erfolgreichem Merge) — der
  nächste Drain-Start desselben Features überschreibt `state.yaml`/`dossier.md`
  mit einem frischen Run. Da alles gitignored ist, entsteht kein Git-Rest.
- **E7 — dev-gui liest `state.yaml` während eines Schreibvorgangs:** der
  Feature-Drain schreibt `state.yaml` atomar (Temp-Datei + `mv`, wie die
  übrige Board-CLI), damit ein Leser nie eine halb geschriebene Datei sieht.
