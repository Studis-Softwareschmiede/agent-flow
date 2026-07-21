> Orientierung, nie Wahrheit: bei Widerspruch gelten Board + docs/specs/.
> Kuratiert von /flow am Ende jeder Session. Max. 60 Zeilen.

## Aktueller Stand
Board fast leer (21.07.2026): 3 To-Do-Storys waren ready (S-098, S-118, S-119).
S-118 (gpg-pass Single-Flight-Lock) ist in dieser Session gelandet (PR #433).
S-098 wurde von einer parallelen `/flow`-Session (Worktree `flow-run`) parallel
bearbeitet — diese Session hat sich bewusst zurückgezogen, um Duplikat-Arbeit
zu vermeiden (kein Vertrags-Mechanismus verhindert das Race auf `board next`
zwischen zwei gleichzeitig gestarteten Sessions; erkannt nur durch manuelle
Worktree-Inspektion). S-119 (train-Auto-Merge) ist noch offen.

## Letzte Arbeiten
- S-118 (AC1–AC6): `provision-gpg-pass.sh` Single-Flight-Lock + sessions-
  übergreifender Cache (mkdir-Lock+trap, Poll-Wartepfad, Stale-Lock-Übernahme,
  `GPG_BW_CACHE_DIR` statt `$TMPDIR`). Reviewer-PASS, Tester-PASS (15/15 grün,
  Flaky-Check 2x). Gelandet PR #433. `board-ship.sh`s `gh pr merge`-Schritt
  scheiterte erneut am main-Worktree-Konflikt (Hauptordner hält `main`
  ausgecheckt) — PR war remote bereits MERGED, Restschritte (Board-Flip via
  temp detached Worktree) manuell nachgezogen (s. `.claude/lessons/flow.md`).
- Duplikat-Dispatch-Risiko entdeckt: zwei `/flow`-Sessions können denselben
  `board next`-Treffer (S-098) parallel als „In Progress" markieren, weil
  Board-Status pro Worktree nur lokal (uncommittet) sichtbar ist, bis er
  gepusht wird. Kein bestehender Lock-Mechanismus dagegen.
- pm-import (S-095–S-097) + pm-intake-gate.py (PR #388) gelandet, Spec active.

## Offene Fäden
- board-ship.sh: `gh pr merge --delete-branch` scheitert weiterhin lokal,
  wenn `main` im Hauptordner ausgecheckt ist (PR landet remote trotzdem) —
  jetzt 3x wiederholt (S-074/S-075/S-118); Skript-Fix erwägen (Merge ohne
  `--delete-branch` + separates `git push origin --delete`).
- Race zwischen parallelen `/flow`-Sessions auf denselben `board next`-Treffer
  (s.o., S-098-Fall) — kein Claim-/Lock-Mechanismus vor dem ersten `board set
  status In Progress`; bislang nur durch Zufall bemerkt.
- `.claude/lessons/orchestrator.md` (5 Lessons L01–L05) wird von der aktuellen
  `retro.md`-Kette nicht mehr gelesen (die zeigt auf `lessons/flow.md`, neu
  angelegt diese Session) — Migration/Ablöse-Markierung offen.
- dev-gui S-383/S-384: Obsidian-Ingest-Runner-Fix + GUI-Ziel-Projekt-Auswahl
  offen.
- AGENTS.md §1c (designer) beschreibt noch den alten Ablauf ohne Freigabe-
  Modus — Doku-Nachzug offen.
