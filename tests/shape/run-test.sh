#!/usr/bin/env bash
# tests/shape/run-test.sh
#
# Fidelity-Test-Gate für scripts/shape (S-068, docs/specs/shape-wrapper-implementation.md
# AC3/AC4; Bauplan docs/architecture/output-shaping-classA-filter.md §6).
#
# Drei Suiten, alle müssen grün sein (Exit 0), sonst Exit 1 — kein Rollout:
#
#   Suite 1 (HARTES Gate, Null-Toleranz) — Byte-Identität stdout + gleicher
#     Exit-Code für `shape <cmd>` vs. bare bei Klasse-B/C-Befehlen (git diff,
#     git show, Test-Fail-Log, Lint-Verstoß, curl-Verbatim) PLUS die zwei
#     Fail-open-Zusatzfälle (Shell-Metazeichen im argv, find -exec).
#   Suite 2 — Transform-Korrektheit für Klasse-A-Befehle: Dedup-Counts exakt,
#     Truncation-Marker korrekt, behaltene Zeilen byte-identisch, Exit-Code
#     erhalten, keine Zeile ohne Count/Marker fallengelassen.
#   Suite 3 — Fail-open/Robustheit bei malformter/binärer/sehr großer Ausgabe:
#     nie leer, nie marker-los abgeschnitten.
#
# Selbst-enthalten: kein Netz, kein realer Toolchain. `pytest`/`eslint`/`curl`
# werden über einen mockbin-PATH-Prefix simuliert (nur die stdout-Fixtures
# ausgeben); git/ls/find/grep sind die echten System-Binaries mit selbst
# angelegten Fixture-Verzeichnissen/-Repos. Berührt nie das echte Repo.
#
# Exit: 0 = alle Tests bestanden, 1 = mindestens ein Fehler

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SHAPE_SCRIPT="${REPO_ROOT}/scripts/shape"
FIXTURES_DIR="${SCRIPT_DIR}/fixtures"

TEST_WORK_DIR="$(mktemp -d /tmp/shape-test.XXXXXX)"
trap 'rm -rf "$TEST_WORK_DIR"' EXIT

FAIL=0
PASS=0
fail() { echo "FAIL: $*" >&2; FAIL=$((FAIL + 1)); }
pass() { echo "PASS: $*"; PASS=$((PASS + 1)); }

export GIT_AUTHOR_NAME="test" GIT_AUTHOR_EMAIL="test@test.local"
export GIT_COMMITTER_NAME="test" GIT_COMMITTER_EMAIL="test@test.local"

# ─── Mockbin: pytest/eslint/curl — reine stdout-Fixture-Ausgabe, kein realer
#     Toolchain nötig (self-contained, Design §6) ─────────────────────────
MOCK_BIN_DIR="${TEST_WORK_DIR}/mockbin"
mkdir -p "$MOCK_BIN_DIR"

cat > "${MOCK_BIN_DIR}/pytest" <<MOCKEOF
#!/usr/bin/env bash
cat "${FIXTURES_DIR}/pytest-fail.log"
exit 1
MOCKEOF
cat > "${MOCK_BIN_DIR}/eslint" <<MOCKEOF
#!/usr/bin/env bash
cat "${FIXTURES_DIR}/lint-violations.txt"
exit 1
MOCKEOF
cat > "${MOCK_BIN_DIR}/curl" <<MOCKEOF
#!/usr/bin/env bash
cat "${FIXTURES_DIR}/curl-verbatim.txt"
exit 0
MOCKEOF
chmod +x "${MOCK_BIN_DIR}/pytest" "${MOCK_BIN_DIR}/eslint" "${MOCK_BIN_DIR}/curl"
export PATH="${MOCK_BIN_DIR}:${PATH}"

# ─── Fixture-Git-Repo (winzig, vom Test selbst angelegt) ───────────────────
GIT_FIXTURE="${TEST_WORK_DIR}/git-fixture"
mkdir -p "$GIT_FIXTURE"
(
  cd "$GIT_FIXTURE"
  git init -q
  printf 'line one\nline two\nline three\n' > widget.txt
  git add -A
  git commit -q -m "initial commit"
  printf 'line one\nline TWO-changed\nline three\nline four\n' > widget.txt
)

# ─── Helfer: bare vs. shape vergleichen (nur stdout + Exit-Code, AC3) ──────
# Nutzung: compare_fidelity "<label>" <cmd> [args...]
compare_fidelity() {
  local label="$1"
  shift
  local bare_out shape_out bare_exit shape_exit
  bare_out="$(mktemp "${TEST_WORK_DIR}/bare_out.XXXXXX")"
  shape_out="$(mktemp "${TEST_WORK_DIR}/shape_out.XXXXXX")"

  "$@" > "$bare_out" 2>/dev/null
  bare_exit=$?
  "$SHAPE_SCRIPT" "$@" > "$shape_out" 2>/dev/null
  shape_exit=$?

  if cmp -s "$bare_out" "$shape_out" && [[ "$bare_exit" == "$shape_exit" ]]; then
    pass "$label"
  else
    fail "$label (bare_exit=$bare_exit shape_exit=$shape_exit)"
    echo "  --- bare ---"; cat "$bare_out" | head -5
    echo "  --- shape ---"; cat "$shape_out" | head -5
  fi
  rm -f "$bare_out" "$shape_out"
}

# ===========================================================================
# Suite 1 — Pass-Through-Fidelity (HARTES Gate, Null-Toleranz)
# ===========================================================================
echo ""
echo "=== Suite 1: Pass-Through-Fidelity (Klasse B/C, Null-Toleranz) ==="

(
  cd "$GIT_FIXTURE"
  compare_fidelity "git diff (uncommitted change) — byte-identisch" git diff
  compare_fidelity "git show HEAD — byte-identisch" git show HEAD
)

compare_fidelity "pytest-Fail-Log-Fixture — byte-identisch" pytest
compare_fidelity "eslint-Lint-Verstoß-Fixture — byte-identisch" eslint
compare_fidelity "curl-Verbatim-Fixture — byte-identisch" curl

# git-Subcommand-Check: nur status/log sind Klasse A, alles andere git roh.
(
  cd "$GIT_FIXTURE"
  compare_fidelity "git blame widget.txt — roh (nicht status/log)" git blame widget.txt
  compare_fidelity "git log --oneline — Klasse A, aber ohne Dedup/Truncation trivial byte-identisch" git log --oneline
)

# Andere Allowlist-Köpfe mit nicht-gelistetem Subcommand -> roh (funktioniert
# unabhängig davon, ob docker/npm im Environment installiert sind: fehlen sie,
# scheitern bare und shape identisch mit "command not found").
compare_fidelity "docker version — roh (nicht ps/images)" docker version
compare_fidelity "npm --version — roh (nicht ls)" npm --version

# Zusatzfall (i) — Shell-Metazeichen im argv: kein sh -c, fail-open, direkter
# argv-Exec (Programmname wörtlich "ls && git diff" existiert nicht -> beide
# Seiten scheitern identisch mit leerem stdout + Exit 127).
METACHAR_CMD="ls && git diff"
BARE_META_OUT="$(mktemp "${TEST_WORK_DIR}/bare_meta.XXXXXX")"
SHAPE_META_OUT="$(mktemp "${TEST_WORK_DIR}/shape_meta.XXXXXX")"
"$METACHAR_CMD" > "$BARE_META_OUT" 2>/dev/null
BARE_META_EXIT=$?
"$SHAPE_SCRIPT" "$METACHAR_CMD" > "$SHAPE_META_OUT" 2>/dev/null
SHAPE_META_EXIT=$?
if cmp -s "$BARE_META_OUT" "$SHAPE_META_OUT" && [[ "$BARE_META_EXIT" == "$SHAPE_META_EXIT" ]]; then
  pass "shape 'ls && git diff' — byte-identisch zu bare (Fail-open bei Metazeichen)"
else
  fail "shape 'ls && git diff' — nicht byte-identisch (bare_exit=$BARE_META_EXIT shape_exit=$SHAPE_META_EXIT)"
fi
rm -f "$BARE_META_OUT" "$SHAPE_META_OUT"

# Zusatzfall (ii) — find -exec: programm-startendes Flag -> fail-open,
# direkter argv-Exec des echten find-Aufrufs (real ausgeführt, kein Shell).
EXEC_TEST_DIR="${TEST_WORK_DIR}/exec-test-dir"
mkdir -p "$EXEC_TEST_DIR"
printf 'file-a-content\n' > "${EXEC_TEST_DIR}/a.txt"
printf 'file-b-content\n' > "${EXEC_TEST_DIR}/b.txt"
(
  cd "$EXEC_TEST_DIR"
  compare_fidelity "shape find . -exec cat {} + — byte-identisch zu bare" find . -type f -exec cat {} +
)

# ===========================================================================
# Suite 2 — Transform-Korrektheit (Klasse A)
# ===========================================================================
echo ""
echo "=== Suite 2: Transform-Korrektheit (Klasse A) ==="

# 2a — Dedup: exakte Counts, Summe = Original-Zeilenzahl, byte-identische
# behaltene Zeilen, keine Umsortierung.
DEDUP_ACTUAL="$("$SHAPE_SCRIPT" grep . "${FIXTURES_DIR}/dedup-input.txt")"
DEDUP_EXPECTED="alpha (×3)
beta (×2)
gamma
delta (×4)"
if [[ "$DEDUP_ACTUAL" == "$DEDUP_EXPECTED" ]]; then
  pass "Dedup: Counts exakt, Reihenfolge erhalten, byte-identische Zeilen"
else
  fail "Dedup: Ausgabe weicht ab"
  echo "  erwartet: $DEDUP_EXPECTED"
  echo "  erhalten: $DEDUP_ACTUAL"
fi

ORIG_LINE_COUNT=$(wc -l < "${FIXTURES_DIR}/dedup-input.txt" | tr -d ' ')
SUM_COUNTS=$(echo "$DEDUP_ACTUAL" | grep -o '×[0-9]*' | tr -d '×' | awk '{s+=$1} END {print s}')
SINGLE_LINES=$(echo "$DEDUP_ACTUAL" | grep -vc '×')
SUM_TOTAL=$((SUM_COUNTS + SINGLE_LINES))
if [[ "$SUM_TOTAL" == "$ORIG_LINE_COUNT" ]]; then
  pass "Dedup: Summe aller Counts ($SUM_TOTAL) = Original-Zeilenzahl ($ORIG_LINE_COUNT) — keine Zeile fallengelassen"
else
  fail "Dedup: Summe ($SUM_TOTAL) != Original-Zeilenzahl ($ORIG_LINE_COUNT)"
fi

# 2b — Truncation: 250 eindeutig benannte Dateien (kein Dedup-Effekt),
# Kopf+Fuß erhalten, Marker nennt korrekte ausgelassene Zeilenzahl.
TRUNC_DIR="${TEST_WORK_DIR}/trunc-dir"
mkdir -p "$TRUNC_DIR"
for i in $(seq -w 1 250); do
  touch "${TRUNC_DIR}/file${i}.txt"
done
BARE_LS="$(ls "$TRUNC_DIR")"
SHAPED_LS="$("$SHAPE_SCRIPT" ls "$TRUNC_DIR")"

BARE_LS_COUNT=$(echo "$BARE_LS" | wc -l | tr -d ' ')
BARE_HEAD_100="$(echo "$BARE_LS" | head -100)"
BARE_TAIL_100="$(echo "$BARE_LS" | tail -100)"
SHAPED_HEAD_100="$(echo "$SHAPED_LS" | head -100)"
SHAPED_TAIL_100="$(echo "$SHAPED_LS" | tail -100)"
MARKER_LINE="$(echo "$SHAPED_LS" | sed -n '101p')"
EXPECTED_MARKER="[… 50 Zeilen ausgelassen (gesamt ${BARE_LS_COUNT}) …]"

if [[ "$SHAPED_HEAD_100" == "$BARE_HEAD_100" ]]; then
  pass "Truncation: Kopf (100 Zeilen) byte-identisch zur bare-Ausgabe"
else
  fail "Truncation: Kopf weicht ab"
fi
if [[ "$SHAPED_TAIL_100" == "$BARE_TAIL_100" ]]; then
  pass "Truncation: Fuß (100 Zeilen) byte-identisch zur bare-Ausgabe"
else
  fail "Truncation: Fuß weicht ab"
fi
if [[ "$MARKER_LINE" == "$EXPECTED_MARKER" ]]; then
  pass "Truncation: Marker nennt korrekte ausgelassene Zeilenzahl ($EXPECTED_MARKER)"
else
  fail "Truncation: Marker falsch — erwartet '$EXPECTED_MARKER', erhalten '$MARKER_LINE'"
fi
SHAPED_LS_LINE_COUNT=$(echo "$SHAPED_LS" | wc -l | tr -d ' ')
if [[ "$SHAPED_LS_LINE_COUNT" == "201" ]]; then
  pass "Truncation: 201 Zeilen (100 Kopf + 1 Marker + 100 Fuß)"
else
  fail "Truncation: erwartet 201 Zeilen, erhalten $SHAPED_LS_LINE_COUNT"
fi

# 2c — Exit-Code erhalten (auch im Fehlerfall eines Klasse-A-Befehls).
grep "NONEXISTENT-STRING-XYZ" "${FIXTURES_DIR}/dedup-input.txt" > /dev/null 2>&1
BARE_GREP_EXIT=$?
"$SHAPE_SCRIPT" grep "NONEXISTENT-STRING-XYZ" "${FIXTURES_DIR}/dedup-input.txt" > /dev/null 2>&1
SHAPE_GREP_EXIT=$?
if [[ "$BARE_GREP_EXIT" == "$SHAPE_GREP_EXIT" ]]; then
  pass "Exit-Code eines fehlschlagenden Klasse-A-Befehls (grep ohne Treffer) erhalten ($SHAPE_GREP_EXIT)"
else
  fail "Exit-Code weicht ab (bare=$BARE_GREP_EXIT shape=$SHAPE_GREP_EXIT)"
fi

# ===========================================================================
# Suite 3 — Fail-open/Robustheit
# ===========================================================================
echo ""
echo "=== Suite 3: Fail-open/Robustheit ==="

# 3a — binäre/NUL-haltige Ausgabe: Byte-Identität shape vs. bare (NICHT nur
# "nicht leer"!) — `$(...)`-Command-Substitution kann selbst keine NUL-Bytes
# halten (C-String-Limit von bash), deshalb hier bewusst datei-basiert via
# compare_fidelity (das prüft cmp auf echten Dateien, nicht auf Variablen).
# Belegt Review-Fund Iteration 1: awk (insb. BSD/macOS one-true-awk) kappt
# Zeilen sonst am ersten NUL-Byte -> stille Korruption, E1-Verstoß.
BINARY_FIXTURE="${TEST_WORK_DIR}/binary-sample.bin"
printf 'plain line one\n\x00\x01\x02binary-noise\xff\xfe\nplain line two\n' > "$BINARY_FIXTURE"
compare_fidelity "Binäre/NUL-haltige Ausgabe (grep -a) — byte-identisch zu bare (kein stiller NUL-Drop)" grep -a . "$BINARY_FIXTURE"

# 3a2 — zweiter, reiner NUL-Fixture (keine druckbaren Zeichen drumherum) für
# zusätzliche Sicherheit gegen den awk-Kappungs-Bug.
PURE_NUL_FIXTURE="${TEST_WORK_DIR}/pure-nul.bin"
printf 'line-a\n\x00\x00\x00\nline-b\n\x00\nline-c\n' > "$PURE_NUL_FIXTURE"
compare_fidelity "Reiner NUL-Byte-Fixture (grep -a) — byte-identisch zu bare" grep -a . "$PURE_NUL_FIXTURE"

# Exit-Code + Nie-Crash trotzdem explizit prüfen (datei-basiert).
BIN_SHAPE_OUT="$(mktemp "${TEST_WORK_DIR}/bin_shape_out.XXXXXX")"
"$SHAPE_SCRIPT" grep -a . "$BINARY_FIXTURE" > "$BIN_SHAPE_OUT" 2>/dev/null
SHAPE_BIN_EXIT=$?
if [[ -s "$BIN_SHAPE_OUT" ]]; then
  pass "Binäre Ausgabe: shape liefert nie-leere Ausgabe (kein stiller Drop)"
else
  fail "Binäre Ausgabe: shape lieferte leere Ausgabe"
fi
if [[ "$SHAPE_BIN_EXIT" -eq 0 ]]; then
  pass "Binäre Ausgabe: shape crasht nicht (Exit 0)"
else
  fail "Binäre Ausgabe: unerwarteter Exit-Code $SHAPE_BIN_EXIT"
fi
rm -f "$BIN_SHAPE_OUT"

# 3b — sehr große Ausgabe (3000 eindeutige Zeilen): nie leer, Marker vorhanden.
BIG_FIXTURE="${TEST_WORK_DIR}/big-input.txt"
awk 'BEGIN { for (i = 1; i <= 3000; i++) print "line" i }' > "$BIG_FIXTURE"
SHAPE_BIG_OUT="$("$SHAPE_SCRIPT" grep line "$BIG_FIXTURE")"
SHAPE_BIG_EXIT=$?
if [[ -n "$SHAPE_BIG_OUT" ]]; then
  pass "Sehr große Ausgabe (3000 Zeilen): shape liefert nie-leere Ausgabe"
else
  fail "Sehr große Ausgabe: shape lieferte leere Ausgabe"
fi
if echo "$SHAPE_BIG_OUT" | grep -q "Zeilen ausgelassen (gesamt 3000)"; then
  pass "Sehr große Ausgabe: Truncation-Marker mit korrekter Gesamtzahl (3000) vorhanden"
else
  fail "Sehr große Ausgabe: Truncation-Marker fehlt oder falsch"
fi
if [[ "$SHAPE_BIG_EXIT" -eq 0 ]]; then
  pass "Sehr große Ausgabe: Exit-Code erhalten (0)"
else
  fail "Sehr große Ausgabe: unerwarteter Exit-Code $SHAPE_BIG_EXIT"
fi

# 3c — leere stdout eines Klasse-A-Befehls: kein Crash, kein sinnloser Marker.
EMPTY_DIR="${TEST_WORK_DIR}/empty-dir"
mkdir -p "$EMPTY_DIR"
SHAPE_EMPTY_OUT="$("$SHAPE_SCRIPT" find "$EMPTY_DIR" -mindepth 1 -type f 2>/dev/null)"
SHAPE_EMPTY_EXIT=$?
if [[ -z "$SHAPE_EMPTY_OUT" && "$SHAPE_EMPTY_EXIT" -eq 0 ]]; then
  pass "Leere Klasse-A-Ausgabe: kein Crash, kein Fantom-Marker"
else
  fail "Leere Klasse-A-Ausgabe: unerwartet (exit=$SHAPE_EMPTY_EXIT, out='$SHAPE_EMPTY_OUT')"
fi

# ===========================================================================
# Ergebnis
# ===========================================================================
echo ""
echo "=============================="
echo "Ergebnis: ${PASS} PASS, ${FAIL} FAIL"
echo "=============================="

if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
exit 0
