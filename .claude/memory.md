> Orientierung, nie Wahrheit: bei Widerspruch gelten Board + docs/specs/.
> Kuratiert von /flow am Ende jeder Session. Max. 60 Zeilen.

## Aktueller Stand
F-031 (rot-team Cloudflare-Access-Service-Token-Protokoll) läuft: S-133
gelandet in `feature/F-031` (PR #454) — war die einzige bereite Story dieses
Batches, weitere F-031-Stories ggf. noch offen. Feature-Merge nach main folgt
gebündelt am Feature-Ende (board-feature-drain.sh --merge-feature), nicht
diese Einzel-Session. F-017 wartet weiterhin auf denselben finalen Merge.
Nachtwächter ist AUS (Owner-Entscheid).

## Letzte Arbeiten
- S-133 (red-team Skill+Agent konsumiert access_header=cf-access, AC15:
  Marker-Guard, Header-Injektion nur per Env-Referenz, Graceful-Blocked,
  Security-Floor) gelandet PR #454 → feature/F-031; 1 Iteration, Review +
  Test PASS ohne Critical/Important, ep_act 3 = ep_est 3.0.
- S-123 (Waiting-Status) gelandet PR #442 → feature/F-017; 1 Iteration.
- S-122 (board-ship PR-Merge worktree-fest) gelandet PR #441.
- S-120 (Claim-Lock) PR #439, S-121 (git-Auth) PR #440 — je 3 Iterationen.

## Offene Fäden
- feature/F-017 UND feature/F-031 nach main mergen (board-ship.sh
  --merge-feature) — sobald der jeweilige Drain das Feature-Ende erkennt.
- AGENTS.md §10 zeigt die red-team-Aufruf-Signatur noch ohne
  access_header=cf-access (Reviewer-Suggestion aus S-133, kein Blocker).
- tests/board-feature-drain: 2 vorbestehende FAILs (13b/13c,
  Dossier-Sentinel) — eigener Fix-Kandidat.
- dev-gui S-428 (Schwester-Story Waiting-Status) ist separat.
- gh-App-Token läuft nach ~1h ab; ensure-gh-auth.sh vor git-Push-Serien
  erneut ausführen.
