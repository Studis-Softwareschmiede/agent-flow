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

### cicd/F06 — Rollout ohne CI-Watch (KRITISCH)
**Problem:** Image wird lokal gepullt und Container neu gestartet, bevor der GitHub-Actions-Build abgeschlossen ist. Ergebnis: `docker pull` liefert das alte `latest`-Image (der neue Build hat es noch nicht überschrieben).

**Symptom:** Betreiber sieht nach dem Rollout noch die alte Version, obwohl der Push schon stattgefunden hat.

**Korrekte Mechanik:** Erst `gh run watch <run-id> --exit-status` abwarten (Abschnitt A2 in `agents/cicd.md`). Dann `docker pull`.

---

### cicd/F07 — `docker image prune` vergessen (WICHTIG)
**Problem:** Nach jedem Rollout bleiben das alte `latest`-Image und dangling Layers auf dem Host liegen. Bei regelmässigem Betrieb füllt sich die Disk.

**Symptom:** `docker images` zeigt viele `<none>`-Zeilen oder mehrere versionierte Images. `df -h` zeigt Disk-Druck.

**Korrekte Mechanik (nach jedem Rollout/Rollback, Pflicht):**
```bash
docker image prune -f
```

`-f` überspringt die Bestätigungs-Abfrage. Bereinigt dangling Images (kein `--all` — das würde auch Images entfernen, die von Containern noch referenziert werden).

---

### cicd/F08 — CI-Run-Zuordnung nur empirisch via `headSha`, nie hergeleitet (KRITISCH)
**Problem:** Um zu wissen, **ob** bzw. **welcher** CI-Run zum eigenen Commit gehört, wird der Run entweder aus der Workflow-Config **hergeleitet** („triggert auf diesem Branch ein Workflow?") oder blind aus `gh run list --limit 1` übernommen. Beides ist eine **Fail-open-Falle** — der Fehlermodus ist identisch: ein roter oder fremder CI wird als „grün/eigen" durchgewunken.

- **Config-Herleitung ist unmöglich in Bash.** Bash kann YAML/JSON nicht robust parsen. Ein Eigenbau-Parser deckt den gemeldeten Fall, aber die **Fehlerklasse bleibt offen**. Verifiziert (end-to-end, zwei Review-Iterationen): `branches: &anchor` und `on: &anchor` (YAML-Anker auf dem `branches:`- bzw. `on:`-Key) wurden beide als Branch-Pattern fehlgelesen → no-trigger → roter CI auf `main` durchgewunken; quotierte Globs (`"*-hotfix"`) sind nach dem Quote-Stripping nicht mehr von echten Aliassen unterscheidbar. **Jeder Flicken deckt den gemeldeten Fall, die Fehlerklasse bleibt.**
- **`--limit 1`-Annahme ist race-anfällig.** Unmittelbar nach `git push` liefert `gh run list --limit 1` wegen Webhook-Verzögerung oft noch den **alten**, bereits abgeschlossenen Run des Vorgänger-Commits → Watch/Rollout auf einem fremden Run.

**Kur — „Nachsehen statt raten":** NICHT das Format parsen und NICHT `.github/workflows/*` interpretieren (weder ganz noch mit `grep`/`sed`/`awk`). Stattdessen nach dem Push ein **begrenztes Fenster** beobachten, ob ein Run erscheint, dessen `headSha` **exakt** die eigene Ziel-SHA ist:

```bash
expect_sha="$(git rev-parse HEAD)"
run_sha="$(gh run list --branch "$branch" --limit 1 --json headSha --jq '.[0].headSha' 2>/dev/null || echo "")"
if [ "$run_sha" = "$expect_sha" ]; then
  gh run watch "$run_id" --exit-status   # eigener Run → scharf beobachten (F09/AC2)
fi
# sonst: Fenster weiterlaufen lassen; Skip nur auf Nicht-default_branch (F09)
```

Die Zuordnung erfolgt **ausschliesslich** über `headSha == eigene SHA`. Ob überhaupt ein Trigger existiert, wird **nur** aus beobachteten Runs beantwortet — nie aus den Workflow-Definitionen.

---

### cicd/F09 — Fail-safe-Richtung bei CI-/Rollout-Gate-Entscheidungen (KRITISCH)
**Problem:** Jede Unsicherheit im CI-Gate (unparsbare Config, unbekannte Syntax, `gh`-Fehler, fremde SHA, Actions-Störung, Auth/Rate-Limit) MUSS zur **sicheren Seite** führen. Fail-**open** (Unsicherheit → Skip → ungeprüfter Code ausgerollt) ist bei einer sicherheitskritischen Entscheidung nicht verhandelbar.

**Richtung (kanonisch):**
- Auf dem **`default_branch`**: jede Unsicherheit → **immer** scharfer Watch bzw. `die`, **nie** Skip. „Kein Run" auf `main` ist ein **Symptom** (Actions-Störung/Auth/Rate-Limit), kein Zustand.
- Ein Run mit **fremder `headSha`** gilt weder als „eigener Run" (seine `conclusion` wird nicht ausgewertet) **noch** als „kein Run" (er beendet die Beobachtung nicht) — er wird ignoriert, das Fenster läuft weiter.
- Eine **fehlgeschlagene oder leere `gh`-Abfrage** gilt **nie** als „kein Trigger" — Auth erneuern + weiterbeobachten.

**Gegen-Richtung (fail-useless vermeiden):** Ein Überschuss-Fix, der **alles** als unsicher behandelt, erzeugt überall Leerlauf und höhlt den Zweck genauso aus. Die belegte, schmale Grenze: **Skip nur auf Nicht-`default_branch`** (dort ist ein verpasster Trigger folgenlos — kein Rollout), **`default_branch` immer scharf**. Ein optionales Beobachtungsfenster steuert **nur die Dauer**, nie das Ergebnis: kein Wert und kein Schalter darf den Watch auf `main` abschalten oder einen gefundenen Run ungeprüft lassen.

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

### cicd/P06 — Kanonische ship-Sequenz (merge → push → CI-Watch → Rollout → Prune)

Die vollständige Abschluss-Sequenz nach `tester`-PASS (Abschnitt A in `agents/cicd.md`):

```
1. git merge + push  (gemäss merge_policy: direct oder PR)
2. gh run watch <run-id> --exit-status  →  nur bei Grün weiter
3. docker pull "${image}:latest"
4. docker rm -f "$app" && docker run -d --name "$app" … "${image}:latest"
5. docker image prune -f                ← Pflicht, nicht auslassbar
```

Jede Abweichung von dieser Reihenfolge ist ein Fehler:
- Schritt 2 überspringen → `F06` (Rollout auf altem Image)
- Schritt 5 überspringen → `F07` (Disk-Drift)
- `docker restart` statt Schritt 4 → `F01` (Image-Update ausbleibend)

---

### cicd/P07 — CI-Watch-Befehl (Standard, mit `headSha`-Zuordnung)

Den zu beobachtenden Run **immer** über die eigene Commit-SHA zuordnen (nicht blind den neuesten Run nehmen — `cicd/F08`):

```bash
expect_sha="$(git rev-parse HEAD)"
run_sha=$(gh run list --repo "$repo" --branch "$default_branch" --limit 1 \
  --json headSha --jq '.[0].headSha')
if [ "$run_sha" = "$expect_sha" ]; then
  run_id=$(gh run list --repo "$repo" --branch "$default_branch" --limit 1 \
    --json databaseId --jq '.[0].databaseId')
  gh run watch "$run_id" --repo "$repo" --exit-status
fi   # sonst: Fenster weiterbeobachten (Webhook-Verzögerung) statt fremden Run watchen
```

`--exit-status` gibt Exit-Code != 0 bei Fehlschlag — damit lässt sich der Rollout sauber abbrechen. Alternative: `gh run watch --interval 10` für explizites Polling-Intervall. Auf dem `default_branch` gilt die Fail-safe-Richtung (`cicd/F09`): erscheint kein Run für die eigene SHA, wird **nicht** übersprungen, sondern gewartet/`die`t.

---

## Reviewer-Checklist (für den `reviewer`-Agenten)
- CI-Workflow-Änderungen (`build.yml`): `permissions: packages: write` vorhanden? Secret-Scan vor Build-Step? (`cicd/P03`, `cicd/F04`)
- Dockerfile-Änderungen: `ARG BUILD_VERSION` + `ENV BUILD_VERSION` + `LABEL build.version` vorhanden? (`cicd/F02`)
- Rollout-Skripte/-Doku: `docker restart` statt `rm + run`? → **Important** (`cicd/F01`)
- Rollout-Skripte/-Doku: `docker image prune -f` vorhanden? Fehlt → **Important** (`cicd/F07`)
- Rollout-Skripte/-Doku: CI-Watch vor `docker pull`? Fehlt → **Important** (`cicd/F06`)
- CI-Watch-/Ship-Skripte: wird der beobachtete Run über `headSha == eigene SHA` zugeordnet (nicht blind `gh run list --limit 1`)? Fehlt → **Critical** (`cicd/F08`)
- CI-Gate-Skripte: wird `.github/workflows/*` (oder ein anderes strukturiertes Format) in Bash mit `grep`/`sed`/`awk`/Eigenbau-Parser interpretiert, um eine sicherheitskritische Entscheidung zu treffen? → **Critical** — empirisch beobachten statt parsen (`cicd/F08`)
- CI-Gate-Entscheidung: führt jede Unsicherheit auf dem `default_branch` zum scharfen Watch/`die` (nie Skip)? Skip nur auf Nicht-`default_branch`? Kein Schalter, der den Watch auf `main` abschaltet? Fehlt → **Critical** (`cicd/F09`)
- gitleaks-Allowlist-Änderungen: jeder neue Entry mit Begründung + bewiesener Nicht-Secret-Nachweis? (`cicd/F03`)

## Test-Approach (für den `tester`-Agenten)
- Nach einem Rollout: Smoke `curl -fsS http://localhost:<port>/` → HTTP 200.
- Versions-Stempel-Check: `docker inspect --format '{{index .Config.Labels "build.version"}}' <image>:latest` → nicht leer, nicht `dev`.
- CI-Pipeline nach dem Fix: `gh run list --limit 1 --json conclusion` → `success`.
- Prune-Check: `docker images --filter dangling=true` → nach `prune -f` sollte die Liste leer sein.
- CI-Gate-Skript (`cicd/F08`/`F09`), Fixture-Stil mit `gh`-Mocks: (a) Mock-Run mit `headSha` ≠ eigene SHA → gilt **nicht** als eigener Run, Fenster läuft weiter (keine `conclusion`-Auswertung); (b) kein Run für die eigene SHA auf **Nicht-`default_branch`** → Skip (Exit 0, kurze Laufzeit); (c) kein Run für die eigene SHA auf **`default_branch`** → **kein** Skip (Timeout/`die`, kein Rollout).
