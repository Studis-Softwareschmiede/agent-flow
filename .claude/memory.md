> Orientierung, nie Wahrheit: bei Widerspruch gelten Board + docs/specs/.
> Kuratiert von /flow am Ende jeder Session. Max. 60 Zeilen.

## Aktueller Stand
Board leer (26.07.2026 abends) — einzig S-117 bleibt bewusst Blocked (wartet
auf nächsten großen /adopt-Fall). Die drei Infrastruktur-Dauerbrenner sind
alle behoben und im Betrieb verifiziert: Claim-Lock (S-120), tokenlose
git-Auth (S-121, inkl. bewiesenem Selbstheilungs-Lauf nach Token-Ablauf)
und board-ship.sh PR-Landung (S-122 — landete sich selbst mit Exit 0 bei
belegtem main, erstmals seit 7 Fehlversuchen kein manueller Nachschritt).
Repo aufgeräumt: alle 19 Remote- und 11 lokalen Alt-Branches gelöscht
(jeder gegen gemergten PR bzw. Inhalt-in-main verifiziert); nur noch main.
Nachtwächter ist AUS (Owner-Entscheid — bei Bedarf in der dev-gui oder via
PUT /api/settings/ticker wieder aktivieren).

## Letzte Arbeiten
- S-122 (board-ship PR-Merge worktree-fest) gelandet PR #441 — 1 Iteration,
  Review+Test PASS; Fix bewies sich an der eigenen Landung (Exit 0).
- S-120 (Claim-Lock) PR #439, S-121 (git-Auth) PR #440 — je 3 Iterationen,
  Reviewer fand 3 echte reproduzierte Fehler vor der Landung.
- Branch-Großputz: 19 remote + 11 lokal gelöscht, main einziger Branch.

## Offene Fäden
- S-117 (Graphify-Pilot) wartet extern — beim nächsten großen /adopt-Fall
  entblocken.
- dev-gui kennt claimed_by/claimed_at/RECLAIMABLE noch nicht (eigene
  JS-Reimplementierung von board next/ready) — separate dev-gui-Story,
  falls der Nachtwächter das Claim-Wissen nutzen soll.
- estimator-Bias-Kalibrierung md|balanced|L/XL fraglich: Kappung drückte
  bei S-120/S-121 unter das Ist, bei S-122 (roh 8.5, Bias→12.75, ist 4)
  weit darüber — Rohschätzungen treffen derzeit besser; Kandidat für
  retro Modus E (lessons/estimator.md hat die Details).
- gh-App-Token läuft nach ~1h ab; ensure-gh-auth.sh vor git-Push-Serien
  erneut ausführen (Helper heilt sich, aber Token-Mint bleibt nötig).
