## flow/L07 — S-098 (2026-07-23): duplicate-dispatch race lässt sich lösen, nicht nur vermeiden
Wenn `board next` das einzige READY-Item liefert und Memory/das aktuelle Board
zeigen, dass es schon mehrfach angefasst und wieder verlassen wurde (Race
zwischen parallelen `/flow`-Sessions): nicht automatisch ein 4. Mal
zurückziehen. Erst prüfen, ob in einem existierenden Story-Worktree
(`git worktree list`, Branch-Name nach Story-ID suchen) bereits verwertbare
Vorarbeit liegt (z.B. ein coder-Commit mit einer fundierten Analyse). Diese
Vorarbeit NICHT blind übernehmen, sondern eigenständig verifizieren (Spec/Code
selbst lesen) und dann reguär durch coder→reviewer→tester→ship schicken. Löst
das eigentliche Problem (Story bleibt liegen) statt es nur zu wiederholen.
**Warum:** S-098 hatte 3 dokumentierte Rückzüge; ein 4. Rückzug hätte am
Grundproblem (kein Claim-Lock vor `status In Progress`) nichts geändert.

## flow/L06 — board-ship.sh lokaler Nachschritt kann trotz erfolgreicher Landung fehlschlagen (flow/P3)
`board-ship.sh` schlägt am lokalen Nachschritt (`gh pr merge`) mit
`fatal: '<branch>' is already used by worktree '<hauptordner>'` fehl, wenn der
Zielbranch (`main`) im geteilten Hauptordner ausgecheckt ist — der PR ist zu
diesem Zeitpunkt aber bereits über `git push` + den vorherigen `gh pr create`
+ implizites Merge-Verhalten (oder einen zweiten `gh pr merge`-Versuch)
remote gelandet. **Vor jeder "nicht gelandet"-Fehlermeldung:**
`gh pr list --head <branch> --state all --json state,mergedAt` prüfen. Bei
`MERGED`: Restschritte manuell nachziehen — `git worktree add --detach
<tmp-pfad> origin/<default_branch>`, dort `board set <id> status Done`
(+ `pr`, dispo-Mirror), committen, `git push origin HEAD:<default_branch>`,
Worktree wieder entfernen. Kein blinder Retry des Scripts (kann Leer-PRs
erzeugen, s. flow/L02).

## flow/L05 — gh-Push-Auth: Basic-Auth-Header als Workaround für Bot-Login-Bug
`gh auth setup-git` konfiguriert einen Credential-Helper, der bei der
GitHub-App-Installation manchmal den Bot-Login statt `x-access-token` als
Username an `git push` liefert → `Invalid username or token`. Workaround, der
in dieser Session zuverlässig funktioniert hat:
```
git config http.https://github.com/.extraheader \
  "AUTHORIZATION: basic $(printf 'x-access-token:%s' "$(gh auth token)" | base64 -w0)"
```
Repo-lokal setzen (gilt dann für alle git-Netzwerkoperationen in diesem
Working-Tree/Worktree). Sollte langfristig in `ensure-gh-auth.sh` fest
verdrahtet werden, damit kein `/flow`-Lauf das manuell lösen muss.
