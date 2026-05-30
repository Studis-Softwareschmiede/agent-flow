#!/usr/bin/env bash
# db-backup.sh — Ad-hoc-Backup-Vorlage (Spec §7)
#
# Dumpt die Projekt-DB via `docker compose exec` im pg_dump-custom-Format
# (`-Fc`). Das custom-Format ist bereits intern komprimiert (zlib) — kein
# zusätzliches gzip nötig. Pflicht-Gegenstück: `db-restore.sh` ruft
# `pg_restore --clean --if-exists` (Spec §7).
#
# Default-Output: `backups/db-<UTC-Timestamp>.dump` relativ zum cwd.
#
# Lese-Reihenfolge:
#   1. $1 (CLI-Argument) — expliziter Output-Pfad
#   2. ./backups/db-YYYYMMDD-HHMMSS.dump
#
# Idempotent: jeder Aufruf erzeugt eine NEUE Datei (Timestamp im Namen),
# überschreibt nichts.
#
# Voraussetzung: cwd ist das Projekt-Repo mit `docker-compose.yml`, der
# `db`-Service läuft und `.env.db` liegt vor (für POSTGRES_USER /
# POSTGRES_DB). Kein hartkodiertes Passwort — pg_dump nutzt PGPASSWORD
# aus dem Container-env.

set -euo pipefail

# ---- env aus .env.db laden (POSTGRES_USER, POSTGRES_DB) ----
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

# ---- Output-Pfad bestimmen ----
TS="$(date -u +%Y%m%d-%H%M%S)"
DEFAULT_OUT="backups/db-${TS}.dump"
OUT="${1:-$DEFAULT_OUT}"
OUT_DIR="$(dirname "$OUT")"
mkdir -p "$OUT_DIR"

# ---- Dump (custom format, intern komprimiert) ----
echo "[db-backup] Dumping ${DB_NAME} (user=${DB_USER}) from service '${SERVICE}' → ${OUT}"
docker compose exec -T "$SERVICE" pg_dump -Fc -U "$DB_USER" -d "$DB_NAME" > "$OUT"

# ---- Reporting ----
SIZE_BYTES="$(wc -c < "$OUT" | tr -d ' ')"
SIZE_HUMAN="$(du -h "$OUT" | awk '{print $1}')"
echo "[db-backup] Done. file=${OUT} size=${SIZE_HUMAN} (${SIZE_BYTES} bytes)"
