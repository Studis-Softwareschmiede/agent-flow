#!/usr/bin/env bash
# tests/from-notes-sync/run-test.sh
#
# @file Self-Test fuer den Re-Sync-Modus (`--sync`) des from-notes-Skills (S-024).
#       Der `--sync`-Modus ist ein eigener Modus DESSELBEN Orchestrierungs-Skills
#       (skills/from-notes/SKILL.md) — ein Prompt, kein ausfuehrbarer Code. Daher
#       pruefen diese Tests die bindenden STRUKTUR-/VERDRAHTUNGS-Invarianten gegen
#       docs/specs/obsidian-sync.md AC1-AC6: eigener Modus + geteilte Basis (Reader
#       S-021, Fragenkatalog-Gate S-022) bei unangetastetem Reconcile-Vertrag, das
#       4-Feld-Divergenz-Bericht-Format (reiner Bericht, kein Gate), das Verbot des
#       Blind-Overwrite (invertierte Reconcile-Autoritaet), genau EIN Fragenkatalog
#       (stage:sync, je Divergenz uebernehmen/behalten/manuell, nur uebernehmen
#       schreibt), Deckungsgleichheit ohne Katalog/Aenderung und die rein-lesende +
#       kein-Folge-Automatismus-Grenze. Ein Live-Teil prueft zusaetzlich, dass ein
#       sync-Katalog mit den drei Richtungs-Optionen den WIEDERVERWENDETEN Gate-
#       Validator besteht (AC4). Beruehrt NIE reale Projekt-Docs/Board/Notizen.
#
# Covers (obsidian-sync): AC1, AC2, AC3, AC4, AC5, AC6
# Covers (from-notes-areas): AC5
#
#   (from-notes-areas)
#   AC5 — Re-Sync-Modus respektiert bestehende areas.yaml: unassignierte Themen
#         als Fragenkatalog-Punkte (stage:sync) mit Bereichs-Zuordnungs-Optionen
#         vorgeschlagen; Rauscharmut wenn keine bereichsfremden Themen;
#         Owner-Entscheid neuer-bereich/skippen/bereich-zuordnung.
#   (obsidian-sync)
#   AC1  — Eigener Modus, geteilte Basis: /agent-flow:from-notes --sync ist ein
#          eigener Modus desselben Skills; nutzt obsidian_source + Notiz-Korpus-Reader
#          + aktuellen docs/concept.md/docs/specs/*-Stand als die zwei Vergleichsseiten;
#          KEIN Reconcile-"Stufe 0", Reconcile-Vertrag bleibt unangetastet.
#   AC2  — Erkennen + Melden: priorisierter Bericht, je Fund notiz_fundstelle +
#          doku_ziel (Dokument+Sektion) + divergenz_art + richtungsvorschlag; reiner
#          Bericht, KEIN Gate, KEINE automatischen Board-Items.
#   AC3  — Kein Blind-Overwrite (invertierte Reconcile-Autoritaet): ueberschreibt
#          Konzept/Spec NIE automatisch; jede Divergenz = User-Entscheid vor jeder
#          Doku-Aenderung.
#   AC4  — Ein Katalog, gerichteter Entscheid, selektives Schreiben: genau EIN
#          Fragenkatalog (Format wie obsidian-ingest AC9, stage:sync), je Divergenz
#          uebernehmen/behalten/manuell; nur "uebernehmen" wird geschrieben. Der
#          wiederverwendete Gate-Validator akzeptiert einen solchen sync-Katalog.
#   AC5  — Kein Rauschen bei Deckungsgleichheit: keine Divergenz -> kein Katalog,
#          keine Aenderung, klare "deckungsgleich"-Meldung.
#   AC6  — Rein lesend + kein Folge-Automatismus: Notiz-Ordner nie beschrieben; kein
#          /flow-Start, keine automatische Story-Anlage; obsidian_source fehlt/unlesbar
#          -> klarer Abbruch (wie obsidian-ingest AC2/AC5).
#
# Exit: 0 = alle Tests bestanden, 1 = mindestens ein Fehler
#
# @trace obsidian-sync#AC1,AC2,AC3,AC4,AC5,AC6
# @trace from-notes-areas#AC5

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SKILL="${REPO_ROOT}/skills/from-notes/SKILL.md"
VALIDATE="${REPO_ROOT}/scripts/obsidian-fragenkatalog-validate.sh"

FAIL=0
PASS=0
fail() { echo "FAIL: $*" >&2; FAIL=$(( FAIL + 1 )); }
pass() { echo "PASS: $*"; PASS=$(( PASS + 1 )); }

# has <regex> <trace-tag> <beschreibung> — case-insensitiv, multi-line-tolerant
has() {
  local pat="$1" tag="$2" desc="$3"
  if grep -qiE "$pat" "$SKILL"; then
    pass "$tag — $desc"
  else
    fail "$tag — $desc (Muster fehlt: /$pat/)"
  fi
}

# ===========================================================================
# Vorbedingung: Skill-Datei + wiederverwendeter Gate-Validator existieren
# ===========================================================================
if [[ -f "$SKILL" ]]; then
  pass "Vorbedingung — skills/from-notes/SKILL.md existiert"
else
  fail "Vorbedingung — skills/from-notes/SKILL.md fehlt"
  echo "from-notes-sync: ${PASS} passed, $(( FAIL + 1 )) failed" >&2
  exit 1
fi
if [[ -x "$VALIDATE" ]]; then
  pass "Vorbedingung — scripts/obsidian-fragenkatalog-validate.sh (wiederverwendetes Gate) vorhanden"
else
  fail "Vorbedingung — scripts/obsidian-fragenkatalog-validate.sh fehlt/nicht ausfuehrbar"
fi

# ===========================================================================
# AC1 — Eigener Modus, geteilte Basis, Reconcile unangetastet
# ===========================================================================
has 'from-notes --sync|--sync'               "@trace obsidian-sync#AC1" "eigener Modus /agent-flow:from-notes --sync benannt"
has 'eigener Modus'                          "@trace obsidian-sync#AC1" "als eigener Modus desselben Skills gekennzeichnet"
has 'obsidian_source'                        "@trace obsidian-sync#AC1" "persistierter obsidian_source als Notiz-Quelle wiederverwendet"
has 'obsidian-corpus-read\.sh'               "@trace obsidian-sync#AC1" "Notiz-Korpus-Reader (S-021) als linke Vergleichsseite wiederverwendet"
has 'docs/concept\.md'                       "@trace obsidian-sync#AC1" "aktueller docs/concept.md-Stand als Vergleichsseite"
has 'docs/specs/\*|docs/specs/'              "@trace obsidian-sync#AC1" "aktueller docs/specs/*-Stand als Vergleichsseite"
has 'reconcile-subsystem\.md'               "@trace obsidian-sync#AC1" "Abgrenzung zum Reconcile-Vertrag benannt"
has 'Reconcile-Vertrag.{0,40}unangetastet|Reconcile.{0,40}unangetastet' \
                                             "@trace obsidian-sync#AC1" "Reconcile-Vertrag bleibt unangetastet"
has 'Reconcile-.{0,6}Stufe.{0,3}0'           "@trace obsidian-sync#AC1" "explizite Absage: kein Reconcile-Stufe-0"

# ===========================================================================
# AC2 — Erkennen + Melden: 4-Feld-Bericht, reiner Bericht (kein Gate/Board-Items)
# ===========================================================================
has 'notiz_fundstelle'                       "@trace obsidian-sync#AC2" "Bericht-Feld notiz_fundstelle"
has 'doku_ziel'                              "@trace obsidian-sync#AC2" "Bericht-Feld doku_ziel (Dokument+Sektion)"
has 'divergenz_art'                          "@trace obsidian-sync#AC2" "Bericht-Feld divergenz_art"
has 'richtungsvorschlag'                     "@trace obsidian-sync#AC2" "Bericht-Feld richtungsvorschlag"
has 'priorisiert'                            "@trace obsidian-sync#AC2" "Bericht ist priorisiert"
has 'kein.{0,6}Gate'                         "@trace obsidian-sync#AC2" "reiner Bericht — kein Gate"
has 'keine.{0,40}Board-Items'                "@trace obsidian-sync#AC2" "kein automatisches Anlegen von Board-Items"

# ===========================================================================
# AC3 — Kein Blind-Overwrite (invertierte Reconcile-Autoritaet)
# ===========================================================================
has 'Blind-Overwrite'                        "@trace obsidian-sync#AC3" "kein Blind-Overwrite als Grenze benannt"
has 'invertierte Reconcile-Autorit'          "@trace obsidian-sync#AC3" "invertierte Reconcile-Autoritaet benannt"
has 'nie automatisch|nie.{0,20}automatisch'  "@trace obsidian-sync#AC3" "Konzept/Spec wird nie automatisch ueberschrieben"
has 'User-Entscheid|zur Entscheidung'        "@trace obsidian-sync#AC3" "jede Divergenz = User-Entscheid vor Doku-Aenderung"

# ===========================================================================
# AC4 — Genau EIN Fragenkatalog, gerichteter Entscheid, selektives Schreiben
# ===========================================================================
has 'genau EIN.{0,4} Fragenkatalog'          "@trace obsidian-sync#AC4" "genau EIN Fragenkatalog (nicht Einzel-Prompts)"
has 'stage:"sync"|stage.{0,4}sync'           "@trace obsidian-sync#AC4" "Katalog-Stage sync (Format wie obsidian-ingest AC9)"
has 'obsidian-fragenkatalog-validate\.sh'    "@trace obsidian-sync#AC4" "wiederverwendetes Fragenkatalog-Gate verdrahtet"
has 'uebernehmen.{0,6}behalten.{0,6}manuell' "@trace obsidian-sync#AC4" "je Divergenz die drei Richtungen uebernehmen/behalten/manuell"
has 'nur.{0,10}uebernehmen|nur die als .uebernehmen' \
                                             "@trace obsidian-sync#AC4" "nur uebernehmen schreibt; behalten/manuell aendern nichts"
has 'bereichsfremd.*Thema|unassigniert.*Thema|Thema.*keinem.*Bereich' \
                                             "@trace from-notes-areas#AC5" "Erkennung bereichsfremder Themen im Re-Sync (AC5)"
has 'neuer-bereich|skippen'                  "@trace from-notes-areas#AC5" "Optionen fuer unassignierte Themen: Bereichs-Zuordnung + neuer-bereich + skippen (AC5)"

# ---- Live-Probe: ein sync-Katalog mit den drei Optionen besteht den Gate-Validator ----
SYNC_CAT='[{"stage":"sync","id":"sync-1","frage":"Notiz idee.md nennt Offline-Modus, docs/concept.md §Scope schliesst ihn aus — Richtung?","quelle":"idee.md -> docs/concept.md §Scope","optionen":["uebernehmen","behalten","manuell"]}]'
set +e
SYNC_OUT="$(printf '%s' "$SYNC_CAT" | bash "$VALIDATE" 2>/dev/null)"
SYNC_RC=$?
set -e
if [[ "$SYNC_OUT" == "valid" && "$SYNC_RC" -eq 0 ]]; then
  pass "@trace obsidian-sync#AC4 — sync-Katalog (stage:sync + uebernehmen/behalten/manuell) besteht den wiederverwendeten Gate-Validator -> valid"
else
  fail "@trace obsidian-sync#AC4 — sync-Katalog: erwartet valid/0, bekam Out='${SYNC_OUT}' RC=${SYNC_RC}"
fi

# ---- Negativ: manuell erfundenes 5. Feld (z.B. entscheid) waere Vertragsverletzung ----
SYNC_BAD='[{"stage":"sync","id":"sync-1","frage":"?","quelle":"idee.md","optionen":["uebernehmen"],"entscheid":"uebernehmen"}]'
set +e
BAD_OUT="$(printf '%s' "$SYNC_BAD" | bash "$VALIDATE" 2>/dev/null)"
BAD_RC=$?
set -e
if [[ "$BAD_RC" -eq 1 && -z "$BAD_OUT" ]]; then
  pass "@trace obsidian-sync#AC4 — sync-Katalog mit Fremdfeld -> Exit 1 (Formatvertrag greift auch fuer stage:sync)"
else
  fail "@trace obsidian-sync#AC4 — sync-Katalog Fremdfeld: erwartet Exit 1/kein Token, bekam Out='${BAD_OUT}' RC=${BAD_RC}"
fi

# ---- Live-Probe AC5 from-notes-areas: sync-Katalog fuer unassignierte Themen besteht den Gate-Validator ----
SYNC_TOPIC='[{"stage":"sync","id":"sync-1","frage":"Notiz nennt Thema \"Offline-Modus\", das in board/areas.yaml keinem Bereich zugeordnet ist — Richtung?","quelle":"idee.md §Scope -> board/areas.yaml","optionen":["bereich-frontend","bereich-backend","neuer-bereich","skippen"]}]'
set +e
TOPIC_OUT="$(printf '%s' "$SYNC_TOPIC" | bash "$VALIDATE" 2>/dev/null)"
TOPIC_RC=$?
set -e
if [[ "$TOPIC_OUT" == "valid" && "$TOPIC_RC" -eq 0 ]]; then
  pass "@trace from-notes-areas#AC5 — sync-Katalog fuer unassigniertes Thema (stage:sync + bereich-*/neuer-bereich/skippen) besteht den wiederverwendeten Gate-Validator -> valid"
else
  fail "@trace from-notes-areas#AC5 — sync-Katalog unassigniertes Thema: erwartet valid/0, bekam Out='${TOPIC_OUT}' RC=${TOPIC_RC}"
fi

# ===========================================================================
# AC5 — Kein Rauschen bei Deckungsgleichheit
# ===========================================================================
has 'deckungsgleich'                         "@trace obsidian-sync#AC5" '"deckungsgleich"-Meldung bei keiner Divergenz'
has 'keine Divergenz.{0,80}kein.{0,20}Fragenkatalog|kein.{0,20}Fragenkatalog.{0,80}keine' \
                                             "@trace obsidian-sync#AC5" "keine Divergenz -> kein Fragenkatalog"
has 'keine.{0,20}(Doku-)?.nderung|keine Doku-.nderung' \
                                             "@trace obsidian-sync#AC5" "keine Divergenz -> keine Doku-Aenderung"

# ===========================================================================
# AC6 — Rein lesend + kein Folge-Automatismus + Abbruch bei fehlender Quelle
# ===========================================================================
has 'rein lesend'                            "@trace obsidian-sync#AC6" "Re-Sync ist rein lesend gegenueber den Notizen"
has 'nie beschrieben|nie.{0,20}beschrieben'  "@trace obsidian-sync#AC6" "Notiz-Ordner wird nie beschrieben"
has 'kein .{0,4}/flow-Start|KEIN /flow|kein.{0,8}/flow'  "@trace obsidian-sync#AC6" "kein /flow-Start"
has 'keine.{0,20}Stor(y|ies).{0,20}automatisch|keine automatische Story-Anlage' \
                                             "@trace obsidian-sync#AC6" "keine automatische Story-Anlage"
has 'klarer Abbruch'                         "@trace obsidian-sync#AC6" "obsidian_source fehlt/unlesbar -> klarer Abbruch (wie obsidian-ingest)"

# ===========================================================================
# Zusammenfassung
# ===========================================================================
echo ""
echo "from-notes-sync: ${PASS} passed, ${FAIL} failed"
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
exit 0
