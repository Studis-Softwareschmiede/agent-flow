---
name: preview
description: Deployt das produktive ghcr-Image eines Projekts als Container und gibt eine Test-URL — up | down | list. Mac (DEPLOY_ROLE=local): http://localhost:<port>. VPS (DEPLOY_ROLE=vps): https://<app>.<PREVIEW_DOMAIN> via Cloudflare-Tunnel. Cleanup lässt das ghcr-Image, das Repo und das Board unangetastet. Im Ziel-Projekt-Repo ausführen.
---

# /preview up | down | list

cwd = Ziel-Projekt-Repo. Liest `.claude/profile.md`. ⚠️ **Shell ist zsh:** Image-Ref immer mit Klammern — `"${image}:latest"`, **nie** `"$image:latest"` (zsh würde `:l` als Lowercase-Modifier interpretieren → kaputter Ref). **Source of Truth = das ghcr-Image** — Container/lokales Image/Cloudflare-Route sind wegwerfbar und jederzeit daraus neu erzeugbar (siehe CONCEPT §8a).

## Variablen (aus dem Profil ableiten)
- `image` ← `profile.image` (z.B. `ghcr.io/studis-softwareschmiede/sandbox-2`).
- `app` ← letztes Segment von `image` (= Repo-/Container-Name).
- `container_port` ← `profile.container_port`; fehlt → `EXPOSE` aus `./Dockerfile` grep'en; sonst `80`.
- `preview_port` ← `profile.preview_port`; fehlt → **erste freie** Host-Port ab `8080` wählen und in `profile.md` eintragen (persistent).
- `role` ← env `DEPLOY_ROLE` (sonst `local`); `domain` ← env `PREVIEW_DOMAIN` (nur bei `vps` nötig).

## up
1. **Image holen:** `docker pull "${image}:latest"`. (Public ghcr → ohne Auth. Bei `denied`: Package-Visibility prüfen — CONCEPT §8a, Org muss public Packages erlauben.)
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
Argument optional (sonst `app` aus dem Profil).
1. `docker rm -f "$app"` (Container stoppen + entfernen).
2. `role=vps`: Tunnel-Ingress-Regel für `$app` entfernen + DNS-CNAME `$app.$domain` via Cloudflare-API löschen.
3. **Optional `--prune`:** `docker rmi "${image}:latest"` (lokales Image; aus ghcr jederzeit wieder ziehbar).
4. **NIE anfassen:** ghcr-Image, Repo, Board, Issues.

## list
- `docker ps -a --filter label=agent-flow.preview --format 'table {{.Names}}\t{{.Ports}}\t{{.Status}}\t{{.Image}}'`.
- `role=vps`: zusätzlich aktive Tunnel-Routen auflisten.

## Grenzen
- Kein App-Code, keine git-/Board-/Issue-Änderungen. Nur Container + (auf VPS) Cloudflare-Routen.
- ghcr-Image ist **Source of Truth** → Cleanup entfernt es nie.
- TTL = manuell: eine Preview lebt bis `/preview down`.
