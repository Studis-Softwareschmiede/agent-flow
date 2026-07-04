#!/usr/bin/env bash
# scripts/obsidian-corpus-read.sh — Notiz-Korpus-Reader für /agent-flow:from-notes
#
# Spec: docs/specs/obsidian-ingest.md AC4, AC5, AC6.
# Vertrag: docs/architecture/obsidian-ingest-subsystem.md §3 (Reader als Basis von Stufe a)
#          + „Notiz-Korpus (Reader-Output)" in der Spec (Verträge).
# Aufrufer: Stufe a der Drei-Stufen-Pipeline (S-023, noch nicht gebaut) UND der Schwester-
#           Modus `/agent-flow:from-notes --sync` (`[[obsidian-sync]]`, noch nicht gebaut).
#           Eigenständiger, wiederverwendbarer Baustein — hat KEINE Abhängigkeit auf die
#           Pipeline drumherum und startet nichts davon.
#
# Liest ALLE `*.md`-Notizen eines Obsidian-Ordners REKURSIV (inkl. Unterordner) und fügt sie
# zu EINEM konsolidierten Korpus zusammen — in DETERMINISTISCHER Reihenfolge (relativer Pfad,
# byteweise alphabetisch stabil) und je Notiz mit einem Herkunfts-Marker (relativer Dateipfad),
# damit spätere Fragenkatalog-Einträge und Sync-Funde auf die Quellnotiz zeigen können (AC4).
#
# Ignorieren + Abbruch statt Leerlauf (AC5):
#   - Nicht-`.md`-Dateien werden übersprungen (Anhänge etc.).
#   - Obsidian-Interna werden übersprungen: das `.obsidian/`-Verzeichnis sowie generell jedes
#     versteckte (dot-)Verzeichnis auf dem Pfad (z.B. `.trash/`, `.git/`).
#   - Ein nicht existierender Pfad ODER ein Ordner ohne jede `.md`-Datei -> KLARER ABBRUCH mit
#     Meldung (Exit 2). NIEMALS leere Ausgabe an einen späteren Pipeline-Schritt, damit keine
#     leere `concept.md`/Spec angelegt wird (deckt E2).
#
# Rein lesend (AC6): der Ordner wird NIE beschrieben, verschoben oder committet — er ist eine
# externe Quelle, kein Repo-Artefakt. Dieses Skript öffnet Dateien ausschließlich lesend.
#
# Usage:
#   scripts/obsidian-corpus-read.sh <ordnerpfad>
#
# Ausgabe (stdout): der konsolidierte Korpus als Text. Je Notiz ein Herkunfts-Marker-Block:
#   ===== NOTE: <relativer-pfad-zur-notiz> =====
#   <voller Inhalt der Notiz>
#   (Leerzeile als Trennung zur nächsten Notiz)
# Der Marker ist maschinell wieder-auffindbar (`quelle`-Feld des Fragenkatalogs, AC9).
#
# stderr: eine informative Zusammenfassungszeile "CORPUS: <n> Notiz(en) aus <pfad>" (kein Teil
#         des stdout-Korpus — Aufrufer parst nur stdout).
#
# Exit 0 — Korpus erfolgreich gelesen (mindestens eine `.md`-Notiz gefunden).
# Exit 2 — klarer Abbruch: Pfad fehlt / ist keine Verzeichnis / enthält keine `.md` (AC5).
# Exit 1 — Aufruffehler (kein Argument).
#
# Requires: bash, python3.

set -euo pipefail

if [[ $# -lt 1 || -z "${1:-}" ]]; then
  echo "FEHLER: kein Notiz-Ordner angegeben. Usage: $(basename "$0") <ordnerpfad>" >&2
  exit 1
fi

NOTES_DIR="$1"

python3 - "$NOTES_DIR" <<'PYEOF'
import os
import sys

notes_dir = sys.argv[1]

# --- AC5: nicht existierender Pfad / kein Verzeichnis -> klarer Abbruch, kein Leerlauf ---
if not os.path.exists(notes_dir):
    print(
        f"FEHLER: Notiz-Ordner {notes_dir!r} existiert nicht — kein Korpus lesbar. "
        f"Kein Leerlauf, keine leere Pipeline.",
        file=sys.stderr,
    )
    sys.exit(2)
if not os.path.isdir(notes_dir):
    print(
        f"FEHLER: {notes_dir!r} ist kein Verzeichnis — es wird ein Obsidian-Notiz-ORDNER erwartet.",
        file=sys.stderr,
    )
    sys.exit(2)

# --- AC4/AC5: alle *.md rekursiv sammeln, Obsidian-Interna + versteckte Dot-Verzeichnisse ---
# ---           überspringen. Herkunfts-Marker = relativer Pfad, POSIX-Trenner (deterministisch). ---
md_files = []
for root, dirs, files in os.walk(notes_dir):
    # Versteckte Verzeichnisse (u.a. `.obsidian/`, `.trash/`, `.git/`) NICHT betreten (AC5).
    # In-place-Filter auf `dirs` beschneidet die os.walk-Traversierung.
    dirs[:] = [d for d in dirs if not d.startswith(".")]
    for name in files:
        # Nur `.md` (case-insensitiv); alles andere (Anhänge etc.) überspringen (AC5).
        if not name.lower().endswith(".md"):
            continue
        abs_path = os.path.join(root, name)
        rel_path = os.path.relpath(abs_path, notes_dir)
        # Herkunfts-Marker deterministisch + plattformstabil: immer POSIX-Trenner.
        rel_marker = rel_path.replace(os.sep, "/")
        md_files.append((rel_marker, abs_path))

# --- AC5: Ordner ohne jede `.md` -> klarer Abbruch, kein Leerlauf ---
if not md_files:
    print(
        f"FEHLER: Notiz-Ordner {notes_dir!r} enthält keine `.md`-Notiz — nichts zu lesen. "
        f"Kein Leerlauf, keine leere Pipeline.",
        file=sys.stderr,
    )
    sys.exit(2)

# --- AC4: DETERMINISTISCHE Reihenfolge (stabil nach relativem Marker, byteweise) ---
md_files.sort(key=lambda item: item[0])

# --- AC4: EIN konsolidierter Korpus, je Notiz mit Herkunfts-Marker. AC6: rein lesend. ---
out = sys.stdout
for rel_marker, abs_path in md_files:
    try:
        with open(abs_path, encoding="utf-8", errors="replace") as f:
            content = f.read()
    except OSError as exc:
        print(
            f"FEHLER: Notiz {rel_marker!r} nicht lesbar ({exc}).",
            file=sys.stderr,
        )
        sys.exit(2)
    out.write(f"===== NOTE: {rel_marker} =====\n")
    out.write(content)
    # Sicherstellen, dass der nächste Marker auf einer eigenen Zeile beginnt.
    if not content.endswith("\n"):
        out.write("\n")
    out.write("\n")

print(f"CORPUS: {len(md_files)} Notiz(en) aus {notes_dir}", file=sys.stderr)
PYEOF
