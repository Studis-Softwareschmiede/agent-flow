#!/usr/bin/env python3
"""pm-intake-gate — Abnahme-Gate nach einem pm-skills-Lauf.

Prüft einen Obsidian-Notiz-Ordner gegen den pm-import-Kontrakt
(docs/specs/pm-import.md), BEVOR /agent-flow:from-notes den Korpus einliest.
Läuft in der Research-Orchestrierung als letzter Schritt jedes PM-Laufs;
erst bei GRÜN bietet das Entscheidungs-Gate den agent-flow-Anstoss an.

Prüfungen (Herleitung aus der Spec):
  G1  artifact:-Frontmatter vorhanden und Typ zulässig            (AC1, Edge «unbekannter Typ»)
  G2  Idempotenz-Anker: version-Frontmatter, bei prd Revision History  (AC6)
  G3  Pflicht-Sektionen je Artefakt-Typ vollständig               (AC2, E1)
  G4  Quell-IDs (FR-n, US-n) eindeutig, keine Duplikate           (AC4)
  G5  Titel vorhanden → stabiler feature-slug ableitbar           (Verträge: Spec-Frontmatter)
  H1  Notiz ohne artifact:, sieht aber wie PM-Artefakt aus        (AC1-Heuristik)
      → --fix stempelt den erkannten Typ nach; sonst Befund

Notizen ohne artifact: und ohne PM-Struktur laufen den Ideen-Pfad (A1) — INFO, kein Befund.
Mechanische Reparatur (--fix) ändert NUR Frontmatter-Stempel, nie Notiz-Inhalt.

Aufruf:
  pm-intake-gate.py <notiz-ordner> [--fix] [--json]
Exit-Codes: 0 = GRÜN (übernahmefähig) · 1 = ROT (Befunde) · 2 = Aufruf-/Lesefehler
"""

import json
import re
import sys
from pathlib import Path

ALLOWED_TYPES = {
    "prd", "problem-statement", "hypothesis", "user-stories",
    "acceptance-criteria", "edge-cases", "adr", "launch-checklist",
}

# Pflicht-Sektionen je Typ (Substring-Match auf Überschriften, case-insensitive).
# prd = Container (Realtest 18.07.2026): Sektionen liegen IM Dokument.
REQUIRED_SECTIONS = {
    "prd": ["problem statement", "non-goals", "user stories",
            "functional requirements", "edge cases", "open questions"],
    "adr": ["context", "decision", "consequences"],
}


def parse_frontmatter(text):
    """Flaches YAML-Frontmatter ohne externe Abhängigkeit (nur key: value)."""
    if not text.startswith("---"):
        return {}, text
    end = text.find("\n---", 3)
    if end < 0:
        return {}, text
    fm = {}
    for line in text[3:end].splitlines():
        m = re.match(r"^([A-Za-z_][\w-]*):\s*(.*)$", line)
        if m:
            fm[m.group(1)] = m.group(2).strip().strip('"').strip("'")
    return fm, text[end + 4:]


def headings(body):
    return [h.strip().lower() for h in re.findall(r"^#{1,6}\s+(.+)$", body, re.M)]


def looks_like_pm(body):
    """AC1-Fallback-Heuristik: charakteristische Struktur → vermuteter Typ."""
    hs = " | ".join(headings(body))
    if re.search(r"\bFR-\d+\b", body) and "functional requirements" in hs:
        return "prd"
    if re.search(r"^\s*(Given|When|Then)\b", body, re.M | re.I):
        return "acceptance-criteria"
    if "consequences" in hs and "decision" in hs:
        return "adr"
    if re.search(r"\bUS-\d+\b", body) and "user stor" in hs:
        return "user-stories"
    return None


def duplicate_ids(body, prefix):
    """Nur Definitionen zählen (Listenpunkt/Tabellenzeile), nicht Querverweise im Fliesstext."""
    ids = re.findall(rf"^\s*(?:[-*]\s*|\|\s*){prefix}-(\d+)\s*[:|]", body, re.M)
    seen, dups = set(), set()
    for i in ids:
        if i in seen:
            dups.add(i)
        seen.add(i)
    return sorted(dups)


def check_note(path, fix):
    text = path.read_text(encoding="utf-8")
    fm, body = parse_frontmatter(text)
    findings, repairs = [], []
    artifact = fm.get("artifact")

    if artifact is None:
        guessed = looks_like_pm(body)
        if guessed is None:
            return {"note": path.name, "path": "ideen-pfad", "status": "INFO",
                    "findings": ["kein artifact:-Feld, keine PM-Struktur → Ideen-Pfad (A1)"]}
        if fix:
            stamp_frontmatter(path, text, {"artifact": guessed})
            repairs.append(f"artifact: {guessed} nachgestempelt (Heuristik)")
            text = path.read_text(encoding="utf-8")
            fm, body = parse_frontmatter(text)
            artifact = guessed
        else:
            findings.append(f"H1: PM-Struktur erkannt ({guessed}), aber artifact:-Stempel fehlt — mit --fix nachstempelbar")
            return {"note": path.name, "path": "pm", "status": "ROT", "findings": findings}

    if artifact not in ALLOWED_TYPES:
        findings.append(f"G1: unbekannter Artefakt-Typ '{artifact}' → Fragenkatalog, kein stiller Ideen-Pfad-Fallback")
        return {"note": path.name, "path": "pm", "status": "ROT", "findings": findings}

    if not fm.get("version"):
        if fix:
            stamp_frontmatter(path, text, {"version": "1"})
            repairs.append("version: 1 nachgestempelt")
        else:
            findings.append("G2: version-Frontmatter fehlt (Idempotenz-Anker, AC6) — mit --fix nachstempelbar")
    if artifact == "prd" and "revision history" not in " | ".join(headings(body)):
        findings.append("G2: Revision History fehlt (Divergenz-Anker, AC6)")

    hs = " | ".join(headings(body))
    for sec in REQUIRED_SECTIONS.get(artifact, []):
        if sec not in hs:
            findings.append(f"G3: Pflicht-Sektion «{sec}» fehlt (E1 → Fragenkatalog)")

    for prefix in ("FR", "US"):
        dups = duplicate_ids(body, prefix)
        if dups:
            findings.append(f"G4: doppelte {prefix}-IDs: {', '.join(prefix + '-' + d for d in dups)}")

    title = next(iter(re.findall(r"^#\s+(.+)$", body, re.M)), fm.get("title"))
    if not title:
        findings.append("G5: kein Titel (H1/Frontmatter) — feature-slug nicht ableitbar")

    status = "ROT" if findings else "GRÜN"
    return {"note": path.name, "path": "pm", "status": status,
            "artifact": artifact, "findings": findings, "repairs": repairs}


def stamp_frontmatter(path, text, fields):
    """Mechanische Reparatur: Felder ins Frontmatter einfügen, Inhalt unangetastet."""
    fm_block = ""
    rest = text
    if text.startswith("---"):
        end = text.find("\n---", 3)
        fm_block, rest = text[4:end], text[end + 4:]
    for k, v in fields.items():
        fm_block = fm_block.rstrip("\n") + f"\n{k}: {v}\n" if fm_block else f"{k}: {v}\n"
    path.write_text(f"---\n{fm_block.strip()}\n---{rest if rest.startswith(chr(10)) else chr(10) + rest}",
                    encoding="utf-8")


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    fix = "--fix" in sys.argv
    as_json = "--json" in sys.argv
    if len(args) != 1:
        print(__doc__, file=sys.stderr)
        return 2
    folder = Path(args[0])
    if not folder.is_dir():
        print(f"Kein Ordner: {folder}", file=sys.stderr)
        return 2

    results = [check_note(p, fix) for p in sorted(folder.glob("*.md"))]
    red = [r for r in results if r["status"] == "ROT"]

    if as_json:
        print(json.dumps({"ready": not red, "results": results}, ensure_ascii=False, indent=2))
    else:
        for r in results:
            print(f"[{r['status']:>5}] {r['note']}" + (f" (artifact: {r.get('artifact')})" if r.get("artifact") else ""))
            for f in r.get("findings", []):
                print(f"        - {f}")
            for rep in r.get("repairs", []):
                print(f"        ✔ {rep}")
        print(f"\nGate: {'ROT — nicht übernahmefähig' if red else 'GRÜN — übernahmefähig für /agent-flow:from-notes'}")
    return 1 if red else 0


if __name__ == "__main__":
    sys.exit(main())
