#!/usr/bin/env bash
# Backup-Vorlage für MariaDB/MySQL-DB (Spec §7).
#
# Verwendung:
#   ./scripts/db-backup.sh            # backup nach ./backups/db-<ts>.sql.gz
#   OUT=/tmp/snap.sql.gz ./scripts/db-backup.sh   # explizites Ziel
#
# Pflicht-ENV (analog .env.db):
#   MARIADB_USER, MARIADB_PASSWORD, MARIADB_DATABASE
# Optional:
#   DB_HOST (default: 127.0.0.1)
#   DB_PORT (default: 3306)
#
# Security-Floor (Spec §7):
#  - KEIN Plaintext-Passwort in argv / Repo / Log.
#  - Credentials via --defaults-extra-file (tempfile, chmod 600).
#  - Backup-Datei nie ins Repo committen (in .gitignore aufnehmen).

set -euo pipefail

: "${MARIADB_USER:?MARIADB_USER required}"
: "${MARIADB_PASSWORD:?MARIADB_PASSWORD required}"
: "${MARIADB_DATABASE:?MARIADB_DATABASE required}"

DB_HOST="${DB_HOST:-127.0.0.1}"
DB_PORT="${DB_PORT:-3306}"

ts="$(date -u +%Y%m%d-%H%M%S)"
OUT_DEFAULT="backups/db-${ts}.sql.gz"
OUT="${OUT:-$OUT_DEFAULT}"

mkdir -p "$(dirname "$OUT")"

CNF="$(mktemp)"
trap 'rm -f "$CNF"' EXIT
chmod 600 "$CNF"
cat >"$CNF" <<EOF
[client]
host=${DB_HOST}
port=${DB_PORT}
user=${MARIADB_USER}
password=${MARIADB_PASSWORD}
EOF

printf '[db-backup] dumping %s@%s:%s/%s → %s\n' \
  "$MARIADB_USER" "$DB_HOST" "$DB_PORT" "$MARIADB_DATABASE" "$OUT"

# --single-transaction = konsistenter Snapshot ohne Tabellen-Locks (InnoDB).
# --quick              = streamt zeilenweise, kein Memory-Buffer für grosse Tabellen.
# --routines / --triggers = stored procedures + trigger mitnehmen.
mariadb-dump \
  --defaults-extra-file="$CNF" \
  --single-transaction \
  --quick \
  --routines \
  --triggers \
  "$MARIADB_DATABASE" \
  | gzip > "$OUT"

printf '[db-backup] done: %s (%s bytes)\n' "$OUT" "$(wc -c <"$OUT" | tr -d ' ')"
