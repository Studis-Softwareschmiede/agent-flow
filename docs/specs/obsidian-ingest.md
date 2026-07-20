---
id: obsidian-ingest
title: Obsidian-Ingest — Notiz-Ordner als Requirement-Quelle (Notiz → Konzept → Spec → Stories)
status: active
area: anforderung-intake
version: 3
spec_format: use-case-2.0
---

# Spec: Obsidian-Ingest  (`obsidian-ingest`)

> **Schicht 3 von 3.** Testbares **Verhalten + Verträge**, sprach-/paradigma-unabhängig (Intent, keine Idiome/Klassen).
> **Source of Truth** für `coder` (baut daraus), `tester` (testet die Acceptance-Kriterien + Coverage-Gate), `reviewer` (prüft den Diff dagegen — hartes Drift-Gate).
> **Subsystem-Vertrag (verbindlich):** `docs/architecture/obsidian-ingest-subsystem.md`. Diese Spec setzt den **agent-flow-Teil** um (Pipeline + Reader + Fragenkatalog-Gate + Profilfeld). Der **dünne dev-gui-Button** (Anzeige/Bedienung) lebt im separaten `dev-gui`-Repo und ist hier **nur Cross-Repo-Abhängigkeit**, kein Board-Item — nur die **Schnittstelle** (Aufruf + Rückgabeformat) ist hier definiert, damit dev-gui andockt.
> **Schwester-Spec:** `[[obsidian-sync]]` (der Re-Sync-Modus) teilt Reader + Fragenkatalog-Gate dieser Spec.
> **Konzept-Herkunft:** `(← C-002)` — CONCEPT.md §11 „Entschieden (Idea-Roundtrip, 07.07.2026)", entstanden aus Ideennotiz `IDEA-002` (`Agent Flow – Konzept Idea-Intake.md`).
> **Erweitert 07.07.2026 (Idea-Roundtrip, Subsystem-Vertrag §4b/§5a):** ID-Kette + Frontmatter-Stempel (AC15–AC18) und `--audit`-Modus (AC19–AC22); das frühere Komplett-Verbot „kein Schreiben in den Vault" ist durch das **Zonen-Modell** ersetzt (AC6/AC17). Der Rückkanal Repo→Vault ist NICHT hier, sondern `[[reconcile]]` Stufe 3.
> **Erweitert 20.07.2026 (Headless-Ausgabevertrag, AC23–AC25):** Ein explizites Aufruf-Signal `--gui` schaltet den **Headless-JSON-Modus** — statt interaktivem `AskUserQuestion` endet jede Runde mit **genau einem** JSON-Objekt (`{status:"needs-answers",catalog:[…]}` bzw. `{status:"done"}`), damit der dev-gui-`ObsidianIngestRunner` das Runden-Ende maschinenlesbar erkennt. Behebt einen reproduzierten Defekt (Pilot-Lauf research-app, Session a69c8b13, 2026-07-19): der headless Lauf gab einen korrekt aufgebauten Stufe-a-Fragenkatalog als **Fliesstext** aus, worauf der Runner „Lauf fehlgeschlagen (kein JSON-Ausgang)" klassifizierte.

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
   vorgelegt (niedrige Nachfrage-Schwelle), nach Beantwortung wird die Stufe committet. Dabei werden die IDs
   vergeben (`IDEA-NNN` je Quellnotiz, `C-NNN (← IDEA-NNN)` je Konzeptabschnitt) und die Frontmatter-Sync-Felder
   der übernommenen Notizen gestempelt (AC15–AC17).
5. **Stufe b** leitet aus dem Konzept die `docs/specs/<feature>.md` ab (+ `architekt`/`dba` wo nötig); Katalog b,
   dann Commit.
6. **Stufe c** zerlegt die Spec(s) über den bestehenden `requirement`-Agenten in Board-Items/Stories (To Do), die
   auf **Spec + AC-Nummern** zeigen; Katalog c, dann Commit.
7. Ausser den Frontmatter-Stempeln (AC17) bleibt der Ordner unangetastet; das Projekt kann jederzeit erneut aus
   den Notizen arbeiten (Re-Ingest, `[[obsidian-sync]]` oder `--audit`).

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
- **AC6** — **Zonen-Modell statt rein lesend (geändert 07.07.2026):** Der **Reader** liest nur; die **Pipeline**
  darf im Obsidian-Ordner ausschließlich die in Subsystem-Vertrag §4b definierten **Frontmatter-Sync-Felder**
  stempeln (AC17) — sonst **nichts**: kein Inhalt der Notizen wird verändert oder gelöscht, keine Datei wird
  angelegt oder entfernt, der Ordner wird nie committet (externe Quelle, kein Repo-Artefakt). Der generierte
  Abschnitt `## Stand aus Konzept (generiert)` wird **nicht** vom Ingest geschrieben, sondern ausschließlich vom
  Rückkanal (`[[reconcile]]` Stufe 3). Repo-seitig wird ausschließlich in `docs/`, `.claude/profile.md` und das
  Board des Ziel-Repos geschrieben.

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
  und Board-Items (To Do) — **kein** App-Code, **kein** `/flow`-Start, **kein** Merge/Deploy und — abgesehen vom
  Frontmatter-Stempel (AC17) — **kein** Schreiben in den Notiz-Ordner (→ AC6). Item-Status bleibt allein `/flow`-Hoheit.

### ID-Kette + Frontmatter-Stempel (Idea-Roundtrip, 07.07.2026)
- **AC15** — **Stabile Ideen-IDs:** Stufe a vergibt für jede in den Korpus eingeflossene Ideennotiz **ohne**
  `idea_id` eine neue, stabile **`IDEA-NNN`** (fortlaufend, nie wiederverwendet) und stempelt sie ins
  Notiz-Frontmatter. Notizen **mit** bestehender `idea_id` behalten sie unverändert (Re-Ingest vergibt nie neu).
- **AC16** — **Konzept-Anker:** Jeder von Stufe a erzeugte/geänderte Konzeptabschnitt in `docs/concept.md` trägt
  eine stabile ID **`C-NNN`** mit Herkunftsvermerk **`(← IDEA-NNN)`**; jede von Stufe b abgeleitete Spec
  referenziert ihre Konzept-Herkunft **`(← C-NNN)`**. Damit ist die Kette
  `IDEA → C → Spec → BR → Story → @trace` durchgängig verankert (Verlängerung der bestehenden Traceability).
- **AC17** — **Frontmatter-Stempel (einzige Vault-Schreiboperation des Ingest):** Nach Übernahme einer Idee
  stempelt Stufe a im Frontmatter der Quellnotiz genau die Sync-Felder aus Subsystem-Vertrag §4b:
  `idea_id` · `idea_status: adopted` · `last_sync` (Zeitstempel) · `sync_hash` (Hash des übernommenen
  Notiz-Stands) · Referenz(en) auf die erzeugten `C-NNN`. **Kein** anderes Frontmatter-Feld und **kein**
  Notiz-Inhalt wird angefasst (→ AC6).
- **AC18** — **Nie löschen, nie anlegen:** Die Ingest-Pipeline löscht **nie** eine Notiz oder einen
  Notiz-Inhalt und legt **nie** neue Ideennotizen an — Überholtes wird ausschließlich per
  `idea_status: superseded` markiert (Stempel nach AC17-Muster); neue Ideennotizen entstehen nur über den
  Rückkanal (`[[reconcile]]` Stufe 3, dort spezifiziert). `idea_status: parked | rejected` wird beim Re-Ingest
  respektiert: solche Notizen fließen **nicht** erneut ins Konzept (bewusste Entscheidung, keine Lücke).

### `--audit` — Integritätsprüfung über die ID-Kette (Idea-Roundtrip, 07.07.2026)
- **AC19** — **Read-only:** `/agent-flow:from-notes --audit` ändert **nichts** — weder Vault noch `docs/` noch
  Board noch Profil. Er erzeugt ausschließlich einen Report.
- **AC20** — **Abgeleitete Coverage-Map, nie handgepflegt:** Der Audit berechnet die Kette
  `IDEA-NNN → C-NNN → Spec → BR → Story → @trace` je Lauf **frisch** aus einem Frontmatter-Scan des
  Vault-Ordners (`obsidian_source`) + einem Scan von `docs/` (Konzept-Anker, Spec-Herkünfte) + der bestehenden
  Traceability-Map. Es existiert **keine** persistierte Map-Datei als Wahrheit.
- **AC21** — **Meldungs-Klassen:** Der Report unterscheidet **Waisen abwärts** (Idee ohne `C-NNN` · Konzept-Anker
  ohne Spec · Spec ohne Story/Test), **Waisen aufwärts** (Spec/Konzeptabschnitt ohne Ideen-Herkunft — typisch
  nach Code-first; Input für `[[reconcile]]` Stufe 3) und **Widersprüche** (z.B. `superseded`-Idee noch
  referenziert, Spec zeigt auf nicht existenten `C-NNN`). `idea_status: parked | rejected` gilt als **bewusste
  Entscheidung** und wird **nicht** als Lücke gemeldet.
- **AC22** — **Report-Format:** kompakter **Ampel-Report je Kette** (grün = durchgängig, gelb = Lücke,
  rot = Widerspruch) im Terminal **und** maschinenlesbar (Fund-Liste analog Fragenkatalog-Feldmuster mit
  `id`, Ketten-Bezug, Klasse, Fundstelle), damit dev-gui ihn später rendern kann — **ohne** Änderung an
  agent-flow.

### Headless-Ausgabevertrag — `--gui`-Signal + JSON-Endausgabe (dev-gui-Schnittstelle, 20.07.2026)
- **AC23** — **Explizites Headless-Signal `--gui` (keine Heuristik):** Ein zusätzliches Aufruf-Token `--gui`
  wird — genau wie `--cost`/`--sync`/`--audit` — **vor** der Ordnerpfad-Auswertung herausgeparst und gehört
  **nicht** zum Ordnerpfad. Ist es gesetzt, läuft die Pipeline im **Headless-JSON-Modus**: **kein** interaktives
  `AskUserQuestion`, stattdessen die JSON-Endausgabe nach AC24. Fehlt das Token, bleibt das **heutige interaktive
  Verhalten** (Katalog via `AskUserQuestion`) **unverändert** — rückwärtskompatibel, keine Verhaltensänderung für
  den Terminal-/Direktaufruf. Das Signal ist **explizit** (der Aufrufer sendet es); die Pipeline **rät nie** anhand
  von TTY-/Umgebungs-Heuristiken, ob sie headless läuft. `--gui` ist mit den bestehenden Modi kombinierbar
  (`--gui --sync`, `--gui --cost <mode>`); es ändert **nur den Ausgabekanal** des Fragenkatalog-Gates, **nicht** die
  Stufen-Logik, die Reihenfolge oder die Schreibzonen.
- **AC24** — **Genau EIN JSON-Objekt als Runden-Ende (Headless-Vertrag):** Im `--gui`-Modus endet **jede Runde**
  (Initial-Lauf **und** jeder Resume nach beantworteten Fragen, Stufe a/b/c **und** `sync` gleichermassen) mit
  **genau EINEM** JSON-Objekt als **letzter Ausgabe** — der finalen Assistant-Nachricht, sodass
  `claude -p … --output-format json` es unverändert in `.result` liefert. **KEIN Fliesstext nach dem JSON**
  (weder Erklärung noch Zusammenfassung):
  - **Anstehendes Fragenkatalog-Gate** (≥1 offene Frage in der gerade erreichten Stufe) →
    `{ "status": "needs-answers", "catalog": [ … ] }`, wobei `catalog` **exakt** die Liste der Frage-Objekte
    gemäss `board/fragenkatalog.schema.json` ist (Feldmenge `stage`/`id`/`frage`/`quelle`/optional `optionen`
    unverändert; `stage` = die anhaltende Stufe `a|b|c|sync`). Der Katalog wird vor der Ausgabe durch den
    bestehenden Gate-Validator (`scripts/obsidian-fragenkatalog-validate.sh`) geprüft; nur ein `valid`-Katalog wird
    als `needs-answers` ausgegeben.
  - **Kein offenes Gate mehr / vollständiger Durchlauf** → `{ "status": "done" }`.
  Ein **leerer** Katalog wird **nie** als `needs-answers` ausgegeben (Konsistenz mit AC8: leer → Auto-Durchlauf,
  die Stufe läuft weiter, das Runden-Ende ist dann entweder das nächste anstehende Gate oder `done`).
- **AC25** — **Fehlerpfad bleibt Fehler (kein künstliches Status-JSON):** Fehlerfälle — klarer Abbruch (E1/E2,
  AC2/AC5), Aufruffehler oder eine Katalog-Vertragsverletzung — dürfen im `--gui`-Modus weiterhin mit
  **exitCode ≠ 0** und/oder Freitext-Meldung enden; der Runner erkennt das ohnehin als „Lauf fehlgeschlagen".
  Es wird **kein** `{status:…}`-JSON künstlich über einen echten Fehler gelegt (kein vorgetäuschtes `done`/
  `needs-answers`). Der JSON-Endvertrag (AC24) gilt **ausschliesslich** für die regulären Runden-Enden
  (Gate erreicht bzw. Durchlauf fertig).

> **Traceability:** Jeder Test trägt das kanonische Trace-Tag `@trace obsidian-ingest#AC<n>`
> gemäss `knowledge/<lang>.md` → `## Spec-Tagging`. Der `tester` rechnet das Coverage-Gate
> (jede genannte AC ≥ 1 deckender Test). Details: `docs/architecture/traceability-subsystem.md`.

## Verträge
- **Skill-Befehl:** `/agent-flow:from-notes [--gui] [--cost <mode>] [--sync|--audit] [<ordnerpfad>]` (Ingest) ·
  `--audit` (Integritätsprüfung, AC19–AC22). Auslöser dünn (dev-gui POST `/api/command` bzw. der headless
  `ObsidianIngestRunner`), gesamte Logik in agent-flow. Der Re-Sync-Modus (`--sync`) ist in `[[obsidian-sync]]`
  spezifiziert. Die Tokens `--gui`/`--cost`/`--sync`/`--audit` werden **vor** der Ordnerpfad-Auswertung
  herausgeparst und gehören **nicht** zum Ordnerpfad (AC23).
- **Headless-Ausgabevertrag (`--gui`, AC23–AC25):** Mit `--gui` (dev-gui-`ObsidianIngestRunner`, Aufruf
  `claude -p '/agent-flow:from-notes --gui <ordner>' --output-format json`) endet **jede Runde** mit **genau
  einem** JSON-**Wrapper-Objekt** als finaler Assistant-Nachricht (`.result`):
  - `{ "status": "needs-answers", "catalog": [ <Frage-Objekte gemäss board/fragenkatalog.schema.json> ] }` bei
    anstehendem Gate (Stufe `a|b|c|sync`), bzw.
  - `{ "status": "done" }` nach vollständigem Durchlauf.
  Das **innere** `catalog[]` folgt unverändert dem AC9-Feldvertrag (`board/fragenkatalog.schema.json`); der
  `{status,catalog}`-**Wrapper** ist der zusätzliche Headless-Rahmen. Die Antworten reicht der Runner im **Resume**
  desselben Session-Kontexts zurück (`--resume`, Zuordnung je Frage über `id`); jeder Resume endet wieder nach
  diesem Vertrag (nächstes Gate oder `done`). **Kein** Fliesstext nach dem JSON (AC24). Ohne `--gui` gilt dieser
  Wrapper **nicht** — der interaktive Terminal-Pfad stellt denselben `catalog` via `AskUserQuestion` (AC23).
- **Frontmatter-Sync-Felder (Vault-Schreibzone, AC17):** `idea_id` (`IDEA-NNN`) · `idea_status`
  (`draft | adopted | parked | rejected | superseded`) · `last_sync` · `sync_hash` · `C-NNN`-Referenz(en) —
  exakt die Felder aus Subsystem-Vertrag §4b; keine weiteren.
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
  **Feldmenge** oben ist der bindende Vertrag.) **Konkrete Serialisierung (Implementierung):** eine JSON-Liste von
  Frage-Objekten, formal beschrieben in `board/fragenkatalog.schema.json` (JSON Schema); der wiederverwendbare
  Gate-Validator `scripts/obsidian-fragenkatalog-validate.sh` prüft einen Katalog gegen diese Feldmenge und
  unterscheidet **leerer Katalog** → Auto-Durchlauf (AC8) von **nicht-leerer Katalog** → dem User vorlegen (AC7).
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
- Obsidian-Interna (`.obsidian/`, Anhänge) → ignoriert (AC5); ausser dem Frontmatter-Stempel (AC17) wird der
  Ordner nie beschrieben (AC6).
- **Headless (`--gui`) — Fliesstext statt JSON** (reproduzierter Defekt, Pilot research-app, Session a69c8b13,
  2026-07-19): der Lauf baute einen korrekten Stufe-a-Katalog auf, gab ihn aber als Fliesstext aus → Runner
  klassifizierte „kein JSON-Ausgang". AC23–AC25 schliessen das: der Skill weiss über `--gui`, dass headless kein
  `AskUserQuestion`-Adressat existiert, und muss das Gate als JSON-Wrapper ausgeben.
- **Headless-Robustheit bei Sub-Agent-Stufen (b/c) — Vorsicht (Präzedenz `[[regression-define]]` AC12/AC13, S-059):**
  Stufe a baut ihren Katalog **ohne** Sub-Agent und kann die JSON-Endnachricht zuverlässig selbst setzen (der
  häufigste headless Runden-Fall). In den Stufen **b/c** dispatcht der Skill Sub-Agenten (`designer`/`requirement`);
  eine orchestrierende `claude -p`-Session neigt dazu, ein Sub-Agent-Ergebnis konversationell **zu Prosa
  zusammenzufassen** — genau das machte bei `regression-define` reine Instruktions-Härtung unzuverlässig, weshalb
  dort auf einen **Datei-Vertrag** (`ergebnis_datei=<pfad>`) umgestellt wurde. Für from-notes bleibt hier der
  stdout-JSON-Vertrag (AC24) — die von b/c erreichten Gates sind der **Skill-eigene** Katalog (nicht ein
  verbatim durchgereichtes Sub-Agent-Result), sodass die finale Assistant-Nachricht steuerbar ist; die
  SKILL.md-Anweisung ist entsprechend strikt zu formulieren. **Sollte** sich der stdout-Vertrag für b/c in der
  Praxis dennoch als unzuverlässig erweisen, ist der bei `regression-define` bewährte `ergebnis_datei=`-Datei-Kanal
  die dokumentierte Ausweichlösung (dann als Folge-Anforderung, Cross-Repo mit dev-gui abzustimmen).

## NFRs
- **Präzision vor Tempo (Erst-Übersetzung):** Stufe a fragt im Zweifel lieber nach (AC10) — Fehlerfortpflanzung in
  Spec/Stories ist teurer als eine Rückfrage.
- **Nachvollziehbarkeit:** Fragenkatalog-Einträge und die abgeleiteten Docs tragen Herkunfts-Bezug zur Quellnotiz
  (AC4), sodass Entscheidungen bis zur Notiz rückverfolgbar sind; die ID-Kette (AC15/AC16) macht das ID-fest.
- **Robustheit:** kein stiller Leerlauf (AC2/AC5); Zwischenstände durable (AC12).
- **Sicherheit/Vorsicht:** Vault-Schreibzugriff strikt auf die Frontmatter-Sync-Felder begrenzt (AC6/AC17);
  kein `/flow`-Start, kein Merge/Deploy (AC14).

## Nicht-Ziele
- **Kein** Ersatz der vagen Anforderung — additiver dritter Weg (AC3).
- **Kein** zweiter Zerlege-Pfad — Stufe c nutzt `requirement` (AC11/AC13).
- **Kein** Schreiben ausserhalb der Frontmatter-Sync-Felder (AC6/AC17); der generierte Abschnitt + neue
  Ideennotizen sind allein Sache des Rückkanals (`[[reconcile]]` Stufe 3) — **kein** Rückschreiben von
  Konzept-Inhalten durch den Ingest selbst.
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
  stellt nur den Befehl `/agent-flow:from-notes`, das Fragenkatalog-Rückgabeformat (AC9) **und** das
  `--gui`-Signal + den `{status,catalog}`-Headless-Wrapper (AC23–AC25) bereit. Die dev-gui-Seite —
  `ObsidianIngestRunner` **sendet** das `--gui`-Signal und **konsumiert/rendert** den Wrapper (dev-gui-Spec
  `obsidian-question-catalog.md`, AC1/AC2/AC12) — ist die **Gegenstück-Story** und entsteht **im dev-gui-Repo,
  NICHT hier**.
- `[[reconcile]]` — Stufe 3 (Obsidian-Rückspielung) konsumiert `idea_id`/`C-NNN`/`last_sync`/`sync_hash`
  (AC15–AC17) als Anker; der `--audit` liefert ihr die Waisen-aufwärts-Liste (AC21).
- Vertrag: `docs/architecture/obsidian-ingest-subsystem.md` (§4b Schreibzonen, §5a Audit). Kontext: CONCEPT §4a (Pipeline) / §4d (durable Docs);
  Abgrenzung zu `docs/architecture/reconcile-subsystem.md` (Reconcile ≠ Re-Sync, siehe `[[obsidian-sync]]`).
