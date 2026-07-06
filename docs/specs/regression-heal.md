---
id: regression-heal
title: Regressions-Heil-Agent — Selektor-Drift reparieren via Playwright-Healer, immer als PR
status: active
version: 1
spec_format: use-case-2.0
area: rollen-agenten
---

# Spec: Regressions-Heil-Agent  (`regression-heal`)

> **Schicht 3 von 3.** Testbares **Verhalten + Verträge** des Heil-Agenten (`agents/regression-heal.md`).
> **Source of Truth** für `coder` (baut die Agent-Definition), `reviewer` (Handoff-Vertrag), `tester` (prüft die AC).
>
> **Detailkonzept-Bindung.** Dieser Agent ist die **Heil-Rolle** des Regressions-Subsystems: bei einem roten Lauf wegen **UI-/Selektor-Drift** erzeugt er einen Reparatur-Diff über den Playwright-**Healer**-Ansatz (Test Agents ab v1.56) — **immer als PR** zur Owner-Freigabe, **nie** als Direkt-Fix. Er unterscheidet Selektor-Drift von echter Verhaltensänderung.

## Zweck

Selbstheilung ohne Selbst-Degradation: wenn eine Regressions-Suite rot läuft, weil sich UI/Selektoren geändert haben (nicht das Verhalten), schlägt der Agent die aktualisierten Locator/Selektoren als reviewbaren Diff vor. Der Owner entscheidet per PR — der Agent merged nie selbst und maskiert **keine** echte Regression.

## Kontext / Designnuancen (bindend)

- **Agenten nur beim Definieren + Heilen** — der Heil-Agent greift **nur** bei rotem Lauf, nicht im Normalbetrieb (deterministischer Runner, [[regression-runner]]).
- **Immer PR, nie Direkt-Fix** — jede Reparatur ist ein Diff zur Owner-Freigabe.
- **Playwright-Healer-Ansatz** — nutzt die Test-Agents-Heilung ab Playwright v1.56.

## Main Success Scenario

1. Ein Regressions-Lauf ist rot; der Fehlschlag wird als **UI-/Selektor-Drift** klassifiziert (Element umbenannt/verschoben, nicht Verhalten geändert).
2. Der Agent ermittelt über den Playwright-Healer-Ansatz die aktualisierten Locator/Selektoren.
3. Er erzeugt einen **Reparatur-Diff** an der/den betroffenen Testdatei(en).
4. Er öffnet einen **PR** mit dem Diff, referenziert den fehlgeschlagenen Lauf + die betroffenen Tests + die Drift-Diagnose.
5. Der Owner reviewt/merged den PR.

## Alternative Flows

### E1: echte Verhaltensänderung (keine Heilung)
- Der rote Lauf beruht auf einer echten Verhaltensänderung (nicht bloß Selektor-Drift) → der Agent **heilt nicht**, sondern meldet die Regression (Eskalation / Lauf bleibt rot), damit ein Selektor-Patch die echte Regression nicht maskiert.

## Acceptance-Kriterien

- **AC1** — Trigger: ein **roter** Regressions-Lauf, dessen Fehlschlag als **UI-/Selektor-Drift** klassifiziert ist (nicht eine echte Verhaltens-Regression).
- **AC2** — Der Agent erzeugt einen **Reparatur-Diff** (aktualisierte Selektoren/Locator) über den Playwright-**Healer**-Ansatz (Test Agents, Playwright ≥ v1.56).
- **AC3** — Die Reparatur wird **immer als PR** zur Owner-Freigabe geliefert; **nie** als Direkt-Fix, der Agent merged nie selbst / pusht nie direkt auf einen geschützten Branch.
- **AC4** — Der Agent unterscheidet Selektor-Drift (Heil-Kandidat) von echter Verhaltensänderung; eine echte Verhaltensänderung wird **nicht** geheilt, sondern eskaliert/bleibt rot (deckt E1) — kein Maskieren einer echten Regression.
- **AC5** — Der Heil-PR referenziert den fehlgeschlagenen Lauf + die betroffene(n) Testdatei(en) + die Drift-Diagnose (nachvollziehbare Spur).

## Verträge

### Heil-PR — Pflicht-Referenzen
```
- lauf:      <Run-ID / CTRF-Report-Referenz des roten Laufs>
- tests:     [tests/regression/<…>.spec.<ext>, …]
- diagnose:  <1–2 Sätze: warum Selektor-Drift, nicht Verhaltensänderung>
- diff:      <aktualisierte Locator/Selektoren>
```

## Edge-Cases & Fehlerverhalten

- **Klassifikation unsicher (Drift vs. Verhalten mehrdeutig)** → konservativ **nicht** heilen, sondern als mögliche Regression melden (AC4-Vorrang: keine stille Maskierung).
- **Playwright < v1.56 im Projekt** → der Healer-Ansatz ist nicht verfügbar; der Agent meldet die Vorbedingungs-Lücke (Version-Bump via [[regression-scaffolding]]/upgrade), statt zu raten.

## NFRs

- **Reversibilität:** jede Heilung ist ein PR/Commit → zurückrollbar.
- **Sicherheit:** kein Auto-Merge; kein Maskieren echter Regressionen.

## Nicht-Ziele

- Testausführung + Testobjekt-Auflösung ([[regression-runner]]).
- Neu-Definition von Tests ([[regression-define]]).

## Abhängigkeiten

- [[regression-runner]] — liefert den roten Lauf + CTRF-Report, auf den die Heilung reagiert.
- [[regression-define]] — erzeugt die Testartefakte, die geheilt werden.
- `knowledge/playwright.md` — Healer-/Test-Agents-Guidance (`/train --bootstrap`-Folgeaktion).
