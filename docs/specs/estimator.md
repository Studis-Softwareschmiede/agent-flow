---
id: estimator
title: Schätz-Agent — Referenz-Story-basierte Dispo-Schätzung (Few-shot) + Selbstverbesserung via retro
status: draft
version: 1
---

# Spec: Schätz-Agent  (`estimator`)

> **Schicht 3 von 3.** Testbares **Verhalten + Verträge**, sprach-/paradigma-unabhängig (Intent, keine Idiome/Klassen).
> **Source of Truth** für `coder` (baut daraus), `tester` (testet die Acceptance-Kriterien), `reviewer` (prüft den Diff dagegen — hartes Drift-Gate).
>
> **Detailkonzept-Bindung.** Das Board-Subsystem ist in `docs/architecture/board-subsystem.md` spezifiziert (bindend, §4.4 „Dispo"). Diese Spec beschreibt die **Agenten-Capability**, die bei `L`/`XL`-Stories die rein heuristische Schätzung aus [[metrics-estimation]] (dort V2/AC2) durch eine **referenz-story-basierte Few-shot-Schätzung** ersetzt und einen **Selbstverbesserungs-Kreis über `retro`** etabliert. Sie setzt das Ledger ([[metrics-ledger]]), die `baseline.json`-Aggregation ([[metrics-retro-aggregation]]) und die Retro-Effektivitätslogik ([[metrics-retro-effectiveness]]) voraus.

## Zweck

Vorab pro Story eine möglichst gute **Dispo-Schätzung** (`dispo_est` in EP + erwartete Tokens) liefern — und zwar nach der Methode, die sich sowohl in der agilen Praxis als auch in der LLM-Forschung als am stärksten erwiesen hat: **relativ gegen Referenz-Stories** (Anker), gespeist als Few-shot-Beispiele. Die Schätzgüte verbessert sich kontinuierlich, indem `retro` den Soll-Ist-Abgleich auswertet und den estimator schichtweise nachkalibriert.

## Kontext / Designnuancen (bindend)

- **Hybrid, token-bewusst.** `S`/`M`-Stories werden **nicht** vom estimator geschätzt — sie laufen rein heuristisch in `/flow` ([[metrics-estimation]] V1). Der estimator-Agent wird **nur bei `L`/`XL`** dispatcht (oder explizit on-demand). Damit fallen Token nur dort an, wo Schätzen wirklich schwer ist.
- **Relativ, nicht absolut.** Der Agent erfindet keine freie Zahl. Er schätzt **relativ** gegen konkrete Beispiel-Stories mit bekanntem Aufwand (Analogy-Based Estimation / Case-Based Reasoning + Few-shot). Die Beispiele kommen aus zwei Quellen: einem kuratierten **Anker-Katalog** (`knowledge/reference-stories.md`) und **Retrieval** der ähnlichsten abgeschlossenen Stories aus `items.jsonl`.
- **EP, keine Währung.** Dispo wird in EP (Effort Points) geschätzt, zusätzlich als erwartete Tokens ausgewiesen. **Kein** Geldwert (Abo-Modell, vgl. [[frontier-cost-mode]]).
- **Funktioniert ab Tag 0.** Bei leerer Historie schätzt der Agent allein über die kuratierten Anker (Cold-Start). Mit wachsender `items.jsonl` verschiebt sich das Gewicht zu realen, retrievten Beispielen.
- **Selbstverbesserung in Schichten mit klarer Autonomie-Grenze.** `retro` passt **nur numerische** Korrekturfaktoren (`estimator_bias`) **automatisch** an. Jede Änderung am **Anker-Katalog** und an der **Agent-Anweisung** läuft über **PR+Gate** (nie Direkt-Edit; Mensch im Loop) — konsistent mit der retro-Policy.
- **Blockiert nie den Loop.** Jeder Fehlerpfad fällt sauber auf `dispo_est = null` mit Begründung zurück (Loop-Schonung, vgl. metrics-subsystem K3).

## Verhalten

### V1 — Dispatch-Bedingung
`/flow` dispatcht den estimator **genau dann**, wenn die Heuristik ([[metrics-estimation]] V1) `size_est ∈ {L, XL}` ergibt, oder wenn explizit `--estimate` für eine Story angefordert wird. `S`/`M` werden ohne Agent rein heuristisch geschätzt. Der estimator **ersetzt** die bisherige 1-Satz-LLM-Korrektur ([[metrics-estimation]] V2) für `L`/`XL`.

### V2 — Few-shot-Beispiele zusammenstellen (scale-aware + Retrieval)
Der estimator stellt seine Beispiel-Menge aus zwei Quellen zusammen:
1. **Anker-Katalog** (`knowledge/reference-stories.md`): die kanonischen Referenz-Stories, **scale-aware** — mindestens je ein Anker pro Grössenklasse `S`/`M`/`L`/`XL`, mit Anker-EP und Fingerprint.
2. **Retrieval** aus `items.jsonl`: die **K ähnlichsten abgeschlossenen** Stories (Default K=5) nach der Ähnlichkeitsfunktion *S1*. Nur Stories mit nicht-`null` `ep_act` sind retrievebar.

**Ähnlichkeitsfunktion S1** (deterministisch, token-frei): gleiche `lang` (harte Vorbedingung, sonst nachrangig) → Label-Überlappung (Jaccard über `labels`) → Nähe von `n_ac` und `n_comp` (kleinere Differenz = ähnlicher). Die Top-K nach S1 werden als reale Beispiele übernommen.

### V3 — Relative Schätzung
Der estimator schätzt `dispo_est` (EP) **relativ** gegen die Beispiel-Menge (V2), begründet anhand der Spec-AC, der Komponenten und der Risikotreiber (`db`/`security`-Labels, offene `depends`, neue Tech, unklare/widersprüchliche AC). Zusätzlich:
- **Token-Erwartung:** `tok_est ≈ dispo_est / baseline.json.ep_per_token` (entfällt, falls `ep_per_token = null`).
- **Konfidenz:** `high | medium | low`, abgeleitet aus Anzahl/Streuung verfügbarer ähnlicher Beispiele und `baseline.json.forecast_mae`.
- **`estimate_note`:** 1–2 Sätze Begründung (Anker-Bezug, Haupttreiber, Risiko).

### V4 — Bias-Korrektur anwenden
Existiert in `baseline.json` ein `estimator_bias`-Faktor für den passenden Schnitt `<lang>|<cost_mode>|<size>`, wendet der estimator ihn auf die Roh-Schätzung an (`dispo_est = roh × (1 + bias)`). Fehlt der Schnitt → gröberer Schnitt → kein Faktor (Faktor 0). Der angewandte Faktor wird in `estimate_note` vermerkt.

### V5 — Cold-Start / Fallback
- **Keine passende Historie** (Retrieval liefert < 1 reale Story im Schnitt): Schätzung allein über die kuratierten Anker; Konfidenz höchstens `medium`.
- **Weder Anker noch Historie nutzbar:** `dispo_est = null`, Konfidenz `low`, `estimate_note` nennt den Grund. Die Heuristik-`size_est` bleibt erhalten.

### V6 — Split-Empfehlung
Stuft der estimator eine Story als `XL` mit hoher Unsicherheit ein (grosse Streuung der Beispiele oder Token-Erwartung über einem konfigurierten Schwellwert), gibt er eine **Split-Empfehlung** in `estimate_note` aus (Vorschlag, in n kleinere Stories zu zerlegen). Die Empfehlung ist beratend — sie ändert das Board nicht selbst.

### V7 — Output & Persistenz
Der estimator gibt `dispo_est` (EP), `tok_est`, `confidence` und `estimate_note` zurück. `/flow` schreibt `dispo_est` + `estimate_note` (+ `confidence`) in die Story (`board/stories/<id>.yaml`, vgl. board-subsystem §4.2) und führt `ep_est` wie gehabt in der `items.jsonl`-Zeile (Soll-Ist). Die Schätzung blockiert nie den Loop (V5-Fallback).

### V8 — Selbstverbesserung Hebel 1: Kalibrierung (automatisch)
`retro` (Aggregations-Modus) berechnet aus `items.jsonl` je Schnitt `<lang>|<cost_mode>|<size>` den **vorzeichenbehafteten** mittleren Schätzfehler (Bias) `ø(ep_est − ep_act) / ep_act` und schreibt daraus einen Korrekturfaktor `estimator_bias[<schnitt>]` **automatisch** in `baseline.json`. Nur dieser numerische Faktor ändert sich ohne menschliche Freigabe.

### V9 — Selbstverbesserung Hebel 2+3: Katalog & Anweisung (PR+Gate)
- **Hebel 2 (Anker-Katalog):** Erkennt `retro` schwache/veraltete Anker oder eine Grössenklasse ohne guten realen Anker, schlägt es eine Aktualisierung von `knowledge/reference-stories.md` aus realen, gut kalibrierten Done-Stories vor — als **PR** (nie Direkt-Edit).
- **Hebel 3 (Agent-Anweisung):** Bleibt ein systematisches Bias-Muster trotz Kalibrierung (V8) bestehen, destilliert `retro` daraus eine konkrete Änderung der estimator-Anweisung (`agents/estimator.md`) und liefert sie als **PR**. Mensch entscheidet.

### V10 — Validierungs-Gate
Jede Anpassung (V8-Faktor, V9-Anker, V9-Anweisung) wird markiert und über die nächsten `N` (Default `N_MIN=10`) `L`/`XL`-Stories beobachtet. Sinkt `forecast_mae` im betroffenen Schnitt → **Validated** (mit gemessener Verbesserung), sonst → **Reverted** (Rückbau auf den vorigen Stand). Status + Messung werden in `baseline.json` (`estimator_calibration`) mitgeführt — analog zu [[metrics-retro-effectiveness]].

## Acceptance-Kriterien

- **AC1** — `/flow` dispatcht den estimator genau bei `size_est ∈ {L,XL}` oder bei `--estimate`; `S`/`M` laufen ohne Agent; der estimator ersetzt die L/XL-1-Satz-Korrektur aus [[metrics-estimation]]. *(V1)*
- **AC2** — Die Few-shot-Menge enthält (a) scale-aware Anker aus `knowledge/reference-stories.md` (≥1 je `S/M/L/XL`) und (b) bis zu K=5 reale Stories aus `items.jsonl` mit nicht-`null` `ep_act`, ausgewählt per Ähnlichkeitsfunktion S1 (lang → Label-Jaccard → Nähe n_ac/n_comp). *(V2)*
- **AC3** — `dispo_est` wird relativ gegen die Beispiel-Menge geschätzt; zusätzlich werden `tok_est` (= `dispo_est / ep_per_token`, entfällt bei `ep_per_token=null`), `confidence ∈ {high,medium,low}` und `estimate_note` (1–2 Sätze, mit Anker-Bezug) erzeugt. *(V3)*
- **AC4** — Ein vorhandener `estimator_bias[<lang>|cost_mode|size>]` wird auf die Roh-Schätzung angewandt und in `estimate_note` vermerkt; fehlender Schnitt → kein Faktor. *(V4)*
- **AC5** — Cold-Start: ohne passende Historie schätzt der Agent allein über Anker (Konfidenz ≤ medium); ohne Anker und ohne Historie → `dispo_est = null`, `confidence=low`, Grund in `estimate_note`; `size_est` bleibt erhalten. *(V5)*
- **AC6** — Bei `XL` mit hoher Unsicherheit gibt der estimator eine beratende Split-Empfehlung in `estimate_note`; das Board wird dadurch nicht automatisch verändert. *(V6)*
- **AC7** — `/flow` persistiert `dispo_est`/`estimate_note`/`confidence` in die Story-YAML und `ep_est` neben `ep_act` in `items.jsonl`; die Schätzung blockiert nie den Loop. *(V7)*
- **AC8** — `retro` berechnet je Schnitt den vorzeichenbehafteten Bias und schreibt `estimator_bias` **automatisch** in `baseline.json` (einzige ohne PR erlaubte Änderung). *(V8)*
- **AC9** — Änderungen an `knowledge/reference-stories.md` und `agents/estimator.md` erfolgen ausschliesslich über PR+Gate (nie Direkt-Edit). *(V9)*
- **AC10** — Jede Anpassung wird über N≥10 L/XL-Stories als Validated/Reverted gegen `forecast_mae` bewertet; Ergebnis steht in `baseline.json.estimator_calibration`. *(V10)*

## Verträge

### Anker-Katalog — `knowledge/reference-stories.md` (kuratiert, committet)
Pro Anker (Markdown-Tabelle oder YAML-Frontmatter-Liste):

| Feld | Bedeutung |
|---|---|
| `id` | stabile Anker-ID, z.B. `ref-M-crud-endpoint` |
| `size` | `S` \| `M` \| `L` \| `XL` |
| `lang` | optional; Stack-spezifischer Anker, sonst generisch |
| `title` | kanonische Story-Beschreibung |
| `fingerprint` | `{ n_ac, n_comp, labels[] }` (für Ähnlichkeitsbezug) |
| `ep_anchor` | Anker-EP-Wert |
| `note` | warum dieser Anker repräsentativ ist |

### `baseline.json` — Erweiterungen (von `retro` gepflegt)
```
estimator_bias:        { "<lang>|<cost_mode>|<size>": <factor: float> }   // V8, auto
estimator_calibration: [ { target, kind: bias|anchor|prompt, status: pending|validated|reverted,
                           baseline_mae, measured_mae, n, decided_after_item } ]   // V10
```
(`ep_per_token`, `forecast_mae`, `medians` stammen aus [[metrics-retro-aggregation]].)

### Story-Felder (Sicht; SoT bleibt items.jsonl)
`dispo_est` (EP, oder `null`), `estimate_note` (text|null), `confidence` (high|medium|low) — vgl. board-subsystem §4.2/§4.4. ID-Brücke: `/flow` schreibt die Story-ID als `item`-Schlüssel ins Ledger.

### estimator-Output (an `/flow`)
```
{ dispo_est: float|null, tok_est: int|null, confidence: "high"|"medium"|"low",
  estimate_note: string, split_suggestion: null|{ into: int, rationale: string } }
```

## Edge-Cases & Fehlerverhalten

- **`ep_per_token = null`** → `tok_est = null`, EP-Schätzung trotzdem gültig.
- **`items.jsonl` fehlt/leer** → reiner Cold-Start (V5), nur Anker.
- **`reference-stories.md` fehlt** → nur Retrieval; fehlt beides → `dispo_est = null` (V5).
- **Widersprüchliche/leere Spec** → Konfidenz `low`, Hinweis in `estimate_note`; kein Abbruch.
- **Bias-Faktor implausibel** (|factor| über konfiguriertem Cap) → auf Cap begrenzt, in `estimate_note` vermerkt.
- **Retrieval findet nur andere `lang`** → niedriger gewichtet, Konfidenz sinkt.

## NFRs

- **Token-Budget:** ein LLM-Durchgang je L/XL-Story; S/M token-frei. Few-shot-Auswahl (S1) ist deterministisch ohne LLM.
- **Determinismus der Auswahl:** gleiche Eingaben → gleiche Beispiel-Menge (reproduzierbare Schätzbasis).
- **Auditierbarkeit:** jede Schätzung trägt ihre Begründung (`estimate_note`); jede Kalibrierung ist in `baseline.json` nachvollziehbar.

## Nicht-Ziele

- EP-Formel / Ledger-Schema ([[metrics-ledger]]).
- Heuristische S/M-Schätzung & `forecast_mae`-Definition ([[metrics-estimation]]).
- baseline.json-Grund-Aggregation/EP-Kalibrierung ([[metrics-retro-aggregation]]).
- Defektraten/LEARNINGS-Lebenszyklus ([[metrics-retro-effectiveness]]).
- Geldwert-Umrechnung (bewusst out-of-scope, Abo-Modell).
- Board-Speicherformat & dev-gui-Aggregation (`docs/architecture/board-subsystem.md`).

## Abhängigkeiten

- [[metrics-estimation]] — heuristische Basis (S/M, size_est, forecast_mae), deren L/XL-Korrektur dieser Agent ersetzt.
- [[metrics-ledger]] · [[metrics-retro-aggregation]] · [[metrics-retro-effectiveness]] — Ledger, baseline.json, Validated/Reverted-Mechanik.
- [[frontier-cost-mode]] — `cost_mode` als Schnitt-Schlüssel; Abo-Modell (kein Geldwert).
- `docs/architecture/board-subsystem.md` §4.4 — Dispo-Felder & ID-Brücke.
- Neuer Agent `agents/estimator.md` + neuer Katalog `knowledge/reference-stories.md` (über PR+Gate).
