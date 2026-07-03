---
id: requirement-area-intake
title: Requirement-Eingangs-Gate — Bereichs-Zuordnung, Begründungszwang, Ideen-Inbox
status: active
version: 1
spec_format: use-case-2.0
area: anforderung-intake
---

# Spec: Requirement-Eingangs-Gate  (`requirement-area-intake`)

> **Schicht 3 von 3.** Testbares **Verhalten + Verträge**, sprach-/paradigma-unabhängig (Intent, keine Idiome/Klassen).
> **Source of Truth** für `coder` (baut daraus — hier: baut das Gate in `agents/requirement.md` ein), `tester` (testet die Acceptance-Kriterien), `reviewer` (prüft den Diff dagegen — hartes Drift-Gate).
>
> **Detailkonzept-Bindung.** Diese Spec definiert das **Eingangs-Gate** des `requirement`-Agenten: wie eine neue Anforderung einem **bestehenden** Bereich ([[board-areas]]) zugeordnet wird, wie bereichsfremde Anforderungen autonom in die **Ideen-Inbox** wandern und wann (ausschliesslich bei echtem Konzept-Widerspruch) der Owner gefragt wird.

## Zweck

Das Front-of-Funnel-Gate stellt sicher, dass jede Anforderung die **stabile Strukturkarte** respektiert: sie landet unter einem bestehenden Bereich (Storys unters Bereichs-Feature, Spec-Erweiterung vor Spec-Neuanlage), oder — wenn sie erkennbar keinem Bereich zugehört — autonom in der Ideen-Inbox. `requirement` legt **nie** selbst neue Bereiche an; nur ein echter Konzept-Widerspruch eskaliert zum Owner.

## Kontext / Designnuancen (bindend)

- **`areas.yaml` ist die Zuordnungs-Basis.** `requirement` liest die Bereichsliste über `board area list` ([[board-area-ops]] AC1) / `board/areas.yaml` ([[board-areas]]).
- **Zuordnung zu einem bestehenden Bereich.** Jede Anforderung wird genau einem bestehenden Bereich zugeordnet; ihre Storys hängen unter das Bereichs-Feature dieses Bereichs, ihre Specs tragen `area: <bereich>`.
- **Spec-Erweiterung vor Spec-Neuanlage.** Innerhalb des zugeordneten Bereichs wird eine bestehende Spec fortgeschrieben, wenn sie thematisch trägt; eine neue Spec entsteht nur, wenn keine passende existiert.
- **`requirement` legt NIE neue Bereiche an.** Neue Bereiche sind eine Owner-Entscheidung; das Gate erzeugt keine Einträge in `areas.yaml`.
- **Bereichsfremdes → Ideen-Inbox, autonom.** Eine erkennbar bereichsfremde Anforderung (passt zu keinem bestehenden Bereich, ist aber kein Widerspruch zum Konzept) landet **autonom** — ohne Owner-Rückfrage — als Eintrag mit `status: Idee` in der Ideen-Inbox, mit einer Begründung, warum sie keinem Bereich zugeordnet wurde.
- **Owner-Rückfrage nur bei echtem Widerspruch.** Nur wenn die Anforderung dem Konzept/der Architektur **widerspricht** (nicht bloss neu ist), stellt das Gate eine Owner-Rückfrage (AskUserQuestion) — sonst arbeitet es autonom.
- **Begründungszwang.** Jede Bereichs-Zuordnung dokumentiert **einen Satz**, warum dieser Bereich — als nachvollziehbare Spur (im Story-/Spec-Kontext bzw. Lauf-Output).

## Main Success Scenario

1. `requirement` liest `board/areas.yaml` (via `board area list`).
2. Für die Anforderung bestimmt es den passenden **bestehenden** Bereich und dokumentiert 1 Satz Begründung.
3. Es schreibt/erweitert die Spec(s) im Bereich (Erweiterung vor Neuanlage) und stempelt neue Specs mit `area: <bereich>`.
4. Es legt die Storys unter dem **Bereichs-Feature** dieses Bereichs an (`parent` = Bereichs-Feature).
5. Der Lauf-Output nennt Bereich + Begründung je Zuordnung.

## Alternative Flows

### A1: bereichsfremde Anforderung (autonom)
- Die Anforderung passt zu keinem bestehenden Bereich, widerspricht aber nicht dem Konzept.
- `requirement` legt **keine** Story/Spec an, sondern schreibt einen Ideen-Inbox-Eintrag (`status: Idee`) mit Titel, Beschreibung und **Begründung**, warum kein Bereich passt — autonom, ohne Owner-Rückfrage.

### E1: Konzept-Widerspruch (Eskalation)
- Die Anforderung widerspricht Konzept/Architektur (nicht nur „neu").
- `requirement` stellt eine **Owner-Rückfrage** (AskUserQuestion) und legt bis zur Klärung weder Story/Spec noch Ideen-Eintrag final an.

## Acceptance-Kriterien

- **AC1** — `requirement` liest zu Lauf-Beginn die Bereichsliste aus `board/areas.yaml` (via `board area list`); fehlt `areas.yaml`, arbeitet es wie bisher (kein Bereichs-Gate) und vermerkt das im Output. *(V1)*
- **AC2** — Jede Anforderung wird genau einem **bestehenden** Bereich zugeordnet: die Storys werden unter das **Bereichs-Feature** dieses Bereichs gehängt (`parent`), neue Specs mit `area: <bereich>` gestempelt; innerhalb des Bereichs wird eine bestehende Spec fortgeschrieben, bevor eine neue angelegt wird. *(V2)*
- **AC3** — `requirement` legt **NIE** selbst einen neuen Bereich in `areas.yaml` an. *(V3)*
- **AC4** — Eine erkennbar bereichsfremde Anforderung (kein passender Bereich, aber kein Konzept-Widerspruch) landet **autonom** als Ideen-Inbox-Eintrag mit `status: Idee` und einer Begründung; es wird dafür **keine** Owner-Rückfrage gestellt und **keine** Story/Spec angelegt. *(V4, A1)*
- **AC5** — Nur ein echter **Konzept-Widerspruch** löst eine Owner-Rückfrage (AskUserQuestion) aus; blosse Neuheit einer Anforderung tut das nicht. *(V5, E1)*
- **AC6** — **Begründungszwang:** jede Bereichs-Zuordnung dokumentiert genau einen Satz, warum dieser Bereich; die Begründung erscheint nachvollziehbar im Lauf-Output (und, wo sinnvoll, im Story-/Spec-Kontext). *(V6)*
- **AC7** — Die Ideen-Inbox ist ein durables, append-only Register bereichsfremder Anforderungen; jeder Eintrag trägt mindestens `titel`, `beschreibung`, `begruendung`, `status: Idee` und einen ISO-8601-UTC-Zeitstempel. Bestehende Einträge werden nie überschrieben. *(V4)*

## Verträge

### Ideen-Inbox — Eintragsformat
*(Konservative Annahme zum Ablage-Ort: append-only Register unter `docs/ideas-inbox.md` — eine Doku-Datei, damit `requirement` ohne neuen board-CLI-Schreibpfad anlegen kann und das Board-Schema unberührt bleibt. Ein Eintrag pro Idee, newest-first oder chronologisch angehängt.)*
```
### <titel>
- status: Idee
- created_at: 2026-07-03T12:00:00Z
- begruendung: <1 Satz: warum keinem bestehenden Bereich zugeordnet>

<beschreibung: die Anforderung in 1–3 Sätzen>
```
Die Ideen-Inbox-Einträge tragen optional ein `area`-Feld, sobald ein `board area split` sie einem Ziel-Bereich vorschlägt ([[board-area-ops]] AC4).

### Bereichs-Zuordnung — Output-Zeile (Begründungszwang)
```
<anforderung> → Bereich <bereich-id> — <1 Satz Begründung>
```

## Edge-Cases & Fehlerverhalten

- **`areas.yaml` fehlt/leer** → Gate deaktiviert, requirement arbeitet wie vor der Bereichs-Umstellung (Output vermerkt „kein Bereichs-Gate: areas.yaml fehlt").
- **Anforderung berührt mehrere Bereiche** → sie wird in bereichs-reine Teil-Anforderungen zerlegt; jede Teil-Anforderung wird ihrem Bereich zugeordnet (je 1 Satz Begründung).
- **Grenzfall Bereichszugehörigkeit unklar, aber kein Widerspruch** → konservativ Ideen-Inbox (AC4) statt Owner-Rückfrage; die Begründung nennt die Unschärfe.
- **Owner nicht erreichbar (autonomer Lauf) + echter Widerspruch** → das Gate bricht den betroffenen Teil ab und benennt den Widerspruch im Output (statt zu raten).

## NFRs

- **Autonomie:** das Gate arbeitet ohne Owner, solange kein echter Widerspruch vorliegt.
- **Nachvollziehbarkeit:** jede Zuordnung und jede Ideen-Ablage trägt eine Begründung.
- **Nicht-destruktiv:** die Ideen-Inbox ist append-only; keine Anforderung geht verloren.

## Nicht-Ziele

- Das Bereichs-Datenmodell + Lint ([[board-areas]]).
- Bereichs-Operationen merge/split/archive ([[board-area-ops]]).
- Die A-priori-Schätzung bei Story-Anlage ([[metrics-estimation]] / [[apriori-token-estimate]]) — unverändert.
- Ein board-natives Ideen-Item-Schema (bewusst als leichtgewichtige Doku-Ablage gehalten; Aufwertung zu einem Board-Typ ist eine spätere Owner-Entscheidung).

## Abhängigkeiten

- [[board-areas]] — Bereichsliste + Feature-Kopplung, gegen die zugeordnet wird.
- [[board-area-ops]] — `board area list` (Lesezugriff) + `split` (das Ideen-Inbox-Einträge mit Ziel-Bereich anreichert).
- `agents/requirement.md` — der Agent, in den dieses Gate eingebaut wird.
</content>
