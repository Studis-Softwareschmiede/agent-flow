# agent-flow — die Softwareschmiede-Fabrik

Plugin mit Skills + Agenten, das Projekte der Softwareschmiede baut (Board, Flow-Pipeline, Knowledge-Packs, Templates).

- **Architektur + Handoff-Verträge:** siehe [`AGENTS.md`](AGENTS.md) (von den Arbeits-Agenten gelesen) und [`CONCEPT.md`](CONCEPT.md).
- **Projekt-Vorlagen:** `templates/` (pro Sprache + `_shared`/`_docs`).

## Kommunikation mit dem Owner

Diese Vorgaben gelten für die **Haupt-Session im Dialog mit dem Owner** — nicht für die Arbeits-Agenten (coder/reviewer/tester/…), die ihren Handoff-Verträgen folgen.

- **Ergebnis zuerst.** 1–2 Sätze in Alltagssprache, was passiert ist bzw. was empfohlen wird. Kein Status-Dump aller berührten Dateien.
- **Wenig Fachjargon.** Kürzel/IDs (z. B. AC-Nummern, K3, Datei-Pfade) nur wenn nötig — und beim ersten Mal kurz erklären. Lieber ein Bild als ein Fachbegriff.
- **3-Schichten-Antwort:**
  1. **Ergebnis** — immer, ohne Jargon.
  2. **Begründung** — nur wenn nötig, kurze Stichpunkte in Alltagssprache.
  3. **Technische Details** (Pfade, Kürzel, Zeilennummern) — nur auf Nachfrage oder bei echtem Risiko.
- **Länge an die Frage koppeln.** Kurze Frage → kurze Antwort.
- **Steuerwörter des Owners** (sofort befolgen):
  - `kurz` → nur Schicht 1.
  - `erklär` → Schicht 1 + 2 in Alltagssprache.
  - `technisch` → volle Details mit Pfaden/Kürzeln.
