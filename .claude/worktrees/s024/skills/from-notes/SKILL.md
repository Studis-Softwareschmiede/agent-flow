---
name: from-notes
description: Speist einen Obsidian-Notiz-Ordner als dritten Requirement-Weg in den Fabrik-Pfad Konzept -> Spezifikation -> Story ein. Orchestriert drei Stufen IN REIHE — (a) Notiz-Korpus -> docs/concept.md, (b) Konzept -> docs/specs/<feature>.md (+ architekt/dba wo nötig), (c) Spec(s) -> Board-Items/Stories über den bestehenden requirement-Agenten. Ein Fragenkatalog-Gate pro Stufe (genau EIN gesammelter Katalog, am Stück beantwortet; leer -> Auto-Durchlauf), Commit pro Stufe in harter Reihenfolge. Zusätzlich der Re-Sync-Modus --sync: wiederholbarer Abgleich Notiz <-> aktuelles Konzept/Spec, meldet Divergenzen als EINEN Fragenkatalog (stage sync), schreibt NUR die vom User als "übernehmen" gewählten Änderungen in docs/ — KEIN Blind-Overwrite (invertierte Reconcile-Autorität). Authoring-only — schreibt NUR docs/, das Profilfeld obsidian_source und Board-Items (To Do); KEIN App-Code, KEIN /flow-Start, KEIN Merge/Deploy, KEIN Schreiben in den Notiz-Ordner. Im Ziel-Projekt-Repo ausführen. Aufruf: /agent-flow:from-notes [--cost <mode>] [--sync] [<ordnerpfad>].
---

# /agent-flow:from-notes [--cost <mode>] [--sync] [<ordnerpfad>]

Speist einen **Obsidian-Notiz-Ordner** (mehrere freie `.md`-Notizen aus der Ideen-/Konzeptphase) als **dritten** Requirement-Weg (neben `new-project`/`init` und `requirement`) in den bestehenden Fabrik-Pfad **Konzept → Spezifikation → Story** ein. cwd = Ziel-Projekt-Repo.

**Dieser Skill ist der einzige Schreiber** der Doc-/Board-/Profil-Änderungen dieses Flusses und orchestriert **drei Stufen in Reihe** — er baut **keinen** eigenen Zerlege-, Schätz- oder Übersetzungs-Baustein neu, sondern **wiederverwendet** die bestehenden Bausteine (Reader, Fragenkatalog-Gate, `requirement`/`architekt`/`dba`).

Bindende Quellen: `docs/specs/obsidian-ingest.md` (AC11–AC14, sowie AC1–AC10 der wiederverwendeten Bausteine) + `docs/architecture/obsidian-ingest-subsystem.md` (§3 Drei-Stufen-Pipeline, §4 `obsidian_source`, §5 Re-Sync, §6 dev-gui-Schnittstelle). Dieser Skill hat **zwei Modi**: den **Ingest-Modus** (Standard, drei Stufen a→b→c, §0–§4 unten) und den **Re-Sync-Modus** (`--sync`, §5 unten; bindende Quelle `docs/specs/obsidian-sync.md` AC1–AC6). Beide teilen Reader (S-021) + Fragenkatalog-Gate (S-022) + `obsidian_source`; `--sync` überschreibt Doku **nie** automatisch (invertierte Reconcile-Autorität) und lässt Reconcile (`docs/architecture/reconcile-subsystem.md`) **unangetastet**.

> **Modus-Weiche (Setup vor allem anderen).** Steht das Token `--sync` in den Argumenten (an beliebiger Stelle, vor der Ordnerpfad-Auswertung herausparsen — analog `--cost`), läuft der **Re-Sync-Modus** (§5) statt der Drei-Stufen-Pipeline (§1–§3). §0/§0a/§0b (Setup, Ordnerauflösung, Reader) sind **beiden** Modi gemeinsam und laufen zuerst.

> **Authoring-only (AC14, hart).** Die Pipeline schreibt **ausschließlich** durable Docs (`docs/`), das Profilfeld `obsidian_source` und Board-Items (Status **To Do**). **Kein** App-Code, **kein** `/flow`-Start, **kein** Merge/Deploy und **kein** Schreiben in den Notiz-Ordner (der Vault ist rein lesende externe Quelle, AC6). Item-Status bleibt allein `/flow`-Hoheit.

## 0. Setup  (beiden Modi gemeinsam)

- **Modus-Token `--sync` herausparsen:** Ist `--sync` in den Argumenten (an beliebiger Stelle) vorhanden → **Re-Sync-Modus** (§5); Token entfernen, es gehört NICHT zum Ordnerpfad. Sonst → Ingest-Modus (§1–§3).
- **Cost-Mode auflösen:** Präzedenz `--cost`-Argument > `profile.cost_mode` > `balanced` (Kurzformen `low`/`max`/`front` normalisieren; `front`→`frontier`). Beim Task-Dispatch der Agenten (`requirement`/`architekt`/`dba` in Stufe b/c) den `model`-Parameter aus `${CLAUDE_PLUGIN_ROOT}/knowledge/model-tiers.md` (Zeile = Rolle) mitgeben; bei `balanced` **keinen** Override (Agent-Frontmatter gilt). Das `--cost`-Token gehört NICHT zum Ordnerpfad — vor der Argument-Auswertung herausparsen.
- **Auth herstellen (nur Ingest-Modus):** `bash "$CLAUDE_PLUGIN_ROOT/scripts/ensure-gh-auth.sh"` (mintet App-Token, loggt `gh` ein — für Stufe c, die über `requirement` Board-Items anlegt). NICHT `gh auth login --web`. Im **Re-Sync-Modus** entfällt dieser Schritt: `--sync` legt **keine** Board-Items an (AC6) — Auth wird nur gebraucht, falls Branch-Protection einen docs-PR erzwingt (siehe §5.4).
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
2. **Fragenkatalog-Gate (AC7/AC8/AC9):** Alle offenen Punkte dieser Stufe **gesammelt** als **genau EINE** JSON-Liste von Frage-Objekten aufbauen — je Objekt `stage:"a"`, `id` (katalog-eindeutig, Muster `a-<n>`), `frage`, `quelle` (Notiz-Fundstelle), optional `optionen[]` (Format-Vertrag: `board/fragenkatalog.schema.json`). Den Katalog durch den wiederverwendeten Gate-Validator prüfen und das Vorlege-Verhalten am stdout-Token festmachen:
   ```bash
   printf '%s' "$KATALOG_A_JSON" | bash "$CLAUDE_PLUGIN_ROOT/scripts/obsidian-fragenkatalog-validate.sh"
   ```
   - **`empty`** → keine offenen Fragen → **Auto-Durchlauf** (AC8): kein Katalog vorlegen, direkt zu 1.3.
   - **`valid`** → nicht-leerer Katalog → dem User **am Stück** vorlegen (AC7): im Terminal-Pfad via `AskUserQuestion` (ein Prompt, alle Fragen zusammen); im dev-gui-Pfad rendert dev-gui denselben JSON-Katalog und reicht die Antworten über die `id`-Zuordnung zurück (AC9). **Erst nach** vollständiger Beantwortung fließen die Antworten in `docs/concept.md` ein.
   - **Exit 1/2** (Vertragsverletzung / Aufrufproblem) → den selbst erzeugten Katalog korrigieren und erneut validieren (nie einen ungültigen Katalog vorlegen).
3. **Commit Stufe a (AC12, durable):** Erst **nachdem** der Katalog beantwortet (oder leer) ist:
   ```bash
   git add docs/concept.md .claude/profile.md && git commit -m "notes(a): Notiz-Korpus -> docs/concept.md (obsidian-ingest)

   Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>" && git push
   ```
   Der Profilfeld-Diff (`obsidian_source`, §0a) fährt hier mit. `.claude/profile.md` nur `git add`en, wenn §0a das Feld tatsächlich gesetzt/geändert hat. Lehnt Branch-Protection den Direkt-Push ab → docs-only-PR öffnen + selbst mergen (analog `requirement`-Skill). Der Notiz-Ordner wird **nie** ge-`add`et (AC6/AC14).

Stufe b startet **erst nach** committetem Stufe-a-Ergebnis (harte Reihenfolge, AC12).

## 2. Stufe b — `docs/concept.md` → `docs/specs/<feature>.md` (AC11b/AC13)

**Ziel:** je Capability des Konzepts **eine** durable Spec ableiten, den bestehenden **Spec-Vertrag wiederverwenden** (AC13) — Vorlage, `spec_format`-Stempel, nummerierte AC, Traceability.

1. **Spec(s) schreiben:** je Capability eine `docs/specs/<feature-slug>.md` aus `templates/_docs/specs/_template.md` — Zweck, Verhalten, **nummerierte Acceptance-Kriterien (AC1, AC2, …)**, Verträge, Edge-Cases, NFRs, Nicht-Ziele. **`spec_format`-Stempel:** den Wert 1:1 aus der **aktuellen** `_template.md` übernehmen (nicht hartkodieren), wie es der Spec-Vertrag (`docs/specs/spec-format-field.md` AC3) und `requirement` fordern.
2. **Tiefes Detail via bestehende Agenten (AC11b/AC13 — kein Neubau):** Wo tiefes Architektur-Detail nötig ist, den **`architekt`**-Agenten (Task) dispatchen → `docs/architecture.md` bzw. `docs/architecture/<subsystem>.md`. Wo ein Datenmodell nötig ist, den **`dba`**-Agenten (Task, Design-Modus) → `docs/data-model.md`. Beide schreiben nur in den Working-Tree (kein Commit) — das Committen macht dieser Skill in 2.4.
3. **Fragenkatalog-Gate (AC7/AC8/AC9):** identische Mechanik wie 1.2, aber `stage:"b"`, `id`-Muster `b-<n>`, `quelle` = Konzept-/Doku-Fundstelle. `empty` → Auto-Durchlauf; `valid` → dem User am Stück vorlegen (`AskUserQuestion` / dev-gui); erst nach Beantwortung fließen die Antworten in die Spec(s)/Architektur ein.
4. **Commit Stufe b (AC12):** Erst nach beantwortetem/leerem Katalog:
   ```bash
   git add docs/ && git commit -m "notes(b): Konzept -> docs/specs/<…> (obsidian-ingest)

   Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>" && git push
   ```
   Alle in dieser Stufe berührten `docs/`-Dateien (Spec(s) + ggf. `architecture*.md`/`data-model.md`) fahren in **einem** Stufe-b-Commit. Branch-Protection → docs-only-PR + Self-Merge.

Stufe c startet **erst nach** committetem Stufe-b-Ergebnis (harte Reihenfolge, AC12).

## 3. Stufe c — Spec(s) → Board-Items/Stories über den `requirement`-Agenten (AC11c/AC13)

**Ziel:** die in Stufe b entstandenen Spec(s) in Board-Items/Stories zerlegen — **über den bestehenden `requirement`-Agenten** (AC11: „kein zweiter Zerlege-Pfad").

1. **`requirement`-Agent dispatchen (Task, `agents/requirement.md`):** als Eingabe die in Stufe b geschriebene(n) Spec(s) übergeben — nicht eine neue vage Anforderung, sondern der Verweis auf die bereits durable Spec(s) mit dem Auftrag, sie in Board-Items zu zerlegen. Der `requirement`-Agent leistet dabei **ohnehin** (AC13):
   - Zerlegung in TODOs (je Item ≈ ein coder→reviewer→tester-Durchlauf),
   - je Item ein Board-Item (**To Do**), das auf **Spec + AC-Nummern** zeigt (**kein** eingebetteter AC-Text),
   - die **A-priori-Schätzung** (`size_est`/`dispo_est`/`confidence`/`estimate_note`) bei der Anlage.

   Da die Spec(s) bereits geschrieben sind, sollte der `requirement`-Agent hier i.d.R. **nicht** erneut Spec-schreiben — sein Fokus ist die Zerlegung. Legt er dabei doch Spec-Feinschliff nach (Working-Tree), fährt der in den Stufe-c-Commit (3.3).
2. **Fragenkatalog-Gate (AC7/AC8/AC9):** Bleiben bei der Zerlegung Unklarheiten offen (z.B. Schnitt-Granularität, Priorität, Abhängigkeiten), diese **gesammelt** als **einen** Katalog `stage:"c"` (`id`-Muster `c-<n>`, `quelle` = Spec-/Doku-Fundstelle) — Validator + Vorlege-Verhalten wie oben. Der `requirement`-Agent stellt seine eigenen gezielten Rückfragen normalerweise selbst; ein separater Stufe-c-Katalog wird nur aufgebaut, wenn nach seinem Lauf noch pipeline-seitige Unklarheiten offen sind (kein leerer Katalog, AC8).
3. **Commit Stufe c (AC12):** Der `requirement`-Agent legt die Board-Items an (Status **To Do**, `/flow`-Hoheit endet dort — kein Status-Vorschub, AC14). Etwaige vom Agenten in den Working-Tree geschriebene `docs/`-Deltas dieser Stufe committen:
   ```bash
   git add docs/ && git commit -m "notes(c): Spec(s) -> Board-Items (obsidian-ingest)

   Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>" && git push
   ```
   Gibt es keinen `docs/`-Delta in Stufe c (Items liegen im File-Board bzw. via `gh` am GitHub-Board), entfällt der Doc-Commit — die Board-Items selbst sind der durable Zustand dieser Stufe.

**Kein `/flow`-Start, kein Merge/Deploy** (AC14). Der Ordner bleibt unangetastet; das Projekt kann jederzeit erneut aus den Notizen arbeiten (Re-Ingest oder `[[obsidian-sync]]`).

## 4. Output (Ingest-Modus)

```
Obsidian-Ingest (from-notes) — Ordner: <aufgelöster-pfad> (Quelle: <Argument | Profil obsidian_source>)
Korpus: <n> Notiz(en) gelesen
Stufe a: docs/concept.md geschrieben — Katalog a: <leer/Auto-Durchlauf | <k> Frage(n) beantwortet> — committet <sha|PR>
Stufe b: docs/specs/<…> (+ <architektur/data-model falls>) — Katalog b: <…> — committet <sha|PR>
Stufe c: <m> Board-Item(s) (To Do) via requirement — Katalog c: <…> — committet <sha|PR|kein Doc-Delta>
  #<id> <title> — Spec <feature-slug> (AC<…>) — size_est: <…> dispo_est: <…>
Bereit für /agent-flow:flow.
```

## 5. Re-Sync-Modus — `/agent-flow:from-notes --sync`  (Spec `docs/specs/obsidian-sync.md`, AC1–AC6)

**Zweck (AC1/AC3):** wiederholbarer Abgleich zwischen dem **aktuellen Notiz-Stand** (`obsidian_source`) und dem **aktuellen Konzept/Spec-Stand** (`docs/concept.md` + `docs/specs/*`). Der Modus **erkennt und meldet** Divergenzen und legt sie dem User **je Divergenz zur Entscheidung** vor — er **überschreibt Konzept/Specs nie automatisch**. Das ist die notiz-getriebene Aufhol-Fähigkeit mit **invertierter Reconcile-Autorität**: bei `/agent-flow:reconcile` gewinnt der Code automatisch gegen die Doku; hier sind die Notizen **unfertige Gedanken** und dürfen die Doku **nicht** automatisch überschreiben.

> **Eigener Modus, geteilte Basis, Reconcile unangetastet (AC1).** `--sync` ist ein **eigener Modus** desselben `from-notes`-Skills — **kein** Reconcile-„Stufe 0". Er nutzt denselben persistierten `obsidian_source` (§0a), denselben Notiz-Korpus-Reader (§0b) und dasselbe Fragenkatalog-Gate (S-022, hier `stage:"sync"`). Der Reconcile-Vertrag (`docs/architecture/reconcile-subsystem.md`) wird **nicht** angefasst und **keine** Reconcile-Stufe angelegt.

**Voraussetzung — §0/§0a/§0b liefen zuerst (gemeinsame Basis):** Ordnerpfad aus **Argument > `obsidian_source`** aufgelöst (§0a) und der Korpus über `scripts/obsidian-corpus-read.sh` gelesen (§0b). Fehlt `obsidian_source` **und** Argument, oder ist der Ordner unlesbar (Reader-Exit 2) → **klarer Abbruch** mit der Reader-/Auflöse-Meldung, **identisch** zum Ingest-Abbruch und zu `[[obsidian-ingest]]` AC2/AC5 (**AC6 / E1**). Es wird **nie** eine leere/überschriebene Doku erzeugt.

1. **Vergleichsseiten aufstellen (AC1/AC2):** links = der Notiz-Korpus (`$CORPUS_FILE`, Reader-Output mit Herkunfts-Markern `===== NOTE: <relativer-pfad> =====`, AC4 des Ingest); rechts = der **aktuelle** `docs/concept.md` + alle `docs/specs/*.md`. Beide Seiten werden rein lesend eingelesen — der Notiz-Ordner bleibt unangetastet (AC6).

2. **Divergenzen erkennen + priorisierten Bericht bauen (AC2):** Notiz-Korpus gegen den Doku-Stand abgleichen und **je Fund** einen Bericht-Eintrag bilden:
   ```
   { notiz_fundstelle, doku_ziel (Dokument + Sektion), divergenz_art, richtungsvorschlag }
   ```
   - **`notiz_fundstelle`** = relativer Notiz-Pfad (aus dem Herkunfts-Marker) + Kontext.
   - **`doku_ziel`** = betroffenes Dokument (`docs/concept.md` oder eine konkrete `docs/specs/<feature>.md`) + Sektion.
   - **`divergenz_art`** ∈ {Notiz **widerspricht** einer Konzept-/Spec-Aussage · Notiz enthält **Neues**, das die Spec nicht abbildet · Doku **enthält**, was die Notiz **nicht mehr trägt**}.
   - **`richtungsvorschlag`** = unverbindliche Empfehlung (übernehmen / behalten / manuell).

   Der Bericht ist **rein informativ** und **priorisiert** (Widersprüche vor „Neues" vor „nicht mehr getragen") — **kein** Gate, **keine** automatischen Board-Items (AC2/AC6). Er wird dem User vor dem Katalog gezeigt.

3. **Deckungsgleichheit → früher, geräuschloser Ausstieg (AC5, *deckt A1*):** Ergibt Schritt 2 **null** Divergenzen → **kein** Fragenkatalog, **keine** Doku-Änderung, **kein** Commit. Klare Meldung „**deckungsgleich** — Notizen und Konzept/Spec stimmen überein, nichts zu tun." und Ende. Nie einen leeren Katalog vorlegen.

4. **Genau EIN Fragenkatalog, gerichteter Entscheid je Divergenz (AC4):** Bei ≥ 1 Divergenz **alle** Funde **gesammelt** als **genau EINE** JSON-Liste von Frage-Objekten aufbauen — je Objekt `stage:"sync"`, `id` (katalog-eindeutig, Muster `sync-<n>`), `frage` (Divergenz + `doku_ziel` in Alltagssprache), `quelle` (`notiz_fundstelle`) und `optionen` = die drei gerichteten Antworten **`übernehmen`** (Notiz in die Doku übernehmen) · **`behalten`** (Doku behalten) · **`manuell`** (offen lassen). Den Katalog durch den geteilten Gate-Validator prüfen und das Vorlege-Verhalten am stdout-Token festmachen:
   ```bash
   printf '%s' "$KATALOG_SYNC_JSON" | bash "$CLAUDE_PLUGIN_ROOT/scripts/obsidian-fragenkatalog-validate.sh"
   ```
   - **`valid`** (≥ 1 Frage) → dem User **am Stück** vorlegen (**genau ein** Katalog, alle Divergenzen zusammen — nie Einzel-Prompt je Fund): Terminal-Pfad via `AskUserQuestion`; dev-gui-Pfad rendert denselben JSON-Katalog und reicht die Antworten über die `id`-Zuordnung zurück (Format = `[[obsidian-ingest]]` AC9, `stage:"sync"`).
   - **`empty`** → dürfte hier nicht auftreten (Schritt 3 fängt den divergenzfreien Fall ab); tritt es doch auf → wie Schritt 3 behandeln (geräuschlos enden).
   - **Exit 1/2** (Vertragsverletzung / Aufrufproblem) → den selbst erzeugten Katalog korrigieren und erneut validieren (nie einen ungültigen Katalog vorlegen).

5. **Selektives Schreiben — nur „übernehmen" (AC3/AC4, *deckt A2*):** **Erst nach** vollständiger Beantwortung des Katalogs:
   - Für jede Divergenz mit Antwort **`übernehmen`** die **notiz-seitige** Aussage in das zugehörige `doku_ziel` (`docs/concept.md` bzw. `docs/specs/<feature>.md`, betroffene Sektion) schreiben.
   - Für **`behalten`** und **`manuell`** wird **nichts** geschrieben — die bestehende `concept.md`/Spec bleibt **unverändert** (*A2*). Nichts wird ohne expliziten „übernehmen"-Entscheid geändert (**AC3 — kein Blind-Overwrite**).
   - Geschrieben wird **ausschließlich** nach `docs/concept.md` / `docs/specs/*` (Schreib-Umfang, Vertrag). **Nie** in den Notiz-Ordner (AC6). Präzisiere die betroffene Sektion konsistent zum Spec-/Konzept-Layout; jede Änderung ist auf `notiz_fundstelle` + den `übernehmen`-Entscheid rückführbar (NFR Nachvollziehbarkeit).

6. **Durable machen — Commit nur bei tatsächlichem Schreib-Delta (AC6):** Wurde in Schritt 5 mindestens eine „übernehmen"-Änderung geschrieben:
   ```bash
   git add docs/ && git commit -m "sync: Notiz-Divergenzen in docs/ übernommen (obsidian-sync)

   Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>" && git push
   ```
   `.claude/profile.md` fährt nur mit, wenn §0a `obsidian_source` tatsächlich gesetzt/geändert hat. Lehnt Branch-Protection den Direkt-Push ab → docs-only-PR öffnen + selbst mergen (analog Ingest-Stufe). Der Notiz-Ordner wird **nie** ge-`add`et (AC6). **Kein** `/flow`-Start und **keine** automatische Story-Anlage — neue Stories entstehen bewusst nur über den Ingest-Stufe-c- bzw. den regulären `requirement`-Fluss (AC6).

### 5a. Output (Re-Sync-Modus)

```
Obsidian-Sync (from-notes --sync) — Ordner: <aufgelöster-pfad> (Quelle: <Argument | Profil obsidian_source>)
Korpus: <n> Notiz(en) gelesen · Vergleich gegen docs/concept.md + docs/specs/*
Divergenzen: <keine → deckungsgleich, nichts geändert>  |  <k> gefunden — Katalog sync (stage:sync)
  übernommen: <u>  ·  behalten: <b>  ·  manuell/offen: <m>
Geschrieben: <docs/… Liste | keine (alles behalten/manuell)> — committet <sha|PR|kein Delta>
Reconcile unangetastet · kein /flow-Start · Notiz-Ordner unverändert.
```

## Grenzen (HART)

- **Authoring-only (AC14):** editiert/erzeugt **ausschließlich** `docs/`, `.claude/profile.md` (nur `obsidian_source`) und Board-Items (**To Do**) — **kein** App-Code, **kein** `/flow`-Start, **kein** Merge/Deploy, **kein** Item-Status jenseits „To Do" (das ist `/flow`-Hoheit).
- **Rein lesende Notiz-Quelle (AC6):** der Obsidian-Ordner wird **nie** beschrieben, verschoben oder ge-`add`et/committet — geschrieben wird nur in `docs/`, `.claude/profile.md` und das Board.
- **Kein zweiter Zerlege-/Schätz-/Übersetzungs-Pfad (AC11/AC13):** Reader (S-021), Fragenkatalog-Gate (S-022), Spec-Vertrag/Vorlage, `requirement` (Zerlegung + Schätzung), `architekt`/`dba` (tiefes Detail) werden **wiederverwendet**, nicht dupliziert.
- **Commit pro Stufe, harte Reihenfolge (AC12):** jede Stufe wird **einzeln** committet, **nachdem** ihr Fragenkatalog beantwortet (oder leer) ist — **nicht** am Ende in einem Rutsch. b startet erst nach committetem a, c erst nach committetem b. Zwischenstände sind durable, der Lauf ist jederzeit fortsetzbar.
- **Genau EIN gesammelter Katalog pro Stufe (AC7), leer → Auto-Durchlauf (AC8):** nie einzeln pro Unklarheit sofort erfragen; nie einen leeren Katalog vorlegen. Das Vorlege-Verhalten entscheidet ausschließlich das stdout-Token des Gate-Validators (`empty` vs. `valid`).
- **Re-Sync — kein Blind-Overwrite (obsidian-sync AC3):** `--sync` überschreibt Konzept/Specs **nie automatisch**. Jede Divergenz wird als **gerichtete** Frage (übernehmen/behalten/manuell) im **einen** `stage:sync`-Katalog vorgelegt; geschrieben werden **nur** die als „übernehmen" gewählten Änderungen (behalten/manuell ändern nichts). Bei **null** Divergenzen: kein Katalog, keine Änderung, „deckungsgleich"-Meldung (AC5).
- **Re-Sync — eigener Modus, Reconcile unangetastet (obsidian-sync AC1/AC6):** `--sync` ist ein **eigener Modus** desselben Skills (**kein** Reconcile-„Stufe 0"); `docs/architecture/reconcile-subsystem.md` bleibt **unberührt**. Der Modus schreibt **nur** in `docs/concept.md`/`docs/specs/*` (nie in den Notiz-Ordner, AC6), startet **kein** `/flow` und legt **keine** Stories automatisch an — neue Stories nur über Ingest-Stufe c / `requirement`.
