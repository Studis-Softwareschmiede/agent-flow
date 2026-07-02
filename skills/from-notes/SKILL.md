---
name: from-notes
description: Speist einen Obsidian-Notiz-Ordner als dritten Requirement-Weg in den Fabrik-Pfad Konzept -> Spezifikation -> Story ein. Orchestriert drei Stufen IN REIHE — (a) Notiz-Korpus -> docs/concept.md, (b) Konzept -> docs/specs/<feature>.md (+ architekt/dba wo nötig), (c) Spec(s) -> Board-Items/Stories über den bestehenden requirement-Agenten. Ein Fragenkatalog-Gate pro Stufe (genau EIN gesammelter Katalog, am Stück beantwortet; leer -> Auto-Durchlauf), Commit pro Stufe in harter Reihenfolge. Authoring-only — schreibt NUR docs/, das Profilfeld obsidian_source und Board-Items (To Do); KEIN App-Code, KEIN /flow-Start, KEIN Merge/Deploy, KEIN Schreiben in den Notiz-Ordner. Im Ziel-Projekt-Repo ausführen. Aufruf: /agent-flow:from-notes [--cost <mode>] [<ordnerpfad>].
---

# /agent-flow:from-notes [--cost <mode>] [<ordnerpfad>]

Speist einen **Obsidian-Notiz-Ordner** (mehrere freie `.md`-Notizen aus der Ideen-/Konzeptphase) als **dritten** Requirement-Weg (neben `new-project`/`init` und `requirement`) in den bestehenden Fabrik-Pfad **Konzept → Spezifikation → Story** ein. cwd = Ziel-Projekt-Repo.

**Dieser Skill ist der einzige Schreiber** der Doc-/Board-/Profil-Änderungen dieses Flusses und orchestriert **drei Stufen in Reihe** — er baut **keinen** eigenen Zerlege-, Schätz- oder Übersetzungs-Baustein neu, sondern **wiederverwendet** die bestehenden Bausteine (Reader, Fragenkatalog-Gate, `requirement`/`architekt`/`dba`).

Bindende Quellen: `docs/specs/obsidian-ingest.md` (AC11–AC14, sowie AC1–AC10 der wiederverwendeten Bausteine) + `docs/architecture/obsidian-ingest-subsystem.md` (§3 Drei-Stufen-Pipeline, §4 `obsidian_source`, §6 dev-gui-Schnittstelle). Der Re-Sync-Modus (`--sync`) ist **nicht** Teil dieses Items — er lebt in `[[obsidian-sync]]` (Schwester-Spec, teilt Reader + Katalog-Gate).

> **Authoring-only (AC14, hart).** Die Pipeline schreibt **ausschließlich** durable Docs (`docs/`), das Profilfeld `obsidian_source` und Board-Items (Status **To Do**). **Kein** App-Code, **kein** `/flow`-Start, **kein** Merge/Deploy und **kein** Schreiben in den Notiz-Ordner (der Vault ist rein lesende externe Quelle, AC6). Item-Status bleibt allein `/flow`-Hoheit.

## 0. Setup

- **Cost-Mode auflösen:** Präzedenz `--cost`-Argument > `profile.cost_mode` > `balanced` (Kurzformen `low`/`max`/`front` normalisieren; `front`→`frontier`). Beim Task-Dispatch der Agenten (`requirement`/`architekt`/`dba` in Stufe b/c) den `model`-Parameter aus `${CLAUDE_PLUGIN_ROOT}/knowledge/model-tiers.md` (Zeile = Rolle) mitgeben; bei `balanced` **keinen** Override (Agent-Frontmatter gilt). Das `--cost`-Token gehört NICHT zum Ordnerpfad — vor der Argument-Auswertung herausparsen.
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

## 4. Output

```
Obsidian-Ingest (from-notes) — Ordner: <aufgelöster-pfad> (Quelle: <Argument | Profil obsidian_source>)
Korpus: <n> Notiz(en) gelesen
Stufe a: docs/concept.md geschrieben — Katalog a: <leer/Auto-Durchlauf | <k> Frage(n) beantwortet> — committet <sha|PR>
Stufe b: docs/specs/<…> (+ <architektur/data-model falls>) — Katalog b: <…> — committet <sha|PR>
Stufe c: <m> Board-Item(s) (To Do) via requirement — Katalog c: <…> — committet <sha|PR|kein Doc-Delta>
  #<id> <title> — Spec <feature-slug> (AC<…>) — size_est: <…> dispo_est: <…>
Bereit für /agent-flow:flow.
```

## Grenzen (HART)

- **Authoring-only (AC14):** editiert/erzeugt **ausschließlich** `docs/`, `.claude/profile.md` (nur `obsidian_source`) und Board-Items (**To Do**) — **kein** App-Code, **kein** `/flow`-Start, **kein** Merge/Deploy, **kein** Item-Status jenseits „To Do" (das ist `/flow`-Hoheit).
- **Rein lesende Notiz-Quelle (AC6):** der Obsidian-Ordner wird **nie** beschrieben, verschoben oder ge-`add`et/committet — geschrieben wird nur in `docs/`, `.claude/profile.md` und das Board.
- **Kein zweiter Zerlege-/Schätz-/Übersetzungs-Pfad (AC11/AC13):** Reader (S-021), Fragenkatalog-Gate (S-022), Spec-Vertrag/Vorlage, `requirement` (Zerlegung + Schätzung), `architekt`/`dba` (tiefes Detail) werden **wiederverwendet**, nicht dupliziert.
- **Commit pro Stufe, harte Reihenfolge (AC12):** jede Stufe wird **einzeln** committet, **nachdem** ihr Fragenkatalog beantwortet (oder leer) ist — **nicht** am Ende in einem Rutsch. b startet erst nach committetem a, c erst nach committetem b. Zwischenstände sind durable, der Lauf ist jederzeit fortsetzbar.
- **Genau EIN gesammelter Katalog pro Stufe (AC7), leer → Auto-Durchlauf (AC8):** nie einzeln pro Unklarheit sofort erfragen; nie einen leeren Katalog vorlegen. Das Vorlege-Verhalten entscheidet ausschließlich das stdout-Token des Gate-Validators (`empty` vs. `valid`).
- **`--sync` ist NICHT Teil dieses Items** — der Re-Sync-Modus lebt in `[[obsidian-sync]]` (eigene Story) und wird hier nicht implementiert.
