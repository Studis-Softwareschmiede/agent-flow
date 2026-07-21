---
id: admin-bereich
title: Admin-Bereich
status: draft               # bleibt draft, bis /flow die stack-spezifische Umsetzung im Zielprojekt liefert
version: 1
spec_format: use-case-2.0
area: <bereich-id>           # von requirement beim Scaffold-Lauf zu setzen (docs/specs/board-areas.md AC6)
---

# Spec: Admin-Bereich  (`admin-bereich`)

> **Schicht 3 von 3.** Testbares **Verhalten + Verträge**, sprach-/paradigma-unabhängig (Intent, keine Idiome/Klassen).
> **Source of Truth** für `coder` (baut daraus), `tester` (testet die Acceptance-Kriterien + Coverage-Gate), `reviewer` (prüft den Diff dagegen — hartes Drift-Gate).
>
> **Fabrik-Herkunft.** Diese Spec ist mit dem Projekt gescaffoldet worden (Fabrik-Standard „Admin-Bereich", `docs/architecture/admin-bereich-subsystem.md`). Sie referenziert die dort bindenden Geschäftsregeln `BR-001`…`BR-011` — die **stack-spezifische Implementierung** (Routen, Session-Mechanismus, UI-Rendering) entsteht **projekt-lokal** über `/flow` (GE6) und ist **nicht** Teil des Fabrik-Scaffolds.

## Zweck

Ein passwortgeschützter Admin-Bereich mit deklarativem Konfig-Editor: Login nur mit Passwort (Einzel-Admin), eine generische UI rendert Parameter aus `config/admin-manifest.yaml`, Änderungen landen in einer persistenten Settings-Ablage und wirken zur Laufzeit ohne Neustart.

## Main Success Scenario

1. Admin ruft den Admin-Bereich über das **dezente Icon oben rechts in der Haupt-App-Leiste** auf (trailing header/toolbar, Tooltip „Administration", kein Body-/Fusszeilen-Link — → BR-012/GE8).
2. Ist noch kein `ADMIN_PASSWORD_HASH` gesetzt, zeigt die App die Einrichtungsseite (nur von localhost erreichbar) → Admin setzt initial ein Passwort.
3. Admin loggt sich mit dem Passwort ein.
4. Die Admin-UI rendert die Parameter generisch aus `config/admin-manifest.yaml`.
5. Admin editiert einen editierbaren Parameter → Wert landet in der Settings-Ablage → wirkt sofort, ohne Neustart.

## Alternative Flows

### A1: Erst-Setup (kein `ADMIN_PASSWORD_HASH` gesetzt)
- Die Einrichtungsseite ist **ausschließlich von localhost** erreichbar; auf einem entfernten Host (z.B. dem VPS) ist sie nie erreichbar (Default-deny).

### A2: Passwort ändern
- Ausschließlich über `scripts/set-admin-password.sh` (lokal). Es gibt **keinen** Passwort-Ändern-Weg im Browser-UI.

### E1: Login mit falschem Passwort
- Zugriff verweigert; Fehlversuch zählt gegen die Login-Härtung (BR-009).

### E2: Zu viele Fehlversuche
- Login wird temporär gesperrt / rate-limitiert (BR-009).

### E3: Zugriff auf einen `editierbar: false`-Parameter ändern
- Wird serverseitig abgelehnt (BR-007) — unabhängig davon, ob das UI das Feld anzeigt.

## Acceptance-Kriterien

- **AC1** — Authentifizierung nur mit Passwort, kein Benutzername, genau **ein** Admin je App (→ BR-001).
- **AC2** — Das Passwort wird nie im Klartext gespeichert; `ADMIN_PASSWORD_HASH` ist ein **argon2id**-Hash, verwaltet über das Secrets-Subsystem (`.env` → `.env.gpg`) (→ BR-002).
- **AC3** — Passwort-Änderung ausschließlich über `scripts/set-admin-password.sh`; kein Passwort-Ändern-Pfad im Browser-UI (→ BR-003, deckt A2).
- **AC4** — Ist beim Start kein `ADMIN_PASSWORD_HASH` gesetzt, zeigt die App eine Einrichtungsseite, die **ausschließlich von localhost** erreichbar ist (→ BR-004, deckt A1).
- **AC5** — Wertauflösung: Settings-Ablage > Default aus `quelle` (→ BR-005).
- **AC6** — Änderungen landen in einer persistenten Settings-Ablage (Settings-Tabelle bei DB-Projekten, sonst `settings.json`) auf einem gemounteten Daten-Volume; sie überleben Container-Neustart/Redeploy (→ BR-006).
- **AC7** — Editierbare Parameter wirken zur Laufzeit ohne Neustart; boot-kritische Parameter (`editierbar: false`) sind nur maskiert sichtbar und über kein UI änderbar (→ BR-007, deckt E3).
- **AC8** — Als `secret`/`maskiert` deklarierte Parameter werden im UI immer maskiert ausgeliefert — nie Klartext an den Browser, auch nicht als Vorbelegung eines Eingabefelds (→ BR-008).
- **AC9** — Der Login hat eine Fehlversuch-Sperre / ein Rate-Limit (→ BR-009, deckt E1, E2).
- **AC10** — Die Sitzung läuft über ein signiertes HttpOnly+SameSite-Cookie; alle state-ändernden Admin-Requests sind CSRF-geschützt (→ BR-010).
- **AC11** — Die Admin-UI rendert Parameter ausschließlich aus dem Manifest-Vertrag (`key`, `quelle`, `typ`, `editierbar`, `secret`, `validierung`) — keine hartkodierten Parameter-spezifischen UI-Zweige (→ BR-011).
- **AC12** — Der Admin-Einstieg ist ein dezentes Icon oben rechts in der Haupt-App-Leiste (trailing header/toolbar, Tooltip „Administration", kein Text-Label), **nie** im Body und **nie** als Fusszeilen-Link (→ BR-012, GE8).

> **Traceability:** Jeder Test trägt das kanonische Trace-Tag `@trace admin-bereich#AC<n>[,BR-NNN]`
> gemäss `knowledge/<lang>.md` → `## Spec-Tagging`. Der `tester` rechnet das Coverage-Gate
> (jede genannte AC + jede referenzierte BR ≥ 1 deckender Test). Details: `docs/architecture/traceability-subsystem.md`.

## Verträge

**Manifest-Vertrag (fix, sprach-neutral, → BR-011).** `config/admin-manifest.yaml`, ein Eintrag je Parameter:

```yaml
parameters:
  - key: FEATURE_FLAG_X
    quelle: settings           # env | config.yaml | settings
    typ: bool                  # bool | int | string | enum | secret
    editierbar: true
    secret: false
    validierung: "true|false"
```

**Stack-spezifisch zu konkretisieren (via `/flow` im Zielprojekt — nicht Teil des Scaffolds):**
- Konkrete Routen (z.B. Login-, Setup-, Admin-UI- und Settings-Endpunkte).
- Der Session-Mechanismus (Cookie-Name, Signierung, Framework-Anbindung, → BR-010).
- Das konkrete Schema der Settings-Ablage (Settings-Tabelle vs. `settings.json`, → BR-006).
- Die Anbindung der Login-Härtung / Rate-Limit-Implementierung (→ BR-009).

## Edge-Cases & Fehlerverhalten

- Kein `ADMIN_PASSWORD_HASH` gesetzt **und** Request kommt nicht von localhost → Einrichtungsseite ist nicht erreichbar (BR-004, Default-deny).
- Zu viele Fehlversuche am Login → Sperre/Rate-Limit greift (BR-009).
- Ein `editierbar: false`-Parameter wird per API/Formular geändert → serverseitig abgelehnt, unabhängig vom UI-Zustand (BR-007).
- Ein `secret`/`maskiert`-Parameter → nie Klartext an den Browser, auch nicht als vorbelegter Formularwert (BR-008).

## NFRs

- **Sicherheit:** siehe Security-Floor `knowledge/security.md` (⚑, Fabrik-Spec [[admin-bereich-knowledge-floor]]).
- **Portabilität:** identisches Verhalten unabhängig vom Stack (Login/Manifest/Settings-Präzedenz).
- **Persistenz:** die Settings-Ablage überlebt Redeploys — das Rollout muss das Settings-Daten-Volume mounten (siehe Rollout-Hinweis unten).

## Nicht-Ziele

- Multi-User-/Rollen-Verwaltung — bewusst Einzel-Admin (BR-001).
- Passwort-Änderung im Browser-UI (BR-003).
- Passwort-Reset per E-Mail / Recovery-Flow — vergessen = lokal neu setzen + deployen (BR-003).
- Bitwarden-/Passphrase-Provisionierung — geerbt vom Secrets-Subsystem.

## Rollout-Hinweis (Cross-Repo, § 6 `admin-bereich-subsystem.md`)

Die Settings-Ablage (BR-006) liegt auf einem **gemounteten Daten-Volume**, damit sie Container-Neustart/Redeploy überlebt. `cicd`/`preview` müssen dieses Settings-Daten-Volume beim `docker run` mounten. **Cross-Repo-Hinweis:** ein dev-gui-VPS-Rollout dieses Projekts muss das Settings-Daten-Volume **ebenfalls** mounten — sonst gehen Einstellungen beim Redeploy verloren.

## Abhängigkeiten

- `docs/architecture/admin-bereich-subsystem.md` — bindende Geschäftsregeln `BR-001`…`BR-011` + gelockte Entscheidungen (GE1–GE7).
- [[secrets-subsystem]] — `ADMIN_PASSWORD_HASH` via `.env`/`.env.gpg`; `scripts/set-admin-password.sh` ruft `scripts/encrypt-env.sh`.
- `config/admin-manifest.yaml` — Manifest-Vertrag (BR-011), Startbestand: vorhandene `.env`-Keys.
