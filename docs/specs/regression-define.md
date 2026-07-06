---
id: regression-define
title: Regressions-Definier-Agent — Spec-Lesen, NL-Vorschlag, Redaktionsschleife, Playwright-Übersetzung
status: active
version: 1
spec_format: use-case-2.0
area: rollen-agenten
---

# Spec: Regressions-Definier-Agent  (`regression-define`)

> **Schicht 3 von 3.** Testbares **Verhalten + Verträge** des Definier-Agenten (`agents/regression-define.md`).
> **Source of Truth** für `coder` (baut die Agent-Definition), `reviewer` (Handoff-Vertrag + Drift-Gate), `tester` (prüft die AC).
>
> **Detailkonzept-Bindung.** Dieser Agent ist die **Definier-Rolle** des Regressions-Subsystems: er verwandelt die Bereichs-Specs in einen **natürlichsprachlichen Testvorschlag** für die dev-gui-Redaktionsschleife und übersetzt die vom Owner redigierte Fassung in Playwright-Testartefakte gemäß [[regression-playwright-conventions]]. Er **führt Tests nicht aus** (das ist [[regression-runner]]) und **heilt nicht** ([[regression-heal]]).

## Zweck

Testdefinition ohne Handarbeit am Testcode: der Agent liest die Specs eines Bereichs (oder eines Verbunds), schlägt in **Alltagssprache** Testfälle (Schritte, Prüfpunkte, Beispieldaten) vor, lässt den Owner in der dev-gui redigieren und übersetzt die **redigierte** Fassung deterministisch in Playwright-Testdatei + Datentabelle + Begleitbeschreibung. Auslieferung als PR/Commit zur Owner-Freigabe. Secrets erscheinen **nie** in den erzeugten Dateien.

## Kontext / Designnuancen (bindend)

- **Agenten nur beim Definieren + Heilen** — der Definier-Agent erzeugt Vorschläge/Artefakte, führt aber keine Testläufe aus (deterministischer Runner, [[regression-runner]]).
- **Zweistufig:** (a) Vorschlag in maschinenlesbarem Rückgabeformat → dev-gui-Redaktionsschleife (Mensch redigiert); (b) Übersetzung der redigierten Fassung → Playwright-Artefakte.
- **Owner-Redaktion ist maßgebend:** die Testdaten-Beispiele der Owner-Fassung werden **1:1** zur Datentabelle.

## Main Success Scenario

1. Eingabe: Projekt + Bereich (oder Verbund-Name) + optionale Owner-Stichworte.
2. Der Agent liest die Specs des Bereichs (Specs mit `area: <bereich>`) und leitet einen natürlichsprachlichen Testvorschlag ab (Schritte, Prüfpunkte, Beispieldaten).
3. Er gibt den Vorschlag im maschinenlesbaren Rückgabeformat für die dev-gui-Redaktionsschleife zurück.
4. Der Owner redigiert den Vorschlag in der dev-gui.
5. Der Agent übersetzt die redigierte Fassung in Playwright-Testdatei + Datentabelle (JSON) + Begleitbeschreibung (`.md`) gemäß [[regression-playwright-conventions]].
6. Er liefert das Ergebnis als PR/Commit zur Owner-Freigabe.

## Alternative Flows

### A1: Verbund-Suite (Infra)
- Eingabe nennt einen Verbund-Namen statt eines Bereichs → Artefakte landen unter `tests/regression/verbund/`; die Begleitbeschreibung trägt `target: ephemeral-infra` + eine **Kosten-/Ressourcen-Deklaration**.

### E1: Secret im Vorschlag/Testdaten
- Würde der Vorschlag oder die Übersetzung ein Secret in eine Testdatei/Datentabelle schreiben → der Agent lehnt ab und ersetzt es durch einen Runtime-Injektions-Platzhalter ([[regression-runner]] AC9), statt das Secret zu materialisieren.

## Acceptance-Kriterien

- **AC1** — Eingabe-Vertrag: **Projekt** + **Bereich** (Bereichs-`id`) **oder Verbund-Name** + **optionale Owner-Stichworte**.
- **AC2** — Der Agent liest die Specs des angegebenen Bereichs (Specs mit `area: <bereich>` bzw. die Verbund-relevanten Specs) und leitet daraus einen **natürlichsprachlichen** Testvorschlag ab: Schritte, Prüfpunkte, Beispieldaten.
- **AC3** — Der Vorschlag wird in einem **maschinenlesbaren** Rückgabeformat geliefert, das die dev-gui-Redaktionsschleife konsumiert (deckt A1: Verbund vs. Bereich).
- **AC4** — Nach Owner-Redaktion übersetzt der Agent die **redigierte** Fassung in Playwright-Testdatei + Datentabelle (JSON neben der Testdatei) + Begleitbeschreibung (`.md`) gemäß [[regression-playwright-conventions]]-Layout.
- **AC5** — Die **Testdaten-Beispiele der Owner-Fassung** werden **1:1** in die Datentabelle (JSON) übernommen.
- **AC6** — Die Begleitbeschreibung trägt den `target:`-Header ([[regression-runner]]); bei Infra-/Verbund-Suiten zusätzlich eine **Kosten-/Ressourcen-Deklaration** (deckt A1).
- **AC7** — Secrets erscheinen **nie** in erzeugten Testdateien/Datentabellen; ein Vorschlag/eine Übersetzung, die ein Secret einbetten würde, wird abgelehnt und durch einen Runtime-Injektions-Platzhalter ersetzt (deckt E1; → [[regression-runner]] AC9).
- **AC8** — Auslieferung erfolgt als **PR/Commit** zur Owner-Freigabe; der Agent merged nie selbst und pusht nie direkt auf einen geschützten Branch.

## Verträge

### Eingabe

Zwei Aufruf-Modi, unterschieden durch das Diskriminator-Feld `modus:`.

**Modus `vorschlag`** (Schritt 1–3 des Main Success Scenario):
```
projekt: <repo>
bereich: <bereich-id> | verbund: <verbund-name>
stichworte: [<optional>, …]
modus: vorschlag
```

**Modus `uebersetzen`** (nach der Owner-Redaktion in der dev-gui, Schritt 5–6):
```
projekt: <repo>
modus: uebersetzen
redigierter_vorschlag: <JSON — dieselbe Struktur wie das Rückgabeformat, vom Owner editiert>
```

### Rückgabeformat Testvorschlag (dev-gui-Redaktionsschleife, maschinenlesbar)
```json
{
  "projekt": "<repo>",
  "ziel": { "typ": "bereich|verbund", "id": "<bereich-id|verbund-name>" },
  "quell_specs": ["docs/specs/<feature>.md", "…"],
  "vorschlag": [
    {
      "titel": "<Testfall-Titel>",
      "schritte": ["<Schritt in Alltagssprache>", "…"],
      "pruefpunkte": ["<erwartetes beobachtbares Ergebnis>", "…"],
      "beispieldaten": [ { "<feld>": "<wert>" } ]
    }
  ],
  "target_vorschlag": "local|ephemeral-infra|url"
}
```
Nach der Owner-Redaktion wird dieselbe Struktur (redigiert) an den Agenten zurückgegeben und in Playwright-Artefakte übersetzt (AC4/AC5).

### Verbund-Spec-Auswahl (Präzisierung zu AC2)

Für `verbund: <verbund-name>` bestimmt der Agent die „Verbund-relevanten Specs" wie folgt: (1) jedes Element der Owner-**Stichworte**, das exakt einer Bereichs-`id` aus `board/areas.yaml` entspricht, zieht dessen Specs (`area: <id>`) hinzu; (2) ergänzend werden Specs herangezogen, deren `id`/`title` den Verbund-Namen wörtlich enthält. Liefert weder (1) noch (2) einen Treffer, gilt derselbe Edge-Case wie bei einem Bereich ohne Specs.

## Edge-Cases & Fehlerverhalten

- **Bereich/Verbund ohne deckende Specs** → der Agent meldet „keine deckenden Specs im Bereich/Verbund `<id>`" statt einen leeren/erfundenen Vorschlag zu liefern.
- **Redigierte Fassung entfernt alle Beispieldaten** → der Test wird ohne Datentabelle erzeugt (nicht-datengetrieben); die Begleitbeschreibung vermerkt das.

## NFRs

- **Nachvollziehbarkeit:** der Vorschlag nennt die Quell-Specs, aus denen er abgeleitet wurde.
- **Sicherheit:** kein Secret-Leak in versionierte Artefakte (AC7).

## Nicht-Ziele

- Testausführung, Testobjekt-Auflösung und Infra-Leitplanken ([[regression-runner]]).
- Reparatur roter Läufe ([[regression-heal]]).
- Die dev-gui-Redaktionsoberfläche selbst (separate dev-gui-Story) — hier nur das Rückgabeformat.

## Abhängigkeiten

- [[regression-playwright-conventions]] — Layout, Datentabellen-Format, Fixture-/Teardown-Muster, in die übersetzt wird.
- [[regression-runner]] — `target:`-Header + Runtime-Secret-Injektion, auf die der Agent verweist.
- `knowledge/playwright.md` — Coder-Guidance, die der Agent beim Übersetzen lädt (`/train --bootstrap`-Folgeaktion).
- dev-gui-Redaktionsschleife (separate dev-gui-Story) — konsumiert das Rückgabeformat.
