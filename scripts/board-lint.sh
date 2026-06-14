#!/usr/bin/env bash
# board-lint.sh — Validiert das board/-Verzeichnis gegen das Board-Schema.
#
# Scope: AC1 (board.yaml Pflichtfelder) +
#        AC4 (ID-Muster, Enums, AC-Tokens, ISO-8601-Zeitstempel) +
#        AC9 (Pflichtfelder und Enum-Verletzungen mit Datei + Feldname).
#
# Ausgabe je Verstoss: FEHLER|WARN <regel-id> <datei> <feld/detail>
# Exit-Code: 1 bei mindestens einem FEHLER, 0 bei nur Warnungen oder gruen.
#
# Requires: bash >= 4.0, python3 (fuer YAML-Parsing via PyYAML)
#
# Lint-Regel-IDs (stabil, aus Spec docs/specs/board-schema.md):
#   FIELD-REQUIRED  — Pflichtfeld fehlt oder leer; board.yaml fehlt (V1, V9)
#   ENUM-INVALID    — Enum-Wert nicht erlaubt, ID-Muster falsch,
#                     implements[]-Eintrag kein AC<n>, Zeitstempel kein ISO-8601-UTC (V4, V9)
#
# Weitergehende Regeln (ID-DUP, PARENT-MISSING, DEPENDS-UNRESOLVED, etc.)
# sind Teil von [[board-cli]] (Folge-Item).

set -euo pipefail

BOARD_DIR="${1:-board}"
EXIT_CODE=0
ERRORS=0

# ---------------------------------------------------------------------------
# Hilfsfunktionen
# ---------------------------------------------------------------------------

fehler() {
  local regel="$1" datei="$2" detail="$3"
  echo "FEHLER ${regel} ${datei} ${detail}"
  ERRORS=$(( ERRORS + 1 ))
}

warn() {
  local regel="$1" datei="$2" detail="$3"
  echo "WARN ${regel} ${datei} ${detail}"
}

# YAML-Datei als Python-dict laden und Pflicht/Enum-Check ausfuehren
lint_feature() {
  local file="$1"
  python3 - "$file" <<'PYEOF'
import sys, yaml, re, os, datetime

REQUIRED = ["id", "title", "goal", "status", "priority", "created_at", "updated_at"]
ENUM_STATUS = {"Backlog", "Planned", "Active", "Done", "Archived"}
ENUM_PRIORITY = {"P0", "P1", "P2", "P3"}
ID_PATTERN = re.compile(r"^F-\d{3,}$")
TS_PATTERN = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$")
DEPENDS_PATTERN = re.compile(r"^F-\d{3,}$")
STORIES_PATTERN = re.compile(r"^S-\d{3,}$")

def ts_to_str(val):
    """Normalisiert einen YAML-geparsten Zeitstempel zu ISO-8601-UTC-String.
    PyYAML parst 'YYYY-MM-DDTHH:MM:SSZ' als datetime-Objekt — wir serialisieren
    es zurueck auf den kanonischen String."""
    if isinstance(val, datetime.datetime):
        if val.tzinfo is not None:
            import datetime as dt
            utc = val.astimezone(dt.timezone.utc)
        else:
            utc = val
        return utc.strftime("%Y-%m-%dT%H:%M:%SZ")
    return str(val)

errors = []
file = sys.argv[1]
rel = os.path.relpath(file)

try:
    with open(file) as f:
        data = yaml.safe_load(f)
except Exception as e:
    print(f"FEHLER FIELD-REQUIRED {rel} <parse-error: {e}>")
    sys.exit(0)

if not isinstance(data, dict):
    print(f"FEHLER FIELD-REQUIRED {rel} <not a mapping>")
    sys.exit(0)

# Pflichtfelder
for field in REQUIRED:
    if field not in data or data[field] is None or str(data[field]).strip() == "":
        errors.append(f"FEHLER FIELD-REQUIRED {rel} {field}")

# Enum-Checks (nur wenn Feld vorhanden)
if "status" in data and data["status"] not in ENUM_STATUS:
    errors.append(f"FEHLER ENUM-INVALID {rel} status={data['status']!r}")
if "priority" in data and data["priority"] not in ENUM_PRIORITY:
    errors.append(f"FEHLER ENUM-INVALID {rel} priority={data['priority']!r}")

# ID-Muster (V4)
if "id" in data and data["id"] is not None:
    if not ID_PATTERN.match(str(data["id"])):
        errors.append(f"FEHLER ENUM-INVALID {rel} id={data['id']!r} (muss F-###)")

# Zeitstempel (V4)
for ts_field in ("created_at", "updated_at"):
    if ts_field in data and data[ts_field] is not None:
        ts_str = ts_to_str(data[ts_field])
        if not TS_PATTERN.match(ts_str):
            errors.append(f"FEHLER ENUM-INVALID {rel} {ts_field}={data[ts_field]!r} (muss ISO-8601-UTC)")

# depends[] — nur F-### erlaubt
if "depends" in data and data["depends"] is not None:
    for dep in (data["depends"] if isinstance(data["depends"], list) else [data["depends"]]):
        if not DEPENDS_PATTERN.match(str(dep)):
            errors.append(f"FEHLER ENUM-INVALID {rel} depends[]={dep!r} (muss F-###)")

# stories[] — nur S-### erlaubt (abgeleitet, Format-Check)
if "stories" in data and data["stories"] is not None:
    for s in (data["stories"] if isinstance(data["stories"], list) else [data["stories"]]):
        if not STORIES_PATTERN.match(str(s)):
            errors.append(f"FEHLER ENUM-INVALID {rel} stories[]={s!r} (muss S-###)")

for e in errors:
    print(e)
PYEOF
}

lint_story() {
  local file="$1"
  python3 - "$file" <<'PYEOF'
import sys, yaml, re, os, datetime

REQUIRED = ["id", "parent", "title", "status", "priority", "spec", "implements", "created_at", "updated_at"]
ENUM_STATUS = {"To Do", "In Progress", "Blocked", "In Review", "Done"}
ENUM_PRIORITY = {"P0", "P1", "P2", "P3"}
ENUM_SIZE_EST = {"S", "M", "L", "XL"}
ENUM_CONFIDENCE = {"high", "medium", "low"}
ID_PATTERN = re.compile(r"^S-\d{3,}$")
PARENT_PATTERN = re.compile(r"^F-\d{3,}$")
DEPENDS_PATTERN = re.compile(r"^S-\d{3,}$")
IMPLEMENTS_PATTERN = re.compile(r"^AC\d+$")
TS_PATTERN = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$")

def ts_to_str(val):
    """Normalisiert einen YAML-geparsten Zeitstempel zu ISO-8601-UTC-String."""
    if isinstance(val, datetime.datetime):
        if val.tzinfo is not None:
            import datetime as dt
            utc = val.astimezone(dt.timezone.utc)
        else:
            utc = val
        return utc.strftime("%Y-%m-%dT%H:%M:%SZ")
    return str(val)

errors = []
file = sys.argv[1]
rel = os.path.relpath(file)

try:
    with open(file) as f:
        data = yaml.safe_load(f)
except Exception as e:
    print(f"FEHLER FIELD-REQUIRED {rel} <parse-error: {e}>")
    sys.exit(0)

if not isinstance(data, dict):
    print(f"FEHLER FIELD-REQUIRED {rel} <not a mapping>")
    sys.exit(0)

# Pflichtfelder
for field in REQUIRED:
    val = data.get(field)
    if val is None or (isinstance(val, str) and val.strip() == "") or (isinstance(val, list) and len(val) == 0):
        errors.append(f"FEHLER FIELD-REQUIRED {rel} {field}")

# Enum-Checks
if "status" in data and data["status"] not in ENUM_STATUS:
    errors.append(f"FEHLER ENUM-INVALID {rel} status={data['status']!r}")
if "priority" in data and data["priority"] not in ENUM_PRIORITY:
    errors.append(f"FEHLER ENUM-INVALID {rel} priority={data['priority']!r}")
if "size_est" in data and data["size_est"] is not None:
    if str(data["size_est"]) not in ENUM_SIZE_EST:
        errors.append(f"FEHLER ENUM-INVALID {rel} size_est={data['size_est']!r}")
if "confidence" in data and data["confidence"] is not None:
    if str(data["confidence"]) not in ENUM_CONFIDENCE:
        errors.append(f"FEHLER ENUM-INVALID {rel} confidence={data['confidence']!r}")

# ID-Muster (V4)
if "id" in data and data["id"] is not None:
    if not ID_PATTERN.match(str(data["id"])):
        errors.append(f"FEHLER ENUM-INVALID {rel} id={data['id']!r} (muss S-###)")

# parent-Muster (V4)
if "parent" in data and data["parent"] is not None:
    if not PARENT_PATTERN.match(str(data["parent"])):
        errors.append(f"FEHLER ENUM-INVALID {rel} parent={data['parent']!r} (muss F-###)")

# implements[] — AC<n>-Tokens (V4)
if "implements" in data and isinstance(data["implements"], list):
    for ac in data["implements"]:
        if not IMPLEMENTS_PATTERN.match(str(ac)):
            errors.append(f"FEHLER ENUM-INVALID {rel} implements[]={ac!r} (muss AC<n>)")

# depends[] — nur S-### erlaubt
if "depends" in data and data["depends"] is not None:
    for dep in (data["depends"] if isinstance(data["depends"], list) else [data["depends"]]):
        if not DEPENDS_PATTERN.match(str(dep)):
            errors.append(f"FEHLER ENUM-INVALID {rel} depends[]={dep!r} (muss S-###)")

# Zeitstempel (V4)
for ts_field in ("created_at", "updated_at"):
    if ts_field in data and data[ts_field] is not None:
        ts_str = ts_to_str(data[ts_field])
        if not TS_PATTERN.match(ts_str):
            errors.append(f"FEHLER ENUM-INVALID {rel} {ts_field}={data[ts_field]!r} (muss ISO-8601-UTC)")

if "done_at" in data and data["done_at"] is not None:
    ts_str = ts_to_str(data["done_at"])
    if not TS_PATTERN.match(ts_str):
        errors.append(f"FEHLER ENUM-INVALID {rel} done_at={data['done_at']!r} (muss ISO-8601-UTC)")

for e in errors:
    print(e)
PYEOF
}

lint_board_yaml() {
  local file="$1"
  python3 - "$file" <<'PYEOF'
import sys, yaml, os

REQUIRED = ["schema_version", "project_slug", "next_feature_id", "next_story_id"]

file = sys.argv[1]
rel = os.path.relpath(file)
errors = []

try:
    with open(file) as f:
        data = yaml.safe_load(f)
except Exception as e:
    print(f"FEHLER FIELD-REQUIRED {rel} <parse-error: {e}>")
    sys.exit(0)

if not isinstance(data, dict):
    print(f"FEHLER FIELD-REQUIRED {rel} <not a mapping>")
    sys.exit(0)

for field in REQUIRED:
    if field not in data or data[field] is None:
        errors.append(f"FEHLER FIELD-REQUIRED {rel} {field}")

# schema_version muss int sein
if "schema_version" in data and data["schema_version"] is not None:
    if not isinstance(data["schema_version"], int):
        errors.append(f"FEHLER ENUM-INVALID {rel} schema_version (muss int, ist {type(data['schema_version']).__name__})")

# next_feature_id / next_story_id muessen int >= 1 sein
for counter in ("next_feature_id", "next_story_id"):
    if counter in data and data[counter] is not None:
        if not isinstance(data[counter], int) or data[counter] < 1:
            errors.append(f"FEHLER ENUM-INVALID {rel} {counter} (muss int >= 1)")

for e in errors:
    print(e)
PYEOF
}

# ---------------------------------------------------------------------------
# Hauptlogik
# ---------------------------------------------------------------------------

# 1. board.yaml pruefen (AC1)
BOARD_YAML="${BOARD_DIR}/board.yaml"
if [[ ! -f "$BOARD_YAML" ]]; then
  fehler "FIELD-REQUIRED" "${BOARD_YAML}" "board.yaml fehlt — Board nicht initialisiert"
  EXIT_CODE=1
else
  mapfile -t board_errors < <(lint_board_yaml "$BOARD_YAML" 2>/dev/null || true)
  for line in "${board_errors[@]}"; do
    echo "$line"
    if [[ "$line" == FEHLER* ]]; then
      ERRORS=$(( ERRORS + 1 ))
    fi
  done
fi

# 2. Feature-YAMLs pruefen (AC2, AC4, AC9)
FEATURES_DIR="${BOARD_DIR}/features"
if [[ -d "$FEATURES_DIR" ]]; then
  while IFS= read -r -d '' file; do
    mapfile -t feature_errors < <(lint_feature "$file" 2>/dev/null || true)
    for line in "${feature_errors[@]}"; do
      echo "$line"
      if [[ "$line" == FEHLER* ]]; then
        ERRORS=$(( ERRORS + 1 ))
      fi
    done
  done < <(find "$FEATURES_DIR" -name "F-*.yaml" -print0 | sort -z)
fi

# 3. Story-YAMLs pruefen (AC3, AC4, AC9)
STORIES_DIR="${BOARD_DIR}/stories"
if [[ -d "$STORIES_DIR" ]]; then
  while IFS= read -r -d '' file; do
    mapfile -t story_errors < <(lint_story "$file" 2>/dev/null || true)
    for line in "${story_errors[@]}"; do
      echo "$line"
      if [[ "$line" == FEHLER* ]]; then
        ERRORS=$(( ERRORS + 1 ))
      fi
    done
  done < <(find "$STORIES_DIR" -name "S-*.yaml" -print0 | sort -z)
fi

# Exit-Code
if [[ $ERRORS -gt 0 ]]; then
  EXIT_CODE=1
fi

exit $EXIT_CODE
