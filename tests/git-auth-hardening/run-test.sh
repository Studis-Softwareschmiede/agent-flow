#!/usr/bin/env bash
# tests/git-auth-hardening/run-test.sh
#
# Selbst-enthaltener Test für scripts/ensure-gh-auth.sh (S-121,
# docs/specs/git-auth-hardening.md). agent-flow ist `language: md` (No-Op-
# Build) — die Abnahme der deterministischen Bash-Mechanik erfolgt hier
# mechanisch. Kein echtes GitHub, kein echtes .env.gpg/GPG, kein Netz:
# `scripts/ensure-gh-auth.sh` wird in eine isolierte Fixture kopiert (eigener
# `scripts/load-env.sh`-Stub daneben, ROOT-relativ aufgelöst) und gegen einen
# Fake-`gh` im PATH gefahren, der den Bot-Login-Bug bewusst reproduziert.
# $HOME zeigt für jeden Testlauf auf ein frisches Tempverzeichnis — die
# echte globale/lokale git-Config des Repos wird NIE berührt.
#
# Jeder Test trägt das kanonische Trace-Tag @trace git-auth-hardening#AC<n>
# (docs/architecture/traceability-subsystem.md).
#
# Covers (docs/specs/git-auth-hardening.md):
#   AC1 — Tokenloser Push-/Fetch-Weg: nach dem Lauf kein http.*.extraheader,
#     keine Credential-Store-Datei mit Token-Klartext, `git credential fill`
#     liefert (als Proxy für den echten push/fetch-Handshake, kein Netz)
#     korrekte username=/password= (Test 1).
#   AC2 — Credential-Helper auf Basis `gh auth git-credential`, Token wird
#     on-demand gestreamt, nie geschrieben (Test 1, Test 5 Wrapper-Datei-
#     Inhalt ohne Tokenwert); Test 4a beweist zusätzlich per echtem `git
#     credential fill`, dass der Wrapper auch dann greift, wenn `gh auth
#     setup-git` bereits VOR dem Lauf einen rohen `!<pfad>/gh
#     auth git-credential`-Eintrag gesetzt hatte (Review-Fund Iteration 2).
#   AC3 — Selbstheilung: vorhandene/veraltete http.*.extraheader-Einträge
#     werden repo-lokal entfernt, bevor der Credential-Weg eingerichtet wird
#     (Test 2, deckt A2).
#   AC4 — Idempotenz: wiederholte Läufe erzeugen keinen Doppel-Eintrag,
#     bereits gesundes Setup bleibt unverändert, ein vorhandener unrelated
#     fremder Helper wird nicht destruktiv überschrieben, ein roher
#     gh-Alt-Eintrag wird kontrolliert ersetzt statt einfach ergänzt
#     (Test 3, Test 4b/4c). Test 4d-1 deckt zusätzlich den "Nicht-Rebuild
#     sieht schon vollständig aus"-Fall ab: die leere Reset-Zeile (schützt
#     vor systemweiten Fremd-Helpern, s. AC2) wird auch dann ergänzt, wenn
#     vorher NUR der Wrapper-Eintrag gesetzt war (Review-Fund Iteration 3).
#   AC5 — Doku-Inspektion: flow/L05 als überholt markiert + neuer Weg
#     genannt, kein Dok empfiehlt mehr Token-in-Datei (Test 8).
#   AC6 — Kein Secret in Datei/Log: weder Token noch dessen Base64-Form
#     taucht irgendwo unter $HOME/im Repo/in der Wrapper-Datei auf (Test 1,
#     Test 5).
#   AC7 — Bot-Login-Bug: Fake-gh liefert bewusst einen Bot-Login-Username,
#     der Wrapper normalisiert ihn auf x-access-token (Test 1); Test 4a
#     deckt zusätzlich den realen Helper-Ordnungskonflikt ab (roher
#     gh-Eintrag, der ohne Fix VOR dem Wrapper greifen und den Bug NIE
#     beheben würde — genau der reproduzierte Review-Fund Iteration 2);
#     Test 4d-2 deckt den zweiten Ordnungskonflikt ab (vollständig
#     antwortender SYSTEM-Scope-Fremd-Helper via GIT_CONFIG_SYSTEM, der ohne
#     die Reset-Zeile VOR dem Wrapper greifen würde — Review-Fund
#     Iteration 3, empirisch reproduziert).
#   AC8 — Headless: kein Lauf braucht/erlaubt interaktive Eingabe; Test 7
#     misst die Laufzeit als Indiz (kein `timeout`(1) auf macOS ohne
#     coreutils verfügbar, siehe Kommentar bei run_sut()).
#   AC9 — Fehlerpfad unverändert: ohne mintbaren Token Exit 1, Klartext-
#     Fehler, KEIN Fallback (weder Helper noch extraheader werden gesetzt)
#     (Test 6, deckt E1).
#
# Exit: 0 = alle Tests bestanden, 1 = mindestens ein Fehler.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
REAL_SCRIPT="${REPO_ROOT}/scripts/ensure-gh-auth.sh"

TEST_WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/git-auth-hardening-test.XXXXXX")"
trap 'rm -rf "$TEST_WORK_DIR"' EXIT

FAIL=0
PASS=0
fail() { echo "FAIL: $*" >&2; FAIL=$((FAIL + 1)); }
pass() { echo "PASS: $*"; PASS=$((PASS + 1)); }

[[ -f "$REAL_SCRIPT" ]] || { echo "FATAL: $REAL_SCRIPT nicht gefunden" >&2; exit 1; }

FAKE_TOKEN="test-fake-app-token-9f31c2"
FAKE_TOKEN_B64="$(printf 'x-access-token:%s' "$FAKE_TOKEN" | base64 | tr -d '\n')"

# ─── Fixture-Helfer ─────────────────────────────────────────────────────────
# Baut ein isoliertes Fixture: <dir>/repo (git-Repo, CWD des SUT-Laufs),
# <dir>/home (isoliertes $HOME für git-global-Config), <dir>/bin (Fake-gh),
# <dir>/sut/scripts/{ensure-gh-auth.sh,load-env.sh} (Kopie des echten
# Skripts + Stub statt echtem .env.gpg-Minting).
setup_fixture() {
  local dir="$1"
  mkdir -p "$dir/repo" "$dir/home" "$dir/bin" "$dir/sut/scripts"
  ( cd "$dir/repo" && git init -q -b main )
  ( cd "$dir/repo" && git config user.email t@example.com && git config user.name t )

  cp "$REAL_SCRIPT" "$dir/sut/scripts/ensure-gh-auth.sh"
  chmod +x "$dir/sut/scripts/ensure-gh-auth.sh"

  cat > "$dir/sut/scripts/load-env.sh" <<'STUBEOF'
#!/usr/bin/env bash
# Test-Stub — ersetzt das echte .env.gpg-Minting (kein GPG/.env.gpg im Test).
if [[ -n "${TEST_STUB_GH_TOKEN:-}" ]]; then
  export GH_TOKEN="$TEST_STUB_GH_TOKEN"
fi
STUBEOF

  cat > "$dir/bin/gh" <<'GHEOF'
#!/usr/bin/env bash
# Fake gh für den Test — reproduziert bewusst den Bot-Login-Bug (AC7).
set -u
if [[ "${1:-}" == "auth" && "${2:-}" == "login" && "${3:-}" == "--with-token" ]]; then
  cat >/dev/null
  exit 0
fi
if [[ "${1:-}" == "auth" && "${2:-}" == "git-credential" ]]; then
  action="${3:-get}"
  case "$action" in
    get)
      cat >/dev/null
      printf 'protocol=https\nhost=github.com\nusername=%s\npassword=%s\n' \
        "${FAKE_GH_CRED_USERNAME:-x-access-token}" "${FAKE_GH_CRED_PASSWORD:-$FAKE_TOKEN_PLACEHOLDER}"
      ;;
    *)
      cat >/dev/null
      ;;
  esac
  exit 0
fi
echo "unhandled fake gh call: $*" >&2
exit 1
GHEOF
  # Placeholder durch echten Fake-Token ersetzen (kein sed -i wegen BSD/GNU-Diff).
  sed "s/\$FAKE_TOKEN_PLACEHOLDER/$FAKE_TOKEN/" "$dir/bin/gh" > "$dir/bin/gh.tmp" && mv "$dir/bin/gh.tmp" "$dir/bin/gh"
  chmod +x "$dir/bin/gh"

  # Fingierter, VOLLSTÄNDIG antwortender Fremd-Helper (simuliert macOS
  # osxkeychain o.ä. mit einem gecachten, fremden/veralteten Credential) —
  # für Test 4d auf SYSTEM-Scope registriert (GIT_CONFIG_SYSTEM).
  cat > "$dir/bin/fake-foreign-system-helper.sh" <<'FOREIGNEOF'
#!/usr/bin/env bash
cat >/dev/null
printf 'protocol=https\nhost=github.com\nusername=system-keychain-user\npassword=system-cached-stale-token\n'
FOREIGNEOF
  chmod +x "$dir/bin/fake-foreign-system-helper.sh"
}

# Führt das SUT (ensure-gh-auth.sh) headless+isoliert aus. Weitere Args sind
# zusätzliche Env-Zuweisungen (z.B. FAKE_GH_CRED_USERNAME=...). `env` statt
# Shell-Prefix-Zuweisung, weil Letztere expandierte "$@"-Werte NICHT als
# Assignment-Wörter erkennt (nur literale Parse-Zeit-Tokens) — `env` prüft
# sein eigenes argv zur Laufzeit und funktioniert daher korrekt. Kein
# `timeout`(1) verwendet (auf macOS ohne coreutils nicht vorhanden) — da
# `gh` UND `load-env.sh` vollständig gefakt sind, ist ein realer
# GPG-Pinentry-Prompt strukturell unerreichbar (siehe Test 7, Laufzeitmessung
# statt Kill-Watchdog).
run_sut() {
  local dir="$1"; shift
  ( cd "$dir/repo" && env \
      HOME="$dir/home" \
      PATH="$dir/bin:$PATH" \
      TEST_STUB_GH_TOKEN="${TEST_STUB_GH_TOKEN-$FAKE_TOKEN}" \
      "$@" \
      bash "$dir/sut/scripts/ensure-gh-auth.sh" )
}

# ─── Test 1: Happy Path — AC1/AC2/AC6/AC7 ──────────────────────────────────
t1="$TEST_WORK_DIR/t1"
setup_fixture "$t1"

run_sut "$t1" FAKE_GH_CRED_USERNAME="some-bot-login[bot]" >/dev/null 2>"$t1/stderr.log"
rc1=$?
if [[ "$rc1" -eq 0 ]]; then
  pass "Test 1a: Happy-Path-Lauf Exit 0"
else
  fail "Test 1a: Exit=$rc1 stderr=$(cat "$t1/stderr.log")"
fi

if ! git -C "$t1/repo" config --local --get-regexp '^http\..*\.extraheader$' >/dev/null 2>&1; then
  pass "Test 1b (AC1): repo-lokale Config enthält keinen http.*.extraheader"
else
  fail "Test 1b (AC1): unerwarteter extraheader nach Lauf gefunden"
fi

if [[ ! -f "$t1/home/.git-credentials" ]]; then
  pass "Test 1c (AC1): keine credential.helper-store-Datei (~/.git-credentials) angelegt"
else
  fail "Test 1c (AC1): ~/.git-credentials wurde angelegt"
fi

cred_out="$(cd "$t1/repo" && env HOME="$t1/home" PATH="$t1/bin:$PATH" bash -c \
  'printf "protocol=https\nhost=github.com\n\n" | git credential fill' 2>"$t1/cred.err")"
if grep -qx "username=x-access-token" <<<"$cred_out" && grep -qx "password=$FAKE_TOKEN" <<<"$cred_out"; then
  pass "Test 1d (AC1/AC2/AC7): git credential fill liefert username=x-access-token trotz Bot-Login-Bug + korrektes Token"
else
  fail "Test 1d: git credential fill lieferte unerwartet: '$cred_out' (err: $(cat "$t1/cred.err"))"
fi

if ! grep -rqF "$FAKE_TOKEN" "$t1/home" 2>/dev/null && ! grep -rqF "$FAKE_TOKEN_B64" "$t1/home" 2>/dev/null; then
  pass "Test 1e (AC6): weder Token noch dessen Base64-Form liegt irgendwo unter \$HOME in einer Datei"
else
  fail "Test 1e (AC6): Token oder Base64-Form in einer Datei unter \$HOME gefunden"
fi

if ! grep -rqF "$FAKE_TOKEN" "$t1/repo/.git" 2>/dev/null; then
  pass "Test 1f (AC6): Token nicht in der Repo-Config/.git gefunden"
else
  fail "Test 1f (AC6): Token in .git gefunden"
fi

# ─── Test 2: Selbstheilung poisoned extraheader — AC3/A2 ──────────────────
t2="$TEST_WORK_DIR/t2"
setup_fixture "$t2"
git -C "$t2/repo" config --local "http.https://github.com/.extraheader" \
  "AUTHORIZATION: basic $FAKE_TOKEN_B64"

run_sut "$t2" >/dev/null 2>"$t2/stderr.log"
rc2=$?
if [[ "$rc2" -eq 0 ]]; then
  pass "Test 2a: Lauf mit vergifteter Config trotzdem Exit 0"
else
  fail "Test 2a: Exit=$rc2 stderr=$(cat "$t2/stderr.log")"
fi
if ! git -C "$t2/repo" config --local --get-regexp '^http\..*\.extraheader$' >/dev/null 2>&1; then
  pass "Test 2b (AC3): vorhandener extraheader wurde entfernt"
else
  fail "Test 2b (AC3): extraheader nach Lauf noch vorhanden"
fi

# Zweiter Lauf (nichts mehr zu bereinigen) bleibt fehlerfrei — Idempotenz.
run_sut "$t2" >/dev/null 2>"$t2/stderr2.log"
rc2b=$?
if [[ "$rc2b" -eq 0 ]]; then
  pass "Test 2c (AC4): wiederholter Lauf ohne extraheader-Rest bleibt fehlerfrei"
else
  fail "Test 2c: zweiter Lauf Exit=$rc2b stderr=$(cat "$t2/stderr2.log")"
fi

# ─── Test 3: Idempotenz Credential-Helper — AC4 ────────────────────────────
t3="$TEST_WORK_DIR/t3"
setup_fixture "$t3"

run_sut "$t3" >/dev/null 2>&1
run_sut "$t3" >/dev/null 2>&1
helper_count="$(HOME="$t3/home" git config --global --get-all credential."https://github.com".helper 2>/dev/null | grep -cF "git-credential-x-access-token.sh")"
if [[ "$helper_count" -eq 1 ]]; then
  pass "Test 3 (AC4): zweimaliger Lauf erzeugt genau EINEN Helper-Eintrag (kein Doppel-Eintrag)"
else
  fail "Test 3 (AC4): erwartet genau 1 Helper-Eintrag, gefunden $helper_count"
fi

# ─── Test 4: Rohe gh-Alt-Konfiguration + fremder Helper — AC2/AC4/AC7 ──────
# Reproduziert exakt den Review-Fund (Iteration 2, CRITICAL): auf jeder
# Alt-Maschine hat `gh auth setup-git` bereits VOR unserem Lauf einen rohen
# `!<pfad>/gh auth git-credential`-Eintrag gesetzt. git befragt Helper in
# Config-Reihenfolge und stoppt beim ersten vollständigen username+password
# (gitcredentials(7)) — ohne Fix würde der rohe Eintrag (Bot-Login) IMMER
# zuerst greifen, der Wrapper würde nie erreicht. Test 4a beweist über
# ECHTES `git credential fill` (nicht nur --get-all-Listing), dass nach dem
# Lauf x-access-token gewinnt. Ein zusätzlicher, unrelated fremder Helper
# (kein gh-Bezug) muss dabei unangetastet erhalten bleiben (Test 4b).
t4="$TEST_WORK_DIR/t4"
setup_fixture "$t4"
mkdir -p "$t4/home"
HOME="$t4/home" git config --global --add credential."https://github.com".helper "!true"
HOME="$t4/home" git config --global --add credential."https://github.com".helper "!$t4/bin/gh auth git-credential"

run_sut "$t4" FAKE_GH_CRED_USERNAME="some-bot-login[bot]" >/dev/null 2>&1

cred_out4="$(cd "$t4/repo" && env HOME="$t4/home" PATH="$t4/bin:$PATH" bash -c \
  'printf "protocol=https\nhost=github.com\n\n" | git credential fill' 2>"$t4/cred.err")"
if grep -qx "username=x-access-token" <<<"$cred_out4" && grep -qx "password=$FAKE_TOKEN" <<<"$cred_out4"; then
  pass "Test 4a (AC2/AC7, Review-Fund Iter.2): git credential fill liefert x-access-token — roher gh-Alt-Eintrag verschattet den Wrapper NICHT mehr"
else
  fail "Test 4a (AC2/AC7): git credential fill lieferte unerwartet: '$cred_out4' (err: $(cat "$t4/cred.err"))"
fi

helpers4="$(HOME="$t4/home" git config --global --get-all credential."https://github.com".helper 2>/dev/null)"
if grep -qxF "!true" <<<"$helpers4" && grep -qF "git-credential-x-access-token.sh" <<<"$helpers4" \
    && ! grep -q "gh auth git-credential" <<<"$helpers4"; then
  pass "Test 4b (AC4): unrelated fremder Helper bleibt erhalten, roher gh-Eintrag entfernt, kein Doppel-Eintrag"
else
  fail "Test 4b (AC4): Helper-Liste unerwartet: '$helpers4'"
fi

# Idempotenz: zweiter Lauf darf die Kette nicht weiter verändern/wachsen lassen.
run_sut "$t4" FAKE_GH_CRED_USERNAME="some-bot-login[bot]" >/dev/null 2>&1
helpers4b="$(HOME="$t4/home" git config --global --get-all credential."https://github.com".helper 2>/dev/null)"
helper4_count="$(HOME="$t4/home" git config --global -z --get-all credential."https://github.com".helper 2>/dev/null | grep -zc '')"
if [[ "$helper4_count" -eq 3 && "$helpers4b" == "$helpers4" ]]; then
  pass "Test 4c (AC4): wiederholter Lauf verändert die bereits korrekte Kette nicht (kein Wachstum, weiterhin [Reset, !true, Wrapper])"
else
  fail "Test 4c (AC4): Kette nach zweitem Lauf verändert oder falsche Anzahl ($helper4_count, erwartet 3): '$helpers4b' (vorher: '$helpers4')"
fi

# ─── Test 4d: Reset-Marker gegen SYSTEM-Scope-Fremd-Helper — AC2/AC4 ───────
# Review-Fund Iteration 3 (CRITICAL): `gh auth setup-git` setzt bewusst eine
# LEERE Reset-Zeile (`helper =` ohne Wert) vor dem eigentlichen Helper — sie
# löscht die bis dahin (aus system-Config, z.B. macOS `osxkeychain` via
# /etc/gitconfig) akkumulierte Helper-Liste. Ausgangslage hier bewusst
# fingiert als exakt der Zustand, den der BUGGY Iteration-2-Rebuild
# hinterlassen hätte: NUR der Wrapper-Eintrag ist gesetzt, OHNE Reset-Zeile
# ("Nicht-Rebuild-Pfad" — sieht auf den ersten Blick bereits vollständig
# aus). Ein Fremd-Helper wird NICHT global, sondern auf SYSTEM-Scope
# registriert (via GIT_CONFIG_SYSTEM statt echtem /etc/gitconfig, damit der
# Test isoliert bleibt). Beweis erfolgt über ECHTES `git credential fill`.
t4d="$TEST_WORK_DIR/t4d"
setup_fixture "$t4d"
mkdir -p "$t4d/home"
_t4d_wrapper_path="$t4d/home/.config/agent-flow/git-credential-x-access-token.sh"
_t4d_wrapper_cmd="!'${_t4d_wrapper_path}'"
HOME="$t4d/home" git config --global --add credential."https://github.com".helper "$_t4d_wrapper_cmd"

_t4d_sysconfig="$t4d/system-gitconfig"
cat > "$_t4d_sysconfig" <<EOF
[credential "https://github.com"]
	helper = !${t4d}/bin/fake-foreign-system-helper.sh
EOF

run_sut "$t4d" GIT_CONFIG_SYSTEM="$_t4d_sysconfig" FAKE_GH_CRED_USERNAME="some-bot-login[bot]" >/dev/null 2>"$t4d/stderr.log"

# 4d-1: der Rebuild MUSS die Reset-Zeile (leerer erster Eintrag) ergänzt
# haben, obwohl der Wrapper vorher schon "vollständig" aussah.
_t4d_entries=()
while IFS= read -r -d '' _e; do _t4d_entries+=("$_e"); done < <(HOME="$t4d/home" git config --global -z --get-all credential."https://github.com".helper 2>/dev/null)
if [[ "${#_t4d_entries[@]}" -ge 1 && -z "${_t4d_entries[0]}" ]]; then
  pass "Test 4d-1 (AC4): Reset-Zeile wurde ergänzt, obwohl nur der Wrapper vorher gesetzt war (Nicht-Rebuild-Pfad geschlossen)"
else
  fail "Test 4d-1 (AC4): keine führende Reset-Zeile — Einträge: ${_t4d_entries[*]}"
fi

# 4d-2: git credential fill (MIT demselben GIT_CONFIG_SYSTEM) muss trotz des
# vollständig antwortenden System-Helpers den Wrapper gewinnen lassen.
_t4d_cred_out="$(cd "$t4d/repo" && env HOME="$t4d/home" PATH="$t4d/bin:$PATH" GIT_CONFIG_SYSTEM="$_t4d_sysconfig" bash -c \
  'printf "protocol=https\nhost=github.com\n\n" | git credential fill' 2>"$t4d/cred.err")"
if grep -qx "username=x-access-token" <<<"$_t4d_cred_out" && grep -qx "password=$FAKE_TOKEN" <<<"$_t4d_cred_out"; then
  pass "Test 4d-2 (AC2/AC4, Review-Fund Iter.3): Wrapper gewinnt trotz vollständig antwortendem SYSTEM-Scope-Fremd-Helper"
else
  fail "Test 4d-2: git credential fill lieferte unerwartet: '$_t4d_cred_out' (err: $(cat "$t4d/cred.err"))"
fi
unset _t4d_wrapper_path _t4d_wrapper_cmd _t4d_sysconfig _t4d_entries _t4d_cred_out _e

# ─── Test 5: Wrapper-Datei enthält kein Token ──────────────────────────────
t5="$TEST_WORK_DIR/t5"
setup_fixture "$t5"
run_sut "$t5" >/dev/null 2>&1
wrapper="$t5/home/.config/agent-flow/git-credential-x-access-token.sh"
if [[ -f "$wrapper" ]] && ! grep -qF "$FAKE_TOKEN" "$wrapper"; then
  pass "Test 5 (AC2/AC6): Wrapper-Datei existiert und enthält keinen Token-Wert"
else
  fail "Test 5: Wrapper-Datei fehlt oder enthält den Token"
fi

# ─── Test 6: Fehlerpfad ohne mintbaren Token — AC9/E1 ──────────────────────
t6="$TEST_WORK_DIR/t6"
setup_fixture "$t6"
TEST_STUB_GH_TOKEN="" run_sut "$t6" >/dev/null 2>"$t6/stderr.log"
rc6=$?
if [[ "$rc6" -eq 1 ]]; then
  pass "Test 6a (AC9): ohne mintbaren GH_TOKEN Exit 1"
else
  fail "Test 6a (AC9): erwartet Exit 1, bekam $rc6"
fi
if grep -qF "GH_TOKEN nicht gemintet" "$t6/stderr.log"; then
  pass "Test 6b (AC9): Klartext-Fehlermeldung auf stderr"
else
  fail "Test 6b (AC9): Fehlermeldung fehlt: $(cat "$t6/stderr.log")"
fi
if [[ ! -f "$t6/home/.config/agent-flow/git-credential-x-access-token.sh" ]]; then
  pass "Test 6c (AC9): kein Credential-Helper-Wrapper angelegt (kein Fallback)"
else
  fail "Test 6c (AC9): Wrapper wurde trotz Fehlerpfad angelegt"
fi
if ! git -C "$t6/repo" config --local --get-regexp '^http\..*\.extraheader$' >/dev/null 2>&1; then
  pass "Test 6d (AC9): kein extraheader als Fallback gesetzt"
else
  fail "Test 6d (AC9): extraheader wurde trotz Fehlerpfad gesetzt"
fi

# ─── Test 7: Headless/kein Hang — AC8 ──────────────────────────────────────
# Laufzeitmessung statt Kill-Watchdog (kein `timeout`(1) auf macOS ohne
# coreutils verfügbar): `gh` UND `load-env.sh` sind vollständig gefakt, ein
# realer interaktiver GPG-Pinentry-Prompt ist strukturell unerreichbar. Ein
# Lauf, der versehentlich doch auf Eingabe wartet, würde weit über die
# Sekundengrenze hinausgehen (bzw. den Testlauf blockieren) — deutlich
# unterhalb einer sinnvollen Wartegrenze ist ein starkes Indiz für headless.
t7="$TEST_WORK_DIR/t7"
setup_fixture "$t7"
_t7_start=$(date +%s)
run_sut "$t7" >/dev/null 2>&1
rc7=$?
_t7_elapsed=$(( $(date +%s) - _t7_start ))
if [[ "$rc7" -eq 0 && "$_t7_elapsed" -le 5 ]]; then
  pass "Test 7 (AC8): Lauf headless in ${_t7_elapsed}s abgeschlossen (kein interaktiver Prompt)"
else
  fail "Test 7 (AC8): rc=$rc7 elapsed=${_t7_elapsed}s (erwartet Exit 0 in <=5s)"
fi

# ─── Test 8: Doku-Inspektion — AC5 ─────────────────────────────────────────
LESSONS_FLOW="$REPO_ROOT/.claude/lessons/flow.md"
if [[ -f "$LESSONS_FLOW" ]]; then
  if grep -q "ÜBERHOLT" "$LESSONS_FLOW" && grep -q "flow/L05" "$LESSONS_FLOW"; then
    pass "Test 8a (AC5): flow/L05 als überholt markiert"
  else
    fail "Test 8a (AC5): flow/L05 nicht als überholt markiert (oder Lesson-Datei nicht gefunden)"
  fi
  if grep -q "tokenlosen Credential-Helper-Weg\|tokenlosen git-Credential-Helper" "$LESSONS_FLOW"; then
    pass "Test 8b (AC5): neuer tokenloser Weg im Lesson-Text referenziert"
  else
    fail "Test 8b (AC5): kein Verweis auf den neuen tokenlosen Weg gefunden"
  fi
else
  fail "Test 8a/8b (AC5): $LESSONS_FLOW nicht gefunden"
fi

if ! grep -rn "extraheader" "$REPO_ROOT/agents/cicd.md" "$REPO_ROOT/scripts/board-ship.sh" 2>/dev/null | grep -qv "^Binary"; then
  pass "Test 8c (AC5): agents/cicd.md und board-ship.sh empfehlen keinen extraheader-Workaround"
else
  fail "Test 8c (AC5): unerwarteter extraheader-Hinweis in agents/cicd.md oder board-ship.sh"
fi

# ─── Zusammenfassung ────────────────────────────────────────────────────────
echo
echo "=== git-auth-hardening: $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]] || exit 1
exit 0
