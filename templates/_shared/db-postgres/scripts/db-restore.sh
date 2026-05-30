#!/usr/bin/env bash
# db-restore.sh — Restore-Vorlage (Spec §7)
#
# Lädt einen gzip-pg_dump (.sql.gz) zurück in die laufende Projekt-DB.
# Voreingestellt destruktiv-sicher: bricht ab, wenn die DB nicht leer
# ist (mindestens eine User-Tabelle außer `_schema_migrations`). Mit
# `--force` als 2. Argument wird die Sicherung übergangen — der Dump
# wird in die existierende DB gespielt (Konflikte sind Restorer-Sache).
#
# Aufruf:
#   ./scripts/db-restore.sh path/to/backup.sql.gz
#   ./scripts/db-restore.sh path/to/backup.sql.gz --force
#
# Idempotent: gleicher Dump zweimal → das zweite Mal kann auf Konflikte
# laufen; das ist erwünscht und durch das leere-DB-Gate abgesichert.

set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "Usage: $0 <backup.sql.gz> [--force]" >&2
  exit 2
fi

BACKUP="$1"
FORCE="${2:-}"

if [ ! -f "$BACKUP" ]; then
  echo "[db-restore] ERROR: backup file not found: ${BACKUP}" >&2
  exit 1
fi

# ---- env aus .env.db laden ----
ENV_FILE="${ENV_FILE:-.env.db}"
if [ -f "$ENV_FILE" ]; then
  set -a
  # shellcheck source=/dev/null
  . "$ENV_FILE"
  set +a
fi

DB_USER="${POSTGRES_USER:-app}"
DB_NAME="${POSTGRES_DB:-app}"
SERVICE="${DB_SERVICE:-db}"

# ---- Sicherheits-Gate: DB leer? ----
# Zählt User-Tabellen im `public`-Schema, ohne den Marker. Nur 0 → frei.
USER_TABLE_COUNT="$(docker compose exec -T "$SERVICE" \
  psql -U "$DB_USER" -d "$DB_NAME" -tAc \
  "SELECT COUNT(*) FROM information_schema.tables \
   WHERE table_schema = 'public' \
     AND table_name <> '_schema_migrations'" | tr -d '[:space:]')"

if [ "$USER_TABLE_COUNT" != "0" ] && [ "$FORCE" != "--force" ]; then
  echo "[db-restore] ERROR: target DB '${DB_NAME}' is not empty (${USER_TABLE_COUNT} user tables present)." >&2
  echo "[db-restore]        Use '--force' to override (will not drop existing tables; psql will surface conflicts)." >&2
  exit 1
fi

# ---- Restore ----
echo "[db-restore] Restoring ${BACKUP} → ${DB_NAME} (user=${DB_USER}, service=${SERVICE}, force=${FORCE:-no})"
gunzip -c "$BACKUP" | docker compose exec -T "$SERVICE" \
  psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$DB_NAME"

echo "[db-restore] Done."
