#!/usr/bin/env bash
set -euo pipefail
# Prüft, ob die Bitwarden-Items für bootstrap.sh korrekt angelegt sind.
# Robust: nutzt `bw list --search` + jq (nicht `bw get item`, das hier hängt).
# Gibt KEINE Secrets aus — nur OK/FEHLER + nicht-sensible IDs.
command -v bw >/dev/null || { echo "✖ bw-CLI fehlt"; exit 1; }
command -v jq >/dev/null || { echo "✖ jq fehlt"; exit 1; }

echo "▸ Bitwarden entsperren (Master-Passwort)"
if bw login --check >/dev/null 2>&1; then BW_SESSION="$(bw unlock --raw)"
else BW_SESSION="$(bw login alex@alexstuder.ch --raw)"; fi
export BW_SESSION; bw sync >/dev/null

ok=1
# 1) GPG-Passphrase
if bw get password studis-softwareschmiede-gpg-passphrase --session "$BW_SESSION" >/dev/null 2>&1; then
  echo "✓ gpg-passphrase: vorhanden"
else echo "✖ gpg-passphrase: FEHLT"; ok=0; fi

# 2) GitHub-App via list+jq (Variable statt offener Pipe → kein Hänger)
APP_ITEM="$(bw list items --search studis-softwareschmiede-github-app --session "$BW_SESSION" \
  | jq -c '[.[] | select(.name=="studis-softwareschmiede-github-app")][0] // empty')"
APP_ID="$(jq -r '.fields[]? | select(.name=="app_id").value // empty' <<<"$APP_ITEM")"
APP_INST="$(jq -r '.fields[]? | select(.name=="installation_id").value // empty' <<<"$APP_ITEM")"
APP_KEY_B64="$(jq -r '.fields[]? | select(.name=="private_key_b64").value // empty' <<<"$APP_ITEM")"
PEM="$(mktemp)"; trap 'rm -f "$PEM"' EXIT; chmod 600 "$PEM"
printf '%s' "$APP_KEY_B64" | base64 -d > "$PEM" 2>/dev/null || true
echo "  github-app: app_id=${APP_ID:-LEER}  installation_id=${APP_INST:-LEER}  key_b64_len=${#APP_KEY_B64}  pem_zeilen=$(wc -l < "$PEM" | tr -d ' ')"
if [ -n "$APP_ID" ] && [ -n "$APP_INST" ] && grep -q 'PRIVATE KEY' "$PEM"; then
  b64url(){ openssl base64 -A | tr '+/' '-_' | tr -d '='; }
  now=$(date +%s)
  jh="$(printf '{"alg":"RS256","typ":"JWT"}' | b64url)"
  jp="$(printf '{"iat":%d,"exp":%d,"iss":"%s"}' "$((now-60))" "$((now+540))" "$APP_ID" | b64url)"
  js="$(printf '%s' "$jh.$jp" | openssl dgst -sha256 -sign "$PEM" | b64url)"
  tok="$(curl -s -X POST -H "Authorization: Bearer $jh.$jp.$js" -H "Accept: application/vnd.github+json" \
        "https://api.github.com/app/installations/$APP_INST/access_tokens" | jq -r '.token // empty')"
  [ -n "$tok" ] && echo "✓ github-app: Felder + Token-Mint OK" || { echo "✖ github-app: Mint fehlgeschlagen (IDs/Key prüfen)"; ok=0; }
else echo "✖ github-app: Felder oder PEM unvollständig"; ok=0; fi

# 3) Claude-Token (optional)
if bw get password studis-softwareschmiede-claude-token --session "$BW_SESSION" >/dev/null 2>&1; then
  echo "✓ claude-token: vorhanden (optional)"
else echo "ℹ claude-token: nicht vorhanden (optional — nativer Login als Fallback)"; fi

echo "---"
[ "$ok" = 1 ] && echo "✅ Bootstrap-Secrets vollständig & funktionsfähig" || echo "✖ Es fehlt etwas (siehe oben)"
