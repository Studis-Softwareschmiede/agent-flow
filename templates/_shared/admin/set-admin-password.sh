#!/usr/bin/env bash
# scripts/set-admin-password.sh — Admin-Passwort setzen/ändern (Fabrik-Standard „Admin-Bereich").
# Vertrag: docs/architecture/admin-bereich-subsystem.md BR-002, BR-003.
#
# Erfragt ein Passwort, erzeugt einen argon2id-Hash, schreibt ihn als
# ADMIN_PASSWORD_HASH in .env und ruft anschließend scripts/encrypt-env.sh auf.
# Das Passwort wird NIE geloggt/ge-echoed; das Script committet nichts.
set -euo pipefail
cd "$(dirname "$0")/.."

command -v argon2 >/dev/null 2>&1 || {
  echo "✖ 'argon2'-Werkzeug fehlt auf diesem Host (z.B. 'apt install argon2' / 'brew install argon2') — Abbruch, kein Klartext-Fallback" >&2
  exit 1
}

read -rs -p "Neues Admin-Passwort: " admin_password
echo
read -rs -p "Passwort wiederholen: " admin_password_confirm
echo

if [[ -z "$admin_password" ]]; then
  echo "✖ Passwort darf nicht leer sein" >&2
  exit 1
fi
if [[ "$admin_password" != "$admin_password_confirm" ]]; then
  echo "✖ Passwörter stimmen nicht überein" >&2
  exit 1
fi

# 16 Rohbytes Salt, hex-kodiert (od -tx1) -> 32-Zeichen-Hex-String.
salt="$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n')"
# Cost-Parameter explizit (argon2-CLI: -m ist log2(KiB) -> 2^16 KiB = 64 MiB),
# oberhalb des OWASP-Minimums (>=19 MiB) und unabhängig von CLI-Version-Defaults.
hash="$(printf '%s' "$admin_password" | argon2 "$salt" -id -e -m 16 -t 3 -p 4)"
unset admin_password admin_password_confirm

[[ -f .env ]] || touch .env

if grep -q '^ADMIN_PASSWORD_HASH=' .env; then
  tmp_env="$(mktemp)"
  # grep -v liefert exit 1, wenn ALLE Zeilen auf das Muster passen (leere .env
  # bliebe übrig) -- unter `set -e` würde das Script sonst hier abbrechen.
  grep -v '^ADMIN_PASSWORD_HASH=' .env > "$tmp_env" || true
  mv "$tmp_env" .env
fi
# Der Hash enthält strukturell '$'-Zeichen (argon2id$v=19$...); einfach quoten,
# damit ein `eval`-basierter Konsum (z.B. scripts/load-env.sh) den Wert nicht
# als Variablen-Referenzen fehlinterpretiert (siehe .claude/lessons/coder.md).
printf "ADMIN_PASSWORD_HASH='%s'\n" "$hash" >> .env
unset hash salt

bash scripts/encrypt-env.sh

echo "✓ Admin-Passwort gesetzt — .env.gpg aktualisiert, nichts committet"
