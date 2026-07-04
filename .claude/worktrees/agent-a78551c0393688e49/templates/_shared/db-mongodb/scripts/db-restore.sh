#!/usr/bin/env bash
# db-restore.sh — Ad-hoc-Restore-Vorlage (Spec §7)
#
# Streamt eine mongodump-archive.gz-Datei via `docker compose exec` in
# den `db`-Service. `--drop` löscht jede Collection vor dem Restore, um
# einen sauberen Zustand zu garantieren — daher die explizite User-
# Bestätigung (Spec §7 Pflicht: „interaktiv, kein silent destroy").
#
# Aufruf:
#   ./scripts/db-restore.sh ./backups/db-20260530-120000.archive.gz
#   FORCE=1 ./scripts/db-restore.sh <file>     # Bestätigung überspringen (CI/Skripte)
#
# Voraussetzung: cwd ist das Projekt-Repo mit `docker-compose.yml`, der
# `db`-Service läuft und `.env.db` liegt vor.

set -euo pipefail

# ---- Argumente ----
if [ "$#" -lt 1 ]; then
  echo "Usage: $0 <backup-archive.gz> [FORCE=1]" >&2
  exit 2
fi
INPUT="$1"
if [ ! -f "$INPUT" ]; then
  echo "[db-restore] ERROR: Backup file not found: ${INPUT}" >&2
  exit 1
fi

# ---- env aus .env.db laden ----
ENV_FILE="${ENV_FILE:-.env.db}"
if [ -f "$ENV_FILE" ]; then
  # shellcheck disable=SC1090
  set -a; . "$ENV_FILE"; set +a
fi

MONGO_USER="${MONGO_INITDB_ROOT_USERNAME:-app}"
MONGO_PASSWORD="${MONGO_INITDB_ROOT_PASSWORD:?MONGO_INITDB_ROOT_PASSWORD must be set in ${ENV_FILE}}"
MONGO_DB="${MONGO_DB:-app}"
SERVICE="${DB_SERVICE:-db}"
FORCE="${FORCE:-0}"

URI="mongodb://${MONGO_USER}:${MONGO_PASSWORD}@localhost:27017/${MONGO_DB}?authSource=admin"

# ---- Empty-DB-Check (Spec §7: kein silent destroy) ----
# Sammelt die App-Collections (ohne System- und Marker-Collection). Wenn
# nicht-leer und FORCE!=1: interaktive Bestätigung.
EXISTING_COLLECTIONS="$(
  docker compose exec -T "$SERVICE" mongosh "$URI" --quiet --eval "
    db.getCollectionNames()
      .filter(n => n !== '_schema_migrations' && !n.startsWith('system.'))
      .join(',')
  " 2>/dev/null || echo ""
)"
# mongosh kann Statusmeldungen mit-print en; trimmen.
EXISTING_COLLECTIONS="$(echo "$EXISTING_COLLECTIONS" | tr -d '\r' | tail -n 1)"

if [ -n "$EXISTING_COLLECTIONS" ] && [ "$FORCE" != "1" ]; then
  echo "[db-restore] WARNING: DB '${MONGO_DB}' is NOT empty."
  echo "[db-restore]   non-system collections: ${EXISTING_COLLECTIONS}"
  echo "[db-restore]   mongorestore --drop will DELETE each restored collection before restoring."
  echo ""
  printf "[db-restore] Type the DB name to confirm restore: "
  read -r CONFIRM
  if [ "$CONFIRM" != "$MONGO_DB" ]; then
    echo "[db-restore] Aborted (typed '${CONFIRM}' ≠ '${MONGO_DB}')." >&2
    exit 1
  fi
fi

# ---- Restore ----
echo "[db-restore] Restoring ${INPUT} → ${MONGO_DB} (user=${MONGO_USER}) on service '${SERVICE}'"
cat "$INPUT" | docker compose exec -T "$SERVICE" \
  mongorestore \
    --uri="$URI" \
    --archive \
    --gzip \
    --drop

echo "[db-restore] Done."
