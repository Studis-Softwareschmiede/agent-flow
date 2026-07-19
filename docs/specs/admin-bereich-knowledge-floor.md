---
id: admin-bereich-knowledge-floor
title: Admin-Bereich-Knowledge-Floor — security.md-⚑-Regeln + UI-Pack-Guidance
status: active
version: 1
spec_format: use-case-2.0
area: wissen-packs
---

# Spec: Admin-Bereich-Knowledge-Floor  (`admin-bereich-knowledge-floor`)

> **Schicht 3 von 3.** Testbares **Verhalten + Verträge**, sprach-/paradigma-unabhängig.
> **Source of Truth** für `coder` (authort die Knowledge-Pack-Ergänzungen), `reviewer` (wendet den Floor an), `tester` (prüft die AC).
>
> **Subsystem-Bindung.** Verankert den **Security-Floor** und die **UI-Rendering-Guidance** des Fabrik-Standards Admin-Bereich (`docs/architecture/admin-bereich-subsystem.md` §5) in den querschnittlichen Knowledge-Packs, damit `reviewer` sie **immer** anwendet — unabhängig vom konsumierenden Projekt.

## Zweck

Der Admin-Bereich ist eine sicherheitskritische Standard-Komponente jeder UI-App. Diese Spec schärft `knowledge/security.md` um Admin-Bereich-spezifische **⚑-Floor-Regeln** (argon2id, Login-Rate-Limit, Session-Cookie, CSRF, Secret-Maskierung, localhost-only-Setup) und ergänzt die UI-Pack-Guidance um das **generische Manifest-Rendering-Muster**, sodass jede stack-spezifische Umsetzung an denselben Prinzipien gemessen wird.

## Acceptance-Kriterien

- **AC1** — `knowledge/security.md` trägt Admin-Bereich-**⚑-Floor-Regeln** (Coder-Guidance): (a) Admin-Passwort als **argon2id**-Hash statt Klartext (→ BR-002, verschärft `security/R06`); (b) **Fehlversuch-Sperre/Rate-Limit** am Login (→ BR-009); (c) **signiertes HttpOnly+SameSite-Session-Cookie** (→ BR-010); (d) **CSRF-Schutz** auf state-ändernden Admin-Requests (→ BR-010); (e) **Secrets im UI maskiert** (→ BR-008); (f) **Setup-Seite nur von localhost** (→ BR-004, `security/R04`).
- **AC2** — Die `knowledge/security.md`-**Reviewer-Checklist** trägt die Spiegel-Einträge zu AC1 mit Severity: Klartext-/schwaches Passwort-Hashing für den Admin-Login → **Critical**; fehlender Login-Rate-Limit → **Important**; fehlendes CSRF / kein HttpOnly+SameSite-Cookie am Admin-Bereich → **Important**; Setup-Seite ohne localhost-Beschränkung (auf VPS erreichbar) → **Critical**; Secret unmaskiert an den Browser ausgeliefert → **Important**.
- **AC3** — Die **UI-Pack-Guidance** (`knowledge/ui.md`, anlegen falls nicht vorhanden) trägt das **generische Manifest-Rendering-Muster**: die Admin-UI wird aus `config/admin-manifest.yaml` gerendert (nicht pro Parameter handgebaut, → GE3/BR-011); `editierbar: false`-Parameter werden nur **maskiert angezeigt** (→ BR-007); `secret`-Parameter werden im UI **maskiert** (→ BR-008). **Erreichbarkeit (Präzisierung):** der Pack-Lademechanismus lädt Domänen-Packs ausschließlich über `profile.domains` (kein automatisches UI-Projekt-Matching) — damit `ui/R01`–`R03` nicht totes Wissen bleiben, deklarieren die UI-Templates (`templates/{angular,html,flutter}/profile.md`) `ui` additiv in `domains` (analog `css`).

> **Traceability:** Jeder Test trägt das kanonische Trace-Tag `@trace admin-bereich-knowledge-floor#AC<n>[,BR-NNN]`
> gemäss `knowledge/<lang>.md` → `## Spec-Tagging`. Der `tester` rechnet das Coverage-Gate.
> Details: `docs/architecture/traceability-subsystem.md`.

## Verträge

### Knowledge-Pack-Ziele
```
knowledge/security.md   # ⚑ Admin-Bereich-Floor (Coder-Guidance + Reviewer-Checklist)
knowledge/ui.md         # generisches Manifest-Rendering-Muster (anlegen falls fehlend)
templates/angular/profile.md   # domains: [css, tailwind, ui] — additiv, Pack-Erreichbarkeit (AC3)
templates/html/profile.md      # domains: [css, ui]           — additiv, Pack-Erreichbarkeit (AC3)
templates/flutter/profile.md   # domains: [ui]                 — additiv, Pack-Erreichbarkeit (AC3)
```

## Edge-Cases & Fehlerverhalten

- **`knowledge/ui.md` existiert nicht** → anlegen (leichter Abschnitt), bestehende UI-Guidance nicht überschreiben.
- **Projekt ohne `domains:[security]`** → der ⚑-Floor greift trotzdem (per Definition Floor, `reviewer` wendet ⚑ immer an).

## NFRs

- **Rückwärtskompatibel:** die Floor-Schärfung ist additiv; bestehende Projekte ohne Admin-Bereich sind nicht betroffen (die Regeln greifen nur bei vorhandenem Admin-Bereich).

## Nicht-Ziele

- Das Scaffold-Fragment/die Spec-Vorlage ([[admin-bereich-scaffolding]]).
- Der Rollout-Volume-Mount ([[admin-bereich-settings-rollout]]).

## Abhängigkeiten

- `docs/architecture/admin-bereich-subsystem.md` §3, §5 — Geschäftsregeln + Floor-Quelle.
- `knowledge/security.md` (Floor `security/R01`, `R04`, `R06`), `knowledge/ui.md`.
