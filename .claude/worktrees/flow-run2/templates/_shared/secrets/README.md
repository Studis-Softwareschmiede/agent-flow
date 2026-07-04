# Template — `secrets`

Scaffold-Fragment für das App-Secrets-Subsystem der Softwareschmiede (Spec [`docs/architecture/secrets-subsystem.md`](../../../docs/architecture/secrets-subsystem.md)).

Dieses Fragment stellt jeder von der Fabrik erzeugten oder adoptierten App ein einheitliches, GPG-symmetrisches Secret-Management zur Verfügung — identisches Muster wie die Fabrik selbst (`scripts/_lib.sh` + `scripts/encrypt-env.sh` etc.).

## Inhalt

| Datei | Zweck |
|---|---|
| `_lib.sh` | Gemeinsame Helfer (nur via `source`): `resolve_pass_file()` — identische Kopie der Fabrik-`scripts/_lib.sh`. |
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

# Im Deploy: entschlüsseln
bash scripts/decrypt-env.sh
# → .env (0600) liegt lokal
docker run -d --env-file .env ...

# Oder: direkt in die Shell laden (kein Klartext auf Platte)
source scripts/load-env.sh
```

## Passphrase-Kette

`resolve_pass_file()` löst in dieser Reihenfolge auf:

```
$GPG_PASS_FILE  >  /etc/softwareschmiede/gpg.pass  >  ~/.config/softwareschmiede/gpg.pass  >  $GPG_PASSPHRASE  >  interaktiver Prompt
```

Die geteilte Fabrik-Passphrase (Bitwarden-Item `studis-softwareschmiede-gpg-passphrase`) muss auf dem Host in einer der vier Quellen provisioniert sein. Das Repo trägt keinen Schlüssel-Setup (GE1, Spec §3).

## Verweis

Vollständige Spec: [`docs/architecture/secrets-subsystem.md`](../../../docs/architecture/secrets-subsystem.md)
