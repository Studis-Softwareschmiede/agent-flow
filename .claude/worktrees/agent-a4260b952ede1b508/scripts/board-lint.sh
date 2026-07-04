#!/usr/bin/env bash
# board-lint.sh — Validiert das board/-Verzeichnis gegen das Board-Schema.
#
# Scope: AC1  (board.yaml Pflichtfelder)
#        AC4  (ID-Muster, Enums, AC-Tokens, ISO-8601-Zeitstempel)
#        AC5  (ID-DUP: doppelte IDs; Dateiname-Praefix passt nicht zur id)
#        AC6  (PARENT-MISSING: Story-parent existiert nicht)
#        AC7  (DEPENDS-UNRESOLVED: nicht aufloesbar / falscher Typ;
#              DEPENDS-CYCLE: Zyklus in depends)
#        AC8  (SPEC-MISSING: Spec-Datei fehlt;
#              AC-MISSING: AC-Nummer nicht in Spec)
#        AC9  (Pflichtfelder und Enum-Verletzungen mit Datei + Feldname)
#        AC10 (ROLLUP-STALE: abgeleitete Felder veraltet — WARN, kein FEHLER)
#        AC11 (deterministisch, FEHLER|WARN-Format, Exit-Code-Semantik)
#        spec-status-lifecycle#AC4 (SPEC-STATUS-INVALID: referenzierte Spec-Datei
#              traegt einen status-Wert ausserhalb {draft, active, superseded})
#
# Ausgabe je Verstoss: FEHLER|WARN <regel-id> <datei> <feld/detail>
# Exit-Code: 1 bei mindestens einem FEHLER, 0 bei nur Warnungen oder gruen.
#
# Requires: bash >= 4.0, python3 (fuer YAML-Parsing via PyYAML)
#
# Lint-Regel-IDs (stabil, aus Spec docs/specs/board-schema.md):
#   FIELD-REQUIRED       — Pflichtfeld fehlt oder leer; board.yaml fehlt (V1, V9)
#   ENUM-INVALID         — Enum-Wert nicht erlaubt, ID-Muster falsch,
#                          implements[]-Eintrag kein AC<n>, Zeitstempel kein ISO-8601-UTC (V4, V9)
#   ID-DUP               — doppelte Feature- oder Story-ID; Dateiname-Praefix != Body-id (V5)
#   PARENT-MISSING       — Story-parent existiert nicht als Datei (V6)
#   DEPENDS-UNRESOLVED   — depends-Referenz nicht aufloesbar oder falscher Typ (V7)
#   DEPENDS-CYCLE        — Zyklus in depends-Graph (V7)
#   SPEC-MISSING         — spec-Datei existiert nicht (V8)
#   AC-MISSING           — implements[]-AC-Nummer nicht in der Spec gefunden (V8)
#   ROLLUP-STALE         — stories[]/progress eines Features veraltet (V10, WARN)
#   STORY-UNSPEC         — importierte Story (github_issue gesetzt) hat spec oder implements
#                          nicht gesetzt — WARN, kein FEHLER (V3, Owner zieht nach im Cut-PR)
#   SPEC-STATUS-INVALID  — referenzierte, existierende Spec-Datei hat Frontmatter-status:
#                          ausserhalb {draft, active, superseded}
#                          (aus Spec docs/specs/spec-status-lifecycle.md, AC4)

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

# Pflichtfelder fuer native Stories (kein github_issue-Feld).
# Fuer importierte Stories (github_issue gesetzt) sind spec und implements optional
# (fehlend → WARN STORY-UNSPEC statt FEHLER FIELD-REQUIRED); sie koennen nachgezogen werden.
REQUIRED_NATIVE   = ["id", "parent", "title", "status", "priority", "spec", "implements", "created_at", "updated_at"]
REQUIRED_IMPORTED = ["id", "parent", "title", "status", "priority", "created_at", "updated_at"]
# Felder, die bei importierten Stories als WARN STORY-UNSPEC gemeldet werden (nicht als FEHLER)
IMPORTED_OPTIONAL_WARN = {"spec", "implements"}

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
warnings = []
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

# Importierte Story erkennen: Feld github_issue gesetzt und nicht None
is_imported = data.get("github_issue") is not None

if is_imported:
    required_fields = REQUIRED_IMPORTED
else:
    required_fields = REQUIRED_NATIVE

# Pflichtfelder pruefen
for field in required_fields:
    val = data.get(field)
    if val is None or (isinstance(val, str) and val.strip() == "") or (isinstance(val, list) and len(val) == 0):
        errors.append(f"FEHLER FIELD-REQUIRED {rel} {field}")

# Fuer importierte Stories: spec/implements fehlt → WARN STORY-UNSPEC (kein FEHLER)
if is_imported:
    for field in IMPORTED_OPTIONAL_WARN:
        val = data.get(field)
        if val is None or (isinstance(val, str) and val.strip() == "") or (isinstance(val, list) and len(val) == 0):
            warnings.append(f"WARN STORY-UNSPEC {rel} {field} (importierte Story — bitte nachziehen im Cut-PR)")

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
for w in warnings:
    print(w)
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

# Integritaetspruefung: AC5, AC6, AC7, AC8, AC10
# Argument: BOARD_DIR
# Gibt FEHLER/WARN-Zeilen aus (gleiche Formatierung wie lint_feature/lint_story).
lint_integrity() {
  local board_dir="$1"
  local repo_root="$2"
  python3 - "$board_dir" "$repo_root" <<'PYEOF'
import sys, os, re, yaml

board_dir = sys.argv[1]
repo_root = sys.argv[2]

features_dir = os.path.join(board_dir, "features")
stories_dir  = os.path.join(board_dir, "stories")

ID_F = re.compile(r"^F-\d{3,}$")
ID_S = re.compile(r"^S-\d{3,}$")
AC_TOK = re.compile(r"^AC\d+$")
# Dateiname-Praefix-Muster: erster Token (F-### oder S-###) aus Basename
PREFIX_F = re.compile(r"^(F-\d{3,})-")
PREFIX_S = re.compile(r"^(S-\d{3,})-")

messages = []  # (sort_key, line)

def rel(path):
    """Relativer Pfad ab repo_root (fuer Ausgabe)."""
    try:
        return os.path.relpath(path, repo_root)
    except Exception:
        return path

def load_yaml_safe(path):
    """Laedt eine YAML-Datei; gibt None zurueck bei Fehler."""
    try:
        with open(path) as f:
            return yaml.safe_load(f)
    except Exception:
        return None

# -----------------------------------------------------------------------
# Alle Feature- und Story-Dateien einsammeln (deterministisch sortiert)
# -----------------------------------------------------------------------
feature_files = []
story_files   = []

if os.path.isdir(features_dir):
    feature_files = sorted(
        os.path.join(features_dir, fn)
        for fn in os.listdir(features_dir)
        if fn.startswith("F-") and fn.endswith(".yaml")
    )
if os.path.isdir(stories_dir):
    story_files = sorted(
        os.path.join(stories_dir, fn)
        for fn in os.listdir(stories_dir)
        if fn.startswith("S-") and fn.endswith(".yaml")
    )

# -----------------------------------------------------------------------
# Daten laden
# -----------------------------------------------------------------------
features = {}  # id -> {data, path}
stories  = {}  # id -> {data, path}

for path in feature_files:
    data = load_yaml_safe(path)
    if not isinstance(data, dict):
        continue
    fid = str(data.get("id", "")).strip()
    if fid:
        features[fid] = {"data": data, "path": path}

for path in story_files:
    data = load_yaml_safe(path)
    if not isinstance(data, dict):
        continue
    sid = str(data.get("id", "")).strip()
    if sid:
        stories[sid] = {"data": data, "path": path}

# -----------------------------------------------------------------------
# AC5 — ID-DUP: doppelte IDs + Dateiname-Praefix != Body-id
# -----------------------------------------------------------------------

# Doppelte Feature-IDs (zwei Dateien mit gleicher id)
seen_fids = {}  # id -> first path
for path in feature_files:
    data = load_yaml_safe(path)
    if not isinstance(data, dict):
        continue
    fid = str(data.get("id", "")).strip()
    if not fid:
        continue
    if fid in seen_fids:
        messages.append((rel(path), f"FEHLER ID-DUP {rel(path)} id={fid!r} bereits in {rel(seen_fids[fid])}"))
    else:
        seen_fids[fid] = path

# Doppelte Story-IDs
seen_sids = {}
for path in story_files:
    data = load_yaml_safe(path)
    if not isinstance(data, dict):
        continue
    sid = str(data.get("id", "")).strip()
    if not sid:
        continue
    if sid in seen_sids:
        messages.append((rel(path), f"FEHLER ID-DUP {rel(path)} id={sid!r} bereits in {rel(seen_sids[sid])}"))
    else:
        seen_sids[sid] = path

# Dateiname-Praefix passt nicht zur Body-id
for path in feature_files:
    data = load_yaml_safe(path)
    if not isinstance(data, dict):
        continue
    body_id = str(data.get("id", "")).strip()
    if not body_id:
        continue
    basename = os.path.basename(path)
    m = PREFIX_F.match(basename)
    if m:
        prefix = m.group(1)
        if prefix != body_id:
            messages.append((rel(path), f"FEHLER ID-DUP {rel(path)} Dateiname-Praefix={prefix!r} != id={body_id!r}"))
    else:
        # Dateiname beginnt zwar mit F-, hat aber kein gueltiges Praefix-Format
        messages.append((rel(path), f"FEHLER ID-DUP {rel(path)} Dateiname-Praefix nicht erkennbar (muss F-###-)"))

for path in story_files:
    data = load_yaml_safe(path)
    if not isinstance(data, dict):
        continue
    body_id = str(data.get("id", "")).strip()
    if not body_id:
        continue
    basename = os.path.basename(path)
    m = PREFIX_S.match(basename)
    if m:
        prefix = m.group(1)
        if prefix != body_id:
            messages.append((rel(path), f"FEHLER ID-DUP {rel(path)} Dateiname-Praefix={prefix!r} != id={body_id!r}"))
    else:
        messages.append((rel(path), f"FEHLER ID-DUP {rel(path)} Dateiname-Praefix nicht erkennbar (muss S-###-)"))

# -----------------------------------------------------------------------
# AC6 — PARENT-MISSING: Story-parent existiert nicht
# -----------------------------------------------------------------------
for sid, entry in stories.items():
    data = entry["data"]
    path = entry["path"]
    parent = data.get("parent")
    if parent is None or str(parent).strip() == "":
        # Bereits von FIELD-REQUIRED abgedeckt; hier nur Existenzpruefung
        continue
    parent_str = str(parent).strip()
    if parent_str not in features:
        messages.append((rel(path), f"FEHLER PARENT-MISSING {rel(path)} parent={parent_str!r} nicht gefunden"))

# -----------------------------------------------------------------------
# AC7 — DEPENDS-UNRESOLVED / DEPENDS-CYCLE
# -----------------------------------------------------------------------

def get_depends_list(data):
    """Gibt normalisierte depends-Liste zurueck (dedupliziert, Strings)."""
    deps = data.get("depends")
    if deps is None:
        return []
    if not isinstance(deps, list):
        deps = [deps]
    seen = set()
    result = []
    for d in deps:
        ds = str(d).strip()
        if ds and ds not in seen:
            seen.add(ds)
            result.append(ds)
    return result

# Features
for fid, entry in features.items():
    data = entry["data"]
    path = entry["path"]
    deps = get_depends_list(data)
    for dep in deps:
        # Selbstreferenz
        if dep == fid:
            messages.append((rel(path), f"FEHLER DEPENDS-CYCLE {rel(path)} depends[]={dep!r} (Selbstreferenz)"))
            continue
        # Falscher Typ: muss F-### sein
        if not ID_F.match(dep):
            messages.append((rel(path), f"FEHLER DEPENDS-UNRESOLVED {rel(path)} depends[]={dep!r} (kein F-###, muss Feature-ID sein)"))
            continue
        # Nicht vorhanden
        if dep not in features:
            messages.append((rel(path), f"FEHLER DEPENDS-UNRESOLVED {rel(path)} depends[]={dep!r} nicht gefunden"))

# Stories
for sid, entry in stories.items():
    data = entry["data"]
    path = entry["path"]
    deps = get_depends_list(data)
    for dep in deps:
        # Selbstreferenz
        if dep == sid:
            messages.append((rel(path), f"FEHLER DEPENDS-CYCLE {rel(path)} depends[]={dep!r} (Selbstreferenz)"))
            continue
        # Falscher Typ: darf nicht auf Feature zeigen
        if ID_F.match(dep):
            messages.append((rel(path), f"FEHLER DEPENDS-UNRESOLVED {rel(path)} depends[]={dep!r} (Feature-ID in Story-depends nicht erlaubt)"))
            continue
        if not ID_S.match(dep):
            messages.append((rel(path), f"FEHLER DEPENDS-UNRESOLVED {rel(path)} depends[]={dep!r} (kein S-###, muss Story-ID sein)"))
            continue
        if dep not in stories:
            messages.append((rel(path), f"FEHLER DEPENDS-UNRESOLVED {rel(path)} depends[]={dep!r} nicht gefunden"))

# Zyklus-Erkennung via DFS (getrennt fuer Features und Stories)
def detect_cycles(graph, all_ids):
    """
    graph: dict id -> [dep_id, ...] (nur guelige IDs im selben Graph)
    Gibt Liste von (node, cycle_path_str) zurueck.
    """
    WHITE, GRAY, BLACK = 0, 1, 2
    color = {i: WHITE for i in all_ids}
    found = []

    def dfs(node, stack):
        color[node] = GRAY
        stack.append(node)
        for nb in graph.get(node, []):
            if nb not in color:
                continue
            if color[nb] == GRAY:
                # Zyklus gefunden — Pfad ab nb
                idx = stack.index(nb)
                cycle = stack[idx:] + [nb]
                found.append((node, " -> ".join(cycle)))
            elif color[nb] == WHITE:
                dfs(nb, stack)
        stack.pop()
        color[node] = BLACK

    for node in sorted(all_ids):
        if color[node] == WHITE:
            dfs(node, [])
    return found

# Feature-Zyklus-Graph (nur guelige F-IDs, keine Selbstrefs, keine missing)
f_graph = {}
for fid, entry in features.items():
    deps = get_depends_list(entry["data"])
    f_graph[fid] = [d for d in deps if d in features and d != fid]

for node, cycle_str in detect_cycles(f_graph, set(features.keys())):
    path = features[node]["path"]
    messages.append((rel(path), f"FEHLER DEPENDS-CYCLE {rel(path)} Zyklus: {cycle_str}"))

# Story-Zyklus-Graph
s_graph = {}
for sid, entry in stories.items():
    deps = get_depends_list(entry["data"])
    s_graph[sid] = [d for d in deps if d in stories and d != sid]

for node, cycle_str in detect_cycles(s_graph, set(stories.keys())):
    path = stories[node]["path"]
    messages.append((rel(path), f"FEHLER DEPENDS-CYCLE {rel(path)} Zyklus: {cycle_str}"))

# -----------------------------------------------------------------------
# AC8 — SPEC-MISSING / AC-MISSING
# -----------------------------------------------------------------------
# Alle Spec-Dateien cachen (AC-Tokens je Spec)
spec_ac_cache = {}  # spec_path -> set of "ACn" strings (or None if missing)
AC_IN_SPEC = re.compile(r"\bAC(\d+)\b")

def get_spec_acs(spec_rel_path):
    """Gibt Set der AC-Tokens in der Spec zurueck, oder None wenn Datei fehlt."""
    if spec_rel_path in spec_ac_cache:
        return spec_ac_cache[spec_rel_path]
    abs_path = os.path.join(repo_root, spec_rel_path)
    if not os.path.isfile(abs_path):
        spec_ac_cache[spec_rel_path] = None
        return None
    try:
        with open(abs_path, encoding="utf-8", errors="replace") as f:
            content = f.read()
        acs = {"AC" + m.group(1) for m in AC_IN_SPEC.finditer(content)}
        spec_ac_cache[spec_rel_path] = acs
        return acs
    except Exception:
        spec_ac_cache[spec_rel_path] = None
        return None

for sid, entry in stories.items():
    data = entry["data"]
    path = entry["path"]
    spec_val = data.get("spec")
    if spec_val is None or str(spec_val).strip() == "":
        # Bereits FIELD-REQUIRED; hier ueberspringen
        continue
    spec_rel = str(spec_val).strip()
    acs = get_spec_acs(spec_rel)
    if acs is None:
        messages.append((rel(path), f"FEHLER SPEC-MISSING {rel(path)} spec={spec_rel!r}"))
        continue
    # Jede implements[]-AC muss in der Spec vorkommen
    impls = data.get("implements")
    if not isinstance(impls, list):
        continue
    for ac in impls:
        ac_str = str(ac).strip()
        if not AC_TOK.match(ac_str):
            continue  # Format-Fehler wird von ENUM-INVALID abgedeckt
        if ac_str not in acs:
            messages.append((rel(path), f"FEHLER AC-MISSING {rel(path)} implements[]={ac_str!r} nicht in {spec_rel!r}"))

# -----------------------------------------------------------------------
# SPEC-STATUS-INVALID — Frontmatter status: einer referenzierten, existierenden
# Spec-Datei ausserhalb {draft, active, superseded}
# (Spec docs/specs/spec-status-lifecycle.md AC4)
# -----------------------------------------------------------------------
VALID_SPEC_STATUS = {"draft", "active", "superseded"}
FRONTMATTER_BLOCK = re.compile(r"^---\s*\n(.*?)\n---\s*\n", re.DOTALL)
FRONTMATTER_STATUS = re.compile(r"^status:\s*(.+?)\s*$", re.MULTILINE)

spec_status_cache = {}  # spec_path -> status string or None (kein Frontmatter/status)

def get_spec_status(spec_rel_path):
    """Liest den Frontmatter-status:-Wert einer Spec-Datei (erster Frontmatter-Block).
    Gibt None zurueck, wenn die Datei fehlt oder keinen status-Schluessel traegt."""
    if spec_rel_path in spec_status_cache:
        return spec_status_cache[spec_rel_path]
    abs_path = os.path.join(repo_root, spec_rel_path)
    if not os.path.isfile(abs_path):
        spec_status_cache[spec_rel_path] = None
        return None
    try:
        with open(abs_path, encoding="utf-8", errors="replace") as f:
            content = f.read()
    except Exception:
        spec_status_cache[spec_rel_path] = None
        return None
    fm_match = FRONTMATTER_BLOCK.match(content)
    if not fm_match:
        spec_status_cache[spec_rel_path] = None
        return None
    status_match = FRONTMATTER_STATUS.search(fm_match.group(1))
    if not status_match:
        spec_status_cache[spec_rel_path] = None
        return None
    # Trailing YAML-Inline-Kommentar (z.B. "active   # in Kraft") abtrennen,
    # bevor der Wert gegen das Enum geprueft wird (coder/L25).
    status_val = status_match.group(1).split("#", 1)[0].strip()
    spec_status_cache[spec_rel_path] = status_val
    return status_val

reported_spec_status = set()  # Dedup: ein Befund je referenzierter Spec-Datei
for sid, entry in stories.items():
    data = entry["data"]
    path = entry["path"]
    spec_val = data.get("spec")
    if spec_val is None or str(spec_val).strip() == "":
        continue
    spec_rel = str(spec_val).strip()
    abs_path = os.path.join(repo_root, spec_rel)
    if not os.path.isfile(abs_path):
        # Fehlende Spec-Datei -> bereits als SPEC-MISSING gemeldet, keine Doppelmeldung
        continue
    if spec_rel in reported_spec_status:
        continue
    status_val = get_spec_status(spec_rel)
    if status_val is not None and status_val not in VALID_SPEC_STATUS:
        reported_spec_status.add(spec_rel)
        messages.append((rel(path), f"FEHLER SPEC-STATUS-INVALID {spec_rel} status={status_val}"))

# -----------------------------------------------------------------------
# AC10 — ROLLUP-STALE: abgeleitete Felder stories[]/progress veraltet (WARN)
# -----------------------------------------------------------------------
# Tatsaechliche Kind-Stories je Feature berechnen
children_of = {fid: [] for fid in features}
for sid, entry in stories.items():
    data = entry["data"]
    parent = data.get("parent")
    if parent and str(parent).strip() in children_of:
        children_of[str(parent).strip()].append(sid)

for fid, entry in features.items():
    data = entry["data"]
    path = entry["path"]
    expected_children = sorted(children_of[fid])

    # stories[]
    stored_stories = data.get("stories")
    if stored_stories is not None:
        if isinstance(stored_stories, list):
            stored_sorted = sorted(str(s).strip() for s in stored_stories if str(s).strip())
        else:
            stored_sorted = [str(stored_stories).strip()]
        if stored_sorted != expected_children:
            messages.append((rel(path), f"WARN ROLLUP-STALE {rel(path)} stories[] veraltet (gespeichert={stored_sorted!r}, erwartet={expected_children!r})"))

    # progress — Konsistenz-Check: einfache Heuristik
    # progress korrekt = "<done>/<total> done ..." basierend auf Kind-Status
    progress_val = data.get("progress")
    total = len(expected_children)
    if total > 0 and (progress_val is None or str(progress_val).strip() == ""):
        # Kind-Stories vorhanden, aber progress ist null/leer → ROLLUP-STALE
        done_count = sum(
            1 for sid in expected_children
            if stories.get(sid, {}).get("data", {}).get("status") == "Done"
        )
        expected_prefix = f"{done_count}/{total} done"
        messages.append((rel(path), f"WARN ROLLUP-STALE {rel(path)} progress null (erwartet '{expected_prefix}')"))
    elif progress_val is not None and str(progress_val).strip() != "":
        # Berechne erwarteten Zaehler
        done_count = sum(
            1 for sid in expected_children
            if stories.get(sid, {}).get("data", {}).get("status") == "Done"
        )
        # Erwartetes Muster: "<done>/<total> done"
        expected_prefix = f"{done_count}/{total} done"
        prog_str = str(progress_val).strip()
        if not prog_str.startswith(expected_prefix):
            messages.append((rel(path), f"WARN ROLLUP-STALE {rel(path)} progress veraltet (gespeichert={prog_str!r}, erwartet beginnt mit {expected_prefix!r})"))

# -----------------------------------------------------------------------
# Ausgabe (deterministisch: sortiert nach Dateipfad, dann Zeileninhalt)
# -----------------------------------------------------------------------
for _, line in sorted(messages):
    print(line)
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

# 4. Integritaetspruefung: AC5, AC6, AC7, AC8, AC10
# Nur ausfuehren wenn board.yaml vorhanden (sonst fehlt der Board-Kontext)
if [[ -f "$BOARD_YAML" ]]; then
  # Repo-Wurzel: Verzeichnis eine Ebene ueber BOARD_DIR (fuer Spec-Pfade)
  REPO_ROOT="$(cd "${BOARD_DIR}/.." 2>/dev/null && pwd)"
  mapfile -t integrity_errors < <(lint_integrity "${BOARD_DIR}" "${REPO_ROOT}" 2>/dev/null || true)
  for line in "${integrity_errors[@]}"; do
    echo "$line"
    if [[ "$line" == FEHLER* ]]; then
      ERRORS=$(( ERRORS + 1 ))
    fi
  done
fi

# Exit-Code
if [[ $ERRORS -gt 0 ]]; then
  EXIT_CODE=1
fi

exit $EXIT_CODE
