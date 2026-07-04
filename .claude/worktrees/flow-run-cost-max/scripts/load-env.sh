#!/usr/bin/env bash
# SOURCE diese Datei:  source scripts/load-env.sh
# Entschlüsselt .env.gpg, exportiert die App-Creds und mintet daraus einen kurzlebigen GH_TOKEN.
# Kein Klartext auf der Platte; der Private Key wird nur als base64 im verschlüsselten .env.gpg gehalten.
_sos_root="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
# shellcheck source=scripts/_lib.sh
source "$_sos_root/scripts/_lib.sh"

if [[ -f "$_sos_root/.env.gpg" ]]; then
  _sos_pf="$(resolve_pass_file || true)"
  set -a
  if [[ -n "${_sos_pf:-}" ]]; then
    eval "$(gpg --batch --quiet --pinentry-mode loopback --passphrase-file "$_sos_pf" -d "$_sos_root/.env.gpg")"
  elif [[ -n "${GPG_PASSPHRASE:-}" ]]; then
    eval "$(printf '%s' "$GPG_PASSPHRASE" | gpg --batch --quiet --pinentry-mode loopback --passphrase-fd 0 -d "$_sos_root/.env.gpg")"
  else
    eval "$(gpg --quiet --pinentry-mode loopback -d "$_sos_root/.env.gpg")"
  fi
  set +a

  if [[ -n "${GH_APP_ID:-}" && -n "${GH_APP_PRIVATE_KEY_B64:-}" ]]; then
    if GH_TOKEN="$("$_sos_root/scripts/gh-app-token.sh")"; then
      export GH_TOKEN
      echo "✓ GH_TOKEN gemintet (GitHub-App-Installation-Token, ~1h)"
    else
      echo "✖ Token-Mint fehlgeschlagen"
    fi
  elif [[ -n "${GH_TOKEN:-}" ]]; then
    echo "✓ env geladen (statischer GH_TOKEN)"
  fi
else
  echo "ℹ .env.gpg fehlt — noch nichts zu laden"
fi
unset _sos_root _sos_pf
