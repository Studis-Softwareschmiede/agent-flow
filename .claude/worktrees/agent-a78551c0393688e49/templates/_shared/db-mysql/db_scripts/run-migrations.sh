#!/usr/bin/env bash
# Migration-Runner für MariaDB/MySQL (Spec §4 + §6, mysql-Dialekt).
#
# Algorithmus:
#   1. Auf DB warten (mariadb-admin ping, max 60s).
#   2. _schema_migrations sicherstellen (CREATE TABLE IF NOT EXISTS).
#   3. Iteriere db_scripts/[0-9][0-9][0-9]_*.sql lexikographisch.
#   4. Bereits applied? → skip.
#      Sonst: Datei-SHA-256 berechnen, Drift gegen gespeicherten Wert prüfen,
#      bei Konflikt abbrechen. Sonst BEGIN; <sql>; INSERT marker; COMMIT.
#
# Verwendung:
#   Container: ENTRYPOINT (compose.fragment.yml → service `migrations`).
#   Lokal:     env-Vars setzen + ./db_scripts/run-migrations.sh
#
# Pflicht-ENV:
#   MARIADB_USER, MARIADB_PASSWORD, MARIADB_DATABASE
# Optional:
#   DB_HOST (default: db)
#   DB_PORT (default: 3306)
#   MIGRATIONS_DIR (default: /db_scripts; lokal ggf. ./db_scripts)
#   WAIT_TIMEOUT  (Sekunden, default: 60)

set -euo pipefail

: "${MARIADB_USER:?MARIADB_USER required}"
: "${MARIADB_PASSWORD:?MARIADB_PASSWORD required}"
: "${MARIADB_DATABASE:?MARIADB_DATABASE required}"

DB_HOST="${DB_HOST:-db}"
DB_PORT="${DB_PORT:-3306}"
MIGRATIONS_DIR="${MIGRATIONS_DIR:-/db_scripts}"
WAIT_TIMEOUT="${WAIT_TIMEOUT:-60}"

log() { printf '[migrations] %s\n' "$*"; }
die() { printf '[migrations] ERROR: %s\n' "$*" >&2; exit 1; }

# mariadb-client kennt --defaults-extra-file für Credentials ohne Plaintext in argv/env.
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

mysql_cmd() {
  mariadb --defaults-extra-file="$CNF" --batch --silent --raw "$MARIADB_DATABASE" "$@"
}

# 1) Wait for DB
log "Waiting up to ${WAIT_TIMEOUT}s for ${DB_HOST}:${DB_PORT} ..."
waited=0
until mariadb-admin --defaults-extra-file="$CNF" ping --silent >/dev/null 2>&1; do
  if [ "$waited" -ge "$WAIT_TIMEOUT" ]; then
    die "DB ${DB_HOST}:${DB_PORT} not reachable after ${WAIT_TIMEOUT}s"
  fi
  sleep 2
  waited=$((waited + 2))
done
log "DB is up."

# 2) Marker table (Spec §4 + §16-R5; siehe knowledge/sql-mysql.md mysql/R01+R02)
log "Ensuring _schema_migrations exists ..."
mysql_cmd <<'SQL'
CREATE TABLE IF NOT EXISTS _schema_migrations (
  version    VARCHAR(255)                                         NOT NULL,
  applied_at DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  checksum   VARCHAR(128),
  PRIMARY KEY (version)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
SQL

# 3) Already-applied set (newline-separated "<version>\t<checksum>")
applied_rows="$(mysql_cmd -e "SELECT version, IFNULL(checksum,'') FROM _schema_migrations" || true)"

# Helper: lookup stored checksum for a version; empty if not applied.
stored_checksum_for() {
  local v="$1"
  printf '%s\n' "$applied_rows" | awk -v v="$v" -F'\t' '$1 == v { print $2; found=1 } END { if (!found) print "" }'
}
is_applied() {
  local v="$1"
  printf '%s\n' "$applied_rows" | awk -v v="$v" -F'\t' '$1 == v { found=1 } END { exit !found }'
}

# 4) Iterate migrations
shopt -s nullglob
files=( "$MIGRATIONS_DIR"/[0-9][0-9][0-9]_*.sql )
shopt -u nullglob

if [ "${#files[@]}" -eq 0 ]; then
  log "No migrations found in ${MIGRATIONS_DIR} (looked for NNN_*.sql)."
  exit 0
fi

# Lexicographic sort (zero-padded NNN ⇒ numeric order)
mapfile -t files < <(printf '%s\n' "${files[@]}" | sort)

applied_count=0
skipped_count=0

for f in "${files[@]}"; do
  base="$(basename "$f")"
  version="${base%.sql}"

  # SHA-256 (coreutils OR busybox)
  if command -v sha256sum >/dev/null 2>&1; then
    checksum="$(sha256sum "$f" | awk '{print $1}')"
  else
    checksum="$(shasum -a 256 "$f" | awk '{print $1}')"
  fi

  if is_applied "$version"; then
    stored="$(stored_checksum_for "$version")"
    if [ -n "$stored" ] && [ "$stored" != "$checksum" ]; then
      die "Drift detected for ${version}: stored=${stored} current=${checksum}. \
Migrations are forward-only — do NOT edit committed files. Add a new NNN_*.sql instead."
    fi
    skipped_count=$((skipped_count + 1))
    continue
  fi

  log "Applying ${version} (sha256=${checksum:0:12}…)"

  # MariaDB-DDL ist meist nicht-transaktional (CREATE TABLE / ALTER triggern
  # implizites COMMIT). Wir wrappen trotzdem BEGIN/COMMIT, weil:
  #  - DML-Teile der Migration so transaktional bleiben.
  #  - Der INSERT in den Marker landet im selben Statement-Batch.
  # Bei reinen DDL-Migrationen ist das Wrap effektiv ein No-op; der
  # Marker-Eintrag ist trotzdem der Single-Source-of-Truth gegen Doppel-Apply.
  {
    printf 'BEGIN;\n'
    cat "$f"
    printf '\nINSERT INTO _schema_migrations (version, checksum) VALUES (%s, %s);\n' \
      "$(printf "'%s'" "$version")" \
      "$(printf "'%s'" "$checksum")"
    printf 'COMMIT;\n'
  } | mysql_cmd

  applied_count=$((applied_count + 1))
done

log "Done. applied=${applied_count} skipped=${skipped_count} total=${#files[@]}"
