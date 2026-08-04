## flow/L09 — S-133 (2026-08-04): `board set <id> status …` ohne `BOARD_WRITER=flow` schlägt STILL fehl — die anderen `set`-Aufrufe im selben Claim-Block laufen trotzdem durch
Der Claim-Block in §2 ruft `board set` **viermal in Folge** auf (`status`,
`claimed_by`, `claimed_at`, `branch`). Fehlt vor dem Block `export
BOARD_WRITER=flow`, weist die CLI **nur** den `status`-Aufruf mit `FEHLER: set:
nur /flow darf Story-Status setzen (BOARD_WRITER=flow fehlt)` zurück — die drei
übrigen `set`-Aufrufe (claimed_by/claimed_at/branch) laufen unbeeindruckt
weiter und liefern `S-133` als Erfolgs-Echo. Ergebnis: ein Claim-Commit, der
aussieht wie ein normaler Claim, aber `status: To Do` behält — ein
Geist-Zustand (claimed, aber nicht In Progress), der beim nächsten `board
next` erneut als Kandidat auftaucht. Wurde erst beim manuellen Nachschauen
der YAML nach dem Commit auffällig (Exit-Code des Gesamtblocks war 0, kein
Bash-`set -e`-Abbruch, da jeder `board set`-Aufruf einzeln evaluiert wird).
**Fix:** `export BOARD_WRITER=flow` **vor** dem gesamten Claim-Block setzen
(nicht nur vor dem `status`-Aufruf) — gilt ebenso für jeden späteren `board
set status …`-Aufruf dieser Session (Blocked/Done). Nach dem Claim-Commit vor
dem Push kurz `grep status board/stories/<id>-*.yaml` gegen den erwarteten
Wert verifizieren, bevor committet wird.

## flow/L08 — S-123 (2026-07-26): /flow --parent im Feature-Worktree — Claim + Ship gehören auf den Feature-Branch
Läuft `/flow --parent F-###` direkt in einem Feature-Worktree, der bereits
`feature/F-###` ausgecheckt hat (board-feature-drain-Modell): (a) der
Claim-Commit wird auf `origin/feature/F-###` gepusht, NICHT auf
`$default_branch` — ein `git push origin HEAD:main` würde den kompletten
unfertigen Feature-Stand nach main tragen (§2 der Skill-Doku beschreibt den
board-weiten Normalfall; Präzedenz: frühere Claim-Commits desselben Drains
liegen ebenfalls auf dem Feature-Branch). (b) `board-ship.sh` Modus B
verweigert den Aufruf vom Ziel-Branch selbst („erwarte einen eigenen
Story-Branch") und verlangt einen sauberen Tree: vor dem Ship also
`git checkout -b feat/<S-###>-<slug>` vom Feature-Worktree-HEAD, Story-Diff
dort committen, dann `board-ship.sh <S-###> --target-branch feature/F-###`;
danach zurück `git checkout feature/F-###` + `git merge --ff-only
origin/feature/F-###` für die Session-Ende-Commits (Dispo-Spiegel/Memory).
Funktionierte für S-123 in einem Durchlauf (PR #442, Exit 0).

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

## flow/L05 — gh-Push-Auth: Basic-Auth-Header als Workaround für Bot-Login-Bug — ÜBERHOLT, siehe unten
**⚠ ÜBERHOLT (2026-07-26, `git-auth-hardening`/S-121):** Der unten
dokumentierte `extraheader`-Workaround ist ein **Anti-Pattern** und darf
NICHT mehr angewendet werden — er hat genau den 23.–26.07.-Ausfall
verursacht: der ~1h gültige App-Token wurde als
`http.https://github.com/.extraheader` in `.git/config` persistiert; nach
Ablauf blockierte der stale Header 3 Tage lang JEDE git-Netzwerkoperation
aller Sessions mit „Invalid username or token", bis er manuell entfernt
wurde. **Neuer Weg:** `scripts/ensure-gh-auth.sh` richtet jetzt einen
tokenlosen, global-scope git-Credential-Helper ein (`gh auth git-credential`
+ Wrapper, der `username=x-access-token` erzwingt) — das Token wird bei
jedem git-Aufruf frisch gestreamt, nie in eine Datei/Config geschrieben. Das
Skript erkennt zudem vorhandene `http.*.extraheader`-Reste (auch von diesem
alten Workaround) und entfernt sie automatisch. Kein manueller Eingriff mehr
nötig — siehe `docs/specs/git-auth-hardening.md`.

Ursprünglicher (jetzt überholter) Lesson-Text, unverändert dokumentiert als
Beleg für den Bug, den `ensure-gh-auth.sh` jetzt abdeckt:
`gh auth setup-git` konfiguriert einen Credential-Helper, der bei der
GitHub-App-Installation manchmal den Bot-Login statt `x-access-token` als
Username an `git push` liefert → `Invalid username or token`. Workaround, der
in dieser Session zuverlässig funktioniert hat:
```
git config http.https://github.com/.extraheader \
  "AUTHORIZATION: basic $(printf 'x-access-token:%s' "$(gh auth token)" | base64 -w0)"
```
Repo-lokal setzen (gilt dann für alle git-Netzwerkoperationen in diesem
Working-Tree/Worktree). ~~Sollte langfristig in `ensure-gh-auth.sh` fest
verdrahtet werden~~ — **NICHT tun**, siehe Warnung oben: `ensure-gh-auth.sh`
verdrahtet stattdessen den tokenlosen Credential-Helper-Weg fest.
