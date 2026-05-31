#!/usr/bin/env bash
# run-all.sh — Führt alle 4 Smoke-Tests des DB-Subsystems sequenziell aus.
#
# Pro Dialekt wird `smoke-<dialect>.sh` aufgerufen, stdout/stderr ins
# Test-Log gespiegelt, Exit-Code gesammelt. Final-Output: Übersicht
# "N/4 PASS" + Liste fehlgeschlagener Dialekte mit Log-Pfad.
#
# Exit:
#   0  — alle 4 grün
#   1  — mindestens einer rot
#
# Voraussetzungen: Docker-Daemon läuft, mind. 2 GB freier RAM (mongo
# + mariadb sind die Speicherschwergewichte). Spec §13.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

DIALECTS=(postgres mysql sqlite mongodb)
LOG_DIR="${LOG_DIR:-$(mktemp -d "/tmp/db-smoke-runs-XXXXXX")}"

printf 'Running DB-subsystem smoke tests — logs in %s\n\n' "$LOG_DIR"

declare -A RESULT=()
declare -A LOGFILE=()

for d in "${DIALECTS[@]}"; do
  script="$SCRIPT_DIR/smoke-${d}.sh"
  logf="$LOG_DIR/smoke-${d}.log"
  LOGFILE[$d]="$logf"

  if [ ! -x "$script" ]; then
    printf '%-10s SKIP (script not executable: %s)\n' "$d" "$script"
    RESULT[$d]="SKIP"
    continue
  fi

  printf '%-10s RUNNING ... ' "$d"
  if "$script" >"$logf" 2>&1; then
    RESULT[$d]="PASS"
    printf 'PASS\n'
  else
    rc=$?
    RESULT[$d]="FAIL($rc)"
    printf 'FAIL (exit %d)\n' "$rc"
  fi
done

# ---- Zusammenfassung ----
pass=0
fail=0
for d in "${DIALECTS[@]}"; do
  case "${RESULT[$d]:-?}" in
    PASS)   pass=$((pass + 1)) ;;
    FAIL*)  fail=$((fail + 1)) ;;
  esac
done
total="${#DIALECTS[@]}"

printf '\n========================================\n'
printf 'Summary: %d/%d PASS\n' "$pass" "$total"
printf '========================================\n'

if [ "$fail" -gt 0 ]; then
  printf '\nFailures:\n'
  for d in "${DIALECTS[@]}"; do
    case "${RESULT[$d]:-?}" in
      FAIL*)
        # Letzte FAIL-Zeile aus dem Log fischen für schnellen Hint
        hint="$(grep -m1 'FAIL:' "${LOGFILE[$d]}" 2>/dev/null || echo 'see log')"
        printf '  %s — %s\n    log:  %s\n    hint: %s\n' "$d" "${RESULT[$d]}" "${LOGFILE[$d]}" "$hint"
        ;;
    esac
  done
  exit 1
fi

printf '\nAll dialects green. Logs retained in %s.\n' "$LOG_DIR"
exit 0
