---
id: board-areas
title: Bereichs-Features — board/areas.yaml, Feature-Bereichs-Kopplung, Bereichs-Lint
status: active
version: 1
spec_format: use-case-2.0
area: board
---

# Spec: Bereichs-Features  (`board-areas`)

> **Schicht 3 von 3.** Testbares **Verhalten + Verträge**, sprach-/paradigma-unabhängig (Intent, keine Idiome/Klassen).
> **Source of Truth** für `coder` (baut daraus), `tester` (testet die Acceptance-Kriterien), `reviewer` (prüft den Diff dagegen — hartes Drift-Gate).
>
> **Detailkonzept-Bindung.** Das Board-Subsystem ist in `docs/architecture/board-subsystem.md` spezifiziert (bindend, §3–§6). Diese Spec ergänzt das Board um die **Bereichs-Ebene**: `board/areas.yaml` (die stabile Strukturkarte der Applikation), die Kopplung Feature→Bereich, die Bereichs-Semantik (Bereichs-Feature ist dauerhaft, Archiv-Semantik liegt auf der Story) und die zugehörigen `board lint`-Regeln. Sie steht neben [[board-schema]] (Datei-Fundament) und wird von [[board-cli]] (Lint) sowie [[board-area-ops]] (Bereichs-Operationen) ausgeführt.

## Zweck

Features werden von **Auftrags-Containern** zu einer **stabilen Strukturkarte** der Applikation umgestellt: Ein *Bereichs-Feature* entspricht einem dauerhaften Produktbereich (Kachel), Storys docken an Bereiche an, und neue Features entstehen nur bei echten neuen Produktbereichen. `board/areas.yaml` ist die **eine Wahrheit** für Kacheln, Dropdowns, das Requirement-Eingangs-Gate und die Spec-Zuordnung.

## Kontext / Designnuancen (bindend)

- **Leitidee.** Ein Feature ist künftig ein *Bereich* (Produktbereich/Kachel), kein Auftrags-Container. Storys sind die Aufträge und hängen unter einem Bereichs-Feature. Neue Features entstehen ausschliesslich bei echten neuen Produktbereichen — nicht pro Anforderung.
- **`board/areas.yaml` = eine Wahrheit.** Die Liste der Bereiche lebt genau einmal je Projekt in `board/areas.yaml`. Kacheln, Dropdowns (dev-gui), das Requirement-Eingangs-Gate ([[requirement-area-intake]]) und die Spec-Bereichs-Zuordnung (`area:`-Frontmatter) speisen sich alle daraus.
- **Bereich ist ein Etikett, keine Datei-Struktur.** Die Bereichszuordnung von Feature/Spec/Story ist ein **Feld** (`area:` bzw. Feature-Kopplung), **NIE** eine Datei-Verschiebung. Spec-IDs, Spec-Dateinamen und Board-Dateinamen bleiben von Bereichs-Operationen unberührt ([[board-area-ops]]).
- **Bereichs-Feature ist dauerhaft.** Ein Bereichs-Feature wird nie „fertig": `board rollup` setzt es nicht automatisch auf `Done`/`Archived`, auch wenn alle Kind-Storys terminal sind.
- **Archiv-Semantik wandert vom Feature auf die Story.** Erledigte (`Done`) Storys sind archivierbar; das Bereichs-Feature bleibt bestehen. Die Mechanik (`board archive-done-stories`) definiert [[board-area-ops]].
- **`board.yaml` bleibt Meta.** Der ID-Zähler bleibt in `board/board.yaml` ([[board-schema]] V1); `areas.yaml` ist eine **eigene** Datei ohne ID-Zähler (Bereichs-`id` ist ein kebab-case-Slug, kein `F-`/`S-`-Muster).
- **Rückwärtskompatibilität.** Ein Feature **ohne** `area`-Feld (Alt-Feature vor Migration) bleibt gültig (kein `lint`-Fehler) bis die Migration ([[board-area-ops]], AC8 hier) es koppelt. Eine Spec **ohne** `area`-Frontmatter (Bestand) bleibt gültig bis zur Migration; **neue** Specs tragen `area` verpflichtend (AC6).

## Main Success Scenario

1. Ein Projekt legt `board/areas.yaml` mit seinen Produktbereichen an (bei `new-project`/`adopt` aus dem Konzept gescaffoldet — [[new-project-board]]).
2. Je Bereich existiert **genau ein** dauerhaftes Bereichs-Feature, das über sein `area`-Feld auf den Bereich zeigt.
3. Eine neue Anforderung wird vom Requirement-Gate einem **bestehenden** Bereich zugeordnet ([[requirement-area-intake]]); ihre Storys hängen unter dem Bereichs-Feature, ihre Spec trägt `area: <bereich>`.
4. `board lint` prüft, dass jede `area`-Referenz (Feature + Spec) auf einen in `areas.yaml` definierten Bereich zeigt.
5. Erledigte Storys werden archiviert; das Bereichs-Feature bleibt und sammelt weiter neue Storys.

## Alternative Flows

### E1: verwaiste Bereichs-Referenz
- Ein Feature oder eine Spec nennt eine `area`, die in `areas.yaml` nicht (mehr) existiert → `board lint` meldet `AREA-UNKNOWN` als **Fehler**.

### E2: `areas.yaml` fehlt / malformt
- `areas.yaml` fehlt → Bereichs-Regeln werden übersprungen (kein Fehler, solange kein Item eine `area` referenziert); referenziert ein Item eine `area` ohne `areas.yaml` → `AREA-UNKNOWN`.
- `areas.yaml` verletzt das Feldformat (fehlendes `id`/`titel`/`reihenfolge`, `id` nicht kebab-case, doppelte `id`, doppelte `reihenfolge`) → `AREA-FIELD` als **Fehler**.

## Acceptance-Kriterien

- **AC1** — `board/areas.yaml` ist eine YAML-Liste von Bereichen; jeder Bereich trägt `id` (kebab-case, projektweit eindeutig), `titel` (Kurztitel), `beschreibung` (genau 1 Satz) und `reihenfolge` (int, eindeutig, für die Kachel-/Dropdown-Sortierung). `areas.yaml` ist die einzige Quelle der Bereichsliste (Kacheln, Dropdowns, Gate, Spec-Zuordnung). *(V1)*
- **AC2** — Ein Bereichs-Feature trägt das Feld `area: <bereich-id>`, das auf einen `areas.yaml`-Eintrag zeigt; `board/feature.schema.json` kennt das optionale Feld `area` (String|null). Genau ein Bereichs-Feature je Bereich ist das Soll (mehrere Features auf denselben Bereich sind erlaubt, aber `board lint` meldet sie als **Warnung** `AREA-DUP-FEATURE`). *(V2)*
- **AC3** — Ein Bereichs-Feature (Feature mit gesetztem `area`) ist dauerhaft: `board rollup` setzt es NIE automatisch auf `Done`/`Archived`, auch wenn alle Kind-Storys terminal (`Done`/`Verworfen`) sind; `progress` wird weiter berechnet, der `status` bleibt unverändert (z.B. `Active`). *(V3)*
- **AC4** — Die Archiv-Semantik liegt auf der Story: erledigte (`Done`) Storys sind archivierbar; das Bereichs-Feature wird dabei NIE archiviert. Die ausführende Mechanik ist `board archive-done-stories` ([[board-area-ops]] AC3). *(V4)*
- **AC5** — `board lint` prüft je Feature-`area` und je Spec-`area`-Frontmatter, dass der Wert in `areas.yaml` existiert; unbekannter/verwaister Bereich → **Fehler** `AREA-UNKNOWN <datei> <area-wert>`. Ein malformtes `areas.yaml` (fehlende Pflichtfelder, `id` nicht kebab-case, doppelte `id`/`reihenfolge`) → **Fehler** `AREA-FIELD <detail>`. Fehlt `areas.yaml` und referenziert kein Item eine `area` → keine Bereichs-Fehler. *(V5)*
- **AC6** — `templates/_docs/specs/_template.md` trägt im Frontmatter das Feld `area:` (Pflicht für **neue** Specs, Bestand optional bis Migration). `requirement` stempelt `area` beim Anlegen einer neuen Spec mit dem zugeordneten Bereich (analog zum `spec_format`-Stempel, [[requirement-area-intake]] AC2/AC6). *(V6)*
- **AC7** — Die initiale `board/areas.yaml` von agent-flow enthält exakt die 10 owner-freigegebenen Bereiche (Vertrag unten): `board`, `flow-orchestrierung`, `rollen-agenten`, `anforderung-intake`, `wissen-packs`, `lernen-retro`, `metriken-schaetzung`, `vorlagen-scaffolding`, `auslieferung`, `doku-reconcile` — mit den dort genannten `titel`/`beschreibung`/`reihenfolge`. *(V7)*
- **AC8** — Bestandsmigration agent-flow: die 15 Bestands-Features werden den 10 Bereichen zugeordnet (je Bereich ein dauerhaftes Bereichs-Feature), alle Storys werden unter das jeweilige Bereichs-Feature umgehängt (`parent` neu, Story-`id`/Spec unverändert), erledigte Storys archiviert und alle Specs mit `area` gestempelt. Die Migration wird als **EIN PR** zur Owner-Freigabe vorgelegt; **keine autonome Löschung** (Alt-Features werden auf `Archived` gesetzt, nicht gelöscht). Nach der Migration ist `board lint` grün. *(V7, V5, [[board-area-ops]])*

## Verträge

### `board/areas.yaml` (Feldformat)
```yaml
- id: board                    # kebab-case, projektweit eindeutig
  titel: Board
  beschreibung: Schema, board-CLI, Lint, GitHub-Export und die Bereichsliste selbst.
  reihenfolge: 1
- id: flow-orchestrierung
  titel: Flow-Orchestrierung
  beschreibung: flow-Skill, Session-Rotation, Gates, Item-Auswahl und Leerlauf-Diagnose.
  reihenfolge: 2
```

### `feature.schema.json` — neues Feld
```
area: <bereich-id> | null      # optional; String, muss (falls gesetzt) in areas.yaml existieren
```

### Spec-Frontmatter — neues Feld
```
area: <bereich-id>             # Pflicht für neue Specs; Bestand optional bis Migration
```

### agent-flow — initiale `board/areas.yaml` (owner-freigegeben, AC7)
```yaml
- id: board
  titel: Board
  beschreibung: Schema, board-CLI, Lint, GitHub-Export und die Bereichsliste.
  reihenfolge: 1
- id: flow-orchestrierung
  titel: Flow-Orchestrierung
  beschreibung: flow-Skill, Session-Rotation, Gates, Item-Auswahl und Leerlauf-Diagnose.
  reihenfolge: 2
- id: rollen-agenten
  titel: Rollen-Agenten
  beschreibung: Agent-Definitionen und Handoff-Verträge der Fabrik-Rollen.
  reihenfolge: 3
- id: anforderung-intake
  titel: Anforderung-Intake
  beschreibung: requirement mit Eingangs-Gate, estimator, Ideen-Inbox und from-notes.
  reihenfolge: 4
- id: wissen-packs
  titel: Wissen-Packs
  beschreibung: Knowledge Packs, train sowie Modell-Matrix und Cost-Modes.
  reihenfolge: 5
- id: lernen-retro
  titel: Lernen-Retro
  beschreibung: retro, Lessons-Lebenszyklus und Write-back.
  reihenfolge: 6
- id: metriken-schaetzung
  titel: Metriken-Schaetzung
  beschreibung: Ledger, Baseline, Kalibrierung und Token-Erfassung.
  reihenfolge: 7
- id: vorlagen-scaffolding
  titel: Vorlagen-Scaffolding
  beschreibung: templates, new-project und adopt.
  reihenfolge: 8
- id: auslieferung
  titel: Auslieferung
  beschreibung: cicd, Landen, CI-Watch, Rollout und preview.
  reihenfolge: 9
- id: doku-reconcile
  titel: Doku-Reconcile
  beschreibung: Konzept-/Architektur-Pflege, reconcile und Spec-Lebenszyklus.
  reihenfolge: 10
```

### `lint`-Regel-IDs (stabil, für CLI-Ausgabe)
`AREA-UNKNOWN` (V5, Fehler — Feature/Spec nennt Bereich, der nicht in `areas.yaml` existiert) · `AREA-FIELD` (V5, Fehler — `areas.yaml` malformt: fehlende Pflichtfelder, `id` nicht kebab-case, doppelte `id`/`reihenfolge`) · `AREA-DUP-FEATURE` (V2, Warnung — mehrere Features auf denselben Bereich gekoppelt).

## Edge-Cases & Fehlerverhalten

- **`areas.yaml` fehlt, kein Item hat `area`** → keine Bereichs-Fehler (Board vor Migration ist gültig).
- **Feature ohne `area`** (Alt-Feature) → kein Fehler (rückwärtskompatibel bis Migration).
- **Spec ohne `area`-Frontmatter** (Bestand) → kein Fehler; **neue** Spec ohne `area` ist ein Prozess-Verstoss des `requirement` (nicht durch `lint` erzwungen, da `lint` „neu" nicht kennt) — der Owner sieht es im Review.
- **`area`-`id` mit Grossbuchstaben/Leerzeichen** → `AREA-FIELD` (nicht kebab-case).
- **Bereichs-Feature mit allen Storys `Done`** → bleibt `Active`, wird nicht auto-`Done` (AC3); die Done-Storys können archiviert werden (AC4).
- **Story hängt an einem Alt-(Auftrags-)Feature** → gültig bis Migration; nach Migration hängt sie am Bereichs-Feature.

## NFRs

- **Diff-Freundlichkeit:** `areas.yaml` ist eine kleine, selten geänderte Datei; stabile Reihenfolge nach `reihenfolge`.
- **Determinismus:** die Bereichs-`lint`-Regeln laufen ohne LLM, rein mechanisch.
- **Stabilität der Referenzen:** Bereichszuordnung ist ein Etikett — Spec-/Datei-IDs bleiben über Merge/Split/Migration hinweg stabil.

## Nicht-Ziele

- CLI-Verben für Bereichs-Operationen (merge/split/archive) — [[board-area-ops]].
- Das Requirement-Eingangs-Gate selbst — [[requirement-area-intake]].
- Scaffolding der Start-`areas.yaml` bei `new-project`/`adopt` — [[new-project-board]].
- Kern-Datei-/ID-Format (Feature/Story-YAML, `board.yaml`) — [[board-schema]].
- dev-gui-Kachel-Rendering — Konsument von `areas.yaml`, ausserhalb dieser Spec.

## Abhängigkeiten

- [[board-schema]] — Datei-Fundament (Feature/Story-YAML, `board.yaml`), das um `area` erweitert wird.
- [[board-cli]] — führt die Bereichs-`lint`-Regeln aus (`board lint`) und ist die format-kennende Stelle.
- [[board-area-ops]] — Bereichs-Operationen (merge/split/archive) + Bestandsmigration.
- [[requirement-area-intake]] — Eingangs-Gate, das `areas.yaml` liest und Specs/Storys Bereichen zuordnet.
- [[new-project-board]] — scaffoldet die Start-`areas.yaml` aus dem Konzept.
- `docs/architecture/board-subsystem.md` §3–§6 — bindendes Detailkonzept (gewinnt einen `areas.yaml`-Abschnitt).
</content>
</invoke>
