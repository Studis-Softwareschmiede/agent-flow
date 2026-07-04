---
name: from-notes
description: Speist einen Obsidian-Notiz-Ordner als dritten Requirement-Weg in den Fabrik-Pfad Konzept -> Spezifikation -> Story ein. Orchestriert drei Stufen IN REIHE — (a) Notiz-Korpus -> docs/concept.md, (b) Konzept -> docs/specs/<feature>.md (+ architekt/dba wo nötig), (c) Spec(s) -> Board-Items/Stories über den bestehenden requirement-Agenten. Ein Fragenkatalog-Gate pro Stufe (genau EIN gesammelter Katalog, am Stück beantwortet; leer -> Auto-Durchlauf), Commit pro Stufe in harter Reihenfolge. Zweiter Modus --sync (Re-Sync, Spec obsidian-sync): gleicht den aktuellen Notiz-Stand gegen docs/concept.md + docs/specs/* ab, meldet Divergenzen als priorisierten Bericht und legt sie als genau EINEN Fragenkatalog (stage sync, je Divergenz uebernehmen/behalten/manuell) vor — schreibt NUR die als uebernehmen gewaehlten Aenderungen, nie automatisch (invertierte Reconcile-Autoritaet); teilt Reader + Katalog-Gate mit dem Ingest und laesst den Reconcile-Vertrag unangetastet (kein Reconcile-Stufe-0). Authoring-only — schreibt NUR docs/, das Profilfeld obsidian_source und Board-Items (To Do); KEIN App-Code, KEIN /flow-Start, KEIN Merge/Deploy, KEIN Schreiben in den Notiz-Ordner. Im Ziel-Projekt-Repo ausführen. Aufruf: /agent-flow:from-notes [--cost <mode>] [--sync] [<ordnerpfad>].
---

# /agent-flow:from-notes [--cost <mode>] [--sync] [<ordnerpfad>]

Speist einen **Obsidian-Notiz-Ordner** (mehrere freie `.md`-Notizen aus der Ideen-/Konzeptphase) als **dritten** Requirement-Weg (neben `new-project`/`init` und `requirement`) in den bestehenden Fabrik-Pfad **Konzept → Spezifikation → Story** ein. cwd = Ziel-Projekt-Repo.

**Dieser Skill ist der einzige Schreiber** der Doc-/Board-/Profil-Änderungen dieses Flusses und orchestriert **drei Stufen in Reihe** — er baut **keinen** eigenen Zerlege-, Schätz- oder Übersetzungs-Baustein neu, sondern **wiederverwendet** die bestehenden Bausteine (Reader, Fragenkatalog-Gate, `requirement`/`architekt`/`dba`).

Bindende Quellen: `docs/specs/obsidian-ingest.md` (AC11–AC14, sowie AC1–AC10 der wiederverwendeten Bausteine) + `docs/architecture/obsidian-ingest-subsystem.md` (§3 Drei-Stufen-Pipeline, §4 `obsidian_source`, §5 Re-Sync, §6 dev-gui-Schnittstelle). Der **Re-Sync-Modus** (`--sync`) ist ein **eigener Modus dieses Skills** (Spec `docs/specs/obsidian-sync.md`, AC1–AC6, §5 unten); er teilt Reader + Katalog-Gate mit dem Ingest und lässt den Reconcile-Vertrag (`docs/architecture/reconcile-subsystem.md`) **unangetastet**.

> **Authoring-only (AC14, hart).** Die Pipeline schreibt **ausschließlich** durable Docs (`docs/`), das Profilfeld `obsidian_source` und Board-Items (Status **To Do**). **Kein** App-Code, **kein** `/flow`-Start, **kein** Merge/Deploy und **kein** Schreiben in den Notiz-Ordner (der Vault ist rein lesende externe Quelle, AC6). Item-Status bleibt allein `/flow`-Hoheit.

## Modus-Wahl — Ingest (Default) vs. Re-Sync (`--sync`) (obsidian-sync AC1)

Der Skill hat **zwei Modi**:

- **ohne `--sync`** → **Ingest** (Default): Stufen a→b→c (§0–§4). Notiz **erzeugt** initial Konzept/Spec/Stories.
- **mit `--sync`** → **Re-Sync** (§5, Spec `docs/specs/obsidian-sync.md`): gleicht den **aktuellen Notiz-Stand** gegen den **aktuellen `docs/concept.md` + `docs/specs/*`-Stand** ab, **meldet** Divergenzen und legt sie als **genau EINEN** Fragenkatalog (`stage:"sync"`) vor — schreibt Konzept/Spec **nie** automatisch (invertierte Reconcile-Autorität, obsidian-sync AC3).

Das `--sync`-Token wird — wie `--cost` — **vor** der Ordnerpfad-Auswertung herausgeparst und gehört **nicht** zum Ordnerpfad. Beide Modi teilen sich denselben **Reader** (§0b) und dasselbe **Fragenkatalog-Gate**; der Re-Sync ist ein **eigener Modus** und lässt den **Reconcile-Vertrag** (`docs/architecture/reconcile-subsystem.md`) **unangetastet** — er ist **kein** Reconcile-„Stufe 0" (obsidian-sync AC1). Bei `--sync` gelten **§0** (Setup) und **§0a/§0b** (Ordner + Reader, rein lesend) sinngemäß; die Ingest-Stufen **§1–§3 laufen dann nicht**, stattdessen **§5**.

## 0. Setup

- **Cost-Mode auflösen:** Präzedenz `--cost`-Argument > `profile.cost_mode` > `balanced` (Kurzformen `low`/`max`/`front` normalisieren; `front`→`frontier`). Beim Task-Dispatch der Agenten (`requirement`/`architekt`/`dba` in Stufe b/c) den `model`-Parameter aus `${CLAUDE_PLUGIN_ROOT}/knowledge/model-tiers.md` (Zeile = Rolle) mitgeben; bei `balanced` **keinen** Override (Agent-Frontmatter gilt). **Ausnahme (Design-Rollen-Pinning, `docs/specs/model-phase-pinning.md` AC3):** der `dba`-Dispatch in Stufe b ist **immer** der **Design-Modus** (Datenmodell-Entwurf → `docs/data-model.md`) — dieser erhält **in jedem Cost-Mode** (auch `low-cost`/`balanced`) einen festen `model: opus`-Override, unabhängig von der `dba`-Matrix-Zeile (die nur den **Review-Modus** des `dba` beschreibt, siehe `knowledge/model-tiers.md` „Design-Rollen-Pinning"). `requirement` (Stufe c) und `architekt` (Stufe b) folgen weiterhin normal der Matrix (dort bereits als Design-Rollen gepinnt). Das `--cost`-Token gehört NICHT zum Ordnerpfad — vor der Argument-Auswertung herausparsen. Ebenso das **`--sync`**-Token (Modus-Wahl, siehe *Modus-Wahl* oben): vor der Ordnerpfad-Auswertung herausparsen; ist es gesetzt → **Re-Sync-Modus** (§5), sonst Ingest.
- **Auth herstellen:** `bash "$CLAUDE_PLUGIN_ROOT/scripts/ensure-gh-auth.sh"` (mintet App-Token, loggt `gh` ein — für Stufe c, die über `requirement` Board-Items anlegt). NICHT `gh auth login --web`.
- **Profil lesen:** `.claude/profile.md` → `default_branch`, `cost_mode`, `obsidian_source` (falls gesetzt).
- **Working-Tree sollte sauber sein**, bevor Stufe a schreibt (sonst vermischen sich fremde Änderungen mit dem Stufen-Commit). Ist der Tree nicht sauber: Hinweis ausgeben, User entscheiden lassen, ob fortgefahren wird.

## 0a. Ordnerpfad auflösen + `obsidian_source` setzen (AC1/AC2 — wiederverwendet, hier nur genutzt)

Precedence **Argument > Profil** (Subsystem §4, Spec AC2):

1. **Ordner-Argument übergeben:** dieses gilt. Als **absoluten** Pfad normalisieren und in `.claude/profile.md` als `obsidian_source: <absoluter-pfad>` setzen/aktualisieren (Feld ist optional/additiv, S-020). War die Zeile im Profil auskommentiert (Vorlagen-Platzhalter `# obsidian_source: …`), wird sie zur aktiven Zeile.
2. **Kein Argument, aber `obsidian_source` im Profil gesetzt:** den Pfad daraus lesen (*deckt A2*).
3. **Weder Argument noch `obsidian_source`:** **klarer Abbruch** mit Meldung „kein Notiz-Ordner angegeben und keiner am Projekt vermerkt" (*deckt E1*, AC2) — **kein** Leerlauf, **keine** leere Pipeline. Ende.

Das Profilfeld-Schreiben ist der **einzige** Profil-Schreibvorgang dieses Skills und fährt mit dem **Stufe-a-Commit** mit (siehe §1.4).

## 0b. Notiz-Korpus lesen (AC4–AC6 — wiederverwendeter Reader, rein lesend)

Den bestehenden **Notiz-Korpus-Reader** aufrufen (S-021, kein Neubau):

```bash
bash "$CLAUDE_PLUGIN_ROOT/scripts/obsidian-corpus-read.sh" "<aufgelöster-ordnerpfad>" > "$CORPUS_FILE"
```

- **Exit 0** → `$CORPUS_FILE` hält den konsolidierten Korpus (deterministisch geordnet, je Notiz ein Herkunfts-Marker `===== NOTE: <relativer-pfad> =====`). Weiter mit Stufe a.
- **Exit 2** (Pfad fehlt / kein Verzeichnis / keine `.md`) → **klarer Abbruch** mit der Reader-Meldung (*deckt E2*, AC5); **niemals** eine leere `concept.md`/Spec anlegen. Ende.
- **Exit 1** (Aufruffehler) → Fehler melden, Ende.

`$CORPUS_FILE` ist eine temporäre Datei (`mktemp`), **nie** im Repo committet — der Vault bleibt rein lesend (AC6). Die Herkunfts-Marker im Korpus liefern das `quelle`-Feld für Fragenkatalog-Einträge (AC9).

## 1. Stufe a — Notiz-Korpus → `docs/concept.md` (AC11a, kritischste Stufe)

**Ziel:** den Notiz-Korpus zum Konzept konsolidieren (Problem · Nutzer · Ziele · Nicht-Ziele · Scope). Diese Stufe ist der **kritische Punkt** (Subsystem §1/§3): eine ungenaue Erst-Übersetzung vererbt Fehler an Spec und Stories.

1. **Übersetzen (niedrigste Nachfrage-Schwelle, AC10):** Aus `$CORPUS_FILE` das Konzept nach `docs/concept.md` schreiben (Skelett `templates/_docs/concept.md`; existiert bereits ein Root-`CONCEPT.md`-Layout wie in manchen Projekten, dort die betroffenen Sektionen ergänzen statt einer neuen Datei — dieselbe Layout-Konvention wie `reconcile`). **Jede** relevante Mehrdeutigkeit/jeder Widerspruch im Ideen-Text wird zur **Frage** (Fragenkatalog-Eintrag), **nicht** zur stillen Annahme — die Schwelle ist hier bewusst niedrig (AC10). Jeder Katalog-Eintrag trägt im `quelle`-Feld den Herkunfts-Marker der Quellnotiz.

2. **Areas-Entwurf ableiten (AC1, from-notes-areas):** Nach der `docs/concept.md`-Erzeugung einen **`areas.yaml`-Entwurf** aus dem Konzept ableiten — je Produktbereich `id` (kebab-case), `titel`, `beschreibung` (genau 1 Satz), `reihenfolge` (int, eindeutig), konform zum Feldformat aus [[board-areas]] AC1 (oder über ein Hilfsskript ableiten). Der Entwurf wird als Liste aufgebaut und zur Bestätigung über das Fragenkatalog-Gate vorgelegt (AC2, siehe 1.3). Lässt sich kein Bereich ableiten → minimaler Platzhalter-Bereich (z.B. `{id: allgemein, titel: Allgemein, beschreibung: Platzhalter, reihenfolge: 1}`) oder dokumentiert übersprungen (*deckt E1* der from-notes-areas-Spec).

3. **Fragenkatalog-Gate mit Areas-Bestätigung (AC2, from-notes-areas):** Alle offenen Punkte dieser Stufe **gesammelt** als **genau EINE** JSON-Liste von Frage-Objekten aufbauen — je Objekt `stage:"a"`, `id` (katalog-eindeutig, Muster `a-<n>` für beide Konzept- und Bereichsfragen, fortlaufend), `frage`, `quelle` (Notiz-Fundstelle oder Konzept-Sektion), optional `optionen[]` (Format-Vertrag: `board/fragenkatalog.schema.json`). **Die abgeleiteten Bereiche aus Schritt 1.2 als zusätzliche Katalog-Punkte integrieren:** je Bereich **eine Frage** zum **Streichen/Ergänzen/Bestätigen** (AC2). Den gesammelten Katalog (Konzept-Fragen + Areas-Fragen) durch den wiederverwendeten Gate-Validator prüfen und das Vorlege-Verhalten am stdout-Token festmachen:
   ```bash
   printf '%s' "$KATALOG_A_JSON" | bash "$CLAUDE_PLUGIN_ROOT/scripts/obsidian-fragenkatalog-validate.sh"
   ```
   - **`empty`** → keine offenen Fragen → **Auto-Durchlauf** (AC8, deckt A1 der from-notes-areas-Spec): kein Katalog vorlegen, abgeleitete Bereiche als Defaults bestätigen, direkt zu 1.4.
   - **`valid`** → nicht-leerer Katalog → dem User **am Stück** vorlegen (AC7): im Terminal-Pfad via `AskUserQuestion` (ein Prompt, alle Fragen zusammen); im dev-gui-Pfad rendert dev-gui denselben JSON-Katalog und reicht die Antworten über die `id`-Zuordnung zurück (AC9). **Erst nach** vollständiger Beantwortung: (a) fließen die Konzept-Antworten in `docs/concept.md` ein, und (b) werden die Areas-Antworten gefiltert (nur "bestätigen"/"ändern" → in Bestätigung aufnehmen, "streichen" → ausschließen).
   - **Exit 1/2** (Vertragsverletzung / Aufrufproblem) → den selbst erzeugten Katalog korrigieren und erneut validieren (nie einen ungültigen Katalog vorlegen).

4. **Commit Stufe a mit areas.yaml (AC3, from-notes-areas, durable):** Erst **nachdem** der Katalog beantwortet (oder leer) ist — die bestätigten Bereiche in `board/areas.yaml` schreiben:
   - Die Bereiche filtern: nur die als "bestätigen" oder "ändern" gebilligten Bereiche übernehmen. Bei Auto-Durchlauf (leerer Katalog): alle abgeleiteten Bereiche als bestätigt.
   - `board/areas.yaml` schreiben: Vor dem Schreiben prüfen, ob `board/areas.yaml` bereits existiert (Re-Ingest-Szenario). **Existiert die Datei:** nur die NEUEN bestätigten Bereiche hinzufügen (deren `id` nicht bereits in der bestehenden `areas.yaml` vorhanden ist); **Bestehendes nicht blind überschreiben** (Spec NFR Nicht-destruktiv, Edge-Case-Abschnitt). **Existiert die Datei noch nicht:** alle bestätigten Bereiche als neue YAML-Array schreiben. Ergebnis: konform zu `board/areas.schema.json`.
   - Dann:
   ```bash
   git add docs/concept.md board/areas.yaml .claude/profile.md && git commit -m "notes(a): Notiz-Korpus -> docs/concept.md + board/areas.yaml (obsidian-ingest from-notes-areas AC1-AC3)

   Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>" && git push
   ```
   Der Profilfeld-Diff (`obsidian_source`, §0a) fährt hier mit. `.claude/profile.md` nur `git add`en, wenn §0a das Feld tatsächlich gesetzt/geändert hat. `board/areas.yaml` nur adden, wenn Bereiche bestätigt wurden (AC3). Lehnt Branch-Protection den Direkt-Push ab → docs-only-PR öffnen + selbst mergen (analog `requirement`-Skill). Der Notiz-Ordner wird **nie** ge-`add`et (AC6/AC14). *(AC3 auch E1: keine `areas.yaml`, wenn Owner alle Bereiche streicht oder der Entwurf leer war → Board-Stufe läuft wie ohne Bereichs-Gate)*

Stufe b startet **erst nach** committetem Stufe-a-Ergebnis (harte Reihenfolge, AC12).

## 2. Stufe b — `docs/concept.md` → `docs/specs/<feature>.md` (AC11b/AC13)

**Ziel:** je Capability des Konzepts **eine** durable Spec ableiten, den bestehenden **Spec-Vertrag wiederverwenden** (AC13) — Vorlage, `spec_format`-Stempel, nummerierte AC, Traceability.

1. **Spec(s) schreiben:** je Capability eine `docs/specs/<feature-slug>.md` aus `templates/_docs/specs/_template.md` — Zweck, Verhalten, **nummerierte Acceptance-Kriterien (AC1, AC2, …)**, Verträge, Edge-Cases, NFRs, Nicht-Ziele. **`spec_format`-Stempel:** den Wert 1:1 aus der **aktuellen** `_template.md` übernehmen (nicht hartkodieren), wie es der Spec-Vertrag (`docs/specs/spec-format-field.md` AC3) und `requirement` fordern.
2. **Tiefes Detail via bestehende Agenten (AC11b/AC13 — kein Neubau):** Wo tiefes Architektur-Detail nötig ist, den **`architekt`**-Agenten (Task) dispatchen → `docs/architecture.md` bzw. `docs/architecture/<subsystem>.md`. Wo ein Datenmodell nötig ist, den **`dba`**-Agenten (Task, **Design-Modus**) → `docs/data-model.md` — dieser Dispatch bekommt **immer** `model: opus` (Design-Rollen-Pinning, siehe §0), unabhängig vom aktiven Cost-Mode. Beide schreiben nur in den Working-Tree (kein Commit) — das Committen macht dieser Skill in 2.4.
3. **Fragenkatalog-Gate (AC7/AC8/AC9):** identische Mechanik wie 1.3, aber `stage:"b"`, `id`-Muster `b-<n>`, `quelle` = Konzept-/Doku-Fundstelle. `empty` → Auto-Durchlauf; `valid` → dem User am Stück vorlegen (`AskUserQuestion` / dev-gui); erst nach Beantwortung fließen die Antworten in die Spec(s)/Architektur ein.
4. **Commit Stufe b (AC12):** Erst nach beantwortetem/leerem Katalog:
   ```bash
   git add docs/ && git commit -m "notes(b): Konzept -> docs/specs/<…> (obsidian-ingest)

   Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>" && git push
   ```
   Alle in dieser Stufe berührten `docs/`-Dateien (Spec(s) + ggf. `architecture*.md`/`data-model.md`) fahren in **einem** Stufe-b-Commit. Branch-Protection → docs-only-PR + Self-Merge.

Stufe c startet **erst nach** committetem Stufe-b-Ergebnis (harte Reihenfolge, AC12).

## 3. Stufe c — Spec(s) → Board-Items/Stories über den `requirement`-Agenten (AC11c/AC13, mit Bereichs-Gate AC4)

**Ziel:** die in Stufe b entstandenen Spec(s) in Board-Items/Stories zerlegen — **über den bestehenden `requirement`-Agenten** (AC11: „kein zweiter Zerlege-Pfad"). **Bereichs-Gate (AC4 der from-notes-areas-Spec):** Der `requirement`-Agent liest in dieser Stufe die in Stufe a geschriebenen **bestätigten Bereiche** aus `board/areas.yaml` — er legt Storys **ausschließlich** unter Bereichs-Features dieser bestätigten Bereiche an (Story-`parent` = Bereichs-Feature des zugeordneten Bereichs; neue Specs tragen `area: <bereich>` im Frontmatter). **Kein** Item ohne Bereich, **keine** autonome Bereichs-Erfindung. Fehlt `board/areas.yaml` oder ist leer (Edge-Case E1: keine Bereiche bestätigt), arbeitet der `requirement`-Agent wie ohne Bereichs-Gate ([[requirement-area-intake]] AC1) und vermerkt das im Output.

1. **`requirement`-Agent dispatchen (Task, `agents/requirement.md`):** als Eingabe die in Stufe b geschriebene(n) Spec(s) übergeben — nicht eine neue vage Anforderung, sondern der Verweis auf die bereits durable Spec(s) mit dem Auftrag, sie in Board-Items zu zerlegen. Der `requirement`-Agent leistet dabei **ohnehin** (AC13):
   - Zerlegung in TODOs (je Item ≈ ein coder→reviewer→tester-Durchlauf),
   - je Item ein Board-Item (**To Do**), das auf **Spec + AC-Nummern** zeigt (**kein** eingebetteter AC-Text),
   - die **A-priori-Schätzung** (`size_est`/`dispo_est`/`confidence`/`estimate_note`) bei der Anlage.

   Da die Spec(s) bereits geschrieben sind, sollte der `requirement`-Agent hier i.d.R. **nicht** erneut Spec-schreiben — sein Fokus ist die Zerlegung. Legt er dabei doch Spec-Feinschliff nach (Working-Tree), fährt der in den Stufe-c-Commit (3.3). **Der Agent führt das Bereichs-Gate durch (AC4):** er liest die bestätigten Bereiche aus `board/areas.yaml`, ordnet jede Spec einem Bereich zu (oder lenkt bereichsfremde Teile in die Ideen-Inbox), und stempelt neue Specs mit `area: <bereich>` — siehe `docs/specs/requirement-area-intake.md` AC1–AC3.
2. **Fragenkatalog-Gate (AC7/AC8/AC9) und Bereichs-Zuordnung (AC4):** Bleiben bei der Zerlegung Unklarheiten offen (z.B. Schnitt-Granularität, Priorität, Abhängigkeiten), diese **gesammelt** als **einen** Katalog `stage:"c"` (`id`-Muster `c-<n>`, `quelle` = Spec-/Doku-Fundstelle) — Validator + Vorlege-Verhalten wie oben. Der `requirement`-Agent stellt seine eigenen gezielten Rückfragen normalerweise selbst; ein separater Stufe-c-Katalog wird nur aufgebaut, wenn nach seinem Lauf noch pipeline-seitige Unklarheiten offen sind (kein leerer Katalog, AC8). **Bereichs-Fragen (AC4):** sollte der `requirement`-Agent bei der Bereichs-Zuordnung feststellen, dass eine Spec keinem bestehenden Bereich passt (bereichsfremd), lenkt er sie autonom in die Ideen-Inbox — es gibt dafür **keine** Owner-Rückfrage, sondern eine Begründung im Output ([[requirement-area-intake]] AC4).
3. **Commit Stufe c (AC12):** Der `requirement`-Agent legt die Board-Items an (Status **To Do**, `/flow`-Hoheit endet dort — kein Status-Vorschub, AC14). Etwaige vom Agenten in den Working-Tree geschriebene `docs/`-Deltas dieser Stufe committen:
   ```bash
   git add docs/ && git commit -m "notes(c): Spec(s) -> Board-Items (obsidian-ingest)

   Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>" && git push
   ```
   Gibt es keinen `docs/`-Delta in Stufe c (Items liegen im File-Board bzw. via `gh` am GitHub-Board), entfällt der Doc-Commit — die Board-Items selbst sind der durable Zustand dieser Stufe.

**Kein `/flow`-Start, kein Merge/Deploy** (AC14). Der Ordner bleibt unangetastet; das Projekt kann jederzeit erneut aus den Notizen arbeiten (Re-Ingest oder `[[obsidian-sync]]`).

## 4. Output

```
Obsidian-Ingest (from-notes) — Ordner: <aufgelöster-pfad> (Quelle: <Argument | Profil obsidian_source>)
Korpus: <n> Notiz(en) gelesen
Stufe a: docs/concept.md geschrieben — Katalog a: <leer/Auto-Durchlauf | <k> Frage(n) beantwortet> — board/areas.yaml: <m Bereiche bestätigt | keine Bereiche bestätigt (E1)> — committet <sha|PR>
Stufe b: docs/specs/<…> (+ <architektur/data-model falls>) — Katalog b: <…> — committet <sha|PR>
Stufe c: <n> Board-Item(s) (To Do) via requirement — Bereichs-Gate: <aktiv (m Bereiche) | nicht aktiv (areas.yaml fehlt, E1)> — Katalog c: <…> — committet <sha|PR|kein Doc-Delta>
  #<id> <title> — Spec <feature-slug> (AC<…>) — Bereich <bereich-id> — size_est: <…> dispo_est: <…>
Bereit für /agent-flow:flow.
```

## 5. Re-Sync-Modus (`--sync`) — Notiz ↔ Konzept/Spec abgleichen (obsidian-sync AC1–AC6)

**Nur bei `--sync`** (statt der Ingest-Stufen §1–§3). Bindende Quelle: `docs/specs/obsidian-sync.md` (AC1–AC6) + `docs/architecture/obsidian-ingest-subsystem.md` §5. Dieser Modus **erkennt und meldet** Widersprüche zwischen dem **aktuellen Notiz-Stand** und dem **aktuellen `docs/concept.md` + `docs/specs/*`-Stand** und legt sie dem User **zur Entscheidung** vor — er **überschreibt Konzept/Spec nie automatisch** (invertierte Reconcile-Autorität, AC3). Er teilt Reader (§0b) + Fragenkatalog-Gate mit dem Ingest, ist aber ein **eigener Modus** und lässt den **Reconcile-Vertrag** (`docs/architecture/reconcile-subsystem.md`) **unangetastet** (AC1) — **kein** Reconcile-„Stufe 0".

### 5.1 Vergleichsseiten beschaffen (AC1, rein lesend)

1. **Ordner auflösen** (Precedence wie §0a: Argument > `obsidian_source`): der Re-Sync läuft im Normalfall **ohne** Ordner-Argument → `obsidian_source` aus `.claude/profile.md`. Fehlt `obsidian_source` **und** kein Argument → **klarer Abbruch** „kein Notiz-Ordner am Projekt vermerkt" (AC6, *deckt E1*). Ende — **kein** Leerlauf, **keine** Doku-Änderung. Der Re-Sync schreibt `obsidian_source` **nicht** neu (nur der Ingest bei explizitem Argument, §0a).
2. **Notiz-Korpus lesen (linke Vergleichsseite)** — derselbe Reader wie §0b (kein Neubau, AC1):
   ```bash
   bash "$CLAUDE_PLUGIN_ROOT/scripts/obsidian-corpus-read.sh" "<aufgelöster-ordnerpfad>" > "$CORPUS_FILE"
   ```
   - **Exit 2** (Ordner unlesbar / keine `.md`) → **klarer Abbruch** mit der Reader-Meldung (AC6, *deckt E1*), **niemals** eine Doku-Änderung. Ende.
   - **Exit 0** → `$CORPUS_FILE` (`mktemp`, **nie** committet — AC6) hält den Korpus; die Herkunfts-Marker `===== NOTE: <pfad> =====` liefern das `notiz_fundstelle`-/`quelle`-Feld.
3. **Doku-Stand lesen (rechte Vergleichsseite)** — der **aktuelle** `docs/concept.md` **+ alle** `docs/specs/*`, **rein lesend**.

### 5.2 Divergenzen erkennen + unassignierte Themen erkennen + priorisierter Bericht (AC2, AC5 — reiner Bericht, kein Gate)

Beide Seiten abgleichen und **Divergenzen** sammeln. Je Fund **genau diese Felder** (Bericht-Format, Vertrag der Spec):

- **`notiz_fundstelle`** — relativer Notiz-Pfad (Herkunfts-Marker) + Kontext,
- **`doku_ziel`** — betroffenes Doku-**Dokument + Sektion** (z.B. `docs/concept.md §Ziele`, `docs/specs/<feature>.md §AC3`),
- **`divergenz_art`** — Art der Divergenz, z.B. *Notiz widerspricht Konzept-Aussage* · *Notiz enthält Neues, das die Spec nicht abbildet* · *Doku enthält, was die Notiz nicht mehr trägt*,
- **`richtungsvorschlag`** — unverbindlicher Vorschlag, welche Richtung plausibel ist.

**Zusätzlich (AC5 — from-notes-areas):** nach dem Inhalts-Abgleich auch **Topics/Themen im aktuellen Notiz-Stand** gegen **bestätigte Bereiche in `board/areas.yaml`** prüfen. Erkennt `--sync` im Notiz-Stand ein **Produktbereich-Thema, das keinem bestehenden Bereich in `board/areas.yaml` zugeordnet ist** (bereichsfremd), wird es separat gemäß Abschnitt 5.2a als **Fragenkatalog-Punkt** (`stage:"sync"`) mit Bereichs-Zuordnungs-Optionen erfasst (nie selbst Bereich angelegt, AC5). **Kein** bereichsfremdes Thema gefunden → kein zusätzlicher Katalog-Punkt, **Rauscharmut** (AC5).

Der Bericht ist **priorisiert** (klarste/wichtigste Widersprüche zuerst) und **rein informativ**: **kein** Gate, **keine** automatischen Board-Items, **kein** `/flow`-Start (AC2/AC6). Widerspricht ein Notiz-Stand **mehreren** Doku-Stellen → **mehrere Funde**, aber in **einem** Bericht/Katalog (nie verstreute Einzel-Prompts).

### 5.2a Unassignierte Produktbereich-Themen als Fragenkatalog-Punkte (AC5 — from-notes-areas)

**Nur wenn `board/areas.yaml` bereits existiert** (Re-Ingest-Szenario mit bestätigten Bereichen):

1. **Themen aus Notiz-Stand extrahieren:** aus dem Notiz-Korpus (linke Seite) diejenigen **Produktbereich-Themen** identifizieren, die im Konzept/in den Notizen als konzeptionelle Bereiche/Domänen erwähnt sind — analog der AC1-Ableitung aus dem Konzept (Scope, Produktabgrenzung).

2. **Gegen bestätigte Bereiche abgleichen:** jedes identifizierte Thema gegen die Liste der `id`-Felder in der existierenden `board/areas.yaml` prüfen. **Bereichsfremd** = Thema kommt in den Notizen vor, sein `id` (oder ein sinngemäßes Äquivalent) fehlt in `areas.yaml`.

3. **Keine Automatic, nur Vorschlag (AC5, invertierte Autorität):** Findet der Abgleich **bereichsfremde Themen:**
   - **nicht** selbst einen neuen Bereich anlegen (AC5 / [[requirement-area-intake]] AC3),
   - stattdessen: für **jedes** bereichsfremde Thema **genau einen** Fragenkatalog-Punkt (Abschnitt 5.4 — Format `{stage:"sync", id:"sync-<n>", …}`) mit:
     - `frage`: "Notiz-Thema ‚<Thema-Name>' — einem bestehenden Bereich zuordnen, neuen Bereich als Owner-Entscheid erstellen oder skippen?"
     - `quelle`: Notiz-Fundstelle(n), wo das Thema genannt wurde,
     - **`optionen`**: min. `["bereich-<id>", "bereich-<id>", …, "neuer-bereich", "skippen"]` — konkrete bestätigte Bereich-IDs aus `areas.yaml` **+ Option „neuer-bereich" (Owner-Entscheid, wird nicht auto-erstellt)** + Option „skippen" (Thema ignorieren); **nie** blind „neuer Bereich wird jetzt angelegt".

4. **Rauscharmut (AC5):** Findet der Abgleich **kein** bereichsfremdes Thema (alle Notiz-Themen sind bereits in `areas.yaml` zugeordnet) → **kein zusätzlicher Fragenkatalog-Punkt**, kein Katalog-Eintrag für Bereichs-Zuordnung (bestätigter Zustand, Deckungsgleichheit in der Bereichs-Dimension, AC5).

### 5.3 Deckungsgleich → Ende ohne Katalog/Änderung (AC5, from-notes-areas — *deckt A1*)

Finden 5.2 + 5.2a **zusammen** (a) **keine** Divergenzen im Inhalts-Abgleich **und** (b) **keine** bereichsfremden Themen → **kein** Fragenkatalog, **keine** Doku-Änderung, **keine** Bereichs-Katalog-Punkte. Klare **„deckungsgleich"**-Meldung ausgeben und **enden** (Rauscharmut, AC5). Der Notiz-Ordner bleibt unangetastet.

### 5.4 Genau EIN Fragenkatalog, gerichteter Entscheid (AC4/AC5, from-notes-areas)

Bei ≥1 Divergenz **oder** ≥1 bereichsfremdes Thema **alle zusammen** als **genau EINEN** Fragenkatalog aufbauen — gleiches maschinenlesbares Rückgabeformat wie `[[obsidian-ingest]]` AC9 (`board/fragenkatalog.schema.json`):
- **Content-Divergenzen:** je Frage `stage:"sync"`, `id`-Muster `sync-<n>` (katalog-eindeutig), `frage` (die Divergenz in Alltagssprache), `quelle` = `notiz_fundstelle` + `doku_ziel`, und `optionen:["uebernehmen","behalten","manuell"]` (je Divergenz **eine** Frage mit genau diesen drei Richtungen).
- **Unassignierte Themen ((AC5, from-notes-areas)):** je Thema ebenfalls `stage:"sync"`, `id`-Muster `sync-<n>` (Fortlauf über alle Katalog-Punkte), `frage` = „Notiz-Thema ‚<name>' — Bereichs-Zuordnung?", `quelle` = Notiz-Fundstelle(n), `optionen:["bereich-<id>", "bereich-<id>", …, "neuer-bereich", "skippen"]` (konkrete Bereichs-IDs aus `areas.yaml` + Owner-Entscheid-Optionen).

Den Katalog durch den **wiederverwendeten** Gate-Validator prüfen:
   ```bash
   printf '%s' "$KATALOG_SYNC_JSON" | bash "$CLAUDE_PLUGIN_ROOT/scripts/obsidian-fragenkatalog-validate.sh"
   ```
   - **`valid`** → dem User **am Stück** vorlegen (Terminal: `AskUserQuestion`, ein Prompt für alle Punkte; dev-gui rendert denselben JSON-Katalog und reicht die Antworten über die `id`-Zuordnung zurück). **Nie** Einzel-Prompt je Fund verstreut (AC4/Edge).
   - **`empty`** darf hier **nicht** auftreten (bei ≥1 Fund aus 5.2+5.2a ist der Katalog nicht leer); erscheint es doch → es lag Deckungsgleichheit vor → 5.3.
   - **Exit 1/2** (Vertragsverletzung / Aufrufproblem) → den selbst erzeugten Katalog korrigieren und erneut validieren (nie einen ungültigen Katalog vorlegen).

### 5.5 Selektiv schreiben — nur „übernehmen"/„neuer-bereich" (AC3/AC4, (AC5, from-notes-areas), *deckt A2*)

Erst **nach** vollständiger Beantwortung, **je Divergenz/Thema** streng nach Entscheid:

**Content-Divergenzen:**
- **`uebernehmen`** → die Notiz-Aussage in das jeweilige `doku_ziel` (`docs/concept.md` bzw. `docs/specs/<feature>.md`) **schreiben**.
- **`behalten`** → **nichts** ändern; die bestehende `concept.md`/Spec bleibt unverändert (*deckt A2*).
- **`manuell`** → **nichts** automatisch ändern; als offener Punkt dem User überlassen.

**Unassignierte Themen ((AC5, from-notes-areas)):**
- **`bereich-<id>`** (bestehender Bereich gewählt) → **nichts schreiben** — die Zuordnung ist dokumentiert (Owner-Entscheid im Katalog), keine Aktualisierung von `board/areas.yaml` erforderlich (der Bereich existiert bereits).
- **`neuer-bereich`** (Owner-Entscheid) → **`board/areas.yaml` append-only** (invertierte Autorität: ein expliziter Owner-Entscheid IST die Freigabe): Bereich mit Feldern `id` (kebab-case, eindeutig), `titel`, `beschreibung` (genau 1 Satz), `reihenfolge` (nächster freier int) aus dem Thema abgeleitet (konform [[board-areas]] AC1) an `board/areas.yaml` anhängen. Bestehendes wird **nie** blind überschrieben (append-only, nicht-destruktiv). `board lint` (`AREA-FIELD`) fängt Formatfehler ab. Der Write fahrt im **Sync-Commit** mit (siehe 5.5a).
- **`skippen`** → **nichts** schreiben; Thema wird nicht weiter berücksichtigt.

**Schreib-Umfang (hart, AC3/AC4/AC5):** **Content-Divergenzen** — ausschließlich die als „übernehmen" gewählten Einträge in `docs/concept.md` / `docs/specs/*` schreiben, **nie** automatisch, **nie** ungefragt, **nie** in den Notiz-Ordner (AC6). **Unassignierte Produktbereich-Themen** — keine Aktualisierung von `board/areas.yaml` für „bereich-<id>"- oder „skippen"-Entscheidungen (Zuordnung ist dokumentiert, Thema wird ignoriert). **Einzige Ausnahme** (AC5): bei explizitem Owner-Entscheid **„neuer-bereich"** einen neuen Bereich (konform [[board-areas]] AC1: `id`/`titel`/`beschreibung`/`reihenfolge` aus dem Thema abgeleitet) **append-only** an `board/areas.yaml` anhängen — **nie** blind überschreiben, **nur** wenn der Owner diesen Entscheid im beantwortetenen Katalog trifft (invertierte Autorität: Entscheid IST Freigabe). Jede geschriebene Änderung ist auf eine `notiz_fundstelle` + einen expliziten User-Entscheid rückführbar (NFR Nachvollziehbarkeit). Gibt es ≥1 „übernehmen" (Content) **oder** ≥1 „neuer-bereich" (Thema), fahren die Änderungen in **einen** durable **Sync-Commit** (siehe 5.5a); Branch-Protection → docs-only-PR + Self-Merge (analog Ingest §1.4).

### 5.5a Sync-Commit — durable Landung bei Schreiben (AC3, AC5)

Erst **nach** vollständiger Schreib-Phase (5.5: alle „übernehmen" + „neuer-bereich" durchgeführt):

```bash
git add docs/ board/areas.yaml && git commit -m "notes(sync): Obsidian-Re-Sync — Divergenzen uebernommen, Bereiche ggf. erweitert (obsidian-sync)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>" && git push
```

- **`docs/`** immer adden, wenn ≥1 „übernehmen" (Content-Schreiben).
- **`board/areas.yaml`** nur adden, wenn ≥1 „neuer-bereich" gewählt wurde (neue Bereiche appended).
- Gibt es **weder** „übernehmen" **noch** „neuer-bereich" → **kein Commit** (Deckungsgleichheit oder nur „behalten"/„skippen", siehe 5.3).
- Lehnt Branch-Protection den Direkt-Push ab → docs-only-PR öffnen + selbst mergen (analog Ingest §1.4).

### 5.6 Kein Folge-Automatismus (AC6)

Der Re-Sync startet **kein** `/flow` und legt **keine** Stories automatisch an — neue Stories entstehen bewusst nur über den Ingest-Stufe-c- bzw. den regulären `requirement`-Fluss. Der Notiz-Ordner wird **nie** beschrieben, verschoben oder ge-`add`et.

### 5.7 Output (Re-Sync)

```
Obsidian-Re-Sync (from-notes --sync) — Ordner: <aufgelöster-pfad> (Quelle: obsidian_source)
Korpus: <n> Notiz(en) gelesen · Vergleich gegen docs/concept.md + docs/specs/*
Divergenzen: <k gefunden | 0 -> deckungsgleich, keine Änderung>
  [P<i>] <notiz_fundstelle> -> <doku_ziel> : <divergenz_art> (Vorschlag: <richtungsvorschlag>)
Katalog sync: <k Frage(n) beantwortet | -> deckungsgleich, kein Katalog>
Geschrieben: <übernommene Divergenz(en) in docs/… -> commit <sha|PR> | keine (alles behalten/manuell)>
Kein /flow-Start, keine Story-Anlage, kein Schreiben in den Notiz-Ordner.
```

## Grenzen (HART)

- **Authoring-only (AC14):** editiert/erzeugt **ausschließlich** `docs/`, `.claude/profile.md` (nur `obsidian_source`) und Board-Items (**To Do**) — **kein** App-Code, **kein** `/flow`-Start, **kein** Merge/Deploy, **kein** Item-Status jenseits „To Do" (das ist `/flow`-Hoheit).
- **Rein lesende Notiz-Quelle (AC6):** der Obsidian-Ordner wird **nie** beschrieben, verschoben oder ge-`add`et/committet — geschrieben wird nur in `docs/`, `.claude/profile.md` und das Board.
- **Kein zweiter Zerlege-/Schätz-/Übersetzungs-Pfad (AC11/AC13):** Reader (S-021), Fragenkatalog-Gate (S-022), Spec-Vertrag/Vorlage, `requirement` (Zerlegung + Schätzung), `architekt`/`dba` (tiefes Detail) werden **wiederverwendet**, nicht dupliziert.
- **Commit pro Stufe, harte Reihenfolge (AC12):** jede Stufe wird **einzeln** committet, **nachdem** ihr Fragenkatalog beantwortet (oder leer) ist — **nicht** am Ende in einem Rutsch. b startet erst nach committetem a, c erst nach committetem b. Zwischenstände sind durable, der Lauf ist jederzeit fortsetzbar.
- **Bereichs-Gate in Stufe c (AC4):** der `requirement`-Agent liest die bestätigten Bereiche aus `board/areas.yaml` (geschrieben in Stufe a, AC3) und ordnet jede Spec einem Bereich zu — Storys hängen unter Bereichs-Features, neue Specs tragen `area: <bereich>`. **Kein** Item ohne Bereich. Edge-Case E1: fehlt `board/areas.yaml` oder ist leer (keine Bereiche bestätigt), arbeitet der Agent wie ohne Bereichs-Gate und vermerkt das im Output — kein Fehler, sondern dokumentierte Situation (der Entwurf war leer oder Owner hat alle Bereiche gestrichen).
- **Genau EIN gesammelter Katalog pro Stufe (AC7), leer → Auto-Durchlauf (AC8):** nie einzeln pro Unklarheit sofort erfragen; nie einen leeren Katalog vorlegen. Das Vorlege-Verhalten entscheidet ausschließlich das stdout-Token des Gate-Validators (`empty` vs. `valid`).
- **Re-Sync (`--sync`) — kein Blind-Overwrite, invertierte Reconcile-Autorität (obsidian-sync AC1/AC3/AC6):** der Re-Sync-Modus (§5) überschreibt Konzept/Spec **nie** automatisch; jede Divergenz ist ein per-Fund-User-Entscheid (`uebernehmen`/`behalten`/`manuell`), und **nur** `uebernehmen` schreibt — ausschließlich nach `docs/concept.md`/`docs/specs/*`, nie in den Notiz-Ordner. Er ist ein **eigener Modus** desselben Skills, teilt Reader + Katalog-Gate mit dem Ingest und lässt den **Reconcile-Vertrag unangetastet** (kein Reconcile-„Stufe 0"). **Kein** `/flow`-Start, **keine** automatische Story-Anlage. Bei Deckungsgleichheit: **kein** Katalog, **keine** Änderung, „deckungsgleich"-Meldung.
