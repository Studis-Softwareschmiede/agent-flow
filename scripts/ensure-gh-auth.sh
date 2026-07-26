#!/usr/bin/env bash
set -euo pipefail
# Persistente gh-Auth über die GitHub App: mintet den App-Token aus .env.gpg
# und loggt gh damit ein (gespeichert in ~/.config/gh, ~1h gültig). Danach
# funktionieren git push/fetch über einen dedizierten Credential-Helper, der
# das Token bei JEDEM git-Netzwerkaufruf frisch aus `gh auth git-credential`
# streamt — es wird NIE in eine Datei/Config geschrieben (git-auth-hardening
# AC1/AC6). Lehre aus dem Vorfall vom 23.–26.07.: ein früherer Workaround
# persistierte den ~1h gültigen App-Token als `http.*.extraheader` in
# .git/config — nach Ablauf blockierte das 3 Tage lang JEDE
# git-Netzwerkoperation aller Sessions mit „Invalid username or token".
# Idempotent: bei schon gültiger gh-Auth passiert nichts Schädliches, das
# Credential-Setup wird bei jedem Lauf verifiziert/ergänzt (kein Doppel-Eintrag).
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"

# shellcheck source=scripts/load-env.sh
source "$ROOT/scripts/load-env.sh" >/dev/null 2>&1 || true
[ -n "${GH_TOKEN:-}" ] || { echo "✖ GH_TOKEN nicht gemintet — .env.gpg / gpg.pass prüfen" >&2; exit 1; }

# gh speichert NUR, wenn keine GH_TOKEN/GITHUB_TOKEN-Env-Var aktiv ist — sonst nutzt es bloss
# die (nicht persistente) Env-Var. Also Token sichern, Env leeren, dann persistent einloggen.
_t="$GH_TOKEN"
unset GH_TOKEN GITHUB_TOKEN
printf '%s' "$_t" | gh auth login --with-token
unset _t

# --- Selbstheilung: veraltete extraheader-Reste des alten Token-Workarounds
# entfernen (git-auth-hardening AC3/A2) — repo-lokal, im aufrufenden
# Working-Tree/Worktree, BEVOR der neue Credential-Weg eingerichtet wird.
# Idempotent: kein Fehler, wenn nichts zu bereinigen ist.
_caller_repo="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -n "$_caller_repo" ]]; then
  while IFS= read -r _stale_key; do
    [[ -n "$_stale_key" ]] || continue
    git -C "$_caller_repo" config --local --unset-all "$_stale_key" 2>/dev/null || true
    echo "✓ veralteten Token-Workaround entfernt: $_stale_key" >&2
  done < <(git -C "$_caller_repo" config --local --name-only --get-regexp '^http\..*\.extraheader$' 2>/dev/null || true)
fi
unset _caller_repo

# --- Credential-Helper mit erzwungenem Username einrichten (AC2/AC7) ---
# Global-Scope (gilt für alle Worktrees, siehe Edge-Case „Mehrere Worktrees").
# Der Wrapper ruft `gh auth git-credential get` und normalisiert die
# `username=`-Zeile auf `x-access-token` — die GitHub-App-Installation
# liefert dafür manchmal stattdessen den Bot-Login, was git mit „Invalid
# username or token" scheitern lässt. Alles über stdin/stdout gestreamt: das
# Token wird NIE auf Platte geschrieben. Ein vorhandener fremder Helper (z.B.
# osxkeychain) wird NICHT überschrieben; nur ein roher, unseren Wrapper
# verschattender `gh auth git-credential`-Eintrag wird ersetzt (Details
# unten, AC4: kein Doppel-Eintrag, bereits gesundes Setup bleibt unverändert).
_helper_dir="${HOME}/.config/agent-flow"
_helper_path="${_helper_dir}/git-credential-x-access-token.sh"
mkdir -p "$_helper_dir"
cat > "$_helper_path" <<'HELPEREOF'
#!/usr/bin/env bash
# Auto-generiert von scripts/ensure-gh-auth.sh — NICHT manuell editieren.
# Git-Credential-Helper-Wrapper (git-auth-hardening AC2/AC7): ruft
# `gh auth git-credential <action>` und erzwingt bei `get` username=x-access-token,
# um den Bot-Login-Bug der GitHub-App-Installation zu umschiffen. Das Token
# wird NUR über stdin/stdout gestreamt, nie auf Platte geschrieben.
set -euo pipefail
action="${1:-get}"
if [[ "$action" == "get" ]]; then
  gh auth git-credential get | sed 's/^username=.*/username=x-access-token/'
else
  gh auth git-credential "$action"
fi
HELPEREOF
chmod +x "$_helper_path"

_helper_cmd="!'${_helper_path}'"

# Bestehende Helper-Kette für github.com bereinigen: git befragt Helper in
# Config-Reihenfolge (system -> global -> local, innerhalb einer Datei in
# Zeilenreihenfolge) und STOPPT, sobald einer username+password liefert
# (gitcredentials(7)). Zwei getrennte Gefahren, beide empirisch reproduziert:
#   (1) Review-Fund Iteration 2: ein roher, von `gh auth setup-git` gesetzter
#       `!<pfad>/gh auth git-credential`-Eintrag VOR unserem Wrapper liefert
#       den Bot-Login-Bug und der Wrapper wird nie erreicht.
#   (2) Review-Fund Iteration 3: `gh auth setup-git` setzt VOR dem rohen
#       gh-Eintrag bewusst eine LEERE Reset-Zeile (`helper =` ohne Wert) —
#       ein leerer Wert löscht die bis dahin (aus system-Config, z.B. macOS
#       `osxkeychain` via /etc/gitconfig) akkumulierte Helper-Liste. Verwirft
#       unser Rebuild diese Reset-Zeile ersatzlos, wird der systemweite
#       Helper wieder wirksam, läuft VOR unserem Wrapper und gewinnt mit
#       einem gecachten (ggf. fremden/veralteten) Credential — der Wrapper
#       wird nie erreicht, AC2 silent verfehlt.
# Fix: die Ziel-Kette ist IMMER ["", <erhaltene fremde Einträge>, Wrapper] —
# die leere Reset-Zeile wird unabhängig davon gesetzt, ob ein roher
# gh-Eintrag gefunden wurde. Rohe gh-Einträge werden entfernt, andere fremde
# Helper (z.B. osxkeychain als expliziter GLOBAL-Eintrag) bleiben erhalten.
# Idempotent: nur neu aufgebaut, wenn die aktuelle Kette nicht schon exakt
# der Ziel-Kette entspricht (Byte-für-Byte-Vergleich, inkl. Reset-Zeile).
_helper_key='credential.https://github.com.helper'
_raw_gh_re='^!([^ ]*/)?gh auth git-credential$'
_current=()
while IFS= read -r -d '' _entry; do
  _current+=("$_entry")
done < <(git config --global -z --get-all "$_helper_key" 2>/dev/null || true)

_keep=()
for _entry in "${_current[@]}"; do
  [[ -z "$_entry" ]] && continue                     # bestehende Reset-Marker: unten explizit neu gesetzt
  [[ "$_entry" =~ $_raw_gh_re ]] && continue          # roher gh-Eintrag verschattet den Wrapper -> entfernen
  [[ "$_entry" == "$_helper_cmd" ]] && continue       # eigenen Eintrag unten frisch ans Ende setzen
  _keep+=("$_entry")
done
_desired=("" "${_keep[@]}" "$_helper_cmd")

_needs_rebuild=0
if [[ "${#_current[@]}" -ne "${#_desired[@]}" ]]; then
  _needs_rebuild=1
else
  for _idx in "${!_desired[@]}"; do
    [[ "${_current[$_idx]}" == "${_desired[$_idx]}" ]] || { _needs_rebuild=1; break; }
  done
fi

if [[ "$_needs_rebuild" -eq 1 ]]; then
  git config --global --unset-all "$_helper_key" 2>/dev/null || true
  for _entry in "${_desired[@]}"; do
    git config --global --add "$_helper_key" "$_entry"
  done
fi
unset _helper_dir _helper_path _helper_cmd _helper_key _raw_gh_re _current _keep _desired _needs_rebuild _idx _entry

echo "✓ gh über GitHub-App authentifiziert (persistent in ~/.config/gh, ~1h gültig) — Push/Fetch über tokenlosen Credential-Helper (x-access-token)"
