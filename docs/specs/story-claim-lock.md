---
id: story-claim-lock
title: Claim-Lock vor Story-Start (Duplicate-Dispatch-Race beheben)
status: active
version: 1
spec_format: use-case-2.0
area: flow-orchestrierung
---

# Spec: Claim-Lock vor Story-Start  (`story-claim-lock`)

> **Schicht 3 von 3.** Testbares **Verhalten + Verträge**, sprach-/paradigma-unabhängig (Intent, keine Idiome/Klassen).
> **Source of Truth** für `coder` (baut daraus), `tester` (testet die Acceptance-Kriterien + Coverage-Gate), `reviewer` (prüft den Diff dagegen — hartes Drift-Gate).
>
> **Einordnung.** Schliesst das Race-Fenster zwischen `board next` und dem Wirksamwerden des `In Progress`-Status. Heute setzt `/flow` §2 den Status **lokal** und committet/pusht ihn erst am Session-Ende (§2b „Commit zurückgehalten bis Session-Ende"). Parallele Sessions in getrennten Worktrees sehen die Reservierung deshalb nicht und greifen denselben `board next`-Treffer. Diese Spec macht die Reservierung zur **atomar gepushten Erst-Operation** und definiert Verlierer-Erkennung + Stale-Reclamation. Ergänzt die Ein-Schreiber-Regel aus [[parallel-session-plan]] AC4 um den fehlenden **Vor-Start-Lock**.

## Zweck
Ein leichtgewichtiger, push-basierter Claim verhindert, dass zwei `/flow`-Sessions (Nachtwächter-Wellen, manuelle Sessions) dieselbe Story parallel bauen. Der Claim ist die **erste** Schreiboperation, bevor der `coder` läuft; die atomare `git push`-Serialisierung auf `default_branch` (die bereits einzige serielle Senke, [[parallel-session-plan]] AC7) entscheidet den Gewinner. Verlierer erkennen den fremden Claim und nehmen das nächste Item. Ein Claim eines toten Claimers läuft nach einer Stale-TTL (analog Nachtwächter `staleInProgressHours`) aus und wird ohne manuellen Eingriff neu vergeben — das behebt zugleich die „Geist-In-Progress"-Story (S-116 stand 5 Tage still). Kein neuer Dienst, headless lauffähig.

## Main Success Scenario
1. `/flow` erhält von `board next` die nächste bereite Story X (Status `To Do`). Zuvor hat `/flow` den Board-Stand von `origin/<default_branch>` frisch geholt (fetch), damit fremde, bereits gepushte Claims sichtbar sind.
2. `/flow` erzeugt einen **opaken Session-Token** (kein Secret) und setzt in **einem** Schritt: `status = In Progress`, `claimed_by = <token>`, `claimed_at = <now ISO-8601>` (+ `branch`) in der Story-YAML.
3. `/flow` committet diese Reservierung und **pusht sie sofort** nach `<default_branch>` — **vor** jedem `coder`-Dispatch. Fast-forward-Push gelingt → der Claim gehört dieser Session; Bau beginnt (§3).
4. Am Session-Ende (Landen/Blocked) bleiben Status/Claim wie üblich Teil des Board-Zustands; bei `Done`/`Verworfen` ist der Claim gegenstandslos (terminal).

## Alternative Flows
### A1: Push abgelehnt, Story inzwischen fremd-geclaimt (Verlierer)
- Der sofortige Push von Schritt 3 wird abgelehnt (non-fast-forward — eine andere Session hat zuerst gepusht). `/flow` fetcht (**kein** `git rebase`/`git merge` — zwei konkurrierende Claims schreiben praktisch immer dieselbe Story-YAML-Datei komplett neu, ein Rebase-Merge-Versuch endet dort fast immer in einem hängenden Konflikt) und liest X **direkt aus dem gefetchten Remote-Objekt** (`git show origin/<default_branch>:<story-pfad>`) erneut, ohne den Working-Tree zu berühren. X ist jetzt `In Progress` mit **fremdem** `claimed_by` und **frischem** `claimed_at` (nicht stale) → `/flow` verwirft die eigene lokale Reservierung (`git reset --hard origin/<default_branch>` — reiner Fast-Forward-Reset, kein Rebase-Zustand existiert), dispatcht **keinen** `coder` auf X und ruft erneut `board next` für das nächste Item auf.

### A2: Push abgelehnt, Grund war ein fremder, unbezogener Commit
- Push abgelehnt, aber nach Re-Read (`git show origin/<default_branch>:<story-pfad>`) ist X weiterhin `To Do` (die Ablehnung kam von einem unbezogenen Board-Commit). `/flow` setzt den lokalen Stand auf `origin/<default_branch>` zurück (`git reset --hard`, kein Rebase) und wiederholt den kompletten Claim-Vorgang (Token bleibt gleich) für X — begrenzte Anzahl Versuche, siehe Edge-Cases.

### A3: Stale-Claim wird neu vergeben (Geist-In-Progress)
- `board next` findet keine `To Do`-Story, aber eine Story Y ist `In Progress` mit `claimed_at` älter als `stale_claim_hours` (Claimer vermutlich tot). `board next` gibt Y als **reclaimable** Kandidat zurück; `/flow` übernimmt sie, indem es `claimed_by`/`claimed_at` mit dem **eigenen** Token/Zeitstempel überschreibt (expliziter Eigentümerwechsel) und den Claim-Push wie in Schritt 3 setzt. Kein manueller Eingriff.

### E1: `default_branch`-Senke dauerhaft belegt
- Der Claim-Push scheitert wiederholt (Senke sehr belegt) über das Retry-Budget hinaus → `/flow` bricht den Claim für X **ohne** Bau ab (Klartext-Diagnose), lässt X als `To Do` und beendet die Runde regulär; kein halb-geclaimter Zwischenzustand bleibt zurück.

## Acceptance-Kriterien

- **AC1** — Claim als erste Schreiboperation: `/flow` §2 erwirbt den Claim (`status = In Progress` + `claimed_by` + `claimed_at`) und **pusht** ihn nach `<default_branch>`, **bevor** irgendein `coder`-Dispatch dieser Story startet. Kein Bau läuft vor dem bestätigten Claim-Push. *(schliesst das heutige Race-Fenster „Status lokal, Commit bis Session-Ende zurückgehalten")*
- **AC2** — Atomarität über Push: die Serialisierung nutzt die atomare `git push`-Semantik auf `<default_branch>`. Wird der Push abgelehnt (non-fast-forward), fetcht `/flow` (**kein** `git rebase`/`git merge` — Story-YAML-Merges sind konfliktträchtig, da beide Seiten dieselbe Datei komplett neu schreiben) und liest die Story **direkt aus dem gefetchten Remote-Stand** (`git show origin/<default_branch>:<story-pfad>`, Working-Tree unangetastet) erneut, bevor es weiter entscheidet. *(deckt A1/A2)*
- **AC3** — Verlierer erkennt fremden Claim: ist die Story nach Re-Read `In Progress` mit fremdem, **frischem** `claimed_by` (nicht stale), dispatcht `/flow` **nie** einen `coder` auf sie, verwirft die eigene Reservierung und ruft erneut `board next` für das nächste Item. *(deckt A1)*
- **AC4** — Retry bei unbezogener Ablehnung: ist die Story nach Re-Read weiterhin `To Do` (Ablehnung durch fremden, unbezogenen Commit), setzt `/flow` den lokalen Stand per `git reset --hard origin/<default_branch>` zurück und wiederholt den kompletten Claim-Vorgang (gleicher Token) — begrenzt durch ein festes Retry-Budget. *(deckt A2)*
- **AC5** — Opaker Session-Token: jede `/flow`-Session erzeugt einen eindeutigen, **opaken** Claim-Token (kein Secret, kein Token/Key), der die besitzende Session für den Lauf identifiziert und in `claimed_by` steht.
- **AC6** — `board next` respektiert frische Claims: `board next` liefert unverändert nur `To Do`-Stories; eine frisch geclaimte (`In Progress`) Story wird einer anderen Session, solange der Claim frisch ist, **nie** als nächstes Item zurückgegeben.
- **AC7** — Stale-TTL konfigurierbar: eine Board-Konfiguration `stale_claim_hours` (in `board/board.yaml`, Default **4**, Semantik analog Nachtwächter `staleInProgressHours`) definiert, ab welchem Alter von `claimed_at` ein `In Progress`-Claim als verwaist gilt. Fehlt der Wert → Default 4.
- **AC8** — Stale-Reclamation ohne Eingriff: `board next` (und damit `/flow` §2) gibt eine `In Progress`-Story mit `claimed_at` älter als `stale_claim_hours` als **reclaimable** Kandidat zurück — nachrangig zu frischen `To Do`-Kandidaten. Beim Übernehmen überschreibt die reclaimende Session `claimed_by`/`claimed_at` mit ihrem eigenen Token/Zeitstempel (expliziter Eigentümerwechsel). *(deckt A3; behebt Geist-In-Progress S-116)*
- **AC9** — `board ready` meldet Stale-Claims: `board ready` weist stale-geclaimte `In Progress`-Stories als **eigene** Kategorie aus (Klartext-Zeile, z.B. `RECLAIMABLE <story>: In Progress seit <t>, Claim stale`), damit Geist-Stories in der Leerlauf-Diagnose sichtbar sind ([[empty-drain-diagnostics]]).
- **AC10** — Schema-Erweiterung: `board/story.schema.json` erhält `claimed_by` (string|null) und `claimed_at` (ISO-8601-string|null); `board set` unterstützt beide Felder. Bestehende Stories ohne die Felder bleiben gültig (null-Default, kein Nachtragen).
- **AC11** — Headless & kein Dienst: der gesamte Mechanismus funktioniert headless ohne neuen Dienst/Daemon/Lock-Server — nur `git push`-Atomarität + Board-CLI + Zeitstempel. *(NFR-hart)*
- **AC12** — Kein Fremd-Schreiben (ausser Reclamation): eine Session schreibt `status`/`claimed_by` einer Story, die sie nicht besitzt, **nie** — Ausnahme ist die explizite Stale-Reclamation (AC8), der bewusste Eigentümerwechsel. Konsistent mit [[parallel-session-plan]] AC4 („je Story genau ein schreibender `/flow`-Orchestrator").
- **AC13** — Sauberer Abbruch bei belegter Senke: kann der Claim-Push über das Retry-Budget hinaus nicht landen, lässt `/flow` die Story als `To Do` (kein halb-geclaimter Zwischenzustand), meldet den Abbruch im Klartext und beendet die Runde regulär. *(deckt E1)*

> **Traceability:** Jeder Test trägt das kanonische Trace-Tag `@trace story-claim-lock#AC<n>`
> gemäss `knowledge/<lang>.md` → `## Spec-Tagging`. Der `tester` rechnet das Coverage-Gate
> (jede genannte AC ≥ 1 deckender Test). Da agent-flow `language: md` ist, erfolgt die
> Abnahme der Skill-/Doku-Anteile als Doku-Inspektion; Schema-, `board next`/`board ready`-
> und Reclamation-Logik werden — soweit mechanisch (Skript-Anteile) — über ein Smoke-Skript
> belegt (analog `tests/board-cli`).

## Verträge

### Story-YAML — neue Felder (`board/story.schema.json`)
```yaml
claimed_by: <opaker-session-token>   # string|null — z.B. host+pid+random; KEIN Secret. null bei nicht-geclaimter Story.
claimed_at: '2026-07-26T18:00:00Z'   # ISO-8601-string|null — Zeitpunkt des Claims. null wenn nicht geclaimt.
```
- Beide Felder default `null`; bestehende Stories ohne die Felder bleiben schema-gültig.
- `board set <id> claimed_by <token>` / `board set <id> claimed_at <iso>` schreiben sie.

### Board-Konfiguration (`board/board.yaml`)
```yaml
stale_claim_hours: 4   # optional; fehlt → Default 4. Alter von claimed_at, ab dem ein In-Progress-Claim verwaist ist.
```

### `board next` — erweiterte Semantik
- Primär: erste bereite `To Do`-Story (unverändert — Priority/Depends-Gate, [[board-cli]] V6).
- Fallback, wenn keine `To Do`-Story bereit ist: erste `In Progress`-Story mit `claimed_at` älter als `stale_claim_hours`, im JSON zusätzlich mit `reclaimable: true` markiert (Eigentümerwechsel-Hinweis für `/flow`).
- Kein Kandidat → leere Ausgabe, Exit 0 (unverändert).

### `board ready` — erweiterte Ausgabe
- Zusätzliche Kategorie-Zeile je stale-geclaimter `In Progress`-Story: `RECLAIMABLE <story>: In Progress seit <claimed_at>, Claim stale (> <stale_claim_hours>h)`.

### `/flow` §2 — Claim-Protokoll (Reihenfolge)
1. `git fetch origin <default_branch>` (Board-Stand frisch) → `board next`.
2. Token erzeugen → `board set X status "In Progress"` + `claimed_by` + `claimed_at` + `branch`.
3. Commit + `git push origin HEAD:<default_branch>`.
   - Erfolg → Bau (§3).
   - Abgelehnt → **rebase-frei** (kein `git rebase`/`git merge` — Story-YAML-Konflikte sind praktisch garantiert und hinterlassen einen hängenden Rebase-Zustand): `git fetch origin <default_branch>`, Re-Read via `git show origin/<default_branch>:<story-pfad>` (Working-Tree unangetastet). Fremd-frisch → `git reset --hard origin/<default_branch>` (eigenen Claim-Commit verwerfen) + `board next` erneut (AC3). Noch `To Do` → `git reset --hard origin/<default_branch>` + kompletten Claim-Vorgang (Schritt 2–3) mit demselben Token neu (Retry, AC4, Budget). Budget erschöpft → `git reset --hard origin/<default_branch>` + Abbruch (AC13).

## Edge-Cases & Fehlerverhalten
- **`default_branch` protected (PR-only):** Board-Meta-Commits pushen bereits heute direkt nach `main` (§5); der Claim-Push nutzt denselben Pfad. Kein PR für den Claim.
- **Retry-Budget:** feste, kleine Obergrenze (z.B. 3 Versuche) für den Claim-Push bei unbezogenen Ablehnungen; danach Abbruch (AC13), nie Endlos-Loop.
- **Uhren-Drift zwischen Hosts:** `stale_claim_hours` grosszügig (Default 4h) gewählt, sodass moderater Zeit-Drift zwischen parallelen Hosts keine verfrühte Reclamation auslöst.
- **Worktree-Isolation:** jede Session claimt/pusht aus ihrem eigenen Worktree; die Board-YAML der geclaimten Story ist die einzige von ihr geschriebene Story-Datei ([[parallel-session-plan]] AC4).
- **Reclamation-Kollision:** zwei Sessions reclaimen dieselbe stale Story gleichzeitig → dieselbe atomare Push-Serialisierung (AC2) entscheidet; der Verlierer erkennt nach Re-Read den neuen frischen fremden Claim (AC3) und nimmt das nächste Item.
- **Kein `git rebase`/`git merge` bei abgelehntem Claim-Push (AC2, empirisch — echter Zwei-Session-Race reproduziert):** zwei konkurrierende Claims schreiben praktisch immer dieselbe Story-YAML-Datei komplett neu (`board set` überschreibt die gesamte Datei) — ein `git rebase`/`git merge` würde dort fast garantiert konfligieren und einen hängenden Rebase-Zustand (`.git/rebase-merge`) hinterlassen, aus dem nachfolgende Befehle (`board show` auf der konfliktbehafteten Datei, ein blosses `git reset --hard`) nicht mehr sauber herauskommen. Der Re-Read nach abgelehntem Push liest deshalb **immer** direkt aus dem Remote-Objekt (`git show origin/<default_branch>:<story-pfad>`), nie aus einem lokal gemergten/rebasten Working-Tree-Stand; die Bereinigung ist ein reiner Fast-Forward-`git reset --hard origin/<default_branch>` (kein Rebase-Abbruch nötig, weil nie rebased wurde).

## NFRs
- **Robustheit:** kein neuer Dienst, kein Lock-Server, headless (AC11); der Mechanismus überlebt Session-Abbrüche (Stale-TTL fängt tote Claimer, AC8).
- **Token-Ökonomie:** Claim-Erwerb und Verlierer-Erkennung sind rein mechanisch (Bash/Git/Board-CLI, kein LLM).
- **Sicherheit:** `claimed_by` ist opak und enthält **kein** Secret (AC5).

## Nicht-Ziele
- **Keine** Änderung der `board next`-Auswahl-Logik für `To Do` (Priority/Depends-Gate bleibt CLI-Hoheit, [[board-cli]]).
- **Keine** verteilte Konsens-/Lock-Infrastruktur — die `git push`-Atomarität genügt.
- **Keine** dev-gui-Nachtwächter-Änderung (die äussere Schleife nutzt `staleInProgressHours` weiter; hier nur der Board-seitige Claim + die Board-TTL).
- **Keine** parallele Merge-/Land-Mechanik — `default_branch` bleibt die eine, seriell bediente Senke ([[parallel-session-plan]] AC7).

## Abhängigkeiten
- [[parallel-session-plan]] — Ein-Schreiber-Regel (AC4) + serielle Merge-Senke (AC7), die dieser Claim ergänzt.
- [[board-cli]] — `board next`/`board ready`/`board set` (erweiterte Semantik + neue Felder).
- [[board-schema]] — `story.schema.json`-Erweiterung (AC10).
- [[empty-drain-diagnostics]] — Leerlauf-Diagnose, um die `RECLAIMABLE`-Kategorie ergänzt (AC9).
- `skills/flow/SKILL.md` §2 (Claim-Protokoll), `scripts/board` (`cmd_next`/`cmd_ready`/`set`), `board/story.schema.json`, `board/board.yaml`.
- Belege: `.claude/lessons/flow.md` flow/L07 (S-098, 3 Rückzüge), `.claude/memory.md` (Claim-Race + Geist-In-Progress S-116).
