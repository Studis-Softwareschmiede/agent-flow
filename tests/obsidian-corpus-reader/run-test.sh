#!/usr/bin/env bash
# tests/obsidian-corpus-reader/run-test.sh
#
# @file Self-Test für scripts/obsidian-corpus-reader.sh (Notiz-Korpus-Reader, Stufe a).
#
# Covers (obsidian-ingest): AC4, AC5, AC6
#   AC4 — Reader liest ALLE *.md rekursiv (inkl. Unterordner), fügt sie zu EINEM Korpus,
#         deterministisch (pfad-alphabetisch) geordnet, je Notiz mit Herkunfts-Marker
#         (relativer Pfad). Verifiziert über: alle Notizen präsent, Reihenfolge stabil &
#         alphabetisch, Marker == relativer Pfad, Unterordner-Notiz enthalten.
#   AC5 — Nicht-*.md + Obsidian-Interna (.obsidian/, Dot-Dirs, Anhänge) übersprungen;
#         nicht existierender Pfad -> Exit 2 + Meldung, KEINE stdout-Ausgabe; Ordner ohne
#         jede *.md -> Exit 2 + Meldung, KEINE stdout-Ausgabe (nie Leerlauf/leere Pipeline).
#   AC6 — Rein lesend: der Fixture-Ordner ist nach dem Lauf byte-identisch (Prüfsumme über
#         alle Dateien + Verzeichnis-Listing unverändert), es wird nichts angelegt/geändert.
#
# @trace obsidian-ingest#AC4
# @trace obsidian-ingest#AC5
# @trace obsidian-ingest#AC6
#
# Verwendet /tmp-Fixtures — berührt NIEMALS reale Obsidian-Ordner.
# Exit: 0 = alle Tests bestanden, 1 = mindestens ein Fehler.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
READER="${REPO_ROOT}/scripts/obsidian-corpus-reader.sh"

# Eigene TMPDIR-Variable (reviewer/L05: $TMPDIR nie überschreiben).
TEST_WORK_DIR="$(mktemp -d /tmp/obsidian-corpus-reader-test.XXXXXX)"
trap 'rm -rf "$TEST_WORK_DIR"' EXIT

FAIL=0
PASS=0
fail() { echo "FAIL: $*" >&2; FAIL=$(( FAIL + 1 )); }
pass() { echo "PASS: $*"; PASS=$(( PASS + 1 )); }

# --- Fixture-Vault mit rekursiver Struktur + Interna/Anhängen aufbauen -------
# Reihenfolge der Anlage bewusst NICHT alphabetisch, um AC4-Sortierung zu prüfen.
VAULT="${TEST_WORK_DIR}/vault"
mkdir -p "${VAULT}/unterordner" "${VAULT}/.obsidian" "${VAULT}/.trash"
printf 'Zebra-Notiz Inhalt.\n' > "${VAULT}/zebra.md"
printf 'Alpha-Notiz Inhalt.\n' > "${VAULT}/alpha.md"
printf 'Tiefe Notiz im Unterordner.\n' > "${VAULT}/unterordner/tief.md"
# Nicht-.md-Dateien (Anhänge) — müssen übersprungen werden (AC5):
printf 'PNG-bytes\n' > "${VAULT}/bild.png"
printf 'nicht markdown\n' > "${VAULT}/notiz.txt"
# Obsidian-Interna — müssen übersprungen werden (AC5), auch wenn sie .md heißen:
printf 'workspace json\n' > "${VAULT}/.obsidian/workspace.md"
printf 'trash note\n' > "${VAULT}/.trash/geloescht.md"

# ===========================================================================
# AC6-Vorbereitung: Prüfsumme des Vaults VOR dem Lauf (Read-Only-Nachweis)
# ===========================================================================
vault_fingerprint() {
  # Deterministischer Fingerabdruck: sortierte Liste aller Pfade + Inhalts-Hashes.
  (cd "$VAULT" && find . -printf '%y %p\n' | LC_ALL=C sort; \
   find "$VAULT" -type f -exec sha256sum {} \; | LC_ALL=C sort | sed "s#${VAULT}##g")
}
FP_BEFORE="$(vault_fingerprint)"

# ===========================================================================
# Test 1 (AC4): alle 3 Notizen präsent, deterministisch alphabetisch geordnet,
#               Marker == relativer Pfad, Unterordner-Notiz enthalten
# ===========================================================================
T1_OUT="$(bash "$READER" "$VAULT" 2>/dev/null)"
# Erwartete Marker-Reihenfolge (pfad-alphabetisch): alpha.md < unterordner/tief.md < zebra.md
EXPECTED_ORDER=$'===== NOTE: alpha.md =====\n===== NOTE: unterordner/tief.md =====\n===== NOTE: zebra.md ====='
GOT_ORDER="$(echo "$T1_OUT" | grep -E '^===== NOTE: ')"
if [[ "$GOT_ORDER" == "$EXPECTED_ORDER" ]]; then
  pass "Test 1 (AC4): alle Notizen präsent, deterministisch pfad-alphabetisch geordnet, Unterordner inkl."
else
  fail "Test 1 (AC4): Marker-Reihenfolge falsch. Erwartet:$'\n'${EXPECTED_ORDER}$'\n'Bekam:$'\n'${GOT_ORDER}"
fi

# ===========================================================================
# Test 2 (AC4): Herkunfts-Marker trägt den relativen Pfad + Inhalt vorhanden
# ===========================================================================
if echo "$T1_OUT" | grep -qF '===== NOTE: unterordner/tief.md =====' \
   && echo "$T1_OUT" | grep -qF 'Tiefe Notiz im Unterordner.' \
   && echo "$T1_OUT" | grep -qF '===== END NOTE: unterordner/tief.md ====='; then
  pass "Test 2 (AC4): Herkunfts-Marker = relativer Pfad (mit /-Separator), Inhalt + END-Marke vorhanden"
else
  fail "Test 2 (AC4): Herkunfts-Marker/Inhalt für Unterordner-Notiz fehlerhaft. Out:$'\n'${T1_OUT}"
fi

# ===========================================================================
# Test 3 (AC5): Nicht-.md + Obsidian-Interna übersprungen
# ===========================================================================
if ! echo "$T1_OUT" | grep -qF 'bild.png' \
   && ! echo "$T1_OUT" | grep -qF 'notiz.txt' \
   && ! echo "$T1_OUT" | grep -qF 'nicht markdown' \
   && ! echo "$T1_OUT" | grep -qF '.obsidian' \
   && ! echo "$T1_OUT" | grep -qF 'workspace json' \
   && ! echo "$T1_OUT" | grep -qF '.trash' \
   && ! echo "$T1_OUT" | grep -qF 'trash note'; then
  pass "Test 3 (AC5): Nicht-.md-Anhänge + .obsidian/ + Dot-Verzeichnisse (auch mit .md) übersprungen"
else
  fail "Test 3 (AC5): unerwünschte Datei/Interna im Korpus. Out:$'\n'${T1_OUT}"
fi

# ===========================================================================
# Test 4 (AC5): nicht existierender Pfad -> Exit 2, Meldung, KEINE stdout-Ausgabe
# ===========================================================================
set +e
T4_OUT="$(bash "$READER" "${TEST_WORK_DIR}/gibt-es-nicht" 2>"${TEST_WORK_DIR}/t4.err")"
T4_EXIT=$?
set -e
if [[ "$T4_EXIT" -eq 2 && -z "$T4_OUT" ]] && grep -qi "existiert nicht\|kein Verzeichnis" "${TEST_WORK_DIR}/t4.err"; then
  pass "Test 4 (AC5/E2): fehlender Pfad -> Exit 2 + klare Meldung + KEINE Korpus-Ausgabe (kein Leerlauf)"
else
  fail "Test 4 (AC5/E2): erwartet Exit 2, leerer stdout, Meldung. Exit=${T4_EXIT} Out='${T4_OUT}' Err=$(cat "${TEST_WORK_DIR}/t4.err")"
fi

# ===========================================================================
# Test 5 (AC5): Ordner ohne jede .md -> Exit 2, Meldung, KEINE stdout-Ausgabe
# ===========================================================================
EMPTY_VAULT="${TEST_WORK_DIR}/leer"
mkdir -p "${EMPTY_VAULT}/.obsidian"
printf 'nur ein Anhang\n' > "${EMPTY_VAULT}/anhang.pdf"
printf 'interna\n' > "${EMPTY_VAULT}/.obsidian/app.md"  # .md nur in Interna -> zählt nicht
set +e
T5_OUT="$(bash "$READER" "$EMPTY_VAULT" 2>"${TEST_WORK_DIR}/t5.err")"
T5_EXIT=$?
set -e
if [[ "$T5_EXIT" -eq 2 && -z "$T5_OUT" ]] && grep -qi "keine .md" "${TEST_WORK_DIR}/t5.err"; then
  pass "Test 5 (AC5/E2): Ordner ohne jede .md (nur Anhänge/Interna) -> Exit 2 + Meldung + kein stdout"
else
  fail "Test 5 (AC5/E2): erwartet Exit 2, leerer stdout, 'keine .md'-Meldung. Exit=${T5_EXIT} Out='${T5_OUT}' Err=$(cat "${TEST_WORK_DIR}/t5.err")"
fi

# ===========================================================================
# Test 6 (AC5): kein Ordner-Argument -> Aufruf-Fehler (Exit 3), kein stdout
# ===========================================================================
set +e
T6_OUT="$(bash "$READER" 2>"${TEST_WORK_DIR}/t6.err")"
T6_EXIT=$?
set -e
if [[ "$T6_EXIT" -eq 3 && -z "$T6_OUT" ]] && grep -qi "kein Notiz-Ordner angegeben" "${TEST_WORK_DIR}/t6.err"; then
  pass "Test 6 (AC5): kein Ordner-Argument -> Exit 3 + klare Meldung + kein stdout"
else
  fail "Test 6 (AC5): erwartet Exit 3 bei fehlendem Argument. Exit=${T6_EXIT} Out='${T6_OUT}' Err=$(cat "${TEST_WORK_DIR}/t6.err")"
fi

# ===========================================================================
# Test 7 (AC6): Vault nach ALLEN Lesevorgängen byte-identisch (rein lesend)
# ===========================================================================
FP_AFTER="$(vault_fingerprint)"
if [[ "$FP_BEFORE" == "$FP_AFTER" ]]; then
  pass "Test 7 (AC6): Vault nach dem Lesen byte-identisch — nichts geschrieben/geändert/gelöscht"
else
  fail "Test 7 (AC6): Vault wurde verändert!"$'\n'"--- diff before/after ---"$'\n'"$(diff <(echo "$FP_BEFORE") <(echo "$FP_AFTER") || true)"
fi

# ===========================================================================
# Zusammenfassung
# ===========================================================================
echo ""
echo "obsidian-corpus-reader: ${PASS} passed, ${FAIL} failed"
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
exit 0
