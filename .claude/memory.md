> Orientierung, nie Wahrheit: bei Widerspruch gelten Board + docs/specs/.
> Kuratiert von /flow am Ende jeder Session. Max. 60 Zeilen.

## Aktueller Stand
Board leer (26.07.2026, nur S-117 bewusst Blocked — wartet auf nächsten
großen /adopt-Fall). Die zwei strukturellen Dauerbrenner sind behoben und
gelandet: S-120 Claim-Lock (atomarer Claim-Push vor coder-Dispatch, rebase-
freie Verlierer-Recovery, Stale-Reclamation nach 4h, RECLAIMABLE-Diagnose)
und S-121 git-Auth-Härtung (tokenloser x-access-token-Credential-Wrapper +
Reset-Marker gegen System-Helper + extraheader-Selbstheilung; auf dieser
Maschine live verifiziert — fetch/fill laufen, kein Token in Dateien).
Künftige /flow-Sessions MÜSSEN das neue Claim-Protokoll in SKILL.md §2
befolgen (Claim sofort committen+pushen, bei Ablehnung git show statt
rebase).

## Letzte Arbeiten
- S-120 (Claim-Lock) gelandet PR #439 — 3 Iterationen; Reviewer fand
  empirisch den Rebase-Deadlock im Verlierer-Pfad (Zwei-Klon-Race-Test
  jetzt in tests/story-claim-lock/, 35 Assertions).
- S-121 (git-Auth) gelandet PR #440 — 3 Iterationen; Reviewer fand 2x
  Helper-Vorrang-Fallen (roher gh-Eintrag zuerst; fehlender Reset-Marker
  ließ System-osxkeychain gewinnen). Tests in tests/git-auth-hardening/.
- S-116 (Simplicity-Leiter) Done ohne Diff — Inhalt war Squash-Beifang in
  PR #433; S-098 gelandet PR #437 (Vorsessions).

## Offene Fäden
- board-ship.sh lokaler Nachschritt (gh pr merge) scheitert weiter am
  main-Worktree-Konflikt im Hauptordner (jetzt 7x: zuletzt S-120/S-121) —
  PR landet remote trotzdem; Restschritte manuell. Skript-Fix weiter offen
  (Kandidat-Story: nach Fehlschlag gh pr view prüfen, bei MERGED Board-Flip
  im Detached-Worktree selbst nachziehen).
- dev-gui reimplementiert board next/ready nativ in JS (BoardAggregator/
  ProjectDrain) — kennt claimed_by/claimed_at/RECLAIMABLE noch nicht;
  dev-gui-seitige Nachführung wäre eine separate Story im dev-gui-Repo.
- Beim S-121-Review hat der Reviewer via git credential-osxkeychain ein
  echtes persönliches GitHub-Token in seinen Tool-Output geholt (nirgends
  persistiert außer im lokalen Session-Transcript). Owner informiert.
- .claude/lessons/orchestrator.md (L01–L05) wird von der retro.md-Kette
  nicht mehr gelesen — Migration/Ablöse-Markierung weiter offen.
