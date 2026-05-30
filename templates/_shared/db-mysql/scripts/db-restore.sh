#!/usr/bin/env bash
# Restore-Vorlage für MariaDB/MySQL-DB (Spec §7).
#
# Verwendung:
#   ./scripts/db-restore.sh backups/db-20260530-120000.sql
#   ./scripts/db-restore.sh backups/db-...sql --force   # überschreibt non-empty DB
#
# Pflicht-ENV (analog .env.db):
#   MARIADB_USER, MARIADB_PASSWORD, MARIADB_DATABASE
#
# Format (Spec §7 verbatim): plain SQL erwartet. Für komprimierte Archive
# vor dem Aufruf manuell entpacken: `gunzip backups/db-*.sql.gz`.
#
# Security-Floor (Spec §7): KEIN silent destroy.
#  1. Empty-DB-Check (zählt Tabellen ausser _schema_migrations) — wenn non-empty
#     und kein --force, interaktive Bestätigung („tippe DB-name").
#  2. Credentials via docker compose exec env (keine Plaintext-Args).
#  3. --force überspringt den Prompt (CI/Scripted-Restore).

set -euo pipefail

usage() {
  cat <<EOF
Usage: $0 <backup.sql> [--force]

ENV:
  MARIADB_USER, MARIADB_PASSWORD, MARIADB_DATABASE  (required)
  COMPOSE_SERVICE  (default: db)         which compose service runs MariaDB
EOF
  exit 2
}

[ "$#" -ge 1 ] || usage
BACKUP_FILE="$1"
FORCE=0
if [ "${2:-}" = "--force" ]; then FORCE=1; fi

: "${MARIADB_USER:?MARIADB_USER required}"
: "${MARIADB_PASSWORD:?MARIADB_PASSWORD required}"
: "${MARIADB_DATABASE:?MARIADB_DATABASE required}"

COMPOSE_SERVICE="${COMPOSE_SERVICE:-db}"

[ -f "$BACKUP_FILE" ] || { printf '[db-restore] ERROR: file not found: %s\n' "$BACKUP_FILE" >&2; exit 1; }

# Empty-DB-Check: zähle alle Tabellen ausser dem Marker.
# `docker compose exec -T` reicht den env via -e durch, kein Plaintext in argv.
table_count="$(
  docker compose exec -T \
    -e MYSQL_PWD="$MARIADB_PASSWORD" \
    "$COMPOSE_SERVICE" \
    mariadb --batch --silent --raw \
      -u "$MARIADB_USER" "$MARIADB_DATABASE" \
      -e "SELECT COUNT(*) FROM information_schema.tables
          WHERE table_schema = '${MARIADB_DATABASE}'
            AND table_name <> '_schema_migrations'"
)"

table_count="${table_count//[[:space:]]/}"
if [ "${table_count:-0}" -gt 0 ] && [ "$FORCE" -ne 1 ]; then
  printf '[db-restore] WARNING: database "%s" already has %s non-meta tables.\n' \
    "$MARIADB_DATABASE" "$table_count"
  printf '[db-restore] Type the DB name "%s" to confirm overwrite (or Ctrl-C to abort): ' \
    "$MARIADB_DATABASE"
  read -r confirm
  if [ "$confirm" != "$MARIADB_DATABASE" ]; then
    printf '[db-restore] aborted (confirmation did not match).\n' >&2
    exit 1
  fi
fi

printf '[db-restore] restoring %s → service "%s" db "%s" user "%s"\n' \
  "$BACKUP_FILE" "$COMPOSE_SERVICE" "$MARIADB_DATABASE" "$MARIADB_USER"

# Plain SQL (Spec §7): `mysql … < backup.sql` — kein gunzip-Wrapper.
docker compose exec -T \
    -e MYSQL_PWD="$MARIADB_PASSWORD" \
    "$COMPOSE_SERVICE" \
    mariadb -u "$MARIADB_USER" "$MARIADB_DATABASE" \
  < "$BACKUP_FILE"

printf '[db-restore] done.\n'
