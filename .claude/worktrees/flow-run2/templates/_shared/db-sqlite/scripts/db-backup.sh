#!/usr/bin/env bash
# SQLite backup — sqlite3 `.backup`-Kommando (online-safe, hot backup).
#
# Hintergrund (Spec §7-Tabelle, Verbatim-Pflicht / coder/L07):
#   Spec §7 mandatiert für SQLite explizit:
#     sqlite3 "$DB_PATH" ".backup '$OUT/app.sqlite'"   (online-safe; nicht plain `cp`)
#   Das `.backup`-Kommando nutzt die SQLite Online Backup API
#   (https://www.sqlite.org/backup.html) — es kopiert die Datenbank-Seiten
#   page-by-page mit korrekter Lock-Koordination und liefert auch bei
#   laufenden Writes eine konsistente Snapshot-Kopie. Kein vorheriger
#   wal_checkpoint nötig — `.backup` integriert WAL-Frames automatisch in
#   die Backup-Datei.
#
# Annahme: Der `migrations`-Service aus compose.fragment.yml ist als
# one-shot-Container definiert und hat sqlite3-CLI + das `db_data`-Volume.
# `docker compose run --rm` startet einen ephemeren Container mit denselben
# Mounts plus zusätzlichem Bind-Mount für das Backup-Output-Verzeichnis.
#
# Aufruf:
#   ./db-backup.sh                  # → ./backups/db-YYYYMMDD-HHMMSS.sqlite
#   ./db-backup.sh /pfad/zum/ziel   # → /pfad/zum/ziel/db-YYYYMMDD-HHMMSS.sqlite

set -euo pipefail

OUT_DIR="${1:-./backups}"
DB_PATH="${DB_PATH:-/data/app.db}"
STAMP="$(date +%Y%m%d-%H%M%S)"
NAME="db-${STAMP}.sqlite"

mkdir -p "$OUT_DIR"
abs_out="$(cd "$OUT_DIR" && pwd)"

echo "[backup] DB_PATH (in container) = $DB_PATH"
echo "[backup] out-dir (on host)      = $abs_out"
echo "[backup] file                   = $NAME"

# `.backup` in einem migrations-Container-Run.
# `/backup` wird vom Host als bind-mount eingehängt, damit die Kopie auf
# dem Host landet (das DB-Volume bleibt unangetastet).
docker compose run --rm \
  -v "$abs_out:/backup" \
  -e DB_PATH="$DB_PATH" \
  migrations \
  sh -c "apk add --no-cache sqlite >/dev/null \
    && sqlite3 \"\$DB_PATH\" \".backup '/backup/${NAME}'\" \
    && echo '[backup] wrote /backup/${NAME}'"

echo "[backup] done: $abs_out/$NAME"
