> Orientierung, nie Wahrheit: bei Widerspruch gelten Board + docs/specs/.
> Kuratiert von /flow am Ende jeder Session. Max. 60 Zeilen.

## Aktueller Stand
Board leer (27.07.2026). S-123 (Story-Status `Waiting`) ist als letzte
F-017-Story in `feature/F-017` gelandet (PR #442) — der finale Merge des
Feature-Branches nach main steht noch aus (macht board-feature-drain.sh
gebündelt via board-ship.sh --merge-feature, nicht die Einzel-Session).
S-117 (Graphify-Pilot) steht jetzt korrekt auf `Waiting` mit wait_reason
(nicht mehr Blocked) — wartet weiter auf den nächsten großen /adopt-Fall,
alarmiert aber nicht mehr als Dauer-Blocker. Nachtwächter ist AUS
(Owner-Entscheid — bei Bedarf in der dev-gui wieder aktivieren).

## Letzte Arbeiten
- S-123 (Waiting-Status: Enum + wait_reason + CLI-Guard + next/rollup/
  Drain-Gate + Erst-Anwendung S-117) gelandet PR #442 → feature/F-017;
  1 Iteration, Review + Test PASS ohne Befund, ep_act 3 = ep_est 3.0.
- S-122 (board-ship PR-Merge worktree-fest) gelandet PR #441 — Fix bewies
  sich an der eigenen Landung (Exit 0 bei belegtem main).
- S-120 (Claim-Lock) PR #439, S-121 (git-Auth) PR #440 — je 3 Iterationen.
- Branch-Großputz: 19 remote + 11 lokal gelöscht.

## Offene Fäden
- feature/F-017 nach main mergen (board-ship.sh --merge-feature) — sobald
  der Drain das Feature-Ende erkennt; danach Worktree wt-run-f017 abbauen.
- tests/board-feature-drain: 2 vorbestehende FAILs (13b/13c,
  Dossier-Sentinel) — dreifach per stash als S-123-unabhängig verifiziert;
  eigener Fix-Kandidat.
- dev-gui S-428 (Schwester-Story Waiting-Status in BoardAggregator/
  Ansichten/Drain) ist separat — dev-gui kennt Waiting/claimed_by noch nicht.
- estimator-Bias md|balanced|L/XL fraglich (S-120–S-122); S-123 (S-Klasse,
  requirement-Heuristik) traf dagegen exakt — Kandidat für retro Modus E.
- gh-App-Token läuft nach ~1h ab; ensure-gh-auth.sh vor git-Push-Serien
  erneut ausführen.
