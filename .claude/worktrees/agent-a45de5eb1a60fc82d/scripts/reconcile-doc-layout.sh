#!/usr/bin/env bash
# scripts/reconcile-doc-layout.sh — Layout-Erkennung fuer den "Dokument fehlt komplett"-
# Schreibpfad von /agent-flow:reconcile Stufe 2.
#
# Spec: docs/specs/reconcile.md AC8. Vertrag: docs/architecture/reconcile-subsystem.md §3
#       (Stufe 2 — Nachziehen). Lehre: .claude/lessons/coder.md coder/L27 — dieselbe
#       Layout-Erkennung wie im Lese-/Vergleichspfad (skills/reconcile/SKILL.md §2b) MUSS auch
#       im Schreibpfad (§2c.2) gelten, sonst legt der Skill beim Neu-Anlegen die kanonische
#       Einzeldatei an, obwohl das Projekt bereits ein abweichendes Mehrdatei-/Root-Muster
#       etabliert hat (wie dieses Repo selbst: Root-CONCEPT.md + docs/architecture/*.md).
#
# Reine Erkennung, KEIN Schreiben, seiteneffektfrei.
#
# Usage:
#   scripts/reconcile-doc-layout.sh <architecture|concept> [repo_root]
#   repo_root Default: `git rev-parse --show-toplevel` (Fallback: cwd, falls kein Git-Repo).
#
# Ausgabe (stdout), GENAU EIN Token:
#   doctype=architecture:
#     multi   — `docs/architecture/` ist ein Verzeichnis mit mind. einer *.md-Datei
#               -> neue Subsystem-Datei unter docs/architecture/<subsystem>.md anlegen
#     single  — kein docs/architecture/-Verzeichnis mit *.md-Inhalt vorhanden
#               -> kanonische Einzeldatei docs/architecture.md anlegen
#   doctype=concept:
#     root      — Root-CONCEPT.md existiert (Großschreibung, Projekt-Wurzel)
#                 -> dorthin schreiben statt neuer docs/concept.md
#     canonical — kein Root-CONCEPT.md vorhanden -> kanonisch docs/concept.md anlegen
#
# Exit 0 bei gueltigem doctype (immer einer der beiden Tokens je Typ — reine Lese-Operation).
# Exit 2 bei fehlendem/ungueltigem Argument (Aufrufproblem, kein Fachfall).
#
# Requires: bash >= 4.0, git (optional, nur fuer repo_root-Default).

set -uo pipefail

DOCTYPE="${1:-}"
REPO_ROOT="${2:-}"

if [[ -z "$DOCTYPE" || ( "$DOCTYPE" != "architecture" && "$DOCTYPE" != "concept" ) ]]; then
  echo "FEHLER: Usage: reconcile-doc-layout.sh <architecture|concept> [repo_root]" >&2
  exit 2
fi

if [[ -z "$REPO_ROOT" ]]; then
  REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi

if [[ "$DOCTYPE" == "architecture" ]]; then
  ARCH_DIR="${REPO_ROOT}/docs/architecture"
  if [[ -d "$ARCH_DIR" ]] && find "$ARCH_DIR" -maxdepth 1 -name '*.md' -type f 2>/dev/null | grep -q .; then
    echo "multi"
  else
    echo "single"
  fi
  exit 0
fi

# doctype == concept
if [[ -f "${REPO_ROOT}/CONCEPT.md" ]]; then
  echo "root"
else
  echo "canonical"
fi
exit 0
