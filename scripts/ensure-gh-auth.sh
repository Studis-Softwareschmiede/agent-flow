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

printf '%s' "$GH_TOKEN" | gh auth login --with-token
gh auth setup-git
echo "✓ gh über GitHub-App authentifiziert (~1h gültig)"
