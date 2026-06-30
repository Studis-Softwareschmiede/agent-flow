---
name: reconcile
description: Startet /agent-flow:reconcile — bringt die docs/ eines Projekts wieder mit der Realität in Deckung (rückwärtige Aufholung, Gegenstück zur vorwärtigen Drift-Disziplin). Stufe 1 (Form, läuft IMMER) hebt jede Spec mit veraltetem/fehlendem spec_format-Stempel automatisch auf die aktuelle Vorlage. Stufe 2 (Inhalt, nur bei leerem Kanban) lässt reviewer im Audit-Modus die Inhalts-Drift zwischen Code und Doku (concept/architecture/specs) ermitteln und zieht die Doku automatisch nach (Code ist maßgebend, kein Einzel-Nachfragen). Beide Stufen liefern zusammen genau EINEN Diff/PR zur Freigabe, protokolliert als EIN Block in docs/spec-audit.md. Kein eigener reconcile-Agent — Orchestrierung lebt komplett in diesem Skill. Aufruf: /agent-flow:reconcile.
---

# /agent-flow:reconcile

Bringt die `docs/` des **aktuellen** Projekt-Repos (cwd) wieder mit der Realität in Deckung — on-demand, in zwei Stufen. **Dieser Skill ist der einzige Schreiber** der Reconcile-Änderungen; es gibt **keinen** separaten `reconcile`-Agent (Vertrag `docs/architecture/reconcile-subsystem.md` §7, Spec `docs/specs/reconcile.md` AC1).

Bindende Quellen: `docs/specs/reconcile.md` (AC1–AC11) + `docs/architecture/reconcile-subsystem.md` (FINAL). **Dieser Skill implementiert Stufe 1 (AC1–AC5) UND Stufe 2 (AC6–AC9, Inhalts-Abgleich) vollständig.** Beide Stufen laufen in **derselben** Session; das Ergebnis (falls beide oder nur eine Stufe Änderungen erzeugt) wird **gemeinsam** als **ein** Diff/PR vorgelegt (§4) und **ein** Logbuch-Block geschrieben (§3) — „Pro Lauf ein Block" (AC10) bezieht sich auf den **gesamten** Reconcile-Lauf, nicht auf die einzelne Stufe.

## 0. Setup
- `.claude/profile.md` lesen → `merge_policy` (`pr`|`direct`), `default_branch`.
- Bei `merge_policy: pr`: Auth sicherstellen — `bash "${CLAUDE_PLUGIN_ROOT}/scripts/ensure-gh-auth.sh"`.
- `git status` — Working-Tree sollte sauber sein, bevor Stufe 1 schreibt (sonst vermischen sich fremde Änderungen mit dem Reconcile-Diff). Ist der Tree nicht sauber: Hinweis ausgeben, User entscheiden lassen, ob fortgefahren wird.

## 1. Stufe 1 (Form) — läuft IMMER (AC2)
Rein doku-intern (kein Code-Bezug) — läuft unabhängig vom Board-Zustand, auch bei vollem Kanban.

### 1a. Erkennung (AC3)
```
bash scripts/reconcile-stage1-detect.sh
```
Liefert pro Zeile TAB-getrennt: `<pfad>  <missing|outdated>  <aktueller-wert>  <ziel-wert>` für jede Spec unter `docs/specs/`, deren `spec_format` vom aktuellen Vorlagenwert (`templates/_docs/specs/_template.md`) abweicht oder ganz fehlt. Eine leere Ausgabe heißt: **keine Form-Drift** → Stufe 1 erzeugt keinen Diff, keinen Logbuch-Block (AC2/E2-Prinzip) — weiter zu §2.

### 1b. Konvertierung je gefundener Spec (AC4)
Für jede vom Detect-Schritt gemeldete Spec, **einzeln und isoliert** (E1 — ein Fehlschlag darf den Gesamtlauf nicht stoppen):

1. **Original lesen** (`Read`) — vollständiger Inhalt, inkl. Frontmatter.
2. **Restrukturieren** — die Skill-Session selbst ist hier "der konvertierende Agent" aus dem Vertrag (§6) — kein Task-Dispatch, keine neue `agents/`-Datei. Inhalt **verlustfrei** in die Abschnitts-Struktur der aktuellen Vorlage (`templates/_docs/specs/_template.md`) überführen:
   - Frontmatter: `id`/`title`/`status`/`version` unverändert übernehmen; `spec_format` auf den Vorlagenwert **neu stempeln**.
   - Bestehende Abschnitte auf die nächstliegende Vorlagen-Überschrift mappen (`## Zweck`, `## Main Success Scenario` *(optional, nur falls im Original vorhanden oder sinnvoll ableitbar)*, `## Alternative Flows` *(optional)*, `## Acceptance-Kriterien`, `## Verträge`, `## Edge-Cases & Fehlerverhalten`, `## NFRs`, `## Nicht-Ziele`, `## Abhängigkeiten`). Inhalt, der keiner Vorlagen-Überschrift sauber zuzuordnen ist, wird unter der inhaltlich nächsten Überschrift **angehängt** statt verworfen (lossless-first, kein hübsches Wegkürzen).
   - **AC-Nummern bleiben stabil** (Vorlage: „AC-IDs sind stabil — nicht umnummerieren"). Reine Format-/Reihenfolge-Anpassung, **keine** inhaltliche Umdeutung der Kriterien.
3. **Schreiben** (`Write`/`Edit`) — derselbe Pfad, restrukturierter Inhalt.
4. **Verifizieren** (Pflicht vor Übernahme — Lossless-Garantie mechanisch absichern):
   - `spec_format` der neu geschriebenen Datei == Vorlagenwert (erneuter Lauf von `reconcile-stage1-detect.sh` meldet die Datei NICHT mehr).
   - Pflicht-Abschnitte vorhanden: `## Zweck`, `## Acceptance-Kriterien`, `## Verträge`, `## Edge-Cases & Fehlerverhalten`, `## Nicht-Ziele`, `## Abhängigkeiten`.
   - **AC-Mengen-Gleichheit:** die Menge der `AC<n>`-Token im Original == die Menge im konvertierten Text (`grep -oE 'AC[0-9]+'`, als Set vergleichen) — keine AC verloren, keine erfunden.
   - **Grobe Inhalts-Untergrenze:** Zeichenzahl der konvertierten Datei ≥ 60 % der Original-Zeichenzahl (Heuristik gegen versehentliches Abschneiden; stilistisches Straffen ist erlaubt, Halbieren-oder-mehr ist verdächtig).
5. **Bei Verifikations-Fehlschlag (E1):** `git checkout -- <pfad>` (Revert auf Original — die Spec bleibt unverändert), die Spec auf die **Nicht-konvertiert-Liste** für den Skill-Output/PR-Bericht setzen, **weiter** mit der nächsten Spec (kein Abbruch des Gesamtlaufs).
6. **Bei Erfolg:** Pfad + Ziel-Version auf die **Konvertiert-Liste** setzen (für §1c/Logbuch).

### 1c. Logbuch-Zeilen sammeln (AC5/AC10/AC11) — Schreiben erfolgt gebündelt in §3
Für jede **tatsächlich konvertierte** Spec (AC11 — „Block enthält nur die getroffenen Änderungen"; nicht-konvertierte Specs sind **keine** Änderung und erscheinen **nicht** im Logbuch, sondern nur im PR-/Skill-Bericht, s. §1b.5) **eine** Zeile auf die **Stufe-1-Logbuch-Liste** sammeln:
```
Spec <pfad> auf <ziel-version> konvertiert
```
Diese Liste wird **nicht** sofort geschrieben — `scripts/spec-audit-append.sh` wird erst **einmal** in §3 aufgerufen, zusammen mit den Stufe-2-Zeilen aus §2d (AC10: „Pro Lauf **ein** Block" — bezieht sich auf den gesamten Reconcile-Lauf, nicht je Stufe einzeln getrennt geschrieben). Ist die Stufe-1-Konvertiert-Liste leer, trägt Stufe 1 einfach nichts zur gemeinsamen Liste bei (kein leerer Beitrag).

## 2. Stufe 2 (Inhalt) — NUR bei leerem Kanban (AC6–AC9)

### 2a. Vorbedingungs-Check (AC6, hart) — graceful bei fehlendem Board
```
bash scripts/reconcile-stage2-gate.sh
```
Liefert auf stdout **genau ein** Token (Details/Spaltenzahlen auf stderr, nur informativ):

- **`empty`** — alle vier Spalten (`To Do`/`In Progress`/`Blocked`/`In Review`) leer → Vorbedingung erfüllt, **weiter mit §2b**.
- **`not-empty`** — mindestens eine Spalte belegt → **Stufe 2 übersprungen**, Ausgabe „Stufe 2 übersprungen — erst Board leerräumen" (AC6/A1). Kein Audit-Dispatch, kein Doku-Nachzug. Weiter mit §3 (nur Stufe-1-Logbuch-Zeilen, falls vorhanden).
- **`no-board`** — das Board-Skelett fehlt (kein `board.yaml`) → die Vorbedingung ist **nicht prüfbar**; das Skript bricht dafür **nicht** hart ab (Review-Lehre S-011: `scripts/board` würde für schreibende Verben hart abbrechen — coder/L15 verlangt für lesende Prüfungen graceful Handling). Ausgabe „Stufe 2 übersprungen — kein Board-Skelett vorhanden, Vorbedingung nicht prüfbar" und **konservativ überspringen** (NFR „Vorsicht" — kein impliziter Inhalts-Abgleich, wenn nicht feststeht, ob noch etwas offen ist). Weiter mit §3.

Das Skript selbst terminiert in allen drei Fällen mit Exit 0 (reine Lese-/Report-Operation) — ein Exit ≠ 0 bedeutet ein echtes Aufrufproblem (z.B. `scripts/board` selbst defekt) und muss dem User gemeldet werden, ohne den Lauf vorzutäuschen.

### 2b. Erkennen — `reviewer` im Audit-Modus, Reconcile-Variante (AC7)
**Nur wenn §2a `empty` ergeben hat.** Dispatch (Task) des `reviewer`-Agenten im **Audit-Modus, Reconcile-Variante** (`agents/reviewer.md` „Audit-Modus — Reconcile-Variante"):

- **Input:** der Bestand des Projekt-Repos (kein Diff). Vergleichsbasis: `concept.md`/`CONCEPT.md` + `architecture.md`/`docs/architecture/*.md` + `docs/specs/*.md` gegen das **beobachtbare Verhalten im Code**. (Standard-Pfade laut Vorlage: `docs/concept.md` + `docs/architecture.md`; führt das Projekt stattdessen einen Root-`CONCEPT.md` und/oder mehrere `docs/architecture/*.md`-Subsystem-Verträge — wie dieses Repo selbst — gelten dessen tatsächliche Doku-Dateien als Vergleichsbasis.)
- **Drift-Heuristik = identisch zum Drift-Gate** (Endpunkte/UI/I-O/Fehler-Statuscodes/Datenfelder/NFR-Limits; reiner Refactor zählt **nicht**).
- **Output:** priorisierter Fund-Report, **je Fund**: `file:line` (Code-Fundstelle) + betroffenes Doku-Dokument + **Richtungsvorschlag** (konkrete Ziel-Formulierung für die Doku-Stelle). **Kein** Gate, **keine** Board-Items — reiner Bericht.
- Leerer Report (keine Drift) → **weiter mit §3 ohne Stufe-2-Beitrag** (A2/E2 — kein Rauschen).

### 2c. Nachziehen — Code ist maßgebend (AC8)
**Nur wenn §2b mindestens einen Fund geliefert hat.** Für **jeden** Fund, **automatisch und ohne Einzel-Nachfragen** (AC8 — „kein per-Drift-Prompt", der Mensch-Gate ist der finale Diff-Blick in §4, nicht eine Entscheidung je Fund):

1. **Existiert das betroffene Dokument:** `Read` (voller Inhalt) → `Edit` die betroffene Stelle entsprechend dem Richtungsvorschlag des `reviewer`-Funds. Code-Verhalten wird **wörtlich/inhaltlich** übernommen — keine eigene Interpretation über den Fund hinaus.
2. **Fehlt das Dokument komplett** (der Fund meldet „Dokument fehlt"): **dieselbe Layout-Erkennung wie in §2b** anwenden, BEVOR `Write` aufgerufen wird — kein blindes Anlegen der kanonischen Einzeldatei, wenn das Projekt bereits ein abweichendes Muster etabliert hat (coder/L27):
   - **Architektur:** `bash scripts/reconcile-doc-layout.sh architecture` ausführen. Liefert `multi` → existiert bereits ein `docs/architecture/`-Verzeichnis mit mindestens einer `*.md`-Subsystem-Datei (wie dieses Repo selbst) → neue Datei unter `docs/architecture/<subsystem>.md` anlegen (Subsystem-Name aus dem Fund-Kontext ableiten — Feature-/Komponentenname des Funds). Liefert `single` → kanonische Einzeldatei `docs/architecture.md` aus `templates/_docs/architecture.md` anlegen.
   - **Konzept:** `bash scripts/reconcile-doc-layout.sh concept` ausführen. Liefert `root` → existiert bereits ein Root-`CONCEPT.md` (wie dieses Repo) → dort die betroffene Sektion ergänzen statt einer neuen `docs/concept.md`. Liefert `canonical` → kanonisch `docs/concept.md` aus `templates/_docs/concept.md` anlegen.
   - **Spec:** unverändert `docs/specs/<feature>.md` aus `templates/_docs/specs/_template.md` (Specs sind bereits 1:1 pro Feature — keine Layout-Variante, `reconcile-doc-layout.sh` kennt diesen Typ nicht).
   In allen Fällen: gefüllt mit dem im Fund beschriebenen, beobachteten Verhalten. Kurz: derselbe Layout-Entscheid wie im Lese-/Vergleichspfad (§2b — „dessen tatsächliche Doku-Dateien als Vergleichsbasis") gilt symmetrisch für den Schreibpfad.
3. Jedes tatsächlich geänderte/neu angelegte Dokument auf die **Stufe-2-Logbuch-Liste** sammeln (§2d) — **ein** Eintrag pro Dokument (nicht pro Einzel-Fund, falls mehrere Funde dasselbe Dokument betreffen).

### 2d. Logbuch-Zeilen sammeln (AC9/AC10/AC11) — Schreiben erfolgt gebündelt in §3
Für jedes in §2c tatsächlich berührte Dokument **eine** Zeile auf die **Stufe-2-Logbuch-Liste**:
```
Konzept <pfad> nachgezogen        (bestehendes Dokument geändert)
Architektur <pfad> nachgezogen    (bestehendes Dokument geändert)
Spec <pfad> nachgezogen           (bestehendes Dokument geändert)
Spec <pfad> neu angelegt          (Dokument existierte nicht)
```
Wie bei §1c wird hier **noch nicht** geschrieben — siehe §3.

## 3. Logbuch — EIN Block für den gesamten Lauf (AC5/AC9/AC10/AC11)
Kombiniere die Stufe-1-Liste (§1c) und die Stufe-2-Liste (§2d) zu **einer** Zeilenmenge (Stufe-1-Zeilen zuerst, danach Stufe-2-Zeilen — feste, nachvollziehbare Reihenfolge) und rufe **einmal** auf:
```
scripts/spec-audit-append.sh \
  "<Stufe-1-Zeile-1>" … \
  "<Stufe-2-Zeile-1>" …
```
Ist die kombinierte Liste leer (weder Stufe 1 noch Stufe 2 hatten etwas zu protokollieren), wird `spec-audit-append.sh` **nicht** aufgerufen — kein leerer Block (AC11).

## 4. Freigabe — EIN Diff für den gesamten Lauf (AC1/AC5/AC9)
Nur falls §1b und/oder §2c mindestens eine Datei tatsächlich geändert/angelegt haben (sonst: nichts zu landen, Lauf endet hier mit „keine Drift gefunden").

- **`merge_policy: pr`:** neuer Branch `reconcile/<YYYY-MM-DD>` ab `default_branch`; **ein** Commit mit **allen** berührten Dateien aus Stufe 1 + Stufe 2 + dem `docs/spec-audit.md`-Block (`git add docs/specs/<konvertierte-pfade> <stufe-2-pfade> docs/spec-audit.md`); Push; `gh pr create` gegen `default_branch` mit Body: Liste der Stufe-1-Konvertierungen (alt-Version → neu-Version) + ggf. Nicht-konvertiert-Liste (§1b.5) + Liste der Stufe-2-Nachzieh-Änderungen (Fund → Doku-Stelle). **Kein Self-Merge** — Freigabe ist Mensch-Gate (analog `train`/`retro`-PR-Mechanik).
- **`merge_policy: direct`:** **kein** Commit — alle Änderungen (Stufe 1 + Stufe 2) bleiben unstaged im Working-Tree als reiner Diff zur Durchsicht (`git diff`). Output nennt explizit, dass nichts committet wurde und der User den Diff selbst prüft/committet.

## Output
```
Stufe 1: <N> Spec(s) konvertiert, <M> nicht-konvertiert (E1)
  Konvertiert: <pfad> (<alt> -> <neu>), …
  Nicht-konvertiert: <pfad> (<grund>), …
Stufe 2: <übersprungen — Board nicht leer | übersprungen — kein Board-Skelett | <K> Dokument(e) nachgezogen | keine Inhalts-Drift gefunden>
  Nachgezogen: <pfad> (<Fund-Kurzbeschreibung>), …
Diff: <PR-Link | "Working-Tree-Diff, nicht committet (merge_policy: direct)" | "keine Drift gefunden — nichts zu tun">
```

## Grenzen (HART)
- Editiert **ausschließlich** Doku: `docs/specs/*.md` (Stufe 1 + Stufe 2), `concept.md`/`CONCEPT.md`, `architecture.md`/`docs/architecture/*.md` (Stufe 2) + `docs/spec-audit.md` (Logbuch) — **kein** App-Code, **keine** Board-Status-Änderung.
- **Kein** eigener `reconcile`-Agent. **Kein** Task-Dispatch für das Schreiben der Konvertierung (Stufe 1) oder des Nachzugs (Stufe 2) — die Skill-Session restrukturiert/schreibt selbst (AC1, Vertrag §7). Der **einzige** Task-Dispatch ist der `reviewer`-Audit-Dispatch in §2b (reines **Erkennen**, kein Schreiben).
- **Kein** Self-Merge des eigenen PRs (`merge_policy: pr`) — Mensch-Gate Pflicht.
- Stufe 2 läuft **ausschließlich** bei `empty` aus §2a (AC6, hart) — bei `not-empty` oder `no-board` **kein** Audit-Dispatch, **kein** Doku-Nachzug.
- **Kein** Einzel-Nachfragen pro Drift-Fund (AC8) — der Mensch-Gate ist ausschließlich der finale Diff-Blick in §4.
