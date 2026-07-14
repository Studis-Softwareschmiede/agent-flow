---
id: output-shaping-prompt-frugality
title: Ausgabe-Token-Diät — Weg C (Prompt-Ebene): sparsame Befehlswahl in den Handoffs
status: active
area: rollen-agenten
version: 1
spec_format: use-case-2.0
---

# Spec: Ausgabe-Token-Diät — Weg C (Prompt-Ebene)  (`output-shaping-prompt-frugality`)

> **Schicht 3 von 3.** Testbares **Verhalten + Verträge**, sprach-/paradigma-unabhängig.
> **Source of Truth** für `coder` (baut daraus), `tester` (prüft die AC), `reviewer` (prüft den Diff dagegen — hartes Drift-Gate).

## Zweck
Umsetzung von **Weg C** aus dem ADR [`docs/architecture/output-token-shaping.md`](../architecture/output-token-shaping.md) (§2/§3.2, messungs-belegt): die risikofreie, sofort umsetzbare Prompt-Ebenen-Sparsamkeit. Der Pilot (dev-gui S-345) hat gezeigt, dass der reale Token-Nutzen in volumenstarken Erkundungs-Befehlen sitzt — die **Agenten-Handoffs** sollen dort von vornherein sparsame Befehle wählen, **ohne** Fremd-Binary, **ohne** Hook (das ist Weg A, separat) und **ohne** die Verbatim-/Gate-Treue anzutasten.

Grundlage ist die konkrete Empfehlungsliste im ADR §2.2. Diese Story zieht sie in die Agenten-Definitionen ein.

## Acceptance-Kriterien

- **AC1 — `agents/reviewer.md` (Stat-vor-Volldiff bei großen Diffs).** Der „Zuerst lesen"-Schritt wird ergänzt: bei **großen** Diffs (Heuristik: `git diff --shortstat` > ~300 geänderte Zeilen) zuerst `git diff --stat` für Umfang/Dateiliste, dann den vollen Diff **gezielt** für die AC-relevanten Dateien ziehen; rein generierte/Lockfile-Diffs nicht vollständig durchlesen. **Bindende Randbedingung im Text:** der volle Diff bleibt Pflicht für **jede** Datei, die einen Critical/Important-Befund tragen könnte — die Übersicht ist vorgeschaltet, sie ersetzt nie den Beleg (Klasse-B-Signalregel unverändert).
- **AC2 — `agents/tester.md` (kein Volltext-Suite-Output ins Handoff).** Das Output-Format (`Result:`/`Failures:`) erhält die explizite Anweisung: bei großen Suiten **nicht** die rohe Volltext-Ausgabe ins Handoff kopieren — nur die Summary-Zeile (`X passed, Y failed`) und bei FAIL den/die betroffenen Failure-Block(e) (Assertion + Datei:Zeile). Grüne Läufe: nur die Summary.
- **AC3 — `agents/reviewer.md` (`grep -rln` statt `grep -rn`, wo nur Existenz/Anzahl zählt).** An der Konsumenten-Prüfstelle (§4b-(c) „per `grep` prüfen, ob ALLE Konsumenten…"): wo nur **Existenz/Anzahl** der Konsumenten relevant ist (nicht der Fundstellen-Kontext als Beleg), `grep -rln` (Dateiliste) statt `grep -rn` (alle Treffer-Zeilen) verwenden. Ausdrücklich **nur**, wenn die Treffer-Zeile selbst kein Verbatim-Beleg werden muss.
- **AC4 — Generische „Zähl- statt Lies-Pflicht" (auf `reviewer` + `tester` ausgedehnt).** Die bereits in `coder/R03` verankerte Konvention (wo nur eine **Zahl** gebraucht wird — Testanzahl, Treffer-Anzahl, Zeilenanzahl — `grep -c`/`wc -l` statt Volltext) wird als generelle Handoff-Regel auch in `agents/reviewer.md` (Zählen von `it(`-Blöcken) und `agents/tester.md` (Zählen von Failures) benannt — als knapper Verweis/Regel, kein Umbau bestehender Abläufe.
- **AC5 — Verbatim-/Fidelity-Doktrin unangetastet (hartes Nicht-Ziel, im Diff nachweisbar).** `coder/R02` und `reviewer/R01` (Verbatim-Pflicht bei Klassifikations-Widerlegung) bleiben **wörtlich unverändert**; `agents/coder.md` Punkt 6 („betroffenen Code in **voller** Datei") bleibt bewusst restriktiv (keine Kürzungsempfehlung dort — ADR §2.2 Punkt 3). Keine der AC1–AC4-Ergänzungen darf so formuliert sein, dass sie an einer Beleg-/Gate-tragenden Stelle kürzt.

## Verträge
- Reine **Textänderung an `agents/*.md`** (Handoff-Prompts) + ggf. ein knapper Verweis in `AGENTS.md`, falls dort eine Sparsamkeits-Konvention zentral gehört. Kein Code, kein Hook, keine Dependency.
- Jede Ergänzung trägt die Randbedingung „nur wo die Ausgabe kein Gate-/Verbatim-Beleg ist" sichtbar im Text — Sparsamkeit ist der Default für Erkundung, **nie** für Beleg.

## Edge-Cases & Fehlerverhalten
- **E1 — Diff knapp unter/über der 300-Zeilen-Heuristik:** die Grenze ist eine Faustregel, kein hartes Gate; im Zweifel voller Diff (Fidelity vor Ersparnis).
- **E2 — Failure-Block sehr groß:** bei FAIL zählt Vollständigkeit des Failure-Blocks vor Kürzung — die Sparsamkeit betrifft nur die **grünen** Zeilen/Progress/Timing, nie den Fehler selbst.

## NFRs
- Kein neues Tooling; die Änderung ist sofort wirksam (Prompt-Disziplin), risikofrei im Sinne der Fidelity (keine maschinelle Kürzung an Belegen).

## Nicht-Ziele
- **Kein** Hook, **kein** Ausgabe-Filter, **kein** Fremd-Binary (das ist Weg A — separate Story `[[output-shaping-classA-filter]]`).
- **Keine** Änderung an `coder/R02`/`reviewer/R01` oder an `coder.md` Punkt 6.
- **Keine** Kürzung an Klasse-B-Belegen oder Klasse-C-Verbatim-Quellen (ADR-Trennlinie bleibt bindend).

## Abhängigkeiten
- ADR [`docs/architecture/output-token-shaping.md`](../architecture/output-token-shaping.md) (§2.2 Empfehlungsliste = Grundlage; §3.0/§3.3 Fidelity-Randbedingung).
- `agents/reviewer.md`, `agents/tester.md`, `agents/coder.md` (Ziel-Dateien / Randbedingung).
