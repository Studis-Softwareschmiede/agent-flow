---
id: obsidian-sync
title: Obsidian-Sync — wiederholter Abgleich Notiz ↔ Konzept/Spec (kein Blind-Overwrite)
status: draft
version: 1
spec_format: use-case-2.0
---

# Spec: Obsidian-Sync  (`obsidian-sync`)

> **Schicht 3 von 3.** Testbares **Verhalten + Verträge**, sprach-/paradigma-unabhängig (Intent, keine Idiome/Klassen).
> **Source of Truth** für `coder` (baut daraus), `tester` (testet die Acceptance-Kriterien + Coverage-Gate), `reviewer` (prüft den Diff dagegen — hartes Drift-Gate).
> **Subsystem-Vertrag (verbindlich):** `docs/architecture/obsidian-ingest-subsystem.md` §5. Diese Spec setzt den **Re-Sync-Modus** um — ein **eigener Modus** desselben `from-notes`-Skills, der Notiz-Reader + Fragenkatalog-Gate mit `[[obsidian-ingest]]` teilt.
> **Abgrenzung zu Reconcile:** bewusst **kein** Reconcile-„Stufe 0" — invertierte Autorität (siehe *Zweck* + Vergleichstabelle in *Verträge*).

## Zweck
`/agent-flow:from-notes --sync` ist der **wiederholbare Abgleich** zwischen dem **aktuellen Notiz-Stand** im
verknüpften Obsidian-Ordner (`obsidian_source`) und dem **aktuellen Konzept/Spec-Stand** (`docs/concept.md` +
`docs/specs/*`). Er **erkennt und meldet Widersprüche** und legt sie dem User **zur Entscheidung** vor —
**überschreibt aber nie automatisch** das Konzept oder die Specs. Damit ist er die notiz-getriebene Aufhol-Fähigkeit,
die die **Autorität von Reconcile invertiert**: bei `/agent-flow:reconcile` gewinnt der Code automatisch gegen die
Doku (Code ist Wahrheit); hier sind die Notizen **unfertige Gedanken** und dürfen die Doku **nicht** automatisch
überschreiben — jede Divergenz ist ein bewusster Mensch-Entscheid.

## Main Success Scenario
1. Der Mensch löst `/agent-flow:from-notes --sync` aus (dev-gui-Button oder Terminal); der Ordner kommt aus
   `obsidian_source` (`[[obsidian-ingest]]` AC1/AC2).
2. Der **Notiz-Korpus-Reader** (`[[obsidian-ingest]]` AC4–AC6) liefert den aktuellen Notiz-Korpus; Vergleichsseite
   ist der aktuelle `docs/concept.md` + `docs/specs/*`-Stand.
3. Der Sync-Modus **erkennt Widersprüche/Divergenzen** zwischen beiden Seiten und stellt sie als priorisierten
   Bericht zusammen (je Fund: Notiz-Fundstelle + betroffenes Doku-Dokument/Sektion + Art der Divergenz).
4. Die Divergenzen werden als **genau EIN Fragenkatalog** vorgelegt (gleiches Rückgabeformat wie
   `[[obsidian-ingest]]` AC9); der User entscheidet **je Divergenz** die Richtung.
5. **Nur die gewählten** Änderungen werden anschließend in die Doku geschrieben — nichts automatisch.
6. Findet der Lauf keine Divergenz, endet er ohne Katalog und ohne Änderung mit „deckungsgleich"-Meldung.

## Alternative Flows
### A1: Keine Divergenz gefunden
- Der Lauf endet ohne Fragenkatalog und **ohne** Doku-Änderung mit klarer „deckungsgleich"-Meldung (AC5).

### A2: User behält bei einer Divergenz die Doku
- Für diese Divergenz wird **nichts** geschrieben; die bestehende `concept.md`/Spec bleibt unverändert (AC4).

### E1: `obsidian_source` nicht gesetzt / Ordner unlesbar
- Klarer Abbruch mit Meldung (kein Ordner am Projekt vermerkt bzw. kein `.md` lesbar) — Verhalten identisch zum
  Reader-Abbruch in `[[obsidian-ingest]]` AC2/AC5 (AC6).

## Acceptance-Kriterien
<!-- Nummeriert, testbar. Board-Items referenzieren diese Nummern. AC-IDs sind stabil (nicht umnummerieren). -->

- **AC1** — **Eigener Modus, geteilte Basis:** `/agent-flow:from-notes --sync` (Arbeitstitel) ist ein **eigener
  Modus** desselben `from-notes`-Skills. Er nutzt den persistierten `obsidian_source` + den Notiz-Korpus-Reader
  (`[[obsidian-ingest]]` AC1/AC2/AC4–AC6) und den **aktuellen** `docs/concept.md` + `docs/specs/*`-Stand als die
  beiden Vergleichsseiten. Es wird **kein** Reconcile-„Stufe 0" angelegt und der Reconcile-Vertrag
  (`docs/architecture/reconcile-subsystem.md`) bleibt **unangetastet**.
- **AC2** — **Erkennen + Melden:** Der Sync-Modus erkennt Widersprüche/Divergenzen zwischen aktuellem Notiz-Stand
  und aktuellem Konzept/Spec-Stand und legt sie als **priorisierten Bericht** vor — je Fund: **Notiz-Fundstelle**
  (relativer Notiz-Pfad + Kontext), **betroffenes Doku-Dokument/Sektion** und **Art der Divergenz** (z.B. Notiz
  widerspricht Konzept-Aussage / Notiz enthält Neues, das die Spec nicht abbildet / Doku enthält, was die Notiz
  nicht mehr trägt). Reiner Bericht — **kein** Gate, **keine** automatischen Board-Items.
- **AC3** — **Kein Blind-Overwrite (invertierte Reconcile-Autorität):** Der Sync-Modus überschreibt Konzept oder
  Specs **nie automatisch**. Die Notizen sind unfertige Gedanken; jede erkannte Divergenz wird dem User **zur
  Entscheidung** vorgelegt, bevor **irgendetwas** an der Doku geändert wird. (Genau der Unterschied zu
  `/agent-flow:reconcile`, wo der Code automatisch gewinnt.)
- **AC4** — **Ein Katalog, gerichteter Entscheid, selektives Schreiben:** Die Divergenzen werden als **genau EINEN
  Fragenkatalog** vorgelegt (gleiches maschinenlesbares Rückgabeformat wie `[[obsidian-ingest]]` AC9, `stage:sync`);
  der User entscheidet **je Divergenz** die Richtung — **Notiz in die Doku übernehmen** · **Doku behalten** ·
  **manuell/offen lassen**. Anschließend werden **nur die als „übernehmen" gewählten** Änderungen in `docs/`
  geschrieben; „behalten"/„manuell" ändern nichts (*deckt A2*).
- **AC5** — **Kein Rauschen bei Deckungsgleichheit:** Findet der Lauf **keine** Divergenz, endet er **ohne**
  Fragenkatalog und **ohne** jede Doku-Änderung mit einer klaren „deckungsgleich"-Meldung. *(deckt A1)*
- **AC6** — **Rein lesend gegenüber den Notizen + kein Folge-Automatismus:** Der Sync-Modus verändert den
  Obsidian-Ordner **nie** (→ `[[obsidian-ingest]]` AC6) und schreibt Doku-Änderungen **ausschließlich** nach
  explizitem User-Entscheid (AC4). Er startet **kein** `/flow` und legt **keine** Stories automatisch an — neue
  Stories entstehen bewusst nur über den Ingest-Stufe-c- bzw. den regulären `requirement`-Fluss. Fehlt
  `obsidian_source` oder ist der Ordner unlesbar → klarer Abbruch wie bei `[[obsidian-ingest]]` (*deckt E1*).

> **Traceability:** Jeder Test trägt das kanonische Trace-Tag `@trace obsidian-sync#AC<n>`
> gemäss `knowledge/<lang>.md` → `## Spec-Tagging`. Der `tester` rechnet das Coverage-Gate
> (jede genannte AC ≥ 1 deckender Test). Details: `docs/architecture/traceability-subsystem.md`.

## Verträge
- **Skill-Befehl:** `/agent-flow:from-notes --sync` (Arbeitstitel). Ordner aus `obsidian_source`. Dünner Auslöser
  (dev-gui POST `/api/command`), Logik in agent-flow.
- **Vergleichsseiten:** links = Notiz-Korpus (Reader-Output, `[[obsidian-ingest]]` AC4), rechts = aktueller
  `docs/concept.md` + `docs/specs/*`-Stand.
- **Fund-/Bericht-Format:** priorisierte Liste, je Fund `{ notiz_fundstelle, doku_ziel (Dokument+Sektion),
  divergenz_art, richtungsvorschlag }`. Reiner Bericht, kein Gate (AC2).
- **Fragenkatalog:** dasselbe Rückgabeformat wie `[[obsidian-ingest]]` AC9 mit `stage: sync`; je Divergenz eine
  Frage mit den Optionen **übernehmen / behalten / manuell** (AC4).
- **Autoritäts-Abgrenzung zu Reconcile (bindend):**

  | | `/agent-flow:reconcile` | `/agent-flow:from-notes --sync` (dies) |
  |---|---|---|
  | Achse | Code ↔ Doku | Notiz ↔ Konzept/Spec |
  | Wahrheit | **Code** (maßgebend) | **weder noch** (Notiz = unfertig) |
  | Bei Divergenz | Doku **automatisch** an Code, kein per-Drift-Prompt | **nichts automatisch** — je Divergenz User-Entscheid |
  | Ergebnis | genau **ein PR** | **ein Fragenkatalog** + selektives Schreiben |

- **Schreib-Umfang:** nur `docs/concept.md` / `docs/specs/*` und **nur** die vom User als „übernehmen" gewählten
  Divergenzen (AC4). **Nie** in den Notiz-Ordner (AC6).

## Edge-Cases & Fehlerverhalten
- **E1:** `obsidian_source` fehlt / Ordner unlesbar → klarer Abbruch (AC6, wie `[[obsidian-ingest]]` AC2/AC5).
- Keine Divergenz → kein Katalog, keine Änderung, „deckungsgleich"-Meldung (AC5).
- User wählt „behalten"/„manuell" → betroffene Doku bleibt unverändert (AC4).
- Widersprüchlicher Notiz-Stand gegen mehrere Doku-Stellen → mehrere Funde in **einem** Katalog (AC4), nie
  Einzel-Prompt je Fund verstreut.

## NFRs
- **Vorsicht/Nicht-Regression der Doku:** kein Blind-Overwrite (AC3) — die durable Source of Truth wird nie
  stillschweigend von unfertigen Notizen überschrieben.
- **Nachvollziehbarkeit:** jede geschriebene Änderung ist auf eine Notiz-Fundstelle + einen expliziten
  User-Entscheid zurückführbar (AC2/AC4).
- **Rauscharmut:** kein Katalog/keine Änderung bei Deckungsgleichheit (AC5).

## Nicht-Ziele
- **Kein** Reconcile-„Stufe 0" — eigener Modus, Reconcile bleibt unangetastet (AC1).
- **Kein** automatisches Überschreiben von Konzept/Spec (AC3).
- **Kein** Rückschreiben in den Notiz-Ordner (AC6).
- **Kein** automatisches Story-Anlegen / kein `/flow`-Start (AC6) — neue Stories nur über Ingest-Stufe c /
  `requirement`.
- **Kein** dev-gui-Button in diesem Repo — Cross-Repo (`[[obsidian-ingest]]`).

## Abhängigkeiten
- `[[obsidian-ingest]]` — **Fundament** (Reader AC4–AC6, `obsidian_source` AC1/AC2, Fragenkatalog-Format AC9);
  muss zuerst existieren.
- `skills/from-notes/SKILL.md` (der `--sync`-Modus, neu) · `.claude/profile.md` (`obsidian_source`).
- **Abgrenzung:** `docs/architecture/reconcile-subsystem.md` (Reconcile — Code↔Doku, automatisch) ist bewusst
  **getrennt**; dieser Modus fasst ihn nicht an.
- Vertrag: `docs/architecture/obsidian-ingest-subsystem.md` §5. Kontext: CONCEPT §4d.
