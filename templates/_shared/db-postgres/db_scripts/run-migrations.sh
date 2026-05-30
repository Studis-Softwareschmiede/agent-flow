#!/usr/bin/env bash
# run-migrations.sh — Migration-Runner für Postgres (Spec §6 + §16-R5)
#
# Läuft im separaten `migrations`-Container (postgres:16-alpine; Spec §16-R4),
# nachdem der `db`-Service healthy ist. Iteriert `db_scripts/<NNN>_*.sql`
# numerisch sortiert und appliziert ungeapplizte Migrationen in einer
# Transaktion. Schreibt Marker (version + applied_at + checksum) in
# `public._schema_migrations`.
#
# Idempotent: mehrfacher Aufruf ohne Schaden — bereits applizierte
# Migrationen werden via Marker übersprungen.
#
# Drift-Detection (Spec §16-R5, optional aber empfohlen): pro Datei wird
# SHA-256 berechnet und gegen den gespeicherten `checksum` verglichen.
# Mismatch → DRIFT-Warning auf stdout (kein hard fail, damit ad-hoc
# Editierungen vor erstem Production-Deploy nicht den ganzen Stack
# blocken; in der Reviewer-Checklist als Critical gewertet).
#
# Exit-Codes: 0 = alle Migrationen ok (incl. skip), 1 = mindestens eine
# fehlgeschlagen.

set -euo pipefail

# ---- Konfiguration (aus env_file `.env.db` + compose-env DB_HOST=db) ----
DB_HOST="${DB_HOST:-db}"
DB_PORT="${DB_PORT:-5432}"
DB_NAME="${POSTGRES_DB:-app}"
DB_USER="${POSTGRES_USER:-app}"
DB_PASSWORD="${POSTGRES_PASSWORD:?POSTGRES_PASSWORD must be set (load .env.db)}"

export PGPASSWORD="$DB_PASSWORD"
export PGHOST="$DB_HOST"
export PGPORT="$DB_PORT"
export PGUSER="$DB_USER"
export PGDATABASE="$DB_NAME"

MIGRATIONS_DIR="${MIGRATIONS_DIR:-/db_scripts}"

# ---- 1. Auf DB warten (max 60s, 2s-Intervall) ----
echo "[run-migrations] Waiting for Postgres at ${DB_HOST}:${DB_PORT} (max 60s)..."
WAIT_MAX=30
WAIT_I=0
until pg_isready -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -q; do
  WAIT_I=$((WAIT_I + 1))
  if [ "$WAIT_I" -ge "$WAIT_MAX" ]; then
    echo "[run-migrations] ERROR: Postgres not ready after 60s — giving up." >&2
    exit 1
  fi
  sleep 2
done
echo "[run-migrations] DB is ready."

# ---- 2. Marker-Tabelle sicherstellen (idempotent, Spec §4 + §16-R5) ----
psql -v ON_ERROR_STOP=1 -q <<'SQL'
CREATE TABLE IF NOT EXISTS public._schema_migrations (
  version    TEXT        PRIMARY KEY,
  applied_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  checksum   TEXT
);
SQL

# ---- 3. Bereits applizierte Versionen laden ----
declare -A APPLIED_VERSIONS=()
declare -A APPLIED_CHECKSUMS=()
while IFS='|' read -r version checksum; do
  [ -z "$version" ] && continue
  APPLIED_VERSIONS["$version"]=1
  APPLIED_CHECKSUMS["$version"]="$checksum"
done < <(psql -tAF '|' -c "SELECT version, COALESCE(checksum,'') FROM public._schema_migrations")

# ---- 4. Migration-Dateien iterieren ----
shopt -s nullglob
FILES=( "$MIGRATIONS_DIR"/[0-9][0-9][0-9]_*.sql )
shopt -u nullglob

if [ "${#FILES[@]}" -eq 0 ]; then
  echo "[run-migrations] No migration files in ${MIGRATIONS_DIR} — nothing to do."
  exit 0
fi

# Lexikographisch sortieren (nullgepaddete 3-stellige Präfixe → numerisch korrekt)
SORTED=()
while IFS= read -r line; do SORTED+=("$line"); done < <(printf '%s\n' "${FILES[@]}" | sort)

APPLIED_COUNT=0
SKIPPED_COUNT=0
DRIFT_COUNT=0

for f in "${SORTED[@]}"; do
  base="$(basename "$f")"
  version="${base:0:3}"

  # SHA-256 des Datei-Inhalts (sha256sum auf alpine via coreutils)
  if command -v sha256sum >/dev/null 2>&1; then
    file_checksum="$(sha256sum "$f" | awk '{print $1}')"
  else
    file_checksum="$(openssl dgst -sha256 "$f" | awk '{print $NF}')"
  fi

  if [ -n "${APPLIED_VERSIONS[$version]:-}" ]; then
    stored_checksum="${APPLIED_CHECKSUMS[$version]:-}"
    if [ -n "$stored_checksum" ] && [ "$stored_checksum" != "$file_checksum" ]; then
      echo "[run-migrations] DRIFT version=${version} file=${base}"
      echo "                 stored_checksum=${stored_checksum}"
      echo "                 file_checksum  =${file_checksum}"
      echo "                 Applied migration was edited after commit (Spec §4 forward-only violation)."
      DRIFT_COUNT=$((DRIFT_COUNT + 1))
    else
      echo "[run-migrations] SKIP  version=${version} file=${base} (already applied)"
    fi
    SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
    continue
  fi

  echo "[run-migrations] APPLY version=${version} file=${base}"
  # In einer Transaktion: die Migration + den Marker-INSERT. Bei Fehler
  # rollt psql ON_ERROR_STOP=1 + die explizite Transaction zurück.
  if ! psql -v ON_ERROR_STOP=1 --single-transaction \
       -v version="$version" -v checksum="$file_checksum" \
       -f "$f" \
       -c "INSERT INTO public._schema_migrations(version, checksum) VALUES (:'version', :'checksum')"
  then
    echo "[run-migrations] ERROR: migration ${base} failed — aborting." >&2
    exit 1
  fi
  APPLIED_COUNT=$((APPLIED_COUNT + 1))
done

# ---- 5. Zusammenfassung ----
echo "[run-migrations] Done. applied=${APPLIED_COUNT} skipped=${SKIPPED_COUNT} drift=${DRIFT_COUNT}"
if [ "$DRIFT_COUNT" -gt 0 ]; then
  echo "[run-migrations] WARNING: ${DRIFT_COUNT} drift(s) detected — review db_scripts/ for edited applied migrations." >&2
fi
exit 0
