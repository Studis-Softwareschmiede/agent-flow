#!/usr/bin/env bash
# SQLite restore — Stoppt App-Container, kopiert Backup-File ins Volume,
# startet App neu.
#
# WARNUNG: DESTRUCTIVE. Überschreibt das laufende DB-File. Skript fragt
# explizit nach (Spec §7 „interaktive Bestätigung, kein silent destroy").
#
# Aufruf:
#   ./db-restore.sh ./backups/db-20260530-101500.sqlite
#   ./db-restore.sh ./backups/db-20260530-101500.sqlite app   # app-service-name override

set -euo pipefail

BACKUP_FILE="${1:?Pfad zum Backup-File erforderlich: ./db-restore.sh <backup.sqlite> [app-service]}"
APP_SERVICE="${2:-app}"
DB_PATH="${DB_PATH:-/data/app.db}"

if [ ! -f "$BACKUP_FILE" ]; then
  echo "[restore][error] Backup-File nicht gefunden: $BACKUP_FILE" >&2
  exit 1
fi

# Empty-DB-Check via Dateigröße. Ein gültiges SQLite-File hat mindestens
# einen 100-Byte-Header (https://www.sqlite.org/fileformat.html §1.2).
size=$(wc -c < "$BACKUP_FILE" | tr -d ' ')
if [ "$size" -lt 100 ]; then
  echo "[restore][error] Backup-File ist verdächtig klein (${size} bytes < 100) — abgebrochen." >&2
  echo "[restore][error] Gültige SQLite-Files starten mit einem 100-Byte-Header." >&2
  exit 1
fi
echo "[restore] backup file size: ${size} bytes"

abs_backup="$(cd "$(dirname "$BACKUP_FILE")" && pwd)/$(basename "$BACKUP_FILE")"
backup_name="$(basename "$BACKUP_FILE")"
project="$(basename "$(pwd)")"

echo ""
echo "==========================================================="
echo " SQLite RESTORE — destructive overwrite"
echo "-----------------------------------------------------------"
echo " project (compose -p)  : ${COMPOSE_PROJECT_NAME:-$project}"
echo " app service to stop   : ${APP_SERVICE}"
echo " backup file (host)    : ${abs_backup}"
echo " target DB_PATH (vol)  : ${DB_PATH}"
echo "==========================================================="
printf "Type the project name '%s' to confirm: " "${COMPOSE_PROJECT_NAME:-$project}"
read -r reply
if [ "$reply" != "${COMPOSE_PROJECT_NAME:-$project}" ]; then
  echo "[restore] aborted (confirmation mismatch)."
  exit 1
fi

echo "[restore] stopping app service: ${APP_SERVICE}"
docker compose stop "${APP_SERVICE}" || {
  echo "[restore][warn] konnte ${APP_SERVICE} nicht stoppen (läuft evtl. nicht) — weiter."
}

echo "[restore] copying ${backup_name} into volume at ${DB_PATH} (+ removing WAL/SHM sidecars)"
docker compose run --rm \
  -v "$abs_backup:/restore/source.sqlite:ro" \
  -e DB_PATH="$DB_PATH" \
  migrations \
  sh -c "apk add --no-cache sqlite >/dev/null \
    && rm -f \"\${DB_PATH}-wal\" \"\${DB_PATH}-shm\" \
    && cp /restore/source.sqlite \"\$DB_PATH\" \
    && sqlite3 \"\$DB_PATH\" 'PRAGMA integrity_check;' \
    && echo '[restore] integrity_check passed'"

echo "[restore] starting app service: ${APP_SERVICE}"
docker compose up -d "${APP_SERVICE}"

echo "[restore] done."
