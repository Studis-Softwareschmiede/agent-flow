#!/usr/bin/env bash
# SOURCE diese Datei:  source scripts/load-env.sh
# Entschlüsselt .env.gpg und exportiert die Variablen (GH_TOKEN …) ins aktuelle Environment.
# Kein Klartext auf der Platte — Entschlüsselung geht direkt nach stdout → eval.
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
  echo "✓ env geladen (GH_TOKEN gesetzt)"
else
  echo "ℹ .env.gpg fehlt — noch nichts zu laden"
fi
unset _sos_root _sos_pf
