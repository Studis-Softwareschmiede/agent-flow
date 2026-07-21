> Orientierung, nie Wahrheit: bei Widerspruch gelten Board + docs/specs/.
> Kuratiert von /flow am Ende jeder Session. Max. 60 Zeilen.

## Aktueller Stand
Board leer — pm-import komplett gelandet (19.07.2026, PRs #389–#391):
`/from-notes` erkennt pm-skills-Artefakte frontmatter-first (`artifact:`),
mappt sie feldgenau (11 Mapping-Zeilen: 8→Stufe b, 1 launch-checklist→Stufe c,
2→Stufe a) und garantiert Idempotenz/ID-Kette/Drift über die bestehende
obsidian-ingest-Mechanik (PM-Version-Vergleichsanker im jeweils schreibenden
Commit). Vorgelagert existiert `scripts/pm-intake-gate.py` (PR #388): prüft
einen Vault-Ordner nach einem pm-skills-Lauf gegen den pm-import-Kontrakt
(--fix stempelt Frontmatter mechanisch nach, --json für headless). Erster
Realtest: Ordner «Last30Days und PM» (Research-App-PRD) → GRÜN.

## Letzte Arbeiten
- S-095/S-096/S-097 (pm-import AC1–AC10): Klassifikation §0c, Mapping-
  Dispatch, Idempotenz §0d in skills/from-notes/SKILL.md. Befunde: Blanket-
  Exclusion drohte stillem Content-Verlust (coder/L1), Versions-Protokoll
  musste an den tatsächlich schreibenden Commit je Stufe (coder/L2).
- pm-intake-gate.py (PR #388) + Spec pm-import (PR #362) gemerged; Spec auf
  active gestempelt.
- S-084–S-094 (Vorsession): Admin-Bereich-Standard + Build-Versionierung
  (Details in docs/specs/admin-bereich-*.md, build-version-stamping.md).

## Offene Fäden
- dev-gui S-383/S-384 (angelegt 19.07.): Obsidian-Ingest startete from-notes
  im Vault-Ordner statt im Ziel-Projekt-Repo → Runner-Fix + GUI-Ziel-Projekt-
  Auswahl offen; bis dahin schlägt der GUI-Ingest fehl («Fragenkatalog konnte
  nicht gelesen werden» ist dieses Symptom).
- pm-intake-gate läuft noch manuell (kein /research-Skill); Verankerung in
  from-notes bräuchte einen expliziten AC (requirement-Eskalation 19.07.).
- board-ship.sh: `gh pr merge` scheitert lokal weiter (main im Hauptordner
  ausgecheckt) — PRs remote sauber gemerged, Restschritte manuell.
- dev-gui: VPS-Rollout Settings-Volume + Wellen-Plan-Konsum-Story offen.
- AGENTS.md §1c (designer) beschreibt noch den alten Ablauf ohne Freigabe-
  Modus — Doku-Nachzug offen.
