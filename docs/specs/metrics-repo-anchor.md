---
id: metrics-repo-anchor
title: Metrik-Schreibpfad am Projekt-Repo verankern (nie Plugin-Root, nie Worktree)
status: active
area: metriken-schaetzung
version: 2
spec_format: use-case-2.0
---

# Spec: Metrik-Schreibpfad am Projekt-Repo verankern  (`metrics-repo-anchor`)

> **Schicht 3 von 3.** Testbares **Verhalten + Verträge**, sprach-/paradigma-unabhängig (Intent, keine Idiome/Klassen).
> **Source of Truth** für `coder` (baut daraus), `tester` (testet die Acceptance-Kriterien + Coverage-Gate), `reviewer` (prüft den Diff dagegen — hartes Drift-Gate).

## Zweck
Vorfall 2026-07-02: Sämtliche Metrik-Zeilen der dev-gui-Flow-Läufe (46 items, 220 dispatches) landeten in `agent-flow/.claude/metrics/` statt im Projekt-Repo `dev-gui/.claude/metrics/` — die dev-gui-Story-Detailansicht zeigte deshalb „kein Agenten-Flow aufgezeichnet" (Start/Dauer/Ist leer). Ursache-Klasse: Der Metrik-Pfad wird zur Laufzeit relativ bzw. über `git rev-parse` aufgelöst; nach Verzeichniswechseln (Worktrees, `${CLAUDE_PLUGIN_ROOT}`-Zugriffe — bei Directory-Install ist die Plugin-Wurzel selbst ein Git-Repo) driftet die Auflösung weg vom Board-Repo. Dieselbe Drift trifft den Token-Nachtrag (`metrics-token-collect` findet keine Subagent-Transcripts → `tok_total` bleibt `null`, seit 2026-06-17 durchgängig). Diese Spec verankert alle Metrik-Pfade einmalig und absolut am Board-Repo.

## Acceptance-Kriterien

- **AC1** — `skills/flow/SKILL.md` §0: `/flow` ermittelt **genau einmal beim Start** (vor jedem Verzeichniswechsel, vor Worktree-Erstellung) den absoluten Pfad des Board-Repos (`METRICS_ROOT` = `git rev-parse --show-toplevel` im Start-Arbeitsverzeichnis) und merkt ihn als Session-Variable.
- **AC2** — ALLE Metrik-Schreibstellen des Skills (dispatches.jsonl nach jedem Dispatch, items.jsonl beim Done, baseline-Lookups §1a) referenzieren ausschließlich `${METRICS_ROOT}/.claude/metrics/…` — kein relativer Pfad, kein erneutes `rev-parse`, kein `${CLAUDE_PLUGIN_ROOT}`-basierter Pfad. **AC2 regelt den Daten-Pfad (wohin geschrieben wird), nicht den Werkzeug-Pfad (von wo das Skript läuft)** — siehe AC6.
- **AC3** — Der Token-Nachtrag (`metrics-token-collect`-Block in SKILL.md) verwendet denselben `${METRICS_ROOT}`-Anker für das Ledger UND ermittelt das Transcript-Verzeichnis der Subagenten korrekt auch dann, wenn die Story in einem Worktree gebaut wurde (Transcript-Slug des tatsächlichen Sitzungs-cwd, nicht des Worktree-Pfads bzw. umgekehrt — die Auflösungsregel ist im Block dokumentiert und deckt beide Fälle Hauptordner/Worktree).
- **AC4** — Plausibilitäts-Gate: Vor dem ersten Metrik-Write prüft der Skill, dass `${METRICS_ROOT}` das Board enthält (`${METRICS_ROOT}/board/board.yaml` existiert); schlägt das fehl, wird die Erfassung mit EINEM Hinweis übersprungen (K3: Messen blockiert nie den Loop) — es wird niemals in ein Repo ohne dieses Board geschrieben.
- **AC5** — Doku-Nachzug: `docs/architecture/board-subsystem.md` (bzw. Metrik-Abschnitt) benennt den Anker-Vertrag und den Vorfall 2026-07-02 als Rationale in einem Satz.
- **AC6** *(V2, Story S-069)* — Die Metrik-Skripte liegen **ausschließlich im Plugin** (`${CLAUDE_PLUGIN_ROOT}/scripts/`) und werden von dort aufgerufen; Projekt-Repos halten **keine** Kopien. Ihr Ledger-Pfad kommt **explizit** aus `METRICS_ROOT` (Parameter/Env, gesetzt in §0) — **nie** aus dem eigenen Skript-Ort (`$SCRIPT_DIR/..`). Fehlt `METRICS_ROOT`, schreibt das Skript nichts und meldet das sichtbar (AC4-Gate bleibt). Rationale: Die Ableitung aus dem Skript-Ort machte den Aufruf über `${METRICS_ROOT}/scripts/…` zur Pflicht — und damit die Erfassung von einer Skript-Kopie im Projekt abhängig. Da die Skripte nie in `templates/` aufgenommen wurden, hatten am 2026-07-17 nur **2 von 8** Projekten überhaupt eine Erfassung (agent-flow zufällig als Plugin selbst, dev-gui via manuellem Nachrüsten S-344); die übrigen sechs — u.a. flashrescue, ki-investment — zeichneten **nichts** auf, ohne jeden Hinweis. Das Werkzeug gehört an einen Ort, die Daten ans Board-Repo.

## Verträge
- **`METRICS_ROOT`:** absoluter Pfad, einmal je Session, unveränderlich; einzige Wahrheit für alle Ledger-Pfade des Laufs.
- **K3 präzisiert (V2):** Metrik-Fehler blockieren nie Gates und stoppen nie den Loop — aber sie sind **sichtbar zu melden** (ein Hinweis mit Ursache ist Pflicht, nicht bloß erlaubt). K3 rechtfertigt Nicht-Blockieren, nicht Unsichtbarkeit (Rationale: 345 Dispatches ohne Token und ohne einen einzigen Hinweis, 2026-07-02 bis 2026-07-17).
- **Append-only unverändert.**

## Edge-Cases & Fehlerverhalten
- **E1:** `/flow` in einem Worktree gestartet (Sonderfall paralleler Sessions) → `rev-parse --show-toplevel` liefert den Worktree; das Plausibilitäts-Gate AC4 findet dort `board/board.yaml` (Worktree spiegelt das Repo) — Schreiben in den Worktree ist dann akzeptiert, die Zeilen landen beim Landen der Story NICHT auf main; dieser Sonderfall ist dokumentiert (Metriken gehören zu Läufen aus dem Hauptordner — Drain/Nachtwächter erfüllen das immer).
- **E2:** Board-Repo ohne `.claude/metrics/` → Verzeichnis anlegen (bestehendes Verhalten).

## NFRs
- Reine Skill-/Doku-Änderung; deterministisch, ~0 zusätzliche LLM-Token (K2/K3 bleiben).

## Nicht-Ziele
- Keine Rück-Migration historischer Fehl-Zeilen (einmalige Daten-Reparatur erfolgte manuell am 2026-07-02).
- Keine Änderung des Ledger-Schemas.

## Abhängigkeiten
- `[[metrics-token-collect]]` (Token-Nachtrag — AC3 präzisiert dessen Pfad-Auflösung).
- Konsument: dev-gui Story-Detailansicht (liest `<projekt>/.claude/metrics/`).
- **Ablösung (V2):** dev-gui-Spec `metrics-scripts-backfill` (Skript-Kopien ins Projekt nachrüsten) wird durch AC6 gegenstandslos und ist mit dessen Umsetzung auf `superseded` zu setzen; die Kopien unter `dev-gui/scripts/metrics-*.sh` entfallen.
