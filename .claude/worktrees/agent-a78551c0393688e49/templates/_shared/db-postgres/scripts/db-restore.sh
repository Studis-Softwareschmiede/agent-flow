#!/usr/bin/env bash
# db-restore.sh — Restore-Vorlage (Spec §7)
#
# Lädt einen pg_dump-custom-Format-Dump (`.dump`, erzeugt via
# `pg_dump -Fc`) zurück in die laufende Projekt-DB. Spec §7 fordert
# `pg_restore --clean --if-exists` — bestehende Objekte werden vor dem
# Re-Create gedroppt (idempotent gegen Wiederholungen).
#
# Sicherheits-Gate (Spec §7, „kein silent destroy"):
#   - Default: interaktive Bestätigung — der User MUSS den DB-Namen
#     wörtlich eintippen, bevor irgendetwas überschrieben wird.
#   - `--force` als 2. Argument überspringt die Bestätigung
#     (z.B. für non-interactive CI/Restore-Smoke).
#
# Aufruf:
#   ./scripts/db-restore.sh path/to/backup.dump
#   ./scripts/db-restore.sh path/to/backup.dump --force
#
# Idempotent: gleicher Dump zweimal hintereinander → `--clean --if-exists`
# stellt sicher, dass der zweite Lauf nicht an „already exists"-Fehlern
# scheitert.

set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "Usage: $0 <backup.dump> [--force]" >&2
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

# ---- Confirmation-Gate (Spec §7: "type DB-name to confirm") ----
if [ "$FORCE" != "--force" ]; then
  echo "[db-restore] About to overwrite database '${DB_NAME}' on service '${SERVICE}'."
  echo "[db-restore] Type the DB name to confirm:"
  # Bevorzugt stdin (TTY oder Pipe — letzteres erlaubt
  # `echo "$DB" | restore.sh ...` für Test-Harnesses ohne `--force`).
  # Wenn stdin nichts liefert, auf /dev/tty zurückfallen. Wenn beides
  # fehlt → harter Fehler statt silent overwrite.
  CONFIRM=""
  if ! IFS= read -r CONFIRM; then
    if [ -r /dev/tty ]; then
      IFS= read -r CONFIRM < /dev/tty || true
    else
      echo "[db-restore] ERROR: no input available for confirmation. Use --force for non-interactive runs." >&2
      exit 1
    fi
  fi
  if [ "$CONFIRM" != "$DB_NAME" ]; then
    echo "[db-restore] ERROR: confirmation mismatch (got: '${CONFIRM}', expected: '${DB_NAME}'). Aborting." >&2
    exit 1
  fi
fi

# ---- Restore ----
echo "[db-restore] Restoring ${BACKUP} → ${DB_NAME} (user=${DB_USER}, service=${SERVICE}, force=${FORCE:-no})"
# pg_restore liest den Dump von stdin (`-`) — wir pipen die Datei via
# `docker compose exec -T` in den Container, ohne sie zu mounten.
docker compose exec -T "$SERVICE" \
  pg_restore --clean --if-exists -U "$DB_USER" -d "$DB_NAME" < "$BACKUP"

echo "[db-restore] Done."
