---
name: preview
description: Deployt das produktive ghcr-Image eines Projekts als Container und gibt eine Test-URL — up [<app>] | down [<app>] | list | available. Mac (DEPLOY_ROLE=local): http://localhost:<port>. VPS (DEPLOY_ROLE=vps): https://<app>.<PREVIEW_DOMAIN> via Cloudflare-Tunnel. Cleanup lässt das ghcr-Image, das Repo und das Board unangetastet. Im Projekt-Repo ausführen — oder up <app> / available repo-unabhängig.
---

# /preview up [<app>] | down [<app>] | list | available

cwd = Ziel-Projekt-Repo (für `up`/`down` **ohne** Argument; liest `.claude/profile.md`). `up <app>` und `available` sind **repo-unabhängig** (Org `studis-softwareschmiede`) — von überall nutzbar. ⚠️ **Shell ist zsh:** Image-Ref immer mit Klammern — `"${image}:latest"`, **nie** `"$image:latest"` (zsh würde `:l` als Lowercase-Modifier interpretieren → kaputter Ref). ⚠️ **ghcr/Docker-Repo-Namen sind IMMER lowercase** — App-/Repo-Namen für `image` und `up <app>` kleinschreiben (`tr 'A-Z' 'a-z'`); GitHub erlaubt Großbuchstaben im Repo-Namen, Docker **nicht** (Repo `Spoon-Knife` → Image `spoon-knife`). **Source of Truth = das ghcr-Image** — Container/lokales Image/Cloudflare-Route sind wegwerfbar und jederzeit daraus neu erzeugbar (siehe CONCEPT §8a).

## Variablen
**Ohne Argument (cwd-Projekt, aus dem Profil):**
- `image` ← `profile.image` (z.B. `ghcr.io/studis-softwareschmiede/sandbox-2`); `app` ← letztes Segment.
- `container_port` ← `profile.container_port`; fehlt → `EXPOSE` aus `./Dockerfile` grep'en; sonst `80`.
- `preview_port` ← `profile.preview_port`; fehlt → **erste freie** Host-Port ab `8080` wählen und in `profile.md` eintragen (persistent).
- `db_dialect` ← `profile.db_dialect` (Werte: `postgres|mysql|sqlite|mongodb|none`; fehlt → `none`). Steuert, ob ein DB-Service vor der App startet (Spec §12 + db-subsystem §2).

**Mit `up <app>` (repo-unabhängig, kein Profil):**
- `app` ← `<app>` **kleingeschrieben** (`tr 'A-Z' 'a-z'`); `image` ← `ghcr.io/studis-softwareschmiede/<app-lowercase>` (Docker-Repo-Namen sind immer lowercase — auch wenn das GitHub-Repo Großbuchstaben hat).
- `container_port` ← **nach dem Pull aus dem Image** ableiten: `docker inspect --format '{{range $p,$_ := .Config.ExposedPorts}}{{$p}} {{end}}' "${image}:latest"` → erste Portnummer; Fallback `80`.
- `preview_port` ← **erste freie** ab `8080` (Laufzeit, nicht persistiert — evtl. kein lokales Profil).
- `db_dialect` ← **immer `none`** (Spec §12 — repo-loser Preview kann den DB-Dialekt nicht aus dem ghcr-Image ableiten; nur App-Container). Hinweis ausgeben: „Repo-loser Preview unterstützt keine DB; im Repo ausführen für vollen Stack."

- `role` ← env `DEPLOY_ROLE` (sonst `local`); `domain` ← env `PREVIEW_DOMAIN` (nur bei `vps` nötig).
- `compose_project` ← `preview-${app}-${preview_port}` (eindeutiger Compose-`-p`-Name pro Preview → **isoliertes Network + isolierte Volumes**, mehrere PR-Previews parallel ohne State-Race; Spec §12).
- `db_volume` ← `${compose_project}_db_data` (vom Compose-Fragment automatisch als named-Volume mit diesem Prefix erzeugt; Spec §12).
- `db_network` ← `${compose_project}_default` (Compose-implicit Default-Netz; App muss `--network "$db_network"` joinen, damit `db` per DNS auflösbar ist).

## up  [<app>]
Ohne Argument: Image/App aus dem cwd-`profile.md`. Mit `<app>`: `image=ghcr.io/studis-softwareschmiede/<app-lowercase>`, kein Profil nötig (Name kleinschreiben!).

**0. Validate-Cache-Check** (Spec [`docs/architecture/db-subsystem.md`](../../docs/architecture/db-subsystem.md) §18) — nur bei **Repo-Modus mit Profil** (nicht bei `up <app>` repo-los) UND nur wenn `db_dialect != none` ODER `companions` nicht leer ist. Vor dem Image-Pull entscheiden, ob ein Mini-Re-Validate nötig ist:
   ```
   # aus .claude/profile.md lesen (yq oder grep-fallback)
   validated_at=$(yq -r '.adoption_validated_at         // ""' .claude/profile.md)
   validated_dialect=$(yq -r '.adoption_validated_dialect    // ""' .claude/profile.md)
   validated_companions=$(yq -o=json '.adoption_validated_companions // []' .claude/profile.md)
   current_dialect="${db_dialect}"
   current_companions=$(yq -o=json '.companions // []' .claude/profile.md)

   CACHE_HIT=false
   if [ -n "$validated_at" ] \
      && [ "$validated_dialect"    = "$current_dialect" ] \
      && [ "$validated_companions" = "$current_companions" ]; then
     CACHE_HIT=true
   fi
   ```
   - **`CACHE_HIT=true`** (Flag gesetzt UND Dialect+Companions unverändert seit Validate): den teuren E2E-Smoke-Check **skippen** — Schritte 1..5 laufen als "schnelles" preview-up (DB+App hochfahren, **keine** Trivial-Query / Marker-Verify). Klar-Output: `cache-hit: profile.adoption_validated_at=<date> — skip E2E re-validate, fast preview-up`.
   - **`CACHE_HIT=false`** (Flag fehlt ODER Dialect/Companions geändert seit Validate ODER durch `/flow` invalidiert): nach dem normalen preview-up (Schritte 1..5) **Mini-Re-Validate** ausführen (gleicher `tester`-Dispatch wie `/adopt` §6.a, aber **ohne** den Coder-Fix-Loop — bei FAIL nur Warn-Output, **nicht** den preview-up abbrechen; siehe Schritt 6 unten). Bei PASS → `adoption_validated_at` neu schreiben (Cache-Refresh, `chore: preview re-validate refresh`-Commit best-effort, scheitert leise wenn Working-Tree dirty).
   - **`up <app>` repo-los** (kein Profil): Cache-Check skip, immer `CACHE_HIT=false`, **kein** Re-Validate (Repo-loser Preview hat keine DB — nichts zu validieren). Identisch zum bestehenden Verhalten.

1. **Image holen:** `docker pull "${image}:latest"`. (Public ghcr → ohne Auth. Bei `denied`: Package-Visibility prüfen — CONCEPT §8a, Org muss public Packages erlauben.) **Bei `up <app>`:** danach `container_port` aus dem Image ableiten (s. Variablen).
2. **DB-Service starten** (nur wenn `db_dialect ∈ {postgres,mysql,mongodb}` — siehe „DB-Subsystem-Integration" unten; bei `sqlite` siehe Sonderfall; bei `none` Schritt überspringen).
3. **App starten** (ersetzt eine evtl. laufende Instanz):
   ```
   docker rm -f "$app" 2>/dev/null || true
   # NETARG ist leer wenn db_dialect=none, sonst --network "$db_network" (= ${compose_project}_default)
   NETARG=""; [ "$db_dialect" != "none" ] && NETARG="--network ${db_network}"
   # DBENV nur wenn DB aktiv; postgres/mysql/mongodb sehen "db" per Compose-DNS, sqlite via Pfad
   DBENV=""
   case "$db_dialect" in
     postgres|mysql|mongodb) DBENV="-e DB_HOST=db" ;;
     sqlite)                 DBENV="-e DB_PATH=/data/app.db -v ${compose_project}_db_data:/data" ;;
   esac
   docker run -d --name "$app" --label agent-flow.preview="$app" \
     --label agent-flow.compose-project="$compose_project" \
     --label agent-flow.db-dialect="$db_dialect" \
     --restart unless-stopped \
     $NETARG $DBENV \
     -p "${preview_port}:${container_port}" "${image}:latest"
   ```
   *(Die `agent-flow.compose-project`/`agent-flow.db-dialect`-Labels werden in `down`/`list` gebraucht — sie sind die einzige Quelle, um die DB-Stack-Zuordnung wiederzufinden, ohne erneut `profile.md` zu lesen.)*
4. **Smoke:** `curl -fsS -o /dev/null -w '%{http_code}' http://localhost:$preview_port/` → 200 erwartet (sonst Logs `docker logs "$app"` zeigen + melden; bei DB-Fehler auch `docker compose -p "$compose_project" logs db migrations`).
5. **URL melden:** (DB ist intern, kein Port-Mapping → URL unverändert zur Variante ohne DB)
   - `local` → **`http://localhost:$preview_port`**
   - `vps` → Cloudflare-Route sicherstellen (s.u.) → **`https://$app.$domain`**

6. **Mini-Re-Validate** (Spec §18, **nur wenn `CACHE_HIT=false` aus Schritt 0** UND Profil vorhanden UND `db_dialect != none` ODER `companions` nicht leer):
   - **Auftrag an `tester` (Adoption-Validate-Modus, kürzer als `/adopt` §6.a — kein eigener `/preview up` mehr, der Stack läuft schon):**
     1. Marker-Migration appliziert (`SELECT count(*) FROM _schema_migrations` ≥ 1 / Mongo-Äquivalent — direkt gegen den laufenden DB-Container über `docker exec`).
     2. Trivial-Query auf marker (1 Zeile reicht).
     3. Companion-Health (falls `companions` nicht leer): `docker inspect <companion>.State.Health.Status == healthy`.
     4. **Kein** `/preview down` — der Stack soll weiterlaufen, der User will ja preview-en.
   - **PASS** → `adoption_validated_at` in `.claude/profile.md` aktualisieren (best-effort-Commit `chore: preview re-validate refresh` auf dem aktuellen Branch; bei dirty Working-Tree: Output „cache-refreshed in profile.md, commit pending — git add .claude/profile.md").
     Klar-Output: `✓ re-validate PASS — cache refreshed, profile.adoption_validated_at=<date>`.
   - **FAIL** → **Warn**, NICHT abbrechen (preview soll trotzdem nutzbar bleiben). Output: `⚠ re-validate FAIL at <stage> — preview is up but unverified. Run /adopt re-validate to fix, or check logs: <hint>`. `adoption_validated_at` bleibt unverändert (alter Wert bleibt — oder fehlt weiter, falls noch nie validiert).
   - **Begründung "Mini" vs `/adopt` §6.c:** `/preview` ist ein Dev-Loop-Befehl, der nicht durch FAIL blockieren darf — die Fix-Verantwortung liegt explizit beim `/adopt re-validate`-Mode oder beim nächsten `/flow`-Item. Kein Coder-Fix-Loop, kein Backlog-Issue.

### DB-Subsystem-Integration (Spec §12)
Nur wenn `db_dialect != none` und Profil vorhanden (also **nicht** bei `up <app>` repo-los).

0. **Enum-Validierung** (vor jedem Pfad-Zugriff `templates/_shared/db-$db_dialect/`):
   ```
   case "$db_dialect" in
     postgres|mysql|sqlite|mongodb|none) ;;
     *) echo "FEHLER: unbekannter db_dialect='$db_dialect' (erlaubt: postgres|mysql|sqlite|mongodb|none) — skip DB-Stack"; db_dialect="none"; return 0 2>/dev/null || exit 1 ;;
   esac
   ```
   Bei unbekanntem Wert: klare Fehlermeldung + skip (kein Pfad-Zusammensetzen mit garbage). Bewahrt auch vor Path-Traversal.
1. **Fragment lokalisieren** (mit Existence-Guard — Spec §14-Amendment Graceful Degradation):
   ```
   FRAG="$CLAUDE_PLUGIN_ROOT/templates/_shared/db-${db_dialect}/compose.fragment.yml"
   [ -f "$FRAG" ] || { echo "FEHLER: kein Compose-Fragment für db_dialect=$db_dialect ($FRAG) — Welle 2 fehlt"; exit 1; }
   ```
2. **Compose-Stack starten** mit eindeutigem Project-Name (isoliertes Network + Volume, mehrere parallele Previews kollidieren nicht):
   ```
   docker compose -p "$compose_project" -f "$FRAG" up -d db
   ```
   *(Bei `sqlite` gibt es **keinen `db`-Service** — Schritt 2+3 entfallen; das Volume `${compose_project}_db_data` wird in Schritt 5 direkt vom App-Container per `-v` gemountet, siehe Sonderfall unten.)*
3. **Healthcheck-Wait** (Timeout 60s, Polling 2s):
   ```
   CID=$(docker compose -p "$compose_project" -f "$FRAG" ps -q db)
   for i in $(seq 1 30); do
     [ "$(docker inspect --format '{{.State.Health.Status}}' "$CID" 2>/dev/null)" = "healthy" ] && break
     sleep 2
   done
   [ "$(docker inspect --format '{{.State.Health.Status}}' "$CID")" = "healthy" ] || {
     docker compose -p "$compose_project" -f "$FRAG" logs db
     echo "DB nicht healthy nach 60s — abbrechen"; exit 1
   }
   ```
4. **Migrations one-shot** (zwischen DB-healthy und App-Start; Spec §12 + §6):
   - **Wenn `./db_scripts/run-migrations.sh` existiert:**
     ```
     docker compose -p "$compose_project" -f "$FRAG" run --rm migrations
     ```
     Exit-Code != 0 → DB-Logs zeigen und abbrechen. Der `migrations`-Service im Fragment ist `restart: "no"` (one-shot) und mountet `./db_scripts:/db_scripts:ro` — er bringt den jeweiligen DB-Client mit (psql/mariadb/mongosh/sqlite3), die App-Images müssen keinen Client backen.
   - **Existiert nicht** → skip + Hinweis: „kein `db_scripts/run-migrations.sh` gefunden — Migrations übersprungen (DB läuft leer)".
5. **SQLite-Sonderfall** (Spec §12): kein `db`-Service, kein Healthcheck — nur der one-shot `migrations`-Service apply'd die Files ins Volume:
   ```
   docker compose -p "$compose_project" -f "$FRAG" run --rm migrations
   ```
   Das Volume `${compose_project}_db_data` wird in Schritt 3 (App-Start) gemountet — die App liest `/data/app.db` per `DB_PATH`-Env (Bestandteil von `DBENV` oben).

### Repo-loser Modus (`up <app>` ohne Profil)
**Keine DB.** Spec §12: der DB-Dialekt kann nicht aus dem ghcr-Image abgeleitet werden. Hinweis ausgeben („Repo-loser Preview unterstützt keine DB; im Repo ausführen für vollen Stack.") und nur den App-Container starten (Schritt 3 mit `db_dialect=none`).

### Nur `role=vps`: Cloudflare-Route anlegen (idempotent)
- `source "$CLAUDE_PLUGIN_ROOT/scripts/load-env.sh"` → `CLOUDFLARE_API_TOKEN` / `_ACCOUNT_ID` / `_ZONE_ID`.
- Tunnel-Ingress `$app.$domain → http://localhost:$preview_port` in die cloudflared-Config eintragen (falls nicht vorhanden) → `cloudflared tunnel route dns <tunnel> $app.$domain` → cloudflared neu laden.
- *(Detail-Implementierung kommt mit dem VPS-Bootstrap; auf dem Mac nicht nötig.)*

## down  [<app>] [--keep-data] [--prune]
Argument optional (sonst `app` aus dem Profil; mit `<app>` ist `image=ghcr.io/studis-softwareschmiede/<app-lowercase>` für `--prune`).
Flags:
- `--keep-data` → DB-Volume behalten (für späteres `up` mit demselben State). Default: löschen — Preview ist disposable (Spec §12 + CONCEPT §8a).
- `--prune` → zusätzlich lokales App-Image entfernen.

1. **DB-Stack-Zuordnung wiederfinden:** `compose_project` aus dem Container-Label lesen (von `up` gesetzt):
   ```
   compose_project=$(docker inspect --format '{{ index .Config.Labels "agent-flow.compose-project" }}' "$app" 2>/dev/null)
   db_dialect=$(docker inspect --format '{{ index .Config.Labels "agent-flow.db-dialect" }}' "$app" 2>/dev/null)
   ```
   Fallback (Container schon weg / kein Label): `compose_project` aus Profil rekonstruieren (`preview-${app}-${profile.preview_port}`).
2. **App-Container** stoppen + entfernen: `docker rm -f "$app"`.
3. **DB-Stack** (nur wenn `db_dialect` gesetzt und `!= none`):
   **Enum-Validierung + Fragment-Guard** (Spec §14-Amendment Graceful Degradation — identisch zu `up`):
   ```
   case "$db_dialect" in
     postgres|mysql|sqlite|mongodb) ;;
     *) echo "WARN: unbekannter db_dialect='$db_dialect' aus Label — skip DB down"; db_dialect="" ;;
   esac
   FRAG="$CLAUDE_PLUGIN_ROOT/templates/_shared/db-${db_dialect}/compose.fragment.yml"
   if [ -n "$db_dialect" ] && [ ! -f "$FRAG" ]; then
     echo "WARN: Fragment fehlt für db_dialect=$db_dialect ($FRAG) — App-Container ist down, DB-Stack-Cleanup übersprungen (manuell prüfen: docker compose -p $compose_project down -v)"
     db_dialect=""
   fi
   ```
   Bei fehlendem Fragment oder unbekanntem Dialekt wird **nur** der App-Container runtergefahren (Schritt 2 bereits erledigt) — kein Crash, klare Warn-Log-Zeile.
   - Default (Volume löschen):
     ```
     [ -n "$db_dialect" ] && docker compose -p "$compose_project" -f "$FRAG" down -v
     ```
     `-v` entfernt das named-Volume `${compose_project}_db_data` (Spec §12).
   - Mit `--keep-data`:
     ```
     [ -n "$db_dialect" ] && docker compose -p "$compose_project" -f "$FRAG" down
     ```
     Volume überlebt für späteres `up` (gleicher `compose_project` → gleiches Volume).
4. `role=vps`: Tunnel-Ingress-Regel für `$app` entfernen + DNS-CNAME `$app.$domain` via Cloudflare-API löschen.
5. **Optional `--prune`:** `docker rmi "${image}:latest"` (lokales Image; aus ghcr jederzeit wieder ziehbar).
6. **NIE anfassen:** ghcr-Image, Repo, Board, Issues, ghcr-DB-Images (`postgres:17-alpine` etc. — bleiben für nächstes `up` im lokalen Cache).

## list
- `docker ps -a --filter label=agent-flow.preview --format '{{.Names}}\t{{.Ports}}\t{{.Status}}\t{{.Image}}\t{{.Label "agent-flow.compose-project"}}\t{{.Label "agent-flow.db-dialect"}}'`.
- Daraus eine Markdown-Tabelle mit **klickbarer URL-Spalte** rendern (die URL gehört **in die Tabelle**, nicht als Zeile darunter): Spalten **Name · URL · Status · Image · DB**. Die URL pro Zeile aus dem veröffentlichten Host-Port ableiten und als blanke URL in die Zelle schreiben (GFM verlinkt sie automatisch → klickbar):
  - `local` → `http://localhost:<hostport>` (Host-Port aus `Ports`, z.B. `0.0.0.0:8080->80/tcp` → `8080`).
  - `vps` → `https://<name>.<PREVIEW_DOMAIN>`.
- **DB-Spalte** (Spec §12) pro Preview:
  - `db_dialect=none` oder Label leer → `—`.
  - sonst, für `compose_project = <labelwert>`:
    - DB-Container-Status: `docker compose -p "$compose_project" ps db --format '{{.State}}'` → `running` / `exited` / `—`. (Bei `sqlite` gibt's keinen `db`-Service → `n/a (sqlite)`.)
    - Volume-Größe: `docker system df -v --format '{{json .}}' | jq -r --arg v "${compose_project}_db_data" '.Volumes[]|select(.Name==$v)|.Size'` (oder Fallback `docker volume inspect ${compose_project}_db_data --format '{{.Mountpoint}}'` + `du -sh`). Fehlt das Volume (already pruned) → `—`.
  - Zellen-Format: `<dialect> · <status> · <size>` (z.B. `postgres · running · 42 MB`, `sqlite · n/a · 1.2 MB`).
- `role=vps`: zusätzlich aktive Tunnel-Routen auflisten.

## available
Listet die **previewbaren Apps** der Org (= Projekt-Repos → ghcr-Image-Kandidat `ghcr.io/studis-softwareschmiede/<name>`) als Menü für `up <app>` — repo-unabhängig:
- `gh repo list studis-softwareschmiede --no-archived --limit 100 --json name -q '.[].name'` → alle Repos **außer `agent-flow`** (die Fabrik selbst ist kein deploybares Projekt).
- Als Liste rendern: `<name>` → ladbar mit `/agent-flow:preview up <name-lowercase>` (Image-/`up`-Name **immer lowercase**, auch wenn das Repo Großbuchstaben hat — sonst schlägt der `docker pull` fehl); bereits laufende via `list` markieren (inkl. DB-Status pro Zeile wie in `list`).
- Hinweis bei jedem Eintrag: „DB nur im Repo-Modus" (Spec §12 — `up <app>` ohne Profil startet keine DB).
- *(Gebaute Images sieht man auf der GitHub-Packages-Seite der Org; die REST-Packages-API ist mit dem App-Token nicht zuverlässig listbar.)*

## Grenzen
- Kein App-Code, keine git-/Board-/Issue-Änderungen. Nur Container + (auf VPS) Cloudflare-Routen.
- ghcr-Image ist **Source of Truth** → Cleanup entfernt es nie.
- TTL = manuell: eine Preview lebt bis `/preview down`.
- DB ist **intern pro Preview** (kein Port-Mapping nach außen — die `ports:`-Zeile im Compose-Fragment ist Preview/Dev-only und auskommentiert für postgres/mongodb; für mysql nur via env-Override). Preview-URL bleibt identisch zur DB-losen Variante.
- DB-Volumes sind **pro Preview isoliert** (`preview-<app>-<port>_db_data`) — parallele PR-Previews kollidieren nicht, Default-`down` löscht das Volume (disposable).
- **Validate-Cache (Schritt 0+6, Spec §18):** Cache-Hit (Flag gesetzt, Dialect+Companions unverändert) → kein Mini-Re-Validate (schneller preview-up). Cache-Miss → Mini-Re-Validate **best-effort**: FAIL bricht preview-up **nicht** ab (Dev-Loop-Verfügbarkeit > Verifikation; Fix via `/adopt re-validate` oder nächstes `/flow`-Item). Schwergewichtiger Coder-Fix-Loop lebt nur in `/adopt` §6, nicht hier.
