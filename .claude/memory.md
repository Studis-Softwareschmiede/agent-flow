> Orientierung, nie Wahrheit: bei Widerspruch gelten Board + docs/specs/.
> Kuratiert von /flow am Ende jeder Session. Max. 60 Zeilen.

## Aktueller Stand
Board leer (23.07.2026) — S-098 war das letzte offene Item und ist jetzt
gelandet (PR #437). Der 4. Anlauf auf S-098 (nach 3x Rückzug wegen
Duplikat-Dispatch-Risiko) wurde diesmal zu Ende gebracht statt erneut
abgebrochen: eine parallele Session (Worktree `flow-run`) hatte bereits
analysiert, dass die ACs ohne Code-Diff erfüllt sind, aber nie durch
Review/Test/Ship geschickt — diese Session hat das eigenständig verifiziert
(nicht blind übernommen) und sauber durch den vollen Build-Loop gezogen.

## Letzte Arbeiten
- S-098 (AC23–AC25): Headless-Ausgabevertrag war bereits vollständig in
  docs/specs/obsidian-ingest.md + skills/from-notes/SKILL.md umgesetzt (Commit
  21629c8). Reviewer fand einen echten Drift-Fund: die als bindend
  referenzierte docs/architecture/obsidian-ingest-subsystem.md §6 war nicht
  nachgezogen (kein --gui/JSON-Vertrag erwähnt). Coder hat das in Iteration 2
  minimal (6 Zeilen) behoben, reviewer PASS, tester SKIPPED-DOC-ONLY. Gelandet
  PR #437. Board-Flip + Dispo-Mirror manuell im detached Worktree nachgezogen
  (board-ship.sh scheiterte am bekannten main-Worktree-Konflikt, flow/P3).
- S-119 (train-Auto-Merge) gelandet PR #434 (vorherige Session).
- S-118 (gpg-pass Single-Flight-Lock) gelandet PR #433.

## Offene Fäden
- `board-ship.sh`: lokaler Nachschritt (`gh pr merge --delete-branch` /
  Board-Flip) scheitert regelmässig am main-Worktree-Konflikt, wenn `main` im
  Hauptordner ausgecheckt ist — PR landet remote trotzdem (jetzt 5x:
  S-074/S-075/S-118/S-119/S-098). Skript-Fix überfällig: nach Fehlschlag
  automatisch `gh pr view --json state,mergedAt` prüfen und bei MERGED die
  Restschritte (Board-Flip im detachten Worktree) selbst nachziehen, statt nur
  abzubrechen.
- `gh auth git-credential` liefert für die App-Installation den Bot-Login
  statt `x-access-token` als Username — `git push` schlägt trotz gültigem
  Token fehl. Workaround (manuell in dieser Session bestätigt funktionsfähig):
  `git config http.https://github.com/.extraheader "AUTHORIZATION: basic
  $(printf 'x-access-token:%s' "$(gh auth token)" | base64 -w0)"` — sollte
  fest in `ensure-gh-auth.sh`/`board-ship.sh` verdrahtet werden, damit jeder
  Lauf das nicht erneut manuell lösen muss.
- Race zwischen parallelen `/flow`-Sessions auf denselben `board next`-Treffer
  — kein Claim-/Lock-Mechanismus vor dem ersten `board set status In
  Progress`; bei S-098 4x beobachtet (3x Rückzug, 1x durchgezogen). Kandidat-
  Fix weiterhin in `.claude/lessons/flow.md` flow/L01 skizziert — jetzt mit
  genug Historie, um ihn tatsächlich umzusetzen.
- `.claude/lessons/orchestrator.md` (5 Lessons L01–L05) wird von der
  aktuellen `retro.md`-Kette nicht mehr gelesen — Migration/Ablöse-Markierung
  weiterhin offen.
