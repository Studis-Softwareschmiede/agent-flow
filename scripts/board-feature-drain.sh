#!/usr/bin/env bash
# scripts/board-feature-drain.sh <F-###> [<container-name>]
#
# Feature-Schicht der 3-Ebenen-Orchestrierung (Owner-Konzept 2026-07-06):
#   Board-Ebene (außen, z.B. dev-guis Nachtwächter/dieses Skripts Aufrufer)
#   → Feature-Ebene (DIESES Skript, deterministisch, kein LLM)
#   → Story-Ebene (`claude -p /agent-flow:flow --parent <F-###>`, frischer
#     Kontext je Story — unverändert das bestehende Session-Rotation-Prinzip,
#     nur auf ein einzelnes Feature verengt).
#
# Zweck: Storys eines Features werden nacheinander gebaut und LANDEN JEWEILS
# NUR im Feature-Branch (kein main-Merge, kein Rollout pro Story) — erst wenn
# ALLE Storys terminal sind (Done oder bewusst Verworfen), EIN einziger Merge
# Feature-Branch → main + EIN Rollout (statt N Merges/N Rollouts). Löst genau
# das "10 Storys, 10× Deploy"-Problem, das der Owner am 2026-07-06 ansprach.
#
# Voraussetzung: ≥ 1 Story unter diesem Feature (Owner-Entscheidung 2026-07-06,
# zweite Korrektur — KEINE Mindestanzahl von 2: der Weg ist für 1 Story
# genauso gültig wie für 30, kein Sonderfall).
#
# Blockade-Verhalten (Owner-Entscheidung 2026-07-06): Bleibt eine Story
# BEWUSST Blocked (status=="Blocked"), wartet das GANZE Feature — kein
# Timeout, kein Teil-Deploy der bereits fertigen Storys. Das Skript beendet
# sich dann mit Exit 3 und einer klaren Diagnose statt endlos zu pollen — ein
# äußerer Aufrufer (Board-Ebene) entscheidet, wann er es erneut versucht (z.B.
# nachdem der Owner die Blockade gelöst hat).
#
# Liegengebliebene Storys (Vorfall 2026-07-06, Owner-Testlauf F-065/S-299):
# Ein nicht-terminaler Status, der weder "To Do" noch "Blocked" ist
# (typischerweise "In Progress"), stammt fast immer aus einer UNTERBROCHENEN
# vorherigen /flow-Sitzung (CI-Timeout, Container-Neustart, abgelaufener
# Token) — niemand hat die Story bewusst blockiert. Das Skript unterscheidet
# das jetzt von einer echten Blockade: die Story wird automatisch auf
# "To Do" zurückgesetzt und im selben Lauf sofort erneut versucht, statt das
# ganze Feature fälschlich als "blockiert" zu melden und auf einen manuellen
# Eingriff zu warten.
#
# Exit 0 = Feature komplett gelandet (oder war schon fertig — idempotent).
# Exit 1 = Fehler (siehe Meldung).
# Exit 3 = Feature wartet auf mindestens eine ECHT (status=="Blocked")
#          blockierte Story.

set -euo pipefail

FEATURE_ID="${1:-}"
APP_NAME="${2:-}"
[[ -n "$FEATURE_ID" ]] || { echo "FEHLER [board-feature-drain]: Verwendung: board-feature-drain.sh <F-###> [<container-name>]" >&2; exit 1; }
[[ "$FEATURE_ID" =~ ^F-[0-9]{3,}$ ]] || { echo "FEHLER [board-feature-drain]: <F-###> im Format F-### erwartet, war '$FEATURE_ID'" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

BOARD_SCRIPT="${SCRIPT_DIR}/board"
SHIP_SCRIPT="${SCRIPT_DIR}/board-ship.sh"
FEATURE_BRANCH="feature/${FEATURE_ID}"

log() { echo "[board-feature-drain] $*"; }
die() { echo "FEHLER [board-feature-drain]: $*" >&2; exit 1; }

DEFAULT_BRANCH="$(grep -m1 '^default_branch:' .claude/profile.md 2>/dev/null | sed 's/default_branch: *//;s/"//g' || true)"
DEFAULT_BRANCH="${DEFAULT_BRANCH:-main}"

# ISO-8601-UTC-Zeitstempel (jetzt) — dieselbe Konvention wie scripts/board (now_ts()).
now_ts() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# --- Run-State (AC9/AC10/E7): board/runs/<F-###>/state.yaml -----------------
# Bindender Schema-Vertrag (Spec §"state.yaml-Schema", u.a. für dev-gui) —
# Feldnamen/Enums NICHT ohne Spec-Änderung anpassen. Atomar geschrieben
# (Temp-Datei + `mv`, wie die übrige Board-CLI) — kein Leser sieht je eine
# halb geschriebene Datei (E7).
RUN_DIR="board/runs/${FEATURE_ID}"
STATE_FILE="${RUN_DIR}/state.yaml"
RUN_STARTED_AT=""

state_write() {
  # state_write <phase> <current_story|-> <done> <total> <round> <last_error|->
  local phase="$1" current_story="$2" done_n="$3" total_n="$4" round_n="$5" last_error="$6"
  mkdir -p "$RUN_DIR"
  [[ -n "$RUN_STARTED_AT" ]] || RUN_STARTED_AT="$(now_ts)"
  local tmp
  tmp="$(mktemp "${RUN_DIR}/state.yaml.XXXXXX")"
  python3 - "$tmp" "$phase" "$current_story" "$done_n" "$total_n" "$round_n" "$last_error" "$FEATURE_ID" "$RUN_STARTED_AT" "$(now_ts)" <<'PYEOF'
import sys, yaml

(tmp, phase, current_story, done_n, total_n, round_n, last_error,
 feature_id, started_at, updated_at) = sys.argv[1:11]

data = {
    "schema_version": 1,
    "feature_id": feature_id,
    "phase": phase,
    "current_story": None if current_story == "-" else current_story,
    "progress": {"done": int(done_n), "total": int(total_n)},
    "round": int(round_n),
    "started_at": started_at,
    "updated_at": updated_at,
    "last_error": None if last_error == "-" else last_error,
}
with open(tmp, "w", encoding="utf-8") as f:
    yaml.dump(data, f, allow_unicode=True, default_flow_style=False, sort_keys=False)
PYEOF
  mv "$tmp" "$STATE_FILE"
}

# Bei jedem Fehler/Exit!=0 (AC9): last_error in state.yaml mit Klartext setzen,
# BEVOR das Skript endet. Nutzt die zuletzt bekannten Phase/Progress/Round-
# Werte (globale Variablen, laufend in der Hauptschleife aktualisiert) — auch
# wenn state.yaml noch gar nicht existiert (sehr früher Abbruch), einfach mit
# Platzhaltern.
CUR_PHASE="dossier"
CUR_STORY="-"
CUR_DONE=0
CUR_TOTAL=0
CUR_ROUND=0

on_error_state() {
  local exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    local msg="Exit ${exit_code}: Feature-Drain für ${FEATURE_ID} abgebrochen (siehe Log oben)."
    state_write "$CUR_PHASE" "$CUR_STORY" "$CUR_DONE" "$CUR_TOTAL" "$CUR_ROUND" "$msg" 2>/dev/null || true
  fi
}
trap on_error_state EXIT

story_status() {
  # story_status <S-###> — liest den aktuellen Status direkt aus der YAML
  # (kein 'board show', um ohne zusätzliche CLI-Abhängigkeit auszukommen).
  python3 - "$1" <<'PYEOF'
import sys, glob, yaml
sid = sys.argv[1]
for path in glob.glob("board/stories/*.yaml"):
    try:
        with open(path) as f:
            data = yaml.safe_load(f) or {}
    except Exception:
        continue
    if str(data.get("id", "")).strip() == sid:
        print(str(data.get("status", "")).strip())
        break
PYEOF
}

progress_done_count() {
  # Anzahl terminaler (Done/Verworfen) Kind-Storys dieses Features — für
  # state.yaml progress.done (AC10: "done" = Anzahl terminaler Storys).
  python3 - "$FEATURE_ID" <<'PYEOF'
import sys, glob, yaml
fid = sys.argv[1]
count = 0
for path in glob.glob("board/stories/*.yaml"):
    try:
        with open(path) as f:
            data = yaml.safe_load(f) or {}
    except Exception:
        continue
    if str(data.get("parent", "")).strip() != fid:
        continue
    if str(data.get("status", "")).strip() in ("Done", "Verworfen"):
        count += 1
print(count)
PYEOF
}

remaining_nonterminal() {
  # Kommagetrennte Liste "<id>:<status>" aller nicht-terminalen Storys dieses
  # Features (leer = alle Done/Verworfen, Feature fertig).
  python3 - "$FEATURE_ID" <<'PYEOF'
import sys, glob, yaml
fid = sys.argv[1]
out = []
for path in glob.glob("board/stories/*.yaml"):
    try:
        with open(path) as f:
            data = yaml.safe_load(f) or {}
    except Exception:
        continue
    if str(data.get("parent", "")).strip() != fid:
        continue
    status = str(data.get("status", "")).strip()
    if status not in ("Done", "Verworfen"):
        out.append(f"{data.get('id')}:{status}")
print(",".join(out))
PYEOF
}

blocked_story_ids() {
  # Kommagetrennte Liste der Story-IDs mit status=="Blocked" — eine ECHTE,
  # bewusste Blockade (Owner-Entscheidung 2026-07-06: dafür wartet das ganze
  # Feature). Getrennt von orphaned_story_ids() (unten), die eine bloß
  # LIEGENGEBLIEBENE Story aus einer unterbrochenen Sitzung erfasst.
  python3 - "$FEATURE_ID" <<'PYEOF'
import sys, glob, yaml
fid = sys.argv[1]
out = []
for path in glob.glob("board/stories/*.yaml"):
    try:
        with open(path) as f:
            data = yaml.safe_load(f) or {}
    except Exception:
        continue
    if str(data.get("parent", "")).strip() != fid:
        continue
    if str(data.get("status", "")).strip() == "Blocked":
        out.append(str(data.get("id", "")).strip())
print(",".join(out))
PYEOF
}

generate_dossier() {
  # Feature-Kontext-Dossier (einmalig, best-effort, AC13/E4): erzeugt
  # board/runs/<F-###>/dossier.md über EINE claude -p-Session, BEVOR die erste
  # Story-Session startet. Fasst die Kind-Storys des Features (IDs, Titel,
  # Specs, implements-ACs, depends) zusammen und bittet um Feature-Ziel,
  # betroffene Specs+ACs, Story-Reihenfolge/Abhängigkeiten, Architektur-
  # Hinweise und bekannte Fallen. Schlägt die Session fehl (Timeout, kein
  # Token, non-zero exit) läuft der Drain OHNE dossier.md weiter — kein
  # Abbruch, kein `die` (best-effort, nie blockierend).
  # Sicherheit: reine Prompt-rein/Text-raus-Zusammenfassung, kein Tool-Zugriff
  # nötig — das Bash-Skript selbst schreibt die Datei per Redirect. Bewusst
  # OHNE --dangerously-skip-permissions (anders als die Story-Session weiter
  # unten): kleinerer Blast-Radius, da der Prompt Freitext (Story-Titel) aus
  # board/stories/*.yaml einbettet (Prompt-Injection-Fläche).
  local dossier_file="${RUN_DIR}/dossier.md"
  local stories_summary
  stories_summary="$(python3 - "$FEATURE_ID" <<'PYEOF'
import sys, glob, yaml
fid = sys.argv[1]
lines = []
for path in glob.glob("board/stories/*.yaml"):
    try:
        with open(path) as f:
            data = yaml.safe_load(f) or {}
    except Exception:
        continue
    if str(data.get("parent", "")).strip() != fid:
        continue
    sid = data.get("id", "")
    title = data.get("title", "")
    spec = data.get("spec", "")
    implements = data.get("implements", []) or []
    depends = data.get("depends", []) or []
    lines.append(
        f"- {sid}: {title}\n"
        f"  spec: {spec}\n"
        f"  implements: {', '.join(implements) if implements else '-'}\n"
        f"  depends: {', '.join(depends) if depends else '-'}"
    )
print("\n".join(lines))
PYEOF
)"

  local prompt
  prompt="Fasse für das Feature ${FEATURE_ID} ein kleines Kontext-Dossier zusammen. Hier die Kind-Storys (ID, Titel, Spec, implements-ACs, depends):

${stories_summary}

Schreibe ein knappes Markdown-Dossier mit folgenden Abschnitten: Feature-Ziel, betroffene Specs + AC-Nummern, sinnvolle Story-Reihenfolge/Abhängigkeiten, Architektur-Hinweise, bekannte Fallen. Halte es kurz (kein Roman) — es dient als vorangestellter Kontext für jede einzelne Story-Session dieses Features."

  mkdir -p "$RUN_DIR"
  if timeout 120s "${BOARD_FEATURE_DRAIN_CLAUDE_CMD:-claude}" -p "$prompt" > "$dossier_file" 2>/dev/null; then
    if [[ -s "$dossier_file" ]]; then
      log "Feature-Kontext-Dossier erzeugt (${dossier_file})."
      return 0
    fi
  fi
  rm -f "$dossier_file"
  log "Dossier-Erzeugung fehlgeschlagen oder leer (best-effort, E4) — Drain läuft ohne dossier.md weiter."
  state_write "$CUR_PHASE" "$CUR_STORY" "$CUR_DONE" "$CUR_TOTAL" "$CUR_ROUND" "Dossier-Erzeugung fehlgeschlagen (claude -p, best-effort) — ohne dossier.md fortgesetzt" 2>/dev/null || true
  return 0
}

orphaned_story_ids() {
  # Kommagetrennte Liste der Story-IDs mit einem nicht-terminalen Status,
  # der weder "To Do" noch "Blocked" ist (typischerweise "In Progress",
  # liegengeblieben durch eine unterbrochene vorherige /flow-Sitzung — z.B.
  # CI-Timeout, Container-Neustart, abgelaufener Token). Vorfall 2026-07-06
  # (Owner-Testlauf F-065/S-299): board-feature-drain.sh meldete das
  # fälschlich als "BLOCKIERT" und gab sofort auf, obwohl niemand die Story
  # bewusst blockiert hatte — nur eine unterbrochene Sitzung lag vor.
  python3 - "$FEATURE_ID" <<'PYEOF'
import sys, glob, yaml
fid = sys.argv[1]
out = []
for path in glob.glob("board/stories/*.yaml"):
    try:
        with open(path) as f:
            data = yaml.safe_load(f) or {}
    except Exception:
        continue
    if str(data.get("parent", "")).strip() != fid:
        continue
    status = str(data.get("status", "")).strip()
    if status not in ("Done", "Verworfen", "Blocked", "To Do"):
        out.append(str(data.get("id", "")).strip())
print(",".join(out))
PYEOF
}

depends_gate_reason() {
  # Für Storys, die "To Do" sind, aber trotzdem NICHT von `board next` ausgewählt
  # wurden (also durch das Depends-Gate blockiert sind, s. SKILL.md "board next
  # respektiert depends bereits") — liefert eine für den Owner verständliche
  # Erklärung: "<dep-id> (<Status>, gehört zu <dep-Feature>)" je nicht-
  # terminaler Abhängigkeit. Owner-Feedback 2026-07-06: der Button sprang
  # lautlos von "In Progress" zurück auf "Umsetzen", ohne zu erklären, dass
  # eine Abhängigkeit in einem ANDEREN Feature noch offen war.
  python3 - "$FEATURE_ID" <<'PYEOF'
import sys, glob, yaml
fid = sys.argv[1]

def load_all():
    out = {}
    for path in glob.glob("board/stories/*.yaml"):
        try:
            with open(path) as f:
                data = yaml.safe_load(f) or {}
        except Exception:
            continue
        sid = str(data.get("id", "")).strip()
        if sid:
            out[sid] = data
    return out

stories = load_all()
lines = []
for sid, data in stories.items():
    if str(data.get("parent", "")).strip() != fid:
        continue
    if str(data.get("status", "")).strip() != "To Do":
        continue
    for dep in (data.get("depends") or []):
        dep = str(dep).strip()
        dep_data = stories.get(dep)
        if dep_data is None:
            continue
        dep_status = str(dep_data.get("status", "")).strip()
        if dep_status in ("Done", "Verworfen"):
            continue
        dep_parent = str(dep_data.get("parent", "")).strip()
        lines.append(f"{sid} wartet auf {dep} ({dep_status}, gehört zu {dep_parent})")
print("; ".join(lines))
PYEOF
}

sync_to_feature_branch() {
  # Sorgt dafür, dass der lokale Checkout IMMER exakt origin/<Feature-Branch>
  # widerspiegelt, bevor Status gelesen/verändert wird — unabhängig davon,
  # auf welchem Branch eine zuvor gestartete /flow-Kindsitzung den geteilten
  # Arbeitsbaum zurückgelassen hat. Vorfall 2026-07-06: /flow checkt intern
  # eigene Arbeits-/Ziel-Branches aus (§5: board-ship.sh --target-branch
  # feature/<F-###>), board-feature-drain.sh selbst wechselt nie zurück —
  # ohne diesen Sync lasen story_status()/remaining_nonterminal() vom
  # Branch-Stand, den die letzte Kindsitzung zufällig hinterlassen hatte,
  # nicht zwingend vom aktuellen origin/feature/<F-###>.
  #
  # 2026-07-06 (vierte Runde): mehrere unabhängige dev-gui-Automatisierungen
  # (z.B. der normale "Board abarbeiten"-Lauf) teilen sich denselben
  # Arbeitsbaum im Container. Hat eine ANDERE, gerade aktive Sitzung dort eine
  # noch nicht committete Datei liegen, verweigert `git checkout` zu Recht
  # ("would be overwritten by checkout") — sonst ginge deren Arbeit verloren.
  # Das ist kein Fehler in board-feature-drain.sh, sondern ein normaler,
  # VORÜBERGEHENDER Zustand. Statt sofort mit rohem Git-Fehlertext
  # abzubrechen, wird mehrfach mit kurzer Wartezeit erneut versucht; bleibt es
  # blockiert, ein klarer, verständlicher Hinweis statt kryptischer Ausgabe.
  local retries="${BOARD_FEATURE_DRAIN_SYNC_RETRIES:-5}"
  local sleep_s="${BOARD_FEATURE_DRAIN_SYNC_SLEEP:-10}"
  git fetch origin "$FEATURE_BRANCH" --quiet
  local attempt=0 checkout_out=""
  while (( attempt < retries )); do
    attempt=$((attempt + 1))
    if checkout_out="$(git checkout -q "$FEATURE_BRANCH" 2>&1)"; then
      git reset --hard -q "origin/${FEATURE_BRANCH}"
      return 0
    fi
    if checkout_out="$(git checkout -q -b "$FEATURE_BRANCH" "origin/${FEATURE_BRANCH}" 2>&1)"; then
      git reset --hard -q "origin/${FEATURE_BRANCH}"
      return 0
    fi
    if echo "$checkout_out" | grep -q "would be overwritten by checkout"; then
      log "Arbeitsverzeichnis wird gerade von einer anderen Sitzung genutzt — warte ${sleep_s}s und versuche erneut (${attempt}/${retries})."
      sleep "$sleep_s"
      continue
    fi
    die "sync_to_feature_branch: unerwarteter Checkout-Fehler: ${checkout_out}"
  done
  echo "WARTET: Arbeitsverzeichnis wird von einer anderen, aktiven Sitzung belegt (unfertige Datei blockiert den Branch-Wechsel) — bitte in Kürze erneut versuchen."
  exit 3
}

# --- Kandidaten-Check: mindestens 1 Story unter diesem Feature? ---
# Owner-Entscheidung 2026-07-06 (zweite Korrektur): KEINE Mindestanzahl mehr —
# der Button/dieses Skript arbeitet ein Feature unabhängig von der Story-Zahl
# ab (1 Story oder 30), immer über denselben Bündel-Weg (ein Feature-Branch,
# ein finaler Merge). Nur "0 Storys" ist ein echter Fehlerfall.
STORY_COUNT="$(python3 - "$FEATURE_ID" <<'PYEOF'
import sys, glob, yaml
fid = sys.argv[1]
count = 0
for path in glob.glob("board/stories/*.yaml"):
    try:
        with open(path) as f:
            data = yaml.safe_load(f) or {}
    except Exception:
        continue
    if str(data.get("parent", "")).strip() == fid:
        count += 1
print(count)
PYEOF
)"
[[ "$STORY_COUNT" -ge 1 ]] || die "Feature ${FEATURE_ID} hat keine Storys."

log "Feature ${FEATURE_ID}: ${STORY_COUNT} Story/Storys — Batch-Modus aktiv (Feature-Branch ${FEATURE_BRANCH})."

# --- Run-State: Drain-Start, Phase "dossier" (AC9) --------------------------
CUR_PHASE="dossier"
CUR_STORY="-"
CUR_DONE="$(progress_done_count)"
CUR_TOTAL="$STORY_COUNT"
CUR_ROUND=0
state_write "$CUR_PHASE" "$CUR_STORY" "$CUR_DONE" "$CUR_TOTAL" "$CUR_ROUND" "-"

# --- Feature-Branch sicherstellen (von origin/default_branch abzweigen, falls neu) ---
git fetch origin "$DEFAULT_BRANCH" --quiet
if ! git rev-parse "origin/${FEATURE_BRANCH}" >/dev/null 2>&1; then
  git push origin "origin/${DEFAULT_BRANCH}:refs/heads/${FEATURE_BRANCH}" --quiet
  log "Feature-Branch ${FEATURE_BRANCH} neu angelegt (von origin/${DEFAULT_BRANCH})."
fi

# --- Feature-Kontext-Dossier: einmalig, VOR der ersten Story-Session (AC13) ---
generate_dossier

# --- Run-State: Phasenwechsel dossier -> story (AC9) ------------------------
CUR_PHASE="story"
state_write "$CUR_PHASE" "$CUR_STORY" "$CUR_DONE" "$CUR_TOTAL" "$CUR_ROUND" "-"

# --- Hauptschleife: eine frische Story-Sitzung nach der anderen ---
for round in $(seq 1 50); do
  CUR_ROUND="$round"
  sync_to_feature_branch
  NEXT_JSON="$("$BOARD_SCRIPT" next --parent "$FEATURE_ID" 2>/dev/null || true)"

  if [[ -z "$NEXT_JSON" ]]; then
    REMAINING="$(remaining_nonterminal)"
    if [[ -z "$REMAINING" ]]; then
      log "Alle Storys von ${FEATURE_ID} terminal (Done/Verworfen) — Feature komplett, finaler Merge folgt."
      break
    fi

    BLOCKED="$(blocked_story_ids)"
    if [[ -n "$BLOCKED" ]]; then
      log "Feature ${FEATURE_ID} wartet — echte Blockade (status=Blocked): ${BLOCKED}"
      echo "BLOCKIERT: ${REMAINING}"
      exit 3
    fi

    ORPHANED="$(orphaned_story_ids)"
    if [[ -n "$ORPHANED" ]]; then
      log "Feature ${FEATURE_ID}: liegengebliebene Story(s) aus unterbrochener Sitzung (${ORPHANED}) — setze auf 'To Do' zurück und versuche erneut."
      for oid in ${ORPHANED//,/ }; do
        BOARD_WRITER=flow "$BOARD_SCRIPT" set "$oid" status "To Do" --reason "Automatisch zurückgesetzt (board-feature-drain.sh): unterbrochene Sitzung, kein bewusster Blocker" >/dev/null
      done
      if [[ -n "$(git status --porcelain -- board/)" ]]; then
        git add board/
        git commit -q -m "chore(board): ${FEATURE_ID} liegengebliebene Story(s) auf To Do zurückgesetzt (${ORPHANED})"
        git push origin "$FEATURE_BRANCH" --quiet
      fi
      continue
    fi

    # Häufigster Fall: eine "To Do"-Story wartet auf eine noch offene
    # Abhängigkeit (ggf. in einem ANDEREN Feature) — `board next` respektiert
    # das Depends-Gate bereits, wählt so eine Story also nicht aus. Owner-
    # Feedback 2026-07-06: statt eines nichtssagenden "BLOCKIERT" jetzt eine
    # konkrete Erklärung, worauf genau gewartet wird.
    DEPENDS_REASON="$(depends_gate_reason)"
    if [[ -n "$DEPENDS_REASON" ]]; then
      log "Feature ${FEATURE_ID} wartet auf Abhängigkeit(en): ${DEPENDS_REASON}"
      echo "WARTET: ${DEPENDS_REASON}"
      exit 3
    fi

    # Echtes Sicherheitsnetz (REMAINING nicht leer, aber weder Blocked noch
    # orphaned noch durch eine erkennbare Abhängigkeit erklärt) — klare
    # Diagnose statt stillem Hang.
    log "Feature ${FEATURE_ID} wartet — keine Story bereit, unklarer Zustand: ${REMAINING}"
    echo "BLOCKIERT: ${REMAINING}"
    exit 3
  fi

  STORY_ID="$(echo "$NEXT_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')"
  STATUS_BEFORE="$(story_status "$STORY_ID")"
  log "Runde ${round}: nächste Story ${STORY_ID} (Status davor: ${STATUS_BEFORE})"

  # Run-State: Runden-/Story-Wechsel (AC9 — current_story, round, updated_at).
  CUR_STORY="$STORY_ID"
  state_write "$CUR_PHASE" "$CUR_STORY" "$CUR_DONE" "$CUR_TOTAL" "$CUR_ROUND" "-"

  # Frische Story-Sitzung (Story-Ebene, eigener Kontext) — /flow im Feature-Scope.
  "${BOARD_FEATURE_DRAIN_CLAUDE_CMD:-claude}" -p "/agent-flow:flow --parent ${FEATURE_ID}" --dangerously-skip-permissions || true

  sync_to_feature_branch
  STATUS_AFTER="$(story_status "$STORY_ID")"

  # L7-Prinzip: Fortschritt verifizieren statt Ausführung zu vertrauen. Bleibt
  # dieselbe Story trotz eines vollen /flow-Laufs unverändert "To Do", ist das
  # verdächtig (Endlos-Risiko) — abbrechen statt bis Runde 50 blind weiterzulaufen.
  if [[ "$STATUS_BEFORE" == "To Do" && "$STATUS_AFTER" == "To Do" ]]; then
    die "Runde ${round}: ${STORY_ID} blieb trotz /flow-Lauf auf 'To Do' — Verdacht auf Zwischenfall (kein Fortschritt). Manuell prüfen (git log, Worktrees, uncommittete Dateien), nicht automatisch weiterlaufen."
  fi

  # Fortschritt nach der Runde aktualisieren (AC9 — progress bei jedem Wechsel).
  CUR_DONE="$(progress_done_count)"
  state_write "$CUR_PHASE" "$CUR_STORY" "$CUR_DONE" "$CUR_TOTAL" "$CUR_ROUND" "-"
done

# --- Run-State: Phasenwechsel story -> merge (AC9) --------------------------
CUR_PHASE="merge"
CUR_STORY="-"
state_write "$CUR_PHASE" "$CUR_STORY" "$CUR_DONE" "$CUR_TOTAL" "$CUR_ROUND" "-"

# --- Finaler Merge: Feature-Branch → main, EINMAL CI-Watch + Rollout ---
# (board-ship.sh --merge-feature beobachtet CI und rollt selbst aus — aus
# Sicht des Run-State bleibt das für AC9 EINE zusammengehörende Phase
# "merge"->"rollout"; wir markieren "rollout" direkt danach, s.u.)
if [[ -n "$APP_NAME" ]]; then
  "$SHIP_SCRIPT" --merge-feature "$FEATURE_BRANCH" "$APP_NAME"
else
  "$SHIP_SCRIPT" --merge-feature "$FEATURE_BRANCH"
fi

# --- Run-State: Phasenwechsel merge -> rollout (AC9, nach erfolgreichem Merge) ---
CUR_PHASE="rollout"
CUR_DONE="$CUR_TOTAL"
state_write "$CUR_PHASE" "$CUR_STORY" "$CUR_DONE" "$CUR_TOTAL" "$CUR_ROUND" "-"

log "Feature ${FEATURE_ID} vollständig gelandet + deployt."

# --- Last-Run-Eindampfung (AC12): NUR nach erfolgreichem finalen Merge (AC6) ---
# state.yaml bleibt als kompaktes Last-Run-Protokoll stehen (Endphase
# "rollout", progress = total/total, Endzeit) — Zwischen-Arbeitsdateien
# (dossier.md/notes.md-Rohstände) haben für einen späteren Lauf keinen Wert
# mehr und werden entfernt. Ein erneuter Drain-Start überschreibt state.yaml
# ohnehin mit einem frischen Run (kein Anhäufen, s. state_write()).
rm -f "${RUN_DIR}/dossier.md" "${RUN_DIR}/notes.md"

exit 0
