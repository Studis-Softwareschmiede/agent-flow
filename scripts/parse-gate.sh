#!/usr/bin/env bash
# scripts/parse-gate.sh <rolle> [<handoff-datei>]
#
# Deterministischer Gate-Token-Parser (Stufe 1, Phase A des
# `flow-deterministic-runner`-Konzepts, docs/architecture/flow-deterministic-runner.md
# §1.5 S3.3/S4.1, §8 Skript-Schnitt). Liest den Klartext-Handoff eines
# reviewer-/dba-/tester-Agenten und extrahiert das Gate-Token MECHANISCH --
# ohne LLM-Aufruf. Kein Verhaltensdelta zu heute (AC3): dieselben Gate-Tokens,
# dieselbe Rollen-Zuordnung wie skills/flow/SKILL.md §3/§4.
#
# Erlaubte Rollen + Token (exakt diese, keine anderen -- AC3):
#   reviewer | dba  ->  Review-Gate: PASS | CHANGES-REQUIRED
#   tester          ->  Test-Gate:   PASS | FAIL | SKIPPED-NO-DOCKER | SKIPPED-DOC-ONLY |
#                                    SKIPPED-NO-BUILD
#
# Bewusst EXPLIZITE Aufzählung (kein generisches "SKIPPED-[A-Z-]+"-Suffix-
# Muster), obwohl AC3 den Test-Gate-Wertebereich in Prosa als "SKIPPED-*"
# abkürzt: das Detailkonzept (§5.1) nennt "ein neuer SKIPPED-*-Wert" selbst
# ausdrücklich als Auslöser für die Judge-Eskalation ("unbekanntes Token"),
# NICHT als Fall für stillschweigendes Akzeptieren. Ein Suffix-Wildcard
# würde ausserdem einen Tippfehler im Suffix (z.B. "SKIPPED-NO-DOCKR")
# ebenso still durchwinken wie einen echten neuen Wert -- das widerspricht
# AC7 (kein stilles Raten) und dem Q7-HART-Entscheid (exakt-Regex, nur
# Whitespace-Normalisierung, sonst mehrdeutig). Ein fünfter, HEUTE bereits
# produktiv genutzter Token (`SKIPPED-NO-BUILD`, agents/tester.md §Gate,
# `profile.build == none`) wird deshalb explizit ergänzt statt generisch
# zugelassen.
#
# Parser-Strenge (Owner-Entscheid Q7 = Option c, HART -- §9 Q7 des
# Detailkonzepts): exakter Regex-Match zuerst. Erlaubte Normalisierung ist
# NUR:
#   - führendes/nachfolgendes Whitespace je Zeile trimmen
#   - mehrfache Leerzeichen um den Doppelpunkt tolerieren
# SONST NICHTS -- keine Case-Insensitivität, kein Fuzzy-Match, keine
# Synonym-Liste. Das deckt sich mit dem `board-ship.sh`-Grundsatz K1
# ("prüft, statt zu behaupten -- bei jeder Unklarheit Abbruch/Eskalation
# statt Raten", S-047-Vorfall) und AC7 dieser Spec.
#
# Eine Zeile zählt NUR, wenn sie (nach Trimmen) am ZEILENANFANG beginnt --
# eine Gate-Zeile mitten in Prosa eingebettet ("Der Status ist Review-Gate:
# PASS heute.") matcht bewusst NICHT (kein Fuzzy-Match, AC7/A1).
#
# Mehrere Gate-Zeilen im selben Handoff sind KEIN Problem, solange sie
# denselben Token tragen (nicht widersprüchlich) -- der Runner soll nicht an
# einer harmlosen Wiederholung scheitern. Tragen sie unterschiedliche Token
# (widersprüchlich), ist das Ergebnis mehrdeutig.
#
# Ausgabe (stdout) bei eindeutigem Treffer: NUR der bare Token-Wert
# (z.B. "PASS", "CHANGES-REQUIRED", "SKIPPED-NO-DOCKER") -- NICHT die
# gesamte "Review-Gate: PASS"-Zeile. Der Aufrufer (künftig
# scripts/board-round.sh) branch't direkt auf diesem Wert.
#
# Exit-Codes (Vertrag, dieses Skript ruft KEINEN Judge -- das ist Aufgabe
# des Aufrufers/board-round.sh in S-128, §5.1 des Detailkonzepts):
#   0 = eindeutiger Treffer, Token auf stdout
#   1 = Aufruf-/Eingabefehler (fehlende/unbekannte Rolle, Datei fehlt/
#       unlesbar) -- kein Handoff-Inhaltsproblem, sondern falscher Gebrauch
#   2 = mehrdeutig / kein Treffer (Zeile fehlt, widersprüchliche Zeilen,
#       unbekanntes Token, Zeile nicht am Zeilenanfang) -- kein Raten, kein
#       Default (AC7). Aufrufer eskaliert an das leichte LLM-Urteil (Judge).
#
# Eingabe: <handoff-datei> als zweites Argument, ODER Klartext auf stdin,
# wenn das Argument weggelassen wird.

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"

usage() {
  cat >&2 <<EOF
Usage: ${SCRIPT_NAME} <rolle> [<handoff-datei>]
  rolle: reviewer | dba | tester
  Ohne <handoff-datei>: Handoff-Text wird von stdin gelesen.
EOF
}

die_usage() {
  echo "FEHLER [${SCRIPT_NAME}]: $*" >&2
  usage
  exit 1
}

die_ambiguous() {
  echo "AMBIGUOUS [${SCRIPT_NAME}]: $*" >&2
  exit 2
}

ROLE="${1:-}"
HANDOFF_FILE="${2:-}"

[ -n "$ROLE" ] || die_usage "Rolle fehlt"

case "$ROLE" in
  reviewer|dba)
    GATE_NAME="Review-Gate"
    TOKEN_ALTERNATION="PASS|CHANGES-REQUIRED"
    ;;
  tester)
    GATE_NAME="Test-Gate"
    TOKEN_ALTERNATION="PASS|FAIL|SKIPPED-NO-DOCKER|SKIPPED-DOC-ONLY|SKIPPED-NO-BUILD"
    ;;
  *)
    die_usage "unbekannte Rolle '${ROLE}' (erlaubt: reviewer, dba, tester)"
    ;;
esac

if [ -n "$HANDOFF_FILE" ]; then
  [ -r "$HANDOFF_FILE" ] || die_usage "Handoff-Datei nicht lesbar: ${HANDOFF_FILE}"
  HANDOFF_TEXT="$(cat "$HANDOFF_FILE")"
else
  HANDOFF_TEXT="$(cat -)"
fi

# Zeilen-Pattern: Gate-Name [ws]* : [ws]* TOKEN [ws]* -- ausschliesslich am
# Zeilenanfang der (bereits getrimmten) Zeile.
PATTERN="^${GATE_NAME}[[:space:]]*:[[:space:]]*(${TOKEN_ALTERNATION})[[:space:]]*\$"

# Zeilen trimmen (führendes/nachfolgendes Whitespace -- die einzige erlaubte
# Normalisierung neben "mehrfache Leerzeichen um den Doppelpunkt", die das
# Pattern selbst über [[:space:]]* abdeckt).
TRIMMED_LINES="$(printf '%s\n' "$HANDOFF_TEXT" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"

MATCHES="$(printf '%s\n' "$TRIMMED_LINES" | grep -E "$PATTERN" || true)"

if [ -z "$MATCHES" ]; then
  die_ambiguous "keine eindeutige ${GATE_NAME}-Zeile im Handoff gefunden"
fi

# Distinkte Token-Werte aus den Treffern extrahieren -- mehrere Zeilen mit
# IDENTISCHEM Token sind kein Widerspruch (harmlose Wiederholung).
TOKENS="$(printf '%s\n' "$MATCHES" | sed -E "s/^${GATE_NAME}[[:space:]]*:[[:space:]]*//; s/[[:space:]]+\$//" | sort -u)"
TOKEN_COUNT="$(printf '%s\n' "$TOKENS" | grep -c . || true)"

if [ "$TOKEN_COUNT" -ne 1 ]; then
  die_ambiguous "widersprüchliche ${GATE_NAME}-Zeilen im Handoff: $(printf '%s' "$TOKENS" | tr '\n' ' ' | sed -E 's/[[:space:]]+$//')"
fi

printf '%s\n' "$TOKENS"
exit 0
