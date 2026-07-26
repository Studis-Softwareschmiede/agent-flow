> Orientierung, nie Wahrheit: bei Widerspruch gelten Board + docs/specs/.
> Kuratiert von /flow am Ende jeder Session. Max. 60 Zeilen.

## Aktueller Stand
Board leer (26.07.2026) — S-116 war das letzte offene Item. Befund der
Abschluss-Session: der komplette S-116-Inhalt (coder/R09, reviewer/R10,
AGENTS.md-Nachzug) war bereits seit 21.07. auf main — versehentlich mit dem
S-118-PR (#433) gemergt. Die Story galt aber weiter als offen und wurde vom
Taktgeber 3x fortschrittslos angefasst und blockiert. Diese Session hat die
5 ACs eigenständig gegen main verifiziert (nicht blind übernommen) und die
Story ohne neuen Diff auf Done geflippt. S-117 bleibt bewusst Blocked
(wartet auf nächsten großen /adopt-Fall, Owner-Entscheid 21.07.).

## Letzte Arbeiten
- S-116 (Simplicity-Leiter): kein Diff nötig — Inhalt war via PR #433
  (S-118-Squash) schon auf main; ACs verifiziert, Done-Flip + Dispo-Mirror.
- S-098 (AC23–AC25): gelandet PR #437 (4. Anlauf nach 3x Claim-Race-Rückzug).
- S-119 (train-Auto-Merge) gelandet PR #434; S-118 (gpg-pass Lock) PR #433.

## Offene Fäden
- Abgelaufener `http.extraheader`-Token in `.git/config` des Hauptordners
  blockierte 23.–26.07. JEDE git-Netzwerkoperation („Invalid username or
  token") — am 26.07. entfernt. Der flow/L05-Workaround (Token in git-Config
  schreiben) ist die falsche Dauerlösung: Kurzzeit-Token läuft ab und
  vergiftet den Ordner. Dauerfix gehört in ensure-gh-auth.sh (Story folgt).
- Claim-Race zwischen parallelen /flow-Sessions (kein Lock vor `In
  Progress`): bei S-098 4x, S-116-Inhalt landete dadurch im falschen PR.
  Fix-Story (Reservierung vor Story-Start) wird angelegt.
- `board-ship.sh` lokaler Nachschritt scheitert am main-Worktree-Konflikt,
  wenn main im Hauptordner ausgecheckt ist (5x beobachtet, flow/P3) —
  Skript-Fix weiter offen.
- `.claude/lessons/orchestrator.md` (L01–L05) wird von der retro.md-Kette
  nicht mehr gelesen — Migration/Ablöse-Markierung weiter offen.
