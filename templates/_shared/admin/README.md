# Template — `admin`

Scaffold-Fragment für den Fabrik-Standard „Admin-Bereich" (Spec [`docs/architecture/admin-bereich-subsystem.md`](../../../docs/architecture/admin-bereich-subsystem.md), Scaffolding-Vertrag [`docs/specs/admin-bereich-scaffolding.md`](../../../docs/specs/admin-bereich-scaffolding.md)).

Dieses Fragment liefert jedem UI-Projekt der Fabrik den Grundstein eines passwortgeschützten Admin-Bereichs — die stack-spezifische Implementierung (Routen, Session, UI-Rendering) macht `coder` via `/flow` im Zielprojekt gegen die mitgescaffoldete Spec-Vorlage (`docs/specs/admin-bereich.md`).

## Inhalt

| Datei | Ziel im App-Repo | Zweck |
|---|---|---|
| `admin-manifest.yaml` | `config/admin-manifest.yaml` | Manifest-Vorlage (→ BR-011): ein Eintrag je Admin-Parameter (`key`, `quelle`, `typ`, `editierbar`, `secret`, `validierung`). Startbestand: die vorhandenen `.env`-Keys des Projekts (Welle-3-Wiring). |
| `set-admin-password.sh` | `scripts/set-admin-password.sh` (executable) | Erfragt ein Passwort, erzeugt einen argon2id-Hash, schreibt `ADMIN_PASSWORD_HASH` in `.env`, ruft `scripts/encrypt-env.sh` auf (→ BR-002, BR-003). |

Die Spec-Vorlage selbst liegt unter `templates/_docs/specs/admin-bereich.md` (→ `docs/specs/admin-bereich.md`).

## Abhängigkeit: Secrets-Subsystem

`set-admin-password.sh` setzt voraus, dass `scripts/encrypt-env.sh` (aus `templates/_shared/secrets/`, siehe [`docs/architecture/secrets-subsystem.md`](../../../docs/architecture/secrets-subsystem.md)) im selben Projekt gescaffoldet ist — beide Fragmente legen ihre Scripts in dasselbe `scripts/`-Verzeichnis.

## Voraussetzung auf dem Host

`set-admin-password.sh` braucht das `argon2`-CLI-Werkzeug (`apt install argon2` / `brew install argon2`). Fehlt es, bricht das Script mit einer klaren Fehlermeldung ab — es gibt **keinen** stillen Klartext-Fallback.

## Verweis

Vollständige Spec: [`docs/architecture/admin-bereich-subsystem.md`](../../../docs/architecture/admin-bereich-subsystem.md), Scaffolding-Vertrag: [`docs/specs/admin-bereich-scaffolding.md`](../../../docs/specs/admin-bereich-scaffolding.md).
