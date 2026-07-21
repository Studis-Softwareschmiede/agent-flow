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

**Korrekt (Build-Zeit-Quelle):** Der Stempel wird **zur Build-Zeit** via Docker `ARG` gesetzt (GitHub Actions schreibt ihn in `build-args`). Das Image trägt den unveränderlichen Build-Zeitpunkt.

> **Amendment (flashrescue, 2026-07-19) — auch build-zeit-gesetzte ENV bleibt ein Laufzeit-Anti-Pattern:**
> Selbst wenn der Stempel korrekt zur Build-Zeit via `ARG`→`ENV` gesetzt wird, darf die **ENV** zur Laufzeit nicht die alleinige Selbstauskunfts-Quelle sein. Befund: Container-Recreate-Werkzeuge (z.B. dev-guis „Update") übernehmen beim Neuaufbau die **ENV des Alt-Containers 1:1** — inkl. der alten `APP_VERSION`/`BUILD_VERSION` — und überschreiben damit die des neuen Images. Ergebnis: neuer Code läuft, die Versionsanzeige bleibt auf dem alten Stand **eingefroren**, wiederholt Fehlalarm beim Betreiber.
> **Fix:** Die Selbstauskunft (`/version`) liest aus einer **beim Build ins Image gebrannten Datei** (kanonisch `/app/VERSION`, siehe [[build-version-stamping]] AC2/AC3), nicht aus der ENV — die Datei ist recreate-immun, die ENV nicht. Die ENV bleibt nur **letzter Fallback**, wenn die Datei fehlt (Lese-/Abgleich-Reihenfolge und Rationale: `cicd/P08`).

**Aktuelles Schema (Standard der Schmiede, siehe [[build-version-stamping]]):**
```dockerfile
ARG APP_VERSION=dev
ARG GIT_SHA=unknown
ARG BUILD_CREATED=""
RUN echo "$APP_VERSION" > /app/VERSION

LABEL org.opencontainers.image.version="$APP_VERSION" \
      org.opencontainers.image.revision="$GIT_SHA" \
      org.opencontainers.image.created="$BUILD_CREATED"
```

```yaml
# templates/_shared/build.yml
- name: Build and push
  uses: docker/build-push-action@v6
  with:
    build-args: |
      APP_VERSION=${{ steps.version.outputs.app_version }}
      GIT_SHA=${{ github.sha }}
    labels: ${{ steps.meta.outputs.labels }}   # docker/metadata-action setzt .created zusätzlich auf Registry-Ebene
```

**Historisches Schema (abgelöst, nicht mehr Standard):** `ARG BUILD_VERSION` / `ENV BUILD_VERSION` / `LABEL build.version` / `/api/version`-Endpunkt aus reiner ENV-Auskunft — ersetzt durch datei-gebrannte `APP_VERSION` + OCI-Standard-Labels + `/version` (`cicd/P08`). Alte Board-/Repo-Referenzen auf `build.version`/`BUILD_VERSION`/`/api/version` sind Bestandsschema, kein aktueller Zielzustand für neue Projekte.

**Format (Standard der Schmiede, weiterhin gültig für den `APP_VERSION`-Wert selbst):** `yyMMddHHmmss ZZZ` (Europe/Zurich) + optional `-<git-sha-short>` (8 Zeichen) für Traceability. Wie der Wert die App zur Laufzeit erreicht, hat sich geändert (Datei statt ENV-Selbstauskunft — siehe Amendment oben).

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

### cicd/F10 — Node20-Actions laufen im Herbst 2026 nicht mehr (GitHub-Runner-Abkündigung)
**Problem:** GitHub kündigt die Node20-Laufzeit für Actions ab: ab 16. Juni 2026 nutzen Runner standardmässig **Node24**; Node20-Actions laufen dann nur noch mit explizitem Opt-out (`ACTIONS_ALLOW_USE_UNSECURE_NODE_VERSION=true`), bevor Node20 im Herbst 2026 endgültig entfernt wird. Betrifft **jede Node20-gebaute Action**, die dieses Pack bisher als Beispiel zeigt:
- `actions/checkout@v4` läuft auf Node20 → auf **`actions/checkout@v5`** (Node24) heben.
- `gitleaks/gitleaks-action@v2` läuft auf Node20 → auf **`gitleaks/gitleaks-action@v3`** heben (laut Maintainer drop-in, „no changes to inputs, outputs, or behavior").

**Symptom (Übergangsfenster):** gelbe Warnung im Actions-Log „Node.js 20 actions are deprecated"; nach der Runner-Migration harter Fehlschlag, wenn kein Opt-out gesetzt ist.

**Fix:** betroffene `uses:`-Pins in `build.yml`/`security.yml` auf die Node24-fähige Major-Version anheben, sobald verfügbar; Major-Pin-Disziplin (`cicd/P04`) bleibt bestehen — nur der Ziel-Major ändert sich.

Quelle: [Deprecation of Node 20 on GitHub Actions runners](https://github.blog/changelog/2025-09-19-deprecation-of-node-20-on-github-actions-runners/) · [gitleaks-action Releases (v3.0.0)](https://github.com/gitleaks/gitleaks-action/releases)

---

### cicd/F11 — `actions/checkout` blockiert seit 20. Juli 2026 Fork-PR-Checkout in `pull_request_target`/`workflow_run` standardmässig
**Problem:** `actions/checkout` v7 (18. Juni 2026) verweigert per Default das Auschecken von Fork-PR-Code in `pull_request_target`- und `workflow_run`-Workflows (Schutz vor „Pwn Request"-Angriffen: `refs/pull/<n>/head`, `refs/pull/<n>/merge`, Fork-HEAD-SHA). Seit **20. Juli 2026** ist dieses Verhalten auch auf **fliessende Major-Tags zurückportiert** (`actions/checkout@v4`, `@v3`, …) — ein Workflow, der bewusst Fork-Code in `pull_request_target`/`workflow_run` auscheckt (z.B. für Preview-Builds), bricht damit **ohne eigene Versionsänderung** um.

**Betrifft nicht** Workflows, die nur auf `push`/`pull_request` (nicht `_target`) triggern (Softwareschmiede-Standard-`build.yml`/`security.yml` sind nicht betroffen) — relevant für jeden CI-Workflow mit `pull_request_target`/`workflow_run` + Fork-Checkout, u.a. Preview-/Fork-basierte Pipelines.

**Fix, falls Fork-Checkout dort bewusst gewollt ist:** `allow-unsafe-pr-checkout: true` explizit setzen — nur nach Prüfung, dass kein Secret-Zugriff/Build-Schritt mit dem Fork-Code kompromittierbar ist.

Quelle: [Safer pull_request_target defaults for GitHub Actions checkout](https://github.blog/changelog/2026-06-18-safer-pull_request_target-defaults-for-github-actions-checkout/)

---

## Patterns / Best-Practices (P-Regeln)

### cicd/P01 — Rollout-Verifikation via Versions-Endpunkt
> **Historisches Schema, für neue Projekte abgelöst durch `cicd/P08` — siehe dort.** Gültig nur noch für Bestandsprojekte, die noch nicht auf das datei-/label-basierte Schema migriert sind.

Nach `docker run` (frische Instanz) den Build-Stempel gegen den laufenden Container abgleichen:
```bash
RUNNING_VERSION=$(curl -fsS "http://localhost:${port}/api/version" | jq -r '.version' 2>/dev/null || echo "")
IMAGE_VERSION=$(docker inspect --format '{{index .Config.Labels "build.version"}}' "${image}:latest")
[ "$RUNNING_VERSION" = "$IMAGE_VERSION" ] && echo "OK" || echo "WARN: version mismatch"
```

Fehlt der Endpunkt → als Spec-Lücke melden (Board-Item anlegen); kein Blocker für den Rollout.

---

### cicd/P02 — Versions-Endpunkt-Spec (historisches Schema)
> **Historisches Schema, für neue Projekte abgelöst durch `cicd/P08` — siehe dort.** Gültig nur noch für Bestandsprojekte, die noch nicht auf das datei-/label-basierte Schema migriert sind.

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
- Actions immer auf eine stabile **Major-Tag** pinnen (z.B. `actions/checkout@v5`, nicht `@main`) — Node20-Majors (`checkout@v4`, `gitleaks-action@v2`) sind Auslaufmodelle, siehe `cicd/F10`.
- Bei `docker/build-push-action` und `docker/login-action` denselben Major-Stand halten (Kompatibilität der Outputs/Inputs).
- `fetch-depth: 0` bei Verwendung von gitleaks (History-Scan).
- Nutzt ein Workflow `pull_request_target`/`workflow_run` mit Fork-Checkout, siehe `cicd/F11` (Default-Verhalten von `actions/checkout` hat sich rückwirkend geändert).

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

### cicd/P08 — Datei-gebrannte Version als Selbstauskunfts-Quelle (ENV nur letzter Fallback)
Die laufende Version wird **datei-/label-first** gelesen, nie ENV-first — weil Recreate-Werkzeuge die ENV überschreiben (`cicd/F02`-Amendment), das Image aber nicht:

```
1. docker inspect → org.opencontainers.image.version   (Label, von außen, Registry-Metadatum)
2. curl /version   → { version } aus gebrannter Datei    (App-Selbstauskunft, von innen)
3. ENV APP_VERSION                                        (letzter Fallback)
4. "unknown"/"dev"
```

**Version-Abgleich nach dem Rollout** (Erweiterung von `cicd/P01`, nicht Duplikat):
```bash
RUNNING_VERSION=$(curl -fsS "http://localhost:${port}/version" | jq -r '.version' 2>/dev/null || echo "")
IMAGE_VERSION=$(docker inspect --format '{{index .Config.Labels "org.opencontainers.image.version"}}' "${image}:latest")
[ "$RUNNING_VERSION" = "$IMAGE_VERSION" ] && echo "OK" || echo "WARN: version mismatch (mögliche ENV-Overwrite-Regression)"
```
Mismatch → **sichtbare WARN**, kein Hard-Fail (Diagnose-Signal, kein Rollout-Blocker).

**Invariante — eine App kann ihre eigenen OCI-Labels nicht von innen lesen:** `org.opencontainers.image.*`-Labels sind Registry-/`docker inspect`-Metadaten für Tools, kein vom laufenden Prozess lesbares Datei-/ENV-Artefakt. Die App selbst kann sie deshalb **nicht** als `/version`-Quelle nutzen. Der Abgleich liest sie darum von außen (`docker inspect`, Schritt 1 oben) gegen die App-eigene `/version`-Auskunft (datei-basiert, Schritt 2) — beide Quellen sind unabhängig voneinander befüllt, deshalb ist ihr Abgleich aussagekräftig (kein Zirkelschluss).

**Frontend-Ergänzung:** bei Web-Frontends ohne serverseitigen `/version`-Endpunkt trägt ein zur Build-Zeit erzeugtes `version.json` im served-dir dieselbe Rolle; `index.html` wird mit `Cache-Control: no-cache`/kurzer Cache-Control ausgeliefert, damit die GUI-Version beim Deploy sofort mitzieht (kein langlebiger Edge-Cache auf dem Einstieg).

Löst die frühere `build.version`-Label-/`/api/version`-Praxis (`cicd/P01`/`cicd/P02`, historisches Schema) für neue Projekte ab, siehe `cicd/F02`-Amendment. Scaffold-Bausteine (Dockerfile/build.yml je Sprach-Template): [[build-version-stamping]]. Rationale + Read-/Abgleich-Reihenfolge: [[build-version-verification]] AC2/AC3/AC5/AC6.

---

## Reviewer-Checklist (für den `reviewer`-Agenten)
- CI-Workflow-Änderungen (`build.yml`): `permissions: packages: write` vorhanden? Secret-Scan vor Build-Step? (`cicd/P03`, `cicd/F04`)
- Dockerfile-Änderungen: wird die Version zur Build-Zeit in eine **Datei** gebrannt (kanonisch `/app/VERSION` bzw. `version.json` bei Frontends), nicht nur als ENV gesetzt? OCI-Standard-Labels (`org.opencontainers.image.version`/`.revision`/`.created`) aus derselben Quelle vorhanden? ENV als **alleinige** Laufzeit-Versionsquelle ohne Datei-Fallback → **Important** (`cicd/F02`, `cicd/P08`)
- Rollout-Skripte/-Doku: `docker restart` statt `rm + run`? → **Important** (`cicd/F01`)
- Rollout-Skripte/-Doku: `docker image prune -f` vorhanden? Fehlt → **Important** (`cicd/F07`)
- Rollout-Skripte/-Doku: CI-Watch vor `docker pull`? Fehlt → **Important** (`cicd/F06`)
- CI-Watch-/Ship-Skripte: wird der beobachtete Run über `headSha == eigene SHA` zugeordnet (nicht blind `gh run list --limit 1`)? Fehlt → **Critical** (`cicd/F08`)
- CI-Gate-Skripte: wird `.github/workflows/*` (oder ein anderes strukturiertes Format) in Bash mit `grep`/`sed`/`awk`/Eigenbau-Parser interpretiert, um eine sicherheitskritische Entscheidung zu treffen? → **Critical** — empirisch beobachten statt parsen (`cicd/F08`)
- CI-Gate-Entscheidung: führt jede Unsicherheit auf dem `default_branch` zum scharfen Watch/`die` (nie Skip)? Skip nur auf Nicht-`default_branch`? Kein Schalter, der den Watch auf `main` abschaltet? Fehlt → **Critical** (`cicd/F09`)
- gitleaks-Allowlist-Änderungen: jeder neue Entry mit Begründung + bewiesener Nicht-Secret-Nachweis? (`cicd/F03`)
- CI-Workflow-Änderungen: Node20-Actions (`actions/checkout@v4`, `gitleaks/gitleaks-action@v2`) noch gepinnt, obwohl Node24-fähige Major existiert? → **Important** (`cicd/F10`)
- Workflows mit `pull_request_target`/`workflow_run` + Fork-Checkout: ist das neue Default-Blockverhalten von `actions/checkout` (seit 20.07.2026 auch auf fliessenden Majors) berücksichtigt bzw. `allow-unsafe-pr-checkout` bewusst + begründet gesetzt? → **Critical**, falls unbemerkt (`cicd/F11`)

## Test-Approach (für den `tester`-Agenten)
- Nach einem Rollout: Smoke `curl -fsS http://localhost:<port>/` → HTTP 200.
- Versions-Stempel-Check: `docker inspect --format '{{index .Config.Labels "org.opencontainers.image.version"}}' <image>:latest` → nicht leer, nicht `dev`.
- Version-Abgleich Datei/Label nach dem Rollout (`cicd/P08`): `curl -fsS http://localhost:<port>/version` (bzw. `version.json` bei Frontends) gegen `docker inspect --format '{{index .Config.Labels "org.opencontainers.image.version"}}' <image>:latest` — bei Match `OK`, bei Mismatch **WARN** erwartet (kein Hard-Fail), mit Hinweis auf mögliche ENV-Overwrite-Regression.
- CI-Pipeline nach dem Fix: `gh run list --limit 1 --json conclusion` → `success`.
- Prune-Check: `docker images --filter dangling=true` → nach `prune -f` sollte die Liste leer sein.
- CI-Gate-Skript (`cicd/F08`/`F09`), Fixture-Stil mit `gh`-Mocks: (a) Mock-Run mit `headSha` ≠ eigene SHA → gilt **nicht** als eigener Run, Fenster läuft weiter (keine `conclusion`-Auswertung); (b) kein Run für die eigene SHA auf **Nicht-`default_branch`** → Skip (Exit 0, kurze Laufzeit); (c) kein Run für die eigene SHA auf **`default_branch`** → **kein** Skip (Timeout/`die`, kein Rollout).
