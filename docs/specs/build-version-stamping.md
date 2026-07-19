---
id: build-version-stamping
title: Build-Versionierung als Scaffold-Standard — EINE Quelle, Datei-gebrannte Version, OCI-Labels, Frontend-no-cache
status: active
version: 1
spec_format: use-case-2.0
area: vorlagen-scaffolding
---

# Spec: Build-Versionierung als Scaffold-Standard  (`build-version-stamping`)

> **Schicht 3 von 3.** Testbares **Verhalten + Verträge**, sprach-/paradigma-unabhängig (Intent, keine Idiome/Klassen).
> **Source of Truth** für `coder` (ändert die Sprach-Templates + verdrahtet die Endpunkt-Vorlage ins Bootstrap), `reviewer` (Drift-Gate + Konsistenz aller Sprach-Templates), `tester` (prüft die AC).
>
> **Subsystem-Bindung.** Diese Spec macht robuste, konsistente Build-Versionierung zum **Scaffold-Default in JEDEM Projekt** — als Ergänzung des Framework-/Build-Subsystems (`docs/architecture/framework-build-subsystem.md`). Sie definiert **was** jedes generierte Projekt an Versionierungs-Bausteinen mitbringt; die cicd-seitige Stempel-/Verifikations-Mechanik liegt in der Schwester-Spec [[build-version-verification]].

## Zweck

Die angezeigte Version eines Projekts soll **immer** dem tatsächlich laufenden Image entsprechen — und **nie wieder nach einem Container-Update einfrieren**. Jedes generierte Projekt bringt dafür von Anfang an dasselbe robuste Muster mit: EINE Build-Zeit-Quelle (`APP_VERSION` + git-SHA), eine ins Image **gebrannte Versions-Datei** als Selbstauskunfts-Quelle (nicht ENV), OCI-Standard-Labels aus derselben Quelle, und bei Web-Frontends dieselbe Version zur Build-Zeit ins Frontend kompiliert plus no-cache-Auslieferung des Einstiegs.

## Kontext / Designnuancen (bindend)

- **Vorfall-Herkunft (flashrescue 2026-07-19):** Die Version kam aus der ENV-Variable `APP_VERSION`. Container-Recreate-Werkzeuge (z.B. dev-guis „Update") übernehmen beim Neuaufbau die ENV des Alt-Containers **1:1** — inkl. der alten `APP_VERSION` — und überschreiben damit die des neuen Images. Ergebnis: neuer Code, eingefrorene Versionsanzeige. Der datierte Befund + die Regel-IDs leben in `knowledge/cicd.md` ([[build-version-verification]] AC4/AC5).
- **ENV ist überschreibbar, eine Image-Datei nicht.** Die Selbstauskunft (`/version`) liest deshalb aus einer **beim Build ins Image gebrannten Datei**, nicht aus der ENV. Fallback-Kette **Datei → ENV → "dev"**, fail-soft (nie 5xx).
- **Eine App kann ihre eigenen OCI-Labels von INNEN nicht lesen** (das sind Registry-/`docker inspect`-Metadaten, nicht Prozess-sichtbar). OCI-Labels sind das **Standard-Image-Metadatum für Tools/Registry**, NICHT die `/version`-Quelle. Deshalb Datei für Selbstauskunft **plus** Labels ergänzend.
- **Fabrik liefert Muster, nicht die App-Implementierung.** Die geänderten Sprach-Dockerfiles + der geteilte CI-Workflow sind Scaffold-Direktartefakte (wie heute); die konkrete `/version`-Route ist `coder`-Arbeit im Ziel-Projekt gegen die gescaffoldete Endpunkt-Vorlage (Vorbild [[admin-bereich-scaffolding]]).

## Main Success Scenario

1. CI baut bei Push ein Image und übergibt `--build-arg APP_VERSION=<build-version>` **und** die git-SHA aus **einer** Quelle.
2. Das Dockerfile **brennt die Version zur Build-Zeit in eine Datei** im Image und setzt die OCI-Standard-Labels aus denselben Werten.
3. Der `/version`-Endpunkt liest die Version aus der **gebrannten Datei** (Fallback: ENV → "dev", fail-soft).
4. Bei einem Web-Frontend wird dieselbe Version zur Build-Zeit **ins Frontend kompiliert**, und der Einstieg (`index.html`) wird mit no-cache/kurzer Cache-Control ausgeliefert.
5. Nach jedem Deploy zeigen App-`/version`, GUI-Stempel und OCI-Image-Label **dieselbe, neueste** Build-Version — unabhängig davon, wie der Container neu aufgebaut wird.

## Alternative Flows

### A1: Service-Projekt-Bootstrap (Endpunkt-Vorlage)
- `new-project`/`adopt` scaffolden bei Service-Projekten die sprach-neutrale `/version`-Endpunkt-Spec-Vorlage und legen **idempotent** eine Board-Story „Version-Endpunkt" (To Do) an, gegen die `coder` via `/flow` die stack-spezifische Route baut.

### E1: Versions-Datei fehlt zur Laufzeit
- Fehlt die gebrannte Datei (z.B. lokaler `docker run` ohne Build-Arg), liefert `/version` den ENV-Wert, sonst `"dev"` — **fail-soft, nie 5xx**.

## Acceptance-Kriterien

- **AC1** — EINE Build-Zeit-Quelle: `templates/_shared/build.yml` übergibt `--build-arg APP_VERSION=<build-version>` **und** die git-SHA (`github.sha`) an `docker/build-push-action`; alle abgeleiteten Metadaten (Datei, ENV, Labels) stammen aus diesen Werten — **keine** zweite Versionsquelle. *(deckt Muster 1)*
- **AC2** — Jedes **Service-Dockerfile** (`js`, `java`, `python`) nimmt `ARG APP_VERSION` (+ git-SHA-ARG) entgegen und **brennt die Version zur Build-Zeit in eine unveränderliche Image-Datei** (kanonischer Pfad `/app/VERSION`); die Datei ist Image-Bestandteil, nicht ENV-abgeleitet. *(deckt Muster 2)*
- **AC3** — Der `/version`-Endpunkt-Vertrag liest die Version aus der gebrannten **Datei**, nicht aus der ENV; Fallback-Kette **Datei → ENV → "dev"**, fail-soft (nie 5xx). *(deckt Muster 2, E1)*
- **AC4** — Jedes Dockerfile (Service **und** Frontend) setzt die **OCI-Standard-Labels** `org.opencontainers.image.version` (=`APP_VERSION`), `org.opencontainers.image.revision` (=git-SHA), `org.opencontainers.image.created` (=Build-Zeit UTC) aus derselben Quelle; im geteilten `build.yml` leiten sich dieselben Labels aus `APP_VERSION`/git-SHA ab (z.B. `docker/metadata-action`-Inputs), nie aus einer abweichenden zweiten Quelle. *(deckt Muster 3)*
- **AC5** — Die Spec dokumentiert explizit die Invariante: eine App kann ihre **eigenen OCI-Labels von innen nicht lesen** (Registry-/`docker inspect`-Metadaten) — Labels sind Tool-/Registry-Metadatum, **nicht** die `/version`-Quelle; deshalb Datei für Selbstauskunft **plus** Labels ergänzend. *(Design-Invariante, deckt Muster 3)*
- **AC6** — **Web-Frontend-Dockerfiles** (`html`, `flutter`, `angular`) kompilieren dieselbe Version zur **Build-Zeit ins Frontend** (Version-Stempel-Artefakt im served-dir, z.B. `version.json` bzw. Framework-Inject wie `--dart-define`/Build-Env) **und** liefern den Einstieg (`index.html`) mit `Cache-Control: no-cache`/kurzer Cache-Control aus (nginx-Konfiguration), damit die GUI-Version beim Deploy sofort mitzieht (kein langlebiger Edge-Cache). *(deckt Muster 4)*
- **AC7** — Das Muster ist **Scaffold-Default in JEDEM Projekt**: die geänderten Template-Dockerfiles + `build.yml` gelten für **alle** Sprach-Templates mit Image-Build (`js`, `java`, `python`, `html`, `flutter`, `angular`) — neue Projekte erhalten das Muster ohne Handarbeit; die Sprach-Templates sind untereinander **konsistent** (gleicher `APP_VERSION`-ARG-Name, gleicher Datei-Pfad, gleiche Label-Keys). *(Standard-Vorgabe)*
- **AC8** — Die Fabrik trägt eine **sprach-neutrale Versions-Endpunkt-Spec-Vorlage** (`templates/_docs/specs/version-endpoint.md`) nach `_template.md`-Muster + `new-project`/`adopt`-Wiring, das sie bei Service-Projekten **idempotent** scaffoldet und **idempotent** eine Board-Story „Version-Endpunkt" (Status To Do) anlegt, die auf die gescaffoldete Spec zeigt (Vorbild [[admin-bereich-scaffolding]]); die stack-spezifische Implementierung macht `coder` via `/flow`. *(Scaffold-Standard, deckt A1)*

> **Traceability:** Jeder Test trägt das kanonische Trace-Tag `@trace build-version-stamping#AC<n>`
> gemäss `knowledge/<lang>.md` → `## Spec-Tagging`. Der `tester` rechnet das Coverage-Gate
> (jede genannte AC ≥ 1 deckender Test). Details: `docs/architecture/traceability-subsystem.md`.

## Verträge

### Geänderte / neue Scaffold-Artefakte
```
templates/_shared/build.yml            # build-args APP_VERSION + git-SHA; OCI-Labels aus derselben Quelle
templates/js/Dockerfile                # ARG APP_VERSION → /app/VERSION brennen + OCI-LABEL
templates/java/Dockerfile              # ARG APP_VERSION → /app/VERSION brennen + OCI-LABEL
templates/python/Dockerfile            # ARG APP_VERSION → /app/VERSION brennen + OCI-LABEL
templates/html/Dockerfile              # ARG APP_VERSION → version.json in served-dir + nginx no-cache index.html + OCI-LABEL
templates/flutter/Dockerfile           # ARG APP_VERSION → --dart-define/version.json + nginx no-cache index.html + OCI-LABEL
templates/angular/Dockerfile           # ARG APP_VERSION → Build-Env/version.json + nginx no-cache index.html + OCI-LABEL
templates/_shared/<nginx-no-cache-snippet>   # geteilte nginx-Konfig für no-cache index.html (Frontend-Templates)
templates/_docs/specs/version-endpoint.md    # NEU: sprach-neutrale /version-Endpunkt-Spec-Vorlage (Bootstrap-kopiert)
<Board-Story „Version-Endpunkt">       # idempotent, To Do, spec: docs/specs/version-endpoint.md (im Ziel-Projekt)
```

### `/version`-Endpunkt (Vertrag der gescaffoldeten Vorlage)
```
GET /version   →  200  { "version": "<APP_VERSION>", "revision": "<git-sha>", "source": "file|env|dev" }
```
- Quelle: gebrannte Image-Datei `/app/VERSION` (bzw. served `version.json`) — **nicht** ENV.
- Fallback: Datei fehlt → ENV `APP_VERSION` → `"dev"`. **Nie 5xx** (fail-soft).

### OCI-Labels (aus der EINEN Quelle)
| Label | Wert |
|---|---|
| `org.opencontainers.image.version` | `APP_VERSION` (Build-Version) |
| `org.opencontainers.image.revision` | git-SHA |
| `org.opencontainers.image.created` | Build-Zeit (UTC, ISO-8601) |

## Edge-Cases & Fehlerverhalten

- **Lokaler `docker build` ohne `--build-arg APP_VERSION`** → `ARG APP_VERSION=dev` als Default; gebrannte Datei enthält `dev`, `/version` liefert `dev` (kein Fehler).
- **Container-Recreate mit übernommener Alt-ENV** → irrelevant: `/version` liest die Datei, nicht die ENV; die Anzeige zieht mit dem neuen Image mit (Kern-Ziel).
- **Frontend ohne serverseitigen Endpunkt** (statisches nginx) → Version als Stempel-Artefakt im served-dir (`version.json`/Meta), Einstieg no-cache → GUI zeigt die neue Version nach Hard-Reload/Deploy sofort.

## NFRs

- **Konsistenz-Ziel (Akzeptanz):** nach jedem Deploy zeigen App-`/version`, GUI-Stempel und OCI-Image-Label **dieselbe, neueste** Build-Version — unabhängig vom Container-Aufbauweg.
- **Robustheit:** `/version` ist fail-soft (nie 5xx); fehlende Datei degradiert sauber.
- **Portabilität:** identisches Versionierungs-Muster über alle Sprach-Templates (gleicher ARG/Pfad/Label-Vertrag).

## Nicht-Ziele

- Die cicd-seitige Stempel-/Verifikations-Mechanik (version-stamp-Modus, Rollout-Abgleich, knowledge/cicd.md-Rationale) — Schwester-Spec [[build-version-verification]].
- Die konkrete stack-spezifische `/version`-Route-Implementierung — projekt-lokal via `/flow` (coder).
- Registry-Retention/Tagging-Strategie (Rollback-Tags) — bestehendes cicd-Wissen (`cicd/F05`).

## Abhängigkeiten

- `docs/architecture/framework-build-subsystem.md` — Sprach-/Build-Achsen, in die dieses Muster einhakt.
- [[build-version-verification]] — cicd-Stempel/-Verifikation + knowledge/cicd.md-Regel-IDs (Schwester-Spec, Bereich `auslieferung`).
- [[admin-bereich-scaffolding]] — Vorbild für idempotentes Bootstrap-Scaffold + Board-Story-Anlage (Endpunkt-Vorlage).
- `skills/new-project`, `skills/adopt` — Bootstrap-Skills, in die das Endpunkt-Wiring (AC8) eingebaut wird.
