#!/usr/bin/env bash
# provision-gpg-pass.sh — materialisiert die PER-APP GPG-Passphrase aus Bitwarden
# in eine kurzlebige 0600-Datei und gibt deren Pfad auf stdout aus.
#
# Doktrin: dev-gui ist die EINZIGE Bitwarden-Boundary. agent-flow bleibt
# Bitwarden-agnostisch — dieses Skript spricht NIE selbst mit einem Bitwarden-
# Konto, sondern nur mit dem laufenden dev-gui-Container (der den unbeaufsichtigten
# Zugang + die bw-CLI besitzt) via `docker exec`. Der Zugang verlässt den Container
# nicht; nur die eine Ziel-Passphrase kommt heraus.
#
# App-Slug-Auflösung:  $1  >  $GPG_BW_APP  >  basename des Git-Toplevel (CWD)
# Item-Konvention:     env.gpg-passphrase-<app>   (dev-gui F-072/F-073)
# Container:           $DEVGUI_CONTAINER (Default: dev-gui-dev-gui-1)
#
# Kein Erfolg (kein Docker/Container/Item/leer) -> Exit !=0, KEINE Ausgabe.
# Der Aufrufer (resolve_pass_file) fällt dann auf die statische gpg.pass zurück.
set -uo pipefail

# 1) App-Slug bestimmen + auf sichere Zeichen begrenzen (fließt in den Item-Namen)
APP="${1:-${GPG_BW_APP:-}}"
[[ -z "$APP" ]] && APP="$(basename "$(git rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null || true)"
APP="${APP//[^a-zA-Z0-9._-]/}"
[[ -n "$APP" ]] || exit 1

# 2) Cache: frische per-App-Datei wiederverwenden (spart bw-Login → Latenz +
#    Rate-Limit). TTL in Minuten via GPG_BW_TTL_MIN (Default 60). Deterministischer
#    0600-Name je App. Alte Reste (>TTL) aufräumen.
umask 077
TDIR="${TMPDIR:-/tmp}"; TDIR="${TDIR%/}"
TTL="${GPG_BW_TTL_MIN:-60}"
CACHE="$TDIR/sos-gpgpass-cache-${APP}"
find "$TDIR" -maxdepth 1 -name 'sos-gpgpass-cache-*' -mmin "+$TTL" -delete 2>/dev/null || true
if [[ -r "$CACHE" && -s "$CACHE" && -n "$(find "$CACHE" -mmin "-$TTL" 2>/dev/null)" ]]; then
  printf '%s' "$CACHE"; exit 0
fi

# 3) Container-Boundary prüfen (nur nötig, wenn kein frischer Cache)
CONTAINER="${DEVGUI_CONTAINER:-dev-gui-dev-gui-1}"
command -v docker >/dev/null 2>&1 || exit 1
docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$CONTAINER" || exit 1

# 4) Passphrase über den dev-gui-Container aus Bitwarden lesen (isolierte bw-Session)
PASS="$(docker exec "$CONTAINER" bash -c '
set -u
F=/home/node/.cred/bitwarden-deploy-access.json
[ -r "$F" ] || exit 1
val(){ node -e "console.log(JSON.parse(require(\"fs\").readFileSync(process.argv[1])).fields[process.argv[2]]?.value||\"\")" "$F" "$1"; }
export BITWARDENCLI_APPDATA_DIR="$(mktemp -d)"
trap "rm -rf \"$BITWARDENCLI_APPDATA_DIR\"" EXIT
SRV="$(val server_url)"; CID="$(val client_id)"; CSEC="$(val client_secret)"; MPW="$(val master_password)"
[ -n "$SRV" ] && bw config server "$SRV" >/dev/null 2>&1
BW_CLIENTID="$CID" BW_CLIENTSECRET="$CSEC" bw login --apikey >/dev/null 2>&1 || exit 1
SESSION="$(BW_PASSWORD="$MPW" bw unlock --passwordenv BW_PASSWORD --raw 2>/dev/null)"
[ -n "$SESSION" ] || exit 1
RC=0
BW_SESSION="$SESSION" bw get password "env.gpg-passphrase-'"$APP"'" 2>/dev/null || RC=1
bw logout >/dev/null 2>&1 || true
exit $RC
')" || exit 1
[[ -n "$PASS" ]] || exit 1

# 5) Atomar in die 0600-Cache-Datei materialisieren, Pfad ausgeben
printf '%s' "$PASS" > "$CACHE.tmp.$$" && chmod 600 "$CACHE.tmp.$$" && mv -f "$CACHE.tmp.$$" "$CACHE"
printf '%s' "$CACHE"
