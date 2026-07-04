#!/usr/bin/env bash
# SQLite migration-runner — Spec §4 (forward-only, marker table) + §16-R5 (checksum drift).
# Pack-Regeln: sqlite/R02 (foreign_keys ON), sqlite/R03 (WAL), sqlite/R04 (STRICT).
#
# Lauf-Kontext: schlanker `migrations`-Container (alpine + sqlite-cli) gemäß
# Compose-Fragment dieses Templates. Wird vor App-Start einmalig ausgeführt
# (depends_on: condition: service_completed_successfully).
#
# Verhalten:
#   1. Stellt sicher, dass die DB-Datei existiert (touch + VACUUM zur Initialisierung).
#   2. Setzt persistente PRAGMAs (journal_mode=WAL, foreign_keys=ON) idempotent.
#   3. Erstellt _schema_migrations als STRICT-Table (sqlite/R04).
#   4. Iteriert db_scripts/[0-9][0-9][0-9]_*.sql lexikographisch (= numerisch
#      bei 3-stelliger nullgepaddeter Nummerierung, Spec §4).
#   5. Drift-Check via SHA-256 gegen gespeicherten checksum (Spec §16-R5).
#   6. Apply: Migration-File via `sqlite3 -bail` (bricht beim ersten Fehler ab) —
#      Migrations DÜRFEN PRAGMAs enthalten (siehe 000_init_meta.sql), daher
#      KEINE äußere BEGIN/COMMIT-Klammerung im Runner (PRAGMAs sind in
#      Transaktionen nicht erlaubt / werden ignoriert). Nach erfolgreichem
#      Apply: separater Marker-INSERT. Bei Fehler stoppt `set -e` den Runner,
#      bevor der Marker geschrieben wird — die Migration bleibt unmarkiert
#      und wird beim nächsten Lauf erneut versucht (Idempotenz ist Pflicht,
#      sqlite/R06).

set -euo pipefail

: "${DB_PATH:?DB_PATH must be set (e.g. /data/app.db)}"

log() { printf '[migrations] %s\n' "$*"; }
die() { printf '[migrations][error] %s\n' "$*" >&2; exit 1; }

command -v sqlite3 >/dev/null || die "sqlite3 CLI nicht installiert"
command -v sha256sum >/dev/null || die "sha256sum nicht verfügbar"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
log "DB_PATH=$DB_PATH"
log "script-dir=$SCRIPT_DIR"

# SQL-Literal-Escaping (security/R03 + sqlite/no-shell-interpolation):
# Die sqlite3-CLI akzeptiert KEINE positionellen Bind-Werte als zusätzliche
# Argumente nach der SQL-Anweisung (Test: alpine:3.20 + sqlite 3.45 → syntax error).
# `.parameter set` evaluiert den Wert als SQL-Expression und ist daher gegen
# Shell-Injection ebenso angreifbar. Robuste, dialekt-portable Lösung:
# Single-Quotes verdoppeln und den Wert als SQL-String-Literal in das Query
# einsetzen. Das ist die kanonische SQL-Escape-Regel (vgl. SQLite docs
# https://www.sqlite.org/lang_expr.html#literal_values_constants_):
#   Eingabe `O'Brien`  → Literal `'O''Brien'`
#   Eingabe `'; DROP …`→ Literal `'''; DROP …'`  (komplett innerhalb des Strings)
# Deterministisch für JEDE Eingabe, kein Restrisiko.
sql_quote() {
  printf "'%s'" "$(printf '%s' "$1" | sed "s/'/''/g")"
}

# 1) DB-Datei sicherstellen (Verzeichnis + leere Datei). VACUUM materialisiert
#    eine valide (leere) SQLite-Datei, falls touch nur eine 0-Byte-Datei erzeugt.
db_dir="$(dirname "$DB_PATH")"
mkdir -p "$db_dir"
if [ ! -f "$DB_PATH" ]; then
  log "creating new SQLite database at $DB_PATH"
  touch "$DB_PATH"
  sqlite3 "$DB_PATH" "VACUUM;"
fi

# 2) Persistente PRAGMAs (WAL ist persistent, foreign_keys ist per-connection —
#    der Runner setzt es jedes Mal, App-Code muss es ebenfalls beim Connect setzen,
#    siehe sqlite/R02). PRAGMAs dürfen nicht in eine Transaktion — daher
#    bewusst eigener sqlite3-Aufruf vor dem Marker/Apply-Block.
log "applying connection PRAGMAs (journal_mode=WAL, foreign_keys=ON)"
sqlite3 "$DB_PATH" <<'SQL'
PRAGMA journal_mode = WAL;
PRAGMA foreign_keys = ON;
SQL

# 3) Marker-Tabelle als STRICT (sqlite/R04, Spec §4 + §16-R5).
sqlite3 "$DB_PATH" <<'SQL'
CREATE TABLE IF NOT EXISTS _schema_migrations (
  version    TEXT NOT NULL PRIMARY KEY,
  applied_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  checksum   TEXT
) STRICT;
SQL

# 4) Bereits applizierte Versionen einlesen (newline-separated).
applied="$(sqlite3 "$DB_PATH" "SELECT version FROM _schema_migrations ORDER BY version;")"

# Hilfs-Funktion: liefert checksum für gegebene Version (leer, wenn nicht gesetzt).
# Version wird via sql_quote() escaped — keine Shell-Interpolation direkt in SQL.
checksum_of() {
  local qv
  qv="$(sql_quote "$1")"
  sqlite3 "$DB_PATH" "SELECT COALESCE(checksum,'') FROM _schema_migrations WHERE version=${qv};"
}

# 5+6) Iterieren, Drift-Check, Apply.
shopt -s nullglob
files=("$SCRIPT_DIR"/[0-9][0-9][0-9]_*.sql)
shopt -u nullglob

if [ "${#files[@]}" -eq 0 ]; then
  log "no migration files matching ${SCRIPT_DIR}/NNN_*.sql — nothing to do"
  exit 0
fi

# Lexikographisch sortieren (= numerisch bei 3-stelliger nullgepaddeter Konvention).
files_sorted=()
while IFS= read -r line; do files_sorted+=("$line"); done < <(printf '%s\n' "${files[@]}" | sort)

for f in "${files_sorted[@]}"; do
  base="$(basename "$f")"
  version="${base:0:3}"
  hash="$(sha256sum "$f" | awk '{print $1}')"

  if grep -qx "$version" <<<"$applied"; then
    stored="$(checksum_of "$version")"
    if [ -n "$stored" ] && [ "$stored" != "$hash" ]; then
      die "DRIFT detected for version $version ($base): stored=$stored file=$hash — forward-only Verstoß (Spec §4)"
    fi
    log "skip  $base (already applied)"
    continue
  fi

  log "apply $base (sha256=$hash)"
  # Apply migration body first. `-bail` stoppt sqlite3 beim ersten Fehler.
  # Bewusst KEIN BEGIN/COMMIT-Wrapper im Runner: Migrationen dürfen PRAGMAs
  # enthalten (PRAGMAs sind in Transaktionen nicht zulässig). Falls eine
  # Migration interne Transaktions-Atomizität braucht, setzt sie BEGIN/COMMIT
  # selbst. Bei Fehler: set -e stoppt sofort, Marker wird NICHT geschrieben →
  # nächster Lauf wendet die Migration erneut an (Idempotenz-Pflicht, sqlite/R06).
  sqlite3 -bail "$DB_PATH" ".read $f"
  # Marker-INSERT mit SQL-Literal-Escaping (security/R03) — version und hash
  # über sql_quote(), keine Shell-Interpolation direkt in SQL.
  qver="$(sql_quote "$version")"
  qhash="$(sql_quote "$hash")"
  sqlite3 -bail "$DB_PATH" \
    "INSERT INTO _schema_migrations(version, checksum) VALUES (${qver}, ${qhash});"
  log "ok    $base"
done

log "migrations complete"
