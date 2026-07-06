#!/usr/bin/env bash
# smoke.sh — Mechanik-Smoke-Test des Regressions-Runners (Template-Artefakt).
#
# Covers (regression-runner): AC1, AC2, AC3, AC5, AC6, AC9
#
# Prüft, ohne echtes Playwright zu installieren (Netzwerk-frei, deterministisch),
# die Runner-Mechanik von `templates/_shared/regression/run-regression.sh` über
# einen Stub-`npx`, der Aufrufe + Umgebung protokolliert statt echte Browser zu
# starten:
#   - AC1: der Runner-Quelltext dispatcht keinen Agenten.
#   - AC2/AC3: `target: local` wird aus der Begleitbeschreibung gelesen und auf
#     `http://localhost:<preview_port>` aufgelöst (Default für Bereichs-Suiten).
#   - AC5: `target: url` läuft gegen die deklarierte URL, ohne lokalen
#     Erreichbarkeits-Check (läuft auch wenn `local` gerade nicht erreichbar ist).
#   - AC6: `target: local` mit nicht erreichbarem Port → Vorbedingungs-Fehler,
#     KEIN Playwright/Stub-Aufruf; mit erreichbarem Port → Lauf wird ausgeführt.
#   - AC9: ein vorhandenes `scripts/load-env.sh` exportiert ein Secret in die
#     Runner-Shell, das an den Playwright-Kindprozess vererbt wird — der Runner
#     liest es nie aus einer Test-/Datendatei und persistiert es nirgends.
#   - Edge-Cases: fehlendes `target` bzw. fehlendes `url`-Feld bei
#     `target: url` → Fehler statt stillschweigendem Default.
#
# Voraussetzungen: bash (auch macOS-Systembash 3.2 kompatibel), curl, python3
# (nur als Wegwerf-HTTP-Server für den "erreichbar"-Fall — kein echtes
# Playwright/npm nötig).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RUNNER_SRC="$REPO_ROOT/templates/_shared/regression/run-regression.sh"

SMOKE_DIR="$(mktemp -d "/tmp/smoke-regression-runner-XXXXXX")"
HTTP_SERVER_PID=""

cleanup() {
  local rc=$?
  [[ -n "$HTTP_SERVER_PID" ]] && kill "$HTTP_SERVER_PID" >/dev/null 2>&1 || true
  rm -rf "$SMOKE_DIR"
  exit "$rc"
}
trap cleanup EXIT INT TERM

log()  { printf '[smoke-regression-runner] %s\n' "$*"; }
fail() { printf '[smoke-regression-runner] FAIL: %s\n' "$*" >&2; exit 1; }

[[ -f "$RUNNER_SRC" ]] || fail "Runner-Skript nicht gefunden: $RUNNER_SRC"

log "SMOKE_DIR=$SMOKE_DIR"

# ---- Fake-App-Repo aufbauen -------------------------------------------------
mkdir -p "$SMOKE_DIR/scripts" "$SMOKE_DIR/.claude" \
         "$SMOKE_DIR/tests/regression/board" \
         "$SMOKE_DIR/tests/regression/verbund" \
         "$SMOKE_DIR/tests/regression/preview" \
         "$SMOKE_DIR/fakebin"

cp "$RUNNER_SRC" "$SMOKE_DIR/scripts/run-regression.sh"
chmod +x "$SMOKE_DIR/scripts/run-regression.sh"

# Stub-`npx`: protokolliert jeden Aufruf (Argumente + relevante Env) statt
# echtes Playwright zu starten. Exit 0 = "grüner" Lauf.
NPX_LOG="$SMOKE_DIR/npx-calls.log"
: >"$NPX_LOG"
cat >"$SMOKE_DIR/fakebin/npx" <<'STUB'
#!/usr/bin/env bash
echo "ARGS: $*" >>"$NPX_LOG"
echo "REGRESSION_BASE_URL=${REGRESSION_BASE_URL:-<unset>}" >>"$NPX_LOG"
echo "REGRESSION_SMOKE_SECRET=${REGRESSION_SMOKE_SECRET:-<unset>}" >>"$NPX_LOG"
echo "---" >>"$NPX_LOG"
exit 0
STUB
sed -i.bak "s#\$NPX_LOG#$NPX_LOG#" "$SMOKE_DIR/fakebin/npx" && rm -f "$SMOKE_DIR/fakebin/npx.bak"
chmod +x "$SMOKE_DIR/fakebin/npx"

# board-Suite: target: local
cat >"$SMOKE_DIR/tests/regression/board/example.md" <<'MD'
---
title: Board Example
target: local
---
MD
: >"$SMOKE_DIR/tests/regression/board/example.spec.ts"

# verbund-Suite: target: ephemeral-infra
cat >"$SMOKE_DIR/tests/regression/verbund/infra.md" <<'MD'
---
title: Infra Example
target: ephemeral-infra
---
MD
: >"$SMOKE_DIR/tests/regression/verbund/infra.spec.ts"

# preview-Suite: target: url
cat >"$SMOKE_DIR/tests/regression/preview/preview.md" <<'MD'
---
title: Preview Example
target: url
url: http://example.invalid
---
MD
: >"$SMOKE_DIR/tests/regression/preview/preview.spec.ts"

run_runner() {
  ( cd "$SMOKE_DIR" && PATH="$SMOKE_DIR/fakebin:$PATH" bash scripts/run-regression.sh "$@" )
}

# ---- AC1: kein Agent-Dispatch im Quelltext ---------------------------------
log "AC1: kein Agent-Dispatch pro Testlauf"
if grep -qiE 'claude[^[:space:]]*[[:space:]]+(agent|task|dispatch)|Task\(' "$RUNNER_SRC"; then
  fail "Runner-Quelltext scheint einen Agenten zu dispatchen"
fi
log "AC1 ok — keine Agent-Dispatch-Aufrufe im Quelltext"

# ---- AC6 (rot): local, Port nicht erreichbar -> Vorbedingungs-Fehler, kein Lauf
log "AC6: local-Ziel nicht erreichbar -> Vorbedingungs-Fehler statt Playwright-Lauf"
cat >"$SMOKE_DIR/.claude/profile.md" <<'PROFILE'
language: js
preview_port: 39217
PROFILE

set +e
out_unreachable="$(run_runner tests/regression/board 2>&1)"
rc_unreachable=$?
set -e
echo "$out_unreachable" | grep -qi "nicht erreichbar" || fail "erwartete Vorbedingungs-Fehlermeldung fehlt: $out_unreachable"
[[ "$rc_unreachable" -ne 0 ]] || fail "erwartete nicht-null Exit-Code bei nicht erreichbarem local-Ziel"
[[ -s "$NPX_LOG" ]] && fail "Stub-npx wurde trotz Vorbedingungs-Fehler aufgerufen (keine roten Tests erwartet)"
log "AC6 (rot) ok — kein Playwright-Aufruf, Exit-Code $rc_unreachable"

# ---- AC5: url-Bucket läuft unabhängig vom (unerreichbaren) local-Ziel -------
log "AC5: target=url läuft ohne lokale Provisionierung/Erreichbarkeits-Check"
: >"$NPX_LOG"
set +e
out_url="$(run_runner tests/regression/preview 2>&1)"
rc_url=$?
set -e
[[ "$rc_url" -eq 0 ]] || fail "url-Suite schlug fehl (rc=$rc_url): $out_url"
grep -q "REGRESSION_BASE_URL=http://example.invalid" "$NPX_LOG" || fail "REGRESSION_BASE_URL wurde nicht auf die deklarierte url gesetzt"
log "AC5 ok — url-Bucket lief mit REGRESSION_BASE_URL=http://example.invalid"

# ---- AC2/AC3/AC6 (grün) + AC9: local erreichbar, Secrets durchgereicht -----
log "AC2/AC3/AC6 (grün) + AC9: local erreichbar + Secret-Injektion ohne Persistierung"
python3 -u -m http.server 0 --bind 127.0.0.1 >"$SMOKE_DIR/http-server.log" 2>&1 &
HTTP_SERVER_PID=$!
for _ in $(seq 1 20); do
  port="$(grep -oE 'port [0-9]+' "$SMOKE_DIR/http-server.log" 2>/dev/null | grep -oE '[0-9]+' | head -1 || true)"
  [[ -n "$port" ]] && break
  sleep 0.2
done
[[ -n "${port:-}" ]] || fail "Wegwerf-HTTP-Server hat keinen Port ausgegeben"

cat >"$SMOKE_DIR/.claude/profile.md" <<PROFILE
language: js
preview_port: ${port}
PROFILE

cat >"$SMOKE_DIR/scripts/load-env.sh" <<'LOADENV'
#!/usr/bin/env bash
export REGRESSION_SMOKE_SECRET="super-secret-value-not-in-any-file"
LOADENV

: >"$NPX_LOG"
set +e
out_local="$(run_runner tests/regression/board 2>&1)"
rc_local=$?
set -e
[[ "$rc_local" -eq 0 ]] || fail "local-Suite schlug trotz erreichbarem Ziel fehl (rc=$rc_local): $out_local"
grep -q "REGRESSION_BASE_URL=http://localhost:${port}" "$NPX_LOG" || fail "REGRESSION_BASE_URL wurde nicht auf http://localhost:${port} aufgelöst"
grep -q "REGRESSION_SMOKE_SECRET=super-secret-value-not-in-any-file" "$NPX_LOG" || fail "Secret wurde nicht an den Playwright-Kindprozess durchgereicht"
log "AC2/AC3/AC6 (grün) ok — REGRESSION_BASE_URL=http://localhost:${port}"
log "AC9 ok — Secret via load-env.sh injiziert, an Kindprozess vererbt"

# AC9 (Negativ-Beweis): das Secret steht in KEINER Test-/Datendatei und wird
# nicht in eine neue Datei im App-Repo persistiert (nur der Stub-Log — reines
# Test-Harness-Artefakt außerhalb des gescaffoldeten Layouts — kennt es).
if grep -rqF "super-secret-value-not-in-any-file" "$SMOKE_DIR/tests"; then
  fail "Secret ist in einer Test-/Datendatei gelandet — AC9 verletzt"
fi
if find "$SMOKE_DIR" -type f -not -path "$SMOKE_DIR/npx-calls.log" -not -path "$SMOKE_DIR/scripts/load-env.sh" \
     -exec grep -lF "super-secret-value-not-in-any-file" {} \; 2>/dev/null | grep -q .; then
  fail "Secret wurde in eine unerwartete Datei persistiert"
fi
log "AC9 ok — keine Persistierung des Secrets ausserhalb der Shell-Weitergabe"

# ---- Edge-Case: target fehlt im Frontmatter --------------------------------
log "Edge-Case: fehlendes 'target' -> Fehler statt stillem Default"
mkdir -p "$SMOKE_DIR/tests/regression/no-target"
cat >"$SMOKE_DIR/tests/regression/no-target/x.md" <<'MD'
---
title: No Target
---
MD
: >"$SMOKE_DIR/tests/regression/no-target/x.spec.ts"
set +e
out_missing="$(run_runner tests/regression/no-target 2>&1)"
rc_missing=$?
set -e
[[ "$rc_missing" -ne 0 ]] || fail "erwartete Fehler bei fehlendem target, bekam Exit 0"
echo "$out_missing" | grep -qi "ohne 'target'" || fail "erwartete Fehlermeldung zu fehlendem target: $out_missing"
log "Edge-Case (fehlendes target) ok"

# ---- Edge-Case: target=url ohne 'url'-Feld ---------------------------------
log "Edge-Case: target=url ohne 'url'-Feld -> Fehler"
mkdir -p "$SMOKE_DIR/tests/regression/no-url"
cat >"$SMOKE_DIR/tests/regression/no-url/x.md" <<'MD'
---
title: No URL
target: url
---
MD
: >"$SMOKE_DIR/tests/regression/no-url/x.spec.ts"
set +e
out_nourl="$(run_runner tests/regression/no-url 2>&1)"
rc_nourl=$?
set -e
[[ "$rc_nourl" -ne 0 ]] || fail "erwartete Fehler bei target=url ohne url-Feld, bekam Exit 0"
echo "$out_nourl" | grep -qi "kein 'url'-Feld" || fail "erwartete Fehlermeldung zu fehlendem url-Feld: $out_nourl"
log "Edge-Case (target=url ohne url) ok"

log "ALL VERTRAEGE PASS"
echo "PASS"
