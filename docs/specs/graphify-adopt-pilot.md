---
id: graphify-adopt-pilot
title: Graphify-Pilot am nächsten großen /adopt-Fall — messungs-gestützt, opt-in
status: active
area: vorlagen-scaffolding
version: 1
spec_format: use-case-2.0
---

# Spec: Graphify-Pilot am nächsten großen /adopt-Fall  (`graphify-adopt-pilot`)

> **Schicht 3 von 3.** Testbares **Verhalten + Verträge**, sprach-/paradigma-unabhängig.
> **Source of Truth** für `coder` (führt den Pilot durch), `tester` (prüft die AC), `reviewer` (prüft gegen die Spec — hartes Drift-Gate).

## Zweck

Zeitlich begrenzter, messungs-gestützter Pilot von **Graphify** (`Graphify-Labs/graphify`, MIT: Codebase → lokaler AST-Knowledge-Graph, deterministisch ohne LLM-Calls) als Explorations-Beschleuniger für die **lese-lastigen `/adopt`-Phasen** großer Bestands-Repos („Spec aus Code ableiten" + Audit). Erwartung laut Hersteller-Messung: deutliche Ersparnis erst ab größeren Korpora (71,5× weniger Tokens/Query bei 52 Dateien, ~1× bei 6) — deshalb **kein Standard-Scaffold**, sondern ein Pilot an einem realen, großen Fall. Doktrin-Einordnung: Graph-Antworten sind **Klasse-A-Material** (Orientierung/Exploration) im Sinne der Trennlinien von `[[output-token-shaping]]` — sie speisen nie ein Gate und nie einen Verbatim-Beleg. Prüf-Herkunft: ADR [`docs/architecture/output-token-shaping.md`](../architecture/output-token-shaping.md) §7.

## Acceptance-Kriterien

- **AC1 — Vorbedingungs-Gate (realer Fall, HART).** Der Pilot startet nur an einem **realen** `/adopt`-Kandidaten mit hinreichend großem Code-Korpus (Richtwert: ≥ 50 Quelldateien oder ≥ 20k LOC; Sprache von den tree-sitter-Grammatiken abgedeckt). Es wird **kein** künstliches Pilot-Repo gebaut; solange kein geeigneter Fall vorliegt, bleibt die Story unbearbeitet in To Do (Warte-Grund über Story-Titel + `estimate_note` sichtbar).
- **AC2 — Eng begrenztes Setup.** Installation nur lokal für das Pilot-Repo (`uv tool install`/`pipx`, gepinnte Version); Graph-Build **ausschließlich** über den deterministischen Code-Pass (0 LLM-Tokens). AUS bleiben: LLM-Doc/PDF-Pass, Strict-Mode, PreToolUse-Hook, MCP-Dauerbetrieb. `graphify-out/` wird **nicht** committet und via Ignore-Mechanismus vom Prompt-Cache ferngehalten.
- **AC3 — Messung mit harter Gegenprobe.** Vergleich Baseline vs. Graph-gestützt über die Adopt-Phasen „Spec aus Code" + „Audit" (mindestens je ein Lauf pro Arm, gleicher Repo-Stand): (a) Token-Verbrauch der Phase (Ist-Erfassung wie im Metrik-Subsystem üblich), (b) **Vollständigkeit der Ergebnisse** — die Audit-Fund-Liste und die abgeleiteten Spec-Inhalte des Graph-Laufs dürfen gegenüber der Baseline keine Funde/Abschnitte verlieren. Verlust ⇒ Pilot **nicht bestanden**, unabhängig von der Ersparnis (Fidelity vor Ersparnis, analog RTK-Protokoll ADR §4).
- **AC4 — Ergebnis + Entscheid dokumentiert.** Kurzbericht (Tokens je Arm, Funde-Abgleich, Betriebs-Reibung: Graph-Staleness, Einrichtungsaufwand, Grammatik-Lücken) als Nachtrag im ADR §7; expliziter Entscheid **ja/nein** zur adopt-Integration. Bei „ja" entsteht eine **separate Folge-Story** (opt-in Profil-Schalter im adopt-Pfad) — nicht Teil dieses Piloten.
- **AC5 — Rückstandsfreier Rückbau.** Nach Abschluss (egal welches Ergebnis) wird Graphify aus dem Pilot-Repo entfernt: Tool deinstalliert, `graphify-out/` + Ignore-Einträge gelöscht; das Pilot-Repo enthält keinerlei Graphify-Artefakte mehr.

## Verträge
- **Klasse-A-Grenze (bindend):** Graph-Abfragen dienen nur der Orientierung (Struktur finden, Aufrufer lokalisieren). Jeder Gate-/Beleg-Schritt (Audit-Befund, Spec-Formulierung, Review) verifiziert am **Roh-Code** (Read/Grep) — der Graph ist nie die letzte Quelle eines Befunds.
- **Kein Fabrik-Repo-Eingriff:** `new-project`/`adopt`/Templates bleiben in diesem Pilot unverändert; einzige Fabrik-Änderung ist der ADR-§7-Nachtrag (AC4).

## Edge-Cases & Fehlerverhalten
- **E1 — Graph veraltet/Kanten falsch (`INFERRED`-Fehlkanten):** Da jede Beleg-Gewinnung am Roh-Code verifiziert (Verträge), führt eine Fehlkante höchstens zu einem Umweg, nie zu einem falschen Befund; auffällige Fehlkanten kommen als Betriebs-Reibung in den Bericht (AC4).
- **E2 — Tooling-Ausfall im Pilot (Install/Build schlägt fehl):** dokumentieren, Pilot abbrechen, Baseline-Arm bleibt gültig; Entscheid dann „nein — nicht betriebsreif" statt endlosem Debugging.

## NFRs
- Pilot-Aufwand begrenzt: keine eigene Infrastruktur, keine Dauerbetriebs-Pflichten; gepinnte Version (junges Tool, hohe Release-Kadenz).

## Nicht-Ziele
- **Kein** Standard-Scaffold-Eintrag in `new-project`/`adopt`/Templates (das wäre die Folge-Story nach positivem Entscheid).
- **Keine** Nutzung des Graphen als Gate-/Beleg-Quelle (Klasse-A-Grenze).
- **Kein** LLM-gestützter Doc-Pass, kein Strict-Mode, kein Hook, kein Committen von `graphify-out/`.

## Abhängigkeiten
- Realer `/adopt`-Fall gemäß AC1 (externes Gate).
- `[[output-token-shaping]]` (Klassen-Doktrin) + ADR [`docs/architecture/output-token-shaping.md`](../architecture/output-token-shaping.md) §7 (Prüf-Herkunft, Bericht-Ziel).
