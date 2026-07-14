---
id: output-token-shaping
title: Ausgabe-Token-Diät im Agenten-Flow — Spike RTK-Mechanik selektiv anwenden
status: active
area: flow-orchestrierung
version: 1
spec_format: use-case-2.0
---

# Spec: Ausgabe-Token-Diät im Agenten-Flow  (`output-token-shaping`)

> **Schicht 3 von 3.** Testbares **Verhalten + Verträge**, sprach-/paradigma-unabhängig (Intent, keine Idiome/Klassen).
> **Source of Truth** für die Spike-Abarbeitung: Dies ist ein **Untersuchungs-Item (Spike)** — die Acceptance-Kriterien sind **Entscheidungs-/Ergebnis-Artefakte** (Klassifikation, Pilot-Messung, ADR), nicht ein Produktiv-Feature. Kein Produktiv-Hook wird im Spike scharfgeschaltet.

## Zweck
Die Arbeits-Agenten (`coder`, `reviewer`, `tester`, `cicd`) sind stark Bash-lastig (Git, Tests, Build, Docker, `grep`/`ls`/`find`). Ein großer Teil des Token-Verbrauchs entsteht durch **Befehls-Ausgaben**, die ungefiltert in den Kontext fließen. Das Projekt **RTK (Rust Token Killer, `rtk-ai/rtk`)** filtert/gruppiert/kürzt/dedupliziert solche Ausgaben transparent per PreToolUse-Hook und verspricht 60–90 % weniger Tokens auf genau diesen Befehlen.

RTK greift jedoch nur **partiell** sinnvoll: Manche unserer Ausgaben **müssen wörtlich und ungekürzt** bleiben, weil harte Doktrin-Regeln darauf beruhen — `coder/R02` und `reviewer/R01` (Verbatim-Pflicht bei Klassifikations-Widerlegung) sowie die Treue der `reviewer`-/`tester`-Gates. Owner-Ziel (2026-07-14): Prüfen, ob wir die **Mechanik selektiv im eigenen Flow hinterlegen** — nur an den Befehlen, wo Fidelity-Verlust billig ist, und dort roh lassen, wo Korrektheit zählt.

## Acceptance-Kriterien

- **AC1 — Trennlinie (Herzstück).** Eine dokumentierte Klassifikation der Bash-Befehle in **„darf gefiltert werden"** (Exploration: `ls`, `find`, `grep`, `git status`, `tree`, Verzeichnis-/Discovery-Befehle) vs. **„muss roh bleiben"** (`git diff`, Test-Runner-Output, Build-/Lint-Logs — alles, was die `reviewer`-/`tester`-Gates und die Verbatim-Belege aus `coder/R02` + `reviewer/R01` speist). Ergebnis: eine Allow-/Denylist als Tabelle in dieser Spec bzw. im Ergebnis-ADR. Grenzfälle (z. B. `git log`, `docker ps`) sind explizit einer Seite zugeordnet.
- **AC2 — Weg C sofort (Prompt-Ebene, risikofrei).** Bestandsaufnahme, welche Agenten-Handoffs (`agents/*.md`) schon sparsame Befehlswahl vorgeben, und eine konkrete Empfehlungsliste für Ergänzungen (z. B. `git diff --stat` vor vollem Diff, `grep -c`, gezielte Datei-Reads statt ganzer Dateien). **Nur Empfehlung, kein Edit im Spike.**
- **AC3 — Weg B Pilot (gemessen).** RTK-Binary in einem **Worktree bzw. Konsum-Projekt** hinter einem PreToolUse-Hook, **beschränkt auf die Allowlist aus AC1**, über N ≥ 3 `/flow`-Läufe gemessen (`rtk gain`). Pflicht-Gegenprobe: Die **Gate-Ergebnisse** (`reviewer`/`tester` PASS/FAIL) bleiben gegenüber einem Baseline-Lauf **unverändert** — kein maskierter Fehlschlag durch gekürzte Ausgabe.
- **AC4 — Entscheidung als ADR.** Ergebnis-Report mit begründeter Empfehlung zwischen **A** (Mechanik selbst nachbauen, nur generische Tricks: Dedup/Truncation-mit-Kontext), **B** (RTK-Binary selektiv), **C** (nur Prompt-Ebene) oder einer **Kombination**. Enthält: gemessene Token-Ersparnis, Fidelity-Risiko-Bewertung, Supply-Chain-Bewertung des Fremd-Binaries und **Verifikation, dass RTK-Telemetrie standardmäßig aus ist** (passt zur Secrets-Doktrin: keine Pfade/Secrets/Quelltext exfiltriert).
- **AC5 — Scaffold-Schalter-Skizze (bedingt).** Nur falls der Pilot (AC3) positiv ausfällt: Skizze, wie ein **optionaler, standardmäßig AUS**-Schalter im `new-project`-/`adopt`-Scaffold aussähe — mit der Allow-/Denylist aus AC1 als Kern und Telemetrie-aus als Default. **Umsetzungsvorschlag, nicht implementiert.**

## Verträge
- **Trennlinie ist bindend:** Egal ob Weg A oder B gewählt wird — die Denylist (`git diff`, Test-/Build-Output, Verbatim-Quellen) darf **nie** durch einen Filter laufen. Diese Liste ist das eigentliche Artefakt des Spikes.
- **Hook wirkt prozessweit, nicht pro Agent:** In Claude Code entscheidet ein PreToolUse-Hook anhand des **Befehls-Musters**, nicht anhand des aufrufenden Agenten. „Nur wo nötig" = „nur bei den richtigen Befehlen".

## Edge-Cases & Fehlerverhalten
- **E1 — Parse-Fehler von RTK:** Reißt RTK bei einem Allowlist-Befehl (unerwartetes Format), MUSS die **Roh-Ausgabe** durchgereicht werden (fail-open), nie eine leere/abgeschnittene. Im Pilot beobachten und im ADR vermerken.
- **E2 — Grenzfall-Befehl doppeldeutig** (z. B. `git show` = Diff-artig): im Zweifel der **Denylist** zuordnen (Fidelity vor Ersparnis).

## NFRs
- Der Spike selbst ändert **keinen** Produktivpfad (keine Hooks scharf, keine Fremd-Dependency dauerhaft aufgenommen). Deliverable ist Doku + Messung + Entscheidung.

## Nicht-Ziele
- Kein produktiver PreToolUse-Hook im Spike-Umfang.
- Keine dauerhafte Aufnahme des RTK-Binaries ohne positive Messung.
- Keine Änderung der Verbatim-Doktrin (`coder/R02`, `reviewer/R01`) — sie ist die Randbedingung, nicht der Verhandlungsgegenstand.
- Kein Nachbau der 100+ befehlsspezifischen RTK-Parser (nur generische Tricks stehen bei Weg A zur Debatte).

## Abhängigkeiten
- `agents/coder.md`, `agents/reviewer.md`, `agents/tester.md` (Handoff-Verträge, Verbatim-Regeln — Randbedingung für AC1/AC2).
- `skills/new-project/SKILL.md`, `skills/adopt` (Scaffold-Ziel für AC5).
- Externe Quelle: `rtk-ai/rtk` (Apache-2.0).
