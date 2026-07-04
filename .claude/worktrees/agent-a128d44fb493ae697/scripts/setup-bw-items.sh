#!/usr/bin/env bash
set -euo pipefail
# Befüllt das Bitwarden-Item studis-softwareschmiede-github-app KORREKT aus .env.gpg
# (Felder app_id, installation_id, private_key_b64) — keine manuelle Paste.
cd "$(dirname "$0")/.."
command -v bw >/dev/null || { echo "✖ bw fehlt"; exit 1; }
command -v jq >/dev/null || { echo "✖ jq fehlt"; exit 1; }

# App-Creds aus .env.gpg laden
source scripts/load-env.sh >/dev/null 2>&1 || true
: "${GH_APP_ID:?fehlt in .env.gpg}"
: "${GH_APP_INSTALLATION_ID:?fehlt in .env.gpg}"
: "${GH_APP_PRIVATE_KEY_B64:?fehlt in .env.gpg}"

NAME="studis-softwareschmiede-github-app"
echo "▸ Bitwarden entsperren (Master-Passwort)"
if bw login --check >/dev/null 2>&1; then BW_SESSION="$(bw unlock --raw)"; else BW_SESSION="$(bw login alex@alexstuder.ch --raw)"; fi
export BW_SESSION; bw sync >/dev/null

ITEM="$(bw list items --search "$NAME" --session "$BW_SESSION" | jq -c --arg n "$NAME" '[.[]|select(.name==$n)][0] // empty')"
[ -n "$ITEM" ] || { echo "✖ Item '$NAME' nicht gefunden — in Bitwarden anlegen (leer reicht), dann erneut."; exit 1; }
ID="$(jq -r '.id' <<<"$ITEM")"

NEW="$(jq --arg a "$GH_APP_ID" --arg i "$GH_APP_INSTALLATION_ID" --arg k "$GH_APP_PRIVATE_KEY_B64" \
  '.fields=[{name:"app_id",value:$a,type:0},{name:"installation_id",value:$i,type:0},{name:"private_key_b64",value:$k,type:1}]' <<<"$ITEM")"
ENC="$(printf '%s' "$NEW" | bw encode)"   # encode liest stdin (kein Vault-Zugriff)
bw edit item "$ID" "$ENC" --session "$BW_SESSION" >/dev/null   # JSON als ARGUMENT → stdin frei, kein readline-Crash
bw sync >/dev/null
echo "✓ '$NAME' befüllt: app_id, installation_id, private_key_b64 (${#GH_APP_PRIVATE_KEY_B64} Zeichen)"
echo "→ jetzt prüfen:  bash scripts/verify-secrets.sh"
