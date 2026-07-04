#!/usr/bin/env bash
# db-backup.sh — Ad-hoc-Backup-Vorlage (Spec §7)
#
# Dumpt die Projekt-DB via `docker compose exec mongodump` im archive-
# Format (single-stream binary, gzipped). Default-Output:
# `backups/db-<UTC-Timestamp>.archive.gz` relativ zum cwd.
#
# Lese-Reihenfolge:
#   1. $1 (CLI-Argument) — expliziter Output-Pfad
#   2. ./backups/db-YYYYMMDD-HHMMSS.archive.gz
#
# Idempotent: jeder Aufruf erzeugt eine NEUE Datei (Timestamp im Namen),
# überschreibt nichts.
#
# Warum archive+gzip (statt Verzeichnis-Dump): single-file, streambar
# (über docker exec stdout), kleiner, restore-symmetrisch zu db-restore.sh.
#
# Voraussetzung: cwd ist das Projekt-Repo mit `docker-compose.yml`, der
# `db`-Service läuft und `.env.db` liegt vor (für MONGO_INITDB_ROOT_*).
# Kein hartkodiertes Passwort — mongodump liest die Credentials aus dem
# URI, der im Container aus der env zusammengesetzt wird.

set -euo pipefail

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

# ---- Output-Pfad bestimmen ----
TS="$(date -u +%Y%m%d-%H%M%S)"
DEFAULT_OUT="backups/db-${TS}.archive.gz"
OUT="${1:-$DEFAULT_OUT}"
OUT_DIR="$(dirname "$OUT")"
mkdir -p "$OUT_DIR"

# ---- Dump ----
# URI wird IM Container zusammengesetzt; mongodump kontaktiert localhost
# (lebt im selben Container wie mongod) → keine Network-Exposure.
echo "[db-backup] Dumping ${MONGO_DB} (user=${MONGO_USER}) from service '${SERVICE}' → ${OUT}"
docker compose exec -T "$SERVICE" \
  mongodump \
    --uri="mongodb://${MONGO_USER}:${MONGO_PASSWORD}@localhost:27017/${MONGO_DB}?authSource=admin" \
    --archive \
    --gzip \
  > "$OUT"

# ---- Reporting ----
SIZE_BYTES="$(wc -c < "$OUT" | tr -d ' ')"
SIZE_HUMAN="$(du -h "$OUT" | awk '{print $1}')"
echo "[db-backup] Done. file=${OUT} size=${SIZE_HUMAN} (${SIZE_BYTES} bytes)"
