---
id: obsidian-ingest
title: Obsidian-Ingest — Notiz-Ordner als Requirement-Quelle (Notiz → Konzept → Spec → Stories)
status: draft
version: 1
spec_format: use-case-2.0
---

# Spec: Obsidian-Ingest  (`obsidian-ingest`)

> **Schicht 3 von 3.** Testbares **Verhalten + Verträge**, sprach-/paradigma-unabhängig (Intent, keine Idiome/Klassen).
> **Source of Truth** für `coder` (baut daraus), `tester` (testet die Acceptance-Kriterien + Coverage-Gate), `reviewer` (prüft den Diff dagegen — hartes Drift-Gate).
> **Subsystem-Vertrag (verbindlich):** `docs/architecture/obsidian-ingest-subsystem.md`. Diese Spec setzt den **agent-flow-Teil** um (Pipeline + Reader + Fragenkatalog-Gate + Profilfeld). Der **dünne dev-gui-Button** (Anzeige/Bedienung) lebt im separaten `dev-gui`-Repo und ist hier **nur Cross-Repo-Abhängigkeit**, kein Board-Item — nur die **Schnittstelle** (Aufruf + Rückgabeformat) ist hier definiert, damit dev-gui andockt.
> **Schwester-Spec:** `[[obsidian-sync]]` (der Re-Sync-Modus) teilt Reader + Fragenkatalog-Gate dieser Spec.

## Zweck
`/agent-flow:from-notes <ordnerpfad>` speist einen **Obsidian-Projektordner** (mehrere freie `.md`-Notizen aus der
Ideen-/Konzeptphase) als **zusätzliche** Requirement-Eingabe in den bestehenden Fabrik-Pfad **Konzept →
Spezifikation → Story** (CONCEPT §4a/§4d) — neben der bisherigen getippten vagen Anforderung. Die Verarbeitung
läuft in **drei Stufen** (Notiz→`concept.md`, Konzept→`specs/`, Spec→Board), jede läuft bei klaren Notizen
**automatisch** durch und hält bei Unklarheiten mit **genau einem gesammelten Fragenkatalog** an. Der verknüpfte
Ordner bleibt am Projekt vermerkt (`obsidian_source`), damit später erneut aus den Notizen gearbeitet werden kann.

## Main Success Scenario
1. Der Mensch löst `/agent-flow:from-notes <ordnerpfad>` aus (dev-gui-Button oder direkt im Projekt-Terminal).
2. Der Ordnerpfad wird als `obsidian_source` im Projekt-Profil vermerkt (oder daraus gelesen, wenn kein Argument).
3. Der **Notiz-Korpus-Reader** liest alle `.md`-Notizen des Ordners in einen konsolidierten, deterministisch
   geordneten Korpus (mit Herkunfts-Markern je Notiz).
4. **Stufe a** übersetzt den Korpus nach `docs/concept.md`; offene Punkte werden als **ein** Fragenkatalog
   vorgelegt (niedrige Nachfrage-Schwelle), nach Beantwortung wird die Stufe committet.
5. **Stufe b** leitet aus dem Konzept die `docs/specs/<feature>.md` ab (+ `architekt`/`dba` wo nötig); Katalog b,
   dann Commit.
6. **Stufe c** zerlegt die Spec(s) über den bestehenden `requirement`-Agenten in Board-Items/Stories (To Do), die
   auf **Spec + AC-Nummern** zeigen; Katalog c, dann Commit.
7. Der Ordner bleibt unangetastet; das Projekt kann jederzeit erneut aus den Notizen arbeiten (Re-Ingest oder
   `[[obsidian-sync]]`).

## Alternative Flows
### A1: Notizen einer Stufe sind klar und widerspruchsfrei
- Die Stufe erzeugt **keinen** Fragenkatalog und läuft automatisch durch bis zum Stufen-Commit (AC8).

### A2: Kein Ordner-Argument, aber `obsidian_source` im Profil gesetzt
- Der Pfad wird aus `obsidian_source` gelesen (AC2). Precedence: Argument > Profil.

### E1: Weder Argument noch `obsidian_source` gesetzt
- Klarer Abbruch mit Meldung „kein Notiz-Ordner angegeben und keiner am Projekt vermerkt" — **kein** Leerlauf,
  **keine** leere Pipeline (AC2).

### E2: Ordner existiert nicht oder enthält keine `.md`
- Klarer Abbruch mit Meldung; **keine** leere Konzept-/Spec-Datei wird angelegt (AC5).

## Acceptance-Kriterien
<!-- Nummeriert, testbar. Board-Items referenzieren diese Nummern. AC-IDs sind stabil (nicht umnummerieren). -->

### Wiederholbare Quelle — `obsidian_source` im Profil
- **AC1** — Der verknüpfte Notiz-Ordner wird als **absoluter Pfad** im Projekt-Profil (`.claude/profile.md`
  Frontmatter, Feld `obsidian_source`) persistiert — **analog zur Board-Referenz**. Einmal verknüpft, bleibt er
  vermerkt und ist für Folgeläufe (Re-Ingest **und** `[[obsidian-sync]]`) verfügbar, ohne den Pfad erneut zu
  übergeben. Das Feld wird auch in die Profil-Vorlage (`templates/**/profile*.md` bzw. das kanonische
  Profil-Skelett) additiv aufgenommen, dokumentiert als optional.
- **AC2** — **Precedence + Abbruch:** Wird die Pipeline mit einem Ordner-Argument gestartet, gilt dieses und
  `obsidian_source` wird darauf gesetzt/aktualisiert (Argument > Profil). Fehlt das Argument, wird
  `obsidian_source` gelesen (*deckt A2*). Fehlt **beides**, bricht die Pipeline mit klarer Meldung ab (*deckt E1*).
- **AC3** — **Additiv/rückwärtskompatibel:** `obsidian_source` ist **optional** — bestehende Profile ohne das Feld
  bleiben gültig, und die bestehende vage-Anforderung-Eingabe (`/agent-flow:requirement`) bleibt **unverändert**
  nutzbar. Die Notiz-Pipeline ist ein **zusätzlicher, dritter** Requirement-Weg, kein Ersatz.

### Notiz-Korpus-Reader
- **AC4** — Der Reader liest **alle** `*.md`-Dateien des verknüpften Ordners (rekursiv, inkl. Unterordner) und
  fügt sie zu **einem** konsolidierten Korpus zusammen, in **deterministischer** Reihenfolge (stabil, z.B.
  Pfad-alphabetisch) und je Notiz mit einem **Herkunfts-Marker** (relativer Dateipfad), damit Fragenkatalog-
  Einträge und Sync-Funde auf die **Quellnotiz** zeigen können.
- **AC5** — **Ignorieren + Abbruch statt Leerlauf:** Nicht-`.md`-Dateien und Obsidian-Interna (u.a. das
  `.obsidian/`-Verzeichnis, Anhänge) werden übersprungen. Ein nicht existierender Pfad **oder** ein Ordner ohne
  jede `.md`-Datei führt zu **klarem Abbruch mit Meldung** — **niemals** zu einer leeren Pipeline oder einer leer
  angelegten `concept.md`/Spec (*deckt E2*).
- **AC6** — **Rein lesend:** Der Reader (und die gesamte Pipeline) verändert den Obsidian-Ordner **nie** und
  committet ihn nie — die Notizen sind eine **externe** Quelle, kein Repo-Artefakt. Geschrieben wird
  ausschließlich in `docs/`, `.claude/profile.md` und das Board des Ziel-Repos.

### Fragenkatalog-Gate + dev-gui-Schnittstelle
- **AC7** — Beim Übergang **jeder** Stufe sammelt die Pipeline offene Unklarheiten/Widersprüche und legt sie als
  **genau EINEN Fragenkatalog** pro Stufe vor (**nicht** einzeln pro Unklarheit sofort erfragt). Der User
  beantwortet den Katalog **am Stück**; **erst danach** wird das Stufen-Ergebnis committet (→ AC12).
- **AC8** — **Automatischer Durchlauf bei Klarheit:** Sind die Notizen für eine Stufe klar und widerspruchsfrei
  (keine offenen Fragen), läuft die Stufe **ohne** Fragenkatalog durch (kein leerer Katalog, keine unnötige
  Rückfrage). *(deckt A1)*
- **AC9** — **Maschinenlesbares Rückgabeformat (dev-gui-Schnittstelle):** Der Fragenkatalog wird in einem
  **definierten, maschinenlesbaren** Format ausgegeben, sodass dev-gui ihn rendern und die Antworten zurückgeben
  kann — je Frage mindestens die Felder `stage` (`a|b|c|sync`), `id` (stabile Frage-ID), `frage` (Text), `quelle`
  (Notiz-/Doku-Fundstelle) und **optional** `optionen[]` (vorgeschlagene Antwortoptionen). Im Terminal-Pfad wird
  **derselbe** Katalog interaktiv gestellt (`AskUserQuestion`). Das Format ist so beschrieben, dass dev-gui
  **ohne** Änderung an agent-flow andockt (siehe *Verträge*).
- **AC10** — **Erst-Übersetzung besonders präzise (fixture-geprüft):** In **Stufe a** (Notiz→Konzept) ist die
  Schwelle zum Nachfragen **bewusst niedrig** — jede relevante Mehrdeutigkeit im Ideen-Text wird eher zur Frage als
  zur stillen Annahme, damit sich Fehlinterpretationen nicht in Spec und Stories fortpflanzen. **Mechanisch
  prüfbar:** ein Test-Fixture-Notizordner mit mindestens einer bewusst mehrdeutigen Aussage (z.B. zwei sich
  widersprechende Aussagen zur Zielgruppe) MUSS in Stufe a mindestens einen Fragenkatalog-Eintrag erzeugen — ein
  stiller Default/eine stille Annahme für diese Mehrdeutigkeit gilt als AC10-Verletzung.

### Drei-Stufen-Pipeline
- **AC11** — Es existiert ein Fabrik-Befehl (Arbeitstitel `/agent-flow:from-notes <ordnerpfad>`), der die drei
  Stufen **in Reihe** orchestriert: **(a)** Korpus → `docs/concept.md`; **(b)** `docs/concept.md` →
  `docs/specs/<feature>.md` (je Capability eine Spec aus `templates/_docs/specs/_template.md`, mit
  `spec_format`-Stempel und nummerierten AC; tiefes Architektur-Detail via `architekt` →
  `docs/architecture.md`/`docs/architecture/<subsystem>.md`, Datenmodell via `dba`); **(c)** Spec(s) → Board-Items/
  Stories **über den bestehenden `requirement`-Agenten** (kein zweiter Zerlege-Pfad), Status **To Do**, jedes Item
  zeigt auf **Spec + AC-Nummern** (kein eingebetteter AC-Text).
- **AC12** — **Commit pro Stufe, harte Reihenfolge:** Jede Stufe wird **einzeln committet**, nachdem ihr
  Fragenkatalog beantwortet (oder leer) ist — **nicht** am Ende in einem Rutsch. Stufe b startet **erst** nach
  committetem Stufe-a-Ergebnis, Stufe c **erst** nach committetem Stufe-b-Ergebnis. So sind Zwischenstände durable
  und der Lauf jederzeit fortsetzbar (Board/`docs/` als persistenter Zustand).
- **AC13** — **Bestehende Verträge werden wiederverwendet, nicht dupliziert:** Stufe b folgt dem Spec-Vertrag
  (Vorlage, Stempel, Traceability); Stufe c erzeugt Items exakt nach dem `requirement`-Item-Vertrag (Spec-ID +
  AC-Nummern statt eingebetteter Kriterien) inkl. der A-priori-Schätzung (`size_est`/`dispo_est`), da `requirement`
  das ohnehin leistet.
- **AC14** — **Authoring-only:** Die Pipeline schreibt **ausschließlich** durable Docs (`docs/`), das Profilfeld
  und Board-Items (To Do) — **kein** App-Code, **kein** `/flow`-Start, **kein** Merge/Deploy und **kein** Schreiben
  in den Notiz-Ordner (→ AC6). Item-Status bleibt allein `/flow`-Hoheit.

> **Traceability:** Jeder Test trägt das kanonische Trace-Tag `@trace obsidian-ingest#AC<n>`
> gemäss `knowledge/<lang>.md` → `## Spec-Tagging`. Der `tester` rechnet das Coverage-Gate
> (jede genannte AC ≥ 1 deckender Test). Details: `docs/architecture/traceability-subsystem.md`.

## Verträge
- **Skill-Befehl:** `/agent-flow:from-notes <ordnerpfad>` (Ingest). Auslöser dünn (dev-gui POST `/api/command`),
  gesamte Logik in agent-flow. Der Re-Sync-Modus (`--sync`) ist in `[[obsidian-sync]]` spezifiziert.
- **Profilfeld:** `.claude/profile.md`-Frontmatter `obsidian_source: <absoluter-ordnerpfad>` (optional/additiv).
  Precedence Argument > Profil; fehlt beides → Abbruch (AC2).
- **Notiz-Korpus (Reader-Output):** ein konsolidierter Text/Struktur aller `*.md` des Ordners, deterministisch
  geordnet, je Segment mit Herkunfts-Marker (relativer Dateipfad). Rein lesend (AC6).
- **Fragenkatalog-Rückgabeformat (dev-gui-Schnittstelle, AC9):** eine **Liste von Frage-Objekten**; je Objekt die
  Pflichtfelder `stage` ∈ `{a,b,c,sync}`, `id` (stabil, katalog-eindeutig), `frage` (Text), `quelle`
  (Notiz-/Doku-Fundstelle, z.B. relativer Notiz-Pfad + Kontext) und **optional** `optionen` (Array
  vorgeschlagener Antworten). dev-gui rendert die Liste, sammelt Antworten und reicht sie zurück (Zuordnung über
  `id`); die Pipeline setzt die Stufe mit den Antworten fort und committet. Terminal-Pfad: gleicher Katalog via
  `AskUserQuestion`. (Das konkrete Serialisierungs-Detail — z.B. JSON-Block — legt die Umsetzung fest; die
  **Feldmenge** oben ist der bindende Vertrag.)
- **Stufen-Outputs:** (a) `docs/concept.md`; (b) `docs/specs/<feature>.md` (+ ggf. `docs/architecture*.md`);
  (c) Board-Items/Stories (To Do) über `requirement`. **Ein Commit pro Stufe** (AC12).
- **Wiederverwendete Agenten:** `requirement` (Stufe c, Zerlegung + Schätzung), `architekt`/`dba` (Stufe b, tiefes
  Detail). Kein neuer Zerlege- oder Schätz-Pfad.

## Edge-Cases & Fehlerverhalten
- **E1:** Weder Argument noch `obsidian_source` → klarer Abbruch, kein Leerlauf (AC2).
- **E2:** Ordner fehlt oder ohne `.md` → klarer Abbruch, **keine** leer angelegte `concept.md`/Spec (AC5).
- Widersprüchliche/mehrdeutige Notizen → gesammelter Fragenkatalog pro Stufe (AC7), Stufe a mit niedrigster
  Schwelle (AC10); nie stille Annahme bei relevanter Mehrdeutigkeit.
- Abbruch/Session-Ende **zwischen** Stufen → committete Stufen bleiben durable (AC12); der Lauf ist fortsetzbar.
- Obsidian-Interna (`.obsidian/`, Anhänge) → ignoriert (AC5); der Ordner wird nie beschrieben (AC6).

## NFRs
- **Präzision vor Tempo (Erst-Übersetzung):** Stufe a fragt im Zweifel lieber nach (AC10) — Fehlerfortpflanzung in
  Spec/Stories ist teurer als eine Rückfrage.
- **Nachvollziehbarkeit:** Fragenkatalog-Einträge und die abgeleiteten Docs tragen Herkunfts-Bezug zur Quellnotiz
  (AC4), sodass Entscheidungen bis zur Notiz rückverfolgbar sind.
- **Robustheit:** kein stiller Leerlauf (AC2/AC5); Zwischenstände durable (AC12).
- **Sicherheit/Vorsicht:** rein lesende externe Quelle (AC6); kein `/flow`-Start, kein Merge/Deploy (AC14).

## Nicht-Ziele
- **Kein** Ersatz der vagen Anforderung — additiver dritter Weg (AC3).
- **Kein** zweiter Zerlege-Pfad — Stufe c nutzt `requirement` (AC11/AC13).
- **Kein** Schreiben in den Notiz-Ordner (AC6); **kein** Rückschreiben nach Obsidian.
- **Kein** dev-gui-Button in diesem Repo — Cross-Repo-Abhängigkeit unten.
- **Kein** `/flow`-Start / Merge / Deploy in der Pipeline (AC14).
- **Kein** Blind-Overwrite bestehender Docs im Re-Sync — das regelt `[[obsidian-sync]]` (eigener Modus).

## Abhängigkeiten
- `[[obsidian-sync]]` — Schwester-Modus (Re-Sync), teilt Reader (AC4–AC6) + Fragenkatalog-Gate (AC7/AC9).
- `agents/requirement.md` (Stufe c: Zerlegung + Schätzung) · `agents/architekt.md` / `agents/dba.md` (Stufe b) ·
  `templates/_docs/specs/_template.md` + `[[spec-format-field]]` (Spec-Vorlage + Stempel) · `.claude/profile.md`
  (neues Feld `obsidian_source`) · `skills/from-notes/SKILL.md` (neu, Arbeitstitel).
- **Cross-Repo-Abhängigkeit (SR — Cross-Repo-Markierung):** Der **Auslöser-Button** + die **Anzeige/Beantwortung
  des Fragenkatalogs** (dritter Anlage-Weg „aus Obsidian-Notizen", Obsidian-Pfad in den Settings) leben im
  **`dev-gui`-Repo** und werden **dort** in eigenen Board-Items umgesetzt — **NICHT** in agent-flow. agent-flow
  stellt nur den Befehl `/agent-flow:from-notes` **und** das Fragenkatalog-Rückgabeformat (AC9) bereit.
- Vertrag: `docs/architecture/obsidian-ingest-subsystem.md`. Kontext: CONCEPT §4a (Pipeline) / §4d (durable Docs);
  Abgrenzung zu `docs/architecture/reconcile-subsystem.md` (Reconcile ≠ Re-Sync, siehe `[[obsidian-sync]]`).
