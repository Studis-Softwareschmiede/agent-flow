---
name: preview
description: Deployt das produktive ghcr-Image eines Projekts als Container und gibt eine Test-URL — up [<app>] | down [<app>] | list | available. Mac (DEPLOY_ROLE=local): http://localhost:<port>. VPS (DEPLOY_ROLE=vps): https://<app>.<PREVIEW_DOMAIN> via Cloudflare-Tunnel. Cleanup lässt das ghcr-Image, das Repo und das Board unangetastet. Im Projekt-Repo ausführen — oder up <app> / available repo-unabhängig.
---

# /preview up [<app>] | down [<app>] | list | available

cwd = Ziel-Projekt-Repo (für `up`/`down` **ohne** Argument; liest `.claude/profile.md`). `up <app>` und `available` sind **repo-unabhängig** (Org `studis-softwareschmiede`) — von überall nutzbar. ⚠️ **Shell ist zsh:** Image-Ref immer mit Klammern — `"${image}:latest"`, **nie** `"$image:latest"` (zsh würde `:l` als Lowercase-Modifier interpretieren → kaputter Ref). **Source of Truth = das ghcr-Image** — Container/lokales Image/Cloudflare-Route sind wegwerfbar und jederzeit daraus neu erzeugbar (siehe CONCEPT §8a).

## Variablen
**Ohne Argument (cwd-Projekt, aus dem Profil):**
- `image` ← `profile.image` (z.B. `ghcr.io/studis-softwareschmiede/sandbox-2`); `app` ← letztes Segment.
- `container_port` ← `profile.container_port`; fehlt → `EXPOSE` aus `./Dockerfile` grep'en; sonst `80`.
- `preview_port` ← `profile.preview_port`; fehlt → **erste freie** Host-Port ab `8080` wählen und in `profile.md` eintragen (persistent).

**Mit `up <app>` (repo-unabhängig, kein Profil):**
- `app` ← `<app>`; `image` ← `ghcr.io/studis-softwareschmiede/<app>`.
- `container_port` ← **nach dem Pull aus dem Image** ableiten: `docker inspect --format '{{range $p,$_ := .Config.ExposedPorts}}{{$p}} {{end}}' "${image}:latest"` → erste Portnummer; Fallback `80`.
- `preview_port` ← **erste freie** ab `8080` (Laufzeit, nicht persistiert — evtl. kein lokales Profil).

- `role` ← env `DEPLOY_ROLE` (sonst `local`); `domain` ← env `PREVIEW_DOMAIN` (nur bei `vps` nötig).

## up  [<app>]
Ohne Argument: Image/App aus dem cwd-`profile.md`. Mit `<app>`: `image=ghcr.io/studis-softwareschmiede/<app>`, kein Profil nötig.
1. **Image holen:** `docker pull "${image}:latest"`. (Public ghcr → ohne Auth. Bei `denied`: Package-Visibility prüfen — CONCEPT §8a, Org muss public Packages erlauben.) **Bei `up <app>`:** danach `container_port` aus dem Image ableiten (s. Variablen).
2. **Starten** (ersetzt eine evtl. laufende Instanz):
   ```
   docker rm -f "$app" 2>/dev/null || true
   docker run -d --name "$app" --label agent-flow.preview="$app" --restart unless-stopped \
     -p "${preview_port}:${container_port}" "${image}:latest"
   ```
3. **Smoke:** `curl -fsS -o /dev/null -w '%{http_code}' http://localhost:$preview_port/` → 200 erwartet (sonst Logs `docker logs "$app"` zeigen + melden).
4. **URL melden:**
   - `local` → **`http://localhost:$preview_port`**
   - `vps` → Cloudflare-Route sicherstellen (s.u.) → **`https://$app.$domain`**

### Nur `role=vps`: Cloudflare-Route anlegen (idempotent)
- `source "$CLAUDE_PLUGIN_ROOT/scripts/load-env.sh"` → `CLOUDFLARE_API_TOKEN` / `_ACCOUNT_ID` / `_ZONE_ID`.
- Tunnel-Ingress `$app.$domain → http://localhost:$preview_port` in die cloudflared-Config eintragen (falls nicht vorhanden) → `cloudflared tunnel route dns <tunnel> $app.$domain` → cloudflared neu laden.
- *(Detail-Implementierung kommt mit dem VPS-Bootstrap; auf dem Mac nicht nötig.)*

## down  [<app>]
Argument optional (sonst `app` aus dem Profil; mit `<app>` ist `image=ghcr.io/studis-softwareschmiede/<app>` für `--prune`).
1. `docker rm -f "$app"` (Container stoppen + entfernen).
2. `role=vps`: Tunnel-Ingress-Regel für `$app` entfernen + DNS-CNAME `$app.$domain` via Cloudflare-API löschen.
3. **Optional `--prune`:** `docker rmi "${image}:latest"` (lokales Image; aus ghcr jederzeit wieder ziehbar).
4. **NIE anfassen:** ghcr-Image, Repo, Board, Issues.

## list
- `docker ps -a --filter label=agent-flow.preview --format '{{.Names}}\t{{.Ports}}\t{{.Status}}\t{{.Image}}'`.
- Daraus eine Markdown-Tabelle mit **klickbarer URL-Spalte** rendern (die URL gehört **in die Tabelle**, nicht als Zeile darunter): Spalten **Name · URL · Status · Image**. Die URL pro Zeile aus dem veröffentlichten Host-Port ableiten und als blanke URL in die Zelle schreiben (GFM verlinkt sie automatisch → klickbar):
  - `local` → `http://localhost:<hostport>` (Host-Port aus `Ports`, z.B. `0.0.0.0:8080->80/tcp` → `8080`).
  - `vps` → `https://<name>.<PREVIEW_DOMAIN>`.
- `role=vps`: zusätzlich aktive Tunnel-Routen auflisten.

## available
Listet die **previewbaren Apps** der Org (= Projekt-Repos → ghcr-Image-Kandidat `ghcr.io/studis-softwareschmiede/<name>`) als Menü für `up <app>` — repo-unabhängig:
- `gh repo list studis-softwareschmiede --no-archived --limit 100 --json name -q '.[].name'` → alle Repos **außer `agent-flow`** (die Fabrik selbst ist kein deploybares Projekt).
- Als Liste rendern: `<name>` → ladbar mit `/agent-flow:preview up <name>`; bereits laufende via `list` markieren.
- *(Gebaute Images sieht man auf der GitHub-Packages-Seite der Org; die REST-Packages-API ist mit dem App-Token nicht zuverlässig listbar.)*

## Grenzen
- Kein App-Code, keine git-/Board-/Issue-Änderungen. Nur Container + (auf VPS) Cloudflare-Routen.
- ghcr-Image ist **Source of Truth** → Cleanup entfernt es nie.
- TTL = manuell: eine Preview lebt bis `/preview down`.
