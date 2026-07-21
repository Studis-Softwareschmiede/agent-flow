#!/usr/bin/env bash
# tests/gpg-pass/run-test.sh
#
# Selbst-enthaltener Test für scripts/provision-gpg-pass.sh (S-118,
# docs/specs/gpg-pass-single-flight.md). agent-flow ist `language: md`
# (No-Op-Build) — die Abnahme der deterministischen Bash-Mechanik erfolgt
# hier mechanisch statt via Sprach-Testframework. Kein Docker, kein
# Bitwarden, kein Netz (GPG_BW_FETCH_CMD ersetzt den Container-Roundtrip,
# AC6).
#
# Jeder Test trägt das kanonische Trace-Tag @trace gpg-pass-single-flight#AC<n>
# (docs/architecture/traceability-subsystem.md).
#
# Covers (docs/specs/gpg-pass-single-flight.md):
#   AC1 — Single-Flight-Lock: exklusives, per-App mkdir-Lock vor dem
#     Roundtrip, Freigabe in JEDEM Ausgang (Test 1 beweist über den
#     Fetch-Zähler, dass unter Konkurrenz nur EIN Halter fetcht; Test 4
#     beweist Freigabe auch im Fehlerpfad — E3).
#   AC2 — Warte-Pfad statt Zweit-Login: Wartende pollen auf frische
#     Cache-Datei ODER Lock-Freigabe (Test 1: alle 12 Aufrufer liefern
#     denselben Pfad + Exit 0, nur 1 Fetch); Warte-Timeout (Test 3, E2).
#   AC3 — Stale-Lock-Übernahme: ein künstlich gealtertes Lock wird
#     gebrochen/übernommen, kein Deadlock (Test 2).
#   AC4 — Cache/Lock-Ort: GPG_BW_CACHE_DIR (Env) übersteuert den Default,
#     Verzeichnis 0700, Cache-Datei 0600, atomar geschrieben (Test 1c/1d);
#     Default-Pfad ist NICHT von $TMPDIR abhängig (Test 6 — Default-Pfad-
#     Auflösung landet unter $HOME, nicht unter $TMPDIR).
#   AC5 — Einzelaufruf-Verhalten unverändert: Erfolg -> stdout=Cache-Pfad,
#     Exit 0 (Test 5a); Fehlschlag (kein Fetch-Hook, kein Docker) -> keine
#     Ausgabe, Exit != 0 (Test 5b); zweiter Aufruf trifft den Cache, ohne
#     erneut zu fetchen (Test 5c).
#   AC6 — Testbarkeit + Parallel-Beweis: GPG_BW_FETCH_CMD ersetzt den
#     Container-Roundtrip (alle Tests); Test 1 startet 12 (>= 10) parallele
#     Aufrufer gegen einen zählenden Mock-Fetch und beweist genau 1
#     Fetch-Ausführung, identischer Cache-Pfad, Exit 0 für alle.
#   E1  — Lock-Halter stirbt: siehe AC3/Test 2 (identischer Mechanismus).
#   E2  — Warte-Timeout überschritten: Test 3 (Exit != 0, keine Ausgabe).
#   E3  — Fetch des Lock-Halters schlägt fehl: Test 4 (Lock wird
#     freigegeben, kein Cache geschrieben, Wartender bekommt genau einen
#     eigenen Versuch statt einer Retry-Schleife).
#
# Exit: 0 = alle Tests bestanden, 1 = mindestens ein Fehler.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PROVISION_SCRIPT="${REPO_ROOT}/scripts/provision-gpg-pass.sh"

TEST_WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/gpg-pass-test.XXXXXX")"
trap 'rm -rf "$TEST_WORK_DIR"' EXIT

FAIL=0
PASS=0
fail() { echo "FAIL: $*" >&2; FAIL=$((FAIL + 1)); }
pass() { echo "PASS: $*"; PASS=$((PASS + 1)); }

[[ -x "$PROVISION_SCRIPT" ]] || { echo "FATAL: $PROVISION_SCRIPT nicht ausführbar" >&2; exit 1; }

# ─── Test 1: Single-Flight unter echter Nebenläufigkeit (AC1/AC2/AC6) ──────
# 12 (>=10) parallele Aufrufer, gleiche App, leerer Cache, gegen einen
# zählenden Mock-Fetch (jeder Aufruf des Hooks haengt einen Marker an eine
# gemeinsame Zähl-Datei — mkdir-basiert atomar, kein Datei-Locking nötig).
test1_dir="${TEST_WORK_DIR}/t1"
mkdir -p "$test1_dir/cache" "$test1_dir/out" "$test1_dir/fetch-calls"
FETCH_MARKER_DIR="$test1_dir/fetch-calls"
FETCH_LOG="$test1_dir/fetch.log"

# Mock-Fetch-Skript: registriert EINEN Aufruf atomar (mkdir als Zähl-Slot),
# simuliert eine kleine Login-Latenz, liefert dann eine feste Passphrase.
cat > "$test1_dir/mock-fetch.sh" <<MOCKEOF
#!/usr/bin/env bash
mkdir "${FETCH_MARKER_DIR}/\$\$-\$RANDOM" 2>/dev/null
echo "call \$\$" >> "${FETCH_LOG}"
sleep 0.3
echo "single-flight-secret-value"
MOCKEOF
chmod +x "$test1_dir/mock-fetch.sh"

N=12
pids=()
for i in $(seq 1 "$N"); do
  (
    GPG_BW_CACHE_DIR="$test1_dir/cache" \
    GPG_BW_FETCH_CMD="$test1_dir/mock-fetch.sh" \
    GPG_BW_WAIT_SEC=20 \
      "$PROVISION_SCRIPT" t1app > "$test1_dir/out/$i.out" 2> "$test1_dir/out/$i.err"
    echo $? > "$test1_dir/out/$i.rc"
  ) &
  pids+=($!)
done
for p in "${pids[@]}"; do wait "$p"; done

fetch_count=$(find "$FETCH_MARKER_DIR" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
if [[ "$fetch_count" -eq 1 ]]; then
  pass "Test 1a: genau 1 Fetch-Ausführung bei $N parallelen Aufrufern (gemessen: $fetch_count)"
else
  fail "Test 1a: erwartet genau 1 Fetch-Ausführung, gemessen $fetch_count"
fi

all_exit0=1
all_same_path=1
ref_path=""
for i in $(seq 1 "$N"); do
  rc="$(cat "$test1_dir/out/$i.rc")"
  out="$(cat "$test1_dir/out/$i.out")"
  [[ "$rc" -eq 0 ]] || { all_exit0=0; fail "Test 1: Aufrufer $i Exit=$rc (erwartet 0)"; }
  if [[ -z "$ref_path" ]]; then ref_path="$out"; fi
  [[ "$out" == "$ref_path" && -n "$out" ]] || { all_same_path=0; fail "Test 1: Aufrufer $i Pfad='$out' weicht ab (Referenz='$ref_path')"; }
done
[[ "$all_exit0" -eq 1 ]] && pass "Test 1b: alle $N Aufrufer Exit 0"
[[ "$all_same_path" -eq 1 ]] && pass "Test 1c: alle $N Aufrufer liefern denselben, nicht-leeren Cache-Pfad ($ref_path)"

if [[ -n "$ref_path" && -r "$ref_path" ]]; then
  content="$(cat "$ref_path")"
  [[ "$content" == "single-flight-secret-value" ]] && pass "Test 1d: Cache-Inhalt korrekt materialisiert" \
    || fail "Test 1d: Cache-Inhalt='$content' unerwartet"
  perm="$(stat -c '%a' "$ref_path" 2>/dev/null || stat -f '%Lp' "$ref_path" 2>/dev/null)"
  [[ "$perm" == "600" ]] && pass "Test 1e: Cache-Datei-Rechte 0600 (gemessen: $perm)" \
    || fail "Test 1e: Cache-Datei-Rechte='$perm' (erwartet 600)"
else
  fail "Test 1d/1e: Cache-Pfad '$ref_path' nicht lesbar"
fi

dirperm="$(stat -c '%a' "$test1_dir/cache" 2>/dev/null || stat -f '%Lp' "$test1_dir/cache" 2>/dev/null)"
[[ "$dirperm" == "700" ]] && pass "Test 1f: Cache-Verzeichnis-Rechte 0700 (gemessen: $dirperm)" \
  || fail "Test 1f: Cache-Verzeichnis-Rechte='$dirperm' (erwartet 700)"

# ─── Test 2: Stale-Lock-Übernahme (AC3, E1) ────────────────────────────────
test2_dir="${TEST_WORK_DIR}/t2"
mkdir -p "$test2_dir/cache"
LOCK_DIR="$test2_dir/cache/sos-gpgpass-lock-t2app"
mkdir -p "$LOCK_DIR"
# Simuliert einen toten Halter: Lock existiert, Zeitstempel weit in der
# Vergangenheit (älter als die Stale-Schwelle).
echo 99999 > "$LOCK_DIR/pid"
echo "$(( $(date +%s) - 3600 ))" > "$LOCK_DIR/acquired_at"

out="$(GPG_BW_CACHE_DIR="$test2_dir/cache" \
       GPG_BW_FETCH_CMD="echo stale-lock-recovered-secret" \
       GPG_BW_WAIT_SEC=5 \
         "$PROVISION_SCRIPT" t2app)"
rc=$?
if [[ "$rc" -eq 0 && -n "$out" && -r "$out" ]]; then
  content="$(cat "$out")"
  if [[ "$content" == "stale-lock-recovered-secret" ]]; then
    pass "Test 2: verwaistes (stale) Lock wurde gebrochen/übernommen, kein Deadlock"
  else
    fail "Test 2: unerwarteter Cache-Inhalt '$content'"
  fi
else
  fail "Test 2: Exit=$rc Out='$out' (erwartet Exit 0 + gültiger Pfad trotz stale Lock)"
fi

# ─── Test 3: Warte-Timeout überschritten (AC2, E2) ─────────────────────────
# Ein frisches (nicht-stale) Lock wird von einem Hintergrundprozess für
# länger als GPG_BW_WAIT_SEC gehalten -> der Wartende muss mit Exit != 0
# und OHNE Ausgabe abbrechen.
test3_dir="${TEST_WORK_DIR}/t3"
mkdir -p "$test3_dir/cache"

(
  GPG_BW_CACHE_DIR="$test3_dir/cache" \
  GPG_BW_FETCH_CMD="sleep 15; echo timeout-holder-secret" \
  GPG_BW_WAIT_SEC=30 \
    "$PROVISION_SCRIPT" t3app > "$test3_dir/holder.out" 2>&1 &
)
# Kurz warten, bis der Hintergrundprozess das Lock sicher erworben hat.
for _ in $(seq 1 50); do
  [[ -d "$test3_dir/cache/sos-gpgpass-lock-t3app" ]] && break
  sleep 0.1
done

# Grosszügiger Sicherheitsabstand zum Holder (15s) gegen Scheduling-Jitter
# unter Last — der Test misst nur "Timeout > Ausgabe/Exit-Verhalten", nicht
# die exakte Wartezeit.
out3="$(GPG_BW_CACHE_DIR="$test3_dir/cache" \
        GPG_BW_FETCH_CMD="echo should-not-be-used" \
        GPG_BW_WAIT_SEC=3 \
          "$PROVISION_SCRIPT" t3app 2>"$test3_dir/waiter.err")"
rc3=$?
if [[ "$rc3" -ne 0 && -z "$out3" ]]; then
  pass "Test 3: Warte-Timeout überschritten -> Exit != 0, keine Ausgabe (rc=$rc3)"
else
  fail "Test 3: erwartet Exit != 0 + leere Ausgabe, bekam rc=$rc3 out='$out3'"
fi
wait 2>/dev/null

# ─── Test 4: Fetch des Lock-Halters schlägt fehl (E3) ──────────────────────
# Lock wird freigegeben, kein Cache geschrieben; ein nachfolgender Aufrufer
# darf danach einen eigenen (erfolgreichen) Versuch machen.
test4_dir="${TEST_WORK_DIR}/t4"
mkdir -p "$test4_dir/cache"

out4a="$(GPG_BW_CACHE_DIR="$test4_dir/cache" \
         GPG_BW_FETCH_CMD="exit 1" \
         GPG_BW_WAIT_SEC=5 \
           "$PROVISION_SCRIPT" t4app 2>/dev/null)"
rc4a=$?
lock_gone=1
[[ -d "$test4_dir/cache/sos-gpgpass-lock-t4app" ]] && lock_gone=0

if [[ "$rc4a" -ne 0 && -z "$out4a" && "$lock_gone" -eq 1 ]]; then
  pass "Test 4a: Fetch-Fehlschlag -> Exit != 0, keine Ausgabe, Lock freigegeben (E3)"
else
  fail "Test 4a: rc=$rc4a out='$out4a' lock_gone=$lock_gone"
fi

out4b="$(GPG_BW_CACHE_DIR="$test4_dir/cache" \
         GPG_BW_FETCH_CMD="echo recovered-after-fetch-failure" \
         GPG_BW_WAIT_SEC=5 \
           "$PROVISION_SCRIPT" t4app)"
rc4b=$?
if [[ "$rc4b" -eq 0 && -n "$out4b" && -r "$out4b" ]]; then
  pass "Test 4b: nachfolgender Aufruf macht einen eigenen, erfolgreichen Versuch"
else
  fail "Test 4b: rc=$rc4b out='$out4b'"
fi

# ─── Test 5: Einzelaufruf-Verhalten unverändert (AC5) ──────────────────────
test5_dir="${TEST_WORK_DIR}/t5"
mkdir -p "$test5_dir/cache"

out5a="$(GPG_BW_CACHE_DIR="$test5_dir/cache" \
         GPG_BW_FETCH_CMD="echo single-caller-secret" \
           "$PROVISION_SCRIPT" t5app)"
rc5a=$?
[[ "$rc5a" -eq 0 && -n "$out5a" ]] && pass "Test 5a: Erfolg -> stdout=Cache-Pfad, Exit 0" \
  || fail "Test 5a: rc=$rc5a out='$out5a'"

out5b="$(GPG_BW_CACHE_DIR="$test5_dir/cache-empty" \
         DEVGUI_CONTAINER="definitely-not-running-xyz" \
           "$PROVISION_SCRIPT" t5app-missing 2>/dev/null)"
rc5b=$?
[[ "$rc5b" -ne 0 && -z "$out5b" ]] && pass "Test 5b: Fehlschlag (kein Hook, kein Docker) -> keine Ausgabe, Exit != 0" \
  || fail "Test 5b: rc=$rc5b out='$out5b'"

rm -f "$test5_dir/second-fetch-marker"
out5c="$(GPG_BW_CACHE_DIR="$test5_dir/cache" \
         GPG_BW_FETCH_CMD="touch '$test5_dir/second-fetch-marker'; echo should-not-refetch" \
           "$PROVISION_SCRIPT" t5app)"
rc5c=$?
if [[ "$rc5c" -eq 0 && "$out5c" == "$out5a" && ! -e "$test5_dir/second-fetch-marker" ]]; then
  pass "Test 5c: zweiter Aufruf trifft den Cache, kein erneuter Fetch"
else
  fail "Test 5c: rc=$rc5c out='$out5c' (erwartet '$out5a', kein Re-Fetch)"
fi

# ─── Test 6: Default-Cache-Ort ist NICHT von $TMPDIR abhängig (AC4) ────────
test6_dir="${TEST_WORK_DIR}/t6"
mkdir -p "$test6_dir/home" "$test6_dir/tmpdir-should-be-unused"

out6="$(HOME="$test6_dir/home" \
        TMPDIR="$test6_dir/tmpdir-should-be-unused" \
        GPG_BW_FETCH_CMD="echo default-location-secret" \
          "$PROVISION_SCRIPT" t6app)"
rc6=$?
if [[ "$rc6" -eq 0 && "$out6" == "$test6_dir/home"* ]]; then
  pass "Test 6a: Default-Cache-Ort liegt unter \$HOME, nicht unter \$TMPDIR"
else
  fail "Test 6a: rc=$rc6 out='$out6' (erwartet Pfad unter $test6_dir/home)"
fi
tmp_leftover="$(find "$test6_dir/tmpdir-should-be-unused" -mindepth 1 2>/dev/null | wc -l | tr -d ' ')"
[[ "$tmp_leftover" -eq 0 ]] && pass "Test 6b: \$TMPDIR bleibt vollständig unberührt" \
  || fail "Test 6b: \$TMPDIR enthält $tmp_leftover unerwartete Artefakte"

# ─── Zusammenfassung ────────────────────────────────────────────────────────
echo
echo "=== gpg-pass single-flight: $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]] || exit 1
exit 0
