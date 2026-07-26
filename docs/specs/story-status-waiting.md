---
id: story-status-waiting
title: Story-Status „Waiting" (extern gated) — Enum-Erweiterung + nicht-terminale Warte-Semantik
status: active
area: board
version: 1
spec_format: use-case-2.0
---

# Spec: Story-Status „Waiting"  (`story-status-waiting`)

> **Schicht 3 von 3.** Testbares **Verhalten + Verträge**, sprach-/paradigma-unabhängig.
> **Source of Truth** für `coder`/`tester`/`reviewer` (hartes Drift-Gate).
>
> **Bindung.** Der kanonische Story-Status-Enum lebt in [[board-schema]] (§V3/AC3) und `docs/architecture/board-subsystem.md` §4.2. Diese Spec erweitert ihn um den **nicht-terminalen** Wert **„Waiting"** — Muster und Werkzeug-Liste analog [[story-status-verworfen]].

## Zweck

Heute wird `Blocked` für ZWEI verschiedene Dinge missbraucht: (a) *die Fabrik kommt nicht weiter* (echtes Hindernis) und (b) *die Story wartet bewusst auf ein externes Ereignis* (z.B. agent-flow S-117 „Graphify-Pilot": wartet auf den nächsten realen großen `/adopt`-Fall). Fall (b) bekommt einen eigenen Status **`Waiting`** mit Pflicht-Warte-Grund (`wait_reason`) — damit Ansichten geparkte Storys ruhig gruppieren können (dev-gui-Gegenstück [[waiting-status-devgui]] im dev-gui-Repo) und Automaten sie nie anfassen, ohne dass sie als Dauer-„Blocker" alarmieren. Owner-Auftrag 2026-07-26 (Vorfall: 30+ Leerlauf-Nacht-Drain-Berichte wegen des S-117-Warte-Gates in Blocked-Optik).

## Kontext / Designnuancen (bindend)

- **NICHT terminal.** Anders als `Verworfen`: `Waiting` zählt überall als **offen** — Depends-Gate NICHT erfüllt (ein Dependent einer wartenden Story bleibt gewartet), Rollup/Progress zählt sie nicht als done, `reconcile`-Drain-Gate wertet sie als offene Spalte.
- **Nie Arbeits-Kandidat.** Wie `Blocked`: `board next` und `/flow` wählen eine `Waiting`-Story **nie**; Drain-Konsumenten (dev-gui) behandeln sie wie `Blocked`/`Idee` (nie Drain-Ziel).
- **Pflicht-Warte-Grund.** Übergang nach `Waiting` erzwingt `--reason` (analog `Blocked`), persistiert als **eigenes** Feld `wait_reason` (nicht `blocked_reason` — die GUI unterscheidet die beiden Kategorien exakt an Status+Feld). Verlassen von `Waiting` löscht `wait_reason`.
- **Exakter Name = Cross-Repo-Vertrag:** exakt `Waiting` (englisch, großes W) in allen Artefakten — dev-gui (BoardAggregator/Ansichten/Drain) verlässt sich darauf.
- **Manuelle/Owner-Entscheidung, kein Loop-Ausgang.** Kein `/flow`-Übergang erzeugt `Waiting` automatisch; Single-Writer (`BOARD_WRITER=flow`) unverändert.

## Acceptance-Kriterien

- **AC1** — **Enum-Erweiterung:** `Waiting` ist gültiger Story-Status überall, wo der Enum erzwungen wird: `scripts/board-lint.sh`, `board/story.schema.json`, kanonische Enum-Doku ([[board-schema]] §V3/AC3, board-subsystem §4.2). Kanonischer Enum danach: `To Do | In Progress | Blocked | Waiting | In Review | Done | Verworfen`. Feature-Enum unverändert. Neues optionales Story-Feld `wait_reason` (String|null) im Schema.
- **AC2** — **Schreibbarkeit via CLI:** `board set <S-###> status Waiting --reason "…"` akzeptiert; `--reason` ist **Pflicht** (analog Blocked), persistiert in `wait_reason`. Übergang setzt kein `done_at`, löscht `blocked_reason`; Verlassen von `Waiting` löscht `wait_reason`.
- **AC3** — **Nicht-terminal + nie Kandidat:** `board next` wählt `Waiting` nie als Kandidat UND wertet eine `Waiting`-depends-Vorbedingung als NICHT erfüllt (offen). Rollup/Progress/`reconcile`-Drain-Gate zählen `Waiting` als offen (wie Blocked). Getestete Invariante (Regressionsschutz).
- **AC4** — **Erst-Anwendung:** S-117 (Graphify-Pilot) wird von `Blocked` auf `Waiting` umgestellt; der bisherige `blocked_reason`-Warte-Text wandert nach `wait_reason`.

## Nicht-Ziele
- Keine dev-gui-Änderung (separates Repo, [[waiting-status-devgui]] dort — S-428).
- Kein automatischer Übergang Waiting→To Do (das Aufwecken bleibt Owner-Entscheidung).
- Keine Änderung der `Blocked`-/`Verworfen`-Semantik.

## Abhängigkeiten
- [[board-schema]] · [[story-status-verworfen]] (Muster) · board-subsystem §4.2/§5 · Cross-Repo: dev-gui `waiting-status-devgui` (S-428, toleriert fehlenden Status bereits heute).
