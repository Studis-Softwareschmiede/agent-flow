---
id: parallel-session-plan
title: Wellen-Plan für parallele /flow-Sessions beim Board-Drain
status: active
version: 1
spec_format: use-case-2.0
area: flow-orchestrierung
---

# Spec: Wellen-Plan für parallele Sessions  (`parallel-session-plan`)

> **Schicht 3 von 3.** Testbares **Verhalten + Verträge**, sprach-/paradigma-unabhängig (Intent, keine Idiome/Klassen).
> **Source of Truth** für `coder` (baut daraus), `tester` (testet die Acceptance-Kriterien + Coverage-Gate), `reviewer` (prüft den Diff dagegen — hartes Drift-Gate).
>
> **Einordnung.** Hebt die bestehende Parallelität eine Ebene höher: heute plant `/flow` in §0a einen Abarbeitungsplan und parallelisiert **innerhalb** einer Session (SR1, parallele coder-Worktrees). Diese Spec macht den Plan zum **persistierten, maschinenlesbaren Artefakt**, sodass die äußere Schleife (dev-gui Nachtwächter/ProjectDrain) je Welle **mehrere unabhängige `/flow`-Sessions parallel** starten kann — jede mit frischem, kleinem Kontext (Session-Rotation-Rationale). SR1 bleibt als Innen-Parallelität bestehen.

## Zweck
Erhält der Orchestrator den Auftrag, ein Board abzuarbeiten, verschafft er sich **zuerst ein Bild**: welche Stories gibt es, welche Abhängigkeiten und Datei-Überschneidungen haben sie — und entwirft daraus einen **Wellen-Plan**, der ausweist, wie viele parallele Sessions die Abarbeitung fahren kann. Der Plan wird als Datei-Vertrag persistiert; die äußere Schleife führt ihn aus. Owner-Entscheid 2026-07-18: die Session-Zahl je Welle bestimmt der Plan **frei** nach fachlicher Unabhängigkeit (keine konfigurierte Obergrenze), weist sie aber sichtbar aus und begründet sie.

## Main Success Scenario
1. Der Plan-Schritt wird zu Drain-Beginn ausgelöst (neuer `/flow`-Modus `--plan`; einmal LLM, danach rein mechanisch): er liest alle To-Do-Stories des Boards (bereite und wartende), deren Specs, `depends`, Labels und berührte Dateien.
2. Aus (a) `depends`-Topologie, (b) Hot-Spot-Datei-Analyse (§0a) und (c) Konflikt-/„heben-sich-auf"-Check entsteht ein **Wellen-Plan**: Welle 1 = alle Stories, die sofort und untereinander konfliktfrei parallel laufen können; Welle 2 = Stories, die auf Welle-1-Ergebnisse warten; usw.
3. Der Plan wird maschinenlesbar nach `board/runs/session-plan.yaml` geschrieben und zusätzlich menschenlesbar ausgegeben (Wellen, Session-Zahl je Welle, Begründung je Gruppierung).
4. Die äußere Schleife liest den Plan und startet je Welle die geplanten `/flow`-Sessions **parallel** (eine Story je Session, bestehende Session-Rotation); nach Abschluss aller Sessions einer Welle folgt die nächste.
5. Vor jedem Wellen-Start wird der Plan **mechanisch revalidiert** (Board-Ist-Stand gegen Plan): erledigte Stories fallen raus, Stories mit nicht-terminalen `depends` (Blocked-Vorgänger) werden übersprungen und als WAITING gemeldet.

## Alternative Flows
### A1: Story wird während einer Welle Blocked
- Die Welle läuft zu Ende (andere Sessions sind unabhängig). Bei der Revalidierung vor der Folgewelle werden alle von der geblockten Story abhängigen Stories übersprungen (WAITING mit Grund); der Rest läuft weiter. Kein neuer LLM-Plan nötig.

### A2: Einzel-Lauf ohne Drain-Auftrag
- Ein normaler `/flow`-Aufruf ohne `--plan` verhält sich unverändert (heutiges §0a + SR1). Der neue Modus ist additiv.

### E1: Plan nicht erstellbar
- Kann der Plan-Schritt nicht abschliessen (Board unlesbar, keine To-Do-Stories), wird kein `session-plan.yaml` geschrieben; bei leerem Board greift die bestehende Leerlauf-Diagnose ([[empty-drain-diagnostics]]). Die äußere Schleife fällt ohne Plan-Datei auf ihr bisheriges serielles Verhalten zurück.

## Acceptance-Kriterien

- **AC1** — Plan-Modus: es existiert ein Plan-Schritt (`/flow --plan` als Einstieg), der alle To-Do-Stories liest und aus `depends`-Topologie + Hot-Spot-Analyse + Konflikt-Check einen Wellen-Plan erstellt; genau **ein** LLM-Planungsdurchgang pro Drain-Auftrag, alles Weitere mechanisch.
- **AC2** — Plan-Artefakt: der Plan wird nach `board/runs/session-plan.yaml` geschrieben (Schema siehe Verträge: Wellen mit Story-Listen, `parallel`-Zahl je Welle, Begründung je Gruppierung, `generated_at`, Plan-Schema-Version) und zusätzlich menschenlesbar ausgegeben.
- **AC3** — Konfliktfreiheit je Welle (HART): zwei Stories mit gemeinsamem Hot-Spot, direkter/transitiver `depends`-Beziehung oder erkanntem inhaltlichem Konflikt stehen NIE gemeinsam parallel in derselben Welle.
- **AC4** — Ein Schreiber je Story: der Plan garantiert, dass keine Story in mehr als einer Session/Welle gleichzeitig eingeplant ist. Die Board-Regel „einziger Schreiber von Board-Status" wird in `docs/architecture/board-subsystem.md` + `skills/flow/SKILL.md` präzisiert zu: **je Story genau ein schreibender `/flow`-Orchestrator**; parallele Sessions schreiben nur die YAML ihrer eigenen Story (+ eigene Metrik-Zeilen).
- **AC5** — Freie, aber ausgewiesene Session-Zahl: die Parallelität je Welle ergibt sich allein aus der fachlichen Unabhängigkeit (keine konfigurierte Obergrenze); der Plan weist die Zahl je Welle explizit aus und begründet die Gruppierung (welche Stories warum parallel/seriell) — sichtbar für den Owner.
- **AC6** — Mechanische Revalidierung vor jeder Welle: vor dem Start einer Welle wird der Plan gegen den aktuellen Board-Stand geprüft (Done/Verworfen = erfüllt; Blocked-Vorgänger ⇒ abhängige Stories übersprungen + WAITING-Meldung mit Grund); dafür ist **kein** weiterer LLM-Lauf nötig. *(deckt A1)*
- **AC7** — Landen bleibt seriell: parallele Sessions bauen gleichzeitig, aber die Merges nach `default_branch` laufen serialisiert (Rebase auf den aktuellen Stand vor jedem Merge, bestehende SR1-/board-ship-Mechanik); der Plan erzwingt keine parallelen Merges und dokumentiert die Land-Reihenfolge nicht vorab (first-come, seriell).
- **AC8** — ID-Reservierung als Vorbedingung: bevor eine Welle mit > 1 Session startet, deren Stories namespaced IDs (`BR`/`ADR`/`C`) vergeben könnten, wird der Reservierungs-Mechanismus aus [[id-block-reservation]] genutzt (je Session/Story-Kontext ein Block). Ohne funktionierende Reservierung startet keine parallele Welle mit ID-Vergabe-Risiko (Abbruch mit Klartext-Diagnose, analog id-block-reservation AC11).
- **AC9** — Konsumenten-Vertrag äußere Schleife: `session-plan.yaml` ist der dateibasierte Vertrag für den Nachtwächter/ProjectDrain (dev-gui): Schema + Semantik (Wellen nacheinander, Stories einer Welle parallel, eine Story je Session, Revalidierung vor Wellen-Start) sind in dieser Spec bindend definiert; die dev-gui-Implementierung ist eine separate Story im dev-gui-Repo (Nicht-Ziel hier). Fehlt die Plan-Datei, bleibt das bisherige serielle Verhalten der äußeren Schleife unverändert. *(deckt A2/E1)*
- **AC10** — Kein Plan bei leerem Board: ohne To-Do-Stories wird kein Plan-Artefakt geschrieben; die bestehende Leerlauf-Diagnose ([[empty-drain-diagnostics]]) bleibt unverändert. *(deckt E1)*

> **Traceability:** Jeder Test trägt das kanonische Trace-Tag `@trace parallel-session-plan#AC<n>`
> gemäss `knowledge/<lang>.md` → `## Spec-Tagging`. Der `tester` rechnet das Coverage-Gate
> (jede genannte AC ≥ 1 deckender Test). Details: `docs/architecture/traceability-subsystem.md`.
> Da agent-flow `language: md` ist, erfolgt die Abnahme der Skill-/Doku-Anteile als
> Doku-Inspektion; Plan-Schema + Revalidierungs-Logik werden — soweit mechanisch
> (Skript-Anteile) — über ein Smoke-Skript belegt (analog `tests/board-cli`).

## Verträge

### Plan-Artefakt `board/runs/session-plan.yaml` (ephemer, gitignored wie `board/runs/`)
```yaml
schema_version: 1
generated_at: '2026-07-18T06:00:00Z'   # ISO-8601
board_ref: agent-flow                   # project_slug aus board/board.yaml
waves:
  - wave: 1
    parallel: 3                         # Anzahl paralleler Sessions dieser Welle
    stories: [S-101, S-103, S-107]      # eine Story je Session
    rationale: 'disjunkte Dateien, keine depends untereinander'
  - wave: 2
    parallel: 1
    stories: [S-104]
    rationale: 'depends auf S-101; Hot-Spot skills/flow/SKILL.md mit S-103 → seriell'
```
- **Semantik:** Wellen strikt nacheinander; Stories innerhalb einer Welle parallel (eine Story je `/flow`-Session, Session-Rotation unverändert). `parallel` == Länge von `stories` (redundant, aber explizit — Owner-Sichtbarkeit AC5).
- **Revalidierung (mechanisch, vor jedem Wellen-Start):** Story nicht mehr To Do ⇒ raus; `depends` nicht terminal ⇒ überspringen + `WAITING <story>: wartet auf <dep> (<status>)`-Meldung.
- **Board-Schreibregel:** jede Session schreibt ausschliesslich die YAML ihrer zugeteilten Story (AC4).

## Edge-Cases & Fehlerverhalten
- **Alle Stories hängen in einer Kette:** der Plan degeneriert zu N Wellen à 1 Story — identisch zum heutigen seriellen Verhalten (korrekt, kein Sonderfall).
- **Plan veraltet (Board von Hand geändert):** die Revalidierung vor jedem Wellen-Start fängt das ab; grob invalide Pläne (referenzierte Story existiert nicht mehr) führen zum Abbruch des Drains mit Klartext-Diagnose, nicht zu stillem Weiterlaufen.
- **Feature-Batches (`board-feature-drain.sh`):** ein Feature-Batch zählt planerisch wie **eine** Session (das Feature landet als Einheit); Stories desselben Features werden nie auf mehrere parallele Sessions verteilt.
- **Abo-Limit:** bewusst KEINE Deckelung (Owner-Entscheid); drückt das Nutzungs-Limit, ist eine `max_parallel_sessions`-Deckelung als kleine Folge-Story nachrüstbar — der Plan-Mechanismus bleibt dafür unverändert.

## NFRs
- Token-Ökonomie: ein LLM-Plan pro Drain; Revalidierung und Wellen-Steuerung sind deterministisch (Bash/Skript, kein LLM).
- Sichtbarkeit: der Owner sieht vor dem Start, wie viele Sessions parallel laufen werden und warum (AC5).
- Robustheit: eine geblockte Story stoppt nie die ganze Abarbeitung — nur ihren Abhängigkeits-Ast (AC6).

## Nicht-Ziele
- **Keine** dev-gui-Implementierung (Nachtwächter-Seite = separate Story im dev-gui-Repo; hier nur der Datei-Vertrag).
- **Keine** konfigurierbare Session-Obergrenze (bewusst; nachrüstbar, s. Edge-Cases).
- **Keine** Ablösung von SR1 (Innen-Parallelität bleibt für eng verwandte Kleingruppen) oder der Feature-Batch-Orchestrierung.
- **Keine** parallele Merge-/Land-Mechanik — `default_branch` bleibt die eine, seriell bediente Senke.
- **Keine** Änderung an der Story-Auswahl-Logik von `board next` (Priority/Depends-Gate bleibt CLI-Hoheit).

## Abhängigkeiten
- [[id-block-reservation]] (S-063) — **Vorbedingung** für parallele Wellen mit ID-Vergabe-Risiko (AC8); die Story zu dieser Spec hängt per `depends` an S-063.
- [[feature-batch-orchestration]] — Feature-Batches als planerische Einheit.
- [[flow-session-rotation]] — eine Story je Session bleibt der Baustein, den der Plan orchestriert.
- [[empty-drain-diagnostics]] — Leerlauf-Verhalten unverändert (AC10).
- `skills/flow/SKILL.md` (§0a wird zum Plan-Modus ausgebaut), `docs/architecture/board-subsystem.md` (Schreibregel-Präzisierung AC4).
- Entscheidungsquelle: Owner-Entscheid 2026-07-18 (Dialog-Session, „Plan-Artefakt, Session-Zahl frei, S-063 zuerst").
