#!/usr/bin/env bash
set -euo pipefail
# =============================================================================
# agent-flow Bootstrap — frische Maschine (macOS/Linux) einsatzbereit machen.
# EINSTIEG = Bitwarden: ein Master-Passwort, alles andere fließt daraus.
# Nach dem Lauf: nur noch `claude` (in neuem Terminal) tippen.
#
# Voraussetzung (einmal anlegen): Bitwarden-Items
#   - studis-softwareschmiede-gpg-passphrase   (Login: password = GPG-Passphrase)
#   - studis-softwareschmiede-github-app       (Notes = .pem; Felder app_id, installation_id)
#   - studis-softwareschmiede-claude-token     (OPTIONAL, Login: password = `claude setup-token`)
#
# STATUS: erste Version — auf frischer Box noch nicht end-to-end getestet.
#         macOS am ehesten erprobt; Linux-Install-Pfade sind best-effort.
# =============================================================================

ORG="Studis-Softwareschmiede"
BW_EMAIL="alex@alexstuder.ch"
WORKDIR="${WORKDIR:-$HOME/Git/$ORG}"
CFG="$HOME/.config/softwareschmiede"

log(){ printf '\033[1;34m▸ %s\033[0m\n' "$*"; }
die(){ printf '\033[1;31m✖ %s\033[0m\n' "$*" >&2; exit 1; }
have(){ command -v "$1" >/dev/null 2>&1; }

case "$(uname -s)" in
  Darwin) PLATFORM=mac ;;
  Linux)  PLATFORM=linux ;;
  *) die "OS $(uname -s) nicht unterstützt" ;;
esac
log "Plattform: $PLATFORM"
ensure_brew(){ have brew || die "Homebrew fehlt — https://brew.sh, dann erneut"; }

# --- 1. Bitwarden CLI ---------------------------------------------------------
if ! have bw; then
  log "Installiere Bitwarden CLI"
  if [ "$PLATFORM" = mac ]; then ensure_brew; brew install bitwarden-cli
  elif have snap; then sudo snap install bw
  elif have npm;  then sudo npm install -g @bitwarden/cli
  else die "bw-Install: weder snap noch npm da — bw manuell installieren"; fi
fi

# --- 2. Bitwarden Login (DER eine interaktive Schritt) ------------------------
log "Bitwarden Login ($BW_EMAIL) — Master-Passwort eingeben"
if bw login --check >/dev/null 2>&1; then BW_SESSION="$(bw unlock --raw)"
else BW_SESSION="$(bw login "$BW_EMAIL" --raw)"; fi
export BW_SESSION
bw sync >/dev/null
bwget(){ bw get "$@" --session "$BW_SESSION"; }
have jq || { log "Installiere jq"; if [ "$PLATFORM" = mac ]; then ensure_brew; brew install jq;
  elif have apt-get; then sudo apt-get update -qq && sudo apt-get install -y jq;
  elif have dnf; then sudo dnf install -y jq; else die "jq fehlt — manuell installieren"; fi; }

# --- 3. Secrets aus Bitwarden -------------------------------------------------
log "Hole Secrets aus Bitwarden"
mkdir -p "$CFG" && chmod 700 "$CFG"
bwget password studis-softwareschmiede-gpg-passphrase > "$CFG/gpg.pass"; chmod 600 "$CFG/gpg.pass"
# GitHub-App via list+jq (robuster als `bw get item`, das hängen kann)
APP_ITEM="$(bw list items --search studis-softwareschmiede-github-app --session "$BW_SESSION" \
  | jq -c '[.[] | select(.name=="studis-softwareschmiede-github-app")][0] // empty')"
APP_ID="$(jq -r '.fields[]? | select(.name=="app_id").value // empty' <<<"$APP_ITEM")"
APP_INST="$(jq -r '.fields[]? | select(.name=="installation_id").value // empty' <<<"$APP_ITEM")"
[ -n "$APP_ID" ] && [ -n "$APP_INST" ] || die "github-app-Item unvollständig (app_id/installation_id)"
PEM="$(mktemp)"; trap 'rm -f "$PEM"' EXIT; chmod 600 "$PEM"
jq -r '.notes // ""' <<<"$APP_ITEM" > "$PEM"
grep -q 'PRIVATE KEY' "$PEM" || die "github-app-Item: kein gültiger Key in Notes"
CLAUDE_TOKEN="$(bwget password studis-softwareschmiede-claude-token 2>/dev/null || true)"

# --- 4. GitHub-Installation-Token minten (inline JWT) -------------------------
log "Minte GitHub-Token aus App-Key"
b64url(){ openssl base64 -A | tr '+/' '-_' | tr -d '='; }
now=$(date +%s)
jh="$(printf '{"alg":"RS256","typ":"JWT"}' | b64url)"
jp="$(printf '{"iat":%d,"exp":%d,"iss":"%s"}' "$((now-60))" "$((now+540))" "$APP_ID" | b64url)"
js="$(printf '%s' "$jh.$jp" | openssl dgst -sha256 -sign "$PEM" | b64url)"
GH_TOKEN="$(curl -s -X POST -H "Authorization: Bearer $jh.$jp.$js" -H "Accept: application/vnd.github+json" \
  "https://api.github.com/app/installations/$APP_INST/access_tokens" | jq -r '.token // empty')"
[ -n "$GH_TOKEN" ] || die "GitHub-Token-Mint fehlgeschlagen (App-Key/IDs prüfen)"
export GH_TOKEN

# --- 5. git/gh ----------------------------------------------------------------
have git || { [ "$PLATFORM" = mac ] && { ensure_brew; brew install git; } || sudo apt-get install -y git; }
if ! have gh; then
  log "Installiere GitHub CLI"
  if [ "$PLATFORM" = mac ]; then ensure_brew; brew install gh
  elif have apt-get; then
    sudo mkdir -p -m 755 /etc/apt/keyrings
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg >/dev/null
    sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
    sudo apt-get update -qq && sudo apt-get install -y gh
  else die "gh-Install: kein brew/apt — gh manuell installieren"; fi
fi
gh auth setup-git   # nutzt GH_TOKEN als Credential-Helper

# --- 6. Repo klonen -----------------------------------------------------------
log "Klone agent-flow nach $WORKDIR"
mkdir -p "$WORKDIR"
[ -d "$WORKDIR/agent-flow/.git" ] || gh repo clone "$ORG/agent-flow" "$WORKDIR/agent-flow"

# --- 7. Claude Code -----------------------------------------------------------
have claude || { log "Installiere Claude Code"; curl -fsSL https://claude.ai/install.sh | bash; }
export PATH="$HOME/.local/bin:$PATH"   # üblicher Install-Pfad

# --- 8. Docker (für den tester) ----------------------------------------------
if ! have docker; then
  log "Installiere Docker"
  if [ "$PLATFORM" = mac ]; then
    ensure_brew; brew install colima docker && colima start || true   # colima = headless-freundlich
  else
    curl -fsSL https://get.docker.com | sudo sh
    sudo usermod -aG docker "$USER" || true   # ab nächstem Login wirksam
  fi
fi

# --- 9. Claude-Auth -----------------------------------------------------------
if [ -n "$CLAUDE_TOKEN" ]; then
  log "Claude-OAuth-Token aus Bitwarden hinterlegen"
  printf '%s' "$CLAUDE_TOKEN" > "$CFG/claude.token"; chmod 600 "$CFG/claude.token"
  line='export CLAUDE_CODE_OAUTH_TOKEN="$(cat ~/.config/softwareschmiede/claude.token 2>/dev/null)"'
  for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
    [ -f "$rc" ] && { grep -qF 'softwareschmiede/claude.token' "$rc" || printf '\n%s\n' "$line" >> "$rc"; }
  done
  export CLAUDE_CODE_OAUTH_TOKEN="$CLAUDE_TOKEN"
fi

# --- 10. Plugin installieren --------------------------------------------------
log "Installiere agent-flow Plugin"
claude plugin marketplace add "$ORG/agent-flow" || true
claude plugin install "agent-flow@agent-flow" --scope user || true

log "FERTIG."
[ -n "${CLAUDE_TOKEN:-}" ] && echo "→ Neues Terminal öffnen, 'claude' starten. /agent-flow:* steht bereit." \
                           || echo "→ Neues Terminal öffnen, 'claude' starten (1× Login), dann /agent-flow:*."
