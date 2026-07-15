#!/usr/bin/env bash
# Gemeinsame Helfer — NICHT direkt ausführen, nur via source.
# GPG-Passphrase-Auflösung (eigene Secret-Domäne der Softwareschmiede):
#   $GPG_PASS_FILE                         (explizit vorgegeben, z.B. dev-gui Headless-Injektion)
#   > Bitwarden per-App (via dev-gui-Container, Item env.gpg-passphrase-<app>)
#   > /etc/softwareschmiede/gpg.pass       (Legacy-Fallback, geteilt)
#   > ~/.config/softwareschmiede/gpg.pass  (Legacy-Fallback, geteilt)
#   > $GPG_PASSPHRASE > interaktiver Prompt (in load-env.sh)
# Bitwarden-Bezug abschaltbar mit GPG_BW_DISABLE=1 (dann nur Legacy-Dateien).
resolve_pass_file() {
  local f
  # 1) Explizit vorgegeben — höchste Priorität (Override / Headless-Injektion).
  if [[ -n "${GPG_PASS_FILE:-}" && -r "${GPG_PASS_FILE:-}" ]]; then
    printf '%s' "$GPG_PASS_FILE"; return 0
  fi
  # 2) Bitwarden als Quelle (per-App, über die dev-gui-Container-Boundary).
  #    Erfolg -> materialisierte 0600-Tempdatei; Fehlschlag -> stiller Fallback.
  if [[ -z "${GPG_BW_DISABLE:-}" ]]; then
    local _bwf _pdir
    _pdir="$(dirname "${BASH_SOURCE[0]:-$0}")"
    _bwf="$("$_pdir/provision-gpg-pass.sh" 2>/dev/null || true)"
    if [[ -n "$_bwf" && -r "$_bwf" ]]; then
      printf '%s' "$_bwf"; return 0
    fi
  fi
  # 3) Legacy-Fallback: statische, geteilte Passphrase-Dateien.
  for f in "/etc/softwareschmiede/gpg.pass" "$HOME/.config/softwareschmiede/gpg.pass"; do
    [[ -n "$f" && -r "$f" ]] && { printf '%s' "$f"; return 0; }
  done
  return 1
}
