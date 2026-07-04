# UpgradePlan — <run_id>

> Spec-Typ: **UpgradePlan** (vom `/upgrade`-Skill erzeugt, Phase D). Durable Source of Truth unter `docs/specs/upgrade-<run_id>.md` — `coder` baut daraus, `tester` testet gegen die AC, `reviewer` prüft dagegen (Drift-Gate, CONCEPT §4d). Bindender Hintergrund: `docs/architecture/upgrade-subsystem.md`.
> Platzhalter `<…>` füllt `/upgrade` beim Anlegen.

- **Spec-ID:** `upgrade-<run_id>`
- **Status:** planning | executing | done | blocked
- **Erzeugt:** <iso-datum> · **Solver-Version:** Pack-Header-Constraints + Web-Fallback (`upgrade-subsystem.md` §6)

## 1. Zweck
Modernisierung des Stacks auf den neuesten, **kompatiblen**, sichersten, funktionierenden Stand — eine Major-Stufe je Achse, gegate-bar via `/flow`.

## 2. Ist → Ziel (Solver-Ergebnis)

| Achse | Ist | Ziel | Begründung (Solver) | Quelle |
|---|---|---|---|---|
| language | `<current>` | `<target>` | <z.B. neueste LTS; deckt Floors X+Y> | <link> |
| build | `<current>` | `<target>` | <…> | <link> |
| frameworks[<id>] | `<current>` | `<target>` | <…> | <link> |
| db_migration_tool | `<current>` | `<target>` | <…> | <link> |
| db_dialect | `<current>` | `<target|unverändert>` | <…> | <link> |
| container_runtime | `<current>` | `<target|unverändert>` | <z.B. Servlet-6.1-Ausschluss Undertow> | <link> |

**Aufgelöste Konflikte:** <z.B. „Ziel-Migrations-Tool fordert höheres Sprach-Minimum als das Ziel-Framework ⇒ Sprach-Ziel auf <LTS> angehoben">
**Bump-Reihenfolge (`order[]`):** `language → build → frameworks → migration → db`
**Unlösbar (`conflicts[]`, → Blocked-Stufen):** <keine | Liste mit Grund>

## 3. Wissenslücken (Phase E)
<Liste der Ziele ohne Pack → `train --bootstrap <pack-id>` (Staging-Dir + agent-flow-PR, Mensch-Gate). | keine>

## 4. Leiter — Acceptance-Kriterien pro Stufe
> Jede Stufe = **ein Board-Item** (`Depends-on` auf die vorige + Solver-Vorbedingungen). Jede AC ist testbar; „Build/Tests grün" ist Pflicht pro Stufe.

### Achse language
- `AC-L1:` `<lang>` von `<v>` auf `<v+>` — Toolchain/CI gepinnt, Build grün
- `AC-L2:` … (weitere Stufen)

### Achse build
- `AC-B1:` `<build-tool>` auf `<ziel>` — Build grün

### Achse frameworks[<id>] (Major-Leiter)
- `AC-F1:` `<id>` `<n>`→`<n+1>` — `<update-cmd>` + Schematics/Migrationen grün, Tests grün
- `AC-F2:` `<id>` `<n+1>`→`<n+2>` — …
- … bis Ziel-Major

### Achse db_migration_tool
- `AC-M1:` `<tool>` auf `<ziel>` — Migrations-Apply grün, Marker-Tabelle ok

### Modernisierung (nach Erreichen der Ziel-Major, optional)
- `AC-X1:` automatisierte Modernisierungs-Schematics anwenden (z.B. standalone/control-flow/inject bei Angular) — Build + Tests grün

## 5. Abschluss-Kriterien (gesamter Plan)
- `AC-Z1:` voller Build + Test-Suite + Smoke grün auf dem Ziel-Stand
- `AC-Z2:` `profile` spiegelt die Ziel-Versionen; `adoption_validated_at` ggf. invalidiert (DB-Achse berührt)
- `AC-Z3:` keine Nutzung entfernter/deprecateter APIs der übersprungenen Majors (reviewer-Checklist der Ziel-Packs)

## 6. Nicht-Ziele
- Kein Tool-/Framework-**Wechsel** (nur Versions-Modernisierung).
- Kein Sprung über mehrere Majors in einem Item.
- Keine neuen user-sichtbaren Features (reiner Upgrade-Scope).

## 7. Abhängigkeiten / Risiken
- 3rd-Party-Libs müssen die Ziel-Majors unterstützen (pro Stufe im reviewer/tester-Gate sichtbar als roter Build).
- Autonom via `train --bootstrap` erzeugte Packs sind im Lauf in Verwendung, gehen aber durch das Mensch-Gate (Report).
