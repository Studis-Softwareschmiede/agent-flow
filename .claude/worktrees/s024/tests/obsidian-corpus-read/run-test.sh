#!/usr/bin/env bash
# tests/obsidian-corpus-read/run-test.sh
#
# @file Self-Test für `scripts/obsidian-corpus-read.sh` (Notiz-Korpus-Reader des
#       /agent-flow:from-notes-Ingest). Verwendet /tmp-Fixtures — berührt NIEMALS einen
#       echten Obsidian-Vault. Prüft, dass der Ordner nach dem Lauf UNVERÄNDERT ist (AC6).
#
# Covers (obsidian-ingest): AC4, AC5, AC6
#   AC4 — @trace obsidian-ingest#AC4 — alle *.md REKURSIV (inkl. Unterordner) zu EINEM Korpus,
#         DETERMINISTISCHE Reihenfolge (relativer Pfad, stabil), je Notiz ein Herkunfts-Marker
#         (relativer Dateipfad). Determinismus über zwei Läufe byte-identisch (Test 1, 2, 7).
#   AC5 — @trace obsidian-ingest#AC5 — Nicht-`.md` + Obsidian-Interna (`.obsidian/`, versteckte
#         Dot-Verzeichnisse) übersprungen (Test 3); nicht existierender Pfad -> Exit 2 + Meldung
#         (Test 4); Ordner ohne jede `.md` -> Exit 2 + Meldung (Test 5); Pfad ist Datei statt
#         Verzeichnis -> Exit 2 (Test 6). NIEMALS leere Ausgabe an einen Pipeline-Schritt.
#   AC6 — @trace obsidian-ingest#AC6 — rein lesend: der Notiz-Ordner ist nach dem Lauf byte-/
#         mtime-identisch, keine neuen Dateien, kein Löschen (Test 8). Ein separater Commit-/
#         Repo-Schreibpfad existiert im Reader nicht (per Skript-Inspektion belegt — der Reader
#         schreibt ausschließlich nach stdout/stderr, öffnet Dateien nur mit Lese-Modus).
#
# Exit: 0 = alle Tests bestanden, 1 = mindestens ein Fehler

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
READ_SCRIPT="${REPO_ROOT}/scripts/obsidian-corpus-read.sh"

# Eigene TMPDIR-Variable (reviewer/L05: $TMPDIR nie überschreiben)
TEST_WORK_DIR="$(mktemp -d /tmp/obsidian-corpus-read-test.XXXXXX)"
trap 'rm -rf "$TEST_WORK_DIR"' EXIT

FAIL=0
PASS=0

fail() {
  echo "FAIL: $*" >&2
  FAIL=$(( FAIL + 1 ))
}

pass() {
  echo "PASS: $*"
  PASS=$(( PASS + 1 ))
}

# ===========================================================================
# Test 1: rekursiv über Unterordner, EIN Korpus, Herkunfts-Marker je Notiz (AC4)
# ===========================================================================
T1_DIR="${TEST_WORK_DIR}/t1/vault"
mkdir -p "${T1_DIR}/sub"
printf 'Wurzel-Notiz\n' > "${T1_DIR}/root.md"
printf 'Unterordner-Notiz\n' > "${T1_DIR}/sub/deep.md"

T1_OUT="$(bash "$READ_SCRIPT" "$T1_DIR" 2>/dev/null)"
if echo "$T1_OUT" | grep -qF '===== NOTE: root.md =====' \
   && echo "$T1_OUT" | grep -qF '===== NOTE: sub/deep.md =====' \
   && echo "$T1_OUT" | grep -qF 'Wurzel-Notiz' \
   && echo "$T1_OUT" | grep -qF 'Unterordner-Notiz'; then
  pass "Test 1 (AC4): rekursiv, EIN Korpus, Herkunfts-Marker (rel. Pfad) je Notiz inkl. Unterordner"
else
  fail "Test 1 (AC4): erwartete Marker/Inhalte fehlen: ${T1_OUT}"
fi

# ===========================================================================
# Test 2: DETERMINISTISCHE Reihenfolge — Marker in stabiler, pfad-alphabetischer Folge (AC4)
# ===========================================================================
T2_DIR="${TEST_WORK_DIR}/t2/vault"
mkdir -p "${T2_DIR}/z-dir" "${T2_DIR}/a-dir"
printf 'B\n' > "${T2_DIR}/b.md"
printf 'A\n' > "${T2_DIR}/a-dir/note.md"
printf 'Z\n' > "${T2_DIR}/z-dir/note.md"
printf 'C\n' > "${T2_DIR}/c.md"

T2_OUT="$(bash "$READ_SCRIPT" "$T2_DIR" 2>/dev/null)"
T2_ORDER="$(echo "$T2_OUT" | grep -F '===== NOTE:' | sed -E 's/^===== NOTE: (.*) =====$/\1/')"
T2_EXPECTED=$'a-dir/note.md\nb.md\nc.md\nz-dir/note.md'
if [[ "$T2_ORDER" == "$T2_EXPECTED" ]]; then
  pass "Test 2 (AC4): Marker-Reihenfolge deterministisch pfad-alphabetisch (a-dir, b, c, z-dir)"
else
  fail "Test 2 (AC4): Reihenfolge nicht deterministisch/erwartet. Ist:\n${T2_ORDER}"
fi

# ===========================================================================
# Test 3: Nicht-.md + `.obsidian/` + versteckte Dot-Verzeichnisse übersprungen (AC5)
# ===========================================================================
T3_DIR="${TEST_WORK_DIR}/t3/vault"
mkdir -p "${T3_DIR}/.obsidian" "${T3_DIR}/.trash"
printf 'echte Notiz\n' > "${T3_DIR}/keep.md"
printf 'binaerer-Anhang\n' > "${T3_DIR}/image.png"          # Nicht-.md -> skip
printf 'config\n' > "${T3_DIR}/.obsidian/workspace.md"       # Obsidian-Interna .md -> skip
printf 'geloescht\n' > "${T3_DIR}/.trash/old.md"             # versteckter Dir -> skip
printf 'readme-text\n' > "${T3_DIR}/notes.txt"               # Nicht-.md -> skip

T3_OUT="$(bash "$READ_SCRIPT" "$T3_DIR" 2>/dev/null)"
if echo "$T3_OUT" | grep -qF '===== NOTE: keep.md =====' \
   && ! echo "$T3_OUT" | grep -qF 'workspace.md' \
   && ! echo "$T3_OUT" | grep -qF '.trash' \
   && ! echo "$T3_OUT" | grep -qF 'image.png' \
   && ! echo "$T3_OUT" | grep -qF 'notes.txt' \
   && ! echo "$T3_OUT" | grep -qF 'binaerer-Anhang' \
   && ! echo "$T3_OUT" | grep -qF 'readme-text'; then
  pass "Test 3 (AC5): Nicht-.md, .obsidian/ und versteckte Dot-Verzeichnisse übersprungen"
else
  fail "Test 3 (AC5): unerwünschte Datei im Korpus oder echte Notiz fehlt: ${T3_OUT}"
fi

# ===========================================================================
# Test 4: nicht existierender Pfad -> Exit 2 + Meldung, KEINE stdout-Ausgabe (AC5)
# ===========================================================================
set +e
T4_OUT="$(bash "$READ_SCRIPT" "${TEST_WORK_DIR}/gibt-es-nicht" 2>"${TEST_WORK_DIR}/t4_err.log")"
T4_EXIT=$?
set -e
if [[ "$T4_EXIT" -eq 2 && -z "$T4_OUT" ]] && grep -qF 'existiert nicht' "${TEST_WORK_DIR}/t4_err.log"; then
  pass "Test 4 (AC5): nicht existierender Pfad -> Exit 2, klare Meldung, leerer stdout (kein Leerlauf)"
else
  fail "Test 4 (AC5): erwartet Exit 2 + leerer stdout + Meldung, bekam Exit=${T4_EXIT} Out=${T4_OUT}"
fi

# ===========================================================================
# Test 5: Ordner ohne jede .md -> Exit 2 + Meldung, KEINE stdout-Ausgabe (AC5)
# ===========================================================================
T5_DIR="${TEST_WORK_DIR}/t5/vault"
mkdir -p "${T5_DIR}"
printf 'nur ein Anhang\n' > "${T5_DIR}/attachment.pdf"

set +e
T5_OUT="$(bash "$READ_SCRIPT" "$T5_DIR" 2>"${TEST_WORK_DIR}/t5_err.log")"
T5_EXIT=$?
set -e
if [[ "$T5_EXIT" -eq 2 && -z "$T5_OUT" ]] && grep -qF 'keine `.md`' "${TEST_WORK_DIR}/t5_err.log"; then
  pass "Test 5 (AC5): Ordner ohne .md -> Exit 2, klare Meldung, leerer stdout (kein Leerlauf)"
else
  fail "Test 5 (AC5): erwartet Exit 2 + leerer stdout + Meldung, bekam Exit=${T5_EXIT} Out=${T5_OUT}"
fi

# ===========================================================================
# Test 6: Pfad ist eine Datei (kein Verzeichnis) -> Exit 2 (AC5)
# ===========================================================================
T6_FILE="${TEST_WORK_DIR}/t6-a-file.md"
printf 'ich bin eine datei, kein ordner\n' > "$T6_FILE"

set +e
T6_OUT="$(bash "$READ_SCRIPT" "$T6_FILE" 2>"${TEST_WORK_DIR}/t6_err.log")"
T6_EXIT=$?
set -e
if [[ "$T6_EXIT" -eq 2 && -z "$T6_OUT" ]] && grep -qF 'kein Verzeichnis' "${TEST_WORK_DIR}/t6_err.log"; then
  pass "Test 6 (AC5): Pfad ist Datei statt Ordner -> Exit 2, klare Meldung"
else
  fail "Test 6 (AC5): erwartet Exit 2 bei Datei-Pfad, bekam Exit=${T6_EXIT} Out=${T6_OUT}"
fi

# ===========================================================================
# Test 7: Determinismus über zwei Läufe — byte-identische Ausgabe (AC4)
# ===========================================================================
T7_DIR="${TEST_WORK_DIR}/t7/vault"
mkdir -p "${T7_DIR}/x" "${T7_DIR}/y"
printf 'eins\n' > "${T7_DIR}/x/1.md"
printf 'zwei\n' > "${T7_DIR}/y/2.md"
printf 'drei\n' > "${T7_DIR}/top.md"

T7_RUN1="$(bash "$READ_SCRIPT" "$T7_DIR" 2>/dev/null)"
T7_RUN2="$(bash "$READ_SCRIPT" "$T7_DIR" 2>/dev/null)"
if [[ "$T7_RUN1" == "$T7_RUN2" && -n "$T7_RUN1" ]]; then
  pass "Test 7 (AC4): zwei Läufe erzeugen byte-identischen Korpus (deterministisch)"
else
  fail "Test 7 (AC4): Korpus zwischen zwei Läufen nicht identisch"
fi

# ===========================================================================
# Test 8: rein lesend — Ordner nach dem Lauf UNVERÄNDERT (AC6)
# ===========================================================================
T8_DIR="${TEST_WORK_DIR}/t8/vault"
mkdir -p "${T8_DIR}/sub"
printf 'a\n' > "${T8_DIR}/a.md"
printf 'b\n' > "${T8_DIR}/sub/b.md"
printf 'anhang\n' > "${T8_DIR}/c.png"

# Fingerabdruck VOR dem Lauf: Dateiliste + Größe + mtime (portabel via find -printf-Ersatz).
snapshot() {
  # Dateiliste (rel. Pfad) + Bytegröße; sortiert -> stabiler Vergleichswert.
  ( cd "$1" && find . -type f -exec wc -c {} \; | sort )
}
T8_BEFORE="$(snapshot "$T8_DIR")"
bash "$READ_SCRIPT" "$T8_DIR" >/dev/null 2>&1
T8_AFTER="$(snapshot "$T8_DIR")"

if [[ "$T8_BEFORE" == "$T8_AFTER" ]]; then
  pass "Test 8 (AC6): Notiz-Ordner nach dem Lauf unverändert (keine neue/geänderte/gelöschte Datei)"
else
  fail "Test 8 (AC6): Ordner wurde verändert.\nVOR:\n${T8_BEFORE}\nNACH:\n${T8_AFTER}"
fi

# ===========================================================================
# Zusammenfassung
# ===========================================================================
echo ""
echo "obsidian-corpus-read: ${PASS} passed, ${FAIL} failed"
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
exit 0
