#!/usr/bin/env bash
# SQLite backup — File-Copy mit vorausgehendem WAL-Checkpoint.
#
# Hintergrund (Spec §7, sqlite/Reviewer-Checklist):
#   Im WAL-Modus (sqlite/R03) leben uncommittete UND committete-aber-
#   nicht-gemergte Writes in der `<db>-wal`-Sidecar-Datei. Ein nackter `cp`
#   auf die `<db>`-Hauptdatei kann daher inkonsistent sein (jüngste Writes
#   fehlen). Mit `PRAGMA wal_checkpoint(TRUNCATE)` werden alle Frames in
#   die Hauptdatei geschrieben und das WAL gekürzt — anschließend ist
#   ein `cp` der Hauptdatei konsistent.
#
# Annahme: Der `migrations`-Service aus compose.fragment.yml ist als
# one-shot-Container definiert und hat sqlite3-CLI + das `db_data`-Volume.
# `docker compose run --rm` startet einen ephemeren Container mit denselben
# Mounts. Falls ein anderer Container parallel SCHREIBT, ist auch mit
# Checkpoint kein Single-Point-in-Time garantiert — für saubere Backups
# entweder die App kurz stoppen oder `db-restore.sh`-Pfad (online .backup)
# verwenden.
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

# Checkpoint + cp in einem migrations-Container-Run.
# `/backup` wird vom Host als bind-mount eingehängt, damit die Kopie auf
# dem Host landet (das DB-Volume bleibt unangetastet).
docker compose run --rm \
  -v "$abs_out:/backup" \
  -e DB_PATH="$DB_PATH" \
  migrations \
  sh -c "apk add --no-cache sqlite >/dev/null \
    && sqlite3 \"\$DB_PATH\" 'PRAGMA wal_checkpoint(TRUNCATE);' \
    && cp \"\$DB_PATH\" \"/backup/${NAME}\" \
    && echo '[backup] wrote /backup/${NAME}'"

echo "[backup] done: $abs_out/$NAME"
