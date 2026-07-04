# Architecture — Secrets-Subsystem (GPG-symmetrisch, geteilte Fabrik-Passphrase)

> **Bindend.** Diese Spec beschreibt **wie** jede von der Fabrik **erzeugte** (`/new-project`) oder **adoptierte** (`/adopt`) Applikation ihre Secrets standardisiert verwaltet: Klartext in `.env` (gitignored), verschlüsselte, committete Kopie `.env.gpg` (GPG-symmetrisch AES256), aufgelöst über die geteilte Fabrik-Passphrase. Sie verdrahtet das bestehende GPG-Muster der Fabrik (`scripts/{_lib.sh,encrypt-env,decrypt-env,load-env}.sh`) als per-App-Scaffold, reconciled es mit dem Secret-Scan-Gate (`security/R01` + gitleaks) und legt den Laufzeit-Konsum beim Rollout fest. Implementierung erfolgt in drei Wellen (Fundament/Spec → Scaffold → Wiring; §12). Abweichungen sind Review-Kriterium.

---

## 1. Zweck & Scope

**Zweck.** Bisher löst die Fabrik **ihre eigenen** Secrets (GitHub-App-Credentials für `gh`) über `.env.gpg` + `scripts/load-env.sh`. Die von der Fabrik betreuten **Applikationen** haben jedoch keinen standardisierten Secret-Mechanismus — jede App erfindet ihn neu (oder committet Klartext, was das Secret-Scan-Gate blockiert). Diese Spec macht den App-Secret-Aspekt zur **erstklassigen, einheitlichen** Achse: jede App trägt `.env` (Klartext, lokal) + `.env.gpg` (verschlüsselt, committet) + ein schlankes per-App-Script-Set, das exakt das bestehende Fabrik-Muster spiegelt.

**Modell in einem Satz.** `.env` ist die lokale Klartext-Wahrheit (NIE committed); `.env.gpg` ist die verschlüsselte, **committete** Repräsentation; die Verschlüsselung ist GPG-symmetrisch AES256 mit der **geteilten** Fabrik-Passphrase; konsumiert wird **zur Laufzeit** beim Rollout (`decrypt → docker run --env-file .env`).

**In Scope.**
- Das `.env` / `.env.gpg`-Dateimodell + per-App-Script-Set (`encrypt-env.sh`, `decrypt-env.sh`, `load-env.sh`, `_lib.sh`).
- Schlüssel-Auflösung über die geteilte Passphrase-Kette (`resolve_pass_file()`, §3).
- `.gitignore`- + gitleaks-Allowlist-Konvention (Klartext blockiert, `.env.gpg` erlaubt — §5, §6).
- Reconciliation mit `security/R01` + dem Secret-Scan-Gate (`build.yml`, `security.yml`).
- Laufzeit-Konsum beim Rollout (`--env-file`, §7).
- Verdrahtung in `/new-project` (initial leeres `.env.gpg`) und `/adopt` (Audit-Finding für Klartext-`.env` in der History).
- `coder`/`/flow` Re-Encrypt-Konvention + Sync-Gate (ist `.env.gpg` aktuell ggü. `.env`? — §9).

**Out of Scope (P1).**
- **Per-App-Bitwarden-Item / per-App-Schlüssel.** Gelockt: EIN geteilter Schlüssel für alle Apps (§3, GE1). Kein Bitwarden-Schritt in `/new-project`.
- **Build-Time-Secret-Konsum** (z.B. private Registries, Build-Args mit Secrets). Pfad dokumentiert, aber **inaktiv** (§8 — „Tür offen, nicht beschritten").
- **History-Rewrite adoptierter Repos.** Vorhandenes Klartext-`.env` in der History wird **nicht** umgeschrieben — nur als Audit-Finding gemeldet (§11, GE5).
- **Secret-Rotation / Versionierung der Passphrase.** Die Passphrase ist umgebungs-gebunden (Bitwarden-Item `studis-softwareschmiede-gpg-passphrase`); ihre Rotation ist ein Ops-Vorgang außerhalb dieses Subsystems.
- **Asymmetrische GPG / per-Recipient-Keys, SOPS, Vault, sealed-secrets.** Bewusst nicht — das bestehende symmetrische Muster der Fabrik wird wiederverwendet (GE2), kein neuer Mechanismus.

---

## 2. Gelockte Entscheidungen (bindend)

Diese Festlegungen sind **vorab getroffen** und in dieser Spec bindend — sie sind **nicht** offene Fragen, sondern Invarianten, an denen `reviewer`/`dba`/`tester` messen.

- **GE1 — Schlüssel-Scope: EIN geteilter Schlüssel für alle Apps.** Wiederverwendung des bestehenden Bitwarden-Items `studis-softwareschmiede-gpg-passphrase`. **KEIN** per-App-Bitwarden-Item, **KEIN** Bitwarden-Schritt in `/new-project`. Begründung: Die Passphrase ist **umgebungs-gebunden** (lebt auf dem Fabrik-Host/-Operator), nicht repo-gebunden — sie wandert nicht mit dem Repo, also braucht das Repo keinen eigenen Schlüssel-Setup-Schritt.
- **GE2 — Mechanismus: bestehendes GPG-Muster wiederverwenden.** Die per-App-Scripts sind **schlanke Kopien** von `scripts/{encrypt-env,decrypt-env,load-env}.sh` + `_lib.sh` mit **identischer** Passphrase-Kette (§3). Kein neuer Krypto-Mechanismus, kein Eigenbau (`security/R06`).
- **GE3 — Konsum-Zeitpunkt: NUR zur Laufzeit.** Beim Deploy/Rollout `.env.gpg` → entschlüsseln → `docker run --env-file .env`. GitHub Actions / Docker-Build brauchen **KEINEN** Schlüssel (§7, §8).
- **GE4 — Initial: leeres `.env.gpg` ab Tag 1.** `/new-project` legt sofort ein initiales (leeres/Platzhalter-)verschlüsseltes `.env.gpg` an und committet es, damit `.gitignore`/gitleaks-Allowlist/Script-Pfade ab Tag 1 erprobt sind (§10).
- **GE5 — Adopt: kein History-Rewrite.** Hat ein adoptiertes Repo bereits ein unverschlüsseltes `.env` in der History → **kein** History-Rewrite; stattdessen Audit-Finding aufs Board (§11).
- **GE6 — Reconciliation: Klartext bleibt scharf, `.env.gpg` explizit erlaubt.** `security/R01` + gitleaks bleiben für **Klartext** scharf (hartkodiertes/unverschlüsseltes Secret = Critical/Fail). Der verschlüsselte `.env.gpg`-Blob wird **explizit** per gitleaks-Allowlist erlaubt (Scaffold-Standard) — sonst blockiert die Fabrik den eigenen Commit (§6).

---

## 3. Schlüssel-Auflösung — die geteilte Passphrase-Kette

**Quelle.** Die Fabrik nutzt heute schon `resolve_pass_file()` in `scripts/_lib.sh`. Das per-App-`_lib.sh` ist eine **identische Kopie** dieser Funktion — keine Abweichung, keine projekt-spezifische Variante.

**Auflösungs-Kette (exakt wie heute, `scripts/_lib.sh`):**

```
$GPG_PASS_FILE  >  /etc/softwareschmiede/gpg.pass  >  ~/.config/softwareschmiede/gpg.pass  >  $GPG_PASSPHRASE  >  interaktiver Prompt
```

- Erste les-/vorhandene Quelle gewinnt (`resolve_pass_file()` gibt den Pfad zurück; ist keine Datei da, fällt `encrypt`/`decrypt`/`load-env` auf `$GPG_PASSPHRASE` bzw. den interaktiven Prompt zurück).
- **Passphrase-Inhalt** = das Bitwarden-Item `studis-softwareschmiede-gpg-passphrase` (geteilt, GE1). Wie die Datei `gpg.pass` auf den Host kommt (manuell, via `scripts/setup-bw-items.sh`-Analogon, Ops-Provisioning), ist **außerhalb** dieses Subsystems — die App-Scripts kennen nur die Kette, nicht die Bitwarden-Mechanik.
- **Cipher:** GPG-symmetrisch, `--cipher-algo AES256`, `--pinentry-mode loopback` (batch-fähig, kein TTY-Pinentry). Identisch zu `scripts/encrypt-env.sh`.

**Warum geteilt statt per-App (GE1, Begründung als Invariante).** Die Passphrase lebt im Operator-Environment (eine der vier Quellen oben), nicht im Repo. Damit ist `.env.gpg` portabel — jeder Fabrik-Host mit der provisionierten Passphrase kann jede App entschlüsseln; das Repo trägt kein Schlüssel-Setup, `/new-project` braucht keinen Bitwarden-Schritt.

---

## 4. Per-App-Script-Set (Scaffold-Fragment `templates/_shared/secrets/`)

Das Scaffold-Fragment liegt unter **`templates/_shared/secrets/`** (gleiche Klasse wie `templates/_shared/db-<dialect>/`) und enthält schlanke Kopien des Fabrik-Musters (GE2):

```
templates/_shared/secrets/
  _lib.sh             # identische Kopie von scripts/_lib.sh (resolve_pass_file)
  encrypt-env.sh      # .env  → .env.gpg   (symmetric AES256, loopback)
  decrypt-env.sh      # .env.gpg → .env     (umask 077, chmod 600 .env)
  load-env.sh         # source: entschlüsselt + exportiert .env-Variablen in die Shell
  .env.example        # Vorlage (Variablen-Namen, KEINE echten Werte) → vom Scaffold nach .env kopierbar
  gitignore.snippet   # die .env-/Klartext-Regeln (§5) zum Anhängen an .gitignore
  gitleaks.toml       # gitleaks-Allowlist-Scaffold (.env.gpg erlaubt — §6)
```

**Ziel-Layout im App-Repo** (wohin das Scaffold die Scripts legt):

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

**Script-Verträge (sprach-neutral, alle Dialekte/Stacks identisch):**

| Script | Aufruf | Vor-Bedingung | Wirkung | Nach-Bedingung |
|---|---|---|---|---|
| `encrypt-env.sh` | `bash scripts/encrypt-env.sh` | `.env` existiert | `gpg --symmetric --cipher-algo AES256` über `.env` → `.env.gpg` | `.env.gpg` aktuell ggü. `.env`; `.env` unverändert |
| `decrypt-env.sh` | `bash scripts/decrypt-env.sh` | `.env.gpg` existiert | `gpg -d .env.gpg` → `.env` (`umask 077`, danach `chmod 600 .env`) | `.env` (0600) liegt lokal, gitignored |
| `load-env.sh` | `source scripts/load-env.sh` | `.env.gpg` existiert (sonst no-op-Hinweis) | entschlüsselt + `set -a; eval …; set +a` → Variablen in der aktuellen Shell | App-Env-Variablen exportiert (kein Klartext auf Platte nötig) |

**Pflicht-Eigenschaften (Review-Kriterium):**
- Alle drei Scripts nutzen **dieselbe** Passphrase-Kette über `source scripts/_lib.sh` (§3) — keine inline-Passphrase, kein hartkodierter Pfad außer den Ketten-Default-Pfaden.
- `decrypt-env.sh` setzt `umask 077` **vor** dem Schreiben und `chmod 600 .env` **danach** (Klartext nie world-readable).
- Kein Script committet, pusht oder ruft `gh`/Netzwerk auf — sie sind reine lokale Krypto-Helfer (im Gegensatz zum Fabrik-eigenen `load-env.sh`, das zusätzlich einen GitHub-App-Token mintet; die **App-Variante ist auf die env-Mechanik reduziert**, ohne Token-Mint).
- `set -euo pipefail` in den ausführbaren Scripts; `_lib.sh` wird nur ge-`source`d, nie direkt ausgeführt.

---

## 5. `.gitignore`-Konvention

Das Scaffold hängt (idempotent — nicht doppelt anhängen) die folgenden Regeln an die `.gitignore` des App-Repos an (Quelle: `templates/_shared/secrets/gitignore.snippet`):

```gitignore
# Plaintext-Secrets — NIE committen (nur .env.gpg ist versioniert)
.env
.env.*           # .env.local, .env.production etc. — alle Klartext-Varianten
!.env.example    # Vorlage MIT committen (keine echten Werte)
!.env.gpg        # verschlüsselt — committet
*.plain
```

**Invarianten:**
- `.env` und alle `.env.*`-Klartext-Varianten sind ignoriert.
- `.env.example` ist **negiert** (committed — Vorlage mit Variablen-Namen, ohne echte Werte).
- `.env.gpg` ist **negiert** (committed — der verschlüsselte Blob).
- Die Reihenfolge der Negationen ist relevant (`.env.*` ignoriert, danach `!.env.example` / `!.env.gpg` re-included).

---

## 6. gitleaks-Allowlist-Konvention + Reconciliation mit `security/R01`

**Das Spannungsfeld.** Das Secret-Scan-Gate (`templates/_shared/build.yml` `secret-scan`-Job + `templates/_shared/security.yml` History-Scan) läuft gitleaks über das Repo. Ein **committeter** `.env.gpg` ist hochentropisches Binär-/Base64-Material → gitleaks würde es als „Secret" flaggen und den **eigenen** Commit der Fabrik blockieren. Gleichzeitig muss `security/R01` (kein Klartext-Secret) **scharf** bleiben.

**Auflösung (GE6) — zwei Sphären sauber getrennt:**

| Artefakt | gitleaks | `security/R01` / Reviewer |
|---|---|---|
| Klartext-Secret im Code/Repo (hartkodiert, in `.env` versehentlich committed, in YAML/SQL) | **Fail** (Treffer) | **Critical** — bleibt scharf |
| `.env.gpg` (verschlüsselter Blob) | **Allowlisted** (kein Treffer) | **erlaubt** — explizit, weil verschlüsselt |
| `.env` (Klartext) im Repo committed | **Fail** (von `.gitignore` ohnehin verhindert; rutscht es durch → Treffer) | **Critical** |

**gitleaks-Allowlist-Scaffold** (`templates/_shared/secrets/gitleaks.toml` → App-`.gitleaks.toml`):

```toml
# Scaffold-Standard der Softwareschmiede — Secrets-Subsystem.
# Erlaubt NUR den verschlüsselten .env.gpg-Blob. Klartext bleibt scharf (security/R01).
[extend]
useDefault = true   # alle eingebauten gitleaks-Regeln bleiben aktiv

[allowlist]
description = "Verschlüsselte Secret-Datei (GPG symmetric AES256) — bewusst committet"
paths = [
  '''^\.env\.gpg$''',   # NUR exakt .env.gpg — NICHT .env, NICHT .env.*
]
```

**Invarianten (Review-Kriterium, hart):**
- Die Allowlist erlaubt **ausschließlich** `^\.env\.gpg$` (Anchor auf genau diese Datei). Eine Allowlist, die `.env` oder `.env.*` (Klartext) mit-allowlisted, ist ein **Critical**-Befund (sie würde `security/R01` aushebeln).
- `useDefault = true` bleibt gesetzt — die Allowlist **erweitert** das Default-Regelset, sie ersetzt es nicht.
- Sowohl `build.yml` (`--no-git`, push-Scan) als auch `security.yml` (History-Scan) respektieren `.gitleaks.toml` automatisch (gitleaks lädt die Repo-Root-Config). Es ist **kein** zusätzliches Flag in den Workflows nötig — der `cicd`-Agent härtet die Allowlist nur „mit Beweis" (siehe `cicd.md` Abschnitt E, „gitleaks-Whitelist nur mit Beweis"); der `.env.gpg`-Eintrag **ist** der dokumentierte, bewiesene Standard-Fall.

**`security/R01`-Präzisierung (landet in `knowledge/security.md` — §13, Item #4).** Der Floor-Wortlaut wird von „Keine Secrets im Code/Repo" geschärft zu: *Klartext-Secrets (Keys/Tokens/Passwörter/Connection-Strings) im Repo → Critical; die **verschlüsselte** `.env.gpg`-Datei (GPG symmetric, geteilte Fabrik-Passphrase) ist der **vorgesehene** Weg, App-Secrets versioniert mitzuführen, und ist KEIN Befund.* Die Reviewer-Checklist erhält den Spiegel-Eintrag.

---

## 7. Laufzeit-Konsum beim Rollout (`--env-file`)

**Konsum-Zeitpunkt (GE3): NUR zur Laufzeit.** Der `cicd`-Agent (bzw. `/preview`) entschlüsselt beim Rollout und übergibt die Variablen via `--env-file`:

```bash
# Rollout-Sequenz (cicd / preview), auf dem Deploy-Host mit provisionierter Passphrase:
bash scripts/decrypt-env.sh                 # .env.gpg → .env (0600), Passphrase aus der Kette (§3)
docker run -d --name "$app" \
  --env-file .env \                         # Laufzeit-Injektion der App-Secrets
  -p "${preview_port}:${container_port}" \
  "${image}:latest"
```

**Invarianten:**
- Der Klartext `.env` existiert nur **transient auf dem Deploy-Host** (gitignored, 0600). Er wird **nie** ins Image gebacken und **nie** committed.
- Das **Image selbst enthält keine App-Secrets** — die Secret-Injektion ist eine Laufzeit-Eigenschaft des Containers, nicht des Images. Damit ist ein in `ghcr.io` veröffentlichtes Image frei von App-Secrets (defense-in-depth: selbst ein öffentlich gepulltes Image leakt nichts).
- Der `cicd`-Rollout (`agents/cicd.md` Abschnitt A3, B, C) erhält den `decrypt → --env-file`-Schritt vor `docker run` (§13, Item #6). VPS-Variante (A3-VPS) identisch: Passphrase ist auf dem VPS provisioniert (eine der vier Ketten-Quellen).
- **CI/Build braucht keinen Schlüssel** (GE3): `build.yml` baut nur das Image (kein `--env-file`, kein decrypt) — die Passphrase ist **nicht** als GitHub-Actions-Secret hinterlegt.

---

## 8. Build-Time-Pfad (dokumentiert, INAKTIV)

**Status: Tür offen, nicht beschritten.** Es gibt Szenarien, in denen ein Secret zur **Build-Zeit** nötig wäre — z.B. Pull aus einer **privaten** Registry, ein lizenzpflichtiges Build-Artefakt, ein Build-Arg mit Credential. P1 deckt das **bewusst nicht** ab (GE3: Konsum nur zur Laufzeit; heutige Apps bauen aus öffentlichen Quellen + pushen via eingebautem `GITHUB_TOKEN`).

**Wenn eine App es künftig braucht (Aktivierungspfad, NICHT P1):**
- Der Schlüssel kommt **nicht** aus `.env.gpg` (das Repo-Artefakt braucht keine CI-Passphrase) — sondern als **GitHub-Actions-Secret** (`secrets.<NAME>`), in `build.yml` als `build-args`/`--secret` injiziert.
- Begründung: Build läuft in GitHub Actions ohne die Fabrik-Passphrase (GE3). Ein dortiges decrypt würde die geteilte Passphrase in die CI-Umgebung exponieren — das vermeiden wir. Build-Secrets sind ein **separater** Trust-Boundary (CI-Runner) und gehören in den GitHub-Secret-Store, nicht in den `.env.gpg`-Pfad.

**Invariante (P1):** `build.yml` enthält **keinen** decrypt-Schritt und **keinen** App-Secret. Ein Diff, der die Fabrik-Passphrase oder einen `.env.gpg`-decrypt in einen GitHub-Workflow einführt, ist ein **Critical**-Befund (exponiert die geteilte Passphrase in die CI). Dieser Abschnitt wird als Kommentar-Notiz in `templates/_shared/build.yml` referenziert (§13, Item #6).

---

## 9. `coder`/`/flow` Re-Encrypt-Konvention + Sync-Gate

**Das Problem.** Ändert sich der Satz der App-Secrets (neue Variable, geänderter Wert), muss `.env` (Klartext, lokal) **und** `.env.gpg` (committed) zusammen aktualisiert werden. Driften sie auseinander, deployt der Rollout (§7) einen veralteten Secret-Satz — ein stiller, schwer zu debuggender Fehler.

**Re-Encrypt-Konvention (coder).** Berührt ein Board-Item die App-Secrets (fügt eine env-Variable hinzu, die der App-Code liest), MUSS der `coder` im selben Working-Tree:
1. `.env.example` um die neue Variable (Name, Platzhalter — **kein** echter Wert) ergänzen.
2. `.env` lokal um die Variable ergänzen (falls für Self-Test/Smoke nötig) und `bash scripts/encrypt-env.sh` ausführen → `.env.gpg` neu schreiben.
3. **Nur `.env.gpg` + `.env.example`** in den Commit aufnehmen — `.env` bleibt durch `.gitignore` draußen.

**Sync-Gate (reviewer / `/flow`).** Ist `.env.gpg` aktuell ggü. `.env`? Da `.env` **nicht** im Repo liegt, ist ein bit-genauer Vergleich nicht universell möglich — das Gate ist daher eine **Konsistenz-Heuristik** (Review-Kriterium):

| Signal | Befund |
|---|---|
| Diff fügt eine env-Variable im App-Code hinzu (Zugriff auf `process.env.X` / `System.getenv("X")` / `os.environ["X"]` …), aber `.env.example` listet `X` nicht | **Important** „Secret-Sync: `.env.example` referenziert `X` nicht — Re-Encrypt-Konvention §9 verletzt" |
| Diff committet eine Klartext-`.env` (oder `.env.*`) | **Critical** (`security/R01`, GE6) |
| Diff ändert `.env.example` (neue Variable), aber `.env.gpg` ist im selben Diff **unverändert** | **Important** „`.env.gpg` nicht re-encrypted nach `.env.example`-Änderung (§9)" — Heuristik, da der Reviewer den Klartext nicht kennt; als „verify" formuliert |
| Diff committet `.env.gpg` ohne zugehörige `.env.example`-/Code-Änderung | Suggestion (kann legitim sein — Wert-Rotation) |

**`/flow`-Verankerung.** Das Sync-Gate ist Teil des regulären `reviewer`-Laufs (kein separater Agent) — `reviewer.md` erhält den Checklist-Eintrag (§13, Item #5). `/flow` selbst triggert **keinen** zusätzlichen Dispatch; der reviewer prüft die Heuristik im normalen Build-Loop (§3). Begründung: analog zum DBA-Trigger, aber leichtgewichtiger — Secret-Sync ist eine Diff-Eigenschaft, kein eigenes Subsystem-Smoke.

**Grenze (Proportionalität).** Reiner App-Code, der **keine** neue env-Variable einführt, triggert das Sync-Gate nicht — kein false-positive auf jedem Diff.

---

## 10. `/new-project`-Verdrahtung (initial leeres `.env.gpg`)

`/new-project` scaffoldet das Secrets-Subsystem **immer** (jede App bekommt es — keine Opt-in-Frage, anders als DB/Companions). Einzufügen als neuer Scaffold-Schritt (zwischen `.claude/`-Scaffold und Deploy-Scaffold):

1. **Script-Set kopieren:** `templates/_shared/secrets/{_lib.sh,encrypt-env.sh,decrypt-env.sh,load-env.sh}` → `scripts/` (executable; `_lib.sh` ohne `+x`).
2. **`.env.example` kopieren** ans Repo-Root (Vorlage, committed).
3. **`.gitignore` ergänzen** um den `gitignore.snippet` (§5, idempotent).
4. **`.gitleaks.toml` kopieren** ans Repo-Root (§6 Allowlist-Scaffold).
5. **Initiales `.env.gpg` anlegen + committen (GE4):**
   - Aus `.env.example` (oder einem leeren/Platzhalter-`.env`) per `bash scripts/encrypt-env.sh` ein initiales `.env.gpg` erzeugen — **vorausgesetzt die Passphrase-Kette (§3) ist auf dem Scaffold-Host auflösbar**.
   - **Passphrase nicht auflösbar** (kein `gpg.pass`, kein `$GPG_PASSPHRASE`, non-interaktiv): kein Hard-Fail — Backlog-Item „Initiales `.env.gpg` erzeugen (`bash scripts/encrypt-env.sh`, sobald Passphrase provisioniert)" + Konsolen-Warnung. Das Scaffold (Scripts, `.gitignore`, `.gitleaks.toml`, `.env.example`) liegt trotzdem.
   - **Zweck (GE4):** ab Tag 1 ist die ganze Kette erprobt — `.gitignore` hält `.env` draußen, die gitleaks-Allowlist lässt `.env.gpg` durch, die Script-Pfade existieren. Der erste echte `git push` mit committetem `.env.gpg` darf das Secret-Scan-Gate **nicht** rot färben (das ist genau der Reconciliation-Test, GE6).
6. **README um Secrets-Abschnitt erweitern:** Verweis auf diese Spec, `.env`/`.env.gpg`-Modell, Workflow (`decrypt-env.sh` lokal → `.env` editieren → `encrypt-env.sh` → `.env.gpg` committen).

**Invariante:** Nach `/new-project` existieren `scripts/{_lib,encrypt-env,decrypt-env,load-env}.sh`, `.env.example`, `.gitleaks.toml`, die `.gitignore`-Regeln und (bei auflösbarer Passphrase) ein committetes `.env.gpg`. Ein `git push` löst das `build.yml`-Secret-Scan-Gate **grün** aus.

---

## 11. `/adopt`-Verdrahtung (Scaffold + Audit-Finding, kein History-Rewrite)

`/adopt` ergänzt das Secrets-Subsystem **idempotent** (wie der ganze `/adopt`-Pfad — kein Auto-Fix, kein Überschreiben), als neuer Detection-/Scaffold-Schritt (analog 2a/2b):

1. **Scaffold ergänzen, falls fehlend** (nicht-destruktiv): Scripts, `.env.example`, `.gitleaks.toml`, `.gitignore`-Regeln wie §10 — aber **nur** wenn die jeweilige Datei noch nicht existiert. Bestehende `.gitleaks.toml` / `.gitignore` werden **gemergt** (Regeln anhängen, nicht überschreiben); Konflikt (bestehende Allowlist erlaubt bereits `.env` Klartext) → Audit-Finding statt Auto-Patch.
2. **Klartext-`.env` in der HEAD-Arbeitskopie** (uncommitted oder versehentlich getrackt): wenn `git ls-files` ein getracktes `.env`/`.env.*` zeigt → **Audit-Finding (Critical)** „Klartext-`.env` ist getrackt — aus dem Index nehmen (`git rm --cached`), in `.gitignore` aufnehmen, Werte nach `.env.gpg` verschlüsseln" (`security/R01`).
3. **Klartext-`.env` in der HISTORY (GE5 — KEIN History-Rewrite):** zeigt `git log --all --full-history -- .env .env.*` einen Treffer (in einem früheren Commit committed, später entfernt) → **Audit-Finding (Important)** aufs Board:
   - **Titel:** `🔒 SECRET-IN-HISTORY: Klartext-.env in der git-History (kein Auto-Rewrite)`
   - **Body:** Pfad + erster Commit-SHA; Hinweis, dass die betroffenen Secrets als **kompromittiert** zu behandeln und zu **rotieren** sind (History-Rewrite ist destruktiv und wird bewusst NICHT automatisch ausgeführt — Mensch entscheidet, ob `git filter-repo`/BFG sinnvoll ist); Verweis auf diese Spec §11.
   - **Labels:** `security`, `secrets-history` (Fallback ohne Labels analog Polyglott-Eskalation, falls Label-Setup fehlt).
4. **Audit-Dispatch:** der bestehende `/adopt`-Audit (Schritt 3, `gitleaks detect --no-git` + reviewer Audit-Modus) deckt Klartext-Funde ohnehin ab — die Secrets-spezifischen Findings (2, 3) ergänzen ihn, dispatchen aber **keinen** Extra-Agenten.

**Invarianten:**
- **Kein History-Rewrite** (GE5) — `/adopt` schreibt nur Backlog-Items, fasst die git-History **nie** an.
- **Kein Auto-Fix** — bestehende `.env`/`.gitignore`/`.gitleaks.toml` werden nie destruktiv überschrieben; Konflikte → Backlog.
- Adoptiert `/adopt` ein Repo **ohne** jedes Secret-Artefakt, ist das initiale `.env.gpg` **optional** (kein GE4-Zwang wie bei `/new-project`) — Scaffold liegt, `.env.gpg` entsteht beim ersten echten Secret. Das Secret-Scan-Gate ist auch ohne `.env.gpg` grün (kein Klartext da).

---

## 12. Build-Wellen

Drei Wellen mit klaren Abhängigkeiten — Wellen 2/3 hängen vom Fundament (dieser Spec):

**Welle 1 — Spec/Fundament** (dieses Dokument, Item #1):
- `docs/architecture/secrets-subsystem.md` (diese Spec) als bindende Source of Truth.
- **Output:** Spec liegt; das bestehende Fabrik-Muster (`scripts/{_lib,encrypt-env,decrypt-env,load-env}.sh`) ist die referenzierte Vorlage — **kein** neuer Code, bestehende Projekte unverändert.

**Welle 2 — Scaffold-Fragment** (braucht Welle 1; Items #2, #4):
- `templates/_shared/secrets/` (Script-Kopien, `.env.example`, `gitignore.snippet`, `gitleaks.toml`) — Item #2.
- `knowledge/security.md` `R01`-Präzisierung + Reviewer-Checklist-Eintrag + gitleaks-Allowlist-Standard — Item #4.
- **Output:** Scaffold-Fragment + geschärfter Floor liegen, aber noch von keinem Skill konsumiert. Bestehende Projekte unverändert (Allowlist-Schärfung ist additiv-rückwärtskompatibel).

**Welle 3 — Wiring** (braucht Welle 1 + 2; Items #3, #5, #6):
- `skills/new-project/SKILL.md` + `skills/adopt/SKILL.md`: Scaffold-Verdrahtung + initial `.env.gpg` + Adopt-Audit-Findings — Item #3.
- `agents/coder.md` + `skills/flow/SKILL.md` (bzw. `agents/reviewer.md`): Re-Encrypt-Konvention + Sync-Gate — Item #5.
- `agents/cicd.md` (+ Notiz in `templates/_shared/build.yml`): Laufzeit-Entschlüsselung beim Rollout (`--env-file`) — Item #6.
- **Output:** End-to-end nutzbar — jede neue/adoptierte App trägt das Subsystem, der Rollout konsumiert es zur Laufzeit.

**Cross-Wellen-Regel.** Welle 3-Items dürfen vorgezogen werden, **wenn** sie sich gegen ein noch fehlendes Welle-2-Artefakt **graceful** verhalten (analog db-subsystem §14 Amendment): existiert `templates/_shared/secrets/` noch nicht, loggt das Skill-Wiring eine Warn-Zeile statt zu scheitern. Item #4 (Allowlist-Schärfung) sollte **vor** Item #2 (oder im selben PR) landen, sonst blockiert der erste committete `.env.gpg` aus #2/#3 das eigene Secret-Scan-Gate (GE6).

---

## 13. Acceptance-Kriterien

Testbar — der Vertrag für `coder`/`reviewer`/`tester`. Board-Items referenzieren diese Nummern.

- **AC1 — Modell.** Ein konformes Repo trägt `.env` (gitignored, NIE im Index/History committed) UND ein committetes `.env.gpg`. `git ls-files` zeigt `.env.gpg`, aber **nie** `.env` oder `.env.*` (außer `.env.example`).
- **AC2 — Verschlüsselung.** `.env.gpg` ist mit GPG-symmetrisch `AES256` erzeugt (`gpg --list-packets .env.gpg` zeigt symmetric/AES256). `decrypt-env.sh` stellt aus `.env.gpg` ein `.env` (0600) wieder her, wenn die Passphrase über die Kette (§3) auflösbar ist.
- **AC3 — Geteilte Passphrase-Kette.** Das per-App-`scripts/_lib.sh` enthält `resolve_pass_file()` **identisch** zur Fabrik-Quelle (`scripts/_lib.sh`): Reihenfolge `$GPG_PASS_FILE` → `/etc/softwareschmiede/gpg.pass` → `~/.config/softwareschmiede/gpg.pass` → `$GPG_PASSPHRASE` → Prompt. Kein per-App-Schlüssel, kein Bitwarden-Schritt im Repo (GE1).
- **AC4 — Script-Set.** `scripts/{encrypt-env,decrypt-env,load-env}.sh` existieren, sind executable, nutzen `set -euo pipefail`, sourcen `_lib.sh`, tragen keine hartkodierte Passphrase. `decrypt-env.sh` setzt `umask 077` + `chmod 600 .env` (GE2).
- **AC5 — `.gitignore`.** Die `.gitignore` ignoriert `.env` + `.env.*`, negiert (`!`) `.env.example` und `.env.gpg`. Ein versuchter `git add .env` schlägt am Ignore (bzw. erzeugt einen Reviewer-Critical, falls erzwungen).
- **AC6 — gitleaks-Allowlist (Reconciliation).** Das Repo trägt eine `.gitleaks.toml` mit `useDefault = true` und einer Allowlist, die **ausschließlich** `^\.env\.gpg$` erlaubt. Ein `gitleaks detect` über ein Repo mit committetem `.env.gpg` ist **grün**; ein committeter Klartext-Wert (z.B. `.env` mit `API_KEY=…`) ist **rot** (GE6).
- **AC7 — `security/R01`-Schärfung.** `knowledge/security.md` formuliert `R01` so, dass Klartext-Secrets Critical bleiben UND `.env.gpg` explizit als zulässiger Weg benannt ist; die Reviewer-Checklist trägt den Spiegel-Eintrag. Ein Reviewer flaggt committeten Klartext als Critical, `.env.gpg` **nicht**.
- **AC8 — Laufzeit-Konsum.** Der `cicd`/`preview`-Rollout führt vor `docker run` `decrypt-env.sh` aus und übergibt `--env-file .env`. Das Image enthält **keine** App-Secrets; `build.yml` enthält **keinen** decrypt-Schritt und **kein** App-Secret (GE3).
- **AC9 — Build-Time inaktiv.** `templates/_shared/build.yml` trägt eine Kommentar-Notiz, die den Build-Time-Pfad als inaktiv markiert (Aktivierung künftig via GitHub-Actions-Secret, nicht via `.env.gpg`-decrypt in CI). Ein Diff, der die Fabrik-Passphrase oder einen `.env.gpg`-decrypt in einen Workflow einführt, ist ein Critical-Befund (§8).
- **AC10 — `/new-project` initial.** Nach `/new-project` existiert das vollständige Scaffold (Scripts, `.env.example`, `.gitignore`-Regeln, `.gitleaks.toml`) und — bei auflösbarer Passphrase — ein committetes initiales `.env.gpg`; der erste `git push` löst das Secret-Scan-Gate **grün** aus. Bei nicht auflösbarer Passphrase: Backlog-Item statt Hard-Fail (GE4).
- **AC11 — `/adopt` Audit, kein Rewrite.** `/adopt` ergänzt fehlendes Scaffold idempotent (überschreibt nichts), legt bei getracktem Klartext-`.env` einen Critical-Befund und bei Klartext-`.env` in der **History** ein Important-Backlog-Item an — **ohne** die git-History umzuschreiben (GE5).
- **AC12 — Sync-Konvention.** Führt ein Diff eine neue App-env-Variable ein, ohne `.env.example` zu ergänzen (oder ohne `.env.gpg` zu re-encrypten), meldet der `reviewer` den dokumentierten Sync-Befund (§9); reiner App-Code ohne neue env-Variable triggert das Gate nicht.

---

## 14. Verträge (Übersicht)

| Vertrag | Form | Quelle/Ziel |
|---|---|---|
| Passphrase-Kette | `resolve_pass_file()` (Bash) | `scripts/_lib.sh` (identische Kopie) |
| Verschlüsselung | `gpg --symmetric --cipher-algo AES256 --pinentry-mode loopback` | `scripts/encrypt-env.sh` |
| Entschlüsselung | `gpg -d` + `umask 077` + `chmod 600` | `scripts/decrypt-env.sh` |
| Env-Load (Shell) | `source scripts/load-env.sh` → `set -a; eval; set +a` | `scripts/load-env.sh` |
| Laufzeit-Injektion | `docker run --env-file .env` (nach decrypt) | `agents/cicd.md` A3 / `skills/preview` |
| Allowlist | `^\.env\.gpg$` (gitleaks `[allowlist].paths`) | `.gitleaks.toml` |
| Ignore-Regeln | `.env`, `.env.*`, `!.env.example`, `!.env.gpg` | `.gitignore` |

---

## 15. Nicht-Ziele

- **Per-App-Schlüssel / Bitwarden-Schritt im Repo** (GE1 — ausgeschlossen).
- **History-Rewrite adoptierter Repos** (GE5 — nur Audit-Finding).
- **Build-Time-Secret-Konsum in P1** (§8 — Tür offen, inaktiv).
- **Bit-genaues `.env`↔`.env.gpg`-Diff-Gate** (`.env` liegt nicht im Repo — das Sync-Gate ist eine dokumentierte Heuristik, §9, kein kryptografischer Beweis).
- **Asymmetrische/Multi-Recipient-Krypto, SOPS, Vault** (GE2 — bestehendes symmetrisches Muster wird wiederverwendet).
- **Secret-Rotation/-Versionierung der geteilten Passphrase** (Ops-Vorgang außerhalb dieses Subsystems).

---

## 16. Abhängigkeiten

- **Bestehendes Fundament (referenziert, nicht neu erfunden):** `scripts/_lib.sh` (`resolve_pass_file`), `scripts/{encrypt-env,decrypt-env,load-env}.sh`.
- **Gate-Infrastruktur:** `templates/_shared/build.yml` (`secret-scan`-Job), `templates/_shared/security.yml` (History-Scan), `knowledge/security.md` (`security/R01`).
- **Scaffold-Klasse:** `templates/_shared/` (neu: `templates/_shared/secrets/`).
- **Skills/Agenten:** `skills/new-project`, `skills/adopt`, `skills/flow`; `agents/coder`, `agents/reviewer`, `agents/cicd`.
- **Verwandte Subsysteme (Pattern-Vorbild):** `docs/architecture/db-subsystem.md` (Scaffold-Fragment-/Wellen-/Detection-Muster).
