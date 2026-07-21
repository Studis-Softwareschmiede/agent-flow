> Orientierung, nie Wahrheit: bei Widerspruch gelten Board + docs/specs/.
> Kuratiert von /flow am Ende jeder Session. Max. 60 Zeilen.

## Aktueller Stand
Board fast leer (21.07.2026). S-119 (train-Auto-Merge) ist in dieser Session
gelandet (PR #434; ein zweiter, inhaltsleerer PR #435 entstand durch einen
Retry-Fehlversuch, harmlos, s. Offene Fäden). S-098 wird weiterhin von einer
parallelen `/flow`-Session (Worktree `flow-run`) bearbeitet — diese Session
hat sich erneut bewusst zurückgezogen, um Duplikat-Arbeit zu vermeiden (jetzt
3. Vorfall dieses Musters). Board danach: nur noch offene Items ausserhalb
dieses unmittelbaren Laufs.

## Letzte Arbeiten
- S-119 (AC1–AC6): `train`-Skill bekommt Auto-Merge-Ausnahme analog
  `retro-auto-merge` (reviewer-PASS → Squash-Merge, Fix-Loop max. 3
  Iterationen, `model-tiers`/`--bootstrap` bleiben beim Mensch-Gate).
  3 Review-Iterationen (Doku-Drift in `agents/retro.md` behoben, dann eine
  versehentliche Simplicity-Leiter-Löschung in `AGENTS.md` behoben). Tester-
  PASS. Gelandet PR #434. Landung mit Nacharbeit: `gh pr merge` scheiterte
  wieder am main-Worktree-Konflikt (s. `.claude/lessons/flow.md` flow/L02),
  ein Retry des Skripts erzeugte zusätzlich einen leeren Zweit-PR (#435,
  Squash-Merges sind für den Ancestry-Check des Skripts nicht erkennbar —
  neue Lesson flow/L06). Board-Flip manuell im detached Worktree nachgezogen.
- S-118 (gpg-pass Single-Flight-Lock) gelandet PR #433 (vorherige Session).
- Duplikat-Dispatch-Risiko (S-098) weiterhin ungelöst, jetzt 3x beobachtet.
- pm-import (S-095–S-097) + pm-intake-gate.py (PR #388) gelandet, Spec active.

## Offene Fäden
- `board-ship.sh`: `gh pr merge --delete-branch` scheitert lokal, wenn `main`
  im Hauptordner ausgecheckt ist (PR landet remote trotzdem, jetzt 4x:
  S-074/S-075/S-118/S-119) UND ein blinder Retry danach ist nicht idempotent
  (erzeugt Leer-PR, da Squash-Merges den Ancestry-Check nie erfüllen) —
  Skript-Fix überfällig: `gh pr view --json state,mergedAt` statt/zusätzlich
  zu `merge-base --is-ancestor`.
- Subagent-Dispatches (coder/reviewer/tester) folgen NICHT automatisch dem
  `EnterWorktree`-cwd der Orchestrator-Session — ohne explizite `cd`-Anweisung
  + Nachverifikation landen Edits im geteilten Hauptordner (bei S-119 einmal
  passiert, rechtzeitig bemerkt + korrigiert). Jeder künftige `/flow`-Lauf in
  einem Worktree muss das im Dispatch-Prompt erzwingen.
- `gh auth git-credential` liefert für die App-Installation den Bot-Login
  statt `x-access-token` als Username — `git push` schlägt trotz gültigem
  Token fehl; Workaround via `http.extraHeader` + Basic-Auth funktioniert,
  sollte aber in `ensure-gh-auth.sh`/`board-ship.sh` fest verdrahtet werden.
- Race zwischen parallelen `/flow`-Sessions auf denselben `board next`-Treffer
  — kein Claim-/Lock-Mechanismus vor dem ersten `board set status In
  Progress`; jetzt 3x beobachtet (S-098), Kandidat-Fix in
  `.claude/lessons/flow.md` flow/L01 skizziert.
- `.claude/lessons/orchestrator.md` (5 Lessons L01–L05) wird von der
  aktuellen `retro.md`-Kette nicht mehr gelesen — Migration/Ablöse-Markierung
  weiterhin offen.
