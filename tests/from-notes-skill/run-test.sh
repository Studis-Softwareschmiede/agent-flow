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
# Covers (from-notes-areas): AC1, AC2, AC3, AC4, AC5
#   AC5 — Re-Sync-Modus respektiert bestehende areas.yaml: unassignierte Themen
#         als Fragenkatalog-Punkte (stage:sync) mit Bereichs-Zuordnungs-Optionen
#         vorgeschlagen; niemals selbst Bereich angelegt (nur Owner-Entscheid).
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
#   (from-notes-areas)
#   AC1 — Nach docs/concept.md-Erzeugung areas.yaml-Entwurf ableiten (id/titel/
#         beschreibung/reihenfolge, kebab-case, 1 Satz, eindeutig) konform
#         board-areas AC1; bei leerem Entwurf Platzhalter oder dokumentiert uebersp.
#   AC2 — Entwurf ueber bestehendes Fragenkatalog-Gate als Teil Stufe-a-Katalog
#         vorlegen (stage:a, je Bereich Streichen/Ergaenzen/Bestaetigen);
#         unstrittig + eindeutig -> Auto-Durchlauf.
#   AC3 — Nach Beantwortung/Bestaetigung board/areas.yaml mit bestaetigung Bereichen
#         schreiben; Schreibvorgang im Stufe-a-Commit; Notiz-Ordner nie beschrieben.
#   AC4 — Board-Stufe c legt Storys ausschliesslich unter Bereichs-Features bestätigter
#         Bereiche an (Story-parent = Bereichs-Feature, neue Spec mit area:<bereich>);
#         kein Item ohne Bereich, keine autonome Bereichs-Erfindung (requirement führt
#         Bereichs-Gate durch, liest bestätigte Bereiche aus areas.yaml). Edge-Case E1:
#         fehlt areas.yaml oder keine Bereiche bestätigt -> verhält sich wie ohne
#         Bereichs-Gate und vermerkt das im Output (no-op, keine Specs ohne area).
#
# Exit: 0 = alle Tests bestanden, 1 = mindestens ein Fehler
#
# @trace obsidian-ingest#AC11,AC12,AC13,AC14
# @trace from-notes-areas#AC1,AC2,AC3,AC4,AC5

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
# AC1–AC3 (from-notes-areas) — Areas-Entwurf in Stufe a
# ===========================================================================
has 'Areas-Entwurf|areas\.yaml-Entwurf'       "@trace from-notes-areas#AC1" "Bereich-Entwurf-Schritt erkannt (AC1)"
has 'Scope|Konzept.*ableiten'                 "@trace from-notes-areas#AC1" "Ableitung aus Konzept-Scope (AC1)"
has 'kebab-case|reihenfolge.*int|titel.*beschreibung' \
                                              "@trace from-notes-areas#AC1" "Feldformat id/titel/beschreibung/reihenfolge (AC1)"
has 'Platzhalter'                             "@trace from-notes-areas#AC1" "Platzhalter bei leerem Entwurf (E1)"

has 'Fragenkatalog.*mit.*Area|Area.*Fragenkatalog' \
                                              "@trace from-notes-areas#AC2" "Areas in Fragenkatalog integriert (AC2)"
has 'Streichen.*Erg.{0,3}nzen|Best.{0,3}tigung' "@trace from-notes-areas#AC2" "Streichen/Ergaenzen/Bestaetigen pro Bereich (AC2)"
has 'a-[0-9]+|stage.*a.*Bereich'              "@trace from-notes-areas#AC2" "Area-Fragen im stage:a-Katalog mit Muster a-<n> (AC2)"
has 'Auto-Durchlauf.*Area|unstrittig'         "@trace from-notes-areas#AC2" "Auto-Durchlauf bei eindeutigem Entwurf (A1)"

has 'board/areas\.yaml.*schreiben|areas\.yaml.*Commit' \
                                              "@trace from-notes-areas#AC3" "board/areas.yaml wird geschrieben (AC3)"
has 'best.{0,3}tigt.*Bereich|best.{0,3}tigte' "@trace from-notes-areas#AC3" "Nur bestaatigte Bereiche in areas.yaml (AC3)"
has 'Stufe.*a.*Commit.*areas|notes\(a\).*areas' \
                                              "@trace from-notes-areas#AC3" "Schreiben faehrt im Stufe-a-Commit (AC3)"

# ===========================================================================
# AC4 (from-notes-areas) — Stufe c mit Bereichs-Gate (bestätigte Bereiche)
# ===========================================================================
has 'Stufe c.*Bereichs-Gate|Bereichs-Gate.*Stufe c|bestätigt.*Bereiche.*Stufe c' \
                                              "@trace from-notes-areas#AC4" "Stufe c mit Bereichs-Gate (AC4)"
has 'requirement.*Bereichs-Gate|requirement.*bestätigt' \
                                              "@trace from-notes-areas#AC4" "requirement-Agent führt Bereichs-Gate durch (AC4)"
has 'areas\.yaml.*liest|liest.*areas\.yaml|bestätigt.*Bereich.*aus.*areas' \
                                              "@trace from-notes-areas#AC4" "Bestätigte Bereiche aus areas.yaml gelesen (AC4)"
has 'Story.*parent.*Bereichs-Feature|parent.*Bereichs-Feature' \
                                              "@trace from-notes-areas#AC4" "Story-parent = Bereichs-Feature (AC4)"
has 'area:.*bereich|area.*Frontmatter|area.*stempel' \
                                              "@trace from-notes-areas#AC4" "Neue Specs mit area:<bereich> gestempelt (AC4)"
has 'kein.*Item.*ohne.*Bereich|keine autonome.*Bereichs-Erfindung' \
                                              "@trace from-notes-areas#AC4" "Kein Item ohne Bereich, keine autonome Erfindung (AC4)"
has 'Edge-Case E1|E1.*Bereich|areas\.yaml.*fehlt.*Gate|keine.*Bereiche.*Gate' \
                                              "@trace from-notes-areas#AC4" "Edge-Case E1: areas.yaml fehlt/leer (AC4)"
has 'Ideen-Inbox|bereichsfremd'               "@trace from-notes-areas#AC4" "Bereichsfremde Specs in Ideen-Inbox (AC4)"

# ===========================================================================
# AC5 (from-notes-areas) — Re-Sync respektiert bestehende areas.yaml, schlägt unassignierte Themen vor
# ===========================================================================
has 'sync.*areas\.yaml|Re-Sync.*areas\.yaml' \
                                              "@trace from-notes-areas#AC5" "Re-Sync-Modus respektiert bestehende areas.yaml (AC5)"
has 'bereichsfremd.*Thema|Thema.*bereichsfremd' \
                                              "@trace from-notes-areas#AC5" "Bereichsfremde Themen im Notiz-Stand erkannt (AC5)"
has 'Fragenkatalog-Punkt.*sync|stage:.*sync.*Bereich' \
                                              "@trace from-notes-areas#AC5" "Unassignierte Themen als Fragenkatalog-Punkte (stage:sync) vorgeschlagen (AC5)"
has 'nie.*selbst.*Bereich.*anlegen|nie.*auto|invertierte Autorität' \
                                              "@trace from-notes-areas#AC5" "Niemals selbst Bereich anlegen — nur Owner-Entscheid (AC5)"
has 'neuer-bereich.*Owner-Entscheid|Owner-Entscheid.*neuer-bereich' \
                                              "@trace from-notes-areas#AC5" "Option 'neuer-bereich' für Owner-Entscheid, nicht auto-Erstellung (AC5)"
has 'Rauscharmut|keine.*bereichsfremd.*keine.*Katalog' \
                                              "@trace from-notes-areas#AC5" "Kein Katalog-Punkt wenn keine bereichsfremden Themen (Rauscharmut, AC5)"

# ===========================================================================
# Schema-Kompatibilität: a-<n>-Muster gegen echten Validator (Critical Fix Iter-2)
# ===========================================================================
# coder/L39: neues id-Muster fuer Fragenkatalog MUSS gegen echten Validator laufen,
# nicht nur gegen die Prosa-Beschreibung. Dieser Test verifiziert, dass a-<n>-Muster
# (fuer beide Konzept- und Area-Fragen) durch board/fragenkatalog.schema.json
# und scripts/obsidian-fragenkatalog-validate.sh validiert (nicht: a-area-<n>).
VALIDATOR="${REPO_ROOT}/scripts/obsidian-fragenkatalog-validate.sh"
if [[ -f "$VALIDATOR" ]]; then
  # Beispiel-Katalog: zwei Fragen mit schema-kompatiblem a-<n>-Muster
  TEST_CATALOG='[
    {"stage":"a","id":"a-1","frage":"Beispiel-Konzept-Frage?","quelle":"Beispiel-Notiz.md"},
    {"stage":"a","id":"a-2","frage":"Beispiel-Area bestaetigen?","quelle":"Konzept-Abschnitt","optionen":["bestaetigen","streichen","aendern"]}
  ]'

  # Durch Validator schicken — muss Exit 0 sein
  if printf '%s' "$TEST_CATALOG" | bash "$VALIDATOR" >/dev/null 2>&1; then
    pass "Schema-Kompatibilität — a-<n>-Muster (Konzept + Area) validiert Exit 0 durch echten Validator"
  else
    fail "Schema-Kompatibilität — a-<n>-Muster validierung fehlgeschlagen (sollte Exit 0 sein)"
  fi
else
  fail "Vorbedingung — Validator-Skript $VALIDATOR fehlt"
fi

# ===========================================================================
# Zusammenfassung
# ===========================================================================
echo ""
echo "from-notes-skill: ${PASS} passed, ${FAIL} failed"
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
exit 0
