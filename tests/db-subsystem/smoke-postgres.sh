#!/usr/bin/env bash
# smoke-postgres.sh — End-to-end Smoke-Test des db-postgres Templates.
#
# Prüft die drei Verträge aus Spec §13:
#   1. Apply — Migration läuft sauber durch (exit 0, Daten lesbar).
#   2. Idempotenz — zweiter Run wendet nichts mehr an (alle skip).
#   3. Drift — eine bereits applizierte Migration nachträglich editiert
#      → Runner erkennt SHA-256-Mismatch (Spec §16-R5).
#
# Postgres-Spezifik: der Runner gibt bei Drift eine WARNING aus und
# exit 0 (kein hard fail) — die Detection erfolgt deshalb über
# Output-Match (Zeichenkette "DRIFT"), nicht über den Exit-Code.
#
# Voraussetzungen: Docker-Daemon läuft, sha256sum verfügbar.
# Cleanup: trap räumt Compose-Stack + temp-Verzeichnis auf, auch bei Fehler.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEMPLATE_DIR="$REPO_ROOT/templates/_shared/db-postgres"
DIALECT="postgres"

# Stable project name → wiederholbare Aufrufe räumen denselben Stack ab.
PROJECT="smoke-${DIALECT}-$$"

TMPDIR="$(mktemp -d "/tmp/smoke-${DIALECT}-XXXXXX")"
cleanup() {
  local rc=$?
  if [ -d "$TMPDIR" ]; then
    ( cd "$TMPDIR" && docker compose -p "$PROJECT" down -v --remove-orphans >/dev/null 2>&1 || true )
    rm -rf "$TMPDIR"
  fi
  exit "$rc"
}
trap cleanup EXIT INT TERM

log() { printf '[smoke-%s] %s\n' "$DIALECT" "$*"; }
fail() { printf '[smoke-%s] FAIL: %s\n' "$DIALECT" "$*" >&2; exit 1; }
# Pure-bash log-indent (avoids ext. sed/cat; satisfies shellcheck SC2001).
indent() { printf '    %s\n' "${1//$'\n'/$'\n'    }"; }

# ---- 0. Sanity-Checks ----
command -v docker >/dev/null || fail "docker CLI not found"
docker info >/dev/null 2>&1 || fail "docker daemon not reachable"
[ -d "$TEMPLATE_DIR" ] || fail "template not found: $TEMPLATE_DIR"

log "TMPDIR=$TMPDIR"
log "PROJECT=$PROJECT"

# ---- 1. Template ins Test-Verzeichnis kopieren ----
mkdir -p "$TMPDIR/db_scripts"
cp "$TEMPLATE_DIR/compose.fragment.yml" "$TMPDIR/docker-compose.yml"
cp "$TEMPLATE_DIR/db_scripts/000_init_meta.sql" "$TMPDIR/db_scripts/"
cp "$TEMPLATE_DIR/db_scripts/run-migrations.sh" "$TMPDIR/db_scripts/"
chmod +x "$TMPDIR/db_scripts/run-migrations.sh"

# ---- 2. Test-Migration anlegen (001_smoke.sql) ----
cat >"$TMPDIR/db_scripts/001_smoke.sql" <<'SQL'
-- Smoke-Test-Migration: legt eine Tabelle an und fügt eine Zeile ein.
CREATE TABLE IF NOT EXISTS smoke (
  id    INT  PRIMARY KEY,
  label TEXT NOT NULL
);
INSERT INTO smoke (id, label) VALUES (1, 'ok')
ON CONFLICT (id) DO NOTHING;
SQL

# ---- 3. .env.db mit Test-Credentials ----
cat >"$TMPDIR/.env.db" <<'ENV'
POSTGRES_USER=smoke
POSTGRES_PASSWORD=smoke-test-pw
POSTGRES_DB=smokedb
ENV

cd "$TMPDIR"

# ---- 4. DB starten + auf healthy warten ----
log "starting db service"
docker compose -p "$PROJECT" up -d db >/dev/null

log "waiting for db to be healthy (max 90s)"
WAITED=0
while :; do
  status="$(docker compose -p "$PROJECT" ps --format json db 2>/dev/null \
            | grep -o '"Health":"[^"]*"' | head -1 | cut -d'"' -f4 || true)"
  [ "$status" = "healthy" ] && break
  WAITED=$((WAITED + 2))
  [ "$WAITED" -ge 90 ] && fail "db never became healthy (status=$status)"
  sleep 2
done
log "db healthy after ${WAITED}s"

# ---- 5. Apply: erster Migrations-Lauf ----
log "VERTRAG 1: apply — initial migrations run"
run_log_1="$(docker compose -p "$PROJECT" run --rm migrations 2>&1)" || {
  echo "$run_log_1"
  fail "first migration run failed"
}
indent "$run_log_1"

# 5a. Test-Daten lesen und verifizieren
log "verifying smoke row"
row="$(docker compose -p "$PROJECT" exec -T -e PGPASSWORD=smoke-test-pw db \
       psql -tAU smoke -d smokedb -c "SELECT id || '|' || label FROM smoke;" \
       | tr -d '\r' | head -1)"
if [ "$row" != "1|ok" ]; then
  fail "expected '1|ok', got '$row'"
fi
log "row verified: $row"

# 5b. Marker-Tabelle hat die zwei angewandten Versionen
applied_count="$(docker compose -p "$PROJECT" exec -T -e PGPASSWORD=smoke-test-pw db \
                 psql -tAU smoke -d smokedb -c "SELECT count(*) FROM public._schema_migrations;" \
                 | tr -d '\r ' | head -1)"
if [ "$applied_count" != "2" ]; then
  fail "expected 2 applied migrations (000+001), got '$applied_count'"
fi
log "marker rows: $applied_count (000 + 001)"

# ---- 6. Idempotenz: zweiter Lauf ----
log "VERTRAG 2: idempotenz — re-run must skip everything"
run_log_2="$(docker compose -p "$PROJECT" run --rm migrations 2>&1)" || {
  echo "$run_log_2"
  fail "second migration run failed"
}
indent "$run_log_2"

if echo "$run_log_2" | grep -q "APPLY "; then
  fail "second run still APPLIED something — not idempotent"
fi
if ! echo "$run_log_2" | grep -q "SKIP "; then
  fail "second run produced no SKIP lines — runner did not see existing markers"
fi

# Marker-Count unverändert
applied_after_rerun="$(docker compose -p "$PROJECT" exec -T -e PGPASSWORD=smoke-test-pw db \
                       psql -tAU smoke -d smokedb -c "SELECT count(*) FROM public._schema_migrations;" \
                       | tr -d '\r ' | head -1)"
if [ "$applied_after_rerun" != "2" ]; then
  fail "marker count drifted after re-run: $applied_after_rerun (expected 2)"
fi
log "idempotenz ok — markers stable at $applied_after_rerun"

# ---- 7. Drift: bereits applizierte Migration editieren ----
log "VERTRAG 3: drift — edit applied migration → runner must detect SHA-mismatch"
echo "-- drift marker $(date +%s)" >>"$TMPDIR/db_scripts/001_smoke.sql"

run_log_3="$(docker compose -p "$PROJECT" run --rm migrations 2>&1)" || true
indent "$run_log_3"

# Postgres-Runner exit 0 bei Drift → über Output-Match prüfen.
if ! echo "$run_log_3" | grep -q "DRIFT version=001"; then
  fail "runner did not log DRIFT for edited migration 001"
fi
if ! echo "$run_log_3" | grep -qi "WARNING.*drift"; then
  fail "runner did not emit drift WARNING summary"
fi
log "drift detected and logged"

log "ALL VERTRAGE PASS (apply + idempotenz + drift)"
echo "PASS"
