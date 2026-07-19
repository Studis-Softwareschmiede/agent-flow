---
id: admin-bereich-settings-rollout
title: Admin-Bereich-Settings-Rollout — cicd/preview mounten das Settings-Daten-Volume
status: active
version: 1
spec_format: use-case-2.0
area: auslieferung
---

# Spec: Admin-Bereich-Settings-Rollout  (`admin-bereich-settings-rollout`)

> **Schicht 3 von 3.** Testbares **Verhalten + Verträge**, sprach-/paradigma-unabhängig.
> **Source of Truth** für `coder`/`cicd` (verdrahtet den Volume-Mount), `reviewer` (Drift-Gate), `tester` (prüft die AC).
>
> **Subsystem-Bindung.** Verankert den **Rollout-Vertrag** des Fabrik-Standards Admin-Bereich (`docs/architecture/admin-bereich-subsystem.md` §6): die persistente Settings-Ablage (BR-006) liegt auf einem gemounteten Daten-Volume, damit Einstellungen Container-Neustart/Redeploy überleben.

## Zweck

Der Admin-Bereich speichert geänderte Parameter in einer Settings-Ablage (settings-Tabelle bei DB-Projekten, sonst `settings.json`). Damit diese Einstellungen einen Redeploy überleben, müssen `cicd` und `preview` beim Rollout das Settings-Daten-Volume mounten. Diese Spec macht den Volume-Mount zum verbindlichen Rollout-Schritt und trägt den expliziten Hinweis, dass der dev-gui-VPS-Rollout dasselbe Volume mounten muss.

## Kontext / Designnuancen (bindend)

- **DB-Projekte:** die Settings-Tabelle ist Teil des ohnehin gemounteten DB-Volumes — kein zusätzliches Volume, aber der Rollout muss die Persistenz sicherstellen.
- **Nicht-DB-Projekte:** `settings.json` braucht ein **dediziertes** gemountetes Volume (sonst geht die Datei beim Redeploy verloren).
- **Laufzeit-Wirkung ohne Neustart** (BR-007) setzt voraus, dass die Ablage über die Container-Lebensdauer hinaus persistent ist.

## Main Success Scenario

1. `cicd`/`preview` rollt ein UI-Projekt mit Admin-Bereich aus.
2. Der Rollout mountet das Settings-Daten-Volume (`docker run -v <settings-volume>:<mount>`).
3. In der Settings-Ablage gesetzte Werte überleben Container-Neustart/Redeploy.

## Alternative Flows

### A1: DB-Projekt
- Die Settings-Tabelle liegt im DB-Volume; der Rollout stellt sicher, dass das DB-Volume gemountet ist (kein separates Settings-Volume nötig).

## Acceptance-Kriterien

- **AC1** — Der `cicd`- und der `preview`-Rollout mounten beim `docker run` das **Settings-Daten-Volume** (dediziertes Volume für `settings.json` bei Nicht-DB-Projekten; DB-Volume bei DB-Projekten) (→ BR-006). *(deckt A1)*
- **AC2** — Die Spec-Vorlage `templates/_docs/specs/admin-bereich.md` und der Rollout-Vertrag tragen den **expliziten Hinweis**, dass der **dev-gui-VPS-Rollout** dieses Settings-Daten-Volume **ebenfalls** mounten muss (sonst Datenverlust beim Redeploy).
- **AC3** — **Persistenz-Nachweis:** ein in der Settings-Ablage gesetzter Wert bleibt nach Container-Neustart/Redeploy erhalten (die Ablage liegt außerhalb des ephemeren Container-Dateisystems, → BR-006).

> **Traceability:** Jeder Test trägt das kanonische Trace-Tag `@trace admin-bereich-settings-rollout#AC<n>[,BR-NNN]`
> gemäss `knowledge/<lang>.md` → `## Spec-Tagging`. Der `tester` rechnet das Coverage-Gate.
> Details: `docs/architecture/traceability-subsystem.md`.

## Verträge

### Rollout-Sequenz (cicd / preview)
```bash
docker run -d --name "$app" \
  -v "${settings_volume}:${settings_mount}" \   # Settings-Daten-Volume (BR-006)
  --env-file .env \                             # Secrets (secrets-subsystem §7)
  -p "${port}:${container_port}" \
  "${image}:latest"
```

## Edge-Cases & Fehlerverhalten

- **Volume fehlt beim Rollout** → Einstellungen sind nach Redeploy verloren; Reviewer-Befund (Rollout mountet kein Settings-Volume).
- **DB-Projekt:** kein separates Settings-Volume, aber DB-Volume-Mount ist Pflicht.

## NFRs

- **Persistenz:** Einstellungen überleben Container-Lebenszyklus (Neustart/Redeploy).

## Nicht-Ziele

- Die Settings-Ablage-Semantik/Präzedenz selbst (`docs/architecture/admin-bereich-subsystem.md` BR-005/BR-006).
- Das Scaffold-Fragment ([[admin-bereich-scaffolding]]).

## Abhängigkeiten

- `docs/architecture/admin-bereich-subsystem.md` §6, BR-006 — Settings-Ablage + Persistenz.
- [[secrets-subsystem]] §7 — Rollout-Sequenz (`--env-file`), an die der Volume-Mount anschließt.
- `agents/cicd.md`, `skills/preview` — die Rollout-Pfade, in die der Mount eingebaut wird.
