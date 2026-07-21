# Born-Secure-Baseline — Web-Sicherheit von Geburt an, nicht reaktiv nachgezogen

> **Status:** akzeptiert — in Bau (F-033). Quer-Achse wie `red-team-subsystem.md`. Sprach-**neutral** im Vertrag,
> pro Stack konkretisiert.

## 1. Zweck & Problem

Ein Red-Team-Lauf gegen eine laufende App fand generische, **von Anfang an vermeidbare** Härtungslücken
(fehlende HTTP-Security-Header, öffentlich exponierte API-Docs/Schema). Solche Klassen sind **keine
projekt-spezifische Erfahrung** — sie sind Standard-Härtung (OWASP), die **jedes** Web-Projekt braucht.

Heute fließt solches Wissen nur **reaktiv** zurück: über den Security-Pack, den `coder`/`reviewer` **pro Story**
anwenden. Es fehlt der **proaktive** Kanal — dass ein neues Projekt schon **geboren** mit der Absicherung startet.
Folge: dieselbe Lücke wird in jedem neuen Projekt aufs Neue reaktiv als Fix-Story nachgezogen.

## 2. Zwei Vorwärts-Kanäle (der Kern)

Sicherheitswissen fließt in neue Arbeit über **zwei** Kanäle — die Fabrik nutzte bisher nur den ersten:

| Kanal | Wirkung | Wer | Wann |
|---|---|---|---|
| **Norm-Wissen** (`knowledge/security.md`) | **reaktiv** — beim Bauen/Review geprüft | `coder` + `reviewer` (Floor) | jede Story |
| **Scaffold-Baseline** (`templates/` + `new-project`) | **proaktiv** — Projekt wird sicher **geboren** | `new-project`/`adopt` | einmal beim Aufsetzen |

Beide zusammen = „born secure": das Gerüst bringt die Absicherung mit (Kanal 2), und der Reviewer stellt sicher,
dass sie nicht wieder herausfällt (Kanal 1).

## 3. Die drei Teile (A + B + C)

### A — Norm-Regeln in den Pack (`knowledge/security.md`, Norm-Lane)
Die fehlenden Standard-Härtungen als **Norm-Lane-Regeln** (`security/R<NN>`, train-Hoheit) + Reviewer-Checklist:
- **HTTP-Security-Response-Header** (OWASP Secure Headers): HSTS, CSP, `X-Content-Type-Options: nosniff`,
  `X-Frame-Options`/`frame-ancestors`, `Referrer-Policy`, `Permissions-Policy`, COEP/COOP/CORP.
- **Keine öffentliche API-Docs/Schema-Exposition in Prod**: Swagger-UI/`/docs`/`/redoc`/`/openapi.json`,
  GraphQL-Introspection — in Produktion aus oder authentifiziert.

### B — Security-Baseline im Gerüst (`templates/` + `new-project`)
Ein **Web-Projekt wird geboren** mit:
- einer **Security-Header-Middleware/-Konfiguration** (pro Stack: Python FastAPI/Flask, JS/Node Express, …),
- **API-Docs in Prod aus/geschützt** (per `ENV`-Schalter, Default: in Prod aus).
Ablage sprach-neutral in `templates/_shared/security-baseline/` (Standard + README) + pro Stack in `templates/<lang>/`.
`new-project` scaffoldet es **idempotent** für Web-Projekte (Muster: DB-Fragmente / Admin-Bereich-Scaffold).

### C — Lernkreis-Klammer (Red-Team/retro → die richtigen Kanäle)
- Der `red-team`-Agent **klassifiziert** jeden bestätigten Fund: **generisch/universell** (gilt für jede App der
  Klasse — z.B. fehlende Header) vs. **projekt-spezifisch** (Logik-/Kontext-Fehler dieses Projekts).
- **Generische** Härtungs-Funde sind **Norm-Wahrheiten** → sie gehören in die **Norm-Lane** (via `train`, ohne die
  „≥2 Projekte"-Hürde der Einsatz-Lane) **und** als **Baseline-Kandidat** ins Gerüst (Teil B). `retro` routet sie
  entsprechend (schlägt Norm-/Baseline-Ergänzung vor), statt sie im Einsatz-Lane-Wartezimmer auf ein Zweitprojekt
  warten zu lassen.
- **Projekt-spezifische** Funde bleiben der reguläre Einsatz-Lane-Pfad (`security/E<NN>`, G1 ≥2 Projekte).

**Warum die Unterscheidung zählt:** „Setze Security-Header" braucht keine zwei Sichtungen, um wahr zu sein — es ist
seit Jahren OWASP-Standard. Der Red-Team-Lauf ist nur der **Auslöser**, der zeigt, dass Pack + Gerüst eine
Norm-Regel vermissen lassen.

## 4. Touchpoints

- `knowledge/security.md` — neue Norm-Regeln (A) + Reviewer-Checklist.
- `templates/_shared/security-baseline/` + `templates/<lang>/` — die Baseline (B).
- `skills/new-project/SKILL.md` (+ `/adopt` via `/init`) — scaffoldet die Baseline idempotent (B).
- `agents/red-team.md` — Fund-Klassifikation generisch vs projekt-spezifisch (C).
- `agents/retro.md` — Routing generischer Härtungs-Funde → Norm-Lane/Baseline statt E-Lane-Wartezimmer (C).

## 5. Bewusst NICHT

- **Keine Laufzeit-Schwere.** Die Baseline ist eine Header-Middleware (Mikrosekunden) + weniger Prod-Endpunkte — kein Overhead.
- **Kein Zwang für Nicht-Web-Projekte.** Die Baseline greift nur für Web-/HTTP-fassende Projekte; DB-/CLI-Only-Projekte bleiben unberührt.
- **Kein Aushebeln der Lane-Trennung.** Norm-Lane bleibt train-Hoheit, Einsatz-Lane retro-Hoheit (F-030); C ändert nur das **Routing** eines Fundes in den richtigen Kanal, nicht die Schreibrechte.
