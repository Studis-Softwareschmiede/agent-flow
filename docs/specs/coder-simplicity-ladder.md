---
id: coder-simplicity-ladder
title: Simplicity-Leiter (Ponytail-Prinzip) in coder-Guidance + reviewer-Checkliste
status: active
area: rollen-agenten
version: 1
spec_format: use-case-2.0
---

# Spec: Simplicity-Leiter (Ponytail-Prinzip)  (`coder-simplicity-ladder`)

> **Schicht 3 von 3.** Testbares **Verhalten + Verträge**, sprach-/paradigma-unabhängig.
> **Source of Truth** für `coder` (baut daraus), `tester` (prüft die AC), `reviewer` (prüft den Diff dagegen — hartes Drift-Gate).

## Zweck

Token-Ersparnis über den bisher unbesetzten Hebel **weniger Code erzeugen** (statt Ausgaben kürzen): Der `coder` steigt vor jedem Neucode-Baustein eine bindende **Simplicity-Leiter** ab — wiederverwenden vor Standardbibliothek vor Plattform-Feature vor installierter Dependency vor Eigencode. Weniger generierter Code spart doppelt: beim Schreiben (Output-Tokens) und downstream (reviewer-Diff-Lektüre, tester-Umfang). Herkunft: destilliert aus dem Ponytail-Regelsatz (`DietrichGebert/ponytail`, MIT; Benchmark-belegt −22 % Tokens / −54 % LOC ohne Safety-Verlust) — **bewusst als eigene Regel übernommen, nicht als Plugin installiert** (dessen Hook-Injektion in alle Subagenten und „YAGNI gilt auch für Tests" kollidieren mit den Handoff-Verträgen bzw. dem Coverage-Gate). Einordnung + Ablehnungsbegründung der geprüften Alternativ-Tools: ADR [`docs/architecture/output-token-shaping.md`](../architecture/output-token-shaping.md) §7.

## Acceptance-Kriterien

- **AC1 — `agents/coder.md`: Regel `coder/R09` (Simplicity-Leiter).** Das Vorgehen erhält (bei Schritt 3, vor dem Implementieren) eine neue bindende Regel `coder/R09`: vor jedem **Neucode-Baustein** (Funktion/Komponente/Utility/Abstraktion) die Leiter absteigen und auf der **ersten tragfähigen Stufe** anhalten — (1) verlangt eine der genannten AC das überhaupt? (nein → weglassen, Verweis `coder/R01`); (2) existiert Gleichwertiges bereits im Projekt-Code → wiederverwenden/erweitern statt duplizieren; (3) Standardbibliothek der Projekt-Sprache; (4) natives Plattform-/Framework-Feature des deklarierten Stacks; (5) bereits installierte Dependency; (6) erst dann minimaler Eigencode. Die bestehende harte Grenze „keine neuen Deps ohne Not" bleibt unverändert das letzte Mittel **nach** Stufe 6.
- **AC2 — Vorrang-Klausel (im Regel-Text von `coder/R09`, HART).** Die Leiter kürzt **nie** an: den genannten AC (Spec = Vertrag), dem Coverage-Gate/Trace-Tags (jede genannte AC ≥ 1 deckender Test — YAGNI gilt **nicht** für geforderte Tests), dem Security-Floor, den Detailkonzept-Vorgaben (`architecture.md`/`data-model.md`/`design.md`) und den Lessons. Hält der `coder` eine AC selbst für überflüssig/vereinfachbar → bestehender Pfad `SPEC-LÜCKE` (Vorgehen-Schritt „Spec-Drift vermeiden"), **nie** stilles Weglassen.
- **AC3 — Handoff-Vermerk (schlank).** Führt die Leiter zu einer Wiederverwendungs-Entscheidung (Stufe 2–5 statt Eigenbau), vermerkt der `coder` das im `Done:`-Handoff mit **einer** Kurzzeile (z. B. `Simplicity: reused <Modul>` / `stdlib <API>`). Kein Pflicht-Boilerplate: greift die Leiter nicht (trivialer Fix, reiner Doku-Diff), entfällt die Zeile ersatzlos.
- **AC4 — `agents/reviewer.md`: Checklisten-Punkt `reviewer/R10`.** Der reviewer prüft den Diff auf Leiter-Verstöße: Eigenbau, wo Stufe 2–5 verfügbar war (Duplikat bestehenden Projekt-Codes, Stdlib-Nachbau, Nachbau einer bereits installierten Dependency) = **Important**-Befund, getaggt mit `coder/R09`. Reine Geschmacks-Vereinfachungen ohne Duplikat-/Nachbau-Charakter bleiben **Suggestions**. Kein neues Gate — die bestehende PASS-Regel (Critical+Important leer) bleibt unverändert.
- **AC5 — `AGENTS.md`-Nachzug (Selbst-Doku-Pflicht).** Der coder-Abschnitt (Roster §2) erwähnt die Simplicity-Leiter in einem Satz (Ablauf Punkt 3), der reviewer-Abschnitt (§3) den neuen Checklisten-Punkt — im **selben** PR wie AC1/AC4.

## Verträge
- Reine **Textänderung** an `agents/coder.md`, `agents/reviewer.md`, `AGENTS.md`. Kein Code, kein Hook, keine Dependency, kein Fremd-Plugin.
- Regel-IDs: `coder/R09` (Leiter + Vorrang-Klausel), `reviewer/R10` (Checklisten-Punkt) — stabile IDs für das Regel-ID-Tagging/Ledger (§5a).

## Edge-Cases & Fehlerverhalten
- **E1 — Wiederverwendung sprengt den Item-Scope:** Ist die tragfähige Stufe 2 nur per Refactor fremden Codes erreichbar (Scope-Creep-Gefahr), gilt die bestehende Grenze „bearbeitet NUR dieses Item": kleiner lokaler Anschluss ja, Quer-Refactor nein → dann ist Stufe 6 (minimaler Eigencode) korrekt und **kein** `reviewer/R10`-Befund.
- **E2 — Stufen-Konflikt mit Detailkonzept:** Schreibt `architecture.md`/`design.md` explizit eine Struktur/Komponente vor, gewinnt das Detailkonzept über die Leiter (AC2) — die Leiter optimiert innerhalb der Vorgaben, nie gegen sie.

## NFRs
- Sofort wirksam (Prompt-Disziplin), kein neues Tooling; erwarteter Effekt: weniger erzeugte LOC/Output-Tokens pro Story sowie kleinere Diffs für reviewer/tester.

## Nicht-Ziele
- **Keine** Installation des Ponytail-Plugins/-Hooks (keine Fremd-Injektion in Subagenten-Sessions).
- **Kein** „YAGNI für Tests" — das Coverage-Gate bleibt unangetastet.
- **Keine** Änderung am Wortlaut von `coder/R01`/`coder/R02` oder an der Verbatim-/Fidelity-Doktrin.
- **Keine** Pack-Änderungen (`knowledge/`): die Leiter ist sprach-neutral und gehört in die Rollen-Definition; sprachspezifische Stdlib-/Plattform-Hinweise bleiben dem normalen `train`/`retro`-Weg überlassen.

## Abhängigkeiten
- ADR [`docs/architecture/output-token-shaping.md`](../architecture/output-token-shaping.md) §7 (Tool-Prüfung 2026-07-21, Herkunft + Abgrenzung).
- `[[output-shaping-prompt-frugality]]` (Weg C — komplementär: dort sparsame Befehlswahl, hier sparsamer Neucode).
