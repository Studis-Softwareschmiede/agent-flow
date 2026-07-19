---
id: admin-bereich-scaffolding
title: Admin-Bereich-Scaffolding — Spec-Vorlage, Manifest + set-admin-password.sh, new-project/init/adopt-Wiring
status: active
version: 1
spec_format: use-case-2.0
area: vorlagen-scaffolding
---

# Spec: Admin-Bereich-Scaffolding  (`admin-bereich-scaffolding`)

> **Schicht 3 von 3.** Testbares **Verhalten + Verträge**, sprach-/paradigma-unabhängig (Intent, keine Idiome/Klassen).
> **Source of Truth** für `coder` (verdrahtet `new-project`/`init`/`adopt` + legt Scaffold-Fragment/Vorlage an), `reviewer` (Idempotenz + Drift-Gate), `tester` (prüft die AC).
>
> **Subsystem-Bindung.** Diese Spec verankert den Fabrik-Standard „Admin-Bereich" (`docs/architecture/admin-bereich-subsystem.md`) im Projekt-Bootstrap — analog zu [[regression-scaffolding]] und [[secrets-subsystem]]. Sie liefert die sprach-neutrale **Spec-Vorlage** + das **Scaffold-Fragment** + die **idempotente Board-Story**; die stack-spezifische Implementierung entsteht projekt-lokal via `/flow` (GE6).

## Zweck

Jedes UI-Projekt der Fabrik startet mit den Bausteinen eines passwortgeschützten Admin-Bereichs — ohne Handarbeit. Der Bootstrap kopiert die sprach-neutrale Spec-Vorlage (`templates/_docs/specs/admin-bereich.md`), das Scaffold-Fragment (`templates/_shared/admin/`: Manifest-Vorlage + `set-admin-password.sh`) und legt idempotent eine Board-Story „Admin-Bereich" an, sodass `/flow` die stack-spezifische Umsetzung direkt aufnehmen kann.

## Kontext / Designnuancen (bindend)

- **Nur UI-Projekte** (GE7): Nicht-UI-Projekte (reine CLI/Lib/Bot) erhalten das Admin-Scaffold **nicht**.
- **Idempotenz** (Vorbild [[regression-scaffolding]] AC3): `init`/`adopt` überschreiben bestehende Admin-Dateien nicht (mergen/überspringen); die Board-Story „Admin-Bereich" wird **nie doppelt** angelegt.
- **Fabrik liefert Vorlage, nicht Implementierung** (GE6): das Scaffold legt Vorlage + Manifest-Vorlage + Password-Script + Story; die Server-/UI-/Session-Umsetzung macht `coder` via `/flow` im Ziel-Projekt gegen die gescaffoldete Spec-Vorlage.
- **Secrets-Kopplung** ([[secrets-subsystem]]): `set-admin-password.sh` schreibt `ADMIN_PASSWORD_HASH` in `.env` und ruft `scripts/encrypt-env.sh` → `.env.gpg` (BR-002, BR-003).

## Main Success Scenario

1. `new-project <name>` läuft für ein **UI-Projekt** (Bootstrap).
2. Es kopiert die Spec-Vorlage `templates/_docs/specs/admin-bereich.md` → `docs/specs/admin-bereich.md`.
3. Es kopiert das Scaffold-Fragment `templates/_shared/admin/` → `config/admin-manifest.yaml` (Startbestand: `.env`-Keys) + `scripts/set-admin-password.sh` (executable).
4. Es legt **idempotent** eine Board-Story „Admin-Bereich" (Status To Do) an, die auf die gescaffoldete Spec zeigt.
5. Das Projekt ist „bereit für `/flow`" (stack-spezifische Umsetzung).

## Alternative Flows

### A1: Adoption bestehender UI-Repos (`init`/`adopt`)
- `init`/`adopt` legen dasselbe Grundgerüst **idempotent** an: bestehende Admin-Dateien werden nicht überschrieben (mergen/überspringen); die Board-Story wird nur angelegt, wenn sie noch nicht existiert.

### A2: Nicht-UI-Projekt
- Ist das Projekt kein UI-Projekt (GE7), wird **kein** Admin-Scaffold angelegt und **keine** Board-Story erzeugt.

## Acceptance-Kriterien

- **AC1** — Die Fabrik trägt eine **sprach-neutrale Spec-Vorlage** `templates/_docs/specs/admin-bereich.md` nach `templates/_docs/specs/_template.md`-Muster (nummerierte AC), die die Geschäftsregeln des Subsystems referenziert (→ BR-001…BR-011) und den Cross-Repo-Hinweis zum Settings-Volume trägt (§6). *(Welle 2)*
- **AC2** — Die Fabrik trägt ein Scaffold-Fragment `templates/_shared/admin/` mit (a) einer **Manifest-Vorlage** `config/admin-manifest.yaml` im Manifest-Vertrag (→ BR-011) und (b) einem **`set-admin-password.sh`**-Template. *(Welle 2)*
- **AC3** — `set-admin-password.sh` erfragt ein Passwort, erzeugt einen **argon2id**-Hash, schreibt ihn als `ADMIN_PASSWORD_HASH` in `.env` und ruft anschließend `scripts/encrypt-env.sh` auf (→ BR-002, BR-003). Es nutzt `set -euo pipefail`, gibt das Passwort **nie** ins Log/echo aus und committet nichts. *(Welle 2)*
- **AC4** — `new-project` scaffoldet bei **UI-Projekten** das Admin-Fragment (Spec-Vorlage + Manifest-Vorlage + `set-admin-password.sh`) und legt **idempotent** eine Board-Story „Admin-Bereich" (Status To Do) an, die auf `docs/specs/admin-bereich.md` zeigt. *(Welle 3)*
- **AC5** — `init`/`adopt` legen dasselbe Grundgerüst **idempotent** an: vorhandene Admin-Dateien werden **nicht** überschrieben (mergen/überspringen), die Board-Story wird **nie doppelt** angelegt. *(deckt A1, Welle 3)*
- **AC6** — Bei **Nicht-UI-Projekten** wird **kein** Admin-Scaffold und **keine** Board-Story angelegt (→ GE7). *(deckt A2)*
- **AC7** — Die Manifest-Vorlage folgt dem Manifest-Vertrag: pro Parameter `key`, `quelle` (`env`|`config.yaml`|`settings`), `typ`, `editierbar`, `secret`/`maskiert`, `validierung`; der Startbestand sind die vorhandenen `.env`-Keys (konservativ `editierbar: false`, Secret-Namensmuster `secret: true`) (→ BR-011, BR-007, BR-008). *(Welle 2)*
- **AC8** — Die stack-spezifische **Implementierung** (Routen, Session, UI-Rendering) ist **nicht** Teil des Scaffolds — die Fabrik liefert nur Spec-Vorlage + Scaffold + Board-Story; die Umsetzung macht `coder` via `/flow` im Ziel-Projekt (→ GE6). *(Welle 3)*

> **Traceability:** Jeder Test trägt das kanonische Trace-Tag `@trace admin-bereich-scaffolding#AC<n>[,BR-NNN]`
> gemäss `knowledge/<lang>.md` → `## Spec-Tagging`. Der `tester` rechnet das Coverage-Gate
> (jede genannte AC + jede referenzierte BR ≥ 1 deckender Test). Details: `docs/architecture/traceability-subsystem.md`.

## Verträge

### Gescaffoldete Artefakte (aus `templates/`)
```
docs/specs/admin-bereich.md          # kopiert aus templates/_docs/specs/admin-bereich.md
config/admin-manifest.yaml           # kopiert aus templates/_shared/admin/ (Startbestand: .env-Keys)
scripts/set-admin-password.sh        # kopiert aus templates/_shared/admin/ (executable)
<Board-Story „Admin-Bereich">        # idempotent, Status To Do, spec: docs/specs/admin-bereich.md
```

### `set-admin-password.sh` — Vertrag
| Aufruf | Vor-Bedingung | Wirkung | Nach-Bedingung |
|---|---|---|---|
| `bash scripts/set-admin-password.sh` | `.env` existiert (oder wird angelegt) | Passwort-Prompt → argon2id-Hash → `ADMIN_PASSWORD_HASH` in `.env` → `bash scripts/encrypt-env.sh` | `.env.gpg` aktuell; Passwort nie geloggt/committet |

## Edge-Cases & Fehlerverhalten

- **Bestehende `config/admin-manifest.yaml` / `set-admin-password.sh`** (bei `init`/`adopt`) → nicht überschreiben; vorhandenen Stand behalten, nur Fehlendes ergänzen (AC5-Idempotenz).
- **Board-Story „Admin-Bereich" existiert bereits** → nicht doppelt anlegen (Titel-/Spec-Match).
- **`argon2`-Werkzeug fehlt auf dem Scaffold-Host** → `set-admin-password.sh` bricht mit klarer Fehlermeldung ab (kein stiller Klartext-Fallback).

## NFRs

- **Idempotenz:** wiederholtes `init`/`adopt` ändert nichts an korrektem Grundgerüst.
- **Portabilität:** identisches Grundgerüst über alle Sprachen (Manifest + Password-Script sprach-neutral).
- **Sicherheit:** `set-admin-password.sh` gibt das Passwort nie im Klartext aus (→ BR-002).

## Nicht-Ziele

- Die stack-spezifische Admin-Bereich-**Implementierung** (Routen/Session/UI) — projekt-lokal via `/flow` (GE6).
- Der Security-Floor in `knowledge/security.md` ([[admin-bereich-knowledge-floor]]).
- Der Rollout-Volume-Mount ([[admin-bereich-settings-rollout]]).
- Die requirement-Frage nach Manifest-Parametern ([[admin-bereich-manifest-intake]]).

## Abhängigkeiten

- `docs/architecture/admin-bereich-subsystem.md` — bindende Geschäftsregeln (BR-001…BR-011) + gelockte Entscheidungen.
- [[secrets-subsystem]] — `ADMIN_PASSWORD_HASH` via `.env`/`.env.gpg`; `set-admin-password.sh` ruft `encrypt-env.sh`.
- [[regression-scaffolding]] — Vorbild für idempotentes Scaffold + Board-Story-Anlage.
- `skills/new-project`, `skills/init`, `skills/adopt` — die Bootstrap-Skills, in die dieser Schritt eingebaut wird.
