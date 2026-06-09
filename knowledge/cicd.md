# Knowledge Pack: cicd  (Domäne — CI/CD, Rollout, Versionierung)

> **Scope:** Produktiver Rollout, Build-Metadaten/Versionierung, CI-Pipeline-Pflege. Geladen vom `cicd`-Agenten. Regel-IDs: `cicd/F<NN>` (Fallen/Anti-Patterns), `cicd/P<NN>` (Patterns).
>
> **Quellenbezug:** Die Patterns in diesem Pack sind aus realen Produktionsproblemen beim Betrieb von `dev-gui` (Softwareschmiede) destilliert:
> (a) gitleaks-CI-Bruch, der manuell gefixt werden musste;
> (b) fehlender Build-Versions-Stempel — ad-hoc erfunden (`yymmddhhmmss ZZZ`, Europe/Zurich, Docker ARG/ENV);
> (c) `docker restart` zieht kein neues Image — Betreiber sah "keine Veränderung".

---

## Fallen / Anti-Patterns (F-Regeln)

### cicd/F01 — `docker restart` ≠ Image-Update (KRITISCH)
**Problem:** `docker restart <container>` startet den Container mit dem **bereits gecachten Image-Layer** neu. Ein neues Image, das via `docker pull` geholt wurde, wird dabei **NICHT** aktiviert.

**Symptom:** Betreiber führt `docker pull` + `docker restart` aus — Container läuft wieder, aber zeigt noch die alte Version. "Keine Veränderung sichtbar."

**Korrekte Mechanik (immer):**
```bash
docker pull "${image}:latest"      # neues Image holen
docker rm -f "$app" 2>/dev/null || true   # alten Container löschen
docker run -d --name "$app" \             # neuen Container aus neuem Image starten
  --restart unless-stopped \
  -p "${port}:${container_port}" \
  "${image}:latest"
```

Equivalent mit Compose:
```bash
docker compose pull
docker compose up -d --force-recreate   # --force-recreate ist Pflicht; ohne es nutzt Compose den alten Container
```

**Nie so:** `docker restart "$app"` nach einem `docker pull` — das macht `--force-recreate` nicht.

---

### cicd/F02 — Versionsstempel zur Container-Start-Zeit, nicht zur Build-Zeit
**Problem:** `ENV BUILD_VERSION=$(date ...)` in der `RUN`-Anweisung oder beim `docker run` als `-e BUILD_VERSION=$(date ...)` gesetzt — dann zeigt jeder Container-Neustart ein neues Datum, obwohl das Image unverändert ist.

**Korrekt:** Der Stempel wird **zur Build-Zeit** via Docker `ARG` gesetzt (GitHub Actions schreibt ihn in `build-args`). Das Image trägt den unveränderlichen Build-Zeitpunkt.

```dockerfile
ARG BUILD_VERSION=dev
ENV BUILD_VERSION=$BUILD_VERSION
LABEL build.version=$BUILD_VERSION
LABEL org.opencontainers.image.version=$BUILD_VERSION
```

```yaml
# .github/workflows/build.yml
- name: Set build version
  run: echo "BUILD_VERSION=$(TZ=Europe/Zurich date +'%y%m%d%H%M%S %Z')" >> $GITHUB_ENV

- name: Build and push
  uses: docker/build-push-action@v5
  with:
    build-args: |
      BUILD_VERSION=${{ env.BUILD_VERSION }}
```

**Format (Standard der Schmiede):** `yyMMddHHmmss ZZZ` (Europe/Zurich) + optional `-<git-sha-short>` (8 Zeichen) für Traceability.

---

### cicd/F03 — gitleaks False-Positives nicht blind whitelisten
**Problem:** CI bricht mit einem gitleaks-Befund auf einem Nicht-Secret (z.B. ein Test-Token, ein Placeholder-String, eine Config-Variable mit Secret-ähnlichem Namen).

**Richtige Reaktion:**
1. **Zuerst verifizieren:** ist es wirklich kein Secret? (Grep nach dem Wert im Repo — ist er irgendwo mit echtem Wert belegt? Ist er in der `.env.gpg`?)
2. Nur wenn zweifelsfrei kein Secret → `.gitleaks.toml` mit spezifischem Allowlist-Entry ergänzen:
   ```toml
   [[allowlist.regexes]]
   description = "placeholder token in tests"
   regex = "test-token-placeholder-[a-z0-9]+"
   ```
3. Wenn unklar → `NEEDS-HUMAN` ausgeben; **nicht** reflexartig whitelisten.

**Warum:** ein echter Secret in der Allowlist macht den Secret-Scan-Gate wertlos.

---

### cicd/F04 — `GITHUB_TOKEN`-Permissions für Image-Push vergessen
**Problem:** `docker push` in `build.yml` schlägt mit `denied: permission_denied` fehl, obwohl `GITHUB_TOKEN` automatisch vorhanden ist.

**Ursache:** Fehlende `permissions: packages: write` im Workflow.

**Fix:**
```yaml
permissions:
  contents: read
  packages: write
```

Dies muss auf Job- oder Workflow-Ebene gesetzt sein. Ohne es hat `GITHUB_TOKEN` kein Schreibrecht auf `ghcr.io`.

---

### cicd/F05 — Rollback ohne bekannten Tag unmöglich
**Problem:** Nach einem fehlgeschlagenen Rollout will man auf die Vorgängerversion zurück — aber es gibt kein Tag außer `latest`.

**Lösung (präventiv):** Immer auch einen stabilen Tag (z.B. `sha-<commit>` oder `<yyMMddHHmmss>`) neben `latest` pushen:
```yaml
tags: |
  ghcr.io/${{ env.IMAGE_NAME }}:latest
  ghcr.io/${{ env.IMAGE_NAME }}:sha-${{ github.sha }}
  ghcr.io/${{ env.IMAGE_NAME }}:${{ env.BUILD_VERSION }}
```

Beim Rollout den `sha-`-Tag in einem Label speichern → für Rollback verfügbar.

---

## Patterns / Best-Practices (P-Regeln)

### cicd/P01 — Rollout-Verifikation via Versions-Endpunkt
Nach `docker run` (frische Instanz) den Build-Stempel gegen den laufenden Container abgleichen:
```bash
RUNNING_VERSION=$(curl -fsS "http://localhost:${port}/api/version" | jq -r '.version' 2>/dev/null || echo "")
IMAGE_VERSION=$(docker inspect --format '{{index .Config.Labels "build.version"}}' "${image}:latest")
[ "$RUNNING_VERSION" = "$IMAGE_VERSION" ] && echo "OK" || echo "WARN: version mismatch"
```

Fehlt der Endpunkt → als Spec-Lücke melden (Board-Item anlegen); kein Blocker für den Rollout.

---

### cicd/P02 — Versions-Endpunkt-Spec (Standard der Schmiede)
Ein einfacher HTTP-Endpunkt `GET /api/version` antwortet mit:
```json
{ "version": "<BUILD_VERSION>", "built": "<ISO-Datetime optional>" }
```

`BUILD_VERSION` wird aus der `BUILD_VERSION`-Env-Variable geladen (die Docker `ARG`→`ENV` gesetzt hat).
Implementierung ist **coder**-Aufgabe (Board-Item, Spec `docs/specs/version-endpoint.md`, AC: 200 + korrekter Wert).

---

### cicd/P03 — Secret-Scan-Gate als erster CI-Step (vor Build)
**Empfehlung:** gitleaks als allererster Step in `build.yml` (vor dem Docker-Build), damit ein Secret-Fund den teureren Build abbricht und kein Image mit Secret im Layer gebaut wird:
```yaml
jobs:
  build:
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0   # geleaks braucht die volle History für --source
      - name: Secret scan (gitleaks)
        uses: gitleaks/gitleaks-action@v2
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
      - name: Build and push
        # ... erst hier
```

---

### cicd/P04 — CI-Workflow-Hygiene (Action-Versionen)
- Actions immer auf eine stabile **Major-Tag** pinnen (z.B. `actions/checkout@v4`, nicht `@main`).
- Bei `docker/build-push-action` und `docker/login-action` denselben Major-Stand halten (Kompatibilität der Outputs/Inputs).
- `fetch-depth: 0` bei Verwendung von gitleaks (History-Scan).

---

### cicd/P05 — Compose-basierter Rollout (wenn Compose vorhanden)
Wenn das Projekt `docker-compose.yml` nutzt:
```bash
docker compose pull                         # neues Image holen
docker compose up -d --force-recreate       # Container recreaten (NICHT nur restart)
docker compose ps                           # Status verifizieren
```

`--force-recreate` ist bei Compose das Äquivalent zu `rm + run` — ohne es werden Container mit unveränderter Konfiguration nicht neu gebaut, auch wenn das Image sich geändert hat.

---

## Reviewer-Checklist (für den `reviewer`-Agenten)
- CI-Workflow-Änderungen (`build.yml`): `permissions: packages: write` vorhanden? Secret-Scan vor Build-Step? (`cicd/P03`, `cicd/F04`)
- Dockerfile-Änderungen: `ARG BUILD_VERSION` + `ENV BUILD_VERSION` + `LABEL build.version` vorhanden? (`cicd/F02`)
- Rollout-Skripte/-Doku: `docker restart` statt `rm + run`? → **Important** (`cicd/F01`)
- gitleaks-Allowlist-Änderungen: jeder neue Entry mit Begründung + bewiesener Nicht-Secret-Nachweis? (`cicd/F03`)

## Test-Approach (für den `tester`-Agenten)
- Nach einem Rollout: Smoke `curl -fsS http://localhost:<port>/` → HTTP 200.
- Versions-Stempel-Check: `docker inspect --format '{{index .Config.Labels "build.version"}}' <image>:latest` → nicht leer, nicht `dev`.
- CI-Pipeline nach dem Fix: `gh run list --limit 1 --json conclusion` → `success`.
