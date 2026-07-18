#!/usr/bin/env bash
# scripts/board-id-reserve.sh <verb> [<args>...]
#
# Mechanik hinter dem zentralen Reservierungs-Ledger board/id-reservations.yaml
# (docs/specs/id-block-reservation.md). Verhindert kollidierende Neu-IDs
# (BR-###/ADR-###/C-### o.ä.), wenn mehrere Feature-Batches PARALLEL laufen —
# jeder Batch/Story-Scope reserviert einen eigenen, zusammenhängenden
# Nummernblock je ID-Namespace, statt dezentral "die nächste freie Nummer im
# eigenen Branch-Stand" zu raten (Vorfall 2026-07-13, ki-investment: BR-132
# dreifach vergeben).
#
# Verben:
#   reserve <namespace> <feature-or-story-id> [<block-size>]
#     Idempotent (AC7): existiert bereits eine AKTIVE Reservierung für
#     (namespace, id), wird sie unverändert zurückgegeben — kein zweiter
#     Block, kein Ledger-Wachstum. Sonst wird atomar ein neuer, disjunkter
#     Block angelegt (Default-Grösse = Namespace-`block_size`, Default 10).
#   extend <namespace> <feature-or-story-id> [<block-size>]
#     Reicht der bestehende Block nicht (E1/AC5): legt UNBEDINGT einen
#     weiteren, disjunkten Block für dieselbe (namespace, id)-Kombination an
#     (keine Idempotenz-Prüfung — jeder Aufruf erzeugt einen neuen Eintrag).
#   consume <namespace> <feature-or-story-id> <id-number>
#     Vermerkt, dass <id-number> tatsächlich vergeben wurde (aktualisiert
#     high_water der aktiven Reservierung). <id-number> MUSS innerhalb des
#     reservierten Blocks liegen (AC4) — sonst Fehler, kein Retry (Logikfehler,
#     kein Push-Konflikt).
#   release <feature-or-story-id>
#     Batch-/Story-Ende (AC10): setzt ALLE aktiven Reservierungen dieser
#     id (über alle Namespaces) auf status=released. high_water bleibt
#     stehen (aus consume-Aufrufen) — ungenutzte Tail-Bereiche gelten ab
#     dann als wiederverwendbar (s. "Reserve-Operation" in der Spec).
#   seed <namespace> <highest-existing-id>
#     Einmalige Migrations-Hilfe (Edge-Case "historisch vergebene IDs
#     unterhalb des ersten Blocks"): legt eine PERMANENTE, nie freigegebene
#     Reservierung (feature_id "_bestand") an, die den Bereich 1..<n> für
#     künftige Block-Berechnungen dauerhaft blockiert. Idempotent — kleinere
#     oder gleiche <n> sind ein No-Op.
#   show <feature-or-story-id>
#     Reine Lese-Operation (kein Commit/Push) — JSON-Array aller
#     Reservierungen (active+released, alle Namespaces) dieser id, gelesen
#     von origin/<default_branch> (frisch gefetcht). AC4: "der reservierte
#     Block ist ... aus Ledger ... lesbar."
#
# Atomarität (AC2/A1): reserve/extend/consume/release/seed mutieren NIE den
# Working-Tree des Aufrufers — sie arbeiten in einem isolierten, detached
# `git worktree` gegen origin/<default_branch>. Ein Push-Reject (paralleler
# Batch war schneller) führt zu re-fetch + Neuberechnung + Retry (begrenzt,
# BOARD_ID_RESERVE_RETRIES). Scheitert der Push endgültig: Exit 1 mit
# Klartext-Diagnose (AC11 — der Aufrufer [board-feature-drain.sh] bricht
# darauf VOR der ersten Story-Session ab, last_error via dessen EXIT-Trap).
#
# Exit 0 = Verb erfolgreich (JSON auf stdout). Exit 1 = Fehler (Diagnose auf
# stderr, kein Ledger-Diff bei Logikfehlern).

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

log() { echo "[board-id-reserve] $*" >&2; }
die() { echo "FEHLER [board-id-reserve]: $*" >&2; exit 1; }

DEFAULT_BRANCH="$(grep -m1 '^default_branch:' .claude/profile.md 2>/dev/null | sed 's/default_branch: *//;s/"//g' || true)"
DEFAULT_BRANCH="${DEFAULT_BRANCH:-main}"

LEDGER_REL_PATH="board/id-reservations.yaml"
MAX_RETRIES="${BOARD_ID_RESERVE_RETRIES:-8}"
RETRY_SLEEP="${BOARD_ID_RESERVE_SLEEP:-1}"

VERB="${1:-}"
[[ -n "$VERB" ]] || die "Verwendung: board-id-reserve.sh <reserve|extend|consume|release|seed|show> <args...>"
shift || true

# --- Der eigentliche Ledger-Mutator (Python) ------------------------------
# Wird für jeden Retry-Versuch FRISCH gegen den zuletzt gefetchten Ledger-
# Stand ausgeführt (kein zwischengespeicherter Zustand über Retries hinweg).
# Exit 0 = mutiert (oder idempotent unverändert), Ergebnis-JSON auf stdout.
# Exit 2 = Logikfehler (z.B. id-number ausserhalb des Blocks, keine aktive
# Reservierung für consume) — wird vom Aufrufer NIE retried.
LEDGER_MUTATOR='
import sys, os, json, datetime

import yaml

DEFAULT_BLOCK_SIZE = 10


def now_iso():
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def load(path):
    if not os.path.exists(path) or os.path.getsize(path) == 0:
        return {"schema_version": 1, "namespaces": {}}
    with open(path, encoding="utf-8") as f:
        data = yaml.safe_load(f) or {}
    data.setdefault("schema_version", 1)
    data.setdefault("namespaces", {})
    return data


def ensure_namespace(data, ns):
    ns_data = data["namespaces"].get(ns) or {}
    ns_data.setdefault("block_size", DEFAULT_BLOCK_SIZE)
    ns_data.setdefault("reservations", [])
    data["namespaces"][ns] = ns_data
    return ns_data


def find_active(reservations, feature_id):
    for r in reservations:
        if r.get("feature_id") == feature_id and r.get("status") == "active":
            return r
    return None


def next_free_block(reservations, size):
    # Jede ACTIVE Reservierung blockiert ihren GESAMTEN [range_start,range_end]
    # Bereich (AC3: kein Wert wird von zwei aktiven Reservierungen desselben
    # Namespace geteilt). Jede RELEASED Reservierung blockiert NUR ihren
    # tatsaechlich genutzten Teil [range_start,high_water] -- high_water is
    # None oder < range_start heisst: gar nichts konsumiert, der komplette
    # Bereich ist wieder frei (AC10 "freigegebene Bereiche duerfen von
    # spaeteren Reservierungen wiederverwendet werden"). First-Fit ab 1.
    blocked = []
    for r in reservations:
        if r.get("status") == "active":
            blocked.append((r["range_start"], r["range_end"]))
        else:
            hw = r.get("high_water")
            if hw is not None and hw >= r["range_start"]:
                blocked.append((r["range_start"], min(hw, r["range_end"])))
    blocked.sort()
    candidate = 1
    for start, end in blocked:
        if candidate + size - 1 < start:
            break
        candidate = max(candidate, end + 1)
    return candidate, candidate + size - 1


def dump(data, path):
    parent = os.path.dirname(path)
    if parent:
        os.makedirs(parent, exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        yaml.dump(data, f, allow_unicode=True, default_flow_style=False, sort_keys=False)


def main():
    mode = sys.argv[1]
    ledger_path = sys.argv[2]
    data = load(ledger_path)

    if mode in ("reserve", "extend"):
        ns, feature_id = sys.argv[3], sys.argv[4]
        size_arg = sys.argv[5] if len(sys.argv) > 5 and sys.argv[5] else ""
        ns_data = ensure_namespace(data, ns)
        size = int(size_arg) if size_arg else ns_data["block_size"]
        if mode == "reserve":
            existing = find_active(ns_data["reservations"], feature_id)
            if existing:
                print(json.dumps({"namespace": ns, **existing}))
                return 0
        start, end = next_free_block(ns_data["reservations"], size)
        entry = {
            "feature_id": feature_id,
            "range_start": start,
            "range_end": end,
            "status": "active",
            "reserved_at": now_iso(),
            "high_water": None,
        }
        ns_data["reservations"].append(entry)
        dump(data, ledger_path)
        print(json.dumps({"namespace": ns, **entry}))
        return 0

    if mode == "consume":
        ns, feature_id, number_arg = sys.argv[3], sys.argv[4], sys.argv[5]
        number = int(number_arg)
        ns_data = ensure_namespace(data, ns)
        entry = find_active(ns_data["reservations"], feature_id)
        if entry is None:
            sys.stderr.write(
                f"keine aktive Reservierung fuer {feature_id}/{ns} -- zuerst reserve aufrufen.\n"
            )
            return 2
        rstart, rend = entry["range_start"], entry["range_end"]
        if not (rstart <= number <= rend):
            sys.stderr.write(
                f"{ns}-{number} liegt ausserhalb des reservierten Blocks "
                f"[{rstart},{rend}] von {feature_id}.\n"
            )
            return 2
        current_hw = entry.get("high_water")
        entry["high_water"] = number if current_hw is None else max(current_hw, number)
        dump(data, ledger_path)
        print(json.dumps({"namespace": ns, **entry}))
        return 0

    if mode == "release":
        feature_id = sys.argv[3]
        released = []
        for ns, ns_data in data["namespaces"].items():
            for r in ns_data.get("reservations", []):
                if r.get("feature_id") == feature_id and r.get("status") == "active":
                    r["status"] = "released"
                    released.append({"namespace": ns, **r})
        dump(data, ledger_path)
        print(json.dumps(released))
        return 0

    if mode == "seed":
        ns, highest_arg = sys.argv[3], sys.argv[4]
        highest = int(highest_arg)
        ns_data = ensure_namespace(data, ns)
        seed_id = "_bestand"
        entry = None
        for r in ns_data["reservations"]:
            if r.get("feature_id") == seed_id:
                entry = r
                break
        if entry is None:
            entry = {
                "feature_id": seed_id,
                "range_start": 1,
                "range_end": highest,
                "status": "active",
                "reserved_at": now_iso(),
                "high_water": highest,
            }
            ns_data["reservations"].insert(0, entry)
        elif highest > entry["range_end"]:
            entry["range_end"] = highest
            entry["high_water"] = highest
        else:
            print(json.dumps({"namespace": ns, **entry}))
            return 0
        dump(data, ledger_path)
        print(json.dumps({"namespace": ns, **entry}))
        return 0

    if mode == "show":
        feature_id = sys.argv[3]
        out = []
        for ns, ns_data in data.get("namespaces", {}).items():
            for r in ns_data.get("reservations", []):
                if r.get("feature_id") == feature_id:
                    out.append({"namespace": ns, **r})
        print(json.dumps(out))
        return 0

    sys.stderr.write(f"unbekannter Modus {mode!r}\n")
    return 2


sys.exit(main())
'

# --- Atomare Mutation mit Push-Retry gegen origin/<default_branch> -------
# run_mutation <mode> <commit-msg> <python-args...>
# Arbeitet in einem isolierten `git worktree` (detached auf
# origin/<default_branch>) -- ruehrt NIE den Working-Tree des Aufrufers an,
# egal auf welchem Branch/mit welchen uncommitteten Aenderungen dieser gerade
# steht (Vorfall-Vermeidung analog board-feature-drain.sh sync_to_feature_branch,
# nur ohne dessen Branch-Wechsel-Bedarf).
WORKTREE_DIR=""
ERR_FILE=""
PUSH_ERR_FILE=""
cleanup_worktree() {
  if [[ -n "$WORKTREE_DIR" && -d "$WORKTREE_DIR" ]]; then
    git worktree remove --force "$WORKTREE_DIR" >/dev/null 2>&1 || true
    rm -rf "$WORKTREE_DIR"
  fi
  [[ -n "$ERR_FILE" ]] && rm -f "$ERR_FILE"
  [[ -n "$PUSH_ERR_FILE" ]] && rm -f "$PUSH_ERR_FILE"
  return 0
}
trap cleanup_worktree EXIT

setup_worktree() {
  git fetch origin "$DEFAULT_BRANCH" --quiet || die "git fetch origin ${DEFAULT_BRANCH} fehlgeschlagen."
  WORKTREE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/board-id-reserve.XXXXXX")"
  git worktree add --detach --quiet "$WORKTREE_DIR" "origin/${DEFAULT_BRANCH}" \
    || die "git worktree add gegen origin/${DEFAULT_BRANCH} fehlgeschlagen."
}

run_mutation() {
  local mode="$1" commit_msg="$2"
  shift 2
  setup_worktree
  local attempt=0 result py_exit last_push_err=""
  ERR_FILE="$(mktemp "${TMPDIR:-/tmp}/board-id-reserve.err.XXXXXX")"
  PUSH_ERR_FILE="$(mktemp "${TMPDIR:-/tmp}/board-id-reserve.push-err.XXXXXX")"
  while (( attempt < MAX_RETRIES )); do
    attempt=$((attempt + 1))
    if (( attempt > 1 )); then
      ( cd "$WORKTREE_DIR" && git fetch origin "$DEFAULT_BRANCH" --quiet \
          && git reset --hard -q "origin/${DEFAULT_BRANCH}" ) \
        || die "run_mutation: re-fetch/reset im Ledger-Worktree fehlgeschlagen."
    fi
    set +e
    result="$(cd "$WORKTREE_DIR" && python3 -c "$LEDGER_MUTATOR" "$mode" "$LEDGER_REL_PATH" "$@" 2>"$ERR_FILE")"
    py_exit=$?
    set -e
    if [[ $py_exit -ne 0 ]]; then
      local err_msg
      err_msg="$(cat "$ERR_FILE" 2>/dev/null || true)"
      die "${mode}: ${err_msg:-unbekannter Fehler (Exit ${py_exit})}"
    fi

    # `git diff` (ohne --cached) ignoriert UNGETRACKTE Dateien -- beim allerersten
    # reserve-Aufruf (Ledger existiert noch nicht) ist die neu geschriebene Datei
    # untracked, ein reines `git diff --quiet` sähe fälschlich "keine Änderung".
    # Daher immer erst `git add`, dann GEGEN DEN INDEX (--cached) auf echten
    # Unterschied zu HEAD prüfen (deckt neu UND geändert einheitlich ab).
    ( cd "$WORKTREE_DIR" && git add "$LEDGER_REL_PATH" )
    if ( cd "$WORKTREE_DIR" && git diff --cached --quiet -- "$LEDGER_REL_PATH" ); then
      echo "$result"
      return 0
    fi
    ( cd "$WORKTREE_DIR" && git commit -q -m "$commit_msg" )
    if ( cd "$WORKTREE_DIR" && git push origin "HEAD:${DEFAULT_BRANCH}" --quiet ) 2>"$PUSH_ERR_FILE"; then
      echo "$result"
      return 0
    fi
    last_push_err="$(cat "$PUSH_ERR_FILE" 2>/dev/null || true)"
    log "Push-Konflikt bei ${mode} (Versuch ${attempt}/${MAX_RETRIES}) — re-fetch + Neuberechnung."
    sleep "$RETRY_SLEEP"
  done
  die "Ledger-Push nach ${MAX_RETRIES} Versuchen endgültig fehlgeschlagen (${mode}) — kein Story-Start ohne gültige Reservierung. Letzter Push-Fehler: ${last_push_err:-(kein stderr erfasst)}"
}

case "$VERB" in
  reserve)
    NS="${1:-}"; ID="${2:-}"; SIZE="${3:-}"
    [[ -n "$NS" && -n "$ID" ]] || die "Verwendung: board-id-reserve.sh reserve <namespace> <feature-or-story-id> [<block-size>]"
    run_mutation "reserve" "chore(board): id-reservations reserve ${NS} ${ID}" "$NS" "$ID" "$SIZE"
    ;;
  extend)
    NS="${1:-}"; ID="${2:-}"; SIZE="${3:-}"
    [[ -n "$NS" && -n "$ID" ]] || die "Verwendung: board-id-reserve.sh extend <namespace> <feature-or-story-id> [<block-size>]"
    run_mutation "extend" "chore(board): id-reservations extend ${NS} ${ID}" "$NS" "$ID" "$SIZE"
    ;;
  consume)
    NS="${1:-}"; ID="${2:-}"; NUMBER="${3:-}"
    [[ -n "$NS" && -n "$ID" && -n "$NUMBER" ]] || die "Verwendung: board-id-reserve.sh consume <namespace> <feature-or-story-id> <id-number>"
    run_mutation "consume" "chore(board): id-reservations consume ${NS}-${NUMBER} (${ID})" "$NS" "$ID" "$NUMBER"
    ;;
  release)
    ID="${1:-}"
    [[ -n "$ID" ]] || die "Verwendung: board-id-reserve.sh release <feature-or-story-id>"
    run_mutation "release" "chore(board): id-reservations release ${ID}" "$ID"
    ;;
  seed)
    NS="${1:-}"; HIGHEST="${2:-}"
    [[ -n "$NS" && -n "$HIGHEST" ]] || die "Verwendung: board-id-reserve.sh seed <namespace> <highest-existing-id>"
    run_mutation "seed" "chore(board): id-reservations seed ${NS} bis ${HIGHEST}" "$NS" "$HIGHEST"
    ;;
  show)
    ID="${1:-}"
    [[ -n "$ID" ]] || die "Verwendung: board-id-reserve.sh show <feature-or-story-id>"
    git fetch origin "$DEFAULT_BRANCH" --quiet || die "git fetch origin ${DEFAULT_BRANCH} fehlgeschlagen."
    TMP_LEDGER="$(mktemp "${TMPDIR:-/tmp}/board-id-reserve-show.XXXXXX")"
    git show "origin/${DEFAULT_BRANCH}:${LEDGER_REL_PATH}" > "$TMP_LEDGER" 2>/dev/null || : > "$TMP_LEDGER"
    python3 -c "$LEDGER_MUTATOR" "show" "$TMP_LEDGER" "$ID"
    rm -f "$TMP_LEDGER"
    ;;
  *)
    die "Unbekanntes Verb '${VERB}' — erwartet: reserve|extend|consume|release|seed|show"
    ;;
esac
