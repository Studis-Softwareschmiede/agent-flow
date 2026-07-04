#!/usr/bin/env bash
# smoke-mongodb.sh — End-to-end Smoke-Test des db-mongodb Templates.
#
# Prüft die drei Verträge aus Spec §13:
#   1. Apply — Migration läuft sauber durch, Test-Document ist auffindbar.
#   2. Idempotenz — zweiter Run wendet nichts mehr an (alle SKIP).
#   3. Drift — bereits applizierte Migration editiert → Runner gibt
#      DRIFT-Warning aus (mongodb-Runner exit 0 wie Postgres; Detection
#      via Output-Match, nicht Exit-Code).
#
# Voraussetzungen: Docker-Daemon läuft.
# Cleanup: trap räumt Compose-Stack + temp-Verzeichnis auf, auch bei Fehler.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEMPLATE_DIR="$REPO_ROOT/templates/_shared/db-mongodb"
DIALECT="mongodb"

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

# ---- 1. Template kopieren ----
mkdir -p "$SMOKE_DIR/db_scripts"
cp "$TEMPLATE_DIR/compose.fragment.yml" "$SMOKE_DIR/docker-compose.yml"
cp "$TEMPLATE_DIR/db_scripts/000_init_meta.js" "$SMOKE_DIR/db_scripts/"
cp "$TEMPLATE_DIR/db_scripts/run-migrations.sh" "$SMOKE_DIR/db_scripts/"
chmod +x "$SMOKE_DIR/db_scripts/run-migrations.sh"

# Test-Migration (.js, mongosh-Syntax). Guard via getCollectionNames()
# gemäß mongo/R01-Idempotenz.
cat >"$SMOKE_DIR/db_scripts/001_smoke.js" <<'JS'
// Smoke-Test: legt eine Collection und ein Dokument an. Idempotent.
if (!db.getCollectionNames().includes('smoke')) {
  db.createCollection('smoke');
}
// replaceOne mit upsert = idempotent gegen Re-Run innerhalb einer Migration
db.smoke.replaceOne(
  { _id: 1 },
  { _id: 1, label: 'ok' },
  { upsert: true }
);
JS

# .env.db mit Test-Credentials
cat >"$SMOKE_DIR/.env.db" <<'ENV'
MONGO_INITDB_ROOT_USERNAME=smoke
MONGO_INITDB_ROOT_PASSWORD=smoke-test-pw
MONGO_DB=smokedb
ENV

cd "$SMOKE_DIR"

# ---- 2. DB starten + warten ----
log "starting db service (mongo:7)"
docker compose -p "$PROJECT" up -d db >/dev/null

log "waiting for db to be healthy (max 120s)"
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

# Smoke-Document lesen
mongo_uri='mongodb://smoke:smoke-test-pw@db:27017/smokedb?authSource=admin'
row="$(docker compose -p "$PROJECT" exec -T db \
       mongosh "$mongo_uri" --quiet --eval \
       "var d = db.smoke.findOne({_id: 1}); print(d ? d._id + '|' + d.label : 'MISSING');" \
       | tr -d '\r' | tail -1)"
if [ "$row" != "1|ok" ]; then
  fail "expected '1|ok', got '$row'"
fi
log "doc verified: $row"

# Marker-Collection: 2 Documents (000 + 001)
applied_count="$(docker compose -p "$PROJECT" exec -T db \
                 mongosh "$mongo_uri" --quiet --eval \
                 "print(db.getCollection('_schema_migrations').countDocuments({}))" \
                 | tr -d '\r ' | tail -1)"
if [ "$applied_count" != "2" ]; then
  fail "expected 2 applied migrations (000+001), got '$applied_count'"
fi
log "marker docs: $applied_count"

# ---- 4. Idempotenz ----
log "VERTRAG 2: idempotenz — re-run must skip everything"
run_log_2="$(docker compose -p "$PROJECT" run --rm migrations 2>&1)" || {
  echo "$run_log_2"
  fail "second migration run failed"
}
indent "$run_log_2"

if echo "$run_log_2" | grep -q "APPLY "; then
  fail "second run applied something — not idempotent"
fi
if ! echo "$run_log_2" | grep -q "SKIP "; then
  fail "second run produced no SKIP lines"
fi

applied_after_rerun="$(docker compose -p "$PROJECT" exec -T db \
                       mongosh "$mongo_uri" --quiet --eval \
                       "print(db.getCollection('_schema_migrations').countDocuments({}))" \
                       | tr -d '\r ' | tail -1)"
if [ "$applied_after_rerun" != "2" ]; then
  fail "marker count drifted after re-run: $applied_after_rerun"
fi
log "idempotenz ok"

# ---- 5. Drift — Mongo-Runner gibt Warning, exit 0 (wie Postgres) ----
log "VERTRAG 3: drift — edit applied migration → runner must log DRIFT"
echo "// drift marker $(date +%s)" >>"$SMOKE_DIR/db_scripts/001_smoke.js"

run_log_3="$(docker compose -p "$PROJECT" run --rm migrations 2>&1)" || true
indent "$run_log_3"

if ! echo "$run_log_3" | grep -q "DRIFT version=001"; then
  fail "runner did not log DRIFT for edited migration 001"
fi
if ! echo "$run_log_3" | grep -qi "WARNING.*drift"; then
  fail "runner did not emit drift WARNING summary"
fi
log "drift detected and logged"

log "ALL VERTRAGE PASS"
echo "PASS"
