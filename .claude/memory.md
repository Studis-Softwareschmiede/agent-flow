> Orientierung, nie Wahrheit: bei Widerspruch gelten Board + docs/specs/.
> Kuratiert von /flow am Ende jeder Session. Max. 60 Zeilen.

## Aktueller Stand
Das Board ist leer — alle 6 offenen Stories wurden am 18.07.2026 in einer
Session gelandet (PRs #357–#364). Die Fabrik hat jetzt: konfigurierbaren
Retro-Cooldown (`retro_cooldown_days`, Default 1 Tag), Retro-Auto-Merge bei
reviewer-PASS (nur retro; train/teamLeader weiter mit Owner-Approve), das
zentrale ID-Reservierungs-Ledger (`board/id-reservations.yaml` +
`board-id-reserve.sh`, C-Bestand 1–2 geseedet), dieses Projekt-Memory
(S-076) und den Wellen-Plan-Modus `/flow --plan` (S-077) samt mechanischer
Revalidierung (`board-plan-validate.sh`). Die dev-gui-Seite des Wellen-Plans
(Nachtwächter liest `session-plan.yaml`) ist noch nicht gebaut.

## Letzte Arbeiten
- S-077: `/flow --plan` erstellt Wellen-Plan als Datei-Vertrag; hartes
  ID-Reservierungs-Gate, Ein-Schreiber-je-Story präzisiert. 2 Iterationen
  (veraltete SR2-Schwelle, Downgrade- statt Abbruch-Semantik korrigiert).
- S-076: Projekt-Memory eingeführt; Persistenz über den Session-Ende-
  Board-Meta-Commit (cicd-A0 nur Ausnahmefall-Backstop).
- S-064: G1-Owner-Override kodifiziert (4 Bedingungen, reviewer/R08);
  Vorlage als SSOT in der Spec.
- S-063 (XL): ID-Block-Reservierung; 3 Iterationen — Review fand fehlendes
  Bestand-Seeding + Solo-Release, tester fand flakiges Test-7-Fixture
  (30/30-Wiederholungs-Abnahme). Ist 11 EP vs. 3.75 geschätzt.
- S-075: Retro-Auto-Merge bei reviewer-PASS (G4 bleibt zwingend).
- S-074: Retro-Cooldown als Profil-Feld, Default 1 Tag.

## Offene Fäden
- `board-ship.sh`: `gh pr merge --delete-branch` scheitert lokal, wenn main
  im Hauptordner ausgecheckt ist (Merge remote OK) — 5× reproduziert,
  Restschritte manuell; Kandidat-Fix siehe orchestrator/L05.
- `skills/flow/SKILL.md` SR2-Sektion nennt noch die obsolete ≥3-Schwelle
  (Widerspruch zu feature-batch-orchestration v2) — Folge-Ticket.
- Veraltete „1×/Woche"-Erwähnungen in metrics-subsystem.md /
  metrics-retro-aggregation.md (Kontext-Prosa) — kleiner Doku-Nachzug.
- dev-gui-Story für den Wellen-Plan-Konsum (Nachtwächter) noch anzulegen.
