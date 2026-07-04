#!/usr/bin/env bash
set -euo pipefail
# Mintet einen kurzlebigen (~1h) GitHub-App-Installation-Token → stdout.
# Erwartet im Environment: GH_APP_ID, GH_APP_INSTALLATION_ID, GH_APP_PRIVATE_KEY_B64.
: "${GH_APP_ID:?GH_APP_ID fehlt}"
: "${GH_APP_INSTALLATION_ID:?GH_APP_INSTALLATION_ID fehlt}"
: "${GH_APP_PRIVATE_KEY_B64:?GH_APP_PRIVATE_KEY_B64 fehlt}"

pem="$(mktemp)"; trap 'rm -f "$pem"' EXIT
chmod 600 "$pem"
printf '%s' "$GH_APP_PRIVATE_KEY_B64" | base64 -d > "$pem"

b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }
now=$(date +%s)
header='{"alg":"RS256","typ":"JWT"}'
payload="$(printf '{"iat":%d,"exp":%d,"iss":"%s"}' "$((now-60))" "$((now+540))" "$GH_APP_ID")"
unsigned="$(printf '%s' "$header" | b64url).$(printf '%s' "$payload" | b64url)"
sig="$(printf '%s' "$unsigned" | openssl dgst -sha256 -sign "$pem" | b64url)"
jwt="$unsigned.$sig"

token="$(curl -s -X POST \
  -H "Authorization: Bearer $jwt" \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "https://api.github.com/app/installations/${GH_APP_INSTALLATION_ID}/access_tokens" \
  | python3 -c 'import sys,json; print(json.load(sys.stdin).get("token",""))')"

[ -n "$token" ] || { echo "✖ Installation-Token-Mint fehlgeschlagen (JWT/IDs/Permissions prüfen)" >&2; exit 1; }
printf '%s' "$token"
