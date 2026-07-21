---
spec_format: use-case-2.0
status: active
---

# Spec: Born-Secure — Norm-Regeln + Security-Baseline-Scaffold + Lernkreis-Klammer

> Setzt A+B+C aus `docs/architecture/born-secure-baseline.md` um. Feature: F-033.

## Kontext & Motivation

Generische, von Beginn an vermeidbare Web-Härtungslücken (fehlende Security-Header, öffentliche API-Docs) fließen
heute nur reaktiv über den Security-Pack zurück, nicht proaktiv ins Gerüst. Neue Projekte starten ungesichert und
ziehen dieselben Fixes je Projekt nach. Diese Spec schließt den proaktiven Kanal + verdrahtet den Lernkreis.

## Akzeptanzkriterien

### Teil A — Norm-Regeln (`knowledge/security.md`, Norm-Lane)
- **AC1 — Security-Header-Regel.** Neue Norm-Lane-Regel (`security/R17`): HTTP-Security-Response-Header nach OWASP
  Secure Headers — HSTS, CSP, `X-Content-Type-Options: nosniff`, `X-Frame-Options`/`frame-ancestors`,
  `Referrer-Policy`, `Permissions-Policy`, COEP/COOP/CORP — mit autoritativer Quelle (Link). Reviewer-Checklist-Zeile
  (Severity: fehlende Header an einem web-fassenden Origin → Important).
- **AC2 — API-Docs-Exposition-Regel.** Neue Norm-Lane-Regel (`security/R18`): API-Docs/Schema (Swagger-UI, `/docs`,
  `/redoc`, `/openapi.json`, GraphQL-Introspection) in **Produktion** aus oder authentifiziert. Reviewer-Checklist-Zeile
  (öffentliche Schema-Exposition in Prod → Important, Info-Disclosure). Beide Regeln liegen ausschließlich in der
  Norm-Lane (`security/R<NN>`), nicht in der Einsatz-Lane.

### Teil B — Security-Baseline-Scaffold (`templates/` + `new-project`)
- **AC3 — Baseline-Standard (sprach-neutral).** `templates/_shared/security-baseline/README.md` beschreibt den
  Standard: welche Header gesetzt werden, dass API-Docs in Prod aus/geschützt sind, und den `ENV`-Schalter
  (Default: Prod = Docs aus). Sprach-neutral, pro Stack konkretisiert.
- **AC4 — Stack-Baseline Python.** `templates/python/` erhält eine Security-Header-Middleware-Vorlage (FastAPI/Flask;
  setzt die AC1-Header; Docs-Exposition per ENV-Schalter, Prod-Default aus).
- **AC5 — Stack-Baseline JS/Node.** `templates/js/` erhält eine Security-Header-Middleware-Vorlage (Express;
  setzt die AC1-Header; Docs/Introspection per ENV-Schalter).
- **AC6 — new-project-Scaffold (idempotent).** `skills/new-project/SKILL.md` scaffoldet die Baseline für
  **Web-/HTTP-fassende** Projekte (nur dann) aus `templates/_shared/security-baseline/` + `templates/<lang>/` —
  **idempotent** (erneuter Lauf / `/adopt`-`/init`-Pfad überschreibt nicht). Nicht-Web-Projekte (DB-/CLI-only)
  bleiben unberührt. Muster wie DB-Fragment-/Admin-Bereich-Scaffold.
- **AC7 — Kein Laufzeit-Overhead / kein Zwang.** Die Baseline ist eine Header-Middleware (kein messbarer Overhead);
  sie greift nur bei Web-Projekten (AC6).

### Teil C — Lernkreis-Klammer (`red-team` + `retro`)
- **AC8 — Fund-Klassifikation.** `agents/red-team.md`: jeder bestätigte Fund wird als **generisch/universell** oder
  **projekt-spezifisch** klassifiziert (im Protokoll + in der Lesson vermerkt).
- **AC9 — Routing generischer Funde.** `agents/retro.md`: **generische** Härtungs-Funde werden als **Norm-Lane-
  Kandidat** (`security/R<NN>`, via `train`, **ohne** die G1-„≥2 Projekte"-Hürde der Einsatz-Lane) **und** als
  **Baseline-Kandidat** (Teil B) vorgeschlagen — statt im E-Lane-Wartezimmer auf ein Zweitprojekt zu warten.
  **Projekt-spezifische** Funde bleiben der reguläre `security/E<NN>`-Pfad (G1 unverändert). Die **Schreibrechte** der
  Lanes (F-030: Norm=train, Einsatz=retro) bleiben unangetastet — C ändert nur das **Routing**.

## Bewusst NICHT

- Kein Aushebeln der Lane-Schreibrechte (F-030); C routet nur.
- Kein Baseline-Zwang für Nicht-Web-Projekte.
- Keine vollständige Abdeckung aller Stacks in dieser Iteration — Python + JS/Node zuerst; das sprach-neutrale
  README (AC3) ist die Vorlage, der weitere Stacks folgen.
