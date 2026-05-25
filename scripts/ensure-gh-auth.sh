#!/usr/bin/env bash
set -euo pipefail
# Persistente gh-Auth über die GitHub App: mintet den App-Token aus .env.gpg
# und loggt gh damit ein (gespeichert in ~/.config/gh, ~1h gültig). Danach nutzen
# gh UND git (via setup-git) diese Auth — ohne dass GH_TOKEN pro Befehl gesetzt sein muss.
# Idempotent: bei schon gültiger gh-Auth passiert nichts.
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
gh auth setup-git
echo "✓ gh über GitHub-App authentifiziert (persistent in ~/.config/gh, ~1h gültig)"
