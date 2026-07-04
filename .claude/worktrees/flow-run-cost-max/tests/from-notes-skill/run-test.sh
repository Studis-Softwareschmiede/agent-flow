#!/usr/bin/env bash
# tests/from-notes-skill/run-test.sh
#
# @file Self-Test fuer den Ingest-Pipeline-Skill skills/from-notes/SKILL.md (S-023).
#       Der Skill ist ein Orchestrierungs-Dokument (Prompt), kein ausfuehrbarer Code —
#       daher pruefen diese Tests die bindenden STRUKTUR-/VERDRAHTUNGS-Invarianten
#       gegen docs/specs/obsidian-ingest.md AC11-AC14: valides Frontmatter, die drei
#       Stufen in Reihe, Wiederverwendung der bestehenden Bausteine (Reader S-021,
#       Fragenkatalog-Gate S-022, requirement/architekt/dba) statt Duplikat, Commit
#       pro Stufe in harter Reihenfolge und die Authoring-only-Grenzen. Beruehrt NIE
#       reale Projekt-Docs/Board — reine Lektuere der eingecheckten Skill-Datei.
#
# Covers (obsidian-ingest): AC11, AC12, AC13, AC14
#   AC11 — Fabrik-Befehl /agent-flow:from-notes orchestriert drei Stufen IN REIHE:
#          (a) Korpus -> docs/concept.md, (b) Konzept -> docs/specs/<feature>.md
#          (+ architekt/dba), (c) Spec(s) -> Board-Items ueber den bestehenden
#          requirement-Agenten (kein zweiter Zerlege-Pfad), Status To Do, Items
#          zeigen auf Spec + AC-Nummern.
#   AC12 — Commit pro Stufe, harte Reihenfolge: jede Stufe einzeln committet nach
#          ihrem Katalog; b nach committetem a, c nach committetem b (nicht in einem
#          Rutsch am Ende).
#   AC13 — bestehende Vertraege wiederverwendet, nicht dupliziert: Spec-Vorlage/
#          Stempel/Traceability (Stufe b), requirement-Item-Vertrag inkl. A-priori-
#          Schaetzung size_est/dispo_est (Stufe c).
#   AC14 — Authoring-only: nur docs/, Profilfeld obsidian_source und Board-Items
#          (To Do); kein App-Code, kein /flow-Start, kein Merge/Deploy, kein
#          Schreiben in den Notiz-Ordner.
#
# Exit: 0 = alle Tests bestanden, 1 = mindestens ein Fehler
#
# @trace obsidian-ingest#AC11,AC12,AC13,AC14

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SKILL="${REPO_ROOT}/skills/from-notes/SKILL.md"

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

# lacks <regex> <trace-tag> <beschreibung> — Muster darf NICHT vorkommen (Negativ-Invariante)
lacks() {
  local pat="$1" tag="$2" desc="$3"
  if grep -qiE "$pat" "$SKILL"; then
    fail "$tag — $desc (verbotenes Muster gefunden: /$pat/)"
  else
    pass "$tag — $desc"
  fi
}

# ===========================================================================
# Vorbedingung: Skill-Datei existiert
# ===========================================================================
if [[ -f "$SKILL" ]]; then
  pass "Vorbedingung — skills/from-notes/SKILL.md existiert"
else
  fail "Vorbedingung — skills/from-notes/SKILL.md fehlt"
  echo "from-notes-skill: ${PASS} passed, $(( FAIL + 1 )) failed" >&2
  exit 1
fi

# ===========================================================================
# Frontmatter — Namenskonvention wie andere Skills (name: <verzeichnisname>)
# ===========================================================================
FM_NAME="$(awk 'NR==1&&/^---/{f=1;next} f&&/^---/{exit} f&&/^name:/{sub(/^name:[ \t]*/,"");print;exit}' "$SKILL")"
if [[ "$FM_NAME" == "from-notes" ]]; then
  pass "Frontmatter — name: from-notes (Konvention: name == Verzeichnisname)"
else
  fail "Frontmatter — name-Feld erwartet 'from-notes', bekam '${FM_NAME}'"
fi
if awk 'NR==1&&/^---/{f=1;next} f&&/^---/{exit} f&&/^description:/{ok=1} END{exit !ok}' "$SKILL"; then
  pass "Frontmatter — description-Feld vorhanden"
else
  fail "Frontmatter — description-Feld fehlt"
fi

# ===========================================================================
# AC11 — Befehlsname + drei Stufen in Reihe + Wiring
# ===========================================================================
has '/agent-flow:from-notes'                    "@trace obsidian-ingest#AC11" "Fabrik-Befehl /agent-flow:from-notes benannt"
has 'Stufe a'                                    "@trace obsidian-ingest#AC11" "Stufe a benannt"
has 'Stufe b'                                    "@trace obsidian-ingest#AC11" "Stufe b benannt"
has 'Stufe c'                                    "@trace obsidian-ingest#AC11" "Stufe c benannt"
has 'docs/concept\.md'                           "@trace obsidian-ingest#AC11" "Stufe a Ziel docs/concept.md"
has 'docs/specs/'                                "@trace obsidian-ingest#AC11" "Stufe b Ziel docs/specs/<feature>.md"
has 'requirement'                                "@trace obsidian-ingest#AC11" "Stufe c ueber requirement-Agenten"
has 'To Do'                                      "@trace obsidian-ingest#AC11" "Board-Items Status To Do"
has 'Spec \+ AC-Nummern|Spec-ID \+ AC|Spec \+ die abgedeckten AC|auf .*Spec.*AC-Nummern' \
                                                 "@trace obsidian-ingest#AC11" "Items zeigen auf Spec + AC-Nummern"
has 'obsidian-corpus-read\.sh'                   "@trace obsidian-ingest#AC11" "Reader-Baustein (S-021) verdrahtet"
has 'obsidian-fragenkatalog-validate\.sh'        "@trace obsidian-ingest#AC11" "Fragenkatalog-Gate (S-022) verdrahtet"
has 'architekt'                                  "@trace obsidian-ingest#AC11" "architekt fuer tiefes Architektur-Detail (Stufe b)"
has 'dba'                                         "@trace obsidian-ingest#AC11" "dba fuer Datenmodell (Stufe b)"

# ===========================================================================
# AC12 — Commit pro Stufe, harte Reihenfolge (b nach a, c nach b)
# ===========================================================================
# Drei separate Stufen-Commits (git commit taucht >=3x auf) statt einem Rutsch.
COMMITS="$(grep -cE 'git (add[^&]*&& *)?git? *commit|git commit' "$SKILL" 2>/dev/null || echo 0)"
if [[ "$COMMITS" -ge 3 ]]; then
  pass "@trace obsidian-ingest#AC12 — mindestens drei separate Stufen-Commits (nicht ein Rutsch am Ende)"
else
  fail "@trace obsidian-ingest#AC12 — erwartet >=3 git-commit-Bloecke (Commit pro Stufe), fand ${COMMITS}"
fi
has 'Stufe b startet .*erst nach.*committet' "@trace obsidian-ingest#AC12" "harte Reihenfolge: b erst nach committetem a"
has 'Stufe c startet .*erst nach.*committet' "@trace obsidian-ingest#AC12" "harte Reihenfolge: c erst nach committetem b"
has 'durable|fortsetzbar'                     "@trace obsidian-ingest#AC12" "Zwischenstaende durable / Lauf fortsetzbar"

# ===========================================================================
# AC13 — bestehende Vertraege wiederverwendet, nicht dupliziert
# ===========================================================================
has 'templates/_docs/specs/_template\.md'    "@trace obsidian-ingest#AC13" "Spec-Vorlage wiederverwendet (Stufe b)"
has 'spec_format'                             "@trace obsidian-ingest#AC13" "spec_format-Stempel-Vertrag (Stufe b)"
has 'size_est'                                "@trace obsidian-ingest#AC13" "A-priori-Schaetzung size_est (requirement, Stufe c)"
has 'dispo_est'                               "@trace obsidian-ingest#AC13" "A-priori-Schaetzung dispo_est (requirement, Stufe c)"
has 'kein zweiten? Zerlege|kein zweiter Zerlege|wiederverwend|dupliziert' \
                                              "@trace obsidian-ingest#AC13" "explizite Wiederverwendung statt Duplikat"

# ===========================================================================
# AC14 — Authoring-only: erlaubte Ziele + verbotene Aktionen
# ===========================================================================
has 'Authoring-only'                          "@trace obsidian-ingest#AC14" "Authoring-only als Grenze benannt"
has 'obsidian_source'                         "@trace obsidian-ingest#AC14" "Profilfeld obsidian_source als erlaubtes Schreibziel"
# Negativ-Invarianten: die Pipeline darf diese NICHT ausloesen.
lacks '(startet|loest aus|ruft auf).{0,40}/agent-flow:flow|/flow-Start ausl|dispatcht /flow' \
                                              "@trace obsidian-ingest#AC14" "kein /flow-Start ausgeloest"
# "kein /flow-Start" / "KEIN /flow" als explizite Grenze MUSS vorkommen (positive Absage).
has 'kein .{0,10}/flow-Start|KEIN /flow'      "@trace obsidian-ingest#AC14" "explizite Absage: kein /flow-Start"
has 'kein .{0,20}Merge/Deploy|KEIN Merge'     "@trace obsidian-ingest#AC14" "explizite Absage: kein Merge/Deploy"
has 'kein.{0,30}Schreiben in den Notiz|rein lesend|nie beschrieben' \
                                              "@trace obsidian-ingest#AC14" "explizite Absage: kein Schreiben in den Notiz-Ordner (AC6-Ruecklauf)"
has 'kein.{0,20}App-Code|KEIN App-Code'       "@trace obsidian-ingest#AC14" "explizite Absage: kein App-Code"

# ===========================================================================
# Zusammenfassung
# ===========================================================================
echo ""
echo "from-notes-skill: ${PASS} passed, ${FAIL} failed"
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
exit 0
