# Architecture — Admin-Bereich-Subsystem (Fabrik-Standard für UI-Projekte)

> **Bindend.** Diese Spec beschreibt den **Fabrik-Standard „Admin-Bereich"**: jedes von der Fabrik erzeugte (`/new-project`) oder adoptierte (`/adopt`) **UI-Projekt** erhält einen passwortgeschützten Admin-Bereich mit deklarativem Konfig-Editor — analog zum Playwright-Regressions-Grundgerüst ([[regression-scaffolding]]) und zum Secrets-Subsystem ([[secrets-subsystem]]), auf denen es aufbaut. Sie legt die **Geschäftsregeln (BR-NNN)** fest, die die stack-spezifische Implementierung (durch `coder` via `/flow` im jeweiligen Projekt) erfüllen muss, sowie die **gelockten Entscheidungen (GE)** des Fabrik-Einbaus. Abweichungen sind Review-Kriterium.

---

## 1. Zweck & Scope

**Zweck.** Bisher erfindet jedes UI-Projekt seinen Admin-/Einstellungs-Bereich neu (oder hat gar keinen). Dieses Subsystem macht den Admin-Bereich zur **erstklassigen, einheitlichen Fabrik-Achse**: jedes UI-Projekt trägt ab Tag 1 einen passwortgeschützten Admin-Bereich mit einem **deklarativen Manifest** (`config/admin-manifest.yaml`), aus dem eine generische Admin-UI Parameter anzeigt/editiert. Die Fabrik liefert die **sprach-neutrale Spec-Vorlage**, das **Scaffold-Fragment** (Manifest-Vorlage + `set-admin-password.sh`) und eine **idempotente Board-Story** — die eigentliche Implementierung ist stack-spezifisch und entsteht projekt-lokal über `/flow`.

**Modell in einem Satz.** Login nur mit Passwort (argon2id, Einzel-Admin, Hash via [[secrets-subsystem]] in `.env.gpg`) → generische Admin-UI rendert aus `config/admin-manifest.yaml` → Änderungen landen in einer persistenten **Settings-Ablage** auf einem gemounteten Daten-Volume (**Vorrang: Settings-Ablage > Default**), wirken zur Laufzeit **ohne Neustart**.

**In Scope.**
- Die **Geschäftsregeln (BR-001…BR-011)**, die jede Admin-Bereich-Implementierung erfüllen muss.
- Die **sprach-neutrale Spec-Vorlage** `templates/_docs/specs/admin-bereich.md` (wird bei UI-Projekten mitgescaffoldet, referenziert diese BR).
- Das **Scaffold-Fragment** `templates/_shared/admin/` (Manifest-Vorlage `config/admin-manifest.yaml` + `scripts/set-admin-password.sh`).
- Die **Verdrahtung** in `/new-project`, `/init`, `/adopt` (UI-Projekte: Scaffold + idempotente Board-Story „Admin-Bereich").
- Der **Security-Floor** in `knowledge/security.md` (⚑) + UI-Pack-Guidance zum generischen Manifest-Rendering.
- Der **Rollout-Vertrag**: `cicd`/`preview` mounten das Settings-Daten-Volume; expliziter Hinweis auf den dev-gui-VPS-Rollout.
- Die **requirement-Frage** bei App-Erstellung, welche Parameter ins Manifest sollen (Startbestand: `.env`-Keys).

**Out of Scope.**
- **Multi-User-/Rollen-Verwaltung.** Bewusst **Einzel-Admin** (BR-001) — kein Benutzer-Register, keine Rollen, keine Einladungen.
- **Passwort-Änderung im Browser-UI** (BR-003 — ausschließlich über `set-admin-password.sh`).
- **Die stack-spezifische Implementierung selbst** (Server-Routen, Session-Middleware, UI-Rendering) — die liefert `coder` via `/flow` **im Ziel-Projekt** gegen die gescaffoldete Spec-Vorlage, nicht diese Fabrik-Spec.
- **Passwort-Reset per E-Mail / Recovery-Flow.** Vergessen = lokal neu setzen + deployen (BR-003).
- **Bitwarden-/Passphrase-Provisionierung** — geerbt von [[secrets-subsystem]] (§2 GE1, dev-gui-Sache).

---

## 2. Gelockte Entscheidungen (bindend)

Vorab getroffene Invarianten (Owner-Diskussion abgeschlossen) — **keine** offenen Fragen.

- **GE1 — Einzel-Admin, Passwort-only.** Ein Admin je App, Login **nur** mit Passwort (kein Benutzername). Kein Multi-User-Modell (BR-001).
- **GE2 — Passwort über das bestehende Secrets-Subsystem.** Der argon2id-Hash liegt als `ADMIN_PASSWORD_HASH` in `.env` und wandert verschlüsselt via `.env.gpg` mit ([[secrets-subsystem]]) — **kein** neuer Secret-Mechanismus. Lokal gesetzt, auf dem VPS gilt dasselbe Passwort (dieselbe `.env.gpg`).
- **GE3 — Deklaratives Manifest, generische UI.** Die Admin-UI wird **nicht** pro Parameter handgebaut, sondern rendert **generisch** aus `config/admin-manifest.yaml`. Neue Parameter = Manifest-Zeile, kein UI-Code.
- **GE4 — Settings-Ablage > Default.** `.env`/`config.yaml`/`settings` liefern nur **Defaults**; Änderungen gehen einheitlich in **eine** persistente Settings-Ablage (settings-Tabelle bei DB-Projekten, sonst `settings.json`) auf einem gemounteten Daten-Volume. Vorrang bei der Auflösung: Settings-Ablage > Default (BR-005).
- **GE5 — Boot-kritische Werte sind read-only.** Werte, die nur beim Start greifen (PORT, DB_URL …), sind `editierbar: false` und werden nur **maskiert angezeigt** (BR-007). Alles andere wirkt zur Laufzeit ohne Neustart.
- **GE6 — Fabrik liefert Vorlage + Scaffold + Story, nicht die Implementierung.** `/new-project`/`/init`/`/adopt` scaffolden Manifest-Vorlage + `set-admin-password.sh` + legen **idempotent** eine Board-Story „Admin-Bereich" an. Die stack-spezifische Umsetzung macht `coder` via `/flow` im Ziel-Projekt.
- **GE7 — Nur UI-Projekte.** Der Admin-Bereich wird **nur** bei UI-Projekten gescaffoldet (Profil-Signal `ui`/vorhandene Oberfläche). Nicht-UI-Projekte (reine CLIs/Libs/Bots) erhalten ihn nicht.
- **GE8 — Einstiegspunkt: Icon oben rechts (Owner-Vorgabe 2026-07-21).** Der Admin-Bereich wird über ein **dezentes Icon in der oberen rechten Ecke der Haupt-App-Leiste** erreicht (trailing header/toolbar-Actions — in Flutter `AppBar.actions`, in Angular/HTML das äquivalente trailing-Toolbar-Element). Ein Zahnrad-/`admin_panel_settings`-Outline-Icon mit Tooltip „Administration", **kein** Text-Label, **kein** Eintrag im Body und **kein** Fusszeilen-Link. Grund: eine Body-/Fusszeilen-Platzierung wirkt deplatziert und musste projekt-lokal wiederholt korrigiert werden; der trailing-App-Leisten-Platz ist die konventionelle Stelle für Betreiber-/Kontobereiche. Dezent gehalten (nur Icon), damit der Kundenfluss im Body unberührt bleibt. Der `designer`/`coder` setzt diese Platzierung als Default, ohne dass der Owner sie je erneut vorgeben muss (BR-012).

---

## 3. Geschäftsregeln (BR-NNN)

Die verbindlichen Regeln, die jede Admin-Bereich-Implementierung erfüllt. Die Spec-Vorlage `templates/_docs/specs/admin-bereich.md` referenziert sie; die Fabrik-Specs unter `docs/specs/admin-bereich-*.md` verweisen per `(→ BR-NNN)`.

- **BR-001 — Login.** Authentifizierung nur mit **Passwort** (kein Benutzername); genau **ein** Admin je App (Einzel-Admin). Kein Benutzer-Register.
- **BR-002 — Passwort-Speicherung.** Das Passwort wird **nie** im Klartext gespeichert, sondern als **argon2id**-Hash in `ADMIN_PASSWORD_HASH` (`.env` → verschlüsselt in `.env.gpg`, [[secrets-subsystem]]). Der Hash wird nie im UI ausgegeben.
- **BR-003 — Passwort-Änderung.** Ausschließlich über `scripts/set-admin-password.sh` (Passwort erfragen → argon2id-Hash → `.env` aktualisieren → `encrypt-env.sh` aufrufen). **Nie** im Browser-UI. Vergessenes Passwort → lokal neu setzen + deployen (kein In-App-Recovery).
- **BR-004 — Erst-Setup (localhost-only).** Ist beim Start **kein** `ADMIN_PASSWORD_HASH` gesetzt, zeigt der Admin-Bereich eine **Einrichtungsseite**, die den Hash in die `.env` schreibt. Diese Seite ist **ausschließlich von localhost** erreichbar; auf dem VPS (nicht-localhost-Request) ist sie **nie** erreichbar (Default deny, → `security/R04`).
- **BR-005 — Konfig-Präzedenz.** Bei der Wertauflösung gilt **Settings-Ablage > Default**. `.env`/`config.yaml`/`settings` liefern nur den Ausgangswert; ein in der Settings-Ablage gesetzter Wert überschreibt ihn.
- **BR-006 — Settings-Ablage + Persistenz.** Änderungen gehen in **eine** Settings-Ablage: **settings-Tabelle** bei DB-Projekten, sonst **`settings.json`** — beides auf einem **gemounteten Daten-Volume**, sodass Einstellungen Container-Neustart/Redeploy **überleben**.
- **BR-007 — Laufzeit-Wirkung + Boot-kritische Werte.** Editierbare Parameter wirken **zur Laufzeit ohne Neustart**. Boot-kritische Werte (PORT, DB_URL …) sind `editierbar: false` und werden nur **maskiert angezeigt** (nie über das UI änderbar).
- **BR-008 — Secret-Maskierung.** Als `secret`/`maskiert` deklarierte Parameter werden im UI **maskiert** ausgeliefert (nie Klartext an den Browser, auch nicht als Vorbelegung eines Eingabefelds).
- **BR-009 — Login-Härtung.** Der Login hat eine **Fehlversuch-Sperre / Rate-Limit** (Brute-Force-Schutz).
- **BR-010 — Session + CSRF.** Die Sitzung läuft über ein **signiertes HttpOnly+SameSite-Cookie**; alle state-ändernden Admin-Requests sind **CSRF-geschützt**.
- **BR-011 — Manifest-Vertrag.** Jeder Manifest-Parameter deklariert: `key`, `quelle` (`env` | `config.yaml` | `settings`), `typ`, `editierbar` (bool), `secret`/`maskiert` (bool), `validierung`. Die generische Admin-UI rendert ausschließlich aus diesen Feldern (GE3).
- **BR-012 — Einstiegspunkt-Platzierung.** Der Admin-Einstieg ist ein **dezentes Icon oben rechts in der Haupt-App-Leiste** (trailing header/toolbar-Actions), mit Tooltip „Administration", ohne Text-Label; **nie** im Body und **nie** als Fusszeilen-Link (GE8). Die generische Umsetzung setzt diese Platzierung als Default (kein projekt-lokaler Owner-Eingriff nötig).

---

## 4. Manifest-Vertrag (`config/admin-manifest.yaml`)

Sprach-neutral, ein Eintrag je Parameter (BR-011):

```yaml
# config/admin-manifest.yaml — deklaratives Admin-Manifest (Fabrik-Standard)
parameters:
  - key: FEATURE_FLAG_X          # eindeutiger Parameter-Schlüssel
    quelle: settings             # env | config.yaml | settings  (Herkunft des Defaults)
    typ: bool                    # bool | int | string | enum | secret
    editierbar: true             # false ⇒ boot-kritisch, nur maskiert anzeigen (BR-007)
    secret: false                # true ⇒ im UI maskiert (BR-008)
    validierung: "true|false"    # Validierungsregel (Typ/Range/Regex/Enum)
  - key: DB_URL
    quelle: env
    typ: secret
    editierbar: false            # boot-kritisch (BR-007)
    secret: true                 # maskiert (BR-008)
    validierung: "^postgres(ql)?://"
```

**Auflösungs-Präzedenz (BR-005):** `Settings-Ablage[key]` falls gesetzt, sonst Default aus `quelle`. **Startbestand des Manifests** (Scaffold + requirement-Frage, §7): die vorhandenen `.env`-Keys, konservativ zunächst `editierbar: false` / bei Secret-Namensmuster `secret: true`.

---

## 5. Security-Floor (⚑, `knowledge/security.md`)

Die folgenden Punkte werden als **Security-Floor** (⚑) in `knowledge/security.md` verankert (Fabrik-Spec [[admin-bereich-knowledge-floor]]) und vom `reviewer` **immer** angewandt:

- argon2id statt Klartext für das Admin-Passwort (BR-002, verschärft `security/R06`).
- Fehlversuch-Sperre / Rate-Limit am Login (BR-009).
- Signiertes HttpOnly+SameSite-Session-Cookie (BR-010).
- CSRF-Schutz auf state-ändernden Admin-Requests (BR-010).
- Secrets im UI maskiert, nie Klartext an den Browser (BR-008).
- Setup-Seite nur von localhost (BR-004, `security/R04` Default-deny).

---

## 6. Rollout — Settings-Daten-Volume

**Konsum beim Rollout.** Die Settings-Ablage (BR-006) liegt auf einem **gemounteten Daten-Volume**, damit sie Container-Neustart/Redeploy überlebt. `cicd` und `preview` mounten dieses Volume beim `docker run` (Fabrik-Spec [[admin-bereich-settings-rollout]]). Bei DB-Projekten ist die Settings-Tabelle ohnehin Teil des DB-Volumes; bei Nicht-DB-Projekten wird ein dediziertes Volume für `settings.json` gemountet.

**Cross-Repo-Hinweis (explizit).** Der **dev-gui-VPS-Rollout** muss dieses Settings-Daten-Volume **ebenfalls** mounten — sonst gehen Einstellungen beim Redeploy verloren. Dieser Hinweis steht auch in der Spec-Vorlage (`templates/_docs/specs/admin-bereich.md`), damit er mit jedem UI-Projekt mitwandert.

---

## 7. requirement-Frage bei App-Erstellung

Bei der Erstellung eines UI-Projekts fragt `requirement`, **welche Parameter** ins Admin-Manifest sollen (Fabrik-Spec [[admin-bereich-manifest-intake]]). **Startbestand:** die vorhandenen `.env`-Keys. Die Antwort füllt die Manifest-Vorlage (BR-011). Autonom/ohne Antwort → konservativer Default: alle `.env`-Keys als `editierbar: false` + Secret-Namensmuster (`*_KEY`, `*_TOKEN`, `*_SECRET`, `*_PASSWORD*`, `*_URL`) als `secret: true` — Verfeinerung erfolgt später projekt-lokal.

---

## 8. Build-Wellen

- **Welle 1 — Fundament/Spec** (dieses Dokument + `docs/specs/admin-bereich-*.md`): bindende Geschäftsregeln + Fabrik-Specs. Kein Code.
- **Welle 2 — Scaffold-Fragment + Spec-Vorlage** ([[admin-bereich-scaffolding]] AC1–AC3, AC7): `templates/_docs/specs/admin-bereich.md`, `templates/_shared/admin/` (Manifest-Vorlage, `set-admin-password.sh`).
- **Welle 3 — Wiring** ([[admin-bereich-scaffolding]] AC4–AC6, AC8): `/new-project`/`/init`/`/adopt`-Verdrahtung + idempotente Board-Story; parallel Security-Floor ([[admin-bereich-knowledge-floor]]), Rollout-Volume ([[admin-bereich-settings-rollout]]), requirement-Frage ([[admin-bereich-manifest-intake]]).

**Cross-Wellen-Regel (graceful).** Existiert `templates/_shared/admin/` noch nicht, loggt das Skill-Wiring eine Warn-Zeile statt zu scheitern (analog [[secrets-subsystem]] §12).

---

## 9. Abhängigkeiten

- **[[secrets-subsystem]]** — trägt `ADMIN_PASSWORD_HASH` via `.env`/`.env.gpg` (GE2); `set-admin-password.sh` ruft `encrypt-env.sh`.
- **[[regression-scaffolding]]** — Vorbild für das idempotente Scaffold-Muster (new-project/init/adopt) + Board-Story-Anlage.
- **[[board-areas]]** — Bereichs-Features, unter denen die Fabrik-Stories hängen.
- **Skills/Agenten:** `skills/new-project`, `skills/init`, `skills/adopt`, `skills/preview`; `agents/cicd`, `agents/requirement`, `agents/coder`, `agents/reviewer`.
- **Knowledge:** `knowledge/security.md` (Floor), UI-Pack-Guidance (generisches Manifest-Rendering).
