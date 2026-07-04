#!/usr/bin/env bash
# run-migrations.sh — Migration-Runner für MongoDB (Spec §6 + §16-R5)
#
# Läuft im separaten `migrations`-Container (mongo:7; Spec §16-R4),
# nachdem der `db`-Service healthy ist. Iteriert `db_scripts/<NNN>_*.js`
# numerisch sortiert und appliziert ungeapplizte Migrationen via mongosh.
# Schreibt Marker (version + applied_at + checksum) in die Collection
# `_schema_migrations`.
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
# Mongo-Spezifik (Spec §4 mongo): Migrationen sind nicht atomar über
# Statements hinweg (kein DDL-Rollback wie SQL). Mitigation = strikte
# Idempotenz pro Datei (siehe knowledge/mongodb.md mongo/R01-R05) —
# bricht eine Migration auf halbem Weg, muss der Rerun sauber durchgehen.
#
# Exit-Codes: 0 = alle Migrationen ok (incl. skip), 1 = mindestens eine
# fehlgeschlagen.

set -euo pipefail

# ---- Konfiguration (aus env_file `.env.db` + compose-env MONGO_HOST=db) ----
MONGO_HOST="${MONGO_HOST:-db}"
MONGO_PORT="${MONGO_PORT:-27017}"
MONGO_DB="${MONGO_DB:-app}"
MONGO_USER="${MONGO_INITDB_ROOT_USERNAME:?MONGO_INITDB_ROOT_USERNAME must be set (load .env.db)}"
MONGO_PASSWORD="${MONGO_INITDB_ROOT_PASSWORD:?MONGO_INITDB_ROOT_PASSWORD must be set (load .env.db)}"

MONGO_URI="mongodb://${MONGO_USER}:${MONGO_PASSWORD}@${MONGO_HOST}:${MONGO_PORT}/${MONGO_DB}?authSource=admin"

MIGRATIONS_DIR="${MIGRATIONS_DIR:-/db_scripts}"

# ---- 1. Auf DB warten (max 60s, 2s-Intervall) ----
echo "[run-migrations] Waiting for MongoDB at ${MONGO_HOST}:${MONGO_PORT} (max 60s)..."
WAIT_MAX=30
WAIT_I=0
until mongosh "$MONGO_URI" --quiet --eval "db.adminCommand({ ping: 1 }).ok" >/dev/null 2>&1; do
  WAIT_I=$((WAIT_I + 1))
  if [ "$WAIT_I" -ge "$WAIT_MAX" ]; then
    echo "[run-migrations] ERROR: MongoDB not ready after 60s — giving up." >&2
    exit 1
  fi
  sleep 2
done
echo "[run-migrations] DB is ready."

# ---- App-DB-Switch + Marker-Accessor (Smoke-Hotfix) ----
#
# Zwei Gotchas, die der Welle-3-Smoke (PR #36 / smoke-mongodb.sh)
# aufgedeckt hat — beide manifestieren sich als
# `TypeError: Cannot read properties of undefined (reading 'find'|'insertOne')`
# auf `db._schema_migrations`:
#
# 1. mongosh's default-`db` ist NICHT garantiert die App-DB aus dem
#    URI-Path: in `--eval`-Aufrufen (im Gegensatz zu interaktivem
#    `use <db>`) verbleibt `db` u.U. auf `test`/`admin`. Fix: vor jedem
#    Statement explizit `db = db.getSiblingDB('${MONGO_DB}')` setzen.
#    Migrations-Files bleiben portabel (kein hardcoded DB-Name); die
#    Verantwortung für den DB-Kontext liegt einzig im Runner.
#
# 2. Collections, deren Name mit `_` beginnt, sind in mongosh NICHT per
#    Dot-Notation erreichbar — `db._schema_migrations` ist immer
#    `undefined`. MongoDB-Doku-Pattern: `db.getCollection('_schema_migrations')`.
#    (Selbe Regel gilt für Bindestrich-Namen.)
#
# Beide Fixes sind im Runner zentralisiert → keine Magie in den
# Migration-Files selbst.
DB_SWITCH="db = db.getSiblingDB('${MONGO_DB}');"
MARKER_ACCESSOR="db.getCollection('_schema_migrations')"

# ---- 2. Marker-Collection sicherstellen (idempotent, Spec §4 + §16-R5) ----
# `createCollection` wirft, wenn die Collection bereits existiert — der
# `getCollectionNames().includes(...)`-Guard schützt vor diesem Fehler
# (knowledge/mongodb.md mongo/R01-Idempotenz).
mongosh "$MONGO_URI" --quiet --eval "
  ${DB_SWITCH}
  if (!db.getCollectionNames().includes('_schema_migrations')) {
    db.createCollection('_schema_migrations');
  }
"

# ---- 3. Bereits applizierte Versionen laden ----
# Format: 'version|checksum' pro Zeile. Leere checksums werden als '' geliefert.
declare -A APPLIED_VERSIONS=()
declare -A APPLIED_CHECKSUMS=()
while IFS='|' read -r version checksum; do
  [ -z "$version" ] && continue
  APPLIED_VERSIONS["$version"]=1
  APPLIED_CHECKSUMS["$version"]="$checksum"
done < <(mongosh "$MONGO_URI" --quiet --eval "
  ${DB_SWITCH}
  ${MARKER_ACCESSOR}.find({}, {_id: 1, checksum: 1}).forEach(function(d) {
    print(d._id + '|' + (d.checksum || ''));
  });
")

# ---- 4. Migration-Dateien iterieren ----
shopt -s nullglob
FILES=( "$MIGRATIONS_DIR"/[0-9][0-9][0-9]_*.js )
shopt -u nullglob

if [ "${#FILES[@]}" -eq 0 ]; then
  echo "[run-migrations] No migration files in ${MIGRATIONS_DIR} — nothing to do."
  exit 0
fi

# Lexikographisch sortieren (nullgepaddete 3-stellige Präfixe → numerisch korrekt)
IFS=$'\n' SORTED=( $(printf '%s\n' "${FILES[@]}" | sort) )
unset IFS

APPLIED_COUNT=0
SKIPPED_COUNT=0
DRIFT_COUNT=0

for f in "${SORTED[@]}"; do
  base="$(basename "$f")"
  version="${base:0:3}"

  # SHA-256 des Datei-Inhalts (sha256sum auf debian/mongo-Image via coreutils)
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
  # WICHTIG: Statt `--file "$f"` direkt zu nutzen (wo `db` u.U. nicht auf
  # die App-DB auflöst), erst `DB_SWITCH` setzen UND DANN per `load()`
  # die Migration ziehen. So bleiben die Migration-Files portabel
  # (kein hardcoded DB-Name im Script) — die Verantwortung für den
  # DB-Kontext liegt einzig im Runner.
  if ! mongosh "$MONGO_URI" --quiet --eval "
    ${DB_SWITCH}
    load('${f}');
  "; then
    echo "[run-migrations] ERROR: migration ${base} failed — aborting." >&2
    exit 1
  fi
  # Marker schreiben — separat, weil mongosh keine Cross-File-Transaktion
  # über Migration + Insert hinweg garantiert (Spec §4 mongo, „nicht atomar
  # über Statements hinweg"). Migrations selbst sind idempotent → der
  # Rerun nach einem Crash zwischen Apply und Marker-Insert ist safe.
  if ! mongosh "$MONGO_URI" --quiet --eval "
    ${DB_SWITCH}
    ${MARKER_ACCESSOR}.insertOne({
      _id: '${version}',
      applied_at: new Date(),
      checksum: '${file_checksum}'
    });
  "; then
    echo "[run-migrations] ERROR: failed to record marker for ${base}." >&2
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
