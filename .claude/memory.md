> Orientierung, nie Wahrheit: bei Widerspruch gelten Board + docs/specs/.
> Kuratiert von /flow am Ende jeder Session. Max. 60 Zeilen.

## Aktueller Stand
Das Board ist wieder leer — die 5 Stories des Owner-Auftrags vom 18.07.2026
(Design-Freigabe-Gate + vertikale Schnitte, PRs #365–#369) sind gelandet.
Neu in der Fabrik: (1) Der designer arbeitet im Vorschlags-/Freigabe-Modus —
docs/design.md entsteht als Entwurf (owner_approved: null) und wird erst nach
expliziter Owner-Freigabe bindend; /flow baut ui-gelabelte Stories nur mit
freigegebenem design.md (§2c-Gate, headless → Blocked). from-notes Stufe b
und requirement dispatchen den designer bei UI-Projekten; requirement vergibt
das ui-Label deterministisch. (2) requirement zerlegt vertikal (Feature-
Schnitte statt Schichten); die /flow-Ordnungsregel „Backend vor Frontend"
ist durch feature-weise Fertigstellung ersetzt.

## Letzte Arbeiten
- S-078/S-079/S-080 (design-owner-approval): designer-Freigabe-Modus,
  Intake-Einbindung (Ein-Katalog-Grundsatz in Stufe b gewahrt), /flow-§2c-
  Bau-Gate. Je 1 Review-Iteration mit Befund (fehlendes Bash-Tool im
  designer-Frontmatter; Abbruch-Zweig ohne Endzustand) — beide gefixt.
- S-081/S-082 (vertical-slice-stories): requirement-Vertrag + AGENTS.md
  vertikal, /flow-§0a-(b)-Ordnungsregel ersetzt. Jeweils PASS in Iteration 1.
- Batch lief als /flow --all mit 3 Wellen (S-078‖S-081 → S-082 → S-079‖S-080),
  Hot-Spot-Serialisierung AGENTS.md bzw. skills/flow/SKILL.md.

## Offene Fäden
- AGENTS.md §1c (designer-Abschnitt) beschreibt noch den alten Ablauf ohne
  Vorschlags-/Freigabe-Modus — kleiner Doku-Nachzug (reconcile oder Mini-Story).
- board-ship.sh: `gh pr merge` scheitert weiterhin lokal, wenn main im
  Hauptordner ausgecheckt ist (heute 4× reproduziert, PRs #365–#369 remote
  sauber gemerged; Restschritte je Story manuell). Fix-Kandidat: orchestrator/L05.
- Veraltete „1×/Woche"-Erwähnungen in metrics-subsystem.md /
  metrics-retro-aggregation.md (Kontext-Prosa) — kleiner Doku-Nachzug.
- dev-gui-Story für den Wellen-Plan-Konsum (Nachtwächter) noch anzulegen.
