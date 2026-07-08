---
id: regression-define
title: Regressions-Definier-Agent — Spec-Lesen, NL-Vorschlag, Redaktionsschleife, Playwright-Übersetzung
status: active
version: 3
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
- **AC9** — **Slash-Command-Einstieg:** `skills/regression-define/SKILL.md` stellt den Aufruf `/agent-flow:regression-define` bereit (Muster der bestehenden Skills unter `skills/`) und **dispatcht den `regression-define`-Agenten** (`agents/regression-define.md`, Task-Tool) mit dem gemäss Verträge-Abschnitt geparsten Eingabe-Vertrag. Die Skill-Datei enthält **keine** Test-/Übersetzungslogik — sie reicht nur durch (Diskriminator `modus`, `projekt`, `bereich`/`verbund`, `stichworte`) und delegiert. Ohne diesen Skill ist der Agent als Slash-Command nicht aufrufbar (der headless dev-gui-Runner S-307 läuft sonst ins Leere).
- **AC10** — **Argument-/STDIN-Vertrag:** Der Skill parst den Diskriminator `modus`. In `modus: vorschlag` reicht er `projekt`, `bereich`/`verbund` und optionale `stichworte` als **Aufruf-Argumente** durch. In `modus: uebersetzen` liest er den `redigierter_vorschlag` (JSON, dieselbe Struktur wie das Rückgabeformat) aus **STDIN** — nicht als Inline-Argument, weil die redigierte Fassung beliebig gross werden kann —, sodass der dev-gui-Runner das redigierte JSON via STDIN übergeben kann. Fehlt in `modus: uebersetzen` der STDIN-`redigierter_vorschlag` → der Skill lehnt mit klarer Meldung ab, statt einen leeren/erfundenen Vorschlag zu übersetzen.
- **AC11** — **Resume-/Zweilauf-Verhalten (dev-gui S-307 Interrupt/Resume):** Der Einstieg unterstützt das zweiläufige Muster — Lauf 1 (`modus: vorschlag`) endet mit dem maschinenlesbaren Rückgabeformat für die Redaktionsschleife; nach der Owner-Redaktion knüpft Lauf 2 (`modus: uebersetzen`) an. Lauf 2 ist **selbst-tragend**: er arbeitet vollständig aus dem `uebersetzen`-Eingabe-Vertrag (`projekt` + `redigierter_vorschlag`) und **benötigt keinen** Zustand aus Lauf 1 (idempotent). Der Skill ist dabei mit `--resume`/Session-Resume kompatibel (der Runner darf denselben Kontext fortsetzen), erzwingt aber keinen Resume-Kontext.
- **AC12** — **Headless-Ausgabe-Disziplin:** Die **finale Ausgabe eines Skill-Laufs** ist **ausschliesslich** das maschinenlesbare Rückgabeformat (JSON gemäss Verträge-Abschnitt) — **keine Prosa** davor oder danach, **keine Rückfragen** an einen Menschen. Der headless dev-gui-Runner (S-307, `RegressionDefineRunner`) parst genau diese Finalausgabe; jede natürlichsprachliche Zusammenfassung oder Rückfrage im Finaltext bricht das Parsen („Vorschlag konnte nicht gelesen werden") und hat headless keinen Adressaten. Anmerkungen, Empfehlungen und Grenzfälle (z. B. Bereichs-Grenzfall „Löschen gehört zu `deployment`" oder eine Verbund-Empfehlung) gehören in das dafür vorgesehene Feld `hinweise[]` des Rückgabeformats, **nicht** in Freitext. In `modus: uebersetzen` bleibt die Finalausgabe das definierte Ergebnis-Objekt (PR-Link + Secrets-/Nicht-datengetrieben-Status); auch hier keine umschliessende Prosa und keine Rückfragen.

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

### Skill-Einstieg / Invocation (AC9–AC11)

Der Aufruf-Einstieg ist `skills/regression-define/SKILL.md` (Slash-Command `/agent-flow:regression-define`), gebaut nach dem Muster der bestehenden Skills (Frontmatter `name`/`description`; Auth via `ensure-gh-auth.sh` falls PR-Auslieferung; Cost-Mode-Auflösung wie `requirement`/`cicd`). Der Skill parst den Diskriminator `modus` und dispatcht den `regression-define`-Agenten:

**Lauf 1 — `modus: vorschlag`** (Argumente):
```
/agent-flow:regression-define modus=vorschlag projekt=<repo> (bereich=<bereich-id> | verbund=<verbund-name>) [stichworte=<w1,w2,…>]
```
Rückgabe: das maschinenlesbare Rückgabeformat (siehe unten) für die dev-gui-Redaktionsschleife.

**Lauf 2 — `modus: uebersetzen`** (redigierte Fassung via STDIN):
```
echo '<redigierter_vorschlag-JSON>' | claude -p '/agent-flow:regression-define modus=uebersetzen projekt=<repo>'
```
Der `redigierter_vorschlag` (dieselbe Struktur wie das Rückgabeformat, vom Owner editiert) kommt über **STDIN**, nicht als Inline-Argument (Grösse). Ergebnis: Playwright-Artefakte als PR/Commit (AC4–AC8). Lauf 2 ist selbst-tragend und `--resume`-kompatibel, aber nicht auf Lauf-1-Zustand angewiesen (AC11).

Headless-Konsument: dev-gui **S-307** (`RegressionDefineRunner`) startet genau diese beiden Läufe im Interrupt/Resume-Muster.

### Rückgabeformat Testvorschlag (dev-gui-Redaktionsschleife, maschinenlesbar)

Die **finale Ausgabe** eines `vorschlag`-Laufs ist genau **dieses** JSON-Objekt und **nichts sonst** (AC12) — keine umschliessende Prosa, keine Rückfrage. Alle Anmerkungen/Empfehlungen/Grenzfälle wandern in das Feld `hinweise[]`.
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
  "target_vorschlag": "local|ephemeral-infra|url",
  "hinweise": ["<Anmerkung/Empfehlung/Grenzfall in Alltagssprache>", "…"]
}
```
- **`hinweise`** (Array, darf leer sein): trägt alle natürlichsprachlichen Anmerkungen, Empfehlungen und Grenzfall-Hinweise, die früher als Freitext/Rückfrage im Finaltext gelandet wären — z. B. „Löschen gehört fachlich eher zu `deployment`" oder eine Verbund-Empfehlung. Der dev-gui-Runner zeigt diese dem Owner in der Redaktionsschleife an, statt dass der Skill eine Rückfrage stellt (AC12). Keine offenen Fragen an einen Menschen — nur maschinenlesbare Hinweise.

Nach der Owner-Redaktion wird dieselbe Struktur (redigiert, inkl. optional bereinigter `hinweise`) an den Agenten zurückgegeben und in Playwright-Artefakte übersetzt (AC4/AC5).

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
- `skills/regression-define/SKILL.md` — der Slash-Command-Einstieg (AC9–AC11), der diesen Agenten dispatcht; ohne ihn ist `/agent-flow:regression-define` nicht aufrufbar.
- dev-gui **S-307** (`RegressionDefineRunner`) — headless Konsument, der den Slash-Command im Interrupt/Resume-Muster startet (Cross-Repo-Abhängigkeit).
