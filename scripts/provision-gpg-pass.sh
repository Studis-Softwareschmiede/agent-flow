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
#
# Single-Flight (S-118, docs/specs/gpg-pass-single-flight.md): bei parallelem
# Fan-out (N Aufrufer, gleiche App, leerer Cache) macht NUR ein Aufrufer den
# Bitwarden-Roundtrip; alle anderen warten auf den gefüllten Cache statt je
# einen eigenen Login auszulösen (Mail-Schwall + Rate-Limit vermeiden).
#   AC1: exklusives, per-App gescoptes mkdir-Lock vor dem Container-Roundtrip,
#        Freigabe in JEDEM Ausgang (trap).
#   AC2: Wartende pollen auf frische Cache-Datei ODER Lock-Freigabe (dann
#        eigener Versuch); Warte-Timeout GPG_BW_WAIT_SEC (Default 90s) -> E2.
#   AC3: Lock älter als Stale-Schwelle gilt als verwaist und wird übernommen.
#   AC4: Cache/Lock an deterministischem, nutzer-privatem Ort (0700), NICHT
#        von session-spezifischem $TMPDIR abhängig. GPG_BW_CACHE_DIR (Env) >
#        fester nutzer-privater Default.
#   AC6: Container-Roundtrip über GPG_BW_FETCH_CMD ersetzbar (nur für Tests).
set -uo pipefail

# 1) App-Slug bestimmen + auf sichere Zeichen begrenzen (fließt in den Item-Namen)
APP="${1:-${GPG_BW_APP:-}}"
[[ -z "$APP" ]] && APP="$(basename "$(git rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null || true)"
APP="${APP//[^a-zA-Z0-9._-]/}"
[[ -n "$APP" ]] || exit 1

# 2) Cache-/Lock-Verzeichnis (AC4): GPG_BW_CACHE_DIR (Env) > fester
#    nutzer-privater Default — NICHT $TMPDIR (session-spezifisch, parallele
#    Agenten mit unterschiedlichem $TMPDIR sehen einander sonst nicht).
umask 077
CDIR="${GPG_BW_CACHE_DIR:-$HOME/.cache/softwareschmiede/gpg-bw}"
CDIR="${CDIR%/}"
mkdir -p "$CDIR" 2>/dev/null || exit 1
chmod 700 "$CDIR" 2>/dev/null || true

TTL="${GPG_BW_TTL_MIN:-60}"
CACHE="$CDIR/sos-gpgpass-cache-${APP}"
LOCK="$CDIR/sos-gpgpass-lock-${APP}"
WAIT_SEC="${GPG_BW_WAIT_SEC:-90}"
# Stale-Schwelle (AC3): eine Eigenschaft des LOCKS selbst (wie lange es
# unangetastet steht), unabhängig vom individuellen Warte-Timeout des
# jeweils fragenden Aufrufers — sonst würde ein Aufrufer mit knappem
# GPG_BW_WAIT_SEC ein von einem anderen Prozess noch aktiv gehaltenes Lock
# fälschlich als verwaist einstufen. Default = der Warte-Timeout-DEFAULT
# (90s, nicht der ggf. überschriebene Laufzeitwert dieses Aufrufs) — passend
# zu AC3 ("Default >= Warte-Timeout"). Kein eigener Env-Regler (Spec-Vertrag
# nennt nur GPG_BW_CACHE_DIR/GPG_BW_WAIT_SEC/GPG_BW_FETCH_CMD als neue
# Env-Parameter).
STALE_SEC=90
POLL_SEC=0.5

# Alte Reste (>TTL) aufräumen (per-App-scope, wie zuvor — nur eigenes Verzeichnis).
find "$CDIR" -maxdepth 1 -name 'sos-gpgpass-cache-*' -mmin "+$TTL" -delete 2>/dev/null || true

cache_fresh() {
  [[ -r "$CACHE" && -s "$CACHE" && -n "$(find "$CACHE" -mmin "-$TTL" 2>/dev/null)" ]]
}

# 3) A1: Cache frisch -> sofort liefern, kein Lock nötig (heutiges Verhalten).
if cache_fresh; then
  printf '%s' "$CACHE"; exit 0
fi

# 4) Single-Flight-Lock (AC1): exklusives, per-App gescoptes mkdir-Lock.
LOCK_HELD=0
release_lock() {
  if [[ "$LOCK_HELD" -eq 1 ]]; then
    rm -rf "$LOCK" 2>/dev/null || true
  fi
  return 0
}
trap release_lock EXIT

acquire_lock() {
  # Erwirbt das Lock atomar (mkdir ist auf POSIX-Dateisystemen atomar);
  # bricht ein verwaistes (stale) Lock, falls es älter als STALE_SEC ist (AC3).
  if mkdir "$LOCK" 2>/dev/null; then
    printf '%s' "$$" > "$LOCK/pid" 2>/dev/null || true
    date +%s > "$LOCK/acquired_at" 2>/dev/null || true
    LOCK_HELD=1
    return 0
  fi
  # Lock existiert bereits — stale?
  local age lock_ts now
  now="$(date +%s)"
  lock_ts="$(cat "$LOCK/acquired_at" 2>/dev/null || true)"
  if [[ -n "$lock_ts" && "$lock_ts" =~ ^[0-9]+$ ]]; then
    age=$((now - lock_ts))
  else
    # Kein lesbarer Zeitstempel: entweder ist der Halter gerade erst dabei,
    # ihn zu schreiben (winziges Race unmittelbar nach `mkdir`, kein
    # portables `find -printf`/`stat` nötig — nächster Poll sieht ihn), oder
    # ein sehr altes Lock-Format ohne Zeitstempeldatei. Konservativ: nicht
    # stale behandeln (age=0), sonst könnte ein frisches Lock fälschlich
    # gebrochen werden.
    age=0
  fi
  if [[ "$age" -ge "$STALE_SEC" ]]; then
    # Verwaistes Lock (E1) -> brechen + übernehmen.
    rm -rf "$LOCK" 2>/dev/null || true
    if mkdir "$LOCK" 2>/dev/null; then
      printf '%s' "$$" > "$LOCK/pid" 2>/dev/null || true
      date +%s > "$LOCK/acquired_at" 2>/dev/null || true
      LOCK_HELD=1
      return 0
    fi
  fi
  return 1
}

do_fetch_and_cache() {
  # 5) Container-Boundary prüfen (nur nötig, wenn kein frischer Cache).
  #    AC6: über GPG_BW_FETCH_CMD ersetzbar (nur für Tests) — Default = der
  #    bisherige docker-exec-Pfad. Der Hook muss die Passphrase auf stdout
  #    ausgeben und mit 0 exiten; Fehlschlag -> Exit !=0, keine Ausgabe.
  local pass
  if [[ -n "${GPG_BW_FETCH_CMD:-}" ]]; then
    pass="$(eval "$GPG_BW_FETCH_CMD" 2>/dev/null)" || return 1
  else
    local container
    container="${DEVGUI_CONTAINER:-dev-gui-dev-gui-1}"
    command -v docker >/dev/null 2>&1 || return 1
    docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$container" || return 1
    pass="$(docker exec "$container" bash -c '
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
')" || return 1
  fi
  [[ -n "$pass" ]] || return 1

  # Atomar in die 0600-Cache-Datei materialisieren.
  printf '%s' "$pass" > "$CACHE.tmp.$$" && chmod 600 "$CACHE.tmp.$$" && mv -f "$CACHE.tmp.$$" "$CACHE"
}

if acquire_lock; then
  # Lock-Halter: doppelt prüfen (ein anderer Prozess könnte den Cache
  # zwischen Schritt 3 und dem Lock-Erwerb gefüllt haben), dann Roundtrip.
  if cache_fresh; then
    printf '%s' "$CACHE"; exit 0
  fi
  if do_fetch_and_cache; then
    printf '%s' "$CACHE"; exit 0
  fi
  # E3: Fetch fehlgeschlagen -> Lock wird über den trap freigegeben, kein
  # Cache geschrieben, kein Retry-Sturm (nur dieser eine Versuch).
  exit 1
fi

# 6) Wartender (AC2/AC3): auf frische Cache-Datei ODER Lock-Freigabe pollen;
#    erkennt dabei auch ein zwischenzeitlich verwaistes (stale) Lock, statt
#    unbeteiligt bis zum eigenen Timeout zu warten (E1).
DEADLINE_AT=$(($(date +%s) + WAIT_SEC))
while :; do
  if cache_fresh; then
    printf '%s' "$CACHE"; exit 0
  fi
  # Nachrücken versuchen, wenn das Lock freigegeben wurde (E3) ODER
  # inzwischen stale ist (E1) — acquire_lock() prüft beides selbst; ist das
  # Lock weder weg noch stale, gibt acquire_lock() sofort false zurück (kein
  # unnötiger mkdir-Versuch gegen ein gültig gehaltenes Lock).
  if acquire_lock; then
    if cache_fresh; then
      printf '%s' "$CACHE"; exit 0
    fi
    if do_fetch_and_cache; then
      printf '%s' "$CACHE"; exit 0
    fi
    exit 1
  fi
  # Entweder hält jemand anderes das (gültige) Lock weiter, oder ein anderer
  # Wartender war beim Nachrücken schneller -> weiter pollen (bis Timeout).
  if [[ "$(date +%s)" -ge "$DEADLINE_AT" ]]; then
    # E2: Warte-Timeout überschritten -> Exit !=0, keine Ausgabe.
    exit 1
  fi
  sleep "$POLL_SEC"
done
