#!/usr/bin/env bash
# smoke-sqlite.sh — End-to-end Smoke-Test des db-sqlite Templates.
#
# Prüft die drei Verträge aus Spec §13:
#   1. Apply — Migration läuft im `migrations`-Container (Alpine + sqlite-CLI),
#      Daten sind in der DB-Datei.
#   2. Idempotenz — zweiter Run wendet nichts mehr an.
#   3. Drift — bereits applizierte Migration editiert → Runner exit != 0
#      (SQLite-Runner ist hard-fail per `die "DRIFT detected …"`).
#
# SQLite-Spezifik:
#   - KEIN db-Service. Nur ein one-shot `migrations`-Container, der die
#     SQLite-Datei im `db_data`-Volume schreibt.
#   - Smoke-Query läuft in einem Throwaway-Alpine-Container, der dasselbe
#     Volume mountet und sqlite-CLI installiert.
#
# Voraussetzungen: Docker-Daemon läuft.
# Cleanup: trap räumt Compose-Stack + temp-Verzeichnis auf, auch bei Fehler.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEMPLATE_DIR="$REPO_ROOT/templates/_shared/db-sqlite"
DIALECT="sqlite"

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

command -v docker >/dev/null || fail "docker CLI not found"
docker info >/dev/null 2>&1 || fail "docker daemon not reachable"
[ -d "$TEMPLATE_DIR" ] || fail "template not found: $TEMPLATE_DIR"

log "TMPDIR=$TMPDIR"
log "PROJECT=$PROJECT"

# ---- 1. Template kopieren ----
mkdir -p "$TMPDIR/db_scripts"
cp "$TEMPLATE_DIR/compose.fragment.yml" "$TMPDIR/docker-compose.yml"
cp "$TEMPLATE_DIR/db_scripts/000_init_meta.sql" "$TMPDIR/db_scripts/"
cp "$TEMPLATE_DIR/db_scripts/run-migrations.sh" "$TMPDIR/db_scripts/"
chmod +x "$TMPDIR/db_scripts/run-migrations.sh"

# Test-Migration — sqlite-Idiome (sqlite/R04: STRICT, sqlite/R03: WAL ist persistent)
cat >"$TMPDIR/db_scripts/001_smoke.sql" <<'SQL'
CREATE TABLE IF NOT EXISTS smoke (
  id    INTEGER NOT NULL PRIMARY KEY,
  label TEXT    NOT NULL
) STRICT;
INSERT OR IGNORE INTO smoke (id, label) VALUES (1, 'ok');
SQL

# .env.db — sqlite hat keine Credentials, nur DB_PATH
cat >"$TMPDIR/.env.db" <<'ENV'
DB_PATH=/data/app.db
ENV

cd "$TMPDIR"

# Volume vor dem ersten Lauf explizit anlegen (compose erstellt es auto bei `up`,
# aber für den `run --rm migrations`-Pfad ohne up brauchen wir es vorher).
# `compose up migrations` wäre alternativ — `run --rm` ist konsistenter mit
# den anderen Smoke-Tests.

# ---- 2. Apply ----
log "VERTRAG 1: apply (one-shot migrations container)"
run_log_1="$(docker compose -p "$PROJECT" run --rm migrations 2>&1)" || {
  echo "$run_log_1"
  fail "first migration run failed"
}
indent "$run_log_1"

# Smoke-Query in Throwaway-Container — mountet dasselbe Volume
volume_name="${PROJECT}_db_data"
log "querying smoke row via throwaway alpine+sqlite container"
row="$(docker run --rm -v "${volume_name}:/data" alpine:3.20 sh -c \
       "apk add --no-cache sqlite >/dev/null && sqlite3 /data/app.db 'SELECT id || \"|\" || label FROM smoke;'" \
       | tr -d '\r' | head -1)"
if [ "$row" != "1|ok" ]; then
  fail "expected '1|ok', got '$row'"
fi
log "row verified: $row"

# Marker-Count = 2 (000 + 001)
applied_count="$(docker run --rm -v "${volume_name}:/data" alpine:3.20 sh -c \
                 "apk add --no-cache sqlite >/dev/null && sqlite3 /data/app.db 'SELECT COUNT(*) FROM _schema_migrations;'" \
                 | tr -d '\r ' | head -1)"
if [ "$applied_count" != "2" ]; then
  fail "expected 2 applied migrations (000+001), got '$applied_count'"
fi
log "marker rows: $applied_count"

# ---- 3. Idempotenz ----
log "VERTRAG 2: idempotenz — re-run must skip everything"
run_log_2="$(docker compose -p "$PROJECT" run --rm migrations 2>&1)" || {
  echo "$run_log_2"
  fail "second migration run failed"
}
indent "$run_log_2"

if echo "$run_log_2" | grep -q "^\[migrations\] apply "; then
  fail "second run applied something — not idempotent"
fi
if ! echo "$run_log_2" | grep -q "^\[migrations\] skip "; then
  fail "second run did not emit any 'skip' lines — runner did not see markers"
fi

applied_after_rerun="$(docker run --rm -v "${volume_name}:/data" alpine:3.20 sh -c \
                       "apk add --no-cache sqlite >/dev/null && sqlite3 /data/app.db 'SELECT COUNT(*) FROM _schema_migrations;'" \
                       | tr -d '\r ' | head -1)"
if [ "$applied_after_rerun" != "2" ]; then
  fail "marker count drifted after re-run: $applied_after_rerun"
fi
log "idempotenz ok"

# ---- 4. Drift — SQLite-Runner hard-fails per `die DRIFT detected` ----
log "VERTRAG 3: drift — edit applied migration → runner exit != 0"
echo "-- drift marker $(date +%s)" >>"$TMPDIR/db_scripts/001_smoke.sql"

set +e
run_log_3="$(docker compose -p "$PROJECT" run --rm migrations 2>&1)"
rc_drift=$?
set -e
indent "$run_log_3"

if [ "$rc_drift" -eq 0 ]; then
  fail "drift run unexpectedly exit 0 (SQLite runner should hard-fail)"
fi
if ! echo "$run_log_3" | grep -qi "DRIFT detected"; then
  fail "runner did not log DRIFT detection"
fi
log "drift detected, runner exit ${rc_drift} (expected non-zero)"

log "ALL VERTRAGE PASS"
echo "PASS"
