#!/usr/bin/env bash
# smoke-mysql.sh — End-to-end Smoke-Test des db-mysql Templates (MariaDB 11).
#
# Prüft die drei Verträge aus Spec §13:
#   1. Apply — Migration läuft sauber durch, Daten sind lesbar.
#   2. Idempotenz — zweiter Run wendet nichts mehr an.
#   3. Drift — bereits applizierte Migration editiert → Runner bricht
#      mit exit 1 ab (MySQL-Runner ist hard-fail bei Drift, siehe
#      run-migrations.sh: `die "Drift detected …"`).
#
# Voraussetzungen: Docker-Daemon läuft.
# Cleanup: trap räumt Compose-Stack + temp-Verzeichnis auf, auch bei Fehler.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEMPLATE_DIR="$REPO_ROOT/templates/_shared/db-mysql"
DIALECT="mysql"

PROJECT="smoke-${DIALECT}-$$"

SMOKE_DIR="$(mktemp -d "/tmp/smoke-${DIALECT}-XXXXXX")"
cleanup() {
  local rc=$?
  if [ -d "$SMOKE_DIR" ]; then
    ( cd "$SMOKE_DIR" && docker compose -p "$PROJECT" down -v --remove-orphans >/dev/null 2>&1 || true )
    rm -rf "$SMOKE_DIR"
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

log "SMOKE_DIR=$SMOKE_DIR"
log "PROJECT=$PROJECT"

# ---- 1. Template kopieren (Compose-Fragment + db_scripts/) ----
mkdir -p "$SMOKE_DIR/db_scripts"
cp "$TEMPLATE_DIR/compose.fragment.yml" "$SMOKE_DIR/docker-compose.yml"
cp "$TEMPLATE_DIR/db_scripts/000_init_meta.sql" "$SMOKE_DIR/db_scripts/"
cp "$TEMPLATE_DIR/db_scripts/run-migrations.sh" "$SMOKE_DIR/db_scripts/"
chmod +x "$SMOKE_DIR/db_scripts/run-migrations.sh"

# Test-Migration anlegen (MySQL/MariaDB: ENGINE=InnoDB + utf8mb4 gemäß mysql/R01+R02)
cat >"$SMOKE_DIR/db_scripts/001_smoke.sql" <<'SQL'
CREATE TABLE IF NOT EXISTS smoke (
  id    INT         NOT NULL,
  label VARCHAR(64) NOT NULL,
  PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
INSERT IGNORE INTO smoke (id, label) VALUES (1, 'ok');
SQL

# .env.db mit Test-Credentials
cat >"$SMOKE_DIR/.env.db" <<'ENV'
MARIADB_DATABASE=smokedb
MARIADB_USER=smoke
MARIADB_PASSWORD=smoke-test-pw
MARIADB_ROOT_PASSWORD=smoke-root-pw
ENV

cd "$SMOKE_DIR"

# ---- 2. DB starten + warten ----
log "starting db service (mariadb:11)"
docker compose -p "$PROJECT" up -d db >/dev/null

log "waiting for db to be healthy (max 120s — mariadb start_period is 30s)"
WAITED=0
while :; do
  status="$(docker compose -p "$PROJECT" ps --format json db 2>/dev/null \
            | grep -o '"Health":"[^"]*"' | head -1 | cut -d'"' -f4 || true)"
  [ "$status" = "healthy" ] && break
  WAITED=$((WAITED + 3))
  [ "$WAITED" -ge 120 ] && fail "db never became healthy (status=$status)"
  sleep 3
done
log "db healthy after ${WAITED}s"

# ---- 3. Apply ----
log "VERTRAG 1: apply"
run_log_1="$(docker compose -p "$PROJECT" run --rm migrations 2>&1)" || {
  echo "$run_log_1"
  fail "first migration run failed"
}
indent "$run_log_1"

# Daten lesen + verifizieren. MARIADB_PASSWORD via env, nicht in argv (sichtbar).
row="$(docker compose -p "$PROJECT" exec -T -e MYSQL_PWD=smoke-test-pw db \
       mariadb -N -B -u smoke smokedb -e "SELECT CONCAT(id,'|',label) FROM smoke;" \
       | tr -d '\r' | head -1)"
if [ "$row" != "1|ok" ]; then
  fail "expected '1|ok', got '$row'"
fi
log "row verified: $row"

# Marker-Count = 2 (000 + 001). MySQL-Runner verwendet vollen basename ohne .sql
# als version → 000_init_meta + 001_smoke. Wichtig: hier zählen, nicht raten.
applied_count="$(docker compose -p "$PROJECT" exec -T -e MYSQL_PWD=smoke-test-pw db \
                 mariadb -N -B -u smoke smokedb -e "SELECT COUNT(*) FROM _schema_migrations;" \
                 | tr -d '\r ' | head -1)"
if [ "$applied_count" != "2" ]; then
  fail "expected 2 applied migrations (000+001), got '$applied_count'"
fi
log "marker rows: $applied_count"

# ---- 4. Idempotenz ----
log "VERTRAG 2: idempotenz — re-run must apply nothing"
run_log_2="$(docker compose -p "$PROJECT" run --rm migrations 2>&1)" || {
  echo "$run_log_2"
  fail "second migration run failed"
}
indent "$run_log_2"

# Runner-Output endet auf "applied=N skipped=M total=…" — applied muss 0 sein.
if echo "$run_log_2" | grep -q "Applying "; then
  fail "second run applied something — not idempotent"
fi
if ! echo "$run_log_2" | grep -q "applied=0 "; then
  fail "second run did not report applied=0"
fi

applied_after_rerun="$(docker compose -p "$PROJECT" exec -T -e MYSQL_PWD=smoke-test-pw db \
                       mariadb -N -B -u smoke smokedb -e "SELECT COUNT(*) FROM _schema_migrations;" \
                       | tr -d '\r ' | head -1)"
if [ "$applied_after_rerun" != "2" ]; then
  fail "marker count drifted after re-run: $applied_after_rerun"
fi
log "idempotenz ok"

# ---- 5. Drift — MySQL-Runner hard-fails ----
log "VERTRAG 3: drift — edit applied migration → runner exit != 0"
echo "-- drift marker $(date +%s)" >>"$SMOKE_DIR/db_scripts/001_smoke.sql"

set +e
run_log_3="$(docker compose -p "$PROJECT" run --rm migrations 2>&1)"
rc_drift=$?
set -e
indent "$run_log_3"

if [ "$rc_drift" -eq 0 ]; then
  fail "drift run unexpectedly exit 0 (MySQL runner should hard-fail)"
fi
if ! echo "$run_log_3" | grep -qi "drift detected"; then
  fail "runner did not log drift detection"
fi
log "drift detected, runner exit ${rc_drift} (expected non-zero)"

log "ALL VERTRAGE PASS"
echo "PASS"
