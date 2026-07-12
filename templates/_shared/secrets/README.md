# Template — `secrets`

Scaffold-Fragment für das App-Secrets-Subsystem der Softwareschmiede (Spec [`docs/architecture/secrets-subsystem.md`](../../../docs/architecture/secrets-subsystem.md)).

Dieses Fragment stellt jeder von der Fabrik erzeugten oder adoptierten App ein einheitliches, GPG-symmetrisches Secret-Management zur Verfügung — identisches Muster wie die Fabrik selbst (`scripts/_lib.sh` + `scripts/encrypt-env.sh` etc.).

## Inhalt

| Datei | Zweck |
|---|---|
| `_lib.sh` | Gemeinsame Helfer (nur via `source`): `resolve_pass_file()` — liefert nur ein **explizit** gesetztes `$GPG_PASS_FILE` (keine Auto-Erkennung geteilter Org-Dateien). |
| `encrypt-env.sh` | `.env` → `.env.gpg` (GPG-symmetrisch AES256, loopback). |
| `decrypt-env.sh` | `.env.gpg` → `.env` (`umask 077`, `chmod 600`) — Klartext nur transient lokal. |
| `load-env.sh` | `source scripts/load-env.sh` — entschlüsselt + exportiert Variablen in die Shell (kein Klartext auf der Platte). |
| `.env.example` | Vorlage mit Variablen-Namen, ohne echte Werte — committed, als Startpunkt für `.env`. |
| `gitignore.snippet` | `.gitignore`-Regeln (§5): `.env` ignoriert, `.env.gpg` + `.env.example` negiert (committed). |
| `gitleaks.toml` | gitleaks-Allowlist-Scaffold (§6): erlaubt `^\.env\.gpg$`, alle anderen Klartext-Signale bleiben scharf. |

## Ziel-Layout im App-Repo

Das Scaffold legt nach `/new-project` oder `/adopt` folgendes an:

```
<app>/
  .env                # Klartext, gitignored, NIE committed
  .env.gpg            # verschlüsselt, committed
  .env.example        # Vorlage (committed, keine echten Werte)
  scripts/
    _lib.sh
    encrypt-env.sh
    decrypt-env.sh
    load-env.sh
  .gitleaks.toml      # Allowlist (committed)
  .gitignore          # enthält die §5-Regeln
```

## Workflow (App-Entwickler)

```bash
# Einmalig: Vorlage kopieren und Werte eintragen
cp .env.example .env
# .env editieren ...

# Verschlüsseln und committen
bash scripts/encrypt-env.sh
git add .env.gpg .env.example
git commit -m "chore: update secrets"

# Oder: direkt in die Shell laden (kein Klartext auf Platte)
source scripts/load-env.sh
```

Im **Deploy zur Laufzeit** wird nicht entschlüsselt-auf-Platte gearbeitet: Der
Deploy-Orchestrator (dev-gui) injiziert die Passphrase als `GPG_PASSPHRASE` in den
Container (`docker run -e GPG_PASSPHRASE=…`), und der `docker-entrypoint.sh` der App
entschlüsselt `.env.gpg` damit beim Start. Der Entrypoint nutzt **ausschließlich**
`$GPG_PASSPHRASE` — die lokalen Scripts hier sind bewusst darauf ausgerichtet.

## Passphrase-Kette (PER-APP)

**Jede App hat ihre EIGENE Passphrase.** `encrypt/decrypt/load-env` lösen identisch in
dieser Reihenfolge auf:

```
$GPG_PASSPHRASE  >  $GPG_PASS_FILE (explizit, app-eigen)  >  interaktiver Prompt
```

- **`$GPG_PASSPHRASE`** ist der Regelweg. Sie liegt im Bitwarden-Item **`deploy-gpg-<app>`**
  (`<app>` = Repo-/Service-Name). dev-gui liest sie beim Deploy aus Bitwarden und injiziert
  sie in den Container. Lokal setzt man sie vor dem Ver-/Entschlüsseln in die Umgebung
  (z. B. `export GPG_PASSPHRASE=…`).
- **`$GPG_PASS_FILE`** ist ein optionaler, **explizit** gesetzter Pfad auf eine
  **app-eigene** Passphrase-Datei (keine Auto-Erkennung).
- Ist nichts gesetzt, fragt `gpg` interaktiv.

### ⚠️ Breaking Change / Migration (ehemalige geteilte Org-Datei)

Früher hatten die **geteilten** Dateien `/etc/softwareschmiede/gpg.pass` bzw.
`~/.config/softwareschmiede/gpg.pass` **Vorrang** vor `$GPG_PASSPHRASE`. Das ist
**entfernt**: eine solche geteilte Datei wird **nicht mehr automatisch** herangezogen.
Grund: existierte die geteilte Datei (inzwischen die *eigene* Passphrase von dev-gui),
verschlüsselte `encrypt-env.sh` die App-`.env` versehentlich mit der **falschen**
Passphrase statt mit der per-App-Passphrase — inkonsistent zum Deploy, der `$GPG_PASSPHRASE`
injiziert.

**Wenn deine App bisher auf die geteilte Datei gesetzt hat:**
1. Lege für die App ein Bitwarden-Item **`deploy-gpg-<app>`** mit einer **eigenen**
   Passphrase an (Owner/Setup).
2. **Re-encrypte** die Secrets mit der neuen Passphrase:
   `export GPG_PASSPHRASE="$(…aus Bitwarden…)"; bash scripts/decrypt-env.sh` *(mit der ALTEN
   Passphrase, um `.env` zurückzugewinnen)*, dann `export GPG_PASSPHRASE="<neue>"; bash
   scripts/encrypt-env.sh` und die neue `.env.gpg` committen.
3. Alternativ (Datei-basiert bleiben): `export GPG_PASS_FILE=/pfad/zu/app-eigener.pass`
   **explizit** setzen — die geteilte Org-Datei wird nicht mehr automatisch gefunden.

Das Repo trägt weiterhin kein Schlüssel-Setup (GE1, Spec §3).

## Verweis

Vollständige Spec: [`docs/architecture/secrets-subsystem.md`](../../../docs/architecture/secrets-subsystem.md)
